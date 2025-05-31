import Foundation
import NostrClient
import Nostr
import CryptoKit
import Security
#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit
#endif

class TrysteroNostrClient: NostrClientDelegate {
    private let client: NostrClient
    private let relays: [String]
    let keyPair: KeyPair  // Made internal for access from TrysteroRoom
    private let appId: String
    private var messageHandler: ((WebRTCSignal, String) -> Void)?
    private var currentRoomId: String?
    
    // Trystero.js compatibility constants
    private static let libName = "Trystero"
    private static let baseEventKind = 20000
    private static let eventKindRange = 10000
    private static let hashLimit = 20  // Match Trystero.js hashLimit for topic hashes
    
    init(relays: [String], appId: String = "") throws {
        self.relays = relays
        self.appId = appId
        
        // Use persistent keypair based on appId for consistent peer identity
        self.keyPair = try Self.getOrCreateKeyPair(for: appId)
        
        self.client = NostrClient()
        self.client.delegate = self
    }
    
    // Persistent keypair storage using Keychain (for consistent peer IDs)
    private static func getOrCreateKeyPair(for appId: String) throws -> KeyPair {
        // Generate device-specific but app-scoped identity
        let deviceId = getDeviceIdentifier()
        let keyId = "TrysteroSwift_\(deviceId)_\(appId.isEmpty ? "default" : appId)"
        
        // Try to load existing keypair from Keychain
        if let existingKeyData = KeychainHelper.load(key: keyId),
           let keyPairData = try? JSONDecoder().decode(KeyPairData.self, from: existingKeyData) {
            print("🔑 [Swift Debug] Loaded existing keypair for appId: '\(appId)'")
            return try KeyPair(hex: keyPairData.privateKey)
        }
        
        // Create new keypair and store it
        let newKeyPair = try KeyPair()
        let keyPairData = KeyPairData(privateKey: newKeyPair.privateKey, publicKey: newKeyPair.publicKey)
        let encodedData = try JSONEncoder().encode(keyPairData)
        
        KeychainHelper.save(key: keyId, data: encodedData)
        print("🔑 [Swift Debug] Created and stored new keypair for appId: '\(appId)'")
        
        return newKeyPair
    }
    
    // Get stable device identifier
    private static func getDeviceIdentifier() -> String {
        #if os(iOS) || os(tvOS) || os(watchOS)
        // iOS: Use identifierForVendor (persistent per vendor, resets on app uninstall)
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            return vendorId
        }
        #elseif os(macOS)
        // macOS: Use hardware UUID (most persistent)
        let task = Process()
        task.launchPath = "/usr/sbin/system_profiler"
        task.arguments = ["SPHardwareDataType"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8),
           let uuidRange = output.range(of: "Hardware UUID: ") {
            let uuidStart = output.index(uuidRange.upperBound, offsetBy: 0)
            let uuidEnd = output.index(uuidStart, offsetBy: 36)
            return String(output[uuidStart..<uuidEnd])
        }
        #endif
        
        // Fallback: Generate and store a UUID in Keychain
        let fallbackKey = "TrysteroSwift_DeviceID"
        if let existingId = KeychainHelper.load(key: fallbackKey),
           let idString = String(data: existingId, encoding: .utf8) {
            return idString
        }
        
        let newId = UUID().uuidString
        KeychainHelper.save(key: fallbackKey, data: newId.data(using: .utf8)!)
        return newId
    }
    
    // MARK: - Trystero.js Compatibility Helpers
    
    /// Generate topic path in Trystero.js format: "Trystero@appId@roomId"
    private func generateTopicPath(roomId: String) -> String {
        return "\(Self.libName)@\(appId)@\(roomId)"
    }
    
    /// Calculate SHA-1 hash and convert to base-36 string like Trystero.js
    private func sha1Hash(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { byte in
            // JavaScript-style byte.toString(36)
            String(byte, radix: 36)
        }.joined()
    }
    
    /// Convert string to number like Trystero.js strToNum function
    private func stringToNumber(_ str: String, modulo: Int) -> Int {
        var sum = 0
        for char in str {
            sum += Int(char.asciiValue ?? 0)
        }
        return sum % modulo
    }
    
    /// Calculate event kind like Trystero.js: strToNum(topicHash, range) + baseKind
    private func calculateEventKind(for roomId: String) -> UInt16 {
        // Trystero.js calculates event kind from the SHA1 topic hash
        let topicHash = generateTopic(roomId: roomId)
        let num = stringToNumber(topicHash, modulo: Self.eventKindRange)
        return UInt16(Self.baseEventKind + num)
    }
    
    /// Generate Trystero.js-compatible topic hash (use full hash for 'x' tag)
    private func generateTopic(roomId: String) -> String {
        let topicPath = generateTopicPath(roomId: roomId)
        return sha1Hash(topicPath)  // Use full hash like Trystero.js actually does
    }
    
    /// Get appropriate expiration time for different signal types
    private func getExpirationTime(for signal: WebRTCSignal) -> Int64 {
        let now = Int64(Date().timeIntervalSince1970)
        
        switch signal {
        case .presence:
            // Presence announcements expire in 5 minutes (300 seconds)
            return now + 300
        case .offer, .answer:
            // WebRTC offers/answers expire in 2 minutes (120 seconds)
            return now + 120
        case .iceCandidate:
            // ICE candidates expire in 1 minute (60 seconds)
            return now + 60
        }
    }
    
    func connect() async throws {
        for relay in relays {
            client.add(relayWithUrl: relay, autoConnect: true)
        }
    }
    
    func disconnect() async {
        client.disconnect()
    }
    
    func subscribe(to roomId: String) async throws {
        self.currentRoomId = roomId
        let rootTopicHash = generateTopic(roomId: roomId)
        let rootEventKind = calculateEventKind(for: roomId)
        let topicPath = generateTopicPath(roomId: roomId)
        
        // Like Trystero.js, also subscribe to our self topic for direct messages
        let selfTopicPath = "\(topicPath)@\(keyPair.publicKey)"
        let selfTopicHash = sha1Hash(selfTopicPath)
        let selfEventKind = UInt16(Self.baseEventKind + stringToNumber(selfTopicHash, modulo: Self.eventKindRange))
        
        print("🔍 [Swift Debug] Subscribing to room: \(roomId)")
        print("🔍 [Swift Debug] Using appId: '\(appId)'")
        print("🔍 [Swift Debug] Topic path: '\(topicPath)'")
        print("🔍 [Swift Debug] Root topic hash: '\(rootTopicHash)'")
        print("🔍 [Swift Debug] Root event kind: \(rootEventKind)")
        print("🔍 [Swift Debug] Self topic hash: '\(selfTopicHash)'")
        print("🔍 [Swift Debug] Self event kind: \(selfEventKind)")
        
        // Subscribe to both root topic (public room events) and self topic (direct messages)
        let rootFilter = Filter(
            kinds: [.custom(rootEventKind)],
            limit: 100,
            tags: [Tag(id: "x", otherInformation: [rootTopicHash])]
        )
        let selfFilter = Filter(
            kinds: [.custom(selfEventKind)],
            limit: 100,
            tags: [Tag(id: "x", otherInformation: [selfTopicHash])]
        )
        
        let subscription = Subscription(filters: [rootFilter, selfFilter])
        client.add(subscriptions: [subscription])
        print("🔍 [Swift Debug] Added subscription with filters for root and self topics")
    }
    
    func publishSignal(_ signal: WebRTCSignal, roomId: String, targetPeer: String?) async throws {
        let content = try signal.toJSON()
        let topicHash = generateTopic(roomId: roomId)
        let eventKind = calculateEventKind(for: roomId)
        
        // Use 'x' tag with full hashed topic (no truncation)
        var tags: [Tag] = [Tag(id: "x", otherInformation: topicHash)]
        if let targetPeer = targetPeer {
            tags.append(Tag(id: "p", otherInformation: targetPeer))
        }
        
        // Add expiration tag for proper ephemeral behavior
        let expirationTime = getExpirationTime(for: signal)
        tags.append(Tag(id: "expiration", otherInformation: String(expirationTime)))
        
        print("🔍 [Swift Debug] Publishing signal:")
        print("🔍 [Swift Debug]   Signal type: \(signal)")
        print("🔍 [Swift Debug]   Room ID: \(roomId)")
        print("🔍 [Swift Debug]   Generated topic hash: '\(topicHash)'")
        print("🔍 [Swift Debug]   Event kind: \(eventKind)")
        print("🔍 [Swift Debug]   Target peer: \(targetPeer ?? "ALL")")
        print("🔍 [Swift Debug]   Expires at: \(expirationTime) (in \(expirationTime - Int64(Date().timeIntervalSince1970))s)")
        
        var event = Event(
            pubkey: keyPair.publicKey,
            createdAt: Timestamp(date: Date()),
            kind: .custom(eventKind),
            tags: tags,
            content: content
        )
        
        try event.sign(with: keyPair)
        print("🔍 [Swift Debug] Event signed with pubkey: \(keyPair.publicKey)")
        
        return try await sendEventWithTimeout(event)
    }
    
    private func sendEventWithTimeout(_ event: Event) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            
            // Add timeout to prevent hanging
            let timer = DispatchSource.makeTimerSource()
            timer.schedule(deadline: .now() + 10) // 10 second timeout
            timer.setEventHandler {
                if !resumed {
                    resumed = true
                    print("🔍 [Swift Debug] Event send timed out")
                    continuation.resume(throwing: TrysteroError.nostrError)
                }
            }
            timer.resume()
            
            client.send(event: event) { error in
                timer.cancel()
                if !resumed {
                    resumed = true
                    if let error = error {
                        print("🔍 [Swift Debug] Event send failed: \(error)")
                        continuation.resume(throwing: error)
                    } else {
                        print("🔍 [Swift Debug] Event sent successfully")
                        continuation.resume()
                    }
                }
            }
        }
    }
    
    func setMessageHandler(_ handler: @escaping (WebRTCSignal, String) -> Void) {
        self.messageHandler = handler
    }
    
    // MARK: - NostrClientDelegate
    
    func didReceive(message: RelayMessage, relayUrl: String) {
        switch message {
        case .event(_, let event):
            print("🔍 [Swift Debug] Received event from \(relayUrl):")
            print("🔍 [Swift Debug]   Event ID: \(event.id ?? "none")")
            print("🔍 [Swift Debug]   Kind: \(event.kind)")
            print("🔍 [Swift Debug]   Pubkey: \(event.pubkey)")
            print("🔍 [Swift Debug]   Tags: \(event.tags)")
            print("🔍 [Swift Debug]   Content: \(event.content)")
            if let roomId = currentRoomId {
                handleNostrEvent(event, for: roomId)
            } else {
                print("🔍 [Swift Debug] No current room ID, ignoring event")
            }
        case .notice(let notice):
            print("🔍 [Swift Debug] Nostr notice from \(relayUrl): \(notice)")
        default:
            print("🔍 [Swift Debug] Other message from \(relayUrl): \(message)")
        }
    }
    
    func didConnect(relayUrl: String) {
        print("Connected to Nostr relay: \(relayUrl)")
    }
    
    func didDisconnect(relayUrl: String) {
        print("Disconnected from Nostr relay: \(relayUrl)")
    }
    
    private func handleNostrEvent(_ event: Event, for roomId: String) {
        // Skip our own events
        guard event.pubkey != keyPair.publicKey else {
            print("🔍 [Swift Debug] Ignoring our own event")
            return
        }
        
        let expectedTopicHash = generateTopic(roomId: roomId)
        let expectedEventKind = calculateEventKind(for: roomId)
        
        print("🔍 [Swift Debug] Processing event in handleNostrEvent:")
        print("🔍 [Swift Debug]   Event kind: \(event.kind)")
        print("🔍 [Swift Debug]   Expected kind: \(expectedEventKind)")
        print("🔍 [Swift Debug]   Kind matches: \(event.kind == .custom(expectedEventKind))")
        
        guard event.kind == .custom(expectedEventKind) else { 
            print("🔍 [Swift Debug] Ignoring event - wrong kind")
            return 
        }
        
        // Check if this event is for our room by looking for 'x' tag with our topic hash
        var isForOurRoom = false
        var foundTopics: [String] = []
        
        for tag in event.tags where tag.id == "x" {
            if let topicValue = tag.otherInformation.first {
                foundTopics.append(topicValue)
                if topicValue == expectedTopicHash {
                    isForOurRoom = true
                }
            }
        }
        
        print("🔍 [Swift Debug] Event topic analysis:")
        print("🔍 [Swift Debug]   Expected topic hash: '\(expectedTopicHash)'")
        print("🔍 [Swift Debug]   Found topic hashes: \(foundTopics)")
        print("🔍 [Swift Debug]   Is for our room: \(isForOurRoom)")
        
        if !isForOurRoom {
            print("🔍 [Swift Debug] Ignoring event - not for our room")
            return
        }
        
        do {
            let signal = try WebRTCSignal.fromJSON(event.content)
            print("🔍 [Swift Debug] Successfully parsed WebRTC signal: \(signal)")
            print("🔍 [Swift Debug] Calling message handler with pubkey: \(event.pubkey)")
            messageHandler?(signal, event.pubkey)
        } catch {
            print("🔍 [Swift Debug] Failed to parse WebRTC signal: \(error)")
            print("🔍 [Swift Debug] Raw content: \(event.content)")
        }
    }
}

enum WebRTCSignal: Codable {
    case offer(sdp: String)
    case answer(sdp: String)
    case iceCandidate(candidate: String, sdpMid: String?, sdpMLineIndex: Int32)
    case presence(peerId: String)
    
    func toJSON() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    static func fromJSON(_ json: String) throws -> WebRTCSignal {
        guard let data = json.data(using: .utf8) else {
            throw TrysteroError.nostrError
        }
        
        // First try standard Swift format
        if let signal = try? JSONDecoder().decode(WebRTCSignal.self, from: data) {
            return signal
        }
        
        // Try Trystero.js format
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Handle direct peerId format: {"peerId":"..."}
            if let peerId = jsonObject["peerId"] as? String {
                return .presence(peerId: peerId)
            }
            
            // Handle other Trystero.js formats
            if let sdp = jsonObject["sdp"] as? String,
               let type = jsonObject["type"] as? String {
                switch type {
                case "offer":
                    return .offer(sdp: sdp)
                case "answer":
                    return .answer(sdp: sdp)
                default:
                    break
                }
            }
            
            // Handle ICE candidate format
            if let candidate = jsonObject["candidate"] as? String {
                let sdpMid = jsonObject["sdpMid"] as? String
                let sdpMLineIndex = jsonObject["sdpMLineIndex"] as? Int32 ?? 0
                return .iceCandidate(candidate: candidate, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex)
            }
        }
        
        throw TrysteroError.invalidSignal
    }
}

// MARK: - Persistent KeyPair Storage

private struct KeyPairData: Codable {
    let privateKey: String
    let publicKey: String
}

private class KeychainHelper {
    static func save(key: String, data: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        SecItemAdd(query as CFDictionary, nil)
    }
    
    static func load(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            return result as? Data
        }
        
        return nil
    }
    
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
