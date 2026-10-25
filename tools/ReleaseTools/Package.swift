// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReleaseTools", platforms: [.macOS(.v15)],
    products: [.executable(name: "snapwell-asc", targets: ["snapwell-asc"])],
    targets: [
        .target(name: "ReleaseCore"),
        .executableTarget(name: "snapwell-asc", dependencies: ["ReleaseCore"]),
        .testTarget(name: "ReleaseCoreTests", dependencies: ["ReleaseCore"])
    ], swiftLanguageModes: [.v5]
)
