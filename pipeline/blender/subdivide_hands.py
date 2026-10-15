# -*- coding: utf-8 -*-
"""맨몸의 손 · 손목 메시를 세분한다 (Blender 헤드리스, 10-15) — rerig_arms.py 다음 단계.

    blender -b --factory-startup -P subdivide_hands.py -- --src <glb> --out <glb> [--cuts 1] [--smooth 1.0] [--from_wrist -0.04]
    보통은 pipeline/make_human_base.py 가 bind → rerig → 이 스크립트를 한 번에 돌린다.

왜(10-15 진단): AI 몸의 손은 정점이 적다 — 손목 띠 36개(Mixamo 원본 125), 손 살 492개(1813). 손목을 크게 꺾거나 주먹을 쥐면
면이 각지게 접히고 손가락이 뭉개져 보였다(사용자: "손메시 세분 한번 해볼까?").
어떻게: 손목 평면에서 아래팔 쪽 --from_wrist(m, 음수 = 팔꿈치 쪽)까지 포함해 그 너머의 면을 Blender subdivide 로 --cuts 번 나눈다
(면 하나 → 4, 경계 면은 다각형으로 이어져 틈이 없다). --smooth 만큼 새 정점을 매끈한 면 쪽으로 붙인다(원래 정점 자리는 그대로).
새 정점의 웨이트 · UV 는 이웃에서 보간(Blender 가 함께 나눔) → 정점당 4 뼈 · 합 1 로 다시 맞춘다. 뼈 · 동작은 그대로.
정점 수는 늘지만 부위 칠하기(parts.json)는 위치 · 평면 기준이라 그대로 맞는다(Godot 가져오기는 원래도 정점 순서를 섞음).
.import 는 있으면 _subresources(뼈 이름표)만 src 것으로 바꾼다(uid 그대로). 마지막 줄 SUBDIV_RESULT {json}.
"""
import bpy, bmesh, sys, os, json


def args():
    a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out = {}
    i = 0
    while i < len(a):
        if a[i].startswith("--") and i + 1 < len(a):
            out[a[i][2:]] = a[i + 1]
            i += 2
        else:
            i += 1
    return out


def copy_import(src, out):
    """src.import 의 _subresources 블록을 out.import 에 — 있으면 그 블록만 바꾼다"""
    si = src + ".import"
    if not os.path.exists(si):
        return "no source .import"

    def block_of(t):
        i0 = t.find("_subresources=")
        if i0 < 0:
            return -1, -1
        depth, i1 = 0, i0 + len("_subresources=")
        for j in range(i1, len(t)):
            if t[j] == "{":
                depth += 1
            elif t[j] == "}":
                depth -= 1
                if depth == 0:
                    return i0, j + 1
        return i0, len(t)

    t = open(si, encoding="utf-8").read()
    s0, s1 = block_of(t)
    if s0 < 0:
        return "source .import has no _subresources"
    block = t[s0:s1]
    oi = out + ".import"
    if os.path.exists(oi):
        ot = open(oi, encoding="utf-8").read()
        k0, k1 = block_of(ot)
        ot = ot[:k0] + block + ot[k1:] if k0 >= 0 else ot.replace("[params]\n", "[params]\n\n" + block + "\n", 1)
    else:
        ot = "[remap]\n\nimporter=\"scene\"\nimporter_version=1\n\n[params]\n\n" + block + "\n"
    with open(oi, "w", encoding="utf-8", newline="\n") as f:
        f.write(ot)
    return "copied _subresources (BoneMap)"


def main():
    a = args()
    src, out = a["src"], a["out"]
    cuts = int(a.get("cuts", "1"))
    smooth = float(a.get("smooth", "1.0"))
    from_wrist = float(a.get("from_wrist", "-0.04"))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    bpy.ops.import_scene.gltf(filepath=src)
    arm = next(o for o in sc.objects if o.type == "ARMATURE")
    body = max((o for o in sc.objects if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)),
               key=lambda o: len(o.data.vertices))
    arm.data.pose_position = "REST"
    keep_action = arm.animation_data.action if arm.animation_data else None
    if arm.animation_data:
        arm.animation_data.action = None
    bpy.context.view_layer.update()
    Wm = arm.matrix_world
    bw = body.matrix_world
    before_v = len(body.data.vertices)
    planes = []
    for side in ("l", "r"):
        hb, lb = arm.data.bones.get("hand_" + side), arm.data.bones.get("lowerarm_" + side)
        if hb is None or lb is None:
            continue
        w = Wm @ hb.head_local
        ax = (w - Wm @ lb.head_local).normalized()
        planes.append((w, ax))
    me = body.data
    bm = bmesh.new()
    bm.from_mesh(me)

    def in_region(f):
        for w, ax in planes:
            if all(((bw @ v.co) - w).dot(ax) > from_wrist for v in f.verts):
                return True
        return False

    # 텍스처 이음매에서 같은 자리 정점이 둘로 나뉘어 있다 — 그대로 나누면 --smooth 가 양쪽을 따로 옮겨 이음매가 갈라진다
    # (10-15 시험: 손바닥 · 손가락에 가는 검은 금). 나눌 구역의 정점만 같은 자리끼리 합친다(UV 는 면 모서리마다라 그대로,
    # 내보낼 때 UV 가 다른 곳은 다시 나뉜다). 웨이트는 이음매 양쪽이 같다(bind 의 웨이트 부드럽게가 같은 자리 정점을 묶음).
    # 구역 바깥 한 겹까지 합친다 — 이음매가 구역 경계를 가로지르면 바깥 면의 이음매 쪽 모서리가 안 나뉘어 경계에 가는 금이 남았다(10-15)
    region_verts = {v for f in bm.faces if in_region(f) for v in f.verts}
    ring = {v2 for v in region_verts for f in v.link_faces for v2 in f.verts}
    welded = 0
    if smooth > 0.0 and ring:
        before = len(bm.verts)
        bmesh.ops.remove_doubles(bm, verts=list(ring), dist=1e-5)
        welded = before - len(bm.verts)
    sel_faces = []
    for f in bm.faces:
        ok = in_region(f)
        f.select_set(ok)
        if ok:
            sel_faces.append(f)
    bm.to_mesh(me)
    bm.free()
    me.update()
    n_sel = len(sel_faces)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_mode(type="FACE")
    bpy.ops.mesh.subdivide(number_cuts=cuts, smoothness=smooth, ngon=True, quadcorner="INNERVERT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
    bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
    after_v = len(body.data.vertices)
    unweighted = sum(1 for v in body.data.vertices if not any(g.weight > 1e-4 for g in v.groups))
    arm.data.pose_position = "POSE"
    if keep_action is not None:
        arm.animation_data.action = keep_action
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True,
                              export_animations=True, export_animation_mode="ACTIONS",
                              export_skins=True, export_all_influences=False)
    res = {"ok": os.path.exists(out), "src": src, "out": out, "cuts": cuts, "smooth": smooth, "from_wrist": from_wrist,
           "faces_subdivided": n_sel, "seam_vertices_welded": welded, "vertices_before": before_v, "vertices_after": after_v, "unweighted": unweighted,
           "godot_import": copy_import(src, out)}
    print("SUBDIV_RESULT " + json.dumps(res, ensure_ascii=False))


main()
