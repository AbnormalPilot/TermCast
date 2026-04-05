// apps/ios/TermCastiOSTests/SessionStoreTests.swift
import Testing
import Foundation
@testable import TermCastiOS

@Suite("SessionStore", .serialized)
@MainActor
struct SessionStoreTests {
    func makeSession(id: UUID = UUID(), shell: String = "zsh") -> Session {
        Session(id: id, pid: 1, tty: "/dev/ttys001", shell: shell,
                termApp: "iTerm2", outPipe: "/tmp/test.out",
                isActive: true, cols: 80, rows: 24)
    }

    @Test("Initial state is empty")
    func initialStateIsEmpty() {
        let store = SessionStore()
        #expect(store.sessions.isEmpty)
        #expect(store.states.isEmpty)
    }

    @Test("apply(.sessions) populates session list")
    func applySessionsPopulates() {
        let store = SessionStore()
        let sessions = [makeSession(), makeSession()]
        store.apply(WSMessage(type: .sessions, sessions: sessions))
        #expect(store.sessions.count == 2)
    }

    @Test("apply(.sessions) marks all sessions active")
    func applySessionsMarksActive() {
        let store = SessionStore()
        let s = makeSession()
        store.apply(WSMessage(type: .sessions, sessions: [s]))
        #expect(store.state(for: s.id) == .active)
    }

    @Test("apply(.sessionOpened) appends new session")
    func applySessionOpenedAppends() {
        let store = SessionStore()
        let s = makeSession()
        store.apply(WSMessage(type: .sessionOpened, session: s))
        #expect(store.sessions.count == 1)
        #expect(store.state(for: s.id) == .active)
    }

    @Test("apply(.sessionOpened) is idempotent — duplicate is not added")
    func applySessionOpenedIdempotent() {
        let store = SessionStore()
        let s = makeSession()
        let msg = WSMessage(type: .sessionOpened, session: s)
        store.apply(msg)
        store.apply(msg)
        #expect(store.sessions.count == 1)
    }

    @Test("apply(.sessionClosed) marks session ended, does not remove")
    func applySessionClosedMarksEnded() {
        let store = SessionStore()
        let s = makeSession()
        store.apply(WSMessage(type: .sessions, sessions: [s]))
        store.apply(WSMessage(type: .sessionClosed, sessionId: s.id.uuidString))
        #expect(store.sessions.count == 1)
        #expect(store.state(for: s.id) == .ended)
    }

    @Test("state(for:) returns .ended for unknown id")
    func stateForUnknownIdReturnsEnded() {
        let store = SessionStore()
        #expect(store.state(for: UUID()) == .ended)
    }

    @Test("apply(.sessions) replaces previous list — immutable assignment")
    func applySessionsReplacesImmutably() {
        let store = SessionStore()
        let s1 = makeSession()
        let s2 = makeSession()
        store.apply(WSMessage(type: .sessions, sessions: [s1]))
        store.apply(WSMessage(type: .sessions, sessions: [s2]))
        #expect(store.sessions.count == 1)
        #expect(store.sessions.first?.id == s2.id)
    }

    @Test("apply ignores unrelated message types")
    func applyIgnoresUnrelatedTypes() {
        let store = SessionStore()
        store.apply(WSMessage(type: .ping))
        store.apply(WSMessage(type: .output, sessionId: UUID().uuidString, data: "aGVsbG8="))
        #expect(store.sessions.isEmpty)
    }

    @Test("apply(.sessionClosed) with unknown id is a no-op")
    func applySessionClosedUnknownIdIsNoop() {
        let store = SessionStore()
        let s = makeSession()
        store.apply(WSMessage(type: .sessions, sessions: [s]))
        store.apply(WSMessage(type: .sessionClosed, sessionId: UUID().uuidString))
        #expect(store.sessions.count == 1)
        #expect(store.state(for: s.id) == .active)
    }
}
