import XCTest
import WebRTC
@testable import TrysteroSwift

final class WebRTCManagerTests: XCTestCase {
    private var webRTCManager: WebRTCManager?
    
    override func setUp() {
        super.setUp()
        webRTCManager = WebRTCManager()
    }
    
    override func tearDown() {
        webRTCManager = nil
        super.tearDown()
    }
    
    func testPeerConnectionCreation() {
        let delegate = MockPeerConnectionDelegate()
        let peerConnection = webRTCManager?.createPeerConnection(delegate: delegate)
        
        XCTAssertNotNil(peerConnection)
        XCTAssertEqual(peerConnection?.signalingState, .stable)
    }
    
    func testDataChannelCreation() {
        let delegate = MockPeerConnectionDelegate()
        guard let webRTCManager = webRTCManager,
              let peerConnection = webRTCManager.createPeerConnection(delegate: delegate) else {
            XCTFail("Failed to create peer connection")
            return
        }
        
        let dataChannel = webRTCManager.createDataChannel(on: peerConnection, label: "test")
        
        XCTAssertNotNil(dataChannel)
        XCTAssertEqual(dataChannel?.label, "test")
    }
    
    func testOfferCreation() async throws {
        let delegate = MockPeerConnectionDelegate()
        guard let webRTCManager = webRTCManager,
              let peerConnection = webRTCManager.createPeerConnection(delegate: delegate) else {
            XCTFail("Failed to create peer connection")
            return
        }
        
        let offer = try await webRTCManager.createOffer(for: peerConnection)
        
        XCTAssertEqual(offer.type, .offer)
        XCTAssertFalse(offer.sdp.isEmpty)
    }
    
    func testAnswerCreation() async throws {
        let delegate = MockPeerConnectionDelegate()
        guard let webRTCManager = webRTCManager,
              let peerConnection = webRTCManager.createPeerConnection(delegate: delegate) else {
            XCTFail("Failed to create peer connection")
            return
        }
        
        // First create and set an offer
        let offer = try await webRTCManager.createOffer(for: peerConnection)
        try await webRTCManager.setRemoteDescription(offer, for: peerConnection)
        
        let answer = try await webRTCManager.createAnswer(for: peerConnection)
        
        XCTAssertEqual(answer.type, .answer)
        XCTAssertFalse(answer.sdp.isEmpty)
    }
    
    func testSetLocalDescription() async throws {
        let delegate = MockPeerConnectionDelegate()
        guard let webRTCManager = webRTCManager,
              let peerConnection = webRTCManager.createPeerConnection(delegate: delegate) else {
            XCTFail("Failed to create peer connection")
            return
        }
        
        let offer = try await webRTCManager.createOffer(for: peerConnection)
        try await webRTCManager.setLocalDescription(offer, for: peerConnection)
        
        XCTAssertEqual(peerConnection.localDescription?.type, .offer)
    }
    
    func testSetRemoteDescription() async throws {
        let delegate = MockPeerConnectionDelegate()
        guard let webRTCManager = webRTCManager,
              let peerConnection = webRTCManager.createPeerConnection(delegate: delegate) else {
            XCTFail("Failed to create peer connection")
            return
        }
        
        let offer = try await webRTCManager.createOffer(for: peerConnection)
        try await webRTCManager.setRemoteDescription(offer, for: peerConnection)
        
        XCTAssertEqual(peerConnection.remoteDescription?.type, .offer)
    }
}

// Mock delegate for testing
class MockPeerConnectionDelegate: NSObject, RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
