extends SceneTree

## ① 유닛 탭(DRUnitPage) 검사(10-16) — 창 없이(--headless): 유닛 목록 · 고르기 · 미리보기 조립 · 상태 틀기 · 칸 바꾸기 ·
## 새 자식 유닛(상속 — 바꾼 칸만 파일에 남는가) · 이 유닛만의 동작 표. 에디터 밖이라 되돌리기 없이 인스턴스를 바로 고치는 길을 탄다
## (에디터 안 길 = 열린 씬 · 되돌리기는 pipeline/check_editor.py). 시험으로 만든 파일은 끝에 지운다.
##   Godot --headless --path <프로젝트> --script res://addons/dot_rigger/tools/unit_page_smoke_cli.gd
## 마지막 줄이 "UNIT PAGE SMOKE OK" 면 통과.

const BASE := "res://game/units/soldier_base.tscn"
const CHILD_NAME := "시험유닛_삭제"

var _fails := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["OK  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## 미리보기 속 그 뼈(마디 가운데)의 캔버스 점
func _bone_canvas(page: DRUnitPage, a: String, b: String = "") -> Vector2:
	var sk := page._prev_ch.get_skeleton()
	var pa := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(a)).origin
	if b != "":
		pa = (pa + sk.global_transform * sk.get_bone_global_pose(sk.find_bone(b)).origin) * 0.5
	return page._dots.world_to_canvas(pa)


## [6] 피격 반응(10-21) — 칸 = 유닛 값 · 칸 → 루트 · 미리보기 · 맞혀 보기(부위 · IK 피격 · 확률 100 / 0 % · 자세별 피격 동작 · 끝나면 원래 상태) · IK 끔 · 빗나감
func _hit_checks(page: DRUnitPage) -> void:
	print("[6] 피격 반응 — 칸 · 맞혀 보기(부위 · IK 피격 · 확률 · 자세별 피격 동작)")
	page.select_unit(BASE)
	await _frames(10)
	var r0 := page._root
	var ch := page._prev_ch
	_check((page._hit_sp["hit_anim_chance"] as SpinBox).value == r0.hit_anim_chance * 100.0 and page._hit_ik_chk.button_pressed == r0.hit_ik_enabled
		and absf((page._hit_sp["hit_ik_deg"] as SpinBox).value - r0.hit_ik_deg) < 0.01,
		"칸 = 유닛 값(피격 동작 확률 %d %% · 최대 %.2f 초 · IK %s · 세기 %.0f° · 길이 %.2f 초)" % [roundi(r0.hit_anim_chance * 100.0), r0.hit_anim_max_sec,
		"켬" if r0.hit_ik_enabled else "끔", r0.hit_ik_deg, r0.hit_ik_sec])
	var chance0 := r0.hit_anim_chance
	(page._hit_sp["hit_anim_chance"] as SpinBox).value = 100.0
	_check(absf(r0.hit_anim_chance - 1.0) < 0.001 and absf(ch.hit_anim_chance - 1.0) < 0.001 and page._prev_ch == ch, "확률 칸 100 % → 유닛 1.0 · 미리보기 사본(다시 조립 안 함)")
	page._hit_btn.button_pressed = true
	page.play_state("서기")
	await _frames(3)
	var r1 := page.hit_test(_bone_canvas(page, "UpperChest"))
	_check(String(r1.get("part", "")) == "가슴" and String(r1.get("anim", "")) == "Idle_Hit" and ch.hit_count() >= 1 and ch.current_motion() == "Idle_Hit"
		and page._pv_hit_left > 0.0 and not page._hit_mark.is_empty(),
		"서기 · 가슴을 누름 → 부위 가슴 · IK 피격 · 피격 동작 %s(%.2f 초) · 표시「%s」" % [r1.get("anim", "-"), page._pv_hit_left, page._now.text.left(50)])
	for i in 8:
		page._process(0.2)
	_check(ch.current_motion() == "Rifle_Idle" and page._pv_hit_left == 0.0, "최대 %.2f 초 뒤 원래 상태(서기 — %s)" % [r0.hit_anim_max_sec, ch.current_motion()])
	(page._hit_sp["hit_anim_chance"] as SpinBox).value = 0.0
	var n0 := ch.hit_count()
	var r2 := page.hit_test(_bone_canvas(page, "Head"))
	_check(String(r2.get("part", "")) == "머리" and not bool(r2.get("rolled", true)) and ch.current_motion() == "Rifle_Idle" and ch.hit_count() > n0,
		"확률 0 %% · 머리를 누름 → IK 피격만 · 하던 동작 그대로(%s)" % ch.current_motion())
	page._hit_ik_chk.button_pressed = false
	for i in 8:
		page._process(0.2)
	var n1 := ch.hit_count()
	var r3 := page.hit_test(_bone_canvas(page, "LeftUpperArm", "LeftLowerArm"))
	_check(not r0.hit_ik_enabled and not ch.hit_ik_enabled and String(r3.get("part", "")) == "왼팔" and ch.hit_count() == n1 and not (page._hit_sp["hit_ik_deg"] as SpinBox).editable,
		"IK 피격 끔 → 부위(%s)만 · 반응 없음 · 세기 · 길이 칸 잠김" % r3.get("part", "-"))
	page._hit_ik_chk.button_pressed = true
	(page._hit_sp["hit_anim_chance"] as SpinBox).value = 100.0
	var stance_anims := {}
	for st in [["앉기", "Crouch_Hit"], ["엎드림", "Rifle_Prone_Hit_Reaction"]]:
		page.play_state(String(st[0]))
		await _frames(3)
		var rr := page.hit_test(_bone_canvas(page, "Chest"))
		stance_anims[st[0]] = rr.get("anim", "")
		for i in 8:
			page._process(0.2)
	_check(stance_anims.get("앉기") == "Crouch_Hit" and stance_anims.get("엎드림") == "Rifle_Prone_Hit_Reaction",
		"자세별 피격 동작: 앉기 → %s · 엎드림 → %s" % [stance_anims.get("앉기", "-"), stance_anims.get("엎드림", "-")])
	var rm := page.hit_test(Vector2(5.0, 5.0))
	_check(rm.is_empty() and page._now.text.contains("안 맞음"), "몸 밖을 누름 → 안 맞음 안내")
	(page._hit_sp["hit_anim_chance"] as SpinBox).value = chance0 * 100.0
	page._hit_btn.button_pressed = false
	_check(absf(r0.hit_anim_chance - chance0) < 0.001, "확률 되돌림 %d %%" % roundi(chance0 * 100.0))


func _run() -> void:
	var page := DRUnitPage.new()
	root.add_child(page)
	page.test_layout(Vector2i(1400, 860))
	await _frames(3)

	print("[1] 목록 · 고르기 · 미리보기")
	_check(page._units.has(BASE), "유닛 목록에 기본형 군인(%d개)" % page._units.size())
	_check(page._sel_path == BASE and page._root != null, "처음 고른 유닛 %s" % page._sel_path.get_file())
	var ch := page._prev_ch
	_check(ch != null and ch.worn("top") != "" and ch.worn("bottom") != "", "미리보기 조립(군복 상의 · 하의)")
	var w := ch.get_weapon_node() if ch != null else null
	_check(w != null and w.get_parent() is BoneAttachment3D and ch.get_support_marker() != null and ch.get_left_arm_ik() != null,
		"미리보기 무기 = 유닛의 소켓 장비(%s · 왼손 표지 · 왼팔 IK)" % (String(w.name) if w != null else "-"))
	_check(page._equip_lbl.text.contains("RightHand") and page._equip_lbl.text.contains("왼손 표지"), "장비 요약: %s" % page._equip_lbl.text.replace("\n", " / "))
	_check(page._motion_ed.table == page._root.motions and page._state_ob.item_count > 0, "동작 표 붙음 · 상태 목록 %d칸" % page._state_ob.item_count)
	page.play_state("서기")
	_check(ch != null and ch.current_motion() == "Rifle_Idle", "상태 서기 → %s" % (ch.current_motion() if ch != null else "?"))
	page.play_state("앉기+사격")
	_check(ch != null and ch.current_motion() == "Crouch_Idle+Firing_Rifle", "상태 앉기+사격 → 상하체 합성 %s" % (ch.current_motion() if ch != null else "?"))
	var before := ch.get_animation_player().current_animation_position if ch != null else 0.0
	await _frames(20)
	_check(ch != null and ch.get_animation_player().current_animation_position != before, "미리보기가 재생됨(초당 12번)")

	print("[2] 칸 바꾸기(키) — 미리보기를 다시 조립")
	var old_h := page._root.height_m
	page._set_prop("height_m", 1.6)
	_check(absf(page._root.height_m - 1.6) < 0.001 and page._prev_ch != ch and absf(page._prev_ch.height_m - 1.6) < 0.001, "키 1.6 → 루트 · 미리보기")
	page._set_prop("height_m", old_h)

	print("[3] 새 자식 유닛(상속)")
	var cpath := page.new_child_unit(CHILD_NAME)
	_check(cpath != "" and FileAccess.file_exists(cpath), "파일 %s" % cpath.get_file())
	_check(page._sel_path == cpath and String((page._units.get(cpath, {}) as Dictionary).get("parent", "")) == BASE, "자식 고름 · 부모 = 기본형 군인")
	_check(not page._parent_vals.is_empty() and page._root.outfit_top == page._parent_vals["outfit_top"], "칸이 부모 값을 따라감(상의 %s)" % page._root.outfit_top.get_base_dir().get_file())
	var cw := page._prev_ch.get_weapon_node() if page._prev_ch != null else null
	_check(cw != null and cw.get_parent() is BoneAttachment3D and page._prev_ch.get_left_arm_ik() != null, "부모의 소켓 장비도 따라옴(%s · 왼팔 IK)" % (String(cw.name) if cw != null else "-"))
	var marks := PackedStringArray()
	for f in DRUnitPage.FIELDS:
		marks.append("%s=%s" % [f[1], (page._fields[f[0]]["mark"] as Label).text])
	print("        표시: ", ", ".join(marks))
	_check((page._fields["outfit_top"]["mark"] as Label).text == "부모 값", "상의 칸 표시 = 부모 값")
	page._set_prop("outfit_top", "")
	_check((page._fields["outfit_top"]["mark"] as Label).text == "바꿈" and (page._fields["outfit_top"]["revert"] as Button).visible and page._prev_ch.worn("top") == "",
		"상의를 (내복)으로 바꾸면 표시 = 바꿈 · 보임 · 미리보기 상의 벗음")
	page._on_save()
	var txt := FileAccess.get_file_as_string(cpath)
	print("        저장한 자식 씬:\n" + txt.indent("          "))
	_check(txt.contains("instance=ExtResource") and txt.contains("outfit_top = \"\""), "자식 씬 = 부모 상속 + 바꾼 상의만")
	_check(not txt.contains("outfit_bottom") and not txt.contains("body_model") and not txt.contains("kar98k"), "안 바꾼 칸(하의 · 몸) · 부모 장비는 파일에 없음 — 부모를 따라감")

	print("[4] 이 유닛만의 동작 표")
	page._on_own_table()
	var tpath := "res://game/units/%s_motions.tres" % cpath.get_file().get_basename()
	_check(FileAccess.file_exists(tpath) and page._root.motions != null and page._root.motions.resource_path == tpath, "표 복사 → %s" % tpath.get_file())
	_check(page._root.motions.library_path.ends_with("%s_anims.res" % cpath.get_file().get_basename()) and page._root.motions.clips.size() > 20, "3D 동작 묶음 경로도 따로 · 줄 %d" % page._root.motions.clips.size())
	page._on_save()
	_check(FileAccess.get_file_as_string(cpath).contains(tpath), "자식 씬이 자기 표를 가리킴")

	print("[5] 도트 느낌(외곽선 · 픽셀 퍼펙트 · 명암 — 게임과 같은 파일)")
	var st := page._style
	_check(st != null and page._dots.outline_style == st.outline_style and page._dots.dot_px == st.dot_px, "처음 값이 미리보기 도트 창에(선 방식 %d · 도트 %d px)" % [page._dots.outline_style, page._dots.dot_px])
	var old_style := st.outline_style
	var old_bands := st.light_bands
	st.outline_style = 0
	st.light_bands = 5
	st.dot_px = 3
	page._apply_style()
	_check(page._dots.outline_style == 0 and page._dots.dot_px == 3 and int(DRCharacter3D.get_shading()["bands"]) == 5 and page._dot_ob.get_selected_id() == 3,
		"바꾸면 바로: 카툰 · 도트 3 px · 명암 5단(공유 재질) · 도트 칸")
	st.outline_style = old_style
	st.light_bands = old_bands
	st.dot_px = 2
	page._apply_style()

	await _hit_checks(page)

	# 치우기(시험 파일)
	page._drop_root()
	page.queue_free()
	await _frames(2)
	for p in [cpath, tpath]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	_check(not FileAccess.file_exists(cpath) and not FileAccess.file_exists(tpath), "시험 파일 지움")
	if _fails.is_empty():
		print("UNIT PAGE SMOKE OK")
	else:
		print("UNIT PAGE SMOKE FAIL ", ", ".join(_fails))
	quit(0 if _fails.is_empty() else 1)
