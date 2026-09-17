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
    var isPersonal: Bool = false
    init(id: UUID, word: String, pinyin: String, category: String, subcategory: String, section: String,
         meanings: [String], keyPoints: String, confusableWords: [ConfusableWord], examples: [Example],
         occurrences: [SourceOccurrence], sourceDeleted: Bool, isPersonal: Bool = false) {
        self.id = id; self.word = word; self.pinyin = pinyin; self.category = category
        self.subcategory = subcategory; self.section = section; self.meanings = meanings
        self.keyPoints = keyPoints; self.confusableWords = confusableWords; self.examples = examples
        self.occurrences = occurrences; self.sourceDeleted = sourceDeleted; self.isPersonal = isPersonal
    }
    private enum CodingKeys: String, CodingKey {
        case id, word, pinyin, category, subcategory, section, meanings, keyPoints, confusableWords, examples, occurrences, sourceDeleted, isPersonal
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); word = try c.decode(String.self, forKey: .word)
        pinyin = try c.decode(String.self, forKey: .pinyin); category = try c.decode(String.self, forKey: .category)
        subcategory = try c.decode(String.self, forKey: .subcategory); section = try c.decode(String.self, forKey: .section)
        meanings = try c.decode([String].self, forKey: .meanings); keyPoints = try c.decode(String.self, forKey: .keyPoints)
        confusableWords = try c.decode([ConfusableWord].self, forKey: .confusableWords)
        examples = try c.decode([Example].self, forKey: .examples); occurrences = try c.decode([SourceOccurrence].self, forKey: .occurrences)
        sourceDeleted = try c.decode(Bool.self, forKey: .sourceDeleted)
        isPersonal = try c.decodeIfPresent(Bool.self, forKey: .isPersonal) ?? false
    }
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
    var personalEntryID: UUID? = nil
    var relatedWordIDs: [UUID] = []
    init(id: UUID, content: String, options: [String], correctAnswer: Int, explanation: String,
         relatedWords: [String], type: QuestionType, source: String, sourceURL: String,
         personalEntryID: UUID? = nil, relatedWordIDs: [UUID] = []) {
        self.id = id; self.content = content; self.options = options; self.correctAnswer = correctAnswer
        self.explanation = explanation; self.relatedWords = relatedWords; self.type = type
        self.source = source; self.sourceURL = sourceURL; self.personalEntryID = personalEntryID
        self.relatedWordIDs = relatedWordIDs
    }
    private enum CodingKeys: String, CodingKey {
        case id, content, options, correctAnswer, explanation, relatedWords, type, source, sourceURL, personalEntryID, relatedWordIDs
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); content = try c.decode(String.self, forKey: .content)
        options = try c.decode([String].self, forKey: .options); correctAnswer = try c.decode(Int.self, forKey: .correctAnswer)
        explanation = try c.decode(String.self, forKey: .explanation); relatedWords = try c.decode([String].self, forKey: .relatedWords)
        type = try c.decode(QuestionType.self, forKey: .type); source = try c.decode(String.self, forKey: .source)
        sourceURL = try c.decode(String.self, forKey: .sourceURL)
        personalEntryID = try c.decodeIfPresent(UUID.self, forKey: .personalEntryID)
        relatedWordIDs = try c.decodeIfPresent([UUID].self, forKey: .relatedWordIDs) ?? []
    }
}
enum QuestionType: String, Codable, CaseIterable {
    case realExam = "真题"
    case practice = "模拟题"
    case definition = "释义自测"
    case manual = "手动录入"
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
struct StudySnapshot: Codable, Equatable {
    var schemaVersion: Int
    var events: [StudyEvent]
    var revisions: [PersonalRevision]
    init(schemaVersion: Int = 3, events: [StudyEvent] = [], revisions: [PersonalRevision] = []) {
        self.schemaVersion = schemaVersion; self.events = events; self.revisions = revisions
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, events, revisions }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        events = try c.decode([StudyEvent].self, forKey: .events)
        // Only a legacy snapshot may omit the directory. A truncated v3 is not empty data.
        if schemaVersion == 2 { revisions = try c.decodeIfPresent([PersonalRevision].self, forKey: .revisions) ?? [] }
        else { revisions = try c.decode([PersonalRevision].self, forKey: .revisions) }
    }
}
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
enum ErrorWordSort: String, CaseIterable, Hashable {
    case errors = "错误次数最多"
    case latestError = "最近错题（日期）"
    case earliestError = "最早错题（日期）"
}
enum AppStyle {
    static let accent = Color(red: 0.06, green: 0.43, blue: 0.53)
}
