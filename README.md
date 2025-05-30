# TrysteroSwift

A Swift library for decentralized peer-to-peer communication using Nostr for peer discovery and WebRTC for data channels. TrysteroSwift provides a Trystero-compatible API for building serverless, real-time applications.

## Features

🌐 **Decentralized** - No central servers required, uses Nostr relays for signaling  
🔗 **WebRTC** - Direct peer-to-peer data channels for low-latency communication  
🏠 **Room-based** - Organize peers into named rooms for group communication  
⚡ **Real-time** - Instant message delivery once P2P connections are established  
🔒 **Privacy-focused** - Data flows directly between peers after initial discovery  

## Quick Start

### Installation

Add TrysteroSwift to your Swift package:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/TrysteroSwift.git", from: "1.0.0")
]
```

### Basic Usage

```swift
import TrysteroSwift

// Create a room configuration
let config = RoomConfig(relays: [
    "wss://relay.damus.io",
    "wss://nos.lol"
])

// Join a room
let room = try Trystero.joinRoom(config: config, roomId: "my-awesome-room")
try await room.join()

// Send data to all peers
let message = "Hello, decentralized world!".data(using: .utf8)!
try room.send(message)

// Send data to specific peer
try room.send(message, to: "peer-id")

// Handle events
room.onPeerJoin { peerId in
    print("Peer joined: \(peerId)")
}

room.onPeerLeave { peerId in
    print("Peer left: \(peerId)")
}

room.onData { data, peerId in
    let message = String(data: data, encoding: .utf8) ?? "Unknown"
    print("Received from \(peerId): \(message)")
}

// Leave the room
await room.leave()
```

## Architecture

TrysteroSwift combines two powerful technologies:

1. **Nostr** - Decentralized relay network for peer discovery and WebRTC signaling
2. **WebRTC** - Direct peer-to-peer data channels for actual communication

### Connection Flow

```
1. Join Room → 2. Discover Peers → 3. Exchange Signals → 4. Direct P2P
     ↓              ↓ (via Nostr)      ↓ (via Nostr)      ↓ (WebRTC)
   [Relay]        [Relay]           [Relay]          [Peer ←→ Peer]
```

After the initial handshake, all communication bypasses the Nostr relays and flows directly between peers.

## API Reference

### RoomConfig

Configure Nostr relays and other room settings:

```swift
let config = RoomConfig(
    relays: ["wss://relay.damus.io", "wss://nos.lol"],
    password: nil  // Future: room passwords
)
```

### TrysteroRoom

Main interface for room-based communication:

```swift
// Join/leave
try await room.join()
await room.leave()

// Send data
try room.send(data)                    // Broadcast to all
try room.send(data, to: peerId)        // Send to specific peer

// Get current peers
let peerIds = room.getPeers()

// Event handlers
room.onPeerJoin { peerId in /* ... */ }
room.onPeerLeave { peerId in /* ... */ }
room.onData { data, peerId in /* ... */ }
```

### Error Handling

```swift
do {
    try room.send(data, to: "unknown-peer")
} catch TrysteroError.peerNotConnected {
    print("Peer is not connected")
} catch TrysteroError.connectionFailed {
    print("WebRTC connection failed")
} catch TrysteroError.nostrError {
    print("Nostr relay error")
}
```

## Platform Support

- **iOS** 13.0+
- **macOS** 14.0+
- **Swift** 6.1+

## Requirements

TrysteroSwift uses binary WebRTC frameworks and requires:
- Xcode with Swift Package Manager
- Network permissions for WebRTC connections
- Internet connectivity for Nostr relay access

## Comparison with Trystero

TrysteroSwift aims for API compatibility with the original JavaScript [Trystero](https://github.com/dmotz/trystero) library:

| Feature | Trystero (JS) | TrysteroSwift |
|---------|---------------|---------------|
| **Peer Discovery** | Multiple strategies | Nostr-only |
| **API Style** | Callback-based | async/await + callbacks |
| **Platform** | Web browsers | iOS/macOS native |
| **Language** | JavaScript | Swift |

## Contributing

We welcome contributions! Please see our contributing guidelines and:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [Trystero](https://github.com/dmotz/trystero) - Original JavaScript implementation and API design
- [Nostr Protocol](https://nostr.com) - Decentralized relay network
- [WebRTC](https://webrtc.org) - Real-time communication standard
- [Galaxoid Labs NostrClient](https://github.com/Galaxoid-Labs/NostrClient) - Swift Nostr implementation

## Related Projects

- [Trystero](https://github.com/dmotz/trystero) - Original JavaScript library
- [NostrClient](https://github.com/Galaxoid-Labs/NostrClient) - Swift Nostr client
- [WebRTC-iOS](https://github.com/stasel/WebRTC) - WebRTC framework for iOS

---

**Built with ❤️ for the decentralized web**