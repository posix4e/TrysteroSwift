import Foundation
import NostrClient
import Nostr

class TrysteroNostrClient: NostrClientDelegate {
    private let client: NostrClient
    private let relays: [String]
    private let keyPair: KeyPair
    private var messageHandler: ((WebRTCSignal, String) -> Void)?
    
    init(relays: [String]) throws {
        self.relays = relays
        self.keyPair = try KeyPair()
        self.client = NostrClient()
        self.client.delegate = self
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
        let filter = Filter(
            kinds: [.custom(29000)],
            limit: 100
        )
        let subscription = Subscription(filters: [filter])
        client.add(subscriptions: [subscription])
    }
    
    func publishSignal(_ signal: WebRTCSignal, roomId: String, targetPeer: String?) async throws {
        let content = try signal.toJSON()
        var tags: [Tag] = [Tag(id: "h", otherInformation: "trystero-\(roomId)")]
        if let targetPeer = targetPeer {
            tags.append(Tag(id: "p", otherInformation: targetPeer))
        }
        
        var event = Event(
            pubkey: keyPair.publicKey,
            createdAt: Timestamp(date: Date()),
            kind: .custom(29000),
            tags: tags,
            content: content
        )
        
        try event.sign(with: keyPair)
        
        return try await withCheckedThrowingContinuation { continuation in
            client.send(event: event) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
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
            handleNostrEvent(event)
        case .notice(let notice):
            print("Nostr notice from \(relayUrl): \(notice)")
        default:
            break
        }
    }
    
    func didConnect(relayUrl: String) {
        print("Connected to Nostr relay: \(relayUrl)")
    }
    
    func didDisconnect(relayUrl: String) {
        print("Disconnected from Nostr relay: \(relayUrl)")
    }
    
    private func handleNostrEvent(_ event: Event) {
        guard event.kind == .custom(29000) else { return }
        
        do {
            let signal = try WebRTCSignal.fromJSON(event.content)
            messageHandler?(signal, event.pubkey)
        } catch {
            print("Failed to parse WebRTC signal: \(error)")
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
        return try JSONDecoder().decode(WebRTCSignal.self, from: data)
    }
}
