extends SceneTree

## 커맨드라인 베이크 하니스 (에디터 UI 없이 파이프라인 검증용)
##
## 사용:
##   Godot.exe --path <프로젝트> --script res://addons/dot_rigger/tools/bake_cli.gd -- \
##       --model=res://models/UAL1.glb --out=res://puppet_test \
##       --yaw=90 --pitch=0 --size=192 --fps=12 \
##       --rest=A_TPose --anims=Idle_Loop,Walk_Fwd_Loop
##
## --diag 만 주면 렌더 없이 본->파트 매핑 결과만 출력한다.
## --nostretch 단축 보정 끔 / --nosmooth 부드러운 도트 이동 셰이더를 붙이지 않음.
## --split_toes 발가락을 발과 따로 꺾음(기본은 발에 합쳐 발은 한 장·발목 회전만).
## --fresh 같은 출력 폴더에 예전에 구운 애니를 이어 담지 않고 이번 애니만 남김.
## --offset_x=0 --offset_y=0 캐릭터 화면 위치 이동(px, +x 오른쪽, +y 위). --nofit 일 때 의미 있음.
## --planar 동작 평면화(2D 게임식) · --pose_yaw=90 각도를 잴 시점(생략 = 자동 측면).
## --outline=1 도트 아웃라인 두께(0~3) · --outline_color=000000 색(html) · --outline_parts 파트별 선(기본은 전체 실루엣).

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
	var model_path := _arg("model", "res://models/UAL1.glb")
	print("[DotRigger] 모델 로드: ", model_path)
	var scene := load(model_path) as PackedScene
	if scene == null:
		printerr("모델을 로드하지 못했습니다: ", model_path)
		quit(1)
		return

	var profile := DRPartProfile.humanoid(_args.has("split_toes"))

	# ---- 진단 모드: 본 -> 파트 매핑만 확인 ----
	if _args.has("diag"):
		_diagnose(scene, profile)
		quit(0)
		return

	var opts := DRBaker.Options.new()
	var sz := int(_arg("size", "192"))
	opts.view_size = Vector2i(sz, sz)
	opts.yaw = float(_arg("yaw", "90"))
	opts.pitch = float(_arg("pitch", "0"))
	opts.ortho_size = float(_arg("ortho", "0"))
	opts.view_offset = Vector2(float(_arg("offset_x", "0")), float(_arg("offset_y", "0")))
	opts.planar = _args.has("planar")
	opts.pose_yaw = float(_arg("pose_yaw", "999"))
	opts.supersample = int(_arg("ss", "1"))
	opts.bleed_rings = int(_arg("bleed", "1"))
	opts.rest_anim = _arg("rest", "")
	opts.rest_time = float(_arg("rest_time", "0"))
	opts.light_bands = int(_arg("bands", "3"))
	opts.color_levels = int(_arg("levels", "0"))
	opts.alpha_threshold = float(_arg("alpha", "0.5"))

	var baker := DRBaker.new()
	if not baker.setup(root, scene, profile, opts):
		printerr("베이커 setup 실패")
		quit(1)
		return

	print("[DotRigger] 파트 %d개: %s" % [baker.rig.order.size(), String(", ").join(baker.rig.order)])
	for pname in baker.rig.order:
		var p: DRRigModel.Part = baker.rig.parts[pname]
		print("   %-12s parent=%-12s root_bone=%-14s bones=%d tris=%d" % [
			pname, (p.parent if p.parent != "" else "-"),
			baker.skeleton.get_bone_name(p.root_bone), p.bones.size(),
			int(baker.split.tri_counts.get(pname, 0))])
	if baker.split.unmapped_bones.size() > 0:
		print("[DotRigger] 매핑 안 된 본: ", baker.split.unmapped_bones)

	await process_frame
	await process_frame

	var ex := DRExporter.new()
	ex.baker = baker
	ex.out_dir = _arg("out", "res://puppet_test")
	ex.anim_fps = int(_arg("fps", "12"))
	var an := _arg("anims", "")
	if an != "":
		ex.anim_names = PackedStringArray(an.split(",", false))
	ex.progress.connect(func(stage, cur, total): print("  [%s] %d/%d" % [stage, cur, total]))
	ex.auto_fit = not _args.has("nofit")
	ex.fit_margin = int(_arg("margin", "6"))
	ex.apply_stretch = not _args.has("nostretch")
	ex.smooth_pixel = not _args.has("nosmooth")
	ex.keep_previous = not _args.has("fresh")
	ex.outline_px = int(_arg("outline", "0"))
	ex.outline_color = Color(_arg("outline_color", "000000"))
	ex.outline_whole = not _args.has("outline_parts")
	var zo := _arg("zorder", "")
	if zo != "":
		ex.z_override = PackedStringArray(zo.split(",", false))

	var res: Dictionary = await ex.run()
	print("[그리기 순서 뒤->앞] ", String(" < ").join(ex.resolve_z_order()))
	_report_foreshortening(ex)

	# 합성 프리뷰(파트가 제대로 다시 합쳐지는지 눈으로 확인용). 프레이밍 보정 후 기준.
	baker.set_rest_pose()
	var comp: Image = await baker.render_all_parts_composite()
	comp.save_png(ex.out_dir.path_join("_preview_composite.png"))
	print("[DotRigger] ortho_size=%.4f" % baker.camera.size)
	if ex.kept_anims.size() > 0:
		print("[DotRigger] 같은 폴더의 예전 애니 이어 담음: ", ex.kept_anims)
	if ex.dropped_reason != "":
		print("[DotRigger] ⚠ ", ex.dropped_reason)
	print("[DotRigger] 결과: ", res)
	quit(0 if bool(res.get("ok", false)) else 1)


## 파트별 화면상 길이 변동(단축률)을 보고한다.
## 1.0 에서 많이 벗어나는 파트일수록 그 각도에서 컷아웃으로 표현하기 어렵고,
## 레스트 포즈를 바꾸면 개선되는 경우가 많다.
func _report_foreshortening(ex: DRExporter) -> void:
	var data: Dictionary = ex.get("_anim_data")
	if data == null or data.is_empty():
		return
	print("\n[단축률 진단] 1.00 에 가까울수록 이 시점에서 컷아웃 표현이 안전함")
	var acc := {}
	for aname in data.keys():
		for fr in data[aname].get("frames", []):
			for pname in fr["parts"].keys():
				var s := float(fr["parts"][pname]["s"])
				if not acc.has(pname):
					acc[pname] = [s, s]
				acc[pname][0] = minf(acc[pname][0], s)
				acc[pname][1] = maxf(acc[pname][1], s)
	var keys := acc.keys()
	keys.sort_custom(func(a, b): return (acc[a][1] - acc[a][0]) > (acc[b][1] - acc[b][0]))
	for k in keys:
		var lo: float = acc[k][0]
		var hi: float = acc[k][1]
		var flag := "  " if (hi - lo) < 0.15 and absf(1.0 - lo) < 0.2 else "<-"
		print("   %-12s %.2f ~ %.2f  %s" % [k, lo, hi, flag])


func _diagnose(scene: PackedScene, profile: DRPartProfile) -> void:
	var inst := scene.instantiate()
	root.add_child(inst)
	var skel := DRBaker._find_node(inst, "Skeleton3D") as Skeleton3D
	if skel == null:
		printerr("Skeleton3D 없음")
		return
	var ap := DRBaker._find_node(inst, "AnimationPlayer") as AnimationPlayer
	print("본 %d개, 애니메이션 %d개" % [
		skel.get_bone_count(),
		(ap.get_animation_list().size() if ap != null else 0)])
	if ap != null:
		print("AnimationPlayer 경로: ", inst.get_path_to(ap))
		print("라이브러리: ", ap.get_animation_library_list())
		var al := ap.get_animation_list()
		print("애니 이름 샘플: ", Array(al).slice(0, 6))
		print("has_animation(Idle_Loop) = ", ap.has_animation("Idle_Loop"))
	var groups := {}
	for bi in skel.get_bone_count():
		var bn := skel.get_bone_name(bi)
		var part := profile.part_for_bone(bn)
		if not groups.has(part):
			groups[part] = []
		groups[part].append(bn)
	var keys := groups.keys()
	keys.sort()
	for k in keys:
		var label: String = k if String(k) != "" else "(미매핑)"
		var lst: Array = groups[k]
		print("%-12s (%d) : %s" % [label, lst.size(),
			String(", ").join(PackedStringArray(lst.slice(0, 8)))
			+ (" ..." if lst.size() > 8 else "")])
	var mi := DRBaker._find_skinned_mesh(inst)
	if mi != null:
		print("스킨드 메쉬: ", mi.name, "  surfaces=", (mi.mesh as ArrayMesh).get_surface_count(),
			"  skin binds=", (mi.skin.get_bind_count() if mi.skin != null else 0))
