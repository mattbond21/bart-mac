// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Bart",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Bart", targets: ["Bart"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")],
    targets: [
        .executableTarget(name: "Bart", dependencies: [.product(name: "Sparkle", package: "Sparkle")]),
        .testTarget(name: "BartTests", dependencies: ["Bart"])
    ]
)
