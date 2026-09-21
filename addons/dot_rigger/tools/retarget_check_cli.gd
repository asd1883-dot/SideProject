extends SceneTree

## Mixamo 접목(리타깃) 검사.
##  [1] 표준 휴머노이드로 다시 가져온 모델(UAL1_humanoid.glb)의 기존 동작이 원본(models/UAL1.glb)과 같은 자세인가
##  [2] 추가 동작 폴더(source3d/mixamo)의 파일이 전부 경고 없이 얹히는가 · 파트 15개 · 미매핑 본 0
##  [3] 얹은 동작을 구우면 씬에 들어가는가
## 재료(source3d)가 없는 PC 에서는 건너뛴다(종료 코드 0).
##
##   Godot.exe --path <프로젝트> --resolution 400x300 \
##     --script res://addons/dot_rigger/tools/retarget_check_cli.gd
##   선택: -- --orig=res://models/UAL1.glb --model=res://source3d/UAL1_humanoid.glb \
##            --extra=res://source3d/mixamo --bonemap=res://source3d/bonemap_ual.tres

const OUT := "res://puppet_test/retarget_bake"
const SAMPLE_ANIMS := ["Idle", "Walk", "Sprint", "Crouch_Fwd", "Crawl_Fwd", "Pistol_Shoot", "Roll", "Death01"]

var _args := {}
var _fail := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			s = s.substr(2)
		var eq := s.find("=")
		if eq >= 0:
			_args[s.substr(0, eq)] = s.substr(eq + 1)
	_run.call_deferred()


func _arg(k: String, d: String) -> String:
	return String(_args.get(k, d))


func _check(ok: bool, msg: String) -> void:
	print(("  OK    " if ok else "  FAIL  ") + msg)
	if not ok:
		_fail += 1


func _skel_of(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _skel_of(c)
		if s != null:
			return s
	return null


func _pose(ap: AnimationPlayer, sk: Skeleton3D, anim: String, t: float) -> void:
	ap.speed_scale = 0.0
	ap.play(anim)
	ap.seek(t, true)
	ap.advance(0.0)
	sk.force_update_all_bone_transforms()


func _run() -> void:
	var orig_path := _arg("orig", "res://models/UAL1.glb")
	var model_path := _arg("model", "res://source3d/UAL1_humanoid.glb")
	var extra_dir := _arg("extra", "res://source3d/mixamo")
	var bm_path := _arg("bonemap", "res://source3d/bonemap_ual.tres")
	if not ResourceLoader.exists(model_path) or not ResourceLoader.exists(bm_path) or DirAccess.open(extra_dir) == null:
		print("접목 검사 건너뜀 — 재료가 없음 (%s · %s · %s)" % [model_path, bm_path, extra_dir])
		quit(0); return

	print("[1] 표준 뼈대로 다시 가져온 모델 = 원본과 같은 자세인가")
	var bm := load(bm_path) as BoneMap
	var a := (load(orig_path) as PackedScene).instantiate()
	var b := (load(model_path) as PackedScene).instantiate()
	root.add_child(a)
	root.add_child(b)
	var a_sk := _skel_of(a)
	var b_sk := _skel_of(b)
	var a_ap := a.get_node("AnimationPlayer") as AnimationPlayer
	var b_ap := b.get_node("AnimationPlayer") as AnimationPlayer
	_check(a_ap.get_animation_list().size() == b_ap.get_animation_list().size(),
		"동작 수 원본 %d = 표준 %d" % [a_ap.get_animation_list().size(), b_ap.get_animation_list().size()])
	var pairs: Array = []   # [원본 본 번호, 표준 본 번호]
	for i in bm.profile.bone_size:
		var pn := bm.profile.get_bone_name(i)
		var sn := bm.get_skeleton_bone_name(pn)
		if String(sn) == "":
			continue
		var ai := a_sk.find_bone(sn)
		var bi := b_sk.find_bone(pn)
		if ai >= 0 and bi >= 0:
			pairs.append([ai, bi])
	_check(pairs.size() >= 50, "짝지은 본 %d개 (표준 이름으로 바뀜)" % pairs.size())
	await process_frame
	# 손가락은 사슬이 길어 오차가 쌓인다 → 몸 관절과 따로 잰다(184px 캔버스에서 1도트 ≈ 0.01 m)
	var worst := 0.0
	var worst_at := ""
	var worst_body := 0.0
	var worst_body_at := ""
	var tested := 0
	for an in SAMPLE_ANIMS:
		if not a_ap.has_animation(an) or not b_ap.has_animation(an):
			continue
		tested += 1
		var length := a_ap.get_animation(an).length
		for f in [0.0, 0.3, 0.6, 0.9]:
			_pose(a_ap, a_sk, an, length * f)
			_pose(b_ap, b_sk, an, length * f)
			for pr in pairs:
				var pa: Vector3 = a_sk.global_transform * a_sk.get_bone_global_pose(pr[0]).origin
				var pb: Vector3 = b_sk.global_transform * b_sk.get_bone_global_pose(pr[1]).origin
				var dist := pa.distance_to(pb)
				var bname := b_sk.get_bone_name(pr[1])
				if dist > worst:
					worst = dist
					worst_at = "%s %d%% %s" % [an, int(f * 100), bname]
				var is_finger := false
				for key in ["Thumb", "Index", "Middle", "Ring", "Little"]:
					if bname.contains(key):
						is_finger = true
				if not is_finger and dist > worst_body:
					worst_body = dist
					worst_body_at = "%s %d%% %s" % [an, int(f * 100), bname]
	_check(tested >= 6 and worst_body < 0.005 and worst < 0.01,
		"동작 %d개 × 4시점 × 본 %d개 — 관절 위치 최대 차이: 몸 %.4f m (%s) < 0.005 · 손가락 포함 %.4f m (%s) < 0.01"
		% [tested, pairs.size(), worst_body, worst_body_at, worst, worst_at])
	a.queue_free()
	b.queue_free()
	await process_frame

	print("[2] 추가 동작 폴더")
	var n_src := 0
	for f in DirAccess.open(extra_dir).get_files():
		if DRBaker.EXTRA_ANIM_EXT.has(String(f).get_extension().to_lower()):
			n_src += 1
	var opts := DRBaker.Options.new()
	opts.view_size = Vector2i(184, 184)
	opts.yaw = -55.0
	opts.rest_anim = "Idle"
	opts.extra_anim_dir = extra_dir
	var baker := DRBaker.new()
	if not baker.setup(root, load(model_path) as PackedScene, DRPartProfile.humanoid(), opts):
		printerr("setup 실패"); quit(1); return
	_check(baker.rig.order.size() == 15 and baker.split.unmapped_bones.is_empty(),
		"파트 %d개 · 미매핑 본 %s" % [baker.rig.order.size(), str(baker.split.unmapped_bones)])
	_check(n_src > 0 and baker.extra_anims.size() == n_src and baker.extra_anim_warnings.is_empty(),
		"파일 %d개 → 동작 %d개, 경고 %d건 %s" % [n_src, baker.extra_anims.size(), baker.extra_anim_warnings.size(), str(baker.extra_anim_warnings)])
	print("        ", ", ".join(baker.extra_anims))
	# 힙 높이가 말이 되는가(위치 트랙 정규화가 틀리면 땅에 박히거나 뜬다). 엎드린 동작도 있으므로 범위는 넓게
	baker.set_rest_pose()
	var hips := baker.skeleton.find_bone("Hips")
	var rest_h: float = (baker.skeleton.global_transform * baker.skeleton.get_bone_global_rest(hips).origin).y
	var bad_h := PackedStringArray()
	for an in baker.extra_anims:
		baker.set_pose(an, 0.0)
		var h: float = (baker.skeleton.global_transform * baker.skeleton.get_bone_global_pose(hips).origin).y
		print("        %-22s 길이 %.2f초 · 힙 높이 %.2f m (레스트 %.2f)" % [an, baker.anim_player.get_animation(an).length, h, rest_h])
		if is_nan(h) or h < 0.02 or h > rest_h * 1.5:
			bad_h.append(an)
	_check(bad_h.is_empty(), "힙 높이가 0.02 m ~ 레스트의 1.5배 안 %s" % str(bad_h))

	print("[3] 얹은 동작 굽기")
	await process_frame
	var ex := DRExporter.new()
	ex.baker = baker
	ex.out_dir = OUT
	ex.keep_previous = false
	ex.outline_px = 1
	var first: String = baker.extra_anims[0] if baker.extra_anims.size() > 0 else ""
	ex.anim_names = PackedStringArray(["Idle", first])
	baker.opts.rest_anim = first
	baker.opts.rest_time = 0.0
	var res: Dictionary = await ex.run()
	var ps := ResourceLoader.load(OUT.path_join("puppet.tscn"), "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var pup := ps.instantiate() if ps != null else null
	var pap := pup.get_node_or_null("AnimationPlayer") as AnimationPlayer if pup != null else null
	_check(bool(res.get("ok", false)) and pap != null and pap.has_animation(first) and pap.has_animation("Idle"),
		"구운 씬에 Idle · %s 가 들어 있음" % first)
	if pup != null:
		pup.free()

	if _fail > 0:
		printerr("접목 검사 실패 %d건" % _fail)
		quit(1); return
	print("접목 검사 전부 통과")
	quit(0)
