"""Question stems must not give answer hints; explanations remain post-answer."""
from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
# Match hint labels, not legitimate meanings such as “语言文字数量极少”.
HINT = re.compile(r'提示[：:]|首字(?:[：:]|为)|字数[：:]|共\s*\d+\s*字|正确答案[：:]')


class QuestionPromptTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.library = json.loads((ROOT / 'Words800App/Resources/library.json').read_text(encoding='utf-8'))

    def test_bundled_question_stems_do_not_contain_answer_hints(self):
        leaks = [q['id'] for q in self.library['questions'] if HINT.search(q['content'])]
        self.assertEqual(len(leaks), 0, f'{len(leaks)} question stems leak hints; first: {leaks[:3]}')

    def test_reported_question_keeps_its_identity_and_explanation_without_hint(self):
        question = next(q for q in self.library['questions'] if q['id'] == '947BFE55-FF46-577B-9C3B-3863D887B92A')
        self.assertEqual(question['options'], ['秉承', '秉持', '凝视', '蔓延'])
        self.assertEqual(question['correctAnswer'], 2)
        self.assertIn('指聚精会神地观看，不眨眼睛，神情专注。', question['content'])
        self.assertNotRegex(question['content'], HINT)
        self.assertIn('原资料释义：', question['explanation'])

    def test_regeneration_does_not_restore_hints(self):
        spec = importlib.util.spec_from_file_location('build_content', ROOT / 'tools/build_content.py')
        generator = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(generator)
        # Minimal source fixture exercises the real generation pipeline without a PDF dependency.
        with tempfile.TemporaryDirectory(prefix='words800-prompt-test-') as directory:
            fixture = Path(directory)
            for relative in ['content', 'tmp/pdfs', 'Words800App/Resources']:
                (fixture / relative).mkdir(parents=True)
            rows = [
                ['', '观察', '凝视', '指聚精会神地观看，不眨眼睛，神情专注。'],
                ['', '承接', '秉承', '接受、承接。'],
                ['', '坚守', '秉持', '所坚守的原则或态度。'],
                ['', '发展', '蔓延', '向周围扩散、延伸。'],
            ]
            (fixture / 'tmp/pdfs/pages.json').write_text(json.dumps([
                {'page': 1, 'tables': []}, {'page': 2, 'tables': [rows]}
            ]), encoding='utf-8')
            (fixture / 'content/category-starts.json').write_text(json.dumps([[2, '凝视', '动作']]), encoding='utf-8')
            (fixture / 'Words800App/Resources/source.pdf').write_bytes(b'%PDF-test-fixture')
            generator.ROOT = fixture
            with redirect_stdout(io.StringIO()):
                generator.main()
            generated = json.loads((fixture / 'Words800App/Resources/library.json').read_text(encoding='utf-8'))
            self.assertEqual(len(generated['questions']), 4)
            for question in generated['questions']:
                self.assertNotRegex(question['content'], HINT)
                self.assertTrue(question['explanation'])


if __name__ == '__main__':
    unittest.main()
