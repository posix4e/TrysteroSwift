#!/usr/bin/env node

// Minimal test harness for CI - verifies Swift <-> JS communication

import * as polyfill from 'node-datachannel/polyfill'
import {WebSocket} from 'ws'
import {joinRoom} from 'trystero/nostr'

// Apply polyfills globally
Object.assign(globalThis, polyfill)
globalThis.WebSocket = WebSocket

const roomId = process.env.INTEROP_ROOM_ID || 'swift-js-test'

console.log('🧪 JavaScript test peer starting...')
console.log(`📍 Room: ${roomId}`)
console.log('⏰ Time:', new Date().toISOString())

const relayUrlsEnv = process.env.TEST_RELAY_URL || 'wss://relay.nostr.band'
const relayUrls = relayUrlsEnv.split(',').map(url => url.trim())
console.log(`🔌 Using relays: ${relayUrls.join(', ')}`)
const room = joinRoom({
  appId: 'interop-test',
  relayUrls: relayUrls
}, roomId)

console.log('📡 JS: Room created, waiting for peers...')

const [sendTest, onTest] = room.makeAction('test')

let testPassed = false

room.onPeerJoin(peerId => {
  console.log(`✅ JS: Connected to peer ${peerId}`)
  sendTest({message: 'Hello from JavaScript!'}, peerId)
})

onTest((data, peerId) => {
  console.log(`📥 JS: Received from ${peerId}:`, data)
  if (data.message && data.message.includes('Swift')) {
    testPassed = true
    console.log('✅ JS: Swift message received - test passed!')

    // Give Swift time to receive our response
    setTimeout(() => {
      room.leave()
      process.exit(0)
    }, 1000)
  }
})

// Timeout after 70 seconds (longer than Swift's 60s timeout)
setTimeout(() => {
  if (!testPassed) {
    console.error('❌ JS: Timeout - no Swift peer connected')
    process.exit(1)
  }
}, 70000)

// Heartbeat every 10 seconds to show we're alive
let heartbeatCount = 0
setInterval(() => {
  heartbeatCount++
  console.log(`💓 JS: Heartbeat #${heartbeatCount} - still waiting...`)
}, 10000)

console.log('⏳ JS: Waiting for Swift peer...')