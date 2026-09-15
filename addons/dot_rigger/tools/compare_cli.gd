extends SceneTree

## 같은 시점에서 "3D 렌더(정답)" 와 "2D 순서 합성(베이크 결과)" 를 나란히 뽑는다.
## 그리기 순서를 맞출 때 무엇이 어긋나는지 보는 용도.
##
##   Godot.exe --path <프로젝트> --resolution 800x600 \
##     --script res://addons/dot_rigger/tools/compare_cli.gd -- \
##     --model=res://models/UAL1.glb --yaw=-65 --rest=Idle --size=192 \
##     --out=res://cmp

var _args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			s = s.substr(2)
		var eq := s.find("=")
		if eq >= 0:
			_args[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			_args[s] = "1"
	_run.call_deferred()


func _arg(k: String, d: String = "") -> String:
	return String(_args.get(k, d))


func _run() -> void:
	var scene := load(_arg("model", "res://models/UAL1.glb")) as PackedScene
	if scene == null:
		printerr("모델 로드 실패"); quit(1); return

	var opts := DRBaker.Options.new()
	var sz := int(_arg("size", "192"))
	opts.view_size = Vector2i(sz, sz)
	opts.yaw = float(_arg("yaw", "90"))
	opts.pitch = float(_arg("pitch", "0"))
	opts.bleed_rings = int(_arg("bleed", "1"))
	opts.rest_anim = _arg("rest", "")
	opts.light_bands = int(_arg("bands", "3"))

	var baker := DRBaker.new()
	if not baker.setup(root, scene, DRPartProfile.humanoid(), opts):
		printerr("setup 실패"); quit(1); return
	baker.set_rest_pose()
	await RenderingServer.frame_post_draw
	await baker.auto_fit(int(_arg("margin", "6")))
	baker.rig.capture_rest(baker.skeleton, baker.camera)

	var out_dir := _arg("out", "res://cmp")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	# 1) 3D 렌더 = 픽셀마다 깊이로 판정한 정답
	var img3: Image = await baker.render_all_parts_composite()
	img3.save_png(out_dir.path_join("a_3d.png"))

	# 2) 깊이 기준 자동 순서로 2D 합성 = 베이크 결과와 같은 방식
	var order := baker.rig.expand_layers(baker.rig.rest_layer_order())   # 베이크 자동 순서와 같은 규칙(레이어 단위)
	print("[그리기 순서 뒤->앞] ", String(" < ").join(PackedStringArray(order)))

	var img2 := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img2.fill(Color(0, 0, 0, 0))
	for n in order:
		var pi: Image = await baker.render_part(String(n))
		img2.blend_rect(pi, Rect2i(Vector2i.ZERO, pi.get_size()), Vector2i.ZERO)
	img2.save_png(out_dir.path_join("b_2d_order.png"))

	# 3) 차이
	var diff := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	var n_diff := 0
	var n_area := 0
	for y in sz:
		for x in sz:
			var c3 := img3.get_pixel(x, y)
			var c2 := img2.get_pixel(x, y)
			if c3.a > 0.0 or c2.a > 0.0:
				n_area += 1
			var d := absf(c3.r - c2.r) + absf(c3.g - c2.g) + absf(c3.b - c2.b) \
				+ absf(c3.a - c2.a)
			if d > 0.15:
				n_diff += 1
				diff.set_pixel(x, y, Color(1, 0.2, 0.2, 1))
	diff.save_png(out_dir.path_join("c_diff.png"))
	print("불일치 %d px / 캐릭터 %d px (%.1f%%)"
		% [n_diff, n_area, 100.0 * float(n_diff) / float(maxi(n_area, 1))])
	print("저장: ", out_dir)
	quit(0)
