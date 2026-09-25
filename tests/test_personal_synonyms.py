"""Regression checks for personal synonym entries added on a word."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PersonalSynonymTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.models = (ROOT / "Words800App/Models.swift").read_text(encoding="utf-8")
        cls.library = (ROOT / "Words800App/WordLibraryView.swift").read_text(encoding="utf-8")
        cls.adaptive = (ROOT / "Words800App/AdaptiveLayout.swift").read_text(encoding="utf-8")
        cls.data_manager = (ROOT / "Words800App/DataManager.swift").read_text(encoding="utf-8")
        cls.codec = (ROOT / "Words800App/SnapshotCodec.swift").read_text(encoding="utf-8")
        cls.learning = (ROOT / "Words800App/LearningEngine.swift").read_text(encoding="utf-8")
        cls.merge = (ROOT / "Words800App/SyncMergeEngine.swift").read_text(encoding="utf-8")
        cls.exchange = (ROOT / "Words800App/SyncExchange.swift").read_text(encoding="utf-8")
        cls.sync_view = (ROOT / "Words800App/NearbySyncView.swift").read_text(encoding="utf-8")
        cls.sync_model = (ROOT / "Words800App/NearbySyncModel.swift").read_text(encoding="utf-8")

    def test_synonyms_are_stored_as_one_canonical_event(self):
        self.assertIn("var personalSynonyms: [ConfusableWord] = []", self.models)
        self.assertIn("var synonymHistory: [StudyEvent] = []", self.models)
        self.assertIn('kind = "synonym"', self.models)
        self.assertIn("encoder.outputFormatting = [.sortedKeys]", self.models)
        self.assertIn("canonical == value", self.models)
        self.assertIn("static func merged(_ local: [ConfusableWord], _ incoming: [ConfusableWord])", self.models)
        self.assertIn('case "synonym": r.personalSynonyms = PersonalSynonyms.decode(e.value); r.synonymHistory.append(e)', self.learning)

    def test_snapshot_and_incremental_writes_validate_the_payload(self):
        self.assertIn('"note", "noteImage", "synonym", "errorAdjustment"', self.codec)
        self.assertIn('case "synonym":\n                guard PersonalSynonyms.isValid(event.value)', self.codec)
        self.assertIn('"note", "synonym", "errorAdjustment"', self.data_manager)
        self.assertIn('case "synonym": return PersonalSynonyms.isValid(event.value)', self.data_manager)
        self.assertIn("func updateSynonyms(for id: UUID, synonyms: [ConfusableWord]) throws", self.data_manager)
        self.assertIn('kind: "synonym"', self.data_manager)
        self.assertIn('kind: "synonym"', self.merge)

    def test_word_detail_shows_built_in_and_personal_synonyms_separately(self):
        self.assertIn('Section("关联词与辨析")', self.library)
        self.assertIn('Section("近义词 · 我的补充")', self.library)
        self.assertIn('Label(synonyms.isEmpty ? "添加近义词" : "编辑补充的近义词", systemImage: "text.badge.plus")', self.library)
        self.assertIn('DisclosureGroup("近义词修改历史（\\(record.synonymHistory.count)）")', self.library)
        self.assertIn("WordUsageSections(word: word, record: record, onEditSynonyms: { openEditor(.synonyms) })", self.library)
        self.assertIn("case notes, errors, source, personalWord, addQuestion, synonyms", self.adaptive)
        self.assertIn("case .synonyms: SynonymEditorView(word: request.word)", self.adaptive)

    def test_editor_keeps_drafts_and_rejects_duplicates(self):
        self.assertIn("struct SynonymEditorView: View", self.library)
        self.assertIn("guard !loadedDraft else { return }", self.library)
        self.assertIn("items = dataManager.getStudyRecord(for: word.id).personalSynonyms", self.library)
        self.assertIn("不能作为它的近义词", self.library)
        self.assertIn("if !trimmedName.isEmpty, !stage() { return }", self.library)
        self.assertIn("items.remove(atOffsets: offsets)", self.library)

    def test_sync_offers_a_real_choice_instead_of_a_silent_overwrite(self):
        self.assertIn("enum Kind { case note, errorCount, synonym }", self.merge)
        self.assertIn('case .synonym: return wordID.uuidString + ".synonym"', self.merge)
        self.assertIn('case .synonym: return "近义词"', self.merge)
        self.assertIn('if event.kind == "synonym" { synonyms.insert(id) }', self.merge)
        self.assertIn("a.synonyms.contains(id) && b.synonyms.contains(id), l.personalSynonyms != r.personalSynonyms", self.merge)
        self.assertIn("case .combined: chosen = PersonalSynonyms.merged(local, incoming)", self.merge)
        self.assertIn('choice(conflict.kind == .note ? "两份笔记合并" : "两份近义词合并", value: .combined, conflict: conflict)', self.sync_view)
        self.assertIn("filled(conflict.localDisplay, conflict)", self.sync_view)
        self.assertIn("补充近义词：", self.sync_model)

    def test_content_capability_rejects_older_peers(self):
        self.assertIn("contentSchemaVersion: 5", self.exchange)
        self.assertIn("header.contentSchemaVersion == 5", self.exchange)


if __name__ == "__main__":
    unittest.main()
