import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 自定义图片图标的存取：统一缩到 256px 存成 PNG，文件名 = 实体_id + on/off
enum TileIconStore {
    /// 弹一个打开面板让用户挑图
    static func chooseFile() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "选一张图标图片"
        panel.message = "建议方形、透明背景的 PNG"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// 把一张图装进本机 icons 目录，返回文件名；读不了/写不了返回 nil
    static func install(entityID: String, state: String, from url: URL) -> String? {
        guard let src = NSImage(contentsOf: url) else { return nil }
        let name = "\(safe(entityID))_\(state).png"
        let dest = StickerSettings.iconsDirectory.appendingPathComponent(name)

        guard let tiff = downscale(src, maxSide: 256).tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return nil }
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
                StickerSettings.forgetCachedImage(named: name)
            }
            try data.write(to: dest)
            StickerSettings.forgetCachedImage(named: name)
            return name
        } catch {
            return nil
        }
    }

    static func remove(file: String) {
        guard !file.isEmpty else { return }
        let dest = StickerSettings.iconsDirectory.appendingPathComponent(file)
        try? FileManager.default.removeItem(at: dest)
        StickerSettings.forgetCachedImage(named: file)
    }

    static func image(_ file: String) -> NSImage? {
        file.isEmpty ? nil : StickerSettings.cachedImage(named: file)
    }

    private static func safe(_ s: String) -> String {
        s.map { ($0.isLetter || $0.isNumber) ? String($0) : "_" }.joined()
    }

    /// 原图可能是手机照片那么大，贴纸上只有 26pt，缩一下省内存也省盘
    private static func downscale(_ img: NSImage, maxSide: CGFloat) -> NSImage {
        guard img.size.width > maxSide || img.size.height > maxSide else { return img }
        let scale = min(maxSide / img.size.width, maxSide / img.size.height)
        let size = NSSize(width: round(img.size.width * scale), height: round(img.size.height * scale))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(size.width),
                                         pixelsHigh: Int(size.height),
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .calibratedRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return img }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        img.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let out = NSImage(size: size)
        out.addRepresentation(rep)
        return out
    }
}

/// 「换自己的图片」面板：开一张、关一张
struct TileImageEditorView: View {
    let entityID: String
    let title: String
    @Binding var image: TileImage
    var onDone: () -> Void

    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("给「\(title)」上传图标").font(.headline)

            HStack(alignment: .top, spacing: 16) {
                slot(title: "开着的样子", state: "on", file: $image.on)
                slot(title: "关着的样子", state: "off", file: $image.off)
            }

            Text("建议 256×256 以上、透明背景的 PNG。上传后会自动缩到 256px，存在本机\n"
                 + "~/Library/Application Support/HASticker/icons/，不会外传。"
                 + "「关着的样子」不传就用开着那张。")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !message.isEmpty {
                Text(message).font(.caption).foregroundColor(.orange)
            }

            HStack {
                Button("清除图片（用回苹果图标）") {
                    TileIconStore.remove(file: image.on)
                    TileIconStore.remove(file: image.off)
                    image = TileImage()
                }
                .disabled(image.isEmpty)
                Spacer()
                Button("完成", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 470)
    }

    private func slot(title: String, state: String, file: Binding<String>) -> some View {
        VStack(spacing: 7) {
            Text(title).font(.caption).foregroundColor(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                if let img = TileIconStore.image(file.wrappedValue) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 62, height: 62)
                } else {
                    Image(systemName: symbolExists("photo.badge.plus") ? "photo.badge.plus" : "plus")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 96, height: 96)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            )

            Button("选择图片…") { pick(state: state, file: file) }
            if !file.wrappedValue.isEmpty {
                Button("移除") {
                    TileIconStore.remove(file: file.wrappedValue)
                    file.wrappedValue = ""
                    message = ""
                }
            }
        }
        .frame(width: 200)
    }

    private func pick(state: String, file: Binding<String>) {
        guard let url = TileIconStore.chooseFile() else { return }
        let old = file.wrappedValue
        guard let name = TileIconStore.install(entityID: entityID, state: state, from: url) else {
            message = "这张图读不了，换一张试试（PNG / JPG 都行）。"
            return
        }
        if !old.isEmpty, old != name { TileIconStore.remove(file: old) }
        file.wrappedValue = name
        message = ""
    }
}
