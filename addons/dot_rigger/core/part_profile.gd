@tool
extends Resource
class_name DRPartProfile

## 본 이름 -> 파트 이름 매핑 규칙. 게임 종류(휴머노이드/차량/중장비)별로
## 프로필만 갈아끼우면 나머지 파이프라인은 그대로 동작한다.

@export var profile_name: String = "Humanoid"

## 순서대로 검사, 첫 매치 승리.
## { pattern: String(정규식), part: String, sided: bool }
@export var rules: Array[Dictionary] = []

## 파트 렌더 순서(뒤 -> 앞)의 기본값. 실제 z는 3D 깊이로 덮어씀.
@export var default_order: PackedStringArray = PackedStringArray()

var _cache: Dictionary = {}
var _re: Array[RegEx] = []


static func humanoid() -> DRPartProfile:
	var p := DRPartProfile.new()
	p.profile_name = "Humanoid"
	p.rules = [
		{"pattern": "^(root|pelvis|hip)", "part": "Hips", "sided": false},
		{"pattern": "(spine|chest|torso)", "part": "Torso", "sided": false},
		{"pattern": "(clavicle|shoulder)", "part": "Torso", "sided": false},
		{"pattern": "(neck|head|jaw|eye)", "part": "Head", "sided": false},
		{"pattern": "(upperarm|upper_arm)", "part": "UpperArm", "sided": true},
		{"pattern": "(lowerarm|forearm|fore_arm)", "part": "Forearm", "sided": true},
		{"pattern": "(hand|index|middle|pinky|ring|thumb|finger)", "part": "Hand", "sided": true},
		{"pattern": "(thigh|upleg|up_leg|upperleg)", "part": "Thigh", "sided": true},
		{"pattern": "(calf|shin|lowerleg|^leg)", "part": "Calf", "sided": true},
		{"pattern": "(foot|ball|toe|ankle)", "part": "Foot", "sided": true},
		{"pattern": "(arm)", "part": "UpperArm", "sided": true},
	]
	p.default_order = PackedStringArray([
		"Hips", "Torso", "Head",
		"L_UpperArm", "L_Forearm", "L_Hand",
		"R_UpperArm", "R_Forearm", "R_Hand",
		"L_Thigh", "L_Calf", "L_Foot",
		"R_Thigh", "R_Calf", "R_Foot",
	])
	return p


func _compile() -> void:
	if _re.size() == rules.size():
		return
	_re.clear()
	for r in rules:
		var rx := RegEx.new()
		rx.compile(String(r.get("pattern", "")))
		_re.append(rx)


## "mixamorig:LeftForeArm" -> {side="L", core="forearm"}
static func normalize(bone_name: String) -> Dictionary:
	var n := bone_name
	if n.contains(":"):
		n = n.split(":")[-1]
	n = n.to_lower()
	var side := ""
	# 접두사
	if n.begins_with("left"):
		side = "L"; n = n.substr(4)
	elif n.begins_with("right"):
		side = "R"; n = n.substr(5)
	elif n.begins_with("l_"):
		side = "L"; n = n.substr(2)
	elif n.begins_with("r_"):
		side = "R"; n = n.substr(2)
	# 접미사
	elif n.ends_with("_l") or n.ends_with(".l"):
		side = "L"; n = n.substr(0, n.length() - 2)
	elif n.ends_with("_r") or n.ends_with(".r"):
		side = "R"; n = n.substr(0, n.length() - 2)
	n = n.strip_edges().lstrip("_.-").rstrip("_.-")
	return {"side": side, "core": n}


## 매칭 실패 시 "" 반환(= 이 본은 어느 파트에도 속하지 않음)
func part_for_bone(bone_name: String) -> String:
	if _cache.has(bone_name):
		return _cache[bone_name]
	_compile()
	var nz := normalize(bone_name)
	var core := String(nz["core"])
	var side := String(nz["side"])
	var result := ""
	for i in rules.size():
		if _re[i].search(core) != null:
			var base := String(rules[i].get("part", ""))
			var sided := bool(rules[i].get("sided", false))
			result = (side + "_" + base) if (sided and side != "") else base
			break
	_cache[bone_name] = result
	return result


func clear_cache() -> void:
	_cache.clear()
	_re.clear()
