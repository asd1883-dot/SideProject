extends RefCounted
class_name BattleSquad

## 분대 기록 — 판단 단위.  분대 두뇌(SquadBrain)가 태세 · 목표 지점 · 엄폐 · 자리를 정하고 병사는 실행한다.  (보병_추상화.md §2-7)
## 사기는 분대의 것, 제압은 병사의 것(§2-8).

## 태세 — 분대 두뇌가 점수로 고른다
enum Posture { ADVANCE, HOLD, RETREAT, CHARGE }
## 지휘 명령 — 강제가 아니라 점수의 가중치
enum Order { NONE, ADVANCE, HOLD, RETREAT }

const POSTURE_NAMES := ["전진", "유지", "후퇴", "돌격"]
const ORDER_NAMES := ["없음", "전진", "정지", "후퇴"]

var id := 0
var team := 0
var type: SoldierType
## 투입 때의 구성원 전부(죽은 병사 포함 — 고정 분대)
var members: Array[BattleSoldier] = []

var order := Order.ADVANCE
var posture := Posture.ADVANCE
var morale := 0.8               # 0 ~ 1
var routed := false             # 패주 — 분대 덮어쓰기(두뇌보다 위)

## 분대가 운용하는 장비(§2-13 — MG42 팀의 MG42 · 주운 버려진 장비)
var equipment: Array[BattleEquipment] = []
## 분대가 적을 보는 거리 — 투입할 때 구성원 무기 · 장비 무기의 가장 긴 사거리(병종 하나면 그 무기 사거리)
var range_m := 0.0

var cover: BattleCover = null   # 예약한 엄폐물
var goal_x := 0.0               # 목표 지점(m)
var brain_timer := 0.0
var scores: Dictionary = {}     # 디버그: 태세별 점수


## 분대가 지금 부릴 수 있는 병사(살아 있고 · 패닉 아니고 · 빙의로 빠지지 않은)
func active() -> Array[BattleSoldier]:
	var out: Array[BattleSoldier] = []
	for s in members:
		if s.can_fight() and not s.detached:
			out.append(s)
	return out


## 부릴 수 있는 병사가 한 명이라도 있나(배열을 만들지 않는다 — 매 걸음 부르는 곳용)
func has_active() -> bool:
	for s in members:
		if s.can_fight() and not s.detached:
			return true
	return false


## 분대의 자리 = 부릴 수 있는 병사들의 x 평균
func anchor_x() -> float:
	var act := active()
	if act.is_empty():
		return goal_x
	var sum := 0.0
	for s in act:
		sum += s.x
	return sum / float(act.size())


func avg_suppression() -> float:
	var act := active()
	if act.is_empty():
		return 0.0
	var sum := 0.0
	for s in act:
		sum += minf(s.suppression, 1.0)
	return sum / float(act.size())
