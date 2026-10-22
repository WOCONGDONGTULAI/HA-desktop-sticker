import Foundation
import AppKit

/// 开机自动启动。
///
/// macOS 13 才有 `SMAppService`（会显示在「系统设置 → 通用 → 登录项」里），
/// 这台机器是 macOS 12，用不了。所以这里统一走最土也最稳的办法：
/// 往 `~/Library/LaunchAgents/` 放一份 plist，登录后 launchd 会把它拉起来。
///
/// 副作用：不会出现在系统设置的登录项列表里，开关只能在本 app 的菜单里改。
enum LaunchAtLogin {

    /// 跟 Info.plist 的 CFBundleIdentifier 一致，方便一眼认出来
    static let label = "com.congdongtulai.HASticker"

    static var agentURL: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return library.appendingPathComponent("LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: agentURL.path)
    }

    /// 正在跑的这个可执行文件（plist 里要指向它）
    static var executablePath: String? {
        Bundle.main.executablePath ?? CommandLine.arguments.first
    }

    // MARK: - 开关

    /// 打开。返回 nil = 成功，否则是失败原因
    @discardableResult
    static func enable() -> String? {
        guard let path = executablePath else { return "拿不到 app 路径" }
        do {
            let dir = agentURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try plist(program: path).write(to: agentURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: agentURL.path)
            unload()          // 万一 launchd 里已经有旧的，先踢掉，等下次登录重新载入
            return nil
        } catch {
            return "写入 LaunchAgents 失败：\(error.localizedDescription)"
        }
    }

    /// 关闭。清掉 launchd 里已载入的那份，再删文件
    @discardableResult
    static func disable() -> String? {
        guard isEnabled else { return nil }
        unload()
        do {
            try FileManager.default.removeItem(at: agentURL)
            return nil
        } catch {
            return "删除 LaunchAgents 失败：\(error.localizedDescription)"
        }
    }

    // MARK: - 内部

    /// app 换过位置（比如从「下载」挪到「应用程序」）就顺手把 plist 里的路径改掉
    static func syncPathIfNeeded() {
        guard isEnabled, let path = executablePath,
              let text = try? String(contentsOf: agentURL, encoding: .utf8),
              !text.contains("<string>\(path)</string>") else { return }
        _ = enable()
    }

    private static func plist(program: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(program)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """
    }

    /// 从 launchd 里注销（新版用 bootout，旧版用 remove）。失败无所谓，文件删了下次就不会再拉起
    private static func unload() {
        guard isEnabled else { return }
        let uid = getuid()
        for args in [["bootout", "gui/\(uid)/\(label)"],
                     ["bootout", "gui/\(uid)", agentURL.path],
                     ["remove", label]] {
            let task = Process()
            task.launchPath = "/bin/launchctl"
            task.arguments = args
            task.standardOutput = nil
            task.standardError = nil
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 { return }
        }
    }
}
