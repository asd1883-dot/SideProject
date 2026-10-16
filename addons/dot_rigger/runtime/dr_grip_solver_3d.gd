@tool
extends SkeletonModifier3D

## 받침대 풀이 수정자(10-16) — DRCharacter3D 가 받침대(DRGripMount3D)가 있을 때 뼈대 아래 **맨 앞**에 넣는다(class_name 없이 — 안에서만 쓴다).
## 수정자 차례 안에서(뼈 자세 = 동작 그대로, 손 IK 전) 받침대 자리(두 손 사이 보간)와 받침대 쪽 손 IK 목표를 맞춘다 —
## 동작 재생 · 되감기 · 에디터 · 도구 누가 자세를 바꿨든 같은 차례로 풀리고, 손이 IK 로 움직인 자리를 받침대가 다시 따라가는 순환이 없다.

var character: Node = null


func _process_modification_with_delta(_delta: float) -> void:
	if character != null and is_instance_valid(character):
		character.call("_solve_mounts", get_skeleton())
