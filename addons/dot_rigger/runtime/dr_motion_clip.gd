@tool
extends Resource
class_name DRMotionClip

## 동작 표의 한 줄(10-16) — "이 상태일 때 이 동작을 이만큼의 비중으로".
## 같은 상태에 줄이 여럿이면 비중대로 하나를 골라 튼다(예: 피격 = hit_1 · hit_2 · hit_3 을 20 · 40 · 40 %).
## 상하체 합성이면 lower(하체) + upper(상체)를 3D 동작 내보내기 때 한 동작으로 굽는다 — 2D 굽기의 합성과 같은 처리
## (DRBaker._make_composite: 길이 맞춤 · 상체 방향 유지 · 몸통 각도). 실행 중에는 구운 동작을 틀기만 해서 섞는 연산이 없다.
## 인스펙터에서 고치는 화면 = ui/motion_table_editor.gd(DRMotionTable 을 열면 나온다).

## 합성 길이 맞춤(DRBaker.LEN_*) 이름 — 인스펙터 목록
const LEN_NAMES := ["하체 시간 · 하체 반복", "하체 시간 · 하체 1번", "상체 시간 · 하체 반복", "상체 시간 · 하체 1번"]

## 상태 이름(동작 표의 키 — 예: "서기", "앉기+사격", "피격+엎드림")
@export var state := ""
## 동작 이름(합성이 아닐 때). 3D 동작 묶음 · 2D 퍼펫의 동작 이름과 같다
@export var anim := ""
## 같은 상태 안에서의 비중(%) — 인스펙터는 같은 상태의 줄들이 합쳐 100 이 되게 맞춘다
@export_range(0.0, 100.0, 0.1, "suffix:%") var weight := 100.0

@export_group("상하체 합성")
## 하체 동작(골반 · 다리) — 하체 · 상체가 둘 다 있으면 합성
@export var lower := ""
## 상체 동작(몸통 · 머리 · 팔)
@export var upper := ""
## 합성 동작 이름(비우면 "하체+상체")
@export var composite_name := ""
@export_enum("하체 시간 · 하체 반복", "하체 시간 · 하체 1번", "상체 시간 · 하체 반복", "상체 시간 · 하체 1번") var length_mode := 2
@export var loop := true
## 상체 방향 유지(0 ~ 1) — 1 이면 골반이 숙어도 몸통이 상체 동작에서와 같은 쪽을 본다(앉아 쏘기 등)
@export_range(0.0, 1.0, 0.05) var upper_keep := 1.0
## 몸통 각도 보정(도, + = 뒤로 젖힘)
@export_range(-90.0, 90.0, 0.5, "suffix:°") var upper_pitch := 0.0


func is_composite() -> bool:
	return lower != "" and upper != ""


## 재생할 동작 이름 — 합성이면 합성 이름(비면 "하체+상체" — DRBaker.composite_name 과 같은 규칙)
func play_name() -> String:
	if is_composite():
		return DRBaker.composite_name(composite_def())
	return anim


## DRBaker 합성 정의(내보내기가 그대로 넘긴다)
func composite_def() -> Dictionary:
	return {"name": composite_name, "lower": lower, "upper": upper, "length_mode": length_mode, "loop": loop,
		"upper_keep": upper_keep, "upper_pitch": upper_pitch}


## 인스펙터의 되돌리기(스냅숏)용
func to_dict() -> Dictionary:
	return {"state": state, "anim": anim, "weight": weight, "lower": lower, "upper": upper, "composite_name": composite_name,
		"length_mode": length_mode, "loop": loop, "upper_keep": upper_keep, "upper_pitch": upper_pitch}


static func from_dict(d: Dictionary) -> DRMotionClip:
	var c := DRMotionClip.new()
	c.state = String(d.get("state", ""))
	c.anim = String(d.get("anim", ""))
	c.weight = float(d.get("weight", 100.0))
	c.lower = String(d.get("lower", ""))
	c.upper = String(d.get("upper", ""))
	c.composite_name = String(d.get("composite_name", ""))
	c.length_mode = int(d.get("length_mode", 2))
	c.loop = bool(d.get("loop", true))
	c.upper_keep = float(d.get("upper_keep", 1.0))
	c.upper_pitch = float(d.get("upper_pitch", 0.0))
	return c
