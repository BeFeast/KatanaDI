// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "KatanaDI",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "KatanaDI",
            targets: ["KatanaDI"]
        )
    ],
    targets: [
        .executableTarget(
            name: "KatanaDI",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AudioUnit"),
                .linkedFramework("CoreAudio")
            ]
        )
    ]
)
