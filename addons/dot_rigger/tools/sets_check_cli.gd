extends SceneTree

## 리깅 애니메이션 세트 베이크 검사.
## 세트 2개(서기: Idle 레스트 · 엎드리기: Crawl_Enter 16% 레스트)를 한 번에 구우면
## <base>/<세트>/ 마다 자기 레스트로 구운 퍼펫이 생기고 sets.json 에 순서대로 적혀야 한다.
##
##   Godot.exe --path <프로젝트> --resolution 400x300 \
##     --script res://addons/dot_rigger/tools/sets_check_cli.gd

const OUT := "res://puppet_test/sets_bake"

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


func _scene_anims(path: String) -> Array:
	var ps := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if ps == null:
		return []
	var pup := ps.instantiate()
	var ap := pup.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var out: Array = Array(ap.get_animation_list()) if ap != null else []
	pup.free()
	out.sort()
	return out


## 씬의 Bone2D 레스트 위치 { 본 이름 -> rest.origin }
func _bone_rests(path: String) -> Dictionary:
	var out := {}
	var ps := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if ps == null:
		return out
	var pup := ps.instantiate()
	var stack: Array = [pup]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is Bone2D:
			out[n.name] = (n as Bone2D).rest.origin
		for c in n.get_children():
			stack.append(c)
	pup.free()
	return out


func _json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}


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

	var sets: Array = [
		{"name": "stand", "rest_anim": "Idle", "rest_time": 0.0, "animations": PackedStringArray(["Idle", "Walk"])},
		# 두 번째 세트만 수동 그리기 순서(오른팔을 오른 허벅지 뒤로) — 세트마다 다른 순서로 구워져야 한다
		{"name": "crawl / test", "rest_anim": "Crawl_Enter", "rest_time": 0.16, "animations": PackedStringArray(["Crawl_Fwd"]),
			"z_auto": false, "z_order": PackedStringArray(["R_UpperArm", "R_Thigh", "Hips", "Torso", "Head"])},
	]
	var sb := DRSetBaker.new()
	sb.baker = baker
	var prog := []
	sb.progress.connect(func(si, sn, sname, stage, cur, total): prog.append([si, sn, sname]))
	var res: Dictionary = await sb.run(sets, OUT, {"fps": 12, "auto_fit": false, "margin": 0, "stretch": true, "smooth": true, "keep_previous": true,
		"outline_px": 1, "outline_color": Color.BLACK, "outline_whole": false})

	print("[1] 결과")
	_check(bool(res.get("ok", false)), "세트 베이크 ok (%s)" % String(res.get("error", "")))
	_check(sb.exporters.size() == 2, "익스포터 %d개" % sb.exporters.size())
	_check(prog.size() > 0 and prog[0][1] == 2 and prog[-1][0] == 1, "진행 신호 세트 번호 %s → %s / %d" % [str(prog[0]) if prog.size() > 0 else "-", str(prog[-1]) if prog.size() > 0 else "-", prog.size()])
	_check(baker.opts.rest_anim == "Idle" and baker.opts.rest_time == 0.0, "끝난 뒤 baker.opts 레스트 원래대로 (%s %.2f)" % [baker.opts.rest_anim, baker.opts.rest_time])

	print("[2] 폴더·씬")
	_check(DRSetBaker.dir_name("crawl / test", 1) == "crawl _ test", "폴더 이름 정리: 'crawl / test' → '%s'" % DRSetBaker.dir_name("crawl / test", 1))
	_check(DRSetBaker.dir_name("  ", 2) == "set3", "빈 이름 → set3 (%s)" % DRSetBaker.dir_name("  ", 2))
	var sa := _scene_anims(OUT.path_join("stand/puppet.tscn"))
	var ca := _scene_anims(OUT.path_join("crawl _ test/puppet.tscn"))
	_check(sa == ["Idle", "Walk"], "stand/puppet.tscn 애니 %s" % str(sa))
	_check(ca == ["Crawl_Fwd"], "crawl _ test/puppet.tscn 애니 %s" % str(ca))

	# 아웃라인: rig.json 에 기록되고, 씬의 art 스프라이트 셰이더 uniform 이 1, 파트 그림은 1px 여유를 두고 잘림
	var rs0 := _json(OUT.path_join("stand/rig.json"))
	var ol_ps := ResourceLoader.load(OUT.path_join("stand/puppet.tscn"), "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var ol_pup := ol_ps.instantiate()
	var ol_art := ol_pup.find_child("art", true, false) as Sprite2D
	var ol_mat := ol_art.material as ShaderMaterial if ol_art != null else null
	_check(int(rs0.get("outline_px", 0)) == 1 and ol_mat != null and int(ol_mat.get_shader_parameter("outline_px")) == 1,
		"아웃라인 1도트 — rig.json outline_px %s · 씬 셰이더 uniform %s" % [rs0.get("outline_px"), ol_mat.get_shader_parameter("outline_px") if ol_mat else "-"])
	var ol_head: Image = Image.load_from_file(ProjectSettings.globalize_path(OUT.path_join("stand/parts/Head.png")))
	var ol_used := ol_head.get_used_rect() if ol_head != null else Rect2i()
	_check(ol_head != null and ol_used.position.x >= 1 and ol_used.position.y >= 1
		and ol_used.end.x <= ol_head.get_width() - 1 and ol_used.end.y <= ol_head.get_height() - 1,
		"파트 그림에 아웃라인용 1px 여유 (Head %s 안 실루엣 %s)" % [str(ol_head.get_size()) if ol_head else "-", str(ol_used)])
	_check(ol_pup.find_child(DRExporter.OUTLINE_NODE, true, false) == null and String(rs0.get("outline_mode", "")) == "parts",
		"파트별 모드 — 밑깔개 없음, rig.json outline_mode %s" % rs0.get("outline_mode", ""))
	ol_pup.free()
	# 전체 실루엣 모드(기본): 파트마다 밑깔개(stretch/outline, z −1, outline_only), 본체 셰이더 outline 0, 파트 그림은 1px 여유
	var exw := DRExporter.new()
	exw.baker = baker
	exw.out_dir = OUT.path_join("stand_whole")
	exw.anim_names = PackedStringArray(["Idle"])
	exw.auto_fit = false
	exw.keep_previous = false
	exw.outline_px = 1
	exw.outline_style = DRExporter.OUTLINE_PIXEL_PERFECT   # 이 굽기는 선 색도 픽셀 퍼펙트(옆 도트 색의 톤)로 — 위 세트 굽기는 카툰
	exw.outline_tone = 0.3
	baker.opts.rest_anim = "Idle"
	baker.opts.rest_time = 0.0
	var resw: Dictionary = await exw.run()
	var wps := ResourceLoader.load(OUT.path_join("stand_whole/puppet.tscn"), "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var wpup := wps.instantiate() if wps != null else null
	var w_art_n := 0
	var w_ol_ok := 0
	var w_ol_mat: ShaderMaterial = null
	var w_art_mat: ShaderMaterial = null
	if wpup != null:
		for wb in wpup.find_children("*", "Bone2D", true, false):
			var wa := wb.get_node_or_null("stretch/art") as Sprite2D
			var wo := wb.get_node_or_null("stretch/" + DRExporter.OUTLINE_NODE) as Sprite2D
			if wa == null:
				continue
			w_art_n += 1
			w_art_mat = wa.material as ShaderMaterial
			if wo != null and wo.texture == wa.texture and wo.position == wa.position and wo.rotation == wa.rotation \
					and wo.z_index == DRExporter.OUTLINE_Z and not wo.z_as_relative:
				w_ol_ok += 1
				w_ol_mat = wo.material as ShaderMaterial
	_check(bool(resw.get("ok", false)) and w_art_n == 15 and w_ol_ok == w_art_n,
		"전체 실루엣 모드 — 파트 %d개 모두 밑깔개(같은 텍스처·자리, z %d) %d개" % [w_art_n, DRExporter.OUTLINE_Z, w_ol_ok])
	_check(w_ol_mat != null and bool(w_ol_mat.get_shader_parameter("outline_only")) and int(w_ol_mat.get_shader_parameter("outline_px")) == 1
		and w_art_mat != null and int(w_art_mat.get_shader_parameter("outline_px")) == 0 and not bool(w_art_mat.get_shader_parameter("outline_only")),
		"밑깔개 머티리얼 outline_only·선 1 · 본체 머티리얼 선 0")
	var whead: Image = Image.load_from_file(ProjectSettings.globalize_path(OUT.path_join("stand_whole/parts/Head.png")))
	var wused := whead.get_used_rect() if whead != null else Rect2i()
	_check(whead != null and wused.position.x >= 1 and wused.position.y >= 1
		and wused.end.x <= whead.get_width() - 1 and wused.end.y <= whead.get_height() - 1,
		"전체 실루엣 모드도 파트 그림에 1px 여유 (Head %s 실루엣 %s)" % [str(whead.get_size()) if whead else "-", str(wused)])
	_check(String(_json(OUT.path_join("stand_whole/rig.json")).get("outline_mode", "")) == "whole", "rig.json outline_mode whole")
	var wj := _json(OUT.path_join("stand_whole/rig.json"))
	_check(w_ol_mat != null and bool(w_ol_mat.get_shader_parameter("outline_tone")) and absf(float(w_ol_mat.get_shader_parameter("outline_tone_strength")) - 0.3) < 0.001
		and String(wj.get("outline_style", "")) == "pixel_perfect" and absf(float(wj.get("outline_tone", 0.0)) - 0.3) < 0.001,
		"선 색 = 픽셀 퍼펙트 — 밑깔개 셰이더 outline_tone 켬·0.30 · rig.json outline_style %s" % wj.get("outline_style", ""))
	_check(ol_mat != null and not bool(ol_mat.get_shader_parameter("outline_tone")) and String(rs0.get("outline_style", "")) == "cartoon",
		"세트 굽기(기본)는 카툰 — outline_tone 꺼짐 · rig.json outline_style %s" % rs0.get("outline_style", ""))
	# 장비도 밑깔개를 받는다
	if wpup != null:
		root.add_child(wpup)
		var hel := DREquipItem.new()
		hel.slot = "helmet"
		hel.part = "Head"
		var hel_img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
		hel_img.fill(Color.YELLOW)
		hel.texture = ImageTexture.create_from_image(hel_img)
		var eq_ok: bool = wpup.equip(hel)
		var eq_ol: Sprite2D = wpup.get_equipped_outline("helmet")
		_check(eq_ok and eq_ol != null and eq_ol.material == w_ol_mat and eq_ol.z_index == DRExporter.OUTLINE_Z
			and eq_ol.get_parent() == wpup.get_equipped("helmet").get_parent(),
			"장비(헬멧)에도 밑깔개 — 머티리얼·z 가 본체 밑깔개와 같음")
		wpup.unequip("helmet")
		_check(wpup.get_equipped_outline("helmet") == null, "장비를 빼면 밑깔개도 빠짐")
		root.remove_child(wpup)
		wpup.free()
	# 루트가 Node2D 인 예전 씬도 DRPuppet 스크립트가 붙어야 한다(스크립트를 CanvasGroup 상속으로 바꾸면 여기서 떨어진다)
	var old_root := Node2D.new()
	old_root.set_script(load("res://addons/dot_rigger/runtime/dr_puppet.gd"))
	_check(old_root.get_script() != null and old_root.has_method("equip"), "예전 씬(루트 Node2D)에도 DRPuppet 스크립트가 붙음")
	old_root.free()

	print("[2-1] 에디터 흐름: 전부 구운 뒤 앞 세트의 rebuild_scene() — 뒷 세트 레스트가 섞이면 안 된다")
	var pre := _bone_rests(OUT.path_join("stand/puppet.tscn"))
	var rb_err: int = sb.exporters[0].rebuild_scene()
	var post := _bone_rests(OUT.path_join("stand/puppet.tscn"))
	var rb_diff := 0
	for k in pre.keys():
		if not post.has(k) or (Vector2(pre[k]) - Vector2(post[k])).length() > 0.01:
			rb_diff += 1
	_check(rb_err == OK and pre.size() > 0 and rb_diff == 0,
		"stand 씬 다시 저장 전후 본 레스트 위치 같음 (본 %d개, 달라진 것 %d개)" % [pre.size(), rb_diff])

	print("[3] 레스트가 세트마다 다르게 들어갔나")
	var rs := _json(OUT.path_join("stand/rig.json"))
	var rc := _json(OUT.path_join("crawl _ test/rig.json"))
	var crawl_len: float = baker.anim_player.get_animation("Crawl_Enter").length
	_check(String(rs.get("view", {}).get("rest_anim", "")) == "Idle", "stand rig.json 레스트 %s" % rs.get("view", {}).get("rest_anim", ""))
	_check(String(rc.get("view", {}).get("rest_anim", "")) == "Crawl_Enter"
		and absf(float(rc.get("view", {}).get("rest_time", -1.0)) - crawl_len * 0.16) < 0.001,
		"crawl rig.json 레스트 %s %.3f초 (기대 Crawl_Enter %.3f)" % [rc.get("view", {}).get("rest_anim", ""), float(rc.get("view", {}).get("rest_time", -1.0)), crawl_len * 0.16])
	# 그리기 순서가 세트마다 따로 들어갔나
	var so: Array = rs.get("layer_order", [])
	var co: Array = rc.get("layer_order", [])
	_check(not bool(rs.get("z_order_manual", true)) and bool(rc.get("z_order_manual", false)),
		"stand 는 자동 순서(z_order_manual %s) · crawl 은 수동(%s)" % [rs.get("z_order_manual"), rc.get("z_order_manual")])
	_check(co.size() == 15 and co.find("R_UpperArm") == 0 and co.find("R_Thigh") == 1 and so != co,
		"crawl layer_order 맨 뒤 = R_UpperArm, 그다음 R_Thigh (15줄) · stand 와 다름 %s" % str(co.slice(0, 3)))
	# 파트 그림이 실제로 다른 자세로 찍혔는지 — 몸통 그림 크기 비교
	var ts := Image.load_from_file(ProjectSettings.globalize_path(OUT.path_join("stand/parts/Torso.png")))
	var tc := Image.load_from_file(ProjectSettings.globalize_path(OUT.path_join("crawl _ test/parts/Torso.png")))
	_check(ts != null and tc != null and ts.get_size() != tc.get_size(),
		"몸통 파트 그림 크기 stand %s ≠ crawl %s" % [str(ts.get_size()) if ts else "-", str(tc.get_size()) if tc else "-"])

	print("[4] sets.json")
	var sj := _json(OUT.path_join("sets.json"))
	var entries: Array = sj.get("sets", [])
	_check(entries.size() == 2, "세트 %d개" % entries.size())
	if entries.size() == 2:
		_check(String(entries[0]["name"]) == "stand" and int(entries[0]["index"]) == 0
			and String(entries[1]["name"]) == "crawl / test" and String(entries[1]["dir"]) == "crawl _ test",
			"순서·이름·폴더 %s / %s" % [entries[0]["name"], entries[1]["dir"]])
		_check(String(entries[1]["scene"]) == "crawl _ test/puppet.tscn" and Array(entries[1]["animations"]) == ["Crawl_Fwd"]
			and absf(float(entries[1]["rest_time"]) - 0.16) < 0.001,
			"crawl 항목: scene %s · 동작 %s · rest_time %.2f" % [entries[1]["scene"], str(entries[1]["animations"]), float(entries[1]["rest_time"])])
		_check(ResourceLoader.exists(OUT.path_join(String(entries[1]["scene"]))), "sets.json 의 scene 경로가 실제 파일")
		_check(bool(entries[1].get("z_order_manual", false)) and Array(entries[1].get("layer_order", [])).slice(0, 2) == ["R_UpperArm", "R_Thigh"]
			and not bool(entries[0].get("z_order_manual", true)),
			"sets.json 에 세트별 순서 기록 (crawl 수동 %s / stand 자동)" % str(Array(entries[1].get("layer_order", [])).slice(0, 2)))

	print("[5] 세트를 빼거나 이름을 바꾸고 다시 구우면 옛 폴더를 치운다")
	_check(Array(res.get("removed_dirs", PackedStringArray())).is_empty(), "첫 굽기는 치울 게 없다")
	# 옛 세트 폴더 하나에는 툴이 만들지 않은 파일을 넣어 둔다 — 그 파일과 폴더는 남아야 한다
	var st_note := OUT.path_join("crawl _ test/memo.txt")
	var st_f := FileAccess.open(st_note, FileAccess.WRITE)
	st_f.store_string("손으로 넣은 파일")
	st_f.close()
	# stand → "Stand"(대소문자만 바꿈: Windows 에서는 같은 폴더) · crawl 세트는 뺌 · 새 세트 하나
	var st_sets: Array = [
		{"name": "Stand", "rest_anim": "Idle", "rest_time": 0.0, "animations": PackedStringArray(["Idle"])},
		{"name": "jog", "rest_anim": "Idle", "rest_time": 0.0, "animations": PackedStringArray(["Jog_Fwd"])},
	]
	var st_res: Dictionary = await sb.run(st_sets, OUT, {"fps": 12, "auto_fit": false, "margin": 0, "stretch": true, "smooth": true,
		"outline_px": 1, "outline_color": Color.BLACK, "outline_whole": false})
	_check(bool(st_res.get("ok", false)), "다시 굽기 ok (%s)" % String(st_res.get("error", "")))
	_check(FileAccess.file_exists(OUT.path_join("Stand/puppet.tscn")) and FileAccess.file_exists(OUT.path_join("Stand/parts/Head.png")),
		"대소문자만 바뀐 세트(stand → Stand)는 방금 구운 게 남는다")
	var st_disk := DirAccess.get_directories_at(ProjectSettings.globalize_path(OUT))
	_check(st_disk.has("Stand") and not st_disk.has("stand"), "디스크의 폴더 이름도 Stand 로 바뀐다 %s" % str(st_disk))
	_check(FileAccess.file_exists(OUT.path_join("jog/puppet.tscn")), "새 세트 jog 있음")
	_check(not FileAccess.file_exists(OUT.path_join("crawl _ test/puppet.tscn")) and not FileAccess.file_exists(OUT.path_join("crawl _ test/rig.json"))
		and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(OUT.path_join("crawl _ test/parts"))),
		"빠진 세트(crawl _ test)의 씬·rig.json·parts 가 지워졌다")
	_check(FileAccess.file_exists(st_note) and Array(st_res.get("left_dirs", PackedStringArray())) == ["crawl _ test"]
		and Array(st_res.get("removed_dirs", PackedStringArray())).is_empty(),
		"손으로 넣은 파일과 그 폴더는 남기고 left_dirs 로 알린다 %s" % str(st_res.get("left_dirs")))
	_check(FileAccess.file_exists(OUT.path_join("stand_whole/puppet.tscn")),
		"sets.json 에 없던 폴더(stand_whole)는 건드리지 않는다")
	# 손으로 넣은 파일을 치우고 한 번 더 — 이번엔 jog 를 빼면 폴더째 없어져야 한다
	var st_res2: Dictionary = await sb.run([st_sets[0]], OUT, {"fps": 12, "auto_fit": false, "margin": 0, "stretch": true, "smooth": true,
		"outline_px": 1, "outline_color": Color.BLACK, "outline_whole": false})
	_check(bool(st_res2.get("ok", false)) and Array(st_res2.get("removed_dirs", PackedStringArray())) == ["jog"]
		and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(OUT.path_join("jog"))),
		"빠진 세트 jog 는 폴더째 없어진다 %s" % str(st_res2.get("removed_dirs")))
	# sets.json 을 손으로 고쳐 바깥을 가리켜도 밖은 지우지 않는다
	var st_guard := DRSetBaker._clean_stale(OUT, PackedStringArray(["..", "../sets_bake", "stand_whole/parts", ""]), PackedStringArray(["Stand"]))
	_check(Array(st_guard["removed"]).is_empty() and Array(st_guard["left"]).is_empty()
		and FileAccess.file_exists(OUT.path_join("stand_whole/parts/Head.png")) and FileAccess.file_exists(OUT.path_join("sets.json")),
		"폴더 이름 하나가 아닌 값(.. · a/b · 빈 값)은 무시한다")

	print("\n" + ("세트 검사 전부 통과" if _fail == 0 else "실패 %d건" % _fail))
	quit(0 if _fail == 0 else 1)
