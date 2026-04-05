import Testing
import Foundation
@testable import TermCast

@Suite("SessionRegistry")
struct SessionRegistryTests {
    @Test("Register and lookup session")
    func registerAndLookup() async {
        let registry = SessionRegistry()
        let reg = ShellRegistration(pid: 1, tty: "/dev/ttys001",
                                    shell: "zsh", term: "iTerm2",
                                    outPipe: "/tmp/tc-test-1.out")
        await registry.register(reg)
        let all = await registry.allSessions()
        #expect(all.count == 1)
        #expect(all.first?.shell == "zsh")
    }

    @Test("Remove session")
    func removeSession() async {
        let registry = SessionRegistry()
        let reg = ShellRegistration(pid: 2, tty: "/dev/ttys002",
                                    shell: "bash", term: "Terminal",
                                    outPipe: "/tmp/tc-test-2.out")
        await registry.register(reg)
        let sessions = await registry.allSessions()
        let id = try! #require(sessions.first).id
        await registry.remove(id: id)
        let remaining = await registry.allSessions()
        #expect(remaining.isEmpty)
    }

    @Test("Multiple sessions")
    func multipleSessions() async {
        let registry = SessionRegistry()
        for i in 0..<5 {
            let reg = ShellRegistration(pid: 100 + i, tty: "/dev/ttys00\(i)",
                                        shell: "zsh", term: "Warp",
                                        outPipe: "/tmp/tc-test-\(i).out")
            await registry.register(reg)
        }
        let all = await registry.allSessions()
        #expect(all.count == 5)
    }
}
