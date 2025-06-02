# TrysteroSwift API Documentation

Learn by example - each code snippet is a working demonstration of TrysteroSwift's features.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Core Concepts](#core-concepts)
3. [Actions (Data Channels)](#actions-data-channels)
4. [Peer Management](#peer-management)
5. [Advanced Usage](#advanced-usage)
6. [Error Handling](#error-handling)

## Getting Started

### Basic Room Connection

```swift
import TrysteroSwift

// Minimal configuration - uses default Nostr relays
let room = Trystero.joinRoom(Config(appId: "my-app"), "lobby")

// With custom relays
let config = Config(
    appId: "my-app",
    relayUrls: ["wss://relay.damus.io", "wss://nos.lol"],
    relayRedundancy: 2  // Use 2 relays for redundancy
)
let room = Trystero.joinRoom(config, "lobby")
```

### Clean Shutdown

```swift
// Always clean up when done
room.leave()
```

## Core Concepts

TrysteroSwift uses the same mental model as Trystero.js:

1. **Rooms** - Named spaces where peers meet
2. **Actions** - Named data channels for different data types
3. **Peer IDs** - Unique identifiers for each peer
4. **Events** - Notifications when peers join/leave

## Actions (Data Channels)

Actions are the primary way to send and receive data.

### Creating Actions

```swift
// Each action creates a dedicated data channel
let (sendChat, onChat) = room.makeAction("chat")
let (sendFile, onFile) = room.makeAction("file")
let (sendState, onState) = room.makeAction("gameState")
```

### Sending Data

```swift
// Broadcast to all peers
sendChat("Hello everyone!", nil)

// Send to specific peer
sendChat("Private message", peerId)

// Send complex data (automatically JSON encoded)
let gameMove = ["type": "move", "x": 10, "y": 20]
sendState(gameMove, nil)
```

### Receiving Data

```swift
// Simple strings
onChat { message, fromPeer in
    print("\(fromPeer): \(message)")
}

// Complex data
onState { data, fromPeer in
    if let move = data as? [String: Any],
       let x = move["x"] as? Int,
       let y = move["y"] as? Int {
        print("Player \(fromPeer) moved to \(x),\(y)")
    }
}
```

## Peer Management

### Peer Discovery

```swift
// Get current connected peers
let peers = room.getPeers()
print("Connected to \(peers.count) peers")

// React to peer changes
room.onPeerJoin { peerId in
    print("Welcome \(peerId)!")
    
    // Send initial state to new peer
    sendState(currentGameState, peerId)
}

room.onPeerLeave { peerId in
    print("\(peerId) disconnected")
    
    // Clean up peer-specific data
    playerStates.removeValue(forKey: peerId)
}
```

### Tracking Peers

```swift
// Example: Multiplayer game lobby
class GameLobby {
    let room: Room
    var players: [String: PlayerInfo] = [:]
    let (sendInfo, onInfo) = room.makeAction("playerInfo")
    
    init() {
        room = Trystero.joinRoom(Config(appId: "my-game"), "lobby")
        
        // Share our info when someone joins
        room.onPeerJoin { peerId in
            self.sendInfo(["name": "Player 1", "ready": false], peerId)
        }
        
        // Track other players
        onInfo { info, peerId in
            if let playerInfo = info as? [String: Any] {
                self.players[peerId] = PlayerInfo(from: playerInfo)
            }
        }
        
        // Remove disconnected players
        room.onPeerLeave { peerId in
            self.players.removeValue(forKey: peerId)
        }
    }
}
```

## Advanced Usage

### Multiple Rooms

```swift
// Users can be in multiple rooms simultaneously
let globalChat = Trystero.joinRoom(config, "global-chat")
let teamChat = Trystero.joinRoom(config, "team-blue")
let gameRoom = Trystero.joinRoom(config, "game-42")

// Each room is independent
let (sendGlobal, _) = globalChat.makeAction("message")
let (sendTeam, _) = teamChat.makeAction("message")

sendGlobal("Hello world!", nil)
sendTeam("Team only message", nil)
```

### Custom WebRTC Configuration

```swift
// Use TURN servers for better connectivity
let iceServers = [
    IceServer(urls: ["stun:stun.l.google.com:19302"]),
    IceServer(
        urls: ["turn:turn.example.com:3478"],
        username: "user",
        credential: "pass"
    )
]

let config = Config(
    appId: "my-app",
    rtcConfig: RTCConfiguration(iceServers: iceServers)
)
```

### Bandwidth Optimization

```swift
// For high-frequency updates (like game state)
let (sendPosition, onPosition) = room.makeAction("position")

// Throttle updates
var lastUpdate = Date()
func updatePosition(x: Double, y: Double) {
    let now = Date()
    if now.timeIntervalSince(lastUpdate) > 0.05 { // Max 20 updates/sec
        sendPosition(["x": x, "y": y], nil)
        lastUpdate = now
    }
}
```

## Error Handling

TrysteroSwift is designed to be resilient, but you should handle edge cases:

```swift
// Network failures are handled internally
// Peers may join/leave at any time

// Defensive programming for peer communication
room.onPeerJoin { peerId in
    // Don't assume peer will stay connected
    self.sendInitialState(to: peerId)
}

func sendToPeer(_ data: Any, _ peerId: String) {
    let peers = room.getPeers()
    if peers.contains(peerId) {
        sendData(data, peerId)
    } else {
        print("Peer \(peerId) is no longer connected")
    }
}

// Handle malformed data gracefully
onData { data, peerId in
    guard let message = data as? [String: Any],
          let type = message["type"] as? String else {
        print("Invalid message from \(peerId)")
        return
    }
    
    // Process valid message
}
```

## Real-World Examples

### 1. Collaborative Whiteboard

```swift
let (sendDraw, onDraw) = room.makeAction("draw")

// Send drawing commands
func userDrew(path: DrawPath) {
    sendDraw([
        "points": path.points.map { ["x": $0.x, "y": $0.y] },
        "color": path.color,
        "width": path.width
    ], nil)
}

// Render remote drawings
onDraw { data, peerId in
    if let drawData = data as? [String: Any] {
        let path = DrawPath(from: drawData)
        canvas.addPath(path, from: peerId)
    }
}
```

### 2. File Sharing

```swift
let (sendFile, onFile) = room.makeAction("file")

// Send file metadata first
func shareFile(_ file: Data, name: String) {
    let chunks = file.chunked(into: 16384) // 16KB chunks
    
    // Send metadata
    sendFile([
        "type": "start",
        "name": name,
        "size": file.count,
        "chunks": chunks.count
    ], nil)
    
    // Send chunks
    for (index, chunk) in chunks.enumerated() {
        sendFile([
            "type": "chunk",
            "name": name,
            "index": index,
            "data": chunk.base64EncodedString()
        ], nil)
    }
    
    // Send completion
    sendFile(["type": "complete", "name": name], nil)
}
```

### 3. Real-time Collaboration

```swift
// Document collaboration with operational transforms
let (sendOp, onOp) = room.makeAction("operation")

// Local change
func textChanged(operation: TextOperation) {
    // Apply locally
    document.apply(operation)
    
    // Broadcast to peers
    sendOp(operation.toJSON(), nil)
}

// Remote changes
onOp { data, peerId in
    if let op = TextOperation(from: data) {
        // Transform against local operations
        let transformed = document.transform(op)
        document.apply(transformed)
        textView.refresh()
    }
}
```

## Best Practices

1. **Use Named Actions** - Separate different data types into different actions
2. **Handle Disconnections** - Peers can leave at any time
3. **Validate Data** - Always validate data from peers
4. **Optimize Bandwidth** - Throttle high-frequency updates
5. **Test Interoperability** - Test with both Swift and JavaScript peers

---

This documentation demonstrates TrysteroSwift through practical examples. For a complete working example, see the [Chat Example](../Examples/Chat/).