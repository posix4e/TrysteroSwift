#!/usr/bin/env node

import {joinRoom} from 'trystero/nostr'
import {polyfill} from 'node-datachannel/polyfill'
import readline from 'readline'

// Polyfill WebRTC for Node.js
polyfill()

// Configuration
const roomName = process.env.CHAT_ROOM || 'trystero-chat-demo'
const userName = process.env.USER_NAME || `JSUser-${Math.floor(Math.random() * 9000) + 1000}`
const appId = process.env.APP_ID || 'trystero-swift-chat'

console.log('🌐 Trystero.js Chat')
console.log('===================')
console.log(`👤 Your name: ${userName}`)
console.log(`🏠 Room: ${roomName}`)
console.log('📡 Connecting to Nostr relays...')

// Join room
const room = joinRoom({
    appId: appId,
    relayUrls: [
        'wss://relay.damus.io',
        'wss://nos.lol',
        'wss://relay.nostr.band'
    ]
}, roomName)

// Create chat action
const [sendMessage, onMessage] = room.makeAction('chat')

// Track peers
const connectedPeers = new Set()

// Handle messages
onMessage((data, peerId) => {
    if (data.text && data.from && data.timestamp) {
        const date = new Date(data.timestamp * 1000)
        const time = date.toLocaleTimeString([], {hour: '2-digit', minute: '2-digit'})
        
        console.log(`\n[${time}] ${data.from}: ${data.text}`)
        process.stdout.write('> ')
    }
})

// Handle peer events
room.onPeerJoin(peerId => {
    connectedPeers.add(peerId)
    console.log(`\n✅ ${peerId} joined (Total peers: ${connectedPeers.size})`)
    
    // Send welcome
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

// Show commands
console.log('Commands:')
console.log('  /peers  - List connected peers')
console.log('  /room   - Show room info')
console.log('  /quit   - Exit chat\n')

// Setup readline
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
    
    // Handle commands
    if (trimmed.startsWith('/')) {
        switch (trimmed) {
            case '/quit':
            case '/exit':
            case '/q':
                console.log('👋 Goodbye!')
                room.leave()
                process.exit(0)
                break
                
            case '/peers':
            case '/list':
                if (connectedPeers.size === 0) {
                    console.log('No peers connected')
                } else {
                    console.log(`Connected peers (${connectedPeers.size}):`)
                    connectedPeers.forEach(peer => {
                        console.log(`  • ${peer}`)
                    })
                }
                break
                
            case '/room':
            case '/info':
                console.log(`Room: ${roomName}`)
                console.log(`Your ID: ${userName}`)
                console.log(`App ID: ${appId}`)
                console.log(`Connected peers: ${connectedPeers.size}`)
                break
                
            default:
                console.log(`Unknown command: ${trimmed}`)
                console.log('Available commands: /peers, /room, /quit')
        }
    } else {
        // Send message
        const message = {
            text: trimmed,
            from: userName,
            timestamp: Date.now() / 1000
        }
        
        // Broadcast
        sendMessage(message)
        
        // Show own message
        const time = new Date().toLocaleTimeString([], {hour: '2-digit', minute: '2-digit'})
        console.log(`[${time}] You: ${trimmed}`)
    }
    
    rl.prompt()
})

// Handle Ctrl+C
process.on('SIGINT', () => {
    console.log('\n👋 Goodbye!')
    room.leave()
    process.exit(0)
})