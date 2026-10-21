extends RefCounted
class_name BattleEquipment

## 운용 장비 기록 — 병사와 따로인 장비(MG42 라페테 …). 노드가 아니다. 전장 관리자(Battlefield)가 배열로 들고 있다.  (보병_추상화.md §2-13)
## 좌석마다 앉은 병사(없으면 null). 탄 · 연사 · 퍼짐은 장비의 것이다(앉은 병사의 소총 탄과 따로).
##   운반 → (분대가 자리 잡음 · 교전) → 설치 중 → 준비 → (분대가 다른 곳으로 감) → 해체 중 → 운반
##   운반병이 쓰러지면 그 자리에 놓인다. 운용하던 분대가 없어지면(전멸 · 패주) 버려진 장비 — 아무 분대(적 포함)나 와서 다시 운용한다.
## 좌석 채우기 · 설치 판단은 장비 두뇌(CrewBrain), 시간 흐름(설치 · 해체 · 운반 자리)은 Battlefield._update_equipment.

enum State { CARRIED, SETUP, READY, TEARDOWN, DROPPED }
const STATE_NAMES := ["운반", "설치 중", "준비", "해체 중", "놓임"]
const SEAT_ARRIVE_M := 0.3          # 좌석 자리에 이만큼 가까우면 앉은 것
const SEAT_DEPTH_TOL := 0.06

var id := 0
var type: EquipmentType
## 지금(버려졌으면 마지막으로) 운용한 편
var team := 0
## 운용하는 분대 — null 이면 버려진 장비
var squad: BattleSquad = null
var x := 0.0
var depth := 0.5
## 총구 방향(+1 = 오른쪽 · −1 = 왼쪽)
var facing := 1
var state := State.CARRIED
var timer := 0.0                    # 설치 · 해체 남은 시간
## 들고 있는 병사(운반) — 놓인 장비를 주우러 가는 병사도 여기(그 병사의 carrying 은 주운 뒤에야 채워진다)
var carrier: BattleSoldier = null
## 설치한 자리의 엄폐물 — 있으면 좌석 병사가 그 엄폐를 받는다
var cover: BattleCover = null
var seats: Array[BattleSoldier] = []
## 좌석이 병사에게 붙이는 수정자의 꼬리표(효율 · 빈 좌석)
var mod_tag := ""

# ── 장비의 무기 상태 — 사격 좌석의 병사가 쏜다 ──
var ammo := 0
var fire_cooldown := 0.0
var bloom_deg := 0.0
var burst_count := 0                # 이번 점사에서 쏜 발 수
var reloader: BattleSoldier = null  # 지금 장전하는 병사(장전 중엔 못 쏜다)


func setup_seats() -> void:
	seats.resize(type.seats.size())
	for i in seats.size():
		seats[i] = null


## 좌석 i 의 자리(x m · 깊이) — 총구 방향 기준 앞뒤
func seat_x(i: int) -> float:
	return x + float(facing) * type.seats[i].offset.x


func seat_depth(i: int) -> float:
	return clampf(depth + type.seats[i].offset.y, 0.02, 0.98)


## 그 병사가 이 장비의 좌석 자리에 와 있나
func at_seat(s: BattleSoldier) -> bool:
	if s == null or s.seat_eq != self or s.seat_idx < 0:
		return false
	return absf(s.x - seat_x(s.seat_idx)) <= SEAT_ARRIVE_M and absf(s.depth - seat_depth(s.seat_idx)) <= SEAT_DEPTH_TOL


## 첫 좌석(사수)의 병사가 자리에 있나 — 설치 · 해체 시간은 이때만 흐른다
func gunner_in_place() -> bool:
	return not seats.is_empty() and at_seat(seats[0])


## 장전 담당 좌석에 (except 말고) 앉은 병사가 있나
func loader_present(except: BattleSoldier = null) -> bool:
	for i in seats.size():
		if type.seats[i].loader and seats[i] != null and seats[i] != except:
			return true
	return false


func is_abandoned() -> bool:
	return squad == null


## 총구 자리(x m) — 장비 사격의 총알이 나가는 곳
func muzzle_x() -> float:
	return x + float(facing) * type.muzzle_ahead_m


func mag_size() -> int:
	return type.weapon.mag_size if type.weapon != null else 0


## 확인용 한 줄
func describe() -> String:
	var crew := PackedStringArray()
	for i in seats.size():
		crew.append("%s %s" % [type.seats[i].role, ("#%d" % seats[i].id) if seats[i] != null else "빈 자리"])
	var st: String = STATE_NAMES[state]
	if state == State.SETUP or state == State.TEARDOWN:
		st += " %.1f초" % maxf(timer, 0.0)
	return "%s #%d  %s%s · 탄 %d/%d · %s" % [type.display_name, id, st, " · 버려짐" if squad == null else "", ammo, mag_size(), " · ".join(crew)]
