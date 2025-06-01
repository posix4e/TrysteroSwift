import Foundation
@preconcurrency import WebRTC

// Import TrysteroRTCConfiguration from Trystero module

/// Manages a single peer connection
@MainActor
class Peer: NSObject {
    let id: String
    private let polite: Bool
    private let rtcConfig: TrysteroRTCConfiguration?
    private var peerConnection: RTCPeerConnection?
    private var dataChannels: [String: RTCDataChannel] = [:]
    private var makingOffer = false
    private var ignoreOffer = false

    // Callbacks
    private let onSignal: (Signal) -> Void
    private let onConnect: () -> Void
    private let onData: (String, Any) -> Void
    private let onStream: (RTCMediaStream) -> Void
    private let onClose: () -> Void

    init(
        id: String,
        polite: Bool,
        config: TrysteroRTCConfiguration?,
        onSignal: @escaping (Signal) -> Void,
        onConnect: @escaping () -> Void,
        onData: @escaping (String, Any) -> Void,
        onStream: @escaping (RTCMediaStream) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.id = id
        self.polite = polite
        self.rtcConfig = config
        self.onSignal = onSignal
        self.onConnect = onConnect
        self.onData = onData
        self.onStream = onStream
        self.onClose = onClose

        super.init()

        createPeerConnection()
    }

    func initiate() {
        // Only impolite peer creates initial offer
        if !polite {
            Task { @MainActor in
                do {
                    try await createOffer()
                } catch {
                    // Failed to create initial offer - log but don't close immediately
                    // The connection might still work if the other peer sends an offer
                    print("❌ Peer: Failed to create initial offer: \(error)")
                }
            }
        }
    }

    func handleSignal(_ signal: Signal) {
        Task { @MainActor in
            await handleSignalAsync(signal)
        }
    }

    @MainActor
    private func handleSignalAsync(_ signal: Signal) async {
        guard let pc = peerConnection else { return }

        switch signal.type {
        case .offer:
            await handleOffer(signal, pc: pc)
        case .answer:
            await handleAnswer(signal, pc: pc)
        case .candidate:
            await handleCandidate(signal, pc: pc)
        case .bye:
            close()
        }
    }

    @MainActor
    private func handleOffer(_ signal: Signal, pc: RTCPeerConnection) async {
        guard let sdp = signal.sdp else { return }

        let offerCollision = makingOffer || pc.signalingState != .stable
        ignoreOffer = !polite && offerCollision

        if ignoreOffer {
            return
        }

        do {
            print("🎯 Peer: Handling offer, creating answer...")
            try await pc.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp))
            let answer = try await pc.answer(for: nil)
            try await pc.setLocalDescription(answer)
            print("📤 Peer: Sending answer")
            onSignal(Signal(type: .answer, sdp: answer.sdp))
        } catch {
            print("❌ Peer: Failed to handle offer: \(error)")
            // Failed to handle offer - connection fails
            close()
        }
    }

    @MainActor
    private func handleAnswer(_ signal: Signal, pc: RTCPeerConnection) async {
        guard let sdp = signal.sdp else { return }
        do {
            try await pc.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp))
        } catch {
            // Failed to set answer - log error but don't close
            print("❌ Peer: Failed to set answer: \(error)")
        }
    }

    @MainActor
    private func handleCandidate(_ signal: Signal, pc: RTCPeerConnection) async {
        guard let candidate = signal.candidate,
              let sdpMid = signal.sdpMid,
              let sdpMLineIndex = signal.sdpMLineIndex else { return }

        let iceCandidate = RTCIceCandidate(
            sdp: candidate,
            sdpMLineIndex: sdpMLineIndex,
            sdpMid: sdpMid
        )

        do {
            try await pc.add(iceCandidate)
        } catch {
            // ICE candidate failures are non-fatal
            // Connection might still succeed with other candidates
        }
    }

    func sendData(type: String, data: Any) {
        print("📤 Peer: Sending data for action '\(type)'")

        // Trystero.js uses a single 'data' channel for all communication
        guard let channel = dataChannels["data"], channel.readyState == .open else {
            print("⚠️ Peer: Data channel not ready, retrying...")
            // Queue data to send when channel opens
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                self.sendData(type: type, data: data)
            }
            return
        }

        // Implement Trystero.js binary protocol
        let typeBytes = type.data(using: .utf8) ?? Data()
        var typePadded = Data(count: 12)
        typePadded.replaceSubrange(0..<min(typeBytes.count, 12), with: typeBytes)

        // Encode the payload
        let isJson = !(data is String || data is Data)
        let isBinary = data is Data

        let payloadData: Data
        if let stringData = data as? String {
            payloadData = stringData.data(using: .utf8) ?? Data()
        } else if let binaryData = data as? Data {
            payloadData = binaryData
        } else {
            // JSON encode
            guard let jsonData = try? JSONSerialization.data(withJSONObject: data) else {
                print("❌ Peer: Failed to serialize data")
                return
            }
            payloadData = jsonData
        }

        // Build the message
        var message = Data()
        message.append(typePadded) // Type (0-11)
        message.append(0) // Nonce (12)
        message.append(UInt8(1 | (isBinary ? 4 : 0) | (isJson ? 8 : 0))) // Tag (13) - isLast=1
        message.append(255) // Progress (14) - 100%
        message.append(payloadData) // Payload (15+)

        let buffer = RTCDataBuffer(data: message, isBinary: true)
        channel.sendData(buffer)
        print("📤 Peer: Sent \(message.count) bytes on 'data' channel (type: '\(type)', isJson: \(isJson), isBinary: \(isBinary))")
    }

    func addStream(_ stream: RTCMediaStream) {
        guard let pc = peerConnection else { return }
        stream.audioTracks.forEach { pc.add($0, streamIds: [stream.streamId]) }
        stream.videoTracks.forEach { pc.add($0, streamIds: [stream.streamId]) }
    }

    func removeStream(_ stream: RTCMediaStream) {
        guard let pc = peerConnection else { return }

        let senders = pc.senders
        for track in stream.audioTracks + stream.videoTracks {
            if let sender = senders.first(where: { $0.track == track }) {
                pc.removeTrack(sender)
            }
        }
    }

    func close() {
        peerConnection?.close()
        peerConnection = nil
        dataChannels.removeAll()
        onClose()
    }

    // MARK: - Private

    private func createPeerConnection() {
        let config = RTCConfiguration()

        // RTCConfiguration.iceServers is mutable and can be appended to
        if let customConfig = rtcConfig {
            // Clear default ice servers and add custom ones
            config.iceServers = customConfig.iceServers.map { server in
                RTCIceServer(
                    urlStrings: server.urls,
                    username: server.username,
                    credential: server.credential
                )
            }
        } else {
            // Use default STUN server
            config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        }

        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue]
        )

        guard let pc = WebRTCClient.factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
        ) else { return }

        self.peerConnection = pc

        // Create data channel - Trystero.js uses "data" for all communication
        createDataChannel(label: "data")
    }

    private func createDataChannel(label: String) {
        guard let pc = peerConnection else { return }
        
        // Check if channel already exists
        if dataChannels[label] != nil {
            print("📡 Peer: Data channel '\(label)' already exists")
            return
        }

        let config = RTCDataChannelConfiguration()
        config.isOrdered = true

        guard let channel = pc.dataChannel(forLabel: label, configuration: config) else {
            print("❌ Peer: Failed to create data channel \(label)")
            return
        }
        channel.delegate = self
        dataChannels[label] = channel
        print("📡 Peer: Created data channel '\(label)', state: \(channel.readyState.rawValue)")
    }

    @MainActor
    private func createOffer() async throws {
        guard let pc = peerConnection else { return }
        
        // Check if we're already in a non-stable state
        if pc.signalingState != .stable {
            print("⚠️ Peer: Cannot create offer - signaling state is \(pc.signalingState)")
            return
        }

        makingOffer = true
        defer { makingOffer = false }

        let offer = try await pc.offer(for: nil)

        // Double-check state hasn't changed
        if pc.signalingState != .stable {
            return
        }

        try await pc.setLocalDescription(offer)

        if let localSdp = pc.localDescription?.sdp {
            onSignal(Signal(type: .offer, sdp: localSdp))
        }
    }
}

// MARK: - RTCPeerConnectionDelegate

extension Peer: RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCSignalingState) {
        // Handle signaling state changes
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        Task { @MainActor in
            self.onStream(stream)
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        // Handle stream removal
    }

    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        Task { @MainActor in
            do {
                try await self.createOffer()
            } catch {
                // Renegotiation failed - connection may degrade
            }
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor in
            print("🔌 Peer: ICE connection state changed to: \(newState)")
        }
        
        switch newState {
        case .connected, .completed:
            Task { @MainActor in
                print("✅ Peer: ICE connection established")
                self.onConnect()
            }
        case .failed:
            Task { @MainActor in
                print("❌ Peer: ICE connection failed")
                self.close()
            }
        case .disconnected:
            Task { @MainActor in
                print("🔌 Peer: ICE connection disconnected")
                // Don't close immediately on disconnect - might reconnect
            }
        default:
            break
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        // Handle gathering state
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        Task { @MainActor in
            self.onSignal(Signal(
                type: .candidate,
                candidate: candidate.sdp,
                sdpMid: candidate.sdpMid,
                sdpMLineIndex: candidate.sdpMLineIndex
            ))
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        // Handle removed candidates
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        Task { @MainActor in
            dataChannel.delegate = self
            self.dataChannels[dataChannel.label] = dataChannel
        }
    }
}

// MARK: - RTCDataChannelDelegate

extension Peer: RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Task { @MainActor in
            print("📡 Peer: Data channel '\(dataChannel.label)' state changed to: \(dataChannel.readyState.rawValue)")
            if dataChannel.readyState == .open {
                print("✅ Peer: Data channel '\(dataChannel.label)' is now open")
                // Store reference to the data channel
                self.dataChannels[dataChannel.label] = dataChannel
            }
        }
    }

    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let data = buffer.data

        Task { @MainActor in
            print("📥 Peer: Received data on channel '\(dataChannel.label)', size: \(data.count)")

            // Trystero.js binary protocol:
            // - Type bytes (0-11): Action type padded to 12 bytes
            // - Nonce (12): Message nonce
            // - Tag (13): Flags (isLast, isMeta, isBinary, isJson)
            // - Progress (14): Progress byte
            // - Payload (15+): Actual data

            if data.count >= 15 {
                // Extract type bytes and convert to string
                let typeBytes = data.subdata(in: 0..<12)
                let typeString = String(data: typeBytes, encoding: .utf8)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0"))

                let tag = data[13]
                let isLast = (tag & 1) != 0
                _ = (tag & 2) != 0 // isMeta - not used yet
                let isBinary = (tag & 4) != 0
                let isJson = (tag & 8) != 0

                let payload = data.subdata(in: 15..<data.count)

                print("📥 Peer: Trystero message - type: '\(typeString ?? "unknown")', isLast: \(isLast), isBinary: \(isBinary), isJson: \(isJson)")

                if let type = typeString, !type.isEmpty {
                    // Decode payload based on flags
                    if let stringData = String(data: payload, encoding: .utf8), !isBinary {
                        if isJson, let jsonObject = try? JSONSerialization.jsonObject(with: payload) {
                            self.onData(type, jsonObject)
                        } else {
                            self.onData(type, stringData)
                        }
                    } else {
                        self.onData(type, payload)
                    }
                } else {
                    // Fallback for non-Trystero messages
                    if let stringData = String(data: data, encoding: .utf8) {
                        print("📥 Peer: String data: \(stringData)")
                        self.onData("data", stringData)
                    } else if let jsonObject = try? JSONSerialization.jsonObject(with: data) {
                        print("📥 Peer: JSON data: \(jsonObject)")
                        self.onData("data", jsonObject)
                    } else {
                        print("📥 Peer: Binary data")
                        self.onData("data", data)
                    }
                }
            } else {
                // Short message, not using Trystero protocol
                if let stringData = String(data: data, encoding: .utf8) {
                    print("📥 Peer: String data: \(stringData)")
                    self.onData("data", stringData)
                } else if let jsonObject = try? JSONSerialization.jsonObject(with: data) {
                    print("📥 Peer: JSON data: \(jsonObject)")
                    self.onData("data", jsonObject)
                } else {
                    print("📥 Peer: Binary data")
                    self.onData("data", data)
                }
            }
        }
    }
}
