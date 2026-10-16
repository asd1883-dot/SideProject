extends SceneTree

## ② 장비 탭(DREquipPage) 검사(10-16, 3D 소켓 정석) — 창 없이(--headless). 에디터 밖이라 되돌리기 없이 인스턴스를 바로 고치는 길을 탄다
## (에디터 안 길 = 열린 씬 · 되돌리기는 pipeline/check_editor.py). 시험으로 만든 파일은 끝에 지운다.
##   Godot --headless --path <프로젝트> --script res://addons/dot_rigger/tools/equip_page_smoke_cli.gd
## [1] 페이지 · 유닛 · 소켓 나무(오른손 → kar98k → 왼손 표지) · 미리보기(소켓 무기 · 도트 재질 · 숨김 부품 · 왼팔 IK)
## [2] 장비 모델 목록 · 무기 기본 자리(asset.json socket_hold — kar98k · mp40)
## [3] 동작마다 왼 손바닥 ↔ 표지(IK 전 · 뒤) — 소총 동작은 IK 뒤 1 cm 안
## [4] 자식 유닛(시험 파일): mp40 넣기(부모 kar98k 는 숨김 · 기본 자리 · 표지) · 머리 소켓 + 대용 헬멧 · 자리 숫자 · IK 비중 → 저장 → 다시 읽기
## [5] 게임처럼 다시 만들기: 숨긴 부모 무기는 지워짐 · 무기 · 헬멧이 뼈를 따라감 · 도트 재질 · fade · 수정자 MANUAL · mp40 왼손 IK
## [6] 뼈대 길이 든 사본도 소켓이 뼈를 따라감(02 U38)
## [7] 유니티식 기즈모(10-16): 단축키 · 이동(+ 눈금 · 취소 · 왼손 IK 따라옴) · 회전(고리 · 눈금 · 중심 모드) · 크기(축 · 전체 · 표지는 없음) · 눌러서 고르기
## 마지막 줄이 "EQUIP PAGE SMOKE OK" 면 통과.

const BASE := "res://game/units/soldier_base.tscn"
const CHILD := "res://game/units/시험장비_삭제.tscn"
const K98 := "res://source3d/weapons/kar98k/kar98k.tscn"
const MP40 := "res://source3d/weapons/mp40/mp40.glb"
const RIFLE := ["Rifle_Aiming_Idle", "Firing_Rifle", "Rifle_Idle", "Walk_With_Rifle", "Crouch_Idle+Firing_Rifle", "Prone_Firing_Rifle"]
const Giz := preload("res://addons/dot_rigger/ui/transform_gizmo.gd")

var _fails := PackedStringArray()


func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("EQUIP PAGE SMOKE FAIL 시간 초과")
		quit(2))
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["OK  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _key(code: Key, ctrl := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	return ev


func _btn_ev(pos: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	return ev


## 기즈모 층에 마우스 끌기를 흉내 낸다(누름 → 6번 움직임 → 뗌). to 가 Callable 이면 누른 뒤에 정한다(회전 고리의 접선처럼)
func _drag_on(giz: Control, from: Vector2, to: Variant, ctrl := false, release := true) -> void:
	giz._gui_input(_btn_ev(from, true))
	var dest: Vector2 = (to as Callable).call() if to is Callable else to
	var prev := from
	for i in 6:
		var m := InputEventMouseMotion.new()
		m.position = from.lerp(dest, float(i + 1) / 6.0)
		m.relative = m.position - prev
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.ctrl_pressed = ctrl
		prev = m.position
		giz._gui_input(m)
	if release:
		giz._gui_input(_btn_ev(dest, false))


## [7] 유니티식 기즈모 — 미리보기 사본을 끌고 놓으면 유닛 노드에 들어가는가(에디터 밖 = 바로. 되돌리기는 check_editor.py)
func _gizmo_checks(page: DREquipPage) -> void:
	print("[7] 기즈모(유니티식) — 이동 · 회전 · 크기 · 눈금 · 피벗/중심 · 취소 · 단축키 · 눌러서 고르기")
	page.select_unit(BASE)
	await _frames(3)
	var giz = page._giz
	var gw := page._weapon_equip()
	page._select_node(page._root.get_path_to(gw))
	page._playing = false
	page.play_motion("Rifle_Aiming_Idle")
	page._seek(0.3)
	page.frame_selected()
	await _frames(3)
	var pn := page._prev_node(gw) as Node3D
	_check(giz.target == pn and pn != null and giz.allow_scale, "기즈모가 고른 무기의 미리보기 사본에 걸림(크기 손잡이 있음)")

	# 단축키(유니티와 같음)
	var keys_ok := true
	for pair in [[KEY_E, Giz.Tool.ROTATE], [KEY_R, Giz.Tool.SCALE], [KEY_Q, Giz.Tool.VIEW], [KEY_Y, Giz.Tool.TRANSFORM], [KEY_W, Giz.Tool.MOVE]]:
		page._unhandled_key_input(_key(pair[0]))
		keys_ok = keys_ok and giz.tool_mode == int(pair[1]) and page._tool_btns[int(pair[1])].button_pressed
	var loc0: bool = giz.local_space
	var piv0: bool = giz.pivot_mode
	page._unhandled_key_input(_key(KEY_X))
	page._unhandled_key_input(_key(KEY_Z))
	var toggled: bool = giz.local_space != loc0 and giz.pivot_mode != piv0 and page._space_btn.text == ("로컬" if giz.local_space else "글로벌")
	page._unhandled_key_input(_key(KEY_X))
	page._unhandled_key_input(_key(KEY_Z))
	_check(keys_ok and toggled and giz.local_space == loc0 and giz.pivot_mode == piv0, "단축키 E R Q Y W → 도구 · 단추, X 로컬/글로벌 · Z 피벗/중심 켜고 끔")
	page._unhandled_key_input(_key(KEY_F))
	_check(page._target.distance_to(Giz.world_aabb(pn).get_center()) < 0.001, "F = 고른 무기를 화면 가운데로")
	await _frames(2)

	# 이동 — X 화살표를 그 화면 방향으로 60 px
	var t0: Transform3D = gw.transform
	var p := giz.handle_point(Giz.H.AX)
	_check(giz.pick(p) == Giz.H.AX, "W: X 화살표 위 점을 고르면 X 축 손잡이")
	var sdir: Vector2 = (giz._p(giz.pivot_point() + giz._axes_now(false)[0] * 0.1) - giz._p(giz.pivot_point())).normalized()
	_drag_on(giz, p, p + sdir * 60.0, false, false)
	var live_ok := absf(page._pos[0].value - pn.position.x * 100.0) < 0.051 and gw.transform.is_equal_approx(t0)     # 칸은 0.1 cm 단위로 반올림
	giz._gui_input(_btn_ev(p + sdir * 60.0, false))
	var d := gw.transform.origin - t0.origin
	_check(live_ok, "끄는 중: 숫자 칸이 사본을 따라가고 유닛 노드는 아직 그대로")
	_check(d.length() > 0.005 and d.normalized().dot(t0.basis.x.normalized()) > 0.999 and gw.transform.basis.is_equal_approx(t0.basis),
		"놓으면 유닛 노드에: 무기 로컬 X 쪽으로 %.1f cm · 회전 그대로" % (d.length() * 100.0))
	var rep := page._prev.support_report()
	_check(not rep.is_empty() and float(rep["ik"]) < 0.01, "무기를 옮겨도 왼손이 따라감(IK 뒤 %.2f cm)" % (float(rep.get("ik", 1.0)) * 100.0))
	# Ctrl = 1 cm 눈금(세상 거리) — 화면에 가장 길게 보이는 축으로
	var w0 := pn.global_position
	var bk := 0
	var bl := -1.0
	for k in 3:
		var ln: float = (giz._p(giz.pivot_point() + giz._axes_now(false)[k] * 0.1) - giz._p(giz.pivot_point())).length()
		if ln > bl:
			bl = ln
			bk = k
	p = giz.handle_point(Giz.H.AX + bk)
	sdir = (giz._p(giz.pivot_point() + giz._axes_now(false)[bk] * 0.1) - giz._p(giz.pivot_point())).normalized()
	_drag_on(giz, p, p + sdir * 37.0, true)
	var wd := pn.global_position.distance_to(w0)
	_check(wd > 0.005 and wd < 0.5 and absf(wd / 0.01 - roundf(wd / 0.01)) < 0.01, "Ctrl 끌기 = 1 cm 눈금(%s 축 37 px → %.4f m)" % ["xyz"[bk], wd])
	# 카메라를 거의 보는 축은 숨기고 못 잡는다(유니티와 같음) — 화면 25 px 미만
	var short_ok := true
	for k in 3:
		var ln: float = (giz._p(giz.pivot_point() + giz._axes_now(false)[k] * Giz.SIZE_PX * giz._wpp(giz.pivot_point())) - giz._p(giz.pivot_point())).length()
		if ln < Giz.AXIS_MIN_PX and giz.pick(giz.handle_point(Giz.H.AX + k)) == Giz.H.AX + k:
			short_ok = false
	_check(short_ok, "카메라를 거의 보는 축(화면 %d px 미만)은 못 잡음" % int(Giz.AXIS_MIN_PX))
	# 취소 — 끄는 중 오른쪽 누름
	var tc: Transform3D = gw.transform
	p = giz.handle_point(Giz.H.AZ)
	_drag_on(giz, p, p + Vector2(40, -25), false, false)
	giz._gui_input(_btn_ev(p + Vector2(40, -25), true, MOUSE_BUTTON_RIGHT))
	_check(not giz.is_dragging() and gw.transform.is_equal_approx(tc) and pn.transform.is_equal_approx(tc), "끄는 중 오른쪽 누름 = 취소(사본 · 유닛 그대로)")

	# 회전 — Z 고리를 접선으로 40 px(= 40/84 rad), Ctrl 이면 15° 눈금
	page.set_tool(Giz.Tool.ROTATE)
	await _frames(1)
	var r0: Transform3D = gw.transform
	p = giz.handle_point(Giz.H.RZ)
	_check(giz.pick(p) == Giz.H.RZ, "E: Z 고리 위 점 = Z 고리 손잡이")
	_drag_on(giz, p, func() -> Vector2: return p + giz._tan * 40.0)
	var q := Quaternion((gw.transform.basis * r0.basis.inverse()).orthonormalized())
	_check(absf(rad_to_deg(q.get_angle()) - rad_to_deg(40.0 / Giz.SIZE_PX)) < 1.0 and absf(absf(q.get_axis().dot(r0.basis.z.normalized())) - 1.0) < 0.01
		and gw.transform.origin.is_equal_approx(r0.origin), "고리를 따라 40 px → 로컬 Z 둘레 %.1f°(피벗 = 원점 그대로)" % rad_to_deg(q.get_angle()))
	var r1: Transform3D = gw.transform
	p = giz.handle_point(Giz.H.RX)
	_drag_on(giz, p, func() -> Vector2: return p + giz._tan * 40.0, true)
	q = Quaternion((gw.transform.basis * r1.basis.inverse()).orthonormalized())
	_check(absf(rad_to_deg(q.get_angle()) - 30.0) < 0.1, "Ctrl 고리 = 15° 눈금(27.3° → %.1f°)" % rad_to_deg(q.get_angle()))
	# 중심(Z) — 메시 가운데로 돌리면 원점이 움직인다
	page.set_pivot_mode(false)
	await _frames(1)
	var c0: Transform3D = gw.transform
	var piv: Vector3 = giz.pivot_point()                       # 중심 = 메시 경계 상자 가운데
	var piv_local := pn.global_transform.affine_inverse() * piv
	p = giz.handle_point(Giz.H.RY)
	_drag_on(giz, p, func() -> Vector2: return p + giz._tan * 30.0)
	_check(gw.transform.origin.distance_to(c0.origin) > 0.01 and (pn.global_transform * piv_local).distance_to(piv) < 0.001,
		"중심 모드 회전: 그 중심점은 제자리 · 원점은 %.1f cm 움직임" % (gw.transform.origin.distance_to(c0.origin) * 100.0))
	page.set_pivot_mode(true)

	# 크기 — X 축 끝을 축 길이만큼 = 2배, 가운데 = 전체, 왼손 표지는 크기 없음
	page.set_tool(Giz.Tool.SCALE)
	await _frames(1)
	var s0 := gw.scale
	p = giz.handle_point(Giz.H.SX)
	_check(giz.pick(p) == Giz.H.SX, "R: X 축 끝 = X 크기 손잡이")
	_drag_on(giz, p, func() -> Vector2: return p + giz._sdir[0] * giz._slen[0])
	_check(absf(gw.scale.x / s0.x - 2.0) < 0.05 and absf(gw.scale.y - s0.y) < 0.001 and absf(gw.scale.z - s0.z) < 0.001,
		"X 축 끝을 축 길이만큼 → x 크기 %.2f배 · y · z 그대로" % (gw.scale.x / s0.x))
	var s1 := gw.scale
	p = giz.handle_point(Giz.H.SALL)
	_drag_on(giz, p, p + Vector2(30, -30))
	_check((gw.scale / s1).is_equal_approx(Vector3.ONE * 1.6), "가운데(전체)를 오른쪽 위로 60 px → 전체 %.2f배" % (gw.scale.x / s1.x))
	var mk := DRCharacter3D.find_support(gw)
	page._select_node(page._root.get_path_to(mk))
	await _frames(2)
	_check(giz.target == page._prev_node(mk) and not giz.allow_scale and giz.pick(giz.handle_point(Giz.H.SX)) == Giz.H.NONE and not page._scl[0].editable,
		"왼손 표지를 고르면 크기 손잡이 · 크기 칸 없음")
	page.set_tool(Giz.Tool.MOVE)

	# 눌러서 고르기 — 표지 · 빈 곳(고르기 풀기) · 무기 몸통
	page._select_node(page._root.get_path_to(gw))
	var mk_pv := page._prev_node(mk) as Node3D
	page._on_view_click(page._cam.unproject_position(mk_pv.global_position))
	var picked_marker := page._sel == page._root.get_path_to(mk)
	page._on_view_click(Vector2(3, 3))
	await _frames(1)
	var cleared := page._sel.is_empty() and giz.target == null
	var mid := page._cam.unproject_position(Giz.world_aabb(pn).get_center())
	page._on_view_click(mid)
	_check(picked_marker and cleared and page._sel == page._root.get_path_to(gw), "누르기: 왼손 표지 → 빈 곳(풀기) → 무기 몸통(무기)")
	await _frames(1)
	# 기즈모 층으로 누르기(끌기 없이) — 고르기 풀린 상태에서 표지 자리를 누르면 표지
	page._on_view_click(Vector2(3, 3))
	await _frames(1)
	var mp := page._cam.unproject_position(mk_pv.global_position)
	giz._gui_input(_btn_ev(mp, true))
	giz._gui_input(_btn_ev(mp, false))
	_check(page._sel == page._root.get_path_to(mk), "기즈모 층을 눌렀다 떼면(끌기 없이) 그 자리 노드를 고름")
	page._playing = true


func _dot(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return false
	var m := mi.get_surface_override_material(0) as ShaderMaterial
	return m != null and m.shader != null and m.shader.resource_path.ends_with("dot_char.gdshader")


func _run() -> void:
	if FileAccess.file_exists(CHILD):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHILD))
	var page := DREquipPage.new()
	root.add_child(page)
	page.test_layout(Vector2i(1400, 860))
	await _frames(3)

	print("[1] 페이지 · 유닛 · 소켓 · 미리보기")
	_check(page._units.has(BASE) and page._sel_path == BASE and page._root != null, "유닛 목록 %d개 · 고른 유닛 %s" % [page._units.size(), page._sel_path.get_file()])
	var socks := page._sockets()
	var w := page._weapon_equip()
	var mk := DRCharacter3D.find_support(w) if w != null else null
	_check(socks.size() >= 1 and socks[0].bone_name == "RightHand" and w != null and w.scene_file_path == K98 and mk is DRHandTarget3D,
		"소켓 %s(%s) → %s → 왼손 표지 %s" % [socks[0].name if not socks.is_empty() else "-", socks[0].bone_name if not socks.is_empty() else "-", w.name if w != null else "-", mk.name if mk != null else "-"])
	_check(page._all_items(page._tree.get_root()).size() >= 3, "소켓 나무 %d줄" % page._all_items(page._tree.get_root()).size())
	var pv := page._prev
	_check(pv != null and pv.get_weapon_node() != null and pv.get_weapon_node().scene_file_path == K98 and pv.get_left_arm_ik() != null, "미리보기: 소켓 무기 · 왼팔 IK")
	var dots := 0
	for mi in (pv.get_equipment_meshes() if pv != null else []):
		if _dot(mi):
			dots += 1
	var bullets := pv.get_weapon_node().get_node_or_null("bullets") as Node3D if pv != null else null
	_check(dots >= 3 and bullets != null and not bullets.visible and not pv.get_equipment_meshes().has(bullets), "장비 메시 도트 재질 %d개 · 탄 클립 숨김(재질도 안 입힘)" % dots)
	_check(pv != null and pv.get_skeleton().modifier_callback_mode_process == Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL, "미리보기 사본 수정자 = 자세가 바뀔 때만(MANUAL)")
	page.play_motion("Firing_Rifle")
	await _frames(12)
	_check(page.current_motion() == "Firing_Rifle" and pv.get_ik_weight() > 0.99 and float(page._live.get("dist", 1.0)) < 0.01,
		"Firing_Rifle 재생 · 왼손 IK 비중 %.2f · 미리보기 갱신 때 손바닥 ↔ 표지 %.2f cm" % [pv.get_ik_weight(), float(page._live.get("dist", 1.0)) * 100.0])
	page._update_info()
	print("        정보 줄: ", page._info.text)

	print("[2] 장비 모델 · 무기 기본 자리")
	var models := PackedStringArray()
	for i in page._model_ob.item_count:
		models.append(String(page._model_ob.get_item_metadata(i)))
	_check(models.has(K98) and models.has(MP40) and models.has(DREquipHold.PLACEHOLDER_HELMET), "모델 목록 %d개(%s)" % [models.size(), ", ".join(models)])
	var hk := DREquipHold.read_hold(DREquipHold.asset_for_model(K98))
	var hm := DREquipHold.read_hold(DREquipHold.asset_for_model(MP40))
	_check(not hk.is_empty() and hk.has("support") and String(hk["scene"]) == K98 and not hm.is_empty() and hm.has("support"), "기본 자리: kar98k(%s) · mp40(%s)" % [str(not hk.is_empty()), str(not hm.is_empty())])
	_check(not hk.is_empty() and (hk["weapon"] as Transform3D).is_equal_approx(w.transform), "kar98k 기본 자리 = soldier_base 의 자리")

	print("[3] 동작마다 왼 손바닥 ↔ 표지(8 시점 평균 / 최대 cm, IK 전 → 뒤)")
	var rep := page.measure_all()
	var by := {}
	for r in rep:
		var d: Dictionary = r
		by[String(d["motion"])] = d
		print("        %-30s 비중 %.1f · IK 전 %5.1f / %5.1f → IK 뒤 %4.1f / %4.1f" % [d["motion"], d["weight"], float(d["raw_avg"]) * 100.0, float(d["raw_max"]) * 100.0, float(d["ik_avg"]) * 100.0, float(d["ik_max"]) * 100.0])
	var bad := PackedStringArray()
	for m in RIFLE:
		if not by.has(m) or float((by[m] as Dictionary)["ik_max"]) > 0.01:
			bad.append(m)
	_check(rep.size() >= 20 and bad.is_empty(), "소총 동작 %d개 IK 뒤 최대 1 cm 안%s" % [RIFLE.size(), "" if bad.is_empty() else " — 넘음: " + ", ".join(bad)])
	_check(by.has("Sprint") and float((by["Sprint"] as Dictionary)["weight"]) == 0.0 and by.has("Toss_Grenade") and float((by["Toss_Grenade"] as Dictionary)["weight"]) == 0.0, "맨손 달리기 · 수류탄 = IK 비중 0(왼손 그대로)")
	_check(page._mt.get_root() != null and page._mt.get_root().get_child_count() == rep.size(), "동작 표 %d줄" % (page._mt.get_root().get_child_count() if page._mt.get_root() != null else 0))

	print("[4] 자식 유닛 — 무기 바꾸기 · 헬멧 소켓 · 자리 · 비중 · 저장 · 다시 읽기")
	var f := FileAccess.open(CHILD, FileAccess.WRITE)
	f.store_string("[gd_scene load_steps=2 format=3]\n\n[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1_parent\"]\n\n[node name=\"시험장비\" instance=ExtResource(\"1_parent\")]\n" % BASE)
	f.close()
	page.scan_units()
	page.select_unit(CHILD)
	await _frames(2)
	_check(page._sel_path == CHILD and page._base_paths.has("오른손/kar98k"), "자식 유닛 고름 · 부모에서 온 노드 %d개(오른손/kar98k 포함)" % page._base_paths.size())
	page._select_node(NodePath("오른손"))
	var mp := page.put_model(MP40)
	await _frames(2)
	var k_old := page._root.get_node_or_null("오른손/kar98k") as Node3D
	var mmk := DRCharacter3D.find_support(mp) if mp != null else null
	_check(mp != null and k_old != null and not k_old.visible and mp.visible and mp.transform.is_equal_approx(hm["weapon"]), "mp40 넣음 — 부모 kar98k 는 숨김(지울 수 없음) · 기본 자리 그대로")
	_check(mmk is DRHandTarget3D and (mmk as Node3D).transform.is_equal_approx(hm["support"]) and (mmk as DRHandTarget3D).motion_weights.size() == (hm["motion_weights"] as Dictionary).size(), "mp40 왼손 표지 · 동작별 비중 %d개(기본 자리에서)" % ((mmk as DRHandTarget3D).motion_weights.size() if mmk is DRHandTarget3D else -1))
	_check(page._prev != null and page._prev.get_weapon_node() != null and page._prev.get_weapon_node().scene_file_path == MP40, "미리보기 무기 = mp40")
	var head := page.add_socket("", "Head")
	page._select_node(page._root.get_path_to(head))
	var helmet := page.put_model(DREquipHold.PLACEHOLDER_HELMET)
	_check(head != null and head.name == "머리" and helmet != null and helmet.get_parent() == head, "머리 소켓(Head) + 대용 헬멧")
	page._select_node(page._root.get_path_to(helmet))
	page._pos[1].value = 12.0
	_check(absf(helmet.position.y - 0.12) < 0.0005, "숫자 칸 → 헬멧 위치 y %.3f m" % helmet.position.y)
	page._select_node(page._root.get_path_to(mp))
	page.set_motion_weight("Rifle_Idle", 0.5)
	_check(mmk is DRHandTarget3D and absf(float((mmk as DRHandTarget3D).motion_weights.get("Rifle_Idle", -1.0)) - 0.5) < 0.001, "IK 비중 Rifle_Idle = 0.5(표지 motion_weights)")
	page.save_unit()
	var txt := FileAccess.get_file_as_string(CHILD)
	print("        저장한 자식 씬:\n" + txt.indent("          ").substr(0, 2400))
	_check(txt.contains("instance=ExtResource") and txt.contains("mp40.glb") and txt.contains("visible = false") and txt.contains("bone_name = \"Head\"") and txt.contains("\"Rifle_Idle\": 0.5"),
		"자식 씬 = 부모 상속 + kar98k 숨김 + mp40 · 표지 + 머리 소켓 · 헬멧")
	_check(not txt.contains("outfit_top") and not txt.contains("DR_LeftArmIK"), "안 바꾼 칸 · 내부 IK 노드는 파일에 없음")
	var back := (ResourceLoader.load(CHILD, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN) as Node3D
	var bmp := back.get_node_or_null("오른손/mp40") as Node3D
	var bmk := DRCharacter3D.find_support(bmp) if bmp != null else null
	var bhl := back.get_node_or_null("머리/헬멧_대용") as Node3D
	_check(bmp != null and bmp.transform.is_equal_approx(mp.transform) and bmk != null and bmk.transform.is_equal_approx((mmk as Node3D).transform)
		and bhl != null and absf(bhl.position.y - 0.12) < 0.0005, "다시 읽기: mp40 자리 · 표지 · 헬멧 자리가 같음")
	back.free()

	print("[5] 게임처럼 다시 만들기(에디터 밖 = 게임 길)")
	var g := (ResourceLoader.load(CHILD, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as DRCharacter3D
	root.add_child(g)
	await _frames(2)
	var gs := g.get_node_or_null("오른손")
	var kept := gs.get_node_or_null("kar98k") if gs != null else null
	_check(gs != null and kept == null and g.get_weapon_node() != null and g.get_weapon_node().scene_file_path == MP40, "숨긴 부모 무기는 지워짐 · 무기 = mp40")
	g.get_animation_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	g.play_motion("Firing_Rifle", 0.0)
	var sk := g.get_skeleton()
	var hs := g.get_node("머리") as BoneAttachment3D
	var worst_r := 0.0
	var worst_h := 0.0
	var worst_ik := 0.0
	for i in 6:
		g.step_motion(1.0 / 12.0)
		await process_frame
		var rh := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand"))
		var hd := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))
		worst_r = maxf(worst_r, rh.origin.distance_to((gs as Node3D).global_position))
		worst_h = maxf(worst_h, hd.origin.distance_to(hs.global_position))
		worst_ik = maxf(worst_ik, float(g.support_report().get("ik", 1.0)))
	_check(worst_r < 0.001 and worst_h < 0.001, "소켓이 뼈를 따라감(오른손 %.4f m · 머리 %.4f m 어긋남)" % [worst_r, worst_h])
	_check(worst_ik < 0.01, "mp40 Firing_Rifle 왼 손바닥 ↔ 표지 IK 뒤 최대 %.2f cm" % (worst_ik * 100.0))
	var gd := 0
	var helmet_dot := false
	for mi in g.get_equipment_meshes():
		if _dot(mi):
			gd += 1
			if String(mi.name) == "헬멧_대용":
				helmet_dot = true
	_check(gd >= 2 and helmet_dot, "장비 도트 재질 %d개(헬멧 포함)" % gd)
	_check(sk.modifier_callback_mode_process == Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL, "게임: 수정자 = 자세가 바뀔 때만(MANUAL)")
	g.set_fade(0.0)
	var hidden := not (gs as Node3D).visible and not hs.visible
	g.set_fade(1.0)
	_check(hidden and (gs as Node3D).visible and hs.visible, "set_fade(0) 이면 소켓 장비도 숨김 · 1 이면 다시 보임")

	print("[6] 뼈대 길이 든 사본 — ① ② 미리보기는 조립된 열린 씬을 pack 한다(소켓의 길까지 담김). 그 길이 저장된 씬도 같다")
	var path_in := String((gs as BoneAttachment3D).external_skeleton)
	var pk := PackedScene.new()
	pk.pack(g)
	var c2 := pk.instantiate() as DRCharacter3D
	root.add_child(c2)
	await _frames(2)
	c2.get_animation_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	c2.play_motion("Firing_Rifle", 0.0)
	var sk2 := c2.get_skeleton()
	var s2 := c2.get_node("오른손") as BoneAttachment3D
	var worst2 := 0.0
	for i in 6:
		c2.step_motion(1.0 / 12.0)
		await process_frame
		var rh2 := sk2.global_transform * sk2.get_bone_global_pose(sk2.find_bone("RightHand"))
		worst2 = maxf(worst2, rh2.origin.distance_to(s2.global_position))
	_check(path_in != "" and worst2 < 0.001, "길(%s)이 든 사본도 소켓이 뼈를 따라감(%.4f m 어긋남)" % [path_in, worst2])
	c2.queue_free()
	g.queue_free()

	await _gizmo_checks(page)

	# 치우기
	page._drop_root()
	page.queue_free()
	await _frames(2)
	if FileAccess.file_exists(CHILD):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHILD))
	_check(not FileAccess.file_exists(CHILD), "시험 파일 지움")
	if _fails.is_empty():
		print("EQUIP PAGE SMOKE OK")
	else:
		print("EQUIP PAGE SMOKE FAIL ", ", ".join(_fails))
	quit(0 if _fails.is_empty() else 1)
