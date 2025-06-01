# Chrome ↔ iOS Interoperability Tests

This directory contains comprehensive tests for validating real-time peer-to-peer communication between Trystero.js (Chrome) and TrysteroSwift (iOS), with support for both manual testing and automated CI/CD execution.

## 🎯 Test Objectives

- **Cross-Platform Compatibility**: Verify TrysteroSwift works seamlessly with Trystero.js
- **Real-Time Communication**: Test bidirectional data exchange
- **Protocol Compliance**: Ensure Nostr and WebRTC protocols are compatible
- **Performance Validation**: Test large data transfers and rapid message sequences
- **Connection Reliability**: Verify peer discovery and connection establishment
- **CI/CD Integration**: Automated testing in GitHub Actions environment

## 🛠️ Test Setup

### Test Modes

1. **Automated Mode** (CI/CD): Headless Chrome automation with coordinated Swift tests
2. **Manual Mode** (Development): Interactive Chrome browser with manual Swift test execution

### Prerequisites

1. **Node.js 18+**: For Chrome automation and Trystero.js
2. **Swift 6.0+**: For iOS test execution
3. **Chrome/Chromium**: Browser or headless automation
4. **Network Access**: Both environments must reach Nostr relays

## 🤖 Automated Testing (CI/CD)

### Quick Start

```bash
# Install dependencies
cd Tests/Interop
npm install

# Run automated tests
./run-ci-test.sh
```

### What Happens

1. **Chrome Automation**: Puppeteer launches headless Chrome with Trystero.js
2. **Coordination**: Chrome waits for iOS peer connection
3. **Swift Execution**: iOS test connects and exchanges messages  
4. **Validation**: Both sides validate message delivery and timing
5. **Reporting**: JSON report generated for CI consumption

### GitHub Actions Integration

The automated tests run in CI via:

```yaml
- name: Run Automated Interoperability Tests
  run: Tests/Interop/run-ci-test.sh
```

Results are uploaded as artifacts and success/failure determines CI status.

## 🖱️ Manual Testing (Development)

### Step 1: Prepare Chrome Environment

1. Open Chrome browser
2. Navigate to `Tests/Interop/chrome-ios-test.html`
3. Wait for "Chrome peer ready" status
4. Note the Chrome peer ID displayed

### Step 2: Run iOS Tests

```bash
# Manual comprehensive test
swift test --filter ChromeInteropTests

# Automated CI-style test  
swift test --filter AutomatedInteropTests
```

### Step 3: Monitor Test Progress

The test will automatically:
1. **Connect** iOS and Chrome peers
2. **Exchange** messages in both directions  
3. **Validate** message delivery and acknowledgments
4. **Test** large data transfers
5. **Perform** ping-pong exchanges

## 📋 Test Phases

### Phase 1: Connection Establishment
- iOS joins room with same config as Chrome
- Waits for Chrome peer discovery
- Establishes WebRTC data channel

### Phase 2: iOS → Chrome Messages
- Sends 4 test messages from iOS to Chrome
- Waits for acknowledgments
- Validates message delivery

### Phase 3: Chrome → iOS Messages  
- Requests Chrome to send test messages
- Receives and validates 4 messages from Chrome
- Confirms bidirectional communication

### Phase 4: Bidirectional Exchange
- Performs 5 rounds of ping-pong
- Tests real-time communication patterns
- Validates timing and sequence

### Phase 5: Large Data Transfer
- Sends 10KB message from iOS to Chrome
- Tests WebRTC data channel limits
- Validates large message handling

## 🔧 Test Configuration

Both tests use identical configuration:

```javascript
// Shared Configuration
const CONFIG = {
    roomId: 'chrome-ios-interop-test',
    appId: 'trystero-interop',
    relays: ['wss://relay.damus.io', 'wss://nos.lol']
};
```

## 📊 Expected Results

### Success Criteria
- ✅ **Connection**: Both peers discover each other within 30 seconds
- ✅ **Messages**: 100% message delivery in both directions
- ✅ **Acknowledgments**: All messages acknowledged within 5 seconds
- ✅ **Ping-Pong**: 5/5 successful round-trips
- ✅ **Large Data**: 10KB transfer successful

### Sample Output

```
🧪 Starting Chrome ↔ iOS interoperability test suite
📱 iOS Test Environment Ready

🔗 Phase 1: Testing connection establishment...
📱 iOS joining room: chrome-ios-interop-test
🔑 iOS peer ID: 8f2923bdc8f0a58bdb89145fec583b402c65cca68adac60b725050339eef4072
👋 Chrome peer joined: abc12345...
✅ Connection established with peer: abc12345678901234567890123456789012345678

📤 Phase 2: Testing iOS → Chrome messages...
  📤 Sending message 1: Hello from iOS!
  ✅ Message 1 acknowledged by Chrome
  📤 Sending message 2: Testing iOS → Chrome communication
  ✅ Message 2 acknowledged by Chrome
  📤 Sending message 3: Message with special chars: 🚀 📱 💻
  ✅ Message 3 acknowledged by Chrome
  📤 Sending message 4: JSON test: {"from":"iOS","test":true}
  ✅ Message 4 acknowledged by Chrome

📥 Phase 3: Testing Chrome → iOS messages...
  📤 Requesting Chrome to send test messages...
  ⏳ Waiting for 4 messages from Chrome...
  📥 Received from Chrome (chrome_to_ios): Hello from Chrome!
  📥 Received from Chrome (chrome_to_ios): Testing Chrome → iOS communication
  📥 Received from Chrome (chrome_to_ios): Message with emojis: 🌐 💻 📱
  📥 Received from Chrome (chrome_to_ios): JSON response: {"from":"Chrome","browser":"Chrome","success":true}
  ✅ Successfully received all messages from Chrome

🔄 Phase 4: Testing bidirectional message exchange...
  🏓 Starting ping-pong exchange (5 rounds)...
    📤 Ping 1: Sending to Chrome...
    📥 Pong 1: Received from Chrome ✅
    📤 Ping 2: Sending to Chrome...
    📥 Pong 2: Received from Chrome ✅
    📤 Ping 3: Sending to Chrome...
    📥 Pong 3: Received from Chrome ✅
    📤 Ping 4: Sending to Chrome...
    📥 Pong 4: Received from Chrome ✅
    📤 Ping 5: Sending to Chrome...
    📥 Pong 5: Received from Chrome ✅

📦 Phase 5: Testing large data transfer...
  📤 Sending large data (10400 chars)...
  ✅ Large data transfer successful

🎉 Chrome ↔ iOS interoperability test completed!

📊 Test Results Summary:
   ✅ Connection Establishment: Connected to 1 peer(s) (2.34s)
   ✅ iOS → Chrome Messages: 4/4 messages acknowledged (4.12s)
   ✅ Chrome → iOS Messages: 4/4 messages received (3.87s)
   ✅ Bidirectional Exchange: 5/5 ping-pong rounds completed (6.23s)
   ✅ Large Data Transfer: 10KB data transferred successfully (1.45s)
📈 Overall: 5/5 tests passed
```

## 🐛 Troubleshooting

### Common Issues

**No Chrome peer connected**
- Ensure Chrome page is open and shows "Chrome peer ready"
- Check that both devices can reach Nostr relays
- Verify same room ID and app ID configuration

**Message delivery failures**
- Check WebRTC connection status in Chrome DevTools
- Verify Nostr relay connectivity
- Ensure consistent Trystero protocol implementation

**Timeout errors**
- Increase timeout values for slower networks
- Check relay responsiveness
- Verify peer discovery is working

### Debug Tools

**Chrome DevTools Console:**
```javascript
// Check connection status
window.testAPI.connectedPeers

// View received messages  
window.testAPI.receivedMessages

// Send manual test message
window.testAPI.sendMessage({
    type: 'debug',
    content: 'Debug message',
    messageId: 'debug_' + Date.now()
});
```

**iOS Debug Output:**
- Enable debug logging in TrysteroSwift
- Monitor Nostr event subscriptions
- Check WebRTC connection states

## 🎯 Extending Tests

### Adding New Test Cases

1. **Create new test phase** in `ChromeInteropTests.swift`
2. **Add corresponding handler** in `chrome-ios-test.html`
3. **Update test results tracking** in both files
4. **Document expected behavior** in this README

### Custom Test Scenarios

```swift
// Example: Custom test phase
private func testCustomScenario() async throws {
    let startTime = Date()
    print("\n🔬 Phase X: Testing custom scenario...")
    
    // Your test logic here
    
    let duration = Date().timeIntervalSince(startTime)
    let success = /* your success condition */
    testResults.append(TestResult(
        testName: "Custom Scenario",
        success: success,
        details: "Custom test details",
        duration: duration
    ))
}
```

## 📈 Performance Metrics

The tests collect detailed performance metrics:

- **Connection Time**: Time to establish peer connection
- **Message Latency**: Round-trip time for acknowledgments  
- **Throughput**: Large data transfer rates
- **Reliability**: Success rates across multiple runs

These metrics help validate that TrysteroSwift meets performance requirements for real-world applications.