// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TedCat",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TedCat", targets: ["TedCat"]),
        .library(name: "TedCatCore", targets: ["TedCatCore"]),
    ],
    targets: [
        // Pure logic: gesture state machine and geometry helpers. No AppKit.
        .target(name: "TedCatCore"),

        // The menu bar application.
        .executableTarget(
            name: "TedCat",
            dependencies: ["TedCatCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ServiceManagement"),
            ]
        ),

        .testTarget(name: "TedCatCoreTests", dependencies: ["TedCatCore"]),
    ]
)
