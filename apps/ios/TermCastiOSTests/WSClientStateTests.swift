import Foundation
import Testing
@testable import TermCastiOS

@Suite("WSClientState")
struct WSClientStateTests {

    @Test("initial state is disconnected")
    func initialStateIsDisconnected() {
        let client = WSClient()
        #expect(client.state == .disconnected)
    }

    @Test("state becomes connecting immediately after connect()")
    func connectTransitionsToConnecting() {
        let client = WSClient()
        // An obviously invalid host — connection will fail, but state is .connecting first
        client.connect(host: "invalid.host.termcast.test", secret: Data(repeating: 0, count: 32))
        #expect(client.state == .connecting)
        client.disconnect()
    }

    @Test("state becomes disconnected after disconnect()")
    func disconnectResetsState() {
        let client = WSClient()
        client.connect(host: "invalid.host.termcast.test", secret: Data(repeating: 0, count: 32))
        client.disconnect()
        #expect(client.state == .disconnected)
    }

    @Test("disconnect() state is disconnected, not authFailed")
    func disconnectDoesNotProduceAuthFailed() {
        let client = WSClient()
        client.connect(host: "invalid.host.termcast.test", secret: Data(repeating: 0, count: 32))
        client.disconnect()
        // After explicit disconnect, state MUST be .disconnected — never .authFailed
        #expect(client.state == .disconnected)
        #expect(client.state != .authFailed)
    }

    @Test("connect() cancels prior connection — state starts as connecting")
    func reconnectStartsFresh() {
        let client = WSClient()
        client.connect(host: "invalid.host.termcast.test", secret: Data(repeating: 0, count: 32))
        // Second connect() should teardown old and start fresh
        client.connect(host: "invalid.host.termcast.test", secret: Data(repeating: 0, count: 32))
        #expect(client.state == .connecting)
        client.disconnect()
    }
}
