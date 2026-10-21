extends SceneTree

## 조준 IK 검사(10-21) — 창 없이(--headless). DRCharacter3D 의 조준 수정자(허리 · 가슴을 돌려 총구가 표적으로)를 사람 몸 + kar98k 로 잰다.
##   Godot --headless --path <프로젝트> --script res://addons/dot_rigger/tools/aim_check_cli.gd
## [1] 구조: 조준 수정자가 뼈대 수정자 차례 맨 앞 · 총구(kar98k +Z 앞 끝) · 돌릴 뼈 셋
## [2] 기본 조준 비중 = 동작 표의 사격 · 조준 상태(Firing_Rifle · 앉기+사격 합성 · 엎드려 사격 1, Rifle_Idle · Sprint · 걷기 0) · 동작별 값 · 합성 = 상체 것
## [3] 표적 정면 · 위 · 아래 · 옆 · 한계 넘음(멈춤) — 총구 기준 ↔ 표적 각
## [4] 실제 총구(반동 포함)의 한 바퀴 평균이 표적으로 · 동작의 흔들림은 그대로(조준 전과 같은 크기)
## [5] 비중 0 동작 · 꺼짐(aim_enabled) · 표적 거둠 = 동작 그대로(뼈 자세가 조준 없을 때와 같음)
## [6] 왼손 IK 가 돌린 자세에서도 총을 잡음(1 cm 안) · 빠르기(초당 각) · 동작이 바뀔 때 비중 섞기
## [7] 게임처럼(캐릭터 돌림 · 키 배율) · 상하체 합성 · 엎드려 사격
## [8] 양손 받침대(두 손 사이 — 시험 파일이 있으면): 두 손 IK · 조준(받침대를 견착점 축으로) · 고정 받침대 = 조준 안 함
## [9] 팔 · 견착(10-21 저녁): 팔 몫 0 · 70 · 100 % 실제 총구 높낮이 · 가슴 뼈 덜 숙임 · 100 % 면 견착점 제자리 · 거두면 팔 IK 꺼짐
## 마지막 줄이 "AIM CHECK OK" 면 통과.

const BASE := "res://game/units/soldier_base.tscn"
const TWO := "res://game/units/_twohand_test.tscn"     # 샌드박스 전용(사용자 양손 씬 사본) — 없으면 [8] 건너뜀
const DT := 1.0 / 12.0

var _fails := PackedStringArray()


func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void:
		print("AIM CHECK FAIL 시간 초과")
		quit(2))
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["OK  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


## 뼈대를 지금 바로 갱신(수정자까지) — 자세를 바꾼 같은 프레임에 잴 때
func _force(ch: DRCharacter3D) -> void:
	var sk := ch.get_skeleton()
	sk.set_bone_pose_rotation(0, sk.get_bone_pose_rotation(0))
	sk.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)


func _step(ch: DRCharacter3D, n: int = 1) -> void:
	for i in n:
		ch.step_motion(DT)
		_force(ch)


## 캐릭터 공간 방향(옆 yaw · 위아래 pitch 도) 으로 가슴 높이에서 dist m 떨어진 표적(세상 좌표)
func _target(ch: DRCharacter3D, yaw: float, pitch: float, dist: float = 10.0) -> Vector3:
	var y := deg_to_rad(yaw)
	var p := deg_to_rad(pitch)
	var d := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p))
	return ch.to_global(Vector3(0.0, 1.35, 0.0) + d * dist)


func _make(path: String) -> DRCharacter3D:
	var ch := (load(path) as PackedScene).instantiate() as DRCharacter3D
	root.add_child(ch)
	ch.get_animation_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return ch


func _start(ch: DRCharacter3D, motion: String, frac: float = 0.3) -> void:
	ch.play_motion(motion, 0.0)
	var ap := ch.get_animation_player()
	ap.seek(ap.get_animation(motion).length * frac, true)
	_force(ch)


## 수정자를 거친 가슴(UpperChest) 자세 — 갱신 신호 안에서 읽는다(갱신이 끝나면 뼈대는 동작 자세로 돌아가 있다)
func _upper_pose(ch: DRCharacter3D) -> Transform3D:
	var sk := ch.get_skeleton()
	var bi := sk.find_bone("UpperChest")
	var got := [Transform3D.IDENTITY]
	var cb := func() -> void: got[0] = sk.get_bone_global_pose(bi)
	sk.skeleton_updated.connect(cb)
	_force(ch)
	sk.skeleton_updated.disconnect(cb)
	return got[0]


## 높낮이(도, 수평 = 0)
static func _elev(v: Vector3) -> float:
	return rad_to_deg(asin(clampf(v.normalized().y, -1.0, 1.0)))


## 한 바퀴(동작 길이) 동안 실제 총구 방향 — [평균 방향, 평균에서 벗어난 각의 평균(도)]. 세상 좌표
func _sweep(ch: DRCharacter3D, motion: String) -> Array:
	_start(ch, motion, 0.0)
	var n := ceili(ch.get_animation_player().get_animation(motion).length / DT)
	var dirs: Array[Vector3] = []
	var mean := Vector3.ZERO
	for i in n:
		_step(ch)
		var m := ch.muzzle_world()
		dirs.append(m[1])
		mean += m[1]
	mean = mean.normalized()
	var dev := 0.0
	for d in dirs:
		dev += rad_to_deg(d.angle_to(mean)) / float(dirs.size())
	return [mean, dev]


func _run() -> void:
	await process_frame
	var ch := _make(BASE)
	await process_frame
	var sk := ch.get_skeleton()

	print("[1] 구조")
	var mods: Array = []
	for c in sk.get_children():
		if c is SkeletonModifier3D:
			mods.append(String(c.name))
	_check(not mods.is_empty() and mods[0] == "DR_AimSolver", "조준 수정자가 맨 앞 — %s" % ", ".join(PackedStringArray(mods)))
	var mz := DRCharacter3D.find_muzzle(ch.get_weapon_node())
	_check(not mz.is_empty() and absf((mz[0] as Vector3).z - 0.764) < 0.01 and absf((mz[0] as Vector3).y - 0.045) < 0.01 and (mz[1] as Vector3).is_equal_approx(Vector3.BACK)
		and absf((mz[2] as Vector3).z + 0.346) < 0.01 and (mz[2] as Vector3).y < -0.01,
		"kar98k 총구 = +Z 앞 끝의 총열 축(원점보다 %.1f cm 위 — 10-21 사용자 \"조준선과 총구가 안 맞네\") · 견착점 = 개머리판 끝 가운데(%.1f cm 아래) %s" % [
		(mz[0] as Vector3).y * 100.0, -(mz[2] as Vector3).y * 100.0, str(mz)])

	print("[2] 기본 조준 비중")
	var expect := {"Firing_Rifle": 1.0, "Crouch_Idle+Firing_Rifle": 1.0, "Prone_Firing_Rifle": 1.0, "Rifle_Idle": 0.0, "Sprint": 0.0, "Walk_With_Rifle": 0.0}
	var bad := PackedStringArray()
	for mo in expect:
		if absf(ch.aim_weight_for(mo) - float(expect[mo])) > 0.001:
			bad.append("%s=%.2f" % [mo, ch.aim_weight_for(mo)])
	_check(bad.is_empty(), "사격 · 조준 상태 = 1, 나머지 0 %s" % ", ".join(bad))
	ch.aim_motion_weights = {"Firing_Rifle": 0.5, "Rifle_Idle": 0.8}
	_check(absf(ch.aim_weight_for("Firing_Rifle") - 0.5) < 0.001 and absf(ch.aim_weight_for("Rifle_Idle") - 0.8) < 0.001 and
		absf(ch.aim_weight_for("Crouch_Idle+Firing_Rifle") - 0.5) < 0.001, "동작별 값 · 합성 = 상체 것(0.5)")
	ch.aim_motion_weights = {}

	print("[3] 표적 방향")
	_start(ch, "Firing_Rifle")
	var no_aim := _upper_pose(ch)
	var hdir0 := ch.muzzle_world()[1] as Vector3       # 조준 전 실제 총구의 좌우 방향
	for c in [[0.0, 0.0, "정면"], [0.0, 25.0, "위 25°"], [0.0, -20.0, "아래 20°"], [12.0, 5.0, "옆으로 12° 벗어난 표적 · 위 5°"]]:
		var tp := _target(ch, c[0], c[1])
		ch.set_aim_target(tp, true)
		_force(ch)
		var r := ch.aim_report()
		var el_t := _elev(ch.global_transform.basis.inverse() * (tp - ch.to_global(r.get("muzzle", Vector3.ZERO))))   # 총구에서 본 표적 높낮이
		var el_m := _elev(r.get("dir", Vector3.ZERO))
		var hd := ch.muzzle_world()[1] as Vector3
		var side := rad_to_deg(Vector2(hd.x, hd.z).angle_to(Vector2(hdir0.x, hdir0.z)))     # 좌우는 안 돈다(횡스크롤 — 10-21 사용자 "옆은 필요 없는 것 같아")
		_check(not r.is_empty() and float(r["err"]) < 0.5 and absf(el_m - el_t) < 0.5 and absf(side) < 1.0 and not bool(r["clamped"]),
			"%s — 총구 높낮이 %.1f° (표적 %.1f°) · 든 각 %+.1f° · 좌우 그대로(%.2f°) · 동작 원래 높낮이 %.1f°" % [c[2], el_m, el_t,
			float(r.get("pitch", 0)), side, float(r.get("base_pitch", 0))])
	ch.set_aim_elevation(12.0, true)
	_force(ch)
	var ra := ch.aim_report()
	_check(not ra.is_empty() and absf(_elev(ra["dir"]) - 12.0) < 0.3, "높낮이로(② 탭 미리보기): 12° → 총구 높낮이 %.1f°" % _elev(ra.get("dir", Vector3.ZERO)))
	ch.set_aim_target(_target(ch, 0.0, 70.0), true)
	_force(ch)
	var rl := ch.aim_report()
	_check(bool(rl.get("clamped", false)) and absf(float(rl["pitch"]) - ch.aim_up_deg) < 0.5,
		"위 70° = 한계 %.0f° 에서 멈춤 — 돌림 %.1f° (필요 %.1f°)" % [ch.aim_up_deg, float(rl.get("pitch", 0)), float(rl.get("want_pitch", 0))])

	print("[4] 실제 총구 · 동작의 흔들림")
	ch.clear_aim_target(true)
	var before: Array = _sweep(ch, "Firing_Rifle")
	ch.set_aim_target(_target(ch, 0.0, 25.0), true)
	var after: Array = _sweep(ch, "Firing_Rifle")
	var tdir: Vector3 = _target(ch, 0.0, 25.0) - (ch.muzzle_world()[0] as Vector3)
	var mean_err := absf(_elev(after[0]) - _elev(tdir))
	_check(mean_err < 1.5, "위 25° 표적 — 한 바퀴 평균 총구 높낮이 %.1f° ↔ 표적 %.1f° (조준 전 %.1f°)" % [_elev(after[0]), _elev(tdir), _elev(before[0])])
	var ratio := float(after[1]) / maxf(float(before[1]), 0.001)
	_check(ratio > 0.7 and ratio < 1.3, "동작의 흔들림 그대로 — 평균에서 벗어난 각 %.2f° → %.2f°" % [float(before[1]), float(after[1])])

	print("[5] 동작 그대로인 경우")
	_start(ch, "Rifle_Idle")
	ch.clear_aim_target(true)
	_force(ch)
	var idle_raw := _upper_pose(ch)
	ch.set_aim_target(_target(ch, 0.0, 25.0), true)
	_force(ch)
	_check(_upper_pose(ch).is_equal_approx(idle_raw) and ch.aim_report().is_empty(), "Rifle_Idle(비중 0) = 표적이 있어도 동작 그대로")
	_start(ch, "Firing_Rifle")
	ch.aim_enabled = false
	ch.play_motion("Firing_Rifle", 0.0)
	_force(ch)
	_check(_upper_pose(ch).is_equal_approx(no_aim), "aim_enabled 끔 = 동작 그대로")
	ch.aim_enabled = true
	ch.play_motion("Firing_Rifle", 0.0)
	_force(ch)
	_check(not _upper_pose(ch).is_equal_approx(no_aim), "다시 켬 = 돌림")
	ch.clear_aim_target()
	_step(ch, int(ceil(DRCharacter3D.AIM_FADE_SEC / DT)) + 1)
	_start(ch, "Firing_Rifle")
	_check(_upper_pose(ch).is_equal_approx(no_aim) and ch.aim_report().is_empty(), "표적 거둠 → %.2f 초 뒤 동작 그대로" % DRCharacter3D.AIM_FADE_SEC)

	print("[6] 왼손 · 빠르기 · 섞기")
	_start(ch, "Firing_Rifle")
	ch.set_aim_target(_target(ch, 0.0, 25.0), true)
	var hand := ch.support_report(0)
	_check(not hand.is_empty() and float(hand["ik"]) < 0.01, "위 25° 조준 중 왼손 ↔ 표지 IK 뒤 %.2f cm" % (float(hand.get("ik", 9)) * 100.0))
	ch.set_aim_target(_target(ch, 0.0, 0.0), true)
	_force(ch)
	var p0 := float(ch.aim_report()["pitch"])
	ch.set_aim_target(_target(ch, 0.0, 30.0))
	_step(ch)
	var p1 := float(ch.aim_report()["pitch"])
	var lim := ch.aim_speed_deg * DT
	_check(p1 - p0 > lim * 0.5 and p1 - p0 <= lim + 0.5, "표적 0° → 30°: 한 장(1/12 초)에 %.1f°(빠르기 %.0f°/s = 한 장 %.1f°)" % [p1 - p0, ch.aim_speed_deg, lim])
	_step(ch, 12)
	_check(float(ch.aim_report()["err"]) < 1.0, "1 초 뒤 따라잡음 — %.2f°" % float(ch.aim_report()["err"]))
	_start(ch, "Rifle_Idle")
	ch.play_motion("Firing_Rifle", 0.1)
	_step(ch)
	var wm := float(ch.aim_report().get("weight", 0.0))
	_step(ch)
	var we := float(ch.aim_report().get("weight", 0.0))
	_check(wm > 0.3 and wm < 0.99 and absf(we - 1.0) < 0.001, "Rifle_Idle → Firing_Rifle 0.1 초 섞기: 비중 %.2f → %.2f" % [wm, we])

	print("[7] 게임처럼 · 합성 · 엎드림")
	ch.rotation.y = deg_to_rad(55.0)
	ch.scale = Vector3.ONE * 1.1
	ch.position = Vector3(3.0, 0.0, -2.0)
	_start(ch, "Firing_Rifle")
	ch.set_aim_target(_target(ch, 0.0, 15.0), true)
	_force(ch)
	_check(float(ch.aim_report().get("err", 999)) < 1.0, "돌림 55° · 배율 1.1 · 옮김 — %.2f°" % float(ch.aim_report().get("err", 999)))
	for mo in ["Crouch_Idle+Firing_Rifle", "Prone_Firing_Rifle"]:
		if not ch.get_animation_player().has_animation(mo):
			_check(false, "%s 동작 없음" % mo)
			continue
		_start(ch, mo)
		ch.set_aim_target(_target(ch, 0.0, 10.0), true)
		_force(ch)
		var rr := ch.aim_report()
		_check(not rr.is_empty() and float(rr["err"]) < 1.5, "%s 위 10° — %.2f° · 왼손 IK 뒤 %.2f cm" % [mo, float(rr.get("err", 999)), float(ch.support_report(0).get("ik", 9)) * 100.0])
	ch.queue_free()

	print("[9] 팔 · 견착 — 높낮이는 견착점 축으로 팔이 주로(사용자: \"진짜 조준을 할 때 팔 부분이 영향이 제일 많이 가잖아 — 양팔로 인한 견착 위치에 따라\")")
	var ch9 := _make(BASE)
	await process_frame
	_start(ch9, "Firing_Rifle")
	var up_raw := _upper_pose(ch9)
	var sh_raw := ch9.shoulder_world()
	var mz_raw := ch9.muzzle_world()
	var turn := {}
	for share in [0.0, 0.7, 1.0]:
		ch9.aim_arm_share = share
		ch9.set_aim_elevation(25.0, true)
		var up := _upper_pose(ch9)
		var r9 := ch9.aim_report()
		var el := _elev(ch9.muzzle_world()[1])
		turn[share] = rad_to_deg(up.basis.get_rotation_quaternion().angle_to(up_raw.basis.get_rotation_quaternion()))
		_check(absf(el - 25.0) < 1.5 and absf(float(r9["arm_pitch"]) - float(r9["pitch"]) * share) < 0.1,
			"팔 몫 %d %% — 실제 총구 높낮이 %.1f°(겨눔 25°) · 팔 %+.1f° · 허리 · 가슴 %+.1f° · 가슴 뼈 돌림 %.1f° · 견착점 이동 %.1f cm · 왼손 IK 뒤 %.2f cm" % [
			roundi(share * 100.0), el, float(r9["arm_pitch"]), float(r9["body_pitch"]), float(turn[share]), ch9.shoulder_world().distance_to(sh_raw) * 100.0,
			float(ch9.support_report(0).get("ik", 9)) * 100.0])
	_check(float(turn[0.7]) < float(turn[0.0]) * 0.5, "가슴 뼈 돌림: 팔 몫 0 %% %.1f° → 70 %% %.1f°(팔이 맡은 만큼 덜 숙임)" % [float(turn[0.0]), float(turn[0.7])])
	_check(ch9.shoulder_world().distance_to(sh_raw) < 0.03, "팔 몫 100 %% = 견착점 거의 제자리(%.1f cm) — 개머리판을 어깨에 댄 채 총구만 듦" % (ch9.shoulder_world().distance_to(sh_raw) * 100.0))
	_check((ch9.muzzle_world()[0] as Vector3).y - (mz_raw[0] as Vector3).y > 0.1, "총구 끝이 %.0f cm 올라감" % (((ch9.muzzle_world()[0] as Vector3).y - (mz_raw[0] as Vector3).y) * 100.0))
	ch9.clear_aim_target(true)
	_force(ch9)
	_check(_upper_pose(ch9).is_equal_approx(up_raw) and ch9.shoulder_world().distance_to(sh_raw) < 0.001, "표적 거둠 → 팔 IK 꺼짐 · 동작 그대로")
	ch9.queue_free()

	print("[8] 양손 받침대")
	if not ResourceLoader.exists(TWO):
		print("  (건너뜀 — %s 없음)" % TWO)
	else:
		var two := _make(TWO)
		await process_frame
		var w := two.get_weapon_node()
		_check(w != null and w.get_parent() is DRGripMount3D, "무기 = 두 손 사이 받침대")
		_start(two, "Firing_Rifle")
		var hl0 := two.support_report(0)       # 조준 전(이 씬의 사격 동작은 왼팔이 원래 6 ~ 7 cm 모자람 — 동작별 무기 자리 맞추기 전)
		var hr0 := two.support_report(1)
		two.set_aim_target(_target(two, 0.0, 20.0), true)
		_force(two)
		var r2 := two.aim_report()
		var hl := two.support_report(0)
		var hr := two.support_report(1)
		_check(not r2.is_empty() and float(r2["err"]) < 0.5, "위 20° — 총구 기준 ↔ 겨눌 방향 %.2f° · 돌림 %.1f°" % [float(r2.get("err", 999)), float(r2.get("pitch", 0))])
		_check(not hl.is_empty() and not hr.is_empty() and float(hl["ik"]) < float(hl0.get("ik", 0)) + 0.01 and float(hr["ik"]) < float(hr0.get("ik", 0)) + 0.01,
			"두 손 IK 뒤 왼 %.2f · 오른 %.2f cm — 조준 전 %.2f · %.2f cm 보다 나빠지지 않음" % [float(hl.get("ik", 9)) * 100.0, float(hr.get("ik", 9)) * 100.0,
			float(hl0.get("ik", 9)) * 100.0, float(hr0.get("ik", 9)) * 100.0])
		two.set_aim_elevation(25.0, true)
		_force(two)
		var el2 := _elev(two.muzzle_world()[1])
		_check(absf(el2 - 25.0) < 1.5 and float(two.aim_report().get("arm_pitch", 0)) > 1.0,
			"양손 받침대도 팔 몫 — 받침대를 견착점 축으로 돌림: 실제 총구 높낮이 %.1f°(겨눔 25°) · 팔 %+.1f°" % [el2, float(two.aim_report().get("arm_pitch", 0))])
		(w.get_parent() as DRGripMount3D).mode = DRGripMount3D.Mode.FIXED
		two.refresh_equipment()
		_start(two, "Firing_Rifle")
		two.set_aim_target(_target(two, 0.0, 20.0), true)
		_force(two)
		_check(two.aim_report().is_empty(), "고정 받침대(땅) = 몸으로 겨누지 않음")
		two.queue_free()

	await process_frame
	if _fails.is_empty():
		print("AIM CHECK OK")
	else:
		print("AIM CHECK FAIL ", ", ".join(_fails))
	quit(0 if _fails.is_empty() else 1)
