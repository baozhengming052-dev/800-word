"""Exercise the release CLI in isolated repositories; never tag/commit the user's repo."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/release.py"
GIT = shutil.which("git") or r"C:\Program Files\Git\cmd\git.exe"


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "Words800App.xcodeproj").mkdir()
        (self.root / "Words800App.xcodeproj/project.pbxproj").write_text(
            "MARKETING_VERSION = 2.1.0;\nCURRENT_PROJECT_VERSION = 3;\n"
            "MARKETING_VERSION = 2.1.0;\nCURRENT_PROJECT_VERSION = 3;\n", encoding="utf-8")
        (self.root / ".github").mkdir()
        template = ROOT / ".github/release-template.md"
        (self.root / ".github/release-template.md").write_text(
            template.read_text(encoding="utf-8") if template.exists() else
            "## $tag\n\n### 更新内容\n\n$changes\n\n### 下载\n\n- [Words800App.ipa]($ipa_url)\n\n源码：$commit\n", encoding="utf-8")
        self.readme("# 项目\n\n## 更新日志\n\n### v1.1.0\n\n- 新增：附近同步\n- 修复：草稿保留\n\n### v1.0.0\n\n- 新增：词库\n")
        self.git("init", "-q")
        self.commit("初始词库")

    def git(self, *args):
        result = subprocess.run([GIT, "-c", "user.name=Release Tests", "-c", "user.email=release-tests@example.invalid", *args],
                                cwd=self.root, capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def readme(self, text):
        (self.root / "README.md").write_text(text, encoding="utf-8")

    def commit(self, message):
        self.git("add", ".")
        self.git("commit", "-qm", message)

    def run_cli(self, command="prepare", ref="refs/tags/v1.1.0", event="push", run_number="555"):
        env = {**os.environ, "GITHUB_REF": ref, "GITHUB_EVENT_NAME": event,
               "GITHUB_REPOSITORY": "owner/words", "GITHUB_SERVER_URL": "https://github.com",
               "GITHUB_OUTPUT": str(self.root / "outputs.txt"), "GITHUB_RUN_NUMBER": run_number,
               "PYTHONIOENCODING": "utf-8"}
        return subprocess.run([sys.executable, str(SCRIPT), command, "--root", str(self.root)],
                              capture_output=True, text=True, encoding="utf-8", env=env)

    def prepare(self, **kwargs):
        result = self.run_cli(**kwargs)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads((self.root / "build/release-metadata.json").read_text(encoding="utf-8"))

    def notes(self):
        return (self.root / "build/release/release-notes.md").read_text(encoding="utf-8")

    def test_tag_controls_versions_and_notes_not_run_counter(self):
        self.git("tag", "v1.1.0")
        metadata = self.prepare()
        self.assertEqual((metadata["version"], metadata["build_number"], metadata["publish"]), ("1.1.0", "1.1.0", True))
        self.assertEqual(metadata["tag"], "v1.1.0")
        self.assertEqual(metadata["commit"], self.git("rev-parse", "HEAD"))
        self.assertIn("附近同步", self.notes())
        self.assertNotIn("新增：词库", self.notes())
        self.assertIn("releases/download/v1.1.0/Words800App.ipa", self.notes())
        self.assertEqual(metadata, self.prepare(run_number="99999"))

    def test_manual_branch_is_preview_only(self):
        metadata = self.prepare(ref="refs/heads/main", event="workflow_dispatch")
        self.assertFalse(metadata["publish"])
        self.assertIsNone(metadata["tag"])
        self.assertEqual((metadata["version"], metadata["build_number"]), ("2.1.0", "3"))
        self.assertIn("不会创建 Release", self.notes())
        self.assertNotIn("releases/download", self.notes())

    def test_manual_existing_tag_can_publish(self):
        self.git("tag", "v1.1.0")
        self.assertTrue(self.prepare(event="workflow_dispatch")["publish"])

    def test_branch_push_and_invalid_tags_fail_closed(self):
        for ref, event in [("refs/heads/main", "push"), ("refs/tags/v1.1", "push"),
                           ("refs/tags/v01.1.0", "push"), ("refs/tags/v1.100.0", "push"),
                           ("refs/tags/v1.1.0-beta", "push"), ("refs/tags/v1.1.0;echoBAD", "push")]:
            with self.subTest(ref=ref):
                result = self.run_cli(ref=ref, event=event)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.root / "build/release-metadata.json").exists())

    def test_tag_must_exist_and_point_at_checked_out_commit(self):
        self.assertNotEqual(self.run_cli().returncode, 0)
        self.git("tag", "v1.1.0")
        self.readme("# 改动\n")
        self.commit("更新代码")
        self.assertNotEqual(self.run_cli().returncode, 0)

    def test_annotated_tag_resolves_to_commit(self):
        self.git("tag", "-am", "release", "v1.1.0")
        self.assertEqual(self.prepare()["commit"], self.git("rev-parse", "HEAD"))

    def test_fenced_example_is_not_treated_as_real_changelog(self):
        self.readme("# 项目\n## 更新日志\n```markdown\n### v1.1.0\n- 示例，不要发布\n```\n\n### v1.1.0\n- 实际修复\n## 发布方式\n其他说明\n")
        self.commit("填写更新日志")
        self.git("tag", "v1.1.0")
        self.prepare()
        self.assertIn("实际修复", self.notes())
        self.assertNotIn("示例，不要发布", self.notes())
        self.assertNotIn("其他说明", self.notes())

    def test_fallback_uses_only_commits_since_previous_tag(self):
        self.git("tag", "v1.0.0")
        self.readme("# 项目\n## 更新日志\n### v1.0.0\n- 旧版本\n")
        self.commit("新增错词排序")
        self.git("tag", "v1.1.0")
        metadata = self.prepare()
        self.assertEqual(metadata["notes_source"], "git")
        self.assertIn("新增错词排序", self.notes())
        self.assertNotIn("初始词库", self.notes())
        self.assertIn("compare/v1.0.0...v1.1.0", self.notes())

    def test_project_readme_and_template_produce_current_release_notes(self):
        self.readme((ROOT / "README.md").read_text(encoding="utf-8"))
        self.commit("更新发布说明")
        self.git("tag", "v2.2.0")
        metadata = self.prepare(ref="refs/tags/v2.2.0")
        self.assertEqual(metadata["notes_source"], "README")
        self.assertIn("## v2.2.0", self.notes())
        self.assertIn("政名政利公考800词", self.notes())
        self.assertIn("### 更新内容", self.notes())
        self.assertIn("### 下载", self.notes())
        self.assertIn("releases/download/v2.2.0/Words800App.ipa", self.notes())
        self.assertNotIn("填写本版本", self.notes())
        self.assertNotIn("git push origin", self.notes())
        self.assertNotIn("## 已写入的功能", self.notes())

    def test_duplicate_version_notes_fail_before_publishing(self):
        self.readme("## 更新日志\n### v1.1.0\n- 第一份\n### v1.1.0\n- 第二份\n")
        self.commit("重复更新记录")
        self.git("tag", "v1.1.0")
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("重复出现", result.stderr)
        self.assertFalse((self.root / "build/release-metadata.json").exists())

    def test_stage_copies_bytes_and_generates_matching_checksum(self):
        self.git("tag", "v1.1.0")
        self.prepare()
        payload = b"test packaging payload, not an installable IPA"
        source = self.root / "build/800词学习助手.ipa"
        source.write_bytes(payload)
        result = self.run_cli(command="stage")
        self.assertEqual(result.returncode, 0, result.stderr)
        staged = self.root / "build/release/Words800App.ipa"
        self.assertEqual(source.read_bytes(), staged.read_bytes())
        checksum = (staged.parent / "Words800App.ipa.sha256").read_text(encoding="utf-8")
        self.assertEqual(checksum, hashlib.sha256(payload).hexdigest() + "  Words800App.ipa\n")
        self.assertTrue((staged.parent / "release-metadata.json").is_file())

    def test_stage_rejects_missing_ipa(self):
        self.git("tag", "v1.1.0")
        self.prepare()
        result = self.run_cli(command="stage")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "build/release/Words800App.ipa").exists())


class BrandingTests(unittest.TestCase):
    def test_installed_bundle_uses_new_display_name_without_changing_identity(self):
        info = plistlib.loads((ROOT / "Words800App/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleDisplayName"], "政名政利公考800词")
        self.assertEqual(info["CFBundleIdentifier"], "$(PRODUCT_BUNDLE_IDENTIFIER)")


if __name__ == "__main__":
    unittest.main()
