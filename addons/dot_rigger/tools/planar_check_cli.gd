extends SceneTree

## 동작 평면화(2D 게임식) 베이크 검사.
## 평면화로 구우면 모든 파트의 늘이기 s = 1, 자식 파트 위치는 프레임 내내 레스트 오프셋(강체 2D 리그),
## 팔은 여전히 흔들리고(회전 트랙 폭), rig.json view 에 planar/pose_yaw 가 남고,
## 같은 폴더에 평면화 끈 애니를 이어 담으려 하면 거절해야 한다.
##
##   Godot.exe --path <프로젝트> --resolution 400x300 \
##     --script res://addons/dot_rigger/tools/planar_check_cli.gd

const OUT := "res://puppet_test/planar_bake"

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  OK    " if ok else "  FAIL  ") + msg)
	if not ok:
		_fail += 1


func _rm_dir(abs_path: String) -> void:
	var d := DirAccess.open(abs_path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_rm_dir(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}


func _run() -> void:
	_rm_dir(ProjectSettings.globalize_path(OUT))
	var scene := load("res://models/UAL1.glb") as PackedScene
	var opts := DRBaker.Options.new()
	opts.view_size = Vector2i(184, 184)
	opts.yaw = -55.0
	opts.rest_anim = "Walk"
	opts.planar = true
	var baker := DRBaker.new()
	if not baker.setup(root, scene, DRPartProfile.humanoid(), opts):
		printerr("setup 실패"); quit(1); return
	opts.rest_time = baker.anim_player.get_animation("Walk").length * 0.88
	baker.set_rest_pose()
	await RenderingServer.frame_post_draw

	print("[1] 포즈 카메라")
	_check(baker.pose_camera != null and not baker.pose_camera.current and baker.camera.current, "포즈 카메라는 렌더하지 않음(current 아님)")
	_check(absf(baker.effective_pose_yaw() - (-90.0)) < 0.01, "자동 동작 시점 = −90° (게임 yaw −55 에 가까운 측면), 실제 %.0f" % baker.effective_pose_yaw())
	_check(absf(baker.pose_camera.size - baker.camera.size) < 1e-6, "포즈 카메라 크기 = 렌더 카메라 크기 %.3f" % baker.pose_camera.size)
	opts.pose_yaw = 0.0
	baker.apply_camera()
	_check(absf(baker.effective_pose_yaw()) < 0.01 and absf(baker.pose_camera.global_transform.basis.z.z - 1.0) < 0.01,
		"동작 시점 0 → 포즈 카메라가 정면(+Z)에서 봄")
	opts.pose_yaw = 999.0
	baker.apply_camera()

	print("[2] 평면화 베이크 — Walk · Jog_Fwd")
	var ex := DRExporter.new()
	ex.baker = baker
	ex.out_dir = OUT
	ex.anim_names = PackedStringArray(["Walk", "Jog_Fwd"])
	ex.auto_fit = false
	ex.keep_previous = false
	var res: Dictionary = await ex.run()
	_check(bool(res.get("ok", false)), "베이크 ok")
	var doc := _json(OUT.path_join("rig.json"))
	var v: Dictionary = doc.get("view", {})
	_check(bool(v.get("planar", false)) and absf(float(v.get("pose_yaw", 0.0)) - (-90.0)) < 0.01,
		"rig.json view.planar %s · pose_yaw %.0f" % [v.get("planar"), float(v.get("pose_yaw", 0.0))])
	var parents := {}
	var rest_head := {}
	for p in doc.get("parts", []):
		parents[String(p["name"])] = String(p["parent"])
		rest_head[String(p["name"])] = Vector2(float(p["rest"]["head"][0]), float(p["rest"]["head"][1]))
	var s_bad := 0
	var p_bad := 0
	var hips_moved := false
	var swing := {}
	var nframes := 0
	for an in ["Walk", "Jog_Fwd"]:
		var frames: Array = doc["animations"][an]["frames"]
		nframes += frames.size()
		for fr in frames:
			var pd: Dictionary = fr["parts"]
			for pn in pd.keys():
				var e: Dictionary = pd[pn]
				if absf(float(e["s"]) - 1.0) > 0.000001:
					s_bad += 1
				var par := String(parents.get(pn, ""))
				if par != "":
					var want: Vector2 = rest_head[pn] - rest_head[par]
					if (Vector2(float(e["p"][0]), float(e["p"][1])) - want).length() > 0.001:
						p_bad += 1
				else:
					if (Vector2(float(e["p"][0]), float(e["p"][1])) - rest_head[pn]).length() > 0.5:
						hips_moved = true
				if not swing.has(pn):
					swing[pn] = [INF, -INF]
				swing[pn][0] = minf(swing[pn][0], float(e["r"]))
				swing[pn][1] = maxf(swing[pn][1], float(e["r"]))
	_check(s_bad == 0, "전 프레임(%d) 전 파트 늘이기 s = 1 (아닌 값 %d개)" % [nframes, s_bad])
	_check(p_bad == 0, "자식 파트 위치 = 레스트 오프셋으로 고정 (어긋난 값 %d개)" % p_bad)
	_check(hips_moved, "힙(루트)은 들썩임이 남음")
	var arm := rad_to_deg(swing["L_UpperArm"][1] - swing["L_UpperArm"][0])
	var thigh := rad_to_deg(swing["R_Thigh"][1] - swing["R_Thigh"][0])
	_check(arm > 20.0 and thigh > 30.0, "회전 폭 L_UpperArm %.0f° · R_Thigh %.0f° (팔다리는 화면 안에서 흔들림)" % [arm, thigh])
	var ps := ResourceLoader.load(OUT.path_join("puppet.tscn"), "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var pup := ps.instantiate()
	var a := (pup.get_node("AnimationPlayer") as AnimationPlayer).get_animation("Walk")
	var fb := pup.find_child("L_Forearm", true, false) as Bone2D
	var t_s := a.find_track(NodePath(String(pup.get_path_to(fb)) + "/stretch:scale"), Animation.TYPE_VALUE)
	var s_const := true
	if t_s >= 0:
		for k in a.track_get_key_count(t_s):
			if (a.track_get_key_value(t_s, k) as Vector2).distance_to(Vector2.ONE) > 0.000001:
				s_const = false
	_check(s_const, "씬 L_Forearm 늘이기 트랙이 전부 (1,1)")
	pup.free()

	print("[3] 평면화 끈 애니는 같은 폴더에 못 섞임")
	opts.planar = false
	baker.apply_camera()
	var ex2 := DRExporter.new()
	ex2.baker = baker
	ex2.out_dir = OUT
	ex2.anim_names = PackedStringArray(["Idle"])
	ex2.auto_fit = false
	ex2.keep_previous = true
	var res2: Dictionary = await ex2.run()
	_check(bool(res2.get("ok", false)) and ex2.dropped_reason.contains("평면화"), "이유: %s" % ex2.dropped_reason)
	var doc2 := _json(OUT.path_join("rig.json"))
	_check((doc2.get("animations", {}) as Dictionary).keys() == ["Idle"], "남은 애니 %s" % str((doc2.get("animations", {}) as Dictionary).keys()))

	print("\n" + ("평면화 검사 전부 통과" if _fail == 0 else "실패 %d건" % _fail))
	quit(0 if _fail == 0 else 1)
