import Testing
import Foundation
@testable import TermCast

@Suite("WebSocketServer", .serialized)
struct WebSocketServerTests {

    @Test("binds to preferred port when available")
    func bindsToPreferredPort() async throws {
        let server = WebSocketServer(
            preferredPort: 9681,
            jwtManager: JWTManager(secret: Data(repeating: 0, count: 32)),
            registry: SessionRegistry(),
            broadcaster: SessionBroadcaster()
        )
        let port = try await server.start()
        #expect(port == 9681)
        try await server.stop()
    }

    @Test("falls back to next port when preferred is occupied")
    func fallsBackWhenPreferredOccupied() async throws {
        let blocker = WebSocketServer(
            preferredPort: 9681,
            jwtManager: JWTManager(secret: Data(repeating: 0, count: 32)),
            registry: SessionRegistry(),
            broadcaster: SessionBroadcaster()
        )
        let firstPort = try await blocker.start()
        #expect(firstPort == 9681)

        let server = WebSocketServer(
            preferredPort: 9681,
            jwtManager: JWTManager(secret: Data(repeating: 0, count: 32)),
            registry: SessionRegistry(),
            broadcaster: SessionBroadcaster()
        )
        let secondPort = try await server.start()
        #expect(secondPort == 9682)

        try await blocker.stop()
        try await server.stop()
    }

    @Test("throws when all ports in range are occupied")
    func throwsWhenAllPortsOccupied() async throws {
        var blockers: [WebSocketServer] = []
        for port in 9690...9694 {
            let b = WebSocketServer(
                preferredPort: port,
                jwtManager: JWTManager(secret: Data(repeating: 0, count: 32)),
                registry: SessionRegistry(),
                broadcaster: SessionBroadcaster()
            )
            let bound = try await b.start()
            #expect(bound == port)
            blockers.append(b)
        }

        let server = WebSocketServer(
            preferredPort: 9690,
            jwtManager: JWTManager(secret: Data(repeating: 0, count: 32)),
            registry: SessionRegistry(),
            broadcaster: SessionBroadcaster()
        )
        await #expect(throws: WebSocketServerError.noPortAvailable) {
            _ = try await server.start()
        }

        for b in blockers { try await b.stop() }
    }
}
