// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "toe",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure-geometry layout engine. No AppKit, no Accessibility, fully testable headless.
        .target(name: "ToeCore", path: "Sources/ToeCore"),
        // The app: everything that touches AppKit, Accessibility and Carbon.
        .executableTarget(
            name: "toe",
            dependencies: ["ToeCore"],
            path: "Sources/toe",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        // XCTest ships with Xcode, not the Command Line Tools, so the layout suite is a
        // plain executable. `make test` therefore works on a bare CLT machine.
        .executableTarget(name: "toe-selftest", dependencies: ["ToeCore"], path: "Sources/toe-selftest"),
    ]
)
