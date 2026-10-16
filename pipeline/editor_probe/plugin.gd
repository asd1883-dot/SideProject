@tool
extends EditorPlugin

## 에디터 안 검사(탐침) — pipeline/check_editor.py 가 샌드박스에 잠깐 넣어 돌린다.
## 명령줄 검사(--script)는 에디터 밖이라 Engine.is_editor_hint() 가 거짓이고 EditorInterface 길을 안 탄다.
## 10-06: 그래서 ③ 탭의 에디터 설정 읽기 오류와 창이 다른 모니터 구석에 뜨는 것을 놓쳤다 → 실제 에디터에서 메뉴를 누른 것처럼 돌려 본다.
## 10-16: 3D 탭 기준 — ① 유닛(열린 씬 · 되돌리기 · 소켓 장비 미리보기) · ② 장비(뼈 소켓 — 자리 칸 · 소켓 더하기를 되돌리기,
##        편집 중인 씬의 왼손 IK 목표가 따라오나, 미리보기 사본이 따라오나) · ③ 복장. 에디터를 --headless 로 띄우면 창 자리 검사는 건너뛴다.

var _headless := false


func _enter_tree() -> void:
	_go.call_deferred()


func _info(hub: Window, tag: String) -> void:
	print("PROBE ", tag, " visible=", hub.visible, " pos=", hub.position, " size=", hub.size, " screen=", hub.current_screen,
		" reachable=", DRHubWindow._reachable(Rect2i(hub.position, hub.size)))


func _expect(ok: bool, what: String) -> void:
	print("PROBE ", "OK   " if ok else "FAIL ", what)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## 오른손 소켓이 손뼈를 따라가나 — 걷기를 몇 번 진행하며 소켓 자리 ↔ 뼈 자리(최대 어긋남 m). 미리보기는 조립된 열린 씬을 pack 한
## 사본이라 소켓에 뼈대 길이 든 채 들어온다 — 10-16 그 길 때문에 묶기를 건너뛰어 소켓이 뼈를 안 따라갔다(3 cm)
func _socket_drift(ch) -> float:
	if ch == null or ch.get_weapon_node() == null:
		return 1.0
	var s: BoneAttachment3D = ch.get_weapon_node().get_parent()
	var sk: Skeleton3D = ch.get_skeleton()
	var bi := sk.find_bone(s.bone_name)
	ch.play_motion("Walk_With_Rifle", 0.0)
	var worst := 0.0
	for i in 4:
		ch.step_motion(1.0 / 12.0)
		await get_tree().process_frame
		worst = maxf(worst, (sk.global_transform * sk.get_bone_global_pose(bi)).origin.distance_to(s.global_position))
	return worst


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	return ev


func _ctrl_key(code: Key, shift := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.ctrl_pressed = true
	ev.shift_pressed = shift
	return ev


## 기즈모 층에 왼쪽 끌기(누름 → 움직임 6번 → 뗌)
func _giz_drag(giz: Control, from: Vector2, to: Vector2) -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = true
	b.position = from
	b.button_mask = MOUSE_BUTTON_MASK_LEFT
	giz._gui_input(b)
	for i in 6:
		var m := InputEventMouseMotion.new()
		m.position = from.lerp(to, float(i + 1) / 6.0)
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		giz._gui_input(m)
	var r := InputEventMouseButton.new()
	r.button_index = MOUSE_BUTTON_LEFT
	r.pressed = false
	r.position = to
	giz._gui_input(r)


## Ctrl+Z 와 같은 것 — obj 가 속한 기록(씬)의 되돌리기. EditorUndoRedoManager 에는 스크립트용 undo() 가 없다(10-16: 부르면 스크립트 오류로 탐침이 멈춤)
func _undo(obj: Object) -> void:
	var m := EditorInterface.get_editor_undo_redo()
	m.get_history_undo_redo(m.get_object_history_id(obj)).undo()


func _go() -> void:
	_headless = DisplayServer.get_name() == "headless"
	await _frames(200)
	print("PROBE start", "  (창 없이 — 창 자리 검사는 건너뜀)" if _headless else "")
	# 메뉴를 누른 것과 같은 순서(plugin._open)
	var hub := DRHubWindow.new()
	EditorInterface.get_base_control().add_child(hub)
	_expect(not hub.visible, "넣기만 해서는 안 뜬다")
	hub.open("unit")
	await get_tree().process_frame
	if not _headless:
		_info(hub, "열림")
		_expect(hub.visible and DRHubWindow._reachable(Rect2i(hub.position, hub.size)), "제목줄을 잡을 수 있는 자리에 뜸")

	# ① 유닛 탭(3D): 유닛을 고르면 그 씬이 에디터에 열리고 루트를 고친다 · 미리보기 = 유닛 사본(소켓 장비까지)
	var unit = hub.page("unit")
	await _frames(120)
	var er = EditorInterface.get_edited_scene_root()
	_expect(unit._root != null and unit._root == er, "① 유닛 탭: 고른 유닛 씬이 에디터에 열리고 그 루트를 고침")
	var pw = unit._prev_ch.get_weapon_node() if unit._prev_ch != null else null
	_expect(pw != null and pw.get_parent() is BoneAttachment3D and unit._prev_ch.get_left_arm_ik() != null, "① 유닛 탭: 미리보기 = 유닛 사본(소켓 무기 · 왼팔 IK)")
	var d1: float = await _socket_drift(unit._prev_ch)
	_expect(d1 < 0.001, "① 미리보기: 소켓이 손뼈를 따라감(걷기 %.4f m 어긋남)" % d1)
	_expect(er is DRCharacter3D and er.get_weapon_node() != null and er.get_left_arm_ik() != null and er.is_processing(),
		"편집 중인 유닛 씬: 소켓 무기 · 왼팔 IK · 에디터 따라가기 켜짐")
	# 칸을 바꾸면 되돌리기에 남는다(씬에 *) → 되돌리면 탭도 따라온다
	var old_h: float = unit._root.height_m
	unit._set_prop("height_m", 1.6)
	_expect(absf(unit._root.height_m - 1.6) < 0.001, "① 유닛 탭: 키 바꾸기 → 열린 씬 루트")
	unit._unhandled_key_input(_ctrl_key(KEY_Z))             # 탭 창에서 누른 Ctrl+Z(10-16 — 전에는 에디터 창에서만 됐다)
	await _frames(30)
	_expect(absf(unit._root.height_m - old_h) < 0.001 and absf((unit._fields["height_m"]["ctl"] as SpinBox).value - old_h) < 0.001, "① 유닛 탭: 탭 창 Ctrl+Z 로 되돌리면 칸도 따라옴")

	# ② 장비 탭 — ① 의 [② 탭] 단추로(같은 유닛)
	unit._on_open_equip()
	await _frames(60)
	var eqp = hub.page("equip")
	_expect(hub._current == "equip" and eqp != null and eqp._root == EditorInterface.get_edited_scene_root(), "② 장비 탭: ① 의 [② 탭] 단추 → 같은 유닛(열린 씬 루트)")
	var ew = eqp._weapon_equip() if eqp != null else null
	_expect(ew != null and eqp._prev != null and eqp._prev.get_left_arm_ik() != null, "② 장비 탭: 무기 %s · 미리보기 왼팔 IK" % (String(ew.name) if ew != null else "-"))
	var d2: float = await _socket_drift(eqp._prev if eqp != null else null)
	_expect(d2 < 0.001, "② 미리보기: 소켓이 손뼈를 따라감(걷기 %.4f m 어긋남)" % d2)
	if ew != null and er is DRCharacter3D:
		# 무기 자리 칸 +1 cm(기즈모와 같은 노드) → 열린 씬 · 왼손 IK 목표 · 미리보기 사본이 따라오고 되돌리기 한 칸
		var t0: Vector3 = er.support_report().get("target", Vector3.ZERO)
		var p0: Vector3 = ew.position
		eqp._select_node(er.get_path_to(ew))
		eqp._pos[0].value = eqp._pos[0].value + 1.0
		await _frames(30)
		var t1: Vector3 = er.support_report().get("target", Vector3.ZERO)
		_expect(absf(ew.position.x - p0.x - 0.01) < 0.0005, "② 장비 탭: 위치 칸 +1 cm → 열린 씬의 무기 노드")
		_expect(absf((t1 - t0).length() - 0.01) < 0.002, "편집 중인 씬: 무기를 옮기면 왼손 IK 목표도 따라감(%.2f cm)" % ((t1 - t0).length() * 100.0))
		var pn = eqp._prev_node(ew)
		_expect(pn != null and (pn as Node3D).position.is_equal_approx(ew.position), "② 미리보기 사본도 같은 자리")
		_undo(er)
		await _frames(30)
		_expect(ew.position.is_equal_approx(p0), "② 장비 탭: Ctrl+Z → 무기 자리 되돌아감")
		# 유니티식 기즈모(10-16): 미리보기에서 X 화살표를 끌어 놓으면 열린 씬의 무기에 되돌리기 한 칸 → 탭 창 Ctrl+Z · Ctrl+Y
		var giz = eqp._giz
		eqp.set_dot_mode(false)
		eqp.set_tool(1)                                        # 이동(W)
		eqp._playing = false
		await _frames(5)
		var gp: Vector2 = giz.handle_point(1)                 # X 화살표
		var gd: Vector2 = (giz._p(giz.pivot_point() + giz._axes_now(false)[0] * 0.1) - giz._p(giz.pivot_point())).normalized()
		var x0: Transform3D = ew.transform
		_giz_drag(giz, gp, gp + gd * 40.0)
		await _frames(5)
		var moved: bool = not ew.transform.is_equal_approx(x0) and ew.transform.basis.is_equal_approx(x0.basis)
		_expect(giz.target == eqp._prev_node(ew) and moved, "② 기즈모: X 화살표를 끌어 놓으면 열린 씬의 무기가 옮겨짐(%.1f cm)" % (ew.transform.origin.distance_to(x0.origin) * 100.0))
		var x1: Transform3D = ew.transform
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		var undone: bool = ew.transform.is_equal_approx(x0) and (eqp._prev_node(ew) as Node3D).transform.is_equal_approx(x0)
		eqp._unhandled_key_input(_ctrl_key(KEY_Y))
		await _frames(30)
		var redone: bool = ew.transform.is_equal_approx(x1)
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		_expect(undone and redone and ew.transform.is_equal_approx(x0), "② 기즈모: 탭 창 Ctrl+Z → 되돌림(미리보기도) · Ctrl+Y → 다시 · 다시 Ctrl+Z")
		eqp._unhandled_key_input(_key(KEY_E))
		_expect(giz.tool_mode == 2, "② 단축키 E = 회전(유니티와 같음)")
		eqp._unhandled_key_input(_key(KEY_W))
		eqp._playing = true
		# 머리 소켓 더하기 → 열린 씬에 붙고 캐릭터가 잇는다 → 되돌리기
		var n0: int = eqp._sockets().size()
		var hs = eqp.add_socket("", "Head")
		await _frames(30)
		_expect(hs != null and eqp._sockets().size() == n0 + 1 and hs.owner == er and er.get_sockets().size() == n0 + 1,
			"② 장비 탭: 머리 소켓 더하기 → 열린 씬(주인 = 루트) · 캐릭터가 뼈에 이음")
		_undo(er)
		await _frames(30)
		_expect(eqp._sockets().size() == n0, "② 장비 탭: Ctrl+Z → 소켓 빠짐")
		# 저장(에디터가 저장 앞뒤로 보내는 알림): 소켓이 가리키는 뼈대 길(안에서 조립한 노드)은 씬 파일에 안 남고 저장 뒤 다시 잇는다
		er.propagate_notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
		var ps := PackedScene.new()
		var packed_ok := ps.pack(er) == OK
		var st := ps.get_state()
		var leaked := PackedStringArray()
		for i in st.get_node_count():
			for j in st.get_node_property_count(i):
				if st.get_node_property_name(i, j) == &"external_skeleton" and not (st.get_node_property_value(i, j) as NodePath).is_empty():
					leaked.append(str(st.get_node_property_value(i, j)))
		er.propagate_notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
		var rebound: bool = not eqp._sockets().is_empty()
		for s in eqp._sockets():                               # 지금 씬에 든 소켓(방금 되돌려 뺀 머리 소켓은 없음)
			rebound = rebound and s.get_skeleton() == er.get_skeleton()
		_expect(packed_ok and leaked.is_empty() and rebound, "저장: 소켓의 뼈대 길은 씬 파일에 안 남고(%s) 저장 뒤 다시 이음" % (", ".join(leaked) if not leaked.is_empty() else "빈 길"))

	# ③ 탭으로(사용자가 흔히 하는 순서)
	(hub._buttons["outfit"] as Button).pressed.emit()
	await _frames(400)
	var outfit = hub.page("outfit")
	_expect(hub._current == "outfit" and outfit != null, "③ 복장 탭 열림")
	(hub._buttons["unit"] as Button).pressed.emit()
	await _frames(30)
	_expect(hub._current == "unit" and unit._prev_ch != null and unit._prev_ch.get_weapon_node() != null, "① 로 돌아와도 미리보기 그대로(소켓 무기)")

	# 닫기(X) → 다시 열기: 같은 탭(창이 있으면 같은 자리)
	(hub._buttons["equip"] as Button).pressed.emit()
	await get_tree().process_frame
	if not _headless:
		hub.position += Vector2i(120, 60)
	var where := hub.position
	hub.close_requested.emit()
	await get_tree().process_frame
	_expect(not hub.visible, "닫기 = 숨김")
	hub.open()
	await get_tree().process_frame
	_expect(hub.visible and hub._current == "equip" and (_headless or hub.position == where), "다시 열면 같은 탭%s" % ("" if _headless else " · 같은 자리"))
	if not _headless:
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
