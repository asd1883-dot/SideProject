extends SceneTree

## 복장 확인 CLI — 기본 몸 퍼펫(DRPuppetSet)에 복장을 입혀 동작마다 몇 프레임 찍어 한 장으로 붙인다.
##   줄 1 = 몸 그대로 · 줄 2 = 복장 전부 · 줄 3 = 상의만(하의 · 신발은 몸 그대로) — 옷만 갈아입는 것 확인용
##
##   godot --path . --resolution 900x700 --script res://addons/dot_rigger/tools/outfit_check_cli.gd -- \
##       --sets=res://puppet/sets.json --outfit=res://outfits/m36/outfit.json --out=res://puppet_test/_outfit_check.png

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


func _arg(key: String, def: String = "") -> String:
	return String(_args.get(key, def))


func _run() -> void:
	var outfit := DROutfit.load_json(_arg("outfit"))
	if outfit == null:
		printerr("복장을 읽을 수 없습니다"); quit(1); return
	var cell := Vector2i(200, 230)
	var frames := int(_arg("frames", "3"))
	var vp := SubViewport.new()
	vp.size = cell
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.17, 0.2)
	bg.size = Vector2(cell)
	vp.add_child(bg)
	var pset := DRPuppetSet.new()
	pset.sets_json = _arg("sets", "res://puppet/sets.json")
	pset.position = Vector2(cell.x * 0.5, cell.y - 12)
	# 세트 캔버스가 칸보다 크면(384px 등) 칸에 들어오게 줄인다 — --scale 로 직접 줄 수도 있다
	var sc := float(_arg("scale", "0"))
	if sc <= 0.0:
		sc = 1.0
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(pset.sets_json))
		if doc is Dictionary and ((doc as Dictionary).get("sets", []) as Array).size() > 0:
			var first: Dictionary = (doc as Dictionary)["sets"][0]
			var rig: Variant = JSON.parse_string(FileAccess.get_file_as_string(pset.sets_json.get_base_dir().path_join(String(first.get("rig", "")))))
			if rig is Dictionary:
				var vs: Array = ((rig as Dictionary).get("view", {}) as Dictionary).get("size", [192, 192])
				sc = minf(1.0, float(cell.y - 20) / float(vs[1]) * 1.15)
	pset.scale = Vector2(sc, sc)
	vp.add_child(pset)
	await process_frame
	var anims := pset.get_animations()
	var modes := ["body", "outfit", "top_only"]
	var sheet := Image.create(cell.x * anims.size() * frames, cell.y * modes.size(), false, Image.FORMAT_RGBA8)
	for mi in modes.size():
		var m: String = modes[mi]
		pset.take_off()
		if m == "outfit":
			print("[복장] 입힌 퍼펫 수: ", pset.wear(outfit))
		elif m == "top_only":
			print("[복장] 상의만 입힌 퍼펫 수: ", pset.wear(outfit, DROutfit.TOP))
		for ai in anims.size():
			pset.play(anims[ai])
			var player := _player_of(pset)
			var length := 1.0
			if player != null and player.current_animation != "":
				length = player.current_animation_length
			for fi in frames:
				if player != null:
					player.seek(length * float(fi) / float(frames), true)
				await process_frame
				await RenderingServer.frame_post_draw
				var img := vp.get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(img, Rect2i(Vector2i.ZERO, cell), Vector2i((ai * frames + fi) * cell.x, mi * cell.y))
	var out := _arg("out", "res://puppet_test/_outfit_check.png")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	sheet.save_png(out)
	print("[복장] 저장: ", out, " · 동작 ", anims)
	quit(0)


func _player_of(pset: Node) -> AnimationPlayer:
	var best: AnimationPlayer = null
	for n in pset.find_children("*", "AnimationPlayer", true, false):
		var ap := n as AnimationPlayer
		if ap.is_playing():
			return ap
		best = ap
	return best
