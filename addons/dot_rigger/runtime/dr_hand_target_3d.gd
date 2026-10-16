@tool
extends Marker3D
class_name DRHandTarget3D

## 손 표지(10-16) — 장비(무기) 노드 아래에 둔다. 원점 = 그 손바닥이 올 자리, 회전 = 그 손 뼈의 회전(손가락 쪽 = +Y).
## 왜: 무기는 받침(오른손 · 왼손 소켓, 또는 두 손 사이 · 땅 받침대 DRGripMount3D)에 붙어 그것과 같이 움직이는데, 동작마다 두 손 사이가 달라
##     (Mixamo 소총 동작 — Rifle_Idle 은 조준 자세보다 왼손이 20 cm 떨어짐) 무기 하나 자리로는 다른 손이 총몸에서 뜬다. 그래서 그 손을 표지에 붙인다.
## DRCharacter3D 가 조립할 때 표지를 찾아 그 팔 두 마디 IK(내장 TwoBoneIK3D)로 손바닥 점을 여기에, 손 회전을 이 표지 회전으로 맞춘다.
## 받침이 그 손이면(오른손 소켓에 든 무기의 오른손 표지) IK 를 안 건다 — 무기가 그 손을 따라가므로.
## 이름이 "왼손" 인 보통 Marker3D 도 왼손 표지로 쓴다(그때 비중은 늘 1). 이 스크립트를 붙이면 동작마다 비중을 줄 수 있다.

## 어느 손(10-16 확장 — 오른손도 IK 로 따라갈 수 있게). 예전 표지(이 칸이 없던 것)는 왼손
@export_enum("왼손", "오른손") var side := 0
## IK 비중(0 = 동작 그대로 · 1 = 표지에 붙임) — 동작마다 따로 안 정한 동작에 쓴다
@export_range(0.0, 1.0, 0.05) var weight := 1.0
## 동작마다 비중(없는 동작 = weight). 그 손이 총을 놓는 동작(수류탄 던지기 · 맨손 달리기 등)은 0
@export var motion_weights: Dictionary[String, float] = {}


func _init() -> void:
	gizmo_extents = 0.06     # 기본 0.25 m 십자는 손보다 커서 무기를 가린다


## 그 동작의 IK 비중
func weight_for(motion: String) -> float:
	return clampf(float(motion_weights.get(motion, weight)), 0.0, 1.0)
