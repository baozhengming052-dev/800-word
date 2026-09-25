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
    /// 自己补充的近义词：与内置「关联词辨析」同结构（词 + 区别说明），默认没有。
    var personalSynonyms: [ConfusableWord] = []
    var synonymHistory: [StudyEvent] = []
    var errorHistory: [StudyEvent] = []
    var lastStudyDate: Date = .distantPast
    var lastErrorDate: Date = .distantPast
    var reviewDate: Date = .distantPast
    var nextReviewDate: Date = .distantFuture
    var streak = 0
    var reviewCount = 0
}

/// A note event holds the layout; immutable noteImage events hold JPEG bytes once.
/// Plain strings remain valid notes from older releases.
struct NoteBlock: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case text, image }
    var id: UUID
    var kind: Kind
    var text: String
    var imageID: UUID?
    static func paragraph(_ text: String = "") -> NoteBlock {
        NoteBlock(id: UUID(), kind: .text, text: text, imageID: nil)
    }
    static func image(_ id: UUID) -> NoteBlock {
        NoteBlock(id: UUID(), kind: .image, text: "", imageID: id)
    }
}

struct RichNote: Codable, Equatable {
    static let prefix = "WORDS800_RICH_NOTE_V1:"
    var blocks: [NoteBlock]
    static func decode(_ value: String) -> RichNote? {
        guard value.hasPrefix(prefix) else { return RichNote(blocks: [.paragraph(value)]) }
        let payload = String(value.dropFirst(prefix.count))
        guard let bytes = payload.data(using: .utf8),
              let note = try? JSONDecoder().decode(RichNote.self, from: bytes), note.isValid else { return nil }
        return note
    }
    var isValid: Bool {
        blocks.count <= 100 && Set(blocks.map(\.id)).count == blocks.count && blocks.allSatisfy { block in
            switch block.kind {
            case .text: return block.imageID == nil && block.text.utf8.count <= 100_000
            case .image: return block.imageID != nil && block.text.isEmpty
            }
        }
    }
    func encode() throws -> String {
        guard isValid else { throw PersonalLibraryError.invalid("笔记内容无效或段落过多。") }
        if blocks.isEmpty { return "" }
        if blocks.allSatisfy({ $0.kind == .text && $0.text.isEmpty }) { return "" }
        if blocks.count == 1, blocks[0].kind == .text { return blocks[0].text }
        let payload = String(decoding: try JSONEncoder().encode(self), as: UTF8.self)
        let value = Self.prefix + payload
        guard value.utf8.count <= 100_000 else { throw PersonalLibraryError.invalid("笔记文字不能超过 100,000 UTF-8 字节。") }
        return value
    }
    var summary: String {
        let text = blocks.map { $0.kind == .image ? "[图片]" : $0.text }.joined(separator: "\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "空笔记" : text
    }
    static func combined(_ left: String, _ right: String) throws -> String {
        if !left.hasPrefix(prefix) && !right.hasPrefix(prefix) {
            let value = [left, right].filter { !$0.isEmpty }.joined(separator: "\n\n")
            guard value.utf8.count <= 100_000 else { throw PersonalLibraryError.invalid("合并后的笔记过长。") }
            return value
        }
        guard let a = decode(left), let b = decode(right) else { throw PersonalLibraryError.invalid("笔记内容无效。") }
        var blocks = left.isEmpty ? [] : a.blocks
        if !blocks.isEmpty && !b.blocks.isEmpty { blocks.append(.paragraph("")) }
        if !right.isEmpty {
            var used = Set(blocks.map(\.id))
            for var block in b.blocks {
                if used.contains(block.id) { block.id = UUID() }
                used.insert(block.id)
                blocks.append(block)
            }
        }
        return try RichNote(blocks: blocks).encode()
    }
}

enum NoteImageLimits {
    static let maximumBytes = 5_000_000
    static let maximumEventBytes = ((maximumBytes + 2) / 3) * 4
}
struct QuestionRecord: Identifiable {
    let id: UUID
    let questionId: UUID
    let isCorrect: Bool
    let selectedAnswer: Int
    let answeredAt: Date
}

/// 个人补充的近义词，保存在 `kind = "synonym"` 的学习事件里。整份列表作为一条不可变事件保存，
/// 沿用笔记的「最新一条生效、历史全部保留」规则，因此备份格式、附近同步和冲突选择都不需要新增数据格式；快照仍是 v3。
enum PersonalSynonyms {
    static let maximumEntries = 200
    static let maximumNameLength = 80
    static let maximumDifferenceLength = 10_000
    static let maximumBytes = 100_000

    /// 去空格、丢掉空名字和超长内容，并按词语去重（后写的覆盖先写的，位置不变）。
    static func normalize(_ items: [ConfusableWord]) -> [ConfusableWord] {
        var result: [ConfusableWord] = []
        for item in items {
            let name = PersonalLibrary.trimmed(item.word)
            let difference = PersonalLibrary.trimmed(item.difference)
            guard !name.isEmpty, name.count <= maximumNameLength, difference.count <= maximumDifferenceLength else { continue }
            let entry = ConfusableWord(word: name, difference: difference)
            if let index = result.firstIndex(where: { PersonalLibrary.normalizedName($0.word) == PersonalLibrary.normalizedName(name) }) {
                result[index] = entry
            } else { result.append(entry) }
        }
        return result
    }

    /// 稳定编码（键排序）：同一份列表在两台设备上产生完全相同的字节，便于去重和冲突比较。
    static func encode(_ items: [ConfusableWord]) throws -> String {
        let value = normalize(items)
        guard value.count <= maximumEntries else { throw PersonalLibraryError.invalid("补充的近义词最多 \(maximumEntries) 条。") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        guard let text = String(data: data, encoding: .utf8), text.utf8.count <= maximumBytes else {
            throw PersonalLibraryError.invalid("补充的近义词内容过长，请精简区别说明。")
        }
        return text
    }

    /// 只接受本 App 写出的规范载荷，避免未整理过的内容进入记录和同步。
    static func decoded(_ value: String) -> [ConfusableWord]? {
        guard value.utf8.count <= maximumBytes,
              let items = try? JSONDecoder().decode([ConfusableWord].self, from: Data(value.utf8)),
              let canonical = try? encode(items), canonical == value else { return nil }
        return items
    }
    static func isValid(_ value: String) -> Bool { decoded(value) != nil }
    /// 归约用：历史记录即使无法解析也不影响其他学习数据。
    static func decode(_ value: String) -> [ConfusableWord] { decoded(value) ?? [] }

    /// 两台都改过时把两份列表按词语合并：本机顺序在前，只补充对方独有的条目。
    static func merged(_ local: [ConfusableWord], _ incoming: [ConfusableWord]) -> [ConfusableWord] {
        var result = normalize(local)
        var seen = Set(result.map { PersonalLibrary.normalizedName($0.word) })
        for item in normalize(incoming) where seen.insert(PersonalLibrary.normalizedName(item.word)).inserted {
            result.append(item)
        }
        return result
    }

    static func summary(_ items: [ConfusableWord]) -> String {
        guard !items.isEmpty else { return "（没有补充近义词）" }
        return items.map { $0.difference.isEmpty ? $0.word : "\($0.word)：\($0.difference)" }.joined(separator: "\n")
    }
    /// 冲突选择界面显示用：把记录里的规范载荷转成可读文字。
    static func displayText(_ value: String) -> String { summary(decode(value)) }
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
