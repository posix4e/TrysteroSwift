import Foundation
import WebRTC
import NostrClient
import Nostr

public class TrysteroRoom {
    private let roomId: String
    private let nostrClient: TrysteroNostrClient
    private let webRTCManager: WebRTCManager
    internal var peers: [String: RTCPeerConnection] = [:]
    private var dataChannels: [String: RTCDataChannel] = [:]
    
    public init(roomId: String, relays: [String] = ["wss://relay.damus.io"], appId: String = "") throws {
        self.roomId = roomId
        self.nostrClient = try TrysteroNostrClient(relays: relays, appId: appId)
        self.webRTCManager = WebRTCManager()
    }
    
    public func join() async throws {
        print("🔍 [Swift Debug] Joining room: \(roomId)")
        
        // Set up message handler for WebRTC signaling
        nostrClient.setMessageHandler { [weak self] signal, fromPeer in
            print("🔍 [Swift Debug] Received signal from \(fromPeer): \(signal)")
            self?.handleWebRTCSignalSync(signal, from: fromPeer)
        }
        
        try await nostrClient.connect()
        try await nostrClient.subscribe(to: roomId)
        try await announcePresence()
        print("🔍 [Swift Debug] Successfully joined room: \(roomId)")
    }
    
    public func leave() async {
        await nostrClient.disconnect()
        closePeerConnections()
    }
    
    public func send(_ data: Data, to peerId: String? = nil) throws {
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
        
        switch signal {
        case .presence(let peerId):
            print("🔍 [Swift Debug] Peer \(fromPeer) announced presence with ID: \(peerId)")
            // For now, just log that we discovered a peer
            print("🔍 [Swift Debug] Discovered peer: \(fromPeer)")
            
        case .offer:
            print("🔍 [Swift Debug] Received WebRTC offer from \(fromPeer)")
            // WebRTC offer handling will be implemented in future versions
            
        case .answer:
            print("🔍 [Swift Debug] Received WebRTC answer from \(fromPeer)")
            // WebRTC answer handling will be implemented in future versions
            
        case .iceCandidate:
            print("🔍 [Swift Debug] Received ICE candidate from \(fromPeer)")
            // ICE candidate handling will be implemented in future versions
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
    }
}

public enum TrysteroError: Error {
    case peerNotConnected
    case connectionFailed
    case nostrError
}
