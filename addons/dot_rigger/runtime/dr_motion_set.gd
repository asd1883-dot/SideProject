@tool
extends Resource
class_name DRMotionSet

## 동작 표의 세트(10-16) — 상태 이름 묶음. 자세별(서기 · 앉기 · 엎드림)이 기본이고, 장비가 생기면 "설치 · 조작" 같은 묶음을 더 만든다.
## 정리용이다 — 게임이 동작을 고를 때는 상태 이름만 본다(어느 세트에 있든 같은 상태면 같은 줄). 인스펙터 · Dot Rigger ① 유닛 탭이 세트별로 보여 준다.

@export var name := ""
## 이 세트에 든 상태 이름(보이는 순서)
@export var states: PackedStringArray = PackedStringArray()


static func make(set_name: String, state_names: PackedStringArray) -> DRMotionSet:
	var s := DRMotionSet.new()
	s.name = set_name
	s.states = state_names
	return s


func to_dict() -> Dictionary:
	return {"name": name, "states": Array(states)}


static func from_dict(d: Dictionary) -> DRMotionSet:
	return make(String(d.get("name", "")), PackedStringArray(d.get("states", [])))
