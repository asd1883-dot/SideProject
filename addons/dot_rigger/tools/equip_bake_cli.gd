extends SceneTree

## 장비(무기) 굽기 CLI — 3D 무기 모델을 퍼펫의 모든 세트에 맞춰 2D 장비로 굽는다.
##
##   godot --path . --resolution 900x700 --script res://addons/dot_rigger/tools/equip_bake_cli.gd -- \
##       --preset=res://UAL1_preset.tres --sets=res://puppet/sets.json \
##       --weapon=res://source3d/weapons/kar98k/Kar98_obj.obj --id=kar98k \
##       --grip_node=trigger --grip_offset=0,-0.01,-0.05 --hide=bullets,bullet --z_after=Torso --shots
##
##   --preset       캐릭터 프리셋(.tres) — 모델 · 추가 동작 폴더 · 도트화 값(명암 단계 등)을 세트를 구울 때와 같게
##   --model / --extra_anims   프리셋 없이 직접 줄 때
##   --part=R_Hand  붙일 손   --support=L_Hand  받치는 손(자동 그립의 총열 방향 = 붙일 손 → 받치는 손)
##   --forward=0,0,1   무기 모델에서 총구 쪽 축
##   --grip_node    무기에서 손이 잡는 자리의 기준 노드(없으면 경계 상자에서 어림) · --grip_offset 그 점에서 더 옮길 양(모델 공간, m)
##   --grip_from    자동 그립을 잡을 세트 이름(기본: 레스트 동작 이름에 rifle·aim 이 든 첫 세트, 없으면 첫 세트)
##   --hide=a,b     숨길 무기 하위 노드   --z_after=Torso  그리기 순서("이 파트 바로 앞")
##   --out=res://equip   --shots  확인용 그림(3D 합성 · 2D 장착)을 res://puppet_test/ 에 저장
## 렌더가 필요하므로 --headless 로는 못 돌린다.

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


func _vec3(s: String, def: Vector3) -> Vector3:
	var p := s.split(",")
	if p.size() != 3:
		return def
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _run() -> void:
	var opts := DRBaker.Options.new()
	var model_path := _arg("model", "res://models/UAL1.glb")
	var preset_path := _arg("preset", "")
	if preset_path != "":
		var p := load(preset_path) as DRPreset
		if p == null:
			printerr("프리셋을 열 수 없습니다: ", preset_path); quit(1); return
		if p.model_path != "":
			model_path = p.model_path
		opts.extra_anim_dir = p.extra_anim_dir
		opts.light_bands = p.light_bands
		opts.ambient = p.ambient
		opts.alpha_threshold = p.alpha_threshold
		opts.color_levels = p.color_levels
		opts.composites = p.composites.duplicate(true)
		opts.composite_upper_parts = p.composite_upper_parts
	model_path = _arg("model", model_path)
	if _args.has("extra_anims"):
		opts.extra_anim_dir = _arg("extra_anims")
	var scene := load(model_path) as PackedScene
	if scene == null:
		printerr("모델을 열 수 없습니다: ", model_path); quit(1); return
	var baker := DRBaker.new()
	if not baker.setup(root, scene, DRPartProfile.humanoid(), opts):
		printerr("setup 실패"); quit(1); return
	await process_frame

	var weapon_path := _arg("weapon", "")
	var ws := load(weapon_path) as PackedScene
	if ws == null:
		printerr("무기 모델을 씬으로 열 수 없습니다(OBJ 는 가져오기 형식을 Scene 으로): ", weapon_path); quit(1); return
	var eb := DREquipBaker.new()
	eb.baker = baker
	eb.sets_json = _arg("sets", "res://puppet/sets.json")
	eb.weapon_scene = ws
	eb.weapon_path = weapon_path
	eb.id = _arg("id", weapon_path.get_file().get_basename())
	eb.slot = _arg("slot", "weapon")
	eb.attach_part = _arg("part", "R_Hand")
	eb.z_after_part = _arg("z_after", "")
	eb.out_dir = _arg("out", "res://equip")
	if _args.has("hide"):
		eb.hidden_nodes = PackedStringArray(_arg("hide").split(",", false))

	# 자동 그립 — 소총을 든 세트의 레스트 자세에서
	var sets := eb.read_sets()
	if sets.is_empty():
		printerr("세트를 읽지 못했습니다: ", eb.sets_json); quit(1); return
	var grip_set: Dictionary = sets[0]
	var want := _arg("grip_from", "")
	for s in sets:
		var sd: Dictionary = s
		var rest := String((sd["rig"] as Dictionary).get("view", {}).get("rest_anim", "")).to_lower()
		if (want != "" and String(sd["name"]) == want) or (want == "" and (rest.contains("rifle") or rest.contains("aim"))):
			grip_set = sd
			break
	if not eb.apply_set(grip_set):
		printerr("그립을 잡을 세트를 세울 수 없습니다: ", ", ".join(eb.warnings)); quit(1); return
	var forward := _vec3(_arg("forward", "0,0,1"), Vector3(0, 0, 1))
	var gp := eb.grip_point_guess(_arg("grip_node", ""), forward) + _vec3(_arg("grip_offset", "0,0,0"), Vector3.ZERO)
	if not eb.auto_grip(_arg("support", "L_Hand"), forward, gp):
		printerr("자동 그립 실패: ", ", ".join(eb.warnings)); quit(1); return
	print("[장비] 그립 기준 세트 = %s · 무기 노드 %s · 그립 점 %s" % [grip_set["name"], str(eb.weapon_node_names()), str(gp)])

	var shots := _args.has("shots")
	if shots:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://puppet_test"))
		for s in sets:
			var sd: Dictionary = s
			if eb.apply_set(sd):
				await RenderingServer.frame_post_draw
				var img3: Image = await eb.render_with_character()
				img3.save_png("res://puppet_test/_equip3d_%s.png" % String(sd["dir"]).validate_filename())

	var res: Dictionary = await eb.run()
	for w in eb.warnings:
		print("[장비] ⚠ ", w)
	print("[장비] 결과: ", JSON.stringify(res))
	if not bool(res.get("ok", false)):
		quit(1); return

	if shots:
		var vp := SubViewport.new()
		vp.size = Vector2i(560, 520)
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var bg := ColorRect.new()
		bg.color = Color(0.36, 0.42, 0.36)
		bg.size = Vector2(vp.size)
		vp.add_child(bg)
		var soldier := DRPuppetSet.new()
		soldier.sets_json = eb.sets_json
		soldier.position = Vector2(280, 470)
		soldier.scale = Vector2(1.4, 1.4)
		vp.add_child(soldier)
		await process_frame
		var es := DREquipSet.load_json(String(res["json"]))
		print("[장비] 장착된 세트 수: ", soldier.equip(es))
		for an in soldier.get_animations():
			soldier.play(an)
			for i in 4:
				await process_frame
			await RenderingServer.frame_post_draw
			vp.get_texture().get_image().save_png("res://puppet_test/_equip2d_%s.png" % String(an).validate_filename())
	baker.cleanup()
	quit(0)
