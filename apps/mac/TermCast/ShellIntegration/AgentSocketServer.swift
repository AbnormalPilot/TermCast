import Foundation
import NIOCore
import NIOPosix

struct ShellRegistration: Sendable {
    let pid: Int
    let tty: String
    let shell: String
    let term: String
    let outPipe: String
}

actor AgentSocketServer {
    private let socketPath: String
    private let onRegister: @Sendable (ShellRegistration) async -> Void
    private var serverChannel: (any Channel)?

    init(socketPath: String, onRegister: @Sendable @escaping (ShellRegistration) async -> Void) {
        self.socketPath = socketPath
        self.onRegister = onRegister
    }

    func start(group: MultiThreadedEventLoopGroup) async throws {
        // Remove stale socket file
        try? FileManager.default.removeItem(atPath: socketPath)

        // Ensure ~/.termcast directory exists
        let dir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let onReg = onRegister
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 32)
            .childChannelInitializer { channel in
                channel.pipeline.addHandlers([
                    ByteToMessageHandler(NewlineFrameDecoder()),
                    RegistrationHandler(onRegister: onReg)
                ])
            }

        serverChannel = try await bootstrap
            .bind(unixDomainSocketPath: socketPath)
            .get()

        // Set socket permissions so only owner can connect
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: socketPath
        )
    }

    func stop() async throws {
        try await serverChannel?.close().get()
        try? FileManager.default.removeItem(atPath: socketPath)
    }
}

// MARK: - Newline frame decoder (splits incoming bytes at '\n')

private struct NewlineFrameDecoder: ByteToMessageDecoder {
    typealias InboundOut = ByteBuffer

    mutating func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        // Look for a newline byte
        let bytes = buffer.withUnsafeReadableBytes { $0 }
        guard let newlineIndex = bytes.firstIndex(of: UInt8(ascii: "\n")) else {
            return .needMoreData
        }
        let length = newlineIndex - bytes.startIndex + 1
        if let slice = buffer.readSlice(length: length) {
            context.fireChannelRead(wrapInboundOut(slice))
        }
        return .continue
    }

    mutating func decodeLast(
        context: ChannelHandlerContext,
        buffer: inout ByteBuffer,
        seenEOF: Bool
    ) throws -> DecodingState {
        // Flush any remaining bytes as a final frame (no trailing newline)
        if buffer.readableBytes > 0, let slice = buffer.readSlice(length: buffer.readableBytes) {
            context.fireChannelRead(wrapInboundOut(slice))
        }
        return .needMoreData
    }
}

// MARK: - Line-based registration handler

private final class RegistrationHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let onRegister: @Sendable (ShellRegistration) async -> Void

    init(onRegister: @Sendable @escaping (ShellRegistration) async -> Void) {
        self.onRegister = onRegister
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        guard let line = buffer.readString(length: buffer.readableBytes) else { return }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let jsonData = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let pid = json["pid"] as? Int,
              let tty = json["tty"] as? String,
              let shell = json["shell"] as? String,
              let outPipe = json["outPipe"] as? String else { return }

        let reg = ShellRegistration(
            pid: pid, tty: tty,
            shell: shell,
            term: json["term"] as? String ?? "unknown",
            outPipe: outPipe
        )
        Task { await self.onRegister(reg) }
        context.close(promise: nil)
    }
}
