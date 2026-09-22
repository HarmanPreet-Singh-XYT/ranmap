#!/usr/bin/env python3
"""Generate the bunded low-poly vehicle glTF models.

The repo ships no binary art, so the four vehicle models used by the 3D map
layer are generated here instead of being hand-authored. Each model is a
handful of axis-aligned boxes (body, cabin, wheels, ...) at *real-world scale*
in metres, glTF Y-up, facing +X, with the origin on the ground at the centre of
the vehicle — which is what `VehicleModelLayerManager` assumes when it places
and rotates a model at a teammate's position.

Run from the repo root:

    python3 tool/generate_vehicle_models.py

It writes assets/models/vehicle_<type>.glb. Re-run after editing a shape and
the new models are bundled on the next build (assets/models/ is listed in
pubspec.yaml).
"""

from __future__ import annotations

import json
import math
import os
import struct

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "models")

FLOAT = 5126
ARRAY_BUFFER = 34962

# Faceted (flat-shaded) shading: each face gets its own normal, so the wheels
# and body read as distinct panels instead of a smoothed blob.
FACE_NORMALS = [
    ((0, 0, 1), [(-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]),
    ((0, 0, -1), [(1, -1, -1), (-1, -1, -1), (-1, 1, -1), (1, 1, -1)]),
    ((1, 0, 0), [(1, -1, 1), (1, -1, -1), (1, 1, -1), (1, 1, 1)]),
    ((-1, 0, 0), [(-1, -1, -1), (-1, -1, 1), (-1, 1, 1), (-1, 1, -1)]),
    ((0, 1, 0), [(-1, 1, 1), (1, 1, 1), (1, 1, -1), (-1, 1, -1)]),
    ((0, -1, 0), [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1)]),
]


def _rotate_y(x: float, z: float, degrees: float) -> tuple[float, float]:
    if degrees == 0:
        return x, z
    r = math.radians(degrees)
    c, s = math.cos(r), math.sin(r)
    return x * c + z * s, -x * s + z * c


def box(cx, cy, cz, sx, sy, sz, material, rot_y=0.0):
    """Triangles for an axis-aligned (optionally Y-rotated) box."""
    hx, hy, hz = sx / 2, sy / 2, sz / 2
    positions, normals = [], []
    for normal, corners in FACE_NORMALS:
        pts = []
        for ux, uy, uz in corners:
            x, z = _rotate_y(ux * hx, uz * hz, rot_y)
            pts.append((cx + x, cy + uy * hy, cz + z))
        for a, b, c in ((0, 1, 2), (0, 2, 3)):
            for idx in (a, b, c):
                positions.append(pts[idx])
        nx, nz = _rotate_y(normal[0], normal[2], rot_y)
        for _ in range(6):
            normals.append((nx, normal[1], nz))
    return material, positions, normals


def wheel(cx, cy, cz, radius, width, material):
    """A wheel approximated as a wide, low box — reads fine at map distance."""
    return box(cx, cy, cz, width, radius * 2, radius * 2, material)


# Material palette — bodies reuse the app's per-vehicle colors (see
# core/constants/avatars.dart) so the 3D models match the rest of the UI.
BODY = 0
GLASS = 1
RUBBER = 2

MATERIALS = [
    {"name": "body", "pbrMetallicRoughness": {"baseColorFactor": [0.0, 0.0, 0.0, 1.0], "metallicFactor": 0.25, "roughnessFactor": 0.5}},
    {"name": "glass", "pbrMetallicRoughness": {"baseColorFactor": [0.09, 0.12, 0.16, 1.0], "metallicFactor": 0.35, "roughnessFactor": 0.15}},
    {"name": "rubber", "pbrMetallicRoughness": {"baseColorFactor": [0.05, 0.05, 0.06, 1.0], "metallicFactor": 0.0, "roughnessFactor": 0.95}},
]


def _body_material(rgb):
    m = json.loads(json.dumps(MATERIALS))
    m[0]["pbrMetallicRoughness"]["baseColorFactor"] = [rgb[0], rgb[1], rgb[2], 1.0]
    return m


def car(color):
    # length (X) 4.4m, width (Z) 1.8m, ~1.5m tall
    return [
        box(0.0, 0.55, 0.0, 4.4, 0.7, 1.8, BODY),
        box(-0.15, 1.05, 0.0, 2.2, 0.6, 1.66, GLASS),
        wheel(1.45, 0.3, 0.86, 0.3, 0.26, RUBBER),
        wheel(1.45, 0.3, -0.86, 0.3, 0.26, RUBBER),
        wheel(-1.45, 0.3, 0.86, 0.3, 0.26, RUBBER),
        wheel(-1.45, 0.3, -0.86, 0.3, 0.26, RUBBER),
    ]


def suv(color):
    # longer, taller, wider than the car
    return [
        box(0.0, 0.72, 0.0, 4.8, 0.95, 1.96, BODY),
        box(-0.25, 1.5, 0.0, 2.5, 0.72, 1.8, GLASS),
        box(2.15, 1.0, 0.0, 0.5, 0.5, 1.86, BODY),
        wheel(1.55, 0.38, 0.94, 0.38, 0.3, RUBBER),
        wheel(1.55, 0.38, -0.94, 0.38, 0.3, RUBBER),
        wheel(-1.55, 0.38, 0.94, 0.38, 0.3, RUBBER),
        wheel(-1.55, 0.38, -0.94, 0.38, 0.3, RUBBER),
    ]


def bike(color):
    # ~2.1m long, ~1.15m tall
    return [
        box(0.0, 0.6, 0.0, 1.3, 0.22, 0.22, BODY),
        box(0.2, 0.8, 0.0, 0.5, 0.28, 0.34, BODY),
        box(-0.4, 0.78, 0.0, 0.55, 0.16, 0.34, GLASS),
        box(0.75, 0.6, 0.0, 0.12, 0.7, 0.12, BODY),
        box(0.78, 1.06, 0.0, 0.1, 0.08, 0.66, RUBBER),
        wheel(0.82, 0.3, 0.0, 0.3, 0.14, RUBBER),
        wheel(-0.82, 0.3, 0.0, 0.3, 0.14, RUBBER),
    ]


def scooter(color):
    # ~1.75m long, ~1.2m tall
    return [
        box(-0.1, 0.3, 0.0, 1.15, 0.12, 0.5, BODY),
        box(0.55, 0.72, 0.0, 0.14, 0.8, 0.14, BODY),
        box(0.58, 1.12, 0.0, 0.1, 0.08, 0.58, RUBBER),
        box(-0.62, 0.72, 0.0, 0.4, 0.16, 0.34, GLASS),
        wheel(0.72, 0.26, 0.0, 0.26, 0.14, RUBBER),
        wheel(-0.72, 0.26, 0.0, 0.26, 0.14, RUBBER),
    ]


def build_glb(parts, body_rgb, path):
    materials = _body_material(body_rgb)

    # Group triangles by material into one primitive per material.
    per_material: dict[int, tuple[list, list]] = {}
    for material, positions, normals in parts:
        store = per_material.setdefault(material, ([], []))
        store[0].extend(positions)
        store[1].extend(normals)

    binary = bytearray()
    buffer_views, accessors, primitives = [], [], []

    def add_view(data: bytes) -> int:
        while len(binary) % 4:
            binary.append(0)
        offset = len(binary)
        binary.extend(data)
        buffer_views.append({"buffer": 0, "byteOffset": offset, "byteLength": len(data), "target": ARRAY_BUFFER})
        return len(buffer_views) - 1

    def add_accessor(view: int, count: int, mins=None, maxs=None) -> int:
        accessor = {"bufferView": view, "componentType": FLOAT, "count": count, "type": "VEC3"}
        if mins is not None:
            accessor["min"] = mins
            accessor["max"] = maxs
        accessors.append(accessor)
        return len(accessors) - 1

    for material, (positions, normals) in sorted(per_material.items()):
        pos_view = add_view(struct.pack("<%df" % (len(positions) * 3), *[c for p in positions for c in p]))
        nor_view = add_view(struct.pack("<%df" % (len(normals) * 3), *[c for n in normals for c in n]))
        mins = [min(p[i] for p in positions) for i in range(3)]
        maxs = [max(p[i] for p in positions) for i in range(3)]
        primitives.append({
            "attributes": {
                "POSITION": add_accessor(pos_view, len(positions), mins, maxs),
                "NORMAL": add_accessor(nor_view, len(normals)),
            },
            "material": material,
            "mode": 4,
        })

    gltf = {
        "asset": {"version": "2.0", "generator": "ranmap/tool/generate_vehicle_models.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0}],
        "meshes": [{"primitives": primitives}],
        "materials": materials,
        "buffers": [{"byteLength": len(binary)}],
        "bufferViews": buffer_views,
        "accessors": accessors,
    }

    json_chunk = json.dumps(gltf, separators=(",", ":")).encode()
    json_chunk += b" " * ((4 - len(json_chunk) % 4) % 4)
    bin_chunk = bytes(binary)
    bin_chunk += b"\x00" * ((4 - len(bin_chunk) % 4) % 4)

    total = 12 + 8 + len(json_chunk) + 8 + len(bin_chunk)
    glb = struct.pack("<III", 0x46546C67, 2, total)
    glb += struct.pack("<II", len(json_chunk), 0x4E4F534A) + json_chunk
    glb += struct.pack("<II", len(bin_chunk), 0x004E4942) + bin_chunk
    with open(path, "wb") as fh:
        fh.write(glb)


# body colors mirror kVehicleOptions usage in the Flutter app.
VEHICLES = {
    "car": (car, (1.0, 0.42, 0.29)),      # #FF6B4A
    "bike": (bike, (0.23, 0.62, 0.36)),   # #3A9D5C
    "scooter": (scooter, (0.23, 0.55, 0.87)),  # #3A8DDE
    "suv": (suv, (0.61, 0.35, 0.71)),     # #9B59B6
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, (factory, color) in VEHICLES.items():
        path = os.path.join(OUT_DIR, f"vehicle_{name}.glb")
        build_glb(factory(color), color, path)
        print(f"wrote {path} ({os.path.getsize(path)} bytes)")


if __name__ == "__main__":
    main()
