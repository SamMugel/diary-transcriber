// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiaryTranscriber",
    platforms: [
        // AI: PRD 20 — bumped from macOS 14 to 15 because Synchronization.Mutex
        //     (used to fix the RecordingOutputDelegate deadlock/data-race) is
        //     only available in the macOS 15.0+ stdlib ABI overlay.
        .macOS(.v15)
    ],
    products: [
        .executable(name: "DiaryTranscriber", targets: ["DiaryTranscriber"])
    ],
    targets: [
        .executableTarget(
            name: "DiaryTranscriber",
            dependencies: ["DiaryTranscriberCore"],
            path: "App",
            swiftSettings: [
                .swiftLanguageMode(.v6) // AI: Swift 6 mode enables strict concurrency (-strict-concurrency=complete); no .unsafeFlags needed / PRD 38
            ]
        ),
        .target(
            name: "DiaryTranscriberCore",
            path: "Sources/DiaryTranscriber",
            swiftSettings: [
                .swiftLanguageMode(.v6) // AI: Swift 6 mode enables strict concurrency (-strict-concurrency=complete); no .unsafeFlags needed / PRD 38
            ]
        ),
        .testTarget(
            name: "DiaryTranscriberTests",
            dependencies: ["DiaryTranscriberCore"],
            path: "Tests/DiaryTranscriberTests",
            swiftSettings: [
                .swiftLanguageMode(.v6) // AI: Swift 6 mode enables strict concurrency (-strict-concurrency=complete); no .unsafeFlags needed / PRD 38
            ]
        )
    ]
)
