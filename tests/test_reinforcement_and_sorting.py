"""Regression checks for question-backed word reinforcement and date-based lists."""

from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ReinforcementAndSortingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.library = (ROOT / "Words800App/WordLibraryView.swift").read_text(encoding="utf-8")
        cls.adaptive = (ROOT / "Words800App/AdaptiveLayout.swift").read_text(encoding="utf-8")
        cls.error_words = (ROOT / "Words800App/ErrorWordsView.swift").read_text(encoding="utf-8")
        cls.data_manager = (ROOT / "Words800App/DataManager.swift").read_text(encoding="utf-8")
        cls.models = (ROOT / "Words800App/Models.swift").read_text(encoding="utf-8")
        cls.personal = (ROOT / "Words800App/PersonalContentViews.swift").read_text(encoding="utf-8")
        cls.practice = (ROOT / "Words800App/PracticeView.swift").read_text(encoding="utf-8")

    def test_reinforcement_shows_related_question_only_after_meaning_reveal(self):
        self.assertIn('if title.contains("巩固")', self.library)
        self.assertIn('StudyRelatedQuestionsCard(word: word, questions: dataManager.relatedQuestions(for: word.id))', self.library)
        self.assertIn('Label("开始关联题巩固", systemImage: "play.fill")', self.library)
        self.assertIn('Text("用题目中的语境确认刚刚看到的释义；作答后才显示答案和解析。")', self.library)
        self.assertIn('PracticeSessionView(questions: relatedPracticeQueue)', self.library)

    def test_word_detail_has_a_visible_question_list_for_added_questions(self):
        self.assertIn('Label(manuallyAddedQuestionCount > 0 ? "查看关联题目（我添加了 \\(manuallyAddedQuestionCount) 道）"', self.library)
        self.assertIn('struct WordRelatedQuestionsView: View', self.library)
        self.assertIn('init(word: Word) { initialWord = word }', self.library)
        self.assertIn('manuallyAddedCount > 0 ? "其中 \\(manuallyAddedCount) 道由你手动添加"', self.library)
        self.assertIn('NavigationLink(destination: QuestionExplanationView(question: question, selectedAnswer: nil))', self.library)
        self.assertIn('Label("查看我添加的题目（\\(personalCount)）", systemImage: "list.bullet.rectangle")', self.practice)

    def test_error_word_dates_have_explicit_sorting_and_cached_results(self):
        self.assertIn('case latestError = "最近错题（日期）"', self.models)
        self.assertIn('case earliestError = "最早错题（日期）"', self.models)
        self.assertIn('private var errorWordCache: [ErrorWordSort: [Word]] = [:]', self.data_manager)
        self.assertIn('func errorWords(sortedBy sort: ErrorWordSort)', self.data_manager)
        self.assertIn('private func invalidateErrorWordCache()', self.data_manager)
        self.assertIn('invalidateErrorWordCache()', self.data_manager)
        self.assertIn('dataManager.errorWords(sortedBy: sort)', self.error_words)
        self.assertIn('Text("最近错题")', self.library)

    def test_manual_question_list_can_sort_by_update_date(self):
        self.assertIn('private enum PersonalQuestionSort: String, CaseIterable', self.personal)
        self.assertIn('case newest = "最近更新（日期）"', self.personal)
        self.assertIn('case oldest = "最早更新（日期）"', self.personal)
        self.assertIn('Date(timeIntervalSince1970: revision.timestamp / 1000)', self.personal)

    def test_related_question_list_sorts_once_per_render(self):
        self.assertIn("let displayedQuestions = questions", self.library)
        self.assertIn("ForEach(displayedQuestions)", self.library)
        self.assertIn("practiceQueue = displayedQuestions", self.library)

    def test_large_error_word_view_is_split_for_swift_type_checking(self):
        self.assertIn("sidebar(displayedWords: displayedWords, wide: wide, compactDetail: compactDetail)", self.error_words)
        self.assertIn("private func controlsSection(displayedWords: [Word])", self.error_words)
        self.assertIn("private func beginPractice(with displayedWords: [Word])", self.error_words)

    def test_error_activity_date_has_explicit_initializers(self):
        self.assertIn("init(word: Word, errorActivityDate: Date? = nil)", self.library)
        self.assertIn("errorActivityDate: Date? = nil,", self.adaptive)
        self.assertIn("self.errorActivityDate = errorActivityDate", self.adaptive)
        self.assertIn("self._selection = selection", self.adaptive)
        self.assertIn("self._compactDetailPresented = compactDetailPresented", self.adaptive)


if __name__ == "__main__":
    unittest.main()
