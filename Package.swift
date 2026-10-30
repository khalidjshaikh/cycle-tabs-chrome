// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CycleTabs",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CycleTabs", targets: ["CycleTabs"])
    ],
    targets: [
        .executableTarget(
            name: "CycleTabs",
            path: "Sources/CycleTabs",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
