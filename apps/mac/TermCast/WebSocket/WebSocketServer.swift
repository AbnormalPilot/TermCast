import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket

enum WebSocketServerError: Error, Equatable {
    case noPortAvailable
}

actor WebSocketServer {
    private let preferredPort: Int
    private let jwtManager: JWTManager
    private let registry: SessionRegistry
    private let broadcaster: SessionBroadcaster
    private var serverChannel: (any Channel)?
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

    nonisolated func eventLoopGroup() -> MultiThreadedEventLoopGroup { group }

    /// Number of consecutive ports to attempt before giving up.
    private static let portAttempts = 5

    init(preferredPort: Int, jwtManager: JWTManager, registry: SessionRegistry, broadcaster: SessionBroadcaster) {
        self.preferredPort = preferredPort
        self.jwtManager = jwtManager
        self.registry = registry
        self.broadcaster = broadcaster
    }

    /// Starts the server, trying preferredPort then up to 4 higher ports on EADDRINUSE.
    /// Returns the port that was successfully bound.
    @discardableResult
    func start() async throws -> Int {
        let jwt = jwtManager
        let reg = registry
        let bc = broadcaster

        let upgrader = NIOWebSocketServerUpgrader(
            shouldUpgrade: { [jwt] channel, head -> EventLoopFuture<HTTPHeaders?> in
                let authHeader = head.headers["Authorization"].first ?? ""
                guard authHeader.hasPrefix("Bearer "),
                      jwt.verify(String(authHeader.dropFirst(7))) else {
                    return channel.eventLoop.makeSucceededFuture(nil)
                }
                return channel.eventLoop.makeSucceededFuture(HTTPHeaders())
            },
            upgradePipelineHandler: { channel, _ -> EventLoopFuture<Void> in
                channel.pipeline.addHandler(WebSocketHandler(registry: reg, broadcaster: bc))
            }
        )

        let upgradeConfig = NIOHTTPServerUpgradeConfiguration(
            upgraders: [upgrader],
            completionHandler: { _ in }
        )

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withServerUpgrade: upgradeConfig)
            }

        for offset in 0..<Self.portAttempts {
            let port = preferredPort + offset
            do {
                serverChannel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
                return port
            } catch let err as IOError where err.errnoCode == EADDRINUSE { // Darwin: 48
                continue
            }
        }
        throw WebSocketServerError.noPortAvailable
    }

    func stop() async throws {
        guard serverChannel != nil else { return }
        try await serverChannel?.close().get()
        serverChannel = nil
        try await group.shutdownGracefully()
    }
}
