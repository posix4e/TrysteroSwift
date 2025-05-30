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
            relays: relays
        )
        
        // Join the room
        room = try Trystero.joinRoom(config: config, roomId: roomId)
        
        // Set up event handlers
        setupEventHandlers()
        
        // Join the room
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        try await room.join()
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
        guard let messageString = String(data: messageData, encoding: .utf8) else {
            throw InteropTestError.invalidResponse
        }
        
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        try room.send(messageData)
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
    func testPingPongExchange() async throws {
        print("🏓 Testing ping-pong exchange...")
        
        let pingMessage = [
            "type": "ping",
            "from": "trystero-swift", 
            "timestamp": "\(Date().timeIntervalSince1970)",
            "message": "ping from Swift"
        ]
        
        let messageData = try JSONSerialization.data(withJSONObject: pingMessage)
        guard let messageString = String(data: messageData, encoding: .utf8) else {
            throw InteropTestError.invalidResponse
        }
        
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        try room.send(messageData)
        print("📤 Sent ping message")
        
        // Wait for pong response
        try await waitForMessage(containing: "pong", timeout: 5.0)
        print("✅ Received pong response")
    }
    
    /// Test multiple rapid message exchanges
    func testMultipleMessageExchange() async throws {
        print("📚 Testing multiple message exchange...")
        
        let messageCount = 5
        var sentMessages: [String] = []
        
        for index in 1...messageCount {
            let message = [
                "type": "test_message",
                "from": "trystero-swift",
                "timestamp": "\(Date().timeIntervalSince1970)",
                "messageNumber": "\(index)",
                "content": "Test message #\(index) from Swift"
            ]
            
            let messageData = try JSONSerialization.data(withJSONObject: message)
            guard let messageString = String(data: messageData, encoding: .utf8) else {
                throw InteropTestError.invalidResponse
            }
            
            guard let room = self.room else {
                throw InteropTestError.noConnection
            }
            try room.send(messageData)
            sentMessages.append(messageString)
            print("📤 Sent message #\(index)")
            
            // Small delay between messages
            try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        
        // Wait for all echo responses
        for index in 1...messageCount {
            try await waitForMessage(containing: "echo", timeout: 5.0)
            print("✅ Received echo response #\(index)")
        }
        
        print("✅ All \(messageCount) messages exchanged successfully")
    }
    
    /// Test direct peer-to-peer messaging
    func testDirectPeerMessaging() async throws {
        print("🎯 Testing direct peer messaging...")
        
        // Join room and wait for peer
        let config = RoomConfig(
            relays: relays
        )
        
        room = try Trystero.joinRoom(config: config, roomId: roomId)
        setupEventHandlers()
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        try await room.join()
        
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
        guard let messageString = String(data: messageData, encoding: .utf8) else {
            throw InteropTestError.invalidResponse
        }
        
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        try room.send(messageData, to: targetPeer)
        print("📤 Sent direct message to \(targetPeer)")
        
        // Wait for response
        try await waitForMessage(containing: "echo", timeout: 10.0)
        print("✅ Received direct message response")
    }
    
    /// Test room persistence and reconnection
    func testRoomPersistenceAndReconnection() async throws {
        print("🔄 Testing room persistence and reconnection...")
        
        let config = RoomConfig(relays: relays)
        
        // Initial connection and send message
        try await performInitialConnection(config: config)
        try await sendTestMessage(type: "before_disconnect", message: "Message before disconnection")
        
        // Disconnect and reconnect
        try await simulateDisconnectAndReconnect(config: config)
        
        // Send message after reconnection and verify
        try await sendTestMessage(type: "after_reconnect", message: "Message after reconnection")
        try await waitForMessage(containing: "echo", timeout: 10.0)
        print("✅ Successfully reconnected and exchanged messages")
    }
    
    // MARK: - Helper Methods
    
    private func performInitialConnection(config: RoomConfig) async throws {
        room = try Trystero.joinRoom(config: config, roomId: roomId)
        setupEventHandlers()
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        try await room.join()
        try await waitForPeerConnection(timeout: 30.0)
    }
    
    private func sendTestMessage(type: String, message: String) async throws {
        let messageDict = [
            "type": type,
            "from": "trystero-swift",
            "timestamp": "\(Date().timeIntervalSince1970)",
            "message": message
        ]
        
        let messageData = try JSONSerialization.data(withJSONObject: messageDict)
        guard let messageString = String(data: messageData, encoding: .utf8) else {
            throw InteropTestError.invalidResponse
        }
        
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        try room.send(messageData)
        print("📤 Sent \(type) message")
    }
    
    private func simulateDisconnectAndReconnect(config: RoomConfig) async throws {
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        await room.leave()
        print("🔌 Disconnected from room")
        
        connectedPeers.removeAll()
        receivedMessages.removeAll()
        
        self.room = try Trystero.joinRoom(config: config, roomId: roomId)
        setupEventHandlers()
        guard let newRoom = self.room else {
            throw InteropTestError.noConnection
        }
        try await newRoom.join()
        print("🔌 Reconnected to room")
        try await waitForPeerConnection(timeout: 30.0)
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
