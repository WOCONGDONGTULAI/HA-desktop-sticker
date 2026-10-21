// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "HASticker",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "HASticker",
            path: "Sources/HASticker"
        )
    ]
)
