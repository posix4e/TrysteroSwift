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
    
    public init(roomId: String, relays: [String] = ["wss://relay.damus.io"]) throws {
        self.roomId = roomId
        self.nostrClient = try TrysteroNostrClient(relays: relays)
        self.webRTCManager = WebRTCManager()
    }
    
    public func join() async throws {
        try await nostrClient.connect()
        try await nostrClient.subscribe(to: roomId)
        try await announcePresence()
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
        // Implementation for announcing presence via Nostr
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
