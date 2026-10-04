// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HoldPicker",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HoldPicker", targets: ["HoldPicker"]),
        .library(name: "HoldPickerCore", targets: ["HoldPickerCore"]),
    ],
    targets: [
        // Pure logic: gesture state machine and geometry helpers. No AppKit.
        .target(name: "HoldPickerCore"),

        // The menu bar application.
        .executableTarget(
            name: "HoldPicker",
            dependencies: ["HoldPickerCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("ServiceManagement"),
            ]
        ),

        .testTarget(name: "HoldPickerCoreTests", dependencies: ["HoldPickerCore"]),
    ]
)
