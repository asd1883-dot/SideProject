extends SceneTree

## 같은 출력 폴더에 여러 번 구우면 애니메이션이 쌓이는지 검사.
## - 같은 레스트 포즈·시점이면 예전 애니 유지 + 이번 애니 추가, 같은 이름은 교체
## - 레스트 포즈가 다르면 예전 애니는 섞지 않고 이유를 남김
## - keep_previous = false 면 이번 애니만
##
##   Godot.exe --path <프로젝트> --resolution 400x300 \
##     --script res://addons/dot_rigger/tools/anim_merge_check_cli.gd

const OUT := "res://puppet_test/merge_bake"

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


func _bake(baker: DRBaker, anims: Array, keep: bool = true) -> DRExporter:
	var ex := DRExporter.new()
	ex.baker = baker
	ex.out_dir = OUT
	ex.anim_fps = 12
	ex.anim_names = PackedStringArray(anims)
	ex.auto_fit = false
	ex.keep_previous = keep
	var res: Dictionary = await ex.run()
	_check(bool(res.get("ok", false)), "베이크 %s (유지 %s) ok" % [str(anims), keep])
	return ex


func _scene_anims() -> Array:
	var ps := ResourceLoader.load(OUT.path_join("puppet.tscn"), "",
		ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if ps == null:
		return []
	var pup := ps.instantiate()
	var ap := pup.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var out: Array = []
	if ap != null:
		out = Array(ap.get_animation_list())
	pup.free()
	out.sort()
	return out


func _json_anims() -> Array:
	var f := FileAccess.open(OUT.path_join("rig.json"), FileAccess.READ)
	if f == null:
		return []
	var doc: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var out: Array = (doc.get("animations", {}) as Dictionary).keys()
	out.sort()
	return out


func _expect(want: Array, tag: String) -> void:
	var s := _scene_anims()
	var j := _json_anims()
	_check(s == want, "%s — 씬 AnimationPlayer 애니 %s" % [tag, str(s)])
	_check(j == want, "%s — rig.json 애니 %s" % [tag, str(j)])


func _run() -> void:
	_rm_dir(ProjectSettings.globalize_path(OUT))
	var scene := load("res://models/UAL1.glb") as PackedScene
	var opts := DRBaker.Options.new()
	opts.view_size = Vector2i(184, 184)
	opts.yaw = -55.0
	opts.rest_anim = "Idle"
	var baker := DRBaker.new()
	if not baker.setup(root, scene, DRPartProfile.humanoid(), opts):
		printerr("setup 실패"); quit(1); return
	baker.set_rest_pose()
	await RenderingServer.frame_post_draw

	print("[1] 레스트 Idle 로 Idle 굽기")
	await _bake(baker, ["Idle"])
	_expect(["Idle"], "Idle 만")

	print("[2] 같은 레스트·시점으로 Jog_Fwd 굽기 → Idle 유지 + Jog_Fwd 추가")
	var ex2: DRExporter = await _bake(baker, ["Jog_Fwd"])
	_expect(["Idle", "Jog_Fwd"], "쌓임")
	_check(Array(ex2.kept_anims) == ["Idle"] and ex2.dropped_reason == "",
		"이어 담은 애니 %s · 못 섞은 이유 \"%s\"" % [str(ex2.kept_anims), ex2.dropped_reason])

	print("[3] Idle 다시 굽기 → 같은 이름은 교체(중복 없음), Jog_Fwd 유지")
	var ex3: DRExporter = await _bake(baker, ["Idle"])
	_expect(["Idle", "Jog_Fwd"], "교체")
	_check(Array(ex3.kept_anims) == ["Jog_Fwd"], "이어 담은 애니 %s" % str(ex3.kept_anims))

	print("[4] 레스트 포즈를 Jog_Fwd 로 바꿔 Idle 굽기 → 예전 애니는 섞지 않음")
	baker.opts.rest_anim = "Jog_Fwd"
	var ex4: DRExporter = await _bake(baker, ["Idle"])
	_expect(["Idle"], "레스트 다름")
	_check(ex4.dropped_reason.contains("레스트 포즈가 다름") and ex4.dropped_reason.contains("Jog_Fwd"),
		"이유: %s" % ex4.dropped_reason)

	print("[5] 레스트를 Idle 로 되돌려 쌓은 뒤, 유지 끄고 굽기 → 이번 애니만")
	baker.opts.rest_anim = "Idle"
	await _bake(baker, ["Jog_Fwd"])
	await _bake(baker, ["Idle"])
	_expect(["Idle", "Jog_Fwd"], "다시 쌓임")
	var ex5: DRExporter = await _bake(baker, ["Idle"], false)
	_expect(["Idle"], "유지 끔")
	_check(ex5.kept_anims.is_empty() and ex5.dropped_reason == "", "유지 끔 — 이어 담은 애니 없음")

	print("\n" + ("애니 누적 검사 전부 통과" if _fail == 0 else "실패 %d건" % _fail))
	quit(0 if _fail == 0 else 1)
