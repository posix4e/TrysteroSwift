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
    private let eventKind: UInt16
    private var peerIdToPubkey: [String: String] = [:]  // Maps internal peerIds to Nostr pubkeys

    var onSignal: ((Signal, String) -> Void)?
    var onPeerPresence: ((String) -> Void)?

    init(config: Config, namespace: String, selfId: String) {
        self.config = config
        self.namespace = namespace
        self.selfId = selfId

        // Calculate topic hash matching Trystero.js: SHA1("Trystero@{appId}@{roomId}")
        let topicPath = "Trystero@\(config.appId)@\(namespace)"
        let topicHash = Self.sha1Hash(topicPath)

        // Calculate event kind from topic hash (matching Trystero.js)
        self.eventKind = Self.topicToKind(topicHash)

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

    func sendSignal(_ signal: Signal, to peerId: String) async throws {
        // Look up the Nostr pubkey for this peerId
        guard let targetPubkey = peerIdToPubkey[peerId] else {
            // If we don't have the mapping, we can't send the signal
            throw TrysteroError.peerNotFound(peerId)
        }

        let content = encodeSignal(signal)

        var event = Event(
            pubkey: keyPair.publicKey,
            createdAt: Timestamp(date: Date()),
            kind: .custom(eventKind),
            tags: [
                Tag(id: "x", otherInformation: Self.sha1Hash("Trystero@\(config.appId)@\(namespace)")),
                Tag(id: "p", otherInformation: targetPubkey)
            ],
            content: content
        )

        try event.sign(with: keyPair)

        // Send event with callback
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                client.send(event: event) { _ in
                    continuation.resume()
                }
            }
        }
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
        let filter = Filter(
            kinds: [.custom(eventKind)],
            tags: [Tag(id: "x", otherInformation: Self.sha1Hash("Trystero@\(config.appId)@\(namespace)"))]
        )

        let subId = UUID().uuidString
        subscriptions.insert(subId)

        let subscription = Subscription(filters: [filter], id: subId)
        client.add(subscriptions: [subscription])
    }

    private func announcePresence() {
        var event = Event(
            pubkey: keyPair.publicKey,
            createdAt: Timestamp(date: Date()),
            kind: .custom(eventKind),
            tags: [Tag(id: "x", otherInformation: Self.sha1Hash("Trystero@\(config.appId)@\(namespace)"))],
            content: "{\"peerId\":\"\(selfId)\"}"
        )

        do {
            try event.sign(with: keyPair)
            Task { @MainActor in
                client.send(event: event) { _ in
                    // Best effort - presence announcements can fail
                }
            }
        } catch {
            // Non-fatal: presence will be re-announced
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
        // Connection established
    }

    nonisolated func didDisconnect(relayUrl: String) {
        // Connection lost
    }

    private func handleEvent(_ event: Event) {
        // Ignore our own events
        guard event.pubkey != keyPair.publicKey else { return }

        let content = event.content
        let fromPeerId = String(event.pubkey.prefix(20))

        if let data = content.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

            // Check if it's a presence announcement (just {peerId: "..."})
            if let peerId = json["peerId"] as? String, json["type"] == nil {
                // Store mapping between internal peerId and Nostr pubkey
                peerIdToPubkey[peerId] = event.pubkey
                onPeerPresence?(peerId)
            }
            // Otherwise check for typed messages
            else if let type = json["type"] as? String {
                if type == "presence" {
                    if let peerId = json["peerId"] as? String {
                        // Store mapping for typed presence too
                        peerIdToPubkey[peerId] = event.pubkey
                        onPeerPresence?(peerId)
                    }
                } else if let signal = decodeSignal(from: json) {
                    onSignal?(signal, fromPeerId)
                }
            }
        }
    }

    private func encodeSignal(_ signal: Signal) -> String {
        var json: [String: Any] = ["type": signal.type.rawValue]

        switch signal.type {
        case .offer, .answer:
            json["sdp"] = signal.sdp
        case .candidate:
            json["candidate"] = signal.candidate
            json["sdpMid"] = signal.sdpMid
            json["sdpMLineIndex"] = signal.sdpMLineIndex
        case .bye:
            break
        }

        // We control the JSON structure, but be defensive
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let string = String(data: data, encoding: .utf8) else {
            // Fallback to empty signal if encoding fails
            return "{\"type\":\"\(signal.type.rawValue)\"}"
        }
        return string
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
