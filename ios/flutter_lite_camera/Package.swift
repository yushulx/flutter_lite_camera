// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "flutter_lite_camera",
    platforms: [
        .iOS("13.0"),
    ],
    products: [
        .library(name: "flutter-lite-camera", targets: ["flutter_lite_camera"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "flutter_lite_camera",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy"),
            ]
        ),
    ]
)
