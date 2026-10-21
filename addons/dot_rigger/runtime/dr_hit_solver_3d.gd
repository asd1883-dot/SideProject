@tool
extends SkeletonModifier3D

## IK 피격 수정자(10-21) — DRCharacter3D 가 뼈대 아래에 둘 넣는다(class_name 없이 — 안에서만 쓴다).
##   DR_HitSolver(조준 수정자 바로 뒤, 받침대 · 손 IK 앞): 몸통 · 머리 · 다리 · 손 IK 없는 팔 — 손 · 무기는 몸을 따라오고 뒤의 손 IK 가 다시 잡는다.
##   DR_HitArmSolver(맨 뒤, after_hands): 손 IK 로 무기를 잡은 팔 — IK 로 잡은 자세 위에 덧씌워 손이 총에서 튕겼다 돌아온다.
## 맞은 부위의 뼈 사슬을 총알 방향으로 젖혔다 돌아오게 한다. 계산은 DRCharacter3D._solve_hits · _solve_hits_after_hands.

var character: Node = null
var after_hands := false


func _process_modification_with_delta(_delta: float) -> void:
	if character != null and is_instance_valid(character):
		character.call("_solve_hits_after_hands" if after_hands else "_solve_hits", get_skeleton())
