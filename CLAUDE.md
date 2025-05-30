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
- Uses Nostr event kind `29000` (ephemeral events) for WebRTC signaling
- Room identification via hashtag: `trystero-{roomId}`
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
// Create and join a room
let room = try Trystero.joinRoom(config: RoomConfig(relays: ["wss://relay.damus.io"]), roomId: "my-room")
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
- Basic room management structure
- WebRTC peer connection handling
- Nostr client integration with proper API usage
- Data channel creation and messaging
- Async/await support throughout
- Sendable compliance for concurrency
- Package dependencies and build configuration

### TODO 🚧
- Complete WebRTC signaling implementation
- ICE candidate exchange via Nostr
- Peer presence announcements
- Event handler implementations
- Connection state management
- Reconnection logic
- Error recovery mechanisms
- Unit tests

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

### Known Issues
- WebRTC RTCSessionDescription concurrency warnings (resolved with manual copying)
- Nostr event filtering needs refinement for room isolation
- Missing ICE candidate handling implementation

## Testing Strategy
1. Unit tests for individual components
2. Integration tests for Nostr + WebRTC flow  
3. Multi-device testing for P2P scenarios
4. Relay compatibility testing
5. Performance testing with multiple peers

## Future Enhancements
- Support for different Nostr relay strategies
- Custom event kinds for specialized use cases
- Encryption layer for enhanced privacy
- Bandwidth optimization
- Room moderation features
- Persistent peer discovery