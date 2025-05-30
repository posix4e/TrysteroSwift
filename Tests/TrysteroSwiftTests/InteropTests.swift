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
    
    /// Test basic connection and message exchange with Node.js Trystero
    func testBasicInteropWithNodeJS() async throws {
        print("🧪 Starting Swift interop test...")
        
        // Create room configuration
        let config = RoomConfig(
            appId: "trystero-swift-interop",
            relays: relays
        )
        
        // Join the room
        room = try Trystero.joinRoom(config: config, roomId: roomId)
        
        // Set up event handlers
        setupEventHandlers()
        
        // Join the room
        try await room!.join()
        print("✅ Swift peer joined room: \(roomId)")
        
        // Wait for Node.js peer connection
        print("⏳ Waiting for Node.js peer to connect...")
        try await waitForPeerConnection(timeout: 30.0)
        
        // Send initial message
        let initialMessage = [
            "type": "greeting",
            "from": "trystero-swift",
            "timestamp": "\(Date().timeIntervalSince1970)",
            "message": "Hello from Swift!"
        ]
        
        let messageData = try JSONSerialization.data(withJSONObject: initialMessage)
        let messageString = String(data: messageData, encoding: .utf8)!
        
        try room!.send(messageString)
        print("📤 Sent initial greeting message")
        
        // Wait for response
        try await waitForMessage(containing: "welcome", timeout: 10.0)
        print("✅ Received welcome response from Node.js")
        
        // Test ping-pong exchange
        try await testPingPongExchange()
        
        // Test multiple message exchange
        try await testMultipleMessageExchange()
        
        print("🎉 Interop test completed successfully!")
    }
    
    /// Test ping-pong message exchange
    private func testPingPongExchange() async throws {
        print("🏓 Testing ping-pong exchange...")
        
        let pingMessage = [
            "type": "ping",
            "from": "trystero-swift", 
            "timestamp": "\(Date().timeIntervalSince1970)",
            "message": "ping from Swift"
        ]
        
        let messageData = try JSONSerialization.data(withJSONObject: pingMessage)
        let messageString = String(data: messageData, encoding: .utf8)!
        
        try room!.send(messageString)
        print("📤 Sent ping message")
        
        // Wait for pong response
        try await waitForMessage(containing: "pong", timeout: 5.0)
        print("✅ Received pong response")
    }
    
    /// Test multiple rapid message exchanges
    private func testMultipleMessageExchange() async throws {
        print("📚 Testing multiple message exchange...")
        
        let messageCount = 5
        var sentMessages: [String] = []
        
        for i in 1...messageCount {
            let message = [
                "type": "test_message",
                "from": "trystero-swift",
                "timestamp": "\(Date().timeIntervalSince1970)",
                "messageNumber": "\(i)",
                "content": "Test message #\(i) from Swift"
            ]
            
            let messageData = try JSONSerialization.data(withJSONObject: message)
            let messageString = String(data: messageData, encoding: .utf8)!
            
            try room!.send(messageString)
            sentMessages.append(messageString)
            print("📤 Sent message #\(i)")
            
            // Small delay between messages
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        
        // Wait for all echo responses
        for i in 1...messageCount {
            try await waitForMessage(containing: "echo", timeout: 5.0)
            print("✅ Received echo response #\(i)")
        }
        
        print("✅ All \(messageCount) messages exchanged successfully")
    }
    
    /// Test direct peer-to-peer messaging
    func testDirectPeerMessaging() async throws {
        print("🎯 Testing direct peer messaging...")
        
        // Join room and wait for peer
        let config = RoomConfig(
            appId: "trystero-swift-interop",
            relays: relays
        )
        
        room = try Trystero.joinRoom(config: config, roomId: roomId)
        setupEventHandlers()
        try await room!.join()
        
        try await waitForPeerConnection(timeout: 30.0)
        
        // Get the first connected peer
        guard let targetPeer = connectedPeers.first else {
            XCTFail("No peers connected for direct messaging test")
            return
        }
        
        let directMessage = [
            "type": "direct_message",
            "from": "trystero-swift",
            "timestamp": "\(Date().timeIntervalSince1970)",
            "message": "This is a direct message to \(targetPeer)"
        ]
        
        let messageData = try JSONSerialization.data(withJSONObject: directMessage)
        let messageString = String(data: messageData, encoding: .utf8)!
        
        try room!.send(messageString, to: targetPeer)
        print("📤 Sent direct message to \(targetPeer)")
        
        // Wait for response
        try await waitForMessage(containing: "echo", timeout: 10.0)
        print("✅ Received direct message response")
    }
    
    /// Test room persistence and reconnection
    func testRoomPersistenceAndReconnection() async throws {
        print("🔄 Testing room persistence and reconnection...")
        
        // Initial connection
        let config = RoomConfig(
            appId: "trystero-swift-interop",
            relays: relays
        )
        
        room = try Trystero.joinRoom(config: config, roomId: roomId)
        setupEventHandlers()
        try await room!.join()
        
        try await waitForPeerConnection(timeout: 30.0)
        
        // Send message before disconnection
        let beforeMessage = [
            "type": "before_disconnect",
            "from": "trystero-swift",
            "timestamp": "\(Date().timeIntervalSince1970)",
            "message": "Message before disconnection"
        ]
        
        let messageData = try JSONSerialization.data(withJSONObject: beforeMessage)
        let messageString = String(data: messageData, encoding: .utf8)!
        
        try room!.send(messageString)
        print("📤 Sent message before disconnection")
        
        // Simulate disconnection
        await room!.leave()
        print("🔌 Disconnected from room")
        
        // Clear state
        connectedPeers.removeAll()
        receivedMessages.removeAll()
        
        // Reconnect
        room = try Trystero.joinRoom(config: config, roomId: roomId)
        setupEventHandlers()
        try await room!.join()
        print("🔌 Reconnected to room")
        
        // Wait for peer reconnection
        try await waitForPeerConnection(timeout: 30.0)
        
        // Send message after reconnection
        let afterMessage = [
            "type": "after_reconnect",
            "from": "trystero-swift",
            "timestamp": "\(Date().timeIntervalSince1970)",
            "message": "Message after reconnection"
        ]
        
        let afterData = try JSONSerialization.data(withJSONObject: afterMessage)
        let afterString = String(data: afterData, encoding: .utf8)!
        
        try room!.send(afterString)
        print("📤 Sent message after reconnection")
        
        try await waitForMessage(containing: "echo", timeout: 10.0)
        print("✅ Successfully reconnected and exchanged messages")
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