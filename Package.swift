// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ribbit",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Ribbit", targets: ["Ribbit"])
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "GhosttyKit",
            path: "Vendor/GhosttyKit.xcframework"
        ),
        .executableTarget(
            name: "Ribbit",
            dependencies: ["GhosttyKit"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedLibrary("c++")
            ]
        ),
        .testTarget(
            name: "RibbitTests",
            dependencies: ["Ribbit"]
        )
    ]
)
