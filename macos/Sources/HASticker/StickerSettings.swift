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

/// 贴纸的内容从哪来
enum StickerSource: String, Codable, CaseIterable, Identifiable {
    case native   // 原生面板：直接调 HA 的 REST + WebSocket，不走网页
    case web      // 嵌 HA 网页

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .native: return "原生面板（推荐，快且干净）"
        case .web:    return "网页（嵌 HA 仪表盘）"
        }
    }
}

struct StickerSettings: Codable {
    var haURL: String = ""
    var token: String = ""            // HA 长期访问令牌（原生面板用）
    var entities: String = ""         // 逗号分隔的 entity_id；留空 = 自动挑
    var icons: [String: String] = [:]  // entity_id -> SF Symbol 名字（手改过的）
    var names: [String: String] = [:]  // entity_id -> 磁贴标题（手改过的）
    var source: StickerSource = .native
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
        let hasURL = !haURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if source == .native {
            return hasURL && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return hasURL
    }

    /// 原生面板用的基地址：从网页地址里剥掉路径，只留 scheme://host:port
    var baseURL: URL? {
        guard let raw = normalizedURLString(), var comps = URLComponents(string: raw) else { return nil }
        comps.path = ""
        comps.query = nil
        comps.fragment = nil
        return comps.url
    }

    /// 手填的实体列表（空数组表示自动挑）
    var explicitEntities: [String] {
        entities.split(whereSeparator: { ",， \n\t".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 磁贴标题：手改过就用改过的，否则用 HA 的 friendly_name
    func title(for entityID: String, fallback: String) -> String {
        guard let n = names[entityID]?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty else { return fallback }
        return n
    }

    /// 磁贴图标：手选过就用选的 SF Symbol，否则用按名字自动猜的那个
    func symbol(for entityID: String, fallback: String) -> String {
        guard let i = icons[entityID]?.trimmingCharacters(in: .whitespacesAndNewlines), !i.isEmpty else { return fallback }
        return i
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
        case haURL, token, entities, source, width, height, opacity, zoom, cornerRadius, mode, appearance, lockPosition, x, y, icons, names
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StickerSettings()
        haURL        = try c.decodeIfPresent(String.self, forKey: .haURL) ?? d.haURL
        token        = try c.decodeIfPresent(String.self, forKey: .token) ?? d.token
        entities     = try c.decodeIfPresent(String.self, forKey: .entities) ?? d.entities
        icons        = try c.decodeIfPresent([String: String].self, forKey: .icons) ?? d.icons
        names        = try c.decodeIfPresent([String: String].self, forKey: .names) ?? d.names
        source       = try c.decodeIfPresent(StickerSource.self, forKey: .source) ?? d.source
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
