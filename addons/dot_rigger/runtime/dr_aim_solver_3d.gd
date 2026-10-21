@tool
extends SkeletonModifier3D

## 조준 수정자(10-21) — DRCharacter3D 가 무기를 들었을 때 뼈대 아래 **맨 앞**에 넣는다(class_name 없이 — 안에서만 쓴다. 받침대 풀이 수정자보다도 앞).
## 수정자 차례 안에서(뼈 자세 = 동작 그대로) 허리 · 가슴을 돌려 총구가 표적을 향하게 한다 — 손 · 무기는 몸을 따라오고,
## 뒤의 받침대 풀이 · 손 IK 가 돌린 자세로 다시 잡는다. 계산은 DRCharacter3D._solve_aim.

var character: Node = null


func _process_modification_with_delta(_delta: float) -> void:
	if character != null and is_instance_valid(character):
		character.call("_solve_aim", get_skeleton())
