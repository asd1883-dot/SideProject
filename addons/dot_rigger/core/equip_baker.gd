@tool
extends RefCounted
class_name DREquipBaker

## 장비(무기) 3D 모델을 퍼펫과 **같은 카메라 · 같은 레스트 자세**로 구워 2D 장비로 만든다.
##
## 세트(서기/앉기/엎드리기)마다 레스트 자세의 손 방향이 달라 장비 그림도 세트마다 한 장이 필요하다.
## 그립(손 뼈 기준의 무기 변환)을 **한 번** 정해 두면, 세트마다
##   rig.json 의 view 로 카메라 복원 → 그 세트의 레스트 자세 → 무기를 손 뼈에 붙임 → 무기만 렌더 → 자르기
## 를 돌려 그림과 오프셋이 자동으로 나온다. 결과는 <out_dir>/<id>/ 에 세트별 PNG + equip.json.
## 게임에서는 DREquipSet.load_json(equip.json) → DRPuppetSet.equip().
##
## baker 는 캐릭터로 setup() 이 끝난 DRBaker(세트를 구울 때와 같은 모델·추가 동작 폴더).

signal progress(set_index: int, set_count: int, set_name: String)

var baker: DRBaker
var sets_json: String = "res://puppet/sets.json"
var weapon_scene: PackedScene
var weapon_path: String = ""          # equip.json 에 남길 출처(다시 구울 때 참고)
var id: String = "weapon"
var slot: String = "weapon"
## 붙일 파트(이 파트의 루트 뼈에 붙는다)
var attach_part: String = "R_Hand"
## 손 뼈 로컬 기준의 무기 변환. auto_grip() 이 채우거나 창에서 직접 맞춘다
var grip: Transform3D = Transform3D.IDENTITY
## 숨길 무기 하위 노드 이름(탄 클립 등)
var hidden_nodes: PackedStringArray = PackedStringArray()
## 그리기 순서 — "이 파트 바로 앞". 비면 z_index(절대값)
var z_after_part: String = ""
var z_index: int = 1000
var out_dir: String = "res://equip"

var _weapon: Node3D = null
var warnings: PackedStringArray = PackedStringArray()


# ---------------------------------------------------------------- 무기 노드

## 무기를 베이커의 뷰포트에 올린다(도트 셰이더를 입혀서). 이미 올라가 있으면 그대로 돌려준다.
func ensure_weapon() -> Node3D:
	if is_instance_valid(_weapon):
		return _weapon
	if baker == null or baker.model_root == null or weapon_scene == null:
		return null
	_weapon = weapon_scene.instantiate() as Node3D
	if _weapon == null:
		return null
	_weapon.name = "DREquipWeapon"
	baker.model_root.get_parent().add_child(_weapon)
	var shader := load(DRBaker.SHADER_PATH) as Shader
	for mi in _meshes(_weapon):
		if mi.mesh is ArrayMesh:
			baker._apply_dot_material(mi, shader)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	apply_hidden()
	return _weapon


func remove_weapon() -> void:
	if is_instance_valid(_weapon):
		_weapon.queue_free()
	_weapon = null


func apply_hidden() -> void:
	if not is_instance_valid(_weapon):
		return
	for mi in _meshes(_weapon):
		mi.visible = not hidden_nodes.has(String(mi.name))


## 무기의 하위 메시 노드 이름들(창의 파트 목록용)
func weapon_node_names() -> PackedStringArray:
	var out := PackedStringArray()
	var w := ensure_weapon()
	if w != null:
		for mi in _meshes(w):
			out.append(String(mi.name))
	return out


static func _meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root as MeshInstance3D)
	for c in root.get_children():
		out.append_array(_meshes(c))
	return out


## 무기 모델 공간의 경계 상자(숨긴 노드 제외)
func weapon_aabb() -> AABB:
	var w := ensure_weapon()
	var box := AABB()
	var first := true
	if w == null:
		return box
	var inv := w.global_transform.affine_inverse()
	for mi in _meshes(w):
		if hidden_nodes.has(String(mi.name)):
			continue
		var b: AABB = (inv * mi.global_transform) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## 무기 모델 공간에서 그 이름의 노드 중심(없으면 경계 상자에서 어림: 뒤에서 35% · 아래 1/3)
func grip_point_guess(node_name: String, forward: Vector3) -> Vector3:
	var w := ensure_weapon()
	if w != null and node_name != "":
		var inv := w.global_transform.affine_inverse()
		for mi in _meshes(w):
			if String(mi.name) == node_name:
				return ((inv * mi.global_transform) * mi.get_aabb()).get_center()
	var box := weapon_aabb()
	var c := box.get_center()
	var half := box.size * 0.5
	var f := forward.normalized()
	return c - f * (absf(f.dot(half)) * 0.3) - Vector3.UP * (half.y * 0.33)


# ---------------------------------------------------------------- 손·그립

## 파트의 루트 뼈가 지금 자세에서 놓인 곳(베이커 월드 좌표)
func bone_world(part: String) -> Transform3D:
	var p: DRRigModel.Part = baker.rig.parts.get(part, null)
	if p == null or p.root_bone < 0:
		return Transform3D.IDENTITY
	return baker.skeleton.global_transform * baker.skeleton.get_bone_global_pose(p.root_bone)


## 파트의 손바닥쯤(뼈의 머리와 꼬리 가운데, 월드 좌표)
func palm_world(part: String) -> Vector3:
	var p: DRRigModel.Part = baker.rig.parts.get(part, null)
	if p == null:
		return Vector3.ZERO
	return bone_world(part) * (p.tail_local * 0.5)


## 지금 자세에서 무기를 손에 놓는다(grip 적용)
func place_weapon() -> void:
	var w := ensure_weapon()
	if w != null:
		w.global_transform = bone_world(attach_part) * grip


## 그립을 자동으로 잡는다 — **지금 자세**(소총을 든 조준 자세여야 한다)에서
##   총열 방향 = 붙일 손(오른손) → 받치는 손(support_part, 왼손),  위 = 월드 위쪽,
##   무기의 grip_point(모델 공간)가 붙일 손의 손바닥에 오도록.
## forward = 무기 모델에서 총구 쪽 축(예: Vector3(0, 0, 1)).
func auto_grip(support_part: String, forward: Vector3, grip_point: Vector3) -> bool:
	var pr := palm_world(attach_part)
	var pl := palm_world(support_part)
	var d := pl - pr
	if d.length() < 0.0001:
		warnings.append("자동 그립: 두 손의 위치가 같습니다 — 파트 이름을 확인하세요")
		return false
	d = d.normalized()
	var up := Vector3.UP
	if absf(d.dot(up)) > 0.98:
		up = Vector3.FORWARD
	# 월드에서 무기가 가질 축: 총구 = d, 위 = up 을 d 에 수직으로
	var side := up.cross(d).normalized()
	var up2 := d.cross(side).normalized()
	var world_basis := Basis(side, up2, d)          # 모델의 (+X, +Y, +Z) 가 (side, up2, d) 로 가는 기저
	# 모델의 총구 축이 +Z 가 아니면 먼저 +Z 로 돌려 놓는다
	var f := forward.normalized()
	var fix := Basis.IDENTITY
	if f.distance_to(Vector3(0, 0, 1)) > 0.001:
		if f.distance_to(Vector3(0, 0, -1)) < 0.001:
			fix = Basis(Vector3.UP, PI)
		else:
			fix = Basis(Quaternion(f, Vector3(0, 0, 1)))
	var b := world_basis * fix
	var origin := pr - b * grip_point
	grip = bone_world(attach_part).affine_inverse() * Transform3D(b, origin)
	return true


# ---------------------------------------------------------------- 굽기

static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


## sets.json 의 세트들 [{name, dir, rig(Dictionary)}]
func read_sets() -> Array:
	var out: Array = []
	var doc := _read_json(sets_json)
	var base := sets_json.get_base_dir()
	for s in doc.get("sets", []):
		var sd: Dictionary = s
		if not bool(sd.get("ok", true)):
			continue
		var rig := _read_json(base.path_join(String(sd.get("rig", ""))))
		if rig.is_empty():
			warnings.append("%s — rig.json 을 읽을 수 없습니다" % String(sd.get("name", "")))
			continue
		out.append({"name": String(sd.get("name", "")), "dir": String(sd.get("dir", "")), "rig": rig})
	return out


## 그 세트를 구울 때의 카메라·레스트 자세로 맞춘다(레스트가 상하체 합성 동작이면 합성부터 다시 만든다)
func apply_set(set_info: Dictionary) -> bool:
	var rig: Dictionary = set_info["rig"]
	var view: Dictionary = rig.get("view", {})
	if view.is_empty():
		warnings.append("%s — rig.json 에 view 가 없습니다(다시 구울 것)" % String(set_info["name"]))
		return false
	var rest := String(view.get("rest_anim", ""))
	if rest != "" and baker.resolve_anim(rest) == "":
		var defs: Array = baker.opts.composites.duplicate()
		var upper := PackedStringArray()
		for c in rig.get("composites", []):
			var cd: Dictionary = c
			defs.append(cd)
			if upper.is_empty():
				upper = PackedStringArray(cd.get("upper_parts", []))
		if defs.size() > 0:
			baker.opts.composites = defs
			baker.build_composites(defs, upper)
			if baker.anim_player != null:
				baker.anim_player.speed_scale = 0.0
		if baker.resolve_anim(rest) == "":
			warnings.append("%s — 레스트 동작 %s 가 이 모델에 없습니다(추가 동작 폴더를 확인)" % [String(set_info["name"]), rest])
			return false
	var size: Array = view.get("size", [baker.opts.view_size.x, baker.opts.view_size.y])
	baker.opts.view_size = Vector2i(int(size[0]), int(size[1]))
	baker.opts.supersample = int(view.get("supersample", 1))
	baker.apply_view_size()
	baker.apply_view(view)
	baker.set_rest_pose()
	return true


## 무기만 보이게 한 장 찍는다(캔버스 크기 그대로)
func render_weapon_only() -> Image:
	for k in baker.part_nodes.keys():
		(baker.part_nodes[k] as MeshInstance3D).visible = false
	place_weapon()
	var img: Image = await baker._grab()
	for k in baker.part_nodes.keys():
		(baker.part_nodes[k] as MeshInstance3D).visible = true
	return img


## 3D 에서 캐릭터와 무기를 같이 찍는다(그립 확인용)
func render_with_character() -> Image:
	for k in baker.part_nodes.keys():
		(baker.part_nodes[k] as MeshInstance3D).visible = true
	place_weapon()
	return await baker._grab()


## 모든 세트에 대해 굽는다. 결과 { ok, error, json, sets: {세트 이름: {image, offset}} }
func run() -> Dictionary:
	warnings = PackedStringArray()
	if baker == null or baker.rig == null or weapon_scene == null:
		return {"ok": false, "error": "베이커 또는 무기 모델이 없습니다"}
	if not baker.rig.parts.has(attach_part):
		return {"ok": false, "error": "붙일 파트가 없습니다: %s" % attach_part}
	if ensure_weapon() == null:
		return {"ok": false, "error": "무기 씬을 올릴 수 없습니다(루트가 Node3D 여야 함)"}
	var sets := read_sets()
	if sets.is_empty():
		return {"ok": false, "error": "sets.json 에서 세트를 읽지 못했습니다: %s" % sets_json}
	var dir := out_dir.path_join(id.validate_filename())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var keep_anim := baker.opts.rest_anim
	var keep_time := baker.opts.rest_time
	var out_sets := {}
	for i in sets.size():
		var si: Dictionary = sets[i]
		progress.emit(i, sets.size(), String(si["name"]))
		if not apply_set(si):
			continue
		await RenderingServer.frame_post_draw
		var img: Image = await render_weapon_only()
		var used := img.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			warnings.append("%s — 무기가 화면에 안 찍혔습니다(틀 밖)" % String(si["name"]))
			continue
		if used.position.x <= 0 or used.position.y <= 0 or used.end.x >= img.get_width() or used.end.y >= img.get_height():
			warnings.append("%s — 무기가 캔버스 가장자리에 닿아 잘렸을 수 있습니다" % String(si["name"]))
		# 아웃라인 밑깔개가 바깥에 선을 그릴 자리(선 두께 + 1)
		var pad := int((si["rig"] as Dictionary).get("outline_px", 0)) + 1
		var cut := Image.create(used.size.x + pad * 2, used.size.y + pad * 2, false, Image.FORMAT_RGBA8)
		cut.blit_rect(img, used, Vector2i(pad, pad))
		var file := String(si["dir"]).validate_filename() + ".png"
		cut.save_png(ProjectSettings.globalize_path(dir.path_join(file)))
		out_sets[String(si["name"])] = {
			"image": file,
			"offset": [used.position.x - pad, used.position.y - pad],
		}
	baker.opts.rest_anim = keep_anim
	baker.opts.rest_time = keep_time
	var g := grip
	var doc := {
		"version": 1,
		"id": id,
		"slot": slot,
		"part": attach_part,
		"z_after_part": z_after_part,
		"z_index": z_index,
		"follow_stretch": false,   # 긴 무기가 손의 단축 보정을 따라 찌그러지면 안 된다
		"source": weapon_path,
		"hidden": Array(hidden_nodes),
		"grip": [g.basis.x.x, g.basis.x.y, g.basis.x.z, g.basis.y.x, g.basis.y.y, g.basis.y.z,
				 g.basis.z.x, g.basis.z.y, g.basis.z.z, g.origin.x, g.origin.y, g.origin.z],
		"sets": out_sets,
	}
	var json_path := dir.path_join("equip.json")
	var f := FileAccess.open(json_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(doc, "\t"))
		f.close()
	return {
		"ok": out_sets.size() > 0,
		"error": "" if out_sets.size() > 0 else "구워진 세트가 없습니다: " + ", ".join(warnings),
		"json": json_path,
		"sets": out_sets,
		"warnings": warnings,
	}


## equip.json 의 grip 배열 → Transform3D
static func grip_from_array(a: Array) -> Transform3D:
	if a.size() < 12:
		return Transform3D.IDENTITY
	return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))
