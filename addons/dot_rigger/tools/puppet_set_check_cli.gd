extends SceneTree

## 런타임 DRPuppetSet 검사 — 구운 세트 여러 벌을 캐릭터 하나처럼 다루는가.
##  [1] 세트 2개(서기: Idle + Pistol_Aim_Neutral · 앉기: Crouch_Idle)를 굽고 sets.json 으로 불러온다 → 동작 3개가 이름만으로 재생
##  [2] 세트가 바뀌어도 발 자리가 같다(원점 = 두 발 사이의 바닥)
##  [3] 조준: 위를 겨누면 몸통이 위로(−), 한계에서 멈춤, **애니가 멈춰 있어도 각도가 쌓이지 않음**, 끄면 원래 자세로
##  [4] 목표가 등 뒤면 돌아보고, 돌아본 채로도 위는 위
##
##   Godot.exe --path <프로젝트> --resolution 900x700 --script res://addons/dot_rigger/tools/puppet_set_check_cli.gd

const MODEL := "res://models/UAL1.glb"
const OUT := "res://puppet_test/pset_bake"

var _fail := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, msg: String) -> void:
	print(("  OK    " if ok else "  FAIL  ") + msg)
	if not ok:
		_fail += 1


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


## 화면에서 캐릭터 그림의 가장 아래 줄(y)과 그 줄의 가운데(x)
func _ground_contact(vp: SubViewport) -> Vector2:
	var img := vp.get_texture().get_image()
	var used := img.get_used_rect()
	var y := used.end.y - 1
	var xs := 0.0
	var n := 0
	for x in range(used.position.x, used.end.x):
		if img.get_pixel(x, y).a > 0.5:
			xs += float(x)
			n += 1
	return Vector2(xs / float(maxi(n, 1)), float(y))


## 시험용 장비 묶음 — 세트마다 크기가 다른 단색 막대(그림이 세트별로 따로라는 걸 보려고)
func _equip_set(id: String, col: Color, set_names: Array) -> DREquipSet:
	var es := DREquipSet.new()
	es.id = id
	es.slot = "weapon"
	for i in set_names.size():
		var img := Image.create(40 + i * 6, 5, false, Image.FORMAT_RGBA8)
		img.fill(col)
		var it := DREquipItem.new()
		it.slot = "weapon"
		it.part = "R_Hand"
		it.texture = ImageTexture.create_from_image(img)
		it.offset = Vector2(40, 50)
		it.z_after_part = "Torso"
		es.items[String(set_names[i])] = it
	return es


func _run() -> void:
	var opts := DRBaker.Options.new()
	opts.view_size = Vector2i(128, 128)
	opts.yaw = -55.0
	opts.rest_anim = "Idle"
	var baker := DRBaker.new()
	if not baker.setup(root, load(MODEL) as PackedScene, DRPartProfile.humanoid(), opts):
		printerr("setup 실패"); quit(1); return
	await process_frame
	var sb := DRSetBaker.new()
	sb.baker = baker
	var res: Dictionary = await sb.run([
		{"name": "stand", "rest_anim": "Pistol_Aim_Neutral", "rest_time": 0.0, "animations": PackedStringArray(["Idle", "Pistol_Aim_Neutral"])},
		{"name": "crouch", "rest_anim": "Crouch_Idle", "rest_time": 0.1, "animations": PackedStringArray(["Crouch_Idle"])},
	], OUT, {"fps": 12, "auto_fit": true, "margin": 8, "keep_previous": false, "smooth": false, "outline_px": 1})
	baker.cleanup()
	if not bool(res.get("ok", false)):
		printerr("세트 굽기 실패: ", res.get("error", "")); quit(1); return

	var vp := SubViewport.new()
	vp.size = Vector2i(600, 500)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var s := DRPuppetSet.new()
	s.sets_json = OUT.path_join("sets.json")
	s.position = Vector2(300, 420)
	s.scale = Vector2(2, 2)
	vp.add_child(s)
	await _frames(3)

	print("[1] 세트를 하나처럼")
	_check(Array(s.get_animations()) == ["Idle", "Pistol_Aim_Neutral", "Crouch_Idle"], "동작 %s" % str(s.get_animations()))
	_check(s.current_animation() == &"Idle" and s.current_set() == "stand", "처음에는 첫 세트의 첫 동작 (%s / %s)" % [s.current_set(), s.current_animation()])
	_check(s.play("Crouch_Idle") and s.current_set() == "crouch" and s.get_puppet() != null and s.get_animation_player().current_animation == "Crouch_Idle",
		"play(\"Crouch_Idle\") → 세트 crouch 로 바뀌고 재생")
	_check(not s.play("Nope"), "없는 이름은 false")
	var visible_n := 0
	for c in s.get_children():
		if (c as Node2D).visible:
			visible_n += 1
	_check(visible_n == 1 and s.get_child_count() == 2, "퍼펫 %d개 중 보이는 것 %d개" % [s.get_child_count(), visible_n])

	print("[2] 발 자리")
	await _frames(4)
	await RenderingServer.frame_post_draw
	var g_crouch := _ground_contact(vp)
	s.play("Idle")
	await _frames(4)
	await RenderingServer.frame_post_draw
	var g_stand := _ground_contact(vp)
	# 원점(300, 420) = 두 발 사이의 바닥. 아웃라인 1도트 × 배율 2 만큼은 아래로 나올 수 있다
	_check(absf(g_stand.y - 420.0) <= 4.0 and absf(g_crouch.y - 420.0) <= 4.0 and absf(g_stand.y - g_crouch.y) <= 3.0,
		"그림의 맨 아래 줄: 서기 y %.0f · 앉기 y %.0f (원점 y 420)" % [g_stand.y, g_crouch.y])

	print("[3] 조준")
	s.play("Pistol_Aim_Neutral")
	s.get_animation_player().speed_scale = 0.0            # 애니를 세워 둔다 — 그래도 각도가 쌓이면 안 된다
	await _frames(3)
	var torso := s.get_puppet().get_bone("Torso")
	var base_rot := torso.rotation
	s.auto_face = false
	s.aim_enabled = true
	s.aim_limit_deg = 30.0
	s.aim_speed = 60.0                                             # 검사에서는 프레임이 아주 빨리 돈다(델타가 작다) — 따라가기가 끝나길 넉넉히 기다린다
	s.aim_target = torso.global_position + Vector2(200, -60)      # 오른쪽 위 — atan2(−60, 200) = −16.7°
	await _frames(400)
	var up_deg := s.get_aim_degrees()
	var rot_a := torso.rotation
	await _frames(300)
	var rot_b := torso.rotation
	_check(absf(up_deg - (-16.7)) < 0.3 and absf(rad_to_deg(rot_a - base_rot) - up_deg) < 0.05, "오른쪽 위를 겨눔: %.1f° (기대 −16.7) · 몸통 본에 그만큼 더해짐" % up_deg)
	_check(absf(rot_b - rot_a) < 0.00005 and absf(rad_to_deg(rot_b - base_rot) - s.get_aim_degrees()) < 0.05,
		"멈춘 애니 위에서 300프레임 더 — 몸통 각도가 쌓이지 않음 (변화 %.6f rad · 본 각도 = 원래 + 조준 %.1f°)" % [absf(rot_b - rot_a), s.get_aim_degrees()])
	s.aim_target = torso.global_position + Vector2(40, -400)      # 거의 수직 위 → 한계 30°
	await _frames(400)
	_check(absf(s.get_aim_degrees() - (-30.0)) < 0.3, "한계에서 멈춤: %.1f° (한계 30)" % s.get_aim_degrees())
	s.aim_target = torso.global_position + Vector2(200, 80)
	await _frames(400)
	_check(s.get_aim_degrees() > 15.0, "아래를 겨눔: %+.1f°" % s.get_aim_degrees())
	s.aim_enabled = false
	await _frames(400)
	_check(absf(torso.rotation - base_rot) < 0.002, "조준을 끄면 원래 자세로 (차이 %.4f rad)" % absf(torso.rotation - base_rot))
	# 세트를 바꿨다 돌아와도 예전 퍼펫에 각도가 남지 않는다
	s.aim_enabled = true
	s.aim_target = torso.global_position + Vector2(200, -60)
	await _frames(300)
	s.play("Crouch_Idle")
	await _frames(5)
	_check(absf(torso.rotation - base_rot) < 0.002, "세트를 바꾸면 예전 퍼펫의 몸통에 더한 각도를 빼 놓음")

	print("[4] 좌우 반전")
	s.play("Pistol_Aim_Neutral")
	s.auto_face = true
	torso = s.get_puppet().get_bone("Torso")
	s.aim_target = torso.global_position + Vector2(-220, -70)      # 등 뒤(왼쪽) 위
	await _frames(400)
	_check(s.get_facing() == -1 and s.scale.x < 0.0, "목표가 왼쪽이면 돌아봄 (scale.x %.1f)" % s.scale.x)
	_check(s.get_aim_degrees() < -10.0, "돌아본 채로도 위는 위: %+.1f°" % s.get_aim_degrees())
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("res://puppet_test/_pset_left_up.png")
	s.aim_target = torso.global_position + Vector2(260, -70)
	await _frames(400)
	_check(s.get_facing() == 1 and s.scale.x > 0.0, "다시 오른쪽이면 되돌아봄")

	print("[5] 장비 — 모든 세트에 한 번에 · 파트 사이 순서 · 무기 교체")
	s.aim_enabled = false
	var eq_a := _equip_set("rifle_a", Color(0.9, 0.2, 0.2), ["stand", "crouch"])
	var eq_b := _equip_set("rifle_b", Color(0.2, 0.4, 0.9), ["stand"])          # 앉기용 그림이 없는 무기
	_check(s.equip(eq_a) == 2, "세트 2개에 모두 장착")
	s.play("Idle")
	await _frames(3)
	var pa := s.get_puppet()
	var spr_a := pa.get_equipped("weapon")
	var torso_art := pa.get_bone("Torso").get_node("stretch/art") as Sprite2D
	var hand_art := pa.get_bone("R_Hand").get_node("stretch/art") as Sprite2D
	_check(spr_a != null and spr_a.get_parent().get_parent() == pa.get_bone("R_Hand"), "서기 세트: 오른손에 붙음")
	_check(torso_art.z_index % DRRigModel.Z_STEP == 0 and torso_art.z_index >= DRRigModel.Z_STEP,
		"파트 z 는 %d 간격 (몸통 %d · 오른손 %d)" % [DRRigModel.Z_STEP, torso_art.z_index, hand_art.z_index])
	# 몸통 바로 다음 순서인 파트의 z (없으면 아주 큰 값)
	var next_z := 100000
	for pn in pa.part_names():
		var pz := (pa.get_bone(pn).get_node("stretch/art") as Sprite2D).z_index
		if pz > torso_art.z_index and pz < next_z:
			next_z = pz
	_check(spr_a != null and spr_a.z_index == torso_art.z_index + 5 and spr_a.z_index < next_z,
		"z_after_part Torso → 몸통(%d) 바로 앞 · 다음 파트(%d) 뒤 (장비 z %d)" % [torso_art.z_index, next_z, spr_a.z_index if spr_a != null else -999])
	s.play("Crouch_Idle")
	await _frames(3)
	var pc := s.get_puppet()
	_check(pc != pa and pc.get_equipped("weapon") != null, "앉기 세트로 넘어가도 들려 있다(그 세트용 그림)")
	_check(pc.get_equipped("weapon").texture != spr_a.texture, "세트마다 자기 그림")
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("res://puppet_test/_pset_equip_crouch.png")
	# 무기 교체 — 같은 슬롯. 앉기용 그림이 없는 무기로 바꾸면 앉기 세트의 슬롯은 빈다
	_check(s.equip(eq_b) == 1 and s.get_equipped("weapon") == eq_b, "무기 교체: 그림이 있는 세트 1개에 장착")
	await _frames(2)
	_check(pc.get_equipped("weapon") == null, "그림이 없는 세트는 슬롯을 비운다(옛 무기가 남지 않음)")
	_check(pa.get_equipped("weapon") != null and pa.get_equipped("weapon").texture == eq_b.item_for("stand").texture, "서기 세트는 새 무기 그림")
	# 다시 읽어도(다시 구운 뒤 R) 장비가 돌아온다
	s.reload()
	await _frames(3)
	s.play("Idle")
	await _frames(2)
	_check(s.get_puppet().get_equipped("weapon") != null, "reload() 뒤에도 다시 장착된다")
	s.unequip("weapon")
	await _frames(2)
	_check(s.get_puppet().get_equipped("weapon") == null and s.get_equipped("weapon") == null, "unequip — 모든 세트에서 뺀다")

	if _fail > 0:
		printerr("퍼펫 세트 검사 실패 %d건" % _fail)
		quit(1); return
	print("퍼펫 세트 검사 전부 통과")
	quit(0)
