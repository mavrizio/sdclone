// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "sdclone",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SDCore", targets: ["SDCore"]),
        .executable(name: "sdclone", targets: ["sdclone"]),
    ],
    targets: [
        .target(name: "SDCore"),
        .executableTarget(name: "sdclone", dependencies: ["SDCore"]),
        .testTarget(name: "SDCoreTests", dependencies: ["SDCore"]),
    ]
)
