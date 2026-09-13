import Foundation
import Combine
import UserNotifications
import CryptoKit

@MainActor final class DataManager: ObservableObject {
    static let shared = DataManager()
    @Published private(set) var words: [Word] = []
    @Published private(set) var questions: [Question] = []
    @Published private(set) var activeQuestions: [Question] = []
    @Published private(set) var archivedWordIDs: Set<UUID> = []
    @Published private(set) var personalHeads: [UUID: [PersonalRevision]] = [:]
    @Published private(set) var contentConflictCount = 0
    @Published private(set) var snapshotGeneration = 0
    @Published private(set) var studyRecords: [UUID: StudyRecord] = [:]
    @Published private(set) var questionRecords: [QuestionRecord] = []
    @Published var message = ""
    private var snapshot = StudySnapshot()
    private var searchIndex: [UUID: String] = [:]
    private var questionsByID: [UUID: Question] = [:]
    private(set) var libraryFingerprint = ""
    private let directory: URL
    private var builtInWords: [Word] = []
    private var builtInQuestions: [Question] = []
    private var store: SnapshotStore?
    private var persistenceAvailable = true

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
    var errorWords: [Word] { sorted(activeWords.filter { getStudyRecord(for: $0.id).errorCount > 0 }, by: .errors) }
    var favoriteWords: [Word] { words.filter { getStudyRecord(for: $0.id).isFavorite } }
    var newWords: [Word] { activeWords.filter { !($0.sourceDeleted) && getStudyRecord(for: $0.id).masteryLevel == .unknown } }
    var dueWords: [Word] {
        sorted(activeWords.filter { word in
            let r = getStudyRecord(for: word.id)
            guard r.lastStudyDate != .distantPast else { return false }
            return r.nextReviewDate <= Date()
        }, by: .errors)
    }
    var accuracy: Int { questionRecords.isEmpty ? 0 : Int(100 * Double(questionRecords.filter { $0.isCorrect }.count) / Double(questionRecords.count)) }
    var todayCount: Int { questionRecords.filter { Calendar.current.isDateInToday($0.answeredAt) }.count }
    var todayLearnedCount: Int {
        Set(snapshot.events.filter { $0.kind == "rating" && Calendar.current.isDateInToday($0.date) }.compactMap { $0.wordID }).count
    }
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
        var proposed = snapshot
        // Preserve local action order even when two actions share a clock tick.
        let stamp = max(event.timestamp, (snapshot.events.map { $0.timestamp }.max() ?? 0) + 0.001)
        proposed.events.append(StudyEvent(id: event.id, wordID: event.wordID, kind: event.kind,
            value: event.value, timestamp: stamp, questionID: event.questionID))
        do { try save(proposed, expected: snapshot, requireResolvedContent: false); return true }
        catch { message = "保存失败：\(error.localizedDescription)"; return false }
    }
    func toggleFavorite(for id: UUID) {
        append(StudyEvent(wordID: id, kind: "favorite", value: getStudyRecord(for: id).isFavorite ? "false" : "true"))
    }
    func updateMasteryLevel(for id: UUID, level: MasteryLevel) { append(StudyEvent(wordID: id, kind: "mastery", value: level.rawValue)) }
    @discardableResult func updateNotes(for id: UUID, notes: String) -> Bool {
        guard notes != getStudyRecord(for: id).personalNotes else { return true }
        return append(StudyEvent(wordID: id, kind: "note", value: notes))
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
        let weak = Set(errorWords.map { $0.id })
        let eligible = Set(activeWords.filter { belongs($0, to: category) && (includeArchived || !$0.sourceDeleted) }.map { $0.id })
        let filtered = activeQuestions.filter { q in
            let linked = relatedWordIDs(for: q)
            return (type == "全部题型" || q.type.rawValue == type) && linked.contains(where: eligible.contains)
            && (!errorsOnly || linked.contains(where: weak.contains))
        }
        if errorsOnly {
            let weights = Dictionary(uniqueKeysWithValues: errorWords.map { ($0.id, getStudyRecord(for: $0.id).errorCount) })
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
        activeQuestions = PersonalTransactions.practiceQuestions(catalog: catalog)
        archivedWordIDs = catalog.archivedWordIDs; personalHeads = catalog.headsByEntryID
        contentConflictCount = catalog.conflictingEntryIDs.count + catalog.nameCollisions.count
        questionsByID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
        searchIndex = [:]
        for word in words {
            let text = ([word.word, word.pinyin, word.category, word.subcategory, word.keyPoints]
                + word.meanings + word.occurrences.map { $0.originalWord }
                + word.confusableWords.map { $0.word + $0.difference }).joined(separator: " ")
            searchIndex[word.id] = normalize(text)
        }
        let state = LearningEngine.reduce(words: words, questions: questions, events: snapshot.events)
        studyRecords = state.records; questionRecords = state.answers
    }
    func question(for event: StudyEvent) -> Question? { event.questionID.flatMap { questionsByID[$0] } }
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
        try store.save(proposed)
        snapshot = proposed; persistenceAvailable = true
        publish(catalog); snapshotGeneration += 1; refreshReminder()
    }
    func expectedHeads(for entryID: UUID) -> Set<UUID> { Set((personalHeads[entryID] ?? []).map(\.id)) }
    func currentRevision(for entryID: UUID) -> PersonalRevision? { personalHeads[entryID]?.last }
    func relatedWordIDs(for question: Question) -> [UUID] {
        LearningEngine.relatedWordIDs(for: question, words: builtInWords)
    }
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
        let center = UNUserNotificationCenter.current()
        let ids = (0..<31).map { "words800.day.\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids + ["words800.daily"])
        guard UserDefaults.standard.bool(forKey: "reminderEnabled") else { return }
        let weak = errorWords.filter { !$0.sourceDeleted && getStudyRecord(for: $0.id).masteryLevel != .mastered }
        let fresh = newWords
        let candidates = weak + fresh.filter { w in !weak.contains(where: { $0.id == w.id }) }
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
