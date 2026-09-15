// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PressureClutch",
    platforms: [.macOS(.v13)],
    targets: [
        // The trackpad's per-finger force is only published by the private MultitouchSupport framework.
        .target(
            name: "CMultitouch",
            path: "Sources/CMultitouch",
            linkerSettings: [.unsafeFlags(["-F/System/Library/PrivateFrameworks", "-framework", "MultitouchSupport"])]
        ),
        .executableTarget(name: "PressureClutch", dependencies: ["CMultitouch"], path: "Sources/PressureClutch"),
    ]
)
