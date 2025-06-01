import Foundation
@preconcurrency import WebRTC
import NostrClient
import Nostr

public final class TrysteroRoom: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate, @unchecked Sendable {
    internal let roomId: String
    internal let nostrClient: TrysteroNostrClient
    private let webRTCManager: WebRTCManager
    private let myPeerId: String
    internal var peers: [String: RTCPeerConnection] = [:]
    internal var dataChannels: [String: RTCDataChannel] = [:]
    private var pendingIceCandidates: [String: [RTCIceCandidate]] = [:]
    internal var connectedPeers: Set<String> = []
    // Reverse mapping for thread-safe peer ID lookup
    private var peerConnections: [ObjectIdentifier: String] = [:]
    private var pubkeyToPeerId: [String: String] = [:] // Map pubkey -> peerId
    internal var peerIdToPubkey: [String: String] = [:] // Map peerId -> pubkey
    private var isJoined = false
    private var presenceTimer: Timer?
    // Connection timeout tracking
    private var connectionTimeouts: [String: Timer] = [:]
    // Synchronization queue for peer operations
    private let peerOperationQueue = DispatchQueue(label: "trystero.peer.operations", qos: .userInitiated)
    
    // Event handlers
    internal var peerJoinHandler: ((String) -> Void)?
    internal var peerLeaveHandler: ((String) -> Void)?
    internal var dataHandler: ((Data, String) -> Void)?
    internal var webrtcConnectingHandler: ((String) -> Void)?
    internal var webrtcConnectedHandler: ((String) -> Void)?
    internal var webrtcDisconnectedHandler: ((String) -> Void)?
    
    public init(roomId: String, relays: [String] = ["wss://relay.damus.io"], appId: String = "") throws {
        self.roomId = roomId
        self.nostrClient = try TrysteroNostrClient(relays: relays, appId: appId)
        self.webRTCManager = WebRTCManager()
        
        // Generate peer ID compatible with Trystero.js format
        self.myPeerId = String.randomString(length: 20)
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
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        try await nostrClient.subscribe(to: roomId)
        try await announcePresence()
        
        // Start periodic presence announcements (every 60 seconds)
        startPresenceTimer()
        
        isJoined = true
        print("🔍 [Swift Debug] Successfully joined room: \(roomId)")
    }
    
    public func leave() async {
        guard isJoined else { return }
        
        stopPresenceTimer()
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
        print("🔍 [Swift Debug] Announcing presence to room: \(roomId) with peer ID: \(myPeerId)")
        let presenceSignal = WebRTCSignal.presence(peerId: myPeerId)
        try await nostrClient.publishSignal(presenceSignal, roomId: roomId, targetPeer: nil)
        print("🔍 [Swift Debug] Presence announcement sent successfully")
    }
    
    private func startPresenceTimer() {
        stopPresenceTimer() // Stop any existing timer
        
        presenceTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isJoined else { return }
                
                do {
                    try await self.announcePresence()
                } catch {
                    print("🔍 [Swift Debug] Failed to send periodic presence: \(error)")
                }
            }
        }
        
        print("🔍 [Swift Debug] Started presence timer (60s intervals)")
    }
    
    private func stopPresenceTimer() {
        presenceTimer?.invalidate()
        presenceTimer = nil
        print("🔍 [Swift Debug] Stopped presence timer")
    }
    
    private func startConnectionTimeout(for peerId: String) {
        // Clear any existing timeout
        connectionTimeouts[peerId]?.invalidate()
        
        // Set new timeout (30 seconds)
        connectionTimeouts[peerId] = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            print("⏰ [Swift Debug] Connection timeout for peer \(String(peerId.prefix(8)))...")
            Task { @MainActor in
                self?.handleConnectionTimeout(peerId: peerId)
            }
        }
        
        print("⏰ [Swift Debug] Started connection timeout for \(String(peerId.prefix(8)))... (30s)")
    }
    
    internal func clearConnectionTimeout(for peerId: String) {
        connectionTimeouts[peerId]?.invalidate()
        connectionTimeouts.removeValue(forKey: peerId)
    }
    
    private func handleConnectionTimeout(peerId: String) {
        print("❌ [Swift Debug] WebRTC connection failed for \(String(peerId.prefix(8)))... (timeout)")
        cleanupPeer(peerId)
        
        // Could add retry logic here in the future
        // For now, just clean up the failed connection
    }
    
    private func handleWebRTCSignalSync(_ signal: WebRTCSignal, from fromPeer: String) {
        print("🔍 [Swift Debug] Processing WebRTC signal from \(fromPeer): \(signal)")
        
        Task {
            do {
                switch signal {
                case .presence(let peerId):
                    print("🔍 [Swift Debug] Peer \(fromPeer) announced presence with ID: \(peerId)")
                    pubkeyToPeerId[fromPeer] = peerId
                    peerIdToPubkey[peerId] = fromPeer
                    print("🔍 [Swift Debug] About to call handlePeerPresence for \(peerId)")
                    await handlePeerPresence(peerId)
                    print("🔍 [Swift Debug] Finished calling handlePeerPresence for \(peerId)")
                    
                case .offer(let sdp):
                    print("🔍 [Swift Debug] Received WebRTC offer from \(fromPeer)")
                    let peerId = pubkeyToPeerId[fromPeer] ?? fromPeer
                    try await handleOffer(sdp: sdp, from: peerId)
                    
                case .answer(let sdp):
                    print("🔍 [Swift Debug] Received WebRTC answer from \(fromPeer)")
                    let peerId = pubkeyToPeerId[fromPeer] ?? fromPeer
                    try await handleAnswer(sdp: sdp, from: peerId)
                    
                case .iceCandidate(let candidate, let sdpMid, let sdpMLineIndex):
                    print("🔍 [Swift Debug] Received ICE candidate from \(fromPeer)")
                    let peerId = pubkeyToPeerId[fromPeer] ?? fromPeer
                    try await handleIceCandidate(candidate: candidate, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex, from: peerId)
                }
            } catch {
                print("🔍 [Swift Debug] Error handling WebRTC signal: \(error)")
            }
        }
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
        // Clean up reverse mapping first
        if let peerConnection = peers[peerId] {
            peerConnections.removeValue(forKey: ObjectIdentifier(peerConnection))
            peerConnection.close()
        }
        
        // Clear connection timeout
        connectionTimeouts[peerId]?.invalidate()
        connectionTimeouts.removeValue(forKey: peerId)
        
        peers.removeValue(forKey: peerId)
        dataChannels.removeValue(forKey: peerId)
        pendingIceCandidates.removeValue(forKey: peerId)
        
        // Clean up pubkey mappings
        if let pubkey = peerIdToPubkey.removeValue(forKey: peerId) {
            pubkeyToPeerId.removeValue(forKey: pubkey)
        }
        
        if connectedPeers.remove(peerId) != nil {
            peerLeaveHandler?(peerId)
            print("👋 [Swift Debug] Peer \(String(peerId.prefix(8)))... left room")
        }
    }
    
    private func closePeerConnections() {
        // Clear all connection timeouts
        for timer in connectionTimeouts.values {
            timer.invalidate()
        }
        connectionTimeouts.removeAll()
        
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
        peerConnections.removeAll()
        pubkeyToPeerId.removeAll()
        peerIdToPubkey.removeAll()
    }
    
    // Helper function to safely get peer ID from peer connection
    internal func getPeerId(for peerConnection: RTCPeerConnection) -> String? {
        return peerConnections[ObjectIdentifier(peerConnection)]
    }
    
    // MARK: - WebRTC Signal Handlers
    
    private func handlePeerPresence(_ peerId: String) async {
        // Skip our own presence announcement
        guard peerId != myPeerId else {
            print("🔍 [Swift Debug] Ignoring our own presence announcement: \(String(peerId.prefix(8)))...")
            return
        }
        
        // Use synchronization to prevent race conditions with multiple peer connections
        await withCheckedContinuation { continuation in
            peerOperationQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                // Check if peer already exists (thread-safe)
                guard self.peers[peerId] == nil else {
                    print("🔍 [Swift Debug] Peer connection already exists for \(peerId)")
                    continuation.resume()
                    return
                }
                
                print("🔗 [Swift Debug] Creating peer connection for: \(peerId)")
                
                Task { @MainActor in
                    await self.createPeerConnectionSafely(for: peerId)
                    continuation.resume()
                }
            }
        }
    }
    
    @MainActor
    private func createPeerConnectionSafely(for peerId: String) async {
        // Double-check peer doesn't exist now that we're on MainActor
        guard peers[peerId] == nil else {
            print("🔍 [Swift Debug] Peer connection already exists for \(peerId) (double-check)")
            return
        }
        
        // Ensure WebRTC operations happen on main queue
        let peerConnection = webRTCManager.createPeerConnection(delegate: self)
        
        guard let peerConnection = peerConnection else {
            print("❌ [Swift Debug] Failed to create peer connection for \(peerId)")
            return
        }
        
        // Ensure peerId is actually a string and add safety check
        let safepeerId = String(describing: peerId)
        print("🔍 [Swift Debug] Setting peer connection for safe peer ID: \(safepeerId)")
        peers[safepeerId] = peerConnection
        peerConnections[ObjectIdentifier(peerConnection)] = safepeerId
        
        // Track peer presence (before WebRTC connection completes)
        connectedPeers.insert(safepeerId)
        peerJoinHandler?(safepeerId)
        print("✅ [Swift Debug] Peer \(String(safepeerId.prefix(8)))... joined room")
        
        // Set connection timeout (30 seconds)
        startConnectionTimeout(for: safepeerId)
        
        // Only create offer if our peer ID is lexicographically smaller (prevents both sides offering)
        let shouldCreateOffer = myPeerId.localizedCompare(safepeerId) == .orderedAscending
        
        if shouldCreateOffer {
            print("🤝 [Swift Debug] We'll create offer for \(safepeerId) (our ID: \(String(myPeerId.prefix(8)))...)")
            
            // Create data channel (only the offerer creates it)
            let dataChannel = webRTCManager.createDataChannel(on: peerConnection, label: "data")
            
            if let dataChannel = dataChannel {
                dataChannel.delegate = self
                dataChannels[safepeerId] = dataChannel
                print("📡 [Swift Debug] Created data channel for \(safepeerId)")
            } else {
                print("❌ [Swift Debug] Failed to create data channel for \(safepeerId)")
            }
            
            // Create and send offer with proper error handling
            do {
                // Small delay to let the peer connection stabilize
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
                
                print("🔧 [Swift Debug] Creating offer for \(safepeerId)...")
                let offer = try await webRTCManager.createOffer(for: peerConnection)
                print("🔧 [Swift Debug] Setting local description for \(safepeerId)...")
                try await webRTCManager.setLocalDescription(offer, for: peerConnection)
                print("🔧 [Swift Debug] Publishing offer signal for \(safepeerId)...")
                
                let signal = WebRTCSignal.offer(sdp: offer.sdp)
                let targetPubkey = peerIdToPubkey[safepeerId] ?? safepeerId
                try await nostrClient.publishSignal(signal, roomId: roomId, targetPeer: targetPubkey)
                print("📤 [Swift Debug] Sent offer to \(safepeerId)")
            } catch {
                print("❌ [Swift Debug] Failed to create/send offer to \(safepeerId): \(error)")
                cleanupPeer(safepeerId)
                return
            }
        } else {
            print("🤝 [Swift Debug] Waiting for offer from \(safepeerId) (their ID is smaller)")
        }
        
        print("🔍 [Swift Debug] Finished calling handlePeerPresence for \(safepeerId)")
    }
    
    private func handleOffer(sdp: String, from peerId: String) async throws {
        print("📥 [Swift Debug] Processing offer from \(peerId)")
        
        try await handleOfferOnMainActor(sdp: sdp, from: peerId)
    }
    
    @MainActor
    private func handleOfferOnMainActor(sdp: String, from peerId: String) async throws {
        var peerConnection = peers[peerId]
        if peerConnection == nil {
            // Create new connection on main queue
            let newConnection = webRTCManager.createPeerConnection(delegate: self)
            guard let newConnection = newConnection else {
                throw TrysteroError.connectionFailed
            }
            peerConnection = newConnection
            peers[peerId] = newConnection
            peerConnections[ObjectIdentifier(newConnection)] = peerId
            
            // Track peer presence for answering peer too
            connectedPeers.insert(peerId)
            peerJoinHandler?(peerId)
            print("✅ [Swift Debug] Peer \(String(peerId.prefix(8)))... joined room (answering)")
        }
        
        guard let connection = peerConnection else {
            throw TrysteroError.connectionFailed
        }
        
        let remoteDescription = RTCSessionDescription(type: .offer, sdp: sdp)
        try await webRTCManager.setRemoteDescription(remoteDescription, for: connection)
        
        // The answering peer also needs to be ready to receive data on the data channel
        // Note: The offering peer creates the data channel, but we need to handle it when it opens
        
        // Small delay to let the remote description process
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        let answer = try await webRTCManager.createAnswer(for: connection)
        try await webRTCManager.setLocalDescription(answer, for: connection)
        
        let signal = WebRTCSignal.answer(sdp: answer.sdp)
        let targetPubkey = peerIdToPubkey[peerId] ?? peerId
        try await nostrClient.publishSignal(signal, roomId: roomId, targetPeer: targetPubkey)
        
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

extension String {
    static func randomString(length: Int) -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).map { _ in letters.randomElement() ?? "a" })
    }
}
