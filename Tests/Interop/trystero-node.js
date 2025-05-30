#!/usr/bin/env node

import { joinRoom } from 'trystero'

const ROOM_ID = 'swift-interop-test'
const RELAY_URLS = ['wss://relay.damus.io', 'wss://nos.lol']

console.log('🟢 Starting Trystero Node.js test harness...')
console.log(`📡 Connecting to relays: ${RELAY_URLS.join(', ')}`)
console.log(`🏠 Room ID: ${ROOM_ID}`)

// Create room configuration
const roomConfig = {
  appId: 'trystero-swift-interop',
  relays: RELAY_URLS
}

// Join the room
const room = joinRoom(roomConfig, ROOM_ID)

// Track connected peers
const peers = new Set()
let messageCount = 0

// Event handlers
room.onPeerJoin(peerId => {
  console.log(`✅ Peer joined: ${peerId}`)
  peers.add(peerId)
  
  // Send welcome message
  const welcomeMessage = {
    type: 'welcome',
    from: 'trystero-node',
    timestamp: Date.now(),
    message: `Hello from Node.js! You are peer ${peers.size}`
  }
  
  room.send(JSON.stringify(welcomeMessage), peerId)
  console.log(`📤 Sent welcome message to ${peerId}`)
})

room.onPeerLeave(peerId => {
  console.log(`❌ Peer left: ${peerId}`)
  peers.delete(peerId)
})

room.onData((data, peerId) => {
  messageCount++
  try {
    const message = JSON.parse(data)
    console.log(`📥 Message ${messageCount} from ${peerId}:`, message)
    
    // Echo back a response
    const response = {
      type: 'echo',
      from: 'trystero-node',
      timestamp: Date.now(),
      originalMessage: message,
      messageNumber: messageCount
    }
    
    room.send(JSON.stringify(response), peerId)
    console.log(`📤 Sent echo response to ${peerId}`)
    
    // If this is a ping, send a pong
    if (message.type === 'ping') {
      setTimeout(() => {
        const pong = {
          type: 'pong',
          from: 'trystero-node',
          timestamp: Date.now(),
          pingTimestamp: message.timestamp
        }
        room.send(JSON.stringify(pong), peerId)
        console.log(`🏓 Sent pong to ${peerId}`)
      }, 100)
    }
    
  } catch (error) {
    console.log(`📥 Raw data from ${peerId}: ${data}`)
    
    // Send simple echo for non-JSON data
    const response = `Echo from Node.js: ${data}`
    room.send(response, peerId)
    console.log(`📤 Sent simple echo to ${peerId}`)
  }
})

// Send periodic status updates
setInterval(() => {
  if (peers.size > 0) {
    const status = {
      type: 'status',
      from: 'trystero-node',
      timestamp: Date.now(),
      connectedPeers: peers.size,
      messagesReceived: messageCount,
      uptime: process.uptime()
    }
    
    room.send(JSON.stringify(status))
    console.log(`📊 Broadcast status update to ${peers.size} peers`)
  }
}, 10000) // Every 10 seconds

// Handle process cleanup
process.on('SIGINT', async () => {
  console.log('\n🛑 Shutting down Node.js test harness...')
  
  if (peers.size > 0) {
    const goodbye = {
      type: 'goodbye',
      from: 'trystero-node',
      timestamp: Date.now(),
      message: 'Node.js peer is shutting down'
    }
    
    room.send(JSON.stringify(goodbye))
    console.log('👋 Sent goodbye message to all peers')
  }
  
  // Give time for message to send
  setTimeout(() => {
    process.exit(0)
  }, 1000)
})

console.log('🚀 Node.js test harness is ready and waiting for Swift peers...')
console.log('💡 Send SIGINT (Ctrl+C) to gracefully shutdown')