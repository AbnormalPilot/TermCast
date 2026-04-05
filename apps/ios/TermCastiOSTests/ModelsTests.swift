import Testing
import Foundation
@testable import TermCastiOS

@Suite("Models")
struct ModelsTests {
    @Test("Session decodes from server JSON")
    func sessionDecoding() throws {
        let json = """
        {"id":"550e8400-e29b-41d4-a716-446655440000","pid":123,"tty":"/dev/ttys003",
         "shell":"zsh","term_app":"iTerm2","out_pipe":"/tmp/test.out",
         "is_active":true,"cols":80,"rows":24}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let session = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        #expect(session.shell == "zsh")
        #expect(session.cols == 80)
    }

    @Test("WSMessage ping decodes")
    func wsmessagePingDecoding() {
        let json = #"{"type":"ping"}"#
        let msg = WSMessage.from(json: json)
        #expect(msg != nil)
        #expect(msg?.type == .ping)
    }

    @Test("WSMessage output has base64 data")
    func wsmessageOutputHasBase64() throws {
        let json = #"{"type":"output","session_id":"abc","data":"aGVsbG8="}"#
        let msg = try #require(WSMessage.from(json: json))
        #expect(msg.data == "aGVsbG8=")
    }
}
