extends SceneTree

## 상하체 합성 검사. (Mixamo 재료에 기대지 않게 UAL1 의 동작만 쓴다)
##  [1] 합성 동작이 만들어지고 길이·반복이 규칙대로인가
##  [2] 자세: 다리·힙은 하체 애니와, 팔·몸통은 상체 애니와 같은가(같은 시점으로 환산해서)
##  [3] 경고: 없는 동작 · 모델에 있는 이름과 겹침 → 만들지 않음
##  [4] 정의를 바꿔 다시 부르면 예전 합성은 빠진다 · 가져온 모델의 라이브러리는 그대로
##  [5] 구우면 씬에 들어가고 rig.json 에 정의가 남는다
##
##   Godot.exe --path <프로젝트> --resolution 400x300 --script res://addons/dot_rigger/tools/composite_check_cli.gd

const MODEL := "res://models/UAL1.glb"
const OUT := "res://puppet_test/composite_bake"

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  OK    " if ok else "  FAIL  ") + msg)
	if not ok:
		_fail += 1


func _local(baker: DRBaker, bone: String) -> Transform3D:
	return baker.skeleton.get_bone_pose(baker.skeleton.find_bone(bone))


## 몸통이 앞으로 숙은 각도(도, + = 앞). 힙 → 목 방향이 수직에서 앞(+Z)으로 기운 정도 — 뼈 위치로 잰다
func _lean(baker: DRBaker) -> float:
	var sk := baker.skeleton
	var v := sk.get_bone_global_pose(sk.find_bone("neck_01")).origin - sk.get_bone_global_pose(sk.find_bone("pelvis")).origin
	return rad_to_deg(atan2(v.z, v.y))


func _near(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 0.0005 and a.basis.get_rotation_quaternion().angle_to(b.basis.get_rotation_quaternion()) < 0.002


func _run() -> void:
	var opts := DRBaker.Options.new()
	opts.view_size = Vector2i(184, 184)
	opts.yaw = -55.0
	opts.rest_anim = "Idle"
	opts.composites = [
		{"name": "Crouch Aim", "lower": "Crouch_Fwd", "upper": "Pistol_Aim_Neutral", "length_mode": DRBaker.LEN_LOWER_SPEED, "loop": true},
		{"name": "WalkShoot", "lower": "Walk", "upper": "Pistol_Shoot", "length_mode": DRBaker.LEN_UPPER_SPEED, "loop": false},
		{"name": "Once", "lower": "Walk", "upper": "Pistol_Reload", "length_mode": DRBaker.LEN_ONCE, "loop": true},
		{"name": "OnceUp", "lower": "Walk", "upper": "Pistol_Reload", "length_mode": DRBaker.LEN_ONCE_UPPER, "loop": true},
		{"name": "NoSuch", "lower": "Walk", "upper": "Nope_Anim"},
		{"name": "Walk", "lower": "Walk", "upper": "Pistol_Shoot"},
	]
	var baker := DRBaker.new()
	if not baker.setup(root, load(MODEL) as PackedScene, DRPartProfile.humanoid(), opts):
		printerr("setup 실패"); quit(1); return
	var ap := baker.anim_player

	print("[1] 만들어짐 · 길이 · 반복")
	_check(Array(baker.composite_anims) == ["Crouch_Aim", "WalkShoot", "Once", "OnceUp"], "합성 동작 %s (공백 → _)" % str(baker.composite_anims))
	var lo_len := ap.get_animation("Crouch_Fwd").length
	var up_len := ap.get_animation("Pistol_Aim_Neutral").length
	var n := maxi(1, int(round(up_len / lo_len)))
	var c1 := ap.get_animation("Crouch_Aim")
	_check(absf(c1.length - lo_len * float(n)) < 0.0001 and c1.loop_mode == Animation.LOOP_LINEAR,
		"하체 시간에 상체를 맞춤 (하체 반복): 길이 %.3f = Crouch_Fwd %.3f × %d (상체 %.3f) · 반복" % [c1.length, lo_len, n, up_len])
	var c2 := ap.get_animation("WalkShoot")
	var walk_len := ap.get_animation("Walk").length
	var shoot_len := ap.get_animation("Pistol_Shoot").length
	_check(absf(c2.length - shoot_len) < 0.0001 and c2.loop_mode == Animation.LOOP_NONE, "상체 시간에 하체를 맞춤 (하체 반복): 길이 %.3f = Pistol_Shoot %.3f · 반복 안 함" % [c2.length, shoot_len])
	var c3 := ap.get_animation("Once")
	_check(absf(c3.length - walk_len) < 0.0001, "하체 시간에 상체를 맞춤 (하체 1번): 길이 %.3f = Walk %.3f" % [c3.length, walk_len])
	var c4 := ap.get_animation("OnceUp")
	var reload_len := ap.get_animation("Pistol_Reload").length
	_check(absf(c4.length - reload_len) < 0.0001 and absf(reload_len - walk_len) > 0.05, "상체 시간에 하체를 맞춤 (하체 1번): 길이 %.3f = Pistol_Reload %.3f (Walk %.3f 와 다름)" % [c4.length, reload_len, walk_len])
	# 하체가 그 길이로 늘어났는가 — 합성의 50% 시점 다리 = Walk 의 50% 시점 다리
	baker.set_pose("OnceUp", c4.length * 0.5)
	var leg_c := _local(baker, "calf_l")
	baker.set_pose("Walk", walk_len * 0.5)
	# (30fps 로 다시 샘플한 값 사이를 보간하므로 샘플 시점이 아닌 곳에서는 아주 조금 다를 수 있다 → 느슨하게 1도 남짓)
	var leg_w := _local(baker, "calf_l")
	var leg_ang := leg_c.basis.get_rotation_quaternion().angle_to(leg_w.basis.get_rotation_quaternion())
	_check(leg_ang < 0.02, "상체 시간에 하체를 맞춤 (하체 1번): 합성 50%% 의 다리 = Walk 50%% 의 다리(각도 차 %.4f rad) — 하체를 상체 길이로 늘임" % leg_ang)
	var info: Dictionary = baker.composite_info[0]
	_check(String(info["lower"]) == "Crouch_Fwd" and int(info["lower_cycles"]) == n and Array(info["upper_parts"]).has("Torso"),
		"정의 기록: %s ← 하체 %s × %d + 상체 %s" % [info["name"], info["lower"], int(info["lower_cycles"]), info["upper"]])

	print("[2] 자세 — 다리·힙 = 하체 애니, 팔·몸통 = 상체 애니")
	var lower_bones := ["pelvis", "thigh_l", "calf_r", "foot_l"]
	var upper_bones := ["spine_02", "upperarm_r", "lowerarm_l", "hand_r", "Head"]
	var bad := PackedStringArray()
	var cases := [["Crouch_Aim", "Crouch_Fwd", "Pistol_Aim_Neutral", n], ["WalkShoot", "Walk", "Pistol_Shoot", maxi(1, int(round(shoot_len / walk_len)))]]
	var samples := 0
	for cs in cases:
		var comp := ap.get_animation(cs[0])
		var lo := ap.get_animation(cs[1])
		var up := ap.get_animation(cs[2])
		var cycles := int(cs[3])
		var steps := int(ceil(comp.length * DRBaker.COMPOSITE_FPS))
		for k in [1, int(steps / 3.0), int(steps / 2.0), steps - 2]:
			var t := float(k) / DRBaker.COMPOSITE_FPS
			var phase := (t / comp.length) * float(cycles)
			var lo_t := (phase - floorf(phase)) * lo.length
			var up_t := (t / comp.length) * up.length
			baker.set_pose(cs[0], t)
			var got := {}
			for b in lower_bones + upper_bones:
				got[b] = _local(baker, b)
			baker.set_pose(cs[1], lo_t)
			for b in lower_bones:
				samples += 1
				if not _near(got[b], _local(baker, b)):
					bad.append("%s t=%.2f %s≠하체" % [cs[0], t, b])
			baker.set_pose(cs[2], up_t)
			for b in upper_bones:
				samples += 1
				if not _near(got[b], _local(baker, b)):
					bad.append("%s t=%.2f %s≠상체" % [cs[0], t, b])
	_check(bad.is_empty(), "뼈 자세 %d개 비교 — 어긋난 것 %d개 %s" % [samples, bad.size(), str(bad.slice(0, 4))])
	# 합성이 정말 섞였는지(그냥 하체 애니와 같으면 안 된다)
	baker.set_pose("Crouch_Aim", 0.2)
	var arm_c := _local(baker, "upperarm_r")
	baker.set_pose("Crouch_Fwd", 0.2)
	_check(not _near(arm_c, _local(baker, "upperarm_r")), "합성의 팔 ≠ 하체 애니(Crouch_Fwd)의 팔")

	print("[2-1] 상체 방향 유지 · 몸통 각도 보정 — 앉기(골반이 앞으로 숙음) + Idle(곧게 섬)")
	# UAL Crouch_Idle 은 골반이 Idle 대비 27° 앞으로 숙어 있어, 허리 각도를 부모 기준 그대로 얹으면 몸통이 같이 숙는다(8° → 33°)
	var saved_defs: Array = opts.composites
	baker.build_composites([
		{"name": "K0", "lower": "Crouch_Idle", "upper": "Idle", "upper_keep": 0.0},
		{"name": "K1", "lower": "Crouch_Idle", "upper": "Idle", "upper_keep": 1.0},
		{"name": "K5", "lower": "Crouch_Idle", "upper": "Idle", "upper_keep": 0.5},
		{"name": "P20", "lower": "Crouch_Idle", "upper": "Idle", "upper_keep": 1.0, "upper_pitch": 20.0},
		{"name": "PM15", "lower": "Crouch_Idle", "upper": "Idle", "upper_keep": 0.0, "upper_pitch": -15.0},
	], PackedStringArray())
	var kc := ap.get_animation("K1")
	var k_t := 44.0 / DRBaker.COMPOSITE_FPS
	var k_up_t := (k_t / kc.length) * ap.get_animation("Idle").length
	var chest := baker.skeleton.find_bone("spine_03")
	baker.set_pose("Idle", k_up_t)
	var idle_chest := baker.skeleton.get_bone_global_pose(chest).basis.get_rotation_quaternion()
	var idle_lean := _lean(baker)
	baker.set_pose("Crouch_Idle", k_t)
	var crouch_calf := _local(baker, "calf_l")
	var leans := {}
	var chests := {}
	for nm in ["K0", "K1", "K5", "P20", "PM15"]:
		baker.set_pose(nm, k_t)
		leans[nm] = _lean(baker)
		chests[nm] = baker.skeleton.get_bone_global_pose(chest).basis.get_rotation_quaternion()
	baker.set_pose("K1", k_t)
	_check(float(leans["K0"]) > idle_lean + 15.0, "방향 유지 0%%(예전 방식): 몸통 숙임 %.1f° — Idle %.1f° 보다 크게 숙음(골반을 따라감)" % [float(leans["K0"]), idle_lean])
	# (뼈 위치로 잰 숙임은 골반 → 허리 첫 마디 구간이 골반과 같이 기울므로 Idle 보다 몇 도 크게 남는다 — 정확한 기준은 가슴의 회전)
	_check(rad_to_deg((chests["K1"] as Quaternion).angle_to(idle_chest)) < 0.5 and absf(float(leans["K1"]) - idle_lean) < 8.0 and _near(_local(baker, "calf_l"), crouch_calf),
		"방향 유지 100%%: 가슴이 Idle 과 같은 쪽(차이 %.2f°) · 몸통 숙임 %.1f° · 다리는 앉기 그대로" % [rad_to_deg((chests["K1"] as Quaternion).angle_to(idle_chest)), float(leans["K1"])])
	_check(float(leans["K5"]) > float(leans["K1"]) + 5.0 and float(leans["K5"]) < float(leans["K0"]) - 5.0,
		"방향 유지 50%%: 그 사이 (%.1f° < %.1f° < %.1f°)" % [float(leans["K1"]), float(leans["K5"]), float(leans["K0"])])
	var p20 := rad_to_deg((chests["P20"] as Quaternion).angle_to(chests["K1"]))
	var p20_d := float(leans["K1"]) - float(leans["P20"])
	_check(absf(p20 - 20.0) < 0.5 and p20_d > 12.0 and p20_d < 21.0,
		"각도 보정 +20°: 가슴이 20° 돌고(%.2f°) 뒤로 젖혀짐 — 숙임 %.1f° → %.1f°" % [p20, float(leans["K1"]), float(leans["P20"])])
	var pm15 := rad_to_deg((chests["PM15"] as Quaternion).angle_to(chests["K0"]))
	var pm15_d := float(leans["PM15"]) - float(leans["K0"])
	_check(absf(pm15 - 15.0) < 0.5 and pm15_d > 9.0 and pm15_d < 16.0,
		"각도 보정 −15°: 앞으로 더 숙임 — 숙임 %.1f° → %.1f°" % [float(leans["K0"]), float(leans["PM15"])])
	var kinfo: Dictionary = baker.composite_info[3]
	_check(absf(float(kinfo["upper_keep"]) - 1.0) < 0.001 and absf(float(kinfo["upper_pitch"]) - 20.0) < 0.001, "정의 기록에 upper_keep · upper_pitch")
	baker.build_composites(saved_defs, PackedStringArray())

	print("[3] 경고")
	var w := baker.composite_warnings
	_check(w.size() == 2 and w[0].contains("NoSuch") and w[1].contains("Walk"), "없는 동작 · 모델과 같은 이름 → 만들지 않고 경고 %d건" % w.size())
	_check(ap.get_animation("Walk").length == walk_len and not baker.composite_anims.has("Walk"), "모델의 Walk 는 그대로")

	print("[4] 다시 만들기 · 원본 라이브러리")
	baker.build_composites([{"name": "OnlyOne", "lower": "Jog_Fwd", "upper": "Pistol_Idle"}], PackedStringArray(["L_UpperArm", "L_Forearm", "L_Hand"]))
	_check(Array(baker.composite_anims) == ["OnlyOne"] and not ap.has_animation("Crouch_Aim") and ap.has_animation("OnlyOne"),
		"정의를 바꾸면 예전 합성은 빠짐 → %s" % str(baker.composite_anims))
	# 상체 파트를 왼팔만으로 — 오른팔은 하체 애니(Jog_Fwd)를 따라야 한다
	baker.set_pose("OnlyOne", 0.2)
	var r_arm := _local(baker, "upperarm_r")
	var l_arm := _local(baker, "upperarm_l")
	baker.set_pose("Jog_Fwd", 0.2)
	_check(_near(r_arm, _local(baker, "upperarm_r")) and not _near(l_arm, _local(baker, "upperarm_l")), "상체 파트 = 왼팔만 → 오른팔은 Jog_Fwd 그대로, 왼팔만 Pistol_Idle")
	var fresh := (load(MODEL) as PackedScene).instantiate()
	var fresh_ap := fresh.get_node("AnimationPlayer") as AnimationPlayer
	_check(not fresh_ap.has_animation("OnlyOne") and not fresh_ap.has_animation("Crouch_Aim"), "가져온 모델의 라이브러리에 새어 들어가지 않음")
	fresh.free()

	print("[4-1] 팝업 미리보기용 합성 — 숨은 이름으로만 들어가고, 치우면 사라진다")
	var before_list := ap.get_animation_list().size()
	var pv: Dictionary = baker.make_composite_preview({"name": "whatever", "lower": "Crouch_Fwd", "upper": "Pistol_Aim_Neutral", "length_mode": DRBaker.LEN_LOWER_SPEED}, PackedStringArray())
	_check(bool(pv.get("ok", false)) and ap.has_animation(DRBaker.PREVIEW_ANIM) and not baker.composite_anims.has(DRBaker.PREVIEW_ANIM)
		and ap.get_animation_list().size() == before_list + 1 and absf(float(pv["length"]) - lo_len * float(n)) < 0.0001,
		"미리보기 동작 %s (%.2f초) — 합성 목록에는 안 들어감" % [DRBaker.PREVIEW_ANIM, float(pv.get("length", 0.0))])
	baker.set_pose(DRBaker.PREVIEW_ANIM, 0.2)
	var pv_arm := _local(baker, "upperarm_r")
	baker.set_pose("Crouch_Fwd", 0.2)
	_check(not _near(pv_arm, _local(baker, "upperarm_r")), "미리보기 동작이 실제로 재생됨(팔 ≠ 하체 애니의 팔)")
	var pv_bad: Dictionary = baker.make_composite_preview({"lower": "Walk", "upper": "Nope"}, PackedStringArray())
	_check(not bool(pv_bad.get("ok", true)) and String(pv_bad.get("warning", "")) != "" and not ap.has_animation(DRBaker.PREVIEW_ANIM), "없는 동작이면 실패 + 이유, 예전 미리보기는 치워짐")
	baker.make_composite_preview({"lower": "Walk", "upper": "Pistol_Idle"}, PackedStringArray())
	baker.clear_composite_preview()
	_check(not ap.has_animation(DRBaker.PREVIEW_ANIM) and ap.get_animation_list().size() == before_list, "clear_composite_preview() 뒤 목록이 원래대로 (%d개)" % before_list)

	print("[4-2] 합성(각도 보정)을 본 뒤의 그냥 Idle 이 처음 Idle 과 같은가 — 트랙 없는 뼈에 자세가 남으면 안 된다(02 C13)")
	# Idle 에는 허리 첫 마디(spine_01)의 회전 트랙이 없고, 각도 보정은 그 뼈에 쓴다 → 예전엔 합성을 본 뒤의 Idle 이 57° 틀어졌다
	var idle_anim := ap.get_animation("Idle")
	var idle_has_spine := false
	for ti in idle_anim.get_track_count():
		if idle_anim.track_get_type(ti) == Animation.TYPE_ROTATION_3D and idle_anim.track_get_path(ti).get_concatenated_subnames() == "spine_01":
			idle_has_spine = true
	var chest2 := baker.skeleton.find_bone("spine_03")
	var fresh_baker := DRBaker.new()
	var fresh_opts := DRBaker.Options.new()
	fresh_opts.view_size = Vector2i(64, 64)
	fresh_baker.setup(root, load(MODEL) as PackedScene, DRPartProfile.humanoid(), fresh_opts)
	fresh_baker.set_pose("Idle", 0.5)
	var q_clean := fresh_baker.skeleton.get_bone_global_pose(chest2).basis.get_rotation_quaternion()
	fresh_baker.cleanup()
	baker.make_composite_preview({"lower": "Crouch_Idle", "upper": "Idle", "upper_keep": 1.0, "upper_pitch": 30.0}, PackedStringArray())
	baker.set_pose(DRBaker.PREVIEW_ANIM, 0.5)
	var q_comp := baker.skeleton.get_bone_global_pose(chest2).basis.get_rotation_quaternion()
	baker.clear_composite_preview()
	baker.set_pose("Idle", 0.5)
	var q_after := baker.skeleton.get_bone_global_pose(chest2).basis.get_rotation_quaternion()
	_check(not idle_has_spine and rad_to_deg(q_clean.angle_to(q_comp)) > 20.0 and rad_to_deg(q_clean.angle_to(q_after)) < 0.05,
		"Idle 에 spine_01 트랙 없음(%s) · 합성 때 가슴 %.1f° 다름 → 다시 Idle: 처음과 %.3f° 차이" % [str(not idle_has_spine), rad_to_deg(q_clean.angle_to(q_comp)), rad_to_deg(q_clean.angle_to(q_after))])

	print("[5] 굽기")
	baker.build_composites(opts.composites, PackedStringArray())
	await process_frame
	var ex := DRExporter.new()
	ex.baker = baker
	ex.out_dir = OUT
	ex.keep_previous = false
	ex.anim_names = PackedStringArray(["Crouch_Aim"])
	baker.opts.rest_anim = "Crouch_Aim"
	baker.opts.rest_time = 0.0
	var res: Dictionary = await ex.run()
	var ps := ResourceLoader.load(OUT.path_join("puppet.tscn"), "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var pup := ps.instantiate() if ps != null else null
	var pap := pup.get_node_or_null("AnimationPlayer") as AnimationPlayer if pup != null else null
	_check(bool(res.get("ok", false)) and pap != null and pap.has_animation("Crouch_Aim")
		and absf(pap.get_animation("Crouch_Aim").length - c1.length) < 0.001, "구운 씬에 Crouch_Aim (길이 %.3f)" % c1.length)
	if pup != null:
		pup.free()
	var f := FileAccess.open(OUT.path_join("rig.json"), FileAccess.READ)
	var doc: Dictionary = JSON.parse_string(f.get_as_text()) if f != null else {}
	var cj: Array = doc.get("composites", [])
	_check(cj.size() == 1 and String(cj[0].get("name", "")) == "Crouch_Aim" and String(cj[0].get("upper", "")) == "Pistol_Aim_Neutral",
		"rig.json composites 에 구운 합성만 %d건 (%s)" % [cj.size(), cj[0].get("name", "") if cj.size() > 0 else "-"])

	if _fail > 0:
		printerr("상하체 합성 검사 실패 %d건" % _fail)
		quit(1); return
	print("상하체 합성 검사 전부 통과")
	quit(0)
