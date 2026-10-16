@tool
extends EditorPlugin

## 에디터 안 검사(탐침) — pipeline/check_editor.py 가 샌드박스에 잠깐 넣어 돌린다.
## 명령줄 검사(--script)는 에디터 밖이라 Engine.is_editor_hint() 가 거짓이고 EditorInterface 길을 안 탄다.
## 10-06: 그래서 ③ 탭의 에디터 설정 읽기 오류와 창이 다른 모니터 구석에 뜨는 것을 놓쳤다 → 실제 에디터에서 메뉴를 누른 것처럼 돌려 본다.

func _enter_tree() -> void:
	_go.call_deferred()


func _info(hub: Window, tag: String) -> void:
	print("PROBE ", tag, " visible=", hub.visible, " pos=", hub.position, " size=", hub.size, " screen=", hub.current_screen,
		" reachable=", DRHubWindow._reachable(Rect2i(hub.position, hub.size)))


func _expect(ok: bool, what: String) -> void:
	print("PROBE ", "OK   " if ok else "FAIL ", what)


func _go() -> void:
	for i in 200:
		await get_tree().process_frame
	print("PROBE start")
	# 메뉴를 누른 것과 같은 순서(plugin._open)
	var hub := DRHubWindow.new()
	EditorInterface.get_base_control().add_child(hub)
	_expect(not hub.visible, "넣기만 해서는 안 뜬다")
	hub.open("unit")
	await get_tree().process_frame
	_info(hub, "열림")
	_expect(hub.visible and DRHubWindow._reachable(Rect2i(hub.position, hub.size)), "제목줄을 잡을 수 있는 자리에 뜸")
	# ① 유닛 탭(10-16, 3D): 유닛을 고르면 그 씬이 에디터에 열리고 루트를 고친다 · 미리보기 캐릭터 조립
	var unit = hub.page("unit")
	for i in 120:
		await get_tree().process_frame
	_expect(unit._root != null and unit._root == EditorInterface.get_edited_scene_root(), "① 유닛 탭: 고른 유닛 씬이 에디터에 열리고 그 루트를 고침")
	_expect(unit._prev_ch != null and unit._prev_ch.get_weapon_node() != null, "① 유닛 탭: 미리보기 캐릭터 조립(무기 포함)")
	# 칸을 바꾸면 되돌리기에 남는다(씬에 *) → 되돌리면 탭도 따라온다
	var old_h: float = unit._root.height_m
	unit._set_prop("height_m", 1.6)
	_expect(absf(unit._root.height_m - 1.6) < 0.001, "① 유닛 탭: 키 바꾸기 → 열린 씬 루트")
	EditorInterface.get_editor_undo_redo().undo()
	for i in 30:
		await get_tree().process_frame
	_expect(absf(unit._root.height_m - old_h) < 0.001 and absf((unit._fields["height_m"]["ctl"] as SpinBox).value - old_h) < 0.001, "① 유닛 탭: Ctrl+Z 로 되돌리면 칸도 따라옴")
	# ③ 탭으로(사용자가 흔히 하는 순서)
	(hub._buttons["outfit"] as Button).pressed.emit()
	for i in 400:
		await get_tree().process_frame
	var outfit = hub.page("outfit")
	_expect(hub._current == "outfit" and outfit != null, "③ 복장 탭 열림")
	(hub._buttons["equip"] as Button).pressed.emit()
	for i in 60:
		await get_tree().process_frame
	_expect(hub._current == "equip" and hub.page("equip") != null, "② 장비 탭 열림")
	# 10-12: 무기 칸이 비면 아무것도 안 떠서 "캐릭터 프리셋을 뭘 넣어도 안 뜬다" — 열기만 해도 캐릭터는 떠야 한다
	var eqp = hub.page("equip")
	var waited := 0
	while (eqp._busy or eqp._soldier == null) and waited < 3000:
		await get_tree().process_frame
		waited += 1
	_expect(is_instance_valid(eqp._soldier) and eqp._pv3.texture != null, "② 탭을 열면 캐릭터(2D · 3D)가 저절로 뜸(무기 없이도)")
	# 닫기(X) → 다시 열기: 같은 자리 · 같은 탭
	hub.position += Vector2i(120, 60)
	var where := hub.position
	hub.close_requested.emit()
	await get_tree().process_frame
	_expect(not hub.visible, "닫기 = 숨김")
	hub.open()
	await get_tree().process_frame
	_expect(hub.visible and hub.position == where and hub._current == "equip", "다시 열면 같은 자리 · 같은 탭")
	# 화면 밖으로 밀려났으면 다시 열 때 구해 온다
	hub.position = Vector2i(-5000, -5000)
	hub.open()
	await get_tree().process_frame
	_info(hub, "구해 옴")
	_expect(DRHubWindow._reachable(Rect2i(hub.position, hub.size)), "화면 밖 창을 구해 옴")
	hub.position = where
	hub.close_requested.emit()
	print("PROBE done")
	get_tree().quit()
