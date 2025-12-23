// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CerkitLibrary",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CerkitCWCompanionLogic", targets: ["CerkitCWCompanionLogic"]),
        .library(name: "ft8_lib", targets: ["ft8_lib"]),
    ],
    targets: [
        .target(
            name: "ft8_lib",
            path: "Libraries/ft8_lib",
            sources: ["ft8", "common", "fft"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("include/common"),
                .headerSearchPath("include/fft"),
                .headerSearchPath("include/ft8"),
                .define("HAVE_STPCPY"),
            ]
        ),
        .target(
            name: "CerkitCWCompanionLogic",
            dependencies: ["ft8_lib"],
            path: "Sources",
            sources: [
                "MorseDecoder.swift", "AudioProcessing.swift", "KiwiClient.swift",
                "FT8Engine.swift", "MorseEncoder.swift", "AudioGenerator.swift",
                "AudioCaptureManager.swift", "CloudReceiverView.swift",
                "IMAADPCMDecoder.swift", "StreamAudioPlayer.swift",
                "WaterfallRenderer.swift", "MetalWaterfallView.swift",
                "AudioSpectrogram.swift", "MaidenheadLocator.swift",
                "WorldMapView.swift",
            ],
            resources: [
                .process("Waterfall.metal")
            ]
        ),
        .testTarget(
            name: "cerkit CW CompanionTests",
            dependencies: ["CerkitCWCompanionLogic"],
            path: "Tests/cerkit CW CompanionTests"
        ),
    ]
)
