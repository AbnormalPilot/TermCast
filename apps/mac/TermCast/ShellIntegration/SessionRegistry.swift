import Foundation

/// Source of truth for all active terminal sessions.
actor SessionRegistry {
    private var sessions: [SessionID: PTYSession] = [:]

    var onSessionAdded: (@Sendable (Session) -> Void)?
    var onSessionRemoved: (@Sendable (SessionID) -> Void)?

    func setOnSessionAdded(_ handler: @escaping @Sendable (Session) -> Void) {
        onSessionAdded = handler
    }

    func setOnSessionRemoved(_ handler: @escaping @Sendable (SessionID) -> Void) {
        onSessionRemoved = handler
    }

    func register(_ reg: ShellRegistration) {
        let session = Session(
            pid: reg.pid,
            tty: reg.tty,
            shell: reg.shell,
            termApp: ProcessInspector.terminalApp(forPID: reg.pid),
            outPipe: reg.outPipe
        )
        let ptySession = PTYSession(session: session)
        let sessionId = session.id

        Task { [weak self] in
            await ptySession.setOnClose {
                Task { await self?.remove(id: sessionId) }
            }
            await ptySession.start()
        }

        sessions[session.id] = ptySession
        onSessionAdded?(session)
    }

    func remove(id: SessionID) {
        guard let pty = sessions.removeValue(forKey: id) else { return }
        Task { await pty.stop() }
        onSessionRemoved?(id)
    }

    func allSessions() -> [Session] {
        sessions.values.map { $0.session }
    }

    func session(id: SessionID) -> PTYSession? {
        sessions[id]
    }

    func setOutputHandler(_ handler: @escaping @Sendable (SessionID, Data) -> Void) {
        for (id, pty) in sessions {
            let sessionId = id
            Task {
                await pty.setOnOutput { data in handler(sessionId, data) }
            }
        }
    }
}
