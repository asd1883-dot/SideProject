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


static func split(mi: MeshInstance3D, skel: Skeleton3D, profile: DRPartProfile,
		bleed_rings: int = 1) -> SplitResult:
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

	# 2) 파트별 서피스 수집
	var per_part_surfaces := {}   # part -> Array[ {arrays, material} ]

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

		var tcount := int(idx.size() / 3)

		# 2-2) 파트별 삼각형 배정
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
			if out_idx.is_empty():
				continue

			# 정점 배열은 원본을 그대로 재사용하고 인덱스만 교체한다.
			# (미사용 정점은 그리지 않으므로 결과는 동일, 리맵 비용 절약)
			var new_arrays := arrays.duplicate(true)
			new_arrays[Mesh.ARRAY_INDEX] = out_idx
			if not per_part_surfaces.has(part):
				per_part_surfaces[part] = []
			per_part_surfaces[part].append({
				"arrays": new_arrays,
				"material": src.surface_get_material(si),
				"format": src.surface_get_format(si),
			})
			res.tri_counts[part] = int(res.tri_counts.get(part, 0)) + int(out_idx.size() / 3)

	# 3) 파트별 ArrayMesh 생성
	for part in per_part_surfaces.keys():
		var am := ArrayMesh.new()
		am.resource_name = "part_%s" % part
		for s in per_part_surfaces[part]:
			var flags := int(s["format"]) & int(Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, s["arrays"], [], {}, flags)
			if s["material"] != null:
				am.surface_set_material(am.get_surface_count() - 1, s["material"])
		res.meshes[part] = am
		res.part_names.append(part)

	return res
