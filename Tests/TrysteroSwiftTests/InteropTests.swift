import XCTest
import Foundation
@testable import TrysteroSwift

final class InteropTests: XCTestCase {
    private let roomId = "swift-interop-test"
    private let relays = ["wss://relay.verified-nostr.com", "wss://multiplexer.huszonegy.world"]
    private var room: TrysteroRoom?
    private var connectedPeers: Set<String> = []
    
    override func tearDown() async throws {
        if let room = room {
            await room.leave()
            self.room = nil
        }
    }
    
    /// Test interoperability with Trystero.js - requires external Node.js peer
    func testTrysteroJSInteroperability() async throws {
        print("🧪 Starting Trystero.js ↔ TrysteroSwift interoperability test...")
        
        let config = RoomConfig(relays: relays, appId: "trystero")
        room = try Trystero.joinRoom(config: config, roomId: roomId)
        
        room?.onPeerJoin { [weak self] peerId in
            print("✅ Swift detected peer joined: \(peerId)")
            self?.connectedPeers.insert(peerId)
        }
        
        room?.onPeerLeave { [weak self] peerId in
            print("❌ Swift detected peer left: \(peerId)")
            self?.connectedPeers.remove(peerId)
        }
        
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        
        try await room.join()
        print("✅ Swift peer joined room: \(roomId)")
        
        // Wait for Node.js peer to connect
        print("⏳ Waiting for Node.js peer to connect...")
        try await waitForPeerConnection(timeout: 30.0)
        print("✅ Found \(connectedPeers.count) connected peers!")
        
        print("🎉 Interoperability test completed successfully!")
    }
    
    private func waitForPeerConnection(timeout: TimeInterval) async throws {
        let startTime = Date()
        
        while connectedPeers.isEmpty {
            if Date().timeIntervalSince(startTime) > timeout {
                throw InteropTestError.timeout("No peers connected within \(timeout) seconds")
            }
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
    }
}

enum InteropTestError: Error {
    case timeout(String)
    case noConnection
    
    var localizedDescription: String {
        switch self {
        case .timeout(let message):
            return "Timeout: \(message)"
        case .noConnection:
            return "No connection established"
        }
    }
}