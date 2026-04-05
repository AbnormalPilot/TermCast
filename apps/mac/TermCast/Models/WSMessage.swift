import Foundation

enum WSMessageType: String, Codable, Equatable {
    // Server → Client
    case sessions, sessionOpened, sessionClosed, output, resize, ping
    // Client → Server
    case attach, input, pong
}

struct WSMessage: Codable {
    let type: WSMessageType
    var sessions: [Session]?
    var session: Session?
    var sessionId: String?
    var data: String?      // base64-encoded bytes
    var cols: Int?
    var rows: Int?

    // MARK: - Server → Client factories
    static func ping() -> WSMessage { WSMessage(type: .ping) }
    static func pong() -> WSMessage { WSMessage(type: .pong) }
    static func sessions(_ sessions: [Session]) -> WSMessage {
        WSMessage(type: .sessions, sessions: sessions)
    }
    static func sessionOpened(_ session: Session) -> WSMessage {
        WSMessage(type: .sessionOpened, session: session)
    }
    static func sessionClosed(_ id: SessionID) -> WSMessage {
        WSMessage(type: .sessionClosed, sessionId: id.uuidString)
    }
    static func output(sessionId: SessionID, data: Data) -> WSMessage {
        WSMessage(type: .output, sessionId: sessionId.uuidString,
                  data: data.base64EncodedString())
    }
    static func resize(sessionId: SessionID, cols: Int, rows: Int) -> WSMessage {
        WSMessage(type: .resize, sessionId: sessionId.uuidString, cols: cols, rows: rows)
    }

    // MARK: - Encoding
    func json() -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        guard let data = try? encoder.encode(self),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    static func from(json: String) -> WSMessage? {
        guard let data = json.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(WSMessage.self, from: data)
    }
}
