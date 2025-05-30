# TrysteroSwift Interoperability Tests

This directory contains cross-platform interoperability tests that validate TrysteroSwift's compatibility with the original [Trystero.js](https://github.com/dmotz/trystero) library.

## Overview

The interop tests ensure that:
- TrysteroSwift can connect to rooms with Trystero.js peers
- Bidirectional message exchange works correctly
- WebRTC signaling is compatible between implementations
- Nostr relay communication follows the same protocol

## Test Components

### 1. Node.js Test Harness (`trystero-node.js`)
- Uses the official Trystero.js library
- Acts as a peer in the test room
- Responds to messages from Swift peers
- Implements ping-pong and echo functionality
- Provides status updates and graceful shutdown

### 2. Swift Interop Tests (`InteropTests.swift`)
- XCTest-based test suite
- Connects TrysteroSwift to the Node.js peer
- Tests various messaging scenarios
- Validates connection persistence and reconnection
- Measures performance and reliability

### 3. Test Runner Script (`run-interop-tests.sh`)
- Orchestrates both Node.js and Swift processes
- Handles dependency installation
- Manages process lifecycle
- Generates comprehensive test reports

## Prerequisites

- **Node.js** (v16+ recommended)
- **npm** (comes with Node.js)
- **Swift 6.0+**
- **Xcode** (for macOS/iOS development)
- **Internet connection** (for Nostr relays)

## Quick Start

1. **Run all tests automatically:**
   ```bash
   cd Tests/Interop
   ./run-interop-tests.sh
   ```

2. **Install dependencies manually:**
   ```bash
   cd Tests/Interop
   npm install
   ```

3. **Run Node.js harness only (for manual testing):**
   ```bash
   ./run-interop-tests.sh --node-only
   ```

4. **Run Swift tests only (assumes Node.js is running):**
   ```bash
   ./run-interop-tests.sh --swift-only
   ```

## Test Scenarios

### Basic Connection Test
- Swift peer joins room
- Node.js peer detects connection
- Welcome message exchange
- Connection stability verification

### Ping-Pong Test
- Swift sends ping message
- Node.js responds with pong
- Round-trip time measurement
- Message integrity verification

### Multiple Message Exchange
- Rapid message sending (5+ messages)
- Echo response validation
- Message ordering verification
- Performance benchmarking

### Direct Peer Messaging
- Targeted message sending
- Peer-specific communication
- Message routing verification

### Reconnection Test
- Graceful disconnection
- Room rejoining
- State restoration
- Message continuity

## Configuration

### Room Settings
- **Room ID:** `swift-interop-test`
- **App ID:** `trystero-swift-interop`
- **Relays:** 
  - `wss://relay.damus.io`
  - `wss://nos.lol`

### Message Format
Messages are exchanged as JSON strings with this structure:
```json
{
  "type": "message_type",
  "from": "sender_identifier", 
  "timestamp": "unix_timestamp",
  "message": "content"
}
```

## Troubleshooting

### Common Issues

**Node.js dependencies not installing:**
```bash
cd Tests/Interop
rm -rf node_modules package-lock.json
npm install
```

**Swift tests timing out:**
- Check internet connection
- Verify Nostr relays are accessible
- Increase timeout values in test code

**WebRTC connection failures:**
- Ensure firewall allows WebRTC traffic
- Try different network environment
- Check relay connectivity

**Tests fail intermittently:**
- Network latency issues
- Relay temporary unavailability
- Run tests multiple times to confirm

### Debug Mode

Enable verbose logging:
```bash
# Node.js side
DEBUG=trystero* node trystero-node.js

# Swift side - modify test timeouts and add logging
```

### Manual Testing

1. Start Node.js harness:
   ```bash
   cd Tests/Interop
   node trystero-node.js
   ```

2. In another terminal, run Swift tests:
   ```bash
   cd ../..
   swift test --filter InteropTests
   ```

## Test Reports

After running tests, check the generated report:
```bash
cat Tests/Interop/interop-test-report.txt
```

The report includes:
- Test execution summary
- Performance metrics
- Error details (if any)
- Environment information

## Contributing

When adding new interop tests:

1. Add test scenarios to `InteropTests.swift`
2. Update Node.js harness if needed
3. Document new test cases in this README
4. Ensure tests are deterministic and robust
5. Update timeout values appropriately

## Performance Benchmarks

Typical performance characteristics:
- **Connection establishment:** 2-5 seconds
- **Message round-trip:** 100-500ms
- **Reconnection time:** 3-8 seconds
- **Message throughput:** 10+ messages/second

## Related Documentation

- [Trystero.js Documentation](https://github.com/dmotz/trystero)
- [Nostr Protocol Specification](https://github.com/nostr-protocol/nips)
- [WebRTC Specifications](https://webrtc.org/getting-started/overview)