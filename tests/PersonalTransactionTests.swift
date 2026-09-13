import Foundation

@main struct PersonalTransactionTests {
    static func main() throws {
        func rejects(_ body: () throws -> Void) {
            do { try body(); fatalError("Expected transaction rejection") } catch { }
        }
        let entry = UUID()
        let empty = StudySnapshot()
        let first = try PersonalTransactions.word(snapshot: empty, builtInWords: [], builtInQuestions: [],
            content: PersonalWordContent(word: "  新词  ", meaning: "  新释义  "), entryID: entry,
            expectedHeads: [], notes: "  第一份笔记  ")
        assert(empty.revisions.isEmpty && empty.events.isEmpty, "Draft construction must not mutate the baseline")
        assert(first.revisions.count == 1 && first.events.count == 1, "A word and its note belong to one proposal")
        assert(first.revisions[0].word?.word == "新词" && first.events[0].value == "  第一份笔记  ")
        rejects { _ = try PersonalTransactions.word(snapshot: empty, builtInWords: [], builtInQuestions: [],
            content: PersonalWordContent(word: "字节界限", meaning: "意义"), entryID: UUID(),
            expectedHeads: [], notes: String(repeating: "中", count: 33_334)) }
        assert(first.events[0].wordID == entry)
        let longNote = try PersonalTransactions.word(snapshot: empty, builtInWords: [], builtInQuestions: [],
            content: PersonalWordContent(word: "长笔记", meaning: "意义"), entryID: UUID(), expectedHeads: [],
            notes: String(repeating: "x", count: 100_000))
        assert(longNote.events[0].value.utf8.count == 100_000, "Notes keep the existing byte limit, not the content character limit")
        let head = first.revisions[0].id
        let edited = try PersonalTransactions.word(snapshot: first, builtInWords: [], builtInQuestions: [],
            content: PersonalWordContent(word: "改名", meaning: "意义"), entryID: entry,
            expectedHeads: [head], notes: nil)
        assert(edited.revisions[1].parents == [head] && edited.revisions[1].entryID == entry)
        assert(edited.events == first.events && edited.revisions[0] == first.revisions[0])
        rejects { _ = try PersonalTransactions.word(snapshot: edited, builtInWords: [], builtInQuestions: [],
            content: PersonalWordContent(word: "过期编辑", meaning: "意义"), entryID: entry, expectedHeads: [head], notes: nil) }
        rejects { _ = try PersonalTransactions.word(snapshot: first, builtInWords: [], builtInQuestions: [],
            content: PersonalWordContent(word: " 新词 ", meaning: "重复"), entryID: UUID(), expectedHeads: [], notes: nil) }
        let questionID = UUID()
        var draft = PersonalQuestionContent(content: "题目", options: ["甲", "乙", "丙", "丁"],
            explanation: "解析", relatedWordIDs: [entry])
        rejects { _ = try PersonalTransactions.question(snapshot: first, builtInWords: [], builtInQuestions: [],
            content: draft, entryID: questionID, expectedHeads: []) }
        draft.correctAnswer = 2
        let withQuestion = try PersonalTransactions.question(snapshot: first, builtInWords: [], builtInQuestions: [],
            content: draft, entryID: questionID, expectedHeads: [])
        let frozenID = withQuestion.revisions.last!.id
        rejects { _ = try PersonalTransactions.question(snapshot: withQuestion, builtInWords: [], builtInQuestions: [],
            content: draft, entryID: questionID, expectedHeads: []) }
        var newAnswer = draft; newAnswer.correctAnswer = 0
        let revisedQuestion = try PersonalTransactions.question(snapshot: withQuestion, builtInWords: [], builtInQuestions: [],
            content: newAnswer, entryID: questionID, expectedHeads: [frozenID])
        let revisedCatalog = try SnapshotCodec.validate(snapshot: revisedQuestion, builtInWords: [], builtInQuestions: [])
        let oldAnswer = StudyEvent(kind: "answer", value: "2", questionID: frozenID)
        let state = LearningEngine.reduce(words: revisedCatalog.words, questions: revisedCatalog.questions, events: [oldAnswer])
        assert(state.answers.first?.isCorrect == true, "Editing the current answer cannot regrade an old version")
        assert(revisedCatalog.activeQuestions.count == 1 && revisedCatalog.activeQuestions[0].correctAnswer == 0)
        let archived = try PersonalTransactions.archive(snapshot: withQuestion, builtInWords: [], builtInQuestions: [],
            entryID: entry, expectedHeads: [head], archived: true)
        let catalog = try SnapshotCodec.validate(snapshot: archived, builtInWords: [], builtInQuestions: [])
        assert(PersonalTransactions.practiceQuestions(catalog: catalog).isEmpty, "Archived-only word links cannot enter a new session")
        assert(catalog.questions.contains { $0.id == frozenID }, "History retains the exact answer version")
        rejects { _ = try PersonalTransactions.archive(snapshot: archived, builtInWords: [], builtInQuestions: [],
            entryID: entry, expectedHeads: [head], archived: false) }
        rejects { _ = try PersonalTransactions.question(snapshot: archived, builtInWords: [], builtInQuestions: [],
            content: draft, entryID: UUID(), expectedHeads: []) }
        let restored = try PersonalTransactions.archive(snapshot: archived, builtInWords: [], builtInQuestions: [],
            entryID: entry, expectedHeads: [archived.revisions.last!.id], archived: false)
        let restoredCatalog = try SnapshotCodec.validate(snapshot: restored, builtInWords: [], builtInQuestions: [])
        assert(PersonalTransactions.practiceQuestions(catalog: restoredCatalog).map(\.id) == [frozenID])
        print("PASS: atomic drafts, captured heads, normalized duplicates, explicit answers, archive practice/history")
    }
}
