import Foundation
import AppKit

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

/// 外观：跟随系统 / 强制浅色 / 强制深色
enum StickerAppearance: String, Codable, CaseIterable, Identifiable {
    case auto
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:  return "跟随系统"
        case .light: return "始终浅色"
        case .dark:  return "始终深色"
        }
    }

    /// 强制模式返回对应的 NSAppearance；跟随系统返回 nil（继承系统）
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto:  return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark:  return NSAppearance(named: .darkAqua)
        }
    }

    /// 实际生效的是不是深色（auto 时按当前系统外观判断）
    var resolvedIsDark: Bool {
        switch self {
        case .dark:  return true
        case .light: return false
        case .auto:
            let app = NSApplication.shared.effectiveAppearance
            return app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
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
    var appearance: StickerAppearance = .auto
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

    static let sampleURL = "http://homeassistant.local:8123/ha-sticker?kiosk"

    // MARK: - Codable
    // 逐字段 decodeIfPresent：老版本 settings.json 缺字段时不会整体解析失败
    // （Codable 默认不会用默认值兜底，缺 key 会直接 throw，那样会把已配好的地址冲掉）

    enum CodingKeys: String, CodingKey {
        case haURL, width, height, opacity, zoom, cornerRadius, mode, appearance, lockPosition, x, y
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StickerSettings()
        haURL        = try c.decodeIfPresent(String.self, forKey: .haURL) ?? d.haURL
        width        = try c.decodeIfPresent(Double.self, forKey: .width) ?? d.width
        height       = try c.decodeIfPresent(Double.self, forKey: .height) ?? d.height
        opacity      = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
        zoom         = try c.decodeIfPresent(Double.self, forKey: .zoom) ?? d.zoom
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? d.cornerRadius
        mode         = try c.decodeIfPresent(StickerMode.self, forKey: .mode) ?? d.mode
        appearance   = try c.decodeIfPresent(StickerAppearance.self, forKey: .appearance) ?? d.appearance
        lockPosition = try c.decodeIfPresent(Bool.self, forKey: .lockPosition) ?? d.lockPosition
        x            = try c.decodeIfPresent(Double.self, forKey: .x)
        y            = try c.decodeIfPresent(Double.self, forKey: .y)
    }
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
