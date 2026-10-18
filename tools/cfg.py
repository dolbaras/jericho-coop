"""Read or set GVars in Jericho's game.cfg (%APPDATA%\\Codemasters\\Clive Barker's Jericho).

Lines look like `Name    = value    ### comment`. Unknown names are appended before `## End`.
Usage: cfg.py get Name...  |  cfg.py set Name=value...
"""
import os, re, sys

CFG = os.path.join(os.environ['APPDATA'], 'Codemasters', "Clive Barker's Jericho", 'game.cfg')
LINE = re.compile(r'^(?P<name>[A-Za-z_][\w]*)(?P<pad>\s*)=\s(?P<value>.*?)(?P<tail>\s+###.*)?$')


def load():
    with open(CFG, 'r', encoding='latin-1', newline='') as f:
        return f.read().split('\n')


def save(lines):
    with open(CFG, 'w', encoding='latin-1', newline='') as f:
        f.write('\n'.join(lines))


def main():
    cmd, args = sys.argv[1], sys.argv[2:]
    lines = load()
    if cmd == 'get':
        for line in lines:
            m = LINE.match(line.rstrip('\r'))
            if m and (not args or m['name'] in args):
                print(f"{m['name']} = {m['value'].strip()}")
        return
    for arg in args:
        name, value = arg.split('=', 1)
        for i, line in enumerate(lines):
            cr = '\r' if line.endswith('\r') else ''
            m = LINE.match(line.rstrip('\r'))
            if m and m['name'] == name:
                tail = m['tail'] or ''
                lines[i] = f"{name}{m['pad']}= {value:<36}{tail.lstrip() and ' ' + tail.lstrip()}{cr}"
                break
        else:
            end = next(i for i, l in enumerate(lines) if l.startswith('## End'))
            cr = '\r' if lines[end].endswith('\r') else ''
            lines[end:end] = [f'{name:<30} = {value}{cr}', cr]
    save(lines)


if __name__ == '__main__':
    main()
