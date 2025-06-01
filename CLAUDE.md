# TrysteroSwift Development Notes

## Overview
TrysteroSwift is a Swift implementation of Trystero.js, providing serverless WebRTC peer-to-peer communication using Nostr for signaling. The library is designed to be API-compatible with the JavaScript version.

## Architecture

### Core Design Principles
1. **API Compatibility** - Match Trystero.js API as closely as possible
2. **Simplicity** - Minimal abstraction layers
3. **Swift Conventions** - Use modern Swift patterns (async/await, Sendable)
4. **Bidirectional Communication** - Full interoperability with JavaScript peers

### Key Components

#### `Trystero.swift`
- Entry point matching `joinRoom()` from Trystero.js
- Configuration struct with same options as JS version

#### `Room.swift`
- Main room class with `makeAction()` method
- Event handlers: `onPeerJoin`, `onPeerLeave`, `onPeerStream`
- Manages peer connections and action routing

#### `Peer.swift`
- WebRTC peer connection management
- Implements "perfect negotiation" pattern
- Handles offer/answer exchange and ICE candidates
- Data channel creation and management

#### `NostrRelay.swift`
- Nostr protocol integration for signaling
- Uses ephemeral events (kind 29000)
- Room namespacing with hashtags
- Peer presence announcements

#### `WebRTCClient.swift`
- WebRTC factory singleton
- Async/await extensions for WebRTC APIs

## Trystero.js Compatibility

### API Mapping
```javascript
// Trystero.js
import {joinRoom} from 'trystero/nostr'
const room = joinRoom({appId: 'app'}, 'room')
const [send, get] = room.makeAction('chat')
```

```swift
// TrysteroSwift
let room = Trystero.joinRoom(Config(appId: "app"), "room")
let (send, get) = room.makeAction("chat")
```

### Key Differences
1. Swift uses tuples for action pairs vs JS array destructuring
2. Optional parameters use Swift optionals vs JS undefined
3. Callbacks use Swift closures vs JS functions
4. Data can be Any type, automatically serialized to JSON

## Testing Strategy

### Unit Tests
- Basic API functionality
- Configuration options
- Event handler registration

### Integration Tests
- JavaScript interoperability
- Peer discovery via Nostr
- Data exchange between Swift and JS peers
- Multiple action types

### Test Infrastructure
```
Tests/
├── TrysteroSwiftTests/     # Swift unit tests
├── Interop/                # JS compatibility tests
│   ├── trystero-node.js    # Node.js test harness
│   └── tests/              # Individual test scenarios
└── test-runner.js          # Test orchestration
```

## Implementation Status

### ✅ Completed
- Core room management
- Trystero.js compatible API
- WebRTC peer connections
- Nostr signaling
- Data channel communication
- Action system (makeAction)
- Peer event handling
- JavaScript interoperability

### 🚧 TODO
- Media stream support (audio/video)
- Binary data optimization
- Relay connection resilience
- Performance optimizations
- Additional Trystero strategies (IPFS, BitTorrent)

## Development Guidelines

### Adding Features
1. Check Trystero.js implementation first
2. Match the JavaScript API exactly
3. Test with both Swift and JS peers
4. Update compatibility tests

### Code Style
- Use modern Swift patterns
- Prefer clarity over cleverness
- Add inline documentation for WebRTC complexity
- Keep Trystero.js parity in mind

## Debugging

### Common Issues
1. **Peers don't connect**: Check relay connectivity
2. **Data not received**: Verify action names match
3. **WebRTC failures**: Check ICE server configuration
4. **Timing issues**: Nostr events are eventually consistent

### Debug Output
The library includes debug logging that can be enabled:
- Peer connection state changes
- Nostr event flow
- WebRTC signaling steps

## Future Enhancements
1. **Additional Strategies**: Support IPFS, BitTorrent, Firebase
2. **Performance**: Connection pooling, binary protocols
3. **Features**: File transfer, streaming, encryption
4. **Platforms**: Linux support, WASM compatibility