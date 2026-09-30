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
## 그립 = 자동 그립(grip_base) 위에 조정을 얹은 것:
##   - 자동 그립: 소총을 든 자세에서 총열 = 붙일 손 → 받치는 손, 무기의 그립 점이 붙일 손의 손바닥에.
##   - 조정은 **무기 축 기준**(x 좌우 · y 위아래 · z 총열 앞뒤 / 회전 x 총구 위아래 · y 좌우 틀기 · z 굴리기)이라
##     보는 각도와 상관없이 뜻이 같고, 손 뼈 로컬로 저장되므로 세트가 바뀌어도 그대로 따라간다.
##   - 모든 자세 공통 조정(adj_pos / adj_rot) + 세트별 조정(set_adjust) — 자세마다 조금씩 다르게 잡을 때.
##
## 그리기 순서(앞 조각): 무기는 한 자리(z_after_part / z_index)에 두고, 그 뒤에 그려지는 파트 중 3D 에서 무기보다
## 카메라에 가까운 부분(총열을 감싼 손가락 등)만 "앞 조각" 으로 따로 찍어 무기 바로 위에 그 파트를 따라 그린다.
## 한 자리 끼우기로는 못 푸는 순환(왼손 < 몸통 < 총 < 왼손)을 Spine 의 손 앞/뒤 나누기처럼 푼다 — 다만 자동.
## 세트마다 3D 렌더 3장(무기만 · 몸만 · 파트 ID 색 + 무기 흰색)으로 픽셀마다 누가 맨 앞인지 안다.
##
## baker 는 캐릭터로 setup() 이 끝난 DRBaker(세트를 구울 때와 같은 모델·추가 동작 폴더).

signal progress(set_index: int, set_count: int, set_name: String)

## 총구 쪽 축 고르기용
const AXES := {"+Z": Vector3(0, 0, 1), "-Z": Vector3(0, 0, -1), "+X": Vector3(1, 0, 0), "-X": Vector3(-1, 0, 0), "+Y": Vector3(0, 1, 0), "-Y": Vector3(0, -1, 0)}
const Z_BACK := 5        # "맨 뒤" 의 절대 z(파트는 10 부터, 밑깔개는 −1)
const Z_FRONT := 1000    # "맨 앞"
const FRONT_MIN_PX := 4  # 이보다 작은 앞 조각은 버린다(가장자리 잡음)
const KEY_COLOR := Color(1.0, 1.0, 1.0)   # 파트 ID 렌더에서 무기의 색(파트는 채도 1 의 색상환 색)

var baker: DRBaker
var sets_json: String = "res://puppet/sets.json"
## 무기 리소스 — PackedScene(파트별로 나뉜 씬) 또는 Mesh(OBJ 를 기본 형식으로 가져온 것, 한 덩어리)
var weapon_res: Resource = null
var weapon_path: String = ""          # equip.json 에 남길 출처(다시 열 때 다시 읽는다)
var weapon_scale: float = 1.0         # 모델 단위가 다를 때(cm 로 만든 모델 = 0.01)
var id: String = "weapon"
var slot: String = "weapon"
## 붙일 파트(이 파트의 루트 뼈에 붙는다) / 자동 그립에서 총열이 향할 파트
var attach_part: String = "R_Hand"
var support_part: String = "L_Hand"
## 무기 모델에서 총구 쪽 축
var forward: Vector3 = Vector3(0, 0, 1)
## 손이 잡는 자리 = 이 노드의 중심(비면 경계 상자에서 어림) + grip_offset(모델 공간)
var grip_node: String = ""
var grip_offset: Vector3 = Vector3.ZERO
## 숨길 무기 하위 노드 이름(탄 클립 등)
var hidden_nodes: PackedStringArray = PackedStringArray()
## 그리기 순서 — "이 파트 바로 앞". 비면 z_index(절대값: Z_BACK = 맨 뒤 · Z_FRONT = 맨 앞)
var z_after_part: String = ""
var z_index: int = Z_FRONT
var out_dir: String = "res://equip"
## 앞 조각을 자동으로 굽는다(끄면 무기가 한 자리에만 그려진다)
var front_pieces: bool = true
## 파트별 앞뒤 규칙 { 파트: RULE_* } — 자동(3D 깊이대로) 대신 손으로 정할 때. 없는 파트는 자동.
##   RULE_WEAPON_FRONT: 겹치면 총이 그 파트를 가린다(파트가 무기 뒤 순서면 앞 조각을 안 만들고, 앞 순서면 총의 그 부분을 파트 위에 얹는다)
##   RULE_PART_FRONT: 겹치면 그 파트가 총을 가린다(파트가 무기 뒤 순서면 겹치는 부분 전부를 앞 조각으로)
var part_rules: Dictionary = {}
const RULE_AUTO := "auto"
const RULE_WEAPON_FRONT := "weapon_front"
const RULE_PART_FRONT := "part_front"
##   RULE_HIDE: 이 장비를 들면 그 파트를 아예 안 그린다(받치는 손이 총 위로 삐져나올 때 등). 자세별 규칙으로 쓰는 게 보통
const RULE_HIDE := "hide"
## 목록 방식(09-23~): 무기는 늘 맨 앞(Z_FRONT)에 두고, 파트마다 "총 뒤로"(RULE_WEAPON_FRONT = 총이 가림) / 그 외(= 파트가 총을 가림)
## / 숨김 을 정한다. 총을 가리는 파트는 겹치는 부분을 조각으로 따로 찍어 총 위에 얹는다. 규칙이 없는 파트 = 총 앞.
var list_mode: bool = true
## 모든 자세에 같은 모습(09-29) — 총을 **한 각도**(보기 틀기 view_yaw · 굴리기 view_roll, 0/0 = 옆모습)에서 찍은 그림을
## 자세마다 그 자세의 총열 방향으로 2D 로 돌려 붙인다. 끄면 자세마다 3D 그대로(손 방향에 따라 총이 비스듬히 · 짧아져 보임).
var consistent_view: bool = true
var view_yaw: float = 0.0     # 도 — 카메라 위쪽 축으로 돌림(총구가 카메라 쪽/반대쪽 = 3/4 모습). 180 = 반대 면(총구 왼쪽)
var view_roll: float = 0.0    # 도 — 총열을 축으로 굴림(윗면·아랫면이 보이게)
## 옛 equip.json(한 자리 방식)을 읽었을 때 그 자리(z_after_part) — 창이 이 파트까지를 "총 뒤로" 로 채운다
var legacy_after: String = ""

# 그립
var grip_base: Transform3D = Transform3D.IDENTITY   # 자동 그립 결과(손 뼈 로컬)
var grip_frame: Basis = Basis.IDENTITY               # 무기 축(x 좌우 · y 위 · z 총열)을 손 뼈 로컬로 — 조정을 이 축으로 준다
var grip_pivot: Vector3 = Vector3.ZERO               # 그립 점의 손 뼈 로컬 위치(회전 조정의 중심)
var adj_pos: Vector3 = Vector3.ZERO                  # 모든 자세 공통 이동(m, 무기 축)
var adj_rot: Vector3 = Vector3.ZERO                  # 모든 자세 공통 회전(도: x 총구 위(+)/아래 · y 좌우 틀기 · z 굴리기)
## 세트 이름 -> { pos: Vector3, rot: Vector3, z_after_part: String, z_index: int, z_override: bool } — 그 자세만 더 조정
var set_adjust: Dictionary = {}

var warnings: PackedStringArray = PackedStringArray()
var _weapon: Node3D = null
var _cur_set: String = ""          # apply_set 으로 세운 세트
var _orders: Dictionary = {}      # 세트 이름 -> 그리기 순서(뒤 → 앞), read_sets 가 채운다
var _cur_ortho: float = 1.0        # 그 세트의 굽는 카메라 크기(확대 보기의 기준)


# ---------------------------------------------------------------- 무기 노드

## 무기를 베이커의 뷰포트에 올린다(도트 셰이더를 입혀서). 이미 올라가 있으면 그대로 돌려준다.
func ensure_weapon() -> Node3D:
	if is_instance_valid(_weapon):
		return _weapon
	if baker == null or baker.model_root == null or weapon_res == null:
		return null
	var w: Node3D = null
	if weapon_res is PackedScene:
		w = (weapon_res as PackedScene).instantiate() as Node3D
	elif weapon_res is Mesh:
		w = Node3D.new()
		var mi := MeshInstance3D.new()
		mi.name = weapon_path.get_file().get_basename() if weapon_path != "" else "mesh"
		mi.mesh = weapon_res
		w.add_child(mi)
	if w == null:
		return null
	w.name = "DREquipWeapon"
	baker.model_root.get_parent().add_child(w)
	var shader := load(DRBaker.SHADER_PATH) as Shader
	for mi in _meshes(w):
		if mi.mesh is ArrayMesh:
			baker._apply_dot_material(mi, shader)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_weapon = w
	apply_hidden()
	return _weapon


## 무기를 뷰포트에서 바로 뗀다. queue_free 가 아니라 즉시 — 같은 프레임에 다시 올리면(설정 복원 때) 이름이 겹쳐
## 옛 것이 남고, 옛 것이 나중에 지워질 때 렌더러가 "material is null" 을 찍는다(09-22 실측).
func remove_weapon() -> void:
	if is_instance_valid(_weapon):
		for mi in _meshes(_weapon):
			for si in mi.get_surface_override_material_count():
				mi.set_surface_override_material(si, null)
		if _weapon.get_parent() != null:
			_weapon.get_parent().remove_child(_weapon)
		_weapon.free()
	_weapon = null


func _set_weapon_visible(on: bool) -> void:
	if is_instance_valid(_weapon):
		_weapon.visible = on


## 무기 리소스를 바꾼다(다시 올린다)
func set_weapon(res: Resource, path: String) -> void:
	remove_weapon()
	weapon_res = res
	weapon_path = path


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


## 파트별로 나뉘어 있나(Mesh 로 가져온 OBJ 는 한 덩어리)
func weapon_is_split() -> bool:
	return weapon_res is PackedScene


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
func grip_point_guess(node_name: String, fwd: Vector3) -> Vector3:
	var w := ensure_weapon()
	if w != null and node_name != "":
		var inv := w.global_transform.affine_inverse()
		for mi in _meshes(w):
			if String(mi.name) == node_name:
				return ((inv * mi.global_transform) * mi.get_aabb()).get_center()
	var box := weapon_aabb()
	var c := box.get_center()
	var half := box.size * 0.5
	var f := fwd.normalized()
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


## 파트 손바닥의 캔버스(퍼펫) 좌표 — apply_set 뒤, 굽는 카메라에서
func palm_canvas(part: String) -> Vector2:
	if baker == null or baker.camera == null:
		return Vector2.ZERO
	return baker.camera.unproject_position(palm_world(part)) / float(maxi(1, baker.opts.supersample))


## 캔버스 1픽셀이 몇 m 인지(굽는 카메라 기준)
func meters_per_px() -> float:
	return _cur_ortho / float(maxi(1, baker.opts.view_size.y))


## 목표 그립(손 뼈 로컬)을 만드는 조정값(공통 + 세트 조정의 합) — compose_grip 의 역
func solve_adjust(target: Transform3D) -> Dictionary:
	var rl := target.basis * grip_base.basis.inverse()
	var r := grip_frame.inverse() * rl * grip_frame
	var e := r.orthonormalized().get_euler()
	var rot := Vector3(-rad_to_deg(e.x), rad_to_deg(e.y), rad_to_deg(e.z))
	var pos := grip_frame.inverse() * (target.origin - grip_pivot - rl * (grip_base.origin - grip_pivot))
	return {"pos": pos, "rot": rot}


## 지금 자세에서 무기를 화면 평면으로 옮기고(delta_px: 캔버스 px, 오른쪽·아래 +) 화면 축으로 돌린(dtheta: 라디안, 시계 방향 +)
## 결과를 조정값으로 돌려준다. pivot_world 를 중심으로 돈다. apply_set 뒤(굽는 카메라)에 부를 것.
func nudge_to_adjust(set_name: String, delta_px: Vector2, dtheta: float, pivot_world: Vector3) -> Dictionary:
	var cam := baker.camera.global_transform
	var mpp := meters_per_px()
	var d := cam.basis.x * (delta_px.x * mpp) - cam.basis.y * (delta_px.y * mpp)
	var rb := Basis(cam.basis.z.normalized(), -dtheta)
	var gw := bone_world(attach_part) * compose_grip(set_name)
	var gw2 := Transform3D(rb, pivot_world - rb * pivot_world + d) * gw
	return solve_adjust(bone_world(attach_part).affine_inverse() * gw2)


## 그 세트의 조정(없으면 빈 값)
func adjust_of(set_name: String) -> Dictionary:
	var d: Dictionary = set_adjust.get(set_name, {})
	return {
		"pos": Vector3(d.get("pos", Vector3.ZERO)),
		"rot": Vector3(d.get("rot", Vector3.ZERO)),
		"z_after_part": String(d.get("z_after_part", "")),
		"z_index": int(d.get("z_index", z_index)),
		"z_override": bool(d.get("z_override", false)),
		"rules": Dictionary(d.get("rules", {})),
	}


## 세트별 조정 저장. 전부 기본값이면 항목을 지운다
func set_adjust_of(set_name: String, pos: Vector3, rot: Vector3, z_override: bool, z_after: String, z_idx: int) -> void:
	var rules: Dictionary = adjust_of(set_name)["rules"]
	if pos.is_zero_approx() and rot.is_zero_approx() and not z_override and rules.is_empty():
		set_adjust.erase(set_name)
		return
	set_adjust[set_name] = {"pos": pos, "rot": rot, "z_override": z_override, "z_after_part": z_after if z_override else "", "z_index": z_idx if z_override else z_index, "rules": rules}


## 파트 앞뒤 규칙 쓰기. set_name 이 비면 공통(part_rules), 아니면 그 자세만. key 가 auto 면 지운다
func set_rule(part: String, key: String, set_name: String = "") -> void:
	if set_name == "":
		if key == RULE_AUTO:
			part_rules.erase(part)
		else:
			part_rules[part] = key
		return
	var a := adjust_of(set_name)
	var rules: Dictionary = a["rules"]
	if key == RULE_AUTO:
		rules.erase(part)
	else:
		rules[part] = key
	set_adjust[set_name] = {"pos": a["pos"], "rot": a["rot"], "z_override": a["z_override"], "z_after_part": a["z_after_part"], "z_index": a["z_index"], "rules": rules}
	if Vector3(a["pos"]).is_zero_approx() and Vector3(a["rot"]).is_zero_approx() and not bool(a["z_override"]) and rules.is_empty():
		set_adjust.erase(set_name)


## 그 자세에서 그 파트의 규칙(자세별 > 공통 > 자동)
func rule_for(set_name: String, part: String) -> String:
	var a := adjust_of(set_name)
	var rules: Dictionary = a["rules"]
	if rules.has(part):
		return String(rules[part])
	return String(part_rules.get(part, RULE_PART_FRONT if list_mode else RULE_AUTO))


## 공통 규칙(자세별 무시)
func common_rule(part: String) -> String:
	return String(part_rules.get(part, RULE_PART_FRONT if list_mode else RULE_AUTO))


## 그 자세의 규칙을 모두 지워 공통을 따르게
func clear_set_rules(set_name: String) -> void:
	if not set_adjust.has(set_name):
		return
	(set_adjust[set_name] as Dictionary)["rules"] = {}
	var a := adjust_of(set_name)
	set_adjust_of(set_name, a["pos"], a["rot"], a["z_override"], a["z_after_part"], a["z_index"])   # 남은 게 없으면 항목째 지운다


## 뒤 → 앞 순서에서 upto 파트까지(포함)를 "총 뒤로" 로(이미 규칙이 있는 파트는 그대로). 새 장비의 기본값
func apply_default_behind(order: Array, upto: String) -> void:
	if upto == "" or not order.has(upto):
		return
	for pn in order:
		if not part_rules.has(String(pn)):
			part_rules[String(pn)] = RULE_WEAPON_FRONT
		if String(pn) == upto:
			break


func _order_of(set_name: String) -> Array:
	var o: Array = _orders.get(set_name, [])
	return o if not o.is_empty() else Array(baker.rig.order)


## 그 자세에서 무기가 그려질 자리 { after, index }.
## 목록 방식: **"총 뒤로" 체크한 파트 중 그리기 순서에서 가장 앞의 것 바로 앞**(없으면 맨 뒤).
## 그보다 앞 순서의 파트는 그냥 순서대로 총을 가리므로 조각이 필요 없다 — 애니가 레스트에서 벗어나도 어긋나지 않는다.
## 조각은 그 자리보다 뒤 순서인데 체크 안 한 파트(총 앞으로 끌어낸 것)만 생긴다.
func weapon_z_for(set_name: String) -> Dictionary:
	if list_mode:
		var last := ""
		for pn in _order_of(set_name):
			if rule_for(set_name, String(pn)) == RULE_WEAPON_FRONT:
				last = String(pn)
		return {"after": last, "index": Z_BACK} if last == "" else {"after": last, "index": Z_FRONT}
	var a := adjust_of(set_name)
	return {"after": String(a["z_after_part"]) if bool(a["z_override"]) else z_after_part, "index": int(a["z_index"]) if bool(a["z_override"]) else z_index}


## 자동 그립 + 공통 조정 + (있으면) 그 세트의 조정 = 손 뼈 로컬의 최종 무기 변환
func compose_grip(set_name: String = "") -> Transform3D:
	var pos := adj_pos
	var rot := adj_rot
	if set_adjust.has(set_name):
		var a := adjust_of(set_name)
		pos += Vector3(a["pos"])
		rot += Vector3(a["rot"])
	return _apply_adjust(grip_base, pos, rot)


## 조정을 무기 축(grip_frame)으로 준다. 회전은 그립 점(grip_pivot)을 중심으로.
## rot.x 는 + 가 총구 위 — 프레임의 x 축(좌우 = 위 × 총열)을 기준으로 하면 + 가 아래라 부호를 뒤집는다.
func _apply_adjust(base: Transform3D, pos: Vector3, rot_deg: Vector3) -> Transform3D:
	var r := Basis.from_euler(Vector3(deg_to_rad(-rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	var rl := grip_frame * r * grip_frame.inverse()
	var out := Transform3D()
	out.basis = rl * base.basis
	out.origin = grip_pivot + rl * (base.origin - grip_pivot) + grip_frame * pos
	return out


## 일관된 보기 자리 — 굽는 카메라 앞에 총을 옆모습(+ view_yaw · view_roll)으로, 손이 잡는 자리를 붙일 손 손바닥에
func place_canonical() -> void:
	var w := ensure_weapon()
	if w == null or baker.camera == null:
		return
	var cb := baker.camera.global_transform.basis
	var d := cb.x.normalized()
	var up := cb.y.normalized()
	var side := up.cross(d).normalized()
	var b0 := Basis(side, up, d)
	var f := forward.normalized()
	var fix := Basis.IDENTITY
	if f.distance_to(Vector3(0, 0, 1)) > 0.001:
		if f.distance_to(Vector3(0, 0, -1)) < 0.001:
			fix = Basis(Vector3.UP, PI)
		else:
			fix = Basis(Quaternion(f, Vector3(0, 0, 1)))
	var b := Basis(up, deg_to_rad(view_yaw)) * Basis(d, deg_to_rad(view_roll)) * b0 * fix
	var bs := b * Basis.from_scale(Vector3.ONE * weapon_scale)
	var gpm := grip_point_guess(grip_node, f) + grip_offset
	# 잡는 자리를 **화면 한가운데**에 — 손 위치에 놓으면 도트 격자에 걸치는 자리가 세트마다 달라 그림이 1px 씩 달라진다
	var co := baker.camera.global_transform.origin
	var dist := (baker._model_aabb.get_center() - co).dot(-cb.z.normalized())   # 깊이도 세트와 무관하게 고정(셰이더가 시선 벡터를 쓴다)
	var target := co - cb.z.normalized() * dist
	w.global_transform = Transform3D(bs, target - bs * gpm)


## 캔버스에서 총열 각도 · 손이 잡는 자리(지금 놓인 총 기준)
func _weapon_canvas_frame() -> Dictionary:
	var ss := float(maxi(1, baker.opts.supersample))
	var xf := _weapon.global_transform
	var o3 := xf.origin
	var f3 := (xf.basis * forward).normalized()
	var gpm := grip_point_guess(grip_node, forward) + grip_offset
	return {
		"barrel": ((baker.camera.unproject_position(o3 + f3 * 0.3) - baker.camera.unproject_position(o3)) / ss).angle(),
		"grip": baker.camera.unproject_position(xf * gpm) / ss,
	}


## 지금 자세에서 무기를 손에 놓는다(그 세트의 그립으로)
func place_weapon(set_name: String = "") -> void:
	var w := ensure_weapon()
	if w == null or baker.rig == null:
		return
	var xf := bone_world(attach_part) * compose_grip(set_name)
	xf.basis = xf.basis * Basis.from_scale(Vector3.ONE * weapon_scale)
	w.global_transform = xf


## 그립을 자동으로 잡는다 — **지금 자세**(소총을 든 조준 자세여야 한다)에서
##   총열 방향 = 붙일 손(attach_part) → 받치는 손(support_part),  위 = 월드 위쪽,
##   무기의 그립 점(grip_node 중심 + grip_offset)이 붙일 손의 손바닥에 오도록.
## 조정(adj_*)은 건드리지 않는다.
func auto_grip() -> bool:
	if baker == null or baker.rig == null or not baker.rig.parts.has(attach_part) or not baker.rig.parts.has(support_part):
		warnings.append("자동 그립: 파트가 없습니다 (%s / %s)" % [attach_part, support_part])
		return false
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
	var gp := (grip_point_guess(grip_node, f) + grip_offset) * weapon_scale
	var origin := pr - b * gp
	var hand_inv := bone_world(attach_part).affine_inverse()
	grip_base = hand_inv * Transform3D(b, origin)
	grip_frame = hand_inv.basis * world_basis       # 조정 축 = 정렬된 무기 축(손 뼈의 배율까지 포함해야 m 단위가 맞는다)
	grip_pivot = hand_inv * pr
	return true


# ---------------------------------------------------------------- 세트·카메라

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
		_orders[String(sd.get("name", ""))] = Array(rig.get("layer_order", []))
	return out


## 그립을 잡기 좋은 세트(레스트 동작 이름에 rifle·aim 이 든 첫 세트, 없으면 첫 세트)
static func pick_grip_set(sets: Array) -> Dictionary:
	for s in sets:
		var sd: Dictionary = s
		var rest := String((sd["rig"] as Dictionary).get("view", {}).get("rest_anim", "")).to_lower()
		if rest.contains("rifle") or rest.contains("aim"):
			return sd
	return sets[0] if sets.size() > 0 else {}


## 그 세트를 구울 때의 카메라·캔버스 크기·레스트 자세로 맞춘다(레스트가 상하체 합성 동작이면 합성부터 다시 만든다)
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
	_cur_set = String(set_info["name"])
	_cur_ortho = baker.camera.size
	return true


func current_set() -> String:
	return _cur_set


## 3D 미리보기용 카메라 — 붙일 손 주변을 zoom 배로 확대해 본다(apply_set 뒤에 부를 것).
## yaw/pitch 를 주면 그 각도에서, 안 주면(NAN) 굽는 시점 그대로. zoom 1 + 굽는 시점 = 굽는 카메라 그대로.
func view_hand(zoom: float, yaw_deg: float = NAN, pitch_deg: float = NAN) -> void:
	var cam := baker.camera
	if cam == null:
		return
	if zoom <= 1.0 and is_nan(yaw_deg):
		return
	var target := palm_world(attach_part)
	if is_nan(yaw_deg):
		var xf := cam.global_transform
		xf.origin = target + xf.basis.z * 5.0
		cam.global_transform = xf
	else:
		var pos := target + DRBaker.view_basis(yaw_deg, pitch_deg) * Vector3(0, 0, 5.0)
		cam.global_transform = Transform3D(Basis(), pos).looking_at(target, Vector3.UP)
	cam.size = _cur_ortho / maxf(zoom, 0.1)


## 장비만 보는 미리보기 카메라 — 굽는 카메라의 방향 그대로, 장비 경계 상자 한가운데를 화면 중심에.
## 보이는 범위 = 장비 긴 변 × span 배(직교 카메라라 거리(z)를 옮겨도 크기는 안 변한다 — 담는 범위로 조절).
## 미리보기 전용: 굽기 전에 apply_set 이 카메라를 되돌린다.
func view_weapon(span: float) -> void:
	var cam := baker.camera
	var w := ensure_weapon()
	if cam == null or w == null:
		return
	var box := weapon_aabb()
	var c: Vector3 = w.global_transform * box.get_center()
	var xf := cam.global_transform
	var depth := (c - xf.origin).dot(-xf.basis.z.normalized())
	xf.origin = c + xf.basis.z.normalized() * maxf(depth, 1.0)
	cam.global_transform = xf
	var long := maxf(box.size.x, maxf(box.size.y, box.size.z)) * weapon_scale
	cam.size = maxf(long * span, 0.01)


## 캐릭터 파트 보이기/숨기기(3D 미리보기에서 무기만 볼 때)
func show_character(on: bool) -> void:
	for k in baker.part_nodes.keys():
		(baker.part_nodes[k] as MeshInstance3D).visible = on


## 무기만 보이게 한 장 찍는다(캔버스 크기 그대로). 캐릭터 파트는 찍은 뒤 다시 보인다
func render_weapon_only(set_name: String = "") -> Image:
	show_character(false)
	place_weapon(set_name)
	var img: Image = await baker._grab()
	show_character(true)
	return img


## 3D 에서 캐릭터와 무기를 같이 찍는다(그립 확인용)
func render_with_character(set_name: String = "") -> Image:
	show_character(true)
	place_weapon(set_name)
	return await baker._grab()


# ---------------------------------------------------------------- 굽기

## 이 세트에서 무기 뒤에 그려지는 파트들(뒤 → 앞 순서에서 무기 자리보다 앞의 것) — 앞 조각 후보
func parts_behind_weapon(set_info: Dictionary) -> PackedStringArray:
	var wz := weapon_z_for(String(set_info["name"]))
	var after := String(wz["after"])
	var zi := int(wz["index"])
	var order: Array = Array((set_info["rig"] as Dictionary).get("layer_order", []))
	if order.is_empty():
		order = Array(baker.rig.order)
	var out := PackedStringArray()
	if after != "" and order.has(after):
		for pn in order:
			out.append(String(pn))
			if String(pn) == after:
				break
		return out
	for i in order.size():
		if (i + 1) * DRRigModel.Z_STEP < zi:
			out.append(String(order[i]))
	return out


static func _id_color(i: int, n: int) -> Color:
	return Color.from_hsv(float(i) / float(maxi(n, 1)), 1.0, 1.0)


## ID 렌더의 픽셀 → 파트 번호. −1 = 무기(흰색), −2 = 빈 곳
static func _decode_id(c: Color, n: int) -> int:
	if c.a < 0.5:
		return -2
	if c.s < 0.35:
		return -1
	return int(roundf(c.h * float(n))) % maxi(n, 1)


## 파트 ID 렌더: 파트마다 색상환의 고유 색(무광), 무기는 흰색 — 픽셀마다 누가 맨 앞인지. with_weapon = false 면 파트끼리만
func _render_id_pass(set_name: String, with_weapon: bool = true) -> Dictionary:
	var names := PackedStringArray(baker.part_nodes.keys())
	for i in names.size():
		var mi := baker.part_nodes[names[i]] as MeshInstance3D
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = _id_color(i, names.size())
		mi.material_override = m
		mi.visible = true
	var w := ensure_weapon()
	var key := StandardMaterial3D.new()
	key.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	key.albedo_color = KEY_COLOR
	for mi in _meshes(w):
		mi.material_override = key
	_set_weapon_visible(with_weapon)
	place_weapon(set_name)
	var keep_levels := baker.opts.color_levels
	baker.opts.color_levels = 0   # ID 색이 양자화로 뭉개지지 않게
	var img: Image = await baker._grab()
	baker.opts.color_levels = keep_levels
	for i in names.size():
		(baker.part_nodes[names[i]] as MeshInstance3D).material_override = null
	for mi in _meshes(w):
		mi.material_override = null
	_set_weapon_visible(true)
	return {"img": img, "names": names}


## 세트 하나를 메모리에서 굽는다 → { ok, image, offset, warning, overlays: [{part, image, offset, pixels}], palm_attach, palm_support }
func bake_set(set_info: Dictionary) -> Dictionary:
	var name := String(set_info["name"])
	if not apply_set(set_info):
		return {"ok": false, "warning": warnings[warnings.size() - 1] if warnings.size() > 0 else "%s — 세트를 세울 수 없습니다" % name}
	await RenderingServer.frame_post_draw
	var palm_a := palm_canvas(attach_part)
	var palm_s := palm_canvas(support_part)
	var img: Image = await render_weapon_only(name)
	var used := img.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return {"ok": false, "warning": "%s — 무기가 화면에 안 찍혔습니다(틀 밖)" % name}
	# 총열이 캔버스에서 향한 각도(기즈모 축을 총에 맞추려고)
	var barrel := 0.0
	if is_instance_valid(_weapon):
		var ss := float(maxi(1, baker.opts.supersample))
		var o3 := _weapon.global_transform.origin
		var f3 := (_weapon.global_transform.basis * forward).normalized()
		barrel = ((baker.camera.unproject_position(o3 + f3 * 0.3) - baker.camera.unproject_position(o3)) / ss).angle()
	var warn := ""
	if used.position.x <= 0 or used.position.y <= 0 or used.end.x >= img.get_width() or used.end.y >= img.get_height():
		warn = "%s — 무기가 캔버스 가장자리에 닿아 잘렸을 수 있습니다" % name
	# 아웃라인 밑깔개가 바깥에 선을 그릴 자리(선 두께 + 1)
	var pad := int((set_info["rig"] as Dictionary).get("outline_px", 0)) + 1
	var cut := Image.create(used.size.x + pad * 2, used.size.y + pad * 2, false, Image.FORMAT_RGBA8)
	cut.blit_rect(img, used, Vector2i(pad, pad))
	# 앞 조각 — 파트별 규칙(자동 = 3D 깊이 · 총이 앞 · 파트가 앞). 무기 발자국 안에서만 본다(밖은 파트 자기 그림이 그린다)
	var overlays: Array = []
	var overlap: Dictionary = {}   # 파트 -> { overlap: 겹치는 px, front: 3D 에서 무기보다 앞인 px, behind_order: bool }
	var behind := parts_behind_weapon(set_info)
	_set_weapon_visible(false)
	show_character(true)
	var body: Image = await baker._grab()
	var idp0: Dictionary = await _render_id_pass(name, false)   # 파트끼리만 — 누가 겹치나
	var idp: Dictionary = await _render_id_pass(name, true)     # 무기까지 — 누가 무기보다 앞인가
	var id0: Image = idp0["img"]
	var idw: Image = idp["img"]
	var names: PackedStringArray = idp["names"]
	var n := names.size()
	var stat_overlap := PackedInt32Array()
	var stat_front := PackedInt32Array()
	stat_overlap.resize(n)
	stat_front.resize(n)
	for y in range(used.position.y, used.end.y):
		for x in range(used.position.x, used.end.x):
			if img.get_pixel(x, y).a < 0.5:
				continue
			var a0 := _decode_id(id0.get_pixel(x, y), n)
			if a0 >= 0:
				stat_overlap[a0] += 1
			var aw := _decode_id(idw.get_pixel(x, y), n)
			if aw >= 0:
				stat_front[aw] += 1
	for pi in n:
		var pn := String(names[pi])
		if stat_overlap[pi] == 0 and stat_front[pi] == 0:
			continue
		var is_behind := behind.has(pn)
		overlap[pn] = {"overlap": stat_overlap[pi], "front": stat_front[pi], "behind_order": is_behind}
		var rule := rule_for(name, pn)
		if rule == RULE_HIDE:
			overlays.append({"part": pn, "kind": "hide", "pixels": 0})
			continue
		var kind := "part"
		var use_all := false      # 겹치는 부분 전부(파트가 앞) / 아니면 3D 에서 앞인 픽셀만(자동)
		if is_behind:
			if rule == RULE_WEAPON_FRONT:
				continue
			if rule == RULE_PART_FRONT and list_mode:
				# 목록 방식 — 겹치는 픽셀만 찍으면 레스트 기준이라 애니에서 손이 움직이면 어긋난다(09-23 사용자 캡처).
				# 파트를 통째로 총 위로 올린다(런타임이 그 파트의 z 를 총 z + 1 + 순번 으로 매 프레임 덮어씀).
				overlays.append({"part": pn, "kind": "raise", "rank": _order_of(name).find(pn), "pixels": stat_overlap[pi]})
				continue
			if rule == RULE_PART_FRONT:
				use_all = true
			elif not front_pieces:
				continue
		else:
			if rule != RULE_WEAPON_FRONT:
				continue
			kind = "weapon"        # 파트가 무기보다 앞 순서인데 총이 가려야 함 → 총의 그 부분을 파트 위에
		var ov := Image.create(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8)
		var count := 0
		for y in range(used.position.y, used.end.y):
			for x in range(used.position.x, used.end.x):
				var wp := img.get_pixel(x, y)
				if wp.a < 0.5:
					continue
				if kind == "weapon":
					if _decode_id(id0.get_pixel(x, y), n) != pi:
						continue   # 그 파트가 있는 자리의 총 픽셀만
					ov.set_pixel(x, y, wp)
					count += 1
				else:
					var src: Image = id0 if use_all else idw
					if _decode_id(src.get_pixel(x, y), n) != pi:
						continue
					var c := body.get_pixel(x, y)
					if c.a < 0.5:
						continue
					ov.set_pixel(x, y, c)
					count += 1
		if count < FRONT_MIN_PX:
			continue
		var r := ov.get_used_rect()
		var ocut := Image.create(r.size.x + pad * 2, r.size.y + pad * 2, false, Image.FORMAT_RGBA8)
		ocut.blit_rect(ov, r, Vector2i(pad, pad))
		overlays.append({"part": pn, "kind": kind, "image": ocut, "offset": Vector2i(r.position.x - pad, r.position.y - pad), "pixels": count})
	# 목록 방식 — 겹치지 않아도 "총 앞" 으로 끌어낸 파트는 올린다(애니 중에 겹칠 수 있다)
	if list_mode:
		for pn in behind:
			var done := false
			for o in overlays:
				done = done or String((o as Dictionary)["part"]) == String(pn)
			if not done and names.has(String(pn)) and rule_for(name, String(pn)) == RULE_PART_FRONT:
				overlays.append({"part": String(pn), "kind": "raise", "rank": _order_of(name).find(String(pn)), "pixels": 0})
	# 겹치지 않는 파트라도 숨김 규칙이면 넣는다
	for pn in names:
		if not overlap.has(String(pn)) and rule_for(name, String(pn)) == RULE_HIDE:
			overlays.append({"part": String(pn), "kind": "hide", "pixels": 0})
	var out_img := cut
	var out_off := Vector2i(used.position.x - pad, used.position.y - pad)
	var out_angle := 0.0
	if consistent_view and is_instance_valid(_weapon):
		# 이 자세의 총열 방향 · 손이 잡는 자리(3D 그대로)
		place_weapon(name)
		var pose := _weapon_canvas_frame()
		# 같은 모습의 그림(옆모습 + 보기 각) — 그 그림의 총열을 이 자세의 총열 방향으로 돌려, 잡는 자리를 맞춘다
		show_character(false)
		place_canonical()
		var canon := _weapon_canvas_frame()
		var cimg: Image = await baker._grab()
		show_character(true)
		place_weapon(name)
		var cu := cimg.get_used_rect()
		if cu.size.x > 0 and cu.size.y > 0:
			out_img = Image.create(cu.size.x + pad * 2, cu.size.y + pad * 2, false, Image.FORMAT_RGBA8)
			out_img.blit_rect(cimg, cu, Vector2i(pad, pad))
			out_angle = float(pose["barrel"]) - float(canon["barrel"])
			var g_img: Vector2 = Vector2(canon["grip"]) - Vector2(cu.position - Vector2i(pad, pad))
			var o := Vector2(pose["grip"]) - g_img.rotated(out_angle)
			out_off = Vector2i(roundi(o.x), roundi(o.y))
			barrel = float(canon["barrel"])   # 그림 안에서의 총열 각(기즈모 축용 — 스프라이트 회전이 나머지를 더한다)
	return {"ok": true, "image": out_img, "offset": out_off, "angle": out_angle, "warning": warn,
		"overlays": overlays, "overlap": overlap, "palm_attach": palm_a, "palm_support": palm_s, "barrel": barrel}


## 모든 세트를 메모리에서 굽는다 → { 세트 이름: bake_set 결과 }. 진행 신호를 낸다
func bake_all(sets: Array = []) -> Dictionary:
	if sets.is_empty():
		sets = read_sets()
	var out := {}
	for i in sets.size():
		var si: Dictionary = sets[i]
		progress.emit(i, sets.size(), String(si["name"]))
		var r: Dictionary = await bake_set(si)
		if String(r.get("warning", "")) != "":
			warnings.append(String(r["warning"]))
		out[String(si["name"])] = r
	return out


## 구운 결과로 런타임 장비 묶음을 만든다(파일 없이 — 미리보기용)
func build_equip_set(baked: Dictionary) -> DREquipSet:
	var es := DREquipSet.new()
	es.id = id
	es.slot = slot
	for set_name in baked.keys():
		var r: Dictionary = baked[set_name]
		if not bool(r.get("ok", false)):
			continue
		var it := DREquipItem.new()
		it.slot = slot
		it.part = attach_part
		it.texture = ImageTexture.create_from_image(r["image"] as Image)
		it.offset = Vector2(r["offset"] as Vector2i)
		it.follow_stretch = false
		it.angle = float(r.get("angle", 0.0))
		var wz := weapon_z_for(String(set_name))
		it.z_after_part = String(wz["after"])
		it.z_index = int(wz["index"])
		var ovs: Array = []
		for o in r.get("overlays", []):
			var od: Dictionary = o
			if String(od.get("kind", "part")) in ["hide", "raise"]:
				ovs.append({"part": String(od["part"]), "kind": String(od["kind"]), "rank": int(od.get("rank", 0))})
				continue
			ovs.append({"part": String(od["part"]), "kind": String(od.get("kind", "part")), "texture": ImageTexture.create_from_image(od["image"] as Image), "offset": Vector2(od["offset"] as Vector2i)})
		it.overlays = ovs
		es.items[String(set_name)] = it
	return es


## 모든 세트에 대해 굽고 파일로 남긴다. 결과 { ok, error, json, sets: {세트 이름: {image, offset}}, warnings }
func run() -> Dictionary:
	warnings = PackedStringArray()
	if baker == null or baker.rig == null or weapon_res == null:
		return {"ok": false, "error": "베이커 또는 무기 모델이 없습니다"}
	if not baker.rig.parts.has(attach_part):
		return {"ok": false, "error": "붙일 파트가 없습니다: %s" % attach_part}
	if ensure_weapon() == null:
		return {"ok": false, "error": "무기를 올릴 수 없습니다(씬의 루트가 Node3D 이거나 Mesh 여야 함)"}
	var sets := read_sets()
	if sets.is_empty():
		return {"ok": false, "error": "sets.json 에서 세트를 읽지 못했습니다: %s" % sets_json}
	var dir := out_dir.path_join(id.validate_filename())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var keep_anim := baker.opts.rest_anim
	var keep_time := baker.opts.rest_time
	var baked: Dictionary = await bake_all(sets)
	baker.opts.rest_anim = keep_anim
	baker.opts.rest_time = keep_time
	var out_sets := {}
	for si in sets:
		var name := String((si as Dictionary)["name"])
		var r: Dictionary = baked.get(name, {})
		if not bool(r.get("ok", false)):
			continue
		var file := String((si as Dictionary)["dir"]).validate_filename() + ".png"
		(r["image"] as Image).save_png(ProjectSettings.globalize_path(dir.path_join(file)))
		var off: Vector2i = r["offset"]
		var entry := {"image": file, "offset": [off.x, off.y], "angle": float(r.get("angle", 0.0)), "grip": _t2a(compose_grip(name))}
		var ov_entries: Array = []
		for o in r.get("overlays", []):
			var od: Dictionary = o
			if String(od.get("kind", "part")) in ["hide", "raise"]:
				ov_entries.append({"part": String(od["part"]), "kind": String(od["kind"]), "rank": int(od.get("rank", 0))})
				continue
			var ofile := "%s_%s_%s.png" % [String((si as Dictionary)["dir"]).validate_filename(), "over" if String(od.get("kind", "part")) == "weapon" else "front", String(od["part"]).validate_filename()]
			(od["image"] as Image).save_png(ProjectSettings.globalize_path(dir.path_join(ofile)))
			var ooff: Vector2i = od["offset"]
			ov_entries.append({"part": String(od["part"]), "kind": String(od.get("kind", "part")), "image": ofile, "offset": [ooff.x, ooff.y], "pixels": int(od.get("pixels", 0))})
		entry["overlays"] = ov_entries
		var wz := weapon_z_for(name)
		entry["z_after_part"] = String(wz["after"])
		entry["z_index"] = int(wz["index"])
		out_sets[name] = entry
	var doc := to_dict()
	doc["sets"] = out_sets
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


# ---------------------------------------------------------------- 저장·복원(equip.json)

static func _t2a(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]


static func _b2a(b: Basis) -> Array:
	return [b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z]


static func _v2a(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _a2v(a: Variant, def: Vector3 = Vector3.ZERO) -> Vector3:
	if a is Array and (a as Array).size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return def


static func _a2b(a: Variant, def: Basis = Basis.IDENTITY) -> Basis:
	if a is Array and (a as Array).size() >= 9:
		return Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]))
	return def


## equip.json 의 grip 배열 → Transform3D
static func grip_from_array(a: Variant) -> Transform3D:
	if not (a is Array) or (a as Array).size() < 12:
		return Transform3D.IDENTITY
	return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))


## 설정 전부(구운 그림 빼고) — equip.json 의 본문
func to_dict() -> Dictionary:
	var sa := {}
	for k in set_adjust.keys():
		var a := adjust_of(String(k))
		sa[String(k)] = {"pos": _v2a(a["pos"]), "rot": _v2a(a["rot"]), "z_override": bool(a["z_override"]),
			"z_after_part": String(a["z_after_part"]), "z_index": int(a["z_index"]), "rules": Dictionary(a["rules"]).duplicate()}
	return {
		"version": 2,
		"id": id,
		"slot": slot,
		"part": attach_part,
		"support_part": support_part,
		"forward": _v2a(forward),
		"grip_node": grip_node,
		"grip_offset": _v2a(grip_offset),
		"weapon_scale": weapon_scale,
		"list_mode": list_mode,
		"consistent_view": consistent_view,
		"view_yaw": view_yaw,
		"view_roll": view_roll,
		"z_after_part": "" if list_mode else z_after_part,
		"z_index": Z_FRONT if list_mode else z_index,
		"front_pieces": front_pieces,
		"part_rules": part_rules.duplicate(),
		"follow_stretch": false,   # 긴 무기가 손의 단축 보정을 따라 찌그러지면 안 된다
		"source": weapon_path,
		"sets_json": sets_json,
		"hidden": Array(hidden_nodes),
		"grip_base": _t2a(grip_base),
		"grip_frame": _b2a(grip_frame),
		"grip_pivot": _v2a(grip_pivot),
		"adj_pos": _v2a(adj_pos),
		"adj_rot": _v2a(adj_rot),
		"set_adjust": sa,
	}


## to_dict() 결과(또는 옛 equip.json)에서 설정을 되돌린다. 무기 리소스는 source 에서 다시 읽는다(있으면)
func from_dict(d: Dictionary) -> void:
	id = String(d.get("id", id))
	slot = String(d.get("slot", slot))
	attach_part = String(d.get("part", attach_part))
	support_part = String(d.get("support_part", support_part))
	forward = _a2v(d.get("forward"), forward)
	grip_node = String(d.get("grip_node", ""))
	grip_offset = _a2v(d.get("grip_offset"))
	weapon_scale = float(d.get("weapon_scale", 1.0))
	z_after_part = String(d.get("z_after_part", ""))
	z_index = int(d.get("z_index", Z_FRONT))
	front_pieces = bool(d.get("front_pieces", true))
	part_rules = {}
	for k in d.get("part_rules", {}).keys():
		part_rules[String(k)] = String(d["part_rules"][k])
	legacy_after = ""
	consistent_view = bool(d.get("consistent_view", false))   # 이 칸이 없던 파일은 예전처럼(자세마다 3D 그대로)
	view_yaw = float(d.get("view_yaw", 0.0))
	view_roll = float(d.get("view_roll", 0.0))
	if not bool(d.get("list_mode", false)):
		# 한 자리 방식이던 옛 파일 — 자동/파트가 앞 규칙은 버리고(목록 방식에선 규칙 없음 = 총 앞), 그 자리까지를 창이 "총 뒤로" 로 채운다
		legacy_after = z_after_part
		var keep := {}
		for k in part_rules.keys():
			if String(part_rules[k]) == RULE_WEAPON_FRONT or String(part_rules[k]) == RULE_HIDE:
				keep[k] = part_rules[k]
		part_rules = keep
	list_mode = true
	z_after_part = ""
	z_index = Z_FRONT
	if d.has("sets_json"):
		sets_json = String(d["sets_json"])
	hidden_nodes = PackedStringArray(d.get("hidden", []))
	if d.has("grip_base"):
		grip_base = grip_from_array(d["grip_base"])
		grip_frame = _a2b(d.get("grip_frame"))
		grip_pivot = _a2v(d.get("grip_pivot"))
	elif d.has("grip"):
		# 09-21 낮의 옛 파일 — 조정 없이 최종 그립만 있다
		grip_base = grip_from_array(d["grip"])
		grip_frame = Basis.IDENTITY
		grip_pivot = grip_base.origin
	adj_pos = _a2v(d.get("adj_pos"))
	adj_rot = _a2v(d.get("adj_rot"))
	set_adjust = {}
	var sa: Dictionary = d.get("set_adjust", {})
	for k in sa.keys():
		var e: Dictionary = sa[k]
		var er := {}
		for rk in Dictionary(e.get("rules", {})).keys():
			er[String(rk)] = String(e["rules"][rk])
		set_adjust[String(k)] = {"pos": _a2v(e.get("pos")), "rot": _a2v(e.get("rot")), "z_override": bool(e.get("z_override", false)),
			"z_after_part": String(e.get("z_after_part", "")), "z_index": int(e.get("z_index", z_index)), "rules": er}
	var src := String(d.get("source", ""))
	if src != "" and src == weapon_path and weapon_res != null:
		pass   # 이미 같은 무기가 올라가 있다
	elif src != "" and load_weapon(src) != null:
		set_weapon(load_weapon(src), src)
	elif src != "":
		warnings.append("무기 모델을 찾을 수 없습니다: %s" % src)
		weapon_path = src


## 무기 파일 불러오기. 가져오기(import)된 것은 그대로, 아직 안 된 glb/gltf(공정이 방금 만든 것)는 런타임으로 읽어 씬으로 만든다
## — 에디터가 열려 있어도 CLI 로 구울 수 있게(에디터가 가져오기 전이라도).
static func load_weapon(path: String) -> Resource:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		return load(path)
	var ext := path.get_extension().to_lower()
	if not (ext in ["glb", "gltf"]) or not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), st) != OK:
		return null
	var root := doc.generate_scene(st)
	if root == null:
		return null
	_own_all(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	root.free()
	return ps


static func _own_all(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		_own_all(c, owner)


# ---------------------------------------------------------------- 자산 기록(asset.json)
# 자산 공정의 기록 파일. 생성 → 정규화(Blender) → 굽기 가 각자 자기 칸을 읽고 결과를 적는다.
#   source{file, generator} · normalize{length_m, forward, up, grip_node, output, result} · character{preset, sets}
#   · equip{…to_dict() 과 같은 칸 + out_dir} · history[]
# 장비 설정의 원본은 여기 "equip" 칸 — 창에서 조정하고 구우면 이 칸도 갱신된다.

## 무기 파일 옆의 asset.json (없으면 "")
static func asset_path_for(weapon_path: String) -> String:
	if weapon_path == "":
		return ""
	var p := weapon_path.get_base_dir().path_join("asset.json")
	return p if FileAccess.file_exists(p) else ""


## asset.json 의 "equip" 칸을 지금 설정으로 갱신하고 기록을 남긴다
func write_asset_equip(asset_path: String, note: String = "") -> bool:
	var d := _read_json(asset_path)
	if d.is_empty():
		return false
	var eq := to_dict()
	eq["out_dir"] = out_dir
	d["equip"] = eq
	var hist: Array = d.get("history", [])
	hist.append({"step": "bake", "at": Time.get_datetime_string_from_system(), "ok": true, "note": note})
	d["history"] = hist
	var f := FileAccess.open(asset_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	return true


## equip.json 을 읽어 설정을 되돌린다(못 읽으면 false)
func load_json(path: String) -> bool:
	var d := _read_json(path)
	if d.is_empty():
		warnings.append("equip.json 을 읽을 수 없습니다: %s" % path)
		return false
	from_dict(d)
	return true
