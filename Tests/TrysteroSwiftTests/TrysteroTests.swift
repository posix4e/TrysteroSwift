import XCTest
@testable import TrysteroSwift

final class TrysteroTests: XCTestCase {
    
    func testRoomCreation() throws {
        let config = RoomConfig(relays: ["wss://test.relay"], appId: "test")
        let room = try Trystero.joinRoom(config: config, roomId: "test-room")
        
        XCTAssertNotNil(room)
        XCTAssertEqual(room.getPeers().count, 0)
    }
    
    func testRoomConfigDefaults() throws {
        let config = RoomConfig()
        let room = try Trystero.joinRoom(config: config, roomId: "test-room")
        
        XCTAssertNotNil(room)
    }
    
    func testEventHandlerSetup() throws {
        let config = RoomConfig(relays: ["wss://test.relay"], appId: "test")
        let room = try Trystero.joinRoom(config: config, roomId: "test-room")
        
        var peerJoinCalled = false
        var peerLeaveCalled = false
        var dataCalled = false
        
        room.onPeerJoin { _ in peerJoinCalled = true }
        room.onPeerLeave { _ in peerLeaveCalled = true }
        room.onData { _, _ in dataCalled = true }
        
        // Handlers should be set but not called yet
        XCTAssertFalse(peerJoinCalled)
        XCTAssertFalse(peerLeaveCalled)
        XCTAssertFalse(dataCalled)
    }
    
    func testSendWithoutJoining() throws {
        let config = RoomConfig(relays: ["wss://test.relay"], appId: "test")
        let room = try Trystero.joinRoom(config: config, roomId: "test-room")
        
        let testData = Data("Hello".utf8)
        
        XCTAssertThrowsError(try room.send(testData)) { error in
            XCTAssertTrue(error is TrysteroError)
            XCTAssertEqual(error as? TrysteroError, .roomNotJoined)
        }
    }
}
