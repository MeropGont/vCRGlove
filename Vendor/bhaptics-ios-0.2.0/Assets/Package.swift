// swift-tools-version: 5.7
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
//        .testTarget(
//            name: "bHapticsSDKTests",
//            dependencies: ["BhapticsSDK"]),
    ]
)
