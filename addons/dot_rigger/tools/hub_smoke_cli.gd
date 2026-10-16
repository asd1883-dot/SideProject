extends SceneTree

## Dot Rigger 창(DRHubWindow, 탭 페이지) 스모크 — 창을 띄워
##  [1] 탭 3개 · 공통 설정 줄(프리셋 · 세트 목록이 자동으로 잡힘 — ② ③ 이 쓴다)
##  [2] ① 유닛 탭(10-16, 3D): 처음 열면 유닛 목록에 기본형 군인이 고르고 미리보기 캐릭터가 조립되고 동작 표가 붙는다
##  [3] ③ 복장 탭: 프리셋 · 세트 칸은 숨고 공통 설정 값을 쓴다 · 안 보이는 탭의 미리보기는 멈춘다
##  [4] Ctrl+1 · 2 · 3 으로 탭 바꾸기 · 페이지는 한 번 만들면 그대로(작업 유지)
##  [5] 한 탭이 "세트를 다시 구웠다"고 알리면 복장 탭이 다음에 보일 때 알아서 다시 불러온다
##
##   godot --path . --resolution 1500x920 --script res://addons/dot_rigger/tools/hub_smoke_cli.gd -- \
##       --model=res://source3d/characters/uniform_m36/uniform_m36.glb
## 필요: res://human.tres(기본 몸 프리셋) · 그 출력 폴더의 sets.json · 뼈대에 붙인 옷 모델 · game/units/soldier_base.tscn

var _fail := 0
var _args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			s = s.substr(2)
		var eq := s.find("=")
		if eq >= 0:
			_args[s.substr(0, eq)] = s.substr(eq + 1)
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print("  %s  %s" % ["OK  " if ok else "FAIL", msg])
	if not ok:
		_fail += 1


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.ctrl_pressed = true
	return ev


func _wait(cond: Callable, cap: int = 3000) -> void:
	var n := 0
	while not bool(cond.call()) and n < cap:
		await process_frame
		n += 1


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://puppet_test"))
	var hub := DRHubWindow.new()
	root.add_child(hub)
	var shown_early := hub.visible     # 넣기만 해서 뜨면 안 된다(10-06: 그래서 다른 모니터 구석에 떴다)
	hub.open()
	await process_frame
	_check(not shown_early and hub.visible, "넣기만 해서는 안 뜨고 open() 이 띄운다")

	print("[1] 탭 · 공통 설정")
	_check(hub._buttons.size() == 3 and hub._current == "unit" and hub._pages.size() == 1, "탭 3개 · 처음 = ① 유닛 · 만든 페이지 1개(나머지는 누를 때)")
	var ctx: Dictionary = hub.get_context()
	_check(FileAccess.file_exists(String(ctx["preset"])) and FileAccess.file_exists(String(ctx["sets"])), "공통 설정 자동: 프리셋 %s · 세트 %s" % [ctx["preset"], ctx["sets"]])

	print("[2] ① 유닛 탭 — 기본형 군인 · 미리보기 · 동작 표")
	var unit: DRUnitPage = hub.page("unit")
	await _wait(func(): return unit._prev_ch != null)
	_check(unit._units.has("res://game/units/soldier_base.tscn"), "유닛 목록에 기본형 군인(%d개)" % unit._units.size())
	_check(unit._root != null and unit._sel_path.ends_with("soldier_base.tscn"), "처음 고른 유닛: %s" % unit._sel_path.get_file())
	_check(unit._prev_ch != null and unit._prev_ch.get_weapon_node() != null and unit._prev_ch.worn("top") != "", "미리보기 캐릭터 조립(군복 · 무기)")
	_check(unit._motion_ed.table == unit._root.motions and unit._state_ob.item_count > 0, "동작 표 붙음 · 상태 목록 %d" % unit._state_ob.item_count)
	_check(unit.hosted and hub.title.contains("유닛"), "창 제목: %s" % hub.title)
	for i in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	hub.get_texture().get_image().save_png("res://puppet_test/_hub_unit.png")

	print("[3] ③ 복장 탭")
	hub.open_page("outfit")
	await process_frame
	var outfit: DROutfitWindow = hub.page("outfit")
	_check(outfit != null and outfit.is_visible_in_tree() and not unit.is_visible_in_tree(), "복장 탭이 보이고 유닛 탭은 숨음")
	_check(not outfit._preset_edit.get_parent().visible and not outfit._sets_edit.get_parent().visible, "복장 탭의 프리셋 · 세트 칸은 숨김(공통 설정이 대신)")
	_check(outfit._preset_edit.text == String(ctx["preset"]) and outfit._sets_edit.text == String(ctx["sets"]), "복장 탭이 공통 설정 값을 씀")
	_check(unit._pv_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "안 보이는 유닛 탭의 미리보기 멈춤")
	outfit._model_edit.text = String(_args.get("model", "res://source3d/characters/uniform_m36/uniform_m36.glb"))
	outfit._on_load()
	await _wait(func(): return outfit._loaded and not outfit._busy and not outfit._pv_dirty)
	_check(outfit._loaded, "옷 모델 불러옴: %s" % outfit._load_status.text.split("\n")[0])
	await process_frame
	await RenderingServer.frame_post_draw
	hub.get_texture().get_image().save_png("res://puppet_test/_hub_outfit.png")

	print("[4] Ctrl+숫자 · 작업 유지")
	hub._on_window_input(_key(KEY_1))
	await process_frame
	_check(hub._current == "unit" and unit.is_visible_in_tree() and not outfit.is_visible_in_tree() and unit._pv_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Ctrl+1 → 유닛 탭(미리보기 다시 켜짐)")
	_check(hub.page("unit") == unit and unit._prev_ch != null and outfit._loaded, "탭을 바꿔도 페이지 · 불러온 것 그대로")
	hub._on_window_input(_key(KEY_2))
	await process_frame
	var equip: DREquipWindow = hub.page("equip")
	_check(hub._current == "equip" and equip != null and not equip._preset_edit.get_parent().visible and equip._sets_edit.text == String(ctx["sets"]), "Ctrl+2 → 장비 탭(공통 설정 값 · 칸 숨김)")
	await RenderingServer.frame_post_draw
	hub.get_texture().get_image().save_png("res://puppet_test/_hub_equip.png")

	print("[5] 세트를 다시 구우면 다른 탭이 알아서 따라옴")
	hub._on_window_input(_key(KEY_1))
	await process_frame
	var old_baker = outfit.baker
	unit.context_changed.emit({"sets": String(ctx["sets"]), "rebaked": true})
	_check(outfit._ctx_stale, "복장 탭에 `다시 불러와야 함` 표시(안 보이는 동안은 그대로)")
	hub._on_window_input(_key(KEY_3))
	await process_frame
	await _wait(func(): return not outfit._ctx_stale and outfit._loaded and not outfit._busy and not outfit._pv_dirty)
	_check(outfit._loaded and outfit.baker != old_baker, "복장 탭으로 오자 알아서 다시 불러옴")

	hub.queue_free()
	await process_frame
	print("Dot Rigger 창(탭) 검사 %s (실패 %d)" % ["전부 통과" if _fail == 0 else "실패 있음", _fail])
	quit(1 if _fail > 0 else 0)
