import Foundation

struct ShellHookInstaller {
    static let hookDir = NSHomeDirectory() + "/.termcast"
    static let binDir = hookDir + "/bin"
    static let hookScriptPath = hookDir + "/hook.sh"
    static let fishHookPath = hookDir + "/hook.fish"

    private static let zshrcPath = NSHomeDirectory() + "/.zshrc"
    private static let bashrcPath = NSHomeDirectory() + "/.bashrc"
    private static let fishConfigPath = NSHomeDirectory() + "/.config/fish/config.fish"

    private static let hookLine = "[ -f ~/.termcast/hook.sh ] && source ~/.termcast/hook.sh"
    private static let fishHookLine = "if test -f ~/.termcast/hook.fish; source ~/.termcast/hook.fish; end"

    static func install() throws {
        try FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)
        try copyHookScript()
        try copyFishHookScript()
        try installHookBinary()
        injectIfNeeded(line: hookLine, into: zshrcPath)
        injectIfNeeded(line: hookLine, into: bashrcPath)
        injectIfNeeded(line: fishHookLine, into: fishConfigPath)
    }

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: hookScriptPath)
    }

    private static func copyHookScript() throws {
        guard let src = Bundle.main.path(forResource: "termcast", ofType: "sh") else {
            throw InstallError.resourceMissing("termcast.sh")
        }
        if FileManager.default.fileExists(atPath: hookScriptPath) {
            try FileManager.default.removeItem(atPath: hookScriptPath)
        }
        try FileManager.default.copyItem(atPath: src, toPath: hookScriptPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: hookScriptPath)
    }

    private static func copyFishHookScript() throws {
        guard let src = Bundle.main.path(forResource: "termcast", ofType: "fish") else { return }
        if FileManager.default.fileExists(atPath: fishHookPath) {
            try FileManager.default.removeItem(atPath: fishHookPath)
        }
        try FileManager.default.copyItem(atPath: src, toPath: fishHookPath)
    }

    private static func installHookBinary() throws {
        let dest = binDir + "/termcast-hook"
        guard let src = Bundle.main.path(forAuxiliaryExecutable: "termcast-hook") else {
            throw InstallError.resourceMissing("termcast-hook binary")
        }
        if FileManager.default.fileExists(atPath: dest) {
            try FileManager.default.removeItem(atPath: dest)
        }
        try FileManager.default.copyItem(atPath: src, toPath: dest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dest)
    }

    private static func injectIfNeeded(line: String, into path: String) {
        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        guard !content.contains("termcast") else { return }
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let newContent = content + "\n# TermCast shell integration\n\(line)\n"
        try? newContent.write(toFile: path, atomically: true, encoding: .utf8)
    }
}

enum InstallError: Error {
    case resourceMissing(String)
}
