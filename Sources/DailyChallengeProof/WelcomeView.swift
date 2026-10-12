import ChallengeCore
import SwiftUI

/// The welcome window's content: where the app lives, then the four steps with the
/// current one highlighted, and a celebration once the challenge starts.
struct WelcomeView: View {
    let model: WelcomeModel
    @Environment(\.trackerReduceMotionOverride) private var reduceMotionOverride
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var visible = false
    @State private var confettiStarted: Date?
    @State private var confettiPlayed = false

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        VStack(spacing: 0) {
            MenuBarIllustration(animate: visible && !reduceMotion && !model.celebrating)
                .padding(.top, 40)
                .padding(.horizontal, Theme.Size.sectionHorizontal)
            if model.celebrating {
                celebration.transition(.opacity)
            } else {
                steps.transition(.opacity)
            }
        }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .background { WelcomeBackground().ignoresSafeArea() }
        .overlay {
            if let confettiStarted { ConfettiView(started: confettiStarted).ignoresSafeArea() }
        }
        .animation(reduceMotion ? nil : Theme.Motion.crossFade, value: model.celebrating)
        .background { PopupVisibilityReader { visible = $0 } }
        // One burst when the challenge starts, if the window is on screen. It is never
        // restarted: the window's visibility can flicker while it resizes for the celebration.
        .onChange(of: model.celebrating) { _, _ in startConfetti() }
        .onChange(of: visible) { _, _ in startConfetti() }
        .task(id: confettiStarted) {
            guard confettiStarted != nil else { return }
            do { try await Task.sleep(for: .seconds(ConfettiBurst.duration)) } catch { return }
            confettiStarted = nil
        }
    }

    private func startConfetti() {
        guard model.celebrating, visible, !reduceMotion, !confettiPlayed else { return }
        confettiPlayed = true
        confettiStarted = Date()
    }

    // MARK: Steps

    private var steps: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Welcome to Daily Challenge").font(Theme.Fonts.screenTitle).tracking(Theme.Tracking.screenTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Your 75-day challenge lives in the menu bar. Four steps to begin.")
                    .font(Theme.Fonts.link).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, Theme.Space.l)
            .padding(.horizontal, Theme.Size.sectionHorizontal)
            VStack(spacing: 2) {
                ForEach(WelcomeStep.allCases, id: \.self) { step in
                    WelcomeStepRow(step: step, current: model.step, targets: model.targets)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, Theme.Space.m)
            HairlineDivider()
            actions
                .padding(.horizontal, Theme.Size.sectionHorizontal)
                .padding(.vertical, Theme.Space.l)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if model.step == .startDate {
            Button { model.openPopup(nil) } label: { Label("Choose your start date", systemImage: "calendar") }
                .buttonStyle(PrimaryPillStyle(height: Theme.Size.largePill, font: Theme.Fonts.appName))
                .keyboardShortcut(.defaultAction)
                .help("Opens Daily Challenge under its menu bar icon")
        } else {
            VStack(spacing: 14) {
                Button { model.openPopup(.createAccount) } label: { Label("Create an account", systemImage: "person.badge.plus") }
                    .buttonStyle(PrimaryPillStyle(height: Theme.Size.largePill, font: Theme.Fonts.appName))
                    .keyboardShortcut(.defaultAction)
                    .help("Opens Daily Challenge under its menu bar icon")
                Button("I already have an account") { model.openPopup(.signIn) }
                    .buttonStyle(LinkStyle())
                    .help("Opens sign in under the menu bar icon")
            }
        }
    }

    // MARK: Celebration

    private var celebration: some View {
        VStack(spacing: 12) {
            Circle().fill(Theme.done)
                .frame(width: 64, height: 64)
                .overlay { Image(systemName: "checkmark").font(.system(size: 28, weight: .heavy)).foregroundStyle(Theme.onDone) }
                .shadow(color: Theme.done.opacity(0.4), radius: 12, y: 6)
                .accessibilityHidden(true)
            Text("You're all set").font(Theme.Fonts.screenTitle).tracking(Theme.Tracking.screenTitle)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(WelcomeStepRow.started(startLabel: model.startLabel, targets: model.targets))
                .font(Theme.Fonts.field).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done") { model.close() }
                .buttonStyle(PrimaryPillStyle(height: Theme.Size.largePill, font: Theme.Fonts.appName))
                .keyboardShortcut(.defaultAction)
                .padding(.top, Theme.Space.xs)
        }
        .padding(.horizontal, Theme.Space.xxl)
        .padding(.top, Theme.Space.xl)
        .padding(.bottom, Theme.Space.l)
    }
}

/// One numbered step: done (green check), current (blue, highlighted) or still to come.
struct WelcomeStepRow: View {
    let step: WelcomeStep
    let current: WelcomeStep
    var targets = Challenge.Targets.standard

    private var done: Bool { step < current }
    private var isCurrent: Bool { step == current }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            disc
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.title(step)).font(Theme.Fonts.rowLabel)
                    .foregroundStyle(done ? Theme.textSecondary : Theme.textPrimary)
                Text(Self.detail(step, targets: targets)).font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if step == .logDay { habits.padding(.top, 4) }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(isCurrent ? Theme.accentTint : .clear)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue + 1) of \(WelcomeStep.allCases.count), \(done ? "done" : isCurrent ? "current" : "to do"): \(Self.title(step)). \(Self.detail(step, targets: targets))")
    }

    private var disc: some View {
        ZStack {
            if done {
                Circle().fill(Theme.done)
                Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.onDone)
            } else if isCurrent {
                Circle().fill(Theme.primaryGradient)
                Text("\(step.rawValue + 1)").font(Theme.Fonts.badge).foregroundStyle(.white)
            } else {
                Circle().strokeBorder(Theme.ringTrack, lineWidth: 2)
                Text("\(step.rawValue + 1)").font(Theme.Fonts.badge).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 28, height: 28)
    }

    /// The daily five's icons: generic rings, then the chosen goals' icons once set.
    private var habits: some View {
        let symbols = ["drop.fill"] + Challenge.TargetSlot.allCases.map { Goals.symbol($0, targets[$0]) }
        return HStack(spacing: 8) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(index == 0 ? Theme.water : Theme.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.controlFill))
            }
        }
    }

    static func title(_ step: WelcomeStep) -> String {
        switch step {
        case .menuBar: "Find the drop in your menu bar"
        case .account: "Create an account or sign in"
        case .startDate: "Choose your daily five and a start date"
        case .logDay: "Log your day"
        }
    }

    static func detail(_ step: WelcomeStep, targets: Challenge.Targets = .standard) -> String {
        switch step {
        case .menuBar: "Daily Challenge has no Dock icon. Click the drop near the clock to open it."
        case .account: "Your account keeps your challenge in sync on every device."
        case .startDate: "The standard five are filled in; change any of them. Day 1 and your time zone stay fixed once you start."
        case .logDay:
            targets == .standard
                ? "Unless you choose your own: \(Goals.sentence(targets)), every day."
                : "\(Goals.sentence(targets)), every day."
        }
    }

    /// The celebration: "Day 1 is Mon 12 Oct. Click the drop in the menu bar each day to log …".
    static func started(startLabel: String, targets: Challenge.Targets) -> String {
        let opening = startLabel.isEmpty ? "Your challenge has started." : "Day 1 is \(startLabel)."
        return "\(opening) Click the drop in the menu bar each day to log \(Goals.sentence(targets))."
    }
}

/// A sketch of the top of the screen: the menu bar with the app's drop icon picked out
/// and a callout under it. A menu-bar app is easy to miss, so this comes first.
struct MenuBarIllustration: View {
    /// Pulse the icon a few times; never more, so nothing keeps moving.
    let animate: Bool
    @State private var pulse = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [Theme.jugTop.opacity(0.45), Theme.primaryBottom.opacity(0.30)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(height: 112)
            .overlay(alignment: .top) { menuBar }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.glassBorder, lineWidth: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Illustration: the Daily Challenge icon, a drop in a circle, in the menu bar near the clock.")
            .task(id: animate) {
                // Three pulses once per window, not again after a visibility flicker.
                guard animate, pulse == 0 else { return }
                for _ in 0..<3 {
                    pulse += 1
                    do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
                }
            }
    }

    private var menuBar: some View {
        HStack(spacing: 12) {
            Circle().fill(Theme.textPrimary.opacity(0.55)).frame(width: 11, height: 11)
            ForEach([34.0, 26, 30, 40], id: \.self) { width in
                Capsule(style: .circular).fill(Theme.textPrimary.opacity(0.22)).frame(width: width, height: 7)
            }
            Spacer(minLength: 0)
            dropIcon
            Image(systemName: "wifi").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary.opacity(0.45))
            Image(systemName: "battery.75percent").font(.system(size: 13, weight: .regular)).foregroundStyle(Theme.textPrimary.opacity(0.45))
            Text("9:41").font(.system(size: 12, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.textPrimary.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(Theme.glass)
    }

    private var dropIcon: some View {
        Image(systemName: "drop.circle.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.accentText)
            .frame(width: 26, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.accentTint))
            .background {
                PulseRing(count: pulse)
            }
            .overlay(alignment: .top) { callout.offset(y: 30) }
    }

    private var callout: some View {
        VStack(spacing: 0) {
            Triangle().fill(Theme.primaryTop).frame(width: 14, height: 7)
            Label("Daily Challenge lives here", systemImage: "arrow.up")
                .labelStyle(.titleOnly)
                .font(Theme.Fonts.link).foregroundStyle(.white)
                .padding(.horizontal, 12).frame(height: 30)
                .background(Capsule(style: .circular).fill(Theme.primaryGradient))
                .shadow(color: Theme.primaryShadow, radius: 6, y: 3)
        }
        .fixedSize()
    }
}

/// An expanding ring behind the icon, once per increment of `count`.
private struct PulseRing: View {
    let count: Int
    @State private var expanded = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(Theme.accentText, lineWidth: 2)
            .scaleEffect(expanded ? 1.9 : 1)
            .opacity(expanded ? 0 : (count == 0 ? 0 : 0.8))
            .onChange(of: count) { _, _ in
                expanded = false
                withAnimation(.easeOut(duration: 1.2)) { expanded = true }
            }
            .accessibilityHidden(true)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// The window's glass: the system blur under the design's tint, opaque with Reduce Transparency.
private struct WelcomeBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Theme.solidGlass
        } else {
            ZStack {
                VisualEffectBlur(material: scheme == .dark ? .hudWindow : .popover)
                Theme.glass
            }
        }
    }
}
