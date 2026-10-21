extends Resource
class_name EquipmentType

## 운용 장비 종류 — MG42 라페테 · 박격포 · 야포처럼 병사와 따로인 장비.  (보병_추상화.md §2-13, 안건 F — 게이츠 오브 헬식)
## 장비는 병사가 아니다: 전장에 따로 기록(BattleEquipment)이 있고, 아무 병사나 좌석에 앉아 운용한다.
## 사수가 쓰러지면 분대가 우선순위대로 다른 병사를 앉히고, 운용하던 분대가 없어지면 버려진 장비가 된다(아군 · 적 누구든 다시 운용).
## 효율 = 최소 + (1 − 최소) × 숙련도 — 숙련도는 병종의 `숙련도`(skills)에서 skill_key 로 찾는다(없으면 0).

@export var display_name := "MG42 라페테"
## 숙련도 이름 — 병종의 `숙련도`(skills)에서 이 이름의 값(0 ~ 1)을 본다
@export var skill_key: StringName = &"MG42"
## 숙련도 0 일 때의 효율. 그 좌석이 맡는 수치에만 붙는다(시간 · 퍼짐 ÷ 효율, 속도 × 효율). 기본: MG42 75 % · 박격포 60 % · 야포 50 %
@export_range(0.1, 1.0, 0.05) var min_efficiency := 0.75

@export_group("무기")
## 장비의 무기 수치(사거리 · 연사 · 탄창 · 퍼짐 · 제압) — 사격 좌석의 능력(장비 사격)이 이것으로 쏜다
@export var weapon: WeaponData
## 총구 높이(m)
@export var muzzle_height := 0.85
## 총구가 장비 자리보다 앞에 있는 거리(m)
@export var muzzle_ahead_m := 0.9
## 선회 빠르기(도/초) — 반대쪽 적을 쏘려면 180° 돈다(사수 좌석의 효율이 붙는 수치)
@export var traverse_deg_s := 90.0

@export_group("좌석")
## 좌석 — 순서 = 우선순위(첫 좌석 = 사수: 이 좌석의 병사가 자리에 있어야 설치 · 해체 · 사격이 된다)
@export var seats: Array[SeatData] = []
## 장전 담당 좌석이 모두 비었을 때 "대신 장전"하는 병사의 장전 시간 곱 — 부사수가 없으면 사수가 직접(×2)
@export var empty_loader_mult := 2.0

@export_group("설치 · 운반")
## 설치 · 해체 시간(초) — 첫 좌석(사수)의 병사가 자리에 있을 때만 흐른다
@export var setup_time := 4.0
@export var teardown_time := 3.0
## 들고 옮길 때 운반병의 속도 곱
@export var carry_speed_mult := 0.7

@export_group("외형")
## 모습 프리팹(씬 — 좌석 자리 = Marker3D). 비우면 화면에 자리 표시(선 · 점 · 글자)만 — 10-21: MG42 모델은 아직 안 구움
@export var prefab: PackedScene


## 숙련도 → 효율
func efficiency(skill: float) -> float:
	return min_efficiency + (1.0 - min_efficiency) * clampf(skill, 0.0, 1.0)
