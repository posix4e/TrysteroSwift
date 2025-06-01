import Foundation
@preconcurrency import WebRTC

/// Manages a single peer connection
class Peer: NSObject {
    let id: String
    private let polite: Bool
    private let rtcConfig: RTCConfiguration?
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
        config: RTCConfiguration?,
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
            Task {
                do {
                    try await createOffer()
                } catch {
                    // Failed to create initial offer - connection will fail
                    close()
                }
            }
        }
    }

    func handleSignal(_ signal: Signal) {
        Task {
            await handleSignalAsync(signal)
        }
    }

    @MainActor
    private func handleSignalAsync(_ signal: Signal) async {
        guard let pc = peerConnection else { return }

        switch signal.type {
        case .offer:
            guard let sdp = signal.sdp else { return }

            let offerCollision = makingOffer || pc.signalingState != .stable
            ignoreOffer = !polite && offerCollision

            if ignoreOffer {
                return
            }

            do {
                try await pc.setRemoteDescription(RTCSessionDescription(type: .offer, sdp: sdp))
                let answer = try await pc.answer(for: nil)
                try await pc.setLocalDescription(answer)
                onSignal(Signal(type: .answer, sdp: answer.sdp))
            } catch {
                // Failed to handle offer - connection fails
                close()
            }

        case .answer:
            guard let sdp = signal.sdp else { return }
            do {
                try await pc.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: sdp))
            } catch {
                // Failed to set answer - connection fails
                close()
            }

        case .candidate:
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

        case .bye:
            close()
        }
    }

    func sendData(type: String, data: Any) {
        guard let channel = dataChannels[type], channel.readyState == .open else {
            // Create channel if it doesn't exist
            createDataChannel(label: type)
            // Queue data to send when channel opens
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.sendData(type: type, data: data)
            }
            return
        }

        let jsonData: Data
        if let stringData = data as? String {
            jsonData = stringData.data(using: .utf8) ?? Data()
        } else {
            // We control the data - should always be serializable
            jsonData = try! JSONSerialization.data(withJSONObject: data)
        }

        let buffer = RTCDataBuffer(data: jsonData, isBinary: false)
        channel.sendData(buffer)
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

        // Apply custom config if provided
        if let customConfig = rtcConfig {
            config.iceServers = customConfig.iceServers.map { server in
                RTCIceServer(
                    urlStrings: server.urls,
                    username: server.username,
                    credential: server.credential
                )
            }
        } else {
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

        // Create default data channel
        createDataChannel(label: "default")
    }

    private func createDataChannel(label: String) {
        guard let pc = peerConnection else { return }

        let config = RTCDataChannelConfiguration()
        config.isOrdered = true

        guard let channel = pc.dataChannel(forLabel: label, configuration: config) else { return }
        channel.delegate = self
        dataChannels[label] = channel
    }

    @MainActor
    private func createOffer() async throws {
        guard let pc = peerConnection else { return }

        makingOffer = true
        defer { makingOffer = false }

        let offer = try await pc.offer(for: nil)

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
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange state: RTCSignalingState) {
        // Handle signaling state changes
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        onStream(stream)
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        // Handle stream removal
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        Task {
            do {
                try await createOffer()
            } catch {
                // Renegotiation failed - connection may degrade
            }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .connected, .completed:
            onConnect()
        case .failed, .disconnected:
            close()
        default:
            break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        // Handle gathering state
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        onSignal(Signal(
            type: .candidate,
            candidate: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex
        ))
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        // Handle removed candidates
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        dataChannel.delegate = self
        dataChannels[dataChannel.label] = dataChannel
    }
}

// MARK: - RTCDataChannelDelegate

extension Peer: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        // Handle state changes
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let data = buffer.data

        if let stringData = String(data: data, encoding: .utf8) {
            onData(dataChannel.label, stringData)
        } else if let jsonObject = try? JSONSerialization.jsonObject(with: data) {
            onData(dataChannel.label, jsonObject)
        } else {
            onData(dataChannel.label, data)
        }
    }
}
