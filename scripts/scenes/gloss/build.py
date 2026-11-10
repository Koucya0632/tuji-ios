"""Builds each scene's `gloss` (點詞翻譯) from seg/*.txt, every Japanese line
split with |, and dict.tsv (surface, reading or -, zh-Hant, zh-Hans, en). A
piece missing from the dictionary is glue: shown, not tappable.

  python3 scripts/scenes/gloss/build.py           # report what is missing
  python3 scripts/scenes/gloss/build.py --write   # write into the scene JSON

konbini-checkout's gloss was written by hand and is left as it is."""
import glob, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCENES = os.path.join(HERE, '..', '..', '..', 'Tuji', 'Resources', 'Scenes')
GLUE_OK = set('はがをにでのともかねよへや、。？！／・… SML') | {'で', 'から', 'まで', 'より', 'けど', 'ので', 'ね', 'よ', 'な', 'ー'}

words = {}
for n, raw in enumerate(open(os.path.join(HERE, 'dict.tsv'), encoding='utf-8'), 1):
    raw = raw.rstrip('\n')
    if not raw.strip() or raw.startswith('#'):
        continue
    cols = raw.split('\t')
    assert len(cols) == 5, (n, raw)
    surface, reading, h, s, e = cols
    assert surface not in words, ('duplicate', surface)
    words[surface] = {"r": None if reading == '-' else reading, "m": {"zh-Hant": h, "zh-Hans": s, "en": e}}

segs = {}
for path in sorted(glob.glob(os.path.join(HERE, 'seg', '*.txt'))):
    scene = None
    for raw in open(path, encoding='utf-8'):
        raw = raw.rstrip('\n')
        if not raw.strip():
            continue
        if raw.startswith('# '):
            scene = raw[2:].strip()
            segs.setdefault(scene, {})
            continue
        parts = raw.split('|')
        segs[scene]["".join(parts)] = parts

def lines_of(scene):
    lines = []
    for q in scene['questions']:
        lines += [p['text'] for p in q['phrasings'] if p.get('text')]
        lines.append(q['response']['ja'])
    for step in (scene.get('stage') or {}).get('steps', {}).values():
        lines += [r['ja'] for r in step.get('replies', []) if r.get('says', True)]
    return list(dict.fromkeys(lines))


wanted = {}
for f in sorted(glob.glob(os.path.join(SCENES, '*.json'))):
    sid = os.path.basename(f)[:-5]
    if sid not in ('index', 'konbini-checkout'):
        wanted[sid] = lines_of(json.load(open(f)))
problems, glue = [], {}
write = '--write' in sys.argv
for scene, lines in wanted.items():
    have = segs.get(scene, {})
    missing = [l for l in lines if l not in have]
    if scene in segs and missing:
        problems += [f'{scene}: no split for {l}' for l in missing]
    if scene not in segs or missing:
        continue
    gloss = {}
    for line in lines:
        tokens = []
        for p in have[line]:
            if p in words:
                t = {"t": p}
                if words[p]["r"]:
                    t["r"] = words[p]["r"]
                t["m"] = words[p]["m"]
                tokens.append(t)
            else:
                tokens.append({"t": p})
                if p not in GLUE_OK:
                    glue.setdefault(p, []).append(scene)
        gloss[line] = tokens
    if write:
        f = os.path.join(SCENES, scene + '.json')
        d = json.load(open(f))
        d['gloss'] = gloss
        open(f, 'w').write(json.dumps(d, indent=2, ensure_ascii=False) + '\n')

done = [s for s in wanted if s in segs and all(l in segs[s] for l in wanted[s])]
print('scenes done', len(done), '/', len(wanted), done)
for p in problems:
    print(p)
for g, where in sorted(glue.items()):
    print('glue', repr(g), sorted(set(where)))
