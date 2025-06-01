import Foundation

/// Errors that can occur in TrysteroSwift
public enum TrysteroError: LocalizedError {
    /// Attempted to use room before connecting
    case notConnected

    /// Failed to connect to any Nostr relays
    case noRelaysConnected

    /// WebRTC connection failed
    case webRTCConnectionFailed(String)

    /// Failed to create WebRTC offer/answer
    case webRTCSignalingFailed(String)

    /// Peer not found or disconnected
    case peerNotFound(String)

    /// Data channel not ready
    case dataChannelNotReady

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Room is not connected"
        case .noRelaysConnected:
            return "Failed to connect to any Nostr relays"
        case .webRTCConnectionFailed(let message):
            return "WebRTC connection failed: \(message)"
        case .webRTCSignalingFailed(let message):
            return "WebRTC signaling failed: \(message)"
        case .peerNotFound(let peerId):
            return "Peer not found: \(peerId)"
        case .dataChannelNotReady:
            return "Data channel is not ready"
        }
    }
}
