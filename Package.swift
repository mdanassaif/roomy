// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Roomy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Roomy",
            path: "Sources/Roomy",
            linkerSettings: [.linkedFramework("IOKit")]
        )
    ]
)
