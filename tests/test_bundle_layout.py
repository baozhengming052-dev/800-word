"""Resolve the real resource build phase and check its installed bundle layout.

Regression: copying a blue folder named Resources creates an invalid iOS bundle
and can make Xcode archive report 'Archive Missing Bundle Identifier'.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def resource_destinations():
    project = (ROOT / 'Words800App.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
    project = re.sub(r'/\*.*?\*/', '', project, flags=re.S)
    objects = dict(re.findall(r'([0-9A-F]{24})\s*=\s*\{([^{}]*)\};', project, re.S))
    phase = next(body for body in objects.values() if 'isa = PBXResourcesBuildPhase;' in body)
    file_list = re.search(r'files\s*=\s*\((.*?)\);', phase, re.S).group(1)
    destinations = set()
    for build_id in re.findall(r'[0-9A-F]{24}', file_list):
        file_id = re.search(r'fileRef\s*=\s*([0-9A-F]{24})', objects[build_id]).group(1)
        reference = objects[file_id]
        path = re.search(r'path\s*=\s*([^;]+);', reference).group(1).strip().strip('"')
        # Asset catalogs compile to Assets.car; ordinary resources retain basename.
        destinations.add('Assets.car' if path.endswith('.xcassets') else Path(path).name)
    return destinations


class BundleLayoutTests(unittest.TestCase):
    def test_no_reserved_resources_directory_in_ios_bundle(self):
        self.assertNotIn('Resources', resource_destinations(),
                         'Copy individual resources, not a Resources folder, into the iOS bundle')

    def test_library_and_pdf_are_installed_at_bundle_root(self):
        self.assertTrue({'library.json', 'source.pdf'} <= resource_destinations(),
                        'Bundle.main must be able to find both files at the iOS resource root')


if __name__ == '__main__':
    unittest.main()
