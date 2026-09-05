// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KVNotesKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "KVNotesKit", targets: ["KVNotesKit"]),
        .library(name: "KVNotesCore", targets: ["KVNotesCore"]),
        .library(name: "KVNotesUI", targets: ["KVNotesUI"]),
        .library(name: "KVNotesTesting", targets: ["KVNotesTesting"])
    ],
    targets: [
        .target(name: "KVNotesCore"),
        .target(
            name: "KVNotesUI",
            dependencies: ["KVNotesCore", "KVNotesTesting"],
            resources: [.process("Resources")]
        ),
        .target(name: "KVNotesTesting", dependencies: ["KVNotesCore"]),
        .target(name: "KVNotesKit", dependencies: ["KVNotesCore", "KVNotesUI"]),
        .testTarget(
            name: "KVNotesTargetBoundaryTests",
            dependencies: ["KVNotesCore", "KVNotesUI", "KVNotesTesting", "KVNotesKit"]
        ),
        .testTarget(name: "KVNotesCoreTests", dependencies: ["KVNotesCore"]),
        .testTarget(
            name: "KVNotesTestingTests",
            dependencies: ["KVNotesCore", "KVNotesTesting"]
        ),
        .testTarget(name: "KVNotesUITests", dependencies: ["KVNotesUI"])
    ],
    swiftLanguageModes: [.v6]
)
