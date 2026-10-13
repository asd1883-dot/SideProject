extends RefCounted
class_name SoldierBrain

## 병사 두뇌 — 가벼운 판단만. 점수제(Utility AI).  (보병_추상화.md §2-3 · §2-7)
##
## 0.2 ~ 0.5 초마다 의도 후보(자리로 · 사격 · 장전 · 숨기 · 대기)에 점수를 매겨 가장 높은 것을 고르고,
## 그 결과를 병사 기록의 "의도" 칸(want_* · target)에 적는다. 몸(BattleBody)이 그걸 읽어 움직인다.
## 분대가 준 자리(goal_x)로 가는 것도 점수 하나일 뿐이라, 제압이 쌓이면 못 나간다(규칙을 따로 넣지 않는다).
## 빙의하면 이 두뇌 대신 플레이어가 같은 칸을 채운다.
##
## 표적은 병사가 고른다 — 사거리(x 거리) 안의 적 아무나(§2-1).

const THINK_MIN := 0.2
const THINK_MAX := 0.5
const ARRIVED_M := 0.4
const NEAR_ENEMY_M := 10.0          # 이 안에 적이 있으면 자리로 가던 중이라도 쏜다
const RUN_OVER_M := 5.0             # 자리까지 이보다 멀면 달린다
const S_STAND := BattleBody.Stance.STAND
const S_CROUCH := BattleBody.Stance.CROUCH
const S_PRONE := BattleBody.Stance.PRONE


static func tick(s: BattleSoldier, bf: Battlefield, dt: float) -> void:
	s.brain_timer -= dt
	if s.brain_timer > 0.0:
		return
	s.brain_timer = bf.rng.randf_range(THINK_MIN, THINK_MAX)
	if not s.can_fight():
		return
	var w := s.type.weapon
	s.use_goal = true

	# 패주 — 분대 덮어쓰기. 명령 무시 · 사격 없이 뒤로 달린다(§2-8)
	if s.squad != null and s.squad.routed:
		s.goal_x = bf.home_x(s.team)
		s.want_run = true
		s.want_stance = S_STAND
		s.want_fire = false
		s.want_reload = false
		s.target = null
		s.can_engage = false
		s.intent_name = "패주"
		s.intent_scores = {}
		return

	_pick_target(s, bf, w)
	var has_target := s.target != null
	var dist_goal := absf(s.goal_x - s.x)
	var arrived := dist_goal <= ARRIVED_M
	var supp := minf(s.suppression, 1.0)
	var near_enemy := has_target and absf(s.target.x - s.x) < NEAR_ENEMY_M
	var at_cover := s.cover != null and s.slot >= 0 and arrived

	# 쏠 수 있는 자세 — 바라는 자세(엄폐의 쏘는 자세 · 맨땅이면 앉기/엎드림)에서 사선이 벽에 막히면 더 일어서 본다. 다 막히면 못 쏜다
	var fire_stance := -1
	if has_target and s.ammo > 0:
		var aim := Ballistics.aim_point(s, s.target)
		var prefer: int = s.cover.fire_stance() if at_cover else (S_PRONE if supp > 0.4 else S_CROUCH)
		var st := prefer
		while st >= S_STAND:
			if not Ballistics.line_blocked(bf, s, st, aim):
				fire_stance = st
				break
			st -= 1
	s.can_engage = fire_stance >= 0 or (has_target and s.ammo <= 0)      # 탄이 떨어졌을 뿐이면 교전 중

	# ── 점수 ──
	var sc := {}
	sc["자리로"] = 0.0 if arrived else 0.75 - 0.5 * supp
	sc["사격"] = 0.0
	if fire_stance >= 0:
		sc["사격"] = (0.85 if arrived else 0.45) - 0.35 * supp + (0.4 if near_enemy else 0.0)
	sc["장전"] = 0.0
	if s.ammo <= 0:
		sc["장전"] = 0.9
	elif s.ammo * 10 < w.mag_size * 4 and not has_target:
		sc["장전"] = 0.5
	sc["숨기"] = 0.8 * supp if supp > 0.35 else 0.0
	sc["대기"] = 0.1
	var best := "대기"
	for k in sc.keys():
		if float(sc[k]) > float(sc[best]):
			best = k
	s.intent_name = best
	s.intent_scores = sc

	# ── 의도 채우기 ──
	s.want_fire = false
	s.want_reload = false
	s.want_run = false
	match best:
		"자리로":
			s.want_stance = S_STAND
			s.want_run = dist_goal > RUN_OVER_M or has_target
			s.want_fire = s.type.fire_while_walking and fire_stance == S_STAND      # 특성이 있을 때만 걸으며 쏜다
			if s.want_fire:
				s.want_run = false
		"사격":
			s.want_fire = true
			s.want_stance = fire_stance
		"장전":
			s.want_reload = true
			s.want_stance = s.cover.hide_stance() if at_cover else S_CROUCH
		"숨기":
			s.want_stance = s.cover.hide_stance() if at_cover else S_PRONE
		_:
			s.want_reload = s.ammo < w.mag_size
			s.want_stance = s.cover.fire_stance() if at_cover else S_STAND


## 표적 고르기 — 가까울수록 · 드러나 있을수록 · 쏘던 표적일수록 점수가 높다
static func _pick_target(s: BattleSoldier, bf: Battlefield, w: WeaponData) -> void:
	var best: BattleSoldier = null
	var best_v := -INF
	for e in bf.enemies_near(s.team, s.x, w.range_m):
		var v := 1.0 - absf(e.x - s.x) / maxf(w.range_m, 1.0)
		if e.is_hidden():
			v -= 0.4
		if e == s.target:
			v += 0.15
		v += bf.rng.randf() * 0.1
		if v > best_v:
			best_v = v
			best = e
	s.target = best
