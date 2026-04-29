// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Codebook",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Codebook", targets: ["Codebook"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.3")
    ],
    targets: [
        .executableTarget(
            name: "Codebook",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"])
            ]
        )
    ]
)
