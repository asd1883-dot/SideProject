@tool
extends Resource
class_name DRPartProfile

## 본 이름 -> 파트 이름 매핑 규칙. 게임 종류(휴머노이드/차량/중장비)별로
## 프로필만 갈아끼우면 나머지 파이프라인은 그대로 동작한다.

@export var profile_name: String = "Humanoid"

## 순서대로 검사, 첫 매치 승리.
## { pattern: String(정규식), part: String, sided: bool, layer: String(선택), stretch: bool(선택, 기본 true),
##   stretch_limit: float(선택) }
## layer 가 있으면 그 파트는 애니메이션에서는 따로 움직이되,
## 그리기 순서 목록에서는 layer 파트의 줄에 묶인다(예: 발가락 → 발).
## stretch 가 false 면 그 파트는 늘이기(단축 보정) 없이 레스트 모양 그대로 회전만 한다(예: 분리 모드의 발가락).
## stretch_limit 이 있으면 그 파트의 늘이기를 1/limit ~ limit 로 묶는다(예: 발 1.15). 없으면 전체 제한(1.6).
## angle_fade 가 있으면 단축률이 그 값 아래일 때 부모 기준 회전을 레스트 쪽으로 눌러 각도 잡음을 막는다(손·발 0.45).
@export var rules: Array[Dictionary] = []

## 파트 렌더 순서(뒤 -> 앞)의 기본값. 실제 z는 3D 깊이로 덮어씀.
@export var default_order: PackedStringArray = PackedStringArray()

var _cache: Dictionary = {}
var _re: Array[RegEx] = []


static func humanoid(split_toes: bool = false) -> DRPartProfile:
	var p := DRPartProfile.new()
	p.profile_name = "Humanoid"
	# 발가락 — 기본은 발에 합친다. 도트 해상도에서 발가락은 2~4픽셀이라 따로 꺾으면
	# 1픽셀도 안 되게 꿈틀거리기만 해서 어설펐다(09-15 실측: 키의 70~80% 가 1px 미만 움직임,
	# 방향 전환 23키에 8~10회, 늘이기 0.62~1.6배로 튐). 발은 레스트 모양 그대로 한 장이고
	# 발목에서 회전만 한다(발 방향은 발 뼈에 고정된 점으로 재므로 발가락 뼈가 접혀도 안 따라감).
	# 발의 늘이기는 켜 둔다 — 끄면 레스트에서 카메라를 향해 짧게 찍힌 발이 걸을 때 못 길어져
	# 3D 대비 발 어긋남이 2배(09-15 Walk −55°: 켬 280px · 끔 405px). 발가락만 따로 꺾을 때는 끈다.
	# split_toes = true 면 예전처럼 발가락을 따로 꺾는다(그리기 순서 목록에서는 발 줄에 묶음).
	var toe_rule := {"pattern": "(ball|toe)", "part": "Foot", "sided": true}
	if split_toes:
		toe_rule = {"pattern": "(ball|toe)", "part": "Toe", "sided": true, "layer": "Foot", "stretch": false}
	p.rules = [
		{"pattern": "^(root|pelvis|hip)", "part": "Hips", "sided": false},
		{"pattern": "(spine|chest|torso)", "part": "Torso", "sided": false},
		{"pattern": "(clavicle|shoulder)", "part": "Torso", "sided": false},
		{"pattern": "(neck|head|jaw|eye)", "part": "Head", "sided": false},
		{"pattern": "(upperarm|upper_arm)", "part": "UpperArm", "sided": true},
		{"pattern": "(lowerarm|forearm|fore_arm)", "part": "Forearm", "sided": true},
		# 손·발처럼 짧은 끝 파트는 카메라를 향하면(단축률 낮음) 2D 각도가 잡음처럼 튄다 → angle_fade 아래에서는
		# 부모 기준 회전을 레스트 쪽으로 눌러 둔다(단축률 0 이면 회전 0, 0.45 이상이면 그대로).
		# little = Godot 표준 휴머노이드(SkeletonProfileHumanoid)의 새끼손가락 이름. 리타깃한 모델은 본 이름이 이 표준으로 바뀐다
		{"pattern": "(hand|index|middle|pinky|little|ring|thumb|finger)", "part": "Hand", "sided": true, "angle_fade": 0.45},
		{"pattern": "(thigh|upleg|up_leg|upperleg)", "part": "Thigh", "sided": true},
		{"pattern": "(calf|shin|lowerleg|^leg)", "part": "Calf", "sided": true},
		toe_rule,   # 발 규칙보다 먼저
		# 발은 늘이기를 ±15% 로 묶는다 — 팔다리처럼 1.6배까지 두면 50px 발이 걸음마다 부풀었다 줄어 지렁이처럼 보인다(09-16).
		# 3D 실루엣과는 조금 더 벌어지지만(발끝 몇 px) 2D 게임 발은 원래 안 늘어난다.
		{"pattern": "(foot|ankle)", "part": "Foot", "sided": true, "stretch_limit": 1.15, "angle_fade": 0.45},
		{"pattern": "(arm)", "part": "UpperArm", "sided": true},
	]
	p.default_order = PackedStringArray([
		"Hips", "Torso", "Head",
		"L_UpperArm", "L_Forearm", "L_Hand",
		"R_UpperArm", "R_Forearm", "R_Hand",
		"L_Thigh", "L_Calf", "L_Foot",
		"R_Thigh", "R_Calf", "R_Foot",
	])
	if split_toes:
		p.default_order.insert(p.default_order.find("L_Foot") + 1, "L_Toe")
		p.default_order.insert(p.default_order.find("R_Foot") + 1, "R_Toe")
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


## 파트가 속한 레이어(그리기 순서 목록의 한 줄). 규칙에 "layer" 가 있으면 그 이름,
## 없으면 파트 자신이 레이어다. 좌우 접두(L_/R_)는 파트 이름을 따른다.
func layer_for_part(part: String) -> String:
	var side := ""
	var base := part
	if part.begins_with("L_") or part.begins_with("R_"):
		side = part.substr(0, 2)
		base = part.substr(2)
	for r in rules:
		if String(r.get("part", "")) == base and String(r.get("layer", "")) != "":
			return side + String(r["layer"])
	return part


## 파트를 늘이기(단축 보정) 해도 되는지. 그 파트 이름의 규칙 중 하나라도 "stretch": false 면 false.
func stretch_for_part(part: String) -> bool:
	var base := part
	if part.begins_with("L_") or part.begins_with("R_"):
		base = part.substr(2)
	for r in rules:
		if String(r.get("part", "")) == base and r.has("stretch") and not bool(r["stretch"]):
			return false
	return true


## 파트별 늘이기 제한(1 보다 큰 배율). 규칙에 없으면 0 (= 전체 제한을 쓴다).
func stretch_limit_for_part(part: String) -> float:
	var base := part
	if part.begins_with("L_") or part.begins_with("R_"):
		base = part.substr(2)
	var lim := 0.0
	for r in rules:
		if String(r.get("part", "")) == base and r.has("stretch_limit"):
			var v := float(r["stretch_limit"])
			if v > 1.0 and (lim == 0.0 or v < lim):
				lim = v
	return lim


## 파트별 각도 안정화 문턱(단축률, 0~1). 규칙에 없으면 0 (= 안 함).
func angle_fade_for_part(part: String) -> float:
	var base := part
	if part.begins_with("L_") or part.begins_with("R_"):
		base = part.substr(2)
	for r in rules:
		if String(r.get("part", "")) == base and r.has("angle_fade"):
			return clampf(float(r["angle_fade"]), 0.0, 1.0)
	return 0.0


func clear_cache() -> void:
	_cache.clear()
	_re.clear()
