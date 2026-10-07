@tool
extends RefCounted
class_name DRMeshCutter

## 자르기 — 부위 경계를 사용자가 그은 직선 · 사각형 그대로 곧게 낸다(10-06).
##
## 붓 · 정점 칠하기는 정점마다 부위를 바꾸므로 경계가 삼각형 모서리를 따라가 톱니(지글재글 · 대각선)가 된다.
## 자르기는 삼각형 자체를 평면에서 쪼갠다 — 모서리 위에 새 정점(위치 · 법선 · UV · 색 · 뼈 웨이트 보간)을 만들어
## 경계가 평면 그대로 곧다. 3D 변형은 그대로(새 정점도 양쪽 정점의 웨이트를 섞어 같이 움직인다).
##
## 자르기 하나 = {"to": 부위, "from": 부위 또는 "*"(아무 부위), "planes": [[nx, ny, nz, d], …]}
##   영역 = 모든 평면에서 n·p ≥ d 인 곳(볼록). 좌표 = 모델 메시 공간(바인드 = T-포즈).
##   같은 뼈대 · 같은 T-포즈의 모델(옷 모델 · 기본 몸)은 같은 자르기가 같은 자리를 자른다.
##   from 부위의 면 중 영역 안 → to 부위로. 정점 칠하기(붓) 다음에, 적힌 순서대로 적용한다.
##   kind = "joint"(관절 경계): 관절마다 부모 · 자식 부위의 경계 — 뼈 방향에 수직인 평면 + 관절 둘레 상자(joint_planes).
##   kind = "line"(직선): from · to 두 부위의 경계 — 선 양 끝 사이(planes[1..])에서 두 부위의 면을 평면 planes[0] 으로 다시 나눈다
##   (앞 = to, 뒤 = from). 어느 쪽 톱니가 넘어와 있었든 경계가 선 그대로 곧다.
## 겹침(margin): 영역으로 가는 쪽은 영역을 margin 만큼 넓혀, 남는 쪽은 margin 만큼 줄여 자른다 →
##   두 조각이 경계에서 조금 겹친다(움직일 때 틈 방지). 보이는 가장자리는 위에 그려지는 조각의 곧은 선.

const MARGIN := 0.012   # m — 굽기용 겹침(1.2 cm ≈ 도트 1칸)


static func plane_dist(pl: Array, p: Vector3) -> float:
	return float(pl[0]) * p.x + float(pl[1]) * p.y + float(pl[2]) * p.z - float(pl[3])


## p 가 영역(planes) 안인가. off > 0 이면 그만큼 안쪽까지만
static func inside(planes: Array, p: Vector3, off: float = 0.0) -> bool:
	for pl in planes:
		if plane_dist(pl, p) < off:
			return false
	return true


## 다각형(정점 목록)을 평면으로 자른다. keep_inside = n·p ≥ d + off 쪽을 남김, 아니면 그 반대쪽
## pos_of(정점) → Vector3 · lerp_fn(a, b, t) → 새 정점
static func clip(poly: Array, pl: Array, off: float, keep_inside: bool, pos_of: Callable, lerp_fn: Callable) -> Array:
	var out: Array = []
	var n := poly.size()
	if n == 0:
		return out
	var ds := PackedFloat32Array()
	ds.resize(n)
	for i in n:
		var d := plane_dist(pl, pos_of.call(poly[i])) - off
		ds[i] = d if keep_inside else -d
	for i in n:
		var j := (i + 1) % n
		var da := ds[i]
		var db := ds[j]
		if da >= 0.0:
			out.append(poly[i])
		if (da >= 0.0) != (db >= 0.0):
			out.append(lerp_fn.call(poly[i], poly[j], da / (da - db)))
	return out


## 볼록 영역으로 다각형을 나눈다 → {"in": [다각형…](영역 + margin), "out": [다각형…](영역 − margin 의 바깥)}
static func split_region(poly: Array, planes: Array, margin: float, pos_of: Callable, lerp_fn: Callable) -> Dictionary:
	var res := {"in": [], "out": []}
	var all_in := true
	for pl in planes:
		var mn := INF
		var mx := -INF
		for r in poly:
			var d := plane_dist(pl, pos_of.call(r))
			mn = minf(mn, d)
			mx = maxf(mx, d)
		if mx < -margin:            # 넓힌 영역 밖 — 그대로 남음
			res["out"].append(poly)
			return res
		if mn < margin:
			all_in = false
	if all_in:                      # 줄인 영역 안 — 통째로 감
		res["in"].append(poly)
		return res
	var inner := poly
	for pl in planes:
		inner = clip(inner, pl, -margin, true, pos_of, lerp_fn)
		if inner.size() < 3:
			break
	if inner.size() >= 3:
		res["in"].append(inner)
	var rest := poly                # 바깥 = 평면마다 "앞 평면들 안 ∩ 이 평면 밖" 의 합
	for pl in planes:
		var o := clip(rest, pl, margin, false, pos_of, lerp_fn)
		if o.size() >= 3:
			res["out"].append(o)
		rest = clip(rest, pl, margin, true, pos_of, lerp_fn)
		if rest.size() < 3:
			break
	return res


static func _fan(poly: Array, out: PackedInt32Array) -> void:
	for k in range(1, poly.size() - 1):
		out.append(int(poly[0]))
		out.append(int(poly[k]))
		out.append(int(poly[k + 1]))


static func _tri_key(arr: PackedInt32Array, k: int) -> Vector3i:
	var a := arr[k * 3]
	var b := arr[k * 3 + 1]
	var c := arr[k * 3 + 2]
	var lo := mini(a, mini(b, c))
	var hi := maxi(a, maxi(b, c))
	return Vector3i(lo, a + b + c - lo - hi, hi)


## 부위별 삼각형 목록(part -> PackedInt32Array, 정점 번호는 pool 기준)에 자르기를 적용한다(제자리).
## parts = 받을 수 있는 부위(없는 부위로 가는 자르기는 건너뜀). 한 면이 여러 부위로 같은 조각이 되면 하나만 남긴다.
static func apply_cuts(part_tris: Dictionary, cuts: Array, pool: VertexPool, parts: Dictionary, margin: float) -> void:
	var pos_of := func(i): return pool.pos[i]
	var lerp_fn := func(a, b, t): return pool.lerp_vertex(a, b, t)
	for c in cuts:
		var cd := c as Dictionary
		var to := String(cd.get("to", ""))
		var planes: Array = cd.get("planes", [])
		if to == "" or not parts.has(to) or planes.is_empty():
			continue
		var from := String(cd.get("from", "*"))
		if _is_boundary(cd):
			if parts.has(from) and from != to:
				_apply_boundary(part_tris, from, to, planes, margin, margin, pos_of, lerp_fn)
			continue
		var srcs: Array = part_tris.keys() if from == "*" else ([from] if part_tris.has(from) else [])
		if cd.has("only"):            # 사각형: 화면에 보이던 부위만(뒤에 숨은 다른 부위는 안 건드림)
			var only: Array = cd["only"]
			srcs = srcs.filter(func(s): return only.has(String(s)))
		var add := PackedInt32Array()
		for s in srcs:
			if String(s) == to:
				continue
			var tris: PackedInt32Array = part_tris[s]
			var keep := PackedInt32Array()
			for k in int(tris.size() / 3):
				var r := split_region([tris[k * 3], tris[k * 3 + 1], tris[k * 3 + 2]], planes, margin, pos_of, lerp_fn)
				for p in r["out"]:
					_fan(p, keep)
				for p in r["in"]:
					_fan(p, add)
			part_tris[s] = keep
		if add.is_empty():
			continue
		part_tris[to] = _merge(part_tris.get(to, PackedInt32Array()), add)


## 직선 = 두 부위(s · t)의 경계. 선의 양 끝 사이(planes[1..])에서 s · t 의 면을 모두 평면 planes[0] 으로 다시 나눈다:
## 평면 앞(n·p ≥ d) = t, 뒤 = s. 원래 어느 쪽 톱니가 넘어와 있었든 경계가 평면 그대로 곧다.
## m_s = s 가 평면 앞(t 쪽)으로 넘어가는 겹침, m_t = t 가 평면 뒤(s 쪽)로 넘어가는 겹침.
static func _apply_boundary(part_tris: Dictionary, s: String, t: String, planes: Array, m_s: float, m_t: float, pos_of: Callable, lerp_fn: Callable) -> void:
	var main: Array = planes[0]
	var slab := planes.slice(1)
	var buf := {}          # 면 키 -> [면, s 에 있었나, t 에 있었나]
	for pair in [[s, 1], [t, 2]]:
		var arr: PackedInt32Array = part_tris.get(pair[0], PackedInt32Array())
		for k in int(arr.size() / 3):
			var key := _tri_key(arr, k)
			if not buf.has(key):
				buf[key] = [[arr[k * 3], arr[k * 3 + 1], arr[k * 3 + 2]], false, false]
			buf[key][pair[1]] = true
	var new_s := PackedInt32Array()
	var new_t := PackedInt32Array()
	for e in buf.values():
		var poly: Array = e[0]
		var r := split_region(poly, slab, 0.0, pos_of, lerp_fn) if not slab.is_empty() else {"in": [poly], "out": []}
		for po in r["out"]:           # 선 양 끝 바깥 — 원래 주인 그대로
			if e[1]:
				_fan(po, new_s)
			if e[2]:
				_fan(po, new_t)
		for pi in r["in"]:
			var pt := clip(pi, main, -m_t, true, pos_of, lerp_fn)
			if pt.size() >= 3:
				_fan(pt, new_t)
			var ps := clip(pi, main, m_s, false, pos_of, lerp_fn)
			if ps.size() >= 3:
				_fan(ps, new_s)
	part_tris[s] = new_s
	part_tris[t] = new_t


static func _merge(cur: PackedInt32Array, add: PackedInt32Array) -> PackedInt32Array:
	var have := {}
	for k in int(cur.size() / 3):
		have[_tri_key(cur, k)] = true
	for k in int(add.size() / 3):
		var key := _tri_key(add, k)
		if have.has(key):
			continue
		have[key] = true
		cur.append(add[k * 3])
		cur.append(add[k * 3 + 1])
		cur.append(add[k * 3 + 2])
	return cur


## 정점 하나의 부위에 자르기들을 적용(표시 · 고르기용 — 굽기의 apply_cuts 와 같은 규칙, 겹침 없이)
static func cut_vertex_part(cuts: Array, p: Vector3, part: String) -> String:
	for c in cuts:
		var cd := c as Dictionary
		var planes: Array = cd.get("planes", [])
		var to := String(cd.get("to", ""))
		var from := String(cd.get("from", "*"))
		if planes.is_empty() or to == "":
			continue
		if _is_boundary(cd):
			if (part == from or part == to) and inside(planes.slice(1), p):
				part = to if plane_dist(planes[0], p) >= 0.0 else from
		elif (from == "*" or from == part) and (not cd.has("only") or (cd["only"] as Array).has(part)) and inside(planes, p):
			part = to
	return part


## 경계 방식(두 부위의 경계를 평면으로 다시 긋기) — 직선 · 관절
static func _is_boundary(cd: Dictionary) -> bool:
	var k := String(cd.get("kind", ""))
	return (k == "line" or k == "joint") and String(cd.get("from", "*")) != "*"


## ---------------------------------------------------------------- 관절 경계
## 관절 경계 = 뼈대의 관절(목 · 손목 · 팔꿈치 …)마다 두 부위(부모 · 자식)의 경계를 곧은 평면으로 정한 것(kind = "joint").
## 평면 = 관절 위치에서 뼈 방향에 수직(위치 · 기울기 조절), 관절 둘레의 상자(h) 안에서만 — 그 두 부위 말고는 안 건드린다.
## 바인드(T-포즈) 위치라 같은 뼈대의 모델(옷 모델 · 기본 몸)에 같은 경계가 그대로 맞는다.

const JOINT_LABELS := {
	"Head": "목", "Torso": "허리",
	"L_UpperArm": "왼 어깨", "L_Forearm": "왼 팔꿈치", "L_Hand": "왼 손목",
	"R_UpperArm": "오른 어깨", "R_Forearm": "오른 팔꿈치", "R_Hand": "오른 손목",
	"L_Thigh": "왼 엉덩이", "L_Calf": "왼 무릎", "L_Foot": "왼 발목",
	"R_Thigh": "오른 엉덩이", "R_Calf": "오른 무릎", "R_Foot": "오른 발목",
}
## 처음 켤 때의 위치(m). 목 관절 뼈(neck_01)는 목 아래 끝이라 거기서 자르면 기본 몸의 어깨 · 민소매가 머리 조각에 딸려 와
## 군복 깃 위로 보인다(10-06 확인: 0 · +3 cm 는 내복 보임, +6 cm 깨끗) → 목은 +6 cm 에서 시작
## 손목은 −3 cm(소매 끝): 손목 관절(0)이나 손 쪽(+)에서 자르면 소매 조각이 옷 모델의 손목(M36 은 손목시계 끈까지)을 끼고
## 열린 통으로 잘려, 뒤에 깔린 기본 몸 손(소매보다 가늚)이 구멍을 못 메워 소매 안으로 배경이 비쳤다(10-06 먼 손 · +2 / 0 cm 확인, −3 cm 깨끗).
const JOINT_DEFAULT_OFFSET := {"Head": 0.06, "L_Hand": -0.03, "R_Hand": -0.03}
## 엉덩이(Hips | Thigh)는 뺀다 — 고관절은 팔다리처럼 둥근 단면이 아니라 상자가 엉덩이 · 옷자락을 가로질러, 상자 안팎이
## 평면 / 웨이트로 따로 나뉘어 조각이 찢기고 옷자락이 허벅지에 붙어 펄럭였다(10-06 확인: 겹침을 꺼도 같음). 그 경계는 웨이트대로.
const JOINT_ORDER := ["Head", "L_Hand", "R_Hand", "Torso", "L_Forearm", "R_Forearm", "L_UpperArm", "R_UpperArm",
	"L_Calf", "R_Calf", "L_Foot", "R_Foot"]


## 뼈 번호 → 바인드 위치(모델 메시 공간). 스킨의 바인드 포즈(메시 → 뼈)를 뒤집어 원점을 얻는다
static func bone_bind_positions(mi: MeshInstance3D, skel: Skeleton3D) -> Dictionary:
	var out := {}
	var skin := mi.skin
	if skin != null:
		var binds := DRMeshSplitter._bind_map(mi, skel)
		for i in skin.get_bind_count():
			var b := binds[i] if i < binds.size() else -1
			if b >= 0:
				out[b] = skin.get_bind_pose(i).affine_inverse().origin
	for b in skel.get_bone_count():
		if not out.has(b):
			out[b] = skel.get_bone_global_rest(b).origin
	return out


## 관절 목록: [{key(자식 부위), from(부모 부위), to(자식 부위), label, c(관절 위치), d(뼈 방향, 부모 → 자식)}]
static func joint_list(split: DRMeshSplitter.SplitResult, mi: MeshInstance3D, skel: Skeleton3D) -> Array:
	var pos := bone_bind_positions(mi, skel)
	var out: Array = []
	for part in JOINT_ORDER:
		if not split.part_bones.has(part):
			continue
		var bones: PackedInt32Array = split.part_bones[part]
		var root := -1
		var best_depth := 1 << 20
		for b in bones:
			if bones.has(skel.get_bone_parent(b)):
				continue
			var depth := 0
			var p := b
			while p >= 0:
				depth += 1
				p = skel.get_bone_parent(p)
			if depth < best_depth:
				best_depth = depth
				root = b
		if root < 0:
			continue
		var pb := skel.get_bone_parent(root)
		var parent_part := ""
		var q := pb
		while q >= 0 and parent_part == "":
			parent_part = String(split.bone_part.get(q, ""))
			q = skel.get_bone_parent(q)
		if parent_part == "" or parent_part == part or pb < 0:
			continue
		var c: Vector3 = pos[root]
		var d := Vector3.ZERO
		if not (part.ends_with("Hand") or part.ends_with("Foot")):
			var acc := Vector3.ZERO
			var n := 0
			for ch in skel.get_bone_children(root):
				if bones.has(ch) and pos.has(ch) and (pos[ch] as Vector3).distance_to(c) > 0.01:
					acc += pos[ch]
					n += 1
			if n > 0:
				d = (acc / n - c).normalized()
		if d == Vector3.ZERO:     # 손 · 발(손가락 · 발끝 쪽은 방향이 제각각) · 자식 없음 → 부모 뼈 방향
			d = (c - (pos[pb] as Vector3)).normalized()
		if d == Vector3.ZERO:
			continue
		out.append({"key": part, "from": parent_part, "to": part, "label": String(JOINT_LABELS.get(part, part)), "c": c, "d": d})
	return out


## 관절 경계의 평면들: [자르는 평면(자식 쪽이 앞), 상자 네 면]. 기울기 축 = 뼈 방향 × 앞(+Z)
static func joint_planes(c: Vector3, d: Vector3, offset: float, tilt_deg: float, h: float) -> Array:
	var a := d.cross(Vector3(0, 0, 1))
	if a.length() < 0.1:
		a = d.cross(Vector3(1, 0, 0))
	a = a.normalized()
	var n := d.rotated(a, deg_to_rad(tilt_deg)).normalized()
	var q := c + d * offset
	var e2 := d.cross(a).normalized()
	var r := func(v: Vector3, dd: float) -> Array:
		return [snappedf(v.x, 0.000001), snappedf(v.y, 0.000001), snappedf(v.z, 0.000001), snappedf(dd, 0.000001)]
	return [r.call(n, n.dot(q)),
		r.call(a, a.dot(c) - h), r.call(-a, -a.dot(c) - h),
		r.call(e2, e2.dot(c) - h), r.call(-e2, -e2.dot(c) - h)]


## 관절 둘레 상자 크기(반): 자식 부위 정점 중 관절 근처(뼈 방향으로 ±6 cm)의 뼈에서 먼 거리 × 1.2 + 2 cm
static func joint_box(points: PackedVector3Array, c: Vector3, d: Vector3) -> float:
	var r := 0.0
	for p in points:
		var v := p - c
		var ax := v.dot(d)
		if absf(ax) > 0.06:
			continue
		r = maxf(r, (v - d * ax).length())
	if r <= 0.0:
		return 0.12
	return clampf(r * 1.2 + 0.02, 0.05, 0.35)


## 서피스 배열에 새 정점(모서리 위 보간)을 덧붙이는 통 — finish() 가 늘어난 배열을 돌려준다
class VertexPool:
	extends RefCounted
	var arrays: Array
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var tan := PackedFloat32Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var bpv := 0
	var custom: Array = []          # [슬롯, 배열, 정점당 개수] — 보간 못 함, 가까운 정점 것 복사
	var _cache := {}

	## 배열은 복사해서 쓴다 — GDScript 의 Packed 배열은 참조라 그대로 덧붙이면 원본(src)이 늘어난다
	func _init(src: Array) -> void:
		arrays = src.duplicate(false)
		pos = (src[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
		var n := pos.size()
		if src[Mesh.ARRAY_NORMAL] != null:
			nrm = (src[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate()
		if src[Mesh.ARRAY_TANGENT] != null:
			tan = (src[Mesh.ARRAY_TANGENT] as PackedFloat32Array).duplicate()
		if src[Mesh.ARRAY_COLOR] != null:
			col = (src[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate()
		if src[Mesh.ARRAY_TEX_UV] != null:
			uv = (src[Mesh.ARRAY_TEX_UV] as PackedVector2Array).duplicate()
		if src[Mesh.ARRAY_TEX_UV2] != null:
			uv2 = (src[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).duplicate()
		if src[Mesh.ARRAY_BONES] != null and src[Mesh.ARRAY_WEIGHTS] != null:
			bones = (src[Mesh.ARRAY_BONES] as PackedInt32Array).duplicate()
			weights = (src[Mesh.ARRAY_WEIGHTS] as PackedFloat32Array).duplicate()
			bpv = int(bones.size() / float(maxi(n, 1)))
		for slot in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			if src[slot] != null and n > 0:
				var a = src[slot].duplicate()
				custom.append([slot, a, int(a.size() / n)])

	## a → b 모서리의 t 지점에 새 정점(같은 모서리 · 같은 자리는 하나로)
	func lerp_vertex(a: int, b: int, t: float) -> int:
		var lo := a
		var hi := b
		var tt := t
		if a > b:
			lo = b
			hi = a
			tt = 1.0 - t
		var key := Vector3i(lo, hi, roundi(tt * 1000000.0))
		if _cache.has(key):
			return int(_cache[key])
		var i := pos.size()
		pos.append(pos[lo].lerp(pos[hi], tt))
		if nrm.size() > 0:
			var nv := nrm[lo].lerp(nrm[hi], tt)
			nrm.append(nv.normalized() if nv.length_squared() > 1e-12 else nrm[lo])
		if tan.size() > 0:
			var ta := Vector3(tan[lo * 4], tan[lo * 4 + 1], tan[lo * 4 + 2])
			var tb := Vector3(tan[hi * 4], tan[hi * 4 + 1], tan[hi * 4 + 2])
			var tv := ta.lerp(tb, tt)
			tv = tv.normalized() if tv.length_squared() > 1e-12 else ta
			tan.append(tv.x)
			tan.append(tv.y)
			tan.append(tv.z)
			tan.append(tan[lo * 4 + 3])
		if col.size() > 0:
			col.append(col[lo].lerp(col[hi], tt))
		if uv.size() > 0:
			uv.append(uv[lo].lerp(uv[hi], tt))
		if uv2.size() > 0:
			uv2.append(uv2[lo].lerp(uv2[hi], tt))
		if bpv > 0:
			_append_weights(lo, hi, tt)
		var near := lo if tt < 0.5 else hi
		for c in custom:
			var arr = c[1]
			var per: int = c[2]
			for k in per:
				arr.append(arr[near * per + k])
			c[1] = arr
		_cache[key] = i
		return i

	func _append_weights(lo: int, hi: int, tt: float) -> void:
		var acc := {}
		for k in bpv:
			var wa := weights[lo * bpv + k] * (1.0 - tt)
			if wa > 0.0:
				var ba := bones[lo * bpv + k]
				acc[ba] = float(acc.get(ba, 0.0)) + wa
			var wb := weights[hi * bpv + k] * tt
			if wb > 0.0:
				var bb := bones[hi * bpv + k]
				acc[bb] = float(acc.get(bb, 0.0)) + wb
		if acc.is_empty():
			var src := lo if tt < 0.5 else hi
			for k in bpv:
				bones.append(bones[src * bpv + k])
				weights.append(weights[src * bpv + k])
			return
		var ks := acc.keys()
		ks.sort_custom(func(x, y): return float(acc[x]) > float(acc[y]))
		var total := 0.0
		for k in mini(bpv, ks.size()):
			total += float(acc[ks[k]])
		for k in bpv:
			if k < ks.size() and total > 0.0:
				bones.append(int(ks[k]))
				weights.append(float(acc[ks[k]]) / total)
			else:
				bones.append(0)
				weights.append(0.0)

	func finish() -> Array:
		var out := arrays.duplicate(false)
		out[Mesh.ARRAY_VERTEX] = pos
		if nrm.size() > 0:
			out[Mesh.ARRAY_NORMAL] = nrm
		if tan.size() > 0:
			out[Mesh.ARRAY_TANGENT] = tan
		if col.size() > 0:
			out[Mesh.ARRAY_COLOR] = col
		if uv.size() > 0:
			out[Mesh.ARRAY_TEX_UV] = uv
		if uv2.size() > 0:
			out[Mesh.ARRAY_TEX_UV2] = uv2
		if bpv > 0:
			out[Mesh.ARRAY_BONES] = bones
			out[Mesh.ARRAY_WEIGHTS] = weights
		for c in custom:
			out[int(c[0])] = c[1]
		return out
