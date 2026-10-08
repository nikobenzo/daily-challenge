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

    private func drawing(level: Double, slosh: Double, spill: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.primary.opacity(contrast == .increased ? 1 : 0.5), lineWidth: 5)
                .frame(width: 47, height: 93).offset(x: 82, y: 9)
            ZStack {
                JugVessel().fill(Color(nsColor: .controlBackgroundColor).opacity(reduceTransparency ? 1 : 0.5))
                JugWater(level: level, slosh: slosh)
                    .fill(LinearGradient(colors: [.cyan.opacity(0.75), .blue.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                    .clipShape(JugVessel())
                JugVessel().stroke(.primary.opacity(contrast == .increased ? 1 : 0.5), lineWidth: 2)
                Capsule().fill(.white.opacity(0.35)).frame(width: 6, height: 78).offset(x: -46, y: 28)
                ForEach([3, 2, 1], id: \.self) { litre in
                    HStack(spacing: 4) {
                        Rectangle().fill(.primary).frame(width: 9, height: 1)
                        Text("\(litre)").font(.system(size: 9, weight: .medium, design: .rounded))
                    }.padding(2)
                        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 3))
                        .offset(x: 43, y: (0.5 - Double(litre) / 4) * 174)
                }
                Text("4 L").font(.caption2.weight(.bold)).padding(2)
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 3))
                    .offset(y: -56)
            }.frame(width: 150, height: 174)
            RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.5))
                .frame(width: 55, height: 10).offset(y: -84)
            if spill > 0 {
                HStack(spacing: 6) {
                    ForEach(0..<3) { index in
                        Image(systemName: "drop.fill").font(.system(size: 9)).offset(y: CGFloat(index % 2) * 7)
                    }
                }.foregroundStyle(.primary).opacity(spill)
                    .offset(x: -70 - (1 - spill) * 12, y: -35 + (1 - spill) * 115)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .clipped()
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
