// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HermesStatusWidget",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "HermesStatusWidget", targets: ["HermesStatusWidget"])
    ],
    targets: [
        .executableTarget(
            name: "HermesStatusWidget",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
