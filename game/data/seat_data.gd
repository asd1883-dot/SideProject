extends Resource
class_name SeatData

## 좌석 — 운용 장비(EquipmentType)의 자리 하나(사수 · 부사수 · 탄약수 …).  (보병_추상화.md §2-13, 안건 F)
## 병사가 이 좌석에 앉으면 병종의 능력 대신 **이 좌석의 능력**을 쓴다. 효율(숙련도)은 이 좌석이 맡는 수치(governs)에만 붙는다.
## 좌석 순서 = 우선순위: 앞 좌석이 비면 뒤 좌석의 병사가 올라가고, 빈 뒤 좌석은 분대의 다른 병사가 채운다.

@export var role := "사수"
## 앉은 병사가 쓰는 능력(병종의 능력 목록을 대신한다) — 예: 사수 = [장비 사격, 대신 장전] · 부사수 = [장비 장전]
@export var abilities: Array[Ability] = []
## 이 좌석이 맡는 수치(StatMod 의 수치 이름) — 효율이 이 수치에만 붙는다. 예: 사수 = 퍼짐 · 조준 시간 · 선회, 부사수 = 장전 시간
@export var governs: Array[StringName] = []
## 장전 담당 — 장전 담당 좌석이 모두 비면 "대신 장전" 능력을 가진 병사의 장전 시간이 장비의 `빈 장전 좌석 곱`만큼 길어진다
@export var loader := false
## 앉는 자리 — x = 총구 방향 기준 앞(+) / 뒤(−) m · y = 깊이(0 ~ 1) 차이
@export var offset := Vector2(-0.7, 0.0)
## 앉아서의 자세
@export_enum("서기", "앉기", "엎드림") var stance := 1
