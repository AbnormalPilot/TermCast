import Foundation

typealias SessionID = UUID

struct Session: Codable, Identifiable, Sendable, Hashable {
    let id: SessionID
    let pid: Int
    let tty: String
    let shell: String
    let termApp: String
    let outPipe: String
    var isActive: Bool
    var cols: Int
    var rows: Int

    enum CodingKeys: String, CodingKey {
        case id
        case pid
        case tty
        case shell
        case termApp = "term_app"
        case outPipe = "out_pipe"
        case isActive = "is_active"
        case cols
        case rows
    }
}
