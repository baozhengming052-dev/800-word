import Foundation

@main struct PersonalLibraryTests {
    static func main() throws {
        let library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let t = 1_700_000_000_000.0
        func catalog(_ revisions: [PersonalRevision], events: [StudyEvent] = []) throws -> PersonalCatalog {
            try SnapshotCodec.validate(snapshot: StudySnapshot(events: events, revisions: revisions),
                builtInWords: library.words, builtInQuestions: library.questions, now: t + 1000)
        }
        func rejects(_ label: String, _ body: () throws -> Void) {
            do { try body(); fatalError("Expected rejection: \(label)") } catch { }
        }
        let entry = UUID()
        let root = PersonalRevision(entryID: entry, timestamp: t, word: PersonalWordContent(word: "自编词", meaning: "自编释义"))
        let renamed = PersonalRevision(entryID: entry, parents: [root.id], timestamp: t - 1,
            word: PersonalWordContent(word: "改名词", meaning: "新释义"))
        let second = PersonalRevision(entryID: UUID(), timestamp: t, word: PersonalWordContent(word: "另一词", meaning: "另一释义"))
        let questionEntry = UUID()
        let original = PersonalRevision(entryID: questionEntry, timestamp: t,
            question: PersonalQuestionContent(content: "选出答案", options: ["甲", "乙", "丙", "丁"], correctAnswer: 1, explanation: "旧解析", relatedWordIDs: [entry]))
        let edited = PersonalRevision(entryID: questionEntry, parents: [original.id], timestamp: t - 2,
            question: PersonalQuestionContent(content: "修改后", options: ["甲", "乙", "丙", "丁"], correctAnswer: 0, explanation: "新解析", relatedWordIDs: [second.entryID]))
        let chain = [edited, renamed, original, second, root]
        let current = try catalog(chain)
        assert(current.words.first { $0.id == entry }?.word == "改名词", "Parents, not timestamps, define the current word")
        assert(current.words.filter { $0.id == entry }.count == 1, "Editing preserves one stable word identity")
        assert(current.words.first { $0.id == entry }?.category == "自建词", "An omitted category has the personal-library category")
        assert(current.questions.first { $0.id == original.id }?.correctAnswer == 1, "Historical answers are immutable")
        assert(current.questions.first { $0.id == original.id }?.relatedWordIDs == [entry], "Historical links survive edits and rename")
        assert(current.activeQuestions.contains { $0.id == edited.id } && !current.activeQuestions.contains { $0.id == original.id })
        assert(current.questions.first { $0.id == original.id }?.type == .manual)
        let archived = PersonalRevision(entryID: questionEntry, parents: [edited.id], timestamp: t,
            question: edited.question, archived: true)
        let archivedWord = PersonalRevision(entryID: entry, parents: [renamed.id], timestamp: t, word: renamed.word, archived: true)
        let history = try catalog(chain + [archived, archivedWord])
        assert(!history.activeQuestions.contains { $0.personalEntryID == questionEntry })
        assert(history.questions.contains { $0.id == original.id } && history.archivedWordIDs.contains(entry))
        let restored = PersonalRevision(entryID: questionEntry, parents: [archived.id], timestamp: t, question: archived.question)
        let restoredWord = PersonalRevision(entryID: entry, parents: [archivedWord.id], timestamp: t, word: renamed.word)
        let restoredCatalog = try catalog(chain + [archived, archivedWord, restored, restoredWord])
        assert(restoredCatalog.activeQuestions.contains { $0.id == restored.id } && !restoredCatalog.archivedWordIDs.contains(entry))
        let sibling = PersonalRevision(entryID: entry, parents: [root.id], timestamp: t, word: PersonalWordContent(word: "并发词", meaning: "意义"))
        let concurrent = try catalog(chain + [sibling])
        assert(concurrent.headsByEntryID[entry]?.count == 2, "Concurrent edits remain inspectable")
        let reversed = try catalog(Array((chain + [sibling]).reversed()))
        assert(concurrent.words.first { $0.id == entry } == reversed.words.first { $0.id == entry }, "Provisional heads are deterministic")
        let collision = PersonalRevision(entryID: UUID(), timestamp: t, word: PersonalWordContent(word: " 改名词 ", meaning: "另一释义"))
        let collisionCatalog = try catalog(chain + [collision])
        assert(!collisionCatalog.nameCollisions.isEmpty, "Name collisions are semantic conflicts, not corruption")
        assert(PersonalLibrary.normalizedName("  Ａbc  ") == PersonalLibrary.normalizedName("abc"))
        let trimmed = PersonalLibrary.normalize(PersonalWordContent(word: "  词语 \n", meaning: "  释义  "))
        assert(trimmed.word == "词语" && trimmed.meaning == "释义")
        let partialWord = try JSONDecoder().decode(PersonalWordContent.self, from: Data("{\"word\":\"词\",\"meaning\":\"意义\"}".utf8))
        assert(partialWord.pinyin.isEmpty && partialWord.category.isEmpty && partialWord.example.isEmpty && partialWord.keyPoints.isEmpty)
        let questionWithoutSource = Data("{\"content\":\"题\",\"options\":[\"甲\",\"乙\",\"丙\",\"丁\"],\"correctAnswer\":0,\"explanation\":\"解析\",\"relatedWordIDs\":[]}".utf8)
        let partialQuestion = try JSONDecoder().decode(PersonalQuestionContent.self, from: questionWithoutSource)
        assert(partialQuestion.source.isEmpty)
        rejects("empty word") { _ = try catalog([PersonalRevision(entryID: UUID(), timestamp: t, word: PersonalWordContent(word: " ", meaning: "释义"))]) }
        rejects("empty meaning") { _ = try catalog([PersonalRevision(entryID: UUID(), timestamp: t, word: PersonalWordContent(word: "词", meaning: " "))]) }
        rejects("empty explanation") { _ = try catalog([root, PersonalRevision(entryID: UUID(), timestamp: t, question: PersonalQuestionContent(content: "题", options: ["甲", "乙", "丙", "丁"], correctAnswer: 0, relatedWordIDs: [entry]))]) }
        rejects("unselected answer") { _ = try catalog([root, PersonalRevision(entryID: UUID(), timestamp: t, question: PersonalQuestionContent(content: "题", options: ["甲", "乙", "丙", "丁"], explanation: "解析", relatedWordIDs: [entry]))]) }
        rejects("duplicate normalized options") { _ = try catalog([root, PersonalRevision(entryID: UUID(), timestamp: t, question: PersonalQuestionContent(content: "题", options: ["Ａ", " a ", "丙", "丁"], correctAnswer: 0, explanation: "解析", relatedWordIDs: [entry]))]) }
        rejects("missing links") { _ = try catalog([PersonalRevision(entryID: UUID(), timestamp: t, question: PersonalQuestionContent(content: "题", options: ["甲", "乙", "丙", "丁"], correctAnswer: 0, explanation: "解析"))]) }
        rejects("unknown linked word") { _ = try catalog([original]) }
        rejects("duplicate links") { _ = try catalog([root, PersonalRevision(entryID: UUID(), timestamp: t, question: PersonalQuestionContent(content: "题", options: ["甲", "乙", "丙", "丁"], correctAnswer: 0, explanation: "解析", relatedWordIDs: [entry, entry]))]) }
        rejects("duplicate revision") { _ = try catalog([root, root]) }
        rejects("changed immutable revision ID") { _ = try catalog([root, PersonalRevision(id: root.id, entryID: entry, timestamp: t, word: renamed.word)]) }
        rejects("absent parent") { _ = try catalog([renamed]) }
        rejects("duplicate parents") { _ = try catalog([root, PersonalRevision(entryID: entry, parents: [root.id, root.id], timestamp: t, word: root.word)]) }
        rejects("cross-entry parent") { _ = try catalog([root, PersonalRevision(entryID: UUID(), parents: [root.id], timestamp: t, word: root.word)]) }
        rejects("mixed payload") { _ = try catalog([root, PersonalRevision(entryID: UUID(), timestamp: t, word: root.word, question: original.question)]) }
        rejects("missing payload") { _ = try catalog([PersonalRevision(entryID: UUID(), timestamp: t)]) }
        rejects("mixed entry kinds") { _ = try catalog([root, PersonalRevision(entryID: entry, parents: [root.id], timestamp: t, question: original.question)]) }
        let a = UUID(), b = UUID()
        rejects("cycle") { _ = try catalog([PersonalRevision(id: a, entryID: entry, parents: [b], timestamp: t, word: root.word), PersonalRevision(id: b, entryID: entry, parents: [a], timestamp: t, word: root.word)]) }
        rejects("built-in entry identity") { _ = try catalog([PersonalRevision(entryID: library.words[0].id, timestamp: t, word: root.word)]) }
        rejects("built-in revision identity") { _ = try catalog([PersonalRevision(id: library.questions[0].id, entryID: entry, timestamp: t, word: root.word)]) }
        rejects("entry/revision identity overlap") { _ = try catalog([root, PersonalRevision(entryID: root.id, timestamp: t, word: renamed.word)]) }
        rejects("future revision") { _ = try catalog([PersonalRevision(entryID: entry, timestamp: t + 90_000_000, word: root.word)]) }
        rejects("word length") { _ = try catalog([PersonalRevision(entryID: entry, timestamp: t, word: PersonalWordContent(word: String(repeating: "词", count: 81), meaning: "意义"))]) }
        rejects("meaning length") { _ = try catalog([PersonalRevision(entryID: entry, timestamp: t, word: PersonalWordContent(word: "词", meaning: String(repeating: "字", count: 10_001)))]) }
        rejects("revision byte limit") { _ = try catalog([PersonalRevision(entryID: entry, timestamp: t, word: PersonalWordContent(word: "a" + String(repeating: "\u{0301}", count: 140_000), meaning: "意义"))]) }
        var deepChain = [root]
        for _ in 0..<2500 { deepChain.append(PersonalRevision(entryID: entry, parents: [deepChain.last!.id], timestamp: t, word: root.word)) }
        let deep = try catalog(Array(deepChain.reversed()))
        assert(deep.headsByEntryID[entry]?.map { $0.id } == [deepChain.last!.id], "Deep chains use iterative topology")
        let independentRoot = PersonalRevision(entryID: entry, timestamp: t, word: renamed.word)
        let roots = try catalog([root, independentRoot])
        assert(roots.headsByEntryID[entry]?.count == 2, "Independent roots remain explicit heads")
        var invalidOption = original.question!
        invalidOption.options[0] = String(repeating: "a", count: 2001)
        rejects("option length") { _ = try catalog([root, PersonalRevision(entryID: questionEntry, timestamp: t, question: invalidOption)]) }
        invalidOption.options = ["", "乙", "丙", "丁"]
        rejects("empty option") { _ = try catalog([root, PersonalRevision(entryID: questionEntry, timestamp: t, question: invalidOption)]) }
        var invalidStem = original.question!; invalidStem.content = "  "
        rejects("empty stem") { _ = try catalog([root, PersonalRevision(entryID: questionEntry, timestamp: t, question: invalidStem)]) }
        let note = StudyEvent(wordID: entry, kind: "note", value: "历史笔记", timestamp: t)
        let snapshot = StudySnapshot(events: [note], revisions: chain)
        let data = try JSONEncoder().encode(snapshot)
        let roundtrip = try SnapshotCodec.decode(data: data, builtInWords: library.words, builtInQuestions: library.questions, now: t)
        assert(roundtrip.schemaVersion == 3 && roundtrip.events == [note] && roundtrip.revisions == chain)
        let legacyEvent = StudyEvent(wordID: library.words[0].id, kind: "note", value: "旧笔记", timestamp: t)
        let legacy = try JSONEncoder().encode(StudySnapshot(schemaVersion: 2, events: [legacyEvent]))
        let migrated = try SnapshotCodec.decode(data: legacy, builtInWords: library.words, builtInQuestions: library.questions, now: t)
        assert(migrated.schemaVersion == 3 && migrated.events == [legacyEvent] && migrated.revisions.isEmpty)
        rejects("unknown schema") { _ = try SnapshotCodec.decode(data: Data("{\"schemaVersion\":4,\"events\":[],\"revisions\":[]}".utf8), builtInWords: [], builtInQuestions: [], now: t) }
        rejects("v3 missing revisions") { _ = try SnapshotCodec.decode(data: Data("{\"schemaVersion\":3,\"events\":[]}".utf8), builtInWords: [], builtInQuestions: [], now: t) }
        rejects("v2 personal payload") { _ = try SnapshotCodec.validate(snapshot: StudySnapshot(schemaVersion: 2, revisions: [root]), builtInWords: [], builtInQuestions: [], now: t) }
        rejects("unknown event") { _ = try catalog(chain, events: [StudyEvent(wordID: entry, kind: "bogus", value: "", timestamp: t)]) }
        for (kind, value) in [("favorite", "maybe"), ("mastery", "bogus"), ("rating", "3"), ("errorAdjustment", "100000")] {
            rejects("invalid \(kind) value") { _ = try catalog(chain, events: [StudyEvent(wordID: entry, kind: kind, value: value, timestamp: t)]) }
        }
        rejects("future event") { _ = try catalog(chain, events: [StudyEvent(wordID: entry, kind: "note", value: "", timestamp: t + 90_000_000)]) }
        rejects("answer out of range") { _ = try catalog(chain, events: [StudyEvent(kind: "answer", value: "4", timestamp: t, questionID: original.id)]) }
        rejects("duplicate event") { _ = try catalog(chain, events: [note, note]) }
        rejects("event value limit") { _ = try catalog(chain, events: [StudyEvent(wordID: entry, kind: "note", value: String(repeating: "a", count: 100_001), timestamp: t)]) }
        rejects("dangling event") { _ = try catalog(chain, events: [StudyEvent(kind: "answer", value: "0", timestamp: t, questionID: UUID())]) }
        let tooManyEvents = (0..<100_000).map { _ in StudyEvent(wordID: entry, kind: "note", value: "", timestamp: t) }
        rejects("combined event and revision limit") { _ = try catalog([root], events: tooManyEvents) }
        rejects("data limit") { _ = try SnapshotCodec.decode(data: Data(repeating: 32, count: 20_000_001), builtInWords: [], builtInQuestions: [], now: t) }
        // Duplicate built-in names must never trap or capture personal names.
        let duplicate = Word(id: UUID(), word: library.words[0].word, pinyin: "", category: "", subcategory: "", section: "", meanings: ["意义"], keyPoints: "", confusableWords: [], examples: [], occurrences: [], sourceDeleted: false)
        _ = try SnapshotCodec.validate(snapshot: StudySnapshot(), builtInWords: library.words + [duplicate], builtInQuestions: library.questions, now: t)
        _ = LearningEngine.reduce(words: library.words + [duplicate], questions: library.questions, events: [])
        print("PASS: personal library identity, history, DAG, conflict, codec and limits")
    }
}
