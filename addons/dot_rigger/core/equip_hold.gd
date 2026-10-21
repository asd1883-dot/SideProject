@tool
extends RefCounted
class_name DREquipHold

## 소켓 장비 도우미(10-16) — ② 장비 탭(DREquipPage)과 검사 도구가 같이 쓴다.
##   - 장비 모델 목록(source3d/weapons/** 의 무기 씬 · glb) · 대용 헬멧
##   - 맞추기: 지금 자세(기준 동작)의 두 손바닥으로 무기를 소켓 기준 자리에 놓고, 왼손 표지를 그 자세의 왼손(손바닥 점 · 손 회전)으로
##   - 무기 기본 자리: asset.json 의 "socket_hold" 칸(소켓 기준 무기 자리 · 무기 기준 왼손 표지 · 동작별 IK 비중) — 다른 유닛 소켓에
##     이 무기를 넣을 때 처음 자리로 쓴다(무기를 바꾸는 자식 프리팹이 처음부터 다시 맞추지 않게). 옛 "equip" 칸(2D 굽기 · DRGripFit)과 따로.
## 무기 모델 약속: +Z = 총구, +Y = 위(정규화 공정 결과 — kar98k.glb · mp40.glb 둘 다). 단위 m.

const MODEL_DIRS := ["res://source3d/weapons", "res://source3d/equipment"]
const PLACEHOLDER_HELMET := "(대용) 헬멧 — 반구"
const HOLD_KEY := "socket_hold"


## 넣을 수 있는 장비 모델 — 무기 씬(.tscn — 숨김 부품 · 표지가 든 감싸기)이 먼저, 그다음 glb · gltf
static func list_models() -> PackedStringArray:
	var scenes := PackedStringArray()
	var raw := PackedStringArray()
	for d in MODEL_DIRS:
		_scan(String(d), scenes, raw)
	scenes.sort()
	raw.sort()
	scenes.append_array(raw)
	return scenes


static func _scan(dir: String, scenes: PackedStringArray, raw: PackedStringArray) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		var ext := String(f).get_extension().to_lower()
		if ext == "tscn" or ext == "scn":
			scenes.append(dir.path_join(String(f)))
		elif ext == "glb" or ext == "gltf":
			raw.append(dir.path_join(String(f)))
	for sub in d.get_directories():
		_scan(dir.path_join(String(sub)), scenes, raw)


## 모델 옆의 asset.json(없으면 "")
static func asset_for_model(model_path: String) -> String:
	if model_path == "" or model_path.begins_with("("):
		return ""
	var p := model_path.get_base_dir().path_join("asset.json")
	return p if FileAccess.file_exists(p) else ""


## 장비 모델 인스턴스(씬에 넣을 것 — 인스턴스로 저장되게 GEN_EDIT_STATE_INSTANCE). 대용 헬멧은 반구 메시 하나
static func instantiate_model(model_path: String) -> Node3D:
	if model_path == PLACEHOLDER_HELMET:
		return placeholder_helmet()
	var ps := load(model_path) as PackedScene if ResourceLoader.exists(model_path) else null
	if ps == null:
		return null
	var n := ps.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE) as Node3D
	return n


## 헬멧 모델이 아직 없어 머리 소켓을 시험할 대용 메시(반구 · 국방색). 진짜 헬멧이 생기면 모델 목록에서 바꿔 넣는다
static func placeholder_helmet() -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = 0.13
	m.height = 0.13
	m.is_hemisphere = true
	m.radial_segments = 16
	m.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.33, 0.36, 0.25)
	m.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "헬멧_대용"
	mi.mesh = m
	mi.position = Vector3(0.0, 0.1, 0.01)
	return mi


## 무기 모델(장비 노드) 안 보이는 메시의 경계 상자 — 장비 노드 기준
static func model_aabb(equip: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array = [[equip, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var n: Node = it[0]
		var xf: Transform3D = it[1]
		if n != equip and n is Node3D:
			if not (n as Node3D).visible:
				continue
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var b: AABB = xf * (n as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
		for c in n.get_children():
			stack.append([c, xf])
	return box


## 오른손이 쥐는 점 어림(장비 노드 기준) — 방아쇠 노드가 있으면 그 5.5 cm 뒤 · 2.5 cm 아래(개머리 손목 / 권총 손잡이),
## 없으면 경계 상자에서(뒤에서 35 % · 아래 1/3 — 옛 DREquipBaker.grip_point_guess 와 같은 식)
static func grip_point_guess(equip: Node3D) -> Vector3:
	var trig := _find_named(equip, "trigger")
	if trig != null:
		var xf := xform_to(equip, trig)
		var c: Vector3 = (xf * (trig as MeshInstance3D).get_aabb()).get_center() if trig is MeshInstance3D else xf.origin
		return c + Vector3(0.0, -0.025, -0.055)
	var box := model_aabb(equip)
	var half := box.size * 0.5
	return box.get_center() - Vector3(0.0, 0.0, half.z * 0.3) - Vector3(0.0, half.y * 0.33, 0.0)


static func _find_named(root: Node, low_name: String) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if String(n.name).to_lower() == low_name:
			return n
		stack.append_array(n.get_children())
	return null


## root 기준 node 의 변환(둘 사이 Node3D 변환을 곱한 것 — 트리 밖이어도 된다)
static func xform_to(root: Node, node: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## 맞추기 — ch 를 동작 motion 의 frac 시점 자세로 세우고(동작 그대로 = IK 전), 두 손바닥으로 무기 자리를 잡는다:
##   쥐는 점(grip_point, 장비 기준) = 오른 손바닥, 쥐는 점 → 받치는 점 방향 = 오른 손바닥 → 왼 손바닥 방향, 위(+Y) = 모델 위에 가깝게.
##   받치는 점(support_point)을 안 주면 총열(+Z) 방향을 쓰고 왼손 표지 = 그 자세의 왼 손바닥 자리.
##   주면(짧은 무기 — 동작의 두 손 거리는 긴 소총 기준이라 mp40 은 왼손이 총구 앞 허공에 뜬다) 왼손 표지 = 그 점(왼손은 IK 로 당겨 온다).
## 돌려주는 값 {weapon: 소켓 기준 무기 변환(장비 노드의 transform), support: 무기 기준 왼손 표지 변환(손바닥 점 · 손 회전), gap: 두 손바닥 거리 m}
## scale = 장비 노드의 배율(보통 1). 자세는 그대로 남는다(부른 쪽이 동작을 다시 튼다)
static func fit(ch: DRCharacter3D, socket_bone: String, motion: String, frac: float, grip_point: Vector3, scale: Vector3 = Vector3.ONE,
		support_point: Variant = null) -> Dictionary:
	var sk := ch.get_skeleton()
	var ap := ch.get_animation_player()
	var body := ch.get_body_entry()
	if sk == null or ap == null or body.is_empty() or not ap.has_animation(motion):
		return {}
	var rig: DRRigModel = body["rig"]
	var pr_part: DRRigModel.Part = rig.parts.get("R_Hand", null)
	var pl_part: DRRigModel.Part = rig.parts.get("L_Hand", null)
	var sb := sk.find_bone(socket_bone)
	if pr_part == null or pl_part == null or sb < 0:
		return {}
	DRGripFit.pose(ch, motion, frac)
	var hs := sk.get_bone_global_pose(sb)
	var hl := sk.get_bone_global_pose(pl_part.root_bone)
	var pr := sk.get_bone_global_pose(pr_part.root_bone) * (pr_part.tail_local * 0.5)
	var pl := hl * (pl_part.tail_local * 0.5)
	var dv := pl - pr
	if dv.length() < 0.01:
		return {}
	var fs := _frame_along(dv.normalized())                         # 뼈대 공간: z = 두 손바닥 방향, y = 위에 가깝게
	var axis_w := Vector3(0, 0, 1)
	if support_point is Vector3 and ((support_point as Vector3) - grip_point).length() > 0.01:
		axis_w = ((support_point as Vector3) - grip_point) * scale
	var fw := _frame_along(axis_w.normalized())                     # 장비 공간: z = 쥐는 점 → 받치는 점(없으면 총열 +Z)
	var b := fs * fw.inverse() * Basis.from_scale(scale)
	var wt := Transform3D(b, pr - b * grip_point)                  # 뼈대 공간 무기
	var w_local := hs.affine_inverse() * wt
	var m := wt.affine_inverse() * Transform3D(hl.basis.orthonormalized(), pl)
	m.basis = m.basis.orthonormalized()
	if support_point is Vector3:
		m.origin = support_point
	return {"weapon": w_local, "support": m, "gap": dv.length()}


## z 를 d 로, y 를 위(+Y)에 가깝게 둔 정규 직교 기저(d 가 거의 수직이면 위 대신 앞)
static func _frame_along(d: Vector3) -> Basis:
	var up := Vector3.UP
	if absf(d.dot(up)) > 0.98:
		up = Vector3.FORWARD
	var side := up.cross(d).normalized()
	return Basis(side, d.cross(side).normalized(), d)


## 동작마다 그 손(side 0 = 왼손 · 1 = 오른손) 수치 — 동작을 틀고(섞기 없이, 그 동작의 IK 비중) samples 시점마다 DRCharacter3D.support_report.
## [{motion, weight, raw_avg, raw_max, ik_avg, ik_max, rot_max, reach_max}] (m · 도). 끝나면 원래 동작 · 시점으로 되돌린다
static func motion_report(ch: DRCharacter3D, motions: PackedStringArray, samples: int = 8, side: int = 0) -> Array:
	var out: Array = []
	var ap := ch.get_animation_player()
	if ap == null or ch.get_arm_ik(side) == null:
		return out
	var keep := ch.current_motion()
	var keep_t := ap.current_animation_position if ap.current_animation != "" else 0.0
	for mo in motions:
		if not ap.has_animation(mo):
			continue
		ch.play_motion(mo, 0.0)
		var acc := {"motion": mo, "weight": ch.get_ik_weight(side), "raw_avg": 0.0, "raw_max": 0.0, "ik_avg": 0.0, "ik_max": 0.0, "rot_max": 0.0, "reach_max": 0.0}
		var n := maxi(samples, 1)
		for i in n:
			ap.seek(ap.get_animation(mo).length * float(i) / float(n), true)
			var r := ch.support_report(side)
			if r.is_empty():
				continue
			acc["raw_avg"] = float(acc["raw_avg"]) + float(r["raw"]) / n
			acc["raw_max"] = maxf(float(acc["raw_max"]), float(r["raw"]))
			acc["ik_avg"] = float(acc["ik_avg"]) + float(r["ik"]) / n
			acc["ik_max"] = maxf(float(acc["ik_max"]), float(r["ik"]))
			acc["rot_max"] = maxf(float(acc["rot_max"]), float(r["rot"]))
			acc["reach_max"] = maxf(float(acc["reach_max"]), float(r["reach"]))
		out.append(acc)
	if keep != "" and ap.has_animation(keep):
		ch.play_motion(keep, 0.0)
		ap.seek(keep_t, true)
	return out


# ---------------------------------------------------------------- 무기 기본 자리(asset.json "socket_hold")

static func _t2a(t: Transform3D) -> Array:
	return [t.basis.x.x, t.basis.x.y, t.basis.x.z, t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z, t.origin.x, t.origin.y, t.origin.z]


static func _a2t(a: Variant) -> Transform3D:
	if not (a is Array) or (a as Array).size() < 12:
		return Transform3D.IDENTITY
	return Transform3D(Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])), Vector3(a[9], a[10], a[11]))


## 무기 기본 자리 읽기 — {bone, scene, weapon(Transform3D), support(Transform3D, 없으면 키 없음), motion_weights{}, motion_offsets{동작: Transform3D}} 또는 {}
static func read_hold(asset_json: String) -> Dictionary:
	if asset_json == "" or not FileAccess.file_exists(asset_json):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(asset_json))
	if not (v is Dictionary) or not (v as Dictionary).has(HOLD_KEY):
		return {}
	var h: Dictionary = v[HOLD_KEY]
	var out := {"bone": String(h.get("bone", "RightHand")), "scene": String(h.get("scene", "")), "weapon": _a2t(h.get("transform"))}
	if h.has("support"):
		out["support"] = _a2t(h["support"])
	var mw := {}
	for k in Dictionary(h.get("motion_weights", {})).keys():
		mw[String(k)] = float(h["motion_weights"][k])
	out["motion_weights"] = mw
	var mo := {}
	for k in Dictionary(h.get("motion_offsets", {})).keys():
		mo[String(k)] = _a2t(h["motion_offsets"][k])
	out["motion_offsets"] = mo
	var am := {}                                  # 조준 표지(10-21) — {"총구": 무기 기준 변환, "견착": …}
	for k in Dictionary(h.get("aim_markers", {})).keys():
		am[String(k)] = _a2t(h["aim_markers"][k])
	out["aim_markers"] = am
	return out


## 무기 기본 자리 쓰기 — asset.json 의 다른 칸은 **글자 그대로** 두고 "socket_hold" 칸만 바꾸거나 더한다(기록 history 에 한 줄).
## 왜 글로 끼우나: 통째로 읽어 JSON.stringify 로 다시 쓰면 Godot 4.7 이 아주 작은 수를 13 자리로 줄여(옛 equip 그립 6.51925802230835e-08
## → 6.519258022e-08, 10-16 실측) 손대지 않은 칸까지 바뀐다
## motion_offsets = 동작별 무기 자리(장비 축 기준 차이 — 받침이 달라도 뜻이 같아 다른 유닛에 그대로 쓴다, 10-19)
## aim_markers = 조준 표지 {"총구": 무기 기준 변환(+Z = 레이 방향), "견착": …}(10-21 — 없으면 게임이 메시에서 잰다)
static func write_hold(asset_json: String, bone: String, scene: String, weapon: Transform3D, support: Variant, motion_weights: Dictionary,
		motion_offsets: Dictionary = {}, aim_markers: Dictionary = {}) -> bool:
	if asset_json == "" or not FileAccess.file_exists(asset_json):
		return false
	var txt := FileAccess.get_file_as_string(asset_json)
	if not (JSON.parse_string(txt) is Dictionary):
		return false
	var at := Time.get_datetime_string_from_system()
	var h := {
		"note": "② 장비 탭(3D 소켓) — 이 무기를 소켓에 넣을 때의 기본 자리. transform = 소켓(뼈) 기준 무기, support = 무기 기준 왼손 표지(원점 = 손바닥 점, 기저 = 왼손 뼈 회전), motion_weights = 동작별 왼손 IK 비중(없는 동작 = 1), motion_offsets = 동작별 무기 자리(무기 축 기준 차이 — 무기 자리 = transform × 이 값), aim_markers = 조준 표지(무기 기준 — 총구 = 레이 자리 · +Z 방향, 견착 = 팔 몫 조준의 축)",
		"bone": bone, "scene": scene, "transform": _t2a(weapon), "motion_weights": motion_weights.duplicate(), "at": at,
	}
	if support is Transform3D:
		h["support"] = _t2a(support)
	if not motion_offsets.is_empty():
		var mo := {}
		for k in motion_offsets.keys():
			if motion_offsets[k] is Transform3D:
				mo[String(k)] = _t2a(motion_offsets[k])
		h["motion_offsets"] = mo
	if not aim_markers.is_empty():
		var am := {}
		for k in aim_markers.keys():
			if aim_markers[k] is Transform3D:
				am[String(k)] = _t2a(aim_markers[k])
		h["aim_markers"] = am
	var block := JSON.stringify(h, "\t", true, true).replace("\n", "\n\t")          # 맨 위 객체 안(들여쓰기 한 칸)
	# 키(뒤에 콜론)로 찾는다 — 기록 안의 값 "step": "socket_hold" 를 잡지 않게(10-16 두 번째 저장에서 normalize 칸을 덮은 일)
	var rk := RegEx.create_from_string("\"%s\"\\s*:\\s*\\{" % HOLD_KEY)
	var mk := rk.search(txt)
	if mk != null:
		var vs := mk.get_end() - 1
		var ve := _close_of(txt, vs)
		if ve < 0:
			return false
		txt = txt.substr(0, vs) + block + txt.substr(ve + 1)
	else:
		var end := txt.rfind("}")
		txt = txt.substr(0, end).rstrip(" \t\r\n") + ",\n\t\"%s\": %s\n" % [HOLD_KEY, block] + txt.substr(end)
	var mh := RegEx.create_from_string("\"history\"\\s*:\\s*\\[").search(txt)
	var ab := mh.get_end() - 1 if mh != null else -1
	var ae := _close_of(txt, ab) if ab >= 0 else -1
	if ae > ab:
		var entry := JSON.stringify({"step": "socket_hold", "at": at, "ok": true, "note": "② 장비 탭"}, "\t", true, true).replace("\n", "\n\t\t")
		var empty := txt.substr(ab + 1, ae - ab - 1).strip_edges() == ""
		txt = txt.substr(0, ae).rstrip(" \t\r\n") + ("\n\t\t" if empty else ",\n\t\t") + entry + "\n\t" + txt.substr(ae)
	if not (JSON.parse_string(txt) is Dictionary):
		push_warning("[DREquipHold] asset.json 끼워 넣기 결과가 JSON 이 아님 — 쓰지 않음: %s" % asset_json)
		return false
	var f := FileAccess.open(asset_json, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(txt)
	f.close()
	return true


## txt[open_at] 의 { 또는 [ 짝이 닫히는 자리(문자열 안의 괄호 · 이스케이프는 건너뜀). 못 찾으면 -1
static func _close_of(txt: String, open_at: int) -> int:
	if open_at < 0 or open_at >= txt.length():
		return -1
	var depth := 0
	var in_str := false
	var i := open_at
	while i < txt.length():
		var c := txt[i]
		if in_str:
			if c == "\\":
				i += 1
			elif c == "\"":
				in_str = false
		elif c == "\"":
			in_str = true
		elif c == "{" or c == "[":
			depth += 1
		elif c == "}" or c == "]":
			depth -= 1
			if depth == 0:
				return i
		i += 1
	return -1
