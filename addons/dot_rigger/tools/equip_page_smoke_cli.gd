extends SceneTree

## ② 장비 탭(DREquipPage) 검사(10-16, 3D 소켓 정석) — 창 없이(--headless). 에디터 밖이라 되돌리기 없이 인스턴스를 바로 고치는 길을 탄다
## (에디터 안 길 = 열린 씬 · 되돌리기는 pipeline/check_editor.py). 시험으로 만든 파일은 끝에 지운다.
##   Godot --headless --path <프로젝트> --script res://addons/dot_rigger/tools/equip_page_smoke_cli.gd
## [1] 페이지 · 유닛 · 소켓 나무(오른손 → kar98k → 왼손 표지) · 미리보기(소켓 무기 · 도트 재질 · 숨김 부품 · 왼팔 IK)
## [2] 장비 모델 목록 · 무기 기본 자리(asset.json socket_hold — kar98k · mp40)
## [3] 동작마다 왼 손바닥 ↔ 표지(IK 전 · 뒤) — 소총 동작은 IK 뒤 1 cm 안
## [4] 자식 유닛(시험 파일): mp40 넣기(부모 kar98k 는 숨김 · 기본 자리 · 표지) · 머리 소켓 + 대용 헬멧 · 자리 숫자 · IK 비중 → 저장 → 다시 읽기
## [5] 게임처럼 다시 만들기: 숨긴 부모 무기는 지워짐 · 무기 · 헬멧이 뼈를 따라감 · 도트 재질 · fade · 수정자 MANUAL · mp40 왼손 IK
## [6] 뼈대 길이 든 사본도 소켓이 뼈를 따라감(02 U38)
## [7] 유니티식 기즈모(10-16): 단축키 · 이동(+ 눈금 · 취소 · 왼손 IK 따라옴) · 회전(고리 · 눈금 · 중심 모드) · 크기(축 · 전체 · 표지는 없음) · 눌러서 고르기
## [8] 잡기(10-16): 오른손 · 왼손 · 양손 · 고정 — 무기 자리 그대로 · 따라가는 손 IK · 게임 길
## [9] 동작별 무기 자리(10-19): 이 동작만(띠 · 크기 없음) · 끌기 → 그 동작만 · 다른 동작 기본 · 상하체 합성 = 상체 것 · 표 칸 · 모든 동작 끌기 = 기본 자리만 ·
##     숫자 칸 · 게임 길 섞어 옮기기 · 맞추기(양손 · 소켓) · 복사 · 붙여넣기 · 기본으로 · asset.json 왕복
## [10] 조준 IK(10-21): 조준 칸 = 유닛 값 · 미리보기(높낮이 · 옆 → 허리 · 가슴) · 표적 십자 · 총구 선 · 한계 · 한계 칸 · 비중 0 동작 안내 ·
##     동작 표 조준 칸(기본 · 따로 · 합성 = 상체) · 비중 절반 · 기본으로 · 끔(잠김) · 미리보기 끔
## 마지막 줄이 "EQUIP PAGE SMOKE OK" 면 통과.

const BASE := "res://game/units/soldier_base.tscn"
const CHILD := "res://game/units/시험장비_삭제.tscn"
const K98 := "res://source3d/weapons/kar98k/kar98k.tscn"
const MP40 := "res://source3d/weapons/mp40/mp40.glb"
const RIFLE := ["Rifle_Aiming_Idle", "Firing_Rifle", "Rifle_Idle", "Walk_With_Rifle", "Crouch_Idle+Firing_Rifle", "Prone_Firing_Rifle"]
const Giz := preload("res://addons/dot_rigger/ui/transform_gizmo.gd")

var _fails := PackedStringArray()


func _initialize() -> void:
	create_timer(420.0).timeout.connect(func() -> void:
		print("EQUIP PAGE SMOKE FAIL 시간 초과")
		quit(2))
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["OK  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _key(code: Key, ctrl := false) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	ev.ctrl_pressed = ctrl
	return ev


func _btn_ev(pos: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = pressed
	ev.position = pos
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed and button == MOUSE_BUTTON_LEFT else 0
	return ev


## 기즈모 층에 마우스 끌기를 흉내 낸다(누름 → 6번 움직임 → 뗌). to 가 Callable 이면 누른 뒤에 정한다(회전 고리의 접선처럼)
func _drag_on(giz: Control, from: Vector2, to: Variant, ctrl := false, release := true) -> void:
	giz._gui_input(_btn_ev(from, true))
	var dest: Vector2 = (to as Callable).call() if to is Callable else to
	var prev := from
	for i in 6:
		var m := InputEventMouseMotion.new()
		m.position = from.lerp(dest, float(i + 1) / 6.0)
		m.relative = m.position - prev
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		m.ctrl_pressed = ctrl
		prev = m.position
		giz._gui_input(m)
	if release:
		giz._gui_input(_btn_ev(dest, false))


## [7] 유니티식 기즈모 — 미리보기 사본을 끌고 놓으면 유닛 노드에 들어가는가(에디터 밖 = 바로. 되돌리기는 check_editor.py)
func _gizmo_checks(page: DREquipPage) -> void:
	print("[7] 기즈모(유니티식) — 이동 · 회전 · 크기 · 눈금 · 피벗/중심 · 취소 · 단축키 · 눌러서 고르기")
	page.select_unit(BASE)
	await _frames(3)
	var giz = page._giz
	var gw := page._weapon_equip()
	page._select_node(page._root.get_path_to(gw))
	page._playing = false
	page.play_motion("Rifle_Aiming_Idle")
	page._seek(0.3)
	page.frame_selected()
	await _frames(3)
	var pn := page._prev_node(gw) as Node3D
	_check(giz.target == pn and pn != null and giz.allow_scale, "기즈모가 고른 무기의 미리보기 사본에 걸림(크기 손잡이 있음)")

	# 단축키(유니티와 같음)
	var keys_ok := true
	for pair in [[KEY_E, Giz.Tool.ROTATE], [KEY_R, Giz.Tool.SCALE], [KEY_Q, Giz.Tool.VIEW], [KEY_Y, Giz.Tool.TRANSFORM], [KEY_W, Giz.Tool.MOVE]]:
		page._unhandled_key_input(_key(pair[0]))
		keys_ok = keys_ok and giz.tool_mode == int(pair[1]) and page._tool_btns[int(pair[1])].button_pressed
	var loc0: bool = giz.local_space
	var piv0: bool = giz.pivot_mode
	page._unhandled_key_input(_key(KEY_X))
	page._unhandled_key_input(_key(KEY_Z))
	var toggled: bool = giz.local_space != loc0 and giz.pivot_mode != piv0 and page._space_btn.text == ("로컬" if giz.local_space else "글로벌")
	page._unhandled_key_input(_key(KEY_X))
	page._unhandled_key_input(_key(KEY_Z))
	_check(keys_ok and toggled and giz.local_space == loc0 and giz.pivot_mode == piv0, "단축키 E R Q Y W → 도구 · 단추, X 로컬/글로벌 · Z 피벗/중심 켜고 끔")
	page._unhandled_key_input(_key(KEY_F))
	_check(page._target.distance_to(Giz.world_aabb(pn).get_center()) < 0.001, "F = 고른 무기를 화면 가운데로")
	await _frames(2)

	# 이동 — X 화살표를 그 화면 방향으로 60 px
	var t0: Transform3D = gw.transform
	var p := giz.handle_point(Giz.H.AX)
	_check(giz.pick(p) == Giz.H.AX, "W: X 화살표 위 점을 고르면 X 축 손잡이")
	var sdir: Vector2 = (giz._p(giz.pivot_point() + giz._axes_now(false)[0] * 0.1) - giz._p(giz.pivot_point())).normalized()
	_drag_on(giz, p, p + sdir * 60.0, false, false)
	var live_ok := absf(page._pos[0].value - pn.position.x * 100.0) < 0.051 and gw.transform.is_equal_approx(t0)     # 칸은 0.1 cm 단위로 반올림
	giz._gui_input(_btn_ev(p + sdir * 60.0, false))
	var d := gw.transform.origin - t0.origin
	_check(live_ok, "끄는 중: 숫자 칸이 사본을 따라가고 유닛 노드는 아직 그대로")
	_check(d.length() > 0.005 and d.normalized().dot(t0.basis.x.normalized()) > 0.999 and gw.transform.basis.is_equal_approx(t0.basis),
		"놓으면 유닛 노드에: 무기 로컬 X 쪽으로 %.1f cm · 회전 그대로" % (d.length() * 100.0))
	var rep := page._prev.support_report()
	_check(not rep.is_empty() and float(rep["ik"]) < 0.01, "무기를 옮겨도 왼손이 따라감(IK 뒤 %.2f cm)" % (float(rep.get("ik", 1.0)) * 100.0))
	# Ctrl = 1 cm 눈금(세상 거리) — 화면에 가장 길게 보이는 축으로
	var w0 := pn.global_position
	var bk := 0
	var bl := -1.0
	for k in 3:
		var ln: float = (giz._p(giz.pivot_point() + giz._axes_now(false)[k] * 0.1) - giz._p(giz.pivot_point())).length()
		if ln > bl:
			bl = ln
			bk = k
	p = giz.handle_point(Giz.H.AX + bk)
	sdir = (giz._p(giz.pivot_point() + giz._axes_now(false)[bk] * 0.1) - giz._p(giz.pivot_point())).normalized()
	_drag_on(giz, p, p + sdir * 37.0, true)
	var wd := pn.global_position.distance_to(w0)
	_check(wd > 0.005 and wd < 0.5 and absf(wd / 0.01 - roundf(wd / 0.01)) < 0.01, "Ctrl 끌기 = 1 cm 눈금(%s 축 37 px → %.4f m)" % ["xyz"[bk], wd])
	# 카메라를 거의 보는 축은 숨기고 못 잡는다(유니티와 같음) — 화면 25 px 미만
	var short_ok := true
	for k in 3:
		var ln: float = (giz._p(giz.pivot_point() + giz._axes_now(false)[k] * Giz.SIZE_PX * giz._wpp(giz.pivot_point())) - giz._p(giz.pivot_point())).length()
		if ln < Giz.AXIS_MIN_PX and giz.pick(giz.handle_point(Giz.H.AX + k)) == Giz.H.AX + k:
			short_ok = false
	_check(short_ok, "카메라를 거의 보는 축(화면 %d px 미만)은 못 잡음" % int(Giz.AXIS_MIN_PX))
	# 취소 — 끄는 중 오른쪽 누름
	var tc: Transform3D = gw.transform
	p = giz.handle_point(Giz.H.AZ)
	_drag_on(giz, p, p + Vector2(40, -25), false, false)
	giz._gui_input(_btn_ev(p + Vector2(40, -25), true, MOUSE_BUTTON_RIGHT))
	_check(not giz.is_dragging() and gw.transform.is_equal_approx(tc) and pn.transform.is_equal_approx(tc), "끄는 중 오른쪽 누름 = 취소(사본 · 유닛 그대로)")

	# 회전 — Z 고리를 접선으로 40 px(= 40/84 rad), Ctrl 이면 15° 눈금
	page.set_tool(Giz.Tool.ROTATE)
	await _frames(1)
	var r0: Transform3D = gw.transform
	p = giz.handle_point(Giz.H.RZ)
	_check(giz.pick(p) == Giz.H.RZ, "E: Z 고리 위 점 = Z 고리 손잡이")
	_drag_on(giz, p, func() -> Vector2: return p + giz._tan * 40.0)
	var q := Quaternion((gw.transform.basis * r0.basis.inverse()).orthonormalized())
	_check(absf(rad_to_deg(q.get_angle()) - rad_to_deg(40.0 / Giz.SIZE_PX)) < 1.0 and absf(absf(q.get_axis().dot(r0.basis.z.normalized())) - 1.0) < 0.01
		and gw.transform.origin.is_equal_approx(r0.origin), "고리를 따라 40 px → 로컬 Z 둘레 %.1f°(피벗 = 원점 그대로)" % rad_to_deg(q.get_angle()))
	var r1: Transform3D = gw.transform
	p = giz.handle_point(Giz.H.RX)
	_drag_on(giz, p, func() -> Vector2: return p + giz._tan * 40.0, true)
	q = Quaternion((gw.transform.basis * r1.basis.inverse()).orthonormalized())
	_check(absf(rad_to_deg(q.get_angle()) - 30.0) < 0.1, "Ctrl 고리 = 15° 눈금(27.3° → %.1f°)" % rad_to_deg(q.get_angle()))
	# 중심(Z) — 메시 가운데로 돌리면 원점이 움직인다
	page.set_pivot_mode(false)
	await _frames(1)
	var c0: Transform3D = gw.transform
	var piv: Vector3 = giz.pivot_point()                       # 중심 = 메시 경계 상자 가운데
	var piv_local := pn.global_transform.affine_inverse() * piv
	p = giz.handle_point(Giz.H.RY)
	_drag_on(giz, p, func() -> Vector2: return p + giz._tan * 30.0)
	_check(gw.transform.origin.distance_to(c0.origin) > 0.01 and (pn.global_transform * piv_local).distance_to(piv) < 0.001,
		"중심 모드 회전: 그 중심점은 제자리 · 원점은 %.1f cm 움직임" % (gw.transform.origin.distance_to(c0.origin) * 100.0))
	page.set_pivot_mode(true)

	# 크기 — X 축 끝을 축 길이만큼 = 2배, 가운데 = 전체, 왼손 표지는 크기 없음
	page.set_tool(Giz.Tool.SCALE)
	await _frames(1)
	var s0 := gw.scale
	p = giz.handle_point(Giz.H.SX)
	_check(giz.pick(p) == Giz.H.SX, "R: X 축 끝 = X 크기 손잡이")
	_drag_on(giz, p, func() -> Vector2: return p + giz._sdir[0] * giz._slen[0])
	_check(absf(gw.scale.x / s0.x - 2.0) < 0.05 and absf(gw.scale.y - s0.y) < 0.001 and absf(gw.scale.z - s0.z) < 0.001,
		"X 축 끝을 축 길이만큼 → x 크기 %.2f배 · y · z 그대로" % (gw.scale.x / s0.x))
	var s1 := gw.scale
	p = giz.handle_point(Giz.H.SALL)
	_drag_on(giz, p, p + Vector2(30, -30))
	_check((gw.scale / s1).is_equal_approx(Vector3.ONE * 1.6), "가운데(전체)를 오른쪽 위로 60 px → 전체 %.2f배" % (gw.scale.x / s1.x))
	var mk := DRCharacter3D.find_support(gw)
	page._select_node(page._root.get_path_to(mk))
	await _frames(2)
	_check(giz.target == page._prev_node(mk) and not giz.allow_scale and giz.pick(giz.handle_point(Giz.H.SX)) == Giz.H.NONE and not page._scl[0].editable,
		"왼손 표지를 고르면 크기 손잡이 · 크기 칸 없음")
	page.set_tool(Giz.Tool.MOVE)

	# 눌러서 고르기 — 표지 · 빈 곳(고르기 풀기) · 무기 몸통
	page._select_node(page._root.get_path_to(gw))
	var mk_pv := page._prev_node(mk) as Node3D
	page._on_view_click(page._cam.unproject_position(mk_pv.global_position))
	var picked_marker := page._sel == page._root.get_path_to(mk)
	page._on_view_click(Vector2(3, 3))
	await _frames(1)
	var cleared := page._sel.is_empty() and giz.target == null
	var mid := page._cam.unproject_position(Giz.world_aabb(pn).get_center())
	page._on_view_click(mid)
	_check(picked_marker and cleared and page._sel == page._root.get_path_to(gw), "누르기: 왼손 표지 → 빈 곳(풀기) → 무기 몸통(무기)")
	await _frames(1)
	# 기즈모 층으로 누르기(끌기 없이) — 고르기 풀린 상태에서 표지 자리를 누르면 표지
	page._on_view_click(Vector2(3, 3))
	await _frames(1)
	var mp := page._cam.unproject_position(mk_pv.global_position)
	giz._gui_input(_btn_ev(mp, true))
	giz._gui_input(_btn_ev(mp, false))
	_check(page._sel == page._root.get_path_to(mk), "기즈모 층을 눌렀다 떼면(끌기 없이) 그 자리 노드를 고름")
	page._playing = true


## 화면에 가장 길게 보이는 이동 축 손잡이(검사 끌기용)
func _long_axis(giz: Control) -> int:
	var bk := 0
	var bl := -1.0
	for k in 3:
		var ln: float = (giz._p(giz.pivot_point() + giz._axes_now(false)[k] * 0.1) - giz._p(giz.pivot_point())).length()
		if ln > bl:
			bl = ln
			bk = k
	return Giz.H.AX + bk


## 지금 두 손 IK 뒤 손바닥 ↔ 표지 중 큰 것(m) — IK 가 없는 손은 뺀다
func _hands_ik(ch: DRCharacter3D) -> float:
	var worst := 0.0
	for side in 2:
		if ch.get_arm_ik(side) != null:
			worst = maxf(worst, float(ch.support_report(side).get("ik", 1.0)))
	return worst


## [8] 잡기(10-16 확장) — 무기를 고정할 곳: 오른손 · 왼손 · 양손(두 손 사이 받침대) · 고정(땅 받침대). 사용자: "오른손 · 왼손 · 양손 —
## 어느 부분(소켓)을 고정할지 … 무기를 움직이면 오른손도 따라가거나 양손이거나". 에디터 밖 = 메모리 인스턴스만 고친다(파일 안 씀)
func _grip_checks(page: DREquipPage) -> void:
	print("[8] 잡기 — 고정할 곳(오른손 · 왼손 · 양손 · 고정)과 따라가는 손")
	page.select_unit(BASE)
	await _frames(3)
	var giz = page._giz
	var gw := page._weapon_equip()
	page._select_node(page._root.get_path_to(gw))
	page._playing = false
	page.play_motion("Rifle_Aiming_Idle")
	page._seek(0.3)
	await _frames(2)
	_check(DREquipPage.grip_kind(gw) == 0 and page._prev.get_arm_ik(0) != null and page._prev.get_arm_ik(1) == null,
		"처음(기본형 군인): 오른손이 받침 · 왼손 IK · 오른손 IK 없음")
	for step in [[1, "왼손"], [2, "양손"], [3, "고정"], [0, "오른손"]]:
		var kind: int = step[0]
		page.play_motion("Rifle_Aiming_Idle")
		page._seek(0.3)
		page._force_pose()
		var w0 := (page._prev_node(gw) as Node3D).global_transform
		page.set_grip(kind)
		await _frames(2)
		var pv := page._prev
		var pw := page._prev_node(gw) as Node3D
		var moved := pw.global_transform.origin.distance_to(w0.origin)
		var turned := rad_to_deg(pw.global_transform.basis.get_rotation_quaternion().angle_to(w0.basis.get_rotation_quaternion()))
		var follow: Array = [[0], [1], [0, 1], [0, 1]][kind]
		var ok_ik := true
		var iks := PackedStringArray()
		for side in 2:
			var has := pv.get_arm_ik(side) != null
			if has != follow.has(side):
				ok_ik = false
			if has:
				var r := pv.support_report(side)
				iks.append("%s %.2f cm" % [DRCharacter3D.SIDE_NAMES[side], float(r.get("ik", 1.0)) * 100.0])
				if r.is_empty() or float(r["ik"]) > 0.01:
					ok_ik = false
		_check(DREquipPage.grip_kind(gw) == kind and moved < 0.002 and turned < 0.5 and ok_ik,
			"%s: 받침 %s · 무기 자리 그대로(%.1f mm · %.2f°) · 따라가는 손 IK(%s)" % [step[1], gw.get_parent().name, moved * 1000.0, turned, ", ".join(iks)])
		if kind == 2:
			var gm := gw.get_parent() as DRGripMount3D
			var pm := page._prev_node(gm) as Node3D
			page.play_motion("Walk_With_Rifle")
			var pts: Array[Vector3] = []
			var worst := 0.0
			for t in [0.1, 0.4, 0.7]:
				page._seek(t)
				worst = maxf(worst, _hands_ik(pv))
				pts.append(pm.global_position)
			var spread := maxf(pts[0].distance_to(pts[1]), pts[1].distance_to(pts[2]))
			_check(spread > 0.01 and worst < 0.01, "양손: 걷기에서 무기가 두 손을 따라 움직임(%.1f cm) · 두 손 IK 뒤 최대 %.2f cm" % [spread * 100.0, worst * 100.0])
			page.set_blend(0.0)
			await _frames(1)
			pv = page._prev
			pm = page._prev_node(gm) as Node3D
			page._seek(0.4)
			pv.support_report(1)                              # 받침대를 지금 자세로 다시 풀게
			var sk := pv.get_skeleton()
			var rpos := (sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand")) * (pm as DRGripMount3D).right_offset).origin
			_check(absf(gm.blend) < 0.001 and pm.global_position.distance_to(rpos) < 0.001, "보간 오른손 100 %% → 받침대 = 오른손 쪽 자리(%.2f mm)" % (pm.global_position.distance_to(rpos) * 1000.0))
			page.set_blend(0.5)
			page.play_motion("Rifle_Aiming_Idle")
			page._seek(0.3)
			page.set_tool(Giz.Tool.MOVE)
			page._select_node(page._root.get_path_to(gw))
			await _frames(2)
			var h: int = _long_axis(giz)
			var p: Vector2 = giz.handle_point(h)
			var sd: Vector2 = (giz._p(giz.pivot_point() + giz._axes_now(false)[h - Giz.H.AX] * 0.1) - giz._p(giz.pivot_point())).normalized()
			var before := gw.transform
			_drag_on(giz, p, p + sd * 25.0)
			_check(not gw.transform.is_equal_approx(before) and _hands_ik(page._prev) < 0.01, "양손: 기즈모로 무기를 옮기면 두 손이 다 따라감(IK 뒤 최대 %.2f cm)" % (_hands_ik(page._prev) * 100.0))
		if kind == 3:
			pw = page._prev_node(gw) as Node3D
			var p0 := pw.global_position
			page.play_motion("Walk_With_Rifle")
			var drift := 0.0
			for t in [0.1, 0.5, 0.9]:
				page._seek(t)
				page._force_pose()
				drift = maxf(drift, pw.global_position.distance_to(p0))
			_check(drift < 0.0005, "고정: 동작이 바뀌어도 무기는 유닛 기준 제자리(%.2f mm)" % (drift * 1000.0))
			page.play_motion("Rifle_Aiming_Idle")
			page._seek(0.3)
			var gm := gw.get_parent() as DRGripMount3D
			page._select_node(page._root.get_path_to(gm))
			await _frames(2)
			_check(giz.target == page._prev_node(gm), "고정 받침대는 기즈모로 옮길 수 있음(두 손 사이 받침대 · 소켓은 아님)")
			var h: int = _long_axis(giz)
			var p: Vector2 = giz.handle_point(h)
			var sd: Vector2 = (giz._p(giz.pivot_point() + giz._axes_now(false)[h - Giz.H.AX] * 0.1) - giz._p(giz.pivot_point())).normalized()
			var mt0 := gm.transform
			_drag_on(giz, p, p + sd * 20.0)
			_check(not gm.transform.is_equal_approx(mt0) and _hands_ik(page._prev) < 0.01, "고정 받침대를 옮기면 무기와 두 손이 같이(IK 뒤 최대 %.2f cm)" % (_hands_ik(page._prev) * 100.0))
			page._select_node(page._root.get_path_to(gw))
	# 게임 길 — 양손으로 바꾼 유닛을 게임처럼 다시 만들어 동작을 돌린다(받침대 풀이 수정자 · 두 손 IK · MANUAL)
	page.set_grip(2)
	await _frames(1)
	var pk := PackedScene.new()
	pk.pack(page._root)
	var g := pk.instantiate() as DRCharacter3D
	root.add_child(g)
	await _frames(2)
	g.get_animation_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	g.play_motion("Walk_With_Rifle", 0.0)
	var gm2 := g.get_weapon_mount()
	var mp: Array[Vector3] = []
	var gworst := 0.0
	for i in 6:
		g.step_motion(1.0 / 12.0)
		await process_frame
		gworst = maxf(gworst, _hands_ik(g))
		mp.append(gm2.global_position)
	_check(gm2 is DRGripMount3D and g.get_arm_ik(0) != null and g.get_arm_ik(1) != null and gworst < 0.01 and mp[0].distance_to(mp[5]) > 0.005
		and g.get_skeleton().modifier_callback_mode_process == Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL,
		"게임 길(양손): 받침대가 두 손을 따라 움직이고(%.1f cm) 두 손 IK 뒤 최대 %.2f cm · 수정자 MANUAL" % [mp[0].distance_to(mp[5]) * 100.0, gworst * 100.0])
	g.queue_free()
	page.set_grip(0)
	page._playing = true


## 기즈모로 고른 노드를 긴 축 쪽으로 px 만큼 끈다
func _drag_long(giz: Control, px: float) -> void:
	var h: int = _long_axis(giz)
	var p: Vector2 = giz.handle_point(h)
	var sd: Vector2 = (giz._p(giz.pivot_point() + giz._axes_now(false)[h - Giz.H.AX] * 0.1) - giz._p(giz.pivot_point())).normalized()
	_drag_on(giz, p, p + sd * px)


## 미리보기 사본의 그 장비 자리(받침 기준)
func _shown(page: DREquipPage, e: Node3D) -> Transform3D:
	return (page._prev_node(e) as Node3D).transform


## [9] 동작별 무기 자리(10-19) — 사용자: "애니메이션별로 양손이든 왼손이든 오른손이든 총기 위치 회전 오프셋을 지정해 둘 수 있는 툴" ·
## "ui / ux 잘 신경 써 줘". 에디터 밖 = 메모리 인스턴스만 고친다(파일 안 씀 — asset.json 은 임시 사본에)
func _offset_checks(page: DREquipPage) -> void:
	print("[9] 동작별 무기 자리 — 이 동작만 · 기본 자리 · 상하체 합성 · 표 · 숫자 칸 · 게임 길 · 맞추기 · 복사 · 기본으로")
	page.select_unit(BASE)
	await _frames(3)
	var giz = page._giz
	var gw := page._weapon_equip()
	page._select_node(page._root.get_path_to(gw))
	page._playing = false
	page.set_tool(Giz.Tool.MOVE)
	page.play_motion("Firing_Rifle")
	page._seek(0.3)
	await _frames(2)
	var base0 := gw.transform
	page.set_per_motion(true)
	await _frames(2)
	_check(page._per_motion and page._pm_banner.visible and page._pm_btns[1].button_pressed and page._pm_label.text.contains("Firing_Rifle") and not giz.allow_scale,
		"이 동작만: 띠「%s」 · 단추 눌림 · 크기 손잡이 없음" % page._pm_label.text.left(48))
	_drag_long(giz, 30.0)
	await _frames(1)
	var offs := DRCharacter3D.motion_offsets(gw)
	var shown := _shown(page, gw)
	_check(offs.size() == 1 and offs.has("Firing_Rifle") and gw.transform.is_equal_approx(base0) and shown.is_equal_approx(base0 * (offs["Firing_Rifle"] as Transform3D)),
		"기즈모 끌기 → Firing_Rifle 만 저장(%s) · 기본 자리 그대로 · 미리보기 = 기본 × 차이" % page._offset_text(gw, "Firing_Rifle"))
	page.play_motion("Rifle_Idle")
	var at_idle := _shown(page, gw)
	page.play_motion("Firing_Rifle")
	_check(at_idle.is_equal_approx(base0) and _shown(page, gw).is_equal_approx(shown), "Rifle_Idle = 기본 자리 · Firing_Rifle 로 돌아오면 다시 그 자리")
	page.play_motion("Crouch_Idle+Firing_Rifle")
	_check(DRCharacter3D.offset_key(gw, "Crouch_Idle+Firing_Rifle") == "Firing_Rifle" and _shown(page, gw).is_equal_approx(shown),
		"상하체 합성 Crouch_Idle+Firing_Rifle = 상체 Firing_Rifle 자리")
	page._fill_motion_table()
	var cells := {}
	var it := page._mt.get_root().get_first_child()
	while it != null:
		cells[it.get_text(0)] = it.get_text(3)
		it = it.get_next()
	_check(String(cells.get("Firing_Rifle", "")).begins_with("●") and String(cells.get("Rifle_Idle", "")) == "기본" and String(cells.get("Crouch_Idle+Firing_Rifle", "")).begins_with("↳"),
		"동작 표 무기 자리 칸: %s · %s · %s" % [cells.get("Firing_Rifle", "-"), cells.get("Rifle_Idle", "-"), cells.get("Crouch_Idle+Firing_Rifle", "-")])
	page._update_info()
	_check(page._info.text.contains("무기 = 이 동작 자리(상체 Firing_Rifle"), "정보 줄 끝: …%s" % page._info.text.right(50))
	# 숫자 칸(이 동작만) — x +1 cm 면 그 동작 자리만 1 cm
	page.play_motion("Firing_Rifle")
	await _frames(1)
	var x0 := page._pos[0].value
	page._pos[0].value = x0 + 1.0
	var moved := (base0 * (DRCharacter3D.motion_offsets(gw)["Firing_Rifle"] as Transform3D)).origin.x - shown.origin.x
	_check(absf(moved - 0.01) < 0.0005 and gw.transform.is_equal_approx(base0), "숫자 칸(이 동작만) x +1 cm → 그 동작 자리만 %.2f cm · 기본 자리 그대로" % (moved * 100.0))
	shown = _shown(page, gw)
	# 모든 동작 — 끌면 기본 자리가 바뀌고 이 동작 차이는 그대로
	var off_keep: Transform3D = DRCharacter3D.motion_offsets(gw)["Firing_Rifle"]
	page.set_per_motion(false)
	await _frames(1)
	_check(not page._pm_banner.visible and giz.allow_scale and page._xf_note.visible, "모든 동작: 띠 없음 · 크기 손잡이 · 안내 줄「%s」" % page._xf_note.text.left(36))
	_drag_long(giz, 20.0)
	await _frames(1)
	var base1 := gw.transform
	_check(not base1.is_equal_approx(base0) and (DRCharacter3D.motion_offsets(gw)["Firing_Rifle"] as Transform3D).is_equal_approx(off_keep)
		and _shown(page, gw).is_equal_approx(base1 * off_keep), "모든 동작: 끌면 기본 자리만 바뀌고 Firing_Rifle 차이는 그대로(보이는 자리 = 새 기본 × 차이)")
	page._set_props_merged("시험: 기본 자리 되돌림", [[gw, "transform", base0]])
	# 게임 길 — 동작이 바뀔 때 손 IK 비중과 같은 시간 동안 섞어 옮긴다
	var pk := PackedScene.new()
	pk.pack(page._root)
	var g := pk.instantiate() as DRCharacter3D
	root.add_child(g)
	await _frames(2)
	g.get_animation_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	g.play_motion("Rifle_Idle", 0.0)
	g.step_motion(0.2)
	var ge := g.get_weapon_node()
	var g0 := ge.transform
	g.play_motion("Firing_Rifle", 0.2)
	g.step_motion(0.1)
	var mid := ge.transform
	var want_mid := base0 * Transform3D.IDENTITY.interpolate_with(off_keep, 0.5)
	g.step_motion(0.15)
	var end := ge.transform
	_check(g0.is_equal_approx(base0) and mid.origin.distance_to(want_mid.origin) < 0.0005 and end.is_equal_approx(base0 * off_keep) and float(g.support_report(0).get("ik", 1.0)) < 0.01,
		"게임 길: Rifle_Idle 기본 → Firing_Rifle 0.2 초 섞기(중간 %.2f mm 차) → 그 자리 · 왼손 IK %.2f cm" % [mid.origin.distance_to(want_mid.origin) * 1000.0, float(g.support_report(0).get("ik", 1.0)) * 100.0])
	g.queue_free()
	# 복사 · 붙여넣기 · 기본으로
	page.copy_motion_offset("Firing_Rifle")
	page.paste_motion_offset("Rifle_Aiming_Idle")
	var o2 := DRCharacter3D.motion_offsets(gw)
	_check(o2.has("Rifle_Aiming_Idle") and (o2["Rifle_Aiming_Idle"] as Transform3D).is_equal_approx(o2["Firing_Rifle"]), "복사 Firing_Rifle → 붙여넣기 Rifle_Aiming_Idle")
	page.reset_motion_offset("Rifle_Aiming_Idle")
	page.reset_motion_offset("Firing_Rifle")
	page.play_motion("Firing_Rifle")
	_check(not gw.has_meta(DRCharacter3D.MOTION_OFFSETS_META) and _shown(page, gw).is_equal_approx(base0), "기본으로 둘 다 → 메타 지워짐 · 미리보기 기본 자리")
	# 맞추기 — 오른손 소켓(든 손 축으로 돌림): Rifle_Idle 은 동작의 왼손이 총에서 20 cm 떨어져 있다 → 무기가 그 손 쪽으로 돌아 동작 그대로의 차이가 준다
	page.play_motion("Rifle_Idle")
	page._seek(0.3)
	page.set_per_motion(true)
	var fr := page.fit_motion_offset()
	var rb := float((fr.get("raw_before", [0, 0]) as Array)[0])
	var ra := float((fr.get("raw_after", [99, 99]) as Array)[0])
	_check(not fr.is_empty() and ra < rb * 0.5 and float((fr["after"] as Array)[0]) < 1.0 and DRCharacter3D.offset_key(gw, "Rifle_Idle") == "Rifle_Idle",
		"맞추기(오른손 소켓) Rifle_Idle: 왼손 동작 그대로 %.1f → %.1f cm · IK 뒤 %.1f cm · %s" % [rb, ra, float((fr.get("after", [9, 9]) as Array)[0]), page._offset_text(gw, "Rifle_Idle")])
	page.reset_motion_offset("Rifle_Idle")
	# 맞추기 — 양손(두 손 사이): 무기를 그 동작에서 팔이 안 닿게 밀어 둔 뒤(사용자 저장 씬의 사격 · 걷기와 같은 일 — 왼팔 6 ~ 8 cm 모자람) 맞추기 → 닿음
	page.set_per_motion(false)
	page.play_motion("Rifle_Aiming_Idle")
	page._seek(0.3)
	page._force_pose()
	page.set_grip(2)
	await _frames(1)
	gw = page._weapon_equip()
	page._select_node(page._root.get_path_to(gw))
	page.play_motion("Firing_Rifle")
	page._seek(0.4)
	page.set_per_motion(true)
	page.set_motion_offset(gw, "Firing_Rifle", Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.18)), "시험: 총구 쪽으로 18 cm 밀기")
	page._seek(0.4)
	var far := page._hand_dists()
	var fh := page.fit_motion_offset()
	var bmax := maxf(float((far["ik"] as Array)[0]), float((far["ik"] as Array)[1]))
	var amax := maxf(float((fh.get("after", [9, 9]) as Array)[0]), float((fh.get("after", [9, 9]) as Array)[1]))
	_check(not fh.is_empty() and bmax > 2.0 and amax < 1.0,
		"맞추기(양손) Firing_Rifle: 밀어 둔 무기(두 손 IK 뒤 최대 %.1f cm — 팔이 안 닿음) → 맞추기 → %.1f cm · %s" % [bmax, amax, page._offset_text(gw, "Firing_Rifle")])
	page.set_per_motion(false)
	page.reset_motion_offset("Firing_Rifle")
	page.set_grip(0)
	gw = page._weapon_equip()
	# asset.json 왕복(임시 사본) — 다른 유닛 소켓에 넣을 때 동작별 자리도
	var tmp := "user://시험_asset.json"
	var src := DREquipHold.asset_for_model(K98)
	DirAccess.copy_absolute(ProjectSettings.globalize_path(src), ProjectSettings.globalize_path(tmp))
	var off_t := Transform3D(Basis(Vector3.UP, 0.1), Vector3(0.01, 0.02, -0.03))
	var okw := DREquipHold.write_hold(tmp, "RightHand", K98, base0, null, {}, {"Firing_Rifle": off_t})
	var rh := DREquipHold.read_hold(tmp)
	_check(okw and (rh.get("motion_offsets", {}) as Dictionary).has("Firing_Rifle") and ((rh["motion_offsets"] as Dictionary)["Firing_Rifle"] as Transform3D).is_equal_approx(off_t),
		"asset.json socket_hold.motion_offsets 쓰기 → 읽기 같음")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	page._playing = true


## 높낮이(도, 수평 = 0)
static func _elev(v: Vector3) -> float:
	return rad_to_deg(asin(clampf(v.normalized().y, -1.0, 1.0)))


func _mt_row(page: DREquipPage, motion: String) -> TreeItem:
	var it := page._mt.get_root().get_first_child() if page._mt.get_root() != null else null
	while it != null and it.get_text(0) != motion:
		it = it.get_next()
	return it


func _mark_count(page: DREquipPage) -> int:
	page._draw_marks()
	if page._imesh.get_surface_count() == 0:
		return 0
	return (page._imesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()


## [10] 조준 IK(10-21) — 왼쪽 조준 칸 · 미리보기(옆 · 높낮이 → 허리 · 가슴) · 표적 · 총구 선 · 동작 표 조준 칸 · 동작별 비중 · 기본으로 · 한계 · 꺼짐
func _aim_checks(page: DREquipPage) -> void:
	print("[10] 조준 IK — 조준 칸 · 미리보기 · 표적 · 총구 선 · 동작 표 조준 칸 · 동작별 비중")
	page.select_unit(BASE)
	await _frames(3)
	var r0 := page._root
	_check(page._aim_chk.button_pressed == r0.aim_enabled and r0.aim_enabled and absf((page._aim_sp["aim_up_deg"] as SpinBox).value - r0.aim_up_deg) < 0.01,
		"조준 칸 = 유닛 값(켬 · 위로 최대 %.0f° · 아래로 최대 %.0f° · 빠르기 %.0f°/s) · 옆 칸 없음 · 설명 줄" % [r0.aim_up_deg, r0.aim_down_deg, r0.aim_speed_deg])
	_check(not page._aim_sp.has("aim_side_deg") and DREquipPage.AIM_HELP.contains("최대") and r0.get("aim_side_deg") == null, "옆(좌우) 조준 없음 — 횡스크롤(10-21 사용자 \"옆은 필요 없는 것 같아\")")
	page._playing = false
	# 조준 비중 0 동작에서 켜면 조준하는 동작으로 바꾼다(10-21 사용자 "토글 누르고 막 끌었는데 변화 없는데?" — 사용자 동작 표의 Rifle_Aiming_Idle 이 0)
	page.play_motion("Rifle_Idle")
	page.set_aim_preview(true)
	await _frames(2)
	_check(page.current_motion() == "Firing_Rifle" and page._status.text.contains("Firing_Rifle 로 바꿈") and not page._prev.aim_report().is_empty(),
		"조준 비중 0 동작(Rifle_Idle)에서 켬 → Firing_Rifle 로 바꿈 · 돎「%s」" % page._status.text.left(60))
	page.set_aim_preview(false)
	page.play_motion("Firing_Rifle")
	page._seek(0.3)
	page._aim_height_sl.set_value_no_signal(0.0)
	var marks_off := _mark_count(page)
	page._aim_height_sl.value = 20.0                 # 꺼진 채 끌면 켜진다
	await _frames(2)
	_check(page._aim_preview, "꺼진 채 높낮이를 끌면 조준 미리보기가 켜짐")
	var ar := page._prev.aim_report()
	_check(page._aim_btn.button_pressed and not ar.is_empty() and absf(_elev(ar["dir"]) - 20.0) < 0.5 and page._aim_lbl.text.contains("+20"),
		"조준 미리보기 표적 높이 +20° → 총구 높낮이 %.1f° · 든 각 %+.1f°「%s」" % [_elev(ar.get("dir", Vector3.ZERO)), float(ar.get("pitch", 0)), page._aim_lbl.text])
	page._update_info()
	_check(page._info.text.contains("(팔 +") and page._info.text.contains("허리 · 가슴"), "정보 줄: …%s" % page._info.text.right(80))
	var marks_on := _mark_count(page)
	_check(marks_on == marks_off + 14, "미리보기 표시 — 표적 십자 · 총구 선 · 견착점 십자(선 정점 %d → %d)" % [marks_off, marks_on])
	# 총구 선이 실제 총구(총열 축)에서 나간다 — 10-21 사용자 "조준선과 총구가 안 맞네? 위치가"
	var mw := page._prev.muzzle_world()
	var wn := page._prev.get_weapon_node()
	var tip_local := wn.global_transform.affine_inverse() * (mw[0] as Vector3)
	_check(absf(tip_local.y - 0.045) < 0.01 and absf(tip_local.z - 0.764) < 0.01, "총구 선 시작 = 총열 축 앞 끝(무기 로컬 y %.1f cm · z %.1f cm)" % [tip_local.y * 100.0, tip_local.z * 100.0])
	page._aim_height_sl.value = 60.0
	await _frames(1)
	ar = page._prev.aim_report()
	_check(bool(ar.get("clamped", false)) and absf(float(ar["pitch"]) - r0.aim_up_deg) < 0.5, "높낮이 +60° = 위 한계 %.0f° 에서 멈춤(돌림 %+.1f°)" % [r0.aim_up_deg, float(ar.get("pitch", 0))])
	var up0 := r0.aim_up_deg
	(page._aim_sp["aim_up_deg"] as SpinBox).value = 25.0
	await _frames(1)
	page._force_pose()
	ar = page._prev.aim_report()
	_check(absf(r0.aim_up_deg - 25.0) < 0.01 and absf(page._prev.aim_up_deg - 25.0) < 0.01 and absf(float(ar.get("pitch", 0)) - 25.0) < 0.5,
		"위 한계 칸 25° → 유닛 값 · 미리보기 사본 · 돌림 %+.1f°" % float(ar.get("pitch", 0)))
	(page._aim_sp["aim_up_deg"] as SpinBox).value = up0
	# 팔 몫 칸(% — 유닛 값은 0 ~ 1)
	var arm0 := r0.aim_arm_share
	(page._aim_sp["aim_arm_share"] as SpinBox).value = 100.0
	await _frames(1)
	page._force_pose()
	ar = page._prev.aim_report()
	_check(absf(r0.aim_arm_share - 1.0) < 0.001 and absf(page._prev.aim_arm_share - 1.0) < 0.001 and absf(float(ar.get("arm_pitch", 0)) - float(ar.get("pitch", 9))) < 0.1
		and absf(float(ar.get("body_pitch", 9))) < 0.1, "팔 몫 칸 100 %% → 유닛 값 1.0 · 미리보기 사본 · 위아래 전부 팔(%+.1f°)" % float(ar.get("arm_pitch", 0)))
	(page._aim_sp["aim_arm_share"] as SpinBox).value = arm0 * 100.0
	await _frames(1)
	_check(absf(r0.aim_arm_share - arm0) < 0.001, "팔 몫 되돌림 %d %%" % roundi(arm0 * 100.0))
	page._aim_height_sl.value = 15.0
	await _frames(1)
	# 비중 0 동작 · 안내
	page.play_motion("Rifle_Idle")
	page._force_pose()
	page._update_info()
	_check(page._prev.aim_report().is_empty() and page._info.text.contains("이 동작은 0 %") and page._aim_lbl.text.contains("조준 0 %"),
		"Rifle_Idle(조준 비중 0) = 안 돎 · 막대 옆 경고「%s」 · 정보 줄 안내" % page._aim_lbl.text)
	# 동작 표 조준 칸
	page._fill_motion_table()
	var rf := _mt_row(page, "Firing_Rifle")
	var ri := _mt_row(page, "Rifle_Idle")
	_check(rf != null and ri != null and absf(rf.get_range(4) - 1.0) < 0.001 and absf(ri.get_range(4)) < 0.001 and rf.is_editable(4),
		"동작 표 조준 칸: Firing_Rifle %.2f · Rifle_Idle %.2f(기본 — 동작 표의 사격 · 조준 상태)" % [rf.get_range(4) if rf else -1.0, ri.get_range(4) if ri else -1.0])
	page.set_aim_weight("Firing_Rifle", 0.5)
	await _frames(1)
	page._fill_motion_table()
	rf = _mt_row(page, "Firing_Rifle")
	_check(absf(float(r0.aim_motion_weights.get("Firing_Rifle", -1.0)) - 0.5) < 0.001 and absf(page._prev.aim_weight_for("Firing_Rifle") - 0.5) < 0.001
		and absf(rf.get_range(4) - 0.5) < 0.001, "Firing_Rifle 조준 0.5 → 유닛 aim_motion_weights · 미리보기 사본 · 표 칸")
	_check(absf(r0.aim_weight_for("Crouch_Idle+Firing_Rifle") - 0.5) < 0.001, "상하체 합성 Crouch_Idle+Firing_Rifle = 상체 Firing_Rifle 값 0.5")
	page.play_motion("Firing_Rifle")
	page._force_pose()
	ar = page._prev.aim_report()
	_check(absf(float(ar.get("weight", 0)) - 0.5) < 0.001, "비중 0.5 = 돌림도 절반(비중 %.2f · 위아래 %+.1f°)" % [float(ar.get("weight", 0)), float(ar.get("pitch", 0))])
	page.set_aim_weight("Firing_Rifle", null)
	page.set_aim_weight("Rifle_Idle", 1.0)
	_check(not r0.aim_motion_weights.has("Firing_Rifle") and absf(float(r0.aim_motion_weights.get("Rifle_Idle", -1.0)) - 1.0) < 0.001, "조준 비중 기본으로(Firing_Rifle) · Rifle_Idle 따로 1")
	page.set_aim_weight("Rifle_Idle", 0.0)
	_check(r0.aim_motion_weights.is_empty(), "기본과 같은 값으로 고치면 따로 값을 지움(aim_motion_weights 비어 있음)")
	# 꺼짐
	page._aim_chk.button_pressed = false
	await _frames(1)
	page._force_pose()
	page._fill_motion_table()
	rf = _mt_row(page, "Firing_Rifle")
	_check(not r0.aim_enabled and not page._prev.aim_enabled and page._prev.aim_report().is_empty() and not rf.is_editable(4) and not (page._aim_sp["aim_up_deg"] as SpinBox).editable,
		"조준 끔 → 유닛 · 미리보기 사본 · 안 돎 · 표 칸 · 숫자 칸 잠김")
	page._aim_chk.button_pressed = true
	await _frames(1)
	await _aim_marker_checks(page)
	page.set_aim_preview(false)
	_check(not page._aim_btn.button_pressed and page._prev.aim_report().is_empty() and _mark_count(page) == marks_off, "조준 미리보기 끔 → 동작 그대로 · 표시 없음")
	page._playing = true


## 미리보기 무기 기준 지금 레이(총구 선) [시작점, 방향] — 무기 로컬
func _ray_local(page: DREquipPage) -> Array:
	var w := page._prev.get_weapon_node()
	var mw := page._prev.muzzle_world()
	var inv := w.global_transform.affine_inverse()
	return [inv * (mw[0] as Vector3), (inv.basis * (mw[1] as Vector3)).normalized()]


## [10] 이어서 — 조준 표지(총구 · 견착) 기즈모 연동(10-21 사용자 "조준선과 총구 위치(즉 레이 기능) — 그 위치를 조정할 수 있는 기즈모 기능 연동도 필요해")
func _aim_marker_checks(page: DREquipPage) -> void:
	var r0 := page._root
	var wn := page._weapon_equip()
	page._select_node(r0.get_path_to(wn))
	var ray0 := _ray_local(page)
	var mk := page.make_aim_marker(DRCharacter3D.MUZZLE_NAME)
	await _frames(2)
	var items := page._all_items(page._tree.get_root())
	var in_tree := false
	for it in items:
		in_tree = in_tree or it.get_text(0).contains("총구 표지")
	_check(mk != null and mk.get_parent() == wn and mk.owner == r0 and mk.position.distance_to(ray0[0] as Vector3) < 0.001 and page._node(page._sel) == mk
		and page._gizmo_target() == page._prev_node(mk) and DREquipPage._is_marker(mk) and in_tree and page._giz.tool_mode == Giz.Tool.MOVE,
		"[총구 표지] → 무기 아래 Marker3D(주인 = 유닛) · 지금 레이 자리에 · 골라짐 · 기즈모 대상 · 이동 도구 · 크기 없음 · 나무 줄")
	page._pos[1].value = page._pos[1].value + 2.0          # 숫자 칸 y +2 cm(기즈모와 같은 길 — 고른 노드 자리)
	await _frames(2)
	page._force_pose()
	var ray1 := _ray_local(page)
	_check(absf((ray1[0] as Vector3).y - (ray0[0] as Vector3).y - 0.02) < 0.001, "총구 표지 y +2 cm → 미리보기 레이 시작점도 %+.1f cm" % (((ray1[0] as Vector3).y - (ray0[0] as Vector3).y) * 100.0))
	page._rot[0].value = page._rot[0].value + 10.0
	await _frames(2)
	page._force_pose()
	var ray2 := _ray_local(page)
	var turned := rad_to_deg((ray2[1] as Vector3).angle_to(ray0[1] as Vector3))
	_check(absf(turned - 10.0) < 0.5, "총구 표지 x 회전 +10° → 레이 방향 %.1f° 바뀜(파란 축 = 방향)" % turned)
	page._set_props_merged("시험: 총구 표지 직접", [[mk, "position", (ray0[0] as Vector3) + Vector3(0.0, 0.0, 0.05)], [mk, "rotation_degrees", Vector3.ZERO]])
	await _frames(2)
	var pm := page._prev_node(mk) as Node3D
	pm.position = (ray0[0] as Vector3) + Vector3(0.0, 0.03, 0.05)       # 기즈모로 끄는 중(미리보기 사본만) — 레이가 바로 따라오나
	page._on_giz_changed(pm)
	var ray3 := _ray_local(page)
	_check((ray3[0] as Vector3).distance_to((ray0[0] as Vector3) + Vector3(0.0, 0.03, 0.05)) < 0.001, "기즈모로 끄는 중에도 레이가 따라옴(놓기 전 — 미리보기 사본)")
	page._sync_preview()
	page.set_aim_preview(true)
	page._aim_height_sl.value = 10.0
	await _frames(2)
	var marks := _mark_count(page)
	page.set_aim_preview(false)
	page._select_node(r0.get_path_to(mk))
	var marks_sel := _mark_count(page)
	_check(marks_sel >= 8 and marks_sel < marks, "미리보기를 꺼도 총구 표지를 고르면 레이 · 견착점을 그림(선 정점 %d — 미리보기 중 %d)" % [marks_sel, marks])
	var shk := page.make_aim_marker(DRCharacter3D.SHOULDER_NAME)
	await _frames(2)
	page._force_pose()
	var sw := page._prev.shoulder_world()
	_check(shk != null and shk.get_parent() == wn and sw.distance_to((page._prev_node(shk) as Node3D).global_position) < 0.001 and shk.position.y < -0.01,
		"[견착 표지] → 개머리판 끝 가운데(y %.1f cm) · 미리보기 견착점 = 그 표지" % (shk.position.y * 100.0 if shk != null else 0.0))
	# asset.json 왕복(임시 사본) — 다른 유닛에 넣을 때 따라감
	var tmp := "user://시험_조준_asset.json"
	DirAccess.copy_absolute(ProjectSettings.globalize_path(DREquipHold.asset_for_model(K98)), ProjectSettings.globalize_path(tmp))
	var aims := {DRCharacter3D.MUZZLE_NAME: mk.transform, DRCharacter3D.SHOULDER_NAME: shk.transform}
	var okw := DREquipHold.write_hold(tmp, "RightHand", K98, wn.transform, null, {}, {}, aims)
	var rh := DREquipHold.read_hold(tmp)
	var am: Dictionary = rh.get("aim_markers", {})
	_check(okw and am.size() == 2 and (am[DRCharacter3D.MUZZLE_NAME] as Transform3D).is_equal_approx(mk.transform), "asset.json socket_hold.aim_markers 쓰기 → 읽기 같음(총구 · 견착)")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	page.clear_aim_markers()
	await _frames(2)
	page._force_pose()
	var ray4 := _ray_local(page)
	_check(DRCharacter3D.find_aim_marker(wn, DRCharacter3D.MUZZLE_NAME) == null and DRCharacter3D.find_aim_marker(wn, DRCharacter3D.SHOULDER_NAME) == null
		and (ray4[0] as Vector3).distance_to(ray0[0] as Vector3) < 0.001, "[자동으로] → 표지 지움 · 레이가 메시에서 잰 자리로 돌아옴")


func _dot(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return false
	var m := mi.get_surface_override_material(0) as ShaderMaterial
	return m != null and m.shader != null and m.shader.resource_path.ends_with("dot_char.gdshader")


func _run() -> void:
	if FileAccess.file_exists(CHILD):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHILD))
	var page := DREquipPage.new()
	root.add_child(page)
	page.test_layout(Vector2i(1400, 860))
	await _frames(3)

	print("[1] 페이지 · 유닛 · 소켓 · 미리보기")
	_check(page._units.has(BASE) and page._sel_path == BASE and page._root != null, "유닛 목록 %d개 · 고른 유닛 %s" % [page._units.size(), page._sel_path.get_file()])
	var socks := page._sockets()
	var w := page._weapon_equip()
	var mk := DRCharacter3D.find_support(w) if w != null else null
	_check(socks.size() >= 1 and socks[0].bone_name == "RightHand" and w != null and w.scene_file_path == K98 and mk is DRHandTarget3D,
		"소켓 %s(%s) → %s → 왼손 표지 %s" % [socks[0].name if not socks.is_empty() else "-", socks[0].bone_name if not socks.is_empty() else "-", w.name if w != null else "-", mk.name if mk != null else "-"])
	_check(page._all_items(page._tree.get_root()).size() >= 3, "소켓 나무 %d줄" % page._all_items(page._tree.get_root()).size())
	var pv := page._prev
	_check(pv != null and pv.get_weapon_node() != null and pv.get_weapon_node().scene_file_path == K98 and pv.get_left_arm_ik() != null, "미리보기: 소켓 무기 · 왼팔 IK")
	var dots := 0
	for mi in (pv.get_equipment_meshes() if pv != null else []):
		if _dot(mi):
			dots += 1
	var bullets := pv.get_weapon_node().get_node_or_null("bullets") as Node3D if pv != null else null
	_check(dots >= 3 and bullets != null and not bullets.visible and not pv.get_equipment_meshes().has(bullets), "장비 메시 도트 재질 %d개 · 탄 클립 숨김(재질도 안 입힘)" % dots)
	_check(pv != null and pv.get_skeleton().modifier_callback_mode_process == Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL, "미리보기 사본 수정자 = 자세가 바뀔 때만(MANUAL)")
	page.play_motion("Firing_Rifle")
	await _frames(12)
	var live0: Dictionary = page._live[0] if page._live.size() > 0 else {}
	_check(page.current_motion() == "Firing_Rifle" and pv.get_ik_weight() > 0.99 and float(live0.get("dist", 1.0)) < 0.01,
		"Firing_Rifle 재생 · 왼손 IK 비중 %.2f · 미리보기 갱신 때 손바닥 ↔ 표지 %.2f cm" % [pv.get_ik_weight(), float(live0.get("dist", 1.0)) * 100.0])
	page._update_info()
	print("        정보 줄: ", page._info.text)

	print("[2] 장비 모델 · 무기 기본 자리")
	var models := PackedStringArray()
	for i in page._model_ob.item_count:
		models.append(String(page._model_ob.get_item_metadata(i)))
	_check(models.has(K98) and models.has(MP40) and models.has(DREquipHold.PLACEHOLDER_HELMET), "모델 목록 %d개(%s)" % [models.size(), ", ".join(models)])
	var hk := DREquipHold.read_hold(DREquipHold.asset_for_model(K98))
	var hm := DREquipHold.read_hold(DREquipHold.asset_for_model(MP40))
	_check(not hk.is_empty() and hk.has("support") and String(hk["scene"]) == K98 and not hm.is_empty() and hm.has("support"), "기본 자리: kar98k(%s) · mp40(%s)" % [str(not hk.is_empty()), str(not hm.is_empty())])
	_check(not hk.is_empty() and (hk["weapon"] as Transform3D).is_equal_approx(w.transform), "kar98k 기본 자리 = soldier_base 의 자리")

	print("[3] 동작마다 왼 손바닥 ↔ 표지(8 시점 평균 / 최대 cm, IK 전 → 뒤)")
	var rep := page.measure_all()
	var by := {}
	for r in rep:
		var d: Dictionary = r
		by[String(d["motion"])] = d
		print("        %-30s 비중 %.1f · IK 전 %5.1f / %5.1f → IK 뒤 %4.1f / %4.1f" % [d["motion"], d["weight"], float(d["raw_avg"]) * 100.0, float(d["raw_max"]) * 100.0, float(d["ik_avg"]) * 100.0, float(d["ik_max"]) * 100.0])
	var bad := PackedStringArray()
	for m in RIFLE:
		if not by.has(m) or float((by[m] as Dictionary)["ik_max"]) > 0.01:
			bad.append(m)
	_check(rep.size() >= 20 and bad.is_empty(), "소총 동작 %d개 IK 뒤 최대 1 cm 안%s" % [RIFLE.size(), "" if bad.is_empty() else " — 넘음: " + ", ".join(bad)])
	_check(by.has("Sprint") and float((by["Sprint"] as Dictionary)["weight"]) == 0.0 and by.has("Toss_Grenade") and float((by["Toss_Grenade"] as Dictionary)["weight"]) == 0.0, "맨손 달리기 · 수류탄 = IK 비중 0(왼손 그대로)")
	_check(page._mt.get_root() != null and page._mt.get_root().get_child_count() == rep.size(), "동작 표 %d줄" % (page._mt.get_root().get_child_count() if page._mt.get_root() != null else 0))

	print("[4] 자식 유닛 — 무기 바꾸기 · 헬멧 소켓 · 자리 · 비중 · 저장 · 다시 읽기")
	var f := FileAccess.open(CHILD, FileAccess.WRITE)
	f.store_string("[gd_scene load_steps=2 format=3]\n\n[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1_parent\"]\n\n[node name=\"시험장비\" instance=ExtResource(\"1_parent\")]\n" % BASE)
	f.close()
	page.scan_units()
	page.select_unit(CHILD)
	await _frames(2)
	_check(page._sel_path == CHILD and page._base_paths.has("오른손/kar98k"), "자식 유닛 고름 · 부모에서 온 노드 %d개(오른손/kar98k 포함)" % page._base_paths.size())
	page._select_node(NodePath("오른손"))
	var mp := page.put_model(MP40)
	await _frames(2)
	var k_old := page._root.get_node_or_null("오른손/kar98k") as Node3D
	var mmk := DRCharacter3D.find_support(mp) if mp != null else null
	_check(mp != null and k_old != null and not k_old.visible and mp.visible and mp.transform.is_equal_approx(hm["weapon"]), "mp40 넣음 — 부모 kar98k 는 숨김(지울 수 없음) · 기본 자리 그대로")
	_check(mmk is DRHandTarget3D and (mmk as Node3D).transform.is_equal_approx(hm["support"]) and (mmk as DRHandTarget3D).motion_weights.size() == (hm["motion_weights"] as Dictionary).size(), "mp40 왼손 표지 · 동작별 비중 %d개(기본 자리에서)" % ((mmk as DRHandTarget3D).motion_weights.size() if mmk is DRHandTarget3D else -1))
	_check(page._prev != null and page._prev.get_weapon_node() != null and page._prev.get_weapon_node().scene_file_path == MP40, "미리보기 무기 = mp40")
	var head := page.add_socket("", "Head")
	page._select_node(page._root.get_path_to(head))
	var helmet := page.put_model(DREquipHold.PLACEHOLDER_HELMET)
	_check(head != null and head.name == "머리" and helmet != null and helmet.get_parent() == head, "머리 소켓(Head) + 대용 헬멧")
	page._select_node(page._root.get_path_to(helmet))
	page._pos[1].value = 12.0
	_check(absf(helmet.position.y - 0.12) < 0.0005, "숫자 칸 → 헬멧 위치 y %.3f m" % helmet.position.y)
	page._select_node(page._root.get_path_to(mp))
	page.set_motion_weight("Rifle_Idle", 0.5)
	_check(mmk is DRHandTarget3D and absf(float((mmk as DRHandTarget3D).motion_weights.get("Rifle_Idle", -1.0)) - 0.5) < 0.001, "IK 비중 Rifle_Idle = 0.5(표지 motion_weights)")
	page.save_unit()
	var txt := FileAccess.get_file_as_string(CHILD)
	print("        저장한 자식 씬:\n" + txt.indent("          ").substr(0, 2400))
	_check(txt.contains("instance=ExtResource") and txt.contains("mp40.glb") and txt.contains("visible = false") and txt.contains("bone_name = \"Head\"") and txt.contains("\"Rifle_Idle\": 0.5"),
		"자식 씬 = 부모 상속 + kar98k 숨김 + mp40 · 표지 + 머리 소켓 · 헬멧")
	_check(not txt.contains("outfit_top") and not txt.contains("DR_LeftArmIK"), "안 바꾼 칸 · 내부 IK 노드는 파일에 없음")
	var back := (ResourceLoader.load(CHILD, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN) as Node3D
	var bmp := back.get_node_or_null("오른손/mp40") as Node3D
	var bmk := DRCharacter3D.find_support(bmp) if bmp != null else null
	var bhl := back.get_node_or_null("머리/헬멧_대용") as Node3D
	_check(bmp != null and bmp.transform.is_equal_approx(mp.transform) and bmk != null and bmk.transform.is_equal_approx((mmk as Node3D).transform)
		and bhl != null and absf(bhl.position.y - 0.12) < 0.0005, "다시 읽기: mp40 자리 · 표지 · 헬멧 자리가 같음")
	back.free()

	print("[5] 게임처럼 다시 만들기(에디터 밖 = 게임 길)")
	var g := (ResourceLoader.load(CHILD, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as DRCharacter3D
	root.add_child(g)
	await _frames(2)
	var gs := g.get_node_or_null("오른손")
	var kept := gs.get_node_or_null("kar98k") if gs != null else null
	_check(gs != null and kept == null and g.get_weapon_node() != null and g.get_weapon_node().scene_file_path == MP40, "숨긴 부모 무기는 지워짐 · 무기 = mp40")
	g.get_animation_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	g.play_motion("Firing_Rifle", 0.0)
	var sk := g.get_skeleton()
	var hs := g.get_node("머리") as BoneAttachment3D
	var worst_r := 0.0
	var worst_h := 0.0
	var worst_ik := 0.0
	for i in 6:
		g.step_motion(1.0 / 12.0)
		await process_frame
		var rh := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand"))
		var hd := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))
		worst_r = maxf(worst_r, rh.origin.distance_to((gs as Node3D).global_position))
		worst_h = maxf(worst_h, hd.origin.distance_to(hs.global_position))
		worst_ik = maxf(worst_ik, float(g.support_report().get("ik", 1.0)))
	_check(worst_r < 0.001 and worst_h < 0.001, "소켓이 뼈를 따라감(오른손 %.4f m · 머리 %.4f m 어긋남)" % [worst_r, worst_h])
	_check(worst_ik < 0.01, "mp40 Firing_Rifle 왼 손바닥 ↔ 표지 IK 뒤 최대 %.2f cm" % (worst_ik * 100.0))
	var gd := 0
	var helmet_dot := false
	for mi in g.get_equipment_meshes():
		if _dot(mi):
			gd += 1
			if String(mi.name) == "헬멧_대용":
				helmet_dot = true
	_check(gd >= 2 and helmet_dot, "장비 도트 재질 %d개(헬멧 포함)" % gd)
	_check(sk.modifier_callback_mode_process == Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL, "게임: 수정자 = 자세가 바뀔 때만(MANUAL)")
	g.set_fade(0.0)
	var hidden := not (gs as Node3D).visible and not hs.visible
	g.set_fade(1.0)
	_check(hidden and (gs as Node3D).visible and hs.visible, "set_fade(0) 이면 소켓 장비도 숨김 · 1 이면 다시 보임")

	print("[6] 뼈대 길이 든 사본 — ① ② 미리보기는 조립된 열린 씬을 pack 한다(소켓의 길까지 담김). 그 길이 저장된 씬도 같다")
	var path_in := String((gs as BoneAttachment3D).external_skeleton)
	var pk := PackedScene.new()
	pk.pack(g)
	var c2 := pk.instantiate() as DRCharacter3D
	root.add_child(c2)
	await _frames(2)
	c2.get_animation_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	c2.play_motion("Firing_Rifle", 0.0)
	var sk2 := c2.get_skeleton()
	var s2 := c2.get_node("오른손") as BoneAttachment3D
	var worst2 := 0.0
	for i in 6:
		c2.step_motion(1.0 / 12.0)
		await process_frame
		var rh2 := sk2.global_transform * sk2.get_bone_global_pose(sk2.find_bone("RightHand"))
		worst2 = maxf(worst2, rh2.origin.distance_to(s2.global_position))
	_check(path_in != "" and worst2 < 0.001, "길(%s)이 든 사본도 소켓이 뼈를 따라감(%.4f m 어긋남)" % [path_in, worst2])
	c2.queue_free()
	g.queue_free()

	await _gizmo_checks(page)
	await _grip_checks(page)
	await _offset_checks(page)
	await _aim_checks(page)

	# 치우기
	page._drop_root()
	page.queue_free()
	await _frames(2)
	if FileAccess.file_exists(CHILD):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHILD))
	_check(not FileAccess.file_exists(CHILD), "시험 파일 지움")
	if _fails.is_empty():
		print("EQUIP PAGE SMOKE OK")
	else:
		print("EQUIP PAGE SMOKE FAIL ", ", ".join(_fails))
	quit(0 if _fails.is_empty() else 1)
