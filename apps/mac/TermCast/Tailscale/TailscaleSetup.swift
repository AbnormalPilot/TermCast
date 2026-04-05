import AppKit
import Foundation
import CoreImage

struct TailscaleStatus: Decodable {
    struct SelfNode: Decodable {
        let dnsName: String
        enum CodingKeys: String, CodingKey { case dnsName = "DNSName" }
    }
    let selfNode: SelfNode
    enum CodingKeys: String, CodingKey { case selfNode = "Self" }
}

struct TailscaleSetup {
    static let tailscaleBin = "/usr/local/bin/tailscale"

    static func isTailscaleInstalled() -> Bool {
        FileManager.default.fileExists(atPath: tailscaleBin)
    }

    @discardableResult
    static func configureServe() throws -> String {
        try shell(tailscaleBin, "serve", "--https=443", "7681")
    }

    static func hostname() throws -> String {
        let json = try shell(tailscaleBin, "status", "--json")
        guard let data = json.data(using: .utf8) else { throw TailscaleError.parseError }
        let status = try JSONDecoder().decode(TailscaleStatus.self, from: data)
        return status.selfNode.dnsName.hasSuffix(".")
            ? String(status.selfNode.dnsName.dropLast()) : status.selfNode.dnsName
    }

    static func qrCode(hostname: String, secret: Data) -> NSImage? {
        let payload: [String: String] = [
            "host": hostname,
            "secret": secret.map { String(format: "%02x", $0) }.joined()
        ]
        guard let json = try? JSONEncoder().encode(payload),
              let str = String(data: json, encoding: .utf8) else { return nil }
        return generateQR(from: str)
    }

    private static func generateQR(from string: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(string.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scale = 10.0
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }

    @discardableResult
    private static func shell(_ args: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}

enum TailscaleError: Error {
    case notInstalled
    case parseError
    case configureError(String)
}
