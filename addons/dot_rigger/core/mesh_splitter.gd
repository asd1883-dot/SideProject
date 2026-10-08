@tool
extends RefCounted
class_name DRMeshSplitter

## 스킨드 메쉬 한 덩어리를 본 웨이트 기준으로 파트별 ArrayMesh 로 분해한다.
##
## 핵심: 정점마다 웨이트가 가장 큰 본(argmax)을 찾아 파트를 정하고,
## 삼각형은 "정점 중 하나라도 파트 P에 속하면 P에 포함" 규칙으로 배정한다.
## 이러면 경계 삼각형이 양쪽 파트에 모두 들어가므로 구멍이 없고,
## 관절에서 자연스러운 겹침(bleed)이 공짜로 생긴다. bleed_rings 로 더 넓힐 수 있다.


class SplitResult:
	var part_names: PackedStringArray = PackedStringArray()
	var meshes: Dictionary = {}          # part -> ArrayMesh
	var bone_part: Dictionary = {}       # skeleton bone idx(int) -> part(String)
	var part_bones: Dictionary = {}      # part -> PackedInt32Array (skeleton bone idx)
	var unmapped_bones: PackedStringArray = PackedStringArray()
	var tri_counts: Dictionary = {}      # part -> int
	## 정점을 실제로 하나라도 지배하는 본들. (bone idx -> true)
	## UE/Mixamo 의 'root' 처럼 살이 안 붙은 기준점 본을 걸러내는 데 쓴다.
	var weighted_bones: Dictionary = {}
	## 관절(부모 조각 · 자식 조각): [{parent, child, pivot(바인드 좌표 = 2D 에서 도는 점), radius(관절 둘레, m)}]
	## radius = 두 조각이 맞닿은 정점(경계)이 관절점에서 떨어진 거리의 BALL_PCT 분위 — 관절 받침 원의 상한(DRBaker.tuck_pairs)
	var joints: Array = []


const BALL_PCT := 0.8


## skin 바인드 인덱스 -> 스켈레톤 본 인덱스
static func _bind_map(mi: MeshInstance3D, skel: Skeleton3D) -> PackedInt32Array:
	var out := PackedInt32Array()
	var skin := mi.skin
	if skin == null:
		for i in skel.get_bone_count():
			out.append(i)
		return out
	for i in skin.get_bind_count():
		var b := skin.get_bind_bone(i)
		if b < 0:
			var nm := skin.get_bind_name(i)
			b = skel.find_bone(String(nm))
		out.append(b)
	return out


## 다리 조각 경계 규칙(10-08) — 다리 사슬(허벅지 · 종아리 · 발) 정점의 조각을 웨이트가 아니라 고관절 · 무릎 · 발목 평면(뼈 방향에 수직)으로 정한다.
## 웨이트(3D 변형)는 그대로. 예전에는 붙이기(bind)가 다리 웨이트를 1 로 덮어 조각을 맞췄는데, 그러면 사타구니 면이 레스트 자세에서
## 26 배까지 늘어났다(02 U20) → 붙이기는 웨이트를 부드럽게 두고, 조각 경계만 여기서 평면으로. 안 그러면 옷자락이 한쪽 허벅지에 붙는 등
## 경계가 들쭉날쭉해진다(M36 상의 자락 오른쪽 반이 오른 허벅지 조각 — 10-08 사용자 "복장 굽기는 왜 이래").
## 돌려주는 값: [{family: [Thigh, Calf, Foot], planes: [[관절 위치, 방향] × 3], parent: 골반 조각}] (좌 · 우)
static func leg_rules(mi: MeshInstance3D, skel: Skeleton3D, part_bones: Dictionary, bone_part: Dictionary) -> Array:
	var out: Array = []
	var pos := DRMeshCutter.bone_bind_positions(mi, skel)
	for s in ["L", "R"]:
		var fam := [s + "_Thigh", s + "_Calf", s + "_Foot"]
		var heads: Array = []
		for pn in fam:
			var r := _root_bone(part_bones.get(pn, PackedInt32Array()), skel)
			if r < 0 or not pos.has(r):
				heads.clear()
				break
			heads.append(pos[r])
		if heads.size() != 3:
			continue
		var parent := ""
		var q := skel.get_bone_parent(_root_bone(part_bones[fam[0]], skel))
		while q >= 0 and parent == "":
			parent = String(bone_part.get(q, ""))
			q = skel.get_bone_parent(q)
		if parent == "" or fam.has(parent):
			continue
		var planes: Array = []
		for i in 3:
			var d: Vector3 = ((heads[i + 1] as Vector3) - (heads[i] as Vector3)) if i < 2 else ((heads[2] as Vector3) - (heads[1] as Vector3))
			if d.length() < 1e-4:
				planes.clear()
				break
			planes.append([heads[i], d.normalized()])
		if planes.size() == 3:
			out.append({"family": fam, "planes": planes, "parent": parent})
	return out


## 그 파트의 맨 위 뼈(부모가 그 파트 밖인 뼈 중 가장 얕은 것)
static func _root_bone(bones: PackedInt32Array, skel: Skeleton3D) -> int:
	var root := -1
	var best := 1 << 20
	for b in bones:
		if bones.has(skel.get_bone_parent(b)):
			continue
		var depth := 0
		var p := b
		while p >= 0:
			depth += 1
			p = skel.get_bone_parent(p)
		if depth < best:
			best = depth
			root = b
	return root


## 다리 사슬 정점(웨이트로 정한 part)을 평면으로 다시: 고관절 평면보다 위 = 골반, 무릎 · 발목 평면 사이 = 그 마디. 사슬이 아니면 그대로
static func leg_part(part: String, p: Vector3, rules: Array) -> String:
	for r in rules:
		var fam: Array = r["family"]
		if not fam.has(part):
			continue
		var planes: Array = r["planes"]
		var seg := -1
		for i in planes.size():
			if (p - (planes[i][0] as Vector3)).dot(planes[i][1] as Vector3) >= 0.0:
				seg = i
		return String(r["parent"]) if seg < 0 else String(fam[seg])
	return part


## overrides = 부위 칠하기(DRPartOverrides). 칠한 정점은 웨이트 대신 칠한 파트로 간다(없는 파트 이름은 무시).
## 그다음 overrides.cuts(자르기)로 삼각형을 평면에서 쪼개 곧은 경계를 낸다(DRMeshCutter — 새 정점이 서피스에 덧붙는다).
static func split(mi: MeshInstance3D, skel: Skeleton3D, profile: DRPartProfile,
		bleed_rings: int = 1, overrides: DRPartOverrides = null) -> SplitResult:
	var res := SplitResult.new()
	var src := mi.mesh as ArrayMesh
	if src == null:
		push_error("[DotRigger] MeshInstance3D 에 ArrayMesh 가 없습니다: %s" % mi.name)
		return res

	# 1) 본 -> 파트
	var seen := {}
	for bi in skel.get_bone_count():
		var bn := skel.get_bone_name(bi)
		var part := profile.part_for_bone(bn)
		if part == "":
			res.unmapped_bones.append(bn)
			continue
		res.bone_part[bi] = part
		if not res.part_bones.has(part):
			res.part_bones[part] = PackedInt32Array()
		var arr: PackedInt32Array = res.part_bones[part]
		arr.append(bi)
		res.part_bones[part] = arr
		seen[part] = true

	var binds := _bind_map(mi, skel)
	var rules := leg_rules(mi, skel, res.part_bones, res.bone_part)

	# 2) 서피스마다 파트별 삼각형 — 다 모은 뒤 관절 공 · 파트 메시를 만든다(공 반지름은 서피스를 통틀어 잰다)
	var surfs: Array = []         # [{arrays, part_tris, material, format}]

	for si in src.get_surface_count():
		if src.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if verts.is_empty() or idx.is_empty() or bones.is_empty():
			continue

		var vcount := verts.size()
		var bpv := int(bones.size() / float(vcount))   # 4 또는 8
		if bpv < 1:
			continue

		# 2-1) 정점 -> 파트 (웨이트 argmax)
		var vpart := PackedStringArray()
		vpart.resize(vcount)
		for v in vcount:
			var best_w := -1.0
			var best_b := -1
			for k in bpv:
				var w := weights[v * bpv + k]
				if w > best_w:
					best_w = w
					best_b = bones[v * bpv + k]
			var skel_b := -1
			if best_b >= 0 and best_b < binds.size():
				skel_b = binds[best_b]
			if skel_b >= 0:
				res.weighted_bones[skel_b] = true
			vpart[v] = String(res.bone_part.get(skel_b, ""))
			if not rules.is_empty():
				vpart[v] = leg_part(vpart[v], verts[v], rules)    # 다리 조각은 관절 평면으로(웨이트는 그대로)
			if overrides != null and not overrides.map.is_empty():
				var op := overrides.part_at(verts[v])
				if op != "" and seen.has(op):
					vpart[v] = op

		var tcount := int(idx.size() / 3)

		# 2-2) 파트별 삼각형 배정
		var part_tris := {}       # part -> PackedInt32Array
		for part in seen.keys():
			var member := {}          # vertex idx -> true
			for v in vcount:
				if vpart[v] == part:
					member[v] = true
			if member.is_empty():
				continue
			# bleed: 이 파트를 건드리는 삼각형의 나머지 정점까지 흡수 (링 확장)
			for _r in bleed_rings:
				var add := {}
				for t in tcount:
					var a := idx[t * 3]; var b := idx[t * 3 + 1]; var c := idx[t * 3 + 2]
					if member.has(a) or member.has(b) or member.has(c):
						add[a] = true; add[b] = true; add[c] = true
				member.merge(add)

			var out_idx := PackedInt32Array()
			for t in tcount:
				var a2 := idx[t * 3]; var b2 := idx[t * 3 + 1]; var c2 := idx[t * 3 + 2]
				if member.has(a2) or member.has(b2) or member.has(c2):
					out_idx.append(a2); out_idx.append(b2); out_idx.append(c2)
			if not out_idx.is_empty():
				part_tris[part] = out_idx

		# 2-3) 자르기 — 곧은 경계(삼각형을 평면에서 쪼갬, 새 정점은 서피스 끝에 덧붙음)
		var surf_arrays := arrays
		if overrides != null and not overrides.cuts.is_empty():
			var pool := DRMeshCutter.VertexPool.new(arrays)
			DRMeshCutter.apply_cuts(part_tris, overrides.cuts, pool, seen, DRMeshCutter.MARGIN)
			surf_arrays = pool.finish()
		surfs.append({"arrays": surf_arrays, "part_tris": part_tris,
			"material": src.surface_get_material(si), "format": src.surface_get_format(si)})

	# 3) 파트별 ArrayMesh 생성
	# 정점 배열은 원본을 그대로 재사용하고 인덱스만 교체한다.
	# (미사용 정점은 그리지 않으므로 결과는 동일, 리맵 비용 절약)
	var per_part_surfaces := {}   # part -> Array[ {arrays, material, format} ]
	for s in surfs:
		var part_tris: Dictionary = s["part_tris"]
		for part in part_tris.keys():
			var out_idx: PackedInt32Array = part_tris[part]
			if out_idx.is_empty():
				continue
			if not per_part_surfaces.has(part):
				per_part_surfaces[part] = []
			per_part_surfaces[part].append(_surface_with(s, out_idx))
			res.tri_counts[part] = int(res.tri_counts.get(part, 0)) + int(out_idx.size() / 3)
	for part in per_part_surfaces.keys():
		res.meshes[part] = _mesh_of("part_%s" % part, per_part_surfaces[part])
		res.part_names.append(part)

	# 4) 관절(관절 받침의 둘레 — 굽는 쪽이 그리기 순서로 아래 조각을 정해 위 조각의 관절 둘레를 품게 한다)
	res.joints = part_joints(mi, skel, res.part_bones, res.bone_part)
	for j in res.joints:
		var jd: Dictionary = j
		jd["radius"] = _joint_radius(surfs, String(jd["parent"]), String(jd["child"]), jd["pivot"])

	return res


static func _surface_with(s: Dictionary, idx: PackedInt32Array) -> Dictionary:
	var arr: Array = (s["arrays"] as Array).duplicate(false)
	arr[Mesh.ARRAY_INDEX] = idx
	return {"arrays": arr, "material": s["material"], "format": s["format"]}


static func _mesh_of(rname: String, surfaces: Array) -> ArrayMesh:
	var am := ArrayMesh.new()
	am.resource_name = rname
	for s in surfaces:
		var flags := int(s["format"]) & int(Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s["arrays"], [], {}, flags)
		if s["material"] != null:
			am.surface_set_material(am.get_surface_count() - 1, s["material"])
	return am


## 조각 사이 관절: 자식 조각의 맨 위 뼈 → 부모 쪽으로 올라가 처음 만나는 다른 조각이 부모. pivot = 그 뼈의 바인드 위치(2D 에서 도는 점)
static func part_joints(mi: MeshInstance3D, skel: Skeleton3D, part_bones: Dictionary, bone_part: Dictionary) -> Array:
	var pos := DRMeshCutter.bone_bind_positions(mi, skel)
	var out: Array = []
	for child in part_bones.keys():
		var r := _root_bone(part_bones[child], skel)
		if r < 0 or not pos.has(r):
			continue
		var parent := ""
		var q := skel.get_bone_parent(r)
		while q >= 0 and parent == "":
			parent = String(bone_part.get(q, ""))
			if parent == String(child):
				parent = ""
			q = skel.get_bone_parent(q)
		if parent == "":
			continue
		out.append({"parent": parent, "child": String(child), "pivot": pos[r], "radius": 0.0})
	return out


## 관절 둘레: 두 조각에 다 쓰인 정점(경계 띠)이 관절점에서 떨어진 거리의 BALL_PCT 분위(m). 맞닿지 않으면 0
static func _joint_radius(surfs: Array, a: String, b: String, pivot: Vector3) -> float:
	var ds := PackedFloat32Array()
	for s in surfs:
		var pt: Dictionary = s["part_tris"]
		if not pt.has(a) or not pt.has(b):
			continue
		var verts: PackedVector3Array = (s["arrays"] as Array)[Mesh.ARRAY_VERTEX]
		var in_a := PackedByteArray()
		in_a.resize(verts.size())
		for i in (pt[a] as PackedInt32Array):
			in_a[i] = 1
		var seen := PackedByteArray()
		seen.resize(verts.size())
		for i in (pt[b] as PackedInt32Array):
			if in_a[i] == 1 and seen[i] == 0:
				seen[i] = 1
				ds.append(verts[i].distance_to(pivot))
	if ds.is_empty():
		return 0.0
	ds.sort()
	return ds[clampi(int(float(ds.size() - 1) * BALL_PCT), 0, ds.size() - 1)]


## 관절 받침 짝: 그리기 순서(뒤 → 앞 파트 목록)로 관절마다 {아래 조각: [위 조각 …]}.
## frames_z = 프레임마다 {파트: z}(자동 순서로 구운 세트) — 주면 모든 프레임에서 아래 · 위가 그대로인 관절만(뒤집히는 관절에 공을 넣으면 위에 덮여 보인다).
## slots = 파트 → 슬롯(복장) — 주면 같은 슬롯끼리만(머리 · 손처럼 기본 몸 그대로 쓰는 조각의 공은 옷 그림에 넣지 않는다).
static func tuck_pairs(joints: Array, order: PackedStringArray, frames_z: Array = [], slots: Dictionary = {}) -> Dictionary:
	var out := {}
	for j in joints:
		var p := String((j as Dictionary)["parent"])
		var c := String((j as Dictionary)["child"])
		var ip := order.find(p)
		var ic := order.find(c)
		if ip < 0 or ic < 0:
			continue
		if not slots.is_empty():
			var sp := String(slots.get(p, ""))
			if sp == "" or sp != String(slots.get(c, "")):
				continue
		var lo := p if ip < ic else c
		var up := c if ip < ic else p
		var stable := true
		for fz in frames_z:
			var zd: Dictionary = fz
			if zd.has(lo) and zd.has(up) and int(zd[lo]) >= int(zd[up]):
				stable = false
				break
		if not stable:
			continue
		if not out.has(lo):
			out[lo] = PackedStringArray()
		var arr: PackedStringArray = out[lo]
		arr.append(up)
		out[lo] = arr
	return out
