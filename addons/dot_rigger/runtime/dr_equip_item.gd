@tool
extends Resource
class_name DREquipItem

## 장비 한 점. 캐릭터와 "완전히 같은 카메라 / 같은 레스트 포즈"로 구웠다면
## 좌표만 맞춰 붙이면 픽셀 단위로 정렬된다.
##
## 이 방식의 요점: 헬멧을 추가할 때 필요한 이미지가
##   프레임 베이크: 방향 x 애니 x 프레임 (수백 장)
##   컷아웃 부착  : 1장
## 이라 장비 종류를 늘려도 리소스가 곱하기가 아니라 더하기로 늘어난다.

## 슬롯 이름. 한 슬롯에는 하나만 장착된다 (예: "helmet", "backpack", "weapon_r")
@export var slot: String = ""

## 붙일 리그 파트 이름 (예: "Head", "Torso", "R_Hand")
@export var part: String = ""

@export var texture: Texture2D

## 이 이미지의 좌상단이 놓일 캔버스 좌표(레스트 포즈 기준).
## 베이크 결과 rig.json 의 crop 원점과 같은 규격이다.
@export var offset: Vector2 = Vector2.ZERO

## 절대 z. 파트 본체의 z 는 프레임마다 깊이로 계산되므로,
## 앞에 그리려면 크게, 뒤에 그리려면 작게 준다.
@export var z_index: int = 0

## 파트의 단축 보정(stretch)을 같이 따를지. 보통 true.
## 헬멧처럼 파트에 밀착된 것은 true, 깃발처럼 매달린 것은 false 가 자연스럽다.
@export var follow_stretch: bool = true

@export var modulate: Color = Color.WHITE
