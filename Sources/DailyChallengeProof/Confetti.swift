import SwiftUI

/// The setup celebration: one finite burst of confetti falling across the welcome window.
/// Pieces are seeded, so every run (and every capture) draws the same burst. The view that
/// shows it removes it after `duration`, runs it only while the window is visible and
/// skips it under Reduce Motion, so nothing animates on its own afterwards.
struct ConfettiBurst {
    static let duration: TimeInterval = 3.2
    /// The last stretch fades every piece out, so the burst never stops mid-air.
    static let fade: TimeInterval = 0.7
    static let colors = [Theme.water, Theme.done, Theme.amber, Theme.primaryTop, Theme.jugTop, Theme.doneText]

    struct Piece {
        let x: Double, drift: Double, speed: Double, delay: Double, spin: Double, phase: Double
        let size: CGSize, color: Int, round: Bool
    }

    struct Placement {
        let point: CGPoint, angle: Double, opacity: Double
    }

    let pieces: [Piece]

    init(count: Int = 80, seed: UInt64 = 75) {
        var random = SplitMix(seed: seed)
        pieces = (0..<count).map { _ in
            Piece(x: .random(in: 0...1, using: &random), drift: .random(in: -36...36, using: &random),
                  speed: .random(in: 40...150, using: &random), delay: .random(in: 0...0.6, using: &random),
                  spin: .random(in: -7...7, using: &random), phase: .random(in: 0...(2 * .pi), using: &random),
                  size: CGSize(width: .random(in: 6...10, using: &random), height: .random(in: 3...6, using: &random)),
                  color: .random(in: 0..<Self.colors.count, using: &random), round: Double.random(in: 0...1, using: &random) < 0.25)
        }
    }

    /// Where a piece is `time` seconds into the burst in a canvas `width` wide, or nil when
    /// it is not drawn (not yet released, or the burst is over).
    func placement(of piece: Piece, at time: TimeInterval, width: CGFloat) -> Placement? {
        let local = time - piece.delay
        guard local >= 0, time < Self.duration else { return nil }
        let gravity = 220.0
        let y = -12 + piece.speed * local + gravity * local * local / 2
        let x = piece.x * width + piece.drift * local + sin(piece.phase + local * 5) * 10
        let opacity = min(1, max(0, (Self.duration - time) / Self.fade))
        return Placement(point: CGPoint(x: x, y: y), angle: piece.phase + piece.spin * local, opacity: opacity)
    }

    /// A small deterministic generator (SplitMix64).
    struct SplitMix: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}

/// Draws a burst that started at `started`. Its parent removes it once the burst is over.
struct ConfettiView: View {
    let started: Date
    private let burst = ConfettiBurst()

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSince(started)
            Canvas { canvas, size in
                for piece in burst.pieces {
                    guard let placement = burst.placement(of: piece, at: time, width: size.width) else { continue }
                    var layer = canvas
                    layer.opacity = placement.opacity
                    layer.translateBy(x: placement.point.x, y: placement.point.y)
                    layer.rotate(by: .radians(placement.angle))
                    let rect = CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2,
                                      width: piece.size.width, height: piece.size.height)
                    layer.fill(piece.round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1),
                               with: .color(ConfettiBurst.colors[piece.color]))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
