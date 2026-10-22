// Sources/BattMateCore/SettingsStore.swift
import Foundation

public final class SettingsStore {
    public let fileURL: URL
    private let fm = FileManager.default

    /// directory 为 nil 时使用 ~/Library/Application Support/BattMate/
    public init(directory: URL? = nil) {
        let dir = directory ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BattMate", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")
    }

    public func load() -> AppConfig {
        guard let data = try? Data(contentsOf: fileURL) else { return .default }
        guard let config = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            save(.default) // 文件损坏：回落默认并重写
            return .default
        }
        return config
    }

    public func save(_ config: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
