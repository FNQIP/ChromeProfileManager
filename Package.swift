// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ChromeProfiles",
    platforms: [
        // Deployment target for the app; also passed to swiftc via --triple,
        // and to xcodebuild via MACOSX_DEPLOYMENT_TARGET in CI.
        .macOS(.v12)
    ],
    products: [
        .executable(name: "ChromeProfiles", targets: ["ChromeProfiles"]),
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
            name: "ChromeProfiles",
            dependencies: ["ProfileKit", "ProfileUI"],
            path: "Sources/ChromeProfiles"
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
