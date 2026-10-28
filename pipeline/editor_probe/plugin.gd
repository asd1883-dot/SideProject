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
	# 피격 반응(10-21): 피격 동작 확률 칸 → 열린 씬 루트 · 미리보기 사본(다시 조립 안 함) → 맞혀 보기(가슴) → 탭 창 Ctrl+Z → 칸 · 사본도
	var pc0: float = unit._root.hit_anim_chance
	var pv0 = unit._prev_ch
	(unit._hit_sp["hit_anim_chance"] as SpinBox).value = 100.0
	await _frames(5)
	var hset: bool = absf(unit._root.hit_anim_chance - 1.0) < 0.001 and unit._prev_ch == pv0 and absf(unit._prev_ch.hit_anim_chance - 1.0) < 0.001
	unit.play_state("서기")
	await _frames(5)
	var hsk: Skeleton3D = unit._prev_ch.get_skeleton()
	var hcp: Vector2 = unit._dots.world_to_canvas(hsk.global_transform * hsk.get_bone_global_pose(hsk.find_bone("UpperChest")).origin)
	var hr: Dictionary = unit.hit_test(hcp)
	var hhit: bool = String(hr.get("part", "")) == "가슴" and String(hr.get("anim", "")) != "" and unit._prev_ch.hit_count() > 0
	unit._unhandled_key_input(_ctrl_key(KEY_Z))
	await _frames(30)
	var hundo: bool = absf(unit._root.hit_anim_chance - pc0) < 0.001 and absf((unit._hit_sp["hit_anim_chance"] as SpinBox).value - pc0 * 100.0) < 0.01 \
		and absf(unit._prev_ch.hit_anim_chance - pc0) < 0.001
	_expect(hset and hhit and hundo, "① 피격: 확률 칸 → 열린 씬 루트 · 미리보기 사본 · 맞혀 보기 가슴 → %s · 탭 창 Ctrl+Z → 칸 · 사본도 (%s %s %s)" % [hr.get("anim", "-"), hset, hhit, hundo])

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
		# 잡기(10-16 확장): 양손(두 손 사이 받침대)으로 바꿨다가 탭 창 Ctrl+Z → 원래 소켓 · 주인 그대로(씬에 저장됨) · 만든 받침대 · 표지 빠짐 → Ctrl+Y → Ctrl+Z
		var parent0: Node = ew.get_parent()
		eqp._select_node(er.get_path_to(ew))
		eqp.set_grip(2)
		await _frames(30)
		var mnt: Node = ew.get_parent()
		var to_mount: bool = mnt is DRGripMount3D and mnt.owner == er and ew.owner == er and DRCharacter3D.find_hand_marker(ew, 1) != null \
			and eqp._prev.get_arm_ik(0) != null and eqp._prev.get_arm_ik(1) != null and er.get_arm_ik(1) != null
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		var back: bool = ew.get_parent() == parent0 and ew.owner == er and not mnt.is_inside_tree() and DRCharacter3D.find_hand_marker(ew, 1) == null \
			and er.get_arm_ik(1) == null
		eqp._unhandled_key_input(_ctrl_key(KEY_Y))
		await _frames(30)
		var again: bool = ew.get_parent() == mnt and mnt.owner == er and ew.owner == er and DRCharacter3D.find_hand_marker(ew, 1) != null
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		_expect(to_mount and back and again and ew.get_parent() == parent0 and ew.owner == er,
			"② 잡기: 양손(받침대 · 오른손 표지 · 두 손 IK) → 탭 창 Ctrl+Z 원래 소켓 · 주인 그대로 → Ctrl+Y 다시 → Ctrl+Z (%s %s %s)" % [to_mount, back, again])
		# 잡기 기억(10-21) · 한 손 잡기(10-27): 동작을 바꿔 가며 양손 → 오른손(오른손만 IK) → 양손 = 처음 양손 자리 그대로 · 기억 메타가 씬에 ·
		# 탭 창 Ctrl+Z 세 번 → 처음 소켓 · 기억 메타도 처음대로
		var x_sock: Transform3D = ew.transform
		var mem0: Variant = ew.get_meta(DREquipPage.GRIP_MEMORY_META) if ew.has_meta(DREquipPage.GRIP_MEMORY_META) else null
		eqp.play_motion("Walk_With_Rifle")
		eqp._seek(0.6)
		eqp.set_grip(2)
		await _frames(30)
		var mnt2: Node = ew.get_parent()
		var x_two: Transform3D = ew.transform
		eqp.play_motion("Firing_Rifle")
		eqp._seek(0.2)
		eqp.set_grip(0)
		await _frames(30)
		var one: bool = DREquipPage.grip_kind(ew) == 0 and ew.get_parent().owner == er and er.get_arm_ik(1) != null 			and eqp._prev.get_ik_weight(1) > 0.99 and eqp._prev.get_ik_weight(0) <= 0.001
		eqp.play_motion("Rifle_Idle")
		eqp._seek(0.5)
		eqp.set_grip(2)
		await _frames(30)
		var kept: bool = ew.get_parent() == mnt2 and ew.transform.is_equal_approx(x_two) and ew.has_meta(DREquipPage.GRIP_MEMORY_META)
		for i in 3:
			eqp._unhandled_key_input(_ctrl_key(KEY_Z))
			await _frames(20)
		var mem1: Variant = ew.get_meta(DREquipPage.GRIP_MEMORY_META) if ew.has_meta(DREquipPage.GRIP_MEMORY_META) else null
		_expect(one and kept and ew.get_parent() == parent0 and ew.transform.is_equal_approx(x_sock) and str(mem1) == str(mem0),
			"② 잡기 기억 · 한 손: 양손 → 오른손(한 손 받침대 · 오른손만 IK %s) → 양손 = 처음 양손 자리 그대로(%s) · Ctrl+Z 세 번 = 처음 소켓 · 메타도 처음대로" % [one, kept])
		# 동작마다 잡기(10-27): 이 동작만 → [오른손] → 열린 씬 왼손 표지 motion_weights(그 동작만 0) · 미리보기 왼손 놓음 → 탭 창 Ctrl+Z → 처음대로
		eqp._select_node(er.get_path_to(ew))
		eqp.play_motion("Firing_Rifle")
		eqp._seek(0.4)
		eqp.set_per_motion(true)
		var lmk := DRCharacter3D.find_hand_marker(ew, 0) as DRHandTarget3D
		var lw0: Dictionary = lmk.motion_weights.duplicate() if lmk != null else {}
		eqp._grip_btns[0].pressed.emit()
		await _frames(20)
		var mg_set: bool = lmk != null and float(lmk.motion_weights.get("Firing_Rifle", -1.0)) == 0.0 and eqp._prev.get_ik_weight(0) <= 0.001 \
			and DREquipPage.motion_grip(ew, "Firing_Rifle") == 0 and DREquipPage.motion_grip(ew, "Rifle_Aiming_Idle") == 2
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(20)
		var mg_undo: bool = lmk != null and str(lmk.motion_weights) == str(lw0) and DREquipPage.motion_grip(ew, "Firing_Rifle") == 2
		eqp.set_per_motion(false)
		_expect(mg_set and mg_undo, "② 동작마다 잡기: 이 동작만 → [오른손] → 열린 씬 왼손 표지 Firing_Rifle 0 · 미리보기 왼손 놓음 · 다른 동작 그대로 → Ctrl+Z 처음대로 (%s %s)" % [mg_set, mg_undo])
		# 손 기준 나무(10-27): 무기를 왼손에 끌어 놓기 → 왼손 잡기 · 옛 손 소켓 정리(열린 씬) → 탭 창 Ctrl+Z → 소켓 되살아남 · 주인 그대로 → Ctrl+Y → Ctrl+Z
		var sock0: Node = ew.get_parent()
		eqp.play_motion("Rifle_Aiming_Idle")
		eqp._seek(0.3)
		eqp.drop_equip_on_grip(er.get_path_to(ew), 1)
		await _frames(30)
		var dropped: bool = DREquipPage.grip_kind(ew) == 1 and not sock0.is_inside_tree() and ew.owner == er and ew.get_parent().owner == er
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		var restored: bool = ew.get_parent() == sock0 and sock0.is_inside_tree() and sock0.owner == er and ew.owner == er \
			and DRCharacter3D.find_hand_marker(ew, 0) != null and DRCharacter3D.find_hand_marker(ew, 0).owner == er
		eqp._unhandled_key_input(_ctrl_key(KEY_Y))
		await _frames(30)
		var redone_drop: bool = DREquipPage.grip_kind(ew) == 1 and not sock0.is_inside_tree()
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		_expect(dropped and restored and redone_drop and ew.get_parent() == sock0,
			"② 손 기준 나무: 무기를 왼손에 끌어 놓기 → 왼손 잡기 · 옛 손 소켓 정리 → Ctrl+Z 소켓 되살아남(주인 그대로) → Ctrl+Y → Ctrl+Z (%s %s %s)" % [dropped, restored, redone_drop])
		# 손 기즈모(10-27): 이 동작만 → 왼손(표지) 기즈모 끌기 → 열린 씬 왼손 표지 메타(그 동작만) · 표지 기본 그대로 → Ctrl+Z 메타 빠짐
		var lm2 := DRCharacter3D.find_hand_marker(ew, 0)
		eqp.play_motion("Rifle_Aiming_Idle")
		eqp._seek(0.3)
		eqp.set_per_motion(true)
		eqp._select_node(er.get_path_to(lm2))
		eqp.set_tool(1)
		await _frames(10)
		var lx0: Transform3D = lm2.transform
		var lgp: Vector2 = giz.handle_point(1)
		var lgd: Vector2 = (giz._p(giz.pivot_point() + giz._axes_now(false)[0] * 0.1) - giz._p(giz.pivot_point())).normalized()
		_giz_drag(giz, lgp, lgp + lgd * 30.0)
		await _frames(10)
		var hand_set: bool = giz.target == eqp._prev_node(lm2) and DRCharacter3D.offset_key(lm2, "Rifle_Aiming_Idle") == "Rifle_Aiming_Idle" and lm2.transform.is_equal_approx(lx0)
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		var hand_undo: bool = DRCharacter3D.motion_offsets(lm2).is_empty() and lm2.transform.is_equal_approx(lx0)
		eqp.set_per_motion(false)
		eqp._select_node(er.get_path_to(ew))
		_expect(hand_set and hand_undo, "② 손 기즈모: 이 동작만 왼손 끌기 → 열린 씬 왼손 표지에 그 동작 자리(기본 그대로) → Ctrl+Z 빠짐 (%s %s)" % [hand_set, hand_undo])
		# 고른 것 유지(10-27 "가끔 안 될 때가 있어"): 무기를 고른 채 잡기 바꿈(무기 경로가 바뀜) → 탭 창 Ctrl+Z(경로가 돌아옴) → 여전히 무기를 고르고 기즈모도 무기
		eqp._select_node(er.get_path_to(ew))
		eqp.set_grip(1)
		await _frames(30)
		var sel_after: bool = eqp._node(eqp._sel) == ew
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(40)
		var sel_undo: bool = eqp._node(eqp._sel) == ew and giz.target == eqp._prev_node(ew)
		_expect(sel_after and sel_undo, "② 고른 것 유지: 무기를 고른 채 잡기 바꿈 → Ctrl+Z(무기 경로가 돌아옴) → 여전히 무기 · 기즈모도 무기 (%s %s)" % [sel_after, sel_undo])
		# 잡기 끄기 = 안 붙음(10-27): 왼손 잡기 → 눌린 [왼손] 다시 누름 → 열린 씬 왼손 표지 비중 0 → Ctrl+Z 비중 1 → Ctrl+Z 옛 소켓으로
		eqp._select_node(er.get_path_to(ew))
		eqp.set_grip(1)
		await _frames(30)
		var lm4 := DRCharacter3D.find_hand_marker(ew, 0) as DRHandTarget3D
		eqp._grip_btns[1].set_pressed_no_signal(false)
		eqp._grip_btns[1].pressed.emit()
		await _frames(20)
		var ug_set: bool = lm4 != null and lm4.weight == 0.0 and DREquipPage.motion_grip(ew, "") == -2 and eqp._prev.get_ik_weight(0) <= 0.001
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		var ug_undo: bool = lm4 != null and lm4.weight == 1.0 and DREquipPage.motion_grip(ew, "") == 1
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(40)
		_expect(ug_set and ug_undo and ew.get_parent() == sock0, "② 잡기 끄기: 눌린 [왼손] 다시 누름 → 열린 씬 왼손 표지 비중 0(안 붙음) → Ctrl+Z 비중 1 → Ctrl+Z 옛 소켓 (%s %s)" % [ug_set, ug_undo])
		# 손은 그대로 두고 총만 옮기기(10-27): 켬 → 무기 끌기 → 열린 씬 무기 · 왼손 표지 둘 다 바뀜 → Ctrl+Z 한 번에 둘 다 처음대로
		eqp.set_per_motion(false)
		eqp._select_node(er.get_path_to(ew))
		eqp._keep_hands_chk.button_pressed = true
		eqp.set_tool(1)
		await _frames(10)
		var lm3 := DRCharacter3D.find_hand_marker(ew, 0)
		var kw0: Transform3D = ew.transform
		var kl0: Transform3D = lm3.transform
		var kp: Vector2 = giz.handle_point(1)
		var kd: Vector2 = (giz._p(giz.pivot_point() + giz._axes_now(false)[0] * 0.1) - giz._p(giz.pivot_point())).normalized()
		_giz_drag(giz, kp, kp + kd * 30.0)
		await _frames(10)
		var keep_set: bool = giz.target == eqp._prev_node(ew) and not ew.transform.is_equal_approx(kw0) and not lm3.transform.is_equal_approx(kl0)
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		var keep_undo: bool = ew.transform.is_equal_approx(kw0) and lm3.transform.is_equal_approx(kl0)
		eqp._keep_hands_chk.button_pressed = false
		_expect(keep_set and keep_undo, "② 손은 그대로 두고 총만 옮기기: 무기 끌기 → 열린 씬 무기 · 왼손 표지 둘 다 바뀜 → Ctrl+Z 한 번에 둘 다 처음대로 (%s %s)" % [keep_set, keep_undo])
		# 동작마다 잡기 — 총 · 손 그대로(10-28): 기본 왼손 → 이 동작만 [오른손] → 미리보기 총 그대로 · 열린 씬 무기(그리고 오른손 표지) 그 동작 자리 →
		#   Ctrl+Z 한 번에 비중 · 자리 다 처음대로 → Ctrl+Z 옛 소켓으로
		eqp._select_node(er.get_path_to(ew))
		eqp.set_grip(1)
		await _frames(30)
		eqp.set_per_motion(true)
		eqp.play_motion("Walk_With_Rifle")
		eqp._seek(0.35)
		await _frames(5)
		var rk0 := DRCharacter3D.find_hand_marker(ew, 1)
		var go0 := str(DRCharacter3D.motion_offsets(ew))
		var ro0 := str(DRCharacter3D.motion_offsets(rk0)) if rk0 != null else ""
		var rw0 := str((rk0 as DRHandTarget3D).motion_weights) if rk0 is DRHandTarget3D else ""
		eqp._force_pose()
		var pg0: Transform3D = (eqp._prev_node(ew) as Node3D).global_transform
		eqp.set_motion_grip("Walk_With_Rifle", 0)
		await _frames(20)
		eqp._seek(0.35)
		eqp._force_pose()
		var pg1: Transform3D = (eqp._prev_node(ew) as Node3D).global_transform
		var gk_set: bool = DREquipPage.motion_grip(ew, "Walk_With_Rifle") == 0 and str(DRCharacter3D.motion_offsets(ew)) != go0 and pg0.origin.distance_to(pg1.origin) < 0.001
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		var rk1 := DRCharacter3D.find_hand_marker(ew, 1)
		var gk_undo: bool = str(DRCharacter3D.motion_offsets(ew)) == go0 and DREquipPage.motion_grip(ew, "Walk_With_Rifle") == 1 and \
			(rk1 == null if rk0 == null else (rk1 == rk0 and str(DRCharacter3D.motion_offsets(rk0)) == ro0 and str((rk0 as DRHandTarget3D).motion_weights) == rw0))
		eqp.set_per_motion(false)
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(40)
		_expect(gk_set and gk_undo and ew.get_parent() == sock0, "② 동작마다 잡기 총 · 손 그대로: 기본 왼손 → Walk_With_Rifle 만 [오른손] → 미리보기 총 %.2f mm · 열린 씬 그 동작 자리 → Ctrl+Z 한 번에 처음대로 → Ctrl+Z 옛 소켓 (%s %s)" % [
			pg0.origin.distance_to(pg1.origin) * 1000.0, gk_set, gk_undo])
		# 동작별 무기 자리(10-19): 이 동작만 → 기즈모 끌기 → 열린 씬 장비의 메타(그 동작만) · 기본 자리 그대로(편집 중인 씬엔 안 얹음) · 미리보기 = 기본 × 차이
		#   · 저장(pack)에 메타가 담김 → 탭 창 Ctrl+Z 메타 빠짐(set_meta null) → Ctrl+Y → Ctrl+Z
		eqp._select_node(er.get_path_to(ew))
		eqp.play_motion("Firing_Rifle")
		eqp._seek(0.3)
		eqp.set_per_motion(true)
		await _frames(5)
		var b0: Transform3D = ew.transform
		var gp2: Vector2 = giz.handle_point(1)
		var gd2: Vector2 = (giz._p(giz.pivot_point() + giz._axes_now(false)[0] * 0.1) - giz._p(giz.pivot_point())).normalized()
		_giz_drag(giz, gp2, gp2 + gd2 * 40.0)
		await _frames(10)
		var om: Dictionary = DRCharacter3D.motion_offsets(ew)
		var stored: bool = om.size() == 1 and om.has("Firing_Rifle") and ew.transform.is_equal_approx(b0) \
			and (eqp._prev_node(ew) as Node3D).transform.is_equal_approx(b0 * (om.get("Firing_Rifle", Transform3D.IDENTITY) as Transform3D))
		var psm := PackedScene.new()
		var in_file := false
		if psm.pack(er) == OK:
			var stm := psm.get_state()
			for i in stm.get_node_count():
				for j in stm.get_node_property_count(i):
					if String(stm.get_node_property_name(i, j)) == "metadata/dr_motion_offsets":
						in_file = true
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		var gone: bool = not ew.has_meta(DRCharacter3D.MOTION_OFFSETS_META) and (eqp._prev_node(ew) as Node3D).transform.is_equal_approx(b0)
		eqp._unhandled_key_input(_ctrl_key(KEY_Y))
		await _frames(30)
		var redo2: bool = DRCharacter3D.motion_offsets(ew).has("Firing_Rifle")
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		eqp.set_per_motion(false)
		_expect(stored and in_file and gone and redo2 and not ew.has_meta(DRCharacter3D.MOTION_OFFSETS_META),
			"② 동작별 자리: 이 동작만 끌기 → 열린 씬 장비 메타(Firing_Rifle)만 · 기본 자리 그대로 · 저장에 담김 → Ctrl+Z 빠짐 → Ctrl+Y → Ctrl+Z (%s %s %s %s)" % [stored, in_file, gone, redo2])
		# 조준 IK(10-21): 조준 미리보기 → 미리보기 사본만 돈다(열린 씬엔 표적 없음) · 동작 표 조준 비중 → 열린 씬 루트 aim_motion_weights ·
		#   위 한계 칸 → 루트 값 → 탭 창 Ctrl+Z 둘 다 빠짐 → Ctrl+Y → Ctrl+Z
		eqp.play_motion("Firing_Rifle")
		eqp._aim_height_sl.value = 20.0
		eqp.set_aim_preview(true)
		await _frames(10)
		var aimed: bool = not eqp._prev.aim_report().is_empty() and er.aim_report().is_empty() and not er.has_aim_target()
		var up0: float = er.aim_up_deg
		eqp.set_aim_weight("Firing_Rifle", 0.5)
		await _frames(10)
		(eqp._aim_sp["aim_up_deg"] as SpinBox).value = up0 - 10.0
		await _frames(10)
		var set_ok: bool = absf(float(er.aim_motion_weights.get("Firing_Rifle", -1.0)) - 0.5) < 0.001 and absf(er.aim_up_deg - (up0 - 10.0)) < 0.01 \
			and absf(eqp._prev.aim_weight_for("Firing_Rifle") - 0.5) < 0.001
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		var undo_up: bool = absf(er.aim_up_deg - up0) < 0.01 and absf((eqp._aim_sp["aim_up_deg"] as SpinBox).value - up0) < 0.01
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		var undo_w: bool = not er.aim_motion_weights.has("Firing_Rifle") and absf(eqp._prev.aim_weight_for("Firing_Rifle") - 1.0) < 0.001
		eqp._unhandled_key_input(_ctrl_key(KEY_Y))
		await _frames(30)
		var redo_w: bool = er.aim_motion_weights.has("Firing_Rifle")
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		eqp.set_aim_preview(false)
		# 조준 표지(10-21): [총구 표지] → 열린 씬 무기 아래(주인 = 루트) · 기즈모 X 화살표 끌기 → 표지 · 미리보기 레이 옮겨짐 → Ctrl+Z 자리 → Ctrl+Z 표지 빠짐
		eqp._select_node(er.get_path_to(ew))
		var amk = eqp.make_aim_marker(DRCharacter3D.MUZZLE_NAME)
		await _frames(10)
		var made: bool = amk != null and amk.get_parent() == ew and amk.owner == er and giz.target == eqp._prev_node(amk)
		var ray_a: Vector3 = eqp._prev.muzzle_world()[0]
		var p_a: Vector3 = amk.position if amk != null else Vector3.ZERO
		var gp3: Vector2 = giz.handle_point(1)
		var gd3: Vector2 = (giz._p(giz.pivot_point() + giz._axes_now(false)[0] * 0.1) - giz._p(giz.pivot_point())).normalized()
		_giz_drag(giz, gp3, gp3 + gd3 * 40.0)
		await _frames(10)
		var dragged: bool = amk != null and not amk.position.is_equal_approx(p_a) and not (eqp._prev.muzzle_world()[0] as Vector3).is_equal_approx(ray_a)
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		var back_pos: bool = amk != null and amk.position.is_equal_approx(p_a)
		eqp._unhandled_key_input(_ctrl_key(KEY_Z))
		await _frames(30)
		var gone_mk: bool = DRCharacter3D.find_aim_marker(ew, DRCharacter3D.MUZZLE_NAME) == null
		_expect(made and dragged and back_pos and gone_mk,
			"② 총구 표지: 만들기 → 열린 씬 무기 아래 · 기즈모 끌기 → 표지 · 미리보기 레이 옮겨짐 → Ctrl+Z 자리 → Ctrl+Z 표지 빠짐 (%s %s %s %s)" % [made, dragged, back_pos, gone_mk])
		_expect(aimed and set_ok and undo_up and undo_w and redo_w and er.aim_motion_weights.is_empty(),
			"② 조준: 미리보기 사본만 돎 · 조준 비중 · 위 한계 → 열린 씬 루트 → Ctrl+Z 한계 · Ctrl+Z 비중 빠짐(미리보기도) → Ctrl+Y → Ctrl+Z (%s %s %s %s %s)" % [aimed, set_ok, undo_up, undo_w, redo_w])
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

	# 고친 코드 적용(10-27 사용자 "적용이 안 되었는데" — 열어 둔 창은 옛 코드라 새 화면이 안 보였다): 지금은 옛 코드 없음(헛경보 없음) ·
	# 창보다 새 파일이 있으면 [고친 코드 적용] 이 보이고 누르면 다시 열기 신호 · 다시 감추기
	var stale0 := DRHubWindow.stale_scripts()
	hub._watch_code()
	var hidden0: bool = not hub._reload_btn.visible
	var made0: float = hub._made_at
	hub._made_at = 0.0
	hub._watch_code()
	var shown: bool = hub._reload_btn.visible and String(hub._reload_btn.tooltip_text).contains("고친 애드온 코드")
	var asked := [false]
	hub.reload_requested.connect(func() -> void: asked[0] = true)
	hub._reload_btn.pressed.emit()
	hub._made_at = made0
	hub._watch_code()
	_expect(stale0.is_empty() and hidden0 and shown and asked[0] and not hub._reload_btn.visible,
		"고친 코드 감시: 옛 코드 없음(%s) · 창보다 새 파일 → [고친 코드 적용] 보임 · 누르면 다시 열기 신호 · 아니면 숨김 (%s %s %s)" % [", ".join(stale0) if not stale0.is_empty() else "헛경보 없음", hidden0, shown, asked[0]])

	# 플러그인 길: [고친 코드 적용] → 옛 코드가 없으면 묻지 않고 창을 새로 만들어 연다
	var plug: Node = null
	for n in get_tree().root.find_children("*", "EditorPlugin", true, false):
		if n.get_script() != null and (n.get_script() as Script).resource_path == "res://addons/dot_rigger/plugin.gd":
			plug = n
	var reopened := false
	if plug != null:
		var old_hub = plug._hub
		await plug._reload_and_open()
		await _frames(30)
		var nh = plug._hub
		reopened = is_instance_valid(nh) and nh != old_hub and nh.visible and nh._reload_btn != null and not nh._reload_btn.visible
		if is_instance_valid(nh):
			nh.close_requested.emit()
	_expect(plug != null and reopened, "플러그인 [고친 코드 적용] → 옛 코드 없으면 묻지 않고 새 창으로 다시 엶(%s)" % ("플러그인 찾음" if plug != null else "플러그인 못 찾음"))

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
