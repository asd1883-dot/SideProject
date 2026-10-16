@tool
extends Node3D
class_name DRGripMount3D

## 장비 받침대(10-16) — 장비(무기)를 손 하나(소켓)가 아니라 "두 손 사이" 또는 "유닛(땅)"에 고정한다. 유닛 프리팹 루트 아래에 소켓처럼 두고
## 장비를 그 아래에 넣는다(받침대 → 장비 → 오른손 · 왼손 표지).
## 사용자(10-16): "오른손 · 왼손 · 양손 — 조인트 느낌, 어느 부분(소켓)을 고정할지 … mp40 이나 라페테에 얹어 양손으로 잡는 mg42 이면?
##   왼손 소켓 · 오른손 소켓 지정해서 보간되는 잡기 … 무기를 기즈모로 움직이면 오른손도 따라가거나 양손이거나."
##   HANDS(두 손 사이): 자리 = 오른손 쪽 자리(오른손 뼈 × right_offset) ↔ 왼손 쪽 자리(왼손 뼈 × left_offset)를 blend 로 보간 —
##     동작 자세(IK 전)로 계산하고, 그 동작에서 IK 를 끈(총을 놓은) 손은 빼고 잡은 손만 따른다. 두 손은 장비 위 표지에 IK 로 붙는다.
##     *_offset 은 맞춘 자세에서 잡아 둔다(② 장비 탭의 "양손" — 그 자세에서는 두 쪽 자리가 같다).
##   FIXED(고정): 이 노드 자리 그대로(유닛 기준) — 라페테(삼각대) 위 MG42 처럼 땅에 놓인 장비. 두 손이 표지에 IK 로 붙는다.
## 자리 계산은 DRCharacter3D 가 뼈대 수정자 차례 맨 앞(runtime/dr_grip_solver_3d.gd)에서 한다 — 누가 자세를 바꿨든 같은 차례로.

enum Mode { HANDS, FIXED }

## 받침 방식 — 두 손 사이(보간) · 고정(유닛 기준)
@export var mode: Mode = Mode.HANDS
## 두 손 사이 어디(0 = 오른손 쪽 · 1 = 왼손 쪽)
@export_range(0.0, 1.0, 0.05) var blend := 0.5
## 오른손 뼈 → 받침대(맞춘 자세에서)
@export var right_offset := Transform3D.IDENTITY
## 왼손 뼈 → 받침대(맞춘 자세에서)
@export var left_offset := Transform3D.IDENTITY
