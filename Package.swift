// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SocialManagerCore", platforms: [.macOS(.v14)], products: [.executable(name: "keepclose", targets: ["KeepCloseCLI"]), .library(name: "SocialManagerCore", targets: ["SocialManagerCore"])], targets: [.executableTarget(name: "KeepCloseCLI", dependencies: ["SocialManagerCore"], path: "Sources/KeepCloseCLI"), .target(name: "SocialManagerCore", path: "SocialManager/Core"), .testTarget(name: "SocialManagerCoreTests", dependencies: ["SocialManagerCore"], path: "Tests/SocialManagerCoreTests")])
