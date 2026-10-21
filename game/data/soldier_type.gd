extends Resource
class_name SoldierType

## 병종 — Unity 로 치면 병사 프리팹 자리. 이 리소스(.tres) 하나를 그 병종의 모든 병사가 같이 쓴다.
## 인스펙터에서 숫자를 바꾸거나 무기 · 복장 · 동작 표를 끌어다 바꿔 끼우면 그 병종 전체가 바뀐다.
## (Docs/게임설계/보병_추상화.md §2-2 데이터 · §2-11 인스펙터)

@export var display_name := "소총수"

@export_group("능력치")
@export var max_hp := 100.0
## 걷는 속도(m/s)
@export var walk_speed := 1.6
## 달리는 속도(m/s)
@export var run_speed := 4.2
## 포복 속도(m/s)
@export var crawl_speed := 0.6
## 앉아서 움직일 때 걷는 속도에 곱
@export var crouch_move_mult := 0.6
## 제압 내성 — 클수록 덜 쌓인다(쌓이는 양을 이 값으로 나눈다)
@export var suppress_resist := 1.0

@export_group("특성")
## 걸으며 쏘기 — 없으면 "행동 중이면 이동은 정지"
@export var fire_while_walking := false

@export_group("능력")
## 이 병종이 할 수 있는 기능(사격 · 장전 …) — 하나 = 능력 파일 하나(game/units/abilities/*.tres). 끌어다 넣고 빼면 그 기능을 얻고 잃는다(§2-13).
## 순서 = 두뇌가 묻는 순서(점수가 같으면 앞의 것)
@export var abilities: Array[Ability] = []
## 숙련도 — 운용 장비 종류(EquipmentType.skill_key, 예: MG42)마다 0 ~ 1. 없으면 0(그 장비의 최소 효율로 운용)
@export var skills: Dictionary[StringName, float] = {}

@export_group("분대")
## 투입할 때 한 분대의 인원(단독 병종이면 1)
@export_range(1, 12, 1) var squad_size := 6

@export_group("무기")
@export var weapon: WeaponData

@export_group("퍼짐 원 — 자세별 곱")
## 자세에 따라 무기의 퍼짐 원에 곱하는 값(작을수록 잘 맞는다)
@export var spread_stand := 1.0
@export var spread_crouch := 0.8
@export var spread_prone := 0.6
## 제압이 1 쌓였을 때 퍼짐 원에 더 곱해지는 양(0.5 면 1.5배)
@export var spread_suppressed_add := 1.0

@export_group("판정 상자 (m)")
## 자세별 몸 상자 — x = 너비(전선 방향) · y = 높이. 총알은 이 상자로 맞는지 본다(그림이 아니라)
@export var box_stand := Vector2(0.5, 1.75)
@export var box_crouch := Vector2(0.6, 1.1)
@export var box_prone := Vector2(1.7, 0.4)
## 몸 두께(깊이 0~1 단위의 절반 폭)
@export var body_depth := 0.05
## 총구 높이(m) — 서기 / 앉기 / 엎드림
@export var muzzle_heights := Vector3(1.45, 0.95, 0.3)

@export_group("외형 3D")
## 유닛 프리팹(씬) — 3D 모습: 몸 · 상의 · 하의 · 무기 · 동작 표 · 키(루트 DRCharacter3D 의 칸).
## 기본형 군인 = game/units/soldier_base.tscn, 다른 유닛 = 그것을 상속한 자식 씬(Dot Rigger ① 유닛 탭). 숫자(능력치 · 판정)는 이 병종 리소스에
@export var prefab: PackedScene

@export_group("외형 2D (예전 퍼펫 화면)")
## 구운 퍼펫 세트(sets.json) — 2D 화면용
@export_file("*.json") var sets_json := "res://puppet/sets.json"
## 복장(outfit.json) — 2D 구운 복장 그림
@export_file("*.json") var outfit_json := ""
## 이 병종의 키(m) — 2D 퍼펫을 이 키에 맞춘다(3D 는 프리팹의 키)
@export var height_m := 1.75
## 구운 퍼펫에서 발끝~머리끝이 몇 픽셀인가(화면 배율 계산용, 2D)
@export var puppet_body_px := 200.0

@export_group("동작 표")
## 2D 화면의 동작 표(3D 는 프리팹의 동작 표 — 기본형 군인은 같은 표를 쓴다)
@export var motions: MotionTable


## 자세(BattleBody.Stance)의 몸 상자
func box(stance: int) -> Vector2:
	match stance:
		1:
			return box_crouch
		2:
			return box_prone
	return box_stand


func muzzle_height(stance: int) -> float:
	match stance:
		1:
			return muzzle_heights.y
		2:
			return muzzle_heights.z
	return muzzle_heights.x


func spread_stance_mult(stance: int) -> float:
	match stance:
		1:
			return spread_crouch
		2:
			return spread_prone
	return spread_stand
