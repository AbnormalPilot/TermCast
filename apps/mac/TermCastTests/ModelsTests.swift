import Foundation
import Testing
@testable import TermCast

@Suite("Models")
struct ModelsTests {
    @Test("Session has unique IDs and default 80x24 size")
    func sessionIsIdentifiable() {
        let s1 = Session(pid: 123, tty: "/dev/ttys003", shell: "zsh", termApp: "iTerm2", outPipe: "/tmp/termcast/123.out")
        let s2 = Session(pid: 456, tty: "/dev/ttys004", shell: "bash", termApp: "Terminal", outPipe: "/tmp/termcast/456.out")
        #expect(s1.id != s2.id)
        #expect(s1.cols == 80)
        #expect(s1.rows == 24)
    }

    @Test("WSMessage ping round-trips through JSON")
    func wsmessageJSONRoundTrip() throws {
        let msg = WSMessage.ping()
        let json = msg.json()
        let decoded = try #require(WSMessage.from(json: json))
        #expect(decoded.type == .ping)
    }

    @Test("Output message encodes data as base64")
    func outputMessageEncodesBase64() throws {
        let id = UUID()
        let data = Data([0x1b, 0x5b, 0x48])  // ESC[H
        let msg = WSMessage.output(sessionId: id, data: data)
        #expect(msg.sessionId == id.uuidString)
        let b64 = try #require(msg.data)
        let decoded = try #require(Data(base64Encoded: b64))
        #expect(decoded == data)
    }
}
