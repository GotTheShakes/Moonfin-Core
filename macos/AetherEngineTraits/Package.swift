// swift-tools-version: 6.1

import PackageDescription

// Turns on AetherEngine's optional components for the macOS app.
//
// Xcode 26 ignores a `traits` list on a package reference in the .pbxproj, and
// xcodebuild has no flag for a package's traits, so the Runner target links
// the engine only through this package, which pins the revision with the
// traits set and re-exports AetherEngine. A direct engine reference beside it
// breaks package resolution. This is the
// engine's documented route for an Xcode project (README, Optional components;
// Probes/AllTraits). Keep the URL and revision in step with
// macos/scripts/wire_macos_player.rb.
let package = Package(
    name: "AetherEngineTraits",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "AetherEngineTraits", targets: ["AetherEngineTraits"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/RadicalMuffinMan/AetherEngine",
            revision: "93a024a5b72a735c996ca289e7dc0ed8d09dc787",
            traits: ["TrueHDObjectAudio", "DTSXObjectAudio", "DualLayerDolbyVision"]
        ),
    ],
    targets: [
        .target(
            name: "AetherEngineTraits",
            dependencies: [.product(name: "AetherEngine", package: "AetherEngine")]
        ),
    ]
)
