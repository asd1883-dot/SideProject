# -*- coding: utf-8 -*-
"""생성한 몸 · 옷을 기준 뼈대에 붙인다 (Blender 헤드리스) — 자산 공정의 캐릭터 칸.

    blender -b --factory-startup -P pipeline/blender/bind_to_skeleton.py -- \
        --base <기준 몸.glb(뼈대 · 동작 · 스킨 메시)> --src <생성한 모델.glb> --out <결과.glb> [--keep_base 0|1] [--fit height|span]

1. 기준 몸(UAL1_humanoid.glb)을 바인드 포즈(T-포즈)로 연다. 뼈대 · 동작은 그대로 쓴다.
2. 생성한 모델(Tripo)의 메시를 하나로 합치고, 기준 몸의 스킨 메시에 크기 · 위치를 맞춘다.
     height(기본) = 키로 균일 배율 후 발바닥 · 가운데 맞춤. 팔 폭이 5% 넘게 다르면 가로만 따로 맞춘다(T-포즈 팔 길이 차).
3. 기준 몸의 웨이트를 가장 가까운 면에서 보간해 복사(Data Transfer) → 정점당 뼈 4개로 제한 · 정규화.
4. 기준 몸 스킨 메시는 뺀다(--keep_base 1 이면 남김 — 옷만 입힐 때).
5. 뼈대 · 모든 동작 · 새 메시를 GLB 로 내보낸다. 결과 요약은 "BIND_RESULT {json}" 한 줄.
"""
import bpy, bmesh, sys, os, json
from mathutils import Vector, Matrix


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


def world_bbox(objs, deps=None):
    lo = Vector((1e9,) * 3); hi = Vector((-1e9,) * 3)
    for o in objs:
        src = o.evaluated_get(deps) if deps else o
        me = src.to_mesh() if deps else o.data
        for v in me.vertices:
            p = src.matrix_world @ v.co
            for k in range(3):
                lo[k] = min(lo[k], p[k]); hi[k] = max(hi[k], p[k])
        if deps:
            src.to_mesh_clear()
    return lo, hi


def main():
    a = args()
    base_path, src_path, out_path = a["base"], a["src"], a["out"]
    keep_base = a.get("keep_base", "0") == "1"
    fit = a.get("fit", "height")
    res = {"ok": False}

    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene

    # 1) 기준 몸
    bpy.ops.import_scene.gltf(filepath=base_path)
    arm = next(o for o in sc.objects if o.type == "ARMATURE")
    base_meshes = [o for o in sc.objects if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)]
    if not base_meshes:
        raise SystemExit("기준 몸에 스킨 메시가 없습니다")
    arm.data.pose_position = "REST"
    keep_action = arm.animation_data.action if arm.animation_data else None
    if arm.animation_data:
        arm.animation_data.action = None
    bpy.context.view_layer.update()
    base = base_meshes[0]
    if len(base_meshes) > 1:
        # 웨이트 원본은 하나로 — 합친 사본을 만든다
        bpy.ops.object.select_all(action="DESELECT")
        copies = []
        for o in base_meshes:
            c = o.copy(); c.data = o.data.copy(); sc.collection.objects.link(c); copies.append(c)
        for c in copies:
            c.select_set(True)
        bpy.context.view_layer.objects.active = copies[0]
        bpy.ops.object.join()
        base = copies[0]
    deps = bpy.context.evaluated_depsgraph_get()
    blo, bhi = world_bbox([base], deps)
    before = set(sc.objects)

    # 2) 생성한 모델
    bpy.ops.import_scene.gltf(filepath=src_path)
    new_objs = [o for o in sc.objects if o not in before]
    src_meshes = [o for o in new_objs if o.type == "MESH"]
    if not src_meshes:
        raise SystemExit("생성한 모델에 메시가 없습니다")
    for o in new_objs:
        if o.type == "ARMATURE":          # 생성기가 붙인 뼈대가 있으면 버린다 — 기준 뼈대만 쓴다
            for m in src_meshes:
                for md in list(m.modifiers):
                    if md.type == "ARMATURE":
                        m.modifiers.remove(md)
    # 부모 관계를 풀고 변환을 메시에 굽는다
    for o in src_meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    bpy.ops.object.select_all(action="DESELECT")
    for o in src_meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = src_meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    if len(src_meshes) > 1:
        bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    for o in new_objs:
        if o != body and o.name in sc.objects:
            bpy.data.objects.remove(o, do_unlink=True)
    body.name = "Body"
    body.data.name = "Body"

    # 방향 맞춤 — 생성기가 인물을 옆으로 돌려 저장하기도 한다(Tripo: 팔이 Y 축).
    #  ① T-포즈 팔 = 가로로 가장 긴 축 → X 로  ② 발끝이 있는 쪽 = 앞 → -Y 로(기준 몸과 같게)
    import math
    turned = 0
    slo, shi = world_bbox([body])
    if (shi.y - slo.y) > (shi.x - slo.x):
        body.data.transform(Matrix.Rotation(math.radians(90), 4, "Z"))
        turned += 90
        slo, shi = world_bbox([body])
    h = shi.z - slo.z
    feet = [v.co for v in body.data.vertices if v.co.z < slo.z + h * 0.03]
    shin = [v.co for v in body.data.vertices if slo.z + h * 0.12 < v.co.z < slo.z + h * 0.25]
    if feet and shin:
        fy = sum(p.y for p in feet) / len(feet)
        sy = sum(p.y for p in shin) / len(shin)
        if fy > sy:            # 발끝이 +Y 쪽 = 뒤를 보고 있다
            body.data.transform(Matrix.Rotation(math.radians(180), 4, "Z"))
            turned += 180
    body.data.update()

    # 크기 · 위치 맞춤
    slo, shi = world_bbox([body])
    bsize, ssize = bhi - blo, shi - slo
    s = bsize.z / ssize.z if ssize.z > 1e-6 else 1.0
    sx = s
    span_ratio = (ssize.x * s) / bsize.x if bsize.x > 1e-6 else 1.0
    if fit == "span" or abs(span_ratio - 1.0) > 0.05:
        sx = bsize.x / ssize.x
    bctr = (blo + bhi) / 2; sctr = (slo + shi) / 2
    M = (Matrix.Translation(Vector((bctr.x, bctr.y, blo.z)))
         @ Matrix.Diagonal(Vector((sx, s, s, 1.0)))
         @ Matrix.Translation(Vector((-sctr.x, -sctr.y, -slo.z))))
    body.data.transform(M)
    body.data.update()
    flo, fhi = world_bbox([body])

    # 3) 웨이트 복사
    # 손 맞춤 — AI 손은 기준 손보다 좁고 손가락 간격 · 엄지 자리가 달라서, 가까운 면만 보고 옮기면
    # 손가락 웨이트가 한 칸씩 밀린다(검지 뼈가 검지 · 중지를 같이 잡음 · 엄지 뼈가 손바닥까지).
    # 복사하는 동안만 AI 손(손목 너머)을 기준 손의 상자 크기로 늘려 손가락끼리 짝을 맞추고, 끝나면 모양을 되돌린다.
    hand_fit = {}
    use_hand_fit = a.get("hand_fit", "1") == "1"

    def warp_hands():
        for side in ("l", "r"):
            hb, lb = arm.data.bones.get("hand_" + side), arm.data.bones.get("lowerarm_" + side)
            if hb is None or lb is None:
                continue
            wrist = arm.matrix_world @ hb.head_local
            ax = (wrist - arm.matrix_world @ lb.head_local).normalized()
            bp = [base.matrix_world @ v.co for v in base.data.vertices if (base.matrix_world @ v.co - wrist).dot(ax) > 0]
            ai = [i for i, v in enumerate(body.data.vertices) if (v.co - wrist).dot(ax) > 0]
            if len(bp) < 10 or len(ai) < 10:
                continue
            blo_h = Vector([min(p[k] for p in bp) for k in range(3)]); bhi_h = Vector([max(p[k] for p in bp) for k in range(3)])
            alo_h = Vector([min(body.data.vertices[i].co[k] for i in ai) for k in range(3)])
            ahi_h = Vector([max(body.data.vertices[i].co[k] for i in ai) for k in range(3)])
            for i in ai:
                p = body.data.vertices[i].co
                q = Vector([blo_h[k] + (p[k] - alo_h[k]) / (ahi_h[k] - alo_h[k]) * (bhi_h[k] - blo_h[k])
                            if ahi_h[k] - alo_h[k] > 1e-5 else p[k] for k in range(3)])
                t = min(1.0, (p - wrist).dot(ax) / 0.03)       # 손목에서 3cm 동안 서서히 — 손목에 이음매가 안 생기게
                body.data.vertices[i].co = p.lerp(q, t)
            hand_fit[side] = {"ai_size": [round(x, 3) for x in (ahi_h - alo_h)], "base_size": [round(x, 3) for x in (bhi_h - blo_h)]}
        body.data.update()

    def transfer():
        for vg in list(body.vertex_groups):
            body.vertex_groups.remove(vg)
        for vg in base.vertex_groups:
            body.vertex_groups.new(name=vg.name)
        orig_co = [v.co.copy() for v in body.data.vertices]
        if use_hand_fit:
            warp_hands()
        bpy.ops.object.select_all(action="DESELECT")
        body.select_set(True)
        bpy.context.view_layer.objects.active = body
        dt = body.modifiers.new("weights", "DATA_TRANSFER")
        dt.object = base
        dt.use_object_transform = True
        dt.use_vert_data = True
        dt.data_types_verts = {"VGROUP_WEIGHTS"}
        dt.vert_mapping = "POLYINTERP_NEAREST"
        dt.layers_vgroup_select_src = "ALL"
        dt.layers_vgroup_select_dst = "NAME"
        bpy.ops.object.modifier_apply(modifier=dt.name)
        bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
        bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
        for v, co in zip(body.data.vertices, orig_co):     # 손 모양 되돌리기
            v.co = co
        body.data.update()

    transfer()

    # 엄지 맞춤 — AI 엄지는 손바닥과 같은 평면으로 뻗어 있고, 기준 뼈대의 엄지뼈는 손바닥 아래 비스듬히 놓여 있다.
    # 웨이트가 맞아도 엄지뼈가 돌 때 다른 방향을 돌리게 되어 주먹을 쥐면 엄지가 아래로 삐져나온다.
    # → AI 엄지를 엄지 뿌리(thumb_01) 기준으로 엄지뼈 방향에 맞게 돌려 놓고(엄지 웨이트만큼 — 뿌리는 조금만) 웨이트를 다시 옮긴다.
    thumb_fit = {}
    if a.get("thumb_fit", "1") == "1":
        gname = {g.index: g.name for g in body.vertex_groups}
        for side in ("l", "r"):
            b1 = arm.data.bones.get("thumb_01_" + side)
            tip = arm.data.bones.get("thumb_04_leaf_" + side) or arm.data.bones.get("thumb_03_" + side)
            if b1 is None or tip is None:
                continue
            pivot = arm.matrix_world @ b1.head_local
            bone_dir = (arm.matrix_world @ tip.head_local) - pivot
            tw = {}
            for v in body.data.vertices:
                w = sum(g.weight for g in v.groups if gname.get(g.group, "").startswith("thumb_") and gname[g.group].endswith("_" + side))
                if w > 0.0:
                    tw[v.index] = w
            core = [body.data.vertices[i].co for i, w in tw.items() if w > 0.5]
            if len(core) < 10 or bone_dir.length < 1e-4:
                continue
            core.sort(key=lambda p: (p - pivot).length)
            far = core[int(len(core) * 0.7):]
            ai_dir = sum((p - pivot for p in far), Vector()) / len(far)
            q = ai_dir.normalized().rotation_difference(bone_dir.normalized())
            from mathutils import Quaternion
            for i, w in tw.items():
                v = body.data.vertices[i]
                r = Quaternion().slerp(q, min(1.0, w))
                v.co = pivot + r @ (v.co - pivot)
            thumb_fit[side] = round(math.degrees(q.angle), 1)
        body.data.update()
        if thumb_fit:
            transfer()
    # 웨이트가 하나도 없는 정점(떨어진 조각 등)
    unweighted = sum(1 for v in body.data.vertices if not any(g.weight > 1e-4 for g in v.groups))
    # 빈 그룹 정리
    used = set()
    for v in body.data.vertices:
        for g in v.groups:
            if g.weight > 1e-4:
                used.add(g.group)
    # 이름으로 모아 두고 지운다(하나 지울 때마다 번호가 당겨진다)
    drop = [vg.name for vg in body.vertex_groups if vg.index not in used]
    for name in drop:
        body.vertex_groups.remove(body.vertex_groups[name])

    body.parent = arm
    body.matrix_parent_inverse = arm.matrix_world.inverted()
    am = body.modifiers.new("Armature", "ARMATURE")
    am.object = arm

    # 4) 기준 스킨 메시 빼기
    if not keep_base:
        for o in set(base_meshes) | {base}:
            if o.name in sc.objects:
                bpy.data.objects.remove(o, do_unlink=True)
    elif base not in base_meshes:
        bpy.data.objects.remove(base, do_unlink=True)

    arm.data.pose_position = "POSE"
    if keep_action is not None:
        arm.animation_data.action = keep_action

    tris = 0
    body.data.calc_loop_triangles()
    tris = len(body.data.loop_triangles)

    # 5) 내보내기
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", export_yup=True,
                              export_animations=True, export_animation_mode="ACTIONS",
                              export_skins=True, export_all_influences=False)
    res = {
        "ok": os.path.exists(out_path),
        "base_size_m": [round(x, 3) for x in bsize],
        "src_size_raw": [round(x, 3) for x in ssize], "turned_deg": turned,
        "scale": round(s, 4), "scale_x": round(sx, 4), "span_ratio_before": round(span_ratio, 3),
        "fitted_size_m": [round(x, 3) for x in (fhi - flo)],
        "hand_fit": hand_fit, "thumb_fit_deg": thumb_fit,
        "triangles": tris, "vertices": len(body.data.vertices),
        "unweighted_vertices": unweighted, "bone_groups": len(body.vertex_groups),
        "actions": len(bpy.data.actions), "kept_base": keep_base, "out": out_path,
    }
    print("BIND_RESULT " + json.dumps(res, ensure_ascii=False))


main()
