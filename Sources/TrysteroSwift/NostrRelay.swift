import Foundation
import NostrClient
import Nostr

/// Handles Nostr relay communication for signaling
@MainActor
class NostrRelay: NostrClientDelegate {
    private let config: Config
    private let namespace: String
    private let selfId: String
    private let keyPair: KeyPair
    private var client: NostrClient
    private var subscriptions: Set<String> = []

    var onSignal: ((Signal, String) -> Void)?
    var onPeerPresence: ((String) -> Void)?

    init(config: Config, namespace: String, selfId: String) {
        self.config = config
        self.namespace = namespace
        self.selfId = selfId

        // Create a new keypair for this room
        do {
            self.keyPair = try KeyPair()
        } catch {
            fatalError("Failed to create Nostr keypair: \(error)")
        }

        self.client = NostrClient()
        self.client.delegate = self
    }

    func connect() async throws {
        let relays = selectRelays()

        // Add relays and connect
        for relay in relays {
            client.add(relayWithUrl: relay, subscriptions: [], autoConnect: true)
        }

        // Subscribe to room events
        subscribeToRoom()

        // Announce presence after a short delay to ensure connection
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
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
        let content = encodeSignal(signal)

        var event = Event(
            pubkey: keyPair.publicKey,
            createdAt: Timestamp(date: Date()),
            kind: .custom(29000), // Ephemeral event
            tags: [
                Tag(id: "t", otherInformation: "trystero-\(namespace)"),
                Tag(id: "p", otherInformation: peerId)
            ],
            content: content
        )

        try event.sign(with: keyPair)

        // Send event with callback
        await withCheckedContinuation { continuation in
            client.send(event: event) { _ in
                continuation.resume()
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
            kinds: [.custom(29000)],
            tags: [Tag(id: "t", otherInformation: "trystero-\(namespace)")]
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
            kind: .custom(29000),
            tags: [Tag(id: "t", otherInformation: "trystero-\(namespace)")],
            content: "{\"type\":\"presence\",\"peerId\":\"\(selfId)\"}"
        )

        do {
            try event.sign(with: keyPair)
            client.send(event: event) { _ in
                // Best effort - presence announcements can fail
            }
        } catch {
            // Non-fatal: presence will be re-announced
        }

        // Re-announce periodically
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            announcePresence()
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
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = json["type"] as? String {

            if type == "presence" {
                if let peerId = json["peerId"] as? String {
                    onPeerPresence?(peerId)
                }
            } else if let signal = decodeSignal(from: json) {
                onSignal?(signal, fromPeerId)
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
