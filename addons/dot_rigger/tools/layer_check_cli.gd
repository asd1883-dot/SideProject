extends SceneTree

## 발 / 발가락 / 레이어 검사.
## [0] 기본 프로필: 발가락은 발에 합친다. 발은 레스트 모양 그대로 한 장이고 발목에서 회전만 한다(늘이기 없음).
## [1]~[4] humanoid(true): 발가락을 따로 꺾는 모드. 발가락은 별도 파트·별도 본이지만
##         그리기 순서에서는 발과 한 줄(한 레이어)로 묶여 항상 발 바로 위에 그려져야 한다.
##
##   Godot.exe --path <프로젝트> --resolution 400x300 \
##     --script res://addons/dot_rigger/tools/layer_check_cli.gd

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  OK    " if ok else "  FAIL  ") + msg)
	if not ok:
		_fail += 1


func _make_baker(scene: PackedScene, profile: DRPartProfile) -> DRBaker:
	var opts := DRBaker.Options.new()
	opts.view_size = Vector2i(184, 184)
	opts.yaw = -55.0
	opts.rest_anim = "Idle"
	var baker := DRBaker.new()
	if not baker.setup(root, scene, profile, opts):
		return null
	baker.set_rest_pose()
	await RenderingServer.frame_post_draw
	await baker.auto_fit(0)
	baker.rig.capture_rest(baker.skeleton, baker.camera)
	return baker


func _run() -> void:
	var scene := load("res://models/UAL1.glb") as PackedScene
	await _check_merged(scene)
	await _check_split(scene)
	print("\n" + ("레이어 검사 전부 통과" if _fail == 0 else "실패 %d건" % _fail))
	quit(0 if _fail == 0 else 1)


# ---------------------------------------------------------------- 기본: 발가락을 발에 합침

func _check_merged(scene: PackedScene) -> void:
	print("[0] 기본 프로필 — 발가락은 발에 합침, 발은 한 장·발목 회전만·늘이기 없음")
	var baker: DRBaker = await _make_baker(scene, DRPartProfile.humanoid())
	if baker == null:
		_check(false, "기본 프로필 setup"); return
	var rig := baker.rig
	_check(rig.order.size() == 15 and rig.layer_names().size() == 15,
		"파트 %d개 · 레이어 %d줄 (기대 15 / 15)" % [rig.order.size(), rig.layer_names().size()])
	_check(not rig.parts.has("L_Toe") and not rig.parts.has("R_Toe"), "발가락 파트 없음")
	for side in ["L", "R"]:
		var foot: String = side + "_Foot"
		var ball: String = "ball_" + side.to_lower()
		_check(baker.profile.part_for_bone(ball) == foot, "%s 본 → %s" % [ball, baker.profile.part_for_bone(ball)])
		var fp: DRRigModel.Part = rig.parts[foot]
		_check(fp.bones.size() >= 2, "%s 에 본 %d개 (발 + 발가락)" % [foot, fp.bones.size()])
		_check(baker.skeleton.get_bone_name(fp.root_bone) == "foot_" + side.to_lower(),
			"%s 루트 본 = %s (발목에서 회전)" % [foot, baker.skeleton.get_bone_name(fp.root_bone)])
		_check(rig.no_stretch.has(foot), "%s 늘이기 끔" % foot)
	_check(not rig.no_stretch.has("L_Calf") and not rig.no_stretch.has("L_UpperArm"),
		"다른 파트는 늘이기 유지 (끔 목록 %s)" % str(rig.no_stretch.keys()))

	var an := baker.resolve_anim("Jog_Fwd")
	var anim := baker.anim_player.get_animation(an)
	var s_bad := ""
	var lo := INF
	var hi := -INF
	for i in 24:
		var t := anim.length * float(i) / 24.0
		baker.set_pose(an, t)
		await RenderingServer.frame_post_draw
		var loc := rig.project_local(baker.skeleton, baker.camera)
		for side in ["L", "R"]:
			var s := float(loc[side + "_Foot"]["s"])
			if absf(s - 1.0) > 0.000001:
				s_bad = "(t=%.2f %s_Foot s=%.3f)" % [t, side, s]
		var r := rad_to_deg(float(loc["L_Foot"]["r"]))
		lo = minf(lo, r)
		hi = maxf(hi, r)
	_check(s_bad == "", "Jog_Fwd 24프레임 전부 발 늘이기 = 1.0 %s" % s_bad)
	_check(hi - lo > 10.0, "L_Foot 발목 회전 폭 %.1f° (발은 여전히 움직임)" % (hi - lo))

	var out_dir := "res://puppet_test/foot_bake"
	var ex := DRExporter.new()
	ex.baker = baker
	ex.out_dir = out_dir
	ex.anim_fps = 12
	ex.anim_names = PackedStringArray(["Jog_Fwd"])
	ex.auto_fit = false
	var res: Dictionary = await ex.run()
	_check(bool(res.get("ok", false)), "기본 프로필 베이크 ok")
	var ps := ResourceLoader.load(out_dir.path_join("puppet.tscn"), "",
		ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var pup := ps.instantiate()
	root.add_child(pup)
	var a := (pup.get_node("AnimationPlayer") as AnimationPlayer).get_animation("Jog_Fwd")
	for side in ["L", "R"]:
		_check(pup.find_child(side + "_Toe", true, false) == null, "씬에 %s_Toe 본 없음" % side)
		var fb := pup.find_child(side + "_Foot", true, false) as Bone2D
		if fb == null:
			_check(false, "씬에 %s_Foot 본" % side)
			continue
		var base := String(pup.get_path_to(fb))
		_check(a.find_track(NodePath(base + "/stretch:scale"), Animation.TYPE_VALUE) < 0,
			"%s_Foot 늘이기 트랙 없음" % side)
		_check(a.find_track(NodePath(base + ":rotation"), Animation.TYPE_VALUE) >= 0,
			"%s_Foot 회전 트랙 있음" % side)
	var calf := pup.find_child("L_Calf", true, false) as Bone2D
	_check(calf != null and a.find_track(NodePath(String(pup.get_path_to(calf)) + "/stretch:scale"),
		Animation.TYPE_VALUE) >= 0, "L_Calf 늘이기 트랙은 그대로 있음")
	pup.queue_free()

	var f := FileAccess.open(out_dir.path_join("rig.json"), FileAccess.READ)
	var doc: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var st := {}
	for p in doc.get("parts", []):
		st[String(p.get("name", ""))] = p.get("stretch", null)
	_check(st.get("L_Foot") == false and st.get("L_Calf") == true,
		"rig.json stretch — L_Foot %s · L_Calf %s" % [st.get("L_Foot"), st.get("L_Calf")])


# ---------------------------------------------------------------- humanoid(true): 발가락을 따로 꺾음

func _check_split(scene: PackedScene) -> void:
	var baker: DRBaker = await _make_baker(scene, DRPartProfile.humanoid(true))
	if baker == null:
		_check(false, "발가락 분리 프로필 setup"); return
	var rig := baker.rig

	print("[1] 발가락 분리 모드 — 구성")
	_check(rig.order.size() == 17, "파트 17개 (실제 %d)" % rig.order.size())
	_check(rig.layer_names().size() == 15, "레이어(순서 목록 줄) 15개 (실제 %d)" % rig.layer_names().size())
	var toe_rows := 0
	for l in rig.layer_names():
		if l.ends_with("_Toe"):
			toe_rows += 1
	_check(toe_rows == 0, "레이어 목록에 발가락 줄 없음 (%d줄)" % toe_rows)
	for side in ["L", "R"]:
		var toe: String = side + "_Toe"
		var foot: String = side + "_Foot"
		_check(rig.parts.has(toe), "%s 파트 존재" % toe)
		if not rig.parts.has(toe):
			continue
		var tp: DRRigModel.Part = rig.parts[toe]
		_check(rig.layer(toe) == foot, "%s 레이어 = %s" % [toe, rig.layer(toe)])
		_check(tp.parent == foot, "%s 부모 파트 = %s" % [toe, tp.parent])
		var rb := baker.skeleton.get_bone_name(tp.root_bone)
		_check(rb == "ball_" + side.to_lower(), "%s 루트 본 = %s" % [toe, rb])
		var tris := int(baker.split.tri_counts.get(toe, 0))
		_check(tris > 0, "%s 삼각형 %d개" % [toe, tris])

	print("[2] Jog_Fwd — 발가락이 발 기준으로 따로 접히나 / 자동 z 가 발 바로 위인가")
	var an := baker.resolve_anim("Jog_Fwd")
	var anim := baker.anim_player.get_animation(an)
	var lo := {"L_Toe": INF, "R_Toe": INF}
	var hi := {"L_Toe": -INF, "R_Toe": -INF}
	var adjacent := true
	var bad := ""
	for i in 24:
		var t := anim.length * float(i) / 24.0
		baker.set_pose(an, t)
		await RenderingServer.frame_post_draw
		var loc := rig.project_local(baker.skeleton, baker.camera)
		for toe in lo.keys():
			var r := rad_to_deg(float(loc[toe]["r"]))
			lo[toe] = minf(float(lo[toe]), r)
			hi[toe] = maxf(float(hi[toe]), r)
		for side in ["L", "R"]:
			var fz := int(loc[side + "_Foot"]["z"])
			var tz := int(loc[side + "_Toe"]["z"])
			if tz != fz + 1:
				adjacent = false
				bad = "(t=%.2f %s 발 z=%d 발가락 z=%d)" % [t, side, fz, tz]
	for toe in lo.keys():
		var sp := float(hi[toe]) - float(lo[toe])
		_check(sp > 10.0, "%s 발 기준 회전 폭 %.1f°" % [toe, sp])
	_check(adjacent, "24프레임 전부 발가락 z = 발 z + 1 %s" % bad)

	print("[3] 수동 순서 — 사용자 프리셋 / 파트 이름이 섞인 옛 목록")
	var pres := load("res://UAL1_preset.tres") as DRPreset
	var src := pres.z_order if pres != null else PackedStringArray()
	var manual := rig.normalize_layer_order(src)
	_check(manual.size() == 15, "프리셋 순서 %d개 → 레이어 %d줄" % [src.size(), manual.size()])
	var norm := rig.normalize_layer_order(PackedStringArray(["L_Toe", "Torso", "L_Foot", "R_Toe"]))
	_check(norm.size() == 15 and norm[0] == "L_Foot" and norm[1] == "Torso" and norm[2] == "R_Foot",
		"[L_Toe, Torso, L_Foot, R_Toe] → %s ..." % str(Array(norm).slice(0, 3)))
	var po := rig.expand_layers(manual)
	for side in ["L", "R"]:
		var fi := po.find(side + "_Foot")
		var ti := po.find(side + "_Toe")
		_check(fi >= 0 and ti == fi + 1, "펼친 순서에서 %s 발 %d번 · 발가락 %d번" % [side, fi, ti])

	print("[4] 베이크 결과 — 수동 순서 + Jog_Fwd")
	var out_dir := "res://puppet_test/layer_bake"
	var ex := DRExporter.new()
	ex.baker = baker
	ex.out_dir = out_dir
	ex.anim_fps = 12
	ex.anim_names = PackedStringArray(["Jog_Fwd"])
	ex.auto_fit = false
	ex.z_override = manual
	var res: Dictionary = await ex.run()
	_check(bool(res.get("ok", false)), "베이크 ok")

	var ps := ResourceLoader.load(out_dir.path_join("puppet.tscn"), "",
		ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var pup := ps.instantiate()
	root.add_child(pup)
	var ap := pup.get_node("AnimationPlayer") as AnimationPlayer
	var a := ap.get_animation("Jog_Fwd")
	for side in ["L", "R"]:
		var toe_bone := pup.find_child(side + "_Toe", true, false) as Bone2D
		var foot_bone := pup.find_child(side + "_Foot", true, false) as Bone2D
		_check(toe_bone != null and foot_bone != null and toe_bone.get_parent() == foot_bone,
			"%s_Toe 본이 %s_Foot 본의 자식" % [side, side])
		if toe_bone == null or foot_bone == null:
			continue
		var tz := (toe_bone.get_node("stretch/art") as Sprite2D).z_index
		var fz := (foot_bone.get_node("stretch/art") as Sprite2D).z_index
		_check(tz == fz + 1, "%s 씬 z_index 발 %d / 발가락 %d" % [side, fz, tz])
		var path := NodePath(String(pup.get_path_to(toe_bone)) + ":rotation")
		var tr := a.find_track(path, Animation.TYPE_VALUE)
		var rlo := INF
		var rhi := -INF
		if tr >= 0:
			for k in a.track_get_key_count(tr):
				var v := float(a.track_get_key_value(tr, k))
				rlo = minf(rlo, v)
				rhi = maxf(rhi, v)
		var span := rad_to_deg(rhi - rlo) if tr >= 0 else 0.0
		_check(tr >= 0 and span > 10.0, "%s_Toe 회전 트랙 폭 %.1f°" % [side, span])

	var f := FileAccess.open(out_dir.path_join("rig.json"), FileAccess.READ)
	var doc: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var lorder: Array = doc.get("layer_order", [])
	var toe_in := 0
	for n in lorder:
		if String(n).ends_with("_Toe"):
			toe_in += 1
	_check(lorder.size() == 15 and toe_in == 0, "rig.json layer_order %d줄, 발가락 줄 %d" % [lorder.size(), toe_in])
	var toe_layer := ""
	for p in doc.get("parts", []):
		if String(p.get("name", "")) == "L_Toe":
			toe_layer = String(p.get("layer", ""))
	_check(toe_layer == "L_Foot", "rig.json parts[L_Toe].layer = %s" % toe_layer)
