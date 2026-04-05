import Foundation

enum WSMessageType: String, Codable, Equatable {
    case sessions, sessionOpened, sessionClosed, output, resize, ping
    case attach, input, pong
}

struct WSMessage: Codable {
    let type: WSMessageType
    var sessions: [Session]? = nil
    var session: Session? = nil
    var sessionId: String? = nil
    var data: String? = nil
    var cols: Int? = nil
    var rows: Int? = nil

    static func attach(sessionId: SessionID) -> WSMessage {
        WSMessage(type: .attach, sessionId: sessionId.uuidString)
    }

    static func input(sessionId: SessionID, bytes: Data) -> WSMessage {
        WSMessage(type: .input, sessionId: sessionId.uuidString,
                  data: bytes.base64EncodedString())
    }

    static func resize(sessionId: SessionID, cols: Int, rows: Int) -> WSMessage {
        WSMessage(type: .resize, sessionId: sessionId.uuidString, cols: cols, rows: rows)
    }

    static func pong() -> WSMessage { WSMessage(type: .pong) }

    static func from(json: String) -> WSMessage? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(WSMessage.self, from: data)
    }

    func json() -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(self),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}
