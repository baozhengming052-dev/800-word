"""Reproducibly import every vocabulary row from the user supplied PDF.

Source text is never silently discarded. Editorial changes live in corrections.json.
"""
import collections
import hashlib
import json
from pathlib import Path
import re
import uuid

ROOT = Path(__file__).resolve().parents[1]
NS = uuid.UUID('5cb74b62-405d-4bc1-8971-35f61ee8786e')

def uid(value):
    return str(uuid.uuid5(NS, value)).upper()

def clean(value):
    return re.sub(r'\s+', '', value or '')

def main():
    pages = json.loads((ROOT / 'tmp/pdfs/pages.json').read_text(encoding='utf-8'))
    corrections_path = ROOT / 'content/corrections.json'
    corrections = json.loads(corrections_path.read_text(encoding='utf-8')) if corrections_path.exists() else {}
    starts = {(page,word): category for page,word,category in json.loads((ROOT/'content/category-starts.json').read_text(encoding='utf-8'))}
    found_starts=set()
    rows = []
    category, subgroup, section = '', '', '成语'
    for page in pages[1:]:
        for table in page['tables']:
            for index, row in enumerate(table):
                if len(row) != 4:
                    continue
                major, minor, word, meaning = map(clean, row)
                if not word or word in ['成语', '词语', '实词']:
                    continue
                original_word = re.sub(r'[（(](删除|修改)[）)]', '', word)
                start_key=(page['page'],original_word)
                if start_key in starts:
                    category=starts[start_key]
                    found_starts.add(start_key)
                    subgroup=''
                section = '实词' if page['page']>=24 else '成语'
                if minor:
                    subgroup = minor
                if word == '(删除)' and not meaning:
                    rows[-1]['sourceDeleted'] = True
                    rows[-1]['originalWord'] += '(删除)'
                    continue
                if not meaning:
                    raise ValueError(f'Missing definition: {page["page"]} {word}')
                deleted = '删除' in word or category == '生僻成语'
                original = word
                word = original_word
                correction = corrections.get(word, {})
                word = correction.get('word', word)
                rows.append(dict(word=word, originalWord=original, category=category,
                                 subcategory=subgroup, section=section, page=page['page'],
                                 originalText=meaning, sourceDeleted=deleted,
                                 correctionNote=correction.get('note','')))

    if set(starts)-found_starts:
        raise ValueError('Unmatched category boundaries: '+str(set(starts)-found_starts))

    by_word = collections.OrderedDict()
    for row in rows:
        by_word.setdefault(row['word'], []).append(row)
    words=[]
    for word, occurrences in by_word.items():
        definitions = list(dict.fromkeys(r['originalText'] for r in occurrences))
        primary = next((r for r in occurrences if not r['sourceDeleted']), occurrences[0])
        # Parenthetical usage restrictions are copied verbatim, not invented explanations.
        notes = list(dict.fromkeys(m for d in definitions for m in re.findall(r'[（(]([^（）()]+)[）)]', d)))
        words.append(dict(id=uid('word:'+word), word=word, pinyin='',
                          category=primary['category'], subcategory=primary['subcategory'],
                          section=primary['section'], meanings=definitions,
                          keyPoints='；'.join(notes), confusableWords=[], examples=[],
                          occurrences=occurrences, sourceDeleted=all(r['sourceDeleted'] for r in occurrences)))
    # Cross-reference explicit mentions in the source; do not call every classmate a synonym.
    for word in words:
        text='；'.join(word['meanings'])
        word['confusableWords']=[dict(word=other['word'], difference='原资料关联：'+next(d for d in word['meanings'] if other['word'] in d))
                                 for other in words if other['word'] != word['word'] and len(other['word'])>=2 and other['word'] in text]
    supplements_path=ROOT/'content/supplements.json'
    if supplements_path.exists():
        supplements=json.loads(supplements_path.read_text(encoding='utf-8'))
        for w in words:
            extra=supplements.get(w['word'],{})
            w['examples']=extra.get('examples',[])
            w['confusableWords']+=extra.get('confusableWords',[])
    question_path=ROOT/'content/questions.editorial.json'
    questions=json.loads(question_path.read_text(encoding='utf-8')) if question_path.exists() else []
    word_index={w['word']:w for w in words}
    mocks=ROOT/'content/mock-sentences.txt'
    if mocks.exists():
        for line in mocks.read_text(encoding='utf-8').splitlines():
            if not line.strip() or line.startswith('#'):
                continue
            target,sentence,distractors,rationale=line.split('|')
            assert target in word_index, target
            assert sentence.count(target)==1, target
            options=[target]+distractors.split(',')
            assert len(set(options))==4, options
            rotation=len(questions)%4
            options=options[rotation:]+options[:rotation]
            q=dict(content=sentence.replace(target,'________')+'\n填入横线部分最恰当的一项是：',
                   options=options, correctAnswer=options.index(target), explanation='解题线索：'+rationale,
                   relatedWords=[target], type='模拟题', source='自编模拟 · 语境与词义辨析', sourceURL='')
            source_notes=[name+'：'+word_index[name]['meanings'][0] for name in options if name in word_index]
            q['explanation']+='\n\n原资料对照：\n'+'\n'.join(source_notes)
            questions.append(q)
            word_index[target]['examples'].append(dict(sentence=sentence,translation='补充例句（自编），不属于 PDF 原文。'))
            for name in distractors.split(','):
                if name in word_index and word_index[name]['category']==word_index[target]['category']:
                    word_index[target]['confusableWords'].append(dict(word=name,difference='补充辨析：'+rationale))
    for q in questions:
        q['id']=uid('question:'+q['content'])
        q.setdefault('sourceURL','')
    # Definition cards cover the full source. They are labelled separately from mock exam questions.
    for w in words:
        others=[x for x in words if x['word'][0]!=w['word'][0] and x['subcategory']==w['subcategory'] and x['category']==w['category']]
        others+= [x for x in words if x['word'][0]!=w['word'][0] and x not in others]
        seed=int(hashlib.sha256(w['word'].encode()).hexdigest()[:8],16)
        choices=[w]+others[:3]
        choices=choices[seed%4:]+choices[:seed%4]
        options=[x['word'] for x in choices]
        definition=w['meanings'][0].replace(w['word'],'该词')
        explanation='原资料释义：'+w['meanings'][0]+'\n\n'+'\n'.join(x['word']+'：'+x['meanings'][0] for x in choices if x['id']!=w['id'])
        questions.append(dict(id=uid('definition:'+w['word']), content='根据原资料，下列释义对应哪个词？\n'+definition,
                              options=options, correctAnswer=options.index(w['word']), explanation=explanation,
                              relatedWords=[w['word']], type='释义自测', source='用户资料 · 第'+str(w['occurrences'][0]['page'])+'页', sourceURL=''))
    bundle=dict(schemaVersion=2, source='高频800词.pdf', sourceSHA256=hashlib.sha256((ROOT/'Words800App/Resources/source.pdf').read_bytes()).hexdigest(),
                words=words, questions=questions)
    output=ROOT/'Words800App/Resources'
    output.mkdir(parents=True,exist_ok=True)
    (output/'library.json').write_text(json.dumps(bundle,ensure_ascii=False,indent=2),encoding='utf-8')
    report=dict(pages=len(pages), sourceRows=len(rows), uniqueWords=len(words),
                deletedOnly=sum(w['sourceDeleted'] for w in words), duplicateWords={k:len(v) for k,v in by_word.items() if len(v)>1},
                byPage=dict(collections.Counter(r['page'] for r in rows)),
                byCategory=dict(collections.Counter(w['category'] for w in words)),
                questions=dict(collections.Counter(q['type'] for q in questions)),
                corrections=corrections, missingExamples=sum(not w['examples'] for w in words))
    (ROOT/'content/import-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False,indent=2))

if __name__=='__main__':
    main()
