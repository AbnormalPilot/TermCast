import Foundation

typealias SessionID = UUID

struct Session: Codable, Identifiable, Sendable {
    let id: SessionID
    let pid: Int
    let tty: String       // e.g. "/dev/ttys003"
    let shell: String     // e.g. "zsh"
    let termApp: String   // e.g. "iTerm2"
    let outPipe: String   // path to named pipe for output capture
    var isActive: Bool
    var cols: Int
    var rows: Int

    init(pid: Int, tty: String, shell: String, termApp: String, outPipe: String) {
        self.id = UUID()
        self.pid = pid
        self.tty = tty
        self.shell = shell
        self.termApp = termApp
        self.outPipe = outPipe
        self.isActive = true
        self.cols = 80
        self.rows = 24
    }
}
