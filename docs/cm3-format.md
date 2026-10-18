# Jericho animation (CM3) and model (SM3) format

Reverse engineered from the retail files and from `Jericho.exe`
(`.\Engine\lee_M3D.cpp`, `Escena.cpp`, `Animacion.cpp`, `AnimGrupo.cpp`; addresses below
are virtual addresses in the retail exe). Code: `tools/m3d.py` (reader/writer, decoder),
`tools/cm3_retarget.py` (retarget + batch), `tools/bfpk.py` (archives).

**Labels:** **[V]** verified on data (round trip, statistics) or read in the exe code;
**[G]** guessed / inferred, not proven. Everything is little endian.

---

## 1. Archives (`Data0*.packed`, BFPK)

- Header `"BFPK"`, u32 version, u32 count; entries {u32 name_len, name, u32 size, u32 offset}. [V]
- **Version 1** (Data00..05): `size` is the **uncompressed** size. The stored record at
  `offset` is `u32 compressed_size` + one zlib stream of that many bytes. [V]
  - zlib level 6 (Python's default) reproduces the stored bytes exactly (1402 of 1402
    sampled records). [V]
  - The old `bfpk.py --extract` read `size` bytes from `offset`, so earlier extracts
    (`work/extracted_anm`, `work/extracted_mdl`) are record + bytes of the next entry.
    `zlib.decompress(data[4:])` still works on them because zlib ignores trailing data.
- **Version 0** (Music.packed): entries stored raw, `size` bytes. [V]
- Mounting (`FUN_00410be0`): opens `<name>.packed`, accepts version 0 or 1, and adds each
  entry to a hash index only if the name is not indexed yet, so the first archive that has
  a name wins. A new archive must use new names. [V for the code, G for "first wins"]
- Which archives are mounted: the names `Data`, `Voices`, `Music`, `Pack`, `Pack1` are
  pushed from SecuROM-wrapped code at 0x11e3b6f..0x11e3c86, which Ghidra does not analyse.
  `Pack`/`Pack1` may be config keys for extra archives. [G] **Open question:** how to make
  the game mount `CoopAnims.packed`. The mod's `dinput8.dll` could call `FUN_00410be0`.

## 2. Common encodings

- **Chunk:** 4-byte tag (`"SCN\0"`, `"ANI\0"`, ...) + u32. The u32 is 0 for plain chunks.
  Only `NABK` is a "sized" chunk: its u32 is the payload size. [V]
- **String:** u32 length including the NUL, then the bytes; an empty string is a single
  u32 0. [V]
- **INI object** (FileINI): u32 present (0/1); if 1: `"INI\0"`, u32 0, u32 1, u32 n, then n
  strings, one per line. Used for the model's `[Model]`, `[RenameNodes]`, `[SuperNodes]`...
  sections and for per-node notes. [V]

## 3. SM3 (model / static scene)

```
"SM3\0" u32 0  u32 0x65226E (M3D version)  u32 hash  u32 hash
"SCN\0" u32 0  u32 1
  string, string (scene root name, e.g. "DC_Root"), INI (FileINI)
  8 + 8 + 24 + 12 + 4 bytes                                     [G: scene settings]
  INI
  u32 materials, materials...                                   (not parsed)
  u32 1, u32 node_count
  node_count x node record
  u32 has_animation [, ANI chunk]
```

Node record (`Escena.cpp`, writer `FUN_005f5bf0`) [V for the layout]:

| bytes | field (EscenaNodo offset) | meaning |
|---|---|---|
| 4 | +0x48 | **animation slot**: index into a CM3's remap table [V] |
| 4 | +0x4c | second index (0..n-1) [G: order of animatable nodes] |
| 4 | +0x50 | -1 in all files seen |
| 4 | +0x18 | flags [G] |
| 4 | +0x1c | 3 or 11 [G] |
| 4 | +0x54 | 0 / -1 / -129 [G] |
| string | | node name |
| string | +0x14 | parent node name ("" for the root) |
| 12 | +0x20 | local bind position (3 f32) [V] |
| 16 | +0x2c | local bind rotation, quaternion x y z w [V] |
| 4 | +0x3c | [G] |
| 64 + 64 | +0x64, +0xa4 | two 4x4 matrices [G: world / inverse] |
| 16 + 12 | +0xe4, +0xf4 | [G] |
| INI | +0x100 | node notes (e.g. "Este Nodo NO SE BORRA!!!") |
| u32 | +0x40 | has object (0/1) |
| u32 + payload | | object type + object (mesh, ...), not parsed |

- Nodes are written in hierarchy order: depth first, parents before children. [V]
- `m3d.sm3_nodes()` parses the records and skips object payloads by scanning for the next
  valid record whose parent is already known. The result is checked against node_count.
  It parses all 733 character, FP actor and prop SM3 files. It fails on 25 level maps
  (portal/camera objects), which the retarget does not need. [V]
- **The engine's node "table" for animation is the slot field, not the record order.**
  Example: `delgado.sm3` has 144 nodes with slots 0..227. `fp_delgado.sm3` has 143 nodes
  with slots 0..186. [V]
- The bind position and rotation are the pose the model was saved in. A const anim channel
  of a node that does not move equals these values exactly (median 0.0°). [V]

## 4. CM3 (animation)

```
"CM3\0" u32 0  u32 0x65226E  u32 hash1 u32 hash2 u32 hash3
"SCN\0" u32 0  u32 1  string string INI  8+8+24+12+4 bytes  INI
        u32 0 (materials)  u32 1  u32 0 (nodes)  u32 1 (has animation)
"ANI\0" u32 0
  u32 4                       version
  f32 fps                     Animacion+0x08 (30.0 everywhere)
  u32 first_frame             +0x0c  (= every track's primer frame) [V]
  u32 frames                  +0x10  length in frames
  u32 ntracks                 +0x30
  u32 flag                    +0x14  (bool; set for vertex-only anims) [G]
  f32 x3                      +0x18  [G: reference offset computed in AnimGrupo.cpp
                                     0x6133c0 from a node position and a track's
                                     first-frame position; kept from the FP file]
  u32 n, n bytes              +0x24/+0x28 REMAP TABLE (see 4.1)
"NABK" u32 size, size bytes   all tracks' channel data, track after track
ntracks x NAM chunk           per-track header, in track order
```

- `hash1..3` (`FUN_00639780` and `FUN_0063d920`): computed from the `.M3D` path and from
  the scene's `.M3D`/`.INI` source paths (`thunk_FUN_01227fe0`). They are compared only
  when the global at 0x8909f4 (rebuild/check-sources mode) is set. In that case a
  mismatch makes the engine try to rebuild from the `.M3D` source, which retail does not
  ship; it then warns "Could not rebuild" and loads the file anyway.
  [V for the code, G for the meaning]. The retarget keeps the FP file's values.
- There is nothing after the last NAM chunk (3633 of 3633 files). [V]

### 4.1 Remap table: how tracks bind to model nodes [V]

`remap[slot] = track_index + 1`; 0 means the slot is not animated. The table length is
`max(model slot) + 1` of the model the animation was made for:

- This holds for all 2266 animations in `models/chars/*/anm` and `models/fpactor/*/anm`.
  Every non-zero entry points to an existing node slot.
- Animations of the same model use different track sets: Delgado's animations have, for
  example, 104, 107, 108 or 139 tracks with different tables. Tracks therefore cannot bind by position in the list, and
  CM3 files contain no node names.
- **Correction to the earlier "bound by index" note:** an FP animation's table is indexed
  by `fp_<char>.sm3` slots. Played on `<char>.sm3`, each full-model node reads
  `remap[its own slot]`, so it gets an unrelated track or none. For example
  `delgado.sm3`'s "Bip Delgado" (slot 5) reads the FP track of "Bip Delgado Spine", and
  Head (slot 115) gets no track. Slots >= 187 (legs) fall outside the table. This also
  explains the head disappearing into the body.
- The lookup code itself was not found: it is probably in the SecuROM-relocated code. The
  rule above is proven by the data.

### 4.2 NAM chunk (per track; reader `FUN_0064cd80`, writer `FUN_0064c580`) [V]

```
"NAM\0" u32 0  u32 1  u32 primer  u32 nframes  u32 flags  u32 opt  u32 stm
  for each channel c in (0x01,0x02,0x04,0x08,0x10,0x80): if c in flags and c in (opt & stm): u32 stream_bytes
  if flags & 0x1000: "EVA\0" chunk (vertex animation; no shipped CM3 uses it)
```

| flag | element | meaning |
|---|---|---|
| 0x01 | 3 x f32 (12 B) | position [V] |
| 0x02 | 4 x f32 (16 B) | rotation quaternion [V] |
| 0x04 | f32 | [G] camera FOV: present on the FP `Camera01` tracks |
| 0x08, 0x10 | f32 | [G] (29 tracks each) |
| 0x80 | u8 | [G] visibility: present on `CH_` mesh nodes |
| 0x1000 | EVA chunk | vertex animation ("ANIM_VERT") |

- `opt` (OPT_SUPPORTED = 7, only pos/rot/f04): the channel is stored once (constant) or as
  a stream.
- `stm`: an opt channel that is also in stm is a self-describing **stream**.
- CM3_SUPPORTED flags mask = 0x109F.
- **Engine rule, fatal if broken** (`FUN_0064b7f0`, the per-frame track sampler,
  Animacion.cpp:524 `"Pos && Rot"`): a track has both pos (0x01) and rot (0x02), or
  neither. A track without either is skipped (e.g. visibility-only `CH_` tracks, flags
  0x80). In the game files, 278,207 + 1,664 + 813 + 29 tracks have both, 220 have neither,
  and none has only one. [V]
- The sampler returns "no transform" when `frame - primer >= nframes`. Quantised streams
  are sampled through code in the SecuROM area (jump at 0x11a2c38). [V]

### 4.3 NABK channel data [V]

For each track in order, for each present channel in flag order: `count` = 1 if
`flag & opt` else `nframes`.

- Stream channel: `bytes = stream_bytes` (from NAM).
- Other channels: `count * element_size`.

Every channel is padded to 4 bytes. The NABK size must equal the sum
(`AnimBlock.SizeBlock == UsedBlock`).

**Stream** (`flag & opt & stm`). Writer: `FUN_0064d070` (the optimizer/compressor).

```
u16 words (= stream bytes / 4, including this header and padding)
u16 sflags   0x8000 = quantised
u16 start    first stored frame
u16 count    stored frames
payload
```

Frames before `start` equal the first stored value, frames after `start+count-1` equal the
last. The stored value at `start` is the frame-0 value. This header and size formula hold
for all 156,844 streams in the game.

- **Position, quantised:** `base` 3 x f32, `scale` f32 (= range/32767), then count x
  3 x int16. `pos = base + q * scale`.
- **Rotation, quantised:** `base` 3 x f32, `scale` f32 (= range/511), then count x u32.
  The u32 packs x = bits 31..21, y = bits 20..10, z = bits 9..0, from `FUN_0064b410`:
  ```
  delta = ((x - 1024) / 2, (y - 1024) / 2, z - 512) * scale
  e = base + delta        # negated euler angles (pitch, yaw, roll), radians
  M = D3DXMatrixRotationYawPitchRoll(yaw=-e1, pitch=-e0, roll=-e2)
  q' = D3DXQuaternionRotationMatrix(M)
  q = (q'.x, q'.y, q'.z, -q'.w)
  ```
  The encoder is `FUN_0064b3c0`: quaternion -> `D3DXMatrixRotationQuaternion(x,y,z,-w)` ->
  `FUN_005ef580` (pitch = atan2(-m21, hypot(m20, m22)), yaw = atan2(m20, m22),
  roll = atan2(m01, m11)), then negated.
- **Not quantised:** count raw elements (12 B position, 16 B quaternion, 4 B float).

Decoder check: `m3d.Track.decode()`. The last frame of each `*init` animation was
compared with the first frame of the matching main animation (all squad members):

| channels compared | count | median error |
|---|---|---|
| rotation stream vs const | 1,140 | 0.016° |
| rotation const vs stream | 116 | 0.000° |
| rotation stream vs stream | 3,293 | 0.017° |
| position, at least one side a stream | 673 | 0.0001 units |

Root motion (DC_Root, biped root) and props that jump in reloads differ, as expected.

### 4.4 Transforms

The engine builds a node's local matrix with `D3DXMatrixRotationQuaternion(x, y, z, -w)`
(`FUN_0060ef00`) and the position as translation. It uses row vectors: world = local x
parent x ... [V]: forward kinematics with this convention puts the retargeted head
2-13 units from the FP animation's `Camera01` (section 6).

## 5. Path resolution

- `FUN_00639730` converts an M3D path to the compiled file name with the template
  `"&U&D&N.CM3"`: same drive, directory and name, extension `.CM3`.
  `FUN_00639940` does the same with `.SM3` for models. [V]
- Archive names are all lowercase, while scripts use mixed case
  (`.../ConversationAnm/Delgado_Play.M3D`), so the pack lookup is case-insensitive.
  [V for the names, G for the mechanism]
- A Lua action with `AnmFilePath = "<LevelPath>/Map/<Scene>/<Scene>Anm/CoopBody_Delgado_Play.M3D"`
  therefore loads `levels/<level>/map/<scene>/<scene>anm/coopbody_delgado_play.cm3`. [G until tested]

## 6. Retargeting FP scene animations (`tools/cm3_retarget.py`)

Inputs per FP animation:

- `levels/<l>/map/<s>/<s>anm/fp_<actor>_<x>.cm3`
- `models/fpactor/fp_<actor>/fp_<actor>.sm3`
- `models/chars/<char>/<char>.sm3` (`rossnude` maps to `ross`, whose skeleton is `Bip Jones`)
- `models/chars/<char>/anm/<char>_relax.cm3`

The output `.../coopbody_<actor>_<x>.cm3` keeps the FP file's header, hashes, SCN, fps,
first frame, frame count and the ANI reference vector. It gets a new remap table sized for
the full model. For each full-model node, in hierarchy order:

1. **Same name and parent in the FP rig.** The name match also accepts the name without
   the FP rig marker: `Bip FP-Cole Neck` matches `Bip Cole Neck`, `BOC_FPS-Black_Codo_L`
   matches `BoC_Black_Codo_L`.
   - Same bone offset (bind position within 0.05), or a node directly under the scene
     root: the FP track is copied byte for byte.
   - Different offset (the FP arms of Ross/Jones are longer): FP rotation with the full
     model's offset. This applies inside an FP-driven chain only, and for props only if
     the FP offset is static.
2. **Same name, different parent** (FP rigs add `Bip Church MASTER`, drop the `Bip Jones`
   root, or hold props under DC_Root), for nodes the idle animates. The local transform is
   recomposed per frame, so the node sits where the FP rig puts it relative to the nearest
   common FP-driven ancestor. It is written as uncompressed per-frame channels.
   - Exception: parts of a prop whose body is not FP-driven stay on the body.
3. **Any other node the idle animates:** constant = idle frame 0 of every channel. pos,
   rot and f04 are stored as const; f08, f10 and b80 are repeated per frame.
4. **Otherwise:** not animated. This covers face bones (`BoeF_*`, driven by the facial
   animations), effect dummies (`DF_*`), DC_Camera and the mesh root, as in the idle.

Every output track also follows the "Pos && Rot" rule. If a track ends up with only
one of the two channels, the missing one is added as a constant (idle frame 0, else the
bind pose). Per-frame pos/rot written by the tool use the game's unquantised stream form
(opt+stm, sflags 0), not plain per-frame arrays, which never occur in the game files for
pos/rot. A full check confirms that every output track has a flags/kind combination that
also occurs in the game's own files.

Validation done by the tool for every output file:

- Every track must have pos and rot, or neither.

- The file is parsed back and must re-serialize identically.
- The remap table length must equal the full model's max slot + 1, with no orphan slots.
- Every track is referenced exactly once.
- Copied tracks must be byte-identical to the FP source.
- Idle constants must equal the idle's frame 0.
- Recomposed nodes must match the FP rig's transform relative to the common ancestor at
  the first, middle and last frame.

The track count is not the model's node count: Delgado has 108 tracks for 144 nodes and
228 slots, the same as the native `delgado_relax.cm3`.

Sanity check (forward kinematics, `work/anim_rt/scratch/fk_check.py`): the median distance
between the retargeted full body's `Bip <X> Head` and the FP rig's `Camera01` is 2-13
units for 58 of 62 files.

| scene | head to Camera01 | why |
|---|---|---|
| AperturaPuerta, Escalada | 80-540 | these scenes film from the scene object, not from Camera01 |
| Delgado Conversation | 19 | after frame ~700 the FP camera moves while the body is static |
| Rawlings PlayI | 22 | [G] |

## 7. Open questions / limits

- How to mount `CoopAnims.packed` (section 1), and whether a scene actor with
  `AnimAbsMove = 1` plays the coopbody file in the right place. Not tested in game, by
  design.
- Meaning of the ANI 3-float vector, the ANI flag, SCN fixed bytes, node fields +0x4c..+0x54,
  and channels 0x04/0x08/0x10/0x80 (guesses above).
- The head and neck helper (`BoC_*_Cuello`) of most characters come from the idle as a
  constant: the FP rigs have no head. Twist bones without an FP counterpart are also idle
  constants.
- Props whose FP name differs stay where the idle holds them (holstered), e.g. Rawlings'
  pistols (`OB_FP-Rawllings_0x_Cuerpo` vs `OB_Rawllings_0x_Pistola`). An explicit alias
  could move them, but the pivots are unverified.
- `[RenameNodes]` in a model's FileINI (e.g. `BoF_Delgado_Mandibula = BoeF_Delgado_Mandibula`)
  is not needed: binding is by slot, and the names in the file are already the new ones.

## 8. In-game crash `!Refs` (objref.h:35) at the end of Conversation: not the animation data

- **Where it fires** (stack of runs 20261019-023233 host and 20261019-011642 client, which
  are identical):
  1. World update `FUN_00423440` processes the entity delete queue.
  2. `cWithLifeEntity` destructor (`FUN_0043bf97`), then `cActCtrl` destructor
     (`FUN_00528ce0`).
  3. Entity SetModel(null) (`FUN_00438d40`), then model release (`FUN_005d945e`), then
     `CModelo::~CModelo` (`FUN_005d69b0`), then `SetEscena(0)` (`FUN_005d64d0`).
  4. NodoR array destructor (`FUN_00615ec0`, 0x130-byte render node per scene node):
     a render node still has `Refs != 0`.
- **When:** at `Scene.EndOfScene`, which deletes every actor. The capture ends 60.0 s
  (1801 frames) after "scene start".
- **Same crash with the raw FP file:** run 011642 client played
  `FP_Delgado_Play.M3D` (not retargeted), logged "scene ended DM_Scene_Conversation",
  then crashed with the same stack.
- **Common factor:** "scene body: ConversationCoopBody shown". Runs where the body was
  hidden reached the end without this crash.
- **Data check:** every track and stream of all 62 coopbody files uses only forms that
  occur in the game's own files, and covers exactly its frames (`check_coverage`).
- [G] The reference is held by something attached to the visible CoopBody's action
  controller or render nodes (the looping channel-1 `CoopFace` action, the
  `NodeModifier`, or an effect on a render node). It is released after the model.
  Suggested Lua fix: before `Scene.EndOfScene` deletes the actors, stop the body's
  channel-1 action, clear its NodeModifier, and hide or delete the body first.
