"""Packaging boundary: Bonjour permission/service declaration must ship in the app."""
import pathlib
import plistlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class DeviceCapabilitiesTests(unittest.TestCase):
    def setUp(self):
        self.info = plistlib.loads((ROOT / "Words800App/Info.plist").read_bytes())

    def test_nearby_discovery_has_permission_and_declared_service(self):
        self.assertTrue(self.info.get("NSLocalNetworkUsageDescription"), "Local discovery needs an explained permission")
        self.assertIn("_words800-sync._tcp", self.info.get("NSBonjourServices", []), "Bonjour must be permitted in the installed bundle")

    def test_ipad_rotates_without_unlocking_iphone(self):
        ipad = self.info["UISupportedInterfaceOrientations~ipad"]
        self.assertIn("UIInterfaceOrientationLandscapeLeft", ipad)
        self.assertIn("UIInterfaceOrientationLandscapeRight", ipad)
        self.assertEqual(self.info["UISupportedInterfaceOrientations"], ["UIInterfaceOrientationPortrait"])


if __name__ == "__main__":
    unittest.main()
