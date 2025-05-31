import Foundation
@preconcurrency import WebRTC
import NostrClient
import Nostr

public final class TrysteroRoom: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate, @unchecked Sendable {
    internal let roomId: String
    internal let nostrClient: TrysteroNostrClient
    private let webRTCManager: WebRTCManager
    internal var peers: [String: RTCPeerConnection] = [:]
    internal var dataChannels: [String: RTCDataChannel] = [:]
    private var pendingIceCandidates: [String: [RTCIceCandidate]] = [:]
    internal var connectedPeers: Set<String> = []
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
        
        // Give relays time to establish connection
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
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
        guard connectedPeers.contains(peerId),
              let dataChannel = dataChannels[peerId],
              dataChannel.readyState == .open else {
            throw TrysteroError.peerNotConnected
        }
        let buffer = RTCDataBuffer(data: data, isBinary: true)
        dataChannel.sendData(buffer)
        print("📤 [Swift Debug] Sent data to \(String(peerId.prefix(8)))...")
    }
    
    private func broadcast(_ data: Data) throws {
        var sentCount = 0
        for (peerId, dataChannel) in dataChannels {
            guard connectedPeers.contains(peerId), dataChannel.readyState == .open else { continue }
            let buffer = RTCDataBuffer(data: data, isBinary: true)
            dataChannel.sendData(buffer)
            sentCount += 1
        }
        print("📤 [Swift Debug] Broadcast data to \(sentCount) peers")
    }
    
    internal func cleanupPeer(_ peerId: String) {
        peers.removeValue(forKey: peerId)
        dataChannels.removeValue(forKey: peerId)
        pendingIceCandidates.removeValue(forKey: peerId)
        
        if connectedPeers.remove(peerId) != nil {
            peerLeaveHandler?(peerId)
            print("👋 [Swift Debug] Peer \(String(peerId.prefix(8)))... left room")
        }
    }
    
    private func closePeerConnections() {
        for (peerId, peerConnection) in peers {
            peerConnection.close()
            if connectedPeers.remove(peerId) != nil {
                peerLeaveHandler?(peerId)
            }
        }
        peers.removeAll()
        dataChannels.removeAll()
        pendingIceCandidates.removeAll()
        connectedPeers.removeAll()
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
        
        // Track peer presence (before WebRTC connection completes)
        connectedPeers.insert(peerId)
        peerJoinHandler?(peerId)
        print("✅ [Swift Debug] Peer \(String(peerId.prefix(8)))... joined room")
        
        // Only create offer if our peer ID is lexicographically smaller (prevents both sides offering)
        let ourPeerId = nostrClient.keyPair.publicKey
        let shouldCreateOffer = ourPeerId.localizedCompare(peerId) == .orderedAscending
        
        if shouldCreateOffer {
            print("🤝 [Swift Debug] We'll create offer for \(peerId) (our ID: \(String(ourPeerId.prefix(8)))...)")
            
            // Create data channel (only the offerer creates it)
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
                cleanupPeer(peerId)
            }
        } else {
            print("🤝 [Swift Debug] Waiting for offer from \(peerId) (their ID is smaller)")
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
        
        // Check if we're in the right state to receive an answer
        guard peerConnection.signalingState == .haveLocalOffer else {
            print("❌ [Swift Debug] Wrong signaling state for answer: \(peerConnection.signalingState)")
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
