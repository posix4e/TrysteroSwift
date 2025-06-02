import Foundation
@preconcurrency import NostrClient
import Nostr
import CryptoKit

/// Handles Nostr relay communication for signaling
@MainActor
class NostrRelay: NostrClientDelegate {
    private let config: Config
    private let namespace: String
    private let selfId: String
    private let keyPair: KeyPair
    private var client: NostrClient
    private var subscriptions: Set<String> = []
    private let rootEventKind: UInt16  // For presence announcements
    private let selfEventKind: UInt16  // For receiving signals
    private var peerIdToPubkey: [String: String] = [:]  // Maps internal peerIds to Nostr pubkeys
    private var pubkeyToPeerId: [String: String] = [:]  // Maps Nostr pubkeys to internal peerIds
    private var peerEventKinds: [String: UInt16] = [:]  // Maps peerIds to their event kinds

    var onSignal: ((Signal, String) -> Void)?
    var onPeerPresence: ((String) -> Void)?

    init(config: Config, namespace: String, selfId: String) {
        self.config = config
        self.namespace = namespace
        self.selfId = selfId

        // Calculate root topic for presence announcements
        let rootTopicPath = "Trystero@\(config.appId)@\(namespace)"
        let rootTopicHash = Self.sha1Hash(rootTopicPath)
        self.rootEventKind = Self.topicToKind(rootTopicHash)

        // Calculate self topic for receiving signals
        let selfTopicPath = "Trystero@\(config.appId)@\(namespace)@\(selfId)"
        let selfTopicHash = Self.sha1Hash(selfTopicPath)
        self.selfEventKind = Self.topicToKind(selfTopicHash)

        // Create a new keypair for this room
        do {
            self.keyPair = try KeyPair()
        } catch {
            fatalError("Failed to create Nostr keypair: \(error)")
        }

        self.client = NostrClient()
        self.client.delegate = self
    }

    // MARK: - Static Methods

    /// Calculate SHA1 hash of a string and return as base36 string (matching Trystero.js)
    /// Each byte is converted to base36 and joined
    private static func sha1Hash(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = Insecure.SHA1.hash(data: data)
        return hash.map { byte in
            String(Int(byte), radix: 36)
        }.joined()
    }

    /// Convert topic string to event kind (matching Trystero.js)
    /// Uses the same algorithm: strToNum(topic, 10_000) + 20_000
    private static func topicToKind(_ topic: String) -> UInt16 {
        let sum = topic.reduce(0) { acc, char in
            acc + Int(char.asciiValue ?? 0)
        }
        return UInt16((sum % 10_000) + 20_000)
    }

    func connect() async throws {
        let relays = selectRelays()
        print("📡 NostrRelay: Connecting to relays: \(relays)")

        // Add relays and connect
        for relay in relays {
            client.add(relayWithUrl: relay, subscriptions: [], autoConnect: true)
        }

        // Subscribe to room events
        subscribeToRoom()

        // Announce presence after a delay with jitter to avoid rate limits
        let jitter = UInt64.random(in: 0...2_000_000_000) // 0-2 seconds random
        try await Task.sleep(nanoseconds: 3_000_000_000 + jitter) // 3-5 seconds
        announcePresence()
    }

    func disconnect() {
        subscriptions.forEach { _ in
            // NostrClient doesn't have direct unsubscribe - remove all and reconnect
        }
        subscriptions.removeAll()
        client.disconnect()
    }

    func sendSignal(_ signal: Signal, to peerId: String) throws {
        // Look up the Nostr pubkey for this peerId
        guard let targetPubkey = peerIdToPubkey[peerId] else {
            // If we don't have the mapping, we can't send the signal
            throw TrysteroError.peerNotFound(peerId)
        }

        let content = encodeSignal(signal)

        // Send to peer's self topic
        let peerTopicPath = "Trystero@\(config.appId)@\(namespace)@\(peerId)"
        let peerTopicHash = Self.sha1Hash(peerTopicPath)
        let peerEventKind = peerEventKinds[peerId] ?? Self.topicToKind(peerTopicHash)

        print("📡 NostrRelay: Sending signal \(signal.type) to peer topic: \(peerTopicHash), event kind: \(peerEventKind)")

        var event = Event(
            pubkey: keyPair.publicKey,
            createdAt: Timestamp(date: Date()),
            kind: .custom(peerEventKind),
            tags: [
                Tag(id: "x", otherInformation: peerTopicHash),
                Tag(id: "p", otherInformation: targetPubkey)
            ],
            content: content
        )

        try event.sign(with: keyPair)

        // Send event without callback
        client.send(event: event)
    }

    // MARK: - Private

    private func selectRelays() -> [String] {
        if let customRelays = config.relayUrls {
            return Array(customRelays.prefix(config.relayRedundancy))
        }

        // Default Trystero relays
        let defaults = [
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.nostr.band",
            "wss://nostr.wine",
            "wss://relay.snort.social"
        ]

        // Deterministic selection based on app ID
        let hash = config.appId.hashValue
        var selected: [String] = []
        var index = abs(hash) % defaults.count

        for _ in 0..<min(config.relayRedundancy, defaults.count) {
            selected.append(defaults[index])
            index = (index + 1) % defaults.count
        }

        return selected
    }

    private func subscribeToRoom() {
        // Subscribe to root topic for presence announcements
        let rootTopicHash = Self.sha1Hash("Trystero@\(config.appId)@\(namespace)")
        print("📡 NostrRelay: Subscribing to root topic hash: \(rootTopicHash), event kind: \(rootEventKind)")

        let rootFilter = Filter(
            kinds: [.custom(rootEventKind)],
            tags: [Tag(id: "x", otherInformation: [rootTopicHash])]
        )

        let rootSubId = UUID().uuidString
        subscriptions.insert(rootSubId)

        let rootSubscription = Subscription(filters: [rootFilter], id: rootSubId)
        client.add(subscriptions: [rootSubscription])

        // Subscribe to self topic for receiving signals
        let selfTopicHash = Self.sha1Hash("Trystero@\(config.appId)@\(namespace)@\(selfId)")
        print("📡 NostrRelay: Subscribing to self topic hash: \(selfTopicHash), event kind: \(selfEventKind)")

        let selfFilter = Filter(
            kinds: [.custom(selfEventKind)],
            tags: [Tag(id: "x", otherInformation: [selfTopicHash])]
        )

        let selfSubId = UUID().uuidString
        subscriptions.insert(selfSubId)

        let selfSubscription = Subscription(filters: [selfFilter], id: selfSubId)
        client.add(subscriptions: [selfSubscription])
    }

    private func announcePresence() {
        let topicHash = Self.sha1Hash("Trystero@\(config.appId)@\(namespace)")
        print("📡 NostrRelay: Announcing presence with peerId: \(selfId), topic hash: \(topicHash), event kind: \(rootEventKind)")

        var event = Event(
            pubkey: keyPair.publicKey,
            createdAt: Timestamp(date: Date()),
            kind: .custom(rootEventKind),
            tags: [Tag(id: "x", otherInformation: topicHash)],
            content: "{\"peerId\":\"\(selfId)\"}"
        )

        do {
            try event.sign(with: keyPair)
            Task { @MainActor in
                client.send(event: event)
                print("📡 NostrRelay: Sent presence announcement")
            }
        } catch {
            print("❌ NostrRelay: Failed to sign presence event: \(error)")
        }

        // Re-announce periodically with longer interval to avoid rate limits
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000_000) // 120 seconds
            self.announcePresence()
        }
    }

    // MARK: - NostrClientDelegate

    nonisolated func didReceive(message: RelayMessage, relayUrl: String) {
        switch message {
        case .event(_, let event):
            Task { @MainActor in
                self.handleEvent(event)
            }
        default:
            break
        }
    }

    nonisolated func didConnect(relayUrl: String) {
        Task { @MainActor in
            print("📡 NostrRelay: Connected to relay: \(relayUrl)")
        }
    }

    nonisolated func didDisconnect(relayUrl: String) {
        Task { @MainActor in
            print("📡 NostrRelay: Disconnected from relay: \(relayUrl)")
        }
    }

    private func handleEvent(_ event: Event) {
        // Ignore our own events
        guard event.pubkey != keyPair.publicKey else { return }

        let content = event.content
        print("📡 NostrRelay: Received event from \(event.pubkey.prefix(8))...: \(content)")

        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            // Check if it's a wrapped offer/answer (from Trystero.js) - check this FIRST
            if let peerId = json["peerId"] as? String,
               let offer = json["offer"] as? [String: Any],
               let offerType = offer["type"] as? String,
               let sdp = offer["sdp"] as? String {
                print("📡 NostrRelay: Received wrapped \(offerType) from peer: \(peerId)")
                // Store mapping
                if peerIdToPubkey[peerId] == nil {
                    peerIdToPubkey[peerId] = event.pubkey
                    pubkeyToPeerId[event.pubkey] = peerId
                    let peerTopicPath = "Trystero@\(config.appId)@\(namespace)@\(peerId)"
                    let peerTopicHash = Self.sha1Hash(peerTopicPath)
                    peerEventKinds[peerId] = Self.topicToKind(peerTopicHash)
                }
                // Don't call onPeerPresence here - let the signal handler create the peer
                // This avoids creating duplicate peers
                print("📡 NostrRelay: Encoded SDP: \(sdp)")
                let decodedSdp = decodeWrappedSdp(sdp)
                print("📡 NostrRelay: Decoded SDP: \(decodedSdp)")
                let signal = Signal(type: offerType == "offer" ? .offer : .answer, sdp: decodedSdp)
                onSignal?(signal, peerId)
            }
            // Check if it's a presence announcement (just {peerId: "..."})
            else if let peerId = json["peerId"] as? String, json["type"] == nil {
                print("📡 NostrRelay: Received presence announcement from peer: \(peerId)")
                // Store bidirectional mapping between internal peerId and Nostr pubkey
                peerIdToPubkey[peerId] = event.pubkey
                pubkeyToPeerId[event.pubkey] = peerId
                // Calculate and store peer's event kind
                let peerTopicPath = "Trystero@\(config.appId)@\(namespace)@\(peerId)"
                let peerTopicHash = Self.sha1Hash(peerTopicPath)
                peerEventKinds[peerId] = Self.topicToKind(peerTopicHash)
                onPeerPresence?(peerId)
            }
            // Check for other typed messages
            else if let type = json["type"] as? String {
                if type == "presence" {
                    if let peerId = json["peerId"] as? String {
                        print("📡 NostrRelay: Received typed presence from peer: \(peerId)")
                        // Store bidirectional mapping for typed presence too
                        peerIdToPubkey[peerId] = event.pubkey
                        pubkeyToPeerId[event.pubkey] = peerId
                        // Calculate and store peer's event kind
                        let peerTopicPath = "Trystero@\(config.appId)@\(namespace)@\(peerId)"
                        let peerTopicHash = Self.sha1Hash(peerTopicPath)
                        peerEventKinds[peerId] = Self.topicToKind(peerTopicHash)
                        onPeerPresence?(peerId)
                    }
                } else if let signal = decodeSignal(from: json) {
                    print("📡 NostrRelay: Received signal type \(signal.type) from \(event.pubkey.prefix(8))...")
                    // Get peerId from the signal content
                    if let signalPeerId = json["peerId"] as? String {
                        // Store mapping if we don't have it
                        if peerIdToPubkey[signalPeerId] == nil {
                            peerIdToPubkey[signalPeerId] = event.pubkey
                            pubkeyToPeerId[event.pubkey] = signalPeerId
                            // Calculate and store peer's event kind
                            let peerTopicPath = "Trystero@\(config.appId)@\(namespace)@\(signalPeerId)"
                            let peerTopicHash = Self.sha1Hash(peerTopicPath)
                            peerEventKinds[signalPeerId] = Self.topicToKind(peerTopicHash)
                        }
                        onSignal?(signal, signalPeerId)
                    } else {
                        print("⚠️ NostrRelay: Received signal without peerId from \(event.pubkey.prefix(8))...")
                    }
                }
            }
        }
    }

    private func encodeSignal(_ signal: Signal) -> String {
        switch signal.type {
        case .offer, .answer:
            // Use wrapped format for offers/answers to match Trystero.js
            var json: [String: Any] = ["peerId": selfId]

            if let sdp = signal.sdp {
                do {
                    let encryptedSdp = try encryptSdp(sdp)
                    let signalData: [String: Any] = [
                        "type": signal.type.rawValue,
                        "sdp": encryptedSdp
                    ]
                    json[signal.type.rawValue] = signalData
                } catch {
                    print("❌ NostrRelay: Failed to encrypt SDP: \(error)")
                    // Fallback to unencrypted
                    let signalData: [String: Any] = [
                        "type": signal.type.rawValue,
                        "sdp": sdp
                    ]
                    json[signal.type.rawValue] = signalData
                }
            }

            guard let data = try? JSONSerialization.data(withJSONObject: json),
                  let string = String(data: data, encoding: .utf8) else {
                return "{\"peerId\":\"\(selfId)\"}"
            }
            return string

        case .candidate:
            // Use regular format for ICE candidates
            let json: [String: Any] = [
                "type": signal.type.rawValue,
                "peerId": selfId,
                "candidate": signal.candidate ?? "",
                "sdpMid": signal.sdpMid ?? "",
                "sdpMLineIndex": signal.sdpMLineIndex ?? 0
            ]

            guard let data = try? JSONSerialization.data(withJSONObject: json),
                  let string = String(data: data, encoding: .utf8) else {
                return "{\"type\":\"\(signal.type.rawValue)\",\"peerId\":\"\(selfId)\"}"
            }
            return string

        case .bye:
            return "{\"type\":\"bye\",\"peerId\":\"\(selfId)\"}"
        }
    }

    private func decodeSignal(from json: [String: Any]) -> Signal? {
        guard let typeString = json["type"] as? String,
              let type = SignalType(rawValue: typeString) else { return nil }

        switch type {
        case .offer, .answer:
            guard let sdp = json["sdp"] as? String else { return nil }
            return Signal(type: type, sdp: sdp)

        case .candidate:
            guard let candidate = json["candidate"] as? String,
                  let sdpMid = json["sdpMid"] as? String,
                  let sdpMLineIndex = json["sdpMLineIndex"] as? Int32 else { return nil }
            return Signal(type: type, candidate: candidate, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex)

        case .bye:
            return Signal(type: type)
        }
    }

    /// Decode wrapped SDP from Trystero.js format
    private func decodeWrappedSdp(_ encoded: String) -> String {
        // Check if it's in the encrypted format "iv$encryptedData"
        guard let dollarIndex = encoded.firstIndex(of: "$") else {
            return encoded
        }

        // Extract IV and encrypted data
        let ivString = String(encoded[..<dollarIndex])
        let base64Part = String(encoded[encoded.index(after: dollarIndex)...])

        // Parse IV from comma-separated numbers
        let ivNumbers = ivString.split(separator: ",").compactMap { Int($0) }
        guard ivNumbers.count == 16 else {
            print("❌ NostrRelay: Invalid IV length: \(ivNumbers.count)")
            return encoded
        }

        let iv = Data(ivNumbers.map { UInt8($0) })

        // Decode base64 encrypted data
        guard let encryptedData = Data(base64Encoded: base64Part) else {
            print("❌ NostrRelay: Failed to decode base64")
            return encoded
        }

        // Decrypt using AES-GCM with empty password
        do {
            let decrypted = try decryptAESGCM(
                encryptedData: encryptedData,
                iv: iv,
                password: "",
                appId: config.appId,
                roomId: namespace
            )

            print("📡 NostrRelay: Successfully decrypted SDP")
            return decrypted
        } catch {
            print("❌ NostrRelay: Failed to decrypt: \(error)")
            return encoded
        }
    }

    /// Decrypt AES-GCM encrypted data matching Trystero.js crypto
    private func decryptAESGCM(encryptedData: Data, iv: Data, password: String, appId: String, roomId: String) throws -> String {
        // Generate key from password using SHA-256 (matching Trystero.js genKey)
        let keyString = "\(password):\(appId):\(roomId)"
        let keyData = Data(keyString.utf8)
        let keyHash = SHA256.hash(data: keyData)

        // Create AES-GCM key
        let key = SymmetricKey(data: keyHash)

        // Create sealed box from encrypted data
        // AES-GCM in WebCrypto includes a 16-byte tag at the end
        let sealedBox = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: iv),
            ciphertext: encryptedData.dropLast(16),
            tag: encryptedData.suffix(16)
        )

        // Decrypt
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        guard let decryptedString = String(data: decryptedData, encoding: .utf8) else {
            throw TrysteroError.webRTCSignalingFailed("Failed to decode decrypted data as UTF-8")
        }

        return decryptedString
    }

    /// Encrypt SDP to match Trystero.js format
    private func encryptSdp(_ sdp: String) throws -> String {
        // Generate random IV (16 bytes)
        let iv = Data((0..<16).map { _ in UInt8.random(in: 0...255) })

        // Generate key from password using SHA-256 (matching Trystero.js genKey)
        let keyString = ":\(config.appId):\(namespace)" // Empty password
        let keyData = Data(keyString.utf8)
        let keyHash = SHA256.hash(data: keyData)

        // Create AES-GCM key
        let key = SymmetricKey(data: keyHash)

        // Encrypt
        let sdpData = Data(sdp.utf8)
        let sealedBox = try AES.GCM.seal(sdpData, using: key, nonce: AES.GCM.Nonce(data: iv))

        // Combine ciphertext and tag
        let encryptedData = sealedBox.ciphertext + sealedBox.tag

        // Format as iv$base64
        let ivString = iv.map { String($0) }.joined(separator: ",")
        let base64String = encryptedData.base64EncodedString()

        return "\(ivString)$\(base64String)"
    }
}

/// WebRTC signaling message
struct Signal {
    let type: SignalType
    var sdp: String?
    var candidate: String?
    var sdpMid: String?
    var sdpMLineIndex: Int32?

    init(type: SignalType, sdp: String? = nil, candidate: String? = nil, sdpMid: String? = nil, sdpMLineIndex: Int32? = nil) {
        self.type = type
        self.sdp = sdp
        self.candidate = candidate
        self.sdpMid = sdpMid
        self.sdpMLineIndex = sdpMLineIndex
    }
}

enum SignalType: String {
    case offer
    case answer
    case candidate
    case bye
}
