import ChallengeCore
import Foundation
import Testing

// The shared rule and wire-format vectors in test-vectors/challenge-rules.json. The Android
// port runs the same file (android/core/src/test/.../ParityVectorTest.kt), so both clients
// are held to the same results; this test proves the expected values against ChallengeCore.

private func vectors() -> [String: Any] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("test-vectors/challenge-rules.json")
    return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
}

private func list(_ key: String) -> [[String: Any]] { vectors()[key] as! [[String: Any]] }

private func date(_ value: Any?) -> Date {
    if let text = value as? String { return ISO8601DateFormatter().date(from: text)! }
    return Date(timeIntervalSinceReferenceDate: (value as! NSNumber).doubleValue)
}

private func decode<T: Decodable>(_ type: T.Type, _ value: Any) throws -> T {
    try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed))
}

private func uuid(_ value: Any?) -> UUID { UUID(uuidString: value as! String)! }

private func errorName(_ error: any Error) -> String {
    (error as? ChallengeError).map { String(describing: $0) } ?? "unexpected \(error)"
}

private func statusName(_ status: Challenge.DayStatus) -> String { status.rawValue }

/// "once", "weekdays 1 2 3" or "every 2", as the vectors write a repeat rule.
private func scheduleName(_ schedule: Challenge.ExtraSchedule) -> String {
    switch schedule {
    case .once: "once"
    case .weekdays(let days): (["weekdays"] + days.sorted().map(String.init)).joined(separator: " ")
    case .every(let interval): "every \(interval)"
    }
}

/// A slot's or water's expected target; every field is given, null for none.
private func expectTargets(_ targets: Challenge.Targets, _ want: [String: Any], _ comment: Comment) {
    for (key, value) in want {
        let fields = value as! [String: Any]
        func optional<T>(_ field: String) -> T? { fields[field] is NSNull ? nil : fields[field] as? T }
        if key == "water" {
            #expect(targets.water == .init(goal: fields["goal"] as! Int, glass: fields["glass"] as! Int), comment)
        } else {
            let target = targets[Challenge.TargetSlot(rawValue: key)!]
            #expect(target == .init(name: fields["name"] as! String, amount: optional("amount"),
                                    unit: (optional("unit") as String?).map { Challenge.TargetUnit(rawValue: $0)! },
                                    icon: optional("icon")), comment)
        }
    }
}

@Test func parityRuleCasesMatchChallengeCore() throws {
    for vector in list("cases") {
        let name = vector["name"] as! String
        var challenge = Challenge(ownerID: uuid(vector["owner"]), startDate: date(vector["start"]),
                                  timeZone: Challenge.canonicalTimeZone(vector["timeZone"] as! String)!)
        for (index, step) in (vector["steps"] as! [[String: Any]]).enumerated() {
            let where_ = Comment(rawValue: "\(name), step \(index + 1) (\(step["op"]!))")
            switch step["op"] as! String {
            case "record":
                let action = try decode(Challenge.Action.self, step["action"]!)
                do {
                    let result = try challenge.record(action, on: date(step["on"]), at: date(step["at"]),
                                                      id: uuid(step["id"]), deviceID: step["device"] as? String)
                    #expect(step["error"] == nil, where_)
                    if step.keys.contains("returns") { #expect(result == nil, where_) }
                    else { #expect(result == uuid(step["id"]), where_) }
                } catch {
                    #expect(errorName(error) == step["error"] as? String, where_)
                }
            case "merge":
                let events = try (step["events"] as! [Any]).map { try decode(Challenge.Activity.self, $0) }
                do {
                    try challenge.merge(events)
                    #expect(step["error"] == nil, where_)
                } catch {
                    #expect(errorName(error) == step["error"] as? String, where_)
                }
            case "summary":
                let summary = challenge.summary(on: date(step["on"]), asOf: date(step["asOf"]))
                if let water = step["water"] as? Int { #expect(summary.waterMillilitres == water, where_) }
                if let value = step["waterComplete"] as? Bool { #expect(summary.waterComplete == value, where_) }
                if let value = step["complete"] as? Bool { #expect(summary.isComplete == value, where_) }
                if let value = step["status"] as? String { #expect(statusName(summary.status) == value, where_) }
                if let value = step["diet"] as? String { #expect(summary.diet.rawValue == value, where_) }
                if let value = step["habits"] as? [String] {
                    #expect(Set(summary.completedHabits.map(\.rawValue)) == Set(value), where_)
                }
                if let value = step["pours"] as? [String] { #expect(summary.activePours.map(\.id) == value.map(uuid), where_) }
                if let value = step["intervalDuration"] as? Double { #expect(summary.interval.duration == value, where_) }
                if let value = step["intervalStart"] { #expect(summary.interval.start == date(value), where_) }
                if let value = step["completedExtras"] as? [String] { #expect(summary.completedExtras == Set(value.map(uuid)), where_) }
                if let value = step["extrasDone"] as? Int { #expect(summary.extrasDone == value, where_) }
                if let value = step["extrasTotal"] as? Int { #expect(summary.extrasTotal == value, where_) }
                if let value = step["allExtrasDone"] as? Bool { #expect(summary.allExtrasDone == value, where_) }
                if let value = step["targets"] as? [String: Any] {
                    expectTargets(summary.targets, value, where_)
                    #expect(summary.targets == challenge.targets(on: date(step["on"])), where_)
                }
                if let value = step["extras"] as? [String] {
                    let shown = summary.extras.map { extra in
                        extra.title + (summary.completedExtras.contains(extra.id) ? " ✓" : "") + (summary.isLate(extra) ? " late" : "")
                    }
                    #expect(shown == value, where_)
                }
            case "streaks":
                let streaks = challenge.streaks(asOf: date(step["asOf"]))
                #expect(streaks.current == step["current"] as! Int, where_)
                if let best = step["best"] as? Int { #expect(streaks.best == best, where_) }
                if let milestones = step["milestones"] as? [Any] { #expect(streaks.milestones == milestones.map(date), where_) }
            case "history":
                let history = challenge.history(on: date(step["on"]))
                #expect(history.map(\.id) == (step["ids"] as! [String]).map(uuid), where_)
                for (undo, pour) in step["undone"] as? [String: String] ?? [:] {
                    #expect(history.first { $0.id == uuid(undo) }?.undonePourID == uuid(pour), where_)
                }
            case "activities":
                #expect(challenge.allActivities.map(\.id) == (step["ids"] as! [String]).map(uuid), where_)
            case "activityDays":
                #expect(challenge.allActivities.map(\.day) == (step["days"] as! [Any]).map(date), where_)
            case "startDate":
                #expect(challenge.startDate == date(step["equals"]), where_)
            case "allExtras":
                let expected = step["extras"] as! [[String: Any]]
                #expect(challenge.allExtras.count == expected.count, where_)
                for (extra, want) in zip(challenge.allExtras, expected) {
                    #expect(extra.id == uuid(want["id"]) && extra.title == want["title"] as? String, where_)
                    #expect(extra.firstDay == date(want["firstDay"]), where_)
                    #expect(extra.completedOn == (want["completedOn"] is NSNull ? nil : date(want["completedOn"])), where_)
                    #expect(extra.archivedFrom == (want["archivedFrom"] is NSNull ? nil : date(want["archivedFrom"])), where_)
                    #expect(scheduleName(extra.schedule) == want["schedule"] as? String ?? "once", where_)
                }
            case "shownExtras":
                #expect(challenge.extras(asOf: date(step["asOf"])).map(\.id) == (step["ids"] as! [String]).map(uuid), where_)
            case "openExtras":
                #expect(challenge.openExtras(asOf: date(step["asOf"])).map(\.id) == (step["ids"] as! [String]).map(uuid), where_)
            case "shownExtrasCount":
                #expect(challenge.extras(asOf: date(step["asOf"])).count == step["count"] as! Int, where_)
            case "openExtrasCount":
                #expect(challenge.openExtras(asOf: date(step["asOf"])).count == step["count"] as! Int, where_)
            default:
                Issue.record("Unknown op \(step["op"]!) in \(name)")
            }
        }
    }
}

private func sortedJSON(kind: String, value: Any) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data: Data = switch kind {
    case "action": try encoder.encode(decode(Challenge.Action.self, value))
    case "activity": try encoder.encode(decode(Challenge.Activity.self, value))
    case "record": try encoder.encode(decode(ChallengeRecord.self, value))
    case "event": try encoder.encode(decode(ChallengeEvent.self, value))
    default: throw CocoaError(.coderInvalidValue)
    }
    return String(decoding: data, as: UTF8.self)
}

@Test func parityWireFormatMatchesChallengeCore() throws {
    for entry in list("encoding") + list("spellings") {
        #expect(try sortedJSON(kind: entry["kind"] as! String, value: entry["value"]!) == entry["sorted"] as! String,
                "\(entry["value"]!)")
    }
    for entry in list("rejected") {
        #expect(throws: (any Error).self, "\(entry["value"]!)") {
            try sortedJSON(kind: entry["kind"] as! String, value: entry["value"]!)
        }
    }
    for entry in list("records") {
        let record = try decode(ChallengeRecord.self, entry["value"]!)
        #expect(record.timeZone == entry["timeZone"] as! String)
        #expect((record.emptyChallenge != nil) == entry["valid"] as! Bool, "\(entry["value"]!)")
    }
}

@Test func paritySmallRulesMatchChallengeCore() {
    for entry in list("zones") {
        let identifier = entry["identifier"] as! String
        #expect((Challenge.canonicalTimeZone(identifier) != nil) == entry["canonical"] as! Bool, "\(identifier)")
    }
    for entry in list("titles") {
        #expect(Challenge.extraTitle(entry["raw"] as! String) == entry["title"] as? String, "\(entry["raw"]!)")
    }
    for entry in list("targetNames") {
        #expect(Challenge.targetName(entry["raw"] as! String) == entry["name"] as? String, "\(entry["raw"]!)")
    }
    for entry in list("icons") {
        #expect(Challenge.isIconID(entry["id"] as! String) == entry["valid"] as! Bool, "\(entry["id"]!)")
    }
    for entry in list("clockWarnings") {
        let activity = Challenge.Activity(id: UUID(), day: date(entry["recordedAt"]), recordedAt: date(entry["recordedAt"]),
                                          action: .pour(450), undonePourID: nil, deviceID: "fixture")
        let event = ChallengeEvent(ownerID: UUID(), challengeID: UUID(), activity: activity, receivedAt: entry["receivedAt"] as? String)
        #expect(event.hasClockWarning == entry["warning"] as! Bool, "\(entry["receivedAt"]!)")
    }
}
