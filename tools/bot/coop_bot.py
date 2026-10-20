"""Headless co-op client for Jericho: speaks the mod's protocol over ENet, no game needed.

Joins a host (the real game running the mod), asks for a squad member, then sends that
body's state 20 times a second following a scripted pattern, and logs what the host sends.
Used for QA with a single game instance (see playbook/automated-qa.md).

Usage: python -I coop_bot.py [--addr 127.0.0.1] [--port 28100] [--want Black]
                             [--pattern circle|still|line] [--seconds 60] [--log bot.txt]
"""
import argparse
import ctypes
import math
import os
import sys
import time

# The co-op version the host expects in hello (lua/coop.lua Coop.VERSION).
COOP_VERSION = "0.2"

HERE = os.path.dirname(os.path.abspath(__file__))
DLL = os.path.join(HERE, '..', '..', 'native', 'build', 'enet64.dll')


class ENetAddress(ctypes.Structure):
    _fields_ = [('host', ctypes.c_uint32), ('port', ctypes.c_uint16)]


class ENetPacket(ctypes.Structure):
    _fields_ = [('referenceCount', ctypes.c_size_t), ('flags', ctypes.c_uint32),
                ('data', ctypes.POINTER(ctypes.c_uint8)), ('dataLength', ctypes.c_size_t)]


class ENetEvent(ctypes.Structure):
    _fields_ = [('type', ctypes.c_int), ('peer', ctypes.c_void_p), ('channelID', ctypes.c_uint8),
                ('data', ctypes.c_uint32), ('packet', ctypes.POINTER(ENetPacket))]


EV_CONNECT, EV_DISCONNECT, EV_RECEIVE = 1, 2, 3
FLAG_RELIABLE = 1

enet = ctypes.CDLL(DLL)
enet.enet_host_create.restype = ctypes.c_void_p
enet.enet_host_create.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_size_t, ctypes.c_uint32, ctypes.c_uint32]
enet.enet_host_connect.restype = ctypes.c_void_p
enet.enet_host_connect.argtypes = [ctypes.c_void_p, ctypes.POINTER(ENetAddress), ctypes.c_size_t, ctypes.c_uint32]
enet.enet_host_service.argtypes = [ctypes.c_void_p, ctypes.POINTER(ENetEvent), ctypes.c_uint32]
enet.enet_address_set_host.argtypes = [ctypes.POINTER(ENetAddress), ctypes.c_char_p]
enet.enet_packet_create.restype = ctypes.POINTER(ENetPacket)
enet.enet_packet_create.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_uint32]
enet.enet_peer_send.argtypes = [ctypes.c_void_p, ctypes.c_uint8, ctypes.POINTER(ENetPacket)]
enet.enet_packet_destroy.argtypes = [ctypes.POINTER(ENetPacket)]
enet.enet_peer_disconnect.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
enet.enet_host_flush.argtypes = [ctypes.c_void_p]
enet.enet_host_destroy.argtypes = [ctypes.c_void_p]


def forward(yaw_deg):
    """Engine convention, measured: Ang.y = yaw moves a body along (-sin, -cos) in x/z."""
    r = math.radians(yaw_deg)
    return -math.sin(r), -math.cos(r)


class Bot:
    RUN_SPEED = 400.0   # units/s at InCtrl_Walk = 1 (measured roughly in rom_tepidarium)

    def __init__(self, args):
        self.args = args
        self.log_file = open(args.log, 'a', encoding='utf-8') if args.log else None
        self.host = None
        self.peer = None
        self.my_id = None
        self.char = None
        self.level = None
        self.states = {}       # name -> last state fields from the host
        self.pos = None
        self.yaw = 0.0
        self.received = 0
        self.ready_at = None

    def log(self, msg):
        line = time.strftime('%H:%M:%S ') + msg
        print(line, flush=True)
        if self.log_file:
            self.log_file.write(line + '\n')
            self.log_file.flush()

    def send(self, text, reliable):
        data = text.encode('latin-1')
        pk = enet.enet_packet_create(data, len(data), FLAG_RELIABLE if reliable else 0)
        enet.enet_peer_send(self.peer, 0 if reliable else 1, pk)

    def connect(self):
        enet.enet_initialize()
        self.host = enet.enet_host_create(None, 1, 2, 0, 0)
        addr = ENetAddress()
        enet.enet_address_set_host(ctypes.byref(addr), self.args.addr.encode())
        addr.port = self.args.port
        self.peer = enet.enet_host_connect(self.host, ctypes.byref(addr), 2, 0)
        self.log(f'connecting to {self.args.addr}:{self.args.port}')

    def on_message(self, text):
        self.received += 1
        f = text.split('|')
        if f[0] == 'welcome':
            self.my_id, self.level, self.char = int(f[1]), f[2], f[3]
            if len(f) >= 8:
                self.pos = [float(f[4]), float(f[5]), float(f[6])]
                self.yaw = float(f[7])
            self.log(f'welcome id={self.my_id} level={self.level} char={self.char} pos={self.pos} yaw={self.yaw}')
            # A real client reports the level loaded; the host's scene gate and catch-up wait for it.
            self.send('lready|' + self.level, True)
        elif f[0] in ('sv', 'cp', 'level'):
            # Save vars / checkpoint / level change (coop_save.lua): log the size and level.
            extra = ''
            if f[0] == 'sv' and len(f) > 1:
                lvl = [l for l in f[1].split('%0A') if l.startswith('level%09')]
                extra = f' bytes={len(f[1])} vars={f[1].count("%0Av%09")} {lvl[0][8:] if lvl else ""}'
            self.log(f'{f[0]}{extra} {f[1] if f[0] == "level" else ""}')
            if f[0] == 'level' and len(f) > 1:
                # A real client loads the next level too and reports it (the host holds that
                # level's opening scenes until then): report after a typical load time.
                self.level = f[1]
                self.ready_at = time.time() + 10
        elif f[0] == 'own':
            if f[1] != getattr(self, 'last_own', None):
                self.last_own = f[1]
                self.log('own ' + f[1])
        elif f[0] == 's' and len(f) >= 12:
            name = f[1]
            self.states[name] = f
            if name == self.char and self.pos is None:
                # The host still sends our body until it learns we own it: start from there.
                self.pos = [float(f[2]), float(f[3]), float(f[4])]
                self.yaw = float(f[5])
                self.log(f'start pos {self.pos} yaw {self.yaw}')

    def load_path(self, path_file):
        """Read 'path|t|x|y|z|yaw|walk' lines recorded by the mod's dev 'wander' bot."""
        pts = []
        with open(path_file, encoding='utf-8', errors='replace') as f:
            for line in f:
                i = line.find('path|')
                if i < 0:
                    continue
                parts = line[i:].strip().split('|')
                t, x, y, z, yaw, walk = (float(v) for v in parts[1:7])
                pts.append((t, x, y, z, yaw, walk))
        return pts

    def step(self, t, dt):
        """Advance the scripted body and return (walk, str)."""
        p = self.args.pattern
        if p == 'replay':
            if not hasattr(self, 'path'):
                self.path = self.load_path(self.args.path)
                self.path_t0 = t
                self.path_i = 0
                self.log(f'replay {len(self.path)} points over {self.path[-1][0]:.1f}s')
            rt = t - self.path_t0
            while self.path_i + 1 < len(self.path) and self.path[self.path_i + 1][0] <= rt:
                self.path_i += 1
            _, x, y, z, yaw, walk = self.path[self.path_i]
            self.pos = [x, y, z]
            self.yaw = yaw
            return (walk if self.path_i + 1 < len(self.path) else 0.0), 0.0
        if p == 'still':
            return 0.0, 0.0
        if p == 'circle':
            self.yaw = (self.yaw + 80.0 * dt) % 360.0     # 80 deg/s
            walk = 1.0
        else:  # line: run 3 s forward, turn around
            if int(t / 3.0) != getattr(self, 'leg', 0):
                self.leg = int(t / 3.0)
                self.yaw = (self.yaw + 180.0) % 360.0
            walk = 1.0
        fx, fz = forward(self.yaw)
        self.pos[0] += fx * self.RUN_SPEED * walk * dt
        self.pos[2] += fz * self.RUN_SPEED * walk * dt
        return walk, 0.0

    def run(self):
        self.connect()
        ev = ENetEvent()
        start = time.time()
        last = start
        next_send = start
        next_report = start + 5
        while time.time() - start < self.args.seconds:
            while enet.enet_host_service(self.host, ctypes.byref(ev), 0) > 0:
                if ev.type == EV_CONNECT:
                    self.log('connected')
                    self.send('hello|' + self.args.want + '||' + COOP_VERSION, True)
                elif ev.type == EV_RECEIVE:
                    pk = ev.packet.contents
                    self.on_message(ctypes.string_at(pk.data, pk.dataLength).decode('latin-1'))
                    enet.enet_packet_destroy(ev.packet)
                elif ev.type == EV_DISCONNECT:
                    self.log('disconnected')
                    return 1
            now = time.time()
            if now >= next_send and self.char and self.pos is not None:
                dt = now - last
                last = now
                walk, strafe = self.step(now - start, dt)
                x, y, z = self.pos
                self.send(f's|{self.char}|{x:.0f}|{y:.0f}|{z:.0f}|{self.yaw:.1f}|0.0|{walk:.2f}|{strafe:.2f}|0|100|BotRun', False)
                next_send = now + 0.05
            elif now >= next_send:
                last = now
                next_send = now + 0.05
            if self.ready_at and now >= self.ready_at:
                self.ready_at = None
                self.send('lready|' + self.level, True)
                self.log('lready ' + self.level)
            if now >= next_report:
                next_report = now + 5
                seen = ','.join(sorted(self.states))
                self.log(f'report char={self.char} pos={self.pos and [round(v) for v in self.pos]} '
                         f'yaw={self.yaw:.0f} received={self.received} host_states={seen}')
            time.sleep(0.005)
        enet.enet_peer_disconnect(self.peer, 0)
        enet.enet_host_flush(self.host)
        time.sleep(0.2)
        enet.enet_host_destroy(self.host)
        self.log('done')
        return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--addr', default='127.0.0.1')
    ap.add_argument('--port', type=int, default=28100)
    ap.add_argument('--want', default='Black')
    ap.add_argument('--pattern', default='circle', choices=['circle', 'still', 'line', 'replay'])
    ap.add_argument('--path', help='log with path| lines for --pattern replay')
    ap.add_argument('--seconds', type=float, default=60)
    ap.add_argument('--log')
    sys.exit(Bot(ap.parse_args()).run())


if __name__ == '__main__':
    main()
