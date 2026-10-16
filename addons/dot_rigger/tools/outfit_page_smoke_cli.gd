extends SceneTree

## ③ 복장 탭(DROutfitPage) 검사(10-16) — 창 없이(--headless): 불러오기 · 미리보기 캐릭터(슬롯 셋 · 차림 4가지 · 동작 재생 · 이음매 따라가기) ·
## 슬롯 바꾸고 저장 → 다시 읽기(다른 키 보존) · 관절 경계 · 붓 칠하기 → parts.json 저장 · 슬롯 메시 다시 자르기 · 되돌리기 · 뚜껑 끔 · 무기.
## 에디터 밖이라 되돌리기는 페이지 자체 스택을 그대로 쓰는 길(에디터 안과 같다).
## 건드리는 파일(outfits/uniform_m36/outfit.json · uniform_m36.parts.json · human_base.parts.json)은 시작할 때 바이트를 읽어 두고
## 끝에(실패해도 — 끝날 때 _finalize · 시간 초과 감시) 그대로 되돌린다. 다른 사람이 같은 사본에서 일할 수 있어 바꿔 두는 시간을 짧게 했다.
##   Godot --headless --path <프로젝트> --script res://addons/dot_rigger/tools/outfit_page_smoke_cli.gd
## 창 모드에서 --shots=res://_out 이면 페이지 화면 · 차림 4가지 · 이음매 그림도 찍는다(--headless 는 렌더가 안 된다). 보조 모니터로:
##   Godot --path <프로젝트> --screen 0 --resolution 1280x720 --script res://addons/dot_rigger/tools/outfit_page_smoke_cli.gd -- --shots=res://_out
## 마지막 줄이 "OUTFIT PAGE SMOKE OK" 면 통과.

const OUTFIT := "res://outfits/uniform_m36/outfit.json"
const UNIFORM_PARTS := "res://source3d/characters/uniform_m36/uniform_m36.parts.json"
const BODY_PARTS := "res://source3d/characters/human_base/human_base.parts.json"
const AIM := "Crouch_Idle+Rifle_Aiming_Idle"
const TIMEOUT_SEC := 240.0

var _fails := PackedStringArray()
var _orig := {}            # 경로 -> PackedByteArray(시작할 때 바이트)
var _shots := ""
var _done := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--shots="):
			_shots = s.substr(8)
	for p in [OUTFIT, UNIFORM_PARTS, BODY_PARTS]:
		_orig[p] = FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else PackedByteArray()
	create_timer(TIMEOUT_SEC).timeout.connect(func():
		if not _done:
			print("  FAIL  시간 초과(%d 초) — 파일을 되돌리고 끝냄" % int(TIMEOUT_SEC))
			_restore()
			print("OUTFIT PAGE SMOKE FAIL 시간 초과")
			quit(1))
	_run.call_deferred()


## 끝날 때 한 번 더(검사 중 스크립트 오류로 _run 이 멈춰도 파일은 되돌린다)
func _finalize() -> void:
	_restore()


func _restore() -> void:
	for p in _orig.keys():
		var want: PackedByteArray = _orig[p]
		if want.is_empty():
			continue
		var now := FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else PackedByteArray()
		if now == want:
			continue
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f != null:
			f.store_buffer(want)
			f.close()


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["OK  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _sum(d: Dictionary) -> int:
	var n := 0
	for v in d.values():
		n += int(v)
	return n


func _joint_offset(path: String, key: String) -> float:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (v is Dictionary):
		return INF
	for c in (v as Dictionary).get("cuts", []):
		if String((c as Dictionary).get("kind", "")) == "joint" and String((c as Dictionary).get("joint", "")) == key:
			return float((c as Dictionary).get("offset", 0.0))
	return INF


func _run() -> void:
	var page := DROutfitPage.new()
	root.add_child(page)
	if _shots != "":
		# 프로젝트 설정(canvas_items 늘이기, 기준 1152×648)이 창 그림을 키워 페이지 아래 · 오른쪽이 잘려 찍혔다 → 그림은 1:1 로
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	page.test_layout(Vector2i(root.size) if _shots != "" else Vector2i(1400, 860))
	await _frames(3)

	print("[1] 불러오기")
	var ok: bool = await page.load_outfit(OUTFIT)
	_check(ok and page._loaded, "불러오기 %s" % OUTFIT)
	if not ok:
		_finish(page)
		return
	_check(page._t_outfit.pos.size() > 1000 and page._t_base.pos.size() > 1000, "칠할 대상: 옷 모델 정점 %d · 기본 몸 정점 %d" % [page._t_outfit.pos.size(), page._t_base.pos.size()])
	_check(page._joints.size() >= 10 and page._joint_opt.item_count == page._joints.size(), "관절 목록 %d개(목 · 손목 · 허리 …)" % page._joints.size())
	_check(page.get_slots().get("Torso") == "top" and page.get_slots().get("Hips") == "bottom" and page.get_slots().get("L_Hand") == "", "슬롯 표(파일 그대로): Torso 상의 · Hips 하의 · 손 기본 몸")
	_check(not page._dirty_doc and page._json_path == OUTFIT, "저장 안 한 고침 없음 · 고치는 파일 %s" % page._json_path)
	_check(page._pm_mi.mesh != null and page._pm_mi.mesh.get_surface_count() == 1, "칠하기 화면(T-포즈 부위 색) 메시")

	print("[2] 미리보기 캐릭터 · 차림 4가지")
	var ch := page.preview_character()
	_check(ch != null and ch.get_slot_node("top").mesh != null and ch.get_slot_node("bottom").mesh != null and ch.get_slot_node("base").mesh != null,
		"미리보기 캐릭터 슬롯 셋에 메시(상의 · 하의 · 머리손)")
	var ro: DRSlotMesh.Result = page.split_results()["outfit"]
	var rb: DRSlotMesh.Result = page.split_results()["body"]
	_check(ro != null and rb != null and ro.tri_counts.has("top") and ro.tri_counts.has("bottom"),
		"옷 자르기: 상의 삼각형 %d(뚜껑 %d) · 하의 %d(뚜껑 %d) · 못 막은 경계 %d · %.0f ms / 기본 몸: 머리손 %d · 상의 %d · 하의 %d" % [
		int(ro.tri_counts.get("top", 0)), int(ro.cap_tris.get("top", 0)), int(ro.tri_counts.get("bottom", 0)), int(ro.cap_tris.get("bottom", 0)), ro.cap_open, ro.ms,
		int(rb.tri_counts.get("base", 0)), int(rb.tri_counts.get("top", 0)), int(rb.tri_counts.get("bottom", 0))])
	# 게임(DRCharacter3D.wear)과 같은 자르기인가 — 같은 파일 · 같은 표면 삼각형 수가 같아야 한다
	var game := DRCharacter3D.load_entry(DRCharacter3D._read_json(OUTFIT)["model"], DRCharacter3D._read_json(OUTFIT)["slots"])
	var gr: DRSlotMesh.Result = game.get("split", null)
	_check(gr != null and gr.tri_counts == ro.tri_counts and gr.vert_counts == ro.vert_counts, "게임 쪽 나누기(DRCharacter3D.load_entry)와 같은 결과(정점 · 삼각형 슬롯별)")
	var om: Dictionary = page._outfit_split["meshes"]
	var bm: Dictionary = page._body_split["meshes"]
	var look_ok := true
	var look_txt := PackedStringArray()
	for look in ["full", "top", "bottom", "naked"]:
		page.set_look(look)
		var t_ok: bool = ch.get_slot_node("top").mesh == (om["top"] if look in ["full", "top"] else bm["top"])
		var b_ok: bool = ch.get_slot_node("bottom").mesh == (om["bottom"] if look in ["full", "bottom"] else bm["bottom"])
		var h_ok: bool = ch.get_slot_node("base").mesh == bm["base"]
		look_ok = look_ok and t_ok and b_ok and h_ok
		look_txt.append("%s(상의 %s · 하의 %s)" % [look, "옷" if ch.get_slot_node("top").mesh == om["top"] else "몸", "옷" if ch.get_slot_node("bottom").mesh == om["bottom"] else "몸"])
	_check(look_ok, "차림 4가지: " + ", ".join(look_txt) + " · 머리 · 손은 늘 기본 몸")
	page.set_look("full")

	print("[3] 동작 · 이음매 따라가기")
	var ap := ch.get_animation_player()
	_check(page._motion_ob.item_count >= 20 and page._cur_motion == AIM, "동작 목록 %d개 · 기본 동작 %s" % [page._motion_ob.item_count, page._cur_motion])
	page._set_playing(true)
	var p0 := ap.current_animation_position
	await _frames(24)
	_check(ap.current_animation == AIM and absf(ap.current_animation_position - p0) > 0.01, "재생됨(초당 12번): %.3f → %.3f s" % [p0, ap.current_animation_position])
	page.pose_at("Firing_Rifle", 0.5)
	var ln := ap.get_animation("Firing_Rifle").length
	_check(ap.current_animation == "Firing_Rifle" and absf(ap.current_animation_position - ln * 0.5) < 0.02 and not page._playing,
		"멈추고 한 순간: Firing_Rifle 50 %% = %.3f / %.3f s" % [ap.current_animation_position, ln])
	page.pose_at(AIM, 0.3)
	page.set_focus("LeftHand")
	await _frames(3)
	var c := Vector2(page._pv_vp.size) * 0.5
	var at := page._dots.world_to_canvas(page._focus_point())
	_check(page._dots.dot_px == 1 and absf(page._dots.px_per_m - 1100.0) < 1.0 and at.distance_to(c) < 1.0,
		"왼 손목 이음매 보기: 도트 1 px · 1 m = %.0f px · 손목 자르는 자리가 화면 가운데에서 %.2f px" % [page._dots.px_per_m, at.distance_to(c)])
	page.set_focus("body")

	if _shots != "":
		await _take_shots(page)

	print("[4] 슬롯 바꾸고 저장 → 다시 읽기")
	var before_doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUTFIT))
	var top0 := int(ro.tri_counts.get("top", 0))
	var bot0 := int(ro.tri_counts.get("bottom", 0))
	page.set_slot("Hips", "top")
	page.refresh_preview_now()
	var r1: DRSlotMesh.Result = page.split_results()["outfit"]
	_check(page._dirty_doc and int(r1.tri_counts.get("top", 0)) > top0 and int(r1.tri_counts.get("bottom", 0)) < bot0,
		"Hips → 상의: 미리보기만 바로(상의 삼각형 %d → %d · 하의 %d → %d) · 저장 안 한 고침 표시" % [top0, int(r1.tri_counts.get("top", 0)), bot0, int(r1.tri_counts.get("bottom", 0))])
	_check(page._slot_warn.text.contains("Hips"), "기본 표와 다름 알림: %s" % page._slot_warn.text.left(40))
	_check(page.save_outfit() and not page._dirty_doc, "저장")
	var txt := FileAccess.get_file_as_string(OUTFIT)
	var d: Dictionary = JSON.parse_string(txt)
	_check(String((d.get("slots", {}) as Dictionary).get("Hips", "")) == "top" and String(d.get("model", "")) == String(before_doc.get("model", "")) and String(d.get("id", "")) == "uniform_m36",
		"파일: slots.Hips = top · model · id 그대로")
	_check(d.has("sets") and d.has("sets_json") and JSON.stringify(d["sets"]) == JSON.stringify(before_doc["sets"]) and String(d["sets_json"]) == String(before_doc["sets_json"]),
		"다른 키(2D 시험장의 sets · sets_json) 그대로")
	_check(txt.contains("\t\t\t\t\t\t104,") and not txt.contains("104.0"), "정수는 정수 그대로(crop 104 — 104.0 으로 안 바뀜)")
	var ok2: bool = await page.load_outfit(OUTFIT)
	_check(ok2 and page.get_slots().get("Hips") == "top", "다시 읽기: Hips = 상의")
	page.set_slot("Hips", "bottom")
	page.save_outfit()
	var same := FileAccess.get_file_as_bytes(OUTFIT) == (_orig[OUTFIT] as PackedByteArray)
	_check(same, "Hips 를 되돌려 저장하면 원래 파일과 바이트까지 같음(저장 형식이 원래 그대로)")
	ch = page.preview_character()

	print("[5] 관절 경계(왼 손목) → parts.json · 슬롯 메시 다시 자르기 · 되돌리기")
	page.refresh_preview_now()
	var ra: DRSlotMesh.Result = page.split_results()["outfit"]
	var rba: DRSlotMesh.Result = page.split_results()["body"]
	var off0 := _joint_offset(UNIFORM_PARTS, "L_Hand")
	_check(page.set_joint_cut("L_Hand", true, 0.02, 0.0), "왼 손목 경계 %.1f cm → +2.0 cm(손 쪽)" % (off0 * 100.0))
	_check(absf(_joint_offset(UNIFORM_PARTS, "L_Hand") - 0.02) < 1e-6 and absf(_joint_offset(BODY_PARTS, "L_Hand") - 0.02) < 1e-6,
		"두 parts.json 에 바로 저장(옷 %.3f · 기본 몸 %.3f m)" % [_joint_offset(UNIFORM_PARTS, "L_Hand"), _joint_offset(BODY_PARTS, "L_Hand")])
	page.refresh_preview_now()
	var rc: DRSlotMesh.Result = page.split_results()["outfit"]
	var rbc: DRSlotMesh.Result = page.split_results()["body"]
	_check(rc != ra and int(rc.tri_counts.get("top", 0)) > int(ra.tri_counts.get("top", 0)) and int(rbc.tri_counts.get("base", 0)) < int(rba.tri_counts.get("base", 0)),
		"다시 잘림: 옷 상의 삼각형 %d → %d(소매가 손 쪽으로 길어짐) · 기본 몸 머리손 %d → %d" % [int(ra.tri_counts.get("top", 0)), int(rc.tri_counts.get("top", 0)),
		int(rba.tri_counts.get("base", 0)), int(rbc.tri_counts.get("base", 0))])
	_check(ch.get_slot_node("top").mesh == (page._outfit_split["meshes"] as Dictionary)["top"], "미리보기 캐릭터에 새 메시가 끼워짐")
	page.undo()
	page.refresh_preview_now()
	var rd: DRSlotMesh.Result = page.split_results()["outfit"]
	_check(absf(_joint_offset(UNIFORM_PARTS, "L_Hand") - off0) < 1e-6 and int(rd.tri_counts.get("top", 0)) == int(ra.tri_counts.get("top", 0)),
		"되돌리기: 경계 %.1f cm · 상의 삼각형 %d" % [_joint_offset(UNIFORM_PARTS, "L_Hand") * 100.0, int(rd.tri_counts.get("top", 0))])
	# 팔꿈치(같은 슬롯 안)를 바꾸면 슬롯 나뉨이 안 바뀌어 다시 자르지 않는다
	page.set_joint_cut("L_Forearm", true, 0.03, 0.0)
	page.refresh_preview_now()
	_check(page.split_results()["outfit"] == rd, "팔꿈치(같은 슬롯 안)를 바꾸면 다시 자르지 않음(needed_cuts 열쇠)")
	page.undo()

	print("[6] 붓 칠하기(둘 다) → 다시 자르기 · 되돌리기")
	# 관절 경계(kind = joint)는 뼈 방향으로 끝없는 기둥 안의 두 부위를 평면으로 다시 나눈다 — 허리 기둥 안의 골반 · 몸통을 붓으로 바꿔도
	# 허리 평면이 도로 나눈다. 그래서 시험은 어느 관절 기둥에도 안 걸리는 칠하기: 왼 허벅지 앞(하의)을 L_UpperArm(상의)으로
	var t: DROutfitPage.PaintTarget = page._t_outfit
	var best := -1
	var best_z := -INF
	for i in t.pos.size():
		if t.part_of(i) == "L_Thigh" and t.pos[i].y > 0.55 and t.pos[i].y < 0.75 and t.pos[i].z > best_z and t.nrm[i].z > 0.5:
			best_z = t.pos[i].z
			best = i
	var top_b := int(page.split_results()["outfit"].tri_counts.get("top", 0))
	var bot_b := int(page.split_results()["outfit"].tri_counts.get("bottom", 0))
	page._stroke = {}
	var n := page.paint_at(t.pos[best], "L_UpperArm", 0.05) if best >= 0 else 0
	page.end_stroke()
	var pj: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(UNIFORM_PARTS))
	_check(n > 0 and (pj.get("points", []) as Array).size() > 0, "붓(5 cm, 허벅지 앞 → L_UpperArm) %d곳 → parts.json 점 %d개(옷) · 기본 몸 %d개" % [n, (pj.get("points", []) as Array).size(), page._t_base.ov.size()])
	page.refresh_preview_now()
	var top_a := int(page.split_results()["outfit"].tri_counts.get("top", 0))
	var bot_a := int(page.split_results()["outfit"].tri_counts.get("bottom", 0))
	_check(top_a > top_b and bot_a < bot_b, "다시 잘림: 상의 삼각형 %d → %d · 하의 %d → %d" % [top_b, top_a, bot_b, bot_a])
	page.undo()
	page.refresh_preview_now()
	_check(page._t_outfit.ov.size() == 0 and page._t_base.ov.size() == 0 and int(page.split_results()["outfit"].tri_counts.get("top", 0)) == top_b, "되돌리기: 칠한 점 0")

	print("[7] 뚜껑 끔 · 무기")
	page._caps_cb.button_pressed = false
	var rn: DRSlotMesh.Result = page.split_results()["outfit"]
	_check(_sum(rn.cap_tris) == 0 and rn.tri_counts["top"] < top_b, "뚜껑 끔: 뚜껑 삼각형 0(상의 %d)" % int(rn.tri_counts["top"]))
	page._caps_cb.button_pressed = true
	_check(_sum(page.split_results()["outfit"].cap_tris) > 0, "뚜껑 켬: 뚜껑 삼각형 %d" % _sum(page.split_results()["outfit"].cap_tris))
	if load(DROutfitPage.WEAPON_UNIT) != null:     # 기본형 군인 프리팹(무기 파일이 없는 새 클론이면 건너뜀)
		page._weapon_cb.button_pressed = true
		var w := ch.get_weapon_node()
		_check(w != null and w.get_parent() is BoneAttachment3D and ch.get_support_marker() != null and ch.get_left_arm_ik() != null,
			"무기 들기 = 기본형 군인의 소켓 장비(%s · 왼손 표지 · 왼팔 IK)" % (String(w.name) if w != null else "-"))
		var rep := ch.support_report()
		_check(not rep.is_empty() and float(rep["ik"]) < 0.01, "왼손이 표지에 붙음(%.2f cm, 동작 그대로면 %.2f cm)" % [float(rep.get("ik", -1.0)) * 100.0, float(rep.get("raw", -1.0)) * 100.0])
		page._weapon_cb.button_pressed = false
		_check(ch.get_weapon_node() == null and ch.get_left_arm_ik() == null and ch.get_sockets().is_empty(), "무기 내림(소켓 · IK 같이 빠짐)")

	_finish(page)


func _finish(page: DROutfitPage) -> void:
	if page != null and is_instance_valid(page):
		page.queue_free()
	await _frames(2)
	_restore()
	var back := true
	for p in _orig.keys():
		if FileAccess.get_file_as_bytes(p) != (_orig[p] as PackedByteArray):
			back = false
	_check(back, "건드린 파일 3개가 시작할 때와 바이트까지 같음")
	_done = true
	if _fails.is_empty():
		print("OUTFIT PAGE SMOKE OK")
	else:
		print("OUTFIT PAGE SMOKE FAIL ", ", ".join(_fails))
	quit(0 if _fails.is_empty() else 1)


# ---------------------------------------------------------------- 그림(창 모드)

func _grab_root() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()


func _grab_pv(page: DROutfitPage) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return page._pv_vp.get_texture().get_image()


func _save(img: Image, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shots))
	var p := ProjectSettings.globalize_path(_shots.path_join(name))
	img.save_png(p)
	print("        → ", _shots.path_join(name))


func _take_shots(page: DROutfitPage) -> void:
	if DisplayServer.get_name() == "headless":
		print("  (그림: --headless 라 건너뜀 — 창 모드로)")
		return
	print("[그림] ", _shots)
	page.pose_at(AIM, 0.3)
	page.set_turn(55.0)
	page.set_look("full")
	page.set_focus("body")
	page._joint_opt.select(1)                 # 왼 손목 — 노란 판
	page._on_joint_selected(true)             # 미리보기도 왼 손목으로
	await _frames(4)
	_save(await _grab_root(), "outfit_page_full.png")
	page.set_focus("body")
	var cells: Array = []
	for look in ["full", "top", "bottom", "naked"]:
		page.set_look(look)
		await _frames(2)
		var img: Image = await _grab_pv(page)
		_save(img, "outfit_page_look_%s.png" % look)
		cells.append(img)
	_save(_row(cells), "outfit_page_looks.png")
	page.set_look("full")
	var seams: Array = []
	for f in ["LeftHand", "RightHand", "neck", "waist"]:
		page.set_focus(f)
		await _frames(3)
		var img2: Image = await _grab_pv(page)
		_save(img2, "outfit_page_seam_%s.png" % f)
		seams.append(img2)
	_save(_row(seams), "outfit_page_seams.png")
	# 같은 왼 손목 · 같은 순간을 내복 ↔ 군복으로(이음매 비교)
	page.set_focus("LeftHand")
	var cmp: Array = []
	for look in ["naked", "full"]:
		page.set_look(look)
		await _frames(2)
		cmp.append(await _grab_pv(page))
	_save(_row(cmp), "outfit_page_lwrist_naked_vs_full.png")
	page.set_look("full")
	page.set_focus("body")
	await _frames(2)


func _row(cells: Array) -> Image:
	var w := 0
	var h := 0
	for c in cells:
		w += (c as Image).get_width()
		h = maxi(h, (c as Image).get_height())
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0.1, 0.1, 0.1))
	var x := 0
	for c in cells:
		var im := c as Image
		if im.get_format() != Image.FORMAT_RGBA8:
			im.convert(Image.FORMAT_RGBA8)
		out.blit_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i(x, 0))
		x += im.get_width()
	return out
