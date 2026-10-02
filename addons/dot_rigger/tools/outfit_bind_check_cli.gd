extends SceneTree

## 복장 굽기 창의 `뼈대에 붙이기`(Blender 를 뒤에서 돌림) 확인 — 버튼을 누른 것처럼 돌리고 끝날 때까지 기다려 결과를 본다.
##   godot --path . --resolution 1400x860 --script res://addons/dot_rigger/tools/outfit_bind_check_cli.gd -- \
##       --raw=C:/.../pipeline/comfy/uniform_m36_80eaf512.glb --id=bind_smoke
## 결과: res://source3d/characters/<id>/<id>.glb (+ .import 의 뼈 이름표). 에디터 밖이라 가져오기 · 불러오기는 안 한다.

var _args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			s = s.substr(2)
		var eq := s.find("=")
		if eq >= 0:
			_args[s.substr(0, eq)] = s.substr(eq + 1)
	_run.call_deferred()


func _run() -> void:
	var win := DROutfitWindow.new()
	root.add_child(win)
	win.popup_centered(Vector2i(1340, 800))
	await process_frame
	win._raw_edit.text = String(_args.get("raw", ""))
	win._id_edit.text = String(_args.get("id", "bind_smoke"))
	win._smooth_spin.value = 12
	win._on_bind()
	print("[붙이기] 시작: ", win._bind_status.text)
	var n := 0
	while win._bind_thread != null and n < 20000:
		await process_frame
		n += 1
	for i in 5:
		await process_frame
	print("[붙이기] 결과: ", win._bind_status.text.replace("\n", " | "))
	var out := "res://source3d/characters/%s/%s.glb" % [win._id_edit.text, win._id_edit.text]
	var ok := FileAccess.file_exists(out) and FileAccess.file_exists(out + ".import") and FileAccess.get_file_as_string(out + ".import").contains("retarget/bone_map")
	print("[붙이기] 파일 %s · 뼈 이름표 %s" % [out, "있음" if ok else "없음"])
	print("[붙이기] 옷 모델 칸: ", win._model_edit.text)
	win.queue_free()
	await process_frame
	quit(0 if ok else 1)
