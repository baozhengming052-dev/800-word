import Foundation
import SwiftUI

struct Word: Identifiable, Codable, Hashable {
    let id: UUID
    let word: String
    let pinyin: String
    let category: String
    let subcategory: String
    let section: String
    let meanings: [String]
    let keyPoints: String
    let confusableWords: [ConfusableWord]
    let examples: [Example]
    let occurrences: [SourceOccurrence]
    let sourceDeleted: Bool
    var sourcePages: String { Array(Set(occurrences.map { $0.page })).sorted().map(String.init).joined(separator: "、") }
}
struct SourceOccurrence: Codable, Hashable {
    let originalWord: String
    let originalText: String
    let category: String
    let subcategory: String
    let page: Int
    let sourceDeleted: Bool
    let correctionNote: String
}
struct ConfusableWord: Codable, Hashable { let word: String; let difference: String }
struct Example: Codable, Hashable { let sentence: String; let translation: String }
struct Question: Identifiable, Codable {
    let id: UUID
    let content: String
    let options: [String]
    let correctAnswer: Int
    let explanation: String
    let relatedWords: [String]
    let type: QuestionType
    let source: String
    let sourceURL: String
}
enum QuestionType: String, Codable, CaseIterable {
    case realExam = "真题"
    case practice = "模拟题"
    case definition = "释义自测"
}
struct Library: Codable { let schemaVersion: Int; let source: String; let words: [Word]; let questions: [Question] }
enum MasteryLevel: String, Codable, CaseIterable {
    case unknown = "未学习", learning = "学习中", familiar = "熟悉", mastered = "已掌握"
    var color: Color {
        switch self { case .unknown: return .secondary; case .learning: return .orange; case .familiar: return .blue; case .mastered: return .green }
    }
}
// Stable event IDs make backup imports idempotent and preserve every note revision.
struct StudyEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let wordID: UUID?
    let kind: String
    let value: String
    let timestamp: Double
    let questionID: UUID?
    init(id: UUID = UUID(), wordID: UUID? = nil, kind: String, value: String,
         timestamp: Double = Date().timeIntervalSince1970 * 1000, questionID: UUID? = nil) {
        self.id = id; self.wordID = wordID; self.kind = kind; self.value = value
        self.timestamp = timestamp; self.questionID = questionID
    }
    var date: Date { Date(timeIntervalSince1970: timestamp / 1000) }
}
struct StudySnapshot: Codable { var schemaVersion = 2; var events: [StudyEvent] = [] }
struct StudyRecord {
    var errorCount = 0
    var isFavorite = false
    var masteryLevel: MasteryLevel = .unknown
    var personalNotes = ""
    var noteHistory: [StudyEvent] = []
    var errorHistory: [StudyEvent] = []
    var lastStudyDate: Date = .distantPast
    var lastErrorDate: Date = .distantPast
    var reviewDate: Date = .distantPast
    var nextReviewDate: Date = .distantFuture
    var streak = 0
    var reviewCount = 0
}
struct QuestionRecord: Identifiable {
    let id: UUID
    let questionId: UUID
    let isCorrect: Bool
    let selectedAnswer: Int
    let answeredAt: Date
}
enum WordSort: String, CaseIterable {
    case original = "资料顺序", errors = "错误次数最多", recent = "最近学习"
}
enum AppStyle {
    static let accent = Color(red: 0.06, green: 0.43, blue: 0.53)
}
