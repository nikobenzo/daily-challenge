import SwiftUI

struct CompletionEffect: View {
    let event: CelebrationEvent?
    @Environment(\.trackerReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.trackerPopupVisible) private var visible
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var active: CelebrationEvent?
    @State private var frameDate = Date()
    private struct PlaybackKey: Equatable {
        let event: CelebrationEvent?
        let reduceMotion: Bool
    }
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        let presentation = active?.presentation(at: frameDate, visible: visible, reduceMotion: reduceMotion) ?? .idle
        Group {
            if let active, presentation != .idle {
                if presentation == .highlight {
                    badge(active.kind)
                } else {
                    let progress = min(1, max(0, frameDate.timeIntervalSince(active.started) / active.duration))
                    ZStack {
                        ForEach(0..<(active.kind == .milestone ? 16 : 8), id: \.self) { index in
                            let angle = Double(index) * .pi / (active.kind == .milestone ? 8 : 4)
                            Image(systemName: "sparkle")
                                .foregroundStyle(Theme.done)
                                .offset(x: cos(angle) * (30 + progress * 110), y: sin(angle) * (20 + progress * 55))
                                .opacity(1 - progress)
                        }
                        badge(active.kind)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: event) { _, event in
            frameDate = Date()
            active = visible ? event : nil
        }
        .onChange(of: visible) { _, _ in active = nil }
        .onDisappear { active = nil }
        .task(id: PlaybackKey(event: active, reduceMotion: reduceMotion)) {
            guard let active else { return }
            do {
                if reduceMotion {
                    // One deadline only: a static badge must not schedule frames.
                    try await Task.sleep(for: .seconds(max(0, active.started.addingTimeInterval(active.duration).timeIntervalSinceNow)))
                } else {
                    try await renderFiniteFrames(active.frameDates) { frameDate = $0 }
                }
            } catch { return }
            self.active = nil
        }
    }

    private func badge(_ kind: CompletionCelebration) -> some View {
        Label(kind == .milestone ? "75 consecutive days!" : "All five complete!",
              systemImage: kind == .milestone ? "trophy.fill" : "checkmark.seal.fill")
            .font(kind == .milestone ? Theme.Fonts.appName : Theme.Fonts.pill)
            .foregroundStyle(Theme.doneText)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Theme.solidGlass, in: Capsule(style: .circular))
            .overlay { Capsule(style: .circular).strokeBorder(Theme.done, lineWidth: 1.5) }
    }
}
