#!/usr/bin/env node

/**
 * Simple test runner for TrysteroSwift
 * Uses existing working components (test-relay.js, chat.js, etc)
 * 
 * Usage:
 *   node test-runner.js relay        # Run relay only
 *   node test-runner.js js-js        # Test JS-to-JS chat  
 *   node test-runner.js js-swift     # Test JS-to-Swift chat
 *   node test-runner.js swift-swift  # Test Swift-to-Swift chat
 */

import { spawn } from 'child_process'
import path from 'path'
import { fileURLToPath } from 'url'

const __filename = fileURLToPath(import.meta.url)
const __dirname = path.dirname(__filename)

class TestRunner {
  constructor() {
    this.processes = []
  }

  async startRelay() {
    console.log('🚀 Starting local relay...')
    
    const relay = spawn('node', ['test-relay.js'], {
      cwd: __dirname,
      stdio: ['ignore', 'inherit', 'inherit']
    })
    
    this.processes.push(relay)
    
    // Wait for relay to start
    await new Promise(resolve => setTimeout(resolve, 2000))
    
    return relay
  }

  async runRelayOnly() {
    await this.startRelay()
    console.log('\n📡 Relay is running. Press Ctrl+C to stop.')
    await new Promise(() => {}) // Run forever
  }

  async runJSToJS() {
    console.log('🧪 Testing JS-to-JS communication...\n')
    
    await this.startRelay()
    
    const roomId = 'test-room-' + Date.now()
    
    // Start first JS chat
    const js1 = spawn('node', ['chat.js'], {
      cwd: __dirname,
      env: {
        ...process.env,
        USER_NAME: 'JS-Alice',
        CHAT_ROOM: roomId,
        RELAY_URLS: 'ws://localhost:7447'
      }
    })
    
    js1.stdout.on('data', data => {
      process.stdout.write(`[JS-Alice] ${data}`)
    })
    
    this.processes.push(js1)
    await new Promise(resolve => setTimeout(resolve, 2000))
    
    // Start second JS chat
    const js2 = spawn('node', ['chat.js'], {
      cwd: __dirname,
      env: {
        ...process.env,
        USER_NAME: 'JS-Bob',
        CHAT_ROOM: roomId,
        RELAY_URLS: 'ws://localhost:7447'
      }
    })
    
    js2.stdout.on('data', data => {
      process.stdout.write(`[JS-Bob] ${data}`)
    })
    
    this.processes.push(js2)
    await new Promise(resolve => setTimeout(resolve, 3000))
    
    // Send test messages
    console.log('\n📤 Sending test messages...\n')
    
    js1.stdin.write('Hello from Alice!\n')
    await new Promise(resolve => setTimeout(resolve, 1000))
    
    js2.stdin.write('Hi from Bob!\n')
    await new Promise(resolve => setTimeout(resolve, 2000))
    
    console.log('\n✅ Test complete! Check output above for message exchange.')
  }

  async runJSToSwift() {
    console.log('🧪 Testing JS-to-Swift communication...\n')
    
    await this.startRelay()
    
    const roomId = 'test-room-' + Date.now()
    const swiftPath = path.join(__dirname, '../../Examples/Chat/.build/debug/TrysteroChat')
    
    // Start Swift chat
    const swift = spawn(swiftPath, [], {
      env: {
        ...process.env,
        USER_NAME: 'Swift-User',
        CHAT_ROOM: roomId,
        RELAY_URLS: 'ws://localhost:7447'
      }
    })
    
    swift.stdout.on('data', data => {
      process.stdout.write(`[Swift] ${data}`)
    })
    
    swift.stderr.on('data', data => {
      process.stderr.write(`[Swift-Error] ${data}`)
    })
    
    this.processes.push(swift)
    await new Promise(resolve => setTimeout(resolve, 3000))
    
    // Start JS chat
    const js = spawn('node', ['chat.js'], {
      cwd: __dirname,
      env: {
        ...process.env,
        USER_NAME: 'JS-User',
        CHAT_ROOM: roomId,
        RELAY_URLS: 'ws://localhost:7447'
      }
    })
    
    js.stdout.on('data', data => {
      process.stdout.write(`[JS] ${data}`)
    })
    
    this.processes.push(js)
    await new Promise(resolve => setTimeout(resolve, 3000))
    
    // Send test messages
    console.log('\n📤 Sending test messages...\n')
    
    js.stdin.write('Hello from JavaScript!\n')
    await new Promise(resolve => setTimeout(resolve, 1000))
    
    swift.stdin.write('Hello from Swift!\n')
    await new Promise(resolve => setTimeout(resolve, 2000))
    
    console.log('\n✅ Test complete! Check output above for message exchange.')
  }

  async runSwiftToSwift() {
    console.log('🧪 Testing Swift-to-Swift communication...\n')
    
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
    await new Promise(resolve => setTimeout(resolve, 3000))
    
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
    await new Promise(resolve => setTimeout(resolve, 3000))
    
    // Send test messages
    console.log('\n📤 Sending test messages...\n')
    
    swift1.stdin.write('Hello from Swift Alice!\n')
    await new Promise(resolve => setTimeout(resolve, 1000))
    
    swift2.stdin.write('Hi from Swift Bob!\n')
    await new Promise(resolve => setTimeout(resolve, 2000))
    
    console.log('\n✅ Test complete! Check output above for message exchange.')
  }

  cleanup() {
    console.log('\n\n🧹 Cleaning up...')
    for (const proc of this.processes) {
      proc.kill()
    }
    // Kill any orphaned relay processes
    spawn('pkill', ['-f', 'test-relay.js'], { stdio: 'ignore' })
  }
}

// Main
async function main() {
  const command = process.argv[2]
  const runner = new TestRunner()
  
  // Cleanup on exit
  process.on('SIGINT', () => {
    runner.cleanup()
    process.exit(0)
  })
  
  try {
    switch (command) {
      case 'relay':
        await runner.runRelayOnly()
        break
        
      case 'js-js':
        await runner.runJSToJS()
        break
        
      case 'js-swift':
        await runner.runJSToSwift()
        break
        
      case 'swift-swift':
        await runner.runSwiftToSwift()
        break
        
      default:
        console.log('TrysteroSwift Test Runner')
        console.log('=========================\n')
        console.log('Usage: node test-runner.js <command>\n')
        console.log('Commands:')
        console.log('  relay        - Run local Nostr relay only')
        console.log('  js-js        - Test JS-to-JS chat')
        console.log('  js-swift     - Test JS-to-Swift chat')
        console.log('  swift-swift  - Test Swift-to-Swift chat')
        console.log('\nExample: node test-runner.js js-js')
    }
  } catch (error) {
    console.error('\n❌ Error:', error)
  } finally {
    runner.cleanup()
  }
}

main().catch(console.error)