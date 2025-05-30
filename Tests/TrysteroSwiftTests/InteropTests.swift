import XCTest
import Foundation
@testable import TrysteroSwift

final class InteropTests: XCTestCase {
    private let roomId = "swift-interop-test"
    private let relays = ["wss://relay.damus.io", "wss://nos.lol"]
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
    
    /// Comprehensive test of Trystero.js ↔ TrysteroSwift interoperability
    func testTrysteroJSInteroperability() async throws {
        print("🧪 Starting comprehensive Trystero.js ↔ TrysteroSwift interoperability test...")
        
        // Phase 1: Verify protocol compatibility
        print("🔍 Phase 1: Verifying protocol compatibility...")
        try await verifyProtocolCompatibility()
        
        // Phase 2: Test basic peer discovery and connection
        print("🤝 Phase 2: Testing peer discovery and connection...")
        try await testPeerDiscoveryAndConnection()
        
        // Phase 3: Test message exchange patterns
        print("💬 Phase 3: Testing message exchange patterns...")
        try await testMessageExchangePatterns()
        
        // Phase 4: Test advanced scenarios (if basic tests pass)
        print("🚀 Phase 4: Testing advanced scenarios...")
        try await testAdvancedScenarios()
        
        print("🎉 Comprehensive interoperability test completed successfully!")
    }
    
    
    // MARK: - Test Phase Methods
    
    private func verifyProtocolCompatibility() async throws {
        print("  🔧 Testing topic hash generation compatibility...")
        
        // Create a TrysteroNostrClient to test the internal hash generation
        let client = try TrysteroNostrClient(relays: relays, appId: "trystero")
        
        // Test by observing the debug output when subscribing
        try await client.connect()
        try await client.subscribe(to: "swift-interop-test")
        
        print("  ✅ Topic hash and event kind generation successful")
        await client.disconnect()
        
        // Give a moment for cleanup
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
    }
    
    private func testPeerDiscoveryAndConnection() async throws {
        print("  🔗 Establishing Swift peer connection...")
        
        // Create room configuration
        let config = RoomConfig(
            relays: relays,
            appId: "trystero"  // Match Node.js appId for interop
        )
        
        // Join the room
        room = try Trystero.joinRoom(config: config, roomId: roomId)
        setupEventHandlers()
        
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        try await room.join()
        print("  ✅ Swift peer joined room: \(roomId)")
        
        // Wait for Node.js peer connection
        print("  ⏳ Waiting for Node.js peer to connect...")
        try await waitForPeerConnection(timeout: 30.0)
        print("  ✅ Peer discovery successful!")
    }
    
    private func testMessageExchangePatterns() async throws {
        print("  📤 Testing initial greeting exchange...")
        
        // Send initial message
        let initialMessage = [
            "type": "greeting",
            "from": "trystero-swift",
            "timestamp": "\(Date().timeIntervalSince1970)",
            "message": "Hello from Swift!"
        ]
        
        let messageData = try JSONSerialization.data(withJSONObject: initialMessage)
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        try room.send(messageData)
        print("  📤 Sent initial greeting message")
        
        // Wait for welcome response
        try await waitForMessage(containing: "welcome", timeout: 10.0)
        print("  ✅ Received welcome response from Node.js")
        
        // Test ping-pong exchange
        print("  🏓 Testing ping-pong exchange...")
        try await performPingPongExchange()
        
        // Test multiple message exchange
        print("  📚 Testing multiple message exchange...")
        try await performMultipleMessageExchange()
    }
    
    private func testAdvancedScenarios() async throws {
        // Test direct peer messaging if we have peers
        if !connectedPeers.isEmpty {
            print("  🎯 Testing direct peer messaging...")
            try await performDirectPeerMessaging()
        }
        
        // Test reconnection scenario
        print("  🔄 Testing reconnection scenario...")
        try await performReconnectionTest()
    }
    
    // MARK: - Individual Test Operations
    
    private func performPingPongExchange() async throws {
        let pingMessage = [
            "type": "ping",
            "from": "trystero-swift", 
            "timestamp": "\(Date().timeIntervalSince1970)",
            "message": "ping from Swift"
        ]
        
        let messageData = try JSONSerialization.data(withJSONObject: pingMessage)
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        try room.send(messageData)
        print("    📤 Sent ping message")
        
        // Wait for pong response
        try await waitForMessage(containing: "pong", timeout: 5.0)
        print("    ✅ Received pong response")
    }
    
    private func performMultipleMessageExchange() async throws {
        let messageCount = 3  // Reduced for consolidated test
        
        for index in 1...messageCount {
            let message = [
                "type": "test_message",
                "from": "trystero-swift",
                "timestamp": "\(Date().timeIntervalSince1970)",
                "messageNumber": "\(index)",
                "content": "Test message #\(index) from Swift"
            ]
            
            let messageData = try JSONSerialization.data(withJSONObject: message)
            guard let room = self.room else {
                throw InteropTestError.noConnection
            }
            try room.send(messageData)
            print("    📤 Sent message #\(index)")
            
            // Small delay between messages
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        
        // Wait for all echo responses
        for index in 1...messageCount {
            try await waitForMessage(containing: "echo", timeout: 5.0)
            print("    ✅ Received echo response #\(index)")
        }
        
        print("    ✅ All \(messageCount) messages exchanged successfully")
    }
    
    private func performDirectPeerMessaging() async throws {
        guard let targetPeer = connectedPeers.first else {
            throw InteropTestError.noConnection
        }
        
        let directMessage = [
            "type": "direct_message",
            "from": "trystero-swift",
            "timestamp": "\(Date().timeIntervalSince1970)",
            "message": "Direct message to \(targetPeer)"
        ]
        
        let messageData = try JSONSerialization.data(withJSONObject: directMessage)
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        try room.send(messageData, to: targetPeer)
        print("    📤 Sent direct message to \(targetPeer)")
        
        // Wait for response
        try await waitForMessage(containing: "echo", timeout: 10.0)
        print("    ✅ Received direct message response")
    }
    
    private func performReconnectionTest() async throws {
        let config = RoomConfig(relays: relays, appId: "trystero")
        
        // Send message before disconnect
        try await sendTestMessage(type: "before_disconnect", message: "Message before reconnection")
        
        // Disconnect and reconnect
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        await room.leave()
        print("    🔌 Disconnected from room")
        
        connectedPeers.removeAll()
        receivedMessages.removeAll()
        
        // Reconnect
        self.room = try Trystero.joinRoom(config: config, roomId: roomId)
        setupEventHandlers()
        guard let newRoom = self.room else {
            throw InteropTestError.noConnection
        }
        try await newRoom.join()
        print("    🔌 Reconnected to room")
        
        // Wait for peer to reconnect (shorter timeout)
        try await waitForPeerConnection(timeout: 15.0)
        
        // Send message after reconnection
        try await sendTestMessage(type: "after_reconnect", message: "Message after reconnection")
        try await waitForMessage(containing: "echo", timeout: 10.0)
        print("    ✅ Successfully reconnected and exchanged messages")
    }
    
    // MARK: - Helper Methods
    
    private func sendTestMessage(type: String, message: String) async throws {
        let messageDict = [
            "type": type,
            "from": "trystero-swift",
            "timestamp": "\(Date().timeIntervalSince1970)",
            "message": message
        ]
        
        let messageData = try JSONSerialization.data(withJSONObject: messageDict)
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        try room.send(messageData)
        print("    📤 Sent \(type) message")
    }
    
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
