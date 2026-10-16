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


func _run() -> void:
	var page := DRUnitPage.new()
	root.add_child(page)
	page.test_layout(Vector2i(1400, 860))
	await _frames(3)

	print("[1] 목록 · 고르기 · 미리보기")
	_check(page._units.has(BASE), "유닛 목록에 기본형 군인(%d개)" % page._units.size())
	_check(page._sel_path == BASE and page._root != null, "처음 고른 유닛 %s" % page._sel_path.get_file())
	var ch := page._prev_ch
	_check(ch != null and ch.get_weapon_node() != null and ch.worn("top") != "" and ch.worn("bottom") != "", "미리보기 조립(군복 상의 · 하의 · 무기)")
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
	_check(not page._parent_vals.is_empty() and page._root.weapon_asset == page._parent_vals["weapon_asset"], "칸이 부모 값을 따라감(무기 %s)" % page._root.weapon_asset.get_base_dir().get_file())
	var marks := PackedStringArray()
	for f in DRUnitPage.FIELDS:
		marks.append("%s=%s" % [f[1], (page._fields[f[0]]["mark"] as Label).text])
	print("        표시: ", ", ".join(marks))
	_check((page._fields["weapon_asset"]["mark"] as Label).text == "부모 값", "무기 칸 표시 = 부모 값")
	var mp40 := "res://source3d/weapons/mp40/asset.json"
	page._set_prop("weapon_asset", mp40)
	_check((page._fields["weapon_asset"]["mark"] as Label).text == "바꿈" and (page._fields["weapon_asset"]["revert"] as Button).visible, "무기를 바꾸면 표시 = 바꿈 · ↺ 보임")
	page._on_save()
	var txt := FileAccess.get_file_as_string(cpath)
	print("        저장한 자식 씬:\n" + txt.indent("          "))
	_check(txt.contains("instance=ExtResource") and txt.contains("weapon_asset = \"%s\"" % mp40), "자식 씬 = 부모 상속 + 바꾼 무기만")
	_check(not txt.contains("outfit_top") and not txt.contains("body_model"), "안 바꾼 칸(상의 · 몸)은 파일에 없음 — 부모를 따라감")

	print("[4] 이 유닛만의 동작 표")
	page._on_own_table()
	var tpath := "res://game/units/%s_motions.tres" % cpath.get_file().get_basename()
	_check(FileAccess.file_exists(tpath) and page._root.motions != null and page._root.motions.resource_path == tpath, "표 복사 → %s" % tpath.get_file())
	_check(page._root.motions.library_path.ends_with("%s_anims.res" % cpath.get_file().get_basename()) and page._root.motions.clips.size() > 20, "3D 동작 묶음 경로도 따로 · 줄 %d" % page._root.motions.clips.size())
	page._on_save()
	_check(FileAccess.get_file_as_string(cpath).contains(tpath), "자식 씬이 자기 표를 가리킴")

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
