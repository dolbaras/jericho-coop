"""Test console: run Lua in a test game on this PC started with JERICHO_CONSOLE=<port>
(run_single.ps1 -Console); lua/dev.lua runs it between frames and sends back what it prints
and returns. The game listens on 127.0.0.1 only (on the N100: luacon.ps1 there, over ssh).

Usage: python -I luacon.py [port] "Lua"      (default 28777)
       python -I luacon.py [port] -          (Lua from stdin)
An expression is returned as is: luacon.py "Game.UsrEntity(0).Name"
"""
import socket, sys


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    host, port = '127.0.0.1', 28777
    if len(args) > 1:
        port = int(args.pop(0))
    code = sys.stdin.read() if args[0] == '-' else args[0]
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(5)
    s.sendto(code.encode('cp1251', 'replace'), (host, port))
    try:
        data, _ = s.recvfrom(65536)
    except socket.timeout:
        print('no answer (is the game running with JERICHO_CONSOLE, past its first frame?)')
        return 1
    print(data.decode('cp1251', 'replace'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
