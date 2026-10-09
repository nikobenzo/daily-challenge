import ChallengeSyncKit
import Testing
@testable import DailyChallengeProof

/// The Mac's auth screen copy; the flows themselves are tested in ChallengeSyncKitTests.
@Test func macAuthCopyNamesNoFixedCodeLength() {
    for step in [AuthStep.createAccount, .forgotPassword, .confirmSignUp(email: "a@b.c"), .resetPassword(email: "a@b.c")] {
        #expect(!step.subtitle.contains("digit"))
    }
}
