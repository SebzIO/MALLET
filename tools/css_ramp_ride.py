"""Rides a .vmf's ramps the way Counter-Strike: Source moves a player, to find seams that stop surfers ("ramp bugs").

A small re-implementation of Source's player movement against brushes: the CS:S player box (32 x 32 x 72), box
traces as CM_ClipBoxToBrush in Source 2013 (planes pushed out by the box, DIST_EPSILON 0.03125), each brush with
vbsp's axial and edge bevel planes, TryPlayerMove with ClipVelocity, gravity 800, 66 ticks a second, and air
strafing into the ramp (sv_airaccelerate 150). From every riding face of every ramp piece it starts a short ride
along the ramp at 1000 and 2000 u/s and counts rides whose speed falls by more than 15% in one tick.

Ramps are the .vmf's func_detail entities (how MALLET writes them). Needs numpy.
    python tools/css_ramp_ride.py map.vmf [more.vmf ...]
"""

import re, sys, itertools, math
import numpy as np

DIST_EPS = 0.03125
EXT = np.array([16.0, 16.0, 36.0])          # half extents; the box's center is origin + (0, 0, 36)
TICK = 1.0 / 66.0
GRAV = 800.0
pt = re.compile(r'"plane" "\(([^)]*)\) \(([^)]*)\) \(([^)]*)\)"')


class Brush:
    def __init__(self, planes):
        self.planes = planes                 # [(n, d)] outward
        self.verts = self._verts()
        self.ok = len(self.verts) >= 4
        if not self.ok:
            return
        self.lo = np.min(self.verts, axis=0)
        self.hi = np.max(self.verts, axis=0)
        self._bevels()
        self.N = np.array([p[0] for p in self.planes])
        self.D = np.array([p[1] for p in self.planes])
        self.off = np.abs(self.N) @ EXT    # Minkowski: the box's reach along each normal

    def _verts(self):
        vs = []
        for a, b, c in itertools.combinations(self.planes, 3):
            A = np.array([a[0], b[0], c[0]])
            if abs(np.linalg.det(A)) < 1e-9:
                continue
            v = np.linalg.solve(A, [a[1], b[1], c[1]])
            if all(n @ v - d < 0.01 for n, d in self.planes):
                if not any(np.linalg.norm(v - u) < 1e-3 for u in vs):
                    vs.append(v)
        return vs

    def _has(self, n, d):
        return any(np.dot(n, m) > 0.9999 and abs(d - e) < 0.01 for m, e in self.planes)

    def _bevels(self):
        add = []
        for ax in range(3):                   # axial bevels: the brush's bounding box
            for s in (-1, 1):
                n = np.zeros(3); n[ax] = s
                if not any(np.dot(n, m) > 0.9999 for m, _ in self.planes):
                    add.append((n, self.hi[ax] if s > 0 else -self.lo[ax]))
        self.planes = self.planes + add
        edges = []                            # edge bevels
        for n, d in list(self.planes):
            fv = [v for v in self.verts if abs(n @ v - d) < 0.01]
            if len(fv) < 3:
                continue
            c = np.mean(fv, axis=0)
            u = fv[0] - c; u /= np.linalg.norm(u); w = np.cross(n, u)
            fv.sort(key=lambda v: math.atan2((v - c) @ w, (v - c) @ u))
            for i in range(len(fv)):
                edges.append((fv[i], fv[(i + 1) % len(fv)]))
        for a, b in edges:
            vec = b - a
            L = np.linalg.norm(vec)
            if L < 0.5:
                continue
            vec /= L
            for ax in range(3):
                for s in (-1, 1):
                    a2 = np.zeros(3); a2[ax] = s
                    n = np.cross(vec, a2)
                    if np.linalg.norm(n) < 0.5:
                        continue
                    n /= np.linalg.norm(n)
                    d = n @ a
                    if self._has(n, d):
                        continue
                    if all(n @ v - d <= 0.1 for v in self.verts):
                        self.planes.append((n, d))

    def clip(self, start, end):
        """Box (centers start -> end) against this brush: (fraction, normal) or None."""
        D = self.D + self.off
        d1 = self.N @ start - D
        d2 = self.N @ end - D
        enter, leave, plane, out = -1.0, 1.0, None, False
        for i in range(len(D)):
            if d1[i] > 0:                     # (Source 2013's CM_ClipBoxToBrush)
                out = True
                if d2[i] > 0:
                    return None
            elif d2[i] <= 0:
                continue
            if d1[i] > d2[i]:
                f = (d1[i] - DIST_EPS) / (d1[i] - d2[i])
                if f > enter:
                    enter, plane = f, i
            else:
                f = (d1[i] + DIST_EPS) / (d1[i] - d2[i])
                leave = min(leave, f)
        if not out:
            return (0.0, None)                # started inside
        if enter < leave and enter > -1 and plane is not None:
            return (max(enter, 0.0), self.N[plane])
        return None


def load(path):
    txt = open(path, encoding='utf-8').read()
    ents = re.split(r'\nentity\n', txt)
    ramps = []
    for e in ents:
        if '"classname" "func_detail"' not in e:
            continue
        bs = []
        for solid in e.split('\tsolid\n')[1:]:
            planes = []
            for m in pt.finditer(solid):
                p = [np.array([float(x) for x in g.split()]) for g in m.groups()]
                n = np.cross(p[2] - p[0], p[1] - p[0]); n /= np.linalg.norm(n)
                planes.append((n, float(n @ p[0])))
            b = Brush(planes)
            if b.ok:
                bs.append(b)
        ramps.append(bs)
    return ramps


def trace(brushes, start, end):
    lo = np.minimum(start, end) - EXT - 1
    hi = np.maximum(start, end) + EXT + 1
    best = (1.0, None)
    for b in brushes:
        if np.any(b.hi < lo) or np.any(b.lo > hi):
            continue
        r = b.clip(start, end)
        if r is not None and r[0] < best[0]:
            best = r
    return best


def clipvel(v, n):
    out = v - n * (v @ n)
    adj = out @ n
    if adj < 0:
        out -= n * adj
    return out


def move(brushes, pos, vel):
    """TryPlayerMove (in the air). pos = box center."""
    primal = vel.copy(); orig = vel.copy(); planes = []; left = TICK; allf = 0.0
    hits = []
    for bump in range(4):
        if not vel.any():
            break
        end = pos + vel * left
        f, n = trace(brushes, pos, end)
        if n is None and f == 0.0:
            return pos, np.zeros(3), hits + ['stuck']
        allf += f
        if f > 0:
            pos = pos + (end - pos) * f
            orig = vel.copy(); planes = []
        if f == 1.0:
            break
        hits.append(n)
        left -= left * f
        planes.append(n)
        if len(planes) == 1:
            vel = clipvel(orig, n); orig = vel.copy()
        else:
            found = False
            for i in range(len(planes)):
                vel = clipvel(orig, planes[i])
                if all(vel @ planes[j] >= 0 for j in range(len(planes)) if j != i):
                    found = True
                    break
            if not found:
                if len(planes) != 2:
                    vel = np.zeros(3); break
                dr = np.cross(planes[0], planes[1])
                if np.linalg.norm(dr) < 1e-6:
                    vel = clipvel(orig, planes[0]); continue
                dr /= np.linalg.norm(dr)
                vel = dr * (dr @ vel)
            if vel @ primal <= 0:
                vel = np.zeros(3); break
    if allf == 0:
        vel = np.zeros(3)
    return pos, vel, hits


def ride(brushes, start, vel, seconds=6.0):
    pos = start.copy(); events = []
    lo = np.min([b.lo for b in brushes], axis=0); hi = np.max([b.hi for b in brushes], axis=0)
    on = 0
    last_n = None
    for tick in range(int(seconds / TICK)):
        vel = vel.copy(); vel[2] -= GRAV * TICK
        if last_n is not None:                # hold the strafe key into the ramp (CS:S air control)
            wd = -last_n.copy(); wd[2] = 0
            if np.linalg.norm(wd) > 1e-3:
                wd /= np.linalg.norm(wd)
                add = 30.0 - vel @ wd
                if add > 0:
                    vel = vel + wd * min(150.0 * 250.0 * TICK, add)
        before = np.linalg.norm(vel)
        pos, vel, hits = move(brushes, pos, vel)
        after = np.linalg.norm(vel)
        if hits:
            on += 1
            if not isinstance(hits[-1], str) and 0.05 < hits[-1][2] < 0.75:
                last_n = hits[-1]
        if hits and after < before * 0.85:
            events.append((round(tick * TICK, 2), round(before), round(after)))
        if pos[2] < lo[2] - 200:
            break
    return events, on, tick * TICK


def faces_of(b):
    out = []
    c = np.mean(b.verts, axis=0)
    for n, d in b.planes[:]:
        fv = [v for v in b.verts if abs(n @ v - d) < 0.01]
        if len(fv) >= 3 and 0.05 < n[2] < 0.75:
            out.append((n, d, np.mean(fv, axis=0)))
    return out


def sweep(path, speeds=(1000, 2000), seconds=0.6):
    """A short steered ride from the middle of every riding face of every piece, along the ramp: how many end in a
    sudden slowdown (speed falls by more than 15% in one tick)."""
    out = []
    for ri, bs in enumerate(load(path)):
        cs = [np.mean(b.verts, axis=0) for b in bs]
        rides = bad = 0
        worst = []
        for i in range(len(bs) - 3):
            for n, d, c in faces_of(bs[i]):
                lvl = np.cross(np.array([0, 0, 1.0]), n); lvl[2] = 0
                if np.linalg.norm(lvl) < 1e-3:
                    continue
                lvl /= np.linalg.norm(lvl)
                if (cs[i + 3] - cs[i]) @ lvl < 0:
                    lvl = -lvl
                for sp in speeds:
                    ev, on, dur = ride(bs, c + n * (np.abs(n) @ EXT + 20.0), lvl * sp, seconds)
                    rides += 1
                    if ev:
                        bad += 1
                        worst.append((i, sp) + ev[0])
        out.append((ri, rides, bad, worst[:5]))
    return out


if __name__ == '__main__':
    for path in sys.argv[1:]:
        for ri, rides, bad, w in sweep(path):
            print(f'{path.split("/")[-1]} ramp {ri}: {bad} of {rides} rides stopped or slowed hard', w)
