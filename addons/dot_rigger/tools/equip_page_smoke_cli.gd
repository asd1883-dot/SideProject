extends SceneTree

## ② 장비 탭(DREquipPage) 검사(10-16, 3D 소켓 정석) — 창 없이(--headless). 에디터 밖이라 되돌리기 없이 인스턴스를 바로 고치는 길을 탄다
## (에디터 안 길 = 열린 씬 · 되돌리기는 pipeline/check_editor.py). 시험으로 만든 파일은 끝에 지운다.
##   Godot --headless --path <프로젝트> --script res://addons/dot_rigger/tools/equip_page_smoke_cli.gd
## [1] 페이지 · 유닛 · 소켓 나무(오른손 → kar98k → 왼손 표지) · 미리보기(소켓 무기 · 도트 재질 · 숨김 부품 · 왼팔 IK)
## [2] 장비 모델 목록 · 무기 기본 자리(asset.json socket_hold — kar98k · mp40)
## [3] 동작마다 왼 손바닥 ↔ 표지(IK 전 · 뒤) — 소총 동작은 IK 뒤 1 cm 안
## [4] 자식 유닛(시험 파일): mp40 넣기(부모 kar98k 는 숨김 · 기본 자리 · 표지) · 머리 소켓 + 대용 헬멧 · 자리 숫자 · IK 비중 → 저장 → 다시 읽기
## [5] 게임처럼 다시 만들기: 숨긴 부모 무기는 지워짐 · 무기 · 헬멧이 뼈를 따라감 · 도트 재질 · fade · 수정자 MANUAL · mp40 왼손 IK
## 마지막 줄이 "EQUIP PAGE SMOKE OK" 면 통과.

const BASE := "res://game/units/soldier_base.tscn"
const CHILD := "res://game/units/시험장비_삭제.tscn"
const K98 := "res://source3d/weapons/kar98k/kar98k.tscn"
const MP40 := "res://source3d/weapons/mp40/mp40.glb"
const RIFLE := ["Rifle_Aiming_Idle", "Firing_Rifle", "Rifle_Idle", "Walk_With_Rifle", "Crouch_Idle+Firing_Rifle", "Prone_Firing_Rifle"]

var _fails := PackedStringArray()


func _initialize() -> void:
	create_timer(240.0).timeout.connect(func() -> void:
		print("EQUIP PAGE SMOKE FAIL 시간 초과")
		quit(2))
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["OK  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _dot(mi: MeshInstance3D) -> bool:
	if mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return false
	var m := mi.get_surface_override_material(0) as ShaderMaterial
	return m != null and m.shader != null and m.shader.resource_path.ends_with("dot_char.gdshader")


func _run() -> void:
	if FileAccess.file_exists(CHILD):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHILD))
	var page := DREquipPage.new()
	root.add_child(page)
	page.test_layout(Vector2i(1400, 860))
	await _frames(3)

	print("[1] 페이지 · 유닛 · 소켓 · 미리보기")
	_check(page._units.has(BASE) and page._sel_path == BASE and page._root != null, "유닛 목록 %d개 · 고른 유닛 %s" % [page._units.size(), page._sel_path.get_file()])
	var socks := page._sockets()
	var w := page._weapon_equip()
	var mk := DRCharacter3D.find_support(w) if w != null else null
	_check(socks.size() >= 1 and socks[0].bone_name == "RightHand" and w != null and w.scene_file_path == K98 and mk is DRHandTarget3D,
		"소켓 %s(%s) → %s → 왼손 표지 %s" % [socks[0].name if not socks.is_empty() else "-", socks[0].bone_name if not socks.is_empty() else "-", w.name if w != null else "-", mk.name if mk != null else "-"])
	_check(page._all_items(page._tree.get_root()).size() >= 3, "소켓 나무 %d줄" % page._all_items(page._tree.get_root()).size())
	var pv := page._prev
	_check(pv != null and pv.get_weapon_node() != null and pv.get_weapon_node().scene_file_path == K98 and pv.get_left_arm_ik() != null, "미리보기: 소켓 무기 · 왼팔 IK")
	var dots := 0
	for mi in (pv.get_equipment_meshes() if pv != null else []):
		if _dot(mi):
			dots += 1
	var bullets := pv.get_weapon_node().get_node_or_null("bullets") as Node3D if pv != null else null
	_check(dots >= 3 and bullets != null and not bullets.visible and not pv.get_equipment_meshes().has(bullets), "장비 메시 도트 재질 %d개 · 탄 클립 숨김(재질도 안 입힘)" % dots)
	_check(pv != null and pv.get_skeleton().modifier_callback_mode_process == Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL, "미리보기 사본 수정자 = 자세가 바뀔 때만(MANUAL)")
	page.play_motion("Firing_Rifle")
	await _frames(12)
	_check(page.current_motion() == "Firing_Rifle" and pv.get_ik_weight() > 0.99 and float(page._live.get("dist", 1.0)) < 0.01,
		"Firing_Rifle 재생 · 왼손 IK 비중 %.2f · 미리보기 갱신 때 손바닥 ↔ 표지 %.2f cm" % [pv.get_ik_weight(), float(page._live.get("dist", 1.0)) * 100.0])
	page._update_info()
	print("        정보 줄: ", page._info.text)

	print("[2] 장비 모델 · 무기 기본 자리")
	var models := PackedStringArray()
	for i in page._model_ob.item_count:
		models.append(String(page._model_ob.get_item_metadata(i)))
	_check(models.has(K98) and models.has(MP40) and models.has(DREquipHold.PLACEHOLDER_HELMET), "모델 목록 %d개(%s)" % [models.size(), ", ".join(models)])
	var hk := DREquipHold.read_hold(DREquipHold.asset_for_model(K98))
	var hm := DREquipHold.read_hold(DREquipHold.asset_for_model(MP40))
	_check(not hk.is_empty() and hk.has("support") and String(hk["scene"]) == K98 and not hm.is_empty() and hm.has("support"), "기본 자리: kar98k(%s) · mp40(%s)" % [str(not hk.is_empty()), str(not hm.is_empty())])
	_check(not hk.is_empty() and (hk["weapon"] as Transform3D).is_equal_approx(w.transform), "kar98k 기본 자리 = soldier_base 의 자리")

	print("[3] 동작마다 왼 손바닥 ↔ 표지(8 시점 평균 / 최대 cm, IK 전 → 뒤)")
	var rep := page.measure_all()
	var by := {}
	for r in rep:
		var d: Dictionary = r
		by[String(d["motion"])] = d
		print("        %-30s 비중 %.1f · IK 전 %5.1f / %5.1f → IK 뒤 %4.1f / %4.1f" % [d["motion"], d["weight"], float(d["raw_avg"]) * 100.0, float(d["raw_max"]) * 100.0, float(d["ik_avg"]) * 100.0, float(d["ik_max"]) * 100.0])
	var bad := PackedStringArray()
	for m in RIFLE:
		if not by.has(m) or float((by[m] as Dictionary)["ik_max"]) > 0.01:
			bad.append(m)
	_check(rep.size() >= 20 and bad.is_empty(), "소총 동작 %d개 IK 뒤 최대 1 cm 안%s" % [RIFLE.size(), "" if bad.is_empty() else " — 넘음: " + ", ".join(bad)])
	_check(by.has("Sprint") and float((by["Sprint"] as Dictionary)["weight"]) == 0.0 and by.has("Toss_Grenade") and float((by["Toss_Grenade"] as Dictionary)["weight"]) == 0.0, "맨손 달리기 · 수류탄 = IK 비중 0(왼손 그대로)")
	_check(page._mt.get_root() != null and page._mt.get_root().get_child_count() == rep.size(), "동작 표 %d줄" % (page._mt.get_root().get_child_count() if page._mt.get_root() != null else 0))

	print("[4] 자식 유닛 — 무기 바꾸기 · 헬멧 소켓 · 자리 · 비중 · 저장 · 다시 읽기")
	var f := FileAccess.open(CHILD, FileAccess.WRITE)
	f.store_string("[gd_scene load_steps=2 format=3]\n\n[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1_parent\"]\n\n[node name=\"시험장비\" instance=ExtResource(\"1_parent\")]\n" % BASE)
	f.close()
	page.scan_units()
	page.select_unit(CHILD)
	await _frames(2)
	_check(page._sel_path == CHILD and page._base_paths.has("오른손/kar98k"), "자식 유닛 고름 · 부모에서 온 노드 %d개(오른손/kar98k 포함)" % page._base_paths.size())
	page._select_node(NodePath("오른손"))
	var mp := page.put_model(MP40)
	await _frames(2)
	var k_old := page._root.get_node_or_null("오른손/kar98k") as Node3D
	var mmk := DRCharacter3D.find_support(mp) if mp != null else null
	_check(mp != null and k_old != null and not k_old.visible and mp.visible and mp.transform.is_equal_approx(hm["weapon"]), "mp40 넣음 — 부모 kar98k 는 숨김(지울 수 없음) · 기본 자리 그대로")
	_check(mmk is DRHandTarget3D and (mmk as Node3D).transform.is_equal_approx(hm["support"]) and (mmk as DRHandTarget3D).motion_weights.size() == (hm["motion_weights"] as Dictionary).size(), "mp40 왼손 표지 · 동작별 비중 %d개(기본 자리에서)" % ((mmk as DRHandTarget3D).motion_weights.size() if mmk is DRHandTarget3D else -1))
	_check(page._prev != null and page._prev.get_weapon_node() != null and page._prev.get_weapon_node().scene_file_path == MP40, "미리보기 무기 = mp40")
	var head := page.add_socket("", "Head")
	page._select_node(page._root.get_path_to(head))
	var helmet := page.put_model(DREquipHold.PLACEHOLDER_HELMET)
	_check(head != null and head.name == "머리" and helmet != null and helmet.get_parent() == head, "머리 소켓(Head) + 대용 헬멧")
	page._select_node(page._root.get_path_to(helmet))
	page._pos[1].value = 12.0
	_check(absf(helmet.position.y - 0.12) < 0.0005, "숫자 칸 → 헬멧 위치 y %.3f m" % helmet.position.y)
	page._select_node(page._root.get_path_to(mp))
	page.set_motion_weight("Rifle_Idle", 0.5)
	_check(mmk is DRHandTarget3D and absf(float((mmk as DRHandTarget3D).motion_weights.get("Rifle_Idle", -1.0)) - 0.5) < 0.001, "IK 비중 Rifle_Idle = 0.5(표지 motion_weights)")
	page.save_unit()
	var txt := FileAccess.get_file_as_string(CHILD)
	print("        저장한 자식 씬:\n" + txt.indent("          ").substr(0, 2400))
	_check(txt.contains("instance=ExtResource") and txt.contains("mp40.glb") and txt.contains("visible = false") and txt.contains("bone_name = \"Head\"") and txt.contains("\"Rifle_Idle\": 0.5"),
		"자식 씬 = 부모 상속 + kar98k 숨김 + mp40 · 표지 + 머리 소켓 · 헬멧")
	_check(not txt.contains("outfit_top") and not txt.contains("DR_LeftArmIK"), "안 바꾼 칸 · 내부 IK 노드는 파일에 없음")
	var back := (ResourceLoader.load(CHILD, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN) as Node3D
	var bmp := back.get_node_or_null("오른손/mp40") as Node3D
	var bmk := DRCharacter3D.find_support(bmp) if bmp != null else null
	var bhl := back.get_node_or_null("머리/헬멧_대용") as Node3D
	_check(bmp != null and bmp.transform.is_equal_approx(mp.transform) and bmk != null and bmk.transform.is_equal_approx((mmk as Node3D).transform)
		and bhl != null and absf(bhl.position.y - 0.12) < 0.0005, "다시 읽기: mp40 자리 · 표지 · 헬멧 자리가 같음")
	back.free()

	print("[5] 게임처럼 다시 만들기(에디터 밖 = 게임 길)")
	var g := (ResourceLoader.load(CHILD, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as DRCharacter3D
	root.add_child(g)
	await _frames(2)
	var gs := g.get_node_or_null("오른손")
	var kept := gs.get_node_or_null("kar98k") if gs != null else null
	_check(gs != null and kept == null and g.get_weapon_node() != null and g.get_weapon_node().scene_file_path == MP40, "숨긴 부모 무기는 지워짐 · 무기 = mp40")
	g.get_animation_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	g.play_motion("Firing_Rifle", 0.0)
	var sk := g.get_skeleton()
	var hs := g.get_node("머리") as BoneAttachment3D
	var worst_r := 0.0
	var worst_h := 0.0
	var worst_ik := 0.0
	for i in 6:
		g.step_motion(1.0 / 12.0)
		await process_frame
		var rh := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("RightHand"))
		var hd := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Head"))
		worst_r = maxf(worst_r, rh.origin.distance_to((gs as Node3D).global_position))
		worst_h = maxf(worst_h, hd.origin.distance_to(hs.global_position))
		worst_ik = maxf(worst_ik, float(g.support_report().get("ik", 1.0)))
	_check(worst_r < 0.001 and worst_h < 0.001, "소켓이 뼈를 따라감(오른손 %.4f m · 머리 %.4f m 어긋남)" % [worst_r, worst_h])
	_check(worst_ik < 0.01, "mp40 Firing_Rifle 왼 손바닥 ↔ 표지 IK 뒤 최대 %.2f cm" % (worst_ik * 100.0))
	var gd := 0
	var helmet_dot := false
	for mi in g.get_equipment_meshes():
		if _dot(mi):
			gd += 1
			if String(mi.name) == "헬멧_대용":
				helmet_dot = true
	_check(gd >= 2 and helmet_dot, "장비 도트 재질 %d개(헬멧 포함)" % gd)
	_check(sk.modifier_callback_mode_process == Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL, "게임: 수정자 = 자세가 바뀔 때만(MANUAL)")
	g.set_fade(0.0)
	var hidden := not (gs as Node3D).visible and not hs.visible
	g.set_fade(1.0)
	_check(hidden and (gs as Node3D).visible and hs.visible, "set_fade(0) 이면 소켓 장비도 숨김 · 1 이면 다시 보임")

	print("[6] 뼈대 길이 든 사본 — ① ② 미리보기는 조립된 열린 씬을 pack 한다(소켓의 길까지 담김). 그 길이 저장된 씬도 같다")
	var path_in := String((gs as BoneAttachment3D).external_skeleton)
	var pk := PackedScene.new()
	pk.pack(g)
	var c2 := pk.instantiate() as DRCharacter3D
	root.add_child(c2)
	await _frames(2)
	c2.get_animation_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	c2.play_motion("Firing_Rifle", 0.0)
	var sk2 := c2.get_skeleton()
	var s2 := c2.get_node("오른손") as BoneAttachment3D
	var worst2 := 0.0
	for i in 6:
		c2.step_motion(1.0 / 12.0)
		await process_frame
		var rh2 := sk2.global_transform * sk2.get_bone_global_pose(sk2.find_bone("RightHand"))
		worst2 = maxf(worst2, rh2.origin.distance_to(s2.global_position))
	_check(path_in != "" and worst2 < 0.001, "길(%s)이 든 사본도 소켓이 뼈를 따라감(%.4f m 어긋남)" % [path_in, worst2])
	c2.queue_free()
	g.queue_free()

	# 치우기
	page._drop_root()
	page.queue_free()
	await _frames(2)
	if FileAccess.file_exists(CHILD):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CHILD))
	_check(not FileAccess.file_exists(CHILD), "시험 파일 지움")
	if _fails.is_empty():
		print("EQUIP PAGE SMOKE OK")
	else:
		print("EQUIP PAGE SMOKE FAIL ", ", ".join(_fails))
	quit(0 if _fails.is_empty() else 1)
