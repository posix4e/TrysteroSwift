import Foundation

public class Trystero {
    public static func joinRoom(config: RoomConfig, roomId: String) throws -> TrysteroRoom {
        let relays = config.relays ?? ["wss://relay.damus.io"]
        return try TrysteroRoom(roomId: roomId, relays: relays)
    }
}

public struct RoomConfig {
    public let relays: [String]?
    public let password: String?
    
    public init(relays: [String]? = nil, password: String? = nil) {
        self.relays = relays
        self.password = password
    }
}

public extension TrysteroRoom {
    func onPeerJoin(_ handler: @escaping (String) -> Void) {
        // Implementation for peer join events
    }
    
    func onPeerLeave(_ handler: @escaping (String) -> Void) {
        // Implementation for peer leave events
    }
    
    func onData(_ handler: @escaping (Data, String) -> Void) {
        // Implementation for data received events
    }
    
    func getPeers() -> [String] {
        return Array(self.peers.keys)
    }
}