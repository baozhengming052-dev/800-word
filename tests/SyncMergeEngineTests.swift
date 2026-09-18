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

        let baseSynonym = event("synonym", try PersonalSynonyms.encode([ConfusableWord(word: "源远", difference: "只强调时间长")]), 60)
        let localSynonym = event("synonym", try PersonalSynonyms.encode([ConfusableWord(word: "源远", difference: "只强调时间长"),
                                                                         ConfusableWord(word: "源源不断", difference: "强调连续")]), 62)
        let remoteSynonym = event("synonym", try PersonalSynonyms.encode([ConfusableWord(word: "源远", difference: "只强调时间长"),
                                                                          ConfusableWord(word: "绵延", difference: "强调延续")]), 61)
        let synonyms = try plan([baseSynonym, localSynonym], [baseSynonym, remoteSynonym])
        assert(synonyms.conflicts.count == 1 && synonyms.conflicts[0].kind == .synonym, "Concurrent synonyms require explicit choice, not clock overwrite")
        assert(synonyms.conflicts[0].localDisplay.contains("源源不断") && !synonyms.conflicts[0].localDisplay.contains("{"), "Synonym conflicts are shown as readable text")
        let keptLocal = try SyncMergeEngine.resolve(synonyms, choices: [synonyms.conflicts[0].id: .local], now: t + 30)
        assert(state(keptLocal).personalSynonyms.map(\.word) == ["源远", "源源不断"], "Keeping the local list drops nothing of its own")
        let synonymJoined = try SyncMergeEngine.resolve(synonyms, choices: [synonyms.conflicts[0].id: .combined], now: t + 30)
        assert(state(synonymJoined).personalSynonyms.map(\.word) == ["源远", "源源不断", "绵延"], "Combined synonyms keep both sides without duplicates")
        assert(state(synonymJoined).synonymHistory.count == 4, "Resolution preserves every synonym revision")
        let cleared = try plan([baseSynonym, localSynonym], [baseSynonym, remoteSynonym, event("synonym", "[]", 63)])
        assert(cleared.conflicts.count == 1, "Clearing one side is still a decision")
        let clearedResolved = try SyncMergeEngine.resolve(cleared, choices: [cleared.conflicts[0].id: .incoming], now: t + 30)
        assert(state(clearedResolved).personalSynonyms.isEmpty, "An explicit empty list is a valid final state")
        let oneSidedSynonym = try plan([baseSynonym, localSynonym], [baseSynonym, a])
        assert(oneSidedSynonym.conflicts.isEmpty && state(oneSidedSynonym.merged).personalSynonyms.count == 2, "One-sided synonym edits merge without a prompt")
        rejects("A non-canonical synonym payload cannot enter the record") {
            _ = try plan([event("synonym", "[{\"difference\":\"\",\"word\":\" 源远 \"}]", 70)], [])
        }

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
        let unicodeNote = event("note", "caf\u{00E9}", 50)
        let normalizedNote = StudyEvent(id: unicodeNote.id, wordID: word.id, kind: "note", value: "cafe\u{0301}", timestamp: unicodeNote.timestamp)
        assert(Array(unicodeNote.value.utf8) != Array(normalizedNote.value.utf8), "Fixture differs in raw payload bytes")
        rejects("Canonical Unicode equivalence cannot permit event ID reuse") { _ = try plan([unicodeNote], [normalizedNote]) }
        rejects("Canonical Unicode equivalence cannot permit event replacement at commit") {
            try SyncMergeEngine.validateCommit(current: StudySnapshot(events: [unicodeNote]), expected: StudySnapshot(events: [unicodeNote]), proposed: StudySnapshot(events: [normalizedNote]))
        }
        let unicodeUnion = try plan([unicodeNote, shared], [shared, unicodeNote])
        assert(Array(unicodeUnion.merged.events.first { $0.id == unicodeNote.id }!.value.utf8) == [0x63, 0x61, 0x66, 0xC3, 0xA9], "Unchanged event bytes survive differently ordered arrays")
        rejects("A stale confirmation cannot overwrite new local work") {
            try SyncMergeEngine.validateCommit(current: StudySnapshot(events: [shared, a]), expected: StudySnapshot(events: [shared]), proposed: StudySnapshot(events: [shared, b]))
        }
        rejects("A proposal cannot remove local history") {
            try SyncMergeEngine.validateCommit(current: StudySnapshot(events: [shared]), expected: StudySnapshot(events: [shared]), proposed: StudySnapshot(events: [b]))
        }
        try SyncMergeEngine.validateCommit(current: StudySnapshot(events: [a, shared]), expected: StudySnapshot(events: [shared, a]), proposed: independent.merged)
        let restored = try JSONDecoder().decode(StudySnapshot.self, from: JSONEncoder().encode(zero))
        assert(restored.schemaVersion == 3 && restored.events == zero.events, "Merged backups use schema 3 without changing learning history")
        print("PASS: sync union, conflict resolution, idempotency, stale and destructive proposal checks")
    }
}
