import Foundation

// Real immutable histories, production catalog/reducer, and transport; no alternate merger.
@main struct PersonalSyncTests {
    static let t = 1_700_000_000_000.0
    static func rejects(_ title: String, _ action: () throws -> Void) {
        do { try action(); fatalError(title) } catch { }
    }
    static func main() throws {
        let library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let builtIn = library.words[0]
        let wordID = UUID(), otherID = UUID(), questionID = UUID()
        let root = PersonalRevision(entryID: wordID, timestamp: t, word: PersonalWordContent(word: "自建甲", meaning: "初义"))
        let other = PersonalRevision(entryID: otherID, timestamp: t, word: PersonalWordContent(word: "自建乙", meaning: "乙义"))
        let q = PersonalQuestionContent(content: "选择甲", options: ["甲", "乙", "丙", "丁"], correctAnswer: 0, explanation: "原解析", relatedWordIDs: [wordID])
        let question = PersonalRevision(entryID: questionID, timestamp: t, question: q)
        func preview(_ local: StudySnapshot, _ remote: StudySnapshot) throws -> SyncMergePreview {
            try SyncMergeEngine.preview(local: local, incoming: remote, words: library.words, questions: library.questions)
        }
        func catalog(_ snapshot: StudySnapshot) throws -> PersonalCatalog {
            try SnapshotCodec.validate(snapshot: snapshot, builtInWords: library.words, builtInQuestions: library.questions)
        }
        func resolveContent(_ p: SyncMergePreview, _ choices: [String: UUID]) throws -> SyncMergePreview {
            try SyncMergeEngine.resolveContent(preview: p, choices: choices, words: library.words, questions: library.questions, now: t + 100)
        }
        let a = StudySnapshot(revisions: [root, question]), b = StudySnapshot(revisions: [other])
        let independent = try preview(a, b)
        assert(independent.contentConflicts.isEmpty && independent.merged.revisions.count == 3)
        assert(independent.contentChanges.incoming.addedWords == 1 && independent.contentChanges.incoming.addedQuestions == 0)
        assert(independent.contentChanges.outgoing.addedWords == 1 && independent.contentChanges.outgoing.addedQuestions == 1)
        assert(independent.incomingCount == 0 && independent.outgoingCount == 0, "Existing count labels remain learning-event counts")
        let oldClockEdit = PersonalRevision(entryID: wordID, parents: [root.id], timestamp: t - 1, word: PersonalWordContent(word: "自建甲", meaning: "改义"))
        let descendant = try preview(a, StudySnapshot(revisions: [root, question, oldClockEdit]))
        let descendantCatalog = try catalog(descendant.merged)
        assert(descendant.contentConflicts.isEmpty && descendantCatalog.headsByEntryID[wordID]?.first?.id == oldClockEdit.id, "DAG descendants win even with an older clock")
        assert(descendant.contentChanges.incoming.editedWords == 1 && descendant.contentChanges.outgoing.editedWords == 0)

        let archived = PersonalRevision(entryID: wordID, parents: [root.id], timestamp: t + 5, word: root.word, archived: true)
        let third = PersonalRevision(entryID: wordID, parents: [root.id], timestamp: t + 6, word: PersonalWordContent(word: "自建甲", meaning: "第三义"))
        let sibling = try preview(StudySnapshot(revisions: [root, oldClockEdit, question]), StudySnapshot(revisions: [root, archived, third, question]))
        assert(sibling.contentConflicts.count == 1 && sibling.contentConflicts[0].options.count == 3, "All concurrent heads need an explicit choice")
        let conflict = sibling.contentConflicts[0]
        assert(conflict.options.contains { $0.revision?.id == archived.id && $0.revision?.archived == true })
        rejects("Learning resolution cannot bypass content decisions") { _ = try SyncMergeEngine.resolve(sibling, choices: [:]) }
        rejects("A received final proposal cannot carry unresolved branches") {
            _ = try SyncMergeEngine.validateProposal(sibling.merged, words: library.words, questions: library.questions)
        }
        rejects("Missing branch choices cannot resolve") { _ = try resolveContent(sibling, [:]) }
        rejects("Unrelated option UUID cannot resolve") { _ = try resolveContent(sibling, [conflict.id: UUID()]) }
        let resolved = try resolveContent(sibling, [conflict.id: oldClockEdit.id])
        let resolution = resolved.merged.revisions.first { !sibling.merged.revisions.contains($0) }!
        assert(Set(resolution.parents) == Set([oldClockEdit.id, archived.id, third.id]) && resolution.word == oldClockEdit.word)
        assert(resolved.contentConflicts.isEmpty && resolved.merged.revisions.count == 6)
        let repeatSync = try preview(resolved.merged, sibling.incoming)
        assert(repeatSync.contentConflicts.isEmpty && repeatSync.merged.revisions == resolved.merged.revisions, "Re-sync does not resurrect handled branches")
        let archiveChoice = try resolveContent(sibling, [conflict.id: archived.id])
        assert(archiveChoice.contentChanges.incoming.archivedWords == 1)

        let duplicate = PersonalRevision(entryID: UUID(), timestamp: t, word: PersonalWordContent(word: " 自建甲 ", meaning: "独立词条"))
        let note = StudyEvent(wordID: duplicate.entryID, kind: "note", value: "不丢笔记", timestamp: t)
        let duplicatePlan = try preview(a, StudySnapshot(events: [note], revisions: [duplicate]))
        let names = duplicatePlan.contentConflicts[0]
        rejects("A received final proposal cannot carry unresolved names") {
            _ = try SyncMergeEngine.validateProposal(duplicatePlan.merged, words: library.words, questions: library.questions)
        }
        assert(names.kind == .nameCollision && Set(names.options.map { $0.id }) == Set([wordID, duplicate.entryID]))
        let unique = try resolveContent(duplicatePlan, [names.id: wordID])
        let uniqueCatalog = try catalog(unique.merged)
        assert(uniqueCatalog.archivedWordIDs.contains(duplicate.entryID) && unique.merged.events == [note])
        assert(unique.merged.revisions.contains(duplicate) && unique.merged.revisions.contains(root), "Name resolution appends archives and preserves both identities")
        let loserHead = uniqueCatalog.headsByEntryID[duplicate.entryID]!.first!
        assert(loserHead.parents == [duplicate.id] && loserHead.archived)
        let winnerHead = uniqueCatalog.headsByEntryID[wordID]!.first!
        assert(winnerHead.parents == [root.id] && !winnerHead.archived && winnerHead.id != root.id, "Keeping a personal winner is also an immutable user decision")
        assert(unique.contentChanges.incoming.editedWords == 1 && unique.contentChanges.incoming.addedWords == 1)
        assert(unique.contentChanges.outgoing.addedWords == 1 && unique.contentChanges.outgoing.archivedWords == 1)
        let oppositeChoice = try resolveContent(duplicatePlan, [names.id: duplicate.entryID])
        let oppositeSync = try preview(unique.merged, oppositeChoice.merged)
        assert(oppositeSync.contentConflicts.count == 2 && oppositeSync.contentConflicts.allSatisfy { $0.kind == .revision }, "Opposite offline name choices must not silently archive both entries")
        for branch in oppositeSync.contentConflicts {
            assert(branch.options.count == 2 && branch.options.contains { $0.revision?.archived == true } && branch.options.contains { $0.revision?.archived == false })
        }
        rejects("Opposite name choices require reconciliation before a final proposal") {
            _ = try SyncMergeEngine.validateProposal(oppositeSync.merged, words: library.words, questions: library.questions)
        }
        let builtinDuplicate = PersonalRevision(entryID: UUID(), timestamp: t, word: PersonalWordContent(word: builtIn.word, meaning: "个人释义"))
        let builtinPlan = try preview(StudySnapshot(), StudySnapshot(revisions: [builtinDuplicate]))
        let builtinConflict = builtinPlan.contentConflicts[0]
        assert(builtinConflict.options.first { $0.id == builtIn.id }?.isSelectable == true)
        assert(builtinConflict.options.first { $0.id == builtinDuplicate.entryID }?.isSelectable == false)
        rejects("A personal duplicate cannot replace a bundled word") { _ = try resolveContent(builtinPlan, [builtinConflict.id: builtinDuplicate.entryID]) }
        let builtinResolved = try resolveContent(builtinPlan, [builtinConflict.id: builtIn.id])
        let builtinCatalog = try catalog(builtinResolved.merged)
        assert(builtinCatalog.archivedWordIDs.contains(builtinDuplicate.entryID))

        let rename = PersonalRevision(entryID: wordID, parents: [root.id], timestamp: t + 20, word: PersonalWordContent(word: "自建乙", meaning: "改名"))
        let renamePlan = try preview(StudySnapshot(revisions: [root, oldClockEdit, other]), StudySnapshot(revisions: [root, rename, other]))
        assert(renamePlan.contentConflicts.count == 1 && renamePlan.contentConflicts[0].kind == .revision)
        let newCollision = try resolveContent(renamePlan, [renamePlan.contentConflicts[0].id: rename.id])
        assert(newCollision.contentConflicts.count == 1 && newCollision.contentConflicts[0].kind == .nameCollision, "A branch choice can require a second name decision")
        rejects("A newly revealed name collision still blocks final resolution") { _ = try SyncMergeEngine.resolve(newCollision, choices: [:]) }

        var changedQ = q; changedQ.correctAnswer = 1; changedQ.relatedWordIDs = [otherID]
        let qEdit = PersonalRevision(entryID: questionID, parents: [question.id], timestamp: t + 10, question: changedQ)
        let qArchive = PersonalRevision(entryID: questionID, parents: [question.id], timestamp: t + 11, question: q, archived: true)
        let answer = StudyEvent(kind: "answer", value: "1", timestamp: t + 2, questionID: question.id)
        let adjustment = StudyEvent(wordID: wordID, kind: "errorAdjustment", value: "2", timestamp: t + 3)
        let qBranches = try preview(StudySnapshot(events: [adjustment], revisions: [root, other, question, qEdit]), StudySnapshot(events: [answer], revisions: [root, other, question, qArchive]))
        assert(qBranches.contentConflicts.count == 1 && qBranches.conflicts.isEmpty, "Learning choices are deferred while content needs decisions")
        let qResolved = try resolveContent(qBranches, [qBranches.contentConflicts[0].id: qEdit.id])
        let qCatalog = try catalog(qResolved.merged)
        assert(qResolved.conflicts.count == 1 && qResolved.conflicts[0].wordID == wordID)
        assert(qCatalog.headsByEntryID[questionID]?.first?.question == changedQ && qCatalog.questions.contains { $0.id == question.id })
        assert(qResolved.contentChanges.incoming.editedQuestions == 1 && qResolved.contentChanges.outgoing.editedQuestions == 1)
        let qArchived = try resolveContent(qBranches, [qBranches.contentConflicts[0].id: qArchive.id])
        assert(qArchived.contentChanges.incoming.archivedQuestions == 1)
        let historical = try preview(StudySnapshot(events: [adjustment], revisions: [root, question, other, qEdit]), StudySnapshot(events: [answer], revisions: [root, question]))
        assert(historical.conflicts.count == 1 && historical.conflicts[0].wordID == wordID, "Unseen old wrong answers retain original answer/link semantics")
        let foreign = try preview(StudySnapshot(), StudySnapshot(events: [answer], revisions: [root, question]))
        let foreignCatalog = try catalog(foreign.merged)
        let state = LearningEngine.reduce(words: foreignCatalog.words, questions: foreignCatalog.questions, events: foreign.merged.events)
        assert(state.records[wordID]?.errorCount == 1, "Foreign personal answers validate against the complete merged directory")
        let repeatedAnswers = (0..<1_200).map { offset in
            StudyEvent(kind: "answer", value: "1", timestamp: t + Double(offset), questionID: question.id)
        }
        let manyHistorical = try preview(StudySnapshot(events: [adjustment], revisions: [root, other, question, qEdit]),
            StudySnapshot(events: repeatedAnswers, revisions: [root, question]))
        assert(manyHistorical.conflicts.count == 1 && manyHistorical.conflicts[0].mergedValue == "1202", "Many old answers retain exact old links with no per-question total deduplication")
        let legacy = try preview(a, StudySnapshot(schemaVersion: 2))
        assert(legacy.merged.schemaVersion == 3 && Set(legacy.merged.revisions.map { $0.id }) == Set([root.id, question.id]))
        let spoof = PersonalRevision(id: root.id, entryID: wordID, timestamp: t, word: PersonalWordContent(word: "自建甲", meaning: "篡改"))
        rejects("A revision ID cannot carry changed payload") { _ = try preview(a, StudySnapshot(revisions: [spoof])) }
        rejects("A content-only local change invalidates an earlier preview") {
            try SyncMergeEngine.validateCommit(current: descendant.merged, expected: a, proposed: independent.merged)
        }
        rejects("Current immutable revisions cannot disappear") {
            try SyncMergeEngine.validateCommit(current: a, expected: a, proposed: StudySnapshot(revisions: [root]))
        }
        rejects("Current immutable revisions cannot change") {
            try SyncMergeEngine.validateCommit(current: StudySnapshot(revisions: [root]), expected: StudySnapshot(revisions: [root]), proposed: StudySnapshot(revisions: [spoof]))
        }
        let final = try SyncMergeEngine.resolve(resolved, choices: [:], now: t + 200)
        _ = try SyncMergeEngine.validateProposal(final, words: library.words, questions: library.questions)
        rejects("A final nearby proposal must use schema 3") {
            _ = try SyncMergeEngine.validateProposal(StudySnapshot(schemaVersion: 2), words: library.words, questions: library.questions)
        }
        try SyncMergeEngine.validateCommit(current: sibling.local, expected: sibling.local, proposed: final)
        for revision in sibling.local.revisions { assert(final.revisions.contains(revision)) }
        for event in sibling.local.events { assert(final.events.contains(event)) }
        let answeredFinal = try SyncMergeEngine.resolve(qResolved, choices: [qResolved.conflicts[0].id: .incoming], now: t + 200)
        try SyncMergeEngine.validateCommit(current: qBranches.local, expected: qBranches.local, proposed: answeredFinal)
        for event in qBranches.local.events + qBranches.incoming.events { assert(answeredFinal.events.contains(event)) }
        for revision in qBranches.local.revisions + qBranches.incoming.revisions { assert(answeredFinal.revisions.contains(revision)) }
        _ = try catalog(answeredFinal)
        rejects("Unknown snapshot versions cannot enter commit") {
            try SyncMergeEngine.validateCommit(current: a, expected: a, proposed: StudySnapshot(schemaVersion: 4, revisions: a.revisions))
        }
        try unicodeIdentity(builtIn: builtIn)
        try limits(builtIn: builtIn, root: root, edit: oldClockEdit, archived: archived)
        print("PASS: personal sync DAG choices, names, historical answers, immutable/stale commits and combined ceilings")
    }

    static func unicodeIdentity(builtIn: Word) throws {
        let composed = "caf\u{00E9}", decomposed = "cafe\u{0301}"
        // These compare equal as Swift Strings but must remain distinct immutable payloads.
        assert(composed == decomposed)
        assert(Array(composed.utf8) == [0x63, 0x61, 0x66, 0xC3, 0xA9])
        assert(Array(decomposed.utf8) == [0x63, 0x61, 0x66, 0x65, 0xCC, 0x81])
        let word = PersonalRevision(entryID: UUID(), timestamp: t,
            word: PersonalWordContent(word: "Unicode fixture", meaning: composed))
        let content = PersonalQuestionContent(content: "Unicode options", options: [composed, "B", "C", "D"],
            correctAnswer: 0, explanation: "Explanation", relatedWordIDs: [word.entryID])
        let question = PersonalRevision(entryID: UUID(), timestamp: t, question: content)
        let note = StudyEvent(wordID: builtIn.id, kind: "note", value: composed, timestamp: t)
        let favorite = StudyEvent(wordID: builtIn.id, kind: "favorite", value: "true", timestamp: t + 1)
        let baseline = StudySnapshot(events: [note, favorite], revisions: [word, question])
        let noteChange = StudyEvent(id: note.id, wordID: note.wordID, kind: note.kind, value: decomposed, timestamp: note.timestamp)
        let wordChange = PersonalRevision(id: word.id, entryID: word.entryID, timestamp: word.timestamp,
            word: PersonalWordContent(word: "Unicode fixture", meaning: decomposed))
        var changedOptions = content; changedOptions.options[0] = decomposed
        let questionChange = PersonalRevision(id: question.id, entryID: question.entryID, timestamp: question.timestamp, question: changedOptions)
        let changed: [(String, StudySnapshot)] = [
            ("event value", StudySnapshot(events: [noteChange, favorite], revisions: [word, question])),
            ("word meaning", StudySnapshot(events: baseline.events, revisions: [wordChange, question])),
            ("question option", StudySnapshot(events: baseline.events, revisions: [word, questionChange]))
        ]
        for (field, replacement) in changed {
            rejects("Union must reject same-ID Unicode replacement in " + field) {
                _ = try SyncMergeEngine.preview(local: baseline, incoming: replacement, words: [builtIn], questions: [])
            }
            rejects("Unicode-only local mutation must invalidate the baseline: " + field) {
                try SyncMergeEngine.validateCommit(current: replacement, expected: baseline, proposed: replacement)
            }
            rejects("Proposal cannot normalize an existing immutable " + field) {
                try SyncMergeEngine.validateCommit(current: baseline, expected: baseline, proposed: replacement)
            }
        }
        let reordered = StudySnapshot(events: [favorite, note], revisions: [question, word])
        let unchanged = try SyncMergeEngine.preview(local: baseline, incoming: reordered, words: [builtIn], questions: [])
        assert(unchanged.merged.events.count == 2 && unchanged.merged.revisions.count == 2)
        try SyncMergeEngine.validateCommit(current: reordered, expected: baseline, proposed: unchanged.merged)
        assert(Array(unchanged.merged.events.first { $0.id == note.id }!.value.utf8) == [0x63, 0x61, 0x66, 0xC3, 0xA9])
        assert(Array(unchanged.merged.revisions.first { $0.id == word.id }!.word!.meaning.utf8) == [0x63, 0x61, 0x66, 0xC3, 0xA9])
        assert(Array(unchanged.merged.revisions.first { $0.id == question.id }!.question!.options[0].utf8) == [0x63, 0x61, 0x66, 0xC3, 0xA9])
    }

    static func limits(builtIn: Word, root: PersonalRevision, edit: PersonalRevision, archived: PersonalRevision) throws {
        func events(_ count: Int, value: String = "true") -> [StudyEvent] {
            (0..<count).map { _ in StudyEvent(wordID: builtIn.id, kind: value == "true" ? "favorite" : "note", value: value, timestamp: t) }
        }
        let many = events(99_998)
        rejects("Union must check combined events plus revisions") {
            _ = try SyncMergeEngine.preview(local: StudySnapshot(events: Array(many.prefix(50_000)), revisions: [root, edit]),
                incoming: StudySnapshot(events: Array(many.suffix(49_998)), revisions: [root, archived]), words: [builtIn], questions: [])
        }
        let atLimit = try SyncMergeEngine.preview(local: StudySnapshot(events: Array(many.prefix(99_997)), revisions: [root, edit]),
            incoming: StudySnapshot(revisions: [root, archived]), words: [builtIn], questions: [])
        rejects("Appending a branch resolution must respect the combined record ceiling") {
            _ = try SyncMergeEngine.resolveContent(preview: atLimit, choices: [atLimit.contentConflicts[0].id: edit.id], words: [builtIn], questions: [], now: t + 100)
        }
        let large = String(repeating: "x", count: 100_000)
        rejects("Union must enforce encoded size after merging individually valid inputs") {
            _ = try SyncMergeEngine.preview(local: StudySnapshot(events: events(101, value: large)), incoming: StudySnapshot(events: events(101, value: large)), words: [builtIn], questions: [])
        }
        let leftNote = StudyEvent(wordID: builtIn.id, kind: "note", value: "左", timestamp: t + 1)
        let rightNote = StudyEvent(wordID: builtIn.id, kind: "note", value: "右", timestamp: t + 2)
        let eventLimit = try SyncMergeEngine.preview(local: StudySnapshot(events: many + [leftNote]),
            incoming: StudySnapshot(events: [rightNote]), words: [builtIn], questions: [])
        rejects("Learning conflict resolution cannot append beyond the record ceiling") {
            _ = try SyncMergeEngine.resolve(eventLimit, choices: [eventLimit.conflicts[0].id: .local], now: t + 100)
        }
        // Make a valid union exactly 100 bytes below 20 MB; a new revision necessarily exceeds it.
        let fillerID = UUID()
        var nearBytes = StudySnapshot(events: events(199, value: large) + [StudyEvent(id: fillerID, wordID: builtIn.id, kind: "note", value: "", timestamp: t)],
            revisions: [root, edit, archived])
        let padding = 19_999_900 - (try JSONEncoder().encode(nearBytes).count)
        assert((1...100_000).contains(padding), "Fixture's final event remains within its independent byte limit")
        nearBytes.events[nearBytes.events.count - 1] = StudyEvent(id: fillerID, wordID: builtIn.id, kind: "note", value: String(repeating: "p", count: padding), timestamp: t)
        let bytePlan = try SyncMergeEngine.preview(local: nearBytes, incoming: StudySnapshot(), words: [builtIn], questions: [])
        rejects("Appending a branch resolution must respect encoded bytes, not just record count") {
            _ = try SyncMergeEngine.resolveContent(preview: bytePlan, choices: [bytePlan.contentConflicts[0].id: edit.id], words: [builtIn], questions: [], now: t + 100)
        }
        var oversizedProposal = nearBytes
        oversizedProposal.events.append(StudyEvent(wordID: builtIn.id, kind: "note", value: large, timestamp: t))
        rejects("Commit also enforces encoded proposal size") {
            try SyncMergeEngine.validateCommit(current: nearBytes, expected: nearBytes, proposed: oversizedProposal)
        }
        var nearNotes = nearBytes
        nearNotes.revisions = []
        nearNotes.events.append(StudyEvent(wordID: builtIn.id, kind: "note", value: String(repeating: "l", count: 5_000), timestamp: t + 10))
        let remoteNote = StudyEvent(wordID: builtIn.id, kind: "note", value: String(repeating: "r", count: 5_000), timestamp: t + 11)
        nearNotes.events.append(remoteNote)
        let notePadding = padding + 19_999_900 - (try JSONEncoder().encode(nearNotes).count)
        assert((1...100_000).contains(notePadding))
        nearNotes.events[199] = StudyEvent(id: fillerID, wordID: builtIn.id, kind: "note", value: String(repeating: "p", count: notePadding), timestamp: t)
        let noteBytePlan = try SyncMergeEngine.preview(local: StudySnapshot(events: Array(nearNotes.events.dropLast())),
            incoming: StudySnapshot(events: [remoteNote]), words: [builtIn], questions: [])
        rejects("Appending a learning resolution must enforce the encoded-size ceiling") {
            _ = try SyncMergeEngine.resolve(noteBytePlan, choices: [noteBytePlan.conflicts[0].id: .local], now: t + 100)
        }
    }
}
