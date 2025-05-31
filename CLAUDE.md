# TrysteroSwift Development Notes

## Project Overview
TrysteroSwift is a Swift library that provides Trystero-compatible peer-to-peer networking using Nostr for peer discovery and WebRTC for data channels. It enables decentralized, serverless communication between peers in named rooms.

## Architecture

### Core Components
- **TrysteroRoom**: Main class for room-based P2P communication
- **TrysteroNostrClient**: Handles Nostr relay connections and signaling
- **WebRTCManager**: Manages WebRTC peer connections and data channels
- **Trystero**: Public API factory class for creating rooms

### Dependencies
- **WebRTC**: `stasel/WebRTC` (release-M137) - WebRTC framework for P2P connections
- **NostrClient**: `Galaxoid-Labs/NostrClient` (main) - Nostr protocol implementation

### Nostr Integration
- Uses Trystero.js-compatible dynamic event kinds (base-36 SHA-1 hash + 20000) for WebRTC signaling
- Room identification via 'x' tags with truncated topic hashes: `Trystero@{appId}@{roomId}`
- Full protocol compatibility with Trystero.js library for cross-platform interoperability
- Peer targeting via pubkey tags when needed
- Automatic key pair generation for each room instance

### WebRTC Flow
1. Peers announce presence via Nostr events
2. WebRTC offers/answers exchanged through Nostr
3. ICE candidates shared via Nostr signaling
4. Direct P2P data channels established
5. Room communication bypasses Nostr relays

## API Design

### Public Interface
```swift
// Create and join a room with Trystero.js compatibility
let config = RoomConfig(
    relays: ["wss://nostr.mom", "wss://relay.snort.social"],
    appId: "trystero"  // Required for interoperability
)
let room = try Trystero.joinRoom(config: config, roomId: "my-room")
try await room.join()

// Send data to all peers or specific peer
try room.send(data)
try room.send(data, to: peerId)

// Event handlers
room.onPeerJoin { peerId in }
room.onPeerLeave { peerId in }
room.onData { data, peerId in }

// Clean up
await room.leave()
```

### Error Handling
- `TrysteroError.peerNotConnected` - Peer not available
- `TrysteroError.connectionFailed` - WebRTC connection issues
- `TrysteroError.nostrError` - Nostr-related failures

## Development Status

### Completed ✅
- **Core Protocol Implementation**
  - Trystero.js-compatible signaling protocol
  - Base-36 SHA-1 topic hash generation
  - Dynamic event kind calculation (strToNum + 20000)
  - Cross-platform JSON format compatibility
- **Nostr Integration**
  - Full Nostr client integration with proper API usage
  - Multi-relay support with fallback handling
  - Event filtering with 'x' tag compatibility
  - Fire-and-forget event publishing to prevent hangs
- **Room Management**
  - Basic room joining and presence announcements
  - Peer discovery via Nostr relay network
  - Event handler setup for peer join/leave/data
- **Testing & CI**
  - Comprehensive interoperability test suite
  - GitHub Actions CI with Swift ↔ Node.js validation
  - SwiftLint strict compliance
  - Relay connectivity resilience
- **Concurrency & Performance**
  - Async/await support throughout
  - Sendable compliance for Swift 6
  - Package dependencies and build configuration

### TODO 🚧
- Complete WebRTC data channel implementation
- ICE candidate exchange via Nostr
- Full peer-to-peer data transmission
- Connection state management
- Reconnection logic
- Error recovery mechanisms
- Enhanced unit test coverage

## Build Instructions

### Requirements
- iOS 17+ / macOS 14+
- Swift 6.0+
- Xcode with Swift Package Manager

### Dependencies
The package automatically fetches:
- WebRTC framework (binary)
- NostrClient Swift package
- Associated Nostr protocol libraries

### Testing
```bash
# Run Swift tests
swift test

# Run interoperability tests (Swift ↔ Node.js)
cd Tests/Interop
npm install
npm run test:interop

# Run CI pipeline locally
npm run test:protocol  # Verify protocol compatibility
```

### Known Limitations
- WebRTC data channels are scaffolded but not fully implemented
- ICE candidate exchange needs completion for full P2P data flow
- Currently supports peer discovery but not complete data transmission

## Testing Strategy
1. **Protocol Compatibility**: Hash generation and event kind validation
2. **Cross-Platform Interoperability**: Swift ↔ Node.js peer discovery via Nostr
3. **CI/CD Validation**: Automated testing with multiple Nostr relays
4. **Relay Resilience**: Graceful handling of relay connectivity issues
5. **Performance Testing**: Multi-peer scenarios and relay fallbacks

## Future Enhancements
- Support for different Nostr relay strategies
- Custom event kinds for specialized use cases
- Encryption layer for enhanced privacy
- Bandwidth optimization
- Room moderation features
- Persistent peer discovery