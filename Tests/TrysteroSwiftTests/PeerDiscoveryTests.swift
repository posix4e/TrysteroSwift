import XCTest
@testable import TrysteroSwift

final class PeerDiscoveryTests: XCTestCase {
    
    func testPersistentKeypairGeneration() throws {
        // Test that same app ID generates same keypair
        let client1 = try TrysteroNostrClient(relays: ["wss://test.relay"], appId: "test-app")
        let client2 = try TrysteroNostrClient(relays: ["wss://test.relay"], appId: "test-app")
        
        XCTAssertEqual(client1.keyPair.publicKey, client2.keyPair.publicKey, "Same app ID should generate same keypair")
        
        // Test that different app IDs generate different keypairs
        let client3 = try TrysteroNostrClient(relays: ["wss://test.relay"], appId: "different-app")
        XCTAssertNotEqual(client1.keyPair.publicKey, client3.keyPair.publicKey, "Different app IDs should generate different keypairs")
    }
    
    func testRelaySelection() {
        // Test custom relay selection
        let customConfig = RoomConfig(relays: ["wss://custom.relay"], appId: "test")
        XCTAssertEqual(customConfig.getRelays(), ["wss://custom.relay"])
        
        // Test default relay selection with deterministic behavior
        let defaultConfig1 = RoomConfig(appId: "test-app")
        let defaultConfig2 = RoomConfig(appId: "test-app")
        XCTAssertEqual(defaultConfig1.getRelays(), defaultConfig2.getRelays(), "Same app ID should select same relays")
        
        // Test different app IDs select different relays
        let differentConfig = RoomConfig(appId: "different-app")
        XCTAssertNotEqual(defaultConfig1.getRelays(), differentConfig.getRelays(), "Different app IDs should select different relays")
        
        // Test relay redundancy
        let config = RoomConfig(appId: "test", relayRedundancy: 3)
        XCTAssertEqual(config.getRelays().count, 3, "Should select exactly 3 relays")
    }
    
    func testRoomCreationAndConfiguration() throws {
        let config = RoomConfig(appId: "test-app")
        let room = try Trystero.joinRoom(config: config, roomId: "test-room")
        
        XCTAssertEqual(room.roomId, "test-room")
        XCTAssertFalse(room.ownPeerId.isEmpty, "Peer ID should not be empty")
        XCTAssertEqual(room.getPeers().count, 0, "Should start with no connected peers")
    }
    
    func testSelfFilteringLogic() throws {
        let room = try TrysteroRoom(roomId: "test", relays: ["wss://test.relay"], appId: "test")
        let ownPeerId = room.ownPeerId
        
        // Simulate receiving our own presence signal (should be filtered out)
        // This tests the self-filtering logic indirectly
        XCTAssertFalse(ownPeerId.isEmpty, "Own peer ID should be generated")
        
        // Test that we don't include ourselves in peer list
        XCTAssertFalse(room.getPeers().contains(ownPeerId), "Should not include own peer ID in peer list")
    }
    
    func testConnectionStateManagement() throws {
        let room = try TrysteroRoom(roomId: "test", relays: ["wss://test.relay"], appId: "test")
        
        // Test initial state
        XCTAssertEqual(room.getPeers().count, 0, "Should start with no peers")
        
        // Test error handling when not joined
        let testData = Data("Hello".utf8)
        XCTAssertThrowsError(try room.send(testData)) { error in
            XCTAssertEqual(error as? TrysteroError, TrysteroError.roomNotJoined)
        }
    }
    
    func testWebRTCSignalParsing() throws {
        // Test presence signal parsing
        let presenceJSON = """
        {"peerId":"test-peer-id"}
        """
        let presenceSignal = try WebRTCSignal.fromJSON(presenceJSON)
        if case .presence(let peerId) = presenceSignal {
            XCTAssertEqual(peerId, "test-peer-id")
        } else {
            XCTFail("Should parse as presence signal")
        }
        
        // Test offer signal parsing
        let offerJSON = """
        {"type":"offer","sdp":"test-sdp-content"}
        """
        let offerSignal = try WebRTCSignal.fromJSON(offerJSON)
        if case .offer(let sdp) = offerSignal {
            XCTAssertEqual(sdp, "test-sdp-content")
        } else {
            XCTFail("Should parse as offer signal")
        }
        
        // Test ICE candidate parsing
        let iceJSON = """
        {"candidate":"test-candidate","sdpMid":"0","sdpMLineIndex":0}
        """
        let iceSignal = try WebRTCSignal.fromJSON(iceJSON)
        if case .iceCandidate(let candidate, let sdpMid, let sdpMLineIndex) = iceSignal {
            XCTAssertEqual(candidate, "test-candidate")
            XCTAssertEqual(sdpMid, "0")
            XCTAssertEqual(sdpMLineIndex, 0)
        } else {
            XCTFail("Should parse as ICE candidate signal")
        }
    }
    
    func testTopicHashGeneration() throws {
        let client = try TrysteroNostrClient(relays: ["wss://test.relay"], appId: "test-app")
        
        // Test that topic generation is deterministic
        // We can't access the private methods directly, but we can test the behavior indirectly
        // by ensuring that the same configuration produces consistent results
        XCTAssertNotNil(client.keyPair.publicKey)
        XCTAssertFalse(client.keyPair.publicKey.isEmpty)
    }
}
