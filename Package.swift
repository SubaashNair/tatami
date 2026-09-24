// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tatami",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Tatami", targets: ["Tatami"])],
    targets: [
        .target(name: "TatamiCore"),
        .executableTarget(name: "Tatami", dependencies: ["TatamiCore"]),
        .testTarget(name: "TatamiCoreTests", dependencies: ["TatamiCore"])
    ]
)
