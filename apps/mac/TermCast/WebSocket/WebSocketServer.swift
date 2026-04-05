import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket

actor WebSocketServer {
    private let port: Int
    private let jwtManager: JWTManager
    private let registry: SessionRegistry
    private let broadcaster: SessionBroadcaster
    private var serverChannel: (any Channel)?
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

    init(port: Int, jwtManager: JWTManager, registry: SessionRegistry, broadcaster: SessionBroadcaster) {
        self.port = port
        self.jwtManager = jwtManager
        self.registry = registry
        self.broadcaster = broadcaster
    }

    func start() async throws {
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

        serverChannel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
    }

    func stop() async throws {
        try await serverChannel?.close().get()
        try await group.shutdownGracefully()
    }
}
