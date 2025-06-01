import Foundation

public class Trystero {
    public static func joinRoom(config: RoomConfig, roomId: String) throws -> TrysteroRoom {
        let relays = config.getRelays()
        let appId = config.appId ?? ""
        return try TrysteroRoom(roomId: roomId, relays: relays, appId: appId)
    }
}

public struct RoomConfig {
    public let relays: [String]?
    public let password: String?
    public let appId: String?
    public let relayRedundancy: Int
    
    // Trystero.js compatible default relay list
    public static let defaultRelays = [
        "wss://eu.purplerelay.com",
        "wss://ftp.halifax.rwth-aachen.de/nostr",
        "wss://multiplexer.huszonegy.world",
        "wss://nostr.cool110.xyz",
        "wss://nostr.data.haus",
        "wss://nostr.grooveix.com",
        "wss://nostr.huszonegy.world",
        "wss://nostr.mom",
        "wss://nostr.sathoarder.com",
        "wss://nostr.vulpem.com",
        "wss://relay.fountain.fm",
        "wss://relay.nostraddress.com",
        "wss://relay.nostromo.social",
        "wss://relay.snort.social",
        "wss://relay.verified-nostr.com",
        "wss://yabu.me/v2"
    ]
    
    public init(relays: [String]? = nil, password: String? = nil, appId: String? = nil, relayRedundancy: Int = 5) {
        self.relays = relays
        self.password = password
        self.appId = appId
        self.relayRedundancy = relayRedundancy
    }
    
    // Get relays using Trystero.js compatible selection logic
    public func getRelays() -> [String] {
        if let customRelays = relays {
            return customRelays
        }
        
        // Use Trystero.js compatible relay selection
        let appId = self.appId ?? ""
        return Self.selectRelaysForAppId(appId, redundancy: relayRedundancy)
    }
    
    // Deterministic relay selection based on app ID (like Trystero.js)
    private static func selectRelaysForAppId(_ appId: String, redundancy: Int) -> [String] {
        let count = min(redundancy, defaultRelays.count)
        
        // Use app ID as seed for deterministic shuffle
        var generator = SeededRandomGenerator(seed: UInt64(appId.djb2hash))
        var shuffledRelays = defaultRelays
        shuffledRelays.shuffle(using: &generator)
        
        return Array(shuffledRelays.prefix(count))
    }
}

// Simple deterministic random number generator using app ID as seed
private struct SeededRandomGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed == 0 ? 1 : seed
    }
    
    mutating func next() -> UInt64 {
        state = state &* 1103515245 &+ 12345
        return state
    }
}

// DJB2 hash algorithm for string to int conversion
private extension String {
    var djb2hash: Int {
        let result = self.utf8.reduce(5381) { hash, byte in
            return ((hash << 5) &+ hash) &+ Int(byte)
        }
        return abs(result) // Ensure positive value for UInt64 conversion
    }
}

public extension TrysteroRoom {
    func onPeerJoin(_ handler: @escaping (String) -> Void) {
        self.peerJoinHandler = handler
    }
    
    func onPeerLeave(_ handler: @escaping (String) -> Void) {
        self.peerLeaveHandler = handler
    }
    
    func onData(_ handler: @escaping (Data, String) -> Void) {
        self.dataHandler = handler
    }
    
    func onWebRTCConnecting(_ handler: @escaping (String) -> Void) {
        self.webrtcConnectingHandler = handler
    }
    
    func onWebRTCConnected(_ handler: @escaping (String) -> Void) {
        self.webrtcConnectedHandler = handler
    }
    
    func onWebRTCDisconnected(_ handler: @escaping (String) -> Void) {
        self.webrtcDisconnectedHandler = handler
    }
    
    func getPeers() -> [String] {
        return Array(self.connectedPeers)
    }
    
    var ownPeerId: String {
        return self.nostrClient.keyPair.publicKey
    }
}
