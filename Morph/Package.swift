// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Morph",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Morph", targets: ["Morph"])],
    targets: [.executableTarget(name: "Morph", path: "Sources/Morph")]
)
