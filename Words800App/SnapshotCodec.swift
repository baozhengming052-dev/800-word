import Foundation

enum SnapshotCodec {
    static let maximumBytes = 20_000_000
    static let maximumRecords = 100_000

    static func decode(data: Data, builtInWords: [Word], builtInQuestions: [Question],
                       now: Double = Date().timeIntervalSince1970 * 1000) throws -> StudySnapshot {
        guard data.count <= maximumBytes else { throw PersonalLibraryError.invalid("备份文件过大。") }
        var snapshot = try JSONDecoder().decode(StudySnapshot.self, from: data)
        _ = try validate(snapshot: snapshot, builtInWords: builtInWords, builtInQuestions: builtInQuestions, now: now)
        snapshot.schemaVersion = 3
        return snapshot
    }

    @discardableResult
    static func validate(snapshot: StudySnapshot, builtInWords: [Word], builtInQuestions: [Question],
                         now: Double = Date().timeIntervalSince1970 * 1000) throws -> PersonalCatalog {
        guard [2, 3].contains(snapshot.schemaVersion), snapshot.schemaVersion != 2 || snapshot.revisions.isEmpty,
              snapshot.events.count <= maximumRecords - snapshot.revisions.count else {
            throw PersonalLibraryError.invalid("不支持的备份版本或记录数量。")
        }
        guard try JSONEncoder().encode(snapshot).count <= maximumBytes else { throw PersonalLibraryError.invalid("备份文件过大。") }
        let catalog = try PersonalLibrary.build(builtInWords: builtInWords, builtInQuestions: builtInQuestions, snapshot: snapshot, now: now)
        let wordIDs = Set(catalog.words.map { $0.id })
        var questionByID: [UUID: Question] = [:]
        for question in catalog.questions {
            guard questionByID.updateValue(question, forKey: question.id) == nil else { throw PersonalLibraryError.invalid("题目编号重复。") }
        }
        let kinds = Set(["answer", "favorite", "mastery", "note", "synonym", "errorAdjustment", "review", "rating"])
        var seen = Set<UUID>()
        for event in snapshot.events {
            guard seen.insert(event.id).inserted, kinds.contains(event.kind), event.timestamp.isFinite,
                  event.timestamp >= 0, event.timestamp <= now + 86_400_000, event.value.utf8.count <= 100_000 else {
                throw PersonalLibraryError.invalid("备份中有无效或重复记录。")
            }
            // Validate optional references as well as the reference required by each event kind.
            if let id = event.wordID, !wordIDs.contains(id) { throw PersonalLibraryError.invalid("学习记录关联的词条不存在。") }
            if let id = event.questionID, questionByID[id] == nil { throw PersonalLibraryError.invalid("学习记录关联的题目版本不存在。") }
            if event.kind == "answer" {
                guard let id = event.questionID, let question = questionByID[id], let answer = Int(event.value),
                      question.options.indices.contains(answer) else { throw PersonalLibraryError.invalid("无效的答题记录。") }
            } else if event.wordID == nil { throw PersonalLibraryError.invalid("学习记录缺少词条编号。") }
            switch event.kind {
            case "errorAdjustment":
                guard let n = Int(event.value), (-99999...99999).contains(n) else { throw PersonalLibraryError.invalid("无效的错误次数调整。") }
            case "favorite":
                guard ["true", "false"].contains(event.value) else { throw PersonalLibraryError.invalid("无效的收藏记录。") }
            case "mastery":
                guard MasteryLevel(rawValue: event.value) != nil else { throw PersonalLibraryError.invalid("无效的掌握程度。") }
            case "rating":
                guard ["0", "1", "2"].contains(event.value) else { throw PersonalLibraryError.invalid("无效的学习反馈。") }
            case "synonym":
                guard PersonalSynonyms.isValid(event.value) else { throw PersonalLibraryError.invalid("无效的近义词补充记录。") }
            default: break
            }
        }
        return catalog
    }
}
