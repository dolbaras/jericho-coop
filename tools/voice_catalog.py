"""Catalog the game's voice lines: every .ogg in Voices/<lang>.packed with its subtitle
text from the language table, so new story beats can be built from lines that exist.

Writes a TSV (keep it private: it contains the game's text) with columns
  file, variant, speaker, key, text
variant is "radio" for the "_"-suffixed copies (radio-filtered versions), else "plain".

Usage: python -I voice_catalog.py <game dir> <language table .dec> <out.tsv>
"""
import os, re, struct, sys


def bfpk_names(path):
    with open(path, 'rb') as f:
        magic, _version, count = struct.unpack('<4sII', f.read(12))
        if magic != b'BFPK':
            raise ValueError(f'{path}: not a BFPK archive')
        for _ in range(count):
            (n,) = struct.unpack('<I', f.read(4))
            name = f.read(n).decode('latin-1')
            f.read(8)
            yield name


def language_table(path, encoding='cp1251'):
    table = {}
    with open(path, 'rb') as f:
        for raw in f.read().decode(encoding, errors='replace').splitlines():
            if '\t' not in raw:
                continue
            key, text = raw.split('\t', 1)
            table[key.strip().lower()] = text.strip()
    return table


def main():
    game, lang, out = sys.argv[1:4]
    voices = os.path.join(game, 'Voices')
    table = language_table(lang)
    rows, matched = [], 0
    for arc in sorted(os.listdir(voices)):
        if not arc.lower().endswith('.packed'):
            continue
        for name in bfpk_names(os.path.join(voices, arc)):
            base = os.path.splitext(os.path.basename(name))[0]
            variant = 'radio' if base.endswith('_') else 'plain'
            key = base.rstrip('_')
            text = table.get(key)
            if text is None:
                # Keys in the table sometimes keep a "NOVOICE"/"VOICE" infix or differ in case.
                alt = re.sub(r'^(hint|chat|radio)_', r'\1_', key)
                text = table.get(alt, '')
            if text:
                matched += 1
            speaker = key.split('_')[1] if key.count('_') >= 1 else ''
            rows.append((name, variant, speaker, key, text.replace('\t', ' ')))
    with open(out, 'w', encoding='utf-8') as f:
        f.write('file\tvariant\tspeaker\tkey\ttext\n')
        for r in rows:
            f.write('\t'.join(r) + '\n')
    print(f'{len(rows)} voice files, {matched} with subtitle text -> {out}')


if __name__ == '__main__':
    main()
