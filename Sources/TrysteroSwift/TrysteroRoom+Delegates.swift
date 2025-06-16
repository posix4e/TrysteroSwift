import Foundation
@preconcurrency import WebRTC

// MARK: - RTCPeerConnectionDelegate
extension TrysteroRoom {
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("🔗 [Swift Debug] Signaling state changed: \(stateChanged)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        print("📺 [Swift Debug] Media stream added")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        print("📺 [Swift Debug] Media stream removed")
    }
    
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        print("🤝 [Swift Debug] Should negotiate")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        print("🧊 [Swift Debug] ICE connection state changed: \(newState)")
        
        // Find peer ID for this connection using safe lookup
        let peerId = getPeerId(for: peerConnection)
        
        switch newState {
        case .checking:
            if let peerId = peerId {
                print("🤝 [Swift Debug] Peer \(peerId) WebRTC connecting")
                webrtcConnectingHandler?(peerId)
            }
        case .connected, .completed:
            if let peerId = peerId {
                print("✅ [Swift Debug] Peer \(peerId) WebRTC connected")
                clearConnectionTimeout(for: peerId)
                webrtcConnectedHandler?(peerId)
                // Note: peerJoinHandler already called in handlePeerPresence
            }
        case .disconnected, .failed, .closed:
            if let peerId = peerId {
                print("❌ [Swift Debug] Peer \(peerId) WebRTC disconnected")
                webrtcDisconnectedHandler?(peerId)
                cleanupPeer(peerId)
            }
        default:
            break
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        print("🧊 [Swift Debug] ICE gathering state changed: \(newState)")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        print("🧊 [Swift Debug] Generated ICE candidate")
        
        let peerId = getPeerId(for: peerConnection)
        guard let targetPeer = peerId else { return }
        
        let signal = WebRTCSignal.iceCandidate(
            candidate: candidate.sdp,
            sdpMid: candidate.sdpMid,
            sdpMLineIndex: candidate.sdpMLineIndex
        )
        
        Task {
            do {
                try await nostrClient.publishSignal(signal, roomId: roomId, targetPeer: targetPeer)
                print("📤 [Swift Debug] Sent ICE candidate to \(targetPeer)")
            } catch {
                print("❌ [Swift Debug] Failed to send ICE candidate: \(error)")
            }
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        print("🧊 [Swift Debug] ICE candidates removed")
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        print("📡 [Swift Debug] Data channel opened: \(dataChannel.label)")
        
        let peerId = getPeerId(for: peerConnection)
        if let peerId = peerId {
            dataChannel.delegate = self
            dataChannels[peerId] = dataChannel
        }
    }
}

// MARK: - RTCDataChannelDelegate
extension TrysteroRoom {
    public func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        print("📡 [Swift Debug] Data channel state changed: \(dataChannel.readyState)")
    }
    
    public func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if let peerId = dataChannels.first(where: { $0.value === dataChannel })?.key {
            print("📥 [Swift Debug] Received data from \(String(peerId.prefix(8)))...")
            dataHandler?(buffer.data, peerId)
        } else {
            print("❌ [Swift Debug] Received data from unknown peer")
        }
    }
}
