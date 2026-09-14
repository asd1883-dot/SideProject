extends SceneTree

## 파트의 "루트 본" 이 실제로 쓸모 있는 본인지 검사한다.
## UE/Mixamo 계열 리그는 맨 위에 'root' 같은 기준점 본이 있는데,
## 이 본은 (a) 정점 웨이트가 없고 (b) 제자리 애니메이션에서 움직이지 않는다.
## 이걸 파트의 루트로 잡으면 피벗이 발바닥에 찍히고 자세도 고정돼 버린다.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load("res://models/UAL1.glb") as PackedScene
	var opts := DRBaker.Options.new()
	opts.view_size = Vector2i(192, 192)
	opts.yaw = 90.0
	opts.rest_anim = "Idle"
	var baker := DRBaker.new()
	if not baker.setup(root, scene, DRPartProfile.humanoid(), opts):
		printerr("setup 실패"); quit(1); return
	var skel := baker.skeleton

	# 1) 어떤 본이 실제로 정점을 지배하는가
	var mi := DRBaker._find_skinned_mesh(baker.model_root)
	var weighted := {}
	if mi != null:
		var binds := DRMeshSplitter._bind_map(mi, skel)
		var am := mi.mesh as ArrayMesh
		for si in am.get_surface_count():
			var arr := am.surface_get_arrays(si)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			if verts.is_empty() or bones.is_empty():
				continue
			var bpv := int(bones.size() / float(verts.size()))
			for v in verts.size():
				var bw := -1.0
				var bb := -1
				for k in bpv:
					if wts[v * bpv + k] > bw:
						bw = wts[v * bpv + k]
						bb = bones[v * bpv + k]
				if bb >= 0 and bb < binds.size():
					weighted[binds[bb]] = true

	# 2) 각 파트의 루트 본이 애니메이션에서 움직이는가
	print("%-12s %-14s %-8s %s" % ["파트", "루트 본", "웨이트", "Jog 중 이동량"])
	var problems: Array = []
	for pname in baker.rig.order:
		var p: DRRigModel.Part = baker.rig.parts[pname]
		var bn := skel.get_bone_name(p.root_bone)
		baker.set_pose("Jog_Fwd", 0.0)
		await RenderingServer.frame_post_draw
		var t0 := skel.get_bone_global_pose(p.root_bone)
		var move := 0.0
		var rot := 0.0
		for f in 6:
			baker.set_pose("Jog_Fwd", float(f) / 6.0 * 0.9)
			await RenderingServer.frame_post_draw
			var t1 := skel.get_bone_global_pose(p.root_bone)
			move = maxf(move, (t1.origin - t0.origin).length())
			rot = maxf(rot, absf(t1.basis.get_euler().length() - t0.basis.get_euler().length()))
		var has_w := weighted.has(p.root_bone)
		var flag := ""
		if not has_w or (move < 0.001 and rot < 0.001):
			flag = "  <-- 문제"
			problems.append(pname)
		print("%-12s %-14s %-8s %.4f (회전 %.4f)%s"
			% [pname, bn, "있음" if has_w else "없음", move, rot, flag])

	if problems.size() > 0:
		printerr("\n루트 본이 부적절한 파트: %s" % String(", ").join(PackedStringArray(problems)))
		quit(1)
	else:
		print("\n모든 파트의 루트 본 정상")
		quit(0)
