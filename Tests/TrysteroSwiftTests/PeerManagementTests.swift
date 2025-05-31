import XCTest
import Foundation
@testable import TrysteroSwift

final class PeerManagementTests: XCTestCase {
    private var room: TrysteroRoom?
    
    override func tearDown() async throws {
        if let room = room {
            await room.leave()
            self.room = nil
        }
    }
    
    /// Test that demonstrates peer tracking functionality that was missing before
    func testPeerTrackingAndEventHandlers() async throws {
        // This test would have FAILED before our fixes because:
        // 1. connectedPeers Set didn't exist
        // 2. peerJoinHandler was never called
        // 3. getPeers() returned WebRTC peers, not tracked peers
        
        let config = RoomConfig(relays: ["wss://relay.damus.io"], appId: "test")
        room = try Trystero.joinRoom(config: config, roomId: "peer-tracking-test")
        
        guard let room = self.room else {
            XCTFail("Failed to create room")
            return
        }
        
        // Track peer events
        var joinedPeers: [String] = []
        var leftPeers: [String] = []
        
        room.onPeerJoin { peerId in
            joinedPeers.append(peerId)
        }
        
        room.onPeerLeave { peerId in
            leftPeers.append(peerId)
        }
        
        // Initially no peers
        XCTAssertEqual(room.getPeers().count, 0, "Should start with no peers")
        XCTAssertTrue(joinedPeers.isEmpty, "No join events should have fired yet")
        
        // Simulate peer presence (this is what happens when another client connects)
        let mockPeerId = "mock-peer-12345"
        await room.simulatePeerPresence(mockPeerId)
        
        // Verify peer was tracked
        XCTAssertEqual(room.getPeers().count, 1, "Should have 1 tracked peer")
        XCTAssertTrue(room.getPeers().contains(mockPeerId), "Should contain the mock peer")
        XCTAssertEqual(joinedPeers.count, 1, "Should have fired 1 join event")
        XCTAssertEqual(joinedPeers.first, mockPeerId, "Join event should contain correct peer ID")
        
        // Simulate peer leaving
        room.simulatePeerDisconnect(mockPeerId)
        
        // Verify peer was removed
        XCTAssertEqual(room.getPeers().count, 0, "Should have 0 peers after disconnect")
        XCTAssertFalse(room.getPeers().contains(mockPeerId), "Should not contain the mock peer")
        XCTAssertEqual(leftPeers.count, 1, "Should have fired 1 leave event")
        XCTAssertEqual(leftPeers.first, mockPeerId, "Leave event should contain correct peer ID")
    }
    
    /// Test that demonstrates data sending validation that was missing before
    func testDataSendingValidation() async throws {
        // This test would have FAILED before our fixes because:
        // 1. sendToPeer didn't check if peer was actually connected
        // 2. No validation of data channel state
        
        let config = RoomConfig(relays: ["wss://relay.damus.io"], appId: "test")
        room = try Trystero.joinRoom(config: config, roomId: "data-validation-test")
        
        guard let room = self.room else {
            XCTFail("Failed to create room")
            return
        }
        
        // Join the room first
        try await room.join()
        
        let testData = Data("Hello World".utf8)
        let fakePeerId = "non-existent-peer"
        
        // Try to send to non-existent peer - should throw error
        XCTAssertThrowsError(try room.send(testData, to: fakePeerId)) { error in
            XCTAssertEqual(error as? TrysteroError, TrysteroError.peerNotConnected)
        }
        
        // Add a peer but don't establish data channel
        await room.simulatePeerPresence(fakePeerId)
        
        // Should still fail because no data channel is ready
        XCTAssertThrowsError(try room.send(testData, to: fakePeerId)) { error in
            XCTAssertEqual(error as? TrysteroError, TrysteroError.peerNotConnected)
        }
    }
    
    /// Test that demonstrates proper cleanup that was missing before
    func testPeerCleanupOnDisconnect() async throws {
        // This test would have FAILED before our fixes because:
        // 1. cleanupPeer() function didn't exist
        // 2. Manual cleanup in multiple places was inconsistent
        // 3. connectedPeers wasn't updated on disconnect
        
        let config = RoomConfig(relays: ["wss://relay.damus.io"], appId: "test")
        room = try Trystero.joinRoom(config: config, roomId: "cleanup-test")
        
        guard let room = self.room else {
            XCTFail("Failed to create room")
            return
        }
        
        var peerEvents: [(String, String)] = [] // (action, peerId)
        
        room.onPeerJoin { peerId in
            peerEvents.append(("join", peerId))
        }
        
        room.onPeerLeave { peerId in
            peerEvents.append(("leave", peerId))
        }
        
        // Add multiple peers
        let peer1 = "peer-1"
        let peer2 = "peer-2"
        
        await room.simulatePeerPresence(peer1)
        await room.simulatePeerPresence(peer2)
        
        // Verify both peers are tracked
        XCTAssertEqual(room.getPeers().count, 2)
        XCTAssertEqual(peerEvents.count, 2)
        
        // Disconnect one peer
        room.simulatePeerDisconnect(peer1)
        
        // Verify proper cleanup
        XCTAssertEqual(room.getPeers().count, 1, "Should have 1 peer remaining")
        XCTAssertFalse(room.getPeers().contains(peer1), "Disconnected peer should be removed")
        XCTAssertTrue(room.getPeers().contains(peer2), "Other peer should remain")
        XCTAssertEqual(peerEvents.count, 3, "Should have 2 joins + 1 leave")
        XCTAssertEqual(peerEvents.last?.0, "leave", "Last event should be leave")
        XCTAssertEqual(peerEvents.last?.1, peer1, "Leave event should be for correct peer")
    }
}

// MARK: - Test Helper Extensions
extension TrysteroRoom {
    /// Simulate peer presence for testing (mimics what happens when real peer connects)
    func simulatePeerPresence(_ peerId: String) async {
        // Add to tracking
        connectedPeers.insert(peerId)
        
        // Fire the join handler (this is what was missing before)
        peerJoinHandler?(peerId)
    }
    
    /// Simulate peer disconnect for testing
    func simulatePeerDisconnect(_ peerId: String) {
        // Use the new cleanup function (this didn't exist before)
        cleanupPeer(peerId)
    }
}
