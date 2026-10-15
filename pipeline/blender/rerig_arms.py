# -*- coding: utf-8 -*-
"""붙인 몸(bind_to_skeleton.py 결과)의 팔 사슬을 몸 자체에 맞춰 다시 리깅한다 (Blender 헤드리스, 10-15).

    blender -b --factory-startup -P rerig_arms.py -- --src <bind 결과.glb> --out <결과.glb> [--raw <손 단계 끈 bind 결과.glb>] [옵션]
    보통은 pipeline/make_human_base.py 가 bind 두 번 + 이 스크립트를 한 번에 돌린다.

옵션(기본): --center_arm 1 --shoulder_k 0 --fingers 1 --mcp_back 0.020 --ratios 0.38,0.32,0.30 --twist 0.45,0.85
  --elbow_blend -0.025,0.045 --wrist_blend -0.022,0.012 --region 0.35,0.50 --thumb_fade 0.0,0.02 --heat 1
  --wrist_smooth -0.06,-0.04,0.015,0.03,40 (--raw 가 있을 때만) --dry 1 (관절만 재고 끝)

입력 = 지금 공정의 bind 결과(UAL 이름 뼈대 + 비틀림 뼈 + 동작 전부). 출력 = 같은 뼈 이름 · 계층 · 동작, 같은 메시(정점 수 · 순서 같음,
위치는 --raw 의 손목 띠 정리만), 팔 사슬 관절을 살 중심으로 옮기고 팔 사슬 웨이트를 몸에서 새로 구한 것. 몸통 · 쇄골 · 다리 웨이트는
그대로 두고 윗팔 가운데부터 새 웨이트로 섞는다.

왜(10-15 human_base 실측 — 사용자: "리깅을 다시 하면 되는 거 아니야?", 인수인계 02 U31):
  * UAL 팔 뼈가 팔꿈치 ~ 손목에서 AI 팔 살 중심보다 2.0 ~ 2.9 cm 뒤(+Y, 새끼 · 팔꿈치뼈 쪽) · ~1 cm 위 — 앞에서 본 T-포즈 그림으로는
    안 보이는 축. Mixamo 소총 동작이 아래팔을 100 ~ 130° 비틀 때마다 손목 · 손이 피부 가장자리를 축으로 휘둘리고 팔꿈치는 관절 뒤를 축으로 접혔다.
  * 손가락 MCP 가 손가락 갈퀴보다 3.5 ~ 4 cm 손목 쪽, PIP 가 갈퀴 위 → 쥐면 손바닥 한가운데가 접혀 능선
    (Mixamo: MCP 는 갈퀴 1.6 cm 앞, PIP 는 1 ~ 2 cm 뒤).
  * thumb_01 이 손목 앞 4 cm 까지 아래팔 살의 8 ~ 20 % 를 잡음 → 엄지가 손목을 끌고 감.

단계
 0. (--raw) 손목 모양 고침: bind 의 손 단계(손 상자 맞춤 · 엄지 돌리기 · 손 크기)가 부분 웨이트로 정점을 옮겨 손목 엄지 쪽에 능선이 생겼다
    (손목을 꺾으면 홈 · 지느러미로 보임). 같은 bind 를 손 단계 없이(정점 순서 같음) 돌린 것과의 변위를 손목 평면 둘레 띠 안에서만 매끈하게 편다.
 1. 관절: 팔꿈치 · 손목(선택: 어깨) → 살 단면 중심. 손가락(검지 ~ 새끼) → 손을 잘라 갈퀴 · 끝을 찾고 MCP = 갈퀴 − mcp_back,
    PIP · DIP 는 비율로 손가락 중심선 위에. 엄지는 그대로(이미 살 위). 옮긴 뼈는 평행이동만(레스트 방향 · 롤 그대로) — UAL 동작의 회전 뜻이 그대로.
    비틀림 뼈는 새 팔꿈치 → 손목 선 위 --twist 비율 자리로.
 2. 웨이트(윗팔 구간부터 바깥): 팔꿈치 = 관절 평면을 가로지르는 smoothstep(--elbow_blend) · 아래팔 = t 에 따라 아래팔 / 비틀림1 / 비틀림2
    구간 선형(DRBaker 비틀림 비율과 같아 비틀림(t) ≈ t × θ) · 손목 = 손목 평면 smoothstep(--wrist_blend) · 손 · 엄지 · 손가락 = UV 이음매를
    합친 몸 사본(물샐틈없는 한 면)에 맞춘 관절 따라 놓은 뼈로 Blender 뼈 열 확산 → 엄지는 손목 뒤에서부터, 손가락 · 엄지의 떨어진 섬 제거.
    정점당 4 뼈 · 합 1.
 3. GLB 내보내기(bind 와 같은 설정) + .import(있으면 _subresources(뼈 이름표)만 src 것으로 바꿈 — uid 등은 그대로). 마지막 줄 RERIG_RESULT {json}.
"""
import bpy, bmesh, sys, os, json, math
from mathutils import Vector, Matrix
import numpy as np


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


A = args()
SRC = A["src"]
OUT = A["out"]
CENTER = A.get("center_arm", "1") == "1"
SHOULDER_K = float(A.get("shoulder_k", "0"))
FINGERS = A.get("fingers", "1") == "1"
MCP_BACK = float(A.get("mcp_back", "0.020"))
RATIOS = [float(x) for x in A.get("ratios", "0.38,0.32,0.30").split(",")]     # MCP->PIP, PIP->DIP, DIP->tip (Mixamo ~.36/.33/.31)
TW = [float(x) for x in A.get("twist", "0.45,0.85").split(",")]
EB = [float(x) for x in A.get("elbow_blend", "-0.025,0.045").split(",")]
WB = [float(x) for x in A.get("wrist_blend", "-0.022,0.012").split(",")]
REGION = [float(x) for x in A.get("region", "0.35,0.50").split(",")]
THUMB_FADE = [float(x) for x in A.get("thumb_fade", "0.0,0.02").split(",")]
HEAT = A.get("heat", "1") == "1"
DRY = A.get("dry", "0") == "1"
RAW = A.get("raw", "")                     # same body bound WITHOUT the hand steps (see wrist_smooth)
WS = [float(x) for x in A.get("wrist_smooth", "-0.06,-0.04,0.015,0.03,40").split(",")]
FING = ("index", "middle", "ring", "pinky")
res = {"src": SRC, "out": OUT}


def smooth(x, a, b):
    if b <= a:
        return 1.0 if x >= a else 0.0
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
bpy.ops.import_scene.gltf(filepath=SRC)
arm = next(o for o in sc.objects if o.type == "ARMATURE")
body = max((o for o in sc.objects if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)),
           key=lambda o: len(o.data.vertices))
arm.data.pose_position = "REST"
keep_action = arm.animation_data.action if arm.animation_data else None
if arm.animation_data:
    arm.animation_data.action = None
bpy.context.view_layer.update()
Wm = arm.matrix_world.copy()
Wi = Wm.inverted()
bw = body.matrix_world.copy()
me = body.data
nv = len(me.vertices)
co0 = np.array([tuple(bw @ v.co) for v in me.vertices])          # world rest positions
co_in = co0.copy()
res["vertices"] = nv


# ---------------------------------------------------------------- optional: wrist geometry repair
# bind_to_skeleton.py's hand steps (hand_fit warp, thumb_fit rotation, hand_scale toward the OLD off-centre wrist) move
# vertices by their partial hand / thumb weights. Around the wrist those weights jump between neighbours (thumb_01 even
# leaked onto the forearm), so the displacement field has a step there: a ridge on the radial edge of the wrist that
# shows as a notch / fin whenever the wrist bends or twists. With --raw (the same bind with the hand steps OFF, same
# vertex order) the hand-step displacement is Laplacian-smoothed inside a band around the wrist plane only; the hand
# shape beyond the band (thumb base, palm, fingers) and the forearm before it keep their positions.
def glb_positions(path):
    import struct
    b = open(path, "rb").read()
    off, js, binc = 12, None, None
    while off < len(b):
        ln, typ = struct.unpack_from("<II", b, off)
        if typ == 0x4E4F534A:
            js = json.loads(b[off + 8: off + 8 + ln])
        elif typ == 0x004E4942:
            binc = b[off + 8: off + 8 + ln]
        off += 8 + ln
    for m in js["meshes"]:
        for pr in m["primitives"]:
            if "JOINTS_0" in pr["attributes"]:
                a = js["accessors"][pr["attributes"]["POSITION"]]
                bv = js["bufferViews"][a["bufferView"]]
                st = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
                p = np.frombuffer(binc, dtype=np.float32, count=a["count"] * 3, offset=st).reshape(-1, 3).astype(np.float64)
                return np.stack([p[:, 0], -p[:, 2], p[:, 1]], axis=1)      # glTF Y-up -> Blender Z-up
    return None


if RAW:
    src_p = glb_positions(SRC)
    raw_p = glb_positions(RAW)
    if src_p is None or raw_p is None or len(raw_p) != nv or np.abs(src_p - co0).max() > 1e-4:
        raise SystemExit("--raw: vertex count/order does not match the source (or mesh node is not identity)")
    D = co0 - raw_p
    keyw = {}
    repw = np.zeros(nv, dtype=np.int64)
    for i in range(nv):
        repw[i] = keyw.setdefault((round(co0[i, 0], 5), round(co0[i, 1], 5), round(co0[i, 2], 5)), len(keyw))
    nw = len(keyw)
    Dw = np.zeros((nw, 3))
    Pw = np.zeros((nw, 3))
    Dw[repw] = D
    Pw[repw] = co0
    nbw = [set() for _ in range(nw)]
    for e in me.edges:
        a_, b_ = repw[e.vertices[0]], repw[e.vertices[1]]
        if a_ != b_:
            nbw[a_].add(b_)
            nbw[b_].add(a_)
    band = np.zeros(nw)
    for sd in ("l", "r"):
        if arm.data.bones.get("hand_" + sd) is None:
            continue
        Wj = Wm @ arm.data.bones["hand_" + sd].head_local
        Ej = Wm @ arm.data.bones["lowerarm_" + sd].head_local
        ax_ = np.array((Wj - Ej).normalized())
        rel = Pw - np.array(Wj)
        s_ = rel @ ax_
        rad = np.linalg.norm(rel - np.outer(s_, ax_), axis=1)
        for i in np.nonzero((s_ > WS[0]) & (s_ < WS[3]) & (rad < 0.08))[0]:
            band[i] = max(band[i], smooth(s_[i], WS[0], WS[1]) * (1.0 - smooth(s_[i], WS[2], WS[3])))
    idx = np.nonzero(band > 0)[0]
    for _ in range(int(WS[4])):
        newD = Dw.copy()
        for i in idx:
            if nbw[i]:
                m_ = Dw[list(nbw[i])].mean(axis=0)
                newD[i] = Dw[i] + 0.5 * band[i] * (m_ - Dw[i])
        Dw = newD
    newP = raw_p + Dw[repw]
    moved = np.linalg.norm(newP - co0, axis=1)
    bwi = bw.inverted()
    for i in np.nonzero(moved > 1e-7)[0]:
        me.vertices[int(i)].co = bwi @ Vector(newP[i])
    me.update()
    co0 = np.array([tuple(bw @ v.co) for v in me.vertices])
    res["wrist_smooth"] = {"band_vertices": int(len(idx)), "moved_vertices": int((moved > 1e-4).sum()),
                           "max_move_cm": round(float(moved.max()) * 100, 2), "mean_move_cm_moved": round(float(moved[moved > 1e-4].mean()) * 100, 2) if (moved > 1e-4).any() else 0}
    print("RERIG_WRIST " + json.dumps(res["wrist_smooth"]))

# ---------------------------------------------------------------- welded topology (UV seams merged)
key = {}
rep = np.zeros(nv, dtype=np.int64)
uniq = []
for i in range(nv):
    k = (round(co0[i, 0], 5), round(co0[i, 1], 5), round(co0[i, 2], 5))
    if k not in key:
        key[k] = len(uniq)
        uniq.append(i)
    rep[i] = key[k]
nu = len(uniq)
UP = co0[uniq]
faces = []
for p in me.polygons:
    f = [int(rep[v]) for v in p.vertices]
    if len(set(f)) == len(f):
        faces.append(f)
edges = set()
for f in faces:
    for j in range(len(f)):
        a_, b_ = f[j], f[(j + 1) % len(f)]
        edges.add((min(a_, b_), max(a_, b_)))
edges = np.array(sorted(edges), dtype=np.int64)
nbr = [[] for _ in range(nu)]
for a_, b_ in edges:
    nbr[a_].append(b_)
    nbr[b_].append(a_)
res["welded_vertices"] = nu


def welded_bmesh(keep=None):
    bm = bmesh.new()
    vs = [bm.verts.new(tuple(p)) for p in UP]
    bm.verts.ensure_lookup_table()
    for f in faces:
        if keep is not None and not all(keep[x] for x in f):
            continue
        try:
            bm.faces.new([vs[x] for x in f])
        except ValueError:
            pass
    return bm


BM_ALL = welded_bmesh()


def slice_loops(bm, P0, ax):
    c = bm.copy()
    r = bmesh.ops.bisect_plane(c, geom=c.verts[:] + c.edges[:] + c.faces[:], dist=1e-7, plane_co=P0, plane_no=ax)
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
        # edge-length weighted centroid (cut points are not uniform)
        acc = Vector()
        tot = 0.0
        pts = []
        for x in es:
            a_, b_ = x.verts[0].co, x.verts[1].co
            l_ = (b_ - a_).length
            acc += (a_ + b_) * 0.5 * l_
            tot += l_
            pts.append(a_.copy())
            pts.append(b_.copy())
        if tot > 1e-9:
            loops.append((acc / tot, pts, tot))
    c.free()
    return loops


def centre_at(P0, ax, rmax=0.09):
    best = None
    for cen, pts, per in slice_loops(BM_ALL, P0, ax):
        d = (cen - P0).length
        if d < rmax and (best is None or d < best[0]):
            best = (d, cen)
    return best[1] if best else None


# ---------------------------------------------------------------- read bones
def B(n):
    return arm.data.bones.get(n)


def head(n):
    return Wm @ B(n).head_local


new_heads = {}        # bone -> new head (world)
joint_report = {}
SIDES = [s for s in ("l", "r") if B("hand_" + s) is not None]

for sd in SIDES:
    SH, EL, WR = head("upperarm_" + sd), head("lowerarm_" + sd), head("hand_" + sd)
    du = (EL - SH).normalized()
    df = (WR - EL).normalized()
    rep_s = {}
    if CENTER:
        # elbow: average of slices around the joint, keep the position along the arm
        cs = []
        for dt in (-0.015, 0.0, 0.015):
            c_ = centre_at(EL + df * dt, df)
            if c_ is not None:
                cs.append(c_ - df * dt)
        EL2 = sum(cs, Vector()) / len(cs) if cs else EL
        EL2 = EL2 - df * (EL2 - EL).dot(df)
        # wrist: narrowest part just before the joint
        cs = []
        for dt in (-0.02, -0.01, 0.0, 0.005):
            c_ = centre_at(WR + df * dt, df)
            if c_ is not None:
                cs.append(c_ - df * dt)
        WR2 = sum(cs, Vector()) / len(cs) if cs else WR
        WR2 = WR2 - df * (WR2 - WR).dot(df)
        SH2 = SH
        if SHOULDER_K > 0:
            cs = []
            for t_ in (0.25, 0.3, 0.35):
                c_ = centre_at(SH + (EL - SH) * t_, du)
                if c_ is not None:
                    cs.append(c_ - (EL - SH) * t_)
            if cs:
                off = sum(cs, Vector()) / len(cs) - SH
                off = off - du * off.dot(du)
                SH2 = SH + off * SHOULDER_K
        new_heads["upperarm_" + sd] = SH2
        new_heads["lowerarm_" + sd] = EL2
        new_heads["hand_" + sd] = WR2
        rep_s["shoulder_cm"] = [round(x * 100, 2) for x in (SH2 - SH)]
        rep_s["elbow_cm"] = [round(x * 100, 2) for x in (EL2 - EL)]
        rep_s["wrist_cm"] = [round(x * 100, 2) for x in (WR2 - WR)]
    else:
        SH2, EL2, WR2 = SH, EL, WR
    for k, f in (("lowerarm_twist_01_" + sd, TW[0]), ("lowerarm_twist_02_" + sd, TW[1])):
        if B(k) is not None:
            new_heads[k] = EL2 + (WR2 - EL2) * f

    # ---------------- fingers: slice the hand along its axis
    if FINGERS:
        mid1 = head("middle_01_" + sd)
        ax = (mid1 - WR).normalized()
        lat = head("index_01_" + sd) - head("pinky_01_" + sd)
        Lx = (lat - ax * lat.dot(ax)).normalized()
        Nx = ax.cross(Lx)
        keep = [((Vector(p) - WR2).dot(ax) > 0.04) and ((Vector(p) - WR2).length < 0.30) for p in UP]
        bmh = welded_bmesh(keep)
        # finger lateral positions (current 02 / 03 joints are inside the free finger) and thumb line
        fl = {f: ((head("%s_02_%s" % (f, sd)) + head("%s_03_%s" % (f, sd))) * 0.5 - WR2).dot(Lx) for f in FING}
        th_pts = [head("thumb_0%d_%s" % (i, sd)) for i in (1, 2, 3)] + [head("thumb_04_leaf_" + sd)]

        def near_thumb(p):
            best = 1e9
            for i in range(3):
                a_, b_ = th_pts[i], th_pts[i + 1]
                d_ = b_ - a_
                t_ = max(0.0, min(1.0, (p - a_).dot(d_) / max(d_.length_squared, 1e-12)))
                best = min(best, (p - (a_ + d_ * t_)).length)
            return best
        amax = max((Vector(p) - WR2).dot(ax) for p in UP if (Vector(p) - WR2).length < 0.30)
        track = {f: [] for f in FING}       # (a, centroid) of loops that hold exactly one finger
        a_ = 0.06
        step = 0.0015
        while a_ < amax + step:
            for cen, pts, per in slice_loops(bmh, WR2 + ax * a_, ax):
                if near_thumb(cen) < 0.012:
                    continue
                ls = [(p - WR2).dot(Lx) for p in pts]
                lo, hi = min(ls) - 0.002, max(ls) + 0.002
                inside = [f for f in FING if lo <= fl[f] <= hi]
                if len(inside) == 1:
                    track[inside[0]].append((a_, cen))
            a_ += step
        bmh.free()
        fingers_rep = {}
        for f in FING:
            T = track[f]
            if len(T) < 6:
                fingers_rep[f] = "not found"
                continue
            # free part = the contiguous run ending at the tip
            T.sort(key=lambda t: t[0])
            run = [T[-1]]
            for t in reversed(T[:-1]):
                if run[-1][0] - t[0] <= step * 1.6:
                    run.append(t)
                else:
                    break
            run.reverse()
            web = run[0][0]
            tip = run[-1][0] + step * 0.5
            # centre line: PCA over the free part (skip the last 8 mm where the tip loop shrinks)
            P = np.array([tuple(c) for a, c in run if a < tip - 0.008] or [tuple(c) for a, c in run])
            cP = P.mean(axis=0)
            _, _, vt = np.linalg.svd(P - cP, full_matrices=False)
            e = Vector(vt[0])
            if e.dot(ax) < 0:
                e = -e
            cV = Vector(cP)

            def at(a_val):          # point on the centre line whose distance along the hand axis is a_val
                s_ = (a_val - (cV - WR2).dot(ax)) / max(e.dot(ax), 1e-6)
                return cV + e * s_
            mcp = web - MCP_BACK
            L = tip - mcp
            pip = mcp + RATIOS[0] * L
            dip = pip + RATIOS[1] * L
            end = tip - 0.003
            J = [at(mcp), at(pip), at(dip), at(end)]
            old = [head("%s_0%d_%s" % (f, i, sd)) for i in (1, 2, 3)] + [head("%s_04_leaf_%s" % (f, sd))]
            for i, n in enumerate(["%s_01_%s" % (f, sd), "%s_02_%s" % (f, sd), "%s_03_%s" % (f, sd), "%s_04_leaf_%s" % (f, sd)]):
                new_heads[n] = J[i]
            fingers_rep[f] = {"web_cm": round(web * 100, 1), "tip_cm": round(tip * 100, 1),
                              "joints_a_cm": [round((j - WR2).dot(ax) * 100, 1) for j in J],
                              "old_a_cm": [round((o - WR).dot(ax) * 100, 1) for o in old],
                              "moved_cm": [round((J[i] - old[i]).length * 100, 1) for i in range(4)]}
        rep_s["fingers"] = fingers_rep
    joint_report[sd] = rep_s
res["joints"] = joint_report
print("RERIG_JOINTS " + json.dumps(joint_report))
if DRY:
    print("RERIG_RESULT " + json.dumps(res))
    raise SystemExit(0)

# ---------------------------------------------------------------- edit bones
bpy.ops.object.select_all(action="DESELECT")
bpy.context.view_layer.objects.active = arm
arm.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
EB_ = arm.data.edit_bones
orig = {eb.name: (eb.head.copy(), eb.tail.copy(), eb.z_axis.copy(), eb.use_connect) for eb in EB_}


def final_head(n):
    if n in new_heads:
        return Wi @ new_heads[n]
    return orig[n][0]


# bones whose head (or a child's head) moved get disconnected first
for n in new_heads:
    eb = EB_.get(n)
    if eb is None:
        continue
    eb.use_connect = False
    for c in eb.children:
        c.use_connect = False


def set_bone(n, h, t, z):
    eb = EB_[n]
    eb.use_connect = False
    eb.head = h
    eb.tail = t
    eb.align_roll(z)


# heat layout: segments along the flesh (temporary)
heat_layout = {}
for sd in SIDES:
    E2, W2 = final_head("lowerarm_" + sd), final_head("hand_" + sd)
    heat_layout["upperarm_" + sd] = (final_head("upperarm_" + sd), E2)
    heat_layout["lowerarm_" + sd] = (E2, W2)
    mcps = [final_head("%s_01_%s" % (f, sd)) for f in FING]
    heat_layout["hand_" + sd] = (W2, sum(mcps, Vector()) / 4.0)
    for f in FING + ("thumb",):
        js = [final_head("%s_0%d_%s" % (f, i, sd)) for i in (1, 2, 3)] + [final_head("%s_04_leaf_%s" % (f, sd))]
        for i in range(3):
            heat_layout["%s_0%d_%s" % (f, i + 1, sd)] = (js[i], js[i + 1])

heat_w = None
if HEAT:
    for n, (h, t) in heat_layout.items():
        set_bone(n, h, t, orig[n][2])
    bpy.ops.object.mode_set(mode="OBJECT")
    # welded proxy object
    pm = bpy.data.meshes.new("HeatProxy")
    pm.from_pydata([tuple(p) for p in UP], [], faces)
    pm.validate()
    proxy = bpy.data.objects.new("HeatProxy", pm)
    sc.collection.objects.link(proxy)
    saved = {b.name: b.use_deform for b in arm.data.bones}
    for b in arm.data.bones:
        b.use_deform = saved[b.name] and "twist" not in b.name and "leaf" not in b.name and b.name != "root"
    bpy.ops.object.select_all(action="DESELECT")
    proxy.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for b in arm.data.bones:
        b.use_deform = saved[b.name]
    gname = {g.index: g.name for g in proxy.vertex_groups}
    heat_w = [dict() for _ in range(nu)]
    zero = 0
    for v in pm.vertices:
        d_ = {gname[g.group]: g.weight for g in v.groups if g.weight > 1e-5}
        if not d_:
            zero += 1
        heat_w[v.index] = d_
    res["heat_unweighted"] = zero
    bpy.data.objects.remove(proxy, do_unlink=True)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    EB_ = arm.data.edit_bones

# final rest: translate moved bones, keep orientation (direction + roll)
for n, (h0, t0, z0, con) in orig.items():
    if n in new_heads:
        h = Wi @ new_heads[n]
        set_bone(n, h, h + (t0 - h0), z0)
    elif n in heat_layout:
        set_bone(n, h0, t0, z0)       # restore after the heat layout
bpy.ops.object.mode_set(mode="OBJECT")

# ---------------------------------------------------------------- weights
gi = {vg.name: vg.index for vg in body.vertex_groups}


def group(n):
    if n not in gi:
        gi[n] = body.vertex_groups.new(name=n).index
    return gi[n]


old_w = [{g.group: g.weight for g in v.groups if g.weight > 0.0} for v in me.vertices]
gname_b = {i: n for n, i in gi.items()}
new_w = [None] * nv
wrep = {}
for sd in SIDES:
    SH2, EL2, WR2 = (new_heads.get(n, head(n)) for n in ("upperarm_" + sd, "lowerarm_" + sd, "hand_" + sd))
    du = (EL2 - SH2)
    Lu = du.length
    du = du / Lu
    df = (WR2 - EL2)
    Lf = df.length
    df = df / Lf
    ne = (du + df).normalized()
    HF = {"hand_" + sd} | {"%s_0%d_%s" % (f, i, sd) for f in FING + ("thumb",) for i in (1, 2, 3)}
    thumb1 = "thumb_01_" + sd
    cnt = 0
    for i in range(nv):
        p = Vector(co0[i])
        u = (p - SH2).dot(du) / Lu
        if u < REGION[0]:
            continue
        # distance to the arm polyline (shoulder-elbow-wrist-hand) — skip far-away flesh (none expected in T-pose)
        rad = min(((p - SH2) - du * max(0.0, min(Lu, (p - SH2).dot(du)))).length,
                  ((p - EL2) - df * max(0.0, (p - EL2).dot(df))).length)
        if rad > 0.16:
            continue
        e = (p - EL2).dot(ne)
        w_low = smooth(e, EB[0], EB[1])
        wd = (p - WR2).dot(df)
        w_hf = smooth(wd, WB[0], WB[1])
        t = (p - EL2).dot(df) / Lf
        W = {}
        W["upperarm_" + sd] = 1.0 - w_low
        fore = w_low * (1.0 - w_hf)
        if fore > 0:
            f1, f2 = TW
            if t <= 0:
                W["lowerarm_" + sd] = fore
            elif t < f1:
                W["lowerarm_" + sd] = fore * (f1 - t) / f1
                W["lowerarm_twist_01_" + sd] = fore * t / f1
            elif t < f2:
                W["lowerarm_twist_01_" + sd] = fore * (f2 - t) / (f2 - f1)
                W["lowerarm_twist_02_" + sd] = fore * (t - f1) / (f2 - f1)
            else:
                W["lowerarm_twist_02_" + sd] = fore
        hand = w_low * w_hf
        if hand > 0:
            fr = {}
            if heat_w is not None:
                hw = heat_w[rep[i]]
                fr = {n: w for n, w in hw.items() if n in HF}
                tot = sum(fr.values())
                s_ = smooth(tot, 0.1, 0.5)
                fr = {n: w / tot * s_ for n, w in fr.items()} if tot > 0 else {}
                fr["hand_" + sd] = fr.get("hand_" + sd, 0.0) + (1.0 - s_)
            else:
                fr = {"hand_" + sd: 1.0}
            # thumb CMC must not pull the wrist: fade thumb_01 in after the wrist plane
            if thumb1 in fr:
                k = smooth(wd, THUMB_FADE[0], THUMB_FADE[1])
                fr["hand_" + sd] = fr.get("hand_" + sd, 0.0) + fr[thumb1] * (1.0 - k)
                fr[thumb1] *= k
            for n, w in fr.items():
                W[n] = W.get(n, 0.0) + hand * w
        # blend with old weights at the start of the region
        k = smooth(u, REGION[0], REGION[1])
        mix = {}
        for g, w in old_w[i].items():
            mix[gname_b[g]] = mix.get(gname_b[g], 0.0) + w * (1.0 - k)
        for n, w in W.items():
            mix[n] = mix.get(n, 0.0) + w * k
        new_w[i] = mix
        cnt += 1
    wrep[sd] = {"region_vertices": cnt}

# island cleanup for finger / thumb bones (welded graph) + spike guard
for sd in SIDES:
    bones = ["%s_0%d_%s" % (f, i, sd) for f in FING + ("thumb",) for i in (1, 2, 3)]
    removed = 0
    for bn_ in bones:
        hs, ts = heat_layout.get(bn_, (None, None))
        if hs is None:
            continue
        hsw, tsw = Wm @ hs, Wm @ ts
        # welded vertex weight = max over its copies
        wv = np.zeros(nu)
        for i in range(nv):
            if new_w[i] is not None:
                wv[rep[i]] = max(wv[rep[i]], new_w[i].get(bn_, 0.0))
        mask = wv > 0.02
        if not mask.any():
            continue
        comp = -np.ones(nu, dtype=np.int64)
        cid = 0
        keepc = set()
        d_ = tsw - hsw
        for s0 in np.nonzero(mask)[0]:
            if comp[s0] >= 0:
                continue
            stack = [s0]
            comp[s0] = cid
            near = False
            while stack:
                x = stack.pop()
                p = Vector(UP[x])
                tt = max(0.0, min(1.0, (p - hsw).dot(d_) / max(d_.length_squared, 1e-12)))
                if (p - (hsw + d_ * tt)).length < 0.02:
                    near = True
                for y in nbr[x]:
                    if mask[y] and comp[y] < 0:
                        comp[y] = cid
                        stack.append(y)
            if near:
                keepc.add(cid)
            cid += 1
        for i in range(nv):
            if new_w[i] is not None and bn_ in new_w[i]:
                c_ = comp[rep[i]]
                if c_ >= 0 and c_ not in keepc:
                    w = new_w[i].pop(bn_)
                    new_w[i]["hand_" + sd] = new_w[i].get("hand_" + sd, 0.0) + w
                    removed += 1
    wrep[sd]["island_vertices_fixed"] = removed

# limit 4 + normalise, write groups
changed = 0
for i in range(nv):
    W = new_w[i]
    if W is None:
        continue
    items = sorted(((n, w) for n, w in W.items() if w > 1e-4), key=lambda kv: -kv[1])[:4]
    s_ = sum(w for _, w in items)
    for g in list(me.vertices[i].groups):
        body.vertex_groups[g.group].remove([i])
    for n, w in items:
        body.vertex_groups[group(n)].add([i], w / s_, "REPLACE")
    changed += 1
res["weights"] = wrep
res["weights_changed_vertices"] = changed

# checks: positions untouched, influences
co1 = np.array([tuple(bw @ v.co) for v in me.vertices])
mv = np.linalg.norm(co1 - co_in, axis=1)
res["max_vertex_move_m"] = round(float(mv.max()), 5)
res["moved_vertices"] = int((mv > 1e-4).sum())
mi = max(len([g for g in v.groups if g.weight > 1e-4]) for v in me.vertices)
res["max_influences"] = mi
res["unweighted"] = sum(1 for v in me.vertices if not any(g.weight > 1e-4 for g in v.groups))

# dominant counts per arm bone (left) for the report
dom = {}
gn = {vg.index: vg.name for vg in body.vertex_groups}
for v in me.vertices:
    if v.groups:
        g = max(v.groups, key=lambda g: g.weight)
        n = gn[g.group]
        if n.endswith("_l") and any(n.startswith(k) for k in ("upperarm", "lowerarm", "hand", "thumb", "index", "middle", "ring", "pinky")):
            dom[n] = dom.get(n, 0) + 1
res["dominant_left"] = dict(sorted(dom.items()))

# ---------------------------------------------------------------- export
arm.data.pose_position = "POSE"
if keep_action is not None:
    arm.animation_data.action = keep_action
os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True,
                          export_animations=True, export_animation_mode="ACTIONS",
                          export_skins=True, export_all_influences=False)
# .import: copy the source's _subresources (BoneMap) so Mixamo motions land on this skeleton
si = SRC + ".import"
note = "no source .import"
if os.path.exists(si):
    t = open(si, encoding="utf-8").read()
    i0 = t.find("_subresources=")
    if i0 >= 0:
        depth, i1 = 0, i0 + len("_subresources=")
        for j in range(i1, len(t)):
            if t[j] == "{":
                depth += 1
            elif t[j] == "}":
                depth -= 1
                if depth == 0:
                    i1 = j + 1
                    break
        block = t[i0:i1]
        oi = OUT + ".import"
        if os.path.exists(oi):
            # 이미 있는 .import(에디터가 쓴 uid · 경로)는 지키고 _subresources 블록만 바꾼다 — 통째로 새로 쓰면 uid 가 바뀌어
            # 그 모델을 uid 로 가리키던 곳이 "Can't find file uid://…" 가 된다(bind_to_skeleton.py 와 같은 방식)
            ot = open(oi, encoding="utf-8").read()
            k0 = ot.find("_subresources=")
            if k0 >= 0:
                depth, k1 = 0, k0 + len("_subresources=")
                for j in range(k1, len(ot)):
                    if ot[j] == "{":
                        depth += 1
                    elif ot[j] == "}":
                        depth -= 1
                        if depth == 0:
                            k1 = j + 1
                            break
                ot = ot[:k0] + block + ot[k1:]
            else:
                ot = ot.replace("[params]\n", "[params]\n\n" + block + "\n", 1)
        else:
            ot = "[remap]\n\nimporter=\"scene\"\nimporter_version=1\n\n[params]\n\n" + block + "\n"
        with open(oi, "w", encoding="utf-8", newline="\n") as f:
            f.write(ot)
        note = "copied _subresources (BoneMap)"
res["godot_import"] = note
res["ok"] = os.path.exists(OUT)
print("RERIG_RESULT " + json.dumps(res, ensure_ascii=False))
