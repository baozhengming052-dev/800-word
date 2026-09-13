import Foundation

struct PersonalWordContent: Codable, Equatable {
    var word: String
    var meaning: String
    var pinyin: String
    var category: String
    var example: String
    var keyPoints: String
    init(word: String = "", meaning: String = "", pinyin: String = "", category: String = "", example: String = "", keyPoints: String = "") {
        self.word = word; self.meaning = meaning; self.pinyin = pinyin; self.category = category
        self.example = example; self.keyPoints = keyPoints
    }
    private enum CodingKeys: String, CodingKey { case word, meaning, pinyin, category, example, keyPoints }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        word = try c.decode(String.self, forKey: .word); meaning = try c.decode(String.self, forKey: .meaning)
        pinyin = try c.decodeIfPresent(String.self, forKey: .pinyin) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        example = try c.decodeIfPresent(String.self, forKey: .example) ?? ""
        keyPoints = try c.decodeIfPresent(String.self, forKey: .keyPoints) ?? ""
    }
}

struct PersonalQuestionContent: Codable, Equatable {
    var content: String
    var options: [String]
    var correctAnswer: Int
    var explanation: String
    var relatedWordIDs: [UUID]
    var source: String
    init(content: String = "", options: [String] = ["", "", "", ""], correctAnswer: Int = -1,
         explanation: String = "", relatedWordIDs: [UUID] = [], source: String = "") {
        self.content = content; self.options = options; self.correctAnswer = correctAnswer
        self.explanation = explanation; self.relatedWordIDs = relatedWordIDs; self.source = source
    }
    private enum CodingKeys: String, CodingKey { case content, options, correctAnswer, explanation, relatedWordIDs, source }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        content = try c.decode(String.self, forKey: .content); options = try c.decode([String].self, forKey: .options)
        correctAnswer = try c.decode(Int.self, forKey: .correctAnswer); explanation = try c.decode(String.self, forKey: .explanation)
        relatedWordIDs = try c.decode([UUID].self, forKey: .relatedWordIDs)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
    }
}

struct PersonalRevision: Codable, Equatable, Identifiable {
    let id: UUID
    let entryID: UUID
    let parents: [UUID]
    let timestamp: Double
    let word: PersonalWordContent?
    let question: PersonalQuestionContent?
    let archived: Bool
    init(id: UUID = UUID(), entryID: UUID, parents: [UUID] = [],
         timestamp: Double = Date().timeIntervalSince1970 * 1000,
         word: PersonalWordContent? = nil, question: PersonalQuestionContent? = nil, archived: Bool = false) {
        self.id = id; self.entryID = entryID; self.parents = parents; self.timestamp = timestamp
        self.word = word; self.question = question; self.archived = archived
    }
}

struct PersonalNameCollision: Identifiable {
    let normalizedName: String
    let wordIDs: [UUID]
    var id: String { normalizedName }
}

struct PersonalCatalog {
    /// Includes built-ins and one deterministic current projection per personal word, even archived ones.
    let words: [Word]
    /// Includes built-ins and EVERY personal question revision (including archived revisions).
    let questions: [Question]
    /// Current nonarchived question heads. Associated-word visibility is a runtime policy.
    let activeQuestions: [Question]
    let archivedWordIDs: Set<UUID>
    /// Sorted ascending by (timestamp, revision UUID); the last is the provisional display head.
    let headsByEntryID: [UUID: [PersonalRevision]]
    let nameCollisions: [PersonalNameCollision]
    var conflictingEntryIDs: Set<UUID> { Set(headsByEntryID.filter { $0.value.count > 1 }.keys) }
}

enum PersonalLibraryError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

enum PersonalLibrary {
    static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func normalizedName(_ text: String) -> String {
        trimmed(text).precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    static func normalize(_ content: PersonalWordContent) -> PersonalWordContent {
        PersonalWordContent(word: trimmed(content.word), meaning: trimmed(content.meaning), pinyin: trimmed(content.pinyin),
            category: trimmed(content.category), example: trimmed(content.example), keyPoints: trimmed(content.keyPoints))
    }
    static func normalize(_ content: PersonalQuestionContent) -> PersonalQuestionContent {
        PersonalQuestionContent(content: trimmed(content.content), options: content.options.map(trimmed), correctAnswer: content.correctAnswer,
            explanation: trimmed(content.explanation), relatedWordIDs: content.relatedWordIDs, source: trimmed(content.source))
    }
    static func validate(_ content: PersonalWordContent) throws {
        let value = normalize(content)
        guard !value.word.isEmpty, !value.meaning.isEmpty else { throw PersonalLibraryError.invalid("请填写词语和释义。") }
        guard content.word.count <= 80, content.pinyin.count <= 100, content.category.count <= 100,
              [content.meaning, content.example, content.keyPoints].allSatisfy({ $0.count <= 10_000 }) else {
            throw PersonalLibraryError.invalid("词条文字超过长度限制。")
        }
    }
    static func validate(_ content: PersonalQuestionContent, validWordIDs: Set<UUID>) throws {
        let value = normalize(content)
        guard !value.content.isEmpty, !value.explanation.isEmpty, value.options.count == 4, value.options.allSatisfy({ !$0.isEmpty }),
              Set(value.options.map(normalizedName)).count == 4, (0...3).contains(value.correctAnswer) else {
            throw PersonalLibraryError.invalid("请填写题干、解析、四个不同选项并选择正确答案。")
        }
        guard !value.relatedWordIDs.isEmpty, Set(value.relatedWordIDs).count == value.relatedWordIDs.count,
              Set(value.relatedWordIDs).isSubset(of: validWordIDs) else { throw PersonalLibraryError.invalid("请关联至少一个有效且不重复的词条。") }
        guard [content.content, content.explanation, content.source].allSatisfy({ $0.count <= 10_000 }),
              content.options.allSatisfy({ $0.count <= 2_000 }) else { throw PersonalLibraryError.invalid("题目文字超过长度限制。") }
    }

    static func build(builtInWords: [Word], builtInQuestions: [Question], snapshot: StudySnapshot,
                      now: Double = Date().timeIntervalSince1970 * 1000) throws -> PersonalCatalog {
        guard snapshot.revisions.count <= 100_000 else { throw PersonalLibraryError.invalid("个人内容数量超限。") }
        let builtInIDs = Set(builtInWords.map { $0.id } + builtInQuestions.map { $0.id })
        var byID: [UUID: PersonalRevision] = [:], kindByEntry: [UUID: Bool] = [:]
        let encoder = JSONEncoder()
        for revision in snapshot.revisions {
            guard (revision.word != nil) != (revision.question != nil), revision.timestamp.isFinite,
                  revision.timestamp >= 0, revision.timestamp <= now + 86_400_000,
                  !builtInIDs.contains(revision.id), !builtInIDs.contains(revision.entryID),
                  byID.updateValue(revision, forKey: revision.id) == nil else {
                throw PersonalLibraryError.invalid("个人内容编号、类型或时间无效。")
            }
            let isWord = revision.word != nil
            if let existing = kindByEntry[revision.entryID], existing != isWord { throw PersonalLibraryError.invalid("同一条目混用了词条和题目。") }
            kindByEntry[revision.entryID] = isWord
            guard try encoder.encode(revision).count <= 256 * 1024 else { throw PersonalLibraryError.invalid("单条个人内容过大。") }
        }
        guard Set(byID.keys).isDisjoint(with: Set(kindByEntry.keys)) else { throw PersonalLibraryError.invalid("条目编号和修订编号重复。") }
        let validWordIDs = Set(builtInWords.map { $0.id }).union(kindByEntry.filter { $0.value }.keys)
        var indegrees: [UUID: Int] = [:], children: [UUID: [UUID]] = [:]
        for revision in snapshot.revisions {
            if let word = revision.word { try validate(word) }
            if let question = revision.question { try validate(question, validWordIDs: validWordIDs) }
            guard Set(revision.parents).count == revision.parents.count else { throw PersonalLibraryError.invalid("修订父节点重复。") }
            indegrees[revision.id] = revision.parents.count
            for parentID in revision.parents {
                guard let parent = byID[parentID], parent.entryID == revision.entryID,
                      (parent.word != nil) == (revision.word != nil) else { throw PersonalLibraryError.invalid("修订父节点缺失或属于其他条目。") }
                children[parentID, default: []].append(revision.id)
            }
        }
        // Kahn's algorithm: unordered histories and deep edit chains take O(vertices + edges).
        var queue = indegrees.filter { $0.value == 0 }.map { $0.key }, offset = 0
        while offset < queue.count {
            let id = queue[offset]; offset += 1
            for child in children[id] ?? [] {
                indegrees[child, default: 0] -= 1
                if indegrees[child] == 0 { queue.append(child) }
            }
        }
        guard queue.count == byID.count else { throw PersonalLibraryError.invalid("修订历史包含循环。") }
        var heads: [UUID: [PersonalRevision]] = [:]
        for revision in snapshot.revisions where children[revision.id] == nil { heads[revision.entryID, default: []].append(revision) }
        for id in Array(heads.keys) { heads[id]?.sort(by: revisionOrder) }
        let selected = heads.values.compactMap { $0.last }.sorted { $0.entryID.uuidString < $1.entryID.uuidString }
        var words = builtInWords, questions = builtInQuestions, active = builtInQuestions, archived = Set<UUID>()
        for revision in selected {
            if let content = revision.word {
                let value = normalize(content)
                words.append(Word(id: revision.entryID, word: value.word, pinyin: value.pinyin, category: value.category.isEmpty ? "自建词" : value.category,
                    subcategory: "", section: "个人词库", meanings: [value.meaning], keyPoints: value.keyPoints,
                    confusableWords: [], examples: value.example.isEmpty ? [] : [Example(sentence: value.example, translation: "")],
                    occurrences: [], sourceDeleted: false, isPersonal: true))
                if revision.archived { archived.insert(revision.entryID) }
            } else if !revision.archived { active.append(projectQuestion(revision)) }
        }
        for revision in snapshot.revisions.sorted(by: revisionOrder) where revision.question != nil { questions.append(projectQuestion(revision)) }
        var names: [String: [UUID]] = [:]
        for word in words where !archived.contains(word.id) { names[normalizedName(word.word), default: []].append(word.id) }
        let personalWordIDs = Set(kindByEntry.filter { $0.value }.keys)
        let collisions = names.compactMap { name, ids -> PersonalNameCollision? in
            // Existing duplicate bundled names alone do not create a personal-content conflict.
            guard ids.count > 1, !Set(ids).isDisjoint(with: personalWordIDs) else { return nil }
            return PersonalNameCollision(normalizedName: name, wordIDs: ids.sorted { $0.uuidString < $1.uuidString })
        }.sorted { $0.normalizedName < $1.normalizedName }
        return PersonalCatalog(words: words, questions: questions, activeQuestions: active, archivedWordIDs: archived,
            headsByEntryID: heads, nameCollisions: collisions)
    }
    static func revisionOrder(_ lhs: PersonalRevision, _ rhs: PersonalRevision) -> Bool {
        lhs.timestamp == rhs.timestamp ? lhs.id.uuidString < rhs.id.uuidString : lhs.timestamp < rhs.timestamp
    }
    private static func projectQuestion(_ revision: PersonalRevision) -> Question {
        let value = normalize(revision.question!) // Only called after the complete directory validates.
        return Question(id: revision.id, content: value.content, options: value.options, correctAnswer: value.correctAnswer,
            explanation: value.explanation, relatedWords: [], type: .manual, source: value.source, sourceURL: "",
            personalEntryID: revision.entryID, relatedWordIDs: value.relatedWordIDs)
    }
}
