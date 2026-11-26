"""Rigged people (M8) -> assets/models/characters/

An original low-poly person with a skeleton, a skinned body and the animations every person in
the game shares. About 1.75 m tall, standing on the origin and facing Blender -Y (Godot +Z).

Skeleton: bone names follow Godot's SkeletonProfileHumanoid (Hips, Spine, Chest, UpperChest,
Neck, Head, LeftShoulder, LeftUpperArm, LeftLowerArm, LeftHand, LeftUpperLeg, LeftLowerLeg,
LeftFoot, LeftToes and the Right ones), so any humanoid GLB with those bones can stand in for it.
All three bodies share the one skeleton, so the animations fit each.

Body: each low-poly part is bound rigidly to one bone (the faceted, toy-like look of the city),
with joint caps at knees, elbows and shoulders; a long skirt or veshti follows the hips and
partly the legs. Materials name the colour channels the game tints per person: chr_top,
chr_bottom, chr_skin, chr_hair; the rest keep their colour.

  chr_man      shirt, trousers, shoes (the player and most men)
  chr_woman    blouse, long skirt, braid, sandals
  chr_elder    shirt, white veshti, towel over the shoulder, grey hair, sandals

Animations (seconds; * = loops): idle* 3, walk* 1.0 (1.4 m/s), run* 0.7 (4 m/s), sprint* 0.55
(6.5 m/s), jump 0.3, fall* 0.8, land 0.3, punch 0.42 (the blow at 0.16), guard* 1.2,
windup 0.45, hit 0.4, knocked 0.9, down* 2, getup 1.2, sit* 2, drive* 2, talk* 2.5.
Rotations are authored in the character's own frame (X to its left, Y backwards, Z up) and
converted to each bone's local space. The script checks a few poses (feet planted, a punch
reaching forward, lying on the ground) and fails if they are wrong.

Run:  "$BLENDER" --background --factory-startup --python tools/blender/humans.py [-- names...]
"""

import math
import os
import sys

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import rotd_mesh as rm  # noqa: E402

FPS = 30

# --------------------------------------------------------------------------- skeleton

# name: (head, tail, parent)
BONES = {
    "Hips": ((0, 0, 0.93), (0, 0, 1.03), None),
    "Spine": ((0, 0, 1.03), (0, 0, 1.16), "Hips"),
    "Chest": ((0, 0, 1.16), (0, 0, 1.29), "Spine"),
    "UpperChest": ((0, 0, 1.29), (0, 0, 1.40), "Chest"),
    "Neck": ((0, 0, 1.40), (0, 0, 1.50), "UpperChest"),
    "Head": ((0, 0, 1.50), (0, 0, 1.75), "Neck"),
}
for _side, _sx in (("Left", 1.0), ("Right", -1.0)):
    BONES.update({
        f"{_side}Shoulder": ((0.02 * _sx, 0, 1.37), (0.16 * _sx, 0, 1.39), "UpperChest"),
        f"{_side}UpperArm": ((0.195 * _sx, 0, 1.385), (0.205 * _sx, 0, 1.10), f"{_side}Shoulder"),
        f"{_side}LowerArm": ((0.205 * _sx, 0, 1.10), (0.21 * _sx, 0, 0.85), f"{_side}UpperArm"),
        f"{_side}Hand": ((0.21 * _sx, 0, 0.85), (0.21 * _sx, 0, 0.76), f"{_side}LowerArm"),
        f"{_side}UpperLeg": ((0.09 * _sx, 0, 0.92), (0.095 * _sx, 0, 0.51), "Hips"),
        f"{_side}LowerLeg": ((0.095 * _sx, 0, 0.51), (0.095 * _sx, 0.015, 0.09), f"{_side}UpperLeg"),
        f"{_side}Foot": ((0.095 * _sx, 0.015, 0.09), (0.095 * _sx, -0.09, 0.025), f"{_side}LowerLeg"),
        f"{_side}Toes": ((0.095 * _sx, -0.09, 0.025), (0.095 * _sx, -0.15, 0.02), f"{_side}Foot"),
    })


def build_armature() -> bpy.types.Object:
    data = bpy.data.armatures.new("Rig")
    rig = bpy.data.objects.new("Rig", data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (head, tail, parent) in BONES.items():
        bone = data.edit_bones.new(name)
        bone.head = head
        bone.tail = tail
        bone.roll = 0.0
        if parent:
            bone.parent = data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return rig


# --------------------------------------------------------------------------- body

class SkinBuilder(rm.MeshBuilder):
    """A MeshBuilder that remembers which bone(s) each vertex follows."""

    def __init__(self) -> None:
        super().__init__()
        self.weights: list[dict] = []

    def on(self, bone: str, build) -> None:
        start = len(self.verts)
        build()
        self.weights.extend({bone: 1.0} for _ in range(len(self.verts) - start))

    def on_blend(self, build, weigh) -> None:
        """Vertices weighted by weigh(position) -> {bone: weight}."""
        start = len(self.verts)
        build()
        self.weights.extend(weigh(self.verts[i]) for i in range(start, len(self.verts)))

    def build_skinned(self, name: str, rig: bpy.types.Object) -> bpy.types.Object:
        obj = self.build(name)
        groups = {bone: obj.vertex_groups.new(name=bone) for bone in BONES}
        for index, w in enumerate(self.weights):
            for bone, value in w.items():
                groups[bone].add([index], value, "REPLACE")
        obj.parent = rig
        modifier = obj.modifiers.new("Armature", "ARMATURE")
        modifier.object = rig
        return obj


def mats() -> dict:
    return {
        "skin": rm.material("chr_skin", "#ffffff", roughness=0.7),
        "hair": rm.material("chr_hair", "#ffffff", roughness=0.8),
        "top": rm.material("chr_top", "#ffffff", roughness=0.85),
        "bottom": rm.material("chr_bottom", "#ffffff", roughness=0.85),
        "shoe": rm.material("chr_shoes", "#2a221c", roughness=0.7),
        "sole": rm.material("chr_sole", "#3a2c22", roughness=0.8),
        "towel": rm.material("chr_towel", "#efe9dc", roughness=0.9),
        "dark": rm.material("chr_detail", "#1d1b1a", roughness=0.8),
    }


def head(sb: SkinBuilder, m: dict, hair: str) -> None:
    sb.on("Neck", lambda: sb.cylinder(0, 0, 1.39, 0.056, 0.05, 0.14, 8, m["skin"]))

    def face() -> None:
        sb.sphere((0, 0, 1.62), 0.105, 10, 6, m["skin"], squash=1.15)
        sb.box(-0.025, -0.118, 1.59, 0.025, -0.096, 1.63, m["skin"])                 # nose
        for x in (-0.04, 0.04):
            sb.box(x - 0.016, -0.102, 1.645, x + 0.016, -0.09, 1.662, m["dark"])     # eyes
        sb.box(-0.03, -0.1, 1.56, 0.03, -0.088, 1.57, m["dark"])                     # mouth
        if hair == "short":
            sb.sphere((0, 0.012, 1.655), 0.112, 10, 5, m["hair"], squash=0.9)
        elif hair == "braid":
            sb.sphere((0, 0.015, 1.65), 0.115, 10, 5, m["hair"], squash=1.0)
            sb.tube((0, 0.1, 1.6), (0, 0.135, 1.12), 0.035, 0.02, 6, m["hair"])
        else:
            sb.sphere((0, 0.03, 1.64), 0.11, 10, 5, m["hair"], squash=0.85)
    sb.on("Head", face)


def torso(sb: SkinBuilder, m: dict, shirt_top: str) -> None:
    top = m[shirt_top]
    sb.on("Spine", lambda: sb.frustum(0, 0, 1.0, 0.31, 0.19, 0.32, 0.195, 0.17, top))
    sb.on("Chest", lambda: sb.frustum(0, 0, 1.16, 0.32, 0.195, 0.35, 0.205, 0.14, top))

    def upper() -> None:
        sb.frustum(0, 0, 1.29, 0.35, 0.205, 0.38, 0.21, 0.13, top)
        sb.box(-0.045, -0.112, 1.36, 0.045, -0.1, 1.42, m["skin"])                    # open neckline
    sb.on("UpperChest", upper)


def arms(sb: SkinBuilder, m: dict, sleeve: float) -> None:
    for side, sx in (("Left", 1.0), ("Right", -1.0)):
        x0, x1, x2 = 0.2 * sx, 0.206 * sx, 0.212 * sx
        sb.on(f"{side}Shoulder", lambda x0=x0: sb.sphere((x0 * 0.92, 0, 1.38), 0.066, 8, 5, m["top"]))
        z_sleeve = 1.385 - sleeve

        def upper(x0=x0, x1=x1, z_sleeve=z_sleeve) -> None:
            sb.tube((x0, 0, 1.40), (x1, 0, z_sleeve), 0.062, 0.058, 8, m["top"])
            if z_sleeve > 1.11:
                sb.tube((x1, 0, z_sleeve + 0.01), (x1, 0, 1.08), 0.05, 0.046, 8, m["skin"])
        sb.on(f"{side}UpperArm", upper)

        def lower(x1=x1, x2=x2) -> None:
            sb.sphere((x1, 0, 1.10), 0.047, 7, 4, m["skin"])
            sb.tube((x1, 0, 1.10), (x2, 0, 0.86), 0.045, 0.038, 8, m["skin"])
        sb.on(f"{side}LowerArm", lower)
        sb.on(f"{side}Hand", lambda x2=x2: sb.box(x2 - 0.03, -0.04, 0.75, x2 + 0.03, 0.04, 0.87, m["skin"]))


def legs(sb: SkinBuilder, m: dict, covered: bool) -> None:
    for side, sx in (("Left", 1.0), ("Right", -1.0)):
        x = 0.095 * sx
        if not covered:
            sb.on(f"{side}UpperLeg", lambda x=x: sb.tube((x, 0, 0.95), (x, 0, 0.5), 0.088, 0.07, 8, m["bottom"]))

            def shin(x=x) -> None:
                sb.sphere((x, 0, 0.51), 0.07, 8, 4, m["bottom"])
                sb.tube((x, 0, 0.51), (x, 0.012, 0.085), 0.066, 0.052, 8, m["bottom"])
            sb.on(f"{side}LowerLeg", shin)
            sb.on(f"{side}Foot", lambda x=x: sb.box(x - 0.055, -0.125, 0.0, x + 0.055, 0.06, 0.09, m["shoe"]))
            sb.on(f"{side}Toes", lambda x=x: sb.box(x - 0.05, -0.17, 0.0, x + 0.05, -0.125, 0.06, m["shoe"]))
        else:
            # Under a long skirt or veshti only the shins and the feet show.
            sb.on(f"{side}LowerLeg", lambda x=x: sb.tube((x, 0, 0.5), (x, 0.012, 0.085), 0.058, 0.045, 8, m["skin"]))

            def sandal(x=x) -> None:
                sb.box(x - 0.045, -0.13, 0.03, x + 0.045, 0.04, 0.085, m["skin"])
                sb.box(x - 0.05, -0.15, 0.0, x + 0.05, 0.05, 0.03, m["sole"])
            sb.on(f"{side}Foot", sandal)


def skirt_weights(top_z: float, bottom_z: float):
    """Near the waist a skirt follows the hips; lower down, half the hips and half the leg on
    its side (a seam down the middle stays with the hips)."""
    def weigh(co: Vector) -> dict:
        t = max(0.0, min(1.0, (top_z - co.z) / (top_z - bottom_z)))
        if abs(co.x) < 0.02 or t < 0.25:
            return {"Hips": 1.0}
        leg = "LeftUpperLeg" if co.x > 0 else "RightUpperLeg"
        share = min(0.55, (t - 0.25) * 0.9)
        return {"Hips": 1.0 - share, leg: share}
    return weigh


def person(name: str, kind: str) -> None:
    rm.clear_scene()
    for arm in list(bpy.data.armatures):
        bpy.data.armatures.remove(arm)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)
    m = mats()
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.render.fps_base = 1.0
    rig = build_armature()
    sb = SkinBuilder()
    torso(sb, m, "top")
    if kind == "man":
        sb.on("Hips", lambda: sb.frustum(0, 0, 0.86, 0.32, 0.2, 0.31, 0.19, 0.16, m["bottom"], bottom=True))
        head(sb, m, "short")
        arms(sb, m, 0.28)
        legs(sb, m, covered=False)
    elif kind == "woman":
        sb.on_blend(lambda: sb.frustum(0, 0, 0.12, 0.46, 0.36, 0.32, 0.22, 0.9, m["bottom"], bottom=True), skirt_weights(1.0, 0.12))
        sb.on("Hips", lambda: sb.box(-0.165, -0.105, 0.98, 0.165, 0.105, 1.04, m["skin"]))       # waist
        head(sb, m, "braid")
        arms(sb, m, 0.16)
        legs(sb, m, covered=True)
    else:
        sb.on_blend(lambda: sb.frustum(0, 0, 0.16, 0.4, 0.31, 0.32, 0.22, 0.86, m["bottom"], bottom=True), skirt_weights(1.0, 0.16))
        sb.on("Hips", lambda: sb.box(-0.168, -0.108, 0.96, 0.168, 0.108, 1.02, m["bottom"]))     # folded waist
        sb.on("UpperChest", lambda: sb.box(0.06, -0.12, 1.12, 0.2, 0.12, 1.47, m["towel"]))      # towel over the shoulder
        head(sb, m, "grey")
        arms(sb, m, 0.28)
        legs(sb, m, covered=True)
    sb.build_skinned("Body", rig)
    for clip in CLIPS:
        make_action(rig, *clip)
    check_poses(rig, name)
    rig.animation_data.action = None
    rm.export_glb("characters", name, animations=True)


# --------------------------------------------------------------------------- posing

def char_rotation(rx: float, ry: float, rz: float) -> Quaternion:
    """A rotation in the character's frame (degrees about its X, Y, Z axes)."""
    return Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_quaternion()


def apply_pose(rig: bpy.types.Object, pose: dict) -> None:
    """Pose bones from {bone: (rx, ry, rz)} in the character's frame (relative to the parent),
    and the hips' offset "loc": (x, y, z) in metres. Bones not named go back to rest.
    Conventions: legs and arms hang down, so a negative rx swings them forward; a positive rx
    bends a knee (shin back); a negative rx bends an elbow (forearm forward); a positive rx
    leans the spine or head forward; a positive rz turns left."""
    for pb in rig.pose.bones:
        rest = pb.bone.matrix_local.to_quaternion()
        rx, ry, rz = pose.get(pb.name, (0.0, 0.0, 0.0))
        q = char_rotation(rx, ry, rz)
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = rest.inverted() @ q @ rest
        if pb.name == "Hips":
            loc = Vector(pose.get("loc", (0.0, 0.0, 0.0)))
            pb.location = rest.inverted() @ loc
        else:
            pb.location = (0.0, 0.0, 0.0)


def mix(a: dict, b: dict, t: float) -> dict:
    out = {}
    for key in set(a) | set(b):
        va = a.get(key, (0.0, 0.0, 0.0))
        vb = b.get(key, (0.0, 0.0, 0.0))
        out[key] = tuple(x + (y - x) * t for x, y in zip(va, vb))
    return out


def smooth(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def keyed(poses: list):
    """A clip from key poses [(time, pose), ...], eased between them."""
    def at(t: float) -> dict:
        for (t0, p0), (t1, p1) in zip(poses, poses[1:]):
            if t <= t1:
                return mix(p0, p1, smooth((t - t0) / max(t1 - t0, 1e-6)))
        return poses[-1][1]
    return at


def sides(bone: str, left: tuple, right: tuple | None = None) -> dict:
    """{LeftX: left, RightX: right}; right defaults to left mirrored (ry and rz flipped)."""
    if right is None:
        right = (left[0], -left[1], -left[2])
    return {f"Left{bone}": left, f"Right{bone}": right}


# Arm hanging relaxed: a little out from the body and bent at the elbow.
def relaxed_arms(extra: float = 0.0) -> dict:
    pose = {}
    pose.update(sides("UpperArm", (0.0, -6.0 - extra, 0.0)))
    pose.update(sides("LowerArm", (-12.0, 0.0, 0.0)))
    return pose


def guard_pose() -> dict:
    pose = {"Spine": (4.0, 0.0, 0.0), "Chest": (3.0, 0.0, 0.0)}
    pose.update(sides("UpperArm", (-50.0, 12.0, 0.0)))
    pose.update(sides("LowerArm", (-105.0, 0.0, 0.0)))
    pose.update(sides("Hand", (10.0, 0.0, 0.0)))
    pose.update(sides("UpperLeg", (-8.0, 0.0, 0.0)))
    pose.update(sides("LowerLeg", (14.0, 0.0, 0.0)))
    pose.update(sides("Foot", (-6.0, 0.0, 0.0)))
    pose["loc"] = (0.0, 0.0, -0.025)
    return pose


def lying_pose() -> dict:
    pose = {"Hips": (-90.0, 0.0, 0.0), "Head": (-15.0, 0.0, 8.0), "Spine": (-4.0, 0.0, 0.0)}
    pose.update(sides("UpperArm", (-10.0, -40.0, 0.0)))
    pose.update(sides("LowerArm", (-25.0, 0.0, 0.0)))
    pose.update(sides("UpperLeg", (4.0, -6.0, 0.0)))
    pose.update(sides("LowerLeg", (10.0, 0.0, 0.0)))
    pose.update(sides("Foot", (-30.0, 0.0, 0.0)))
    pose["loc"] = (0.0, 0.22, -0.8)
    return pose


def seated_pose(arms: dict) -> dict:
    pose = {"Spine": (-4.0, 0.0, 0.0)}
    pose.update(sides("UpperLeg", (-88.0, -4.0, 0.0)))
    pose.update(sides("LowerLeg", (88.0, 0.0, 0.0)))
    pose.update(arms)
    return pose


def idle(t: float) -> dict:
    b = math.sin(t / 3.0 * math.tau)
    pose = relaxed_arms(1.0 * b)
    pose["Chest"] = (1.2 * b, 0.0, 0.0)
    pose["Head"] = (1.5 * math.sin(t / 3.0 * math.tau * 2.0), 0.0, 2.0 * math.sin(t / 3.0 * math.tau))
    pose["loc"] = (0.004 * b, 0.0, 0.0)
    return pose


def gait(length: float, thigh: float, knee_swing: float, knee_stance: float, arm: float, elbow: float,
         lean: float, bob: float, sway: float):
    """A walk or run cycle `length` seconds long."""
    def at(t: float) -> dict:
        p = t / length * math.tau
        pose = {"Spine": (lean, 0.0, -sway * 0.7 * math.sin(p)), "Hips": (0.0, 0.0, sway * math.sin(p)),
                "Head": (-lean * 0.6, 0.0, sway * 0.3 * math.sin(p))}
        for side, phase in (("Left", p), ("Right", p + math.pi)):
            swing = math.sin(phase)
            th = -thigh * swing
            kn = knee_stance + knee_swing * max(0.0, math.cos(phase)) ** 1.5
            pose[f"{side}UpperLeg"] = (th, 0.0, 0.0)
            pose[f"{side}LowerLeg"] = (kn, 0.0, 0.0)
            pose[f"{side}Foot"] = (-(th + kn) * 0.75, 0.0, 0.0)
            sign = 1.0 if side == "Left" else -1.0
            pose[f"{side}UpperArm"] = (arm * swing, -6.0 * sign, 0.0)
            pose[f"{side}LowerArm"] = (-(elbow + elbow * 0.5 * max(0.0, -swing)), 0.0, 0.0)
        pose["loc"] = (0.0, 0.0, -bob * 0.5 + bob * 0.5 * math.cos(2.0 * p))
        return pose
    return at


walk = gait(1.0, 24.0, 38.0, 5.0, 18.0, 14.0, 2.0, 0.025, 4.0)
run = gait(0.7, 38.0, 75.0, 22.0, 32.0, 75.0, 9.0, 0.05, 6.0)
sprint = gait(0.55, 50.0, 95.0, 25.0, 48.0, 85.0, 15.0, 0.06, 7.0)


def fall_loop(t: float) -> dict:
    w = math.sin(t / 0.8 * math.tau)
    pose = {"Spine": (4.0, 0.0, 0.0)}
    pose.update(sides("UpperArm", (-25.0 + 6.0 * w, -38.0, 0.0)))
    pose.update(sides("LowerArm", (-30.0, 0.0, 0.0)))
    pose["LeftUpperLeg"] = (-22.0 + 8.0 * w, 0.0, 0.0)
    pose["RightUpperLeg"] = (-12.0 - 8.0 * w, 0.0, 0.0)
    pose.update(sides("LowerLeg", (32.0, 0.0, 0.0)))
    return pose


def talk_loop(t: float) -> dict:
    p = t / 2.5 * math.tau
    pose = idle(t)
    pose["RightUpperArm"] = (-22.0 - 12.0 * math.sin(p), 10.0, 0.0)
    pose["RightLowerArm"] = (-60.0 - 18.0 * math.sin(p * 2.0), 0.0, 0.0)
    pose["RightHand"] = (0.0, 0.0, 20.0 * math.sin(p * 2.0))
    pose["LeftUpperArm"] = (-8.0 - 6.0 * math.sin(p + 1.3), -8.0, 0.0)
    pose["LeftLowerArm"] = (-35.0, 0.0, 0.0)
    pose["Head"] = (4.0 * math.sin(p * 2.0), 0.0, 6.0 * math.sin(p))
    return pose


def guard_loop(t: float) -> dict:
    pose = guard_pose()
    b = math.sin(t / 1.2 * math.tau)
    pose["loc"] = (0.0, 0.0, -0.025 + 0.012 * b)
    pose["Spine"] = (4.0, 0.0, 3.0 * b)
    return pose


def punch_pose(reach: float) -> dict:
    """The right fist thrown straight out at `reach` 0-1 from the guard."""
    pose = guard_pose()
    pose["RightUpperArm"] = (-50.0 - 40.0 * reach, 12.0 - 14.0 * reach, 0.0)
    pose["RightLowerArm"] = (-105.0 + 100.0 * reach, 0.0, 0.0)
    pose["UpperChest"] = (0.0, 0.0, 22.0 * reach)
    pose["Hips"] = (0.0, 0.0, 10.0 * reach)
    pose["Head"] = (0.0, 0.0, -18.0 * reach)
    return pose


def windup_pose(drawn: float) -> dict:
    pose = guard_pose()
    pose["RightUpperArm"] = (-50.0 + 55.0 * drawn, 12.0 + 18.0 * drawn, 0.0)
    pose["RightLowerArm"] = (-105.0 - 15.0 * drawn, 0.0, 0.0)
    pose["UpperChest"] = (0.0, 0.0, -26.0 * drawn)
    pose["Hips"] = (0.0, 0.0, -10.0 * drawn)
    return pose


def hit_pose(recoil: float) -> dict:
    pose = relaxed_arms()
    pose["Spine"] = (-16.0 * recoil, 0.0, 0.0)
    pose["Chest"] = (-8.0 * recoil, 0.0, 0.0)
    pose["Head"] = (-22.0 * recoil, 0.0, 10.0 * recoil)
    pose.update(sides("UpperArm", (-15.0 * recoil, -6.0 - 28.0 * recoil, 0.0)))
    pose.update(sides("UpperLeg", (-10.0 * recoil, 0.0, 0.0)))
    pose.update(sides("LowerLeg", (16.0 * recoil, 0.0, 0.0)))
    pose["loc"] = (0.0, 0.03 * recoil, -0.03 * recoil)
    return pose


def crouch_pose(depth: float, arms_up: float) -> dict:
    pose = {"Spine": (10.0 * depth, 0.0, 0.0)}
    pose.update(sides("UpperLeg", (-45.0 * depth, 0.0, 0.0)))
    pose.update(sides("LowerLeg", (80.0 * depth, 0.0, 0.0)))
    pose.update(sides("Foot", (-35.0 * depth, 0.0, 0.0)))
    pose.update(sides("UpperArm", (-40.0 * arms_up, -10.0, 0.0)))
    pose.update(sides("LowerArm", (-20.0, 0.0, 0.0)))
    pose["loc"] = (0.0, 0.03 * depth, -0.22 * depth)
    return pose


def kneel_pose() -> dict:
    pose = {"Spine": (30.0, 0.0, 0.0), "Chest": (10.0, 0.0, 0.0)}
    pose["LeftUpperLeg"] = (-90.0, 0.0, 0.0)
    pose["LeftLowerLeg"] = (95.0, 0.0, 0.0)
    pose["RightUpperLeg"] = (-10.0, 0.0, 0.0)
    pose["RightLowerLeg"] = (100.0, 0.0, 0.0)
    pose["RightFoot"] = (40.0, 0.0, 0.0)
    pose.update(sides("UpperArm", (-30.0, -10.0, 0.0)))
    pose.update(sides("LowerArm", (-40.0, 0.0, 0.0)))
    pose["loc"] = (0.0, 0.05, -0.42)
    return pose


def sit_loop(t: float) -> dict:
    arms = {}
    arms.update(sides("UpperArm", (-28.0, -4.0, 0.0)))
    arms.update(sides("LowerArm", (-48.0, 0.0, 0.0)))
    pose = seated_pose(arms)
    pose["Chest"] = (1.0 * math.sin(t / 2.0 * math.tau), 0.0, 0.0)
    return pose


def drive_loop(t: float) -> dict:
    arms = {}
    arms.update(sides("UpperArm", (-48.0, 10.0, 0.0)))
    arms.update(sides("LowerArm", (-42.0, 0.0, 0.0)))
    pose = seated_pose(arms)
    pose["Head"] = (0.0, 0.0, 3.0 * math.sin(t / 2.0 * math.tau))
    return pose


def down_loop(t: float) -> dict:
    pose = lying_pose()
    pose["Chest"] = (-1.0 * math.sin(t / 2.0 * math.tau), 0.0, 0.0)
    return pose


# (name, seconds, loops, pose function)
CLIPS = [
    ("idle", 3.0, True, idle),
    ("walk", 1.0, True, walk),
    ("run", 0.7, True, run),
    ("sprint", 0.55, True, sprint),
    ("jump", 0.3, False, keyed([(0.0, crouch_pose(0.0, 0.0)), (0.12, crouch_pose(0.5, 0.2)), (0.3, crouch_pose(0.0, 1.0))])),
    ("fall", 0.8, True, fall_loop),
    ("land", 0.3, False, keyed([(0.0, crouch_pose(0.1, 0.6)), (0.1, crouch_pose(0.6, 0.0)), (0.3, crouch_pose(0.0, 0.0))])),
    ("punch", 0.42, False, keyed([(0.0, punch_pose(0.0)), (0.16, punch_pose(1.0)), (0.24, punch_pose(0.95)), (0.42, punch_pose(0.0))])),
    ("guard", 1.2, True, guard_loop),
    ("windup", 0.45, False, keyed([(0.0, windup_pose(0.0)), (0.2, windup_pose(1.0)), (0.45, windup_pose(1.0))])),
    ("hit", 0.4, False, keyed([(0.0, hit_pose(0.0)), (0.1, hit_pose(1.0)), (0.4, hit_pose(0.0))])),
    ("knocked", 0.9, False, keyed([(0.0, hit_pose(0.0)), (0.12, hit_pose(1.0)), (0.6, lying_pose()), (0.9, lying_pose())])),
    ("down", 2.0, True, down_loop),
    ("getup", 1.2, False, keyed([(0.0, lying_pose()), (0.45, kneel_pose()), (0.85, crouch_pose(0.4, 0.0)), (1.2, idle(0.0))])),
    ("sit", 2.0, True, sit_loop),
    ("drive", 2.0, True, drive_loop),
    ("talk", 2.5, True, talk_loop),
]


def make_action(rig: bpy.types.Object, name: str, seconds: float, loops: bool, at) -> bpy.types.Action:
    """Samples `at(t)` at FPS into a new action and puts it on its own NLA track (the glTF
    exporter writes one animation per action). A loop's last frame equals its first."""
    if rig.animation_data is None:
        rig.animation_data_create()
    action = bpy.data.actions.new(name)
    action.use_fake_user = True
    rig.animation_data.action = action
    frames = max(2, round(seconds * FPS))
    for f in range(frames + 1):
        t = seconds * f / frames if not loops else seconds * (f % frames) / frames
        apply_pose(rig, at(t))
        for pb in rig.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=f + 1)
            if pb.name == "Hips":
                pb.keyframe_insert("location", frame=f + 1)
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 1, action)
    rig.animation_data.action = None
    return action


# --------------------------------------------------------------------------- checks

def world_point(rig: bpy.types.Object, bone: str, tail: bool = True) -> Vector:
    pb = rig.pose.bones[bone]
    return rig.matrix_world @ (pb.tail if tail else pb.head)


def check_poses(rig: bpy.types.Object, name: str) -> None:
    """A few facts about the poses that must hold, or the export fails."""
    problems = []

    def posed(pose: dict) -> None:
        apply_pose(rig, pose)
        bpy.context.view_layer.update()

    posed(idle(0.0))
    for side in ("Left", "Right"):
        foot = world_point(rig, f"{side}Foot", tail=False)
        if abs(foot.z - 0.09) > 0.02:
            problems.append(f"idle: {side} ankle at {foot.z:.3f} m (expected 0.09)")
    posed(walk(0.25))                      # the left leg is forward at a quarter of the cycle
    left, right = world_point(rig, "LeftFoot", False), world_point(rig, "RightFoot", False)
    if not left.y < right.y - 0.25:
        problems.append(f"walk: at a quarter cycle the left foot should be well ahead (y {left.y:.2f} vs {right.y:.2f})")
    posed(punch_pose(1.0))
    fist = world_point(rig, "RightHand")
    if not (fist.y < -0.45 and 1.15 < fist.z < 1.6):
        problems.append(f"punch: the right fist should be out in front at chest height (at {tuple(round(v, 2) for v in fist)})")
    posed(lying_pose())
    head = world_point(rig, "Head", tail=False)
    hips = world_point(rig, "Hips", tail=False)
    feet = world_point(rig, "LeftFoot", tail=False)
    if not (head.z < 0.35 and hips.z < 0.3 and feet.z < 0.35 and head.y > hips.y > feet.y):
        problems.append(f"lying: head {tuple(round(v, 2) for v in head)}, hips {tuple(round(v, 2) for v in hips)}, feet {tuple(round(v, 2) for v in feet)}: should lie flat on the back, feet forward")
    posed(sit_loop(0.0))
    knee = world_point(rig, "LeftUpperLeg")
    if not (abs(knee.z - 0.92) < 0.08 and knee.y < -0.3):
        problems.append(f"sit: the knee should be out in front at hip height (at {tuple(round(v, 2) for v in knee)})")
    apply_pose(rig, {})
    bpy.context.view_layer.update()
    if problems:
        raise SystemExit(f"{name}: pose check failed:\n  " + "\n  ".join(problems))
    print(f"{name}: poses checked (feet, walk, punch, lying, sitting)")


BUILDERS = {
    "chr_man": lambda: person("chr_man", "man"),
    "chr_woman": lambda: person("chr_woman", "woman"),
    "chr_elder": lambda: person("chr_elder", "elder"),
}


def main() -> None:
    for name in (rm.script_args() or list(BUILDERS)):
        BUILDERS[name]()


main()
