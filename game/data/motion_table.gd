extends Resource
class_name MotionTable

## 동작 표 — "어느 상태일 때 어느 동작(퍼펫 애니)을 재생하나".  (보병_추상화.md §2-5 · §2-11)
##
## 키 = 상태 이름, 값 = 퍼펫 동작 이름. 인스펙터에서 줄을 더하거나 값만 바꾸면 된다(코드는 그대로).
##   "달리기": "Sprint"
##   "앉기+사격": "Crouch_Idle+Firing_Rifle"
##
## 상태 이름 = 바탕(서기 · 걷기 · 달리기 · 앉기 · 엎드림 · 포복) [+ 행동(조준 · 사격 · 장전 · 투척 · 근접)]
##            또는 덮어쓰기(피격 · 제압 · 패닉 · 사망).  쓸 수 있는 이름 전부 = all_keys()
## 표에 없는 조합은 덜 구체적인 것으로 내려간다: "걷기+사격" → "서기+사격" → "걷기" → 기본 동작.

const BASES := ["서기", "걷기", "달리기", "앉기", "엎드림", "포복"]
const ACTIONS := ["조준", "사격", "장전", "투척", "근접"]
const OVERRIDES := ["피격", "제압", "패닉", "사망"]

## 상태 이름 → 퍼펫 동작 이름
@export var motions: Dictionary[String, String] = {}
## 어디에도 안 걸릴 때 재생할 동작(비우면 지금 동작을 그대로 둔다)
@export var default_motion := ""


## 표에 쓸 수 있는 상태 이름 전부(인스펙터 · 검사용)
static func all_keys() -> PackedStringArray:
	var out := PackedStringArray()
	for b in BASES:
		out.append(b)
		for a in ACTIONS:
			out.append("%s+%s" % [b, a])
	for o in OVERRIDES:
		out.append(o)
		for st in ["앉기", "엎드림"]:
			out.append("%s+%s" % [o, st])
	return out


## 후보 이름들(구체적인 것부터) 가운데, 표에 있고 그 동작이 퍼펫에 실제로 있는 첫 번째를 돌려준다. 없으면 "".
## available = 퍼펫이 가진 동작 이름들(DRPuppetSet.get_animations())
func find(candidates: PackedStringArray, available: PackedStringArray) -> String:
	for key in candidates:
		var m := String(motions.get(key, ""))
		if m != "" and available.has(m):
			return m
	if default_motion != "" and available.has(default_motion):
		return default_motion
	return ""


## 표에 적혀 있는데 퍼펫에 없는 동작들(= 더 구워야 하는 것). {상태 이름: 동작 이름}
func missing(available: PackedStringArray) -> Dictionary:
	var out := {}
	for key in motions.keys():
		var m := String(motions[key])
		if m != "" and not available.has(m):
			out[key] = m
	return out
