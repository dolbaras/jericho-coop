"""Retarget Jericho first-person scene animations (fp_<char>_*.cm3) to the
character's full-body model, and pack the results into a new BFPK archive.

How tracks bind to a model (see mod/docs/cm3-format.md): every SM3 node has an
animation slot (first u32 of its node record); a CM3 carries a byte table
(ANI remap) with remap[slot] = track + 1 (0 = node not animated). An FP
animation's table is indexed by fp_<char>.sm3 slots, which differ from
<char>.sm3 slots, so the FP file played on the full model scrambles bones.

The retargeted file keeps the FP animation's header, timing, scene data and
first frame, and gets a new remap table built for the full model (rules in
retarget()): biped/prop nodes that also exist in the FP rig take the FP track
(raw copy; FP rotation with the full model's bone offset where the FP rig has
other bone lengths; recomposed per frame where the FP rig has other parents),
any other node the character's idle (<char>_relax.cm3) animates takes the
idle's frame 0 as a constant, and the rest (face bones, effect dummies...)
stays unanimated, as in the idle.

Usage (from the jericho folder; game data is read from work/game/Data0*.packed):
  python -I mod/tools/cm3_retarget.py one levels/.../fp_delgado_play.cm3 [--out DIR] [--pack FILE]
  python -I mod/tools/cm3_retarget.py batch [--out DIR] [--pack FILE]
  python -I mod/tools/cm3_retarget.py info  <archive path or local .cm3>
  python -I mod/tools/cm3_retarget.py roundtrip [--filter GLOB]
"""
import argparse, fnmatch, glob, json, math, os, posixpath, re, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bfpk, m3d  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
JERICHO = os.path.normpath(os.path.join(HERE, '..', '..'))
DEFAULT_GAME = os.path.join(JERICHO, 'work', 'game')
DEFAULT_OUT = os.path.join(JERICHO, 'work', 'anim_rt')

# FP actor -> full-body character folder, when the names differ
FULL_MODEL_OF = {'rossnude': 'ross'}
OUT_PREFIX = 'coopbody_'
# An entry naming this builder's version in the pack; the installer rebuilds a pack without it.
PACK_MARK = 'coop/coopbody_pack_v2.txt'
# Full bodies whose props are all hidden: Ross's model holds Jones' rifle, whose textures
# live only in Jones' folder (untextured on Ross). Textures cannot be added through Pack1:
# the game hangs loading a level when Pack1 holds model textures (tested 2026-10-19, also
# with the whole folder and uncompressed).
HIDE_ALL_PROPS = {'ross'}


class GameFiles:
    """Read-only access to the game's archives by archive path (case-insensitive)."""

    def __init__(self, game_dir):
        self.index = {}
        paths = sorted(glob.glob(os.path.join(game_dir, 'Data*.packed')))
        if not paths:
            raise SystemExit(f'no Data*.packed in {game_dir}')
        for p in paths:
            version, entries = bfpk.read_index(p)
            for e in entries:
                self.index.setdefault(e[0].lower(), (p, version, e))
        self._cache = {}

    def names(self, pattern='*'):
        return sorted(n for n in self.index if fnmatch.fnmatch(n, pattern))

    def exists(self, name):
        return name.lower() in self.index

    def read(self, name):
        name = name.lower().replace('\\', '/')
        if name in self._cache:
            return self._cache[name]
        if name not in self.index:
            raise KeyError(name)
        path, version, entry = self.index[name]
        with open(path, 'rb') as f:
            data = bfpk.unpack_stored(version, bfpk.read_stored(f, version, entry))
        if len(self._cache) > 64:
            self._cache.clear()
        self._cache[name] = data
        return data


def load(files, name_or_path):
    if os.path.isfile(name_or_path):
        return bfpk.read_file(name_or_path)
    try:
        return files.read(name_or_path)
    except KeyError:
        raise SystemExit(f'{name_or_path}: neither a file nor an entry of the game archives')


# ------------------------------------------------------------ retargeting

def check_fits(cm3, sm3, what):
    """The CM3 remap table must be indexed by this model's slots."""
    slots = {n['slot'] for n in sm3['nodes']}
    want = max(slots) + 1
    if len(cm3.ani_blob) != want:
        raise ValueError(f'{what}: remap table has {len(cm3.ani_blob)} slots, model needs {want}')
    orphan = [s for s in cm3.slot_map() if s not in slots]
    if orphan:
        raise ValueError(f'{what}: remap entries for slots missing in the model: {orphan[:8]}')


def norm_name(name):
    """Name with the FP rig markers removed ("Bip FP-Cole Neck" -> "bip cole neck")."""
    return re.sub(r'(?i)(^|[ _])fps?-', lambda m: m.group(1), name).lower()


ROOT_PARENTS = ('', '_raiz_escena', 'DC_Root')


def bind_pos(node):
    return struct.unpack_from('<3f', node['fixed'], 0)


def bind_xf(node):
    return m3d.xf(struct.unpack_from('<4f', node['fixed'], 12), bind_pos(node))


def local_xfs(node, track, nframes):
    """Per-frame local transforms of a node (track channels, else bind pose)."""
    pos = track.decode(0x01) if track is not None and track.flags & 0x01 else None
    rot = track.decode(0x02) if track is not None and track.flags & 0x02 else None
    if pos is None and rot is None:
        return [bind_xf(node)] * nframes
    bq = struct.unpack_from('<4f', node['fixed'], 12)
    bp = bind_pos(node)
    return [m3d.xf(rot[i] if rot else bq, pos[i] if pos else bp) for i in range(nframes)]


def chain_xfs(chain, get_local, nframes):
    """Product of per-frame locals: chain[0] (lowest) ... chain[-1]."""
    acc = None
    for n in chain:
        loc = get_local(n)
        acc = loc if acc is None else [m3d.xf_mul(a, b) for a, b in zip(acc, loc)]
    return acc


def complete_pos_rot(track, node, idle_track):
    """Engine rule (Animacion.cpp:524, FUN_0064b7f0): a track has both a
    position and a rotation channel, or neither ("Pos && Rot", fatal).
    Adds the missing one as a constant: idle frame 0, else the bind pose.
    Returns True if a channel was added."""
    have = track.flags & 0x03
    if have in (0, 0x03):
        return False
    need = 0x03 & ~have
    if idle_track is not None and idle_track.flags & need:
        value = idle_track.value_at(need, 0)
    elif need == 0x01:
        value = bind_pos(node)
    else:
        value = struct.unpack_from('<4f', node['fixed'], 12)
    track.set_const(need, value)
    return True


def match_name(node, fp_by_name, fp_by_norm):
    fpn = fp_by_name.get(node['name'])
    if fpn is None:
        cand = fp_by_norm.get(norm_name(node['name']), [])
        fpn = cand[0] if len(cand) == 1 else None
    return fpn


def retarget(fp_cm3, fp_sm3, full_sm3, idle_cm3, max_offset=0.05, hide_props=False):
    """Return (new CM3 object, report dict).

    For every full-model node, in hierarchy order:
      1. FP node with the same name (or the same name without the FP rig
         marker "FP-"/"FPS-") and the same parent:
         - same bone offset (local bind position), or a node directly under
           the scene root -> FP track copied byte for byte;
         - other offset, inside an FP-driven chain -> FP rotation + the full
           model's offset (biped bones always; props only if the FP offset
           is static).
      2. FP node with the same name but a different parent, for a node the
         idle animates (FP rigs add or drop helper nodes such as
         "Bip Church MASTER", or hold props under DC_Root): the local
         transform is recomposed per frame so the node ends up where the FP
         rig puts it relative to the nearest common FP-driven ancestor.
      3. otherwise, a node the idle animates -> idle frame 0 (constant).
      4. otherwise -> not animated.
    Local bind rotations are not compared: they are only the pose the model
    was saved in.
    """
    check_fits(fp_cm3, fp_sm3, 'FP animation vs FP model')
    check_fits(idle_cm3, full_sm3, 'idle vs full model')
    fp_by_name = {n['name']: n for n in fp_sm3['nodes']}
    fp_by_norm = {}
    for n in fp_sm3['nodes']:
        fp_by_norm.setdefault(norm_name(n['name']), []).append(n)
    full_by_name = {n['name']: n for n in full_sm3['nodes']}
    fp_map = fp_cm3.slot_map()
    idle_map = idle_cm3.slot_map()
    primer, nframes = fp_cm3.ani_0c, fp_cm3.frames

    def fp_track(fpn):
        return fp_cm3.tracks[fp_map[fpn['slot']]] if fpn['slot'] in fp_map else None

    fp_local_cache, out_local_cache = {}, {}

    def fp_local(fpn):
        if fpn['name'] not in fp_local_cache:
            fp_local_cache[fpn['name']] = local_xfs(fpn, fp_track(fpn), nframes)
        return fp_local_cache[fpn['name']]

    out_track = {}

    def out_local(node):
        if node['name'] not in out_local_cache:
            out_local_cache[node['name']] = local_xfs(node, out_track.get(node['name']), nframes)
        return out_local_cache[node['name']]

    tracks, remap = [], bytearray(len(idle_cm3.ani_blob))
    rep = {'from_fp': [], 'from_idle': [], 'aliases': [], 'fp_rotation_only': [], 'fp_composed': [],
           'fp_rejected': [], 'not_animated': [], 'composed_chains': {}, 'pos_rot_completed': []}
    fp_driver = {}          # full node name -> FP node that drives it
    full_of_fp = {}         # FP node name -> full node name it drives
    for node in full_sm3['nodes']:
        name, slot = node['name'], node['slot']
        fpn = match_name(node, fp_by_name, fp_by_norm)
        t = fp_track(fpn) if fpn is not None else None
        if t is not None and (t.primer != primer or t.nframes != nframes):
            raise ValueError(f'{name}: FP track timing {t.primer}/{t.nframes} != {primer}/{nframes}')
        src, why = None, None
        if t is not None and norm_name(fpn['parent']) == norm_name(node['parent']):
            d = math.dist(bind_pos(fpn), bind_pos(node))
            if node['parent'] in ROOT_PARENTS or d <= max_offset:
                src = t.copy()
            else:
                why = f'{name}: bone offset differs by {d:.2f} from {fpn["name"]}'
                static = t.kind(0x01) in (None, 'const') or name.startswith('Bip ')
                if not t.flags & 0x03:
                    src, why = t.copy(), None    # no transform channels: offset irrelevant
                elif node['parent'] in fp_driver and static:
                    src = t.copy()
                    it = idle_cm3.tracks[idle_map[slot]] if slot in idle_map else None
                    pos = it.value_at(0x01, 0) if it is not None and it.flags & 0x01 else bind_pos(node)
                    src.set_const(0x01, pos)
                    rep['fp_rotation_only'].append(why)
                    why = None
        elif (t is not None and slot in idle_map and node['parent'] not in fp_driver
              and name.startswith('OB_') and node['parent'].startswith('OB_')):
            # part of a prop whose body is not FP-driven: keep it on the body
            why = f'{name}: prop part, its body {node["parent"]!r} is not FP-driven'
        elif t is not None and slot in idle_map:
            # different parent: find the nearest FP ancestor that drives a full ancestor
            full_anc = []
            p = full_by_name.get(node['parent'])
            while p is not None:
                full_anc.append(p)
                p = full_by_name.get(p['parent'])
            full_anc_names = [a['name'] for a in full_anc]
            fp_chain, g = [fpn], fp_by_name.get(fpn['parent'])
            while g is not None and full_of_fp.get(g['name']) not in full_anc_names:
                fp_chain.append(g)
                g = fp_by_name.get(g['parent'])
            if g is None:
                why = f'{name}: no common driven ancestor with {fpn["name"]}'
            else:
                a_name = full_of_fp[g['name']]
                full_chain = full_anc[:full_anc_names.index(a_name)]
                fpx = chain_xfs(fp_chain, fp_local, nframes)
                if full_chain:
                    fux = chain_xfs(full_chain, out_local, nframes)
                    loc = [m3d.xf_mul(a, m3d.xf_inv(b)) for a, b in zip(fpx, fux)]
                else:
                    loc = fpx
                values = {0x01: [x[1] for x in loc], 0x02: [m3d.xf_quat(x) for x in loc]}
                for v in (0x01, 0x02):
                    if all(values[v][0] == x for x in values[v]):
                        values[v] = values[v][0]
                for f, _, _ in m3d.CHANNELS:
                    if f not in (0x01, 0x02) and t.flags & f:
                        values[f] = t.decode(f)
                src = m3d.make_track(primer, nframes, values)
                rep['composed_chains'][name] = dict(fp=[x['name'] for x in fp_chain], fp_top=g['name'],
                                                    full=[x['name'] for x in full_chain], full_top=a_name)
                rep['fp_composed'].append(
                    f'{name}: FP chain {" < ".join(x["name"] for x in fp_chain)} < {g["name"]}; '
                    f'full chain {" < ".join([name] + [x["name"] for x in full_chain])} < {a_name}')
        elif fpn is not None and t is not None:
            why = f'{name}: parent differs (FP {fpn["parent"]!r}, full {node["parent"]!r}) and the idle does not animate it'
        if src is not None:
            fp_driver[name] = fpn['name']
            full_of_fp[fpn['name']] = name
            rep['from_fp'].append(name)
            if fpn['name'] != name:
                rep['aliases'].append(f"{name} <- {fpn['name']}")
        if why:
            rep['fp_rejected'].append(why)
        if src is None and slot in idle_map:
            it = idle_cm3.tracks[idle_map[slot]]
            if it.flags & m3d.FLAG_EVA:
                raise ValueError(f'{name}: idle track has vertex animation')
            src = m3d.make_track(primer, nframes,
                                 {f: it.value_at(f, 0) for f, _, _ in m3d.CHANNELS if it.flags & f})
            rep['from_idle'].append(name)
        if src is None:
            rep['not_animated'].append(name)
            continue
        if complete_pos_rot(src, node, idle_cm3.tracks[idle_map[slot]] if slot in idle_map else None):
            rep['pos_rot_completed'].append(name)
        out_track[name] = src
        tracks.append(src)
        if len(tracks) > 255:
            raise ValueError('more than 255 tracks: the remap table has one byte per slot')
        remap[slot] = len(tracks)
    # Props hung on the model's root (spare magazines, Delgado's belt) that the scene does
    # not move would float at their idle spot, away from the body the scene moves: hidden
    # with the visibility channel (0x80, 0..255, as the game's own files hide magazines and
    # grenades), with their sub-parts. Props on a bone (holstered pistol, flashlight,
    # rifle in hand) follow that bone and stay. hide_props hides every prop.
    hidden = set()
    for node in full_sm3['nodes']:
        name, slot = node['name'], node['slot']
        loose = name.startswith('OB_') and name not in fp_driver and node['parent'] in ROOT_PARENTS
        if not ((name.startswith('OB_') and hide_props) or loose or node['parent'] in hidden):
            continue
        hidden.add(name)
        old_t = out_track.get(name)
        values = {}
        for f in (0x01, 0x02):
            v = old_t.decode(f) if old_t is not None and old_t.flags & f else None
            if v is None:
                values[f] = bind_pos(node) if f == 0x01 else struct.unpack_from('<4f', node['fixed'], 12)
            else:
                values[f] = v[0] if all(x == v[0] for x in v) else list(v)
        values[0x80] = [0] * nframes
        new_t = m3d.make_track(primer, nframes, values)
        if old_t is not None:
            tracks[tracks.index(old_t)] = new_t
        else:
            tracks.append(new_t)
            if len(tracks) > 255:
                raise ValueError('more than 255 tracks: the remap table has one byte per slot')
            remap[slot] = len(tracks)
        out_track[name] = new_t
    rep['hidden_props'] = sorted(hidden)
    fp_names = {n['name'] for n in fp_sm3['nodes'] if n['slot'] in fp_map}
    rep['fp_tracks_unused'] = sorted(fp_names - set(full_of_fp))
    rep['fp_driver'] = fp_driver

    out = m3d.CM3.__new__(m3d.CM3)
    out.__dict__.update(fp_cm3.__dict__)       # header, SCN, ANI fields of the FP file
    out.tracks = tracks
    out.ani_blob = bytes(remap)
    rep.update(tracks=len(tracks), model_nodes=len(full_sm3['nodes']), slots=len(remap),
               frames=nframes, first_frame=primer, fps=fp_cm3.fps_value)
    return out, rep


# ------------------------------------------------------------ locomotion
# First-person scenes move the camera through the scene, and the body with it, but nobody
# animated the legs for a camera that never sees them: the full body glides with its legs
# still (TheTrap: the whole walk). Where the pelvis travels and the FP legs do not move, the
# character's own walk cycle (<char>_walk.cm3, in place) is blended onto the legs, its phase
# advanced by the distance travelled at the speed the cycle was made for.

LEG_PARTS = ('Thigh', 'Calf', 'Foot', 'Toe0')
WALK_MIN, WALK_FULL = 30.0, 70.0      # pelvis speed (units/s): no walk below, full walk above
LEGS_STILL = 25.0                     # FP thigh turning slower than this (deg/s): legs not animated
BLEND_SECONDS = 0.5


def slerp(a, b, t):
    dot = sum(x * y for x, y in zip(a, b))
    if dot < 0:
        b, dot = tuple(-x for x in b), -dot
    if dot > 0.9995:
        r = tuple(x + (y - x) * t for x, y in zip(a, b))
    else:
        th = math.acos(min(1.0, dot))
        s0, s1 = math.sin((1 - t) * th) / math.sin(th), math.sin(t * th) / math.sin(th)
        r = tuple(s0 * x + s1 * y for x, y in zip(a, b))
    n = math.sqrt(sum(x * x for x in r)) or 1.0
    return tuple(x / n for x in r)


def _worlds(sm3, cm3, nframes):
    by = {n['name']: n for n in sm3['nodes']}
    mp = cm3.slot_map()
    cache = {}

    def local(n):
        if n['name'] not in cache:
            t = cm3.tracks[mp[n['slot']]] if n['slot'] in mp else None
            cache[n['name']] = local_xfs(n, t, nframes)
        return cache[n['name']]

    def world(name):
        chain, n = [], by.get(name)
        while n is not None:
            chain.append(n)
            n = by.get(n['parent'])
        return chain_xfs(chain, local, nframes) if chain else None
    return by, local, world


def walk_speed(full_sm3, walk_cm3, pre):
    """Speed the walk cycle is made for: its pelvis travel (cycles with root motion), else how
    fast the supporting foot slides back (cycles made in place)."""
    nf, fps = walk_cm3.frames, walk_cm3.fps_value or 30
    _, _, world = _worlds(full_sm3, walk_cm3, nf)
    pel = world(f'{pre} Pelvis')
    if pel:
        a, b = pel[0][1], pel[-1][1]
        v = math.hypot(b[0] - a[0], b[2] - a[2]) * fps / max(1, nf - 1)
        if v > 20:
            return v
    feet = [world(f'{pre} {s} Foot') for s in 'LR']
    if not all(feet):
        return None
    speeds = []
    for f in range(nf - 1):
        low = min((0, 1), key=lambda i: feet[i][f][1][1])
        a, b = feet[low][f][1], feet[low][f + 1][1]
        speeds.append(math.hypot(b[0] - a[0], b[2] - a[2]) * fps)
    speeds.sort()
    v = speeds[len(speeds) // 2]
    return v if v > 20 else None


def add_locomotion(out, full_sm3, walk_cm3, rep):
    nf, fps = out.frames, out.fps_value or 30
    pel_node = next((n for n in full_sm3['nodes'] if n['name'].endswith(' Pelvis')), None)
    if pel_node is None or walk_cm3 is None:
        return
    pre = pel_node['name'][:-len(' Pelvis')]
    vref = walk_speed(full_sm3, walk_cm3, pre)
    if not vref:
        rep['locomotion'] = 'no walk speed'
        return
    by, local, world = _worlds(full_sm3, out, nf)
    pel = world(pel_node['name'])
    k = 3
    speed, still = [], []
    thighs = [by.get(f'{pre} {s} Thigh') for s in 'LR']
    if not all(thighs):
        return
    tl = [local(t) for t in thighs]
    for f in range(nf):
        a, b = max(0, f - k), min(nf - 1, f + k)
        dt = (b - a) / fps or 1.0
        p0, p1 = pel[a][1], pel[b][1]
        speed.append(math.hypot(p1[0] - p0[0], p1[2] - p0[2]) / dt)
        turn = max(m3d.quat_angle_deg(m3d.xf_quat(x[a]), m3d.xf_quat(x[b])) for x in tl) / dt
        still.append(turn < LEGS_STILL)
    raw = [min(1.0, max(0.0, (v - WALK_MIN) / (WALK_FULL - WALK_MIN))) if st else 0.0
           for v, st in zip(speed, still)]
    half = max(1, int(BLEND_SECONDS * fps / 2))
    w = [sum(raw[max(0, f - half):f + half + 1]) / len(raw[max(0, f - half):f + half + 1]) for f in range(nf)]
    if max(w) < 0.05:
        return
    # walk cycle rotations of the leg bones
    wnf, wfps = walk_cm3.frames, walk_cm3.fps_value or 30
    wmap, omap = walk_cm3.slot_map(), out.slot_map()
    parts = []
    for s in 'LR':
        for part in LEG_PARTS:
            n = by.get(f'{pre} {s} {part}')
            if n is None or n['slot'] not in wmap or n['slot'] not in omap:
                continue
            wt = walk_cm3.tracks[wmap[n['slot']]]
            if not wt.flags & 0x02:
                continue
            parts.append((n, wt.decode(0x02)))
    if not parts:
        return
    phase, ph = [], 0.0
    for f in range(nf):
        phase.append(ph)
        ph = (ph + speed[f] / vref * wfps / fps) % wnf
    for n, wrot in parts:
        old = out.tracks[omap[n['slot']]]
        rot = old.decode(0x02) or [struct.unpack_from('<4f', n['fixed'], 12)] * nf
        pos = old.decode(0x01) or [bind_pos(n)] * nf
        new_rot = []
        for f in range(nf):
            if w[f] <= 0.001:
                new_rot.append(rot[f])
                continue
            i0 = int(phase[f]) % wnf
            i1 = (i0 + 1) % wnf
            wq = slerp(wrot[i0], wrot[i1], phase[f] - int(phase[f]))
            new_rot.append(slerp(rot[f], wq, w[f]))
        values = {0x01: pos[0] if all(x == pos[0] for x in pos) else list(pos), 0x02: new_rot}
        for fl, _, _ in m3d.CHANNELS:
            if fl not in (0x01, 0x02) and old.flags & fl:
                values[fl] = old.decode(fl)
        new = m3d.make_track(old.primer, nf, values)
        out.tracks[omap[n['slot']]] = new
        rep.setdefault('locomotion_nodes', []).append(n['name'])
    rep['locomotion'] = dict(walk_speed=round(vref), frames_walking=sum(1 for x in w if x > 0.5), frames=nf)


# ------------------------------------------------------------ steadying
# A first-person scene shakes its camera (the helicopter's vibration, steps, hits) through
# the body: root, spine, neck and head jitter frame to frame. Seen on the full body that is a
# shivering man. The core of the body is smoothed over STEADY_SECONDS (a centred moving
# average of rotations and of the root's position); slower motion stays.

STEADY_PARTS = ('', ' Pelvis', ' Spine', ' Spine1', ' Spine2', ' Neck', ' Head')
STEADY_SECONDS = 0.3


def _avg_quat(qs):
    ref = qs[len(qs) // 2]
    acc = [0.0, 0.0, 0.0, 0.0]
    for q in qs:
        sgn = 1.0 if sum(a * b for a, b in zip(q, ref)) >= 0 else -1.0
        for i in range(4):
            acc[i] += sgn * q[i]
    n = math.sqrt(sum(x * x for x in acc)) or 1.0
    return tuple(x / n for x in acc)


def steady_core(out, full_sm3, rep):
    nf, fps = out.frames, out.fps_value or 30
    pel = next((n for n in full_sm3['nodes'] if n['name'].endswith(' Pelvis')), None)
    if pel is None or nf < 5:
        return
    pre = pel['name'][:-len(' Pelvis')]
    by = {n['name']: n for n in full_sm3['nodes']}
    omap = out.slot_map()
    half = max(1, int(STEADY_SECONDS * fps / 2))
    done = []
    for part in STEADY_PARTS:
        n = by.get(pre + part)
        if n is None or n['slot'] not in omap:
            continue
        old = out.tracks[omap[n['slot']]]
        if not old.flags & 0x02 or old.kind(0x02) == 'const':
            continue
        rot = old.decode(0x02)
        new_rot = [_avg_quat(rot[max(0, f - half):f + half + 1]) for f in range(nf)]
        pos = old.decode(0x01) or [bind_pos(n)] * nf
        if part == '' and old.kind(0x01) not in (None, 'const'):
            new_pos = []
            for f in range(nf):
                win = pos[max(0, f - half):f + half + 1]
                new_pos.append(tuple(sum(p[i] for p in win) / len(win) for i in range(3)))
            pos = new_pos
        values = {0x01: pos[0] if all(x == pos[0] for x in pos) else list(pos), 0x02: new_rot}
        for fl, _, _ in m3d.CHANNELS:
            if fl not in (0x01, 0x02) and old.flags & fl:
                values[fl] = old.decode(fl)
        out.tracks[omap[n['slot']]] = m3d.make_track(old.primer, nf, values)
        rep.setdefault('locomotion_nodes', []).append(n['name'])
        done.append(n['name'])
    rep['steadied'] = done


def check_coverage(c):
    """Every channel must cover the animation's frames the way the game's own files do
    (checked against all 3633 shipped CM3: no stream ends past nframes, every stream
    has >= 1 key, quantised and plain streams have exactly header + count elements)."""
    for i, t in enumerate(c.tracks):
        assert t.nframes == c.frames and t.primer == c.ani_0c, f'track {i}: timing'
        for f, elt, nm in m3d.CHANNELS:
            k = t.kind(f)
            if k is None:
                continue
            raw = t.data[f]
            if k == 'const':
                assert len(raw) == (elt + 3) & ~3, f'track {i} {nm}: const size'
            elif k == 'frames':
                assert len(raw) == (t.nframes * elt + 3) & ~3, f'track {i} {nm}: per-frame size'
            else:
                words, sflags, start, cnt = struct.unpack_from('<4H', raw, 0)
                assert words * 4 == len(raw) == t.stream_size[f], f'track {i} {nm}: stream size'
                assert cnt >= 1 and start + cnt <= t.nframes, f'track {i} {nm}: keys {start}+{cnt} > {t.nframes}'
                assert sflags in (0, 0x8000), f'track {i} {nm}: stream flags {sflags:#x}'
                if sflags & 0x8000:
                    assert f in (0x01, 0x02), f'track {i} {nm}: quantised {nm}'
                    body = 16 + cnt * (6 if f == 0x01 else 4)
                else:
                    body = cnt * elt
                assert (8 + body + 3) & ~3 == len(raw), f'track {i} {nm}: stream body'
            vals = t.decode(f)
            assert len(vals) == t.nframes, f'track {i} {nm}: decodes {len(vals)} frames'


def validate(data, full_sm3, fp_sm3, fp_cm3, idle_cm3, rep):
    """Parse the serialized output back and check it against its sources."""
    c = m3d.CM3(data)
    assert c.serialize() == data, 'output does not re-serialize identically'
    check_fits(c, full_sm3, 'output vs full model')
    assert c.frames == fp_cm3.frames and c.fps == fp_cm3.fps and c.ani_0c == fp_cm3.ani_0c
    assert c.ani_vec == fp_cm3.ani_vec and c.head == fp_cm3.head
    check_coverage(c)
    smap = c.slot_map()
    for i, t in enumerate(c.tracks):
        # Animacion.cpp:524 "Pos && Rot": both transform channels or neither
        assert t.flags & 0x03 in (0, 0x03), f'track {i}: position without rotation or vice versa'
        assert t.nframes == c.frames and t.primer == c.ani_0c, f'track {i}: timing'
    assert len(smap) == len(c.tracks) == rep['tracks'], 'every track must be referenced once'
    assert sorted(smap.values()) == list(range(len(c.tracks)))
    by_name = {n['name']: n for n in full_sm3['nodes']}
    hidden = set(rep.get('hidden_props', []))
    animated = set(rep['from_fp']) | set(rep['from_idle']) | hidden
    assert len(animated) == len(c.tracks)
    for name in hidden:
        t = c.tracks[smap[by_name[name]['slot']]]
        assert t.flags & 0x80 and set(t.decode(0x80)) == {0}, name
    fp_names = {n['name']: n for n in fp_sm3['nodes']}
    fpm, idm = fp_cm3.slot_map(), idle_cm3.slot_map()
    rot_only = {x.split(':')[0] for x in rep['fp_rotation_only']}
    composed = {x.split(':')[0] for x in rep['fp_composed']}
    walked = set(rep.get('locomotion_nodes', []))
    for name in rep['from_fp']:
        if name in hidden:
            continue
        t = c.tracks[smap[by_name[name]['slot']]]
        if name in walked:
            # legs blended with the walk cycle: the FP position kept, a rotation per frame
            assert t.flags & 0x03 == 0x03 and t.kind(0x02) == 'stream', name
            continue
        s = fp_cm3.tracks[fpm[fp_names[rep['fp_driver'][name]]['slot']]]
        if name in composed:
            # node relative to the common ancestor must match the FP rig
            ch = rep['composed_chains'][name]
            if walked & set(ch['full']):
                continue   # rides on a walking leg (a holster): follows the new leg
            fpn = {n['name']: n for n in fp_sm3['nodes']}
            for fr in sorted({0, c.frames // 2, c.frames - 1}):
                def at(nodes, cm, names):
                    m = cm.slot_map()
                    acc = None
                    for nm in names:
                        nd = nodes[nm]
                        tr = cm.tracks[m[nd['slot']]] if nd['slot'] in m else None
                        loc = local_xfs(nd, tr, c.frames)[fr] if tr is not None else bind_xf(nd)
                        acc = loc if acc is None else m3d.xf_mul(acc, loc)
                    return acc
                want = at(fpn, fp_cm3, ch['fp'])
                got = at(by_name, c, [name] + ch['full'])
                assert math.dist(want[1], got[1]) < 0.05, name
                assert m3d.quat_angle_deg(m3d.xf_quat(want), m3d.xf_quat(got)) < 0.05, name
            continue
        if name in rep['pos_rot_completed']:
            for f, _, _ in m3d.CHANNELS:
                if s.flags & f and not (name in rot_only and f == 0x01):
                    assert t.data.get(f) == s.data.get(f), name
            assert t.flags & 0x03 == 0x03, name
        elif name in rot_only:
            for f, _, _ in m3d.CHANNELS:
                if f != 0x01:
                    assert t.data.get(f) == s.data.get(f), name
            assert t.kind(0x01) == 'const', name
        else:
            assert t.nabk() == s.nabk() and t.nam() == s.nam(), name
    for name in rep['from_idle']:
        if name in hidden or name in walked:
            continue
        t = c.tracks[smap[by_name[name]['slot']]]
        s = idle_cm3.tracks[idm[by_name[name]['slot']]]
        for f, _, _ in m3d.CHANNELS:
            if s.flags & f:
                b = s.value_at(f, 0)
                for a in (t.value_at(f, 0), t.value_at(f, t.nframes - 1)):
                    if f == 0x02:
                        assert m3d.quat_angle_deg(a, b) < 0.01, name
                    elif f == 0x01:
                        assert max(abs(x - y) for x, y in zip(a, b)) < 1e-3, name
                    else:
                        assert abs(a - b) < 1e-5, name
    return c


def plan_for(fp_path):
    """Archive paths needed for one FP animation."""
    d, fname = posixpath.split(fp_path.lower().replace('\\', '/'))
    if not fname.startswith('fp_'):
        raise ValueError(f'{fname}: not an fp_* animation')
    return d, fname


def fp_actor_of(fname, files):
    actors = sorted({n.split('/')[2][3:] for n in files.names('models/fpactor/fp_*/fp_*.sm3')},
                    key=len, reverse=True)
    for a in actors:
        if fname.startswith(f'fp_{a}_') or fname == f'fp_{a}.cm3':
            return a
    raise ValueError(f'{fname}: no models/fpactor/fp_<char> model matches')


def do_one(files, fp_path, out_dir, models_cache):
    d, fname = plan_for(fp_path)
    actor = fp_actor_of(fname, files)
    char = FULL_MODEL_OF.get(actor, actor)
    paths = dict(fp_anim=f'{d}/{fname}',
                 fp_model=f'models/fpactor/fp_{actor}/fp_{actor}.sm3',
                 full_model=f'models/chars/{char}/{char}.sm3',
                 idle=f'models/chars/{char}/anm/{char}_relax.cm3')
    for k, p in paths.items():
        if not files.exists(p):
            raise ValueError(f'{k}: {p} not in the archives')

    def model(p):
        if p not in models_cache:
            models_cache[p] = m3d.sm3_nodes(files.read(p))
        return models_cache[p]

    fp_cm3 = m3d.CM3(files.read(paths['fp_anim']))
    fp_sm3, full_sm3 = model(paths['fp_model']), model(paths['full_model'])
    idle_cm3 = m3d.CM3(files.read(paths['idle']))
    out, rep = retarget(fp_cm3, fp_sm3, full_sm3, idle_cm3, hide_props=char in HIDE_ALL_PROPS)
    steady_core(out, full_sm3, rep)
    walk_path = f'models/chars/{char}/anm/{char}_walk.cm3'
    if files.exists(walk_path):
        walk_cm3 = m3d.CM3(files.read(walk_path))
        check_fits(walk_cm3, full_sm3, 'walk vs full model')
        add_locomotion(out, full_sm3, walk_cm3, rep)
    data = out.serialize()
    validate(data, full_sm3, fp_sm3, fp_cm3, idle_cm3, rep)
    out_name = f'{d}/{OUT_PREFIX}{fname[3:]}'
    if files.exists(out_name):
        raise ValueError(f'{out_name} already exists in the game archives')
    rep.update(paths, output=out_name, actor=actor, char=char, bytes=len(data))
    if out_dir:
        dst = os.path.join(out_dir, *out_name.split('/'))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, 'wb') as f:
            f.write(data)
    return out_name, data, rep


def write_pack(path, items):
    bfpk.write_archive(path, items)
    version, entries = bfpk.read_index(path)
    with open(path, 'rb') as f:
        for (name, data), e in zip(items, entries):
            assert e[0] == name and e[1] == len(data)
            assert bfpk.unpack_stored(version, bfpk.read_stored(f, version, e)) == data
            if name.endswith('.cm3'):
                m3d.CM3(data)
    return len(entries)


def summary(rep):
    return (f"{rep['output']}: {rep['tracks']} tracks ({len(rep['from_fp'])} FP, "
            f"{len(rep['from_idle'])} idle), model {rep['model_nodes']} nodes / {rep['slots']} slots, "
            f"{rep['frames']} frames @ {rep['fps']:g} fps")


def cmd_one(a, files):
    out_dir = os.path.join(a.out, 'out')
    name, data, rep = do_one(files, a.fp_anim, out_dir, {})
    print(summary(rep))
    print('  filled from idle frame 0:', ', '.join(rep['from_idle']))
    print('  not animated:', ', '.join(rep['not_animated']))
    if rep['fp_composed']:
        print('  recomposed for a different parent chain:', '; '.join(rep['fp_composed']))
    if rep['fp_rotation_only']:
        print('  FP rotation with the full model offset:', '; '.join(rep['fp_rotation_only']))
    if rep['fp_rejected']:
        print('  FP track not used:', '; '.join(rep['fp_rejected']))
    if rep['aliases']:
        print('  matched by name without the FP rig marker:', ', '.join(rep['aliases']))
    print('  FP tracks without a full-model node:', ', '.join(rep['fp_tracks_unused']))
    with open(os.path.join(a.out, 'report_' + posixpath.basename(name) + '.json'), 'w') as f:
        json.dump(rep, f, indent=1)
    if a.pack:
        n = write_pack(a.pack, [(name, data)])
        print(f'packed {n} file(s) into {a.pack}')


# Full-body models the mod shows in first-person scenes (lua/coop_scenes.lua S.BODY_MODEL).
STANDIN_MODELS = ('black', 'church', 'cole', 'delgado', 'jones', 'rawlings', 'trueross')


def texture_fixes(files):
    """Not used (Pack1 cannot carry textures, see HIDE_ALL_PROPS). Textures a stand-in model names but its own dds folder lacks (TrueRoss holds Jones'
    rifle: OB_Jones_01-02_Fusil-*), copied from the folder that has them, under the path
    the engine looks in. Returns [(archive name, data)]."""
    have = {}
    for n in files.names('models/*/*/dds/*'):
        have.setdefault(posixpath.basename(n), n)
    out = []
    for m in STANDIN_MODELS:
        sm = f'models/chars/{m}/{m}.sm3'
        if not files.exists(sm):
            continue
        refs = sorted({x.decode().lower() for x in
                       re.findall(rb'[A-Za-z0-9_\-.]{3,60}\.bmp', files.read(sm), re.I)})
        for r in refs:
            stem = r[:-4]
            if stem.startswith('envmap_'):
                continue
            own = [f'models/chars/{m}/dds/{stem}.dds1', f'models/chars/{m}/dds/{stem}.dds']
            if any(files.exists(x) for x in own):
                continue
            for ext in ('.dds1', '.dds'):
                src = have.get(stem + ext)
                if src:
                    out.append((f'models/chars/{m}/dds/{stem}{ext}', files.read(src)))
                    print(f'texture {m}: {stem}{ext} from {src}')
                    break
    return out


def cmd_batch(a, files):
    out_dir = os.path.join(a.out, 'out')
    items, reports, errors, cache = [], [], [], {}
    for p in files.names('levels/*/map/*/*anm/fp_*.cm3'):
        try:
            name, data, rep = do_one(files, p, out_dir, cache)
        except (ValueError, AssertionError, m3d.FormatError) as e:
            errors.append((p, str(e)))
            print(f'SKIP {p}: {e}')
            continue
        items.append((name, data))
        reports.append(rep)
        print(summary(rep))
    with open(os.path.join(a.out, 'batch_report.json'), 'w') as f:
        json.dump({'files': reports, 'errors': errors}, f, indent=1)
    if a.pack and items:
        # what built this pack (the installer rebuilds an older one): PACK_MARK
        n = write_pack(a.pack, items + [(PACK_MARK, PACK_MARK.encode('latin-1'))])
        print(f'packed {n} file(s) into {a.pack} ({os.path.getsize(a.pack)} bytes)')
    bad = 0
    for name, data in items:
        check_coverage(m3d.CM3(data))
    for name, data in items:
        c = m3d.CM3(data)
        bad += sum(1 for t in c.tracks if t.flags & 0x03 not in (0, 0x03))
    print(f'{len(items)} generated, {len(errors)} skipped; '
          f'{sum(len(m3d.CM3(d).tracks) for _, d in items)} tracks, {bad} violate "Pos && Rot"; '
          f'{sum(len(r["pos_rot_completed"]) for r in reports)} tracks completed with a constant channel; '
          f'frame coverage of every channel checked')


def cmd_info(a, files):
    c = m3d.CM3(load(files, a.file))
    vec = struct.unpack('<3f', c.ani_vec)
    print(f'frames {c.frames} (first {c.ani_0c}) fps {c.fps_value:g} tracks {len(c.tracks)} '
          f'remap slots {len(c.ani_blob)} flag {c.ani_bool} vec {vec}')
    names = {}
    if a.model:
        names = {n['slot']: n['name'] for n in m3d.sm3_nodes(load(files, a.model))['nodes']}
    inv = {t: s for s, t in c.slot_map().items()}
    for i, t in enumerate(c.tracks):
        s = inv.get(i)
        ch = ' '.join(f'{nm}:{t.kind(f)}' for f, _, nm in m3d.CHANNELS if t.flags & f)
        print(f'{i:4d} slot {s if s is not None else "-":>4} {names.get(s, ""):40s} {ch}')


def cmd_roundtrip(a, files):
    ok = bad = 0
    for n in files.names(a.filter):
        d = files.read(n)
        try:
            same = m3d.CM3(d).serialize() == d
        except m3d.FormatError as e:
            same = False
            print(f'ERROR {n}: {e}')
        ok += same
        bad += not same
        if not same:
            print(f'DIFF {n}')
    print(f'{ok} identical, {bad} different')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--game', default=DEFAULT_GAME, help='folder with Data0*.packed')
    ap.add_argument('--out', default=DEFAULT_OUT, help='output folder (files go to OUT/out/...)')
    sub = ap.add_subparsers(dest='cmd', required=True)
    p = sub.add_parser('one')
    p.add_argument('fp_anim')
    p.add_argument('--pack')
    p = sub.add_parser('batch')
    p.add_argument('--pack', default=os.path.join(DEFAULT_OUT, 'CoopAnims.packed'))
    p = sub.add_parser('info')
    p.add_argument('file')
    p.add_argument('--model', help='SM3 (archive path or file) to name the tracks')
    p = sub.add_parser('roundtrip')
    p.add_argument('--filter', default='*.cm3')
    a = ap.parse_args()
    files = GameFiles(a.game)
    os.makedirs(a.out, exist_ok=True)
    {'one': cmd_one, 'batch': cmd_batch, 'info': cmd_info, 'roundtrip': cmd_roundtrip}[a.cmd](a, files)


if __name__ == '__main__':
    main()
