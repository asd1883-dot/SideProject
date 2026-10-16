extends SceneTree

## Dot Rigger 창(DRHubWindow, 탭 페이지) 스모크 — 창을 띄워(10-16 3D 노선 기준)
##  [1] 탭 3개 · 처음 = ① 유닛 · 페이지는 누를 때 만든다
##  [2] ① 유닛 탭: 처음 열면 기본형 군인을 고르고 미리보기 캐릭터가 조립되고 동작 표가 붙는다
##  [3] ③ 복장 탭: 군복 불러오기 · 미리보기 캐릭터 · 안 보이는 탭(①)의 미리보기는 멈춘다
##  [4] Ctrl+1 · 2 · 3 으로 탭 바꾸기 · 페이지는 한 번 만들면 그대로(작업 유지)
##
##   godot --path . --screen 0 --resolution 1500x920 --script res://addons/dot_rigger/tools/hub_smoke_cli.gd
## 필요: game/units/soldier_base.tscn · outfits/uniform_m36/outfit.json · game/motions/rifleman_anims.res. 그림 = res://puppet_test/_hub_*.png

const OUTFIT := "res://outfits/uniform_m36/outfit.json"

var _fail := 0


func _initialize() -> void:
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


func _shot(hub: Window, name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	hub.get_texture().get_image().save_png("res://puppet_test/%s.png" % name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://puppet_test"))
	var hub := DRHubWindow.new()
	root.add_child(hub)
	var shown_early := hub.visible     # 넣기만 해서 뜨면 안 된다(10-06: 그래서 다른 모니터 구석에 떴다)
	hub.open()
	await process_frame
	_check(not shown_early and hub.visible, "넣기만 해서는 안 뜨고 open() 이 띄운다")

	print("[1] 탭")
	_check(hub._buttons.size() == 3 and hub._current == "unit" and hub._pages.size() == 1, "탭 3개 · 처음 = ① 유닛 · 만든 페이지 1개(나머지는 누를 때)")

	print("[2] ① 유닛 탭 — 기본형 군인 · 미리보기 · 동작 표")
	var unit: DRUnitPage = hub.page("unit")
	await _wait(func(): return unit._prev_ch != null)
	_check(unit._units.has("res://game/units/soldier_base.tscn"), "유닛 목록에 기본형 군인(%d개)" % unit._units.size())
	_check(unit._root != null and unit._sel_path.ends_with("soldier_base.tscn"), "처음 고른 유닛: %s" % unit._sel_path.get_file())
	_check(unit._prev_ch != null and unit._prev_ch.worn("top") != "", "미리보기 캐릭터 조립(군복)")
	_check(unit._motion_ed.table == unit._root.motions and unit._state_ob.item_count > 0, "동작 표 붙음 · 상태 목록 %d" % unit._state_ob.item_count)
	_check(unit.hosted and hub.title.contains("유닛"), "창 제목: %s" % hub.title)
	for i in 30:
		await process_frame
	await _shot(hub, "_hub_unit")

	print("[3] ③ 복장 탭")
	hub.open_page("outfit")
	await process_frame
	var outfit: DROutfitPage = hub.page("outfit")
	_check(outfit != null and outfit.is_visible_in_tree() and not unit.is_visible_in_tree(), "복장 탭이 보이고 유닛 탭은 숨음")
	_check(unit._pv_vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "안 보이는 유닛 탭의 미리보기 멈춤")
	await _wait(func(): return not outfit._busy)
	if not outfit._loaded:
		outfit.load_outfit(OUTFIT)
	await _wait(func(): return outfit._loaded and not outfit._busy and outfit._pv_ch != null)
	_check(outfit._loaded and outfit._pv_ch != null and outfit._pv_ch.worn("top") != "", "군복 불러옴 · 미리보기 캐릭터가 입음")
	for i in 30:
		await process_frame
	await _shot(hub, "_hub_outfit")

	print("[4] Ctrl+숫자 · 작업 유지")
	hub._on_window_input(_key(KEY_1))
	await process_frame
	_check(hub._current == "unit" and unit.is_visible_in_tree() and not outfit.is_visible_in_tree() and unit._pv_vp.render_target_update_mode == SubViewport.UPDATE_ALWAYS, "Ctrl+1 → 유닛 탭(미리보기 다시 켜짐)")
	_check(hub.page("unit") == unit and unit._prev_ch != null and outfit._loaded, "탭을 바꿔도 페이지 · 불러온 것 그대로")
	hub._on_window_input(_key(KEY_2))
	await process_frame
	_check(hub._current == "equip" and hub.page("equip") != null and hub.page("equip").is_visible_in_tree(), "Ctrl+2 → ② 장비 탭")
	for i in 30:
		await process_frame
	await _shot(hub, "_hub_equip")
	hub._on_window_input(_key(KEY_3))
	await process_frame
	_check(hub._current == "outfit" and hub.page("outfit") == outfit and outfit._loaded, "Ctrl+3 → ③ 복장 탭(불러온 것 그대로)")

	hub.queue_free()
	await process_frame
	print("Dot Rigger 창(탭) 검사 %s (실패 %d)" % ["전부 통과" if _fail == 0 else "실패 있음", _fail])
	quit(1 if _fail > 0 else 0)
