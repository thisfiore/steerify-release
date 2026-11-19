// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SteerApp",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "SteerApp",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Sources/SteerApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
