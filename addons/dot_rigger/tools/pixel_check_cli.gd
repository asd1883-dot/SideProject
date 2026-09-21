extends SceneTree

## 도트 격자 고정 검사.
##  [1] 구우면 puppet_pixel.tscn 이 나오고(래퍼 = DRPixelPuppet, 안쪽은 puppet.tscn **참조**), 경계 섞기는 꺼진다
##  [2] 래퍼를 3배로 그리면 모든 도트가 3×3 한 덩어리(같은 격자) — 그냥 puppet.tscn 을 3배 하면 기울어진 도트가 나온다(대조)
##  [3] 모든 애니의 모든 프레임이 래퍼 뷰포트 안에 담긴다(가장자리 1px 가 비어 있음)
##  [4] extra_margin 을 키워도 화면의 퍼펫 자리는 그대로
##  [5] 끄고 다시 구우면 예전 puppet_pixel.tscn 이 지워진다
##
##   Godot.exe --path <프로젝트> --resolution 900x700 --script res://addons/dot_rigger/tools/pixel_check_cli.gd

const MODEL := "res://models/UAL1.glb"
const OUT := "res://puppet_test/pixel_bake"
const ANIMS := ["Jog_Fwd", "Roll"]
const SCALE := 3

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  OK    " if ok else "  FAIL  ") + msg)
	if not ok:
		_fail += 1


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


## 3×3 칸 가운데 색이 한 가지가 아닌 칸 수(내용이 있는 칸만 센다)
func _mixed_blocks(img: Image) -> Array:
	var mixed := 0
	var filled := 0
	for by in int(img.get_height() / float(SCALE)):
		for bx in int(img.get_width() / float(SCALE)):
			var c0 := img.get_pixel(bx * SCALE, by * SCALE)
			var same := true
			var any := c0.a > 0.0
			for dy in SCALE:
				for dx in SCALE:
					var c := img.get_pixel(bx * SCALE + dx, by * SCALE + dy)
					if c.a > 0.0:
						any = true
					if not c.is_equal_approx(c0):
						same = false
			if any:
				filled += 1
				if not same:
					mixed += 1
	return [mixed, filled]


func _run() -> void:
	var opts := DRBaker.Options.new()
	opts.view_size = Vector2i(96, 96)
	opts.yaw = -55.0
	opts.rest_anim = "Walk"
	opts.rest_time = 0.3
	var baker := DRBaker.new()
	if not baker.setup(root, load(MODEL) as PackedScene, DRPartProfile.humanoid(), opts):
		printerr("setup 실패"); quit(1); return
	await process_frame
	var ex := DRExporter.new()
	ex.baker = baker
	ex.out_dir = OUT
	ex.keep_previous = false
	ex.anim_names = PackedStringArray(ANIMS)
	ex.apply_cfg({"smooth": true, "outline_px": 1, "outline_whole": true, "pixel_grid": true})
	var res: Dictionary = await ex.run()

	print("[1] 산출물")
	var pixel_path := OUT.path_join(DRExporter.PIXEL_SCENE)
	_check(bool(res.get("ok", false)) and String(res.get("pixel_scene", "")) == pixel_path and FileAccess.file_exists(pixel_path), "puppet_pixel.tscn 생성 (%s)" % res.get("pixel_scene", ""))
	var rj := _json(OUT.path_join("rig.json"))
	var pv: Dictionary = rj.get("pixel_view", {})
	_check(bool(rj.get("pixel_grid", false)) and not bool(rj.get("smooth_pixel", true)) and pv.has("size") and pv.has("origin"),
		"rig.json pixel_grid · smooth_pixel 꺼짐 · pixel_view %s" % str(pv))
	var txt := FileAccess.get_file_as_string(pixel_path)
	_check(txt.contains("instance=ExtResource") and not txt.contains("Bone2D"), "안쪽 퍼펫은 puppet.tscn 참조(씬에 풀려 들어가지 않음)")
	var wrap := (ResourceLoader.load(pixel_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var view := wrap.get_node_or_null("View") as SubViewport
	var art := wrap.find_child("art", true, false) as Sprite2D
	var art_mat := art.material as ShaderMaterial if art != null else null
	_check(wrap is DRPixelPuppet and view != null and view.snap_2d_transforms_to_pixel and view.transparent_bg
		and view.canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		and wrap.get_puppet() != null and wrap.get_animation_player() != null,
		"래퍼 = DRPixelPuppet · View(투명·nearest·정수 맞춤) · get_puppet()/get_animation_player()")
	_check(art_mat == null or not bool(art_mat.get_shader_parameter("smooth_edges")), "파트 셰이더의 경계 섞기 꺼짐")

	print("[2] 도트 격자 — 3배로 그렸을 때 3×3 칸이 한 색인가")
	var big := SubViewport.new()
	big.size = Vector2i(900, 700)
	big.transparent_bg = true
	big.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	big.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(big)
	big.add_child(wrap)
	var pw := wrap as DRPixelPuppet
	pw.pixel_scale = SCALE
	pw.position = Vector2(pw.view_origin) * float(SCALE)      # Screen 의 왼쪽 위가 (0,0) → 칸이 3의 배수에 맞는다
	var ap := pw.get_animation_player()
	ap.speed_scale = 0.0          # 시간을 세워 둔다 — 안 그러면 찍는 사이에 자세가 흘러 [4] 의 전후 비교가 안 맞는다
	var worst_mixed := 0
	var total_filled := 0
	var edge_hits := 0
	var frames := 0
	var keep_img: Image = null
	for an in ANIMS:
		ap.play(an)
		var length := ap.get_animation(an).length
		for i in 6:
			ap.seek(length * (float(i) + 0.37) / 6.0, true)
			ap.advance(0.0)
			for _j in 4:
				await RenderingServer.frame_post_draw
			var img := big.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			img = img.get_region(Rect2i(Vector2i.ZERO, pw.view_size * SCALE))
			var mb := _mixed_blocks(img)
			worst_mixed = maxi(worst_mixed, int(mb[0]))
			total_filled += int(mb[1])
			frames += 1
			# [3] 래퍼 뷰포트의 가장자리 1px
			var vi := view.get_texture().get_image()
			for x in vi.get_width():
				if vi.get_pixel(x, 0).a > 0.0 or vi.get_pixel(x, vi.get_height() - 1).a > 0.0:
					edge_hits += 1
			for y in vi.get_height():
				if vi.get_pixel(0, y).a > 0.0 or vi.get_pixel(vi.get_width() - 1, y).a > 0.0:
					edge_hits += 1
			if an == "Jog_Fwd" and i == 2:
				keep_img = img
				img.save_png("res://puppet_test/_pixel_wrapper_x3.png")
	_check(worst_mixed == 0 and total_filled > 1000, "래퍼: %d프레임, 내용 있는 칸 %d개 중 색이 섞인 칸 최대 %d개" % [frames, total_filled, worst_mixed])
	print("[3] 움직임 범위")
	_check(edge_hits == 0, "Jog_Fwd · Roll 전 프레임이 뷰포트 %s 안 (가장자리에 닿은 픽셀 %d개) — 캔버스는 %s" % [str(pw.view_size), edge_hits, str(opts.view_size)])

	print("[4] extra_margin")
	ap.play("Jog_Fwd")
	ap.seek(ap.get_animation("Jog_Fwd").length * (2.37 / 6.0), true)
	ap.advance(0.0)
	pw.extra_margin = 5
	for _j in 4:
		await RenderingServer.frame_post_draw
	var img_m := big.get_texture().get_image()
	img_m.convert(Image.FORMAT_RGBA8)
	img_m = img_m.get_region(Rect2i(Vector2i.ZERO, pw.view_size * SCALE))
	var moved := 0
	for y in keep_img.get_height():
		for x in keep_img.get_width():
			if not keep_img.get_pixel(x, y).is_equal_approx(img_m.get_pixel(x, y)):
				moved += 1
	_check(view.size == pw.view_size + Vector2i(10, 10) and moved == 0, "여유 5 → 뷰포트 %s, 화면의 퍼펫은 그대로(달라진 픽셀 %d개)" % [str(view.size), moved])
	big.remove_child(wrap)
	wrap.free()

	# 대조: 래퍼 없이 puppet.tscn 을 3배 → 기울어진 도트(섞인 칸)가 생겨야 정상
	var plain := (ResourceLoader.load(OUT.path_join("puppet.tscn"), "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node2D
	big.add_child(plain)
	plain.scale = Vector2(SCALE, SCALE)
	plain.position = Vector2(60, 60)
	var pap := plain.get_node("AnimationPlayer") as AnimationPlayer
	pap.speed_scale = 0.0
	pap.play("Jog_Fwd")
	pap.seek(pap.get_animation("Jog_Fwd").length * (2.37 / 6.0), true)
	pap.advance(0.0)
	for _j in 4:
		await RenderingServer.frame_post_draw
	var img_p := big.get_texture().get_image()
	img_p.convert(Image.FORMAT_RGBA8)
	img_p.save_png("res://puppet_test/_pixel_plain_x3.png")
	var mp := _mixed_blocks(img_p)
	_check(int(mp[0]) > 50, "대조 — puppet.tscn 을 그냥 3배: 색이 섞인 칸 %d/%d개(기울어진 도트)" % [int(mp[0]), int(mp[1])])
	big.remove_child(plain)
	plain.free()

	print("[5] 끄고 다시 굽기")
	var ex2 := DRExporter.new()
	ex2.baker = baker
	ex2.out_dir = OUT
	ex2.keep_previous = false
	ex2.anim_names = PackedStringArray(["Jog_Fwd"])
	ex2.apply_cfg({"smooth": true, "pixel_grid": false})
	var res2: Dictionary = await ex2.run()
	var rj2 := _json(OUT.path_join("rig.json"))
	_check(bool(res2.get("ok", false)) and not FileAccess.file_exists(pixel_path) and not bool(rj2.get("pixel_grid", true)) and bool(rj2.get("smooth_pixel", false)),
		"puppet_pixel.tscn 지워짐 · rig.json pixel_grid false · smooth_pixel 다시 켜짐")

	if _fail > 0:
		printerr("도트 격자 고정 검사 실패 %d건" % _fail)
		quit(1); return
	print("도트 격자 고정 검사 전부 통과")
	quit(0)
