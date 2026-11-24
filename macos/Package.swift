// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FizzDeck",
    platforms: [
        .macOS("26.0"),
    ],
    products: [
        .executable(name: "FizzDeck", targets: ["FizzDeck"]),
    ],
    targets: [
        .executableTarget(
            name: "FizzDeck",
            path: "Sources/FizzDeck",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "FizzDeckTests",
            dependencies: ["FizzDeck"],
            path: "Tests/FizzDeckTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
