// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "AppleNotesRemindersCLI",
  platforms: [.macOS(.v14)],
  products: [
    .executable(name: "apple-notes-reminders", targets: ["AppleNotesRemindersCLI"]),
    .library(name: "AppleProductivityCore", targets: ["AppleProductivityCore"]),
  ],
  dependencies: [
    .package(
      url: "https://github.com/apple/swift-argument-parser.git",
      exact: "1.8.2"
    ),
    .package(
      url: "https://github.com/modelcontextprotocol/swift-sdk.git",
      exact: "0.12.1"
    ),
  ],
  targets: [
    .target(
      name: "AppleProductivityCore",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("EventKit"),
      ]
    ),
    .executableTarget(
      name: "AppleNotesRemindersCLI",
      dependencies: [
        "AppleProductivityCore",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "MCP", package: "swift-sdk"),
      ],
      exclude: ["Resources/Info.plist"],
      linkerSettings: [
        .unsafeFlags([
          "-Xlinker", "-sectcreate",
          "-Xlinker", "__TEXT",
          "-Xlinker", "__info_plist",
          "-Xlinker", "Sources/AppleNotesRemindersCLI/Resources/Info.plist",
        ])
      ]
    ),
    .executableTarget(
      name: "ContractTests",
      dependencies: ["AppleProductivityCore"],
      path: "ContractTests"
    ),
    .testTarget(
      name: "AppleProductivityCoreTests",
      dependencies: ["AppleProductivityCore"]
    ),
  ]
)
