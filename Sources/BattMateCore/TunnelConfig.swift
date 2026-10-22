// Sources/BattMateCore/TunnelConfig.swift
import Foundation

/// 一条本机端口 → 服务器端口的 SSH 本地转发映射。
public struct TunnelConfig: Codable, Equatable, Identifiable {
    public var id: UUID
    public var localPort: Int
    public var remotePort: Int
    public var enabled: Bool

    public init(id: UUID = UUID(), localPort: Int, remotePort: Int, enabled: Bool = true) {
        self.id = id
        self.localPort = localPort
        self.remotePort = remotePort
        self.enabled = enabled
    }

    public static func isValidPort(_ port: Int) -> Bool {
        (1...65535).contains(port)
    }

    public var forwardDescription: String {
        "本机 \(localPort) → 服务器 \(remotePort)"
    }

    private enum CodingKeys: String, CodingKey {
        case id, localPort, remotePort, enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        localPort = try c.decode(Int.self, forKey: .localPort)
        remotePort = try c.decode(Int.self, forKey: .remotePort)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

public enum TunnelValidator {
    /// 返回用户可读的配置错误；空数组表示合法
    public static func errors(for tunnels: [TunnelConfig]) -> [String] {
        var errors: [String] = []
        var localPortFirstIndex: [Int: Int] = [:]

        for (index, tunnel) in tunnels.enumerated() {
            let label = "第 \(index + 1) 条映射"
            if !TunnelConfig.isValidPort(tunnel.localPort) {
                errors.append("\(label)本机端口 \(tunnel.localPort) 无效（1~65535）")
            }
            if !TunnelConfig.isValidPort(tunnel.remotePort) {
                errors.append("\(label)映射端口 \(tunnel.remotePort) 无效（1~65535）")
            }
            if let first = localPortFirstIndex[tunnel.localPort] {
                errors.append("\(label)本机端口 \(tunnel.localPort) 与第 \(first + 1) 条重复")
            } else {
                localPortFirstIndex[tunnel.localPort] = index
            }
        }
        return errors
    }
}
