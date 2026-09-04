// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "YFShip",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "yfship",
            targets: ["YFShip"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.5.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "YFShip",
            dependencies: [
                .product(
                    name: "ArgumentParser",
                    package: "swift-argument-parser"
                )
            ],
            resources: [
                .embedInCode("Resources/BenchmarkDestinations.json")
            ]
        ),
        .testTarget(
            name: "YFShipTests",
            dependencies: ["YFShip"],
            resources: [
                .copy("Fixtures")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
