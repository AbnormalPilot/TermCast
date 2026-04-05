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
}
