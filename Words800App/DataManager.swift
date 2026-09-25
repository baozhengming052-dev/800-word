import Foundation
import Combine
import UserNotifications
import CryptoKit

@MainActor final class DataManager: ObservableObject {
    private final class LearningViewState {
        var records: [UUID: StudyRecord] = [:]
        var answers: [QuestionRecord] = []
        var correctAnswerCount = 0
        var summaryDay = Date.distantPast
        var todayAnswerCount = 0
        var todayRatedWordIDs = Set<UUID>()
        init(records: [UUID: StudyRecord] = [:], answers: [QuestionRecord] = [], correctAnswerCount: Int = 0,
             summaryDay: Date = .distantPast, todayAnswerCount: Int = 0, todayRatedWordIDs: Set<UUID> = []) {
            self.records = records; self.answers = answers; self.correctAnswerCount = correctAnswerCount
            self.summaryDay = summaryDay; self.todayAnswerCount = todayAnswerCount; self.todayRatedWordIDs = todayRatedWordIDs
        }
    }
    static let shared = DataManager()
    @Published private(set) var words: [Word] = []
    @Published private(set) var questions: [Question] = []
    @Published private(set) var activeQuestions: [Question] = []
    @Published private(set) var archivedWordIDs: Set<UUID> = []
    @Published private(set) var personalHeads: [UUID: [PersonalRevision]] = [:]
    @Published private(set) var contentConflictCount = 0
    private var learningViewState = LearningViewState()
    @Published var message = ""
    let snapshotDidChange = PassthroughSubject<Void, Never>()
    private var snapshot = StudySnapshot()
    private var searchIndex: [UUID: String] = [:]
    private var wordsByID: [UUID: Word] = [:]
    private var questionsByID: [UUID: Question] = [:]
    private var learningContext = LearningEngine.Context(words: [], questions: [])
    private var activeQuestionsByWordID: [UUID: [Question]] = [:]
    private var errorWordCache: [ErrorWordSort: [Word]] = [:]
    private var wordIDs = Set<UUID>()
    private var eventIDs = Set<UUID>()
    private var noteImageValues: [UUID: String] = [:]
    private var noteImageWordIDs: [UUID: UUID] = [:]
    private let noteImageCache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 24_000_000
        return cache
    }()
    private var lastEventTimestamp = 0.0
    private var reminderRefreshWorkItem: DispatchWorkItem?
    private(set) var libraryFingerprint = ""
    private let directory: URL
    private var builtInWords: [Word] = []
    private var builtInQuestions: [Question] = []
    private var store: SnapshotStore?
    private var persistenceAvailable = true

    var studyRecords: [UUID: StudyRecord] { learningViewState.records }
    var questionRecords: [QuestionRecord] { learningViewState.answers }

    private init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Words800", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = Bundle.main.url(forResource: "library", withExtension: "json")
            guard let resource = url else { throw AppError.text("词库文件缺失，请重新安装完整安装包。") }
            let libraryData = try Data(contentsOf: resource)
            let library = try JSONDecoder().decode(Library.self, from: libraryData)
            libraryFingerprint = SHA256.hash(data: libraryData).map { String(format: "%02x", $0) }.joined()
            builtInWords = library.words; builtInQuestions = library.questions
            words = library.words; questions = library.questions
            let storage = SnapshotStore(directory: directory) { bytes in
                try SnapshotCodec.decode(data: bytes, builtInWords: library.words, builtInQuestions: library.questions)
            }
            store = storage
            if let loaded = try storage.load() { snapshot = loaded }
            else { try migrateLegacy() }
            try rebuild()
            if let recovery = storage.recoveryMessage { message = recovery }
        } catch {
            persistenceAvailable = false
            message = "载入失败，已暂停写入以保护记录：\(error.localizedDescription)"
        }
    }
    enum AppError: LocalizedError {
        case text(String)
        var errorDescription: String? { switch self { case .text(let text): return text } }
    }
    func getStudyRecord(for id: UUID) -> StudyRecord { studyRecords[id] ?? StudyRecord() }
    var categories: [String] {
        activeWords.reduce(into: [String]()) { result, word in
            for occurrence in word.occurrences where !result.contains(occurrence.category) { result.append(occurrence.category) }
            if word.isPersonal && !result.contains(word.category) { result.append(word.category) }
        }
    }
    var activeWords: [Word] { words.filter { !archivedWordIDs.contains($0.id) } }
    var errorWords: [Word] { errorWords(sortedBy: .errors) }
    var favoriteWords: [Word] { words.filter { getStudyRecord(for: $0.id).isFavorite } }
    var newWords: [Word] { activeWords.filter { !($0.sourceDeleted) && getStudyRecord(for: $0.id).masteryLevel == .unknown } }
    var dueWords: [Word] {
        sorted(activeWords.filter { word in
            let r = getStudyRecord(for: word.id)
            guard r.lastStudyDate != .distantPast else { return false }
            return r.nextReviewDate <= Date()
        }, by: .errors)
    }
    var accuracy: Int { questionRecords.isEmpty ? 0 : Int(100 * Double(learningViewState.correctAnswerCount) / Double(questionRecords.count)) }
    var todayCount: Int { learningViewState.todayAnswerCount }
    var todayLearnedCount: Int { learningViewState.todayRatedWordIDs.count }
    func belongs(_ word: Word, to category: String) -> Bool {
        category == "全部分类" || (word.isPersonal && word.category == category) || word.occurrences.contains { $0.category == category }
    }
    func sorted(_ list: [Word], by sort: WordSort) -> [Word] {
        switch sort {
        case .original: return list
        case .errors: return list.sorted {
            let a = getStudyRecord(for: $0.id), b = getStudyRecord(for: $1.id)
            if a.errorCount != b.errorCount { return a.errorCount > b.errorCount }
            if a.lastErrorDate != b.lastErrorDate { return a.lastErrorDate > b.lastErrorDate }
            return $0.word < $1.word
        }
        case .recent: return list.sorted { getStudyRecord(for: $0.id).lastStudyDate > getStudyRecord(for: $1.id).lastStudyDate }
        }
    }
    func errorWords(sortedBy sort: ErrorWordSort) -> [Word] {
        if let cached = errorWordCache[sort] { return cached }
        let result = activeWords.filter { getStudyRecord(for: $0.id).errorCount > 0 }.sorted { lhs, rhs in
            let left = getStudyRecord(for: lhs.id), right = getStudyRecord(for: rhs.id)
            switch sort {
            case .errors:
                if left.errorCount != right.errorCount { return left.errorCount > right.errorCount }
                if left.lastErrorDate != right.lastErrorDate { return left.lastErrorDate > right.lastErrorDate }
            case .latestError:
                if left.lastErrorDate != right.lastErrorDate { return left.lastErrorDate > right.lastErrorDate }
                if left.errorCount != right.errorCount { return left.errorCount > right.errorCount }
            case .earliestError:
                if left.lastErrorDate != right.lastErrorDate { return left.lastErrorDate < right.lastErrorDate }
                if left.errorCount != right.errorCount { return left.errorCount > right.errorCount }
            }
            return lhs.word < rhs.word
        }
        errorWordCache[sort] = result
        return result
    }
    private func invalidateErrorWordCache() { errorWordCache.removeAll(keepingCapacity: true) }
    private func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
    }
    func searchWords(keyword: String, includePersonalArchived: Bool = false) -> [Word] {
        let words = includePersonalArchived ? self.words : activeWords
        let key = normalize(keyword).trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return words }
        let tokens = key.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let direct = words.filter { w in tokens.allSatisfy { searchIndex[w.id, default: ""].contains($0) } }
        if !direct.isEmpty {
            return direct.sorted {
                let a = $0.word == key ? 0 : ($0.word.contains(key) ? 1 : 2)
                let b = $1.word == key ? 0 : ($1.word.contains(key) ? 1 : 2)
                return a < b
            }
        }
        return words.filter { word in
            let target = normalize(word.word)
            var remaining = Array(key)[...]
            for char in target where remaining.first == char { remaining = remaining.dropFirst() }
            return (key.count >= 2 && remaining.isEmpty) || (key.count >= 3 && editDistance(key, target) <= 1)
        }
    }
    private func editDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if abs(x.count - y.count) > 1 { return 2 }
        var previous = Array(0...y.count)
        for (i, c) in x.enumerated() {
            var row = [i + 1]
            for (j, d) in y.enumerated() { row.append(min(row[j] + 1, previous[j + 1] + 1, previous[j] + (c == d ? 0 : 1))) }
            previous = row
        }
        return previous.last ?? 0
    }
    @discardableResult private func append(_ event: StudyEvent) -> Bool {
        guard persistenceAvailable else { message = "学习记录未能载入，请先在“我的”导入有效备份。"; return false }
        guard let store = store else { message = "词库或存储目录未能载入，无法安全保存。"; return false }
        var proposed = snapshot
        // Preserve local action order even when two actions share a clock tick.
        let stamp = max(event.timestamp, lastEventTimestamp + 0.001)
        let storedEvent = StudyEvent(id: event.id, wordID: event.wordID, kind: event.kind,
            value: event.value, timestamp: stamp, questionID: event.questionID)
        guard validateIncrementalEvent(storedEvent) else {
            message = "学习记录内容无效，未写入。"
            return false
        }
        proposed.events.append(storedEvent)
        do {
            // The unchanged prefix was already validated. Keep an atomic previous copy, but do not
            // decode and revalidate three complete history files for every study tap.
            try store.saveValidated(proposed)
            let viewState = learningViewState
            objectWillChange.send()
            refreshDailyMetricsIfNeeded(viewState)
            let previousAnswerCount = viewState.answers.count
            LearningEngine.apply(storedEvent, context: learningContext, records: &viewState.records, answers: &viewState.answers)
            invalidateErrorWordCache()
            if viewState.answers.count > previousAnswerCount, let answer = viewState.answers.last {
                if answer.isCorrect { viewState.correctAnswerCount += 1 }
                if Calendar.current.isDate(answer.answeredAt, inSameDayAs: viewState.summaryDay) { viewState.todayAnswerCount += 1 }
            }
            if storedEvent.kind == "rating", let id = storedEvent.wordID,
               Calendar.current.isDate(storedEvent.date, inSameDayAs: viewState.summaryDay) {
                viewState.todayRatedWordIDs.insert(id)
            }
            snapshot = proposed; lastEventTimestamp = stamp; eventIDs.insert(storedEvent.id)
            snapshotDidChange.send()
            scheduleReminderRefresh()
            return true
        }
        catch { message = "保存失败：\(error.localizedDescription)"; return false }
    }
    private func validateIncrementalEvent(_ event: StudyEvent) -> Bool {
        guard snapshot.events.count < SnapshotCodec.maximumRecords - snapshot.revisions.count,
              !eventIDs.contains(event.id), event.timestamp.isFinite, event.timestamp >= 0,
              event.timestamp <= Date().timeIntervalSince1970 * 1000 + 86_400_000,
              event.value.utf8.count <= 100_000 else { return false }
        let kinds = Set(["answer", "favorite", "mastery", "note", "synonym", "errorAdjustment", "review", "rating"])
        guard kinds.contains(event.kind) else { return false }
        if let id = event.wordID, !wordIDs.contains(id) { return false }
        if let id = event.questionID, questionsByID[id] == nil { return false }
        if event.kind == "answer" {
            guard let id = event.questionID, let question = questionsByID[id], let answer = Int(event.value),
                  question.options.indices.contains(answer) else { return false }
        } else if event.wordID == nil { return false }
        switch event.kind {
        case "errorAdjustment": return Int(event.value).map { (-99999...99999).contains($0) } ?? false
        case "favorite": return ["true", "false"].contains(event.value)
        case "mastery": return MasteryLevel(rawValue: event.value) != nil
        case "rating": return ["0", "1", "2"].contains(event.value)
        case "synonym": return PersonalSynonyms.isValid(event.value)
        default: return true
        }
    }
    private func refreshDailyMetricsIfNeeded(_ state: LearningViewState, now: Date = Date()) {
        let day = Calendar.current.startOfDay(for: now)
        guard state.summaryDay != day else { return }
        state.summaryDay = day
        state.todayAnswerCount = state.answers.lazy.filter { Calendar.current.isDate($0.answeredAt, inSameDayAs: day) }.count
        state.todayRatedWordIDs = Set(snapshot.events.lazy.filter {
            $0.kind == "rating" && Calendar.current.isDate($0.date, inSameDayAs: day)
        }.compactMap(\.wordID))
    }
    func refreshDailyMetrics() {
        let state = learningViewState
        let day = Calendar.current.startOfDay(for: Date())
        guard state.summaryDay != day else { return }
        objectWillChange.send()
        refreshDailyMetricsIfNeeded(state)
    }
    func toggleFavorite(for id: UUID) {
        append(StudyEvent(wordID: id, kind: "favorite", value: getStudyRecord(for: id).isFavorite ? "false" : "true"))
    }
    func updateMasteryLevel(for id: UUID, level: MasteryLevel) { append(StudyEvent(wordID: id, kind: "mastery", value: level.rawValue)) }
    @discardableResult func updateNotes(for id: UUID, notes: String) -> Bool {
        guard notes != getStudyRecord(for: id).personalNotes else { return true }
        return append(StudyEvent(wordID: id, kind: "note", value: notes))
    }
    func noteImageData(for id: UUID) -> Data? {
        let key = id.uuidString as NSString
        if let cached = noteImageCache.object(forKey: key) { return cached as Data }
        guard let value = noteImageValues[id], let data = Data(base64Encoded: value) else { return nil }
        noteImageCache.setObject(data as NSData, forKey: key, cost: data.count)
        return data
    }
    func updateRichNote(for id: UUID, note: RichNote, newImages: [UUID: Data], expectedValue: String) throws {
        guard persistenceAvailable, let store = store else { throw AppError.text("记录尚未成功载入，无法保存笔记。") }
        guard wordIDs.contains(id), getStudyRecord(for: id).personalNotes == expectedValue else {
            throw AppError.text("这条笔记已在其他页面或同步中更新，请重新打开后编辑。")
        }
        let value = try note.encode()
        let imageIDs = note.blocks.compactMap(\.imageID)
        guard Set(imageIDs).count == imageIDs.count,
              imageIDs.allSatisfy({ newImages[$0] != nil || noteImageWordIDs[$0] == id }),
              newImages.keys.allSatisfy({ imageIDs.contains($0) && !eventIDs.contains($0) }) else {
            throw AppError.text("笔记图片缺失或重复，请重新选择。")
        }
        guard newImages.values.allSatisfy({ (100...NoteImageLimits.maximumBytes).contains($0.count) && $0.starts(with: [0xFF, 0xD8, 0xFF])
            && $0.suffix(2).elementsEqual([0xFF, 0xD9]) }) else {
            throw AppError.text("图片过大或格式无效，请重新选择。")
        }
        guard value != expectedValue || !newImages.isEmpty else { return }
        var proposed = snapshot
        var stamp = max(Date().timeIntervalSince1970 * 1000, lastEventTimestamp + 0.001)
        for imageID in imageIDs {
            guard let bytes = newImages[imageID] else { continue }
            proposed.events.append(StudyEvent(id: imageID, wordID: id, kind: "noteImage",
                value: bytes.base64EncodedString(), timestamp: stamp))
            stamp += 0.001
        }
        let noteEvent = StudyEvent(wordID: id, kind: "note", value: value, timestamp: stamp)
        proposed.events.append(noteEvent)
        guard proposed.events.count <= SnapshotCodec.maximumRecords - proposed.revisions.count else {
            throw AppError.text("笔记历史已达到记录上限。")
        }
        try store.saveValidated(proposed)
        objectWillChange.send()
        let viewState = learningViewState
        LearningEngine.apply(noteEvent, context: learningContext, records: &viewState.records, answers: &viewState.answers)
        for event in proposed.events.suffix(newImages.count + 1) where event.kind == "noteImage" {
            noteImageValues[event.id] = event.value
            noteImageWordIDs[event.id] = id
            eventIDs.insert(event.id)
        }
        eventIDs.insert(noteEvent.id)
        snapshot = proposed; lastEventTimestamp = stamp
        snapshotDidChange.send()
    }
    /// 补充近义词按整份列表保存，和笔记一样只增量写一条事件，不重建词库、搜索索引和题目目录。
    func updateSynonyms(for id: UUID, synonyms: [ConfusableWord]) throws {
        let value = PersonalSynonyms.normalize(synonyms)
        guard value != getStudyRecord(for: id).personalSynonyms else { return }
        let payload = try PersonalSynonyms.encode(value)
        guard append(StudyEvent(wordID: id, kind: "synonym", value: payload)) else {
            throw AppError.text(message.isEmpty ? "近义词未能保存，请重试。" : message)
        }
    }
    @discardableResult func setErrorCount(for id: UUID, count: Int) -> Bool {
        // Record the correction itself so manually editing a total never erases past questions.
        let delta = max(0, min(99999, count)) - getStudyRecord(for: id).errorCount
        return delta == 0 || append(StudyEvent(wordID: id, kind: "errorAdjustment", value: String(delta)))
    }
    func reviewed(_ id: UUID) { append(StudyEvent(wordID: id, kind: "review", value: "")) }
    @discardableResult func rate(_ id: UUID, rating: Int) -> Bool {
        guard (0...2).contains(rating) else { return false }
        return append(StudyEvent(wordID: id, kind: "rating", value: String(rating)))
    }
    @discardableResult func submitAnswer(questionId: UUID, selectedAnswer: Int) -> Bool {
        guard let q = questionsByID[questionId], q.options.indices.contains(selectedAnswer) else { return false }
        return append(StudyEvent(kind: "answer", value: String(selectedAnswer), questionID: questionId))
    }
    func practiceQuestions(type: String, category: String, errorsOnly: Bool, limit: Int, includeArchived: Bool = false) -> [Question] {
        let currentErrorWords = errorWords
        let weak = Set(currentErrorWords.map { $0.id })
        let eligible = Set(activeWords.filter { belongs($0, to: category) && (includeArchived || !$0.sourceDeleted) }.map { $0.id })
        let filtered = activeQuestions.filter { q in
            let linked = relatedWordIDs(for: q)
            return (type == "全部题型" || q.type.rawValue == type) && linked.contains(where: eligible.contains)
            && (!errorsOnly || linked.contains(where: weak.contains))
        }
        if errorsOnly {
            let weights = Dictionary(uniqueKeysWithValues: currentErrorWords.map { ($0.id, getStudyRecord(for: $0.id).errorCount) })
            return Array(filtered.shuffled().sorted {
                (relatedWordIDs(for: $0).map { weights[$0, default: 0] }.max() ?? 0) >
                (relatedWordIDs(for: $1).map { weights[$0, default: 0] }.max() ?? 0)
            }.prefix(limit))
        }
        return Array(filtered.shuffled().prefix(limit))
    }
    private func rebuild() throws {
        publish(try catalog(for: snapshot))
    }
    private func publish(_ catalog: PersonalCatalog) {
        words = catalog.words; questions = catalog.questions
        learningContext = LearningEngine.Context(words: words, questions: questions)
        activeQuestions = PersonalTransactions.practiceQuestions(catalog: catalog, context: learningContext)
        archivedWordIDs = catalog.archivedWordIDs; personalHeads = catalog.headsByEntryID
        contentConflictCount = catalog.conflictingEntryIDs.count + catalog.nameCollisions.count
        questionsByID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
        wordsByID = Dictionary(uniqueKeysWithValues: words.map { ($0.id, $0) })
        wordIDs = Set(words.map(\.id))
        eventIDs = Set(snapshot.events.map(\.id))
        noteImageValues = Dictionary(uniqueKeysWithValues: snapshot.events.compactMap { event in
            event.kind == "noteImage" ? (event.id, event.value) : nil
        })
        noteImageWordIDs = Dictionary(uniqueKeysWithValues: snapshot.events.compactMap { event in
            event.kind == "noteImage" ? event.wordID.map { (event.id, $0) } : nil
        })
        noteImageCache.removeAllObjects()
        activeQuestionsByWordID = [:]
        for question in activeQuestions {
            for id in learningContext.relatedWordIDs(for: question) {
                activeQuestionsByWordID[id, default: []].append(question)
            }
        }
        searchIndex = [:]
        for word in words {
            let text = ([word.word, word.pinyin, word.category, word.subcategory, word.keyPoints]
                + word.meanings + word.occurrences.map { $0.originalWord }
                + word.confusableWords.map { $0.word + $0.difference }).joined(separator: " ")
            searchIndex[word.id] = normalize(text)
        }
        let state = LearningEngine.reduce(words: words, questions: questions, events: snapshot.events)
        let viewState = LearningViewState(records: state.records, answers: state.answers,
            correctAnswerCount: state.answers.lazy.filter(\.isCorrect).count)
        refreshDailyMetricsIfNeeded(viewState)
        learningViewState = viewState
        invalidateErrorWordCache()
        lastEventTimestamp = snapshot.events.reduce(0) { max($0, $1.timestamp) }
    }
    func question(for event: StudyEvent) -> Question? { event.questionID.flatMap { questionsByID[$0] } }
    func question(for id: UUID) -> Question? { questionsByID[id] }
    func word(for id: UUID) -> Word? { wordsByID[id] }
    func activeWord(for id: UUID) -> Word? { archivedWordIDs.contains(id) ? nil : wordsByID[id] }
    private func decodeSnapshot(_ data: Data) throws -> StudySnapshot {
        try SnapshotCodec.decode(data: data, builtInWords: builtInWords, builtInQuestions: builtInQuestions)
    }
    func exportData() throws -> Data {
        guard persistenceAvailable else { throw AppError.text("记录尚未成功载入，不能导出空白备份覆盖你的有效备份。") }
        return try JSONEncoder().encode(snapshot)
    }
    func importData(_ data: Data) throws {
        let preview = try previewImport(data)
        guard preview.contentConflicts.isEmpty, preview.conflicts.isEmpty else { throw AppError.text("备份包含冲突，请在导入预览中选择要保留的内容。") }
        try commitImport(preview.merged, expected: preview.local)
    }
    func previewImport(_ data: Data) throws -> SyncMergePreview {
        let incoming = try decodeSnapshot(data)
        return try SyncMergeEngine.preview(local: snapshot, incoming: incoming, words: builtInWords, questions: builtInQuestions)
    }
    func validatedSnapshot(_ data: Data) throws -> StudySnapshot { try decodeSnapshot(data) }
    func encodedSnapshot(_ value: StudySnapshot) throws -> Data {
        let data = try JSONEncoder().encode(value)
        _ = try decodeSnapshot(data)
        return data
    }
    func commitImport(_ proposed: StudySnapshot, expected: StudySnapshot) throws {
        try save(proposed, expected: expected, requireResolvedContent: true, recovering: true)
    }
    func catalog(for value: StudySnapshot) throws -> PersonalCatalog {
        try SnapshotCodec.validate(snapshot: value, builtInWords: builtInWords, builtInQuestions: builtInQuestions)
    }
    func validateProposal(_ proposed: StudySnapshot, expected: StudySnapshot) throws {
        try SyncMergeEngine.validateCommit(current: snapshot, expected: expected, proposed: proposed)
        try SyncMergeEngine.validateProposal(proposed, words: builtInWords, questions: builtInQuestions)
    }
    func resolveContent(_ preview: SyncMergePreview, choices: [String: UUID]) throws -> SyncMergePreview {
        try SyncMergeEngine.validateCommit(current: snapshot, expected: preview.local, proposed: preview.merged)
        return try SyncMergeEngine.resolveContent(preview: preview, choices: choices, words: builtInWords, questions: builtInQuestions)
    }
    private func save(_ proposed: StudySnapshot, expected: StudySnapshot, requireResolvedContent: Bool, recovering: Bool = false) throws {
        guard persistenceAvailable || recovering else { throw AppError.text("记录未能载入，写入已暂停。请在“我的”导入有效备份后重试。") }
        guard let store = store else { throw AppError.text("词库或存储目录未能载入，无法安全保存。") }
        try SyncMergeEngine.validateCommit(current: snapshot, expected: expected, proposed: proposed)
        let catalog: PersonalCatalog
        if requireResolvedContent {
            catalog = try SyncMergeEngine.validateProposal(proposed, words: builtInWords, questions: builtInQuestions)
        } else { catalog = try self.catalog(for: proposed) }
        // The proposal was fully checked above; reuse the validated in-memory/disk prefix when safe.
        try store.saveValidated(proposed)
        snapshot = proposed; persistenceAvailable = true
        publish(catalog); snapshotDidChange.send(); scheduleReminderRefresh()
    }
    func expectedHeads(for entryID: UUID) -> Set<UUID> { Set((personalHeads[entryID] ?? []).map(\.id)) }
    func currentRevision(for entryID: UUID) -> PersonalRevision? { personalHeads[entryID]?.last }
    func relatedWordIDs(for question: Question) -> [UUID] {
        learningContext.relatedWordIDs(for: question)
    }
    func relatedQuestions(for wordID: UUID) -> [Question] { activeQuestionsByWordID[wordID] ?? [] }
    func matchingWords(_ name: String, excluding entryID: UUID? = nil) -> [Word] {
        let key = PersonalLibrary.normalizedName(name)
        return activeWords.filter { $0.id != entryID && PersonalLibrary.normalizedName($0.word) == key }
    }
    @discardableResult func savePersonalWord(content: PersonalWordContent, wordID: UUID,
                                             expectedHeads: Set<UUID>, notes: String?) throws -> UUID {
        let proposed = try PersonalTransactions.word(snapshot: snapshot, builtInWords: builtInWords, builtInQuestions: builtInQuestions,
            content: content, entryID: wordID, expectedHeads: expectedHeads, notes: notes)
        try save(proposed, expected: snapshot, requireResolvedContent: true)
        return wordID
    }
    @discardableResult func savePersonalQuestion(content: PersonalQuestionContent, entryID: UUID,
                                                 expectedHeads: Set<UUID>) throws -> UUID {
        let proposed = try PersonalTransactions.question(snapshot: snapshot, builtInWords: builtInWords, builtInQuestions: builtInQuestions,
            content: content, entryID: entryID, expectedHeads: expectedHeads)
        try save(proposed, expected: snapshot, requireResolvedContent: true)
        return entryID
    }
    func setPersonalArchived(entryID: UUID, expectedHeads: Set<UUID>, archived: Bool) throws {
        let proposed = try PersonalTransactions.archive(snapshot: snapshot, builtInWords: builtInWords, builtInQuestions: builtInQuestions,
            entryID: entryID, expectedHeads: expectedHeads, archived: archived)
        try save(proposed, expected: snapshot, requireResolvedContent: true)
    }

    // Local notifications: errors first, then new words. No network or push service.
    func configureReminder(enabled: Bool, hour: Int, minute: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        if enabled {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                guard granted else { message = "通知尚未允许，请到 iPhone 设置中为本 App 开启通知。"; return false }
            } catch { message = error.localizedDescription; return false }
        }
        UserDefaults.standard.set(enabled, forKey: "reminderEnabled")
        UserDefaults.standard.set(hour, forKey: "reminderHour")
        UserDefaults.standard.set(minute, forKey: "reminderMinute")
        refreshReminder()
        message = enabled ? String(format: "已设置每天 %02d:%02d 巩固提醒", hour, minute) : "已关闭复习提醒"
        return true
    }
    func refreshReminder() {
        reminderRefreshWorkItem?.cancel(); reminderRefreshWorkItem = nil
        let center = UNUserNotificationCenter.current()
        let ids = (0..<31).map { "words800.day.\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids + ["words800.daily"])
        guard UserDefaults.standard.bool(forKey: "reminderEnabled") else { return }
        let weak = errorWords.filter { !$0.sourceDeleted && getStudyRecord(for: $0.id).masteryLevel != .mastered }
        let fresh = newWords
        let weakIDs = Set(weak.map(\.id))
        let candidates = weak + fresh.filter { !weakIDs.contains($0.id) }
        let hour = (UserDefaults.standard.object(forKey: "reminderHour") as? Int) ?? 20
        let minute = UserDefaults.standard.integer(forKey: "reminderMinute")
        let calendar = Calendar.current
        guard let next = calendar.nextDate(after: Date(), matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime) else { return }
        // Seven weekday schedules repeat indefinitely; learning refreshes their selected words.
        for day in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: day, to: next) else { continue }
            let content = UNMutableNotificationContent()
            var picks: [Word] = []
            if !weak.isEmpty { picks.append(weak[day % weak.count]) }
            if !fresh.isEmpty {
                let word = fresh[day % fresh.count]
                if !picks.contains(where: { $0.id == word.id }) { picks.append(word) }
            }
            if picks.isEmpty && !candidates.isEmpty { picks = [candidates[day % candidates.count]] }
            content.title = "政名政利公考 · 巩固时间"
            content.body = picks.isEmpty ? "复习已掌握的词，再完成一组练习。" : picks.map { w in
                let count = getStudyRecord(for: w.id).errorCount
                return "\(w.word)（\(count > 0 ? "错\(count)次" : "生词")）：\(String(w.meanings.first?.prefix(42) ?? ""))"
            }.joined(separator: "\n")
            content.sound = .default
            content.userInfo = ["destination": "review", "wordIDs": picks.map { $0.id.uuidString }]
            let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.weekday, .hour, .minute], from: date), repeats: true)
            center.add(UNNotificationRequest(identifier: ids[day], content: content, trigger: trigger)) { error in
                if let error = error { Task { @MainActor in self.message = "提醒设置失败：\(error.localizedDescription)" } }
            }
        }
    }
    func scheduleReminderRefresh(after delay: TimeInterval = 8) {
        reminderRefreshWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshReminder() }
        reminderRefreshWorkItem = work
        // Notifications do not need to be rebuilt between every word in a fast study run.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func migrateLegacy() throws {
        // Preserve old defaults and raw backup even for the sample words absent from the real source.
        let old = UserDefaults.standard
        let keys = ["saved_words", "saved_questions", "saved_study_records", "saved_question_records"]
        let archive = keys.reduce(into: [String: String]()) { result, key in
            if let data = old.data(forKey: key) { result[key] = data.base64EncodedString() }
        }
        if !archive.isEmpty {
            try JSONEncoder().encode(archive).write(to: directory.appendingPathComponent("legacy-backup.json"), options: .atomic)
        }
        guard let wordData = old.data(forKey: "saved_words"),
              let oldWords = try JSONSerialization.jsonObject(with: wordData) as? [[String: Any]],
              let recordData = old.data(forKey: "saved_study_records"),
              let raw = try JSONSerialization.jsonObject(with: recordData) as? [Any] else { return }
        let oldNames = Dictionary(uniqueKeysWithValues: oldWords.compactMap { w -> (String, String)? in
            guard let id = w["id"] as? String, let name = w["word"] as? String else { return nil }
            return (id.uppercased(), name)
        })
        var proposed = StudySnapshot()
        if raw.count >= 2 {
            for i in stride(from: 0, to: raw.count - 1, by: 2) {
                guard let oldID = raw[i] as? String, let r = raw[i + 1] as? [String: Any],
                      let name = oldNames[oldID.uppercased()], let w = words.first(where: { $0.word == name }) else { continue }
                let stamp = (((r["lastStudyDate"] as? Double) ?? Date().timeIntervalSinceReferenceDate) + 978307200) * 1000
                for (index, pair) in [("favorite", "isFavorite"), ("mastery", "masteryLevel"), ("note", "personalNotes"), ("errorAdjustment", "errorCount")].enumerated() {
                    let (kind, key) = pair
                    let value: String
                    if kind == "favorite" { value = ((r[key] as? Bool) ?? false) ? "true" : "false" }
                    else if kind == "errorAdjustment" { value = String((r[key] as? Int) ?? 0) }
                    else { value = (r[key] as? String) ?? (kind == "mastery" ? "未学习" : "") }
                    proposed.events.append(StudyEvent(wordID: w.id, kind: kind, value: value, timestamp: stamp + Double(index)))
                }
            }
        }
        guard let store = store else { throw AppError.text("存储目录尚未准备好。") }
        try store.save(proposed)
        snapshot = proposed
    }
}
