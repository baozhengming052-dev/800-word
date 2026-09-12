import Foundation

// Run against the production reducer/merger; no parallel implementation in the tests.
@main struct SyncMergeEngineTests {
    static func main() throws {
        let library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let word = library.words.first { $0.word == "源远流长" }!
        let question = library.questions.first { $0.relatedWords == [word.word] }!
        let t = 1_700_000_000_000.0
        func event(_ kind: String, _ value: String, _ offset: Double) -> StudyEvent {
            StudyEvent(wordID: word.id, kind: kind, value: value, timestamp: t + offset)
        }
        func wrong(_ offset: Double) -> StudyEvent {
            StudyEvent(kind: "answer", value: String((question.correctAnswer + 1) % 4), timestamp: t + offset, questionID: question.id)
        }
        func plan(_ local: [StudyEvent], _ remote: [StudyEvent]) throws -> SyncMergePreview {
            try SyncMergeEngine.preview(local: StudySnapshot(events: local), incoming: StudySnapshot(events: remote), words: library.words, questions: library.questions)
        }
        func state(_ value: StudySnapshot) -> StudyRecord {
            LearningEngine.reduce(words: library.words, questions: library.questions, events: value.events).records[word.id] ?? StudyRecord()
        }
        func rejects(_ title: String, _ action: () throws -> Void) {
            do { try action(); fatalError(title) } catch { /* expected */ }
        }
        let shared = wrong(1), a = wrong(2), b = wrong(3)
        let independent = try plan([shared, a], [shared, b])
        assert(independent.conflicts.isEmpty && independent.merged.events.count == 3, "Common attempts deduplicate; distinct attempts remain")
        assert(state(independent.merged).errorCount == 3, "Do not sum both device totals")
        let repeatPlan = try plan(independent.merged.events, [shared, b])
        assert(repeatPlan.merged.events.count == 3 && repeatPlan.conflicts.isEmpty, "Repeat/older snapshots are idempotent")
        let reverse = try plan([shared, b], [shared, a])
        assert(reverse.merged.events == independent.merged.events, "Event union is commutative and ordered")

        let baseNote = event("note", "原笔记", 10)
        let localNote = event("note", "手机笔记", 12), remoteNote = event("note", "平板笔记", 11)
        let notes = try plan([baseNote, localNote], [baseNote, remoteNote])
        assert(notes.conflicts.count == 1 && notes.conflicts[0].kind == .note, "Concurrent notes require explicit choice, not clock overwrite")
        rejects("Missing choices must not save") { _ = try SyncMergeEngine.resolve(notes, choices: [:], now: t + 30) }
        let joined = try SyncMergeEngine.resolve(notes, choices: [notes.conflicts[0].id: .combined], now: t + 30)
        assert(state(joined).personalNotes == "手机笔记\n\n平板笔记", "Combined notes retain both texts")
        assert(state(joined).noteHistory.count == 4, "Resolution preserves all note revisions")
        let keepEmpty = try plan([baseNote, event("note", "", 13)], [baseNote, remoteNote])
        let empty = try SyncMergeEngine.resolve(keepEmpty, choices: [keepEmpty.conflicts[0].id: .local], now: t + 30)
        assert(state(empty).personalNotes.isEmpty, "Explicitly clearing a note remains a valid choice")
        let oneSided = try plan([baseNote, localNote], [baseNote, a])
        assert(oneSided.conflicts.isEmpty && state(oneSided.merged).personalNotes == "手机笔记", "Unrelated remote answers do not cause note conflicts")

        let baseCount = event("errorAdjustment", "5", 20)
        let leftReset = event("errorAdjustment", "-5", 22)
        let rightIncrease = event("errorAdjustment", "2", 23)
        let counts = try plan([baseCount, leftReset], [baseCount, rightIncrease])
        assert(counts.conflicts.count == 1 && counts.conflicts[0].localValue == "0" && counts.conflicts[0].incomingValue == "7", "Manual totals must be presented as totals")
        let zero = try SyncMergeEngine.resolve(counts, choices: [counts.conflicts[0].id: .local], now: t + 30)
        assert(state(zero).errorCount == 0 && zero.events.count == 4, "Choosing zero retains history and does not add totals")
        let retry = try plan(zero.events, counts.incoming.events)
        assert(retry.conflicts.isEmpty && state(retry.merged).errorCount == 0, "Resolved old conflict does not reappear")
        let newAttempt = wrong(40)
        let afterRetry = try plan(zero.events, zero.events + [newAttempt])
        assert(state(afterRetry.merged).errorCount == 1, "An answer after reset is counted")
        let manualVsAnswer = try plan([baseCount, leftReset], [baseCount, a])
        assert(manualVsAnswer.conflicts.count == 1, "A manual reset and unseen wrong attempt need a decision")
        let equalEdits = try plan([baseCount, event("errorAdjustment", "2", 22)], [baseCount, rightIncrease])
        assert(equalEdits.conflicts.count == 1, "Equal device totals cannot accidentally become nine")
        let equalResolved = try SyncMergeEngine.resolve(equalEdits, choices: [equalEdits.conflicts[0].id: .incoming], now: t + 30)
        assert(state(equalResolved).errorCount == 7, "Identical parallel manual edits count only chosen total")

        let spoof = StudyEvent(id: shared.id, kind: "answer", value: "999", timestamp: shared.timestamp, questionID: shared.questionID)
        rejects("A reused event ID cannot rewrite history") { _ = try plan([shared], [spoof]) }
        rejects("Duplicate input IDs must be rejected") { _ = try plan([shared, shared], []) }
        rejects("A stale confirmation cannot overwrite new local work") {
            try SyncMergeEngine.validateCommit(current: StudySnapshot(events: [shared, a]), expected: StudySnapshot(events: [shared]), proposed: StudySnapshot(events: [shared, b]))
        }
        rejects("A proposal cannot remove local history") {
            try SyncMergeEngine.validateCommit(current: StudySnapshot(events: [shared]), expected: StudySnapshot(events: [shared]), proposed: StudySnapshot(events: [b]))
        }
        try SyncMergeEngine.validateCommit(current: StudySnapshot(events: [a, shared]), expected: StudySnapshot(events: [shared, a]), proposed: independent.merged)
        let restored = try JSONDecoder().decode(StudySnapshot.self, from: JSONEncoder().encode(zero))
        assert(restored.schemaVersion == 2 && restored.events == zero.events, "Existing backups stay compatible")
        print("PASS: sync union, conflict resolution, idempotency, stale and destructive proposal checks")
    }
}
