// swift-tools-version: 6.0

import PackageDescription

let commandLineToolsFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let commandLineToolsTestingLibraries = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

let package = Package(
    name: "CodexUsage",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexUsageCore", targets: ["CodexUsageCore"]),
        .executable(name: "CodexUsage", targets: ["CodexUsage"]),
    ],
    targets: [
        .target(name: "CodexUsageCore"),
        .executableTarget(name: "CodexUsage", dependencies: ["CodexUsageCore"]),
        .testTarget(
            name: "CodexUsageCoreTests",
            dependencies: ["CodexUsageCore"],
            swiftSettings: [.unsafeFlags(["-F", commandLineToolsFrameworks])],
            linkerSettings: [
                .unsafeFlags([
                    "-F", commandLineToolsFrameworks,
                    "-Xlinker", "-rpath",
                    "-Xlinker", commandLineToolsFrameworks,
                    "-Xlinker", "-rpath",
                    "-Xlinker", commandLineToolsTestingLibraries,
                ])
            ]
        ),
    ]
)
