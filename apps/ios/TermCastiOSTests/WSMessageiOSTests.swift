// apps/ios/TermCastiOSTests/WSMessageiOSTests.swift
import Testing
import Foundation
@testable import TermCastiOS

@Suite("WSMessage iOS")
struct WSMessageiOSTests {
    @Test("attach factory sets sessionId")
    func attachFactory() {
        let id = UUID()
        let msg = WSMessage.attach(sessionId: id)
        #expect(msg.type == .attach)
        #expect(msg.sessionId == id.uuidString)
    }

    @Test("input factory encodes data as base64")
    func inputFactory() throws {
        let id = UUID()
        let bytes = Data([0x03])
        let msg = WSMessage.input(sessionId: id, bytes: bytes)
        #expect(msg.type == .input)
        let b64 = try #require(msg.data)
        #expect(Data(base64Encoded: b64) == bytes)
    }

    @Test("resize factory stores cols and rows")
    func resizeFactory() {
        let id = UUID()
        let msg = WSMessage.resize(sessionId: id, cols: 120, rows: 40)
        #expect(msg.type == .resize)
        #expect(msg.cols == 120)
        #expect(msg.rows == 40)
    }

    @Test("pong factory produces type pong")
    func pongFactory() {
        let msg = WSMessage.pong()
        #expect(msg.type == .pong)
    }

    @Test("json() uses snake_case for sessionId")
    func jsonUsesSnakeCase() {
        let msg = WSMessage.attach(sessionId: UUID())
        let json = msg.json()
        #expect(json.contains("session_id"))
        #expect(!json.contains("sessionId"))
    }

    @Test("from(json:) returns nil for empty string")
    func fromJSONEmptyStringReturnsNil() {
        #expect(WSMessage.from(json: "") == nil)
    }

    @Test("from(json:) returns nil for malformed JSON")
    func fromJSONMalformedReturnsNil() {
        #expect(WSMessage.from(json: "{bad json}") == nil)
    }

    @Test("from(json:) decodes sessions array")
    func fromJSONDecodesSessions() throws {
        let json = """
        {"type":"sessions","sessions":[
          {"id":"550e8400-e29b-41d4-a716-446655440000","pid":1,"tty":"/dev/ttys001",
           "shell":"zsh","term_app":"iTerm2","out_pipe":"/tmp/1.out",
           "is_active":true,"cols":80,"rows":24}
        ]}
        """
        let msg = try #require(WSMessage.from(json: json))
        #expect(msg.type == .sessions)
        #expect(msg.sessions?.count == 1)
        #expect(msg.sessions?.first?.shell == "zsh")
    }

    @Test("from(json:) returns nil for unknown message type")
    func fromJSONUnknownTypeReturnsNil() {
        let json = #"{"type":"unknown_future_type"}"#
        #expect(WSMessage.from(json: json) == nil)
    }

    @Test("ping memberwise init round-trips via json")
    func pingRoundTrip() throws {
        let msg = WSMessage(type: .ping)
        let json = msg.json()
        let decoded = try #require(WSMessage.from(json: json))
        #expect(decoded.type == .ping)
    }

    @Test("attach message encodes sessionId correctly")
    func attachMessageEncodesSessionId() {
        let id = UUID(uuidString: "AABBCCDD-1234-5678-ABCD-000000000001")!
        let msg = WSMessage.attach(sessionId: id)
        #expect(msg.type == .attach)
        #expect(msg.sessionId == "AABBCCDD-1234-5678-ABCD-000000000001")
        let json = msg.json()
        #expect(json.contains("\"attach\""))
        #expect(json.contains("AABBCCDD-1234-5678-ABCD-000000000001"))
    }
}
