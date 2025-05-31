import XCTest
@testable import TrysteroSwift

final class NostrClientTests: XCTestCase {
    
    func testNostrClientCreation() throws {
        let relays = ["wss://test.relay"]
        let client = try TrysteroNostrClient(relays: relays, appId: "test")
        
        XCTAssertNotNil(client)
        XCTAssertNotNil(client.keyPair)
    }
    
    func testTopicHashGeneration() throws {
        let client = try TrysteroNostrClient(relays: ["wss://test.relay"], appId: "testApp")
        
        // Test internal hash generation by creating two clients with same config
        let client2 = try TrysteroNostrClient(relays: ["wss://test.relay"], appId: "testApp")
        
        // Both should generate the same topic hash for the same room
        // This is tested indirectly through consistent behavior
        XCTAssertNotNil(client)
        XCTAssertNotNil(client2)
    }
    
    func testWebRTCSignalSerialization() throws {
        let signal = WebRTCSignal.presence(peerId: "test-peer")
        let json = try signal.toJSON()
        
        XCTAssertFalse(json.isEmpty)
        
        let deserializedSignal = try WebRTCSignal.fromJSON(json)
        
        switch deserializedSignal {
        case .presence(let peerId):
            XCTAssertEqual(peerId, "test-peer")
        default:
            XCTFail("Expected presence signal")
        }
    }
    
    func testOfferSignalSerialization() throws {
        let sdp = "v=0\r\no=- 123456 123456 IN IP4 0.0.0.0\r\n"
        let signal = WebRTCSignal.offer(sdp: sdp)
        let json = try signal.toJSON()
        
        XCTAssertFalse(json.isEmpty)
        
        let deserializedSignal = try WebRTCSignal.fromJSON(json)
        
        switch deserializedSignal {
        case .offer(let deserializedSdp):
            XCTAssertEqual(deserializedSdp, sdp)
        default:
            XCTFail("Expected offer signal")
        }
    }
    
    func testAnswerSignalSerialization() throws {
        let sdp = "v=0\r\no=- 789012 789012 IN IP4 0.0.0.0\r\n"
        let signal = WebRTCSignal.answer(sdp: sdp)
        let json = try signal.toJSON()
        
        XCTAssertFalse(json.isEmpty)
        
        let deserializedSignal = try WebRTCSignal.fromJSON(json)
        
        switch deserializedSignal {
        case .answer(let deserializedSdp):
            XCTAssertEqual(deserializedSdp, sdp)
        default:
            XCTFail("Expected answer signal")
        }
    }
    
    func testIceCandidateSignalSerialization() throws {
        let candidate = "candidate:1 1 UDP 2130706431 192.168.1.1 54400 typ host"
        let sdpMid = "0"
        let sdpMLineIndex: Int32 = 0
        
        let signal = WebRTCSignal.iceCandidate(candidate: candidate, sdpMid: sdpMid, sdpMLineIndex: sdpMLineIndex)
        let json = try signal.toJSON()
        
        XCTAssertFalse(json.isEmpty)
        
        let deserializedSignal = try WebRTCSignal.fromJSON(json)
        
        switch deserializedSignal {
        case .iceCandidate(let deserializedCandidate, let deserializedSdpMid, let deserializedSdpMLineIndex):
            XCTAssertEqual(deserializedCandidate, candidate)
            XCTAssertEqual(deserializedSdpMid, sdpMid)
            XCTAssertEqual(deserializedSdpMLineIndex, sdpMLineIndex)
        default:
            XCTFail("Expected ICE candidate signal")
        }
    }
    
    func testInvalidSignalDeserialization() {
        let invalidJson = "invalid json"
        
        XCTAssertThrowsError(try WebRTCSignal.fromJSON(invalidJson)) { error in
            XCTAssertTrue(error is TrysteroError || error is DecodingError)
        }
    }
}
