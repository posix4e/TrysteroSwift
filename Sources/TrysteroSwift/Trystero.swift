import Foundation

/// Main entry point matching Trystero.js API
public enum Trystero {
    /// Join a room using Nostr strategy (matching trystero/nostr)
    public static func joinRoom(_ config: Config, _ namespace: String) -> Room {
        return Room(config: config, namespace: namespace)
    }
}

/// Configuration matching Trystero.js options
public struct Config {
    public let appId: String
    public var relayUrls: [String]?
    public var relayRedundancy: Int
    public var rtcConfig: RTCConfiguration?
    
    public init(
        appId: String,
        relayUrls: [String]? = nil,
        relayRedundancy: Int = 2,
        rtcConfig: RTCConfiguration? = nil
    ) {
        self.appId = appId
        self.relayUrls = relayUrls
        self.relayRedundancy = relayRedundancy
        self.rtcConfig = rtcConfig
    }
}

/// WebRTC configuration
public struct RTCConfiguration {
    public let iceServers: [IceServer]
    
    public init(iceServers: [IceServer] = IceServer.defaults) {
        self.iceServers = iceServers
    }
}

public struct IceServer {
    public let urls: [String]
    public let username: String?
    public let credential: String?
    
    public static let defaults = [
        IceServer(urls: ["stun:stun.l.google.com:19302"], username: nil, credential: nil)
    ]
    
    public init(urls: [String], username: String? = nil, credential: String? = nil) {
        self.urls = urls
        self.username = username
        self.credential = credential
    }
}