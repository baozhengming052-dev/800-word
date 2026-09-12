"""Offline standard-library checks. Swift grammar check is NOT a compiler."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import plistlib
import re
import struct
import sys
import uuid
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parents[1]

def check(condition, message):
    if not condition:
        raise AssertionError(message)

def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))

def validate():
    app = ROOT / 'Words800App'
    library = read_json(app / 'Resources/library.json')
    report = read_json(ROOT / 'content/import-report.json')
    words, questions = library['words'], library['questions']
    check(library['schemaVersion'] == 2, 'Library schema')
    names = {w['word'] for w in words}
    check(len(words) == len(names) == report['uniqueWords'] == 865, 'Unique word count')
    check(sum(len(w['occurrences']) for w in words) == report['sourceRows'] == 874, 'Every source occurrence retained')
    check(sum(w['sourceDeleted'] for w in words) == 62, 'Source deletion marks')
    all_ids = [w['id'] for w in words] + [q['id'] for q in questions]
    check(len(set(all_ids)) == len(all_ids), 'Unique stable IDs')
    for value in all_ids:
        uuid.UUID(value)
    for word in words:
        check(word['meanings'] and all(word['meanings']), f"Missing meaning: {word['word']}")
        check(word['category'] and word['occurrences'], f"Missing source: {word['word']}")
        check(word['sourceDeleted'] == all(o['sourceDeleted'] for o in word['occurrences']), 'Archive aggregation')
        for occurrence in word['occurrences']:
            check(2 <= occurrence['page'] <= 28 and occurrence['originalText'], 'Invalid source occurrence')
    for q in questions:
        check(len(q['options']) == len(set(q['options'])) == 4, 'Four distinct options')
        check(isinstance(q['correctAnswer'], int) and 0 <= q['correctAnswer'] < 4, 'Answer index')
        check(q['content'] and q['explanation'] and q['source'], 'Incomplete question')
        check(q['relatedWords'] and set(q['relatedWords']) <= names, 'Question-word relation')
        if q['type'] == '真题':
            check(q['sourceURL'].startswith('https://'), 'Real question needs provenance')
    check(dict(Counter(q['type'] for q in questions)) == report['questions'], 'Question counts')
    source = app / 'Resources/source.pdf'
    check(hashlib.sha256(source.read_bytes()).hexdigest() == library['sourceSHA256'], 'PDF fingerprint')
    check(sum(not w['examples'] for w in words) == report['missingExamples'], 'Honest example coverage')
    page_counts = Counter(str(o['page']) for w in words for o in w['occurrences'])
    check(dict(page_counts) == report['byPage'], 'Per-page completeness')
    # If a local extraction is present, compare every original row, not only counts.
    extraction = ROOT / 'tmp/pdfs/pages.json'
    if extraction.exists():
        expected = []
        for page in read_json(extraction)[1:]:
            for table in page['tables']:
                for row in table:
                    if len(row) != 4:
                        continue
                    raw_word, raw_text = (re.sub(r'\s+', '', value or '') for value in row[2:])
                    if not raw_word or raw_word in ['成语', '词语', '实词']:
                        continue
                    if raw_word == '(删除)' and not raw_text:
                        number, word, meaning = expected[-1]
                        expected[-1] = (number, word + '(删除)', meaning)
                    else:
                        expected.append((page['page'], raw_word, raw_text))
        actual = [(o['page'], o['originalWord'], o['originalText']) for w in words for o in w['occurrences']]
        check(Counter(expected) == Counter(actual), 'Exact source text retained for every PDF row')
        print('PASS: every original PDF row matches bundled source text')
    pbx = (ROOT / 'Words800App.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
    identifiers = set(re.findall(r'\b[0-9A-F]{24}\b', pbx))
    definitions = re.findall(r'^\s*([0-9A-F]{24})(?: /\*.*?\*/)? = \{\s*isa =', pbx, re.M)
    check(identifiers == set(definitions), 'All Xcode object references resolve')
    check(len(definitions) == len(set(definitions)), 'Duplicate project objects')
    check(not re.search(r'\bA100000[0-9A-F]{2}\b', pbx), 'Nonstandard project identifiers')
    for source_file in app.glob('*.swift'):
        check(f'path = {source_file.name};' in pbx, f'Unregistered source {source_file.name}')
        check(pbx.count(f'{source_file.name} in Sources') == 2, f'Source build phase {source_file.name}')
    check('lastKnownFileType = folder; path = Resources;' not in pbx, 'Reserved Resources directory must not be copied into iOS bundle')
    for filename in ['library.json', 'source.pdf']:
        check(pbx.count(f'{filename} in Resources') == 2, f'Individual resource build phase: {filename}')
    scheme = ET.parse(ROOT / 'Words800App.xcodeproj/xcshareddata/xcschemes/Words800App.xcscheme')
    for reference in scheme.findall('.//BuildableReference'):
        check(reference.attrib['BlueprintIdentifier'] in identifiers, 'Shared scheme target')
        check(reference.attrib['ReferencedContainer'] == 'container:Words800App.xcodeproj', 'Scheme container')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    check(info['CFBundleShortVersionString'] == '2.1', 'Version')
    check(info['CFBundleVersion'] == '3', 'Build version')
    check(info.get('NSLocalNetworkUsageDescription'), 'Nearby permission explanation')
    check('_words800-sync._tcp' in info.get('NSBonjourServices', []), 'Nearby Bonjour service')
    check('NSCameraUsageDescription' not in info, 'No unused QR camera permission')
    check('UISceneConfigurations' not in info.get('UIApplicationSceneManifest', {}), 'No nonexistent scene delegate')
    check('IPHONEOS_DEPLOYMENT_TARGET = 15.0;' in pbx, 'iOS 16.5 compatibility floor')
    icons_dir = app / 'Assets.xcassets/AppIcon.appiconset'
    icons = read_json(icons_dir / 'Contents.json')
    for icon in icons['images']:
        data = (icons_dir / icon['filename']).read_bytes()
        check(data[:8] == b'\x89PNG\r\n\x1a\n', 'PNG signature')
        width, height = struct.unpack('>II', data[16:24])
        size = round(float(icon['size'].split('x')[0]) * float(icon['scale'][:-1]))
        check(width == height == size and data[25] == 2, 'Icon dimensions and opaque RGB')
    print(f'PASS: content, {len(words)} words / {len(questions)} questions, PDF hash, project references, shared scheme, plist and icons')

def swift_syntax():
    sys.path.insert(0, str(ROOT / 'tmp/validation-deps'))
    import tree_sitter
    import tree_sitter_swift
    parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
    files = list((ROOT / 'Words800App').glob('*.swift')) + list((ROOT / 'tests').glob('*.swift'))
    for path in files:
        tree = parser.parse(path.read_bytes())
        if tree.root_node.has_error:
            stack = [tree.root_node]
            while stack:
                node = stack.pop()
                if node.type == 'ERROR' or node.is_missing:
                    print(path.name, node.type, node.start_point, node.text[:200])
                stack.extend(reversed(node.children))
            raise AssertionError(f'Swift syntax: {path.name}')
    print(f'PASS: Swift grammar parsed in {len(files)} files (not type checking or iOS compilation)')

def validate_ipa(path):
    with zipfile.ZipFile(path) as archive:
        check(archive.testzip() is None, 'Archive CRC')
        prefix = 'Payload/Words800App.app/'
        check(not any(name.startswith(prefix + 'Resources/') for name in archive.namelist()), 'Reserved Resources directory inside iOS bundle')
        info = plistlib.loads(archive.read(prefix + 'Info.plist'))
        check(info['CFBundleIdentifier'] == 'com.peanut13.words800', 'Bundle ID')
        check(info['CFBundlePackageType'] == 'APPL', 'App bundle type')
        minimum = tuple(int(v) for v in info['MinimumOSVersion'].split('.'))
        check(minimum <= (16, 5), 'Minimum iOS version exceeds user device')
        executable = archive.read(prefix + info['CFBundleExecutable'])
        check(executable[:4] == b'\xcf\xfa\xed\xfe', 'Mach-O 64-bit executable')
        check(struct.unpack('<I', executable[4:8])[0] == 0x0100000C, 'ARM64 executable, not simulator')
        for filename in ['library.json', 'source.pdf']:
            bundled = archive.read(prefix + filename)
            check(bundled == (ROOT / 'Words800App/Resources' / filename).read_bytes(), 'Complete IPA resources')
        check(prefix + 'Assets.car' in archive.namelist(), 'Compiled assets')
    print('PASS: IPA structure, ARM64 executable, iOS floor and complete bundled resources')

if __name__ == '__main__':
    args = argparse.ArgumentParser()
    args.add_argument('--swift-syntax', action='store_true')
    args.add_argument('--ipa', type=Path)
    options = args.parse_args()
    validate()
    if options.swift_syntax:
        swift_syntax()
    if options.ipa:
        validate_ipa(options.ipa)
