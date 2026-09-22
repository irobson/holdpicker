// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HoldShot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HoldShot", targets: ["HoldShot"]),
        .library(name: "HoldShotCore", targets: ["HoldShotCore"]),
    ],
    targets: [
        // Pure logic: gesture state machine and geometry helpers. No AppKit.
        .target(name: "HoldShotCore"),

        // The menu bar application.
        .executableTarget(
            name: "HoldShot",
            dependencies: ["HoldShotCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),

        .testTarget(name: "HoldShotCoreTests", dependencies: ["HoldShotCore"]),
    ]
)
