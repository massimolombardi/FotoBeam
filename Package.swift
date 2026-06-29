// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FotoBeam",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FotoBeam", targets: ["FotoBeam"])
    ],
    targets: [
        .executableTarget(
            name: "FotoBeam"
        )
    ]
)
