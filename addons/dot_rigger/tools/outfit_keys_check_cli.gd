extends SceneTree

## 시험장(test/puppet_test.tscn)의 복장 키 확인 — 씬을 띄우고 O(상의) · P(하의) 를 차례로 눌러 화면을 찍는다.
##   찍는 차례: 시작 → O → P → O → P   (복장 1벌이면: 기본 몸 → 상의만 → 상의+하의 → 하의만 → 기본 몸)
##
##   godot --path . --resolution 900x700 --script res://addons/dot_rigger/tools/outfit_keys_check_cli.gd -- --out=res://puppet_test/_outfit_keys.png

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


func _press(key: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = key
		ev.physical_keycode = key
		ev.pressed = down
		Input.parse_input_event(ev)
		await process_frame


func _shot() -> Image:
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _run() -> void:
	var ps := load(String(_args.get("scene", "res://test/puppet_test.tscn"))) as PackedScene
	if ps == null:
		printerr("시험장 씬을 열 수 없습니다"); quit(1); return
	var scene := ps.instantiate()
	root.add_child(scene)
	var shots: Array = [await _shot()]
	for key in [KEY_O, KEY_P, KEY_O, KEY_P]:
		await _press(key)
		shots.append(await _shot())
	var w: int = (shots[0] as Image).get_width()
	var h: int = (shots[0] as Image).get_height()
	var sheet := Image.create(w * shots.size(), h, false, Image.FORMAT_RGBA8)
	for i in shots.size():
		sheet.blit_rect(shots[i], Rect2i(0, 0, w, h), Vector2i(i * w, 0))
	sheet.resize(sheet.get_width() / 2, sheet.get_height() / 2, Image.INTERPOLATE_BILINEAR)
	var out := String(_args.get("out", "res://puppet_test/_outfit_keys.png"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	sheet.save_png(out)
	var lbl := _find_label(scene)
	print("[복장 키] 저장: ", out)
	if lbl != null:
		for line in lbl.text.split("\n"):
			if line.begins_with("복장"):
				print("[복장 키] 마지막 표시: ", line)
	quit(0)


func _find_label(n: Node) -> Label:
	for c in n.get_children():
		if c is Label:
			return c as Label
		var d := _find_label(c)
		if d != null:
			return d
	return null
