// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChromeProfileManager",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ChromeProfileManager", targets: ["ChromeProfileManager"]),
        .library(name: "ProfileKit", targets: ["ProfileKit"]),
        .library(name: "ProfileUI", targets: ["ProfileUI"])
    ],
    targets: [
        // All filesystem, process and launch logic lives here so it can be
        // unit-tested without a UI and without a real Chrome installation.
        .target(
            name: "ProfileKit",
            path: "Sources/ProfileKit"
        ),
        // Presentation model for the menu: no AppKit, fully testable.
        .target(
            name: "ProfileUI",
            dependencies: ["ProfileKit"],
            path: "Sources/ProfileUI"
        ),
        // Thin AppKit shell: status item, menus, dialogs.
        .executableTarget(
            name: "ChromeProfileManager",
            dependencies: ["ProfileKit", "ProfileUI"],
            path: "Sources/ChromeProfileManager"
        ),
        // Developer-only acceptance harness. Launches a real Chrome instance
        // against a temporary profile and is never part of the app bundle.
        .executableTarget(
            name: "IntegrationCheck",
            dependencies: ["ProfileKit"],
            path: "Sources/IntegrationCheck"
        ),
        .testTarget(
            name: "ProfileKitTests",
            dependencies: ["ProfileKit"],
            path: "Tests/ProfileKitTests"
        ),
        .testTarget(
            name: "ProfileUITests",
            dependencies: ["ProfileUI", "ProfileKit"],
            path: "Tests/ProfileUITests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
