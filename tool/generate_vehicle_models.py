#!/usr/bin/env python3
"""Generate the cartoon vehicle glTF models used by the 3D map layer.

The repo ships no binary art, so the four vehicle models (car, suv, bike,
scooter) are modelled procedurally here in pure Python (no dependencies):
chunky, rounded, smooth-shaded shapes with oversized wheels, glowing lights,
chrome trim and — for the two-wheelers — a little helmeted rider.

Conventions (what `VehicleModelLayerManager` / the location puck assume):
real-world metres, glTF Y-up, the vehicle faces +X, and the origin sits on the
ground at the centre of the vehicle.

Geometry is emitted the way a DCC exporter would: indexed triangle lists
(uint16), smooth normals and a UV set (TEXCOORD_0), one primitive per material.

Run from the repo root:

    python3 tool/generate_vehicle_models.py

It writes assets/models/vehicle_<type>.glb. Re-run after editing a shape and the
new models are bundled on the next build (assets/models/ is in pubspec.yaml).
"""

from __future__ import annotations

import json
import math
import os
import struct

OUT_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "models"
)

FLOAT = 5126
UNSIGNED_SHORT = 5123
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963

# --------------------------------------------------------------------------
# Small vector / matrix helpers (3x3 row-major rotation matrices)
# --------------------------------------------------------------------------

IDENTITY = ((1, 0, 0), (0, 1, 0), (0, 0, 1))


def rot_x(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return ((1, 0, 0), (0, c, -s), (0, s, c))


def rot_y(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return ((c, 0, s), (0, 1, 0), (-s, 0, c))


def rot_z(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return ((c, -s, 0), (s, c, 0), (0, 0, 1))


def mat_mul(a, b):
    return tuple(
        tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3))
        for i in range(3)
    )


def apply(m, v):
    return (
        m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
        m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
        m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2],
    )


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def length(v):
    return math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])


def normalize(v):
    n = length(v)
    return (0.0, 1.0, 0.0) if n < 1e-12 else (v[0] / n, v[1] / n, v[2] / n)


def cross(a, b):
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def orient_y_to(direction):
    """Rotation matrix taking +Y onto `direction`."""
    d = normalize(direction)
    y = (0.0, 1.0, 0.0)
    axis = cross(y, d)
    s = length(axis)
    c = dot(y, d)
    if s < 1e-9:
        return IDENTITY if c > 0 else rot_x(180)
    k = (axis[0] / s, axis[1] / s, axis[2] / s)
    kx, ky, kz = k
    return (
        (c + kx * kx * (1 - c), kx * ky * (1 - c) - kz * s, kx * kz * (1 - c) + ky * s),
        (ky * kx * (1 - c) + kz * s, c + ky * ky * (1 - c), ky * kz * (1 - c) - kx * s),
        (kz * kx * (1 - c) - ky * s, kz * ky * (1 - c) + kx * s, c + kz * kz * (1 - c)),
    )


# --------------------------------------------------------------------------
# Mesh container. A "grid" is a list of rows of (pos, normal, uv) vertices that
# gets triangulated as quads; winding is auto-corrected against the normals.
# --------------------------------------------------------------------------


class Mesh:
    def __init__(self):
        self.pos, self.nor, self.uv, self.idx = [], [], [], []

    def add_grid(self, grid, R=IDENTITY, t=(0.0, 0.0, 0.0)):
        base = len(self.pos)
        rows = len(grid)
        cols = len(grid[0])
        for row in grid:
            for p, n, uv in row:
                q = apply(R, p)
                self.pos.append((q[0] + t[0], q[1] + t[1], q[2] + t[2]))
                self.nor.append(normalize(apply(R, n)))
                self.uv.append(uv)

        def vid(i, j):
            return base + i * cols + j

        for i in range(rows - 1):
            for j in range(cols - 1):
                a, b, c, d = vid(i, j), vid(i + 1, j), vid(i + 1, j + 1), vid(i, j + 1)
                for tri in ((a, b, c), (a, c, d)):
                    self._add_tri(*tri)

    def _add_tri(self, a, b, c):
        pa, pb, pc = self.pos[a], self.pos[b], self.pos[c]
        face = cross(sub(pb, pa), sub(pc, pa))
        if length(face) < 1e-12:  # degenerate (collapsed pole row)
            return
        avg = (
            self.nor[a][0] + self.nor[b][0] + self.nor[c][0],
            self.nor[a][1] + self.nor[b][1] + self.nor[c][1],
            self.nor[a][2] + self.nor[b][2] + self.nor[c][2],
        )
        if dot(face, avg) < 0:
            b, c = c, b
        self.idx.extend((a, b, c))


# --------------------------------------------------------------------------
# Shape primitives (all built in local space; placed via Mesh.add_grid)
# --------------------------------------------------------------------------


def _samples(half, r, seg):
    """Sample positions along one axis of a rounded box: dense in the corner
    bands, nothing across the flat middle."""
    lo = [-half + r * k / seg for k in range(seg + 1)]
    hi = [half - r + r * k / seg for k in range(seg + 1)]
    out = lo + hi
    dedup = []
    for v in out:
        if not dedup or abs(v - dedup[-1]) > 1e-9:
            dedup.append(v)
    return dedup


def rounded_box(sx, sy, sz, r, seg=3, taper=(0.0, 0.0)):
    """A box with rounded edges/corners. `taper` = (x, z) fractional inward
    shrink of the top relative to the bottom (for sloped cabins)."""
    half = (sx / 2, sy / 2, sz / 2)
    r = min(r, min(half) * 0.999)
    samples = [_samples(h, r, seg) for h in half]
    grids = []
    for axis in range(3):
        for sign in (-1, 1):
            a1, a2 = [i for i in range(3) if i != axis]
            grid = []
            for u in samples[a1]:
                row = []
                for v in samples[a2]:
                    s = [0.0, 0.0, 0.0]
                    s[axis] = sign * half[axis]
                    s[a1] = u
                    s[a2] = v
                    inner = [
                        max(-(half[i] - r), min(half[i] - r, s[i])) for i in range(3)
                    ]
                    d = [s[i] - inner[i] for i in range(3)]
                    n = normalize(d)
                    p = [inner[i] + n[i] * r for i in range(3)]
                    if taper[0] or taper[1]:
                        k = (p[1] + half[1]) / sy  # 0 at bottom .. 1 at top
                        p[0] *= 1 - taper[0] * k
                        p[2] *= 1 - taper[1] * k
                    uv = ((u + half[a1]) / (2 * half[a1]), (v + half[a2]) / (2 * half[a2]))
                    row.append((tuple(p), n, uv))
                grid.append(row)
            grids.append(grid)
    return grids


def ellipsoid(rx, ry, rz, seg_u=14, seg_v=8):
    grid = []
    for j in range(seg_v + 1):
        lat = -math.pi / 2 + math.pi * j / seg_v
        row = []
        for i in range(seg_u + 1):
            lon = 2 * math.pi * i / seg_u
            x = math.cos(lat) * math.cos(lon)
            y = math.sin(lat)
            z = math.cos(lat) * math.sin(lon)
            p = (rx * x, ry * y, rz * z)
            n = normalize((x / rx, y / ry, z / rz))
            row.append((p, n, (i / seg_u, j / seg_v)))
        grid.append(row)
    return [grid]


def lathe(strips, segments=20):
    """Surface of revolution around the Y axis. Each strip is a polyline of
    (radius, axial) points travelled so the outward normal is to the right of
    travel; interior points are smoothed, strips meet in hard edges."""
    grids = []
    for strip in strips:
        m = len(strip)
        # per-segment outward normals in the (r, a) plane
        seg_n = []
        for i in range(m - 1):
            dr, da = strip[i + 1][0] - strip[i][0], strip[i + 1][1] - strip[i][1]
            l = math.hypot(dr, da) or 1.0
            seg_n.append((da / l, -dr / l))
        pt_n = []
        for i in range(m):
            parts = []
            if i > 0:
                parts.append(seg_n[i - 1])
            if i < m - 1:
                parts.append(seg_n[i])
            nr = sum(p[0] for p in parts)
            na = sum(p[1] for p in parts)
            l = math.hypot(nr, na) or 1.0
            pt_n.append((nr / l, na / l))
        # cumulative v along the profile
        acc = [0.0]
        for i in range(1, m):
            acc.append(acc[-1] + math.hypot(strip[i][0] - strip[i - 1][0], strip[i][1] - strip[i - 1][1]))
        total = acc[-1] or 1.0
        grid = []
        for i in range(m):
            row = []
            for k in range(segments + 1):
                th = 2 * math.pi * k / segments
                c, s = math.cos(th), math.sin(th)
                r, a = strip[i]
                nr, na = pt_n[i]
                row.append(((r * c, a, r * s), (nr * c, na, nr * s), (k / segments, acc[i] / total)))
            grid.append(row)
        grids.append(grid)
    return grids


def _arc(cr_, ca, radius, a0, a1, n):
    return [
        (
            cr_ + radius * math.cos(math.radians(a0 + (a1 - a0) * k / n)),
            ca + radius * math.sin(math.radians(a0 + (a1 - a0) * k / n)),
        )
        for k in range(n + 1)
    ]


def disc(radius, half_thickness, corner=0.0, segments=24):
    """Cylinder about Y with optionally rounded rim edges."""
    if corner <= 0:
        return lathe(
            [[(0, -half_thickness), (radius, -half_thickness), (radius, half_thickness), (0, half_thickness)]],
            segments,
        )
    c = min(corner, radius * 0.99, half_thickness * 0.99)
    strip = [(0, -half_thickness)]
    strip += _arc(radius - c, -half_thickness + c, c, -90, 0, 4)
    strip += _arc(radius - c, half_thickness - c, c, 0, 90, 4)
    strip += [(0, half_thickness)]
    return lathe([strip], segments)


def capsule(p0, p1, radius, segments=10):
    """A rounded rod between two points."""
    d = sub(p1, p0)
    L = length(d)
    strip = _arc(0, 0, radius, -90, 0, 4) + _arc(0, L, radius, 0, 90, 4)
    return lathe([strip], segments), orient_y_to(d), p0


# --------------------------------------------------------------------------
# Palette
# --------------------------------------------------------------------------

BODY, BODY_DARK, GLASS, RUBBER, CHROME, HEADLIGHT, TAILLIGHT, TRIM, WHITE, JACKET = range(10)


def materials(body_rgb):
    def pbr(rgb, metal, rough):
        return {
            "baseColorFactor": [rgb[0], rgb[1], rgb[2], 1.0],
            "metallicFactor": metal,
            "roughnessFactor": rough,
        }

    dark = tuple(c * 0.55 for c in body_rgb)
    return [
        {"name": "body", "pbrMetallicRoughness": pbr(body_rgb, 0.1, 0.35)},
        {"name": "body_dark", "pbrMetallicRoughness": pbr(dark, 0.1, 0.5)},
        {"name": "glass", "pbrMetallicRoughness": pbr((0.16, 0.27, 0.38), 0.2, 0.08)},
        {"name": "rubber", "pbrMetallicRoughness": pbr((0.07, 0.07, 0.08), 0.0, 0.95)},
        {"name": "chrome", "pbrMetallicRoughness": pbr((0.82, 0.84, 0.88), 0.35, 0.25)},
        {
            "name": "headlight",
            "pbrMetallicRoughness": pbr((1.0, 0.96, 0.78), 0.0, 0.2),
            "emissiveFactor": [1.0, 0.9, 0.5],
        },
        {
            "name": "taillight",
            "pbrMetallicRoughness": pbr((0.92, 0.1, 0.1), 0.0, 0.3),
            "emissiveFactor": [0.8, 0.05, 0.05],
        },
        {"name": "trim", "pbrMetallicRoughness": pbr((0.15, 0.15, 0.18), 0.1, 0.6)},
        {"name": "white", "pbrMetallicRoughness": pbr((0.97, 0.97, 0.97), 0.0, 0.4)},
        {"name": "jacket", "pbrMetallicRoughness": pbr((0.14, 0.2, 0.34), 0.0, 0.7)},
    ]


class Scene:
    def __init__(self):
        self.meshes = {}

    def _mesh(self, material):
        return self.meshes.setdefault(material, Mesh())

    def add(self, material, grids, R=IDENTITY, t=(0.0, 0.0, 0.0)):
        mesh = self._mesh(material)
        for g in grids:
            mesh.add_grid(g, R, t)

    def box(self, material, center, size, r, seg=3, taper=(0.0, 0.0), R=IDENTITY):
        self.add(material, rounded_box(*size, r, seg, taper), R, center)

    def ball(self, material, center, radii, R=IDENTITY, seg_u=14, seg_v=8):
        self.add(material, ellipsoid(*radii, seg_u, seg_v), R, center)

    def rod(self, material, p0, p1, radius):
        grids, R, t = capsule(p0, p1, radius)
        self.add(material, grids, R, t)

    def wheel(self, cx, cy, cz, radius, half_width, hub=0.6, side=1.0):
        """Tyre + chrome hub + dark centre cap. Axle along Z."""
        R = rot_x(90)
        c = (cx, cy, cz)
        self.add(RUBBER, disc(radius, half_width, corner=half_width * 0.85, segments=20), R, c)
        # rim faces on both sides
        self.add(CHROME, disc(radius * hub, half_width + 0.012, corner=0.02, segments=18), R, c)
        self.add(TRIM, disc(radius * hub * 0.45, half_width + 0.03, corner=0.015, segments=12), R, c)
        # bolts
        for k in range(5):
            ang = 2 * math.pi * k / 5
            for z_sign in (-1, 1):
                bx = cx + radius * hub * 0.72 * math.cos(ang)
                by = cy + radius * hub * 0.72 * math.sin(ang)
                self.ball(TRIM, (bx, by, cz + z_sign * (half_width + 0.02)), (0.02, 0.02, 0.012), seg_u=5, seg_v=3)


# --------------------------------------------------------------------------
# Vehicles
# --------------------------------------------------------------------------


def build_car(s: Scene):
    # ~4.2 m long, ~1.9 m wide (over the tyres), ~1.6 m tall
    s.box(BODY, (0, 0.72, 0), (4.1, 0.78, 1.76), 0.34)              # lower body
    s.box(BODY_DARK, (0, 0.34, 0), (3.9, 0.16, 1.7), 0.07, 3)       # sill / skirt
    s.box(GLASS, (-0.22, 1.27, 0), (2.15, 0.7, 1.58), 0.3, 3, (0.16, 0.1))  # greenhouse
    s.box(BODY, (-0.25, 1.62, 0), (1.85, 0.14, 1.44), 0.07, 3, (0.1, 0.06))  # roof
    # bumpers
    s.box(CHROME, (2.05, 0.44, 0), (0.24, 0.26, 1.66), 0.1, 3)
    s.box(CHROME, (-2.05, 0.44, 0), (0.24, 0.26, 1.66), 0.1, 3)
    # grille + plates
    s.box(TRIM, (2.06, 0.7, 0), (0.06, 0.22, 0.74), 0.03, 2)
    s.box(WHITE, (2.19, 0.44, 0), (0.02, 0.14, 0.38), 0.01, 2)
    s.box(WHITE, (-2.19, 0.44, 0), (0.02, 0.14, 0.38), 0.01, 2)
    # lights
    for z in (-0.6, 0.6):
        s.ball(HEADLIGHT, (2.0, 0.83, z), (0.1, 0.14, 0.24), seg_u=12, seg_v=8)
        s.box(TAILLIGHT, (-2.04, 0.86, z), (0.07, 0.16, 0.38), 0.03, 2)
    # mirrors, door seams, handles, antenna
    for z in (-1, 1):
        s.box(BODY, (0.5, 1.08, z * 1.0), (0.16, 0.13, 0.2), 0.05, 2)
        s.box(TRIM, (0.06, 0.9, z * 0.885), (0.03, 0.62, 0.02), 0.01, 1)
        s.box(TRIM, (-0.95, 0.9, z * 0.885), (0.03, 0.62, 0.02), 0.01, 1)
        s.box(TRIM, (0.35, 0.98, z * 0.89), (0.22, 0.04, 0.03), 0.015, 2)
    s.rod(TRIM, (-1.5, 1.66, 0.5), (-1.62, 2.1, 0.5), 0.015)
    # wheels + arches
    for x in (1.32, -1.32):
        for z in (-1, 1):
            s.add(TRIM, disc(0.47, 0.012, segments=24), rot_x(90), (x, 0.44, z * 0.885))
            s.wheel(x, 0.44, z * 0.83, 0.44, 0.16)


def build_suv(s: Scene):
    # ~4.7 m long, ~2.0 m wide, ~1.95 m tall, chunky off-roader
    s.box(BODY, (0, 0.9, 0), (4.6, 0.98, 1.92), 0.3)
    s.box(BODY_DARK, (0, 0.46, 0), (4.4, 0.2, 1.88), 0.08, 3)
    s.box(GLASS, (-0.35, 1.72, 0), (3.0, 0.82, 1.78), 0.26, 3, (0.08, 0.05))
    s.box(BODY, (-0.38, 2.14, 0), (2.7, 0.14, 1.66), 0.06, 3, (0.06, 0.04))
    s.box(BODY, (0.75, 1.42, 0), (0.05, 0.05, 1.2), 0.02, 1)  # hood line
    # roof rack
    for z in (-0.72, 0.72):
        s.rod(TRIM, (0.9, 2.28, z), (-1.7, 2.28, z), 0.03)
    for x in (0.5, -0.4, -1.3):
        s.rod(TRIM, (x, 2.28, -0.75), (x, 2.28, 0.75), 0.025)
    s.box(TRIM, (0.9, 2.38, 0), (0.16, 0.12, 1.5), 0.04, 2)      # light bar
    for z in (-0.5, -0.17, 0.17, 0.5):
        s.ball(HEADLIGHT, (1.0, 2.38, z), (0.03, 0.05, 0.06), seg_u=8, seg_v=6)
    # bumpers + bull bar
    s.box(TRIM, (2.32, 0.5, 0), (0.3, 0.32, 1.84), 0.1, 3)
    s.box(TRIM, (-2.32, 0.5, 0), (0.3, 0.32, 1.84), 0.1, 3)
    s.rod(CHROME, (2.5, 0.42, -0.7), (2.5, 0.95, -0.55), 0.045)
    s.rod(CHROME, (2.5, 0.42, 0.7), (2.5, 0.95, 0.55), 0.045)
    s.rod(CHROME, (2.5, 0.95, -0.55), (2.5, 0.95, 0.55), 0.045)
    # grille, lights
    s.box(TRIM, (2.31, 0.95, 0), (0.06, 0.34, 0.9), 0.04, 2)
    for z in (-0.7, 0.7):
        s.ball(HEADLIGHT, (2.28, 1.1, z), (0.09, 0.2, 0.2), seg_u=12, seg_v=8)
        s.box(TAILLIGHT, (-2.32, 1.2, z), (0.07, 0.34, 0.2), 0.03, 2)
    # spare wheel on the tailgate
    s.add(RUBBER, disc(0.5, 0.15, 0.1, 28), rot_z(90), (-2.55, 1.15, 0))
    s.add(CHROME, disc(0.28, 0.16, 0.02, 20), rot_z(90), (-2.55, 1.15, 0))
    s.add(BODY, disc(0.16, 0.17, 0.02, 16), rot_z(90), (-2.55, 1.15, 0))
    # mirrors, handles, arches
    for z in (-1, 1):
        s.box(TRIM, (0.85, 1.4, z * 1.05), (0.18, 0.16, 0.22), 0.05, 2)
        s.box(TRIM, (0.35, 1.2, z * 0.965), (0.03, 0.72, 0.02), 0.01, 1)
        s.box(TRIM, (-1.2, 1.2, z * 0.965), (0.03, 0.72, 0.02), 0.01, 1)
        s.box(TRIM, (0.55, 1.2, z * 0.975), (0.24, 0.05, 0.03), 0.015, 2)
    for x in (1.5, -1.5):
        for z in (-1, 1):
            s.box(BODY_DARK, (x, 0.75, z * 0.99), (1.35, 0.14, 0.14), 0.06, 2)  # flare
            s.add(TRIM, disc(0.58, 0.012, segments=24), rot_x(90), (x, 0.55, z * 0.965))
            s.wheel(x, 0.55, z * 0.9, 0.55, 0.2, hub=0.55)


def _rider(s: Scene, hip, torso_lean, head, grips, feet, jacket=JACKET):
    """A chubby, helmeted cartoon rider."""
    # torso
    s.box(jacket, (hip[0] + 0.05, hip[1] + 0.36, hip[2]), (0.42, 0.7, 0.54), 0.17, 3, R=rot_z(torso_lean))
    # helmet: white shell, dark visor, chin + top stripe
    hx, hy, hz = head
    s.ball(WHITE, (hx, hy, hz), (0.29, 0.29, 0.28), seg_u=20, seg_v=12)
    s.ball(GLASS, (hx + 0.17, hy - 0.02, hz), (0.15, 0.13, 0.22), seg_u=14, seg_v=8)
    s.box(BODY, (hx - 0.02, hy + 0.2, hz), (0.34, 0.06, 0.1), 0.03, 2)
    # arms + gloves, legs + boots
    for z_sign in (-1, 1):
        shoulder = (hip[0] + 0.12, hip[1] + 0.52, hip[2] + z_sign * 0.28)
        grip = (grips[0], grips[1], z_sign * grips[2])
        s.rod(jacket, shoulder, grip, 0.07)
        s.ball(TRIM, grip, (0.075, 0.075, 0.075), seg_u=8, seg_v=6)
        thigh_end = (feet[0] + 0.05, feet[1] + 0.4, z_sign * 0.22)
        s.rod(TRIM, (hip[0], hip[1] + 0.05, z_sign * 0.16), thigh_end, 0.09)
        s.rod(TRIM, thigh_end, (feet[0], feet[1] + 0.06, z_sign * 0.22), 0.075)
        s.box(RUBBER, (feet[0] + 0.06, feet[1] + 0.03, z_sign * 0.22), (0.3, 0.12, 0.13), 0.05, 2)


def build_bike(s: Scene):
    # a chunky cruiser/adventure motorcycle with a rider, ~2.2 m long
    for x in (0.86, -0.86):
        s.wheel(x, 0.4, 0, 0.4, 0.09, hub=0.62)
    # frame, engine, tank, seat, tail
    s.box(TRIM, (0.0, 0.55, 0), (0.62, 0.42, 0.34), 0.12, 3)                 # engine
    s.box(CHROME, (0.05, 0.36, 0), (0.34, 0.16, 0.36), 0.06, 2)              # sump
    s.ball(BODY, (0.3, 1.02, 0), (0.46, 0.25, 0.24), seg_u=18, seg_v=10)     # tank
    s.box(TRIM, (-0.4, 0.93, 0), (0.78, 0.13, 0.3), 0.06, 3)                 # seat
    s.box(BODY, (-0.95, 0.94, 0), (0.55, 0.1, 0.3), 0.05, 3, R=rot_z(8))     # tail
    s.box(TAILLIGHT, (-1.22, 0.9, 0), (0.06, 0.09, 0.22), 0.03, 2)
    s.box(BODY, (0.9, 0.82, 0), (0.62, 0.06, 0.22), 0.03, 2, R=rot_z(-6))    # front fender
    s.box(BODY, (-0.9, 0.7, 0), (0.6, 0.06, 0.2), 0.03, 2, R=rot_z(6))       # rear fender
    # fork, bars, headlight
    for z in (-0.11, 0.11):
        s.rod(CHROME, (0.86, 0.4, z), (0.6, 1.12, z), 0.035)
    s.rod(TRIM, (0.6, 1.14, -0.42), (0.6, 1.14, 0.42), 0.03)
    s.ball(HEADLIGHT, (0.8, 1.08, 0), (0.11, 0.13, 0.13), seg_u=14, seg_v=8)
    for z in (-0.4, 0.4):
        s.ball(CHROME, (0.6, 1.24, z), (0.05, 0.03, 0.05), seg_u=8, seg_v=6)
    # exhaust
    s.rod(CHROME, (0.25, 0.32, 0.2), (-1.0, 0.42, 0.22), 0.06)
    s.ball(TRIM, (-1.02, 0.42, 0.22), (0.05, 0.07, 0.07), seg_u=8, seg_v=6)
    _rider(
        s,
        hip=(-0.42, 1.0, 0),
        torso_lean=-14,
        head=(-0.06, 1.95, 0),
        grips=(0.6, 1.14, 0.4),
        feet=(0.08, 0.42, 0),
    )


def build_scooter(s: Scene):
    # a retro Vespa-style scooter with a delivery top-case and rider, ~1.9 m long
    for x in (0.78, -0.62):
        s.wheel(x, 0.27, 0, 0.27, 0.08, hub=0.62)
    s.box(BODY, (-0.5, 0.62, 0), (0.9, 0.6, 0.52), 0.24, 3)                  # rear body
    s.box(BODY_DARK, (-0.95, 0.5, 0), (0.3, 0.16, 0.4), 0.06, 3)
    s.box(BODY, (0.05, 0.3, 0), (0.86, 0.1, 0.46), 0.05, 3)                  # floorboard
    s.box(TRIM, (0.05, 0.36, 0), (0.7, 0.02, 0.36), 0.01, 1)                 # floor mat
    s.box(BODY, (0.55, 0.72, 0), (0.22, 0.86, 0.46), 0.1, 3, R=rot_z(-12))  # leg shield
    s.box(BODY, (0.74, 0.5, 0), (0.6, 0.12, 0.3), 0.05, 2, R=rot_z(-4))      # front fender
    s.box(TRIM, (-0.42, 1.0, 0), (0.6, 0.13, 0.36), 0.06, 3)                 # seat
    s.box(TAILLIGHT, (-0.98, 0.72, 0), (0.05, 0.1, 0.22), 0.025, 2)
    # steering: stem, cowl with round headlight, bars, mirrors
    s.rod(CHROME, (0.66, 1.12, 0), (0.66, 1.3, 0), 0.05)
    s.box(BODY, (0.66, 1.28, 0), (0.28, 0.2, 0.34), 0.08, 3)
    s.ball(HEADLIGHT, (0.82, 1.24, 0), (0.09, 0.13, 0.13), seg_u=14, seg_v=8)
    s.rod(TRIM, (0.62, 1.36, -0.4), (0.62, 1.36, 0.4), 0.03)
    for z in (-1, 1):
        s.rod(CHROME, (0.62, 1.38, z * 0.36), (0.56, 1.6, z * 0.44), 0.015)
        s.ball(CHROME, (0.56, 1.63, z * 0.44), (0.05, 0.035, 0.06), seg_u=8, seg_v=6)
        s.ball(CHROME, (0.62, 1.36, z * 0.42), (0.05, 0.04, 0.05), seg_u=8, seg_v=6)
    # delivery top-case
    s.box(WHITE, (-0.95, 1.2, 0), (0.55, 0.42, 0.5), 0.1, 3)
    s.box(BODY, (-0.95, 1.43, 0), (0.5, 0.05, 0.46), 0.02, 2)
    s.rod(TRIM, (-0.75, 0.98, -0.16), (-0.9, 1.0, -0.16), 0.02)
    _rider(
        s,
        hip=(-0.4, 1.06, 0),
        torso_lean=-6,
        head=(-0.26, 1.98, 0),
        grips=(0.62, 1.36, 0.4),
        feet=(0.32, 0.36, 0),
    )


# body colors mirror kVehicleOptions usage in the Flutter app.
VEHICLES = {
    "car": (build_car, (1.0, 0.42, 0.29)),        # #FF6B4A
    "suv": (build_suv, (0.61, 0.35, 0.71)),       # #9B59B6
    "bike": (build_bike, (0.23, 0.62, 0.36)),     # #3A9D5C
    "scooter": (build_scooter, (0.23, 0.55, 0.87)),  # #3A8DDE
}


# --------------------------------------------------------------------------
# GLB writer
# --------------------------------------------------------------------------


def write_glb(scene: Scene, body_rgb, path, name):
    mats = materials(body_rgb)
    binary = bytearray()
    views, accessors, primitives = [], [], []

    def pad():
        while len(binary) % 4:
            binary.append(0)

    def add_view(data, target):
        pad()
        offset = len(binary)
        binary.extend(data)
        views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": target})
        return len(views) - 1

    def add_accessor(view, component, count, kind, mins=None, maxs=None):
        acc = {"bufferView": view, "componentType": component, "count": count, "type": kind}
        if mins is not None:
            acc["min"], acc["max"] = mins, maxs
        accessors.append(acc)
        return len(accessors) - 1

    triangles = 0
    for material in sorted(scene.meshes):
        mesh = scene.meshes[material]
        if not mesh.idx:
            continue
        assert len(mesh.pos) < 65536, "uint16 index overflow"
        pos = struct.pack("<%df" % (3 * len(mesh.pos)), *[c for p in mesh.pos for c in p])
        nor = struct.pack("<%df" % (3 * len(mesh.nor)), *[c for n in mesh.nor for c in n])
        uv = struct.pack("<%df" % (2 * len(mesh.uv)), *[c for t in mesh.uv for c in t])
        idx = struct.pack("<%dH" % len(mesh.idx), *mesh.idx)
        mins = [min(p[i] for p in mesh.pos) for i in range(3)]
        maxs = [max(p[i] for p in mesh.pos) for i in range(3)]
        n = len(mesh.pos)
        primitives.append(
            {
                "attributes": {
                    "POSITION": add_accessor(add_view(pos, ARRAY_BUFFER), FLOAT, n, "VEC3", mins, maxs),
                    "NORMAL": add_accessor(add_view(nor, ARRAY_BUFFER), FLOAT, n, "VEC3"),
                    "TEXCOORD_0": add_accessor(add_view(uv, ARRAY_BUFFER), FLOAT, n, "VEC2"),
                },
                "indices": add_accessor(
                    add_view(idx, ELEMENT_ARRAY_BUFFER), UNSIGNED_SHORT, len(mesh.idx), "SCALAR"
                ),
                "material": material,
                "mode": 4,
            }
        )
        triangles += len(mesh.idx) // 3

    pad()
    gltf = {
        "asset": {"version": "2.0", "generator": "ranmap/tool/generate_vehicle_models.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": primitives}],
        "materials": mats,
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": views,
        "accessors": accessors,
    }

    json_chunk = json.dumps(gltf, separators=(",", ":")).encode()
    json_chunk += b" " * ((4 - len(json_chunk) % 4) % 4)
    bin_chunk = bytes(binary)
    total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    glb = struct.pack("<III", 0x46546C67, 2, total)
    glb += struct.pack("<II", len(json_chunk), 0x4E4F534A) + json_chunk
    glb += struct.pack("<II", len(bin_chunk), 0x004E4942) + bin_chunk
    with open(path, "wb") as fh:
        fh.write(glb)
    return triangles


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, (builder, color) in VEHICLES.items():
        scene = Scene()
        builder(scene)
        path = os.path.join(OUT_DIR, f"vehicle_{name}.glb")
        tris = write_glb(scene, color, path, f"vehicle_{name}")
        print(f"wrote {path} ({os.path.getsize(path)} bytes, {tris} triangles)")


if __name__ == "__main__":
    main()
