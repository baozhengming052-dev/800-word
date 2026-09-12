import Foundation
import SwiftUI

// MARK: - Word Model
struct Word: Identifiable, Codable, Hashable {
    let id: UUID
    let word: String
    let pinyin: String
    let category: String
    let meanings: [String]
    let keyPoints: String
    let confusableWords: [ConfusableWord]
    let examples: [Example]

    init(id: UUID = UUID(), word: String, pinyin: String, category: String, meanings: [String], keyPoints: String, confusableWords: [ConfusableWord], examples: [Example]) {
        self.id = id
        self.word = word
        self.pinyin = pinyin
        self.category = category
        self.meanings = meanings
        self.keyPoints = keyPoints
        self.confusableWords = confusableWords
        self.examples = examples
    }
}

struct ConfusableWord: Codable, Hashable {
    let word: String
    let difference: String
}

struct Example: Codable, Hashable {
    let sentence: String
    let translation: String
}

// MARK: - Question Model
struct Question: Identifiable, Codable {
    let id: UUID
    let content: String
    let options: [String]
    let correctAnswer: Int
    let explanation: String
    let relatedWords: [String]
    let type: QuestionType
    let source: String // "国考2023" etc

    init(id: UUID = UUID(), content: String, options: [String], correctAnswer: Int, explanation: String, relatedWords: [String], type: QuestionType, source: String) {
        self.id = id
        self.content = content
        self.options = options
        self.correctAnswer = correctAnswer
        self.explanation = explanation
        self.relatedWords = relatedWords
        self.type = type
        self.source = source
    }
}

enum QuestionType: String, Codable, CaseIterable {
    case realExam = "真题"
    case practice = "模拟题"
}

// MARK: - User Study Record
struct StudyRecord: Identifiable, Codable {
    let id: UUID
    let wordId: UUID
    var errorCount: Int
    var isFavorite: Bool
    var masteryLevel: MasteryLevel
    var personalNotes: String
    var errorHistory: [ErrorRecord]
    var lastStudyDate: Date

    init(id: UUID = UUID(), wordId: UUID, errorCount: Int = 0, isFavorite: Bool = false, masteryLevel: MasteryLevel = .unknown, personalNotes: String = "", errorHistory: [ErrorRecord] = [], lastStudyDate: Date = Date()) {
        self.id = id
        self.wordId = wordId
        self.errorCount = errorCount
        self.isFavorite = isFavorite
        self.masteryLevel = masteryLevel
        self.personalNotes = personalNotes
        self.errorHistory = errorHistory
        self.lastStudyDate = lastStudyDate
    }
}

enum MasteryLevel: String, Codable, CaseIterable {
    case unknown = "未学习"
    case learning = "学习中"
    case familiar = "熟悉"
    case mastered = "已掌握"

    var color: Color {
        switch self {
        case .unknown: return .gray
        case .learning: return .orange
        case .familiar: return .blue
        case .mastered: return .green
        }
    }
}

struct ErrorRecord: Identifiable, Codable {
    let id: UUID
    let date: Date
    let questionId: UUID?
    let context: String

    init(id: UUID = UUID(), date: Date = Date(), questionId: UUID? = nil, context: String) {
        self.id = id
        self.date = date
        self.questionId = questionId
        self.context = context
    }
}

// MARK: - Question Record
struct QuestionRecord: Identifiable, Codable {
    let id: UUID
    let questionId: UUID
    var isCorrect: Bool
    let answeredAt: Date
    let selectedAnswer: Int

    init(id: UUID = UUID(), questionId: UUID, isCorrect: Bool, answeredAt: Date = Date(), selectedAnswer: Int) {
        self.id = id
        self.questionId = questionId
        self.isCorrect = isCorrect
        self.answeredAt = answeredAt
        self.selectedAnswer = selectedAnswer
    }
}
