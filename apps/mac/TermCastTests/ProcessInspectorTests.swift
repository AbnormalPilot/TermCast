import Testing
import Foundation
@testable import TermCast

@Suite("ProcessInspector")
struct ProcessInspectorTests {
    @Test("Current process has a non-empty name")
    func currentProcessHasName() {
        let name = ProcessInspector.processName(of: Int(ProcessInfo.processInfo.processIdentifier))
        #expect(!name.isEmpty)
    }

    @Test("Current process has a valid parent PID")
    func parentPIDExists() {
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        let ppid = ProcessInspector.parentPID(of: pid)
        #expect(ppid != nil)
        #expect((ppid ?? 0) > 0)
    }

    @Test("Unknown PID returns nil parent")
    func unknownPIDReturnsNil() {
        #expect(ProcessInspector.parentPID(of: 9_999_999) == nil)
    }

    @Test("Terminal app lookup returns non-empty string")
    func terminalAppFromCurrentProcess() {
        // Running inside Xcode test runner — walks up to find Xcode or returns "Unknown"
        let pid = Int(ProcessInfo.processInfo.processIdentifier)
        let app = ProcessInspector.terminalApp(forPID: pid)
        #expect(!app.isEmpty)
    }
}
