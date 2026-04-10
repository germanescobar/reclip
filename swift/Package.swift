// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LoomClone",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/awslabs/aws-sdk-swift.git", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "LoomClone",
            dependencies: [
                .product(name: "AWSS3", package: "aws-sdk-swift"),
            ],
            path: "LoomClone",
            exclude: ["Info.plist", "LoomClone.entitlements"],
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreImage"),
                .linkedFramework("Metal"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
            ]
        )
    ]
)
