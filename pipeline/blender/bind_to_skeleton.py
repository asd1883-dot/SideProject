# -*- coding: utf-8 -*-
"""생성한 몸 · 옷을 기준 뼈대에 붙인다 (Blender 헤드리스) — 자산 공정의 캐릭터 칸.

    blender -b --factory-startup -P pipeline/blender/bind_to_skeleton.py -- \
        --base <기준 몸.glb(뼈대 · 동작 · 스킨 메시)> --src <생성한 모델.glb> --out <결과.glb> [--keep_base 0|1] [--fit height|span]
        [--hand_fit 1] [--hand_keep 1] [--thumb_fit 1] [--thumb_slim 0.55] [--hand_heat 0] [--smooth 12] [--part_fix 1] [--part_fix_legs 1] [--part_fix_soft 0] [--hip_heat 0] [--shoulder_cut 0]
     맨몸(human_base) · 옷(uniform_m36) 모두 기본값(다리 정리 켬 — 10-08 옷도 되돌림). 원본 = pipeline/comfy/human_8581eb8d.glb · uniform_m36_80eaf512.glb, 기준 = source3d/UAL1_humanoid.glb

1. 기준 몸(UAL1_humanoid.glb)을 바인드 포즈(T-포즈)로 연다. 뼈대 · 동작은 그대로 쓴다.
2. 생성한 모델(Tripo)의 메시를 하나로 합치고, 기준 몸의 스킨 메시에 크기 · 위치를 맞춘다.
     height(기본) = 키로 균일 배율 후 발바닥 · 가운데 맞춤. 팔 폭이 5% 넘게 다르면 가로만 따로 맞춘다(T-포즈 팔 길이 차).
3. 기준 몸의 웨이트를 가장 가까운 면에서 보간해 복사(Data Transfer) → 정점당 뼈 4개로 제한 · 정규화.
     손 맞춤(hand_fit) · 엄지 맞춤(thumb_fit: 엄지를 엄지뼈 방향으로 돌림) · 엄지 가늘게(thumb_slim 0.55: AI 엄지를 엄지뼈 축 쪽으로
     당김 — 10-06 "엄지가 너무 두껍다") 뒤 다시 복사. 이 셋은 엄지 정점 위치를 바꾼다(손바닥 · 다른 곳은 그대로).
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
        if not keep_hands:
            for v, co in zip(body.data.vertices, orig_co):     # 손 모양 되돌리기
                v.co = co
        body.data.update()

    # 손 모양 유지(hand_keep, 10-06 2차) — 되돌리면 AI 손가락이 뼈 사슬에서 4~5cm 떨어진 채 남는다(손가락 끝 ↔ 끝 뼈:
    # 검지 4.7 · 중지 4.2 · 약지 3.9 · 새끼 4.4cm, 마네킹은 0.5cm). 주먹을 쥐면 손가락이 자기 밖의 관절을 축으로 접혀
    # 구겨진 뭉치가 되고, 엄지가 감쌀 주먹이 없어 엄지가 밖으로 삐져나온다. → 손 맞춤 모양 그대로 둔다(손이 기준 손 크기로 조금 넓어짐).
    keep_hands = use_hand_fit and a.get("hand_keep", "1") == "1"
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
            # 엄지 가늘게(10-06) — AI 엄지는 마네킹보다 굵다(단면 2.5~3cm vs 1.6~2cm, 엄지뼈 축에서 0.5cm 어긋남).
            # 컷아웃 2D 는 레스트 자세 그림 한 장이라 주먹에서 엄지가 두꺼운 판으로 보인다(사용자: "엄지가 너무 두껍게").
            # 웨이트만 다듬어서는(엄지뼈가 물갈퀴 · 손바닥 살을 덜 잡게) 2D 손 그림이 그대로였다(10-06 시험) — 굵기는 모양 문제 → 엄지뼈 축 쪽으로 당긴다:
            # 축에서 떨어진 거리 × thumb_slim(엄지 웨이트만큼 · 뿌리(thumb_01)에서 둘째 마디(thumb_02)까지 서서히 — 손바닥은 그대로).
            # 0.55 → 엄지 반지름 중앙값 1.5cm → 0.9cm(실제 엄지 ~1cm, 마네킹 0.7cm). 1 = 끔. 엄지 정점 위치만 바뀐다(최대 약 1.3cm).
            # 웨이트는 가늘게 한 모양에 다시 복사된다(아래 transfer) — 마네킹 엄지와 겹쳐 엄지 웨이트도 깔끔해진다.
            slim = float(a.get("thumb_slim", "0.55"))
            if slim < 0.999:
                b2 = arm.data.bones.get("thumb_02_" + side)
                a2 = ((arm.matrix_world @ b2.head_local) - pivot).dot(bone_dir.normalized()) if b2 else 0.04
                dn = bone_dir.normalized()
                for i, w in tw.items():
                    v = body.data.vertices[i]
                    rel = v.co - pivot
                    ax_ = rel.dot(dn)
                    ramp = min(1.0, max(0.0, ax_ / max(a2, 1e-4)))
                    k = 1.0 - (1.0 - slim) * min(1.0, w) * ramp
                    radial = rel - dn * ax_
                    v.co = pivot + dn * ax_ + radial * k
                thumb_fit[side + "_slim"] = slim
        body.data.update()
        if thumb_fit:
            transfer()
    # 손 웨이트를 AI 손 모양에서 다시(10-06 2차) — 가까운 면 복사는 마네킹 손가락 마디를 AI 손에 비율로만 옮겨서, 손바닥 · 손가락
    # 길이 비율이 다른 AI 손은 손바닥 살이 손가락 뼈에, 엄지 뿌리 · 두툼한 손바닥(축에서 4~7cm)이 thumb_01 에 붙는다.
    # 주먹을 쥐면 손가락이 구겨져 작은 뭉치가 되고, 엄지 + 엄지 뿌리 살이 주먹 밖으로 긴 띠처럼 늘어진다(2D 에서 "엄지가 아래로 삐죽").
    # → 손 조각만 떼어(손 맞춤 상자에 맞춘 자리에서) 그 쪽 손 · 손가락 · 아래팔 뼈로만 Blender 자동 웨이트(뼈 열 확산)를 구하고,
    #   손목에서 3cm 동안 섞어 원래 웨이트를 바꾼다. 위치는 그대로.
    hand_heat = {}
    if a.get("hand_heat", "0") == "1":     # 기본 끔 — 10-07 시험: 손가락 몇 정점이 엉뚱한 뼈를 받아 주먹에서 가시처럼 튐(hand_keep 만으로 주먹이 더 깔끔)
        orig_co = [v.co.copy() for v in body.data.vertices]
        if use_hand_fit:
            warp_hands()
        oid = body.data.attributes.new("dr_oid", "INT", "POINT")
        for v in body.data.vertices:
            oid.data[v.index].value = v.index
        FINGER_HEADS = ("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_", "lowerarm_")
        for side in ("l", "r"):
            hb, lb = arm.data.bones.get("hand_" + side), arm.data.bones.get("lowerarm_" + side)
            if hb is None or lb is None:
                continue
            wrist = arm.matrix_world @ hb.head_local
            ax = (wrist - arm.matrix_world @ lb.head_local).normalized()
            piece = body.copy()
            piece.data = body.data.copy()
            sc.collection.objects.link(piece)
            for md in list(piece.modifiers):
                piece.modifiers.remove(md)
            piece.vertex_groups.clear()
            piece.parent = None
            bm = bmesh.new()
            bm.from_mesh(piece.data)
            mw = piece.matrix_world
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if ((mw @ v.co) - wrist).dot(ax) < -0.04], context="VERTS")
            bm.to_mesh(piece.data)
            bm.free()
            saved = {b.name: b.use_deform for b in arm.data.bones}
            for b in arm.data.bones:
                b.use_deform = b.name.endswith("_" + side) and b.name.startswith(FINGER_HEADS) and "leaf" not in b.name
            bpy.ops.object.select_all(action="DESELECT")
            piece.select_set(True)
            arm.select_set(True)
            bpy.context.view_layer.objects.active = arm
            bpy.ops.object.parent_set(type="ARMATURE_AUTO")
            for b in arm.data.bones:
                b.use_deform = saved[b.name]
            pg = {g.index: g.name for g in piece.vertex_groups}
            po = piece.data.attributes["dr_oid"]
            heat = {}
            for v in piece.data.vertices:
                ws = {pg[g.group]: g.weight for g in v.groups if g.weight > 1e-4}
                if ws:
                    heat[po.data[v.index].value] = ws
            bpy.data.objects.remove(piece, do_unlink=True)
            bgi = {vg.name: vg.index for vg in body.vertex_groups}
            changed = 0
            for vi, ws in heat.items():
                t = min(1.0, max(0.0, (orig_co[vi] - wrist).dot(ax) / 0.03))
                if t <= 0.0:
                    continue
                v = body.data.vertices[vi]
                cur = {g.group: g.weight for g in v.groups}
                tot_h = sum(ws.values())
                new = {gi: w * (1.0 - t) for gi, w in cur.items()}
                for n, w in ws.items():
                    if n in bgi:
                        new[bgi[n]] = new.get(bgi[n], 0.0) + t * w / tot_h
                top = sorted(new.items(), key=lambda kv: kv[1], reverse=True)[:4]
                s_ = sum(w for _, w in top)
                for g in list(v.groups):
                    body.vertex_groups[g.group].remove([vi])
                for gi, w in top:
                    if w > 1e-4:
                        body.vertex_groups[gi].add([vi], w / s_, "REPLACE")
                changed += 1
            hand_heat[side] = changed
        body.data.attributes.remove(body.data.attributes["dr_oid"])
        for v, co in zip(body.data.vertices, orig_co):     # 손 모양 되돌리기
            v.co = co
        body.data.update()
    # 웨이트 부드럽게 — 기준 몸(UAL1 마네킹)은 관절마다 잘린 인형이라 웨이트가 칼같이 끊겨 있다(0 아니면 1).
    # 그대로 옮기면 매끈한 사람 피부가 관절에서 찢어지거나 튀어나온다(무릎 뒤 · 반바지 뒤 · 어깨 위).
    # 이웃 정점 평균으로 여러 번 번지게 해 관절 주변에 섞이는 띠를 만든다. 손(손목 너머)은 손가락을 맞춰 둔 그대로 둔다.
    smooth_n = int(a.get("smooth", "12"))
    smoothed = 0
    if smooth_n > 0:
        import numpy as np
        me = body.data
        nv = len(me.vertices)
        groups = [vg.name for vg in body.vertex_groups]
        W = np.zeros((nv, len(groups)), dtype=np.float64)
        for v in me.vertices:
            for g in v.groups:
                W[v.index, g.group] = g.weight
        # 텍스처 이음매에서 같은 자리에 정점이 둘(이상)로 나뉘어 있다 — 따로 번지면 그 자리가 갈라진다.
        # 같은 자리 정점을 하나(rep)로 묶어 번지게 하고 결과를 똑같이 나눠 준다.
        rep = np.zeros(nv, dtype=np.int64)
        seen = {}
        for v in me.vertices:
            k = (round(v.co.x, 5), round(v.co.y, 5), round(v.co.z, 5))
            rep[v.index] = seen.setdefault(k, v.index)
        ev = np.zeros(len(me.edges) * 2, dtype=np.int64)
        me.edges.foreach_get("vertices", ev)
        ev = rep[ev.reshape(-1, 2)]
        ev = ev[ev[:, 0] != ev[:, 1]]
        ev = np.unique(np.sort(ev, axis=1), axis=0)
        deg = np.bincount(ev.ravel(), minlength=nv).astype(np.float64)
        deg[deg == 0] = 1.0
        W = W[rep]
        free = np.ones(nv, dtype=bool)
        for side in ("l", "r"):
            hb, lb = arm.data.bones.get("hand_" + side), arm.data.bones.get("lowerarm_" + side)
            if hb is None or lb is None:
                continue
            wrist = arm.matrix_world @ hb.head_local
            ax = (wrist - arm.matrix_world @ lb.head_local).normalized()
            for v in me.vertices:
                if (v.co - wrist).dot(ax) > 0.01:
                    free[v.index] = False
        for _ in range(smooth_n):
            acc = np.zeros_like(W)
            np.add.at(acc, ev[:, 0], W[ev[:, 1]])
            np.add.at(acc, ev[:, 1], W[ev[:, 0]])
            avg = acc / deg[:, None]
            W[free] = W[free] + 0.5 * (avg[free] - W[free])
            W = W[rep]          # 묶인 정점은 대표와 같은 값
        # 정점당 4개 · 합 1
        for i in range(nv):
            row = W[i]
            if np.count_nonzero(row > 1e-4) > 4:
                cut = np.sort(row)[-4]
                row[row < cut] = 0.0
            s_ = row.sum()
            if s_ > 0:
                W[i] = row / s_
        for gi, name in enumerate(groups):
            vg = body.vertex_groups[name]
            col = W[:, gi]
            nz = np.nonzero(col > 1e-4)[0]
            vg.remove(list(range(nv)))
            for i in nz:
                vg.add([int(i)], float(col[i]), "REPLACE")
        smoothed = int(free.sum())
    # 골반 웨이트를 AI 몸 모양에서 다시(hip_heat, 10-06) — 마네킹은 다리를 따로 깎은 인형이라 골반 ↔ 허벅지 웨이트가
    # 사타구니에서 칼같이 끊긴다. 가까운 면으로 옮기면 이어진 사람 사타구니 · 엉덩이 아래 · 옷자락에 0/1 경계가 생기고,
    # 허벅지를 들면(Sprint 레스트) 그 경계의 면이 9 ~ 26 배로 늘어나 2D 사타구니에 어두운 조각 · 비침이 생겼다(02 U20).
    # → 무릎 위 ~ spine_02 사이만 떼어 골반 · spine_01 · 두 허벅지 뼈로만 Blender 자동 웨이트(뼈 열 확산)를 구하고,
    #   위 · 아래 끝 6 cm 동안 원래 웨이트와 섞는다. 위치는 그대로. 열 확산은 반대쪽 다리로 번지지 않는다.
    hip_heat = {}
    # 기본 끔(10-07): 3D 변형은 매끈해지지만(늘어난 면 447 → 69) 2D 조각 경계(웨이트가 가장 센 뼈)가 허벅지 아래로 내려가
    # 골반 조각에 허벅지 윗살 띠가 남아 다리를 차면 "유령 띠"가 보였다(02 U20). 옷자락이 있으면 자락이 다리로 갈라진다.
    if a.get("hip_heat", "0") == "1":
        HIP_BONES = ("pelvis", "spine_01", "thigh_l", "thigh_r")
        bz = {n: (arm.matrix_world @ arm.data.bones[n].head_local).z for n in ("calf_l", "spine_02") if arm.data.bones.get(n)}
        if len(bz) == 2 and all(arm.data.bones.get(n) for n in HIP_BONES):
            z_lo = bz["calf_l"] + 0.15
            z_hi = bz["spine_02"]
            band = 0.06
            oid = body.data.attributes.new("dr_oid", "INT", "POINT")
            for v in body.data.vertices:
                oid.data[v.index].value = v.index
            piece = body.copy()
            piece.data = body.data.copy()
            sc.collection.objects.link(piece)
            for md in list(piece.modifiers):
                piece.modifiers.remove(md)
            piece.vertex_groups.clear()
            piece.parent = None
            bm = bmesh.new()
            bm.from_mesh(piece.data)
            mw = piece.matrix_world
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if not (z_lo - 0.02 <= (mw @ v.co).z <= z_hi + 0.02)], context="VERTS")
            bm.to_mesh(piece.data)
            bm.free()
            saved = {b.name: b.use_deform for b in arm.data.bones}
            for b in arm.data.bones:
                b.use_deform = b.name in HIP_BONES
            bpy.ops.object.select_all(action="DESELECT")
            piece.select_set(True)
            arm.select_set(True)
            bpy.context.view_layer.objects.active = arm
            bpy.ops.object.parent_set(type="ARMATURE_AUTO")
            for b in arm.data.bones:
                b.use_deform = saved[b.name]
            pg = {g.index: g.name for g in piece.vertex_groups}
            po = piece.data.attributes["dr_oid"]
            heat = {}
            for v in piece.data.vertices:
                ws = {pg[g.group]: g.weight for g in v.groups if g.weight > 1e-4}
                if ws:
                    heat[po.data[v.index].value] = ws
            bpy.data.objects.remove(piece, do_unlink=True)
            body.data.attributes.remove(body.data.attributes["dr_oid"])
            bgi = {vg.name: vg.index for vg in body.vertex_groups}
            for n in HIP_BONES:
                if n not in bgi:
                    bgi[n] = body.vertex_groups.new(name=n).index
            # ⚠ 긴 상의 자락이 있는 옷(M36)은 끌 것(--hip_heat 0): 열 확산이 자락을 다리 표면으로 보고 허벅지에 붙여 뛸 때 자락이
            # 두 갈래로 갈라져 다리를 따라간다(10-07: 늘어난 면 최대 35 배). 골반 쪽 정점만 원래대로 두는 절충은 경계가 다시 딱 끊겨 더 나빴다.
            changed = 0
            for vi, ws in heat.items():
                z = (body.matrix_world @ body.data.vertices[vi].co).z
                t_ = min(1.0, max(0.0, min(z - z_lo, z_hi - z) / band))
                if t_ <= 0.0:
                    continue
                v = body.data.vertices[vi]
                cur = {g.group: g.weight for g in v.groups}
                tot_h = sum(ws.values())
                new = {gi: w * (1.0 - t_) for gi, w in cur.items()}
                for n, w in ws.items():
                    new[bgi[n]] = new.get(bgi[n], 0.0) + t_ * w / tot_h
                top = sorted(new.items(), key=lambda kv: kv[1], reverse=True)[:4]
                s_ = sum(w for _, w in top)
                for g in list(v.groups):
                    body.vertex_groups[g.group].remove([vi])
                for gi, w in top:
                    if w > 1e-4:
                        body.vertex_groups[gi].add([vi], w / s_, "REPLACE")
                changed += 1
            hip_heat = {"vertices": changed, "z": [round(z_lo, 3), round(z_hi, 3)], "heat_found": len(heat)}
    # 관절 경계 정리 — 굽기 도구는 "웨이트가 가장 큰 뼈"로 조각(파트)을 자른다. 가까운 면으로 옮긴 웨이트는
    # 이어진 피부에서 경계가 관절과 어긋나, 윗팔 조각에 겨드랑이 · 가슴 옆살이, 허벅지 조각에 무릎 아래 살이 붙는다(10-02).
    # 팔 · 다리 사슬마다 관절에 평면(뼈 방향에 수직)을 세워, 평면 기준으로 어느 뼈 조각인지 다시 정한다.
    # 바뀐 정점만 그 뼈 하나로(웨이트 1) — 나머지는 부드럽게 번진 웨이트 그대로.
    part_fix = {}
    soft = a.get("part_fix_soft", "0") == "1"     # 시험용(10-07): 경계만 바로잡고 부드럽게 — 2D 에서 낫지 않아 기본 끔
    if a.get("part_fix", "1") == "1":
        me = body.data
        gidx = {vg.name: vg.index for vg in body.vertex_groups}
        gname = {i: n for n, i in gidx.items()}
        M = arm.matrix_world

        # 어깨 경계를 관절보다 팔 쪽으로 shoulder_cut m 옮기는 선택(기본 0). 10-02 시험: 0.04 로 옮겨도
        # Sprint 의 어깨 원판은 그대로였다 — 원판은 웨이트가 아니라 팔이 뒤로 젖혀질 때 윗팔 단면이 보이는 컷아웃 한계.
        shoulder_cut = float(a.get("shoulder_cut", "0.0"))

        def bone_plane(name):
            b = arm.data.bones.get(name)
            if b is None:
                return None
            h, tl = M @ b.head_local, M @ b.tail_local
            d = (tl - h).normalized()
            if name.startswith("upperarm_"):
                h = h + d * shoulder_cut
            return h, d

        FINGERS = ("thumb_", "index_", "middle_", "ring_", "pinky_")
        chains = []
        for sd in ("l", "r"):
            chains.append({"bones": ["upperarm_" + sd, "lowerarm_" + sd, "hand_" + sd], "parent": "clavicle_" + sd,
                           "family": lambda n, sd=sd: n in ("upperarm_" + sd, "lowerarm_" + sd, "hand_" + sd) or (n.startswith(FINGERS) and n.endswith("_" + sd)),
                           "steal": ("clavicle_" + sd, "spine_03", "spine_02"), "steal_r": float(a.get("steal_r", "0.075"))})
            # 다리 관절 경계 정리 — 기본 켬(10-08 되돌림). 끄면 3D 사타구니 면 늘어남은 줄지만(26 → 5.5 배) 2D 조각의 관절 부분이
            # 고무처럼 비틀린 채 잘려, 2D 에서 다리를 벌리면 사타구니 · 무릎 뒤 틈이 더 벌어졌다(틈 픽셀 2563 → 2980, 02 U22).
            # 2D 컷아웃은 인형처럼 딱딱한 다리가 낫다 — 맨몸 · 옷 모두 켬.
            if a.get("part_fix_legs", "1") != "1":
                continue
            chains.append({"bones": ["thigh_" + sd, "calf_" + sd, "foot_" + sd], "parent": "pelvis",
                           "family": lambda n, sd=sd: n in ("thigh_" + sd, "calf_" + sd, "foot_" + sd, "ball_" + sd),
                           # soft: 골반 웨이트가 센 허벅지 윗살(자동 웨이트가 골반을 허벅지 아래까지 번지게 함)도 허벅지 조각으로 — 허벅지 축에서 steal_leg_r 안만(옷자락 제외)
                           "steal": ("pelvis",) if soft else (), "steal_r": float(a.get("steal_leg_r", "0.10")) if soft else 0.0})
        changed = {}
        for ch in chains:
            planes = [bone_plane(n) for n in ch["bones"]]
            if any(pl is None for pl in planes) or any(n not in gidx for n in ch["bones"]):
                continue
            h0, d0 = planes[0]
            cnt = 0
            for v in me.vertices:
                if not v.groups:
                    continue
                best = max(v.groups, key=lambda g: g.weight)
                cur = gname.get(best.group, "")
                in_family = ch["family"](cur)
                p = v.co
                seg = -1
                for i, (h, d) in enumerate(planes):
                    if (p - h).dot(d) >= 0.0:
                        seg = i
                if in_family:
                    if seg < 0:
                        target = ch["parent"]                     # 첫 관절보다 안쪽 = 몸통/골반
                    else:
                        target = ch["bones"][seg]
                        if seg == len(planes) - 1 and cur != ch["bones"][-1] and (cur.startswith(FINGERS) or cur.startswith("ball_")):
                            target = cur                           # 손가락 · 발가락은 맞춰 둔 그대로
                elif cur in ch["steal"] and seg >= 0:
                    # 어깨 바깥쪽(관절 평면 너머) 살이 몸통에 붙어 있으면 윗팔로 — 팔 굵기 안쪽만
                    off = (p - h0) - d0 * (p - h0).dot(d0)
                    if off.length > ch["steal_r"]:
                        continue
                    target = ch["bones"][seg]
                else:
                    continue
                if target != cur and target in gidx:
                    changed[v.index] = target
                    cnt += 1
            part_fix["/".join(ch["bones"][:1])] = cnt
        for vi, target in changed.items():
            if soft:
                # 부드럽게(part_fix_soft, 10-07): 웨이트 1 로 덮으면 경계에 0/1 단이 생겨 그 면이 레스트 자세에서 몇 배로 늘어난다
                # (사타구니 9 ~ 26 배). 그 뼈를 지금 가장 센 뼈보다 조금만 세게(+0.05) 하고 나머지는 비율대로 — 조각 경계는 바로잡고 변형은 부드럽게.
                v = me.vertices[vi]
                cur = {gname[g.group]: g.weight for g in v.groups if g.group in gname}
                top = max(cur.values()) if cur else 0.0
                cur[target] = max(cur.get(target, 0.0), top + 0.05)
                items = sorted(cur.items(), key=lambda kv: kv[1], reverse=True)[:4]
                s_ = sum(w for _, w in items)
                for g in list(v.groups):
                    body.vertex_groups[g.group].remove([vi])
                for nm, w in items:
                    if w > 1e-4 and nm in gidx:
                        body.vertex_groups[nm].add([vi], w / s_, "REPLACE")
                continue
            for vg in body.vertex_groups:
                vg.remove([vi])
            body.vertex_groups[target].add([vi], 1.0, "REPLACE")
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
    # Godot 가져오기 설정 — 기준 몸의 .import 에 뼈 이름표(BoneMap, 리타깃)가 있으면 결과에도 똑같이.
    # 없으면 source3d/mixamo 같은 "추가 동작"이 뼈를 하나도 못 찾아 T-포즈로 멈춘다(10-02 라이플 · 조준).
    import_note = "기준 몸에 가져오기 설정 없음"
    bi = base_path + ".import"
    if os.path.exists(bi):
        btxt = open(bi, encoding="utf-8").read()
        i0 = btxt.find("_subresources=")
        if i0 >= 0:
            # 중괄호 짝을 세어 블록 끝을 찾는다
            depth, i1 = 0, i0 + len("_subresources=")
            for j in range(i1, len(btxt)):
                if btxt[j] == "{":
                    depth += 1
                elif btxt[j] == "}":
                    depth -= 1
                    if depth == 0:
                        i1 = j + 1
                        break
            block = btxt[i0:i1]
            oi = out_path + ".import"
            if os.path.exists(oi):
                otxt = open(oi, encoding="utf-8").read()
                k0 = otxt.find("_subresources=")
                if k0 >= 0:
                    depth, k1 = 0, k0 + len("_subresources=")
                    for j in range(k1, len(otxt)):
                        if otxt[j] == "{":
                            depth += 1
                        elif otxt[j] == "}":
                            depth -= 1
                            if depth == 0:
                                k1 = j + 1
                                break
                    otxt = otxt[:k0] + block + otxt[k1:]
                else:
                    otxt = otxt.replace("[params]\n", "[params]\n\n" + block + "\n", 1)
            else:
                otxt = "[remap]\n\nimporter=\"scene\"\nimporter_version=1\n\n[params]\n\n" + block + "\n"
            with open(oi, "w", encoding="utf-8", newline="\n") as f:
                f.write(otxt)
            import_note = "기준 몸의 _subresources(뼈 이름표) 복사"
    res = {
        "godot_import": import_note,
        "ok": os.path.exists(out_path),
        "base_size_m": [round(x, 3) for x in bsize],
        "src_size_raw": [round(x, 3) for x in ssize], "turned_deg": turned,
        "scale": round(s, 4), "scale_x": round(sx, 4), "span_ratio_before": round(span_ratio, 3),
        "fitted_size_m": [round(x, 3) for x in (fhi - flo)],
        "hand_fit": hand_fit, "thumb_fit_deg": thumb_fit, "hand_heat": hand_heat, "hip_heat": hip_heat, "smooth_iter": smooth_n, "smoothed_vertices": smoothed, "part_fix": part_fix,
        "triangles": tris, "vertices": len(body.data.vertices),
        "unweighted_vertices": unweighted, "bone_groups": len(body.vertex_groups),
        "actions": len(bpy.data.actions), "kept_base": keep_base, "out": out_path,
    }
    print("BIND_RESULT " + json.dumps(res, ensure_ascii=False))


main()
