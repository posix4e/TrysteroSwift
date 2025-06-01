import Foundation
import NostrClient
import Nostr

/// Handles Nostr relay communication for signaling
class NostrRelay {
    private let config: Config
    private let namespace: String
    private let selfId: String
    private let keyPair: NostrKeypair
    private var client: NostrClient.Client?
    private var subscriptions: Set<String> = []
    
    var onSignal: ((Signal, String) -> Void)?
    var onPeerPresence: ((String) -> Void)?
    
    init(config: Config, namespace: String, selfId: String) {
        self.config = config
        self.namespace = namespace
        self.selfId = selfId
        self.keyPair = NostrKeypair()!
    }
    
    func connect() async throws {
        let relays = selectRelays()
        
        client = Client(keypair: keyPair)
        
        for relay in relays {
            try? await client?.connect(to: relay)
        }
        
        // Subscribe to room events
        await subscribeToRoom()
        
        // Announce presence
        await announcePresence()
    }
    
    func disconnect() {
        subscriptions.forEach { client?.unsubscribe(subscriptionId: $0) }
        subscriptions.removeAll()
        client?.disconnect()
        client = nil
    }
    
    func sendSignal(_ signal: Signal, to peerId: String) async throws {
        guard let client = client else { return }
        
        let content = encodeSignal(signal)
        let tags: [[String]] = [
            ["t", "trystero-\(namespace)"],
            ["p", peerId]
        ]
        
        let event = NostrEvent(
            keyPair: keyPair,
            kind: .custom(29000), // Ephemeral event
            content: content,
            tags: tags
        )
        
        try await client.publishEvent(event)
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
    
    private func subscribeToRoom() async {
        guard let client = client else { return }
        
        let filter = NostrFilter(
            kinds: [.custom(29000)],
            tags: ["t": ["trystero-\(namespace)"]]
        )
        
        let subId = UUID().uuidString
        subscriptions.insert(subId)
        
        client.subscribe(with: filter, subscriptionId: subId) { [weak self] event in
            self?.handleEvent(event)
        }
    }
    
    private func announcePresence() async {
        guard let client = client else { return }
        
        let event = NostrEvent(
            keyPair: keyPair,
            kind: .custom(29000),
            content: #"{"type":"presence","peerId":"\#(selfId)"}"#,
            tags: [["t", "trystero-\(namespace)"]]
        )
        
        try? await client.publishEvent(event)
        
        // Re-announce periodically
        Task {
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            await announcePresence()
        }
    }
    
    private func handleEvent(_ event: NostrEvent) {
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
        
        let data = try! JSONSerialization.data(withJSONObject: json)
        return String(data: data, encoding: .utf8)!
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