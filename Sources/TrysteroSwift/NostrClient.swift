import Foundation
import NostrClient
import Nostr
import CryptoKit

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
    
    init(relays: [String], appId: String = "") throws {
        self.relays = relays
        self.appId = appId
        self.keyPair = try KeyPair()
        self.client = NostrClient()
        self.client.delegate = self
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
    
    /// Calculate event kind like Trystero.js: strToNum(fullTopicHash, range) + baseKind
    private func calculateEventKind(for fullTopicHash: String) -> UInt16 {
        let num = stringToNumber(fullTopicHash, modulo: Self.eventKindRange)
        return UInt16(Self.baseEventKind + num)
    }
    
    /// Generate Trystero.js-compatible topic hash (first 20 chars of base-36 SHA1)
    private func generateTopic(roomId: String) -> (fullHash: String, truncatedHash: String) {
        let topicPath = generateTopicPath(roomId: roomId)
        let fullHash = sha1Hash(topicPath)
        let truncatedHash = String(fullHash.prefix(20))  // First 20 characters like Trystero.js hashLimit
        return (fullHash: fullHash, truncatedHash: truncatedHash)
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
        let topicHashes = generateTopic(roomId: roomId)
        let eventKind = calculateEventKind(for: topicHashes.fullHash)
        let topicPath = generateTopicPath(roomId: roomId)
        
        print("🔍 [Swift Debug] Subscribing to room: \(roomId)")
        print("🔍 [Swift Debug] Using appId: '\(appId)'")
        print("🔍 [Swift Debug] Topic path: '\(topicPath)'")
        print("🔍 [Swift Debug] Generated full topic hash: '\(topicHashes.fullHash)'")
        print("🔍 [Swift Debug] Generated truncated topic hash: '\(topicHashes.truncatedHash)'")
        print("🔍 [Swift Debug] Calculated event kind: \(eventKind)")
        
        let filter = Filter(
            kinds: [.custom(eventKind)],
            limit: 100
        )
        let subscription = Subscription(filters: [filter])
        client.add(subscriptions: [subscription])
        print("🔍 [Swift Debug] Added subscription with filter: kinds=[\(eventKind)], limit=100")
        print("🔍 [Swift Debug] Will filter by 'x' tag with value: '\(topicHashes.truncatedHash)'")
    }
    
    func publishSignal(_ signal: WebRTCSignal, roomId: String, targetPeer: String?) async throws {
        let content = try signal.toJSON()
        let topicHashes = generateTopic(roomId: roomId)
        let eventKind = calculateEventKind(for: topicHashes.fullHash)
        let topicPath = generateTopicPath(roomId: roomId)
        
        // Use 'x' tag with truncated hashed topic like Trystero.js
        var tags: [Tag] = [Tag(id: "x", otherInformation: topicHashes.truncatedHash)]
        if let targetPeer = targetPeer {
            tags.append(Tag(id: "p", otherInformation: targetPeer))
        }
        
        print("🔍 [Swift Debug] Publishing signal:")
        print("🔍 [Swift Debug]   Signal type: \(signal)")
        print("🔍 [Swift Debug]   Room ID: \(roomId)")
        print("🔍 [Swift Debug]   App ID: '\(appId)'")
        print("🔍 [Swift Debug]   Topic path: '\(topicPath)'")
        print("🔍 [Swift Debug]   Generated full topic hash: '\(topicHashes.fullHash)'")
        print("🔍 [Swift Debug]   Generated truncated topic hash: '\(topicHashes.truncatedHash)'")
        print("🔍 [Swift Debug]   Event kind: \(eventKind)")
        print("🔍 [Swift Debug]   Target peer: \(targetPeer ?? "ALL")")
        print("🔍 [Swift Debug]   Tags: \(tags)")
        print("🔍 [Swift Debug]   Content: \(content)")
        
        var event = Event(
            pubkey: keyPair.publicKey,
            createdAt: Timestamp(date: Date()),
            kind: .custom(eventKind),
            tags: tags,
            content: content
        )
        
        try event.sign(with: keyPair)
        
        print("🔍 [Swift Debug] Event signed with pubkey: \(keyPair.publicKey)")
        
        // Send event without waiting for completion to avoid hanging
        client.send(event: event) { error in
            if let error = error {
                print("🔍 [Swift Debug] Event send failed: \(error)")
            } else {
                print("🔍 [Swift Debug] Event sent successfully")
            }
        }
        print("🔍 [Swift Debug] Event queued for sending")
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
        let expectedTopicHashes = generateTopic(roomId: roomId)
        let expectedEventKind = calculateEventKind(for: expectedTopicHashes.fullHash)
        
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
                // Accept both truncated hash (20 chars) and full hash (40 chars) for compatibility
                if topicValue == expectedTopicHashes.truncatedHash || topicValue == expectedTopicHashes.fullHash {
                    isForOurRoom = true
                }
            }
        }
        
        print("🔍 [Swift Debug] Event topic analysis:")
        print("🔍 [Swift Debug]   Expected truncated topic hash: '\(expectedTopicHashes.truncatedHash)'")
        print("🔍 [Swift Debug]   Expected full topic hash: '\(expectedTopicHashes.fullHash)'")
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
        
        // Try standard Swift format first
        do {
            return try JSONDecoder().decode(WebRTCSignal.self, from: data)
        } catch {
            // If that fails, try Node.js Trystero.js format
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let peerId = jsonObject["peerId"] as? String {
                // Node.js sends simple {"peerId": "..."} for presence announcements
                return .presence(peerId: peerId)
            }
            
            // If both fail, throw the original error
            throw error
        }
    }
}
