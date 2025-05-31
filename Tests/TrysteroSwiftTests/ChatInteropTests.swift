import XCTest
import Foundation
@testable import TrysteroSwift

final class ChatInteropTests: XCTestCase {
    private let roomId = "swift-chat-test"
    private let relays = ["wss://relay.damus.io", "wss://nos.lol"]
    private var room: TrysteroRoom?
    private var receivedMessages: [ChatMessage] = []
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
    
    /// Interactive chat test for manual testing with Chrome/Node.js
    func testInteractiveChatWithChrome() async throws {
        print("🗣️  Starting interactive chat test...")
        print("💡 Instructions:")
        print("   1. Run: cd Tests/Interop && node trystero-node.js --chat")
        print("   2. Type messages in the Node.js terminal")
        print("   3. This Swift test will echo messages back")
        print("   4. Press Ctrl+C in Node.js to stop")
        
        // Connect to room
        let config = RoomConfig(relays: relays, appId: "trystero")
        room = try Trystero.joinRoom(config: config, roomId: roomId)
        setupChatEventHandlers()
        
        guard let room = self.room else {
            throw ChatTestError.noConnection
        }
        
        try await room.join()
        print("✅ Swift chat peer connected to room: \(roomId)")
        
        // Send initial greeting
        try await sendChatMessage("Hello from Swift! Ready to chat.")
        
        // Wait for peer connection
        print("⏳ Waiting for Chrome/Node.js peer to connect...")
        try await waitForPeerConnection(timeout: 60.0)
        print("✅ Chrome/Node.js peer connected!")
        
        // Interactive chat loop - run for 5 minutes
        print("🗣️  Starting 5-minute interactive chat session...")
        print("📝 Swift will send periodic messages and log all received messages")
        
        let startTime = Date()
        let chatDuration: TimeInterval = 300 // 5 minutes
        var messageCounter = 1
        var lastMessageTime = Date()
        
        while Date().timeIntervalSince(startTime) < chatDuration {
            // Send a message every 10 seconds if we have peers
            if !connectedPeers.isEmpty && Date().timeIntervalSince(lastMessageTime) > 10 {
                let message = "Swift message #\(messageCounter) - \(Date().formatted(date: .omitted, time: .shortened))"
                try await sendChatMessage(message)
                messageCounter += 1
                lastMessageTime = Date()
            }
            
            // Check for new messages and echo them
            await processPendingMessages()
            
            // Small delay to prevent busy waiting
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        }
        
        // Send goodbye message
        try await sendChatMessage("Chat session ended. Goodbye from Swift!")
        print("👋 5-minute chat session completed")
        
        // Show chat summary
        printChatSummary()
    }
    
    private func setupChatEventHandlers() {
        room?.onPeerJoin { [weak self] peerId in
            print("👋 Peer joined chat: \(String(peerId.prefix(8)))...")
            self?.connectedPeers.insert(peerId)
        }
        
        room?.onPeerLeave { [weak self] peerId in
            print("👋 Peer left chat: \(String(peerId.prefix(8)))...")
            self?.connectedPeers.remove(peerId)
        }
        
        room?.onData { [weak self] data, peerId in
            guard let messageText = String(data: data, encoding: .utf8) else { return }
            
            let message = ChatMessage(
                text: messageText,
                sender: String(peerId.prefix(8)) + "...",
                timestamp: Date(),
                isFromSelf: false
            )
            
            self?.receivedMessages.append(message)
            print("📥 Received: \"\(messageText)\" from \(message.sender)")
        }
    }
    
    private func sendChatMessage(_ text: String) async throws {
        let chatMessage = [
            "type": "chat",
            "from": "swift-user",
            "timestamp": "\(Int(Date().timeIntervalSince1970 * 1000))",
            "message": text
        ]
        
        let messageData = try JSONSerialization.data(withJSONObject: chatMessage)
        guard let room = self.room else {
            throw ChatTestError.noConnection
        }
        
        try room.send(messageData)
        print("📤 Sent: \"\(text)\"")
    }
    
    private func processPendingMessages() async {
        // This is handled by the event handlers automatically
        // Just a placeholder for any additional processing needed
    }
    
    private func waitForPeerConnection(timeout: TimeInterval) async throws {
        let startTime = Date()
        
        while connectedPeers.isEmpty {
            if Date().timeIntervalSince(startTime) > timeout {
                throw ChatTestError.timeout("No peers connected within \(timeout) seconds")
            }
            
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
    }
    
    private func printChatSummary() {
        print("\n📊 Chat Session Summary:")
        print("   Messages received: \(receivedMessages.count)")
        print("   Connected peers: \(connectedPeers.count)")
        print("   Room ID: \(roomId)")
        
        if !receivedMessages.isEmpty {
            print("\n💬 Last few messages:")
            for message in receivedMessages.suffix(5) {
                let timeStr = DateFormatter.localizedString(from: message.timestamp, 
                                                           dateStyle: .none, 
                                                           timeStyle: .medium)
                print("   [\(timeStr)] \(message.sender): \(message.text)")
            }
        }
    }
}

struct ChatMessage {
    let text: String
    let sender: String
    let timestamp: Date
    let isFromSelf: Bool
}

enum ChatTestError: Error {
    case timeout(String)
    case noConnection
    case invalidMessage
    
    var localizedDescription: String {
        switch self {
        case .timeout(let message):
            return "Timeout: \(message)"
        case .noConnection:
            return "No connection established"
        case .invalidMessage:
            return "Invalid message format"
        }
    }
}
