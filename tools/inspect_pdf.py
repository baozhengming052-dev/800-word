"""Read-only source inspection; scratch renders/extractions are reproducible."""
from pathlib import Path
import json
import pdfplumber

root = Path(__file__).resolve().parents[1]
out = root / 'tmp' / 'pdfs'
out.mkdir(parents=True, exist_ok=True)
source = root / 'Words800App/Resources/source.pdf'
if not source.exists():
    source = root.parent / '高频800词.pdf'
with pdfplumber.open(source) as pdf:
    pages = []
    for number, page in enumerate(pdf.pages, 1):
        tables = page.extract_tables()
        pages.append({'page': number, 'text': page.extract_text(), 'tables': tables})
    (out / 'pages.json').write_text(json.dumps(pages, ensure_ascii=False, indent=2), encoding='utf-8')
    for i in [1, 13, 27]:
        pdf.pages[i].to_image(resolution=120).save(out / f'page-{i+1}.png')
    print('pages:',len(pages))
    for p in pages[:3]:
        print('PAGE',p['page'], 'TABLES', len(p['tables']))
        print(json.dumps(p['tables'],ensure_ascii=False)[:14000])
