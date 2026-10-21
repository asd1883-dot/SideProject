extends RefCounted
class_name BrainCtx

## 병사 두뇌가 한 번 생각할 때 능력(Ability)들과 나누는 값.  (보병_추상화.md §2-13)
## 두뇌가 위쪽(입력)을 채우고, 능력이 score() 에서 아래쪽(계획)을 적는다. 두뇌가 하나를 돌려 쓴다(생각할 때마다 만들지 않는다).

# ── 두뇌가 채우는 것 ──
var has_target := false
var arrived := false            # 분대가 준 자리에 도착
var at_cover := false           # 엄폐 칸에 도착
var near_enemy := false
var supp := 0.0                 # 제압(0 ~ 1)
var dist_goal := 0.0

# ── 능력이 적는 것 ──
## 사격 능력이 찾은 "쏠 수 있는 자세"(BattleBody.Stance, −1 = 못 쏜다). 걸으며 쏘기 · 자리로 의도도 이걸 본다
var fire_stance := -1
## 교전 중 — 분대 두뇌가 "교전 중인 병사"로 센다(BattleSoldier.can_engage)
var engage := false


func reset() -> void:
	has_target = false
	arrived = false
	at_cover = false
	near_enemy = false
	supp = 0.0
	dist_goal = 0.0
	fire_stance = -1
	engage = false
