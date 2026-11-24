// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GHealthCore",
    platforms: [.iOS("26.0"), .macOS(.v15)],
    products: [.library(name: "GHealthCore", targets: ["GHealthCore"])],
    targets: [.target(name: "GHealthCore"), .testTarget(name: "GHealthCoreTests", dependencies: ["GHealthCore"])]
)
