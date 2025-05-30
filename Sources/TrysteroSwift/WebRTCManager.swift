import Foundation
import WebRTC

class WebRTCManager: NSObject {
    private let peerConnectionFactory: RTCPeerConnectionFactory
    private let configuration: RTCConfiguration
    
    override init() {
        RTCInitializeSSL()
        
        let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
        let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
        
        self.peerConnectionFactory = RTCPeerConnectionFactory(
            encoderFactory: videoEncoderFactory,
            decoderFactory: videoDecoderFactory
        )
        
        self.configuration = RTCConfiguration()
        configuration.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"]),
            RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"])
        ]
        configuration.sdpSemantics = .unifiedPlan
        
        super.init()
    }
    
    func createPeerConnection(delegate: RTCPeerConnectionDelegate) -> RTCPeerConnection? {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]
        )
        
        return peerConnectionFactory.peerConnection(
            with: configuration,
            constraints: constraints,
            delegate: delegate
        )
    }
    
    func createDataChannel(on peerConnection: RTCPeerConnection, label: String) -> RTCDataChannel? {
        let config = RTCDataChannelConfiguration()
        config.isOrdered = true
        
        return peerConnection.dataChannel(forLabel: label, configuration: config)
    }
    
    func createOffer(for peerConnection: RTCPeerConnection) async throws -> RTCSessionDescription {
        return try await withCheckedThrowingContinuation { continuation in
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            
            peerConnection.offer(for: constraints) { sdp, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let sdp = sdp {
                    let newSdp = RTCSessionDescription(type: sdp.type, sdp: sdp.sdp)
                    continuation.resume(returning: newSdp)
                } else {
                    continuation.resume(throwing: TrysteroError.connectionFailed)
                }
            }
        }
    }
    
    func createAnswer(for peerConnection: RTCPeerConnection) async throws -> RTCSessionDescription {
        return try await withCheckedThrowingContinuation { continuation in
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            
            peerConnection.answer(for: constraints) { sdp, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let sdp = sdp {
                    let newSdp = RTCSessionDescription(type: sdp.type, sdp: sdp.sdp)
                    continuation.resume(returning: newSdp)
                } else {
                    continuation.resume(throwing: TrysteroError.connectionFailed)
                }
            }
        }
    }
    
    func setLocalDescription(_ sdp: RTCSessionDescription, for peerConnection: RTCPeerConnection) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.setLocalDescription(sdp) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
    
    func setRemoteDescription(_ sdp: RTCSessionDescription, for peerConnection: RTCPeerConnection) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            peerConnection.setRemoteDescription(sdp) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
    
    deinit {
        RTCCleanupSSL()
    }
}