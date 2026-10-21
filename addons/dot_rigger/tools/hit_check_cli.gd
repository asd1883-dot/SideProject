extends SceneTree

## 피격 반응 검사(10-21) — 창 없이(--headless). DRCharacter3D 의 IK 피격(맞은 부위가 총알 방향으로 젖혀졌다 돌아옴)과 시뮬의 피격 신호를 사람 몸 + kar98k 로 잰다.
##   Godot --headless --path <프로젝트> --script res://addons/dot_rigger/tools/hit_check_cli.gd
## [1] 구조: 피격 수정자가 조준 수정자 · 조준 팔 IK 바로 뒤, 손 IK 보다 앞
## [2] 부위 고르기: 머리 · 가슴 · 배 · 왼팔 · 오른팔 · 왼다리 · 오른다리 · 몸에서 먼 점 = ""
## [3] 젖혀짐: 맞은 부위가 총알 방향으로 밀림(앞에서 맞으면 뒤로 · 뒤에서 맞으면 앞으로) · 첫 장에 거의 끝까지 · 길이 뒤 동작 그대로
## [4] IK 끔 = 부위만 · 반응 없음 · 여러 발 = 최대 HIT_MAX · 세기 배율 · 가슴 맞는 중에도 왼손이 총에
## [5] 시뮬: 맞으면(살아 있으면) soldier_hit 신호 — 맞은 점(높이 · 깊이)이 표적 몸 상자 안 · 총알 방향 x 가 쏜 쪽에서 표적 쪽
## 마지막 줄이 "HIT CHECK OK" 면 통과.

const BASE := "res://game/units/soldier_base.tscn"
const DT := 1.0 / 12.0
const TestField := preload("res://game/tools/test_field.gd")

var _fails := PackedStringArray()


func _initialize() -> void:
	create_timer(300.0).timeout.connect(func() -> void:
		print("HIT CHECK FAIL 시간 초과")
		quit(2))
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["OK  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _force(ch: DRCharacter3D) -> void:
	var sk := ch.get_skeleton()
	sk.set_bone_pose_rotation(0, sk.get_bone_pose_rotation(0))
	sk.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)


## 수정자를 거친 뼈 자리(세상) — 갱신 신호 안에서 읽는다
func _posed(ch: DRCharacter3D, bone: String) -> Vector3:
	var sk := ch.get_skeleton()
	var bi := sk.find_bone(bone)
	var got := [Vector3.ZERO]
	var cb := func() -> void: got[0] = sk.global_transform * sk.get_bone_global_pose(bi).origin
	sk.skeleton_updated.connect(cb)
	_force(ch)
	sk.skeleton_updated.disconnect(cb)
	return got[0]


## 수정자를 거친 뼈의 한 점(세상 — 뼈 로컬 off)
func _posed_at(ch: DRCharacter3D, bone: String, off: Vector3) -> Vector3:
	var sk := ch.get_skeleton()
	var bi := sk.find_bone(bone)
	var got := [Vector3.ZERO]
	var cb := func() -> void: got[0] = sk.global_transform * (sk.get_bone_global_pose(bi) * off)
	sk.skeleton_updated.connect(cb)
	_force(ch)
	sk.skeleton_updated.disconnect(cb)
	return got[0]


## 두 뼈 가운데(세상)
func _mid(ch: DRCharacter3D, a: String, b: String) -> Vector3:
	return (_bone(ch, a) + _bone(ch, b)) * 0.5


## 동작을 n 장 진행하며 뼈대를 바로 다시 푼다(창 없는 검사는 프레임을 안 넘겨 미뤄진 갱신이 안 돈다)
func _step(ch: DRCharacter3D, n: int = 1) -> void:
	for i in n:
		ch.step_motion(DT)
		_force(ch)


## 지금(수정자 전) 뼈 자리(세상)
func _bone(ch: DRCharacter3D, bone: String) -> Vector3:
	var sk := ch.get_skeleton()
	return sk.global_transform * sk.get_bone_global_pose(sk.find_bone(bone)).origin


func _run() -> void:
	await process_frame
	var ch := (load(BASE) as PackedScene).instantiate() as DRCharacter3D
	root.add_child(ch)
	await process_frame
	var ap := ch.get_animation_player()
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ch.play_motion("Firing_Rifle", 0.0)
	ap.seek(ap.get_animation("Firing_Rifle").length * 0.3, true)
	ap.speed_scale = 0.0                          # 자세를 멈춰 둔다(반응만 보게)
	_force(ch)
	var sk := ch.get_skeleton()
	var fwd := ch.global_transform.basis.z.normalized()      # 몸 앞(+Z)

	print("[1] 구조")
	var mods: Array = []
	for c in sk.get_children():
		if c is SkeletonModifier3D:
			mods.append(String(c.name))
	var hi := mods.find("DR_HitSolver")
	_check(hi > 0 and hi > mods.find("DR_AimRightHandRot") and hi < mods.find("DR_LeftRef"), "피격 수정자 차례 — %s" % ", ".join(PackedStringArray(mods)))

	print("[2] 부위 고르기")
	var cases := [["Head", "", Vector3.UP * 0.08, "머리"], ["UpperChest", "", fwd * 0.12, "가슴"], ["Spine", "", fwd * 0.12, "배"],
		["LeftLowerArm", "LeftHand", Vector3.ZERO, "왼팔"], ["RightUpperArm", "RightLowerArm", Vector3.ZERO, "오른팔"],
		["LeftLowerLeg", "LeftFoot", fwd * 0.05, "왼다리"], ["RightUpperLeg", "RightLowerLeg", fwd * 0.06, "오른다리"]]
	var bad := PackedStringArray()
	var inv := sk.global_transform.affine_inverse()
	for c in cases:
		var base: Vector3 = _bone(ch, String(c[0])) if String(c[1]) == "" else _mid(ch, String(c[0]), String(c[1]))   # 팔 · 다리는 마디 가운데
		var pt: Vector3 = base + (c[2] as Vector3)
		var got := ch.hit_part_at(inv * pt)
		if got != String(c[3]):
			bad.append("%s→%s(기대 %s)" % [c[0], got, c[3]])
	_check(bad.is_empty(), "뼈 마디 가까이 = 부위 %s" % ", ".join(bad))
	_check(ch.hit_part_at(inv * (_bone(ch, "Hips") + fwd * 1.0)) == "", "몸에서 1 m 앞 = 안 맞음(\"\")")

	print("[3] 젖혀짐 · 시간")
	var dir_in := -fwd                                       # 앞(적)에서 몸 쪽으로
	# [맞힐 뼈, 맞힐 점 더하기, 기대 부위, 잴 뼈, 잴 점(뼈 로컬)] — 머리는 머리 위쪽(머리뼈 원점은 목) · 왼팔은 팔꿈치(맞은 곳 — 팔이 맞으면 그 손 IK 를 잠깐 풀어 손도 총에서 튕김)
	for c in [["UpperChest", fwd * 0.12, "가슴", "UpperChest", Vector3.ZERO], ["Head", fwd * 0.08, "머리", "Head", Vector3.UP * 0.15],
			["LeftLowerArm", Vector3.ZERO, "왼팔", "LeftLowerArm", Vector3.ZERO]]:
		var bone := String(c[3])
		var rest := _posed_at(ch, bone, c[4])
		var part := ch.hit_react(_bone(ch, String(c[0])) + (c[1] as Vector3), dir_in)
		_step(ch)
		var peak := _posed_at(ch, bone, c[4])
		var moved := (peak - rest).dot(dir_in)
		var a0: float = ch.hit_report()[0]["angle"] if ch.hit_count() > 0 else 0.0
		_step(ch, 12)
		var back := _posed_at(ch, bone, c[4])
		_check(part == String(c[2]) and moved > 0.01 and a0 > ch.hit_ik_deg * 0.85 and ch.hit_count() == 0 and back.distance_to(rest) < 0.001,
			"%s 앞에서 맞음 → %s 이 총알 방향으로 %.1f cm(첫 장 %.0f° · 세기 %.0f°) → %.2f 초 뒤 동작 그대로" % [part, bone, moved * 100.0, a0, ch.hit_ik_deg, ch.hit_ik_sec * 1.5])
	var rest2 := _posed(ch, "UpperChest")
	ch.hit_react(_bone(ch, "UpperChest") - fwd * 0.12, fwd)            # 뒤에서
	_step(ch)
	var moved2 := (_posed(ch, "UpperChest") - rest2).dot(fwd)
	_check(moved2 > 0.01, "가슴 뒤에서 맞음 → 앞으로 %.1f cm" % (moved2 * 100.0))
	_step(ch, 12)

	print("[4] 끔 · 여러 발 · 배율 · 왼손")
	ch.hit_ik_enabled = false
	var p_off := ch.hit_react(_bone(ch, "UpperChest") + fwd * 0.12, dir_in)
	_check(p_off == "가슴" and ch.hit_count() == 0, "IK 끔 = 부위(%s)만 · 반응 없음" % p_off)
	ch.hit_ik_enabled = true
	# 왼팔이 맞으면 왼손 IK 를 잠깐 풀어 손이 총에서 튕겼다 돌아온다(안 풀면 손이 총에 묶여 팔꿈치만 0.8 cm)
	var h0 := ch.support_report(0)
	ch.hit_react(_mid(ch, "LeftLowerArm", "LeftHand"), dir_in)
	_step(ch)
	var h1 := ch.support_report(0)
	_step(ch, 12)
	var h2 := ch.support_report(0)
	_check(float(h1.get("ik", 0)) > 0.02 and float(h2.get("ik", 9)) < float(h0.get("ik", 0)) + 0.002,
		"왼팔 맞음 → 왼손이 총에서 %.1f cm 튕김 → 다시 잡음(%.2f cm)" % [float(h1.get("ik", 0)) * 100.0, float(h2.get("ik", 9)) * 100.0])
	ch.hit_ik_enabled = true
	for i in 6:
		ch.hit_react(_bone(ch, "UpperChest") + fwd * 0.12, dir_in)
	_check(ch.hit_count() == DRCharacter3D.HIT_MAX, "6 발 → 동시에 %d 개(최대 %d)" % [ch.hit_count(), DRCharacter3D.HIT_MAX])
	var hand := ch.support_report(0)
	_check(not hand.is_empty() and float(hand["ik"]) < 0.01, "가슴에 여러 발 맞는 중 왼손 ↔ 표지 IK 뒤 %.2f cm" % (float(hand.get("ik", 9)) * 100.0))
	_step(ch, 12)
	ch.hit_react(_bone(ch, "UpperChest") + fwd * 0.12, dir_in, 0.5)
	_step(ch)
	var ah: float = ch.hit_report()[0]["angle"]
	_check(absf(ah - ch.hit_ik_deg * 0.5) < ch.hit_ik_deg * 0.15, "세기 배율 0.5 → 첫 장 %.1f°" % ah)
	ch.queue_free()

	print("[5] 시뮬 피격 신호")
	var type := load("res://game/units/rifleman.tres") as SoldierType
	var bf := Battlefield.new()
	bf.running = false
	bf.rng.seed = 1941
	TestField.build(bf)
	root.add_child(bf)
	var got: Array = []
	bf.soldier_hit.connect(func(s: BattleSoldier, info: Dictionary) -> void: got.append([s, info]))
	for i in 2:
		bf.deploy_squad(0, type)
		bf.deploy_squad(1, type)
	for k in int(40.0 * 60.0):
		bf.step(1.0 / 60.0)
		if got.size() >= 10:
			break
	var inside := 0
	var dir_ok := 0
	for g in got:
		var s: BattleSoldier = g[0]
		var info: Dictionary = g[1]
		var pt: Vector3 = info["point"]
		var d: Vector3 = info["dir"]
		var box := s.type.box(s.stance)
		# 신호 때의 몸 상자로 잰다 — 총알이 나는 동안(0.05 ~ 0.1 초) 자세 · 자리가 바뀌었을 수 있어 서기 상자 높이 · x 여유 0.5 m
		var stand := s.type.box(BattleBody.Stance.STAND)
		if pt.y >= -0.01 and pt.y <= stand.y + 0.01 and absf(pt.x - s.x) <= maxf(box.x, stand.x) * 0.5 + 0.5:
			inside += 1
		else:
			print("    밖: 맞은 점 %s · 표적 x %.2f 자세 %d 상자 %s" % [str(pt), s.x, s.stance, str(box)])
		var sh: BattleSoldier = info["shooter"]
		if sh != null and signf(d.x) == signf(s.x - sh.x):
			dir_ok += 1
	_check(got.size() >= 5 and inside == got.size() and dir_ok == got.size(),
		"맞음 신호 %d 번 — 맞은 점이 몸 상자 안 %d · 총알 방향 = 쏜 쪽 → 표적 %d" % [got.size(), inside, dir_ok])
	bf.clear()
	bf.queue_free()

	await process_frame
	if _fails.is_empty():
		print("HIT CHECK OK")
	else:
		print("HIT CHECK FAIL ", ", ".join(_fails))
	quit(0 if _fails.is_empty() else 1)
