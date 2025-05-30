#!/usr/bin/env node
import WebSocket from 'ws'
import {joinRoom} from 'trystero'
import {RTCPeerConnection} from 'node-datachannel/polyfill'

// Set up WebSocket polyfill for Node.js environment
global.WebSocket = WebSocket

const ROOM_ID = 'swift-interop-test'
const RELAY_URLS = ['wss://relay.damus.io', 'wss://nos.lol']

console.log('🟢 Starting Trystero Node.js test harness...')
console.log(`📡 Connecting to relays: ${RELAY_URLS.join(', ')}`)
console.log(`🏠 Room ID: ${ROOM_ID}`)

// Create room configuration (using minimal appId to match Swift default behavior)
const roomConfig = {
  appId: '',  // Empty string - matches Swift's likely default
  rtcPolyfill: RTCPeerConnection,
  relays: RELAY_URLS
}

console.log('📋 Room configuration:', JSON.stringify(roomConfig, null, 2))

// Join the room
const room = joinRoom(roomConfig, ROOM_ID)
console.log('🏠 Joined room successfully')

// Track connected peers
const peers = new Set()
let messageCount = 0

// Send periodic presence announcements
setInterval(() => {
  console.log(`📊 Node.js Status: ${peers.size} peers connected, ${messageCount} messages received`)
}, 5000)

// Set up data channel
const [sendData, getData] = room.makeAction('data')

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
  
  sendData(JSON.stringify(welcomeMessage), peerId)
  console.log(`📤 Sent welcome message to ${peerId}`)
})

room.onPeerLeave(peerId => {
  console.log(`❌ Peer left: ${peerId}`)
  peers.delete(peerId)
})

getData((data, peerId) => {
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
    
    sendData(JSON.stringify(response), peerId)
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
        sendData(JSON.stringify(pong), peerId)
        console.log(`🏓 Sent pong to ${peerId}`)
      }, 100)
    }
    
  } catch (error) {
    console.log(`📥 Raw data from ${peerId}: ${data}`)
    
    // Send simple echo for non-JSON data
    const response = `Echo from Node.js: ${data}`
    sendData(response, peerId)
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
    
    sendData(JSON.stringify(status))
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
    
    sendData(JSON.stringify(goodbye))
    console.log('👋 Sent goodbye message to all peers')
  }
  
  // Give time for message to send
  setTimeout(() => {
    process.exit(0)
  }, 1000)
})

console.log('🚀 Node.js test harness is ready and waiting for Swift peers...')
console.log('💡 Send SIGINT (Ctrl+C) to gracefully shutdown')
