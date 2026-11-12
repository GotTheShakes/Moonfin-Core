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
            revision: "34f149ba2dd483f490dca13a5a3027d58a9956f5",
            // DTSXObjectAudio is left out: at this revision its decoder fails to
            // compile with Xcode 26.3's Swift ("sending value of non-Sendable type
            // '() async -> DTSXObjectAudioDecoder.Verdict?'" in
            // SoftwarePlaybackHost+AudioProducer.swift). Add it back once CI builds
            // with Xcode 27. DTS:X tracks still play, as their 7.1 bed.
            traits: ["TrueHDObjectAudio", "DualLayerDolbyVision"]
        ),
    ],
    targets: [
        .target(
            name: "AetherEngineTraits",
            dependencies: [.product(name: "AetherEngine", package: "AetherEngine")]
        ),
    ]
)
