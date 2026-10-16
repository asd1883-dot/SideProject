extends SceneTree

## 동작 표 검사(10-16) — 창 없이: 예전 표 옮기기 · 비중대로 고르기 · % 맞추기 · 인스펙터 편집 화면(되돌리기 없이 바로 고치는 길).
##   Godot --headless --path <프로젝트> --script res://game/tools/motion_table_smoke.gd
## 마지막 줄이 "MOTION TABLE SMOKE OK" 면 통과.

const TABLE_PATH := "res://game/units/rifleman_motions.tres"

var _fails := PackedStringArray()


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails.append(what)
		print("  ✗ ", what)


func _run() -> void:
	# 1) 지금 표(예전 형식이어도 불러오면 줄로 옮겨진다)
	var t := load(TABLE_PATH) as MotionTable
	_check(t != null, "표를 못 읽음")
	if t == null:
		_finish()
		return
	var states := {}
	for c in t.clips:
		states[c.state] = true
	print("표  줄 %d · 상태 %d · 합성 %d · 동작 이름 %d · library_path %s" % [t.clips.size(), states.size(), t.composite_defs().size(),
		t.motion_names().size(), t.library_path])
	_check(t.clips.size() >= 20, "줄이 너무 적음(%d)" % t.clips.size())
	_check(t.composite_defs().size() >= 1, "상하체 합성 줄이 없음")

	# 2) % 맞추기
	var w := DRMotionTable.rebalance(PackedFloat32Array([100.0 / 3.0, 100.0 / 3.0, 100.0 / 3.0]), 0, 20.0)
	print("맞추기  33 · 33 · 33 → 첫 줄 20 = %s" % str(w))
	_check(absf(w[0] - 20.0) < 0.01 and absf(w[1] - 40.0) < 0.01 and absf(w[2] - 40.0) < 0.01, "rebalance 20 · 40 · 40 아님")
	var w2 := DRMotionTable.with_added(PackedFloat32Array([20.0, 40.0, 40.0]))
	print("        20 · 40 · 40 + 새 줄 = %s" % str(w2))
	_check(absf(w2[3] - 25.0) < 0.01 and absf(w2[0] - 15.0) < 0.01, "with_added 15 · 30 · 30 · 25 아님")
	var w3 := DRMotionTable.without(PackedFloat32Array([20.0, 40.0, 40.0]), 0)
	print("        20 · 40 · 40 에서 첫 줄 빼기 = %s" % str(w3))
	_check(absf(w3[0] - 50.0) < 0.01, "without 50 · 50 아님")

	# 3) 비중대로 고르기 — 피격에 hit_1 · hit_2 · hit_3 = 20 · 40 · 40
	var mt := MotionTable.new()
	for p in [["Hit_Chest", 20.0], ["Hit_Head", 40.0], ["Hit_Stomach", 40.0]]:
		var c := DRMotionClip.new()
		c.state = "피격"
		c.anim = String(p[0])
		c.weight = float(p[1])
		mt.clips.append(c)
	mt.emit_changed()
	var avail := PackedStringArray(["Hit_Chest", "Hit_Head", "Hit_Stomach"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 1941
	var count := {}
	var n := 20000
	for i in n:
		var m := mt.pick(PackedStringArray(["피격", "서기"]), avail, rng)
		count[m] = int(count.get(m, 0)) + 1
	var f1 := float(count.get("Hit_Chest", 0)) / n
	var f2 := float(count.get("Hit_Head", 0)) / n
	var f3 := float(count.get("Hit_Stomach", 0)) / n
	print("고르기  %d번: Hit_Chest %.3f · Hit_Head %.3f · Hit_Stomach %.3f (목표 0.2 · 0.4 · 0.4)" % [n, f1, f2, f3])
	_check(absf(f1 - 0.2) < 0.015 and absf(f2 - 0.4) < 0.015 and absf(f3 - 0.4) < 0.015, "비중대로 안 나옴")
	# 없는 동작은 빼고 나머지끼리 — Hit_Head 가 없으면 20 : 40 → 1/3 : 2/3
	count = {}
	for i in n:
		var m := mt.pick(PackedStringArray(["피격"]), PackedStringArray(["Hit_Chest", "Hit_Stomach"]), rng)
		count[m] = int(count.get(m, 0)) + 1
	var g1 := float(count.get("Hit_Chest", 0)) / n
	print("        Hit_Head 없을 때: Hit_Chest %.3f (목표 0.333)" % g1)
	_check(absf(g1 - 1.0 / 3.0) < 0.015, "없는 동작을 뺀 비중이 틀림")
	_check(mt.pick(PackedStringArray(["사망"]), avail, rng) == "", "표에 없는 상태에서 뭔가 고름")
	_check(mt.variant_count("피격", avail) == 3 and mt.has_motion("피격", "Hit_Head"), "variant_count · has_motion")

	# 4) 예전 형식(상태 → 이름 하나) 옮기기
	var legacy := MotionTable.new()
	legacy.motions = {"서기": "Rifle_Idle", "앉기+사격": "Crouch_Idle+Firing_Rifle"}
	var lc := legacy.clips_of("앉기+사격")
	print("옮기기  예전 2줄 → 줄 %d · 앉기+사격 = 합성 %s (하체 %s · 상체 %s · 이름 %s)" % [legacy.clips.size(),
		str(lc.size() == 1 and lc[0].is_composite()), lc[0].lower if lc.size() > 0 else "", lc[0].upper if lc.size() > 0 else "",
		lc[0].play_name() if lc.size() > 0 else ""])
	_check(legacy.clips.size() == 2 and lc.size() == 1 and lc[0].play_name() == "Crouch_Idle+Firing_Rifle", "예전 표 옮기기")
	_check(legacy.motions.is_empty(), "옮긴 뒤 예전 칸이 안 비워짐")

	# 5) 저장 → 다시 읽기(줄 · 비중 · 합성이 그대로)
	var tmp := "user://_motion_table_smoke.tres"
	var e := ResourceSaver.save(mt, tmp)
	var back := ResourceLoader.load(tmp, "", ResourceLoader.CACHE_MODE_IGNORE) as MotionTable
	_check(e == OK and back != null and back.clips.size() == 3 and absf(back.clips[0].weight - 20.0) < 0.001, "저장 · 다시 읽기")

	# 6) 인스펙터 편집 화면(에디터 밖이라 되돌리기 없이 바로 고친다) — 피격에 줄 더하기 · 비중 · 지우기 · 균등 · 합성
	var ed := DRMotionTableEditor.new()
	ed.table = mt
	root.add_child(ed)
	await process_frame
	ed._add_clip("피격", false)
	print("화면  줄 더하기 → %s" % _ws(mt, "피격"))
	_check(mt.clips_of("피격").size() == 4, "줄 더하기")
	ed._remove_clip(mt.clips.size() - 1)
	ed._equalize("피격")
	print("      지우고 균등 → %s" % _ws(mt, "피격"))
	var first := mt.clips.find(mt.clips_of("피격")[0])
	ed._set_weight("피격", first, 20.0)
	print("      첫 줄 20 → %s" % _ws(mt, "피격"))
	var ws := mt.clips_of("피격")
	_check(absf(ws[0].weight - 20.0) < 0.01 and absf(ws[1].weight - 40.0) < 0.01 and absf(ws[2].weight - 40.0) < 0.01, "화면에서 20 · 40 · 40")
	ed._add_clip("앉기+사격", true)
	var ci := mt.clips.find(mt.clips_of("앉기+사격")[0])
	ed._set_field(ci, "upper", "Firing_Rifle")
	var cc := mt.clips_of("앉기+사격")[0]
	print("      합성 줄 → 하체 %s · 상체 %s → %s" % [cc.lower, cc.upper, cc.play_name()])
	_check(cc.is_composite() and cc.play_name() == "Crouch_Idle+Firing_Rifle", "화면에서 합성 줄")
	await process_frame
	await process_frame
	var rows := ed.find_children("*", "SpinBox", true, false).size()
	print("      화면 다시 그림: 비중 칸 %d개" % rows)
	ed._show_empty.button_pressed = true
	await process_frame
	await process_frame
	var heads := _state_heads(ed)
	print("      빈 상태도 보기: 세트 %d개 · 상태 칸 %d개" % [ed._list.get_child_count(), heads])
	_check(heads >= MotionTable.all_keys().size(), "빈 상태도 보기")

	# 7) 세트 — 기본(자세별 셋이 상태 54개를 한 번씩) · 세트 더하기 · 새 상태 · 옮기기 · 이름 바꾸기 · 지우기
	var ds := MotionTable.new().default_sets()
	var cover := {}
	var dup := 0
	for s in ds:
		for st in s.states:
			dup += 1 if cover.has(st) else 0
			cover[st] = true
	print("세트  기본 %s · 상태 %d개(겹침 %d)" % [", ".join(ds.map(func(s): return "%s %d" % [s.name, s.states.size()])), cover.size(), dup])
	_check(ds.size() == 3 and cover.size() == MotionTable.all_keys().size() and dup == 0, "기본 세트가 상태를 한 번씩 덮지 않음")
	ed._new_set.text = "설치"
	ed._on_add_set()
	ed._add_clip("설치", false, "설치")
	ed._move_state("피격", "앉기")
	print("      세트 더하기 · 새 상태 → %s · 설치 상태의 세트 %s · 피격 → %s" % [str(mt.sets.map(func(s): return s.name)), mt.set_of("설치"), mt.set_of("피격")])
	_check(mt.sets.size() == 4 and mt.set_of("설치") == "설치" and mt.clips_of("설치").size() == 1 and mt.set_of("피격") == "앉기", "세트 더하기 · 새 상태 · 옮기기")
	ed._rename_set("설치", "거치")
	_check(mt.set_of("설치") == "거치", "세트 이름 바꾸기")
	ed._delete_set("거치")
	_check(mt.sets.size() == 3 and mt.set_of("설치") == "" and mt.clips_of("설치").size() == 1, "세트 지우기(상태 · 줄은 남음)")
	print("      이름 바꾸기 · 지우기 → 세트 %s · 설치 상태는 세트 없음(줄 %d)" % [str(mt.sets.map(func(s): return s.name)), mt.clips_of("설치").size()])
	await process_frame
	await process_frame
	var e2 := ResourceSaver.save(mt, tmp)
	var back2 := ResourceLoader.load(tmp, "", ResourceLoader.CACHE_MODE_IGNORE) as MotionTable
	_check(e2 == OK and back2 != null and back2.sets.size() == 3 and back2.set_of("피격") == "앉기", "세트 저장 · 다시 읽기")
	ed.queue_free()
	_finish()


## 화면의 상태 칸 수(접기 단추 "▸ 상태" · "▾ 상태" — 세트 단추는 "세트 ·" 가 든다)
func _state_heads(ed: DRMotionTableEditor) -> int:
	var n := 0
	for b in ed._list.find_children("*", "Button", true, false):
		var t := (b as Button).text
		if (t.begins_with("▸ ") or t.begins_with("▾ ")) and not t.contains("세트 ·"):
			n += 1
	return n


func _ws(t: DRMotionTable, st: String) -> String:
	var out := PackedStringArray()
	for c in t.clips_of(st):
		out.append("%s %.1f" % [c.play_name() if c.play_name() != "" else "(빈)", c.weight])
	return " · ".join(out)


func _finish() -> void:
	if _fails.is_empty():
		print("MOTION TABLE SMOKE OK")
	else:
		print("MOTION TABLE SMOKE FAIL ", ", ".join(_fails))
	quit(0 if _fails.is_empty() else 1)
