// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "cerkit CW Companion",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CerkitCWCompanionLogic", targets: ["CerkitCWCompanionLogic"])
    ],
    targets: [
        .target(
            name: "CerkitCWCompanionLogic",
            path: "cerkit CW Companion",
            exclude: [
                "cerkit_CW_CompanionApp.swift", "ContentView.swift", "Assets.xcassets",
                "Preview Content",
            ],
            sources: ["MorseDecoder.swift", "AudioProcessing.swift"]
        ),
        .testTarget(
            name: "cerkit CW CompanionTests",
            dependencies: ["CerkitCWCompanionLogic"],
            path: "Tests/cerkit CW CompanionTests"
        ),
    ]
)
