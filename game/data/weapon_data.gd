extends Resource
class_name WeaponData

## 무기 데이터 — 인스펙터에서 값만 바꿔 끼운다. 병종(SoldierType)의 `무기` 칸에 끌어다 놓는다.
## (Docs/게임설계/보병_추상화.md §2-11 데이터 · §2-12 명중)

@export var display_name := "소총"

@export_group("사격")
## 사거리(m). 표적 고르기는 x 거리만 본다
@export var range_m := 60.0
## 겨누는 시간(초) — 조준을 시작해 첫 발까지
@export var aim_time := 0.6
## 한 발 쏘고 다음 발까지(초)
@export var fire_interval := 1.5
@export var mag_size := 5
@export var reload_time := 3.0
## 총알 속도(m/s) — 맞은 결과를 비행 시간만큼 늦게 적용한다
@export var bullet_speed := 500.0
@export var damage := 60.0

@export_group("퍼짐 원")
## 퍼짐 원의 반지름(도). 좁을수록 잘 맞는다 — 각도라서 먼 표적일수록 원이 커진다
@export_range(0.0, 10.0, 0.05) var spread_deg := 0.8
## 걸으며 쏠 때 곱(걸으며 쏘기 특성이 있는 병종만)
@export var spread_move_mult := 2.5
## 연사 — 한 발마다 넓어지는 양(도)
@export var spread_per_shot_deg := 0.4
## 쉬면 초당 돌아오는 양(도)
@export var spread_recover_deg := 1.2

@export_group("제압")
## 총알이 근처를 지나갈 때 그 병사에게 쌓이는 제압(1 을 넘으면 제압 상태)
@export var suppress_power := 0.3
## "근처"의 반지름(m)
@export var suppress_radius_m := 1.2

@export_group("외형")
## 구운 장비(equip.json) — 비우면 맨손(2D)
@export_file("*.json") var equip_json := ""
## 3D 무기 모델(장비 창이 만든 asset.json — 쥐는 자리 포함). 비우면 3D 화면에서 맨손
@export_file("*.json") var model_asset := ""
