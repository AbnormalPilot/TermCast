import Testing
import Foundation
@testable import TermCast

/// Tests the full path: shell registers → session appears in registry → ring buffer is empty on start.
@Suite("Integration")
struct IntegrationTests {
    @Test("Session registration flow")
    func sessionRegistrationFlow() async throws {
        let registry = SessionRegistry()
        let broadcaster = SessionBroadcaster()

        var openedSessions: [Session] = []
        await registry.setOnSessionAdded { openedSessions.append($0) }

        // Create a real named pipe so PTYSession can open it
        let tmpDir = "/tmp/termcast-test"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        let pipePath = "\(tmpDir)/\(Int.random(in: 10000..<99999)).out"
        if mkfifo(pipePath, 0o600) != 0 {
            // Pipe already exists from a previous run — clean up and retry
            try? FileManager.default.removeItem(atPath: pipePath)
            mkfifo(pipePath, 0o600)
        }
        defer { try? FileManager.default.removeItem(atPath: pipePath) }

        let reg = ShellRegistration(
            pid: Int(ProcessInfo.processInfo.processIdentifier),
            tty: "/dev/null",
            shell: "zsh",
            term: "TestTerminal",
            outPipe: pipePath
        )
        await registry.register(reg)

        // Give PTYSession a moment to start (it tries to open the pipe)
        try await Task.sleep(nanoseconds: 100_000_000)

        let sessions = await registry.allSessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.shell == "zsh")
        #expect(!openedSessions.isEmpty)

        // Ring buffer should be empty — no output has flowed yet
        guard let pty = await registry.session(id: sessions.first!.id) else {
            Issue.record("PTYSession not found in registry")
            return
        }
        let snapshot = await pty.bufferSnapshot()
        #expect(snapshot.isEmpty)

        // Broadcaster is wired correctly (no clients yet, but it should exist)
        let clientCount = await broadcaster.clientCount
        #expect(clientCount == 0)
    }
}
