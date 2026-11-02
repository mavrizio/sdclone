// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "sdclone",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SDCore", targets: ["SDCore"]),
        .executable(name: "sdclone", targets: ["sdclone"]),
        .executable(name: "SDCloneApp", targets: ["SDCloneApp"]),
    ],
    targets: [
        .target(name: "SDCore"),
        .executableTarget(name: "sdclone", dependencies: ["SDCore"]),
        .executableTarget(name: "SDCloneApp", dependencies: ["SDCore"]),
        .testTarget(name: "SDCoreTests", dependencies: ["SDCore"]),
    ]
)
