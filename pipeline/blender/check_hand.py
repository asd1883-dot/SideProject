# -*- coding: utf-8 -*-
# 손가락별 웨이트 색칠 렌더 + 통계
#   blender -b --factory-startup -P hand_weights.py -- --glb X.glb --out prefix --action Sprint_Loop --time 0.417
import bpy, sys, os, json, math
from mathutils import Vector, Matrix

a = sys.argv[sys.argv.index("--") + 1:]
opt = {a[i][2:]: a[i + 1] for i in range(0, len(a) - 1, 2) if a[i].startswith("--")}
glb, out = opt["glb"], opt["out"]
action_name = opt.get("action", "Sprint_Loop")
t_sec = float(opt.get("time", "0.417"))
side = opt.get("side", "l")

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=glb)
arm = next(o for o in sc.objects if o.type == "ARMATURE")
meshes = [o for o in sc.objects if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)]

COL = {"thumb": (1, 0.1, 0.1), "index": (0.1, 0.9, 0.1), "middle": (0.15, 0.35, 1), "ring": (1, 0.9, 0.1),
       "pinky": (1, 0.2, 1), "hand": (0.75, 0.75, 0.75), "lowerarm": (0.3, 0.3, 0.3)}

stats = {}
for o in meshes:
    me = o.data
    gname = {g.index: g.name for g in o.vertex_groups}
    if "dom" in me.color_attributes:
        me.color_attributes.remove(me.color_attributes["dom"])
    ca = me.color_attributes.new("dom", "FLOAT_COLOR", "POINT")
    for v in me.vertices:
        c = (0.12, 0.12, 0.12)
        if v.groups:
            g = max(v.groups, key=lambda g: g.weight)
            n = gname.get(g.group, "")
            for k in COL:
                if n.startswith(k + "_") and n.endswith("_" + side) or n == k + "_" + side:
                    c = COL[k]
                    stats[k] = stats.get(k, 0) + 1
                    break
        ca.data[v.index].color = (c[0], c[1], c[2], 1.0)
    me.color_attributes.active_color = ca

# 엄지 웨이트(합) 분포 — 엄지 뼈 웨이트를 조금이라도 받는 정점 수 · 0.5 넘는 수 · 손바닥(hand_) 이 최대인데 엄지 웨이트 > 0.2 인 수
tw = {"any": 0, "gt05": 0, "palm_with_thumb": 0}
for o in meshes:
    gname = {g.index: g.name for g in o.vertex_groups}
    for v in o.data.vertices:
        w = sum(g.weight for g in v.groups if gname.get(g.group, "").startswith("thumb_") and gname[g.group].endswith("_" + side))
        if w > 0.01:
            tw["any"] += 1
        if w > 0.5:
            tw["gt05"] += 1
        if v.groups:
            best = gname.get(max(v.groups, key=lambda g: g.weight).group, "")
            if best == "hand_" + side and w > 0.2:
                tw["palm_with_thumb"] += 1
stats["thumb_weight"] = tw

sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "VERTEX"
sc.render.resolution_x = 700
sc.render.resolution_y = 700
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new("w") if sc.world is None else sc.world

cam_d = bpy.data.cameras.new("cam")
cam_d.type = "ORTHO"
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam


def hand_center():
    pb = arm.pose.bones.get("hand_" + side)
    mid = arm.pose.bones.get("middle_02_" + side) or arm.pose.bones.get("middle_01_" + side)
    h = arm.matrix_world @ pb.head
    m = arm.matrix_world @ mid.head if mid else h
    return (h + m) / 2


def shoot(tag, views):
    bpy.context.view_layer.update()
    c = hand_center()
    for vn, d in views:
        d = Vector(d).normalized()
        cam.location = c + d * 1.0
        cam.rotation_euler = (-d).to_track_quat("-Z", "Z" if abs(d.z) < 0.9 else "Y").to_euler()
        cam_d.ortho_scale = 0.26
        sc.render.filepath = "%s_%s_%s.png" % (out, tag, vn)
        bpy.ops.render.render(write_still=True)


views = [("front", (0, -1, 0)), ("top", (0, 0, 1)), ("bottom", (0, 0, -1)), ("side", (1 if side == "l" else -1, 0, 0))]
arm.data.pose_position = "REST"
if "view" not in opt:
    shoot("rest", views)

act = bpy.data.actions.get(action_name)
if act is None:
    cand = [x for x in bpy.data.actions if action_name.lower() in x.name.lower()]
    act = cand[0] if cand else None
if act is not None:
    arm.data.pose_position = "POSE"
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    fps = sc.render.fps / sc.render.fps_base
    f = act.frame_range[0] + t_sec * fps
    sc.frame_set(int(f), subframe=f - int(f))
    # 카메라는 옆(-55° 쯤)에서 — 굽기 시점과 비슷하게: 사용자 yaw -55
    yaw = math.radians(-55)
    sd = (math.sin(yaw), -math.cos(yaw), 0.0)
    views2 = [("front", (0, -1, 0)), ("yaw55", sd), ("side", (1, 0, 0)), ("side2", (-1, 0, 0))]
    if "view" in opt:
        views2 = [("bake", tuple(float(x) for x in opt["view"].split(",")))]
    shoot("pose", views2)
    stats["action"] = act.name
    stats["frame"] = f
print("HANDSTATS " + json.dumps(stats))
