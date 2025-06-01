#!/usr/bin/env node

// Minimal test harness for CI - verifies Swift <-> JS communication

import {joinRoom} from 'trystero/nostr'
import {polyfill} from 'node-datachannel/polyfill'

polyfill()

const roomId = process.env.INTEROP_ROOM_ID || 'swift-js-test'

console.log('🧪 JavaScript test peer starting...')
console.log(`📍 Room: ${roomId}`)

const room = joinRoom({
    appId: 'interop-test',
    relayUrls: ['wss://relay.damus.io', 'wss://nos.lol']
}, roomId)

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

// Timeout after 30 seconds
setTimeout(() => {
    if (!testPassed) {
        console.error('❌ JS: Timeout - no Swift peer connected')
        process.exit(1)
    }
}, 30000)

console.log('⏳ JS: Waiting for Swift peer...')