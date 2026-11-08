// swift-tools-version: 6.0
import PackageDescription

// nur fuer die logik-tests auf dem host (swift test). Die app selbst baut ueber project.yml (XcodeGen).
let package = Package(
    name: "FairyLogic",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FairyLogic", path: "HelloFairy/Logic"),
        .testTarget(name: "FairyLogicTests", dependencies: ["FairyLogic"], path: "Tests/FairyLogicTests"),
    ],
    swiftLanguageModes: [.v5]
)
