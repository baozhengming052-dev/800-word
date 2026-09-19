"""Regression checks for the two-school launch and home branding."""

import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class CollaborationBrandingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.content_view = (ROOT / "Words800App/ContentView.swift").read_text(encoding="utf-8")
        cls.assets = ROOT / "Words800App/Assets.xcassets"

    def test_vector_logos_are_packaged_as_universal_images(self):
        pairs = (
            ("HNIEBrand.imageset", "hnie-brand.svg"),
            ("TJCUBrand.imageset", "tjcu-brand.svg"),
        )
        for folder_name, filename in pairs:
            folder = self.assets / folder_name
            svg = folder / filename
            metadata = json.loads((folder / "Contents.json").read_text(encoding="utf-8"))
            self.assertTrue(svg.is_file())
            self.assertGreater(svg.stat().st_size, 1_000)
            self.assertEqual(metadata["images"][0]["filename"], filename)
            self.assertEqual(metadata["images"][0]["idiom"], "universal")
            self.assertTrue(metadata["properties"]["preserves-vector-representation"])

    def test_launch_branding_uses_both_assets_and_dismisses_itself(self):
        self.assertIn("struct CollaborationLaunchView: View", self.content_view)
        self.assertIn('Image("HNIEBrand")', self.content_view)
        self.assertIn('Image("TJCUBrand")', self.content_view)
        self.assertIn("showLaunchBranding = false", self.content_view)
        self.assertIn("accessibilityReduceMotion", self.content_view)
        self.assertNotIn("private func logoCard", self.content_view)

    def test_home_has_a_compact_accessible_joint_mark(self):
        self.assertIn("struct CollaborationHomeMark: View", self.content_view)
        self.assertIn("CollaborationHomeMark()", self.content_view)
        self.assertIn("湖南工程学院 × 天津商业大学", self.content_view)
        self.assertIn("湖南工程学院与天津商业大学联合学习项目", self.content_view)

    def test_tjcu_asset_is_the_wide_name_lockup(self):
        svg = (self.assets / "TJCUBrand.imageset/tjcu-brand.svg").read_text(encoding="utf-8")
        self.assertIn('viewBox="2800 10250 17400 4750"', svg)
        self.assertNotIn('width="889.357666015625"', svg)


if __name__ == "__main__":
    unittest.main()
