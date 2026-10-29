// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tatami",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tatami", targets: ["Tatami"]),
        // Not named "tatami": macOS file names ignore case, so it would collide with the app binary. It is installed as `tatami`.
        .executable(name: "tatami-cli", targets: ["TatamiCLI"]),
    ],
    targets: [
        .target(name: "TatamiCore"),
        .executableTarget(name: "Tatami", dependencies: ["TatamiCore"]),
        .executableTarget(name: "TatamiCLI", dependencies: ["TatamiCore"]),
        .testTarget(name: "TatamiCoreTests", dependencies: ["TatamiCore"])
    ]
)
