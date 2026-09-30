# -*- coding: utf-8 -*-
"""무기 정규화 (Blender 헤드리스) — 자산 공정 1단계의 두 번째 칸.

    blender -b --factory-startup -P pipeline/blender/normalize_weapon.py -- --asset <asset.json 절대경로> --project <프로젝트 절대경로>

asset.json 의 "normalize" 칸을 읽어 원본 3D(OBJ/FBX/GLB)를 규격에 맞춰 GLB 로 내보내고,
결과(잰 길이 · 배율 · 찾은 총구 축 · 파트 이름 · 삼각형 수)를 "normalize.result" 에 적는다.

규격(Godot 에서 보는 축 기준):
  - 총구 = +Z  (Blender 에서는 -Y — glTF 내보내기가 Blender Z-up 을 Y-up 으로 바꾼다)
  - 위   = +Y  (Blender +Z)
  - 크기 = normalize.length_m (총구 축 길이, m). 0 이면 그대로
  - 원점 = 손이 잡는 자리(normalize.grip_node 노드의 중심). 없으면 경계 상자 가운데
  - 파트(하위 오브젝트)는 이름 그대로 나눠 둔다 — 장비 굽기 창에서 파트별로 숨긴다
"""
import bpy, bmesh, json, sys, os, math
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


def res_to_abs(p, project):
    if p.startswith("res://"):
        return os.path.join(project, p[6:].replace("/", os.sep))
    return p


AXES = {"+X": Vector((1, 0, 0)), "-X": Vector((-1, 0, 0)), "+Y": Vector((0, 1, 0)),
        "-Y": Vector((0, -1, 0)), "+Z": Vector((0, 0, 1)), "-Z": Vector((0, 0, -1))}


def world_verts(objs):
    for o in objs:
        m = o.matrix_world
        for v in o.data.vertices:
            yield m @ v.co


def bbox(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for p in world_verts(objs):
        for k in range(3):
            lo[k] = min(lo[k], p[k])
            hi[k] = max(hi[k], p[k])
    return lo, hi


def detect_forward(objs):
    """가장 긴 축 = 총열. 방향은 양 끝 10% 조각의 단면이 작은 쪽(총구는 가늘고 개머리판은 두껍다)"""
    lo, hi = bbox(objs)
    size = hi - lo
    ax = max(range(3), key=lambda k: size[k])
    others = [k for k in range(3) if k != ax]
    ends = {}
    for side, lim in (("lo", lo[ax] + size[ax] * 0.1), ("hi", hi[ax] - size[ax] * 0.1)):
        a = [1e9, 1e9]
        b = [-1e9, -1e9]
        for p in world_verts(objs):
            if (side == "lo" and p[ax] <= lim) or (side == "hi" and p[ax] >= lim):
                for j, k in enumerate(others):
                    a[j] = min(a[j], p[k])
                    b[j] = max(b[j], p[k])
        ends[side] = max(0.0, b[0] - a[0]) * max(0.0, b[1] - a[1])
    v = Vector((0, 0, 0))
    v[ax] = 1.0 if ends["hi"] < ends["lo"] else -1.0
    name = ("+" if v[ax] > 0 else "-") + "XYZ"[ax]
    return v, name, ends


def main():
    a = args()
    asset_path = a["asset"]
    project = a["project"]
    with open(asset_path, encoding="utf-8") as f:
        asset = json.load(f)
    nz = asset.setdefault("normalize", {})
    src = res_to_abs(asset["source"]["file"], project)
    out = res_to_abs(nz.get("output", ""), project)
    result = {"ok": False}

    bpy.ops.wm.read_factory_settings(use_empty=True)
    ext = os.path.splitext(src)[1].lower()
    if ext == ".obj":
        bpy.ops.wm.obj_import(filepath=src)
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=src)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=src)
    else:
        raise SystemExit("모르는 원본 형식: " + ext)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not objs:
        raise SystemExit("메시가 없습니다: " + src)

    # 총구 축
    fwd_cfg = str(nz.get("forward", "auto"))
    if fwd_cfg in AXES:
        f = AXES[fwd_cfg].copy()
        fwd_name = fwd_cfg
        ends = None
    else:
        f, fwd_name, ends = detect_forward(objs)
    up_cfg = str(nz.get("up", "+Z"))
    up = AXES.get(up_cfg, Vector((0, 0, 1))).copy()
    if abs(up.dot(f)) > 0.9:
        up = Vector((0, 1, 0)) if abs(f.y) < 0.9 else Vector((0, 0, 1))
    up = (up - f * up.dot(f)).normalized()
    side = f.cross(up)
    # 원본 (side, f, up) → Blender (+X, -Y, +Z)  → glTF 에서 총구 +Z · 위 +Y
    src_m = Matrix((side, f, up)).transposed()          # 열 = 원본 축
    dst_m = Matrix(((1, 0, 0), (0, -1, 0), (0, 0, 1))).transposed()
    rot = (dst_m @ src_m.inverted()).to_4x4()
    for o in objs:
        o.matrix_world = rot @ o.matrix_world

    # 크기 — 총구 축(Blender Y) 길이
    lo, hi = bbox(objs)
    length_before = hi.y - lo.y
    want = float(nz.get("length_m", 0.0) or 0.0)
    scale = want / length_before if want > 0 and length_before > 1e-6 else 1.0
    sm = Matrix.Scale(scale, 4)
    for o in objs:
        o.matrix_world = sm @ o.matrix_world

    # 원점 — 손이 잡는 자리
    grip_name = str(nz.get("grip_node", ""))
    grip_obj = next((o for o in objs if o.name == grip_name or o.name.split(".")[0] == grip_name), None) if grip_name else None
    if grip_obj is not None:
        glo, ghi = bbox([grip_obj])
        center = (glo + ghi) * 0.5
    else:
        lo, hi = bbox(objs)
        center = (lo + hi) * 0.5
    tm = Matrix.Translation(-center)
    for o in objs:
        o.matrix_world = tm @ o.matrix_world

    # 변환 적용(메시에 굽기) — 파트 이름은 그대로
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    def count_tris():
        n = 0
        for o in objs:
            o.data.calc_loop_triangles()
            n += len(o.data.loop_triangles)
        return n

    # 면 줄이기 — AI 생성 메시는 수십만~백만 면이라 도트 굽기에 쓸 만큼만 남긴다(UV · 텍스처는 유지)
    tris_before = tris = count_tris()
    max_tris = int(nz.get("max_triangles", 0) or 0)
    if max_tris > 0 and tris > max_tris:
        for o in objs:
            bpy.context.view_layer.objects.active = o
            m = o.modifiers.new("decimate", "DECIMATE")
            m.ratio = max_tris / float(tris)
            bpy.ops.object.modifier_apply(modifier=m.name)
        tris = count_tris()

    # 파트 자르기 — AI 생성 메시는 한 덩어리라 탄알집 같은 부품을 상자 범위로 떼어 낸다.
    # normalize.split = { "<파트 이름>": {"min": [x, y, z], "max": [x, y, z]} }  (Godot 축 · 정규화된 결과 기준 m:
    #   x = 옆, y = 위, z = 총구 쪽). 면의 가운데가 상자 안이면 그 파트로 간다.
    for part_name, box in dict(nz.get("split", {})).items():
        gmin, gmax = box["min"], box["max"]
        bmin = Vector((gmin[0], -gmax[2], gmin[1]))   # Godot (x, y, z) → Blender (x, -z, y)
        bmax = Vector((gmax[0], -gmin[2], gmax[1]))
        inside = lambda c: all(bmin[k] <= c[k] <= bmax[k] for k in range(3))
        pieces = []
        for o in list(objs):
            bm = bmesh.new()
            bm.from_mesh(o.data)
            sel = [f for f in bm.faces if inside(f.calc_center_median())]
            if not sel:
                bm.free()
                continue
            new = o.copy()
            new.data = o.data.copy()
            bpy.context.scene.collection.objects.link(new)
            bm2 = bmesh.new()
            bm2.from_mesh(new.data)
            bmesh.ops.delete(bm2, geom=[f for f in bm2.faces if not inside(f.calc_center_median())], context="FACES")
            bm2.to_mesh(new.data)
            bm2.free()
            bmesh.ops.delete(bm, geom=sel, context="FACES")
            bm.to_mesh(o.data)
            bm.free()
            pieces.append(new)
        if not pieces:
            print("SPLIT_WARN '%s' 상자 안에 면이 없습니다" % part_name)
            continue
        if len(pieces) > 1:
            bpy.ops.object.select_all(action="DESELECT")
            for p in pieces:
                p.select_set(True)
            bpy.context.view_layer.objects.active = pieces[0]
            bpy.ops.object.join()
        pieces[0].name = part_name
        pieces[0].data.name = part_name
        objs.append(pieces[0])
    lo, hi = bbox(objs)

    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", export_yup=True, use_selection=False)

    result = {
        "ok": os.path.exists(out),
        "source": src,
        "forward_found": fwd_name,
        "end_sections": ends,
        "length_before_m": round(length_before, 4),
        "scale": round(scale, 6),
        "length_m": round(hi.y - lo.y, 4),
        "size_m": [round(hi.x - lo.x, 4), round(hi.z - lo.z, 4), round(hi.y - lo.y, 4)],   # Godot 기준 x · y(위) · z(총구)
        "grip_found": grip_obj is not None,
        "parts": sorted(o.name for o in objs),
        "triangles": tris,
        "triangles_before": tris_before,
        "output": out,
    }
    nz["result"] = result
    with open(asset_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(asset, f, ensure_ascii=False, indent="\t")
    print("NORMALIZE_RESULT " + json.dumps(result, ensure_ascii=False))


main()
