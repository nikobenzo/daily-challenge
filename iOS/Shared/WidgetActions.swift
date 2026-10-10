import ChallengeCore
import Foundation

/// The only identity a widget control carries: opaque, credential-free, and refused
/// once the app publishes another account generation or challenge.
struct WidgetActionBinding: Equatable, Sendable {
    let generation: UUID
    let challengeID: UUID
}

/// What a widget tap asks for. The stored state, re-read under the lock, decides the
/// actual event; nothing rendered (a completion, an amount, a day) is authoritative.
struct WidgetActionRequest: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case pour, undoPour, toggleHabit(Challenge.Habit), toggleDiet, toggleExtra(UUID)
    }
    enum Kind: String, Sendable { case pour, undoPour, habit, diet, extra }

    let action: Action
    let binding: WidgetActionBinding

    init(_ action: Action, binding: WidgetActionBinding) {
        self.action = action
        self.binding = binding
    }

    /// Intent parameters arrive as strings. Only supported habit identifiers, extra
    /// UUIDs and the opaque binding parse; there is no owner, date, amount or path.
    init?(kind: Kind, target: String = "", generation: String, challenge: String) {
        guard let generation = UUID(uuidString: generation), let challenge = UUID(uuidString: challenge) else { return nil }
        switch kind {
        case .pour: action = .pour
        case .undoPour: action = .undoPour
        case .diet: action = .toggleDiet
        case .habit:
            guard let habit = Challenge.Habit(rawValue: target) else { return nil }
            action = .toggleHabit(habit)
        case .extra:
            guard let id = UUID(uuidString: target) else { return nil }
            action = .toggleExtra(id)
        }
        binding = WidgetActionBinding(generation: generation, challengeID: challenge)
    }
}

enum WidgetActionOutcome: Equatable, Sendable {
    /// Durably saved in the shared history and pending queue; not yet uploaded.
    case recorded(UUID)
    /// Minus with no pour today: no event and no error.
    case unchanged
    /// A diet already marked missed is left alone; the widget links into the app.
    case openApp
}

enum WidgetActionError: LocalizedError {
    case refused
    var errorDescription: String? { "That item is no longer on today's list. Open Daily Challenge to see it." }
}

/// Durable widget writes without an app process or a SwiftUI binding. Every action is
/// an existing `Challenge.Action` recorded through `ChallengeStore.record` in the
/// shared store's locked fresh-load transaction, so the app's next foreground or
/// refresh sync uploads it like any other pending event.
struct WidgetActionRecorder {
    static let pourMillilitres = 450

    let store: PhoneSharedStore
    var clock: () -> Date = Date.init
    var onCommitted: () -> Void = {}

    /// `invocationID` is the event ID: one per perform, reused only when the same
    /// invocation retries, so a retry never adds a second event while distinct taps
    /// stay distinct. Errors leave the prior history untouched.
    func perform(_ request: WidgetActionRequest, invocationID: UUID = UUID()) throws -> WidgetActionOutcome {
        let (_, outcome) = try store.transaction(generation: request.binding.generation,
                                                 challengeID: request.binding.challengeID) { current -> WidgetActionOutcome in
            guard let challenge = current.challenge else { throw ChallengeStoreError.notStarted }
            if challenge.allActivities.contains(where: { $0.id == invocationID }) { return .recorded(invocationID) }
            // Captured once, under the lock: the execution day, never the rendered one.
            let now = clock()
            let today = challenge.summary(on: now, asOf: now)
            guard today.status != .outsideChallenge, today.status != .future else { throw ChallengeError.dateOutsideChallenge }
            let action: Challenge.Action
            switch request.action {
            case .pour:
                action = .pour(Self.pourMillilitres)
            case .undoPour:
                guard !today.activePours.isEmpty else { return .unchanged }
                action = .undoLatestPour
            case .toggleHabit(let habit):
                action = .setHabit(habit, completed: !today.completedHabits.contains(habit))
            case .toggleDiet:
                switch today.diet {
                case .missed: return .openApp
                case .pending: action = .setDiet(.clean)
                case .clean: action = .setDiet(.pending)
                }
            case .toggleExtra(let id):
                guard today.extras.contains(where: { $0.id == id }) else { throw WidgetActionError.refused }
                action = .setExtra(id: id, completed: !today.completedExtras.contains(id))
            }
            guard let recorded = try current.record(action, on: now, at: now, id: invocationID) else { return .unchanged }
            return .recorded(recorded)
        }
        if case .recorded = outcome { onCommitted() }
        return outcome
    }
}

extension PhoneSharedStore {
    /// The extension's view of the group: no legacy root, never relocation or account
    /// selection (it only reads metadata the app published).
    static func widgetExtension() -> PhoneSharedStore {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        #if DEBUG
        // An explicit persisted fixture switch crosses the process boundary. It is
        // absent in Release, and fixture history never shares the production root.
        if let container, FileManager.default.fileExists(atPath: container.appendingPathComponent("widget-fixture-enabled").path) {
            return PhoneSharedStore(root: container.appendingPathComponent("WidgetFixtures"))
        }
        #endif
        return PhoneSharedStore(root: container?.appendingPathComponent("ChallengeHistory"))
    }
}
