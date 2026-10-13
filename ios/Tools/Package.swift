// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "Tools",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/apollographql/apollo-ios", from: "2.4.0")],
    targets: [.target(name: "Tools", dependencies: [.product(name: "Apollo", package: "apollo-ios")], path: "Sources")]
)
