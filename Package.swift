// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiaryTranscriber",
    platforms: [
        .macOS(.v14)
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
                .swiftLanguageMode(.v6)
            ]
        ),
        .target(
            name: "DiaryTranscriberCore",
            path: "Sources/DiaryTranscriber",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "DiaryTranscriberTests",
            dependencies: ["DiaryTranscriberCore"],
            path: "Tests/DiaryTranscriberTests",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
