extends SceneTree

## 장비 부착 검증. 퍼펫에 헬멧 1장을 붙이고 애니메이션을 돌려서
## 프레임 내내 머리에 정확히 붙어 다니는지 확인한다.
##
##   Godot.exe --path <프로젝트> --script res://addons/dot_rigger/tools/equip_test_cli.gd -- \
##       --scene=res://puppet_test/puppet.tscn --anim=Jog_Fwd \
##       --tex=res://puppet_test/_test_helmet.png --part=Head --frames=12

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
		printerr("씬 로드 실패"); quit(1); return

	# rig.json 에서 뷰 크기와 붙일 파트의 crop 원점을 읽는다.
	var rig_path := scene_path.get_base_dir().path_join("rig.json")
	var f := FileAccess.open(rig_path, FileAccess.READ)
	if f == null:
		printerr("rig.json 없음"); quit(1); return
	var doc: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var sz: Array = doc["view"]["size"]
	var view := Vector2i(int(sz[0]), int(sz[1]))

	var part := _arg("part", "Head")
	var crop := Vector2.ZERO
	for p in doc["parts"]:
		if String(p["name"]) == part:
			crop = Vector2(float(p["crop"][0]), float(p["crop"][1]))
	print("파트 %s crop 원점 = %s" % [part, crop])

	var vp := SubViewport.new()
	vp.size = view
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(vp)
	var puppet := ps.instantiate()
	vp.add_child(puppet)

	if not (puppet is DRPuppet):
		printerr("퍼펫에 DRPuppet 스크립트가 없습니다 (다시 베이크 필요)")
		quit(1); return
	var pup := puppet as DRPuppet
	print("인식된 파트: ", pup.part_names())

	# 장비 1점 장착
	var tex_path := _arg("tex", "")
	var item := DREquipItem.new()
	item.slot = "helmet"
	item.part = part
	item.texture = ResourceLoader.load(tex_path, "Texture2D") as Texture2D
	if item.texture == null:
		printerr("장비 텍스처 로드 실패: ", tex_path); quit(1); return
	# 이미지 좌상단을 파트 crop 원점 기준으로 배치
	item.offset = crop + Vector2(float(_arg("dx", "0")), float(_arg("dy", "0")))
	item.z_index = int(_arg("z", "30"))
	if not pup.equip(item):
		printerr("장착 실패"); quit(1); return
	print("장착 완료: slot=%s part=%s offset=%s z=%d" % [item.slot, item.part, item.offset, item.z_index])

	# 애니메이션 캡처
	var ap := puppet.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var aname := _arg("anim", "")
	if ap == null or not ap.has_animation(aname):
		printerr("애니메이션 없음: ", aname); quit(1); return
	var anim := ap.get_animation(aname)
	var n := int(_arg("frames", "12"))
	var sc := int(_arg("scale", "3"))
	var strip := Image.create(view.x * sc * n, view.y * sc, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.13, 0.13, 0.16, 1.0))
	ap.play(aname)
	for i in n:
		ap.seek((float(i) / float(n)) * anim.length, true)
		ap.advance(0.0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		if sc > 1:
			img.resize(view.x * sc, view.y * sc, Image.INTERPOLATE_NEAREST)
		strip.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(i * view.x * sc, 0))
	var outp := scene_path.get_base_dir().path_join("_equip_%s_strip.png" % aname)
	strip.save_png(outp)
	print("저장: ", outp)
	quit(0)
