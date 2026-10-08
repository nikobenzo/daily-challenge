// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DailyChallenge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DailyChallengeProof", targets: ["DailyChallengeProof"])
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", exact: "2.55.3")
    ],
    targets: [
        .target(name: "ProbeCore"),
        .target(name: "ChallengeCore"),
        .executableTarget(
            name: "DailyChallengeProof",
            dependencies: ["ProbeCore", "ChallengeCore", .product(name: "Supabase", package: "supabase-swift")]
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
