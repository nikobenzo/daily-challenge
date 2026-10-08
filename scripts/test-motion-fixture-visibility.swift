import AppKit

@main struct FixtureVisibilityTests {
    static func main() {
        for expected in [false, true] {
            var stable = FixtureVisibilityInterval(expectedVisible: expected, initialVisible: expected)
            for _ in 0..<10 { stable.observe(expected) }
            precondition(stable.isValid)

            var interrupted = FixtureVisibilityInterval(expectedVisible: expected, initialVisible: expected)
            for visible in [expected, !expected, expected] { interrupted.observe(visible) }
            precondition(!interrupted.isValid)
            for _ in 0..<10 { interrupted.observe(expected) }
            precondition(!interrupted.isValid)

            var wrongStart = FixtureVisibilityInterval(expectedVisible: expected, initialVisible: !expected)
            wrongStart.observe(expected)
            precondition(!wrongStart.isValid)

            var wrongEnd = FixtureVisibilityInterval(expectedVisible: expected, initialVisible: expected)
            wrongEnd.observe(!expected)
            precondition(!wrongEnd.isValid)

            interrupted = FixtureVisibilityInterval(expectedVisible: expected, initialVisible: expected)
            precondition(interrupted.isValid)
        }
        print("Fixture visibility transition tests passed")
    }
}
