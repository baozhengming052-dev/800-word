import Foundation

/// Pure proposals; the runtime publishes only after SnapshotStore saves the complete value.
enum PersonalTransactions {
    private static func head(_ catalog: PersonalCatalog, entryID: UUID, expected: Set<UUID>) throws -> PersonalRevision? {
        let heads = catalog.headsByEntryID[entryID] ?? []
        guard Set(heads.map(\.id)) == expected else {
            throw PersonalLibraryError.invalid("此条目已在其他页面或同步中更新。草稿仍保留，请取消后重新打开，核对最新内容再编辑。")
        }
        guard heads.count <= 1 else {
            throw PersonalLibraryError.invalid("此条目存在多个版本，请先到“我的 → 处理本机内容冲突”选择版本。")
        }
        return heads.first
    }

    static func word(snapshot: StudySnapshot, builtInWords: [Word], builtInQuestions: [Question],
                     content: PersonalWordContent, entryID: UUID, expectedHeads: Set<UUID>, notes: String?) throws -> StudySnapshot {
        let catalog = try SnapshotCodec.validate(snapshot: snapshot, builtInWords: builtInWords, builtInQuestions: builtInQuestions)
        let previous = try head(catalog, entryID: entryID, expected: expectedHeads)
        guard previous == nil || previous?.word != nil else { throw PersonalLibraryError.invalid("条目类型不匹配。") }
        let value = PersonalLibrary.normalize(content)
        try PersonalLibrary.validate(value)
        let archived = previous?.archived ?? false
        if !archived, catalog.words.contains(where: {
            $0.id != entryID && !catalog.archivedWordIDs.contains($0.id)
                && PersonalLibrary.normalizedName($0.word) == PersonalLibrary.normalizedName(value.word)
        }) { throw PersonalLibraryError.invalid("已有同名词条。请打开已有词条添加笔记或题目。") }
        var proposed = snapshot
        proposed.revisions.append(PersonalRevision(entryID: entryID, parents: previous.map { [$0.id] } ?? [], word: value, archived: archived))
        if let notes = notes {
            let value = notes
            guard value.utf8.count <= 100_000 else { throw PersonalLibraryError.invalid("笔记不能超过 100,000 UTF-8 字节。") }
            let stamp = max(Date().timeIntervalSince1970 * 1000, (snapshot.events.map(\.timestamp).max() ?? 0) + 0.001)
            proposed.events.append(StudyEvent(wordID: entryID, kind: "note", value: value, timestamp: stamp))
        }
        try SyncMergeEngine.validateProposal(proposed, words: builtInWords, questions: builtInQuestions)
        return proposed
    }

    static func question(snapshot: StudySnapshot, builtInWords: [Word], builtInQuestions: [Question],
                         content: PersonalQuestionContent, entryID: UUID, expectedHeads: Set<UUID>) throws -> StudySnapshot {
        let catalog = try SnapshotCodec.validate(snapshot: snapshot, builtInWords: builtInWords, builtInQuestions: builtInQuestions)
        let previous = try head(catalog, entryID: entryID, expected: expectedHeads)
        guard previous == nil || previous?.question != nil else { throw PersonalLibraryError.invalid("条目类型不匹配。") }
        let value = PersonalLibrary.normalize(content)
        let activeIDs = Set(catalog.words.filter { !catalog.archivedWordIDs.contains($0.id) }.map(\.id))
        try PersonalLibrary.validate(value, validWordIDs: activeIDs)
        var proposed = snapshot
        proposed.revisions.append(PersonalRevision(entryID: entryID, parents: previous.map { [$0.id] } ?? [],
            question: value, archived: previous?.archived ?? false))
        try SyncMergeEngine.validateProposal(proposed, words: builtInWords, questions: builtInQuestions)
        return proposed
    }

    static func archive(snapshot: StudySnapshot, builtInWords: [Word], builtInQuestions: [Question],
                        entryID: UUID, expectedHeads: Set<UUID>, archived: Bool) throws -> StudySnapshot {
        let catalog = try SnapshotCodec.validate(snapshot: snapshot, builtInWords: builtInWords, builtInQuestions: builtInQuestions)
        guard let previous = try head(catalog, entryID: entryID, expected: expectedHeads) else {
            throw PersonalLibraryError.invalid("只能归档或恢复手动添加的内容。")
        }
        var proposed = snapshot
        proposed.revisions.append(PersonalRevision(entryID: entryID, parents: [previous.id], word: previous.word,
            question: previous.question, archived: archived))
        try SyncMergeEngine.validateProposal(proposed, words: builtInWords, questions: builtInQuestions)
        return proposed
    }

    static func practiceQuestions(catalog: PersonalCatalog) -> [Question] {
        let activeIDs = Set(catalog.words.filter { !catalog.archivedWordIDs.contains($0.id) }.map(\.id))
        let builtInWords = catalog.words.filter { !$0.isPersonal }
        return catalog.activeQuestions.filter {
            LearningEngine.relatedWordIDs(for: $0, words: $0.personalEntryID == nil ? builtInWords : []).contains(where: activeIDs.contains)
        }
    }
}
