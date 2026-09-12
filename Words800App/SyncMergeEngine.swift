import Foundation

enum SyncError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

struct SyncConflict: Identifiable {
    enum Kind { case note, errorCount }
    let wordID: UUID
    let word: String
    let kind: Kind
    let localValue: String
    let incomingValue: String
    let mergedValue: String
    var id: String { wordID.uuidString + (kind == .note ? ".note" : ".errors") }
    var title: String { kind == .note ? "笔记" : "错误次数" }
}

enum SyncChoice: String, CaseIterable { case local, incoming, combined }

struct SyncMergePreview: Identifiable {
    let id = UUID()
    let local: StudySnapshot
    let incoming: StudySnapshot
    let merged: StudySnapshot
    let conflicts: [SyncConflict]
    var incomingCount: Int { merged.events.count - local.events.count }
    var outgoingCount: Int { merged.events.count - incoming.events.count }
}

// Same reducer and same event IDs as offline learning. Totals are never added together.
enum SyncMergeEngine {
    static func eventMap(_ snapshot: StudySnapshot) throws -> [UUID: StudyEvent] {
        guard snapshot.schemaVersion == 2, snapshot.events.count <= 100000 else {
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

    static func preview(local: StudySnapshot, incoming: StudySnapshot, words: [Word], questions: [Question]) throws -> SyncMergePreview {
        let left = try eventMap(local), right = try eventMap(incoming)
        var union = left
        for (id, event) in right {
            if let existing = union[id], existing != event { throw SyncError.invalid("同一条记录内容不一致，已停止合并。") }
            union[id] = event
        }
        guard union.count <= 100000 else { throw SyncError.invalid("合并后的记录超过上限，未修改本机数据。") }
        let merged = StudySnapshot(events: ordered(Array(union.values)))
        let localOnly = local.events.filter { right[$0.id] == nil }
        let remoteOnly = incoming.events.filter { left[$0.id] == nil }
        let localState = LearningEngine.reduce(words: words, questions: questions, events: local.events).records
        let remoteState = LearningEngine.reduce(words: words, questions: questions, events: incoming.events).records
        let mergedState = LearningEngine.reduce(words: words, questions: questions, events: merged.events).records
        let qByID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
        let wordByName = Dictionary(uniqueKeysWithValues: words.map { ($0.word, $0.id) })
        func edits(_ events: [StudyEvent]) -> (notes: Set<UUID>, manual: Set<UUID>, errors: Set<UUID>) {
            var notes = Set<UUID>(), manual = Set<UUID>(), errors = Set<UUID>()
            for event in events {
                if let id = event.wordID {
                    if event.kind == "note" { notes.insert(id) }
                    if event.kind == "errorAdjustment" { manual.insert(id); errors.insert(id) }
                    if event.kind == "rating" && event.value == "0" { errors.insert(id) }
                }
                if event.kind == "answer", let qid = event.questionID, let q = qByID[qid], Int(event.value) != q.correctAnswer {
                    for name in q.relatedWords { if let id = wordByName[name] { errors.insert(id) } }
                }
            }
            return (notes, manual, errors)
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
        }
        return SyncMergePreview(local: local, incoming: incoming, merged: merged, conflicts: conflicts)
    }

    static func resolve(_ preview: SyncMergePreview, choices: [String: SyncChoice], now: Double = Date().timeIntervalSince1970 * 1000) throws -> StudySnapshot {
        var result = preview.merged
        var stamp = max(now, (result.events.map { $0.timestamp }.max() ?? 0) + 1)
        for conflict in preview.conflicts {
            guard let choice = choices[conflict.id] else { throw SyncError.invalid("请先处理所有冲突，再确认合并。") }
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
                // Each adjustment must stay readable by the existing v2 validator.
                while delta != 0 {
                    let part = max(-99999, min(99999, delta))
                    result.events.append(StudyEvent(wordID: conflict.wordID, kind: "errorAdjustment", value: String(part), timestamp: stamp))
                    stamp += 1; delta -= part
                }
            }
        }
        return result
    }

    static func validateCommit(current: StudySnapshot, expected: StudySnapshot, proposed: StudySnapshot) throws {
        let currentMap = try eventMap(current), expectedMap = try eventMap(expected), proposedMap = try eventMap(proposed)
        guard currentMap == expectedMap else { throw SyncError.invalid("预览后本机又有新记录，已停止保存。请重新同步或重新导入。") }
        for (id, event) in currentMap where proposedMap[id] != event {
            throw SyncError.invalid("合并结果缺少本机记录或改写了历史，已拒绝保存。")
        }
    }

    private static func ordered(_ events: [StudyEvent]) -> [StudyEvent] {
        events.sorted { $0.timestamp == $1.timestamp ? $0.id.uuidString < $1.id.uuidString : $0.timestamp < $1.timestamp }
    }
}
