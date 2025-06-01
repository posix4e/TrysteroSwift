#!/usr/bin/env node

// Minimal Nostr relay for testing - just broadcasts everything
import {WebSocketServer} from 'ws'

const port = process.env.RELAY_PORT || 7777
const wss = new WebSocketServer({port})

const subscriptions = new Map() // subId -> {ws, filters}
const events = [] // Store all events

console.log(`🚀 Test relay starting on ws://localhost:${port}`)

wss.on('connection', (ws) => {
  console.log('📱 Client connected')

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data.toString())

      if (msg[0] === 'EVENT') {
        // Store and broadcast event
        const event = msg[1]
        events.push(event)
        console.log(`📨 Event: ${event.kind} from ${event.pubkey.substring(0, 8)}...`)

        // Send to all matching subscriptions
        for (const [subId, sub] of subscriptions) {
          if (matchesFilters(event, sub.filters)) {
            sub.ws.send(JSON.stringify(['EVENT', subId, event]))
          }
        }
      } else if (msg[0] === 'REQ') {
        // Subscribe
        const subId = msg[1]
        const filters = msg.slice(2)
        subscriptions.set(subId, {ws, filters})

        // Send existing events
        for (const event of events) {
          if (matchesFilters(event, filters)) {
            ws.send(JSON.stringify(['EVENT', subId, event]))
          }
        }

        ws.send(JSON.stringify(['EOSE', subId]))
      } else if (msg[0] === 'CLOSE') {
        // Unsubscribe
        subscriptions.delete(msg[1])
      }
    } catch (e) {
      console.error('❌ Error:', e.message)
    }
  })

  ws.on('close', () => {
    // Remove subscriptions for this connection
    for (const [subId, sub] of subscriptions) {
      if (sub.ws === ws) subscriptions.delete(subId)
    }
  })
})

function matchesFilters(event, filters) {
  // Simple filter matching - just check tags for now
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