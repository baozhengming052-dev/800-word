import Foundation

@main struct LearningEngineTests {
    static func main() throws {
        let path = CommandLine.arguments[1]
        let library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let word = library.words.first { $0.word == "源远流长" }!
        let question = library.questions.first { $0.relatedWords == [word.word] }!
        let t = 1_700_000_000_000.0
        func event(_ kind: String, _ value: String, _ offset: Double) -> StudyEvent {
            StudyEvent(wordID: word.id, kind: kind, value: value, timestamp: t + offset)
        }
        func record(_ events: [StudyEvent]) -> StudyRecord {
            LearningEngine.reduce(words: library.words, questions: library.questions, events: events).records[word.id] ?? StudyRecord()
        }
        let wrong = StudyEvent(kind: "answer", value: String((question.correctAnswer + 1) % 4), timestamp: t, questionID: question.id)
        let correct = StudyEvent(kind: "answer", value: String(question.correctAnswer), timestamp: t + 1, questionID: question.id)
        assert(record([wrong]).errorCount == 1, "Wrong answers add exactly one error")
        assert(record([correct]).errorCount == 0, "Correct answers never add errors")
        assert(record([correct]).nextReviewDate == correct.date.addingTimeInterval(86400), "First correct answer schedules review")
        assert(record([wrong, event("errorAdjustment", "4", 10)]).errorCount == 5, "Manual editing can increase total")
        let reset = record([wrong, event("errorAdjustment", "-1", 10)])
        assert(reset.errorCount == 0 && reset.errorHistory.count == 2, "Zero total keeps error history")
        assert(record([event("errorAdjustment", "-100", 10)]).errorCount == 0, "Counts cannot be negative")
        let rating = record([event("rating", "0", 10)])
        assert(rating.errorCount == 1 && rating.masteryLevel == .learning, "Forgot adds error and learning state")
        assert(rating.nextReviewDate.timeIntervalSince1970 == (t + 10) / 1000 + 600, "Forgot schedules ten minutes")
        let known = (0..<4).map { event("rating", "2", Double($0) * 1000) }
        let mastered = record(known)
        assert(mastered.masteryLevel == .mastered && mastered.streak == 4, "Repeated recall advances mastery")
        assert(mastered.nextReviewDate.timeIntervalSince1970 == (t + 3000) / 1000 + 14 * 86400, "Fourth recall schedules fourteen days")
        let notes = [event("note", "first", 1), event("note", "second", 2)]
        assert(record(Array(notes.reversed())).personalNotes == "second", "Chronology is independent of input order")
        assert(record(notes).noteHistory.count == 2, "Both note revisions retained")
        assert(record([event("favorite", "true", 1), event("favorite", "false", 2)]).isFavorite == false, "Unfavorite persists")
        let sample = StudySnapshot(events: [wrong, correct] + notes)
        let decoded = try JSONDecoder().decode(StudySnapshot.self, from: JSONEncoder().encode(sample))
        assert(sample.events == decoded.events, "Backup is lossless")
        let reduced = LearningEngine.reduce(words: library.words, questions: library.questions, events: decoded.events)
        assert(reduced.answers.count == 2 && reduced.answers.filter { $0.isCorrect }.count == 1, "Statistics reflect actual attempts")
        let ownWord = PersonalRevision(entryID: UUID(), timestamp: t, word: PersonalWordContent(word: "自己的词", meaning: "意义"))
        let otherWord = PersonalRevision(entryID: UUID(), timestamp: t, word: PersonalWordContent(word: word.word, meaning: "同名个人词"))
        let original = PersonalRevision(entryID: UUID(), timestamp: t, question: PersonalQuestionContent(content: "旧题", options: ["甲", "乙", "丙", "丁"], correctAnswer: 1, explanation: "旧解析", relatedWordIDs: [ownWord.entryID]))
        let edit = PersonalRevision(entryID: original.entryID, parents: [original.id], timestamp: t + 1, question: PersonalQuestionContent(content: "新题", options: ["甲", "乙", "丙", "丁"], correctAnswer: 0, explanation: "新解析", relatedWordIDs: [otherWord.entryID]))
        let catalog = try SnapshotCodec.validate(snapshot: StudySnapshot(revisions: [ownWord, otherWord, original, edit]), builtInWords: library.words, builtInQuestions: library.questions, now: t)
        let oldAnswer = StudyEvent(kind: "answer", value: "0", timestamp: t, questionID: original.id)
        let historical = LearningEngine.reduce(words: catalog.words, questions: catalog.questions, events: [oldAnswer])
        assert(historical.answers.first?.isCorrect == false, "Old answers must use the old answer key")
        assert(historical.records[ownWord.entryID]?.errorCount == 1 && historical.records[otherWord.entryID] == nil, "Old answers retain the original UUID association")
        let builtInAnswer = LearningEngine.reduce(words: catalog.words, questions: catalog.questions, events: [wrong])
        assert(builtInAnswer.records[word.id]?.errorCount == 1 && builtInAnswer.records[otherWord.entryID] == nil, "Built-in names never capture personal words")
        let incrementalEvents = [wrong, correct, event("favorite", "true", 2), event("rating", "0", 3), event("note", "增量笔记", 4)]
        let context = LearningEngine.Context(words: library.words, questions: library.questions)
        var incrementalRecords: [UUID: StudyRecord] = [:]
        var incrementalAnswers: [QuestionRecord] = []
        for item in incrementalEvents {
            LearningEngine.apply(item, context: context, records: &incrementalRecords, answers: &incrementalAnswers)
        }
        let complete = LearningEngine.reduce(words: library.words, questions: library.questions, events: incrementalEvents)
        let incremental = incrementalRecords[word.id]!
        let completeRecord = complete.records[word.id]!
        assert(incremental.errorCount == completeRecord.errorCount && incremental.isFavorite == completeRecord.isFavorite)
        assert(incremental.masteryLevel == completeRecord.masteryLevel && incremental.personalNotes == completeRecord.personalNotes)
        assert(incremental.nextReviewDate == completeRecord.nextReviewDate && incrementalAnswers.map(\.id) == complete.answers.map(\.id),
               "Incremental event updates must exactly match a complete history rebuild")
        assert(context.relatedWordIDs(for: question) == [word.id], "Cached question links preserve built-in associations")
        print("PASS: learning rules and revision-specific historical answers/links")
    }
}
