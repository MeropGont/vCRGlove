// swift-tools-version: 5.5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Bhaptics",
    platforms: [
        .macOS(.v10_15), .iOS(.v13)
    ],
    products: [
        .library(
            name: "Bhaptics",
            targets: ["BhapticsExample", "BhapticsPlugin"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "BhapticsExample",
            dependencies: ["BhapticsPlugin"]
        ),
        .binaryTarget(
            name: "BhapticsPlugin",
            path: "BhapticsPlugin.xcframework"
        )
//        .binaryTarget(
//            name: "BhapticsPlugin",
//            url: "https://github.com/westside/apple-bhaptics/raw/main/BhapticsPlugin.zip",
//            checksum: "2acba9c6ee00e4eb098e67c02d3e3e437f7b0e15cd384212509c0fe3d77eef20"
//        )
//        .testTarget(
//            name: "bHapticsSDKTests",
//            dependencies: ["BhapticsSDK"]),
    ]
)
