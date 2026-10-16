@tool
extends DRMotionTable
class_name MotionTable

## 동작 표 — "어느 상태일 때 어느 동작을 재생하나".  (보병_추상화.md §2-5 · §2-11)
##
## 10-16 부터 상태마다 동작을 **여러 개 · 비중(%)** 으로 둔다(DRMotionTable). 인스펙터에서 이 파일을 열면 상태별 편집 화면이 나온다
## (Dot Rigger 의 ui/motion_table_editor.gd): 동작 고르기 · 비중 % · 상하체 합성(하체 + 상체) · 3D 동작 내보내기.
##   피격: Idle_Hit 50 % · Hit_Chest 50 %  → 맞을 때마다 둘 중 하나
##   앉기+사격: 합성(하체 Crouch_Idle + 상체 Firing_Rifle)
##
## 상태 이름 = 바탕(서기 · 걷기 · 달리기 · 앉기 · 앉아걷기 · 엎드림 · 포복) [+ 행동(조준 · 사격 · 장전 · 투척 · 근접)]
##            또는 덮어쓰기(피격 · 제압 · 패닉 · 사망) [+ 자세(앉기 · 엎드림)].  쓸 수 있는 이름 전부 = all_keys()
## 표에 없는 조합은 덜 구체적인 것으로 내려간다: "걷기+사격" → "서기+사격" → "걷기" → "달리기" → 기본 동작.
## 이동은 아직 없는 동작을 대신한다: 걷기 → 달리기(느리게) · 앉아걷기 → 앉기 → 걷기 · 포복 → 엎드림.
## 덮어쓰기는 자세를 따진다 — 엎드린 병사가 서기용 동작을 쓰면 벌떡 일어섰다 쓰러지기 때문:
##   사망: 서기 "사망" · 앉기 "사망+앉기" → "사망" · 엎드림 "사망+엎드림"(없으면 엎드린 채 멈춤)
##   피격: 서기 "피격" · 앉기 "피격+앉기" → "앉기" · 엎드림 "피격+엎드림" → "엎드림"
##   제압: "제압+자세" → "제압" → 자세
## (내려가는 순서를 만드는 곳 = game/view/battle_view.gd 의 _candidates · _death_keys)

const BASES := ["서기", "걷기", "달리기", "앉기", "앉아걷기", "엎드림", "포복"]
const ACTIONS := ["조준", "사격", "장전", "투척", "근접"]
const OVERRIDES := ["피격", "제압", "패닉", "사망"]

## 예전 표(10-15 까지: 상태 → 동작 이름 하나). 예전 파일을 불러오면 줄(clips)로 옮기고 비운다 — 인스펙터에는 안 보인다.
## "A+B" 이름은 상하체 합성(하체 A + 상체 B, 합성 기본 설정 = 프리셋 첫 합성과 같은 길이 맞춤 2 · 반복 · 상체 방향 유지 1)으로 옮긴다
@export_storage var motions: Dictionary[String, String] = {}:
	set(v):
		if not v.is_empty():
			_migrate_legacy(v)
		motions = {}


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


## 인스펙터가 보여 줄 상태 — 쓸 수 있는 이름 전부(순서대로) + 줄에만 있는 이름(오타 등 — 인스펙터가 경고)
func state_names() -> PackedStringArray:
	var out := all_keys()
	for c in clips:
		if c != null and not out.has(c.state):
			out.append(c.state)
	return out


## 예전 이름(10-15 까지) — pick 과 같다
func find(candidates: PackedStringArray, available: PackedStringArray) -> String:
	return pick(candidates, available)


func _migrate_legacy(old: Dictionary) -> void:
	for key in old.keys():
		var st := String(key)
		var m := String(old[key])
		if m == "" or not clips_of(st).is_empty():
			continue
		var c := DRMotionClip.new()
		c.state = st
		var plus := m.find("+")
		if plus > 0 and plus < m.length() - 1:
			c.lower = m.substr(0, plus)
			c.upper = m.substr(plus + 1)
		else:
			c.anim = m
		clips.append(c)
	emit_changed()
