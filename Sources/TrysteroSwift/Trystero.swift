import Foundation

public class Trystero {
    public static func joinRoom(config: RoomConfig, roomId: String) throws -> TrysteroRoom {
        let relays = config.relays ?? ["wss://relay.damus.io"]
        let appId = config.appId ?? ""
        return try TrysteroRoom(roomId: roomId, relays: relays, appId: appId)
    }
}

public struct RoomConfig {
    public let relays: [String]?
    public let password: String?
    public let appId: String?
    
    public init(relays: [String]? = nil, password: String? = nil, appId: String? = nil) {
        self.relays = relays
        self.password = password
        self.appId = appId
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
