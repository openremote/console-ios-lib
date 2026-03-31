// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "ORLib",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "ORLib",
            targets: ["ORLib"]),
    ],
    dependencies: [
        .package(
            name: "ESPProvision",
            url: "https://github.com/espressif/esp-idf-provisioning-ios.git",
            "3.0.2" ..< "4.0.0"
        ),
        .package(
            name: "RandomPasswordGenerator",
            url: "https://github.com/yukanamori/RandomPasswordGenerator.git",
            .exact("0.1.0")
        ),
        .package(
            name: "SwiftLintPlugins",
            url: "https://github.com/SimplyDanny/SwiftLintPlugins",
            from:"0.63.2")
    ],
    targets: [
        .target(
            name: "ORLib",
            dependencies: ["ESPProvision", "RandomPasswordGenerator"],
            path: "ORLib",
            resources: [
                .process("Media.xcassets")
            ],
            plugins: [.plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins")]
        ),
        .testTarget(
            name: "ORLibTests",
            dependencies: ["ORLib"],
            path: "Tests",
            resources: [
                .copy("Fixtures")
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
