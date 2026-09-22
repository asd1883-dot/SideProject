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

## 그리기 순서를 "이 파트 바로 앞"으로 정한다(예: "Torso" = 몸통 바로 앞 · 몸통보다 앞 순서인 파트들의 뒤). 비면 위의 z_index(절대값)를 쓴다.
## 파트의 z 는 세트마다 다르고 자동 순서로 구운 씬은 프레임마다도 바뀌므로, 절대값보다 이쪽이 안전하다 — 퍼펫이 그 파트의 z 를 매 프레임 따라간다.
## (파트 z 간격이 10 인 씬이어야 사이에 낀다. 09-21 이전에 구운 씬은 간격이 1 이라 그 파트와 같은 z 가 된다 → 다시 구울 것.)
@export var z_after_part: String = ""

## 파트의 단축 보정(stretch)을 같이 따를지. 보통 true.
## 헬멧처럼 파트에 밀착된 것은 true, 깃발처럼 매달린 것은 false 가 자연스럽다.
@export var follow_stretch: bool = true

@export var modulate: Color = Color.WHITE

## 앞 조각 — 이 장비보다 **앞에 있는 파트의 그 부분**만 따로 찍은 그림들. [{ part: String, texture: Texture2D, offset: Vector2 }]
## 총을 쥔 손가락처럼 장비 앞에 와야 하는 부분이 장비 바로 위(z + 1)에 그 파트를 따라 그려진다(Spine 의 손 앞/뒤 나누기를 자동으로).
## 장비 굽기 창이 3D 깊이로 만들어 equip.json 에 같이 남긴다.
@export var overlays: Array = []
