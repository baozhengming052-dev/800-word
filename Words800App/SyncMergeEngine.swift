import Foundation

enum SyncError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

struct SyncConflict: Identifiable {
    enum Kind { case note, errorCount, synonym }
    let wordID: UUID
    let word: String
    let kind: Kind
    /// 记录里的原始载荷；近义词是规范 JSON，界面用下面的显示属性转成可读文字。
    let localValue: String
    let incomingValue: String
    let mergedValue: String
    var id: String {
        switch kind {
        case .note: return wordID.uuidString + ".note"
        case .errorCount: return wordID.uuidString + ".errors"
        case .synonym: return wordID.uuidString + ".synonym"
        }
    }
    var title: String {
        switch kind {
        case .note: return "笔记"
        case .errorCount: return "错误次数"
        case .synonym: return "近义词"
        }
    }
    var localDisplay: String { display(localValue) }
    var incomingDisplay: String { display(incomingValue) }
    private func display(_ value: String) -> String {
        kind == .synonym ? PersonalSynonyms.displayText(value) : value
    }
}

enum SyncChoice: String, CaseIterable { case local, incoming, combined }

struct SyncContentOption: Identifiable {
    /// Revision UUID for a branch choice; stable word UUID for a name choice.
    let id: UUID
    let entryID: UUID
    let revision: PersonalRevision?
    let builtInWord: Word?
    let isSelectable: Bool
}

struct SyncContentConflict: Identifiable {
    enum Kind { case revision, nameCollision }
    let id: String
    let kind: Kind
    let entryID: UUID?
    let normalizedName: String?
    let options: [SyncContentOption]
}

struct SyncContentChangeCounts {
    var addedWords = 0
    var editedWords = 0
    var archivedWords = 0
    var addedQuestions = 0
    var editedQuestions = 0
    var archivedQuestions = 0
    var total: Int { addedWords + editedWords + archivedWords + addedQuestions + editedQuestions + archivedQuestions }
}

struct SyncContentChangeSummary {
    /// Entries whose head set changes on the local / incoming device, respectively.
    let incoming: SyncContentChangeCounts
    let outgoing: SyncContentChangeCounts
}

struct SyncMergePreview: Identifiable {
    let id = UUID()
    let local: StudySnapshot
    let incoming: StudySnapshot
    let merged: StudySnapshot
    let conflicts: [SyncConflict]
    let contentConflicts: [SyncContentConflict]
    let contentChanges: SyncContentChangeSummary
    // Capture the original bundled directory so final learning resolution can validate itself.
    fileprivate let builtInWords: [Word]
    fileprivate let builtInQuestions: [Question]
    var incomingCount: Int { merged.events.count - local.events.count }
    var outgoingCount: Int { merged.events.count - incoming.events.count }
}

// Same reducer and same event IDs as offline learning. Totals are never added together.
enum SyncMergeEngine {
    // Swift String/Equatable treats canonically equivalent Unicode as equal. Immutable
    // payload identity instead preserves each string's encoded bytes and every array's order.
    // Sorted object keys remove irrelevant encoder key ordering, not content distinctions.
    private static func immutableEqual<Record: Encodable>(_ lhs: Record, _ rhs: Record) throws -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(lhs) == encoder.encode(rhs)
    }

    private static func containsUnchanged<Record: Encodable>(_ records: [UUID: Record], in candidate: [UUID: Record]) throws -> Bool {
        for (id, record) in records {
            guard let existing = candidate[id], try immutableEqual(record, existing) else { return false }
        }
        return true
    }

    static func eventMap(_ snapshot: StudySnapshot) throws -> [UUID: StudyEvent] {
        guard [2, 3].contains(snapshot.schemaVersion), snapshot.schemaVersion != 2 || snapshot.revisions.isEmpty,
              snapshot.events.count <= SnapshotCodec.maximumRecords - snapshot.revisions.count,
              try JSONEncoder().encode(snapshot).count <= SnapshotCodec.maximumBytes else {
            throw SyncError.invalid("记录版本不支持或数量超限，请让两台设备安装同一新版 App。")
        }
        var result: [UUID: StudyEvent] = [:]
        for event in snapshot.events {
            guard result.updateValue(event, forKey: event.id) == nil else {
                throw SyncError.invalid("备份中存在重复的记录编号，已停止合并。")
            }
        }
        return result
    }

    private static func revisionMap(_ snapshot: StudySnapshot) throws -> [UUID: PersonalRevision] {
        var result: [UUID: PersonalRevision] = [:]
        for revision in snapshot.revisions {
            guard result.updateValue(revision, forKey: revision.id) == nil else {
                throw SyncError.invalid("备份中存在重复的内容修订编号，已停止合并。")
            }
        }
        return result
    }

    static func preview(local: StudySnapshot, incoming: StudySnapshot, words: [Word], questions: [Question]) throws -> SyncMergePreview {
        let now = Date().timeIntervalSince1970 * 1000
        try SnapshotCodec.validate(snapshot: local, builtInWords: words, builtInQuestions: questions, now: now)
        try SnapshotCodec.validate(snapshot: incoming, builtInWords: words, builtInQuestions: questions, now: now)
        let left = try eventMap(local), right = try eventMap(incoming)
        var union = left
        for (id, event) in right {
            if let existing = union[id] {
                guard try immutableEqual(existing, event) else { throw SyncError.invalid("同一条记录内容不一致，已停止合并。") }
            } else { union[id] = event }
        }
        var revisions = try revisionMap(local)
        for (id, revision) in try revisionMap(incoming) {
            if let existing = revisions[id] {
                guard try immutableEqual(existing, revision) else { throw SyncError.invalid("同一内容修订编号的载荷不一致，已停止合并。") }
            } else { revisions[id] = revision }
        }
        let merged = StudySnapshot(events: ordered(Array(union.values)), revisions: Array(revisions.values).sorted(by: PersonalLibrary.revisionOrder))
        return try makePreview(local: local, incoming: incoming, merged: merged, words: words, questions: questions, now: now)
    }

    private static func makePreview(local: StudySnapshot, incoming: StudySnapshot, merged: StudySnapshot,
                                    words: [Word], questions: [Question], now: Double) throws -> SyncMergePreview {
        let catalog = try SnapshotCodec.validate(snapshot: merged, builtInWords: words, builtInQuestions: questions, now: now)
        let localCatalog = try PersonalLibrary.build(builtInWords: words, builtInQuestions: questions, snapshot: local, now: now)
        let incomingCatalog = try PersonalLibrary.build(builtInWords: words, builtInQuestions: questions, snapshot: incoming, now: now)
        let content = contentConflicts(catalog: catalog, builtInWords: words)
        let summary = SyncContentChangeSummary(incoming: changes(from: localCatalog, to: catalog), outgoing: changes(from: incomingCatalog, to: catalog))
        // Do not ask for learning choices against a provisional content projection.
        let conflicts = content.isEmpty ? learningConflicts(local: local, incoming: incoming, merged: merged, catalog: catalog) : []
        return SyncMergePreview(local: local, incoming: incoming, merged: merged, conflicts: conflicts,
            contentConflicts: content, contentChanges: summary, builtInWords: words, builtInQuestions: questions)
    }

    private static func contentConflicts(catalog: PersonalCatalog, builtInWords: [Word]) -> [SyncContentConflict] {
        let branches = catalog.headsByEntryID.filter { $0.value.count > 1 }.sorted { $0.key.uuidString < $1.key.uuidString }.map { id, heads in
            SyncContentConflict(id: "revision." + id.uuidString, kind: .revision, entryID: id, normalizedName: nil,
                options: heads.map { SyncContentOption(id: $0.id, entryID: id, revision: $0, builtInWord: nil, isSelectable: true) })
        }
        // A branch choice can rename/archive an entry. Resolve those choices before presenting name collisions.
        if !branches.isEmpty { return branches }
        var builtIns: [UUID: Word] = [:]
        for word in builtInWords { builtIns[word.id] = word }
        return catalog.nameCollisions.map { collision in
            let hasBuiltIn = collision.wordIDs.contains { builtIns[$0] != nil }
            let options = collision.wordIDs.map { id in
                SyncContentOption(id: id, entryID: id, revision: catalog.headsByEntryID[id]?.first,
                    builtInWord: builtIns[id], isSelectable: !hasBuiltIn || builtIns[id] != nil)
            }
            return SyncContentConflict(id: "name." + collision.normalizedName, kind: .nameCollision, entryID: nil,
                normalizedName: collision.normalizedName, options: options)
        }
    }

    private static func changes(from baseline: PersonalCatalog, to merged: PersonalCatalog) -> SyncContentChangeCounts {
        var result = SyncContentChangeCounts()
        for (id, heads) in merged.headsByEntryID {
            let previous = baseline.headsByEntryID[id] ?? []
            guard Set(previous.map { $0.id }) != Set(heads.map { $0.id }) else { continue }
            let isWord = heads[0].word != nil
            // Categories are disjoint. Newly discovered archived entries still count as additions.
            if previous.isEmpty {
                if isWord { result.addedWords += 1 } else { result.addedQuestions += 1 }
            } else if heads.allSatisfy({ $0.archived }) {
                if isWord { result.archivedWords += 1 } else { result.archivedQuestions += 1 }
            } else {
                if isWord { result.editedWords += 1 } else { result.editedQuestions += 1 }
            }
        }
        return result
    }

    private static func learningConflicts(local: StudySnapshot, incoming: StudySnapshot, merged: StudySnapshot,
                                         catalog: PersonalCatalog) -> [SyncConflict] {
        let left = Set(local.events.map { $0.id }), right = Set(incoming.events.map { $0.id })
        let localOnly = local.events.filter { !right.contains($0.id) }
        let remoteOnly = incoming.events.filter { !left.contains($0.id) }
        let words = catalog.words, questions = catalog.questions
        let localState = LearningEngine.reduce(words: words, questions: questions, events: local.events).records
        let remoteState = LearningEngine.reduce(words: words, questions: questions, events: incoming.events).records
        let mergedState = LearningEngine.reduce(words: words, questions: questions, events: merged.events).records
        let qByID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
        let learningContext = LearningEngine.Context(words: words, questions: questions)
        var linksByQuestionID: [UUID: [UUID]] = [:]
        func edits(_ events: [StudyEvent]) -> (notes: Set<UUID>, manual: Set<UUID>, errors: Set<UUID>, synonyms: Set<UUID>) {
            var notes = Set<UUID>(), manual = Set<UUID>(), errors = Set<UUID>(), synonyms = Set<UUID>()
            for event in events {
                if let id = event.wordID {
                    if event.kind == "note" { notes.insert(id) }
                    if event.kind == "synonym" { synonyms.insert(id) }
                    if event.kind == "errorAdjustment" { manual.insert(id); errors.insert(id) }
                    if event.kind == "rating" && event.value == "0" { errors.insert(id) }
                }
                if event.kind == "answer", let qid = event.questionID, let q = qByID[qid], Int(event.value) != q.correctAnswer {
                    if linksByQuestionID[qid] == nil {
                        // UUID-linked personal questions need no spelling lookup. Cache bundled lookups per revision.
                        linksByQuestionID[qid] = learningContext.relatedWordIDs(for: q)
                    }
                    errors.formUnion(linksByQuestionID[qid] ?? [])
                }
            }
            return (notes, manual, errors, synonyms)
        }
        let a = edits(localOnly), b = edits(remoteOnly)
        var conflicts: [SyncConflict] = []
        for word in words {
            let id = word.id, l = localState[id] ?? StudyRecord(), r = remoteState[id] ?? StudyRecord()
            let m = mergedState[id] ?? StudyRecord()
            if a.notes.contains(id) && b.notes.contains(id) && l.personalNotes != r.personalNotes {
                conflicts.append(SyncConflict(wordID: id, word: word.word, kind: .note,
                    localValue: l.personalNotes, incomingValue: r.personalNotes, mergedValue: m.personalNotes))
            }
            // A reset and an unseen wrong answer also conflict, even if device totals happen to match.
            if (a.manual.contains(id) && b.errors.contains(id)) || (b.manual.contains(id) && a.errors.contains(id)) {
                conflicts.append(SyncConflict(wordID: id, word: word.word, kind: .errorCount,
                    localValue: String(l.errorCount), incomingValue: String(r.errorCount), mergedValue: String(m.errorCount)))
            }
            // 两台各自补充了不同的近义词：必须选一份或合并，不能按时钟静默丢掉一边。
            if a.synonyms.contains(id) && b.synonyms.contains(id), l.personalSynonyms != r.personalSynonyms {
                conflicts.append(SyncConflict(wordID: id, word: word.word, kind: .synonym,
                    localValue: (try? PersonalSynonyms.encode(l.personalSynonyms)) ?? "[]",
                    incomingValue: (try? PersonalSynonyms.encode(r.personalSynonyms)) ?? "[]",
                    mergedValue: (try? PersonalSynonyms.encode(m.personalSynonyms)) ?? "[]"))
            }
        }
        return conflicts
    }

    /// Choices map conflict.id to option.id. New name conflicts may require another call.
    static func resolveContent(preview: SyncMergePreview, choices: [String: UUID], words: [Word], questions: [Question],
                               now: Double = Date().timeIntervalSince1970 * 1000) throws -> SyncMergePreview {
        let catalog = try SnapshotCodec.validate(snapshot: preview.merged, builtInWords: words, builtInQuestions: questions, now: now)
        let conflicts = contentConflicts(catalog: catalog, builtInWords: words)
        guard Set(choices.keys) == Set(conflicts.map { $0.id }) else { throw SyncError.invalid("请先处理当前全部内容冲突，再继续。") }
        var result = preview.merged
        for conflict in conflicts {
            guard let chosenID = choices[conflict.id], let selected = conflict.options.first(where: { $0.id == chosenID }), selected.isSelectable else {
                throw SyncError.invalid("内容选择已失效，或不能用个人词条替换内置词条。")
            }
            if conflict.kind == .revision {
                guard let chosen = selected.revision else { throw SyncError.invalid("内容修订不存在。") }
                let parents = (catalog.headsByEntryID[chosen.entryID] ?? []).map { $0.id }.sorted { $0.uuidString < $1.uuidString }
                result.revisions.append(PersonalRevision(entryID: chosen.entryID, parents: parents, timestamp: now,
                    word: chosen.word.map { PersonalLibrary.normalize($0) }, question: chosen.question.map { PersonalLibrary.normalize($0) }, archived: chosen.archived))
            } else {
                // Record the keep-active decision too: opposite offline resolutions must become
                // active/archive siblings, rather than silently archiving both words on the next union.
                for option in conflict.options where option.builtInWord == nil {
                    guard let head = option.revision else { throw SyncError.invalid("重名词条的当前版本不存在。") }
                    let parents = (catalog.headsByEntryID[head.entryID] ?? []).map { $0.id }.sorted { $0.uuidString < $1.uuidString }
                    result.revisions.append(PersonalRevision(entryID: head.entryID, parents: parents, timestamp: now,
                        word: head.word.map { PersonalLibrary.normalize($0) }, archived: option.id != chosenID))
                }
            }
        }
        result.revisions.sort(by: PersonalLibrary.revisionOrder)
        return try makePreview(local: preview.local, incoming: preview.incoming, merged: result, words: words, questions: questions, now: now)
    }

    static func resolve(_ preview: SyncMergePreview, choices: [String: SyncChoice], now: Double = Date().timeIntervalSince1970 * 1000) throws -> StudySnapshot {
        guard preview.contentConflicts.isEmpty else { throw SyncError.invalid("请先处理词条和题目的内容冲突，再处理学习记录。") }
        var result = preview.merged
        var stamp = max(now, (result.events.map { $0.timestamp }.max() ?? 0) + 1)
        for conflict in preview.conflicts {
            guard let choice = choices[conflict.id] else { throw SyncError.invalid("请先处理所有冲突，再确认合并。") }
            // 近义词以整份列表保存，选择后写入一条新事件；旧内容仍留在修改历史里。
            if conflict.kind == .synonym {
                let local = PersonalSynonyms.decode(conflict.localValue)
                let incoming = PersonalSynonyms.decode(conflict.incomingValue)
                let chosen: [ConfusableWord]
                switch choice {
                case .local: chosen = local
                case .incoming: chosen = incoming
                case .combined: chosen = PersonalSynonyms.merged(local, incoming)
                }
                result.events.append(StudyEvent(wordID: conflict.wordID, kind: "synonym",
                    value: try PersonalSynonyms.encode(chosen), timestamp: stamp))
                stamp += 1
                continue
            }
            let value: String
            switch choice {
            case .local: value = conflict.localValue
            case .incoming: value = conflict.incomingValue
            case .combined:
                guard conflict.kind == .note else { throw SyncError.invalid("错误次数不能直接相加，请选择最终总数。") }
                value = [conflict.localValue, conflict.incomingValue].filter { !$0.isEmpty }.joined(separator: "\n\n")
            }
            if conflict.kind == .note {
                guard value.utf8.count <= 100000 else { throw SyncError.invalid("合并后的笔记过长，请选择其中一份，另一份仍保留在历史中。") }
                result.events.append(StudyEvent(wordID: conflict.wordID, kind: "note", value: value, timestamp: stamp))
                stamp += 1
            } else {
                guard let target = Int(value), let existing = Int(conflict.mergedValue) else { throw SyncError.invalid("无效的错误次数。") }
                var delta = target - existing
                // Each immutable adjustment retains the established bounded event format.
                while delta != 0 {
                    let part = max(-99999, min(99999, delta))
                    result.events.append(StudyEvent(wordID: conflict.wordID, kind: "errorAdjustment", value: String(part), timestamp: stamp))
                    stamp += 1; delta -= part
                }
            }
        }
        try validateProposal(result, words: preview.builtInWords, questions: preview.builtInQuestions, now: now)
        return result
    }

    /// Final proposals require stronger semantic guarantees than an importable conflict-bearing snapshot.
    @discardableResult
    static func validateProposal(_ proposed: StudySnapshot, words: [Word], questions: [Question],
                                 now: Double = Date().timeIntervalSince1970 * 1000) throws -> PersonalCatalog {
        guard proposed.schemaVersion == 3 else { throw SyncError.invalid("合并结果必须使用新版个人内容格式，请更新两台设备的 App。") }
        let catalog = try SnapshotCodec.validate(snapshot: proposed, builtInWords: words, builtInQuestions: questions, now: now)
        guard catalog.conflictingEntryIDs.isEmpty, catalog.nameCollisions.isEmpty else { throw SyncError.invalid("仍有未处理的个人内容冲突。") }
        return catalog
    }

    /// Pair with validateProposal against the original bundled directory before any disk write.
    static func validateCommit(current: StudySnapshot, expected: StudySnapshot, proposed: StudySnapshot) throws {
        let currentMap = try eventMap(current), expectedMap = try eventMap(expected), proposedMap = try eventMap(proposed)
        let currentRevisions = try revisionMap(current), expectedRevisions = try revisionMap(expected), proposedRevisions = try revisionMap(proposed)
        guard current.schemaVersion == expected.schemaVersion,
              currentMap.count == expectedMap.count, currentRevisions.count == expectedRevisions.count,
              try containsUnchanged(currentMap, in: expectedMap),
              try containsUnchanged(currentRevisions, in: expectedRevisions) else {
            throw SyncError.invalid("预览后本机学习记录或个人内容已变化，已停止保存。请重新同步或重新导入。")
        }
        guard proposed.schemaVersion == 3 else { throw SyncError.invalid("合并结果必须使用新版个人内容格式。") }
        guard try containsUnchanged(currentMap, in: proposedMap) else {
            throw SyncError.invalid("合并结果缺少本机记录或改写了历史，已拒绝保存。")
        }
        guard try containsUnchanged(currentRevisions, in: proposedRevisions) else {
            throw SyncError.invalid("合并结果缺少本机内容修订或改写了历史，已拒绝保存。")
        }
    }

    private static func ordered(_ events: [StudyEvent]) -> [StudyEvent] {
        events.sorted { $0.timestamp == $1.timestamp ? $0.id.uuidString < $1.id.uuidString : $0.timestamp < $1.timestamp }
    }
}
