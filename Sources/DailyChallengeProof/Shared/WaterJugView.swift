import ChallengeSyncKit
import SwiftUI

/// Bounded procedural motion; its finite frame task ends after settling.
struct WaterJugView: View {
    let millilitres: Int
    /// The day's water goal: a full jug.
    var goal = 4_000
    @Environment(\.trackerReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.trackerPopupVisible) private var visible
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var motion: WaterMotion?
    @State private var frameDate = Date()
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        Group {
            if let motion, motion.isActive(at: frameDate, visible: visible, reduceMotion: reduceMotion) {
                drawing(level: motion.level(at: frameDate), slosh: motion.slosh(at: frameDate),
                        spill: motion.spills ? 1 - motion.progress(at: frameDate) : 0)
            } else {
                drawing(level: min(1, max(0, Double(millilitres) / Double(goal))), slosh: 0, spill: 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goal == 4_000 ? "Four-litre water jug" : "Water jug")
        .accessibilityValue("\(millilitres) of \(goal.formatted()) millilitres\(millilitres > goal ? ", goal exceeded" : "")")
        .onChange(of: millilitres) { old, new in
            let presentationLevel = motion?.level(at: frameDate)
            frameDate = Date()
            motion = visible && !reduceMotion
                ? WaterMotion(from: old, to: new, started: frameDate, presentationLevel: presentationLevel, goal: goal)
                : nil
        }
        .onChange(of: visible) { _, _ in motion = nil }
        .onChange(of: reduceMotion) { _, _ in motion = nil }
        .onDisappear { motion = nil }
        .task(id: motion) {
            guard let motion else { return }
            do { try await renderFiniteFrames(motion.frameDates) { frameDate = $0 } } catch { return }
            self.motion = nil
        }
    }

    private func drawing(level: Double, slosh: Double, spill: Double) -> some View {
        JugDrawing(millilitres: millilitres, level: level, goal: goal, slosh: slosh, spill: spill)
    }
}
