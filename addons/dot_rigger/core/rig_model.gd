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
func project_local(skel: Skeleton3D, cam: Camera3D) -> Dictionary:
	var pr := project(skel, cam)
	var world_rot := {}
	var world_pos := {}
	var out := {}
	for pname in order:
		if not pr.has(pname):
			continue
		var p: Part = parts[pname]
		var d: Dictionary = pr[pname]
		var wr: float = float(d["angle"]) - p.rest_angle
		var wp: Vector2 = d["head2d"]
		world_rot[pname] = wr
		world_pos[pname] = wp
		var lp := wp
		var lr := wr
		if p.parent != "" and world_pos.has(p.parent):
			var qx := Transform2D(float(world_rot[p.parent]), world_pos[p.parent])
			lp = qx.affine_inverse() * wp
			lr = wr - float(world_rot[p.parent])
		out[pname] = {
			"p": lp,
			"r": lr,
			"s": float(d["len2d"]) / p.rest_len2d,
			"d": float(d["depth"]),
		}

	# 깊이 -> z 순번. 카메라 공간에서 앞쪽일수록 더 작은 음수이므로
	# 내림차순 = 먼 것부터 = 뒤에 그릴 것부터.
	var ranked := out.keys()
	ranked.sort_custom(func(a, b): return float(out[a]["d"]) > float(out[b]["d"]))
	for k in ranked.size():
		out[ranked[k]]["z"] = k
	return out


func capture_rest(skel: Skeleton3D, cam: Camera3D) -> void:
	var pr := project(skel, cam)
	for pname in pr.keys():
		var p: Part = parts[pname]
		var d: Dictionary = pr[pname]
		p.rest_head2d = d["head2d"]
		p.rest_angle = d["angle"]
		p.rest_len2d = maxf(float(d["len2d"]), 1e-4)
		p.rest_depth = d["depth"]
