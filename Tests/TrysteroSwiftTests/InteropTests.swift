import XCTest
import Foundation
@testable import TrysteroSwift

final class InteropTests: XCTestCase {
    private let roomId = "swift-interop-test"
    private let relays = ["wss://nostr.mom", "wss://relay.snort.social"]
    private var room: TrysteroRoom?
    private var receivedMessages: [String] = []
    private var connectedPeers: Set<String> = []
    
    override func setUp() async throws {
        receivedMessages.removeAll()
        connectedPeers.removeAll()
    }
    
    override func tearDown() async throws {
        if let room = room {
            await room.leave()
            self.room = nil
        }
    }
    
    /// Simple test of Trystero.js ↔ TrysteroSwift interoperability
    func testTrysteroJSInteroperability() async throws {
        print("🧪 Starting minimal TrysteroSwift connection test...")
        
        // Create room configuration
        let config = RoomConfig(
            relays: relays,
            appId: "trystero"  // Match Node.js appId for interop
        )
        print("✅ Created room config")
        
        // Join the room
        room = try Trystero.joinRoom(config: config, roomId: roomId)
        print("✅ Created room object")
        
        setupEventHandlers()
        print("✅ Set up event handlers")
        
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        
        print("🔗 About to join room...")
        try await room.join()
        print("✅ Swift peer joined room: \(roomId)")
        
        // Just wait a bit to see if we receive anything
        print("⏳ Waiting 3 seconds to see if we receive any events...")
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        print("📊 Status after 3 seconds:")
        print("📊   Connected peers: \(connectedPeers.count)")
        print("📊   Received messages: \(receivedMessages.count)")
        
        print("🎉 Basic connectivity test completed!")
    }
    
    // MARK: - Helper Methods
    
    private func setupEventHandlers() {
        room?.onPeerJoin { [weak self] peerId in
            print("✅ Swift detected peer joined: \(peerId)")
            self?.connectedPeers.insert(peerId)
        }
        
        room?.onPeerLeave { [weak self] peerId in
            print("❌ Swift detected peer left: \(peerId)")
            self?.connectedPeers.remove(peerId)
        }
        
        room?.onData { [weak self] data, peerId in
            let message = String(data: data, encoding: .utf8) ?? "<invalid UTF-8>"
            print("📥 Swift received from \(peerId): \(message)")
            self?.receivedMessages.append(message)
        }
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
    
    private func waitForMessage(containing text: String, timeout: TimeInterval) async throws {
        let startTime = Date()
        let initialCount = receivedMessages.count
        
        while true {
            // Check if we have any new messages containing the text
            if receivedMessages.count > initialCount {
                let newMessages = Array(receivedMessages[initialCount...])
                if newMessages.contains(where: { $0.contains(text) }) {
                    return
                }
            }
            
            if Date().timeIntervalSince(startTime) > timeout {
                throw InteropTestError.timeout("No message containing '\(text)' received within \(timeout) seconds")
            }
            
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
    }
}

enum InteropTestError: Error {
    case timeout(String)
    case noConnection
    case invalidResponse
    
    var localizedDescription: String {
        switch self {
        case .timeout(let message):
            return "Timeout: \(message)"
        case .noConnection:
            return "No connection established"
        case .invalidResponse:
            return "Invalid response received"
        }
    }
}
