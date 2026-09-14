extends SceneTree

## 생성된 puppet.tscn 을 실제로 Godot 에서 재생해 프레임을 캡처한다.
## (파이썬 재구성이 아니라 엔진이 진짜로 그 결과를 내는지 확인하는 용도)
##
##   Godot.exe --path <프로젝트> --script res://addons/dot_rigger/tools/preview_cli.gd -- \
##       --scene=res://puppet_test/puppet.tscn --anim=Jog_Fwd --frames=12 --scale=3

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
	var scene_path := _arg("scene", "res://puppet_test/puppet.tscn")
	var ps := load(scene_path) as PackedScene
	if ps == null:
		printerr("씬 로드 실패: ", scene_path)
		quit(1)
		return

	var rig_path := scene_path.get_base_dir().path_join("rig.json")
	var view := Vector2i(192, 192)
	var f := FileAccess.open(rig_path, FileAccess.READ)
	if f != null:
		var doc = JSON.parse_string(f.get_as_text())
		f.close()
		if doc is Dictionary and doc.has("view"):
			var sz: Array = doc["view"]["size"]
			view = Vector2i(int(sz[0]), int(sz[1]))

	var vp := SubViewport.new()
	vp.size = view
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(vp)

	var puppet := ps.instantiate() as Node2D
	vp.add_child(puppet)

	# --static: 애니메이션을 재생하지 않고 씬 그대로(레스트 상태) 한 장만 찍는다.
	# 정지 상태의 z_index 배치를 확인하는 용도.
	if _args.has("static"):
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var simg := vp.get_texture().get_image()
		simg.convert(Image.FORMAT_RGBA8)
		var ssc := int(_arg("scale", "3"))
		if ssc > 1:
			simg.resize(view.x * ssc, view.y * ssc, Image.INTERPOLATE_NEAREST)
		var sp := scene_path.get_base_dir().path_join("_engine_static.png")
		simg.save_png(sp)
		print("정지 렌더 저장: ", sp)
		quit(0)
		return

	var ap := puppet.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		printerr("AnimationPlayer 없음")
		quit(1)
		return
	print("씬 애니메이션: ", ap.get_animation_list())
	print("퍼펫 자식: ", puppet.get_node("Skeleton2D").get_children().size(), "개 루트 본")

	var aname := _arg("anim", "")
	if aname == "" or not ap.has_animation(aname):
		var lst := ap.get_animation_list()
		if lst.size() == 0:
			printerr("애니메이션이 없습니다")
			quit(1)
			return
		aname = String(lst[0])
	var anim := ap.get_animation(aname)
	var n := int(_arg("frames", "12"))
	var sc := int(_arg("scale", "3"))
	var out_dir := scene_path.get_base_dir()

	print("재생: %s  length=%.3f  트랙 %d개" % [aname, anim.length, anim.get_track_count()])

	var strip := Image.create(view.x * sc * n, view.y * sc, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.13, 0.13, 0.16, 1.0))
	ap.play(aname)
	for i in n:
		var t := (float(i) / float(n)) * anim.length
		ap.seek(t, true)
		ap.advance(0.0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		if sc > 1:
			img.resize(view.x * sc, view.y * sc, Image.INTERPOLATE_NEAREST)
		strip.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()),
			Vector2i(i * view.x * sc, 0))
	var p := out_dir.path_join("_engine_%s_strip.png" % aname)
	strip.save_png(p)
	print("저장: ", p)
	quit(0)
