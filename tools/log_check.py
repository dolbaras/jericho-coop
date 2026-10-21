"""Check game logs (game.log next to coop.txt in a run folder) for what a player would see go
wrong: engine errors ("Error at"), and textures the engine could not find (drawn checkered or
as a flat stand-in colour). The game itself misses some textures; those are listed in
docs/known-missing-textures.txt, and only new ones are reported.

Usage: python -I log_check.py <game.log or run folder>... [--update]
  --update   add the missing textures found to the known list (after checking them by eye)
Exit code 1 when an error or a new missing texture is found.
"""
import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
KNOWN = os.path.join(HERE, '..', 'docs', 'known-missing-textures.txt')
TEX = re.compile(r"Texture not found: '([^']*)'")


def load_known():
    if not os.path.exists(KNOWN):
        return set()
    with open(KNOWN, encoding='utf-8') as f:
        return {ln.strip().lower() for ln in f if ln.strip() and not ln.startswith('#')}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    update = '--update' in sys.argv
    known = load_known()
    found, errors = set(), []
    for a in args:
        p = os.path.join(a, 'game.log') if os.path.isdir(a) else a
        if not os.path.exists(p):
            continue
        with open(p, encoding='latin-1') as f:
            for ln in f:
                m = TEX.search(ln)
                if m:
                    found.add(m.group(1).strip().lower())
                elif 'Error at' in ln:
                    errors.append(ln.strip())
    new = sorted(found - known)
    print(f'game.log: {len(errors)} engine error(s), {len(found)} missing texture(s), {len(new)} new')
    for e in errors[:10]:
        print('  error:', e)
    for t in new:
        print('  new missing texture:', t)
    if update and new:
        with open(KNOWN, 'a', encoding='utf-8') as f:
            for t in new:
                f.write(t + '\n')
        print(f'added {len(new)} to {os.path.normpath(KNOWN)}')
        return 0
    return 1 if errors or new else 0


if __name__ == '__main__':
    sys.exit(main())
