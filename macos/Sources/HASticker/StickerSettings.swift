import Foundation

/// 贴纸的三种贴法
enum StickerMode: String, Codable, CaseIterable, Identifiable {
    case desktop   // 贴在桌面层：Win+D 跟着出现，被其他窗口正常遮挡
    case floating  // 置顶：浮在所有窗口之上
    case normal    // 普通窗口

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .desktop:  return "桌面层（贴住桌面）"
        case .floating: return "置顶（浮在所有窗口上）"
        case .normal:   return "普通窗口"
        }
    }
}

struct StickerSettings: Codable {
    var haURL: String = ""
    var width: Double = 320
    var height: Double = 480
    var opacity: Double = 1.0
    var zoom: Double = 1.0
    var cornerRadius: Double = 12
    var mode: StickerMode = .desktop
    var lockPosition: Bool = false
    var x: Double?
    var y: Double?

    var isConfigured: Bool {
        !haURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 没写 scheme 的自动补 http://
    func normalizedURLString() -> String? {
        var s = haURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.contains("://") { s = "http://" + s }
        return s
    }

    static let sampleURL = "http://homeassistant.local:8123/sticker?kiosk"
}

extension StickerSettings {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first!
        let folder = base.appendingPathComponent("HASticker", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("settings.json")
    }

    static func load() -> StickerSettings {
        guard let data = try? Data(contentsOf: fileURL) else { return StickerSettings() }
        guard let s = try? JSONDecoder().decode(StickerSettings.self, from: data) else { return StickerSettings() }
        return s
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: StickerSettings.fileURL, options: .atomic)
    }

    static func reset() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
