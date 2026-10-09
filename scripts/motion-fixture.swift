// Standalone offline fixture: only production motion views and pure challenge rules.
// No auth, Keychain, user defaults, network, or production data paths are linked.
import AppKit
import ChallengeSyncKit
import Observation
import SwiftUI

@MainActor @Observable final class FixtureState {
    var amount = 3_600
    var celebration: CelebrationEvent?
    var visible = false
    let motionDisabled = CommandLine.arguments.contains("--no-motion")
}

struct FixtureSurface: View {
    let state: FixtureState
    var body: some View {
        VStack(spacing: 14) {
            Text("Daily Challenge · MOTION FIXTURE").font(.headline)
            WaterJugView(millilitres: state.amount)
                .overlay { CompletionEffect(event: state.celebration) }
            Button("\(state.amount) ml · fixture only") {}
        }
        .padding(16).frame(width: 420, height: 320)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .environment(\.trackerPopupVisible, state.visible)
        .environment(\.trackerReduceMotionOverride, state.motionDisabled ? true : nil)
        .background { PopupVisibilityReader { state.visible = $0 } }
    }
}

@main struct MotionFixture {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let state = FixtureState()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 420, height: 320),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Daily Challenge MOTION FIXTURE"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FixtureSurface(state: state))
        let visibility = FixtureVisibilityMonitor(window: window)
        func cpuSeconds() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        Task { @MainActor in
            // Allow launch work to settle before sampling.
            print("MODE \(state.motionDisabled ? "motion-disabled" : "motion-enabled") · cumulative getrusage CPU deltas")
            try? await Task.sleep(for: .seconds(3))
            for phase in ["hidden", "idle-open", "animating", "settled", "hidden-after"] {
                if phase == "idle-open" {
                    window.orderFrontRegardless()
                    app.activate(ignoringOtherApps: true)
                }
                if phase == "hidden-after" {
                    // Dismiss during an effect, not only after an idle window.
                    state.amount = 4_950
                    state.celebration = CelebrationEvent(kind: .milestone, started: Date())
                    try? await Task.sleep(for: .seconds(0.2))
                    window.orderOut(nil)
                }
                try? await Task.sleep(for: .seconds(phase == "settled" ? 10 : 4))
                let expectedVisible = !phase.hasPrefix("hidden")
                visibility.begin(expectedVisible: expectedVisible)
                guard visibility.validate() else {
                    print("INVALID: fixture visibility does not match phase \(phase)")
                    exit(2)
                }
                let start = Date(), cpuStart = cpuSeconds()
                print("START \(phase) visible=\(state.visible)")
                fflush(stdout)
                if phase == "animating" {
                    for index in 0..<10 {
                        guard visibility.validate() else { print("INVALID: fixture became occluded"); exit(2) }
                        state.amount = index.isMultiple(of: 2) ? 4_500 : 3_600
                        state.celebration = CelebrationEvent(kind: index.isMultiple(of: 2) ? .daily : .milestone, started: Date())
                        try? await Task.sleep(for: .seconds(1))
                    }
                } else if phase == "settled" {
                    // Two independent instantaneous CPU-time deltas, not ps's
                    // decaying %CPU average. Start after ten seconds of settling.
                    for interval in 1...2 {
                        let intervalStart = Date(), intervalCPU = cpuSeconds()
                        try? await Task.sleep(for: .seconds(30))
                        let wall = Date().timeIntervalSince(intervalStart), cpu = cpuSeconds() - intervalCPU
                        guard visibility.validate() else {
                            print("INVALID: fixture visibility changed during settled")
                            exit(2)
                        }
                        print(String(format: "DELTA settled-%d wall=%.3fs cpu=%.4fs average=%.3f%%", interval, wall, cpu, 100 * cpu / wall))
                        fflush(stdout)
                    }
                } else { try? await Task.sleep(for: .seconds(10)) }
                guard visibility.validate() else {
                    print("INVALID: fixture visibility changed during \(phase)")
                    exit(2)
                }
                let elapsed = Date().timeIntervalSince(start)
                print(String(format: "RESULT %@ wall=%.3fs cpu=%.4fs average=%.3f%% visible=%@", phase, elapsed,
                             cpuSeconds() - cpuStart, 100 * (cpuSeconds() - cpuStart) / elapsed, String(state.visible)))
                fflush(stdout)
            }
            window.close()
            app.terminate(nil)
        }
        app.run()
    }
}
