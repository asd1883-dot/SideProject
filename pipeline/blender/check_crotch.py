# -*- coding: utf-8 -*-
# 사타구니 리깅 진단: 정점마다 가장 센 뼈로 색칠(골반 회색 · 왼 허벅지 초록 · 오른 허벅지 파랑 · 몸통 노랑 · 그 밖 어둡게)
# + Sprint 레스트 프레임에서 면이 레스트보다 많이 늘어난 곳(빨강) + 통계(반대쪽 다리 뼈를 가진 정점 · 늘어난 면)
#   blender -b --factory-startup -P crotch_weights.py -- --glb X.glb --out prefix [--time 0.417]
import bpy, sys, json, math
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
opt = {a[i][2:]: a[i + 1] for i in range(0, len(a) - 1, 2) if a[i].startswith("--")}
glb, out = opt["glb"], opt["out"]
t_sec = float(opt.get("time", "0.417"))

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=glb)
arm = next(o for o in sc.objects if o.type == "ARMATURE")
meshes = [o for o in sc.objects if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)]
M = arm.matrix_world
pelvis = M @ arm.data.bones["pelvis"].head_local
thl = M @ arm.data.bones["thigh_l"].head_local
thr = M @ arm.data.bones["thigh_r"].head_local
calf_y = (M @ arm.data.bones["calf_l"].head_local).z
print("BONES pelvis", tuple(round(x, 3) for x in pelvis), "thigh_l", tuple(round(x, 3) for x in thl), "thigh_r", tuple(round(x, 3) for x in thr))
lx = 1.0 if thl.x > pelvis.x else -1.0      # 왼다리가 있는 x 쪽


def cls(n):
    if n == "pelvis":
        return "pelvis"
    if n.startswith(("thigh_l", "thigh_twist_01_l", "thigh_twist_l")):
        return "thigh_l"
    if n.startswith(("thigh_r", "thigh_twist_01_r", "thigh_twist_r")):
        return "thigh_r"
    if n.startswith("spine"):
        return "spine"
    if n.startswith(("calf", "foot", "ball")):
        return "leg_low"
    return "other"


COL = {"pelvis": (0.7, 0.7, 0.7), "thigh_l": (0.1, 0.85, 0.2), "thigh_r": (0.15, 0.35, 1.0), "spine": (1.0, 0.85, 0.1),
       "leg_low": (0.35, 0.25, 0.15), "other": (0.12, 0.12, 0.12)}

stats = {"cross_l_on_right": 0, "cross_r_on_left": 0, "crotch_verts": 0, "crotch_mixed_lr": 0}
rest_co = {}
for o in meshes:
    me = o.data
    gname = {g.index: g.name for g in o.vertex_groups}
    ca = me.color_attributes.new("dom", "FLOAT_COLOR", "POINT")
    for v in me.vertices:
        p = o.matrix_world @ v.co
        c = COL["other"]
        if v.groups:
            g = max(v.groups, key=lambda g: g.weight)
            k = cls(gname.get(g.group, ""))
            c = COL[k]
            side = (p.x - pelvis.x) * lx      # + = 왼다리 쪽
            in_crotch = calf_y < p.z < pelvis.z + 0.05 and abs(p.x - pelvis.x) < 0.12
            if in_crotch:
                stats["crotch_verts"] += 1
                wl = sum(gg.weight for gg in v.groups if cls(gname.get(gg.group, "")) == "thigh_l")
                wr = sum(gg.weight for gg in v.groups if cls(gname.get(gg.group, "")) == "thigh_r")
                if wl > 0.15 and wr > 0.15:
                    stats["crotch_mixed_lr"] += 1
            if k == "thigh_l" and side < -0.01:
                stats["cross_l_on_right"] += 1
            if k == "thigh_r" and side > 0.01:
                stats["cross_r_on_left"] += 1
        ca.data[v.index].color = (c[0], c[1], c[2], 1.0)
    me.color_attributes.active_color = ca
    rest_co[o.name] = [o.matrix_world @ v.co for v in me.vertices]

sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.render.resolution_x = 640
sc.render.resolution_y = 640
cam_d = bpy.data.cameras.new("cam")
cam_d.type = "ORTHO"
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam


def shoot(tag, views, color_type, attr=None):
    sc.display.shading.color_type = color_type
    for o in meshes:
        if attr and attr in o.data.color_attributes:
            o.data.color_attributes.active_color = o.data.color_attributes[attr]
    bpy.context.view_layer.update()
    c = (M @ arm.pose.bones["pelvis"].head) + Vector((0, 0, -0.12))
    for vn, d in views:
        d = Vector(d).normalized()
        cam.location = c + d * 2.0
        cam.rotation_euler = (-d).to_track_quat("-Z", "Z" if abs(d.z) < 0.9 else "Y").to_euler()
        cam_d.ortho_scale = 0.62
        sc.render.filepath = "%s_%s_%s.png" % (out, tag, vn)
        bpy.ops.render.render(write_still=True)


yaw = math.radians(-55)
bake = (math.sin(yaw), -math.cos(yaw), 0.0)
views = [("front", (0, -1, 0)), ("bake", bake), ("back", (0, 1, 0)), ("low", (0, -1, -0.8))]
arm.data.pose_position = "REST"
shoot("rest", views[:1], "VERTEX", "dom")

act = bpy.data.actions.get("Sprint_Loop") or next((x for x in bpy.data.actions if "sprint" in x.name.lower()), None)
arm.data.pose_position = "POSE"
if arm.animation_data is None:
    arm.animation_data_create()
arm.animation_data.action = act
fps = sc.render.fps / sc.render.fps_base
f = act.frame_range[0] + t_sec * fps
sc.frame_set(int(f), subframe=f - int(f))
deps = bpy.context.evaluated_depsgraph_get()
stretched = 0
worst = []
for o in meshes:
    ev = o.evaluated_get(deps)
    em = ev.to_mesh()
    posed = [ev.matrix_world @ v.co for v in em.vertices]
    ev.to_mesh_clear()
    rc = rest_co[o.name]
    sa = o.data.color_attributes.new("stretch", "FLOAT_COLOR", "POINT")
    dom = o.data.color_attributes["dom"]
    for v in o.data.vertices:
        c = dom.data[v.index].color
        sa.data[v.index].color = (c[0] * 0.5 + 0.25, c[1] * 0.5 + 0.25, c[2] * 0.5 + 0.25, 1.0)
    for poly in o.data.polygons:
        vs = list(poly.vertices)
        ratio = 0.0
        for i in range(len(vs)):
            a_, b_ = vs[i], vs[(i + 1) % len(vs)]
            lr = (rc[a_] - rc[b_]).length
            lp = (posed[a_] - posed[b_]).length
            if lr > 1e-5:
                ratio = max(ratio, lp / lr)
        cz = sum((rc[i].z for i in vs)) / len(vs)
        cx = sum((rc[i].x for i in vs)) / len(vs)
        if ratio > 1.8 and calf_y < cz < pelvis.z + 0.08 and abs(cx - pelvis.x) < 0.2:
            stretched += 1
            worst.append(round(ratio, 2))
            for i in vs:
                sa.data[i].color = (1.0, 0.0, 0.0, 1.0)
    o.data.color_attributes.active_color = sa
stats["stretched_faces_hip_region(>1.8x)"] = stretched
stats["worst_ratios"] = sorted(worst, reverse=True)[:8]
shoot("pose", views, "VERTEX", "stretch")
shoot("posetex", views[1:2], "TEXTURE")
print("CROTCH " + json.dumps(stats))
