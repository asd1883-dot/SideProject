# -*- coding: utf-8 -*-
"""생성한 몸 · 옷을 기준 뼈대에 붙인다 (Blender 헤드리스) — 자산 공정의 캐릭터 칸.

    blender -b --factory-startup -P pipeline/blender/bind_to_skeleton.py -- \
        --base <기준 몸.glb(뼈대 · 동작 · 스킨 메시)> --src <생성한 모델.glb> --out <결과.glb> [--keep_base 0|1] [--fit height|span]
        [--hand_fit 1] [--hand_keep 1] [--thumb_fit 1] [--thumb_slim 0.55] [--finger_fit 1] [--forearm_twist 1] [--hand_scale 0.86] [--thumb_len 0.80] [--hand_heat 0] [--smooth 12] [--part_fix 1] [--part_fix_legs 1] [--part_fix_soft 0] [--hip_heat 0] [--shoulder_cut 0]
        옷(기준 몸이 사람 몸 = 뼈대 그대로) 전용: [--limb_fit 1] [--limb_fit_target base|bone] [--limb_fit_upper 0.3,…] [--limb_fit_fore 0.1,…]
        [--limb_fit_blend 0.15,0.45] [--cuff_fit 1] [--cuff_start -0.12] [--cuff_at -0.03] [--cuff_margin 0.006] [--cuff_fade 0.025]
        [--arm_smooth 0] [--part_fix_arms 0]   (기준 몸이 UAL 마네킹이면 이 칸들은 무시 — 맨몸 공정은 그대로)
     맨몸(human_base) · 옷(uniform_m36) 모두 기본값(다리 정리 켬 — 10-08 옷도 되돌림). 원본 = pipeline/comfy/human_8581eb8d.glb · uniform_m36_80eaf512.glb, 기준 = source3d/UAL1_humanoid.glb
     ★ 맨몸은 10-15 부터 이 결과에 rerig_arms.py(팔 사슬을 몸 자체에 맞춰 다시 리깅)를 더한 것 — pipeline/make_human_base.py 로 한 번에.
     ★ 옷은 10-15 부터 --base human_base.glb(사람 몸 뼈대 그대로, skeleton_from_base). 10-16 부터 옷은 팔 살을 그 뼈대 팔 축에 맞춘 뒤
       웨이트를 옮기고(limb_fit) 팔에는 2D 용 웨이트 번지기 · 관절 정리를 안 한다 — 3D 에서 소매 끝이 맨몸 손목과 같은 축 · 같은 비틀림으로 움직이게.

1. 기준 몸(UAL1_humanoid.glb)을 바인드 포즈(T-포즈)로 연다. 뼈대 · 동작은 그대로 쓴다.
2. 생성한 모델(Tripo)의 메시를 하나로 합치고, 기준 몸의 스킨 메시에 크기 · 위치를 맞춘다.
     height(기본) = 키로 균일 배율 후 발바닥 · 가운데 맞춤. 팔 폭이 5% 넘게 다르면 가로만 따로 맞춘다(T-포즈 팔 길이 차).
3. 기준 몸의 웨이트를 가장 가까운 면에서 보간해 복사(Data Transfer) → 정점당 뼈 4개로 제한 · 정규화.
     손 맞춤(hand_fit) · 엄지 맞춤(thumb_fit: 엄지를 엄지뼈 방향으로 돌림) · 엄지 가늘게(thumb_slim 0.55: AI 엄지를 엄지뼈 축 쪽으로
     당김 — 10-06 "엄지가 너무 두껍다") 뒤 다시 복사. 이 셋은 엄지 정점 위치를 바꾼다(손바닥 · 다른 곳은 그대로).
4. 기준 몸 스킨 메시는 뺀다(--keep_base 1 이면 남김 — 옷만 입힐 때).
5. 뼈대 · 모든 동작 · 새 메시를 GLB 로 내보낸다. 결과 요약은 "BIND_RESULT {json}" 한 줄.
"""
import bpy, bmesh, sys, os, json, math
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


def _smoothstep(x, a, b):
    if b <= a:
        return 1.0 if x >= a else 0.0
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def _slice_loops(bm, p0, ax, segs=None):
    """bm 을 평면(p0, ax)으로 잘라 나온 고리마다 (중심 — 모서리 길이 가중, 점들). rerig_arms.py 의 slice_loops 와 같은 식.
    segs(리스트)를 주면 단면 선분(두 끝점)을 모두 덧붙인다 — 외곽 반지름을 선분으로 재는 데(_profile)"""
    c = bm.copy()
    r = bmesh.ops.bisect_plane(c, geom=c.verts[:] + c.edges[:] + c.faces[:], dist=1e-7, plane_co=p0, plane_no=ax)
    cut = [e for e in r["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
    adj = {}
    for e in cut:
        for v in e.verts:
            adj.setdefault(v, []).append(e)
    seen = set()
    loops = []
    for e in cut:
        if e in seen:
            continue
        stack = [e]
        seen.add(e)
        es = []
        while stack:
            x = stack.pop()
            es.append(x)
            for v in x.verts:
                for y in adj.get(v, []):
                    if y not in seen:
                        seen.add(y)
                        stack.append(y)
        acc = Vector()
        tot = 0.0
        pts = []
        for x in es:
            a_, b_ = x.verts[0].co, x.verts[1].co
            l_ = (b_ - a_).length
            acc += (a_ + b_) * 0.5 * l_
            tot += l_
            pts.append(a_.copy())
            if segs is not None:
                segs.append((a_.copy(), b_.copy()))
        if tot > 1e-9:
            loops.append((acc / tot, pts))
    c.free()
    return loops


def _welded(obj):
    """메시 사본(세상 좌표, 텍스처 이음매로 나뉜 정점을 합침 — 단면이 닫힌 고리가 되게)"""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bm.transform(obj.matrix_world)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    return bm


def _centre(bm, p0, ax, rmax=0.09):
    """평면(p0, ax) 단면 고리 중 중심이 p0 에 가장 가까운 것 → (중심, 점들) 또는 None"""
    best = None
    for cen, pts in _slice_loops(bm, p0, ax):
        d = (cen - p0).length
        if d < rmax and (best is None or d < best[0]):
            best = (d, cen, pts)
    return (best[1], best[2]) if best else None


def fit_arms_to_bones(body, arm, stations_u, stations_f, blend, base=None):
    """옷 팔 살을 기준 몸 팔에 맞춘다(limb_fit, 10-16) — 옷(skeleton_from_base)은 사람 몸 뼈대를 그대로 받는데
    팔 살은 다른 AI 모델이라 자리가 다르다(uniform_m36: 소매 단면 중심이 뼈 축보다 2 ~ 2.6 cm 아래 · 아래팔 끝 2 cm 앞, 사람 몸은 1 cm 안).
    그러면 ① 3D 에서 손목 이음매(옷 소매 ↔ 기본 몸 손)가 어긋나 손이 소매 구멍 가장자리에서 나오고(게임 시점에서 검은 뚜껑 아래로 손이
    비켜 "손목이 꺾여 보임" — 사용자 10-16) ② Mixamo 가 손을 100 ~ 130° 비틀 때 소매가 가장자리 축으로 휘둘린다(사람 몸 U31 과 같은 일).
    사람 몸은 rerig_arms.py 로 뼈를 살 중심에 옮겼지만 옷은 뼈대가 공용이라 뼈를 못 옮긴다 → 살을 옮긴다.
    단면(뼈에 수직인 평면으로 자른 고리 중 축에 가장 가까운 것)마다 옷 중심이 기준 몸(base, 없으면 뼈 축) 중심에서 떨어진 만큼(축에 수직
    성분)을 정점마다 빼 준다 — 기준 몸 중심에 맞추면 손목 자르기 평면에서 소매 고리가 손목 고리와 같은 중심이 된다(기준 몸 팔은 뼈 축에서 1 cm 안).
    어깨 → 팔꿈치 → 손목 길이 s 를 따라 단면 사이를 선형으로, 마지막 단면 너머(손)는 그대로, 어깨 쪽은 blend(윗팔 비율)로 0 → 1.
    팔 정점 = 그 자리 단면 반지름의 1.3 배 + 1 cm 안(몸통 · 겨드랑이는 안 건드림). 정점 수 · 순서 그대로, 웨이트 복사 전에 한다."""
    import numpy as np
    me = body.data
    co = np.array([tuple(body.matrix_world @ v.co) for v in me.vertices])
    bm = _welded(body)
    bm_base = _welded(base) if base is not None else None
    M = arm.matrix_world
    out = {}
    disp = np.zeros_like(co)
    for sd in ("l", "r"):
        bu, bl, bh = (arm.data.bones.get(n + sd) for n in ("upperarm_", "lowerarm_", "hand_"))
        if bu is None or bl is None or bh is None:
            continue
        SH, EL, WR = M @ bu.head_local, M @ bl.head_local, M @ bh.head_local
        du = EL - SH
        Lu = du.length
        du = du / Lu
        df = WR - EL
        Lf = df.length
        df = df / Lf
        st = []          # (s, 오프셋(축에 수직), 단면 최대 반지름)
        for u in stations_u:
            p0 = SH + du * (u * Lu)
            st.append((u * Lu, p0, du))
        for t in stations_f:
            p0 = EL + df * (t * Lf)
            st.append((Lu + t * Lf, p0, df))
        found = []
        n_base = 0
        for s_, p0, ax in st:
            got = _centre(bm, p0, ax)
            if got is None:
                continue
            target = p0
            if bm_base is not None:
                gb = _centre(bm_base, p0, ax)
                if gb is not None:
                    target = gb[0]
                    n_base += 1
            off = got[0] - target
            off = off - ax * off.dot(ax)
            rmax = max(((q - p0) - ax * (q - p0).dot(ax)).length for q in got[1])
            found.append((s_, np.array(tuple(off)), rmax))
        if len(found) < 3:
            continue
        S = np.array([f[0] for f in found])
        OFF = np.array([f[1] for f in found])
        RM = np.array([f[2] for f in found])
        moved = 0
        far = 0.0
        for i in range(len(co)):
            p = Vector(co[i])
            a_ = (p - SH).dot(du)
            if a_ < 0.0:
                continue
            b_ = (p - EL).dot(df)
            if b_ < 0.0:
                if a_ > Lu:
                    continue
                s_ = a_
                r_ = ((p - SH) - du * a_).length
            else:
                s_ = Lu + b_
                r_ = ((p - EL) - df * b_).length
            if s_ > S[-1]:
                rlim = 0.14                                     # 손(손가락 · 엄지까지)
            else:
                rlim = float(np.interp(s_, S, RM)) * 1.3 + 0.01
            if r_ > rlim:
                continue
            w = _smoothstep(s_, blend[0] * Lu, blend[1] * Lu)
            if w <= 0.0:
                continue
            o = np.array([np.interp(s_, S, OFF[:, k]) for k in range(3)])
            disp[i] = -o * w
            moved += 1
            far = max(far, float(np.linalg.norm(o * w)))
        out[sd] = {"stations_cm": [[round(float(S[k]) * 100, 1), [round(float(x) * 100, 2) for x in OFF[k]], round(float(RM[k]) * 100, 1)] for k in range(len(S))],
                   "target": "base %d/%d" % (n_base, len(st)) if bm_base is not None else "bone axis",
                   "moved_vertices": moved, "max_move_cm": round(far * 100, 2)}
    bm.free()
    if bm_base is not None:
        bm_base.free()
    mwi = body.matrix_world.inverted()
    for i in np.nonzero(np.linalg.norm(disp, axis=1) > 1e-7)[0]:
        me.vertices[int(i)].co = mwi @ Vector(tuple(co[i] + disp[i]))
    me.update()
    return out


def _profile(segs, p0, ax, u, v, n=36, rmax=0.12):
    """단면 선분들의 바깥 외곽 반지름 — 축(p0 · ax) 둘레 n 칸의 가운데 방향 광선이 선분과 만나는 가장 먼 거리.
    점으로만 재면 소매 바깥 고리의 긴 모서리가 칸을 건너뛰어 그 칸에 안쪽 고리(AI 모델 자기 팔)가 잡힌다(10-16 시험). 못 만난 칸은 양옆으로 보간"""
    s2 = []
    for a_, b_ in segs:
        da, db = a_ - p0, b_ - p0
        A = (da.dot(u), da.dot(v))
        B = (db.dot(u), db.dot(v))
        if math.hypot(*A) > rmax and math.hypot(*B) > rmax:
            continue
        s2.append((A, B))
    out = [-1.0] * n
    for k in range(n):
        th = -math.pi + (k + 0.5) * 2.0 * math.pi / n
        dx, dy = math.cos(th), math.sin(th)
        best = -1.0
        for A, B in s2:
            ex, ey = B[0] - A[0], B[1] - A[1]
            den = dx * ey - dy * ex
            if abs(den) < 1e-12:
                continue
            t = (A[0] * dy - A[1] * dx) / den
            if t < 0.0 or t > 1.0:
                continue
            px, py = A[0] + ex * t, A[1] + ey * t
            s_ = px * dx + py * dy
            if s_ > best:
                best = s_
        out[k] = best
    have = [k for k in range(n) if out[k] >= 0.0]
    if len(have) < 3:
        return None
    fill = list(out)
    for k in range(n):
        if out[k] >= 0.0:
            continue
        lo, hi, dl, dh = k, k, 0, 0
        while out[lo] < 0.0:
            lo = (lo - 1) % n
            dl += 1
        while out[hi] < 0.0:
            hi = (hi + 1) % n
            dh += 1
        fill[k] = out[lo] + (out[hi] - out[lo]) * dl / (dl + dh)
    return fill


def fit_cuffs(body, arm, base, start, cuff_at, margin, fade_end, n=36):
    """소매 끝 맞춤(cuff_fit, 10-16) — 3D 에서 옷 소매는 손목 자르기 평면(parts.json 손목 관절, 기본 −3 cm)에서 끝나고 그 너머는 기본 몸 손이다.
    소매 끝이 손목보다 많이 굵으면(uniform_m36: 둘레 29.9 cm vs 맨몸 손목 20.0) 그 사이 뚜껑 띠(어두운 단면)가 1 ~ 2 cm 로 넓게 보인다.
    소매 바깥 외곽을 칸(각도)마다 기준 몸 외곽 + margin 이 되게 손목 쪽에서만 줄이거나(넓으면) 늘린다(좁아서 맨몸이 비어져 나오면):
    배율 = (기준 반지름 + margin) / 옷 반지름, 정점마다 축 둘레 반지름에 곱한다(소매 안쪽 고리 — AI 모델 자기 팔 — 도 같은 배율이라 안에 머문다).
    손목에서 start(−) → cuff_at 사이 smoothstep 으로 0 → 1, 손목 관절 너머 fade_end 까지 1 → 0(옷 자기 손은 그대로). 팔 살 맞춤(limb_fit) 뒤에."""
    import numpy as np
    me = body.data
    co = np.array([tuple(body.matrix_world @ v.co) for v in me.vertices])
    bm = _welded(body)
    bmb = _welded(base)
    M = arm.matrix_world
    out = {}
    disp = np.zeros_like(co)
    # 재는 자리는 소매 끝(cuff_at)까지만 — 그 너머(손목 관절 둘레)는 AI 모델 자기 손 · 엄지가 단면에 섞여 외곽이 엉뚱해진다(10-16 시험:
    # 손목 관절 자리를 넣었더니 배율이 2.9 까지 튀어 소매가 7 cm 부풀었다). 너머는 소매 끝 배율을 그대로(np.interp 가 끝값을 이어 줌)
    offs = [start + (cuff_at - start) * i / 4.0 for i in range(5)]
    for sd in ("l", "r"):
        bl, bh = arm.data.bones.get("lowerarm_" + sd), arm.data.bones.get("hand_" + sd)
        if bl is None or bh is None:
            continue
        EL, WR = M @ bl.head_local, M @ bh.head_local
        ax = (WR - EL).normalized()
        u = Vector((0.0, 0.0, 1.0))
        u = (u - ax * u.dot(ax)).normalized()
        v = ax.cross(u)
        F = []           # 칸마다 배율 [자리] — 자리 = offs
        used = []
        rep = []         # 자리마다 [cm, 옷 평균 반지름, 기준 몸 평균 반지름, 배율 최소, 최대]
        for off in offs:
            p0 = WR + ax * off
            go = _centre(bm, p0, ax, 0.12)
            gb = _centre(bmb, p0, ax, 0.12)
            if go is None or gb is None:
                continue
            # 단면 선분 전부(소매 바깥 · 안쪽 고리)로 바깥 외곽 — 축에서 12 cm 안
            sg_o = []
            sg_b = []
            _slice_loops(bm, p0, ax, sg_o)
            _slice_loops(bmb, p0, ax, sg_b)
            ro = _profile(sg_o, p0, ax, u, v, n)
            rb = _profile(sg_b, p0, ax, u, v, n)
            if ro is None or rb is None:
                continue
            f = [(rb[k] + margin) / max(ro[k], 1e-4) for k in range(n)]
            f = [(f[(k - 1) % n] + 2.0 * f[k] + f[(k + 1) % n]) / 4.0 for k in range(n)]       # 칸 사이를 매끈하게
            F.append(f)
            used.append(off)
            rep.append([round(off * 100, 1), round(sum(ro) / n * 100, 2), round(sum(rb) / n * 100, 2), round(min(f), 2), round(max(f), 2)])
        if len(used) < 2:
            continue
        OFF = np.array(used)
        FA = np.array(F)                          # (자리, 칸)
        moved = 0
        far = 0.0
        WRn = np.array(tuple(WR))
        axn = np.array(tuple(ax))
        un = np.array(tuple(u))
        vn = np.array(tuple(v))
        d_all = (co - WRn) @ axn
        for i in np.nonzero((d_all > start) & (d_all < fade_end))[0]:
            d = float(d_all[i])
            rel = co[i] - WRn - axn * d
            r = float(np.linalg.norm(rel))
            if r < 1e-6 or r > 0.12:
                continue
            k_ = _smoothstep(d, start, cuff_at) * (1.0 - _smoothstep(d, 0.0, fade_end))
            if k_ <= 0.0:
                continue
            th = math.atan2(float(rel @ vn), float(rel @ un))
            x = (th + math.pi) / (2 * math.pi) * n - 0.5
            k0 = int(math.floor(x)) % n
            k1 = (k0 + 1) % n
            fr = x - math.floor(x)
            fcol = FA[:, k0] * (1.0 - fr) + FA[:, k1] * fr
            f = float(np.interp(d, OFF, fcol))
            s = 1.0 + (f - 1.0) * k_
            disp[i] = rel * (s - 1.0)
            moved += 1
            far = max(far, abs(s - 1.0) * r)
        out[sd] = {"stations": rep, "moved_vertices": moved, "max_move_cm": round(far * 100, 2)}
    bm.free()
    bmb.free()
    mwi = body.matrix_world.inverted()
    for i in np.nonzero(np.linalg.norm(disp, axis=1) > 1e-7)[0]:
        me.vertices[int(i)].co = mwi @ Vector(tuple(co[i] + disp[i]))
    me.update()
    return out


def arm_coords(co, arm, sd):
    """정점(세상 좌표 numpy (n, 3))마다 팔 사슬 위 자리 — (s = 어깨 → 팔꿈치 → 손목 너머 길이, 축 거리, 윗팔 길이). 팔 밖(어깨 안쪽)은 s = -1"""
    import numpy as np
    M = arm.matrix_world
    bu, bl, bh = (arm.data.bones.get(n + sd) for n in ("upperarm_", "lowerarm_", "hand_"))
    n = len(co)
    S = -np.ones(n)
    R = np.full(n, 1e9)
    if bu is None or bl is None or bh is None:
        return S, R, 0.0
    SH, EL, WR = (np.array(tuple(M @ b.head_local)) for b in (bu, bl, bh))
    du = EL - SH
    Lu = float(np.linalg.norm(du))
    du /= Lu
    df = WR - EL
    df /= float(np.linalg.norm(df))
    a_ = (co - SH) @ du
    b_ = (co - EL) @ df
    ru = np.linalg.norm((co - SH) - np.outer(a_, du), axis=1)
    rf = np.linalg.norm((co - EL) - np.outer(b_, df), axis=1)
    up = (a_ >= 0.0) & (b_ < 0.0) & (a_ <= Lu)
    fo = (a_ >= 0.0) & (b_ >= 0.0)
    S[up] = a_[up]
    R[up] = ru[up]
    S[fo] = Lu + b_[fo]
    R[fo] = rf[fo]
    return S, R, Lu


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
    # 기준 몸이 이미 이 공정으로 만든 사람 몸(human_base — 비틀림 뼈가 있음)이면 뼈대는 그 몸 것을 그대로 쓴다(10-15):
    # 손가락 뼈 맞춤 · 비틀림 뼈 넣기 · 손 크기(손 뼈 옮김)를 건너뛴다. 옷(③ 복장)의 관절이 맨몸과 하나라도 다르면 2D 에서
    # 옷 조각이 맨몸 뼈에 얹힐 때 그만큼 어긋난다(소매 ↔ 손 2 cm). 웨이트도 사람 몸에서 옮겨 와 비틀림 몫까지 이미 들어 있다.
    skel_from_base = any(b.name.startswith("lowerarm_twist_") for b in arm.data.bones)
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

    # 2.5) 팔 살을 기준 뼈대 팔 축에 맞춤(limb_fit, 10-16) — 옷(기준 몸 뼈대를 그대로 쓸 때)만 기본 켬. 웨이트 복사 전에 해야
    # 소매 살이 사람 팔을 같은 축으로 둘러싸 가까운 면 복사가 같은 자리(같은 비틀림 몫)의 웨이트를 받는다. fit_arms_to_bones 머리말 참고.
    limb_fit = {}
    if skel_from_base and a.get("limb_fit", "1") == "1":
        su = [float(x) for x in a.get("limb_fit_upper", "0.3,0.45,0.6,0.75,0.9").split(",")]
        sf = [float(x) for x in a.get("limb_fit_fore", "0.1,0.25,0.4,0.55,0.7,0.8,0.88,0.95").split(",")]
        bl_ = [float(x) for x in a.get("limb_fit_blend", "0.15,0.45").split(",")]
        limb_fit = fit_arms_to_bones(body, arm, su, sf, bl_, base if a.get("limb_fit_target", "base") == "base" else None)
        flo, fhi = world_bbox([body])
    # 소매 끝 맞춤(cuff_fit, 10-16) — 소매 끝 외곽을 맨몸 손목 + margin 으로(뚜껑 띠가 얇게). fit_cuffs 머리말 참고
    cuff_fit = {}
    if skel_from_base and a.get("cuff_fit", "1") == "1":
        cuff_fit = fit_cuffs(body, arm, base, float(a.get("cuff_start", "-0.12")), float(a.get("cuff_at", "-0.03")),
                             float(a.get("cuff_margin", "0.006")), float(a.get("cuff_fade", "0.025")))
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
    arm_frozen = 0
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
        # 옷(기준 몸 뼈대 그대로)은 팔(윗팔 가운데부터 바깥)을 번지게 하지 않는다(10-16) — 사람 몸 팔 웨이트는 이미 매끈한 식
        # (rerig_arms.py: 아래팔 t 에 따라 비틀림 뼈로 선형 · 손목 평면 smoothstep)이라 복사한 그대로가 맨몸과 같은 변형이다.
        # 번지게 하면 손목 쪽 자르기 고리(−3 cm)에 손 0.2 · 비틀림1 0.1 · 엄지 0.05 가 섞여(사람 몸은 비틀림2 1.0) 손을 굽히거나
        # 비틀 때 소매 끝이 맨몸 손목과 다르게 움직였다(uniform_m36 10-15 판).
        arm_frozen = 0
        if skel_from_base and a.get("arm_smooth", "0") != "1":
            co_np = np.array([tuple(body.matrix_world @ v.co) for v in me.vertices])
            for side in ("l", "r"):
                S_, R_, Lu_ = arm_coords(co_np, arm, side)
                if Lu_ <= 0.0:
                    continue
                m_ = (S_ >= 0.5 * Lu_) & (R_ < 0.14)
                arm_frozen += int((m_ & free).sum())
                free[m_] = False
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
        # 옷(기준 몸 뼈대 그대로)의 팔은 건너뛴다(10-16) — 이 정리는 2D 조각 경계용으로 정점을 뼈 하나(웨이트 1)로 덮는데, 비틀림 뼈를
        # 모르는 채 손목 평면 앞의 손 웨이트 정점을 아래팔 1.0(안 비틀림)으로 바꿔 비트는 이웃 사이에 가시를 만든다. 3D 슬롯 경계는
        # parts.json 관절 자르기 평면이 정하므로 팔 웨이트는 맨몸에서 옮긴 그대로 둔다.
        arm_chains = not skel_from_base or a.get("part_fix_arms", "0") == "1"
        for sd in ("l", "r"):
            if arm_chains:
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

    # 손가락 뼈 맞춤(finger_fit, 10-14) — 웨이트는 손가락마다 맞게 붙어 있는데(색칠 확인), 기준 뼈대의 손가락 뼈가 AI 손가락 살에서
    # 옆으로 2.4 ~ 3.7 cm 비켜 있었다(마네킹 0.4 ~ 0.8 cm). 손가락을 구부리면 살 밖의 축을 중심으로 접혀 살이 아래로 늘어진 뭉치가 되고
    # 펴진 손가락만 길게 남아 "엄지가 길고 손목이 휘었다"(사용자, Mixamo Rifle Idle). 살은 그대로 두고 **뼈를 살 중심선으로** 옮긴다:
    # 손가락마다 그 손가락 웨이트 > 0.5 정점들의 주축(PCA)을 구하고, 마디(01 · 02 · 03 머리, 03 꼬리, leaf 꼬리)를 그 선 위로
    # 투영(길이 방향 자리는 유지). 엄지는 thumb_fit 으로 이미 0.5 ~ 0.7 cm 라 건드리지 않는다. 롤은 원래 축을 따라 다시 맞춘다.
    finger_fit = {}
    if a.get("finger_fit", "1") == "1" and not skel_from_base:
        import numpy as np
        gname = {g.index: g.name for g in body.vertex_groups}
        pts_by = {}
        for side in ("l", "r"):
            for finger in ("index", "middle", "ring", "pinky"):
                names = {"%s_0%d_%s" % (finger, i, side) for i in (1, 2, 3)} | {"%s_04_leaf_%s" % (finger, side)}
                P = [body.matrix_world @ v.co for v in body.data.vertices
                     if sum(g.weight for g in v.groups if gname.get(g.group, "") in names) > 0.5]
                if len(P) >= 12:
                    pts_by[(side, finger)] = P
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = arm
        arm.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        Wm = arm.matrix_world
        Wi = Wm.inverted()
        for (side, finger), P in pts_by.items():
            ebs = [arm.data.edit_bones.get("%s_0%d_%s" % (finger, i, side)) for i in (1, 2, 3)]
            leaf = arm.data.edit_bones.get("%s_04_leaf_%s" % (finger, side))
            if None in ebs:
                continue
            chain = ebs + ([leaf] if leaf else [])
            J = [Wm @ ebs[0].head, Wm @ ebs[1].head, Wm @ ebs[2].head, Wm @ ebs[2].tail] + ([Wm @ leaf.tail] if leaf else [])
            A = np.array([[p.x, p.y, p.z] for p in P])
            c = A.mean(axis=0)
            _, _, vt = np.linalg.svd(A - c, full_matrices=False)
            e = Vector(vt[0])
            if e.dot(J[3] - J[0]) < 0:
                e = -e
            cv = Vector(c)
            NJ = [cv + e * (j - cv).dot(e) for j in J]
            zs = [eb.z_axis.copy() for eb in chain]
            for eb in chain:
                eb.use_connect = False
            for k, eb in enumerate(chain):
                eb.head = Wi @ NJ[k]
                eb.tail = Wi @ NJ[k + 1]
                eb.align_roll(zs[k])
            moved = max((NJ[k] - J[k]).length for k in range(len(J)))
            turn = math.degrees((J[3] - J[0]).angle(NJ[3] - NJ[0])) if (J[3] - J[0]).length > 1e-6 else 0.0
            finger_fit["%s_%s" % (finger, side)] = {"moved_cm": round(moved * 100, 1), "turn_deg": round(turn, 1)}
        bpy.ops.object.mode_set(mode="OBJECT")

    # 아래팔 비틀림 뼈(forearm_twist, 10-14) — Mixamo 동작은 손을 아래팔 축으로 100 ~ 130° 비틀면서 아래팔은 0°로 두고(손목이 다 떠안음),
    # UAL 동작은 아래팔이 비튼다(손목 0°). 이 몸의 살은 UAL 에서 옮겨 와 손목이 큰 비틀림을 못 받는다 → Mixamo 소총 동작에서
    # 손목이 사탕 껍질처럼 꼬여 가늘어지고 뾰족하게 튐(사용자: "팔목 자체가 휘어졌다"). 비틀림을 손목에 몰든 팔꿈치에 몰든 100° 가 넘으면
    # 그 자리가 무너졌다(시험) → 아래팔에 비틀림 뼈 둘(팔꿈치→손목 TW1 · TW2 지점)을 넣고, 아래팔 살 웨이트를 그 자리에 따라
    # 아래팔 · 비틀림1 · 비틀림2 · 손으로 나눈다(삼각 함수). 비틀림 뼈는 동작에 없으므로 Dot Rigger(DRBaker)가 손의 비틀림 × 자리 비율로 돌린다.
    # 같이: 웨이트 부드럽게(smooth)가 손목 손 웨이트를 아래팔 중간까지 번지게 해 두어(손을 비틀면 아래팔 중간이 가시처럼 튐) 그것도 걷힌다.
    forearm_twist = {}
    if a.get("forearm_twist", "1") == "1" and not skel_from_base:
        TW1, TW2 = 0.45, 0.85
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = arm
        arm.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        Wm = arm.matrix_world
        axes = {}
        for side in ("l", "r"):
            la, hd = arm.data.edit_bones.get("lowerarm_" + side), arm.data.edit_bones.get("hand_" + side)
            if la is None or hd is None:
                continue
            E, Wr = la.head.copy(), hd.head.copy()          # 아마추어 공간
            z = la.z_axis.copy()
            for name, t0, t1 in (("lowerarm_twist_01_" + side, TW1, TW2), ("lowerarm_twist_02_" + side, TW2, 1.0)):
                eb = arm.data.edit_bones.get(name) or arm.data.edit_bones.new(name)
                eb.head = E + (Wr - E) * t0
                eb.tail = E + (Wr - E) * t1
                eb.parent = la
                eb.use_connect = False
                eb.use_deform = True
                eb.align_roll(z)
            axes[side] = (Wm @ E, Wm @ Wr)
        bpy.ops.object.mode_set(mode="OBJECT")
        for side, (E, Wr) in axes.items():
            names = ["lowerarm_" + side, "lowerarm_twist_01_" + side, "lowerarm_twist_02_" + side, "hand_" + side]
            for n in names:
                if n not in body.vertex_groups:
                    body.vertex_groups.new(name=n)
            gi = {n: body.vertex_groups[n].index for n in names}
            ax = Wr - E
            L2 = ax.length_squared
            moved = 0
            for v in body.data.vertices:
                cur = {g.group: g.weight for g in v.groups}
                w_la, w_hd = cur.get(gi[names[0]], 0.0), cur.get(gi[names[3]], 0.0)
                if w_la <= 1e-4:
                    continue                                  # 아래팔 웨이트가 없는 정점(손바닥 · 손가락 · 윗팔)은 그대로
                p = body.matrix_world @ v.co
                t = (p - E).dot(ax) / L2
                radial = ((p - E) - ax * t).length
                if t <= 0.0 or radial > 0.12:
                    continue                                  # 팔꿈치 안쪽 · 팔에서 먼 살은 그대로
                if t >= 1.0:
                    new = {gi[names[2]]: w_la}                # 손목 너머 살에 남은 아래팔 웨이트 = 손목 쪽 비틀림 뼈로(손목에서 끊기지 않게)
                    keep_hand = True
                else:
                    W_arm = w_la + w_hd                       # 아래팔 + (번진) 손 웨이트를 자리에 따라 다시 나눈다
                    if t < TW1:
                        new = {gi[names[0]]: W_arm * (TW1 - t) / TW1, gi[names[1]]: W_arm * t / TW1}
                    elif t < TW2:
                        new = {gi[names[1]]: W_arm * (TW2 - t) / (TW2 - TW1), gi[names[2]]: W_arm * (t - TW1) / (TW2 - TW1)}
                    else:
                        new = {gi[names[2]]: W_arm * (1.0 - t) / (1.0 - TW2), gi[names[3]]: W_arm * (t - TW2) / (1.0 - TW2)}
                    keep_hand = False
                for g in list(v.groups):
                    if g.group == gi[names[0]] or (g.group == gi[names[3]] and not keep_hand):
                        body.vertex_groups[g.group].remove([v.index])
                for g_i, w in new.items():
                    if w > 1e-5:
                        body.vertex_groups[g_i].add([v.index], w, "ADD")
                moved += 1
            forearm_twist[side] = moved
        bpy.ops.object.select_all(action="DESELECT")
        body.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
        bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)

    # 손 크기 · 엄지 길이(hand_scale · thumb_len, 10-15) — AI 몸은 마네킹 치수 안내 그림(SPEC.md)을 따라 만들어 손이 마네킹만큼 크다
    # (손목 → 손끝 상자 23.4 cm, 마네킹 22.9 · 키 1.83 m 사람 ~20 cm): 손바닥(손목 → 중지 뿌리) 12.0 cm(Mixamo 원본 10.1),
    # 엄지(뿌리 관절 → 끝) 8.8 cm = 검지의 83 %(Mixamo · 사람 64 % 안팎). 사용자: "엄지 김" — Rifle Idle 에서 왼손 엄지를 펴면 막대처럼 튀어나옴.
    # → 손(손목 너머 전부)을 손목 기준으로 hand_scale 만큼 줄이고, 엄지 바깥 마디(thumb_02 머리 = 뿌리 관절 너머)는 엄지 축으로 thumb_len 만큼 더 줄인다.
    #   살은 뼈마다의 변환을 그 웨이트로 섞어(스키닝과 같은 식) 옮기고, 손 · 손가락 · 엄지 뼈도 같은 변환으로 옮긴다(방향 · 롤 그대로 → 동작은 같은 각도).
    #   손목은 아래팔(그대로) ↔ 손(줄임) 웨이트가 섞인 띠라 이음매 없이 좁아진다. 정점 수 · 순서 그대로. 1 = 끔.
    hand_reshape = {}
    hs = float(a.get("hand_scale", "0.86"))
    tl = float(a.get("thumb_len", "0.80"))
    if (abs(hs - 1.0) > 1e-3 or abs(tl - 1.0) > 1e-3) and not skel_from_base:
        Wm = arm.matrix_world
        Wi = Wm.inverted()
        xf = {}                                   # 뼈 이름 -> 그 뼈 살 · 마디를 옮기는 함수(세상 좌표)

        def make_hand(W):
            return lambda p: W + (p - W) * hs

        def make_thumb(Mj, MjT, t):
            def f(p):
                q = (p - Mj) * hs
                return MjT + q - t * ((1.0 - tl) * q.dot(t))
            return f

        for side in ("l", "r"):
            hb = arm.data.bones.get("hand_" + side)
            if hb is None:
                continue
            W = Wm @ hb.head_local
            T_hand = make_hand(W)
            for b in [hb] + list(hb.children_recursive):
                xf[b.name] = T_hand
            t2, t3 = arm.data.bones.get("thumb_02_" + side), arm.data.bones.get("thumb_03_" + side)
            if t2 is not None and t3 is not None:
                Mj = Wm @ t2.head_local
                t = ((Wm @ t3.tail_local) - Mj).normalized()
                T_thumb = make_thumb(Mj, T_hand(Mj), t)
                for b in [t2] + list(t2.children_recursive):
                    xf[b.name] = T_thumb
            hand_reshape[side] = {"wrist": [round(x, 3) for x in W]}
        gname = {g.index: g.name for g in body.vertex_groups}
        mw = body.matrix_world
        mwi = mw.inverted()
        moved, far = 0, 0.0
        for v in body.data.vertices:
            ws = [(gname.get(g.group, ""), g.weight) for g in v.groups if g.weight > 0.0]
            if not any(n in xf for n, _ in ws):
                continue
            tot = sum(w for _, w in ws)
            p = mw @ v.co
            q = Vector()
            for n, w in ws:
                q += (xf[n](p) if n in xf else p) * (w / tot)
            far = max(far, (q - p).length)
            v.co = mwi @ q
            moved += 1
        body.data.update()
        bpy.ops.object.select_all(action="DESELECT")
        bpy.context.view_layer.objects.active = arm
        arm.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        ebs = arm.data.edit_bones
        new_ht = {}
        for n, f in xf.items():
            eb = ebs.get(n)
            if eb is not None:
                new_ht[n] = (Wi @ f(Wm @ eb.head), Wi @ f(Wm @ eb.tail), eb.z_axis.copy())
        for n, (h, tl_, z) in new_ht.items():      # 모두 구한 뒤에 한꺼번에(이어진 뼈가 서로 끌지 않게)
            eb = ebs[n]
            eb.use_connect = False
            eb.head = h
            eb.tail = tl_
            eb.align_roll(z)
        bpy.ops.object.mode_set(mode="OBJECT")
        hand_reshape.update({"scale": hs, "thumb_len": tl, "vertices": moved, "max_move_cm": round(far * 100, 1), "bones": len(new_ht)})

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
        "skeleton_from_base": skel_from_base, "limb_fit": limb_fit, "cuff_fit": cuff_fit, "arm_smooth_frozen": arm_frozen,
        "hand_fit": hand_fit, "thumb_fit_deg": thumb_fit, "finger_fit": finger_fit, "forearm_twist": forearm_twist, "hand_reshape": hand_reshape, "hand_heat": hand_heat, "hip_heat": hip_heat, "smooth_iter": smooth_n, "smoothed_vertices": smoothed, "part_fix": part_fix,
        "triangles": tris, "vertices": len(body.data.vertices),
        "unweighted_vertices": unweighted, "bone_groups": len(body.vertex_groups),
        "actions": len(bpy.data.actions), "kept_base": keep_base, "out": out_path,
    }
    print("BIND_RESULT " + json.dumps(res, ensure_ascii=False))


main()
