import Foundation
import Darwin.sys.proc_info

struct ProcessInspector {
    private static let knownTerminals = [
        "iTerm2", "Terminal", "Warp", "Alacritty",
        "kitty", "Code", "Code Helper", "Hyper"
    ]

    /// Returns the process name for a given PID.
    static func processName(of pid: Int) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        proc_name(Int32(pid), &buffer, UInt32(buffer.count))
        return String(cString: buffer)
    }

    /// Returns the parent PID of a given PID, or nil if unavailable.
    static func parentPID(of pid: Int) -> Int? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = proc_pidinfo(Int32(pid), PROC_PIDTBSDINFO, 0, &info, size)
        guard result == size else { return nil }
        let ppid = Int(info.pbi_ppid)
        return ppid > 0 ? ppid : nil
    }

    /// Walks the parent chain (up to 8 hops) to find a known terminal emulator.
    static func terminalApp(forPID pid: Int) -> String {
        var current = pid
        for _ in 0..<8 {
            let name = processName(of: current)
            if knownTerminals.contains(where: { name.contains($0) }) { return name }
            guard let parent = parentPID(of: current) else { break }
            if parent == current || parent <= 1 { break }
            current = parent
        }
        return "Unknown"
    }
}
