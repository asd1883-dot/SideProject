@tool
extends RefCounted
class_name DRSlotMesh

## 3D 캐릭터의 슬롯 메시 나누기(10-15) — 스킨드 통메시 하나를 상의(top) · 하의(bottom) · 기본(base: 머리 · 손) 덩어리로 자른다.
##
## 2D 컷아웃 굽기의 리소스 관리가 너무 힘들어 3D 캐릭터를 게임에 바로 쓰기로 했다(10-15). 옷 갈아입히기는 2D 와 같은 뜻 —
## 슬롯 덩어리를 기본 몸 것 ↔ 복장 것으로 바꿔 끼운다(DRCharacter3D).
##
## 경계는 2D 굽기(DRMeshSplitter)와 **같은 것**을 쓴다: 정점 → 파트(웨이트 argmax → 다리 평면 leg_rules → 부위 칠하기),
## 그다음 관절 자르기(<모델>.parts.json 의 cuts → DRMeshCutter.apply_cuts). 기본 몸과 복장의 parts.json 이 같은 평면이면
## (human_base · uniform_m36 은 10-15 기준 12 개 다 같음) 두 모델의 슬롯 경계가 같은 자리에서 맞물린다. 다른 점 둘:
##  - 겹침이 없다. 2D 조각은 움직일 때 틈이 안 보이게 경계 삼각형을 양쪽 조각에 다 넣고(bleed) 자르기도 1.2 cm 겹치지만,
##    3D 는 겹치면 같은 면이 두 번 그려져 깜빡이고(z-fighting) 옷 밖으로 살이 비친다. 같은 원본 메시의 조각끼리는
##    경계 정점이 같은 자리 · 같은 웨이트라 겹치지 않아도 틈이 안 생긴다 → 삼각형마다 파트 하나(세 정점의 다수결), 자르기는 겹침 0.
##  - 쓰는 정점만 담는다. 2D 는 원본 정점 배열을 그대로 두고 인덱스만 바꿨지만(굽기 때만 그리므로), 3D 는 병사마다
##    GPU 스키닝이 메시의 정점 **전부**를 돌린다 → 안 쓰는 정점을 빼야 세 덩어리를 합쳐도 원본 정점 수와 거의 같다.
##  - 슬롯 경계의 구멍(목 · 손목 · 허리 단면)을 어두운 뚜껑으로 막는다(_add_caps — 옷 속이 비어 소매 → 몸통 → 반대 소매로 배경이 비치던 것).
##  - 슬롯 나뉨에 영향 없는 같은 슬롯 안 자르기(팔꿈치 · 무릎 …)는 건너뛴다(needed_cuts — 슬롯 넓이 · 상자가 전부 자른 것과 같음을 10-15 확인).
## 스킨(뼈 인덱스 · 웨이트) · UV · 노멀은 그대로라 원래 Skin 을 그대로 쓴다. 에디터 전용 API 없음 — 게임 실행 중에도 돈다.

const SLOT_TOP := "top"
const SLOT_BOTTOM := "bottom"
const SLOT_BASE := "base"
## 파트 → 슬롯 기본 표. outfit.json 의 slots 와 같은 형식("" = 기본 몸 그대로 = base). DROutfit 의 TOP · BOTTOM + SHOES 묶음과 같다.
const DEFAULT_SLOTS := {
	"Torso": "top", "L_UpperArm": "top", "R_UpperArm": "top", "L_Forearm": "top", "R_Forearm": "top",
	"Hips": "bottom", "L_Thigh": "bottom", "R_Thigh": "bottom", "L_Calf": "bottom", "R_Calf": "bottom",
	"L_Foot": "bottom", "R_Foot": "bottom",
	"Head": "", "L_Hand": "", "R_Hand": "",
}
## 넓이가 이보다 작은 삼각형(두 변 외적 길이의 제곱, m⁴)은 뺀다 — 겹침 0 자르기가 평면 위 정점에서 만드는 넓이 0 조각
const DEGENERATE_EPS := 1e-20
## 슬롯 경계 뚜껑의 정점 색(셰이더가 albedo 에 곱한다) — 옷 속 그늘처럼 거의 검정. 나머지 정점은 흰색(그대로)
const CAP_COLOR := Color(0.07, 0.07, 0.07, 1.0)
## 같은 자리 정점 합치기 눈금(1/m) — 0.01 mm. 텍스처 · 노멀 이음매로 둘로 나뉜 정점을 경계 고리에서 하나로 본다
const WELD := 100000.0


class Result:
	extends RefCounted
	## 슬롯 -> ArrayMesh(그 슬롯이 쓰는 정점만, 원래 서피스 재질 그대로)
	var meshes: Dictionary = {}
	var vert_counts: Dictionary = {}      # 슬롯 -> 정점 수
	var tri_counts: Dictionary = {}       # 슬롯 -> 삼각형 수
	var part_tri_counts: Dictionary = {}  # 파트 -> 삼각형 수(자르기 뒤)
	## DRMeshSplitter.SplitResult 와 같은 뜻 — 뼈 번호 -> 파트 / 파트 -> 뼈 번호들 / 정점을 실제로 지배하는 뼈(DRRigModel.build 용)
	var bone_part: Dictionary = {}
	var part_bones: Dictionary = {}
	var weighted_bones: Dictionary = {}
	var source_verts: int = 0             # 원본 정점 수(자르기 전)
	var source_tris: int = 0              # 원본 삼각형 수
	var cut_new_verts: int = 0            # 자르기가 모서리 위에 새로 만든 정점 수
	var unassigned_tris: int = 0          # 세 정점 모두 파트가 없어 base 로 보낸 삼각형
	var degenerate_tris: int = 0          # 넓이 0 이라 뺀 삼각형
	var cuts_total: int = 0               # parts.json 의 자르기 수
	var cuts_used: int = 0                # 그중 슬롯 나뉨에 영향이 있어 실제로 쓴 수(needed_cuts)
	var cap_loops: Dictionary = {}        # 슬롯 -> 막은 경계 고리 수(뚜껑)
	var cap_tris: Dictionary = {}         # 슬롯 -> 뚜껑 삼각형 수(tri_counts 에 포함)
	var cap_fan: int = 0                  # 평면 삼각분할이 안 돼 가운데 점 부채꼴로 막은 고리 수
	var cap_open: int = 0                 # 닫히지 않은 경계 사슬(못 막음 — 원본 메시의 열린 가장자리와 이어진 것 등)
	var ms: float = 0.0                   # 나누기 시간(ms)


## 파트 → 슬롯(outfit.json 의 slots 형식). "shoes"(옛 신발)는 하의, "" · 표에 없음 = base
static func slot_of(part: String, table: Dictionary) -> String:
	var s := String(table.get(part, ""))
	if s == "shoes":
		s = SLOT_BOTTOM
	return s if s != "" else SLOT_BASE


## slot_table: 파트 → 슬롯(비면 DEFAULT_SLOTS). overrides: 부위 칠하기 · 관절 자르기(DRPartOverrides.load_for(glb 경로)), null = 웨이트대로
## prune_cuts: 슬롯 나뉨에 영향 없는 자르기를 건너뜀(needed_cuts — 결과 슬롯은 같고 정점 · 삼각형이 준다). false = 2D 처럼 전부(비교 시험용)
## caps: 슬롯 경계의 구멍(목 · 손목 · 허리 단면)을 어두운 뚜껑으로 막는다(_add_caps). false = 안 막음(비교 시험용)
static func split(mi: MeshInstance3D, skel: Skeleton3D, profile: DRPartProfile, slot_table: Dictionary = {},
		overrides: DRPartOverrides = null, prune_cuts: bool = true, caps: bool = true) -> Result:
	var t0 := Time.get_ticks_usec()
	var res := Result.new()
	var table: Dictionary = slot_table if not slot_table.is_empty() else DEFAULT_SLOTS
	var src := mi.mesh as ArrayMesh
	if src == null:
		push_error("[DRSlotMesh] MeshInstance3D 에 ArrayMesh 가 없습니다: %s" % mi.name)
		return res

	# 1) 뼈 → 파트 (DRMeshSplitter.split 과 같음)
	var seen := {}
	for bi in skel.get_bone_count():
		var part := profile.part_for_bone(skel.get_bone_name(bi))
		if part == "":
			continue
		res.bone_part[bi] = part
		var arr: PackedInt32Array = res.part_bones.get(part, PackedInt32Array())
		arr.append(bi)
		res.part_bones[part] = arr
		seen[part] = true
	var binds := DRMeshSplitter._bind_map(mi, skel)
	var rules := DRMeshSplitter.leg_rules(mi, skel, res.part_bones, res.bone_part)
	var paint := overrides != null and not overrides.map.is_empty()
	var cuts: Array = [] if overrides == null else (needed_cuts(overrides.cuts, table) if prune_cuts else overrides.cuts)
	res.cuts_total = overrides.cuts.size() if overrides != null else 0
	res.cuts_used = cuts.size()

	var per_slot := {}   # 슬롯 -> [{arrays, material, format}]
	for si in src.get_surface_count():
		if src.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		if verts.is_empty() or bones.is_empty():
			continue
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():                   # 인덱스 없는 서피스 = 정점 순서대로 삼각형
			idx = PackedInt32Array(range(verts.size()))
			arrays[Mesh.ARRAY_INDEX] = idx
		var vcount := verts.size()
		var bpv := int(bones.size() / float(vcount))   # 4 또는 8
		if bpv < 1:
			continue
		res.source_verts += vcount
		res.source_tris += int(idx.size() / 3)

		# 2-1) 정점 → 파트: 웨이트 argmax → 다리 평면 → 부위 칠하기 (DRMeshSplitter.split 2-1 과 같은 순서 · 같은 규칙)
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
			var p := String(res.bone_part.get(skel_b, ""))
			if not rules.is_empty():
				p = DRMeshSplitter.leg_part(p, verts[v], rules)
			if paint:
				var op := overrides.part_at(verts[v])
				if op != "" and seen.has(op):
					p = op
			vpart[v] = p

		# 2-2) 삼각형 → 파트 하나(세 정점의 다수결). 2D 는 "정점 하나라도 그 파트면 그 파트" 라 경계 삼각형이 양쪽에 다 들어갔다
		var part_tris := {}   # 파트 -> PackedInt32Array(정점 번호 3 개씩)
		for t in int(idx.size() / 3):
			var a := idx[t * 3]
			var b := idx[t * 3 + 1]
			var c := idx[t * 3 + 2]
			var p := _vote(vpart[a], vpart[b], vpart[c])
			if p == "":
				res.unassigned_tris += 1
			var arr: PackedInt32Array = part_tris.get(p, PackedInt32Array())
			arr.append(a)
			arr.append(b)
			arr.append(c)
			part_tris[p] = arr

		# 2-3) 관절 자르기 — 2D 와 같은 평면, 겹침 0. 평면에 걸친 삼각형은 쪼개져 양쪽 파트로 나뉜다(새 정점은 서피스 끝에 덧붙음).
		#      슬롯 나뉨에 영향이 없는 자르기(같은 슬롯 안 — 팔꿈치 · 무릎 …)는 건너뛴다(needed_cuts) — 결과 슬롯은 전부 자른 것과 같다
		var surf_arrays := arrays
		if not cuts.is_empty():
			var pool := DRMeshCutter.VertexPool.new(arrays)
			DRMeshCutter.apply_cuts(part_tris, cuts, pool, seen, 0.0)
			surf_arrays = pool.finish()
			res.cut_new_verts += (surf_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() - vcount

		# 3) 파트 → 슬롯, 슬롯마다 쓰는 정점만 모은 서피스
		var slot_idx := {}
		for p in part_tris.keys():
			var tris: PackedInt32Array = part_tris[p]
			res.part_tri_counts[p] = int(res.part_tri_counts.get(p, 0)) + int(tris.size() / 3)
			var s := slot_of(String(p), table)
			var acc: PackedInt32Array = slot_idx.get(s, PackedInt32Array())
			acc.append_array(tris)
			slot_idx[s] = acc
		if caps and slot_idx.size() > 1:
			surf_arrays = _add_caps(surf_arrays, slot_idx, res)
		for s in slot_idx.keys():
			var compact := _compact(surf_arrays, slot_idx[s], res)
			if compact.is_empty():
				continue
			if not per_slot.has(s):
				per_slot[s] = []
			(per_slot[s] as Array).append({"arrays": compact, "material": src.surface_get_material(si), "format": src.surface_get_format(si)})
			res.vert_counts[s] = int(res.vert_counts.get(s, 0)) + (compact[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			res.tri_counts[s] = int(res.tri_counts.get(s, 0)) + int((compact[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3)

	# 4) 슬롯마다 ArrayMesh
	for s in per_slot.keys():
		var am := ArrayMesh.new()
		am.resource_name = "slot_%s" % s
		for e in per_slot[s]:
			var ed: Dictionary = e
			var flags := int(ed["format"]) & int(Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ed["arrays"], [], {}, flags)
			if ed["material"] != null:
				am.surface_set_material(am.get_surface_count() - 1, ed["material"])
		res.meshes[s] = am
	res.ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return res


## 슬롯 나뉨에 영향이 있는 자르기만 고른다(적힌 순서 유지). 뒤에서부터 훑어
##   - 두 파트의 슬롯이 다른 자르기(목 · 손목 · 허리) · from "*"(아무 부위) 자르기는 쓴다,
##   - 같은 슬롯 안 자르기(어깨 · 팔꿈치 · 무릎 · 발목)는 그 **뒤의** 쓰는 자르기가 그 파트를 읽을 때만 쓴다.
## 같은 슬롯 안 자르기는 두 파트 사이에서 삼각형을 옮길 뿐 슬롯은 안 바꾼다 → 뒤에서 그 파트를 다시 읽는 자르기가 없으면 빼도
## 슬롯 나뉨이 전부 자른 것과 **똑같다**. 빼면 쓸데없이 쪼개진 삼각형 · 새 정점이 준다(병사마다 GPU 스키닝 정점 수).
static func needed_cuts(cuts: Array, table: Dictionary) -> Array:
	var keep: Array = []
	var need := {}
	var all := false
	for i in range(cuts.size() - 1, -1, -1):
		var cd: Dictionary = cuts[i]
		var to := String(cd.get("to", ""))
		var from := String(cd.get("from", "*"))
		var k := false
		if from == "*" or to == "":
			k = true
			all = true
		elif slot_of(from, table) != slot_of(to, table):
			k = true
		elif all or need.has(from) or need.has(to):
			k = true
		if k:
			keep.push_front(cd)
			need[from] = true
			need[to] = true
	return keep


## 슬롯 경계 뚜껑(10-15) — 슬롯마다 "원본 메시에서는 안쪽인데 이 슬롯에서는 가장자리인" 모서리(= 다른 슬롯과의 경계: 목 · 손목 · 허리 단면)를
## 고리로 이어, 그 고리를 평면 다각형으로 삼각분할한 뚜껑을 덧붙인다(정점 색 CAP_COLOR — 거의 검정, 나머지 정점은 흰색).
## 왜: 옷을 입히면 그 슬롯의 몸을 빼므로 옷은 속이 빈 껍데기다. 양면 그리기(dot_char)로 옷 안쪽 면은 보이지만, 시선이 구멍 둘을
## 지나면(T-포즈에서 팔 축을 따라 오른 소매 → 몸통 → 왼 소매) 껍데기를 뚫고 배경이 비쳤다(10-15 시험 1025 px). 뚜껑이 있으면 슬롯 덩어리가
## 닫혀 어떤 방향에서도 배경이 안 비치고, 소매 · 깃 틈으로는 어두운 속이 보인다. 뚜껑 정점은 고리 정점의 뼈 · 웨이트를 그대로 써서 같이 움직인다.
## 뚜껑은 같은 슬롯 덩어리의 반대편과 맞닿는 면이라(맨몸이면 몸 안쪽) 평소엔 가려 안 보인다.
static func _add_caps(arrays: Array, slot_idx: Dictionary, res: Result) -> Array:
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := pos.size()
	var weld := PackedInt32Array()
	weld.resize(n)
	var first := {}
	for v in n:
		var p := pos[v]
		var k := Vector3i(roundi(p.x * WELD), roundi(p.y * WELD), roundi(p.z * WELD))
		var f: Variant = first.get(k)
		if f == null:
			first[k] = v
			weld[v] = v
		else:
			weld[v] = int(f)
	# 모서리(합친 정점 쌍) → 전체 슬롯에서 쓰인 수. 1 이면 원본 메시의 열린 가장자리(막지 않음)
	var all_cnt := {}
	for s in slot_idx.keys():
		var tris: PackedInt32Array = slot_idx[s]
		for i in tris.size():
			var t0 := i - i % 3
			var a := weld[tris[i]]
			var b := weld[tris[t0 + (i - t0 + 1) % 3]]
			if a != b:
				var e := Vector2i(mini(a, b), maxi(a, b))
				all_cnt[e] = int(all_cnt.get(e, 0)) + 1
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
	var bpv := int(bones.size() / n) if n > 0 else 0
	var cap_src := PackedInt32Array()      # 새 정점마다 속성을 베낄 원본 정점
	var cap_pos := PackedVector3Array()
	var cap_nrm := PackedVector3Array()
	var cap_bw := {}                       # 새 정점(로컬 번호) -> [뼈, 웨이트] (부채꼴 가운데 점만)
	for s in slot_idx.keys():
		var tris: PackedInt32Array = slot_idx[s]
		var cnt := {}
		var dir := {}
		for i in tris.size():
			var t0 := i - i % 3
			var va := tris[i]
			var vb := tris[t0 + (i - t0 + 1) % 3]
			var a := weld[va]
			var b := weld[vb]
			if a == b:
				continue
			var e := Vector2i(mini(a, b), maxi(a, b))
			cnt[e] = int(cnt.get(e, 0)) + 1
			dir[e] = Vector3i(va, vb, tris[t0 + (i - t0 + 2) % 3])
		# 합친 정점 -> [Vector3i(원본 a, 원본 b, 그 삼각형의 나머지 정점) …] — 이 슬롯 삼각형의 감김 방향 그대로의 경계 모서리.
		# 나머지 정점은 경계에서 슬롯 쪽에 있다 → 뚜껑 노멀을 슬롯 바깥(구멍 밖)으로 돌리는 데 쓴다
		var nxt := {}
		for e in cnt.keys():
			if int(cnt[e]) != 1 or int(all_cnt.get(e, 0)) < 2:
				continue
			var d: Vector3i = dir[e]
			var ka := weld[d.x]
			if not nxt.has(ka):
				nxt[ka] = []
			(nxt[ka] as Array).append(d)
		var add := PackedInt32Array()
		var loops := 0
		while not nxt.is_empty():
			var start: int = nxt.keys()[0]
			var cur := start
			var loop := PackedInt32Array()
			var inner := Vector3.ZERO          # 경계 삼각형 나머지 정점의 합(슬롯 쪽)
			var closed := false
			for _g in 1000000:
				var lst: Array = nxt.get(cur, [])
				if lst.is_empty():
					break
				var d: Vector3i = lst.pop_back()
				if lst.is_empty():
					nxt.erase(cur)
				loop.append(d.x)
				inner += pos[d.z]
				cur = weld[d.y]
				if cur == start:
					closed = true
					break
			if not closed or loop.size() < 3:
				res.cap_open += 1
				continue
			# 고리 평면(뉴웰 법선 — 고리 순서의 오른손 방향)과 무게중심
			var m := loop.size()
			var nn := Vector3.ZERO
			var c := Vector3.ZERO
			for i in m:
				var p := pos[loop[i]]
				var q := pos[loop[(i + 1) % m]]
				nn.x += (p.y - q.y) * (p.z + q.z)
				nn.y += (p.z - q.z) * (p.x + q.x)
				nn.z += (p.x - q.x) * (p.y + q.y)
				c += p
			c /= float(m)
			if nn.length() < 1e-9:
				res.cap_open += 1
				continue
			nn = nn.normalized()
			# 뚜껑 노멀 = 슬롯 바깥쪽(경계 삼각형이 있는 쪽의 반대) — 구멍 밖에서 들여다볼 때 겉면으로 칠해진다
			var n_out := nn if (inner / float(m) - c).dot(nn) < 0.0 else -nn
			var u := nn.cross(Vector3.UP if absf(nn.y) < 0.9 else Vector3.RIGHT).normalized()
			var w := nn.cross(u)
			var poly := PackedVector2Array()
			poly.resize(m)
			for i in m:
				var r := pos[loop[i]] - c
				poly[i] = Vector2(r.dot(u), r.dot(w))
			var base := n + cap_src.size()
			for i in m:
				cap_src.append(loop[i])
				cap_pos.append(pos[loop[i]])
				cap_nrm.append(n_out)
			# 뚜껑은 고리 모서리를 슬롯 삼각형과 반대 방향으로 지나야 덩어리와 한 방향으로 닫힌다 → 2D 에서 고리와 반대로 감긴 삼각형
			var tri := Geometry2D.triangulate_polygon(poly)
			if not tri.is_empty():
				for k in int(tri.size() / 3):
					var i0 := tri[k * 3]
					var i1 := tri[k * 3 + 1]
					var i2 := tri[k * 3 + 2]
					if (poly[i1] - poly[i0]).cross(poly[i2] - poly[i0]) > 0.0:
						var tmp := i1
						i1 = i2
						i2 = tmp
					add.append(base + i0)
					add.append(base + i1)
					add.append(base + i2)
			else:                              # 고리가 평면에 비춰 꼬임 — 가운데 점 부채꼴
				res.cap_fan += 1
				var ci := n + cap_src.size()
				cap_bw[cap_src.size()] = _avg_weights(loop, bones, weights, bpv)
				cap_src.append(loop[0])
				cap_pos.append(c)
				cap_nrm.append(n_out)
				for i in m:
					add.append(ci)
					add.append(base + (i + 1) % m)
					add.append(base + i)
			loops += 1
		if loops > 0:
			res.cap_loops[s] = int(res.cap_loops.get(s, 0)) + loops
			res.cap_tris[s] = int(res.cap_tris.get(s, 0)) + int(add.size() / 3)
			tris.append_array(add)
			slot_idx[s] = tris
	return _append_cap_vertices(arrays, n, cap_src, cap_pos, cap_nrm, cap_bw, bpv)


## 고리 정점들의 웨이트 평균(뼈별로 더해 큰 것 bpv 개, 합 1) → [PackedInt32Array 뼈, PackedFloat32Array 웨이트]
static func _avg_weights(loop: PackedInt32Array, bones: PackedInt32Array, weights: PackedFloat32Array, bpv: int) -> Array:
	var acc := {}
	for v in loop:
		for k in bpv:
			var wv := weights[v * bpv + k]
			if wv > 0.0:
				var b := bones[v * bpv + k]
				acc[b] = float(acc.get(b, 0.0)) + wv
	var ks := acc.keys()
	ks.sort_custom(func(x, y): return float(acc[x]) > float(acc[y]))
	var total := 0.0
	for k in mini(bpv, ks.size()):
		total += float(acc[ks[k]])
	var ob := PackedInt32Array()
	var ow := PackedFloat32Array()
	for k in bpv:
		if k < ks.size() and total > 0.0:
			ob.append(int(ks[k]))
			ow.append(float(acc[ks[k]]) / total)
		else:
			ob.append(0)
			ow.append(0.0)
	return [ob, ow]


## 뚜껑 정점을 서피스 배열 끝에 덧붙인다(위치 · 노멀은 뚜껑 것, 색은 CAP_COLOR, 나머지는 원본 정점 것). 정점 색 배열이 없으면 흰색으로 만든다
static func _append_cap_vertices(arrays: Array, n: int, cap_src: PackedInt32Array, cap_pos: PackedVector3Array,
		cap_nrm: PackedVector3Array, cap_bw: Dictionary, bpv: int) -> Array:
	var add := cap_src.size()
	if add == 0:
		return arrays
	var out := arrays.duplicate(false)
	for slot in Mesh.ARRAY_MAX:
		if slot == Mesh.ARRAY_INDEX:
			continue
		var src = arrays[slot]
		if slot == Mesh.ARRAY_COLOR:
			var col := PackedColorArray()
			if src != null and (src as PackedColorArray).size() == n:
				col = (src as PackedColorArray).duplicate()
			else:
				col.resize(n)
				col.fill(Color.WHITE)
			for i in add:
				col.append(CAP_COLOR)
			out[slot] = col
			continue
		if src == null:
			continue
		var size: int = src.size()
		if size == 0 or size % n != 0:
			continue
		var per := int(size / n)
		var dst = src.duplicate()
		dst.resize(size + add * per)
		for i in add:
			var o := size + i * per
			if slot == Mesh.ARRAY_VERTEX:
				dst[o] = cap_pos[i]
			elif slot == Mesh.ARRAY_NORMAL:
				dst[o] = cap_nrm[i]
			elif (slot == Mesh.ARRAY_BONES or slot == Mesh.ARRAY_WEIGHTS) and cap_bw.has(i) and per == bpv:
				var ow: Array = cap_bw[i]
				var arr = ow[0] if slot == Mesh.ARRAY_BONES else ow[1]
				for j in per:
					dst[o + j] = arr[j]
			else:
				var so := cap_src[i] * per
				for j in per:
					dst[o + j] = src[so + j]
		out[slot] = dst
	return out


## 세 정점 파트의 다수결. 셋 다 다르면 첫 정점 것(세 파트가 만나는 점 — 겨드랑이 · 사타구니 — 에만 생기고, 슬롯 경계는 관절 자르기가 다시 긋는다)
static func _vote(a: String, b: String, c: String) -> String:
	if a != "" and (a == b or a == c):
		return a
	if b != "" and b == c:
		return b
	if a != "":
		return a
	if b != "":
		return b
	return c


## 삼각형 목록이 쓰는 정점만 모은 서피스 배열(정점 번호를 새로 매김). 넓이 0 삼각형은 뺀다. 쓸 삼각형이 없으면 []
static func _compact(arrays: Array, tris: PackedInt32Array, res: Result) -> Array:
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n := pos.size()
	var remap := PackedInt32Array()
	remap.resize(n)
	remap.fill(-1)
	var keep := PackedInt32Array()
	var out_idx := PackedInt32Array()
	for k in int(tris.size() / 3):
		var a := tris[k * 3]
		var b := tris[k * 3 + 1]
		var c := tris[k * 3 + 2]
		if a == b or b == c or a == c or (pos[b] - pos[a]).cross(pos[c] - pos[a]).length_squared() <= DEGENERATE_EPS:
			res.degenerate_tris += 1
			continue
		for v in [a, b, c]:
			var vi: int = v
			if remap[vi] < 0:
				remap[vi] = keep.size()
				keep.append(vi)
			out_idx.append(remap[vi])
	if out_idx.is_empty():
		return []
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	for slot in Mesh.ARRAY_MAX:
		if slot == Mesh.ARRAY_INDEX or arrays[slot] == null:
			continue
		var src = arrays[slot]
		var size: int = src.size()
		if size == 0 or size % n != 0:
			continue
		out[slot] = _gather(src, int(size / n), keep)
	out[Mesh.ARRAY_INDEX] = out_idx
	return out


## 정점당 per 칸씩 든 배열(Packed*)에서 keep 정점 것만 같은 형식으로
static func _gather(src, per: int, keep: PackedInt32Array):
	var out = src.slice(0, 0)
	out.resize(keep.size() * per)
	var k := 0
	if per == 1:
		for v in keep:
			out[k] = src[v]
			k += 1
	else:
		for v in keep:
			var b := v * per
			for j in per:
				out[k] = src[b + j]
				k += 1
	return out
