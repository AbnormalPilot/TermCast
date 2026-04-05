import Testing
import Foundation
@testable import TermCast

@Suite("WSMessage")
struct WSMessageTests {
    @Test("ping factory produces type ping")
    func pingFactory() {
        let msg = WSMessage.ping()
        #expect(msg.type == .ping)
    }

    @Test("pong factory produces type pong")
    func pongFactory() {
        let msg = WSMessage.pong()
        #expect(msg.type == .pong)
    }

    @Test("sessionOpened embeds session")
    func sessionOpenedEmbedsSession() {
        let session = Session(pid: 1, tty: "/dev/ttys001", shell: "zsh",
                               termApp: "iTerm2", outPipe: "/tmp/1.out")
        let msg = WSMessage.sessionOpened(session)
        #expect(msg.type == .sessionOpened)
        #expect(msg.session?.shell == "zsh")
    }

    @Test("sessionClosed encodes UUID as string")
    func sessionClosedEncodesUUID() {
        let id = UUID()
        let msg = WSMessage.sessionClosed(id)
        #expect(msg.type == .sessionClosed)
        #expect(msg.sessionId == id.uuidString)
    }

    @Test("output encodes data as base64")
    func outputEncodesAsBase64() throws {
        let id = UUID()
        let data = Data([0x1b, 0x5b, 0x41])
        let msg = WSMessage.output(sessionId: id, data: data)
        #expect(msg.type == .output)
        let b64 = try #require(msg.data)
        let decoded = try #require(Data(base64Encoded: b64))
        #expect(decoded == data)
    }

    @Test("json() serializes with snake_case keys")
    func jsonSerializesSnakeCase() throws {
        let id = UUID()
        let msg = WSMessage.sessionClosed(id)
        let json = msg.json()
        #expect(json.contains("session_id"))
        #expect(!json.contains("sessionId"))
    }

    @Test("from(json:) round-trips ping")
    func fromJSONRoundTripsPing() throws {
        let json = #"{"type":"ping"}"#
        let msg = try #require(WSMessage.from(json: json))
        #expect(msg.type == .ping)
    }

    @Test("from(json:) returns nil for invalid JSON")
    func fromJSONReturnsNilForInvalidJSON() {
        #expect(WSMessage.from(json: "not json at all") == nil)
    }

    @Test("from(json:) returns nil for unknown type")
    func fromJSONReturnsNilForUnknownType() {
        let json = #"{"type":"unknown_future_type"}"#
        #expect(WSMessage.from(json: json) == nil)
    }

    @Test("output message JSON round-trip")
    func outputJSONRoundTrip() throws {
        let id = UUID()
        let data = Data("hello".utf8)
        let msg = WSMessage.output(sessionId: id, data: data)
        let json = msg.json()
        let decoded = try #require(WSMessage.from(json: json))
        #expect(decoded.type == .output)
        let b64 = try #require(decoded.data)
        let decodedData = try #require(Data(base64Encoded: b64))
        #expect(decodedData == data)
    }
}
