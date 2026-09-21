extends SceneTree

## 리타깃용 BoneMap(.tres) 을 만든다 — 뼈대 본 이름 ↔ Godot 표준 휴머노이드(SkeletonProfileHumanoid) 짝 맞춤 표.
## 에디터의 임포트 창(Skeleton3D → Retarget → Bone Map → 새 BoneMap)이 자동으로 짝지어 주는 것과 같은 결과물이고,
## 에디터 없이 되풀이해서 만들 수 있게 둔 것. 만든 파일은 임포트 창의 Bone Map 칸에서 `불러오기` 로 지정한다.
##
##   Godot.exe --headless --path <프로젝트> --script res://addons/dot_rigger/tools/make_bonemap_cli.gd -- \
##       --kind=mixamo --prefix=mixamorig9_ --out=res://source3d/bonemap_mixamo.tres
##   --kind=mixamo  Mixamo 뼈대. --prefix 는 파일마다 다를 수 있다(mixamorig_, mixamorig9_ …) — Mixamo 에서 고른 캐릭터에 따라 붙는 번호.
##                  FBX 안의 "mixamorig9:Hips" 는 Godot 가 읽으면 "mixamorig9_Hips" 가 된다.
##   --kind=ual     Quaternius Universal Animation Library(UE 식 이름: pelvis, upperarm_l …)

const FINGERS := {"Thumb": "thumb", "Index": "index", "Middle": "middle", "Ring": "ring", "Little": "pinky"}

var _args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			s = s.substr(2)
		var eq := s.find("=")
		if eq >= 0:
			_args[s.substr(0, eq)] = s.substr(eq + 1)
	var kind := String(_args.get("kind", "mixamo"))
	var prefix := String(_args.get("prefix", "mixamorig_" if kind == "mixamo" else ""))
	var out := String(_args.get("out", "res://source3d/bonemap_%s.tres" % kind))
	var map := _ual() if kind == "ual" else _mixamo()
	var bm := BoneMap.new()
	bm.profile = SkeletonProfileHumanoid.new()
	var n := 0
	for k in map.keys():
		if bm.profile.find_bone(StringName(k)) < 0:
			printerr("프로필에 없는 이름: ", k)
			continue
		bm.set_skeleton_bone_name(StringName(k), StringName(prefix + String(map[k])))
		n += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
	var err := ResourceSaver.save(bm, out)
	print("%s — %s, 접두사 '%s', 짝 %d개 / 표준 본 %d개, 저장 %s" % [out, kind, prefix, n, bm.profile.bone_size, "OK" if err == OK else str(err)])
	quit(0 if err == OK else 1)


func _ual() -> Dictionary:
	var m := {"Root": "root", "Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_02", "UpperChest": "spine_03",
		"Neck": "neck_01", "Head": "Head"}
	for side in [["Left", "l"], ["Right", "r"]]:
		var S: String = side[0]
		var s: String = side[1]
		m[S + "Shoulder"] = "clavicle_" + s
		m[S + "UpperArm"] = "upperarm_" + s
		m[S + "LowerArm"] = "lowerarm_" + s
		m[S + "Hand"] = "hand_" + s
		m[S + "UpperLeg"] = "thigh_" + s
		m[S + "LowerLeg"] = "calf_" + s
		m[S + "Foot"] = "foot_" + s
		m[S + "Toes"] = "ball_" + s
		for f in FINGERS.keys():
			var segs := _segs(f)
			for i in 3:
				m[S + f + segs[i]] = "%s_0%d_%s" % [FINGERS[f], i + 1, s]
	return m


func _mixamo() -> Dictionary:
	var m := {"Hips": "Hips", "Spine": "Spine", "Chest": "Spine1", "UpperChest": "Spine2", "Neck": "Neck", "Head": "Head"}
	for S in ["Left", "Right"]:
		m[S + "Shoulder"] = S + "Shoulder"
		m[S + "UpperArm"] = S + "Arm"
		m[S + "LowerArm"] = S + "ForeArm"
		m[S + "Hand"] = S + "Hand"
		m[S + "UpperLeg"] = S + "UpLeg"
		m[S + "LowerLeg"] = S + "Leg"
		m[S + "Foot"] = S + "Foot"
		m[S + "Toes"] = S + "ToeBase"
		for f in FINGERS.keys():
			var segs := _segs(f)
			var mf: String = "Pinky" if f == "Little" else f
			for i in 3:
				m[S + f + segs[i]] = "%sHand%s%d" % [S, mf, i + 1]
	return m


func _segs(finger: String) -> Array:
	return ["Metacarpal", "Proximal", "Distal"] if finger == "Thumb" else ["Proximal", "Intermediate", "Distal"]
