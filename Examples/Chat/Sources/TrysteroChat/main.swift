import Foundation
import TrysteroSwift

// Simple P2P Chat using TrysteroSwift
// This demonstrates the core API and serves as a living test

print("🌐 TrysteroSwift Chat")
print("====================")

// Get configuration from environment or use defaults
let roomName = ProcessInfo.processInfo.environment["CHAT_ROOM"] ?? "trystero-chat-demo"
let userName = ProcessInfo.processInfo.environment["USER_NAME"] ?? "User-\(Int.random(in: 1000...9999))"
let appId = ProcessInfo.processInfo.environment["APP_ID"] ?? "trystero-swift-chat"

print("👤 Your name: \(userName)")
print("🏠 Room: \(roomName)")
print("📡 Connecting to Nostr relays...")

// Create room with custom relays for better reliability
let relayUrls = ProcessInfo.processInfo.environment["RELAY_URLS"]?
    .split(separator: ",")
    .map { String($0).trimmingCharacters(in: .whitespaces) } ?? [
        "ws://localhost:7447"
    ]

let config = Config(
    appId: appId,
    relayUrls: relayUrls,
    relayRedundancy: relayUrls.count
)

let room = Trystero.joinRoom(config, roomName)

// Create chat action - this is the core Trystero pattern
let (sendMessage, onMessage) = room.makeAction("chat")

// Track connected peers
var connectedPeers: Set<String> = []

// Handle incoming messages
onMessage { data, _ in
    if let message = data as? [String: Any],
       let text = message["text"] as? String,
       let from = message["from"] as? String,
       let timestamp = message["timestamp"] as? Double {

        let date = Date(timeIntervalSince1970: timestamp)
        let time = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)

        print("\n[\(time)] \(from): \(text)")
        print("> ", terminator: "")
        fflush(stdout)
    }
}

// Handle peer events
room.onPeerJoin { peerId in
    connectedPeers.insert(peerId)
    print("\n✅ \(peerId) joined (Total peers: \(connectedPeers.count))")

    // Send a welcome message
    let welcome: [String: Any] = [
        "text": "\(userName) joined the chat",
        "from": "System",
        "timestamp": Date().timeIntervalSince1970
    ]
    sendMessage(welcome, peerId)

    print("> ", terminator: "")
    fflush(stdout)
}

room.onPeerLeave { peerId in
    connectedPeers.remove(peerId)
    print("\n❌ \(peerId) left (Total peers: \(connectedPeers.count))")
    print("> ", terminator: "")
    fflush(stdout)
}

print("✅ Connected! Type messages to chat, or 'quit' to exit.\n")

// Show commands
print("Commands:")
print("  /peers  - List connected peers")
print("  /room   - Show room info")
print("  /quit   - Exit chat\n")

// Main chat loop
print("> ", terminator: "")
fflush(stdout)

while let input = readLine() {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmed.isEmpty {
        print("> ", terminator: "")
        fflush(stdout)
        continue
    }

    // Handle commands
    if trimmed.hasPrefix("/") {
        switch trimmed {
        case "/quit", "/exit", "/q":
            print("👋 Goodbye!")
            room.leave()
            exit(0)

        case "/peers", "/list":
            if connectedPeers.isEmpty {
                print("No peers connected")
            } else {
                print("Connected peers (\(connectedPeers.count)):")
                for peer in connectedPeers {
                    print("  • \(peer)")
                }
            }

        case "/room", "/info":
            print("Room: \(roomName)")
            print("Your ID: \(userName)")
            print("App ID: \(appId)")
            print("Connected peers: \(connectedPeers.count)")

        default:
            print("Unknown command: \(trimmed)")
            print("Available commands: /peers, /room, /quit")
        }
    } else {
        // Send chat message
        let message: [String: Any] = [
            "text": trimmed,
            "from": userName,
            "timestamp": Date().timeIntervalSince1970
        ]

        // Broadcast to all peers
        sendMessage(message, nil)

        // Show our own message
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        print("[\(time)] You: \(trimmed)")
    }

    print("> ", terminator: "")
    fflush(stdout)
}

// Keep the program running
RunLoop.main.run()
