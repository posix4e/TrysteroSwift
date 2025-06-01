import Foundation
@preconcurrency import WebRTC

// MARK: - RTCPeerConnectionDelegate
extension TrysteroRoom {
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        Task { @MainActor in
            print("🔗 [Swift Debug] Signaling state changed: \(stateChanged)")
        }
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
        Task { @MainActor in
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
                    
                    // Check data channel state when ICE connects
                    if let dataChannel = dataChannels[peerId] {
                        print("📡 [Swift Debug] Data channel state for \(peerId) when ICE connected: \(dataChannel.readyState)")
                    } else {
                        print("📡 [Swift Debug] No data channel found for \(peerId) when ICE connected")
                    }
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
        
        Task { @MainActor in
            do {
                let targetPubkey = peerIdToPubkey[targetPeer] ?? targetPeer
                try await nostrClient.publishSignal(signal, roomId: roomId, targetPeer: targetPubkey)
                print("📤 [Swift Debug] Sent ICE candidate to \(targetPeer) (pubkey: \(targetPubkey))")
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
        Task { @MainActor in
            let peerId = dataChannels.first(where: { $0.value === dataChannel })?.key ?? "unknown"
            print("📡 [Swift Debug] Data channel (\(peerId)) state changed: \(dataChannel.readyState)")
            
            if dataChannel.readyState == .open {
                print("🎉 [Swift Debug] Data channel for \(peerId) is now OPEN - ready for messaging!")
                
                // Send a test message immediately when channel opens
                let testMessage = Data("Hello from Swift - channel opened!".utf8)
                let buffer = RTCDataBuffer(data: testMessage, isBinary: false)
                dataChannel.sendData(buffer)
                print("📤 [Swift Debug] Sent test message on newly opened channel to \(peerId)")
            }
        }
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
