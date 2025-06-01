import XCTest
@testable import TrysteroSwift

/// Minimal integration test - verifies basic functionality
@MainActor
final class IntegrationTest: XCTestCase {

    /// Test basic room join/leave functionality
    func testRoomLifecycle() throws {
        let config = Config(appId: "test-app")
        let room = Trystero.joinRoom(config, "test-room")

        // Verify we can get peers (should be empty)
        XCTAssertEqual(room.getPeers().count, 0)

        // Verify we can create actions
        let (send, _) = room.makeAction("test")
        XCTAssertNotNil(send)

        // Clean up
        room.leave()
    }

    /// Test JavaScript interoperability
    func testJavaScriptInterop() async throws {
        // This test is run by CI with a JavaScript peer
        let roomId = ProcessInfo.processInfo.environment["INTEROP_ROOM_ID"] ?? "swift-js-test"
        let expectJS = ProcessInfo.processInfo.environment["EXPECT_JS_PEER"] == "true"

        print("🧪 Swift: Starting interop test")
        print("📍 Room ID: \(roomId)")
        print("⏳ Expecting JS peer: \(expectJS)")

        let config = Config(
            appId: "interop-test",
            relayUrls: [
                "wss://relay.nostr.band",
                "wss://nostr-pub.wellorder.net",
                "wss://relay.damus.io"
            ]
        )

        let room = Trystero.joinRoom(config, roomId)
        let (sendTest, onTest) = room.makeAction("test")

        if expectJS {
            // Wait for JS peer and exchange messages
            let connected = XCTestExpectation(description: "JS peer connected")
            let received = XCTestExpectation(description: "Received JS message")

            // Add a small delay to allow relay connections
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            print("🔄 Swift: Ready to connect")

            room.onPeerJoin { peerId in
                print("✅ Swift: Connected to peer \(peerId)")
                sendTest(["message": "Hello from Swift!"], peerId)
                connected.fulfill()
            }

            onTest { data, peerId in
                print("📥 Swift: Received from \(peerId): \(data)")
                received.fulfill()
            }

            await fulfillment(of: [connected, received], timeout: 60)
            print("✅ Swift: JavaScript interop successful")
        } else {
            // Just verify room works
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        room.leave()
    }
}
