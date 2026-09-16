@tool
extends RefCounted
class_name DRRigModel

## 파트 계층 구조와 3D->2D 투영 수학.
##
## 핵심 아이디어: 파트마다 "루트 본"과 그 본의 로컬 공간에 고정된 "tail 점"을 잡아두면,
## 어떤 애니메이션 프레임에서든 head/tail 두 점을 카메라로 투영하는 것만으로
## 2D 각도 / 길이(단축률) / 깊이(z-order)가 전부 나온다. 리그 규격에 의존하지 않는다.


class Part:
	var name: String
	var parent: String = ""          # 부모 파트 이름 ("" = 루트)
	var root_bone: int = -1          # 스켈레톤 본 인덱스
	var bones: PackedInt32Array = PackedInt32Array()
	var tail_local: Vector3 = Vector3.ZERO
	var rest_head2d: Vector2 = Vector2.ZERO
	var rest_angle: float = 0.0
	var rest_len2d: float = 1.0
	var rest_depth: float = 0.0


var parts: Dictionary = {}                  # name -> Part
var order: PackedStringArray = PackedStringArray()   # 계층 순(부모 먼저)
var root_parts: PackedStringArray = PackedStringArray()
## 파트 -> 레이어. 없는 파트는 자기 이름이 곧 레이어(아래 '레이어' 절 참고).
var layer_of: Dictionary = {}
## 늘이기(단축 보정)를 하지 않는 파트 집합 { part: true }. 프로필 규칙의 "stretch": false 에서 온다(예: 발).
## project_local() 의 s 가 항상 1 이라 2D 프리뷰와 베이크가 같이 따른다.
var no_stretch: Dictionary = {}
## 파트별 늘이기 제한 { part: float } — s 를 1/limit ~ limit 로 묶는다(예: 발 1.15). 없는 파트는 전체 제한(익스포터·프리뷰의 1.6).
var stretch_limit: Dictionary = {}
## 파트별 각도 안정화 { part: 단축률 문턱 }. 뼈가 카메라를 향해 화면 길이가 문턱 아래로 짧아지면
## 2D 각도는 잡음이라, 부모 기준 회전을 단축률에 비례해 레스트(0) 쪽으로 누른다. 손·발용.
var angle_fade: Dictionary = {}
## 동작 평면화용 — 포즈 시점(보통 측면)에서 잰 레스트 각도/머리 위치 { part -> float / Vector2 }.
## capture_rest(…, pose_cam) 이 채우고 project_local(…, pose_cam) 이 쓴다. 비어 있으면 평면화 안 함.
var rest_angle_pose: Dictionary = {}
var rest_head_pose: Dictionary = {}


## weighted: 정점을 실제로 지배하는 본 집합(bone idx -> true). 비어 있으면 무시한다.
static func build(skel: Skeleton3D, bone_part: Dictionary, part_bones: Dictionary,
		weighted: Dictionary = {}) -> DRRigModel:
	var m := DRRigModel.new()

	for pname in part_bones.keys():
		var p := Part.new()
		p.name = String(pname)
		p.bones = part_bones[pname]

		# 루트 본 후보는 "살이 붙은 본"으로 제한한다.
		# UE/Mixamo 리그 맨 위의 'root' 는 정점 웨이트도 없고 제자리 애니메이션에서
		# 움직이지도 않는 바닥 기준점이라, 이걸 파트 피벗으로 잡으면
		# 피벗이 발바닥에 찍히고 그 파트(와 자식들)가 통째로 고정돼 버린다.
		var pool := PackedInt32Array()
		for bi in p.bones:
			if weighted.is_empty() or weighted.has(bi):
				pool.append(bi)
		if pool.is_empty():
			pool = p.bones

		# 그중 부모가 같은 파트의 후보가 아닌 본(= 이 파트에서 가장 위) 을 고른다
		var best := -1
		var best_depth := 1 << 30
		for bi in pool:
			var par := skel.get_bone_parent(bi)
			if par >= 0 and String(bone_part.get(par, "")) == p.name \
					and pool.has(par):
				continue
			var d := 0
			var w := bi
			while skel.get_bone_parent(w) >= 0:
				w = skel.get_bone_parent(w)
				d += 1
			if d < best_depth:
				best_depth = d
				best = bi
		p.root_bone = best if best >= 0 else (pool[0] if pool.size() > 0 else -1)
		m.parts[p.name] = p

	# 부모 파트 = 루트 본의 조상 중 처음 만나는 다른 파트
	for pname in m.parts.keys():
		var p: Part = m.parts[pname]
		var w := skel.get_bone_parent(p.root_bone)
		while w >= 0:
			var q := String(bone_part.get(w, ""))
			if q != "" and q != p.name:
				p.parent = q
				break
			w = skel.get_bone_parent(w)
		if p.parent == "":
			m.root_parts.append(p.name)

	m._compute_tails(skel, bone_part)
	m._compute_order()
	return m


func _compute_tails(skel: Skeleton3D, bone_part: Dictionary) -> void:
	for pname in parts.keys():
		var p: Part = parts[pname]
		var mine := {}
		for b in p.bones:
			mine[b] = true
		# 이 파트 안에서 더 내려갈 곳이 없는 본들
		var ends: PackedInt32Array = PackedInt32Array()
		for b in p.bones:
			var has_inner := false
			for c in skel.get_bone_children(b):
				if mine.has(c):
					has_inner = true
					break
			if not has_inner:
				ends.append(b)
		if ends.is_empty():
			ends = p.bones

		# 1순위: 말단 본의 자식 중 파트 밖으로 나가는 본들의 평균 위치
		var acc := Vector3.ZERO
		var n := 0
		for b in ends:
			for c in skel.get_bone_children(b):
				if not mine.has(c):
					acc += skel.get_bone_global_rest(c).origin
					n += 1
		# 2순위: 말단 본 자체의 평균 위치
		if n == 0 and not (ends.size() == 1 and ends[0] == p.root_bone):
			for b in ends:
				acc += skel.get_bone_global_rest(b).origin
				n += 1

		var root_rest := skel.get_bone_global_rest(p.root_bone)
		var tail_world: Vector3
		if n > 0:
			tail_world = acc / float(n)
		else:
			# 3순위: 부모에서 이 본으로 오는 방향으로 연장
			var par := skel.get_bone_parent(p.root_bone)
			var dir := Vector3.UP
			if par >= 0:
				var d := root_rest.origin - skel.get_bone_global_rest(par).origin
				if d.length() > 1e-6:
					dir = d.normalized()
			tail_world = root_rest.origin + dir * 0.1

		p.tail_local = root_rest.affine_inverse() * tail_world
		if p.tail_local.length() < 1e-5:
			p.tail_local = Vector3(0, 0.1, 0)


func _compute_order() -> void:
	order = PackedStringArray()
	var pending := parts.keys()
	pending.sort()
	var placed := {}
	var guard := 0
	while pending.size() > 0 and guard < 1000:
		guard += 1
		var next := []
		for pname in pending:
			var p: Part = parts[pname]
			if p.parent == "" or placed.has(p.parent):
				order.append(p.name)
				placed[p.name] = true
			else:
				next.append(pname)
		if next.size() == pending.size():
			for pname in next:      # 사이클 방지
				order.append(String(pname))
			break
		pending = next


## 현재 스켈레톤 포즈를 카메라로 투영. { part -> {head2d, angle, len2d, depth, tail2d} }
func project(skel: Skeleton3D, cam: Camera3D) -> Dictionary:
	var out := {}
	var sk_xform := skel.global_transform
	var cam_inv := cam.global_transform.affine_inverse()
	for pname in parts.keys():
		var p: Part = parts[pname]
		if p.root_bone < 0:
			continue
		var world := sk_xform * skel.get_bone_global_pose(p.root_bone)
		var head3d := world.origin
		var tail3d := world * p.tail_local
		var h2 := cam.unproject_position(head3d)
		var t2 := cam.unproject_position(tail3d)
		var v := t2 - h2
		var dh := (cam_inv * head3d).z
		var dt := (cam_inv * tail3d).z
		out[pname] = {
			"head2d": h2,
			"tail2d": t2,
			"angle": v.angle(),
			"len2d": v.length(),
			# 그리기 순서용 깊이. 루트 본 한 점만 재면 긴 파트(전완 등)가
			# 실제로 차지하는 영역을 대표하지 못해 손/전완 순서가 뒤집힌다.
			# head~tail 평균이 파트 전체를 훨씬 잘 대표한다.
			"depth": (dh + dt) * 0.5,
			"depth_head": dh,
		}
	return out


## project() 결과를 계층 기준 로컬 트랜스폼으로 바꾸고 z 순위까지 매긴다.
## 베이크(애니메이션 커브 생성)와 2D 프리뷰가 같은 값을 써야 하므로 여기 둔다.
## { part -> { p:Vector2(로컬 위치), r:float(로컬 회전), s:float(축방향 배율),
##             d:float(깊이), z:int(뒤에서부터의 순번) } }
## pose_cam 을 주면 **동작 평면화**: 각도는 pose_cam(보통 측면) 시점에서 잰 "레스트 대비 회전"만 쓰고
## 위치는 레스트 오프셋(강체 2D 리그), 늘이기는 1. 깊이(그리기 순서)만 렌더 카메라 값.
## 3D 를 그대로 투영하면 팔이 카메라 쪽으로 오갈 때 짧아졌다 길어지며 종이가 접히듯 보이는데(페이퍼맨),
## 2D 게임의 컷아웃은 팔다리가 화면 안에서만 돈다 — 그 느낌을 내려면 각도를 측면에서 재야 한다.
## 화면 길이 ÷ 실제 뼈 길이(픽셀). 1 = 화면과 나란, 0 = 카메라를 향함. 직교 카메라라 위치와 무관.
func _fore_of(pname: String, len2d: float, cam: Camera3D) -> float:
	var p: Part = parts[pname]
	var vp := cam.get_viewport()
	if vp == null:
		return 1.0
	var ppu := float(vp.get_visible_rect().size.y) / maxf(cam.size, 1e-6)
	return clampf(len2d / maxf(p.tail_local.length() * ppu, 1e-4), 0.0, 1.0)


## angle_fade 파트: 단축률이 문턱 아래면 회전을 레스트(0) 쪽으로 누른다. 문턱 이상이면 그대로.
func _fade_rot(pname: String, lr: float, fore: float) -> float:
	if not angle_fade.has(pname):
		return lr
	var thr := float(angle_fade[pname])
	if thr <= 0.0 or fore >= thr:
		return lr
	return lerp_angle(0.0, lr, fore / thr)


func project_local(skel: Skeleton3D, cam: Camera3D, pose_cam: Camera3D = null) -> Dictionary:
	var pr := project(skel, cam)
	var out := {}
	if pose_cam != null and not rest_angle_pose.is_empty():
		out = _project_local_planar(skel, pr, pose_cam)
	else:
		var world_rot := {}
		var world_pos := {}
		for pname in order:
			if not pr.has(pname):
				continue
			var p: Part = parts[pname]
			var d: Dictionary = pr[pname]
			var wr: float = float(d["angle"]) - p.rest_angle
			var wp: Vector2 = d["head2d"]
			var lp := wp
			var lr := wr
			if p.parent != "" and world_pos.has(p.parent):
				var qx := Transform2D(float(world_rot[p.parent]), world_pos[p.parent])
				lp = qx.affine_inverse() * wp
				lr = wr - float(world_rot[p.parent])
			# 손·발이 카메라를 향해 짧아지면 각도가 잡음 → 레스트 쪽으로 누른다. 자식(발가락 분리 모드)도 이 값을 기준으로 삼는다
			var faded := _fade_rot(pname, lr, _fore_of(pname, float(d["len2d"]), cam))
			if faded != lr:
				wr += faded - lr
				lr = faded
			world_rot[pname] = wr
			world_pos[pname] = wp
			var s := 1.0 if no_stretch.has(pname) else float(d["len2d"]) / p.rest_len2d
			if stretch_limit.has(pname):
				var lim := float(stretch_limit[pname])
				s = clampf(s, 1.0 / lim, lim)
			out[pname] = {
				"p": lp,
				"r": lr,
				"s": s,
				"d": float(d["depth"]),
			}

	# 깊이 -> z 순번. 레이어 단위로 정렬한 뒤 파트로 펼친다.
	# (발가락은 발과 한 레이어라 항상 발 바로 위의 z 를 받는다)
	var depth_of := {}
	for pn in out.keys():
		depth_of[pn] = float(out[pn]["d"])
	var k := 0
	for pn in expand_layers(auto_layer_order(depth_of)):
		if out.has(pn):
			out[pn]["z"] = k
			k += 1
	return out


# ---------------------------------------------------------------- 레이어
# 파트   = 애니메이션 단위. 본에 붙어 따로 움직인다.
# 레이어 = 그리기 순서 목록의 한 줄. 깊이를 함께 다룬다.
# 대부분은 파트 하나가 곧 레이어지만, 발가락처럼 "움직임은 따로, 순서는 발과 한 몸"인
# 파트는 부모 파트의 레이어에 묶는다. 한 레이어 안은 계층 순(부모가 뒤)이라
# 발가락은 항상 발 바로 위에 그려진다.

func layer(part: String) -> String:
	return String(layer_of.get(part, part))


## 레이어 이름들, 계층 순(부모 먼저).
func layer_names() -> PackedStringArray:
	var out := PackedStringArray()
	var seen := {}
	for p in order:
		var l := layer(p)
		if not seen.has(l):
			seen[l] = true
			out.append(l)
	return out


## 한 레이어에 속한 파트들, 계층 순.
func layer_parts(layer_name: String) -> PackedStringArray:
	var out := PackedStringArray()
	for p in order:
		if layer(p) == layer_name:
			out.append(p)
	return out


## 레이어 순서(뒤 -> 앞)를 파트 순서로 펼친다. 목록에 없는 레이어는 끝에 계층 순으로 붙인다.
func expand_layers(layer_order: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var done := {}
	for l in layer_order:
		if done.has(l):
			continue
		done[l] = true
		out.append_array(layer_parts(l))
	for l in layer_names():
		if not done.has(l):
			done[l] = true
			out.append_array(layer_parts(l))
	return out


## 이름 목록을 레이어 순서로 정리한다. 레이어 이름이든 옛 프리셋처럼 파트 이름(L_Toe)이
## 섞여 있든 받아서 중복 없이 레이어로 바꾸고, 빠진 레이어는 끝에 계층 순으로 붙인다.
func normalize_layer_order(names: PackedStringArray) -> PackedStringArray:
	var known := {}
	for l in layer_names():
		known[l] = true
	var out := PackedStringArray()
	var seen := {}
	for n in names:
		var l := layer(String(n))
		if known.has(l) and not seen.has(l):
			seen[l] = true
			out.append(l)
	for l in layer_names():
		if not seen.has(l):
			out.append(l)
	return out


## 깊이(part -> 카메라 공간 z)로 레이어를 뒤 -> 앞 정렬한다.
## 레이어 깊이 = 레이어와 이름이 같은 파트(발 레이어면 발)의 깊이. 없으면 레이어 첫 파트.
func auto_layer_order(depth_of: Dictionary) -> PackedStringArray:
	var ls: Array = []
	var ld := {}
	for l in layer_names():
		var key := l
		if not depth_of.has(key):
			var lp := layer_parts(l)
			if lp.size() > 0:
				key = lp[0]
		ls.append(l)
		ld[l] = float(depth_of.get(key, 0.0))
	# 카메라 공간 z 는 앞쪽일수록 더 작은 음수 -> 내림차순 = 먼 것부터
	ls.sort_custom(func(a, b): return float(ld[a]) > float(ld[b]))
	return PackedStringArray(ls)


func rest_layer_order() -> PackedStringArray:
	var d := {}
	for pn in parts.keys():
		d[pn] = (parts[pn] as Part).rest_depth
	return auto_layer_order(d)


## 평면화 계산. pr = 렌더 카메라 투영(깊이용), pose_cam = 각도를 잴 시점.
## 파트의 로컬 회전 = (포즈 시점 각도 − 포즈 시점 레스트 각도) − 부모의 같은 값. 위치 = 레스트 오프셋.
## 루트 파트(힙)만 포즈 시점의 머리 위치 이동(px)을 그대로 받아 위아래 들썩임을 살린다.
func _project_local_planar(skel: Skeleton3D, pr: Dictionary, pose_cam: Camera3D) -> Dictionary:
	var pp := project(skel, pose_cam)
	var wdelta := {}
	var out := {}
	for pname in order:
		if not pr.has(pname) or not pp.has(pname) or not rest_angle_pose.has(pname):
			continue
		var p: Part = parts[pname]
		var wd := wrapf(float(pp[pname]["angle"]) - float(rest_angle_pose[pname]), -PI, PI)
		var lr: float = wd
		var lp: Vector2
		if p.parent != "" and wdelta.has(p.parent):
			lr = wrapf(lr - float(wdelta[p.parent]), -PI, PI)
			# 포즈 시점에서 카메라를 향하는 손·발은 각도 잡음 → 레스트 쪽으로(단축률은 포즈 시점 것)
			var faded := _fade_rot(pname, lr, _fore_of(pname, float(pp[pname]["len2d"]), pose_cam))
			if faded != lr:
				wd += faded - lr
				lr = faded
			lp = p.rest_head2d - (parts[p.parent] as Part).rest_head2d
		else:
			var hp: Vector2 = pp[pname]["head2d"]
			lp = p.rest_head2d + (hp - Vector2(rest_head_pose.get(pname, hp)))
		wdelta[pname] = wd
		out[pname] = {"p": lp, "r": lr, "s": 1.0, "d": float(pr[pname]["depth"])}
	return out


## 파트별 단축률 { part -> 0~1 }. 1 = 뼈가 화면과 나란함, 0 = 카메라를 향함.
## (화면상 head~tail 길이 ÷ 실제 뼈 길이를 픽셀로 환산한 것)
## 레스트 포즈 고르기의 기준: 이 값이 낮은 파트는 그림이 짧고 얇게 찍혀서
## 그 파트가 화면과 나란해지는 동작에서 3D 와 크게 어긋난다.
func foreshortening(skel: Skeleton3D, cam: Camera3D, view_h_px: float) -> Dictionary:
	var pr := project(skel, cam)
	var ppu := view_h_px / maxf(cam.size, 1e-6)   # 픽셀 / 월드 단위 (직교 카메라)
	var out := {}
	for pname in pr.keys():
		var p: Part = parts[pname]
		var full := p.tail_local.length() * ppu
		out[pname] = clampf(float(pr[pname]["len2d"]) / maxf(full, 1e-4), 0.0, 1.0)
	return out


func capture_rest(skel: Skeleton3D, cam: Camera3D, pose_cam: Camera3D = null) -> void:
	var pr := project(skel, cam)
	for pname in pr.keys():
		var p: Part = parts[pname]
		var d: Dictionary = pr[pname]
		p.rest_head2d = d["head2d"]
		p.rest_angle = d["angle"]
		p.rest_len2d = maxf(float(d["len2d"]), 1e-4)
		p.rest_depth = d["depth"]
	rest_angle_pose.clear()
	rest_head_pose.clear()
	if pose_cam != null:
		var pp := project(skel, pose_cam)
		for pname in pp.keys():
			rest_angle_pose[pname] = float(pp[pname]["angle"])
			rest_head_pose[pname] = pp[pname]["head2d"]
