import Foundation

// Deterministic learning rules shared by the app and the standalone macOS tests.
enum LearningEngine {
    struct Context {
        fileprivate let questionsByID: [UUID: Question]
        fileprivate let linksByQuestionID: [UUID: [UUID]]

        init(words: [Word], questions: [Question]) {
            let names = LearningEngine.builtInNameLookup(words: words)
            questionsByID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
            linksByQuestionID = Dictionary(uniqueKeysWithValues: questions.map {
                ($0.id, LearningEngine.relatedWordIDs(for: $0, builtInNames: names))
            })
        }

        func relatedWordIDs(for question: Question) -> [UUID] {
            linksByQuestionID[question.id] ?? []
        }
    }
    private static func builtInNameLookup(words: [Word]) -> [String: UUID] {
        var result: [String: UUID] = [:]
        for word in words where !word.isPersonal {
            // A duplicated bundled spelling resolves deterministically, without trapping.
            if let previous = result[word.word], previous.uuidString < word.id.uuidString { continue }
            result[word.word] = word.id
        }
        return result
    }
    private static func relatedWordIDs(for question: Question, builtInNames: [String: UUID]) -> [UUID] {
        let ids = question.personalEntryID == nil ? question.relatedWords.compactMap { builtInNames[$0] } : question.relatedWordIDs
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
    static func relatedWordIDs(for question: Question, words: [Word]) -> [UUID] {
        relatedWordIDs(for: question, builtInNames: question.personalEntryID == nil ? builtInNameLookup(words: words) : [:])
    }
    static func apply(_ e: StudyEvent, context: Context,
                      records: inout [UUID: StudyRecord], answers: inout [QuestionRecord]) {
        if e.kind == "answer", let id = e.questionID, let q = context.questionsByID[id], let answer = Int(e.value) {
            let correct = answer == q.correctAnswer
            answers.append(QuestionRecord(id: e.id, questionId: id, isCorrect: correct, selectedAnswer: answer, answeredAt: e.date))
            for wid in context.linksByQuestionID[id] ?? [] {
                var r = records[wid] ?? StudyRecord()
                if !correct {
                    r.errorCount += 1; r.errorHistory.append(e); r.lastErrorDate = e.date
                    r.nextReviewDate = e.date.addingTimeInterval(600)
                    r.masteryLevel = .learning; r.streak = 0
                }
                if r.masteryLevel == .unknown {
                    r.masteryLevel = .learning
                    r.nextReviewDate = e.date.addingTimeInterval(86400)
                }
                r.lastStudyDate = max(r.lastStudyDate, e.date); records[wid] = r
            }
        } else if let id = e.wordID {
            var r = records[id] ?? StudyRecord()
            switch e.kind {
            case "favorite": r.isFavorite = e.value == "true"
            case "mastery":
                r.masteryLevel = MasteryLevel(rawValue: e.value) ?? .unknown
                r.nextReviewDate = e.date.addingTimeInterval(r.masteryLevel == .mastered ? 30 * 86400 : 86400)
            case "note": r.personalNotes = e.value; r.noteHistory.append(e)
            case "synonym": r.personalSynonyms = PersonalSynonyms.decode(e.value); r.synonymHistory.append(e)
            case "errorAdjustment":
                let delta = Int(e.value) ?? 0
                r.errorCount = max(0, r.errorCount + delta); r.errorHistory.append(e)
                if delta > 0 { r.lastErrorDate = e.date; r.nextReviewDate = e.date.addingTimeInterval(600); if r.masteryLevel == .unknown { r.masteryLevel = .learning } }
            case "review": r.reviewDate = e.date; if r.masteryLevel == .unknown { r.masteryLevel = .learning }
            case "rating":
                r.reviewDate = e.date; r.reviewCount += 1
                switch Int(e.value) ?? 0 {
                case 0:
                    r.streak = 0; r.masteryLevel = .learning; r.errorCount += 1
                    r.errorHistory.append(e); r.lastErrorDate = e.date
                    r.nextReviewDate = e.date.addingTimeInterval(600)
                case 1:
                    r.streak = 0; r.masteryLevel = .learning
                    r.nextReviewDate = e.date.addingTimeInterval(86400)
                default:
                    r.streak += 1; r.masteryLevel = r.streak >= 4 ? .mastered : .familiar
                    let days = [1, 3, 7, 14, 30][min(r.streak - 1, 4)]
                    r.nextReviewDate = e.date.addingTimeInterval(Double(days) * 86400)
                }
            default: break
            }
            if ["mastery", "review", "errorAdjustment", "rating"].contains(e.kind) { r.lastStudyDate = max(r.lastStudyDate, e.date) }
            records[id] = r
        }
    }
    static func reduce(words: [Word], questions: [Question], events: [StudyEvent]) -> (records: [UUID: StudyRecord], answers: [QuestionRecord]) {
        let context = Context(words: words, questions: questions)
        var records: [UUID: StudyRecord] = [:], answers: [QuestionRecord] = []
        let ordered = events.sorted { $0.timestamp == $1.timestamp ? $0.id.uuidString < $1.id.uuidString : $0.timestamp < $1.timestamp }
        for event in ordered { apply(event, context: context, records: &records, answers: &answers) }
        return (records, answers)
    }
}
