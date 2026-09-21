// swift-tools-version: 6.0

import Foundation
import PackageDescription

let developerDirectory = ProcessInfo.processInfo.environment["DEVELOPER_DIR"]
    ?? "/Library/Developer/CommandLineTools"
let commandLineToolsFrameworks = FileManager.default.fileExists(
    atPath: "\(developerDirectory)/Library/Developer/Frameworks/Testing.framework"
)
    ? "\(developerDirectory)/Library/Developer/Frameworks"
    : "\(developerDirectory)/Library/Frameworks"
let commandLineToolsTestingLibraries = FileManager.default.fileExists(
    atPath: "\(developerDirectory)/Library/Developer/usr/lib"
)
    ? "\(developerDirectory)/Library/Developer/usr/lib"
    : "\(developerDirectory)/usr/lib"

let package = Package(
    name: "CodexUsage",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CodexUsageCore", targets: ["CodexUsageCore"]),
        .executable(name: "CodexUsage", targets: ["CodexUsage"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .target(name: "CodexUsageCore"),
        .executableTarget(
            name: "CodexUsage",
            dependencies: [
                "CodexUsageCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/CodexUsageApp",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@loader_path/../Frameworks",
                ]),
            ]
        ),
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
