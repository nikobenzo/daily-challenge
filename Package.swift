// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DailyChallenge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DailyChallengeProof", targets: ["DailyChallengeProof"])
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", exact: "2.55.3"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0")
    ],
    targets: [
        .target(name: "ProbeCore"),
        .target(name: "ChallengeCore"),
        .executableTarget(
            name: "DailyChallengeProof",
            dependencies: [
                "ProbeCore", "ChallengeCore",
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "Sparkle", package: "Sparkle")
            ],
            // scripts/build-proof.sh embeds Sparkle.framework in Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "ProbeCoreTests", dependencies: ["ProbeCore"]),
        .testTarget(name: "ChallengeCoreTests", dependencies: ["ChallengeCore"]),
        .testTarget(name: "TrackerInterfaceTests", dependencies: ["DailyChallengeProof", "ChallengeCore"]),
        .testTarget(
            name: "ProofAuthTests",
            dependencies: ["DailyChallengeProof", "ChallengeCore", .product(name: "Supabase", package: "supabase-swift")]
        )
    ]
)
