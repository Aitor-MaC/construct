// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MacterminalCore",
  defaultLocalization: "en",
  platforms: [.macOS("27.2")],
  products: [
    .library(name: "MacterminalCore", targets: ["MacterminalCore"]),
    .library(name: "MacterminalTerminal", targets: ["MacterminalTerminal"]),
  ],
  dependencies: [
    .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", revision: "1488fac94f52e3934ffba185b44c2395d4f95d3c")
  ],
  targets: [
    .target(name: "MacterminalCore", resources: [.process("Resources")]),
    .target(
      name: "MacterminalTerminal",
      dependencies: ["MacterminalCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
      resources: [.process("Resources")]),
    .testTarget(name: "MacterminalCoreTests", dependencies: ["MacterminalCore"]),
    .testTarget(name: "MacterminalTerminalTests", dependencies: ["MacterminalTerminal"]),
  ]
)
