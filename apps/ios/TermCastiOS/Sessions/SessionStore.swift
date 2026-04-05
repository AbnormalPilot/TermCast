// apps/ios/TermCastiOS/Sessions/SessionStore.swift
import Foundation

enum SessionState {
    case active
    case ended   // session closed, history preserved for scroll
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published private(set) var states: [SessionID: SessionState] = [:]

    // MARK: - Updates from WebSocket messages

    func apply(_ message: WSMessage) {
        switch message.type {
        case .sessions:
            let newSessions = message.sessions ?? []
            sessions = newSessions
            states = newSessions.reduce(into: states) { $0[$1.id] = .active }

        case .sessionOpened:
            if let session = message.session {
                if !sessions.contains(where: { $0.id == session.id }) {
                    sessions = sessions + [session]
                }
                states = states.merging([session.id: .active]) { _, new in new }
            }

        case .sessionClosed:
            if let idStr = message.sessionId, let id = UUID(uuidString: idStr) {
                states = states.merging([id: .ended]) { _, new in new }
                // Don't remove — keep tab open for scroll history
            }

        default: break
        }
    }

    func state(for id: SessionID) -> SessionState {
        states[id] ?? .ended
    }
}
