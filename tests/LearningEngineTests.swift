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
        print("PASS: 15 learning-engine assertions")
    }
}
