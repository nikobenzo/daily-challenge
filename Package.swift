// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DailyChallenge",
    // iOS is for the iPhone app's Xcode project (iOS/), which links only the two libraries.
    platforms: [.macOS(.v14), .iOS("26.0")],
    products: [
        .executable(name: "DailyChallengeProof", targets: ["DailyChallengeProof"]),
        .library(name: "ChallengeCore", targets: ["ChallengeCore"]),
        .library(name: "ChallengeSyncKit", targets: ["ChallengeSyncKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", exact: "2.55.3"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0")
    ],
    targets: [
        .target(name: "ProbeCore"),
        .target(name: "ChallengeCore"),
        // Platform-neutral auth, transport and sync coordinator shared by the Mac and iPhone apps.
        .target(
            name: "ChallengeSyncKit",
            dependencies: ["ChallengeCore", .product(name: "Supabase", package: "supabase-swift")]
        ),
        .executableTarget(
            name: "DailyChallengeProof",
            dependencies: [
                "ProbeCore", "ChallengeCore", "ChallengeSyncKit",
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            // scripts/build-proof.sh embeds Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore"]),
        .testTarget(name: "ChallengeCoreTests", dependencies: ["ChallengeCore"]),
        .testTarget(
            name: "ChallengeSyncKitTests",
            dependencies: ["ChallengeSyncKit", "ChallengeCore", .product(name: "Supabase", package: "supabase-swift")]
        ),
        .testTarget(name: "TrackerInterfaceTests", dependencies: ["DailyChallengeProof", "ChallengeCore", "ChallengeSyncKit"]),
        .testTarget(
            name: "ProofAuthTests",
            dependencies: ["DailyChallengeProof", "ChallengeCore", "ChallengeSyncKit",
                           .product(name: "Supabase", package: "supabase-swift")]
        )
    ]
)
