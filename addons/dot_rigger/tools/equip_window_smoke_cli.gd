extends SceneTree

## 장비 굽기 창(DREquipWindow) 스모크 — 창을 띄워 불러오기 → 2D 미리보기(앞 조각) → 기즈모 조정 → 세트별 조정 → 3D 보기 → 굽기 → 다시 열기.
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
	_check(win._z_common.get_item_text(win._z_common.selected) == "Torso 바로 앞", "기본 자리 = Torso 바로 앞 (%s)" % win._z_common.get_item_text(win._z_common.selected))
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

	print("[3] 2D 미리보기 · 앞 조각")
	_check(win._last_baked.size() == win._sets.size(), "세트 %d개 임시로 구움" % win._last_baked.size())
	var all_ok := true
	for k in win._last_baked.keys():
		all_ok = all_ok and bool((win._last_baked[k] as Dictionary).get("ok", false))
	_check(all_ok, "전부 ok")
	var aim: Dictionary = win._last_baked.get("Rifle_Aiming_Idle", {})
	var aim_ovs: Array = aim.get("overlays", [])
	var ov_parts := PackedStringArray()
	var ov_px := 0
	for o in aim_ovs:
		ov_parts.append(String((o as Dictionary)["part"]))
		ov_px += int((o as Dictionary)["pixels"])
	_check(aim_ovs.size() > 0 and ov_parts.has("L_Hand"), "조준 자세의 앞 조각에 왼손이 있다(총열을 감싼 손가락): %s · %dpx" % [str(ov_parts), ov_px])
	_check(not ov_parts.has("R_Hand") and not ov_parts.has("Head"), "무기보다 앞 순서인 파트(R_Hand · Head)는 앞 조각을 안 만든다")
	var behind := eb.parts_behind_weapon(win._sets[win._set_index("Rifle_Aiming_Idle")])
	_check(behind.has("L_Hand") and behind.has("Torso") and not behind.has("R_Hand"), "Torso 바로 앞 → 뒤에 그려지는 파트 %d개(L_Hand·Torso 포함, R_Hand 제외)" % behind.size())
	var palm: Vector2 = aim.get("palm_attach", Vector2.ZERO)
	var wrect := Rect2(Vector2(aim["offset"] as Vector2i), Vector2((aim["image"] as Image).get_size()))
	_check(wrect.grow(24.0).has_point(palm), "붙일 손 손바닥 %s 이 무기 그림 %s 안팎에" % [str(palm), str(wrect)])
	var soldier: DRPuppetSet = win._soldier
	_check(soldier != null and soldier.run_in_editor and soldier.get_equipped("weapon") != null, "2D 병사에 장착됨")
	var pup: DRPuppet = soldier.get_puppet()
	var spr: Sprite2D = pup.get_equipped("weapon")
	var torso_art: Sprite2D = pup.get_bone("Torso").get_node("stretch/art")
	_check(spr != null and spr.z_index == torso_art.z_index + pup._z_gap(), "무기 z = Torso 바로 앞 (%d = %d + %d)" % [spr.z_index, torso_art.z_index, pup._z_gap()])
	var ovs_2d: Array = pup.get_equipped_overlays("weapon")
	var ov_ok := ovs_2d.size() == aim_ovs.size()
	for o in ovs_2d:
		var os := o as Sprite2D
		ov_ok = ov_ok and os.z_index == spr.z_index + 1 and os.get_parent().get_parent() is Bone2D
	_check(ov_ok and ovs_2d.size() > 0, "앞 조각 스프라이트 %d개 — 무기 z + 1 · 파트 뼈에 붙음" % ovs_2d.size())
	_check(win._front_status.text.begins_with("앞 조각 — ") and win._front_status.text.contains("L_Hand"), "앞 조각 요약: %s" % win._front_status.text)
	_check(win._gizmo.visible and win._gizmo.pivot != Vector2.ZERO, "기즈모 보임 · 자리 %s" % str(win._gizmo.pivot))
	var piv_vp: Vector2 = win._gizmo.pivot
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
	# 드래그 흉내: 누르고 → 끌고 → 놓기(가운데 점). TextureRect 좌표계는 뷰포트와 다르므로 내부 함수로 직접
	var piv := win._gizmo.pivot
	win._gz_begin("xy", piv)
	var spr_now: Sprite2D = soldier.get_puppet().get_equipped("weapon")
	win._gz_update(piv + Vector2(0, -20) * absf(soldier.scale.x), false)
	_check(win._gz_active == "xy" and spr_now.position != win._gz_spr_pos, "끄는 동안 무기 그림이 바로 움직인다")
	win._gz_end()
	await _wait_idle(win)
	var a3 := (win._last_baked["Rifle_Aiming_Idle"] as Dictionary)["offset"] as Vector2i
	_check(absi(a3.y - a0.y + 20) <= 1 and absi(a3.x - a0.x) <= 1, "위로 20px 끌어 놓으면 무기 그림이 20px 위로 (%s → %s)" % [str(a0), str(a3)])
	win._gz_reset.pressed.emit()
	await _wait_idle(win)

	print("[5] 세트별 조정(이 자세만)")
	var idle_i := win._set_index("Idle")
	win._view_set.select(idle_i)
	win._view_set.item_selected.emit(idle_i)
	await _frames(2)
	_check(win._set_title.text.ends_with("Idle") and win._z_set.selected == 0 and String(soldier.current_set()) == "Idle", "자세를 Idle 로 → 2D 도 Idle · 순서 (공통과 같게)")
	win._gz_set_only.button_pressed = true
	var i0 := (win._last_baked["Idle"] as Dictionary)["offset"] as Vector2i
	var r0 := (win._last_baked["Rifle_Aiming_Idle"] as Dictionary)["offset"] as Vector2i
	win._commit_gizmo(Vector2(0, 12), 0.0)
	await _wait_idle(win)
	var i1 := (win._last_baked["Idle"] as Dictionary)["offset"] as Vector2i
	var r1 := (win._last_baked["Rifle_Aiming_Idle"] as Dictionary)["offset"] as Vector2i
	_check(eb.set_adjust.has("Idle") and eb.adj_pos.is_zero_approx(), "이 자세만 → Idle 조정에만 들어감")
	_check(absi(i1.y - i0.y - 12) <= 1 and r1 == r0, "Idle 무기만 12px 내려감 (%s → %s) · 조준 자세 그대로" % [str(i0), str(i1)])
	var hips_i := -1
	for i in win._z_set.item_count:
		if win._z_set.get_item_text(i) == "Hips 바로 앞":
			hips_i = i
	win._z_set.select(hips_i)
	win._z_set.item_selected.emit(hips_i)
	await _wait_idle(win)
	var a_idle := eb.adjust_of("Idle")
	_check(bool(a_idle["z_override"]) and String(a_idle["z_after_part"]) == "Hips", "Idle 만 기본 자리 Hips 바로 앞")
	var pup_i: DRPuppet = soldier.get_puppet()
	var spr_i: Sprite2D = pup_i.get_equipped("weapon")
	var hips_art: Sprite2D = pup_i.get_bone("Hips").get_node("stretch/art")
	_check(spr_i != null and spr_i.z_index == hips_art.z_index + pup_i._z_gap(), "Idle 의 무기 z = Hips 바로 앞 (%d)" % spr_i.z_index)
	win._pv2_aim.value = 25.0
	await _frames(40)
	_check(soldier.aim_enabled and soldier.get_aim_degrees() < -10.0, "조준 슬라이더 25 → 몸통이 위로 (%.1f°)" % soldier.get_aim_degrees())
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
	_check(sd.size() == win._sets.size() and sd.has("Idle") and String((sd["Idle"] as Dictionary).get("z_after_part", "")) == "Hips", "세트 %d개 · Idle 에 자기 자리(Hips)" % sd.size())
	var aim_json: Dictionary = sd.get("Rifle_Aiming_Idle", {})
	var aim_json_ovs: Array = aim_json.get("overlays", [])
	_check(aim_json_ovs.size() > 0, "조준 자세 앞 조각 %d개가 파일로" % aim_json_ovs.size())
	for o in aim_json_ovs:
		_check(FileAccess.file_exists(OUT.path_join("kar98k_smoke").path_join(String((o as Dictionary)["image"]))), "앞 조각 파일 %s" % String((o as Dictionary)["image"]))
	for k in sd.keys():
		_check(FileAccess.file_exists(OUT.path_join("kar98k_smoke").path_join(String((sd[k] as Dictionary)["image"]))), "%s 그림 파일" % k)
	_check(win._status.text.begins_with("완료") and win._status.text.contains("앞 조각"), "상태: %s" % win._status.text.split("\n")[0])
	var es := DREquipSet.load_json(json)
	var es_aim := es.item_for("Rifle_Aiming_Idle") as DREquipItem
	_check(es != null and es.items.size() == sd.size() and (es.item_for("Idle") as DREquipItem).z_after_part == "Hips"
		and es_aim.z_after_part == "Torso" and es_aim.overlays.size() == aim_json_ovs.size(), "런타임 load_json — 세트별 자리 · 앞 조각까지")

	print("[8] 다시 열기(복원)")
	var win2 := DREquipWindow.new()
	root.add_child(win2)
	win2.popup_centered(Vector2i(1180, 720))
	await process_frame
	win2._preset_edit.text = PRESET
	win2._open_json(json)
	await _wait_idle(win2)
	_check(win2._loaded and win2._weapon_edit.text == WEAPON and win2._id_edit.text == "kar98k_smoke", "열기 → 무기·이름 되돌아옴")
	_check(win2.eb.grip_base.is_equal_approx(eb.grip_base) and win2.eb.grip_frame.is_equal_approx(eb.grip_frame), "그립 같음")
	_check(win2.eb.set_adjust.has("Idle") and String(win2.eb.adjust_of("Idle")["z_after_part"]) == "Hips"
		and Vector3(win2.eb.adjust_of("Idle")["pos"]).is_equal_approx(Vector3(eb.adjust_of("Idle")["pos"])), "Idle 조정·자리 같음")
	_check(win2._out_edit.text == OUT, "출력 폴더 %s" % win2._out_edit.text)
	win2._view_set.select(idle_i)
	win2._view_set.item_selected.emit(idle_i)
	await _frames(1)
	_check(win2._z_set.get_item_text(win2._z_set.selected) == "Hips 바로 앞", "칸에도 되돌아옴")
	win2._set_clear.pressed.emit()
	await _frames(1)
	_check(not win2.eb.set_adjust.has("Idle"), "이 자세 조정 지우기 → 항목 없어짐")
	await _wait_idle(win2)

	win.queue_free()
	win2.queue_free()
	await process_frame
	if _fail > 0:
		printerr("장비 창 스모크 실패 %d건" % _fail)
		quit(1); return
	print("장비 창 스모크 전부 통과")
	quit(0)
