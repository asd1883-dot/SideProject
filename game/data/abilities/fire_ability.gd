extends Ability
class_name FireAbility

## 사격 — 표적을 겨눠(준비 = 조준) 한 발 쏘고(실행 = 사격 자세), 계속 쏘고 싶으면 다시 겨눈다(이미 겨눴으니 연사 간격만 기다림).
## 무기 = 병종의 무기(SoldierType.weapon). 명중은 퍼짐 원 + 경로 판정(Ballistics).  (보병_추상화.md §2-12 · §2-13)
## 두뇌 점수: 쏠 수 있는 자세(엄폐의 쏘는 자세 · 맨땅이면 앉기/엎드림, 사선이 벽에 막히면 더 일어서 봄)가 있을 때만.

const S_STAND := BattleBody.Stance.STAND
const S_CROUCH := BattleBody.Stance.CROUCH
const S_PRONE := BattleBody.Stance.PRONE


func _init() -> void:
	display_name = "사격"
	intent = "사격"
	priority = 0


func score(s: BattleSoldier, bf: Battlefield, c: BrainCtx) -> float:
	# 쏠 수 있는 자세 — 바라는 자세에서 사선이 벽에 막히면 더 일어서 본다. 다 막히면 못 쏜다
	var fire_stance := -1
	if c.has_target and s.ammo > 0:
		var aim := Ballistics.aim_point(s, s.target)
		var prefer: int = s.cover.fire_stance() if c.at_cover else (S_PRONE if c.supp > 0.4 else S_CROUCH)
		var st := prefer
		while st >= S_STAND:
			if not Ballistics.line_blocked(bf, s, st, aim):
				fire_stance = st
				break
			st -= 1
	c.fire_stance = fire_stance
	c.engage = fire_stance >= 0 or (c.has_target and s.ammo <= 0)      # 탄이 떨어졌을 뿐이면 교전 중
	if fire_stance < 0:
		return 0.0
	return (0.85 if c.arrived else 0.45) - 0.35 * c.supp + (0.4 if c.near_enemy else 0.0)


func apply(s: BattleSoldier, c: BrainCtx) -> void:
	s.want_fire = true
	s.want_stance = c.fire_stance


func wants(s: BattleSoldier) -> bool:
	return s.want_fire and s.ammo > 0


func begin(s: BattleSoldier, _bf: Battlefield) -> void:
	s.phase = Phase.PREP
	s.act_state = BattleBody.Act.AIM
	s.act_timer = s.type.weapon.aim_time


func step(s: BattleSoldier, bf: Battlefield, dt: float) -> bool:
	if s.phase == Phase.PREP:
		if not s.want_fire or s.ammo <= 0:
			return false
		s.act_timer -= dt
		if s.act_timer <= 0.0 and s.fire_cooldown <= 0.0:
			Ballistics.fire(bf, s)
			s.phase = Phase.EXEC
			s.act_state = BattleBody.Act.FIRE
			s.act_timer = BattleBody.FIRE_POSE
			s.fire_cooldown = s.type.weapon.fire_interval
		return true
	# 실행(한 발 쏜 뒤 사격 자세가 보이는 동안)
	s.act_timer -= dt
	if s.act_timer > 0.0:
		return true
	if s.want_fire and s.ammo > 0:
		s.phase = Phase.PREP
		s.act_state = BattleBody.Act.AIM
		s.act_timer = 0.0                   # 이미 겨누고 있었으니 다음 발은 연사 간격만 기다린다
		return true
	return false
