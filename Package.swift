// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SocialManagerCore", platforms: [.macOS(.v14)],
    products: [.executable(name: "keepclose", targets: ["KeepCloseCLI"]),
               .library(name: "SocialManagerCore", targets: ["SocialManagerCore"])],
    dependencies: [.package(url: "https://github.com/Slaymish/HamishNativeLibrary.git", .upToNextMinor(from: "0.2.0"))],
    targets: [
        .executableTarget(name: "KeepCloseCLI", dependencies: ["SocialManagerCore",
            .product(name: "NativeCore", package: "HamishNativeLibrary")], path: "Sources/KeepCloseCLI"),
        .target(name: "SocialManagerCore", dependencies: [
            .product(name: "NativeCore", package: "HamishNativeLibrary"),
            .product(name: "NativeSecurity", package: "HamishNativeLibrary"),
            .product(name: "AgentInterchange", package: "HamishNativeLibrary")], path: "SocialManager/Core"),
        .testTarget(name: "SocialManagerCoreTests", dependencies: ["SocialManagerCore"], path: "Tests/SocialManagerCoreTests")
    ])
