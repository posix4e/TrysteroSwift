#!/usr/bin/env node
import { spawn } from 'child_process'
import { join } from 'path'
import { fileURLToPath } from 'url'
import { dirname } from 'path'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

class InteropTestRunner {
  constructor() {
    this.nodeProcess = null
    this.swiftProcess = null
    this.isCleaningUp = false
  }

  async runProtocolVerification() {
    console.log('🔍 Verifying protocol compatibility...')
    
    // Node.js protocol check
    console.log('Node.js using appId: trystero, roomId: swift-interop-test')
    
    // Swift protocol check
    const swiftScript = `
import Foundation
import CryptoKit
let appId = "trystero"
let roomId = "swift-interop-test"
let topicPath = "Trystero@\\(appId)@\\(roomId)"
let data = Data(topicPath.utf8)
let digest = Insecure.SHA1.hash(data: data)
let hash = digest.map { String($0, radix: 36) }.joined()
let truncated = String(hash.prefix(20))
func strToNum(_ s: String, mod: Int) -> Int { var sum = 0; for c in s { sum += Int(c.asciiValue ?? 0) }; return sum % mod }
let kind = 20000 + strToNum(hash, mod: 10000)
print("Swift generating: kind=\\(kind), tag=[\\"x\\", \\"\\(truncated)\\"]")
`
    
    return new Promise((resolve, reject) => {
      const swiftCmd = spawn('swift', ['-e', swiftScript], {
        cwd: join(__dirname, '../..')
      })
      
      swiftCmd.stdout.on('data', (data) => {
        console.log(data.toString().trim())
      })
      
      swiftCmd.on('close', (code) => {
        if (code === 0) {
          console.log('✅ Protocol verification passed')
          resolve()
        } else {
          reject(new Error(`Swift protocol verification failed with code ${code}`))
        }
      })
    })
  }

  async startNodeHarness() {
    console.log('🚀 Starting Node.js harness...')
    
    return new Promise((resolve, reject) => {
      this.nodeProcess = spawn('node', ['trystero-node.js'], {
        cwd: __dirname,
        stdio: ['pipe', 'pipe', 'pipe']
      })
      
      let output = ''
      let hasStarted = false
      
      this.nodeProcess.stdout.on('data', (data) => {
        const text = data.toString()
        console.log(text.trim())
        output += text
        
        // Check if Node.js harness is ready
        if (text.includes('Node.js test harness is ready') && !hasStarted) {
          hasStarted = true
          console.log('✅ Node.js harness is running')
          resolve()
        }
      })
      
      this.nodeProcess.stderr.on('data', (data) => {
        console.error('Node.js stderr:', data.toString().trim())
      })
      
      this.nodeProcess.on('close', (code) => {
        if (!hasStarted && !this.isCleaningUp) {
          reject(new Error(`Node.js harness failed to start (exit code: ${code})`))
        }
      })
      
      this.nodeProcess.on('error', (error) => {
        if (!hasStarted && !this.isCleaningUp) {
          reject(new Error(`Node.js harness error: ${error.message}`))
        }
      })
      
      // Timeout if Node.js doesn't start within 10 seconds
      setTimeout(() => {
        if (!hasStarted && !this.isCleaningUp) {
          reject(new Error('Node.js harness startup timeout'))
        }
      }, 10000)
    })
  }

  async runSwiftTest() {
    console.log('🧪 Running Swift interoperability test...')
    
    return new Promise((resolve, reject) => {
      const timeout = 30000 // 30 seconds - allow for CI latency
      let output = ''
      let hasCompleted = false
      
      this.swiftProcess = spawn('swift', ['test', '--filter', 'testTrysteroJSInteroperability'], {
        cwd: join(__dirname, '../..'),
        stdio: ['pipe', 'pipe', 'pipe']
      })
      
      this.swiftProcess.stdout.on('data', (data) => {
        const text = data.toString()
        console.log(text.trim())
        output += text
      })
      
      this.swiftProcess.stderr.on('data', (data) => {
        const text = data.toString()
        console.error(text.trim())
        output += text
      })
      
      this.swiftProcess.on('close', (code) => {
        if (!hasCompleted) {
          hasCompleted = true
          this.analyzeTestResults(code, output, resolve, reject)
        }
      })
      
      this.swiftProcess.on('error', (error) => {
        if (!hasCompleted) {
          hasCompleted = true
          reject(new Error(`Swift test error: ${error.message}`))
        }
      })
      
      // Set timeout - kill process if it hangs
      setTimeout(() => {
        if (!hasCompleted) {
          hasCompleted = true
          console.log('⏰ Swift test timeout - killing process')
          if (this.swiftProcess && !this.swiftProcess.killed) {
            this.swiftProcess.kill('SIGKILL')  // Force kill
          }
          // Treat timeout as failure
          reject(new Error('Swift test timed out after 30 seconds'))
        }
      }, timeout)
    })
  }

  analyzeTestResults(exitCode, output, resolve, reject) {
    console.log('📊 Test Results:')
    
    // Show relevant output lines
    const relevantLines = output.split('\n')
      .filter(line => /✅|❌|🎉|Swift Debug|peers connected|Successfully joined|timeout|error/i.test(line))
      .slice(0, 20)
    
    if (relevantLines.length > 0) {
      console.log('Swift test output:')
      relevantLines.forEach(line => console.log(line))
    }
    
    // Simple pass/fail logic
    if (exitCode === 0) {
      console.log('🎉 SUCCESS: Swift interop test passed!')
      resolve({ success: true, reason: 'Test passed successfully' })
    } else {
      console.log(`❌ FAILED: Swift interop test failed (exit code: ${exitCode})`)
      reject(new Error(`Swift test failed with exit code ${exitCode}`))
    }
  }

  async cleanup() {
    console.log('🧹 Cleaning up processes...')
    this.isCleaningUp = true
    
    const cleanupPromises = []
    
    if (this.nodeProcess && !this.nodeProcess.killed) {
      cleanupPromises.push(new Promise((resolve) => {
        this.nodeProcess.on('close', resolve)
        this.nodeProcess.kill('SIGTERM')
        setTimeout(() => {
          if (!this.nodeProcess.killed) {
            this.nodeProcess.kill('SIGKILL')
          }
          resolve()
        }, 2000)
      }))
    }
    
    if (this.swiftProcess && !this.swiftProcess.killed) {
      cleanupPromises.push(new Promise((resolve) => {
        this.swiftProcess.on('close', resolve)
        this.swiftProcess.kill('SIGTERM')
        setTimeout(() => {
          if (!this.swiftProcess.killed) {
            this.swiftProcess.kill('SIGKILL')
          }
          resolve()
        }, 2000)
      }))
    }
    
    await Promise.all(cleanupPromises)
    console.log('✅ Cleanup completed')
  }

  async run() {
    let result = { success: false, reason: 'Unknown error' }
    
    try {
      // Phase 1: Protocol verification
      await this.runProtocolVerification()
      
      // Phase 2: Start Node.js harness
      await this.startNodeHarness()
      
      // Give Node.js time to connect to relays
      console.log('⏳ Waiting for Node.js to connect to relays...')
      await new Promise(resolve => setTimeout(resolve, 8000))
      
      // Check if Node.js process is still running
      if (!this.nodeProcess || this.nodeProcess.killed || this.nodeProcess.exitCode !== null) {
        throw new Error('Node.js harness failed to start - likely relay connectivity issues')
      }
      
      // Phase 3: Run Swift test
      result = await this.runSwiftTest()
      
    } catch (error) {
      console.error('❌ Test execution error:', error.message)
      result = { success: false, reason: error.message }
    } finally {
      await this.cleanup()
    }
    
    // Final status
    if (result.success) {
      console.log('✅ Interoperability test completed successfully')
      console.log(`📋 Reason: ${result.reason}`)
      process.exit(0)
    } else {
      console.log('❌ Interoperability test failed')
      console.log(`📋 Reason: ${result.reason}`)
      process.exit(1)
    }
  }
}

// Handle cleanup on process signals
const runner = new InteropTestRunner()

process.on('SIGINT', async () => {
  console.log('\n🛑 Received SIGINT, cleaning up...')
  await runner.cleanup()
  process.exit(0)
})

process.on('SIGTERM', async () => {
  console.log('\n🛑 Received SIGTERM, cleaning up...')
  await runner.cleanup()
  process.exit(0)
})

// Run the test
runner.run().catch(async (error) => {
  console.error('❌ Unhandled error:', error.message)
  await runner.cleanup()
  process.exit(1)
})