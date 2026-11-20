// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SteerApp",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "SteerApp",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm"), .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/SteerApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
