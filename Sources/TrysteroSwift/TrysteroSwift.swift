import Foundation
@preconcurrency import WebRTC
import NostrClient
import Nostr

public final class TrysteroRoom: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate, @unchecked Sendable {
    private let roomId: String
    private let nostrClient: TrysteroNostrClient
    private let webRTCManager: WebRTCManager
    internal var peers: [String: RTCPeerConnection] = [:]
    private var dataChannels: [String: RTCDataChannel] = [:]
    private var pendingIceCandidates: [String: [RTCIceCandidate]] = [:]
    private var isJoined = false
    
    // Event handlers
    internal var peerJoinHandler: ((String) -> Void)?
    internal var peerLeaveHandler: ((String) -> Void)?
    internal var dataHandler: ((Data, String) -> Void)?
    
    public init(roomId: String, relays: [String] = ["wss://relay.damus.io"], appId: String = "") throws {
        self.roomId = roomId
        self.nostrClient = try TrysteroNostrClient(relays: relays, appId: appId)
        self.webRTCManager = WebRTCManager()
    }
    
    public func join() async throws {
        guard !isJoined else { return }
        
        print("🔍 [Swift Debug] Joining room: \(roomId)")
        
        // Set up message handler for WebRTC signaling
        nostrClient.setMessageHandler { [weak self] signal, fromPeer in
            print("🔍 [Swift Debug] Received signal from \(fromPeer): \(signal)")
            self?.handleWebRTCSignalSync(signal, from: fromPeer)
        }
        
        try await nostrClient.connect()
        try await nostrClient.subscribe(to: roomId)
        try await announcePresence()
        
        isJoined = true
        print("🔍 [Swift Debug] Successfully joined room: \(roomId)")
    }
    
    public func leave() async {
        guard isJoined else { return }
        
        await nostrClient.disconnect()
        closePeerConnections()
        isJoined = false
        print("🔍 [Swift Debug] Left room: \(roomId)")
    }
    
    public func send(_ data: Data, to peerId: String? = nil) throws {
        guard isJoined else {
            throw TrysteroError.roomNotJoined
        }
        
        if let peerId = peerId {
            try sendToPeer(data, peerId: peerId)
        } else {
            try broadcast(data)
        }
    }
    
    private func announcePresence() async throws {
        print("🔍 [Swift Debug] Announcing presence to room: \(roomId)")
        let presenceSignal = WebRTCSignal.presence(peerId: nostrClient.keyPair.publicKey)
        try await nostrClient.publishSignal(presenceSignal, roomId: roomId, targetPeer: nil)
        print("🔍 [Swift Debug] Presence announcement sent successfully")
    }
    
    private func handleWebRTCSignalSync(_ signal: WebRTCSignal, from fromPeer: String) {
        print("🔍 [Swift Debug] Processing WebRTC signal from \(fromPeer): \(signal)")
        
        Task {
            do {
                switch signal {
                case .presence(let peerId):
                    print("🔍 [Swift Debug] Peer \(fromPeer) announced presence with ID: \(peerId)")
                    await handlePeerPresence(fromPeer)
                    
                case .offer(let sdp):
                    print("🔍 [Swift Debug] Received WebRTC offer from \(fromPeer)")
                    try await handleOffer(sdp: sdp, from: fromPeer)
                    
                case .answer(let sdp):
                    print("🔍 [Swift Debug] Received WebRTC answer from \(fromPeer)")
                    try await handleAnswer(sdp: sdp, from: fromPeer)
                    
                case .iceCandidate(let candidate, let sdpMid, let sdpMLineIndex):
                    print("🔍 [Swift Debug] Received ICE candidate from \(fromPeer)")
                    try await handleIceCandidate(candidate: candidate, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex, from: fromPeer)
                }
            } catch {
                print("🔍 [Swift Debug] Error handling WebRTC signal: \(error)")
            }
        }
    }
    
    private func handleWebRTCSignal(_ signal: WebRTCSignal, from fromPeer: String) async {
        handleWebRTCSignalSync(signal, from: fromPeer)
    }
    
    private func sendToPeer(_ data: Data, peerId: String) throws {
        guard let dataChannel = dataChannels[peerId] else {
            throw TrysteroError.peerNotConnected
        }
        let buffer = RTCDataBuffer(data: data, isBinary: true)
        dataChannel.sendData(buffer)
    }
    
    private func broadcast(_ data: Data) throws {
        for (_, dataChannel) in dataChannels {
            let buffer = RTCDataBuffer(data: data, isBinary: true)
            dataChannel.sendData(buffer)
        }
    }
    
    private func closePeerConnections() {
        for (_, peerConnection) in peers {
            peerConnection.close()
        }
        peers.removeAll()
        dataChannels.removeAll()
        pendingIceCandidates.removeAll()
    }
    
    // MARK: - WebRTC Signal Handlers
    
    private func handlePeerPresence(_ peerId: String) async {
        guard peers[peerId] == nil else { return }
        
        print("🔗 [Swift Debug] Creating peer connection for: \(peerId)")
        
        guard let peerConnection = webRTCManager.createPeerConnection(delegate: self) else {
            print("❌ [Swift Debug] Failed to create peer connection for \(peerId)")
            return
        }
        
        peers[peerId] = peerConnection
        
        // Create data channel
        if let dataChannel = webRTCManager.createDataChannel(on: peerConnection, label: "data") {
            dataChannel.delegate = self
            dataChannels[peerId] = dataChannel
            print("📡 [Swift Debug] Created data channel for \(peerId)")
        }
        
        // Create and send offer
        do {
            let offer = try await webRTCManager.createOffer(for: peerConnection)
            try await webRTCManager.setLocalDescription(offer, for: peerConnection)
            
            let signal = WebRTCSignal.offer(sdp: offer.sdp)
            try await nostrClient.publishSignal(signal, roomId: roomId, targetPeer: peerId)
            print("📤 [Swift Debug] Sent offer to \(peerId)")
        } catch {
            print("❌ [Swift Debug] Failed to create/send offer to \(peerId): \(error)")
            peers.removeValue(forKey: peerId)
            dataChannels.removeValue(forKey: peerId)
        }
    }
    
    private func handleOffer(sdp: String, from peerId: String) async throws {
        print("📥 [Swift Debug] Processing offer from \(peerId)")
        
        var peerConnection = peers[peerId]
        if peerConnection == nil {
            guard let newConnection = webRTCManager.createPeerConnection(delegate: self) else {
                throw TrysteroError.connectionFailed
            }
            peerConnection = newConnection
            peers[peerId] = newConnection
        }
        
        guard let connection = peerConnection else {
            throw TrysteroError.connectionFailed
        }
        
        let remoteDescription = RTCSessionDescription(type: .offer, sdp: sdp)
        try await webRTCManager.setRemoteDescription(remoteDescription, for: connection)
        
        let answer = try await webRTCManager.createAnswer(for: connection)
        try await webRTCManager.setLocalDescription(answer, for: connection)
        
        let signal = WebRTCSignal.answer(sdp: answer.sdp)
        try await nostrClient.publishSignal(signal, roomId: roomId, targetPeer: peerId)
        
        // Add any pending ICE candidates
        if let candidates = pendingIceCandidates.removeValue(forKey: peerId) {
            for candidate in candidates {
                do {
                    try await connection.add(candidate)
                } catch {
                    print("❌ [Swift Debug] Failed to add ICE candidate: \(error)")
                }
            }
        }
        
        print("📤 [Swift Debug] Sent answer to \(peerId)")
    }
    
    private func handleAnswer(sdp: String, from peerId: String) async throws {
        print("📥 [Swift Debug] Processing answer from \(peerId)")
        
        guard let peerConnection = peers[peerId] else {
            print("❌ [Swift Debug] No peer connection found for \(peerId)")
            return
        }
        
        let remoteDescription = RTCSessionDescription(type: .answer, sdp: sdp)
        try await webRTCManager.setRemoteDescription(remoteDescription, for: peerConnection)
        
        // Add any pending ICE candidates
        if let candidates = pendingIceCandidates.removeValue(forKey: peerId) {
            for candidate in candidates {
                do {
                    try await peerConnection.add(candidate)
                } catch {
                    print("❌ [Swift Debug] Failed to add ICE candidate: \(error)")
                }
            }
        }
        
        print("✅ [Swift Debug] Successfully processed answer from \(peerId)")
    }
    
    private func handleIceCandidate(candidate: String, sdpMid: String?, sdpMLineIndex: Int32, from peerId: String) async throws {
        print("📥 [Swift Debug] Processing ICE candidate from \(peerId)")
        
        let iceCandidate = RTCIceCandidate(sdp: candidate, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        
        if let peerConnection = peers[peerId] {
            if peerConnection.remoteDescription != nil {
                do {
                    try await peerConnection.add(iceCandidate)
                    print("✅ [Swift Debug] Added ICE candidate to \(peerId)")
                } catch {
                    print("❌ [Swift Debug] Failed to add ICE candidate: \(error)")
                }
            } else {
                // Store for later
                if pendingIceCandidates[peerId] == nil {
                    pendingIceCandidates[peerId] = []
                }
                pendingIceCandidates[peerId]?.append(iceCandidate)
                print("📦 [Swift Debug] Stored ICE candidate for \(peerId) (waiting for remote description)")
            }
        } else {
            print("❌ [Swift Debug] No peer connection found for ICE candidate from \(peerId)")
        }
    }
    
    // MARK: - RTCPeerConnectionDelegate
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("🔗 [Swift Debug] Signaling state changed: \(stateChanged)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("📺 [Swift Debug] Media stream added")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("📺 [Swift Debug] Media stream removed")
    }
    
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("🤝 [Swift Debug] Should negotiate")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("🧊 [Swift Debug] ICE connection state changed: \(newState)")
        
        // Find peer ID for this connection
        let peerId = peers.first { $0.value === peerConnection }?.key
        
        switch newState {
        case .connected, .completed:
            if let peerId = peerId {
                print("✅ [Swift Debug] Peer \(peerId) connected")
                peerJoinHandler?(peerId)
            }
        case .disconnected, .failed, .closed:
            if let peerId = peerId {
                print("❌ [Swift Debug] Peer \(peerId) disconnected")
                peerLeaveHandler?(peerId)
                peers.removeValue(forKey: peerId)
                dataChannels.removeValue(forKey: peerId)
                pendingIceCandidates.removeValue(forKey: peerId)
            }
        default:
            break
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("🧊 [Swift Debug] ICE gathering state changed: \(newState)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("🧊 [Swift Debug] Generated ICE candidate")
        
        let peerId = peers.first { $0.value === peerConnection }?.key
        guard let targetPeer = peerId else { return }
        
        let signal = WebRTCSignal.iceCandidate(
            candidate: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex
        )
        
        Task {
            do {
                try await nostrClient.publishSignal(signal, roomId: roomId, targetPeer: targetPeer)
                print("📤 [Swift Debug] Sent ICE candidate to \(targetPeer)")
            } catch {
                print("❌ [Swift Debug] Failed to send ICE candidate: \(error)")
            }
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("🧊 [Swift Debug] ICE candidates removed")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("📡 [Swift Debug] Data channel opened: \(dataChannel.label)")
        
        let peerId = peers.first { $0.value === peerConnection }?.key
        if let peerId = peerId {
            dataChannel.delegate = self
            dataChannels[peerId] = dataChannel
        }
    }
    
    // MARK: - RTCDataChannelDelegate
    
    public func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("📡 [Swift Debug] Data channel state changed: \(dataChannel.readyState)")
    }
    
    public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let peerId = dataChannels.first { $0.value === dataChannel }?.key
        if let peerId = peerId {
            print("📥 [Swift Debug] Received data from \(peerId)")
            dataHandler?(buffer.data, peerId)
        }
    }
}

public enum TrysteroError: Error, LocalizedError, Equatable {
    case peerNotConnected
    case connectionFailed
    case nostrError
    case invalidSignal
    case roomNotJoined
    case webRTCError(String)
    
    public var errorDescription: String? {
        switch self {
        case .peerNotConnected:
            return "Peer is not connected"
        case .connectionFailed:
            return "Failed to establish connection"
        case .nostrError:
            return "Nostr relay error"
        case .invalidSignal:
            return "Invalid WebRTC signal received"
        case .roomNotJoined:
            return "Room has not been joined"
        case .webRTCError(let message):
            return "WebRTC error: \(message)"
        }
    }
}
