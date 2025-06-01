import Foundation
@preconcurrency import WebRTC

/// Singleton WebRTC factory
enum WebRTCClient {
    private static let initializationQueue = DispatchQueue(label: "webrtc.init")
    
    static let factory: RTCPeerConnectionFactory = {
        initializationQueue.sync {
            RTCInitializeSSL()
            let videoEncoderFactory = RTCDefaultVideoEncoderFactory()
            let videoDecoderFactory = RTCDefaultVideoDecoderFactory()
            return RTCPeerConnectionFactory(
                encoderFactory: videoEncoderFactory,
                decoderFactory: videoDecoderFactory
            )
        }
    }()
}

// MARK: - Async/await extensions for WebRTC

extension RTCPeerConnection {
    func offer(for constraints: RTCMediaConstraints?) async throws -> RTCSessionDescription {
        return try await withCheckedThrowingContinuation { continuation in
            self.offer(for: constraints ?? RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { sdp, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let sdp = sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: NSError(domain: "WebRTC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create offer"]))
                }
            }
        }
    }
    
    func answer(for constraints: RTCMediaConstraints?) async throws -> RTCSessionDescription {
        return try await withCheckedThrowingContinuation { continuation in
            self.answer(for: constraints ?? RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)) { sdp, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let sdp = sdp {
                    continuation.resume(returning: sdp)
                } else {
                    continuation.resume(throwing: NSError(domain: "WebRTC", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create answer"]))
                }
            }
        }
    }
    
    func setLocalDescription(_ sdp: RTCSessionDescription) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.setLocalDescription(sdp) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func setRemoteDescription(_ sdp: RTCSessionDescription) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.setRemoteDescription(sdp) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
    
    func add(_ candidate: RTCIceCandidate) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            self.add(candidate) { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}