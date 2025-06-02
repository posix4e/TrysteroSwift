# TrysteroSwift

A Swift implementation of [Trystero](https://github.com/dmotz/trystero) - serverless WebRTC matchmaking for decentralized applications. Compatible with Trystero.js for cross-platform peer-to-peer communication.

## Features

🌐 **Decentralized** - No servers required, uses Nostr relays for peer discovery  
🔗 **WebRTC** - Direct peer-to-peer connections for low-latency communication  
🏠 **Room-based** - Organize peers into namespaces  
⚡ **Real-time** - Instant bidirectional data channels  
🔄 **Trystero.js Compatible** - Works seamlessly with JavaScript peers  

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/posix4e/TrysteroSwift.git", from: "2.0.0")
]
```

## Quick Start

```swift
import TrysteroSwift

// Join a room (matching Trystero.js API)
let config = Config(appId: "my-app")
let room = Trystero.joinRoom(config, "my-room")

// Make actions (data channels)
let (sendChat, getChat) = room.makeAction("chat")
let (sendFile, getFile) = room.makeAction("file")

// Handle peer events
room.onPeerJoin { peerId in
    print("Peer joined: \(peerId)")
    sendChat("Welcome!", peerId)
}

room.onPeerLeave { peerId in
    print("Peer left: \(peerId)")
}

// Receive data
getChat { message, peerId in
    print("\(peerId): \(message)")
}

getFile { fileData, peerId in
    // Handle file data
}

// Broadcast to all peers
sendChat("Hello everyone!", nil)

// Clean up
room.leave()
```

## JavaScript Compatibility

TrysteroSwift is designed to be fully compatible with [Trystero.js](https://github.com/dmotz/trystero):

```javascript
// JavaScript peer
import {joinRoom} from 'trystero/nostr'

const room = joinRoom({appId: 'my-app'}, 'my-room')
const [send, recv] = room.makeAction('chat')

recv((data, peerId) => console.log(`${peerId}: ${data}`))
room.onPeerJoin(id => send('Hello from JS!', id))
```

```swift
// Swift peer - fully compatible!
let room = Trystero.joinRoom(Config(appId: "my-app"), "my-room")
let (send, recv) = room.makeAction("chat")

recv { data, peerId in print("\(peerId): \(data)") }
room.onPeerJoin { id in send("Hello from Swift!", id) }
```

## API Reference

### Configuration

```swift
let config = Config(
    appId: "my-app",              // Required: identifies your app
    relayUrls: ["wss://..."],     // Optional: custom Nostr relays
    relayRedundancy: 2,           // Optional: number of relays to use
    rtcConfig: RTCConfiguration() // Optional: custom WebRTC config
)
```

### Room Methods

```swift
// Create actions (data channels)
let (send, receive) = room.makeAction("action-name")

// Send data
send("Hello", nil)        // Broadcast to all
send("Hello", peerId)     // Send to specific peer

// Receive data
receive { data, peerId in
    // Handle received data
}

// Media streams (audio/video)
room.addStream(stream)
room.removeStream(stream)
room.onPeerStream { stream, peerId in 
    // Handle incoming stream
}

// Peer management
let peers = room.getPeers()  // Get connected peer IDs
room.leave()                  // Leave room and cleanup
```

## How It Works

1. **Peer Discovery** - Peers find each other via Nostr relay announcements
2. **Signaling** - WebRTC offers/answers exchanged through Nostr events  
3. **Direct Connection** - WebRTC data channels established between peers
4. **Communication** - All data flows directly peer-to-peer

## Requirements

- iOS 17.0+ / macOS 14.0+
- Swift 6.0+
- Xcode 15.0+

## Examples

See the [Chat Example](Examples/Chat/) for a complete working application demonstrating all features.

```bash
cd Examples/Chat
swift run TrysteroChat
```

## Testing

Run the test suite:

```bash
swift test
```

For JavaScript interoperability tests:

```bash
cd Tests/Interop
npm install
npm test
```

## Contributing

We welcome contributions! Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [Trystero](https://github.com/dmotz/trystero) - Original JavaScript implementation
- [Nostr Protocol](https://nostr.com) - Decentralized relay network
- [WebRTC](https://webrtc.org) - Real-time communication standard
- [Galaxoid Labs NostrClient](https://github.com/Galaxoid-Labs/NostrClient) - Swift Nostr client

---

**Built with ❤️ for the decentralized web**