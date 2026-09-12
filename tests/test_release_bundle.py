"""An uploaded IPA must expose the exact Tag version, brand, and existing bundle ID."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("bundle_validator", ROOT / "tools/validate_project.py")
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class ReleaseBundleTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(hasattr(VALIDATOR, "validate_bundle_info"), "Archive metadata needs a version/name validation boundary")
        self.info = {"CFBundleIdentifier": "com.peanut13.words800", "CFBundlePackageType": "APPL",
                     "CFBundleDisplayName": "政名政利公考800词", "CFBundleShortVersionString": "1.1.0",
                     "CFBundleVersion": "1.1.0"}

    def test_accepts_tagged_bundle(self):
        VALIDATOR.validate_bundle_info(self.info, "1.1.0", "1.1.0")

    def test_rejects_unresolved_or_wrong_version(self):
        for key, value in [("CFBundleShortVersionString", "2.1.0"), ("CFBundleVersion", "9999"),
                           ("CFBundleShortVersionString", "$(MARKETING_VERSION)")]:
            with self.subTest(key=key, value=value), self.assertRaises(AssertionError):
                VALIDATOR.validate_bundle_info({**self.info, key: value}, "1.1.0", "1.1.0")

    def test_rejects_old_brand_or_changed_app_identity(self):
        for key, value in [("CFBundleDisplayName", "花生十三800词"), ("CFBundleIdentifier", "com.changed.app")]:
            with self.subTest(key=key), self.assertRaises(AssertionError):
                VALIDATOR.validate_bundle_info({**self.info, key: value}, "1.1.0", "1.1.0")


if __name__ == "__main__":
    unittest.main()
