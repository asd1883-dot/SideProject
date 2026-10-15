extends SceneTree

## 부위 칠하기(<모델>.parts.json)의 관절 자르기(kind = "joint") 평면을 지금 기준 몸의 관절 자리로 다시 계산한다(10-15).
## 관절 자르기는 칠할 때의 관절 자리로 평면 좌표를 저장해 두므로, 리깅으로 관절을 옮기면(rerig_arms.py) 예전 자리에 남는다.
## 저장된 offset · tilt · h(상자 반 크기)는 그대로 두고 평면만 바꾼다. 직선 자르기(kind = "line") · 칠한 점은 그대로.
##
##   godot --headless --path . --script res://addons/dot_rigger/tools/recut_joints_cli.gd -- \
##       <기준 몸 씬 res://…glb> <입력 parts.json(절대 경로)> <출력 parts.json(절대 경로)> [입력 출력 …]
## 옷의 칠하기도 기준 몸 관절로(③ 창이 관절 자르기를 기본 몸 관절로 만들어 둘 다에 넣는다). 줄마다 평면 이동 거리 · 방향 변화를 찍는다.
func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() < 3:
		print("쓰는 법: -- <기준 몸 씬> <입력 parts.json> <출력 parts.json> [입력 출력 …]")
		quit(1)
		return
	var opts := DRBaker.Options.new()
	opts.view_size = Vector2i(32, 32)
	var b := DRBaker.new()
	if not b.setup(root, load(a[0]) as PackedScene, DRPartProfile.humanoid(false), opts):
		print("RECUT FAIL 기준 몸을 불러오지 못했습니다: ", a[0])
		quit(1)
		return
	var joints := {}
	for j in DRMeshCutter.joint_list(b.split, b.source_mesh_instance, b.skeleton):
		joints[String(j["key"])] = j
	var i := 1
	while i + 1 < a.size():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(a[i]))
		if not (d is Dictionary):
			print("RECUT FAIL 읽을 수 없음: ", a[i])
			quit(1)
			return
		for c in (d as Dictionary).get("cuts", []):
			var cd := c as Dictionary
			if String(cd.get("kind", "")) != "joint":
				continue
			var key := String(cd.get("joint", ""))
			if not joints.has(key):
				print("RECUT 관절 없음 ", key)
				continue
			var j: Dictionary = joints[key]
			var old_pl: Array = cd["planes"][0]
			var np: Array = DRMeshCutter.joint_planes(j["c"], j["d"], float(cd.get("offset", 0.0)), float(cd.get("tilt", 0.0)), float(cd.get("h", 0.1)))
			var n_old := Vector3(old_pl[0], old_pl[1], old_pl[2])
			var q: Vector3 = (j["c"] as Vector3) + (j["d"] as Vector3) * float(cd.get("offset", 0.0))
			print("RECUT %-11s 평면 이동 %.1f cm · 방향 %.1f°" % [key, absf(n_old.dot(q) - float(old_pl[3])) * 100.0,
				rad_to_deg(n_old.angle_to(Vector3(np[0][0], np[0][1], np[0][2])))])
			cd["planes"] = np
		var f := FileAccess.open(a[i + 1], FileAccess.WRITE)
		f.store_string(JSON.stringify(d))
		f.close()
		print("RECUT saved ", a[i + 1])
		i += 2
	quit()
