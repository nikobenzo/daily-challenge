import SwiftUI

/// Bounded procedural motion; its finite frame task ends after settling.
struct WaterJugView: View {
    let millilitres: Int
    @Environment(\.trackerReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.trackerPopupVisible) private var visible
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var motion: WaterMotion?
    @State private var frameDate = Date()
    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if let motion, motion.isActive(at: frameDate, visible: visible, reduceMotion: reduceMotion) {
                drawing(level: motion.level(at: frameDate), slosh: motion.slosh(at: frameDate),
                        spill: motion.spills ? 1 - motion.progress(at: frameDate) : 0)
            } else {
                drawing(level: min(1, max(0, Double(millilitres) / 4_000)), slosh: 0, spill: 0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Four-litre water jug")
        .accessibilityValue("\(millilitres) of 4,000 millilitres\(millilitres > 4_000 ? ", goal exceeded" : "")")
        .onChange(of: millilitres) { old, new in
            let presentationLevel = motion?.level(at: frameDate)
            frameDate = Date()
            motion = visible && !reduceMotion
                ? WaterMotion(from: old, to: new, started: frameDate, presentationLevel: presentationLevel)
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

    /// 88 × 112 jug (board viewBox 124 × 158): glass vessel, gradient water, handle and cap.
    /// Over the goal the water stays at the rim and droplets sit under the jug.
    private func drawing(level: Double, slosh: Double, spill: Double) -> some View {
        let outline = contrast == .increased ? Theme.textPrimary : Theme.jugOutline
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(outline.opacity(0.75), lineWidth: 5)
                .frame(width: 30, height: 44)
                .offset(x: 56, y: 42)
            ZStack {
                JugVessel().fill(reduceTransparency ? Theme.solidGlass : Theme.jugGlass)
                JugWater(level: level, slosh: slosh)
                    .fill(Theme.jugGradient)
                    .clipShape(JugVessel())
                JugVessel().stroke(outline, lineWidth: 2.5)
                Capsule(style: .circular).fill(.white.opacity(0.35)).frame(width: 4, height: 54).offset(x: -21, y: 14)
            }
            .frame(width: 66, height: 100)
            .offset(y: 10)
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.jugGlass)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(outline, lineWidth: 2))
                .frame(width: 28, height: 8)
                .offset(x: 19, y: 3)
            if millilitres > 4_000 {
                HStack(spacing: 34) {
                    ForEach(0..<2) { _ in Image(systemName: "drop.fill").font(.system(size: 8)) }
                }
                .foregroundStyle(Theme.water)
                .offset(x: 13, y: 113)
            }
            if spill > 0 {
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        Image(systemName: "drop.fill").font(.system(size: 8)).offset(y: CGFloat(index % 2) * 6)
                    }
                }.foregroundStyle(Theme.water).opacity(spill)
                    .offset(x: 16, y: -2 - (1 - spill) * 12)
            }
        }
        .frame(width: Theme.Size.jug.width + 8, height: Theme.Size.jug.height + 14, alignment: .topLeading)
    }
}

private struct JugVessel: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        return Path { path in
            path.move(to: CGPoint(x: w * 0.33, y: 0))
            path.addLine(to: CGPoint(x: w * 0.67, y: 0))
            path.addLine(to: CGPoint(x: w * 0.67, y: h * 0.12))
            path.addQuadCurve(to: CGPoint(x: w * 0.94, y: h * 0.31), control: CGPoint(x: w * 0.94, y: h * 0.16))
            path.addLine(to: CGPoint(x: w * 0.94, y: h * 0.88))
            path.addQuadCurve(to: CGPoint(x: w * 0.81, y: h), control: CGPoint(x: w * 0.94, y: h))
            path.addLine(to: CGPoint(x: w * 0.19, y: h))
            path.addQuadCurve(to: CGPoint(x: w * 0.06, y: h * 0.88), control: CGPoint(x: w * 0.06, y: h))
            path.addLine(to: CGPoint(x: w * 0.06, y: h * 0.31))
            path.addQuadCurve(to: CGPoint(x: w * 0.33, y: h * 0.12), control: CGPoint(x: w * 0.06, y: h * 0.16))
            path.closeSubpath()
        }
    }
}

private struct JugWater: Shape {
    var level: Double
    var slosh: Double

    func path(in rect: CGRect) -> Path {
        guard level > 0 else { return Path() }
        let surface = rect.height * (1 - min(1, max(0, level)))
        return Path { path in
            path.move(to: CGPoint(x: 0, y: surface))
            for step in 0...24 {
                let x = rect.width * Double(step) / 24
                let wave = sin(Double(step) / 24 * .pi * 2) * slosh
                path.addLine(to: CGPoint(x: x, y: surface + wave))
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
