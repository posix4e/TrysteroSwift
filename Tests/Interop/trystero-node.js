#!/usr/bin/env node
import WebSocket from 'ws'
import {joinRoom} from 'trystero'
import {RTCPeerConnection} from 'node-datachannel/polyfill'

// Set up WebSocket polyfill for Node.js environment with debugging
const OriginalWebSocket = WebSocket

class DebugWebSocket extends OriginalWebSocket {
  constructor(url, protocols) {
    super(url, protocols)
    console.log(`🔍 [Node.js Debug] WebSocket connecting to: ${url}`)
    
    this.addEventListener('open', () => {
      console.log(`🔍 [Node.js Debug] WebSocket opened: ${url}`)
    })
    
    this.addEventListener('message', (event) => {
      try {
        const message = JSON.parse(event.data)
        if (message[0] === 'EVENT') {
          const eventData = message[2]
          console.log(`🔍 [Node.js Debug] Received Nostr event from ${url}:`)
          console.log(`🔍 [Node.js Debug]   ID: ${eventData.id}`)
          console.log(`🔍 [Node.js Debug]   Kind: ${eventData.kind}`)
          console.log(`🔍 [Node.js Debug]   Pubkey: ${eventData.pubkey}`)
          console.log(`🔍 [Node.js Debug]   Tags: ${JSON.stringify(eventData.tags)}`)
          console.log(`🔍 [Node.js Debug]   Content: ${eventData.content}`)
        }
      } catch (e) {
        // Not JSON or not a Nostr event, ignore
      }
    })
    
    const originalSend = this.send
    this.send = function(data) {
      try {
        const message = JSON.parse(data)
        if (message[0] === 'EVENT') {
          const eventData = message[1]
          console.log(`🔍 [Node.js Debug] Sending Nostr event to ${url}:`)
          console.log(`🔍 [Node.js Debug]   ID: ${eventData.id}`)
          console.log(`🔍 [Node.js Debug]   Kind: ${eventData.kind}`)
          console.log(`🔍 [Node.js Debug]   Pubkey: ${eventData.pubkey}`)
          console.log(`🔍 [Node.js Debug]   Tags: ${JSON.stringify(eventData.tags)}`)
          console.log(`🔍 [Node.js Debug]   Content: ${eventData.content}`)
        } else if (message[0] === 'REQ') {
          console.log(`🔍 [Node.js Debug] Sending subscription to ${url}:`)
          console.log(`🔍 [Node.js Debug]   Subscription: ${JSON.stringify(message)}`)
        }
      } catch (e) {
        // Not JSON, still send
      }
      return originalSend.call(this, data)
    }
  }
}

global.WebSocket = DebugWebSocket

const ROOM_ID = 'swift-interop-test'
const RELAY_URLS = ['wss://relay.damus.io', 'wss://nos.lol']

console.log('🟢 Starting Trystero Node.js test harness...')
console.log(`📡 Connecting to relays: ${RELAY_URLS.join(', ')}`)
console.log(`🏠 Room ID: ${ROOM_ID}`)

// Create room configuration (using minimal appId - Trystero.js requires non-empty appId)
const roomConfig = {
  appId: 'trystero',  // Minimal appId that Trystero.js will accept
  rtcPolyfill: RTCPeerConnection,
  relays: RELAY_URLS
}

console.log('📋 Room configuration:', JSON.stringify(roomConfig, null, 2))

// Join the room
const room = joinRoom(roomConfig, ROOM_ID)
console.log('🏠 Joined room successfully')

// Debug: Try to inspect the room object to understand internal workings
console.log('🔍 [Node.js Debug] Room object inspection:')
console.log('🔍 [Node.js Debug]   Room keys:', Object.keys(room))

// If we can access internal room properties, log them
if (room._nostrTopic) {
  console.log('🔍 [Node.js Debug]   Nostr topic:', room._nostrTopic)
}
if (room._appId) {
  console.log('🔍 [Node.js Debug]   Internal appId:', room._appId)
}
if (room._roomId) {
  console.log('🔍 [Node.js Debug]   Internal roomId:', room._roomId)
}

// Track connected peers
const peers = new Set()
let messageCount = 0

// Send periodic presence announcements and debug info
setInterval(() => {
  console.log(`📊 Node.js Status: ${peers.size} peers connected, ${messageCount} messages received`)
  console.log(`🔍 [Node.js Debug] Room configuration:`)
  console.log(`🔍 [Node.js Debug]   appId: '${roomConfig.appId}'`)
  console.log(`🔍 [Node.js Debug]   roomId: '${ROOM_ID}'`)
  console.log(`🔍 [Node.js Debug]   Expected Swift hashtag: '${roomConfig.appId}-${ROOM_ID}'`)
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
