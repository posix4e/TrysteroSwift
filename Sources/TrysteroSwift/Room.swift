import Foundation
@preconcurrency import WebRTC

/// Room class matching Trystero.js room API
@MainActor
public class Room {
    private let namespace: String
    private let config: Config
    private let selfId: String
    private let nostr: NostrRelay
    private var peers: [String: Peer] = [:]
    private var actions: [String: Action] = [:]

    // Event handlers
    private var onPeerJoinHandler: ((String) -> Void)?
    private var onPeerLeaveHandler: ((String) -> Void)?
    private var onPeerStreamHandler: ((RTCMediaStream, String) -> Void)?

    public init(config: Config, namespace: String) {
        self.config = config
        self.namespace = namespace
        self.selfId = Self.generateId()
        self.nostr = NostrRelay(config: config, namespace: namespace, selfId: selfId)

        setupNostrHandlers()
    }

    /// Make an action (data channel) - matches Trystero.js API
    public func makeAction(_ type: String) -> (send: (Any, String?) -> Void, receive: (@escaping (Any, String) -> Void) -> Void) {
        let action = Action(type: type)
        actions[type] = action

        let send: (Any, String?) -> Void = { [weak self] data, peerId in
            self?.sendAction(type: type, data: data, to: peerId)
        }

        let receive: (@escaping (Any, String) -> Void) -> Void = { handler in
            action.handler = handler
        }

        return (send: send, receive: receive)
    }

    /// Register peer join handler
    public func onPeerJoin(_ handler: @escaping (String) -> Void) {
        onPeerJoinHandler = handler
    }

    /// Register peer leave handler
    public func onPeerLeave(_ handler: @escaping (String) -> Void) {
        onPeerLeaveHandler = handler
    }

    /// Register peer stream handler (for video/audio)
    public func onPeerStream(_ handler: @escaping (RTCMediaStream, String) -> Void) {
        onPeerStreamHandler = handler
    }

    /// Add media stream
    public func addStream(_ stream: RTCMediaStream) {
        for peer in peers.values {
            peer.addStream(stream)
        }
    }

    /// Remove media stream
    public func removeStream(_ stream: RTCMediaStream) {
        for peer in peers.values {
            peer.removeStream(stream)
        }
    }

    /// Get list of peer IDs
    public func getPeers() -> [String] {
        return Array(peers.keys)
    }

    /// Leave the room
    public func leave() {
        nostr.disconnect()
        for peer in peers.values {
            peer.close()
        }
        peers.removeAll()
        actions.removeAll()
    }

    // MARK: - Private methods

    private func setupNostrHandlers() {
        nostr.onSignal = { [weak self] signal, fromPeerId in
            self?.handleSignal(signal, from: fromPeerId)
        }

        nostr.onPeerPresence = { [weak self] peerId in
            self?.handlePeerPresence(peerId)
        }

        Task { @MainActor in
            do {
                try await nostr.connect()
            } catch {
                // Connection failures will be visible when trying to send
                // Room remains usable but won't connect to peers
            }
        }
    }

    private func handlePeerPresence(_ peerId: String) {
        guard peerId != selfId else { return }

        print("👥 Room: Handling peer presence for \(peerId), selfId: \(selfId)")

        if peers[peerId] == nil {
            let polite = selfId > peerId
            print("👥 Room: Creating new peer connection, polite: \(polite)")
            print("👥 Room: selfId=\(selfId), peerId=\(peerId), comparison: \(selfId) > \(peerId) = \(polite)")

            let peer = Peer(
                id: peerId,
                polite: polite,
                config: config.rtcConfig,
                onSignal: { [weak self] signal in
                    Task { @MainActor in
                        do {
                            print("📤 Room: Sending signal \(signal.type) to \(peerId)")
                            try self?.nostr.sendSignal(signal, to: peerId)
                        } catch {
                            print("❌ Room: Failed to send signal to \(peerId): \(error)")
                        }
                    }
                },
                onConnect: { [weak self] in
                    self?.handlePeerConnect(peerId)
                },
                onData: { [weak self] type, data in
                    self?.handlePeerData(peerId: peerId, type: type, data: data)
                },
                onStream: { [weak self] stream in
                    self?.onPeerStreamHandler?(stream, peerId)
                },
                onClose: { [weak self] in
                    self?.handlePeerLeave(peerId)
                }
            )

            peers[peerId] = peer
            // Only initiate if we're impolite (initiator)
            if !polite {
                peer.initiate()
            }
        } else {
            print("👥 Room: Peer \(peerId) already exists")
        }
    }

    private func handleSignal(_ signal: Signal, from peerId: String) {
        print("📥 Room: Received signal \(signal.type) from \(peerId)")

        if let peer = peers[peerId] {
            peer.handleSignal(signal)
        } else if signal.type != .bye {
            print("📥 Room: Creating peer for unknown sender \(peerId)")
            // When we receive an offer from an unknown peer, we are polite
            let polite = signal.type == .offer

            let peer = Peer(
                id: peerId,
                polite: polite,
                config: config.rtcConfig,
                onSignal: { [weak self] signal in
                    print("📤 Room: Sending signal \(signal.type) to \(peerId)")
                    do {
                        try self?.nostr.sendSignal(signal, to: peerId)
                    } catch {
                        print("❌ Room: Failed to send signal: \(error)")
                    }
                },
                onConnect: { [weak self] in
                    self?.handlePeerConnect(peerId)
                },
                onData: { [weak self] type, data in
                    self?.handlePeerData(peerId: peerId, type: type, data: data)
                },
                onStream: { [weak self] stream in
                    self?.onPeerStreamHandler?(stream, peerId)
                },
                onClose: { [weak self] in
                    self?.handlePeerLeave(peerId)
                }
            )

            peers[peerId] = peer
            // Don't call initiate() - we're responding to their offer
            peer.handleSignal(signal)
        }
    }

    private func handlePeerConnect(_ peerId: String) {
        print("✅ Room: Peer connected: \(peerId)")
        onPeerJoinHandler?(peerId)
    }

    private func handlePeerLeave(_ peerId: String) {
        print("🚪 Room: Peer left: \(peerId)")
        peers.removeValue(forKey: peerId)
        onPeerLeaveHandler?(peerId)
    }

    private func handlePeerData(peerId: String, type: String, data: Any) {
        actions[type]?.handler?(data, peerId)
    }

    private func sendAction(type: String, data: Any, to peerId: String?) {
        if let peerId = peerId {
            guard let peer = peers[peerId] else {
                // Silently ignore - peer may have disconnected
                return
            }
            peer.sendData(type: type, data: data)
        } else {
            // Broadcast to all peers
            for peer in peers.values {
                peer.sendData(type: type, data: data)
            }
        }
    }

    private static func generateId() -> String {
        return String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(20))
    }
}

// MARK: - Supporting Types

private class Action {
    let type: String
    var handler: ((Any, String) -> Void)?

    init(type: String) {
        self.type = type
    }
}
