extends SceneTree

## 장비 굽기 창(DREquipWindow) 스모크 — 창을 띄워 불러오기 → 2D 미리보기(총 뒤로 보낼 파트 체크 목록) → 기즈모 조정 → 세트별 조정 → 3D 보기 → 굽기 → 다시 열기.
##
##   godot --path . --resolution 1240x800 --script res://addons/dot_rigger/tools/equip_window_smoke_cli.gd
##
## 필요: res://UAL1_preset.tres · res://puppet/sets.json(세트 3개 이상) · res://source3d/weapons/kar98k/Kar98_obj.obj(Scene 으로 가져온 것)

const PRESET := "res://UAL1_preset.tres"
const SETS := "res://puppet/sets.json"
const WEAPON := "res://source3d/weapons/kar98k/Kar98_obj.obj"
const OUT := "res://puppet_test/equip_bake"

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print("  %s  %s" % ["OK  " if ok else "FAIL", msg])
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _wait_idle(win, cap: int = 1500) -> void:
	var n := 0
	while (win._busy or win._pv2_dirty) and n < cap:
		await process_frame
		n += 1


func _opaque(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				n += 1
	return n


## 눈에 띄게 다른 픽셀 수(채널 차 8/255 초과)
func _img_diff(a: Image, b: Image) -> int:
	var n := 0
	for y in a.get_height():
		for x in a.get_width():
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if maxf(maxf(absf(p.r - q.r), absf(p.g - q.g)), maxf(absf(p.b - q.b), absf(p.a - q.a))) > 8.0 / 255.0:
				n += 1
	return n


func _rm_dir(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	for f in DirAccess.get_files_at(abs_path):
		DirAccess.remove_absolute(abs_path.path_join(f))
	DirAccess.remove_absolute(abs_path)


## 무기 총열이 화면(캔버스, y 아래)에서 향한 각도(도) — apply_set 뒤
func _barrel_screen_deg(eb: DREquipBaker, set_name: String) -> float:
	var w: Node3D = eb.ensure_weapon()
	eb.place_weapon(set_name)
	var cam: Camera3D = eb.baker.camera
	var o := w.global_transform.origin
	var f := w.global_transform.basis * eb.forward
	var p0 := cam.unproject_position(o)
	var p1 := cam.unproject_position(o + f.normalized() * 0.3)
	return rad_to_deg((p1 - p0).angle())


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://puppet_test"))
	_rm_dir(ProjectSettings.globalize_path(OUT.path_join("kar98k_smoke")))
	var win := DREquipWindow.new()
	root.add_child(win)
	win.popup_centered(Vector2i(1180, 720))   # 창(1240x800) 안에 제목줄까지 들어오게 — 문서용 캡처
	await process_frame

	print("[1] 창 구성")
	_check(win._preset_edit.text != "", "프리셋 기본값 %s" % win._preset_edit.text)
	_check(win._bake_btn.disabled and win._view_angle.item_count == 5 and win._forward.item_count == 6, "불러오기 전엔 굽기 잠김 · 각도 5 · 축 6")
	_check(not win._panel3d.visible and win._gz_attach.button_pressed and not win._gz_support.button_pressed, "3D 는 숨김 · 기즈모 기준 = 붙일 손")
	_check(win.size.y <= 820 and win.size.x <= 1260, "창 크기 %s (줄바꿈 라벨이 창을 늘리지 않음)" % str(win.size))

	print("[2] 불러오기")
	win._preset_edit.text = PRESET
	win._sets_edit.text = SETS
	win._weapon_edit.text = WEAPON
	win._id_edit.text = "kar98k_smoke"
	win._out_edit.text = OUT
	win._on_load()
	await _wait_idle(win)
	_check(win._loaded and not win._bake_btn.disabled, "불러옴: %s" % win._load_status.text.split("\n")[0])
	if not win._loaded:
		printerr("불러오기 실패 — 중단"); quit(1); return
	_check(win._sets.size() >= 3, "세트 %d개" % win._sets.size())
	_check(win._node_checks.size() == 6 and win._node_checks.has("trigger"), "무기 파트 6개(체크박스) %s" % str(win._node_checks.keys()))
	_check(win._attach.get_item_text(win._attach.selected) == "R_Hand" and win._support.get_item_text(win._support.selected) == "L_Hand", "붙일 손 R_Hand · 받치는 손 L_Hand")
	_check(win._grip_set_name == "Rifle_Aiming_Idle" and win._view_set.get_item_text(win._view_set.selected) == "Rifle_Aiming_Idle", "자동 그립 기준 = 소총 든 자세 %s" % win._grip_set_name)
	_check(not win.eb.grip_base.is_equal_approx(Transform3D.IDENTITY), "자동 그립 잡힘")
	_check(win.eb.common_rule("L_Hand") == "weapon_front" and win.eb.common_rule("Torso") == "weapon_front" and win.eb.common_rule("R_Hand") == "part_front" and win.eb.common_rule("Head") == "part_front",
		"기본: 몸통까지(뒤 → 앞) 총 뒤 · 오른손·머리는 총 앞 %s" % str(win.eb.part_rules))
	var eb: DREquipBaker = win.eb
	# 손이 잡는 자리 = 방아쇠(실사용과 같게). 경계 상자 어림으로는 총이 왼손보다 앞에 놓여 앞 조각이 안 생길 수 있다
	var trig_i := -1
	for i in win._grip_node.item_count:
		if win._grip_node.get_item_text(i) == "trigger":
			trig_i = i
	win._grip_node.select(trig_i)
	win._grip_node.item_selected.emit(trig_i)
	await _wait_idle(win)
	_check(eb.grip_node == "trigger", "손이 잡는 자리 = trigger")

	print("[3] 2D 미리보기 · 체크 목록")
	_check(win._last_baked.size() == win._sets.size(), "세트 %d개 임시로 구움" % win._last_baked.size())
	var all_ok := true
	for k in win._last_baked.keys():
		all_ok = all_ok and bool((win._last_baked[k] as Dictionary).get("ok", false))
	_check(all_ok, "전부 ok")
	var aim: Dictionary = win._last_baked.get("Rifle_Aiming_Idle", {})
	var kinds := {}
	for o in aim.get("overlays", []):
		kinds[String((o as Dictionary)["part"])] = String((o as Dictionary).get("kind", "part"))
	_check(not kinds.has("L_Hand"), "왼손 = 총 뒤 → 왼손 조각 없음(총이 왼손을 가린다) %s" % str(kinds))
	_check(not kinds.has("R_Hand"), "오른손 = 총 앞 · 순서도 Torso 보다 앞 → 조각 없이 순서대로 가린다 %s" % str(kinds))
	var palm: Vector2 = aim.get("palm_attach", Vector2.ZERO)
	var wrect := Rect2(Vector2(aim["offset"] as Vector2i), Vector2((aim["image"] as Image).get_size()))
	_check(wrect.grow(24.0).has_point(palm), "붙일 손 손바닥 %s 이 무기 그림 %s 안팎에" % [str(palm), str(wrect)])
	var soldier: DRPuppetSet = win._soldier
	_check(soldier != null and soldier.run_in_editor and soldier.get_equipped("weapon") != null, "2D 병사에 장착됨")
	var pup: DRPuppet = soldier.get_puppet()
	var spr: Sprite2D = pup.get_equipped("weapon")
	var torso_z: int = (pup.get_bone("Torso").get_node("stretch/art") as Sprite2D).z_index
	_check(spr != null and spr.z_index == torso_z + pup._z_gap(), "총 자리 = 체크한 파트 중 가장 앞(Torso) 바로 앞 z %d" % (spr.z_index if spr else -1))
	var ovs_2d: Array = pup.get_equipped_overlays("weapon")
	_check(ovs_2d.is_empty(), "기본(몸통까지 총 뒤)은 조각 없이 순서만으로 — 오른팔·머리는 원래 순서대로 총 앞 (조각 %d)" % ovs_2d.size())
	_check(win._rule_rows.size() == 15 and (win._rule_rows["L_Hand"]["behind"] as CheckBox).button_pressed
		and not (win._rule_rows["R_Hand"]["behind"] as CheckBox).button_pressed, "체크 목록 15줄 · 왼손 체크 · 오른손 해제")
	_check((win._rule_rows["L_Hand"]["lbl"] as Label).text.contains("겹침"), "겹치는 파트 표시: %s" % (win._rule_rows["L_Hand"]["lbl"] as Label).text)

	print("[3-0] 모든 자세에 같은 모습")
	_check(eb.consistent_view, "새 장비는 기본으로 켜짐")
	var cv_size := Vector2i.ZERO
	var cv_same := true
	var cv_first: Image = null
	for k in win._last_baked.keys():
		var im: Image = (win._last_baked[k] as Dictionary)["image"]
		if cv_size == Vector2i.ZERO:
			cv_size = im.get_size()
			cv_first = im
		cv_same = cv_same and im.get_size() == cv_size and _img_diff(im, cv_first) == 0
	_check(cv_same, "모든 자세의 총 그림이 픽셀까지 같다 %s" % str(cv_size))
	var ang_sprite := rad_to_deg(pup.get_equipped("weapon").rotation)
	var ang_baked := rad_to_deg(float(aim.get("angle", 0.0)))
	_check(absf(ang_sprite - ang_baked) < 0.01, "게임에서 그림이 자세의 총열 방향으로 돌아 붙음 (%.1f°)" % ang_sprite)
	win._open_view_popup()
	await _frames(2)
	_check(win._view_dlg.visible and win._view_on.button_pressed, "총 보는 각도 팝업이 뜬다")
	win._view_yaw.value = 30.0
	await _frames(2)
	_check(is_equal_approx(eb.view_yaw, 30.0), "팝업에서 틀기 30°")
	win._view_dlg.canceled.emit()
	win._view_dlg.hide()
	await _frames(2)
	_check(is_equal_approx(eb.view_yaw, 0.0), "취소하면 되돌아감")
	win._open_view_popup()
	await _frames(1)
	win._view_yaw.value = 25.0
	win._view_dlg.confirmed.emit()
	win._view_dlg.hide()
	await _wait_idle(win)
	var sz2: Vector2i = ((win._last_baked["Rifle_Aiming_Idle"] as Dictionary)["image"] as Image).get_size()
	_check(is_equal_approx(eb.view_yaw, 25.0) and sz2 != cv_size, "적용하면 모든 자세가 새 각도로 다시 구워짐 (%s → %s)" % [str(cv_size), str(sz2)])
	win._open_view_popup()
	await _frames(1)
	win._view_yaw.value = 0.0
	win._view_dlg.confirmed.emit()
	win._view_dlg.hide()
	await _wait_idle(win)
	aim = win._last_baked["Rifle_Aiming_Idle"]

	print("[3-1] 체크 목록 조작")
	var lh: Dictionary = win._rule_rows["L_Hand"]
	(lh["behind"] as CheckBox).button_pressed = false
	await _wait_idle(win)
	var lh_kind := ""
	for o in (win._last_baked["Rifle_Aiming_Idle"] as Dictionary).get("overlays", []):
		if String((o as Dictionary)["part"]) == "L_Hand":
			lh_kind = String((o as Dictionary)["kind"])
	_check(eb.common_rule("L_Hand") == "part_front" and lh_kind == "raise", "왼손 체크 해제 → 왼손을 통째로 총 위로(%s)" % lh_kind)
	var pup_l: DRPuppet = soldier.get_puppet()
	var lart: Sprite2D = pup_l.get_bone("L_Hand").get_node("stretch/art")
	await _frames(5)
	_check(lart.z_index > pup_l.get_equipped("weapon").z_index, "재생 중에도 왼손 z(%d) > 총 z(%d)" % [lart.z_index, pup_l.get_equipped("weapon").z_index])
	(lh["behind"] as CheckBox).button_pressed = true
	await _wait_idle(win)
	var still := false
	for o in (win._last_baked["Rifle_Aiming_Idle"] as Dictionary).get("overlays", []):
		still = still or String((o as Dictionary)["part"]) == "L_Hand"
	_check(eb.common_rule("L_Hand") == "weapon_front" and not still, "다시 체크 → 총이 왼손을 가림")
	lart = soldier.get_puppet().get_bone("L_Hand").get_node("stretch/art")
	_check(lart.z_index < soldier.get_puppet().get_equipped("weapon").z_index, "왼손 z 원래대로(%d)" % lart.z_index)
	# 숨김 — 이 자세만
	win._rule_set_only.button_pressed = true
	lh = win._rule_rows["L_Hand"]
	(lh["hide"] as CheckBox).button_pressed = true
	await _wait_idle(win)
	_check(eb.rule_for("Rifle_Aiming_Idle", "L_Hand") == "hide" and eb.rule_for("Idle", "L_Hand") == "weapon_front", "이 자세만 숨김 → 조준 자세에만 hide")
	var lh_art: Sprite2D = soldier.get_puppet().get_bone("L_Hand").get_node("stretch/art")
	_check(not lh_art.visible, "조준 자세 퍼펫에서 왼손 그림이 안 그려진다")
	_check((lh["lbl"] as Label).text.ends_with("[이 자세]") and (lh["behind"] as CheckBox).disabled, "칸에 [이 자세] · 숨김이면 총 뒤로 칸 잠김")
	win._rule_reset.pressed.emit()
	await _wait_idle(win)
	_check(lh_art.visible and eb.set_adjust.is_empty(), "이 자세를 공통으로 → 왼손 다시 보이고 자세 규칙 비움")
	win._rule_set_only.button_pressed = false
	# 전부 앞으로 / 전부 뒤로
	var all_front_btn: Button = null
	var all_back_btn: Button = null
	for c in win._rule_reset.get_parent().get_children():
		if c is Button and (c as Button).text == "전부 앞으로":
			all_front_btn = c
		if c is Button and (c as Button).text == "전부 뒤로":
			all_back_btn = c
	all_back_btn.pressed.emit()
	await _wait_idle(win)
	var n_part := 0
	for o in (win._last_baked["Rifle_Aiming_Idle"] as Dictionary).get("overlays", []):
		if String((o as Dictionary).get("kind", "part")) == "part":
			n_part += 1
	_check(n_part == 0 and eb.common_rule("R_Hand") == "weapon_front", "전부 뒤로 → 총 위에 얹히는 조각 없음")
	all_front_btn.pressed.emit()
	await _wait_idle(win)
	_check(eb.part_rules.is_empty(), "전부 앞으로 → 공통 규칙 비움(규칙 없음 = 총 앞)")
	eb.apply_default_behind(win._layer_order(win._sets[win._set_index("Rifle_Aiming_Idle")]), "Torso")
	win._fill_rule_grid()
	win._mark_pv2()
	await _wait_idle(win)
	aim = win._last_baked["Rifle_Aiming_Idle"]
	_check(win._gizmo.visible and win._gizmo.pivot != Vector2.ZERO, "기즈모 보임 · 자리 %s" % str(win._gizmo.pivot))
	var piv_vp: Vector2 = win._gizmo.pivot
	spr = soldier.get_puppet().get_equipped("weapon")   # 다시 구우면 스프라이트가 새로 만들어진다
	_check(piv_vp.distance_to(spr.global_position) < 120.0, "기즈모(붙일 손)가 무기 그림 원점 근처 (%.0f px)" % piv_vp.distance_to(spr.global_position))

	print("[4] 기즈모 조정")
	var a0 := aim["offset"] as Vector2i
	win._commit_gizmo(Vector2(10, 0), 0.0)         # 화면 오른쪽 10 캔버스 px
	await _wait_idle(win)
	var a1 := (win._last_baked["Rifle_Aiming_Idle"] as Dictionary)["offset"] as Vector2i
	_check(absi((a1.x - a0.x) - 10) <= 1 and absi(a1.y - a0.y) <= 1, "오른쪽으로 10px 끌면 무기 그림이 10px 이동 (%s → %s)" % [str(a0), str(a1)])
	_check(not eb.adj_pos.is_zero_approx() and eb.set_adjust.is_empty(), "공통 조정에 들어감(이 자세만 꺼짐) adj_pos %s" % str(eb.adj_pos))
	eb.apply_set(win._sets[win._set_index("Rifle_Aiming_Idle")])
	var deg0 := _barrel_screen_deg(eb, "Rifle_Aiming_Idle")
	var p_before: Vector3 = eb.palm_world("R_Hand")
	var w: Node3D = eb.ensure_weapon()
	var q_local: Vector3 = w.global_transform.affine_inverse() * p_before   # 붙일 손 손바닥 자리의 무기 점
	win._commit_gizmo(Vector2.ZERO, deg_to_rad(15.0))   # 붙일 손 중심으로 15° (화면 시계 방향)
	await _wait_idle(win)
	eb.apply_set(win._sets[win._set_index("Rifle_Aiming_Idle")])
	var deg1 := _barrel_screen_deg(eb, "Rifle_Aiming_Idle")
	_check(absf(wrapf(deg1 - deg0, -180.0, 180.0) - 15.0) < 1.0, "링을 15° 돌리면 화면에서 총열이 15° 돈다 (%.1f° → %.1f°)" % [deg0, deg1])
	var q_after: Vector3 = w.global_transform * q_local
	_check(q_after.distance_to(p_before) < 0.002, "붙일 손 자리는 제자리 (%.4f m)" % q_after.distance_to(p_before))
	# 받치는 손 기준 회전 — 받치는 손 자리가 제자리
	win._gz_support.button_pressed = true
	await _frames(1)
	_check(win._gizmo.label.begins_with("받치는 손") and win._gizmo.pivot.distance_to(piv_vp) > 20.0, "받치는 손 기준으로 바꾸면 기즈모가 왼손으로 (%s)" % win._gizmo.label)
	var ps_before: Vector3 = eb.palm_world("L_Hand")
	var qs_local: Vector3 = w.global_transform.affine_inverse() * ps_before
	win._commit_gizmo(Vector2.ZERO, deg_to_rad(-10.0))
	await _wait_idle(win)
	eb.apply_set(win._sets[win._set_index("Rifle_Aiming_Idle")])
	eb.place_weapon("Rifle_Aiming_Idle")
	_check((w.global_transform * qs_local).distance_to(ps_before) < 0.002, "받치는 손 중심 회전 — 받치는 손 자리 제자리 (%.4f m)" % (w.global_transform * qs_local).distance_to(ps_before))
	var deg2 := _barrel_screen_deg(eb, "Rifle_Aiming_Idle")
	_check(absf(wrapf(deg2 - deg1, -180.0, 180.0) + 10.0) < 1.0, "−10° → 총열 %.1f° → %.1f°" % [deg1, deg2])
	win._gz_attach.button_pressed = true
	win._gz_reset.pressed.emit()
	await _wait_idle(win)
	_check(eb.adj_pos.is_zero_approx() and eb.adj_rot.is_zero_approx(), "조정 리셋 → 공통 0")
	var a2 := (win._last_baked["Rifle_Aiming_Idle"] as Dictionary)["offset"] as Vector2i
	_check(a2 == a0, "리셋 뒤 무기 그림 자리 원래대로 %s" % str(a2))
	# 드래그 흉내 — 재생을 멈추고(같은 프레임에서 비교) 화면에서 끈 만큼 총이 화면에서 움직여야 한다(손이 애니로 돌아가 있어도)
	win._pv2_play.button_pressed = false
	await _frames(2)
	var spr0: Sprite2D = soldier.get_puppet().get_equipped("weapon")
	var c0: Vector2 = spr0.get_global_transform() * (spr0.texture.get_size() * 0.5)
	var ax0: Vector2 = win._gizmo.ax
	var piv := win._gizmo.pivot
	var drag := Vector2(-14, -22)
	win._gz_begin("xy", piv)
	win._gz_update(piv + drag, false)
	_check(win._gz_active == "xy" and spr0.position != win._gz_spr_pos, "끄는 동안 무기 그림이 바로 움직인다")
	win._gz_end()
	await _wait_idle(win)
	await _frames(2)
	var spr1: Sprite2D = soldier.get_puppet().get_equipped("weapon")
	var c1: Vector2 = spr1.get_global_transform() * (spr1.texture.get_size() * 0.5)
	_check((c1 - c0 - drag).length() < 2.5 * absf(soldier.scale.x), "끈 만큼 화면에서 정확히 움직임 (끈 %s · 움직임 %s)" % [str(drag), str(c1 - c0)])
	# 축이 총을 따라 도는가
	win._commit_gizmo(Vector2.ZERO, deg_to_rad(20.0))
	await _wait_idle(win)
	await _frames(2)
	win._gizmo_axes()
	var turn := rad_to_deg(ax0.angle_to(win._gizmo.ax))
	_check(absf(absf(turn) - 20.0) < 2.0, "총을 20° 돌리면 기즈모 축도 20° 돈다 (%.1f°)" % turn)
	# 초기값으로
	var init_btn: Button = win._gz_reset.get_parent().get_node("GizmoInit")
	win._gz_set_only.button_pressed = true
	win._commit_gizmo(Vector2(0, 8), 0.0)
	await _wait_idle(win)
	win._gz_set_only.button_pressed = false
	init_btn.pressed.emit()
	await _wait_idle(win)
	var any_set := false
	for k in eb.set_adjust.keys():
		any_set = any_set or not Vector3(eb.adjust_of(String(k))["pos"]).is_zero_approx() or not Vector3(eb.adjust_of(String(k))["rot"]).is_zero_approx()
	_check(eb.adj_pos.is_zero_approx() and eb.adj_rot.is_zero_approx() and not any_set, "초기값으로 → 공통·자세별 조정 모두 0")
	var a4 := (win._last_baked["Rifle_Aiming_Idle"] as Dictionary)["offset"] as Vector2i
	_check(a4 == a0, "초기값으로 뒤 무기 그림 자리 처음대로 %s" % str(a4))
	win._pv2_play.button_pressed = true
	win._gz_reset.pressed.emit()
	await _wait_idle(win)

	print("[5] 세트별 조정(이 자세만)")
	var idle_i := win._set_index("Idle")
	win._view_set.select(idle_i)
	win._view_set.item_selected.emit(idle_i)
	await _frames(2)
	_check(win._set_title.text.ends_with("Idle") and String(soldier.current_set()) == "Idle", "자세를 Idle 로 → 2D 도 Idle")
	win._gz_set_only.button_pressed = true
	var i0 := (win._last_baked["Idle"] as Dictionary)["offset"] as Vector2i
	var r0 := (win._last_baked["Rifle_Aiming_Idle"] as Dictionary)["offset"] as Vector2i
	win._commit_gizmo(Vector2(0, 12), 0.0)
	await _wait_idle(win)
	var i1 := (win._last_baked["Idle"] as Dictionary)["offset"] as Vector2i
	var r1 := (win._last_baked["Rifle_Aiming_Idle"] as Dictionary)["offset"] as Vector2i
	_check(eb.set_adjust.has("Idle") and eb.adj_pos.is_zero_approx(), "이 자세만 → Idle 조정에만 들어감")
	_check(absi(i1.y - i0.y - 12) <= 1 and r1 == r0, "Idle 무기만 12px 내려감 (%s → %s) · 조준 자세 그대로" % [str(i0), str(i1)])
	win._rule_set_only.button_pressed = true
	var rh: Dictionary = win._rule_rows["R_Hand"]
	(rh["behind"] as CheckBox).button_pressed = true
	await _wait_idle(win)
	_check(eb.rule_for("Idle", "R_Hand") == "weapon_front" and eb.rule_for("Rifle_Aiming_Idle", "R_Hand") == "part_front", "이 자세만(Idle) 오른손 총 뒤 → 조준 자세는 그대로")
	win._rule_set_only.button_pressed = false
	win._pv2_aim.value = 16.0
	await _frames(40)
	_check(soldier.aim_enabled and soldier.get_aim_degrees() < -10.0, "조준 슬라이더 16 → 몸통이 위로 (%.1f°)" % soldier.get_aim_degrees())
	win._pv2_aim.value = 0.0
	var rifle_i := win._set_index("Rifle_Aiming_Idle")
	win._view_set.select(rifle_i)
	win._view_set.item_selected.emit(rifle_i)
	await _frames(3)
	await RenderingServer.frame_post_draw
	win._vp2.get_texture().get_image().save_png("res://puppet_test/_equipwin_2d.png")
	root.get_texture().get_image().save_png("res://puppet_test/_equipwin_layout.png")   # 창 전체(문서용)

	print("[6] 3D 보기(켜면)")
	win._show3d.button_pressed = true
	await _frames(3)
	await RenderingServer.frame_post_draw
	var vp: SubViewport = win.baker.viewport
	_check(win._panel3d.visible and win._pv3.texture == vp.get_texture(), "3D 칸이 베이커 뷰포트를 보여 줌")
	var full := _opaque(vp.get_texture().get_image())
	win._show_char.button_pressed = false
	await _frames(3)
	await RenderingServer.frame_post_draw
	var only_w := _opaque(vp.get_texture().get_image())
	_check(full > only_w and only_w > 50, "캐릭터 끄면 무기만: %d → %d px" % [full, only_w])
	win._show_char.button_pressed = true
	var ortho: float = eb._cur_ortho
	win._view_zoom.value = 3.0
	await _frames(1)
	_check(is_equal_approx(win.baker.camera.size, ortho / 3.0), "확대 ×3 → 카메라 크기 %.3f (굽는 크기 %.3f)" % [win.baker.camera.size, ortho])
	win._view_zoom.value = 1.0
	win._show3d.button_pressed = false
	await _frames(1)
	_check(not win._panel3d.visible and is_equal_approx(win.baker.camera.size, ortho), "3D 를 끄면 굽는 카메라 그대로")

	print("[7] 굽기")
	win._on_bake()
	await _wait_idle(win)
	var json := OUT.path_join("kar98k_smoke/equip.json")
	_check(FileAccess.file_exists(json), "equip.json 생김 %s" % json)
	var d := DREquipBaker._read_json(json)
	_check(int(d.get("version", 0)) == 2 and d.has("grip_base") and d.has("grip_frame") and d.has("set_adjust") and bool(d.get("front_pieces", false)), "본문에 그립·조정·앞 조각 설정 저장")
	var sd: Dictionary = d.get("sets", {})
	_check(sd.size() == win._sets.size() and bool(d.get("list_mode", false)) and String((((d["set_adjust"] as Dictionary).get("Idle", {}) as Dictionary).get("rules", {}) as Dictionary).get("R_Hand", "")) == "weapon_front",
		"세트 %d개 · 목록 방식 · Idle 자세 규칙 저장" % sd.size())
	var aim_json: Dictionary = sd.get("Rifle_Aiming_Idle", {})
	var aim_json_ovs: Array = aim_json.get("overlays", [])
	_check(aim_json_ovs.is_empty(), "기본(몸통까지 총 뒤)은 조각 파일 없음 — 순서만으로 (%d)" % aim_json_ovs.size())
	for o in aim_json_ovs:
		_check(FileAccess.file_exists(OUT.path_join("kar98k_smoke").path_join(String((o as Dictionary)["image"]))), "앞 조각 파일 %s" % String((o as Dictionary)["image"]))
	for k in sd.keys():
		_check(FileAccess.file_exists(OUT.path_join("kar98k_smoke").path_join(String((sd[k] as Dictionary)["image"]))), "%s 그림 파일" % k)
	_check(win._status.text.begins_with("완료"), "상태: %s" % win._status.text.split("\n")[0])
	var es := DREquipSet.load_json(json)
	var es_aim := es.item_for("Rifle_Aiming_Idle") as DREquipItem
	_check(es != null and es.items.size() == sd.size() and es_aim.z_after_part == "Torso"
		and es_aim.overlays.size() == aim_json_ovs.size(), "런타임 load_json — 총 맨 앞 · 조각까지")

	print("[8] 다시 열기(복원)")
	_check(String((d.get("part_rules", {}) as Dictionary).get("L_Hand", "")) == "weapon_front", "공통 규칙이 equip.json 에 저장")
	var win2 := DREquipWindow.new()
	root.add_child(win2)
	win2.popup_centered(Vector2i(1180, 720))
	await process_frame
	win2._preset_edit.text = PRESET
	win2._open_json(json)
	await _wait_idle(win2)
	_check(win2._loaded and win2._weapon_edit.text == WEAPON and win2._id_edit.text == "kar98k_smoke", "열기 → 무기·이름 되돌아옴")
	_check(win2.eb.grip_base.is_equal_approx(eb.grip_base) and win2.eb.grip_frame.is_equal_approx(eb.grip_frame), "그립 같음")
	_check(win2.eb.set_adjust.has("Idle") and win2.eb.rule_for("Idle", "R_Hand") == "weapon_front"
		and Vector3(win2.eb.adjust_of("Idle")["pos"]).is_equal_approx(Vector3(eb.adjust_of("Idle")["pos"])), "Idle 조정·자세 규칙 같음")
	_check(win2._out_edit.text == OUT, "출력 폴더 %s" % win2._out_edit.text)
	_check(win2.eb.common_rule("L_Hand") == "weapon_front" and (win2._rule_rows["L_Hand"]["behind"] as CheckBox).button_pressed, "규칙도 되돌아옴(체크까지)")
	win2._view_set.select(idle_i)
	win2._view_set.item_selected.emit(idle_i)
	await _frames(1)
	win2._rule_set_only.button_pressed = true
	await _frames(1)
	_check((win2._rule_rows["R_Hand"]["behind"] as CheckBox).button_pressed, "Idle 에서 이 자세만 → 오른손 체크 되돌아옴")
	win2._set_clear.pressed.emit()
	win2._rule_reset.pressed.emit()
	await _frames(1)
	_check(not win2.eb.set_adjust.has("Idle"), "조정·규칙 지우기 → 항목 없어짐")
	await _wait_idle(win2)

	win.queue_free()
	win2.queue_free()
	await process_frame
	if _fail > 0:
		printerr("장비 창 스모크 실패 %d건" % _fail)
		quit(1); return
	print("장비 창 스모크 전부 통과")
	quit(0)
