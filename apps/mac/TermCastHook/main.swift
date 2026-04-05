import Foundation

// MARK: - Parse command-line arguments

var pid: Int = 0
var tty = ""
var shell = ""
var term = ""
var outPipe = ""

var args = CommandLine.arguments.dropFirst()
while let arg = args.first {
    args = args.dropFirst()
    switch arg {
    case "--pid":      pid = Int(args.first ?? "") ?? 0; args = args.dropFirst()
    case "--tty":      tty = args.first ?? ""; args = args.dropFirst()
    case "--shell":    shell = args.first ?? ""; args = args.dropFirst()
    case "--term":     term = args.first ?? ""; args = args.dropFirst()
    case "--out-pipe": outPipe = args.first ?? ""; args = args.dropFirst()
    default: break
    }
}

guard pid > 0, !tty.isEmpty, !outPipe.isEmpty else {
    fputs("termcast-hook: missing required arguments\n", stderr)
    exit(1)
}

// MARK: - Connect to agent Unix socket

let socketPath = NSHomeDirectory() + "/.termcast/agent.sock"
let sock = socket(AF_UNIX, SOCK_STREAM, 0)
guard sock >= 0 else { exit(0) }  // Agent not running — silent exit

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
withUnsafeMutableBytes(of: &addr.sun_path) { dest in
    socketPath.withCString { src in
        _ = strlcpy(dest.baseAddress!.assumingMemoryBound(to: CChar.self), src, dest.count)
    }
}

let connectResult = withUnsafePointer(to: &addr) { ptr in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}

guard connectResult == 0 else {
    close(sock)
    exit(0)  // Agent socket not available — silent exit
}

// MARK: - Send registration JSON

let registration: [String: Any] = [
    "pid": pid,
    "tty": tty,
    "shell": shell,
    "term": term,
    "outPipe": outPipe
]
if let data = try? JSONSerialization.data(withJSONObject: registration),
   var payload = String(data: data, encoding: .utf8) {
    payload += "\n"
    _ = payload.withCString { ptr in
        send(sock, ptr, strlen(ptr), 0)
    }
}

close(sock)
