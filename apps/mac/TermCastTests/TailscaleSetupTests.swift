import Foundation
import Testing
@testable import TermCast

@Suite("TailscaleSetup")
struct TailscaleSetupTests {

    @Test("candidatePaths includes all known install locations")
    func candidatePathsComplete() {
        let paths = TailscaleSetup.candidatePaths
        #expect(paths.contains("/usr/local/bin/tailscale"))
        #expect(paths.contains("/opt/homebrew/bin/tailscale"))
        #expect(paths.contains("/Applications/Tailscale.app/Contents/MacOS/Tailscale"))
    }

    @Test("resolvePath returns nil when no candidate exists")
    func resolvePathNilWhenNoneExist() {
        let result = TailscaleSetup.resolvePath(checking: ["/nonexistent1", "/nonexistent2"])
        #expect(result == nil)
    }

    @Test("resolvePath returns first existing path")
    func resolvePathReturnsFirst() {
        // /usr/bin/env always exists on macOS — use it as a known sentinel
        let result = TailscaleSetup.resolvePath(checking: ["/nonexistent", "/usr/bin/env"])
        #expect(result == "/usr/bin/env")
    }

    @Test("resolvePath skips nonexistent paths before first hit")
    func resolvePathSkipsNonexistent() {
        let result = TailscaleSetup.resolvePath(checking: ["/nonexistent1", "/usr/bin/env", "/usr/bin/true"])
        #expect(result == "/usr/bin/env")
    }
}
