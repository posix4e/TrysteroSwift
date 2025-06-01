import Foundation
@preconcurrency import WebRTC

/// Main entry point matching Trystero.js API
public enum Trystero {
    /// Join a room using Nostr strategy (matching trystero/nostr)
    @MainActor
    public static func joinRoom(_ config: Config, _ namespace: String) -> Room {
        return Room(config: config, namespace: namespace)
    }
}

/// Configuration matching Trystero.js options
public struct Config {
    public let appId: String
    public var relayUrls: [String]?
    public var relayRedundancy: Int
    public var rtcConfig: TrysteroRTCConfiguration?

    public init(
        appId: String,
        relayUrls: [String]? = nil,
        relayRedundancy: Int = 2,
        rtcConfig: TrysteroRTCConfiguration? = nil
    ) {
        self.appId = appId
        self.relayUrls = relayUrls
        self.relayRedundancy = relayRedundancy
        self.rtcConfig = rtcConfig
    }
}

/// WebRTC configuration wrapper to avoid naming conflicts
public struct TrysteroRTCConfiguration: Sendable {
    public let iceServers: [TrysteroIceServer]

    public init(iceServers: [TrysteroIceServer] = TrysteroIceServer.defaults) {
        self.iceServers = iceServers
    }
}

public struct TrysteroIceServer: Sendable {
    public let urls: [String]
    public let username: String?
    public let credential: String?

    public static let defaults = [
        TrysteroIceServer(urls: ["stun:stun.l.google.com:19302"], username: nil, credential: nil)
    ]

    public init(urls: [String], username: String? = nil, credential: String? = nil) {
        self.urls = urls
        self.username = username
        self.credential = credential
    }
}
