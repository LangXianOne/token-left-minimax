// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MiniMaxQuota",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MiniMaxQuota", targets: ["MiniMaxQuota"])
    ],
    targets: [
        .executableTarget(
            name: "MiniMaxQuota",
            path: "Sources/MiniMaxQuota"
        )
    ]
)
