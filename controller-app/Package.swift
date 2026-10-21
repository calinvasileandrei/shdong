// swift-tools-version:5.10
import Foundation
import PackageDescription

// With only the Command Line Tools installed (no Xcode), swift-testing lives outside the default
// search paths.
let cltDeveloper = "/Library/Developer/CommandLineTools/Library/Developer"
let hasCLTTesting = FileManager.default.fileExists(atPath: cltDeveloper + "/Frameworks/Testing.framework")
let testingSwiftFlags = hasCLTTesting ? ["-F", cltDeveloper + "/Frameworks"] : []
let testingLinkerFlags = hasCLTTesting
    ? ["-F", cltDeveloper + "/Frameworks",
       "-Xlinker", "-rpath", "-Xlinker", cltDeveloper + "/Frameworks",
       "-Xlinker", "-rpath", "-Xlinker", cltDeveloper + "/usr/lib"]
    : []

let package = Package(
    name: "Shdong",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Shdong", targets: ["Shdong"]),
        .executable(name: "shdong-mock-bridge", targets: ["ShdongMockBridge"]),
    ],
    targets: [
        // Pure logic shared by the app, the mock bridge and the tests: protocol, key map, mouse math.
        .target(name: "ShdongCore"),
        .executableTarget(
            name: "Shdong",
            dependencies: ["ShdongCore"],
            linkerSettings: [
                // Embed Info.plist so camera/accessibility prompts work even when run unbundled.
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist", "-Xlinker", "Resources/Info.plist"]),
            ]
        ),
        .executableTarget(name: "ShdongMockBridge", dependencies: ["ShdongCore"]),
        .testTarget(
            name: "ShdongCoreTests",
            dependencies: ["ShdongCore"],
            swiftSettings: [.unsafeFlags(testingSwiftFlags)],
            linkerSettings: [.unsafeFlags(testingLinkerFlags)]
        ),
    ]
)
