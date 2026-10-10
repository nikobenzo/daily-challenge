import AppIntents
import ChallengeCore
import SwiftUI
import WidgetKit

/// Runs in the widget extension; no app process, network or session is involved.
/// Success means durably saved to the shared pending queue: the app uploads it on its
/// next foreground or iOS-selected refresh. Failures are calm: history is untouched
/// and the reload shows the stored state (or "Open Daily Challenge"), never success.
enum WidgetIntentRunner {
    static func run(_ request: WidgetActionRequest?) {
        defer { WidgetCenter.shared.reloadAllTimelines() }
        guard let request else { return }
        // A fresh event ID for every perform(): parameters are archived with the
        // rendered timeline, so a render-time ID would merge distinct taps.
        _ = try? WidgetActionRecorder(store: .widgetExtension()).perform(request)
    }
}

struct PourWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Add 450 ml of water"
    static let isDiscoverable = false
    @Parameter(title: "Generation") var generation: String
    @Parameter(title: "Challenge") var challenge: String
    init() {}
    init(_ binding: WidgetActionBinding) {
        generation = binding.generation.uuidString
        challenge = binding.challengeID.uuidString
    }
    func perform() async throws -> some IntentResult {
        WidgetIntentRunner.run(WidgetActionRequest(kind: .pour, generation: generation, challenge: challenge))
        return .result()
    }
}

struct UndoWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo today's latest pour"
    static let isDiscoverable = false
    @Parameter(title: "Generation") var generation: String
    @Parameter(title: "Challenge") var challenge: String
    init() {}
    init(_ binding: WidgetActionBinding) {
        generation = binding.generation.uuidString
        challenge = binding.challengeID.uuidString
    }
    func perform() async throws -> some IntentResult {
        WidgetIntentRunner.run(WidgetActionRequest(kind: .undoPour, generation: generation, challenge: challenge))
        return .result()
    }
}

struct ToggleHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Tick or untick a requirement"
    static let isDiscoverable = false
    @Parameter(title: "Requirement") var habit: String
    @Parameter(title: "Generation") var generation: String
    @Parameter(title: "Challenge") var challenge: String
    init() {}
    init(_ habit: Challenge.Habit, _ binding: WidgetActionBinding) {
        self.habit = habit.rawValue
        generation = binding.generation.uuidString
        challenge = binding.challengeID.uuidString
    }
    func perform() async throws -> some IntentResult {
        WidgetIntentRunner.run(WidgetActionRequest(kind: .habit, target: habit, generation: generation, challenge: challenge))
        return .result()
    }
}

/// D-W1: pending ↔ clean only. A stored missed day is left alone.
struct SetDietIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark the diet clean or pending"
    static let isDiscoverable = false
    @Parameter(title: "Generation") var generation: String
    @Parameter(title: "Challenge") var challenge: String
    init() {}
    init(_ binding: WidgetActionBinding) {
        generation = binding.generation.uuidString
        challenge = binding.challengeID.uuidString
    }
    func perform() async throws -> some IntentResult {
        WidgetIntentRunner.run(WidgetActionRequest(kind: .diet, generation: generation, challenge: challenge))
        return .result()
    }
}

struct ToggleExtraIntent: AppIntent {
    static let title: LocalizedStringResource = "Tick or untick an extra"
    static let isDiscoverable = false
    @Parameter(title: "Extra") var extra: String
    @Parameter(title: "Generation") var generation: String
    @Parameter(title: "Challenge") var challenge: String
    init() {}
    init(_ extra: UUID, _ binding: WidgetActionBinding) {
        self.extra = extra.uuidString
        generation = binding.generation.uuidString
        challenge = binding.challengeID.uuidString
    }
    func perform() async throws -> some IntentResult {
        WidgetIntentRunner.run(WidgetActionRequest(kind: .extra, target: extra, generation: generation, challenge: challenge))
        return .result()
    }
}

/// Buttons, not intent Toggles: WidgetKit flips a Toggle optimistically, before the
/// transaction has succeeded.
struct WidgetIntentButton<Label: View>: View {
    let request: WidgetActionRequest
    let label: Label
    var body: some View {
        Group {
            switch request.action {
            case .pour: Button(intent: PourWaterIntent(request.binding)) { label }
            case .undoPour: Button(intent: UndoWaterIntent(request.binding)) { label }
            case .toggleHabit(let habit): Button(intent: ToggleHabitIntent(habit, request.binding)) { label }
            case .toggleDiet: Button(intent: SetDietIntent(request.binding)) { label }
            case .toggleExtra(let id): Button(intent: ToggleExtraIntent(id, request.binding)) { label }
            }
        }.buttonStyle(.plain)
    }
}
