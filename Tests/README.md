# TrysteroSwift Tests

Simple, practical tests that verify TrysteroSwift works correctly.

## Structure

```
Tests/
├── TrysteroSwiftTests/
│   └── IntegrationTest.swift    # Basic Swift tests
└── Interop/
    ├── test.js                  # Minimal JS interop test
    └── chat.js                  # Interactive chat for manual testing
```

## Running Tests

### Swift Tests
```bash
# Run all tests
swift test

# Run specific test
swift test --filter testRoomLifecycle
```

### JavaScript Interoperability
```bash
cd Tests/Interop
npm install

# Automated test
npm test

# Interactive chat (manual testing)
npm run chat
```

### Full Integration Test

Run the chat example in multiple terminals:

```bash
# Terminal 1 - Swift
cd Examples/Chat
swift run TrysteroChat

# Terminal 2 - JavaScript  
cd Tests/Interop
npm run chat

# They will automatically discover each other and can exchange messages
```

## Philosophy

- **Practical over theoretical** - Test actual use cases, not abstractions
- **Examples as tests** - The chat app serves as both documentation and test
- **Minimal complexity** - Keep tests simple and understandable
- **Focus on interop** - The main goal is Swift <-> JavaScript compatibility

## CI Testing

The CI runs:
1. Basic Swift compilation and unit tests
2. Automated Swift <-> JavaScript message exchange
3. Verifies bidirectional communication works

This ensures TrysteroSwift remains compatible with Trystero.js.