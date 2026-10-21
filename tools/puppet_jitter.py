"""(From the fork MAK-PIVO/jericho-coop.) Smoothness of other players' bodies from a 'puppetlog' run (lua/dev.lua).

    python puppet_jitter.py <coop log> [<coop log> ...]

For each puppet: frames, mean speed, how often a frame moves the body much more than the
frames around it (a visible jump), the 95th percentile of acceleration, and how often the
body turns more than 15 degrees in one frame. Lower is smoother. Standard library only.
"""
import math
import sys


def stats(rows):
    rows.sort()
    out = {"frames": len(rows)}
    if len(rows) < 10:
        return out
    steps, speeds, turns = [], [], []
    for (t0, x0, y0, z0, a0), (t1, x1, y1, z1, a1) in zip(rows, rows[1:]):
        dt = t1 - t0
        if dt <= 0:
            continue
        d = math.hypot(x1 - x0, z1 - z0)
        steps.append((d, dt))
        speeds.append(d / dt)
        da = (a1 - a0 + 180) % 360 - 180
        turns.append(abs(da))
    acc = sorted(abs(b - a) / max(dt, 1e-3) for a, b, (_, dt) in zip(speeds, speeds[1:], steps[1:]))
    # A jump: a frame's movement over 3x the median of its 9 neighbours and over 15 units.
    jumps = 0
    for i in range(len(steps)):
        around = sorted(s[0] for s in steps[max(0, i - 4):i + 5] if s is not steps[i])
        med = around[len(around) // 2] if around else 0
        if steps[i][0] > max(15.0, 3 * med):
            jumps += 1
    out.update(
        speed=sum(speeds) / len(speeds),
        jumps=jumps,
        jumps_per_min=jumps / max(rows[-1][0] - rows[0][0], 1e-3) * 60,
        acc_p95=acc[int(len(acc) * 0.95)] if acc else 0,
        turn_p95=sorted(turns)[int(len(turns) * 0.95)] if turns else 0,
        turns_over_15=sum(1 for a in turns if a > 15),
        fps=len(rows) / max(rows[-1][0] - rows[0][0], 1e-3),
    )
    return out


def main():
    for path in sys.argv[1:]:
        by = {}
        for line in open(path, encoding="latin-1"):
            i = line.find("pp|")
            if i < 0:
                continue
            f = line[i:].strip().split("|")
            if len(f) < 7:
                continue
            by.setdefault(f[2], []).append(tuple(float(v) for v in (f[1], f[3], f[4], f[5], f[6])))
        print(path)
        for name, rows in sorted(by.items()):
            s = stats(rows)
            if "speed" not in s:
                print(f"  {name}: {s['frames']} frames")
                continue
            print(f"  {name}: {s['frames']} frames {s['fps']:.0f} fps, speed {s['speed']:.0f}/s, "
                  f"jumps {s['jumps']} ({s['jumps_per_min']:.1f}/min), acc p95 {s['acc_p95']:.0f}, "
                  f"turn p95 {s['turn_p95']:.1f} deg, turns>15deg {s['turns_over_15']}")


if __name__ == "__main__":
    main()
