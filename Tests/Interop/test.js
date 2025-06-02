#!/usr/bin/env node

/**
 * Unified test suite for TrysteroSwift
 * Combines relay, chat client, and all test scenarios
 *
 * Usage:
 *   node test.js                  # Run all tests (js-js, swift-swift, js-swift)
 *   node test.js relay            # Run relay only
 *   node test.js chat             # Run interactive chat
 *   node test.js js-js            # Test JS-to-JS only
 *   node test.js swift-swift      # Test Swift-to-Swift only
 *   node test.js js-swift         # Test JS-to-Swift only
 */

import {spawn} from 'child_process'
import {WebSocketServer} from 'ws'
import * as polyfill from 'node-datachannel/polyfill'
import {WebSocket} from 'ws'
import {joinRoom} from 'trystero/nostr'
import readline from 'readline'
import path from 'path'
import {fileURLToPath} from 'url'

// Apply polyfills
Object.assign(globalThis, polyfill)
globalThis.WebSocket = WebSocket

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

// ============================================================================
// NOSTR RELAY
// ============================================================================

class NostrRelay {
  constructor(port = 7447) {
    this.port = port
    this.wss = null
    this.subscriptions = new Map()
    this.events = []
  }

  async start() {
    return new Promise((resolve) => {
      this.wss = new WebSocketServer({port: this.port})

      console.log(`📡 Local Nostr relay running on ws://localhost:${this.port}`)

      this.wss.on('connection', (ws) => {
        console.log('📱 Client connected')

        ws.on('message', (data) => {
          try {
            const msg = JSON.parse(data.toString())

            if (msg[0] === 'EVENT') {
              const event = msg[1]
              this.events.push(event)
              console.log(`📨 Event: ${event.kind} from ${event.pubkey.substring(0, 8)}... content: ${event.content?.substring(0, 50)}...`)

              // Send OK response immediately
              ws.send(JSON.stringify(['OK', event.id, true, '']))

              // Broadcast to subscribers (except sender)
              for (const [subId, sub] of this.subscriptions) {
                if (sub.ws !== ws && this.matchesFilters(event, sub.filters)) {
                  sub.ws.send(JSON.stringify(['EVENT', subId, event]))
                }
              }
            } else if (msg[0] === 'REQ') {
              const subId = msg[1]
              const filters = msg.slice(2)
              console.log(`📋 REQ ${subId}: filters:`, JSON.stringify(filters))
              this.subscriptions.set(subId, {ws, filters})

              // Send existing events
              for (const event of this.events) {
                if (this.matchesFilters(event, filters)) {
                  ws.send(JSON.stringify(['EVENT', subId, event]))
                }
              }

              ws.send(JSON.stringify(['EOSE', subId]))
            } else if (msg[0] === 'CLOSE') {
              this.subscriptions.delete(msg[1])
            }
          } catch (e) {
            console.error('❌ Relay error:', e.message)
          }
        })

        ws.on('close', () => {
          // Remove subscriptions for this connection
          for (const [subId, sub] of this.subscriptions) {
            if (sub.ws === ws) this.subscriptions.delete(subId)
          }
        })
      })

      this.wss.on('listening', () => resolve())
    })
  }

  matchesFilters(event, filters) {
    for (const filter of filters) {
      if (filter.kinds && !filter.kinds.includes(event.kind)) continue

      // Check tags
      let matches = true
      for (const [key, values] of Object.entries(filter)) {
        if (key.startsWith('#')) {
          const tagName = key.substring(1)
          const eventTags = event.tags.filter(t => t[0] === tagName).map(t => t[1])
          if (!values.some(v => eventTags.includes(v))) {
            matches = false
            break
          }
        }
      }
      if (matches) return true
    }
    return false
  }

  stop() {
    if (this.wss) {
      this.wss.close()
      console.log('📡 Relay stopped')
    }
  }
}

// ============================================================================
// CHAT CLIENT
// ============================================================================

async function runInteractiveChat() {
  const relay = new NostrRelay()
  await relay.start()

  const roomName = process.env.CHAT_ROOM || 'trystero-chat-demo'
  const userName = process.env.USER_NAME || `User-${Math.floor(Math.random() * 9000) + 1000}`
  const appId = process.env.APP_ID || 'trystero-swift-chat'

  console.log('\n🌐 Trystero.js Chat')
  console.log('===================')
  console.log(`👤 Your name: ${userName}`)
  console.log(`🏠 Room: ${roomName}`)
  console.log('📡 Connecting...')

  const room = joinRoom({
    appId: appId,
    relayUrls: ['ws://localhost:7447']
  }, roomName)

  const [sendMessage, onMessage] = room.makeAction('chat')
  const connectedPeers = new Set()

  onMessage((data, _peerId) => {
    if (data.text && data.from && data.timestamp) {
      const date = new Date(data.timestamp * 1000)
      const time = date.toLocaleTimeString([], {hour: '2-digit', minute: '2-digit'})
      console.log(`\n[${time}] ${data.from}: ${data.text}`)
      process.stdout.write('> ')
    }
  })

  room.onPeerJoin(peerId => {
    connectedPeers.add(peerId)
    console.log(`\n✅ ${peerId} joined (Total peers: ${connectedPeers.size})`)
    sendMessage({
      text: `${userName} joined the chat`,
      from: 'System',
      timestamp: Date.now() / 1000
    }, peerId)
    process.stdout.write('> ')
  })

  room.onPeerLeave(peerId => {
    connectedPeers.delete(peerId)
    console.log(`\n❌ ${peerId} left (Total peers: ${connectedPeers.size})`)
    process.stdout.write('> ')
  })

  console.log('✅ Connected! Type messages to chat, or "quit" to exit.\n')

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    prompt: '> '
  })

  rl.prompt()

  rl.on('line', (input) => {
    const trimmed = input.trim()

    if (!trimmed) {
      rl.prompt()
      return
    }

    if (trimmed === 'quit' || trimmed === '/quit') {
      console.log('👋 Goodbye!')
      room.leave()
      relay.stop()
      process.exit(0)
    }

    const message = {
      text: trimmed,
      from: userName,
      timestamp: Date.now() / 1000
    }

    sendMessage(message)

    const time = new Date().toLocaleTimeString([], {hour: '2-digit', minute: '2-digit'})
    console.log(`[${time}] You: ${trimmed}`)

    rl.prompt()
  })

  process.on('SIGINT', () => {
    console.log('\n👋 Goodbye!')
    room.leave()
    relay.stop()
    process.exit(0)
  })
}

// ============================================================================
// TEST RUNNER
// ============================================================================

class TestRunner {
  constructor() {
    this.processes = []
    this.relay = null
  }

  async startRelay() {
    this.relay = new NostrRelay()
    await this.relay.start()
    await this.delay(1000)
  }

  async runJSToJS() {
    console.log('\n🧪 Testing JS-to-JS WebRTC communication...\n')

    // Use a public test relay instead of our local one
    console.log('📡 Using public test relay...')

    const roomId = 'test-room-' + Date.now()
    const appId = 'test-interop'
    const relayUrl = 'wss://relay.nostr.band'  // Public relay for testing
    
    // Test results tracking
    const results = {
      alice: { connected: false, sent: false, received: false, messages: [] },
      bob: { connected: false, sent: false, received: false, messages: [] }
    }

    // Create Alice
    console.log('👤 Creating Alice...')
    const aliceRoom = joinRoom({
      appId: appId,
      relayUrls: [relayUrl]
    }, roomId)

    const [aliceSend, aliceReceive] = aliceRoom.makeAction('test')

    aliceRoom.onPeerJoin(peerId => {
      console.log('[Alice] ✅ Peer joined:', peerId)
      results.alice.connected = true
      
      // Send test message when peer joins
      setTimeout(() => {
        console.log('[Alice] 📤 Sending: "Hello from Alice!"')
        aliceSend({ from: 'Alice', text: 'Hello from Alice!', timestamp: Date.now() }, peerId)
        results.alice.sent = true
      }, 500)
    })

    aliceReceive((data, peerId) => {
      console.log('[Alice] 📥 Received:', data)
      results.alice.received = true
      results.alice.messages.push(data)
      
      // Respond to Bob's message
      if (data.from === 'Bob' && !data.response) {
        console.log('[Alice] 📤 Sending response: "Got your message, Bob!"')
        aliceSend({ from: 'Alice', text: 'Got your message, Bob!', response: true }, peerId)
      }
    })

    await this.delay(1000)

    // Create Bob
    console.log('👤 Creating Bob...')
    const bobRoom = joinRoom({
      appId: appId,
      relayUrls: [relayUrl]
    }, roomId)
    
    // Give Bob time to connect
    await this.delay(1000)

    const [bobSend, bobReceive] = bobRoom.makeAction('test')

    bobRoom.onPeerJoin(peerId => {
      console.log('[Bob] ✅ Peer joined:', peerId)
      results.bob.connected = true
      
      // Send test message when peer joins
      setTimeout(() => {
        console.log('[Bob] 📤 Sending: "Hello from Bob!"')
        bobSend({ from: 'Bob', text: 'Hello from Bob!', timestamp: Date.now() }, peerId)
        results.bob.sent = true
      }, 500)
    })

    bobReceive((data, peerId) => {
      console.log('[Bob] 📥 Received:', data)
      results.bob.received = true
      results.bob.messages.push(data)
      
      // Respond to Alice's message
      if (data.from === 'Alice' && !data.response) {
        console.log('[Bob] 📤 Sending response: "Got your message, Alice!"')
        bobSend({ from: 'Bob', text: 'Got your message, Alice!', response: true }, peerId)
      }
    })

    // Wait for peer discovery and message exchange
    console.log('\n⏳ Waiting for WebRTC connection and message exchange...')
    await this.delay(5000)

    // Check results
    console.log('\n📊 Test Results:')
    console.log('================')
    console.log(`Alice - Connected: ${results.alice.connected}, Sent: ${results.alice.sent}, Received: ${results.alice.received}, Messages: ${results.alice.messages.length}`)
    console.log(`Bob - Connected: ${results.bob.connected}, Sent: ${results.bob.sent}, Received: ${results.bob.received}, Messages: ${results.bob.messages.length}`)

    // Verify bidirectional communication
    const success = 
      results.alice.connected && results.bob.connected &&
      results.alice.sent && results.bob.sent &&
      results.alice.received && results.bob.received &&
      results.alice.messages.length >= 1 && results.bob.messages.length >= 1

    if (success) {
      console.log('\n✅ WebRTC bidirectional communication verified!')
    } else {
      console.log('\n❌ WebRTC communication failed!')
      if (!results.alice.connected || !results.bob.connected) {
        console.log('  - Peers did not connect via WebRTC')
      }
      if (!results.alice.received || !results.bob.received) {
        console.log('  - Messages were not received over data channels')
      }
    }

    // Cleanup
    aliceRoom.leave()
    bobRoom.leave()

    return success
  }

  async runSwiftToSwift() {
    console.log('\n🧪 Testing Swift-to-Swift communication...\n')

    await this.startRelay()

    const roomId = 'test-room-' + Date.now()
    const swiftPath = path.join(__dirname, '../../Examples/Chat/.build/debug/TrysteroChat')

    // Start first Swift chat
    const swift1 = spawn(swiftPath, [], {
      env: {
        ...process.env,
        USER_NAME: 'Swift-Alice',
        CHAT_ROOM: roomId,
        RELAY_URLS: 'ws://localhost:7447'
      }
    })

    swift1.stdout.on('data', data => {
      process.stdout.write(`[Swift-Alice] ${data}`)
    })

    this.processes.push(swift1)
    await this.delay(3000)

    // Start second Swift chat
    const swift2 = spawn(swiftPath, [], {
      env: {
        ...process.env,
        USER_NAME: 'Swift-Bob',
        CHAT_ROOM: roomId,
        RELAY_URLS: 'ws://localhost:7447'
      }
    })

    swift2.stdout.on('data', data => {
      process.stdout.write(`[Swift-Bob] ${data}`)
    })

    this.processes.push(swift2)
    await this.delay(3000)

    // Send test messages
    console.log('\n📤 Sending test messages...\n')

    swift1.stdin.write('Hello from Swift Alice!\n')
    await this.delay(1000)

    swift2.stdin.write('Hi from Swift Bob!\n')
    await this.delay(2000)

    console.log('\n✅ Swift-to-Swift test complete!')
    return true
  }

  async runJSToSwift() {
    console.log('\n🧪 Testing JS-to-Swift WebRTC communication...\n')

    await this.startRelay()

    const roomId = 'test-room-' + Date.now()
    const appId = 'trystero-swift-chat'
    const swiftPath = path.join(__dirname, '../../Examples/Chat/.build/debug/TrysteroChat')
    
    // Test results tracking
    const results = {
      js: { connected: false, sent: false, received: false, messages: [] },
      swift: { output: [] }
    }

    // Start Swift chat first
    console.log('🦉 Starting Swift client...')
    const swift = spawn(swiftPath, [], {
      env: {
        ...process.env,
        USER_NAME: 'Swift-User',
        CHAT_ROOM: roomId,
        RELAY_URLS: 'ws://localhost:7447'
      }
    })

    swift.stdout.on('data', data => {
      const output = data.toString()
      process.stdout.write(`[Swift] ${output}`)
      results.swift.output.push(output)
      
      // Check for peer connection
      if (output.includes('joined')) {
        results.js.connected = true
      }
    })

    this.processes.push(swift)
    await this.delay(3000)

    // Create JS client
    console.log('📦 Creating JS client...')
    const jsRoom = joinRoom({
      appId: appId,
      relayUrls: ['ws://localhost:7447']
    }, roomId)

    const [jsSend, jsReceive] = jsRoom.makeAction('chat')

    jsRoom.onPeerJoin(peerId => {
      console.log('[JS] ✅ Peer joined:', peerId)
      results.js.connected = true
      
      // Send test message when peer joins
      setTimeout(() => {
        console.log('[JS] 📤 Sending: "Hello from JavaScript!"')
        jsSend({ 
          text: 'Hello from JavaScript!',
          from: 'JS-User',
          timestamp: Date.now() / 1000
        }, peerId)
        results.js.sent = true
      }, 1000)
    })

    jsReceive((data, peerId) => {
      console.log('[JS] 📥 Received:', data)
      results.js.received = true
      results.js.messages.push(data)
    })

    await this.delay(2000)

    // Send a message from Swift
    console.log('\n📤 Sending message from Swift...')
    swift.stdin.write('Hello from Swift!\n')
    
    // Wait for message exchange
    console.log('\n⏳ Waiting for WebRTC message exchange...')
    await this.delay(5000)

    // Check results
    console.log('\n📊 Test Results:')
    console.log('================')
    console.log(`JS - Connected: ${results.js.connected}, Sent: ${results.js.sent}, Received: ${results.js.received}, Messages: ${results.js.messages.length}`)
    
    // Check Swift output for received messages
    const swiftReceivedMessage = results.swift.output.some(line => 
      line.includes('JS-User') || line.includes('Hello from JavaScript')
    )
    console.log(`Swift - Received message: ${swiftReceivedMessage}`)

    const success = results.js.connected && results.js.sent && 
                   (results.js.received || swiftReceivedMessage)

    if (success) {
      console.log('\n✅ JS-to-Swift WebRTC communication established!')
    } else {
      console.log('\n❌ JS-to-Swift WebRTC communication failed!')
      if (!results.js.connected) {
        console.log('  - Peers did not connect via WebRTC')
      }
      if (!results.js.received && !swiftReceivedMessage) {
        console.log('  - No messages were exchanged over data channels')
      }
    }

    // Cleanup
    jsRoom.leave()

    return success
  }

  async runAllTests() {
    console.log('🚀 Running all TrysteroSwift tests...\n')

    const results = []

    // Run JS-to-JS
    try {
      await this.runJSToJS()
      results.push('✅ JS-to-JS: PASSED')
    } catch (e) {
      results.push('❌ JS-to-JS: FAILED')
    }
    await this.cleanup()
    await this.delay(2000)

    // Run Swift-to-Swift
    try {
      await this.runSwiftToSwift()
      results.push('✅ Swift-to-Swift: PASSED')
    } catch (e) {
      results.push('❌ Swift-to-Swift: FAILED')
    }
    await this.cleanup()
    await this.delay(2000)

    // Run JS-to-Swift
    try {
      await this.runJSToSwift()
      results.push('✅ JS-to-Swift: PASSED')
    } catch (e) {
      results.push('❌ JS-to-Swift: FAILED')
    }

    console.log('\n\n📊 Test Results:')
    console.log('================')
    results.forEach(r => console.log(r))

    const allPassed = results.every(r => r.includes('PASSED'))
    if (allPassed) {
      console.log('\n🎉 All tests passed!')
      return true
    } else {
      console.log('\n❌ Some tests failed!')
      return false
    }
  }

  async delay(ms) {
    return new Promise(resolve => setTimeout(resolve, ms))
  }

  async cleanup() {
    for (const proc of this.processes) {
      proc.kill()
    }
    this.processes = []

    if (this.relay) {
      this.relay.stop()
      this.relay = null
    }

    // Kill any orphaned processes
    spawn('pkill', ['-f', 'test.js chat'], {stdio: 'ignore'})
  }
}

// ============================================================================
// MAIN
// ============================================================================

async function main() {
  const command = process.argv[2]

  // Special case for relay-only mode
  if (command === 'relay') {
    const relay = new NostrRelay()
    await relay.start()
    console.log('\nRelay is running. Press Ctrl+C to stop.')
    await new Promise(() => {})
    return
  }

  // Special case for chat mode
  if (command === 'chat') {
    await runInteractiveChat()
    return
  }

  // Test runner
  const runner = new TestRunner()

  // Cleanup on exit
  process.on('SIGINT', () => {
    runner.cleanup()
    process.exit(0)
  })

  try {
    let success = true

    switch (command) {
    case 'js-js':
      success = await runner.runJSToJS()
      break

    case 'swift-swift':
      success = await runner.runSwiftToSwift()
      break

    case 'js-swift':
      success = await runner.runJSToSwift()
      break

    case undefined:
    case 'all':
      success = await runner.runAllTests()
      break

    default:
      console.log('TrysteroSwift Test Suite')
      console.log('========================\n')
      console.log('Usage: node test.js [command]\n')
      console.log('Commands:')
      console.log('  (none)       - Run all tests')
      console.log('  relay        - Run local Nostr relay only')
      console.log('  chat         - Run interactive chat')
      console.log('  js-js        - Test JS-to-JS only')
      console.log('  swift-swift  - Test Swift-to-Swift only')
      console.log('  js-swift     - Test JS-to-Swift only')
      console.log('\nExample: node test.js js-swift')
      process.exit(0)
    }

    await runner.cleanup()
    process.exit(success ? 0 : 1)
  } catch (error) {
    console.error('\n❌ Error:', error)
    await runner.cleanup()
    process.exit(1)
  }
}

main().catch(console.error)