"""Manual word/question workflows must keep the two-way continuous entry points."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ManualContentFlowTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.library_view = (ROOT / "Words800App/WordLibraryView.swift").read_text(encoding="utf-8")
        cls.editors = (ROOT / "Words800App/PersonalContentViews.swift").read_text(encoding="utf-8")

    def test_new_word_can_immediately_open_a_prelinked_question_editor(self):
        self.assertIn("PersonalWordEditor(onSaved: savedNewWord", self.library_view)
        self.assertIn("立即添加题目", self.library_view)
        self.assertIn("NewWordQuestionRequest(id: id)", self.library_view)
        self.assertIn("PersonalQuestionEditor(relatedWordIDs: [request.id])", self.library_view)

    def test_question_editor_can_create_and_link_a_new_word(self):
        self.assertIn("PersonalWordEditor(onSaved: selectWord, onUseExisting: selectWord)", self.editors)
        self.assertIn("if !content.relatedWordIDs.contains(id) { content.relatedWordIDs.append(id) }", self.editors)

    def test_word_detail_keeps_manual_question_entry(self):
        self.assertIn('Label("给这个词添加题目", systemImage: "plus.square")', self.library_view)


if __name__ == "__main__":
    unittest.main()
