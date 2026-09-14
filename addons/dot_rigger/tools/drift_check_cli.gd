extends SceneTree

## 포즈 고정 검사.
## set_pose() 로 자세를 잡은 뒤 프레임이 흘러도 그 자세가 그대로여야 한다.
## AnimationPlayer 가 계속 재생 중이면 파트를 한 장씩 찍는 사이에 자세가 흘러
## 15장이 서로 어긋난 스프라이트가 나온다.

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

	baker.set_rest_pose()
	await RenderingServer.frame_post_draw
	var skel := baker.skeleton
	var probe := skel.find_bone("hand_l")
	if probe < 0:
		probe = 0
	var t0 := skel.get_bone_global_pose(probe)
	var ap := baker.anim_player
	print("재생 상태: is_playing=%s  current=%s  pos=%.3f"
		% [ap.is_playing(), ap.current_animation, ap.current_animation_position])

	# 파트 15장을 찍는 것과 같은 만큼 프레임을 흘려보낸다
	for i in 30:
		await RenderingServer.frame_post_draw
	var t1 := skel.get_bone_global_pose(probe)
	var moved := (t1.origin - t0.origin).length()
	print("30프레임 후 재생위치=%.3f, 본 이동량=%.6f" % [ap.current_animation_position, moved])

	# 실제로 파트를 두 번 찍어 같은 그림이 나오는지
	var a: Image = await baker.render_part("Head")
	for i in 20:
		await RenderingServer.frame_post_draw
	var b: Image = await baker.render_part("Head")
	var diff := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				diff += 1
	print("같은 파트를 시간차로 두 번 렌더 → 다른 픽셀 %d개" % diff)

	# 고정은 됐는데 "엉뚱한 자세로 고정"된 건 아닌지 확인한다.
	# stop() 은 마지막 자세를 그대로 남기므로 바인드 포즈 기준으로는 비교가 안 된다.
	# 대신 서로 확실히 다른 두 자세를 세워 보고 실제로 달라지는지를 본다.
	var poses := [["Idle", 0.0], ["Idle", 0.5], ["A_TPose", 0.0]]
	var shots := []
	for p in poses:
		baker.set_pose(String(p[0]), float(p[1]))
		await RenderingServer.frame_post_draw
		shots.append({
			"name": "%s@%.0f%%" % [p[0], float(p[1]) * 100.0],
			"img": await baker.render_all_parts_composite(),
			"bone": skel.get_bone_global_pose(probe).origin,
		})
	var ok := true
	for i in shots.size():
		for j in range(i + 1, shots.size()):
			var d := 0
			var ia: Image = shots[i]["img"]
			var ib: Image = shots[j]["img"]
			for y in ia.get_height():
				for x in ia.get_width():
					if ia.get_pixel(x, y) != ib.get_pixel(x, y):
						d += 1
			var bd: float = (Vector3(shots[i]["bone"]) - Vector3(shots[j]["bone"])).length()
			print("  %-12s vs %-12s : 본 거리 %.4f, 다른 픽셀 %d개"
				% [shots[i]["name"], shots[j]["name"], bd, d])
			if d == 0:
				ok = false
	if not ok:
		printerr("서로 다른 자세인데 결과가 같습니다 — 자세가 적용되지 않음")
		quit(1); return

	if moved > 0.0005 or diff > 0:
		printerr("포즈가 고정되지 않습니다 (본 이동 %.6f, 픽셀차 %d)" % [moved, diff])
		quit(1)
	else:
		print("포즈 고정 OK")
		quit(0)
