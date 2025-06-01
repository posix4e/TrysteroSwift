# TrysteroSwift Chat Example

A simple peer-to-peer chat application demonstrating TrysteroSwift's API.

## Running the Chat

### Swift Version

```bash
# Build and run
swift run TrysteroChat

# Or with custom settings
USER_NAME="Alice" CHAT_ROOM="my-room" swift run TrysteroChat
```

### JavaScript Version (for testing interoperability)

```bash
cd ../../Tests/Interop
npm install
node chat.js
```

## How It Works

This chat app demonstrates the core TrysteroSwift patterns:

### 1. Joining a Room

```swift
let config = Config(
    appId: "my-chat-app",
    relayUrls: ["wss://relay.damus.io", "wss://nos.lol"]
)
let room = Trystero.joinRoom(config, "room-name")
```

### 2. Creating Actions (Data Channels)

```swift
// Create a named action for sending/receiving data
let (sendMessage, onMessage) = room.makeAction("chat")

// Send data (broadcast to all)
sendMessage(["text": "Hello!"], nil)

// Send to specific peer
sendMessage(["text": "Hello!"], peerId)

// Receive data
onMessage { data, peerId in
    print("Got \(data) from \(peerId)")
}
```

### 3. Handling Peer Events

```swift
room.onPeerJoin { peerId in
    print("Peer joined: \(peerId)")
}

room.onPeerLeave { peerId in
    print("Peer left: \(peerId)")
}
```

### 4. Clean Shutdown

```swift
room.leave()
```

## Testing Interoperability

Run multiple instances to test P2P communication:

```bash
# Terminal 1 - Swift peer
USER_NAME="Alice" swift run TrysteroChat

# Terminal 2 - Another Swift peer
USER_NAME="Bob" swift run TrysteroChat

# Terminal 3 - JavaScript peer (if available)
USER_NAME="Charlie" node ../../Tests/Interop/chat.js
```

All peers will automatically discover each other and can exchange messages.

## Architecture Notes

- **Peer Discovery**: Via Nostr relay announcements
- **Connection**: Direct WebRTC data channels
- **Message Format**: JSON-encoded data
- **Room Isolation**: Only peers in same room connect

This example serves as both documentation and integration test for TrysteroSwift.