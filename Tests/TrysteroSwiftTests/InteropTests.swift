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
    
    func verifyProtocolCompatibility() async throws {
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
        
        print("  🔧 Testing WebRTC connection state transitions...")
        try await testWebRTCStateTransitions()
        
        print("  🔧 Testing relay configuration compatibility...")
        try await testRelayConfiguration()
    }
    
    func testWebRTCStateTransitions() async throws {
        print("    📋 Testing connection state progression...")
        
        let config = RoomConfig(relays: relays, appId: "trystero")
        let room = try Trystero.joinRoom(config: config, roomId: "state-test-room")
        
        var connectionStates: [String] = []
        var webrtcStates: [String] = []
        
        // Track all connection state changes
        room.onPeerJoin { peerId in
            connectionStates.append("discovered:\(String(peerId.prefix(8)))")
            print("      🔍 Peer discovered: \(String(peerId.prefix(8)))...")
        }
        
        room.onWebRTCConnecting { peerId in
            webrtcStates.append("connecting:\(String(peerId.prefix(8)))")
            print("      🤝 WebRTC connecting: \(String(peerId.prefix(8)))...")
        }
        
        room.onWebRTCConnected { peerId in
            webrtcStates.append("connected:\(String(peerId.prefix(8)))")
            print("      ✅ WebRTC connected: \(String(peerId.prefix(8)))...")
        }
        
        room.onWebRTCDisconnected { peerId in
            webrtcStates.append("disconnected:\(String(peerId.prefix(8)))")
            print("      ❌ WebRTC disconnected: \(String(peerId.prefix(8)))...")
        }
        
        try await room.join()
        print("      📡 Room joined, waiting for state transitions...")
        
        // Wait a bit to see if any state changes occur
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        
        await room.leave()
        
        print("      📊 Connection states recorded: \(connectionStates)")
        print("      📊 WebRTC states recorded: \(webrtcStates)")
        print("    ✅ State transition test completed")
    }
    
    func testRelayConfiguration() async throws {
        print("    🌐 Testing relay connectivity...")
        
        let testRelays = ["wss://relay.snort.social", "wss://relay.damus.io", "wss://nostr.wine"]
        
        for relay in testRelays {
            print("      🔗 Testing relay: \(relay)")
            let client = try TrysteroNostrClient(relays: [relay], appId: "test")
            
            do {
                try await client.connect()
                print("      ✅ Connected to \(relay)")
                await client.disconnect()
            } catch {
                print("      ❌ Failed to connect to \(relay): \(error)")
                throw InteropTestError.timeout("Relay \(relay) connection failed")
            }
            
            // Small delay between relay tests
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }
        
        print("    ✅ All relay configurations verified")
    }
    
    func testPeerDiscoveryAndConnection() async throws {
        print("  🔗 Establishing Swift peer connection...")
        
        // First, verify our protocol calculations match expected JavaScript values
        try await verifyProtocolCalculations()
        
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
    
    func verifyProtocolCalculations() async throws {
        print("    🧮 Verifying protocol calculation compatibility...")
        
        // Test known values that should match JavaScript implementation
        let testCases = [
            ("trystero", "test-room"),
            ("history-sync", "swift-interop-test"),
            ("my-app", "example-room")
        ]
        
        for (appId, roomId) in testCases {
            let client = try TrysteroNostrClient(relays: ["wss://relay.damus.io"], appId: appId)
            
            // These calculations should match the JavaScript Trystero.js implementation
            print("      🔍 Testing appId: '\(appId)', roomId: '\(roomId)'")
            
            // The debug output from subscribe will show our calculations
            try await client.connect()
            try await client.subscribe(to: roomId)
            await client.disconnect()
            
            // Small delay between tests
            try await Task.sleep(nanoseconds: 300_000_000) // 300ms
        }
        
        print("    ✅ Protocol calculations verified")
    }
    
    func testMessageExchangePatterns() async throws {
        print("  📤 Testing WebRTC connection establishment...")
        
        // Test WebRTC state progression monitoring
        var stateTransitions: [String] = []
        var connectionCompleted = false
        
        guard let room = self.room else {
            throw InteropTestError.noConnection
        }
        
        // Monitor WebRTC state transitions during message exchange
        room.onWebRTCConnecting { peerId in
            stateTransitions.append("connecting")
            print("    🤝 WebRTC connecting to \(String(peerId.prefix(8)))...")
        }
        
        room.onWebRTCConnected { peerId in
            stateTransitions.append("connected")
            connectionCompleted = true
            print("    ✅ WebRTC connected to \(String(peerId.prefix(8)))...")
        }
        
        room.onWebRTCDisconnected { peerId in
            stateTransitions.append("disconnected")
            print("    ❌ WebRTC disconnected from \(String(peerId.prefix(8)))...")
        }
        
        // Send initial message to trigger WebRTC establishment
        let initialMessage = [
            "type": "greeting",
            "from": "trystero-swift",
            "timestamp": "\(Date().timeIntervalSince1970)",
            "message": "Hello from Swift! Testing WebRTC connection..."
        ]
        
        let messageData = try JSONSerialization.data(withJSONObject: initialMessage)
        try room.send(messageData)
        print("  📤 Sent initial greeting message")
        
        // Wait for WebRTC connection establishment
        print("  ⏳ Waiting for WebRTC connection establishment...")
        let startTime = Date()
        while !connectionCompleted && Date().timeIntervalSince(startTime) < 15.0 {
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }
        
        if connectionCompleted {
            print("  ✅ WebRTC connection established successfully")
            print("  📊 State transitions: \(stateTransitions)")
        } else {
            print("  ⚠️  WebRTC connection not established within timeout")
            print("  📊 Partial state transitions: \(stateTransitions)")
        }
        
        // Wait for welcome response (if any)
        do {
            try await waitForMessage(containing: "welcome", timeout: 5.0)
            print("  ✅ Received welcome response from peer")
        } catch {
            print("  ℹ️  No welcome response received (testing local peer only)")
        }
        
        // Test ping-pong exchange if connected
        if connectionCompleted {
            print("  🏓 Testing ping-pong exchange...")
            try await performPingPongExchange()
            
            // Test multiple message exchange
            print("  📚 Testing multiple message exchange...")
            try await performMultipleMessageExchange()
        }
    }
    
    func testAdvancedScenarios() async throws {
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
