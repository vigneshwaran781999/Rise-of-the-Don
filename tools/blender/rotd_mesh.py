"""Shared helpers for the RISE OF THE DON Blender generator scripts.

Coordinates here are Blender's: X right, Y "into the screen", Z up, 1 unit = 1 metre.
The glTF exporter converts to Godot's Y-up:  Blender (x, y, z)  ->  Godot (x, z, -y).
So geometry facing Blender -Y ends up facing Godot +Z. Every generator builds its
"front" facing Blender -Y, which means "front faces +Z" once imported into Godot.

Geometry is built with MeshBuilder (plain vertex/face lists, flat shaded, box-projected
UVs) and turned into one Blender object per call to build(). No bpy.ops calls are used
except the glTF export, so the scripts behave the same in --background mode.
"""

from __future__ import annotations

import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
MODELS_DIR = os.path.join(PROJECT_ROOT, "assets", "models")


# --------------------------------------------------------------------------- scene / io

def script_args() -> list[str]:
    """Arguments passed after the `--` separator on the Blender command line."""
    if "--" in sys.argv:
        return sys.argv[sys.argv.index("--") + 1:]
    return []


def clear_scene() -> None:
    """Remove every object, mesh and material so the next asset starts clean."""
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        bpy.data.meshes.remove(mesh)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)
    for cam in list(bpy.data.cameras):
        bpy.data.cameras.remove(cam)
    for light in list(bpy.data.lights):
        bpy.data.lights.remove(light)


def export_glb(category: str, file_stem: str, animations: bool = False) -> str:
    """Export everything in the scene to assets/models/<category>/<file_stem>.glb. With
    `animations`, each NLA track becomes one animation (rigged characters, M8); skinned meshes
    keep their armature modifier (not applied)."""
    out_dir = os.path.join(MODELS_DIR, category)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, file_stem + ".glb")
    options = {}
    if animations:
        options = {"export_animation_mode": "NLA_TRACKS", "export_skins": True, "export_force_sampling": True}
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=False,
        export_apply=not animations,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
        export_animations=animations,
        export_materials="EXPORT",
        **options,
    )
    tris = 0
    for obj in bpy.data.objects:
        if obj.type == "MESH":
            tris += sum(len(p.vertices) - 2 for p in obj.data.polygons)
    print(f"EXPORTED {os.path.relpath(path, PROJECT_ROOT)}  ({tris} tris incl. collision)")
    return path


# --------------------------------------------------------------------------- materials

def _srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_color(value: str) -> tuple[float, float, float]:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) / 255.0 for i in (0, 2, 4))  # type: ignore[return-value]


def material(name: str, color: str, roughness: float = 0.85, metallic: float = 0.0,
             emission: str | None = None, emission_strength: float = 1.0,
             double_sided: bool = False) -> bpy.types.Material:
    """Get or create a Principled BSDF material. `color` and `emission` are sRGB hex strings."""
    existing = bpy.data.materials.get(name)
    if existing is not None:
        return existing
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    rgb = tuple(_srgb_to_linear(c) for c in hex_color(color))
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    if emission is not None:
        erg = tuple(_srgb_to_linear(c) for c in hex_color(emission))
        emission_input = bsdf.inputs.get("Emission Color") or bsdf.inputs.get("Emission")
        emission_input.default_value = (*erg, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    mat.diffuse_color = (*rgb, 1.0)
    mat.use_backface_culling = not double_sided
    return mat


# --------------------------------------------------------------------------- mesh builder

def _newell_normal(pts: list[Vector]) -> Vector:
    n = Vector((0.0, 0.0, 0.0))
    for i, a in enumerate(pts):
        b = pts[(i + 1) % len(pts)]
        n.x += (a.y - b.y) * (a.z + b.z)
        n.y += (a.z - b.z) * (a.x + b.x)
        n.z += (a.x - b.x) * (a.y + b.y)
    return n.normalized() if n.length > 1e-9 else n


class MeshBuilder:
    """Accumulates flat-shaded polygons with per-face materials, then builds one object."""

    def __init__(self) -> None:
        self.verts: list[Vector] = []
        self.faces: list[list[int]] = []
        self.face_mats: list[int] = []
        self.materials: list[bpy.types.Material] = []

    # ---- low level

    def _mat_index(self, mat: bpy.types.Material) -> int:
        if mat not in self.materials:
            self.materials.append(mat)
        return self.materials.index(mat)

    def face(self, pts, mat: bpy.types.Material, outward: Vector | None = None,
             inside: Vector | None = None) -> None:
        """Add one polygon. Winding is fixed so its normal points along `outward`,
        or away from the point `inside`. With neither, the given order is kept."""
        p = [Vector(v) for v in pts]
        n = _newell_normal(p)
        if outward is not None and n.dot(Vector(outward)) < 0.0:
            p.reverse()
        elif inside is not None:
            centre = sum(p, Vector()) / len(p)
            if n.dot(centre - Vector(inside)) < 0.0:
                p.reverse()
        base = len(self.verts)
        self.verts.extend(p)
        self.faces.append(list(range(base, base + len(p))))
        self.face_mats.append(self._mat_index(mat))

    def mark(self) -> int:
        """Remember the current vertex count; pass it to transform_since()."""
        return len(self.verts)

    def transform_since(self, mark: int, matrix: Matrix) -> None:
        for i in range(mark, len(self.verts)):
            self.verts[i] = matrix @ self.verts[i]

    # ---- primitives

    def box(self, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float,
            mat: bpy.types.Material, skip: tuple[str, ...] = ()) -> None:
        """Axis-aligned box from min to max corner. `skip` drops faces:
        'top', 'bottom', 'front' (-Y), 'back' (+Y), 'left' (-X), 'right' (+X)."""
        x0, x1 = min(x0, x1), max(x0, x1)
        y0, y1 = min(y0, y1), max(y0, y1)
        z0, z1 = min(z0, z1), max(z0, z1)
        quads = {
            "bottom": [(x0, y0, z0), (x0, y1, z0), (x1, y1, z0), (x1, y0, z0)],
            "top": [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],
            "front": [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],
            "back": [(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)],
            "left": [(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)],
            "right": [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)],
        }
        for name, quad in quads.items():
            if name not in skip:
                self.face(quad, mat)

    def box_c(self, cx: float, cy: float, z0: float, sx: float, sy: float, h: float,
              mat: bpy.types.Material, skip: tuple[str, ...] = ()) -> None:
        """Box with its base centred on (cx, cy, z0)."""
        self.box(cx - sx / 2, cy - sy / 2, z0, cx + sx / 2, cy + sy / 2, z0 + h, mat, skip)

    def frustum(self, cx: float, cy: float, z0: float, sx0: float, sy0: float,
                sx1: float, sy1: float, h: float, mat: bpy.types.Material,
                bottom: bool = False) -> None:
        """Tapered box: base sx0 x sy0 at z0, top sx1 x sy1 at z0 + h."""
        b = [(cx - sx0 / 2, cy - sy0 / 2, z0), (cx + sx0 / 2, cy - sy0 / 2, z0),
             (cx + sx0 / 2, cy + sy0 / 2, z0), (cx - sx0 / 2, cy + sy0 / 2, z0)]
        z1 = z0 + h
        t = [(cx - sx1 / 2, cy - sy1 / 2, z1), (cx + sx1 / 2, cy - sy1 / 2, z1),
             (cx + sx1 / 2, cy + sy1 / 2, z1), (cx - sx1 / 2, cy + sy1 / 2, z1)]
        inside = Vector((cx, cy, z0 + h * 0.5))
        for i in range(4):
            j = (i + 1) % 4
            self.face([b[i], b[j], t[j], t[i]], mat, inside=inside)
        if sx1 > 1e-6 and sy1 > 1e-6:
            self.face(t, mat, inside=inside)
        if bottom:
            self.face(b, mat, inside=inside)

    def tube(self, p0, p1, r0: float, r1: float, segments: int, mat: bpy.types.Material,
             caps: bool = True, cap_mat: bpy.types.Material | None = None) -> None:
        """Cylinder/cone between two points (r1 = 0 makes a cone)."""
        a, b = Vector(p0), Vector(p1)
        axis = (b - a).normalized()
        helper = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
        u = axis.cross(helper).normalized()
        v = axis.cross(u).normalized()
        ring0, ring1 = [], []
        for i in range(segments):
            ang = 2.0 * math.pi * i / segments
            d = u * math.cos(ang) + v * math.sin(ang)
            ring0.append(a + d * r0)
            ring1.append(b + d * r1)
        inside = (a + b) * 0.5
        for i in range(segments):
            j = (i + 1) % segments
            if r1 > 1e-6:
                self.face([ring0[i], ring0[j], ring1[j], ring1[i]], mat, inside=inside)
            else:
                self.face([ring0[i], ring0[j], b], mat, inside=inside)
        if caps:
            cm = cap_mat or mat
            self.face(ring0, cm, outward=-axis)
            if r1 > 1e-6:
                self.face(ring1, cm, outward=axis)

    def cylinder(self, cx: float, cy: float, z0: float, r0: float, r1: float, h: float,
                 segments: int, mat: bpy.types.Material, caps: bool = True) -> None:
        self.tube((cx, cy, z0), (cx, cy, z0 + h), r0, r1, segments, mat, caps)

    def sphere(self, centre, r: float, segments: int, rings: int, mat: bpy.types.Material,
               squash: float = 1.0) -> None:
        c = Vector(centre)
        rows = []
        for ri in range(1, rings):
            phi = math.pi * ri / rings
            row = []
            for si in range(segments):
                th = 2.0 * math.pi * si / segments
                row.append(c + Vector((r * math.sin(phi) * math.cos(th),
                                       r * math.sin(phi) * math.sin(th),
                                       r * math.cos(phi) * squash)))
            rows.append(row)
        top = c + Vector((0, 0, r * squash))
        bot = c - Vector((0, 0, r * squash))
        for si in range(segments):
            sj = (si + 1) % segments
            self.face([top, rows[0][si], rows[0][sj]], mat, inside=c)
            self.face([bot, rows[-1][sj], rows[-1][si]], mat, inside=c)
            for ri in range(len(rows) - 1):
                self.face([rows[ri][si], rows[ri + 1][si], rows[ri + 1][sj], rows[ri][sj]], mat, inside=c)

    def prism(self, profile, axis: str, a0: float, a1: float, mat: bpy.types.Material,
              ends: bool = True) -> None:
        """Extrude a convex 2D profile along 'X' or 'Y' from a0 to a1.
        For axis 'X' the profile points are (y, z); for axis 'Y' they are (x, z)."""
        def p3(pt, a):
            return Vector((a, pt[0], pt[1])) if axis == "X" else Vector((pt[0], a, pt[1]))
        n = len(profile)
        cu = sum(p[0] for p in profile) / n
        cz = sum(p[1] for p in profile) / n
        inside = p3((cu, cz), (a0 + a1) * 0.5)
        for i in range(n):
            j = (i + 1) % n
            self.face([p3(profile[i], a0), p3(profile[j], a0), p3(profile[j], a1), p3(profile[i], a1)],
                      mat, inside=inside)
        if ends:
            self.face([p3(p, a0) for p in profile], mat, inside=inside)
            self.face([p3(p, a1) for p in profile], mat, inside=inside)

    def convex_hull(self, points, mat: bpy.types.Material) -> None:
        """Add the convex hull of a point cloud (used for bevelled collision shapes)."""
        import bmesh
        bm = bmesh.new()
        for p in points:
            bm.verts.new(Vector(p))
        bmesh.ops.convex_hull(bm, input=list(bm.verts))
        centre = sum((Vector(p) for p in points), Vector()) / len(points)
        for f in bm.faces:
            self.face([v.co.copy() for v in f.verts], mat, inside=centre)
        bm.free()

    # ---- output

    def build(self, name: str) -> bpy.types.Object:
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        mesh.update()
        for mat in self.materials:
            mesh.materials.append(mat)
        for poly, mi in zip(mesh.polygons, self.face_mats):
            poly.material_index = mi
            poly.use_smooth = False
        uv = mesh.uv_layers.new(name="UVMap")
        for poly in mesh.polygons:
            n = poly.normal
            ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
            for li in poly.loop_indices:
                co = mesh.vertices[mesh.loops[li].vertex_index].co
                if az >= ax and az >= ay:
                    uv.data[li].uv = (co.x * 0.25, co.y * 0.25)
                elif ax >= ay:
                    uv.data[li].uv = (co.y * 0.25, co.z * 0.25)
                else:
                    uv.data[li].uv = (co.x * 0.25, co.z * 0.25)
        mesh.validate()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def collision_material() -> bpy.types.Material:
    """Collision-only meshes still need a material slot for a clean export."""
    return material("collision", "#ff00ff", double_sided=False)


class CollisionSet:
    """Collision for one asset as separate convex pieces. Each piece is exported as its own
    '<name>_cNN-convcolonly' object, so Godot's importer gives it its own convex shape. Unlike
    one '-colonly' trimesh, touching pieces never fuse when the district builder turns them
    into convex hulls (a gateway passage between two piers stays open)."""

    def __init__(self, name: str) -> None:
        self.name = name
        self.parts: list[MeshBuilder] = []

    def _new(self) -> MeshBuilder:
        mb = MeshBuilder()
        self.parts.append(mb)
        return mb

    def box(self, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> None:
        self._new().box(x0, y0, z0, x1, y1, z1, collision_material())

    def hull(self, points) -> None:
        self._new().convex_hull(points, collision_material())

    def frustum(self, cx: float, cy: float, z0: float, sx0: float, sy0: float,
                sx1: float, sy1: float, h: float) -> None:
        self._new().frustum(cx, cy, z0, sx0, sy0, sx1, sy1, h, collision_material(), bottom=True)

    def build(self) -> None:
        for i, mb in enumerate(self.parts):
            mb.build(f"{self.name}_c{i:02d}-convcolonly")


# --------------------------------------------------------------------------- block letters

# 5-row block letters for signs (shop boards, rooftop signs, neon). "#" is a pixel.
PIXEL_FONT = {
    " ": ("..", "..", "..", "..", ".."),
    "A": ("###", "#.#", "###", "#.#", "#.#"),
    "B": ("##.", "#.#", "##.", "#.#", "##."),
    "C": ("###", "#..", "#..", "#..", "###"),
    "D": ("##.", "#.#", "#.#", "#.#", "##."),
    "E": ("###", "#..", "###", "#..", "###"),
    "F": ("###", "#..", "##.", "#..", "#.."),
    "G": ("###", "#..", "#.#", "#.#", "###"),
    "H": ("#.#", "#.#", "###", "#.#", "#.#"),
    "I": ("###", ".#.", ".#.", ".#.", "###"),
    "J": ("..#", "..#", "..#", "#.#", "###"),
    "K": ("#.#", "#.#", "##.", "#.#", "#.#"),
    "L": ("#..", "#..", "#..", "#..", "###"),
    "M": ("#...#", "##.##", "#.#.#", "#...#", "#...#"),
    "N": ("#..#", "##.#", "#.##", "#..#", "#..#"),
    "O": ("###", "#.#", "#.#", "#.#", "###"),
    "P": ("###", "#.#", "###", "#..", "#.."),
    "Q": ("###", "#.#", "#.#", "###", "..#"),
    "R": ("##.", "#.#", "##.", "#.#", "#.#"),
    "S": ("###", "#..", "###", "..#", "###"),
    "T": ("###", ".#.", ".#.", ".#.", ".#."),
    "U": ("#.#", "#.#", "#.#", "#.#", "###"),
    "V": ("#.#", "#.#", "#.#", "#.#", ".#."),
    "W": ("#...#", "#...#", "#.#.#", "##.##", "#...#"),
    "X": ("#.#", "#.#", ".#.", "#.#", "#.#"),
    "Y": ("#.#", "#.#", ".#.", ".#.", ".#."),
    "Z": ("###", "..#", ".#.", "#..", "###"),
}


def text_width(text: str, pixel: float) -> float:
    return sum((len(PIXEL_FONT[ch][0]) + 1) * pixel for ch in text) - pixel


def pixel_text(mb: MeshBuilder, text: str, x_centre: float, y_front: float, z_bottom: float, pixel: float,
               material, depth: float = 0.03) -> None:
    """Block letters (PIXEL_FONT) standing just in front of the plane y = y_front, reading left to
    right for someone looking at it from the front (-Y side), one pixel apart. Each run of pixels
    in a row is one box, `depth` thick."""
    x = x_centre - text_width(text, pixel) / 2
    for ch in text:
        glyph = PIXEL_FONT[ch]
        cols = len(glyph[0])
        for r, row in enumerate(glyph):
            z_top = z_bottom + (5 - r) * pixel
            c = 0
            while c < cols:
                if row[c] != "#":
                    c += 1
                    continue
                end = c
                while end < cols and row[end] == "#":
                    end += 1
                mb.box(x + c * pixel, y_front - depth, z_top - pixel, x + end * pixel, y_front, z_top, material, skip=("back",))
                c = end
        x += (cols + 1) * pixel
