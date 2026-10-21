@tool
extends SkeletonModifier3D

## IK 피격 수정자(10-21) — DRCharacter3D 가 뼈대 아래 조준 수정자 바로 뒤(손 IK 보다 앞)에 넣는다(class_name 없이 — 안에서만 쓴다).
## 맞은 부위의 뼈 사슬을 총알 방향으로 젖혔다 돌아오게 한다 — 손 · 무기는 몸을 따라오고 뒤의 손 IK 가 다시 잡는다. 계산은 DRCharacter3D._solve_hits.

var character: Node = null


func _process_modification_with_delta(_delta: float) -> void:
	if character != null and is_instance_valid(character):
		character.call("_solve_hits", get_skeleton())
