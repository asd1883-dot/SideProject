extends SceneTree

## 복장 굽기 창(DROutfitWindow) 스모크 — 창을 띄워 불러오기 → 2D 미리보기(입힘) → 3D 고르기 · 칠하기 → 다시 자르기
## → 되돌리기 → 슬롯 바꾸기 · 미리보기 슬롯 끄기 → 굽기 → outfit.json 다시 읽기.
##
##   godot --path . --resolution 1400x860 --script res://addons/dot_rigger/tools/outfit_window_smoke_cli.gd -- \
##       --preset=res://human.tres --sets=res://puppet/sets.json --model=res://source3d/characters/uniform_m36/uniform_m36.glb
##
## 필요: 기본 몸으로 구운 sets.json · 같은 뼈대에 붙인 옷 모델(.glb)

const OUT := "res://puppet_test/outfit_win"

var _fail := 0
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


func _check(ok: bool, msg: String) -> void:
	print("  %s  %s" % ["OK  " if ok else "FAIL", msg])
	if not ok:
		_fail += 1


func _wait_idle(win, cap: int = 3000) -> void:
	var n := 0
	await process_frame
	while (win._busy or win._pv_dirty or win._resplit_dirty) and n < cap:
		await process_frame
		n += 1


func _art(pup: DRPuppet, part: String) -> Sprite2D:
	var b := pup.get_bone(part)
	return b.get_node_or_null("stretch/art") as Sprite2D if b != null else null


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://puppet_test"))
	var model := _arg("model", "res://source3d/characters/uniform_m36/uniform_m36.glb")
	var parts_json := DRPartOverrides.path_for(model)
	var had_paint := FileAccess.file_exists(parts_json)
	var keep_paint := FileAccess.get_file_as_string(parts_json) if had_paint else ""
	var win := DROutfitWindow.new()
	root.add_child(win)
	win.popup_centered(Vector2i(1340, 800))
	await process_frame

	print("[1] 창 구성")
	_check(win._bake_btn.disabled, "불러오기 전엔 굽기 잠김")
	_check(win._slot_opts.size() == 15 and win._part_btns.size() == 16, "슬롯 칸 15 · 칠할 부위 단추 16(지우개 포함)")
	_check(win.size.y <= 880 and win.size.x <= 1420, "창 크기 %s (줄바꿈 라벨이 창을 늘리지 않음)" % str(win.size))

	print("[2] 불러오기")
	win._preset_edit.text = _arg("preset", "res://human.tres")
	win._sets_edit.text = _arg("sets", "res://puppet/sets.json")
	win._model_edit.text = model
	win._id_edit.text = "outfit_smoke"
	win._out_edit.text = OUT
	win._on_load()
	await _wait_idle(win)
	_check(win._loaded and not win._bake_btn.disabled, "불러옴: %s" % win._load_status.text.split("\n")[0])
	if not win._loaded:
		printerr("불러오기 실패 — 중단"); quit(1); return
	var autos := {}
	for p in win._pm_auto:
		autos[p] = int(autos.get(p, 0)) + 1
	_check(win._pm_pos.size() > 1000 and autos.has("Torso") and autos.has("Hips") and autos.has("L_Thigh"), "3D 칠하기 메시 정점 %d · 부위 %d종 %s" % [win._pm_pos.size(), autos.size(), str(autos)])
	_check(win._pm_mi.mesh != null and win._tri_a.size() > 1000, "부위 색 메시 · 고르기 삼각형 %d" % win._tri_a.size())

	print("[3] 2D 미리보기 — 기본 몸 퍼펫에 입힘")
	var sname := String((win.ob.sets[0] as Dictionary)["name"])
	_check(win._baked.has(sname) and (win._baked[sname] as Dictionary).size() == 12, "세트 %s 임시로 구움: 파트 %d장" % [sname, (win._baked.get(sname, {}) as Dictionary).size()])
	var pup: DRPuppet = win._soldier.get_puppet()
	_check(pup != null and pup._worn.has("Torso") and pup._worn.has("L_Foot") and not pup._worn.has("Head") and not pup._worn.has("L_Hand"), "몸통 · 발은 옷 그림 · 머리 · 손은 몸 그대로 (바꾼 파트 %d)" % (pup._worn.size() if pup != null else -1))
	await process_frame
	await RenderingServer.frame_post_draw
	win._vp2.get_texture().get_image().save_png("res://puppet_test/_outfitwin_2d.png")

	print("[4] 3D 고르기 · 칠하기 → 저장 → 다시 자르기")
	# 골반 조각의 정점 하나를 화면으로 옮겨 광선으로 다시 고른다
	var hips_i := win._pm_auto.find("Hips")
	var target: Vector3 = win._pm_pos[hips_i]
	var tris_before := int(win.baker.split.tri_counts.get("Torso", 0))
	var vp_pos: Vector2 = win._cam3.unproject_position(target)
	var h: Dictionary = win.pick(vp_pos)
	_check(bool(h.get("hit", false)), "화면 %s 에서 모델 표면을 맞힘" % str(vp_pos))
	win._painting = true
	win._stroke = {}
	var n := win.paint_at(target, "Torso", 0.06)
	win.end_stroke()
	_check(n > 0 and win._ov.size() == n, "골반 쪽 정점 %d곳을 Torso 로 칠함" % n)
	_check(FileAccess.file_exists(parts_json), "칠하기 저장: %s" % parts_json)
	var back := DRPartOverrides.load_for(model)
	_check(back.size() == n, "다시 읽어도 %d곳" % back.size())
	await _wait_idle(win)
	var tris_after := int(win.baker.split.tri_counts.get("Torso", 0))
	_check(tris_after > tris_before, "다시 자른 몸통 조각 삼각형 %d → %d" % [tris_before, tris_after])
	await process_frame
	await RenderingServer.frame_post_draw
	win._vp3.get_texture().get_image().save_png("res://puppet_test/_outfitwin_3d.png")

	print("[5] 되돌리기")
	win._on_undo()
	_check(win._ov.size() == 0, "칠한 것 되돌림(남은 %d곳)" % win._ov.size())
	await _wait_idle(win)
	_check(int(win.baker.split.tri_counts.get("Torso", 0)) == tris_before, "몸통 조각 삼각형 원래대로 %d" % int(win.baker.split.tri_counts.get("Torso", 0)))

	print("[6] 슬롯 · 미리보기 슬롯 끄기")
	var hips_opt: OptionButton = win._slot_opts["Hips"]
	hips_opt.select(0)
	hips_opt.item_selected.emit(0)    # Hips → 상의
	await _wait_idle(win)
	_check(win._outfit != null and win._outfit.slot_parts("top").has("Hips"), "Hips 를 상의로: 상의 = %s" % str(win._outfit.slot_parts("top") if win._outfit != null else []))
	(win._wear_cb["bottom"] as CheckBox).button_pressed = false
	(win._wear_cb["shoes"] as CheckBox).button_pressed = false
	await process_frame
	pup = win._soldier.get_puppet()
	_check(pup._worn.has("Torso") and pup._worn.has("Hips") and not pup._worn.has("L_Thigh") and not pup._worn.has("L_Foot"), "상의만 입힘 — 다리 · 발은 몸 그대로 (바꾼 파트 %s)" % str(pup._worn.keys()))
	(win._wear_cb["bottom"] as CheckBox).button_pressed = true
	(win._wear_cb["shoes"] as CheckBox).button_pressed = true

	print("[7] 굽기 → outfit.json")
	win._on_bake()
	await _wait_idle(win)
	var jp := OUT.path_join("outfit_smoke").path_join("outfit.json")
	_check(FileAccess.file_exists(jp), "굽기 결과 %s" % jp)
	var o := DROutfit.load_json(jp)
	_check(o != null and o.sets.has(sname) and (o.sets[sname] as Dictionary).size() == 12, "다시 읽음: 세트 %s 파트 %d" % [sname, (o.sets.get(sname, {}) as Dictionary).size() if o != null else -1])
	_check(o != null and String(o.slots.get("Hips", "")) == "top", "슬롯이 파일에 남음 (Hips = %s)" % (String(o.slots.get("Hips", "")) if o != null else "?"))
	root.get_texture().get_image().save_png("res://puppet_test/_outfitwin_layout.png")

	# 칠하기 파일 원래대로
	if had_paint:
		var f := FileAccess.open(parts_json, FileAccess.WRITE)
		f.store_string(keep_paint)
		f.close()
	elif FileAccess.file_exists(parts_json):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(parts_json))
	win.queue_free()
	await process_frame
	print("복장 굽기 창 검사 %s (실패 %d)" % ["전부 통과" if _fail == 0 else "실패 있음", _fail])
	quit(1 if _fail > 0 else 0)
