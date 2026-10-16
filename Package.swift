// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SlideSnap",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SlideSnapApp", targets: ["SlideSnapApp"]),  // binary is renamed in the .app
        .executable(name: "slidesnap", targets: ["SlideSnapCLI"]),
        .library(name: "SlideSnapCore", targets: ["SlideSnapCore"]),
    ],
    targets: [
        .target(name: "SlideSnapCore"),
        // Separate folder names: Sources/SlideSnap and Sources/slidesnap would be one
        // folder on a case-insensitive disk.
        .executableTarget(name: "SlideSnapApp", dependencies: ["SlideSnapCore"]),
        .executableTarget(name: "SlideSnapCLI", dependencies: ["SlideSnapCore"]),
    ]
)
