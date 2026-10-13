extends RefCounted
class_name SquadBrain

## 분대 두뇌 — "무엇을 할지"를 분대 단위로 정한다. 점수제(Utility AI).  (보병_추상화.md §2-3 · §2-7 · §2-10)
##
## 0.5 ~ 1 초마다 태세(전진 · 유지 · 후퇴 · 돌격)마다 점수를 매겨 가장 높은 것을 고르고,
## 그 태세에 맞는 목표 지점 · 엄폐물(예약) · 병사별 자리를 정한다. 병사는 그 자리로 가는 것을 "가중치"로 받는다(강제 아님).
## 지휘 명령(order)도 강제가 아니라 점수에 더해지는 가중치 → 명령받아도 제압당하면 못 나간다.
## 무거운 조회(엄폐 찾기 · 앞쪽 적 세기)는 병사 수가 아니라 분대 수만큼만 돈다.
##
## 표적은 분대가 정하지 않는다(분대끼리 짝지으면 열 시스템으로 되돌아간다) — 병사가 고른다.

const THINK_MIN := 0.5
const THINK_MAX := 1.0
const LOOK_AHEAD_M := 30.0          # 이 안에서 다음 엄폐물을 찾는다
const STEP_M := 10.0                # 엄폐물이 없을 때 한 번에 나아가는 거리
const SPREAD_LIMIT_M := 8.0         # 앞선 병사와 뒤처진 병사가 이보다 벌어지면 기다린다
const ENEMY_KEEP_M := 3.0           # 적보다 이만큼은 못 미친 엄폐물까지만 간다
const STANDOFF_M := 12.0            # 엄폐물 없이 나아갈 때 적과 두는 거리 — 적이 차지한 벽 코앞까지 붙으면 일방적으로 맞는다(10-13 시험: 4 대 68)
const STAGGER_M := 1.1              # 분대마다 서는 자리를 이만큼씩 어긋나게(여러 분대가 같은 x 에 기둥처럼 겹치지 않게)
const HYSTERESIS := 0.08            # 지금 태세에 주는 덤(판단이 떨지 않게)
# 지휘 명령이 그 태세 점수에 더하는 가중치
const ORDER_ADVANCE_W := 0.5
const ORDER_HOLD_W := 0.6
const ORDER_RETREAT_W := 0.7
const P_ADVANCE := BattleSquad.Posture.ADVANCE
const P_HOLD := BattleSquad.Posture.HOLD
const P_RETREAT := BattleSquad.Posture.RETREAT
const P_CHARGE := BattleSquad.Posture.CHARGE


static func tick(sq: BattleSquad, bf: Battlefield, dt: float) -> void:
	sq.brain_timer -= dt
	if sq.brain_timer > 0.0:
		return
	sq.brain_timer = bf.rng.randf_range(THINK_MIN, THINK_MAX)
	var act := sq.active()
	if act.is_empty() or sq.routed:
		return                                      # 패주는 두뇌보다 위(Battlefield 가 건다). 병사가 알아서 뒤로 달린다

	# ── 입력 ──
	var fwd := bf.forward(sq.team)
	var anchor := sq.anchor_x()
	var enemies := bf.enemies_near(sq.team, anchor, sq.type.weapon.range_m)
	var has_enemy := not enemies.is_empty()
	var supp := sq.avg_suppression()
	var alive_ratio := float(act.size()) / float(maxi(sq.members.size(), 1))
	var pressure := clampf(float(enemies.size()) / float(act.size()), 0.0, 2.0) * 0.5
	var covered := 0
	var engaging := 0
	var min_x := INF
	var max_x := -INF
	for s in act:
		if s.in_cover:
			covered += 1
		if s.can_engage:
			engaging += 1
		min_x = minf(min_x, s.x)
		max_x = maxf(max_x, s.x)
	var cover_ratio := float(covered) / float(act.size())
	var stretched := (max_x - min_x) > SPREAD_LIMIT_M
	# 교전 중 = 적이 사거리 안에 있고, 그 적을 실제로 쏠 수 있는 병사가 있다.
	# 사거리 안이어도 벽에 가려 아무도 못 쏘면 교전이 아니다 — 안 그러면 서로 못 쏘는 채로 영원히 "유지"한다(10-13 시험에서 교착)
	var contact := has_enemy and engaging > 0
	if has_enemy and not contact:
		pressure *= 0.3

	# ── 점수 ──
	var sc := {}
	sc[P_ADVANCE] = 0.35 + 0.25 * sq.morale - 0.7 * supp - 0.4 * (1.0 - alive_ratio) - 0.35 * pressure \
			- (0.3 if stretched else 0.0) - (0.25 if (contact and cover_ratio > 0.5) else 0.0)
	sc[P_HOLD] = 0.3 + (0.35 if contact else 0.0) + 0.25 * cover_ratio + (0.3 if stretched else 0.0)
	sc[P_RETREAT] = 0.05 + 0.8 * (1.0 - sq.morale) * (1.0 if has_enemy else 0.3) + 0.4 * supp * (1.0 - cover_ratio)
	sc[P_CHARGE] = -1.0                              # 돌격은 아직 없음(근접이 들어올 때)
	match sq.order:                                  # 지휘 명령 = 가중치
		BattleSquad.Order.ADVANCE:
			sc[P_ADVANCE] += ORDER_ADVANCE_W
		BattleSquad.Order.HOLD:
			sc[P_HOLD] += ORDER_HOLD_W
		BattleSquad.Order.RETREAT:
			sc[P_RETREAT] += ORDER_RETREAT_W
	sc[sq.posture] += HYSTERESIS
	var best: int = sq.posture
	for k in sc.keys():
		if float(sc[k]) > float(sc[best]):
			best = k
	sq.posture = best
	sq.scores = {}
	for k in sc.keys():
		sq.scores[BattleSquad.POSTURE_NAMES[k]] = snappedf(float(sc[k]), 0.01)

	# ── 목표 지점 · 엄폐물 ──
	var hold_in_place := false
	# 적이 앞쪽 어디까지 와 있나(그보다 앞의 엄폐물로는 안 간다)
	var enemy_front := INF
	for e in enemies:
		var ahead := (e.x - anchor) * float(fwd)
		if ahead > 0.0:
			enemy_front = minf(enemy_front, ahead)
	match sq.posture:
		P_ADVANCE:
			if sq.cover != null and cover_ratio <= 0.5 and _usable(sq.cover, sq, fwd):
				pass                                 # 가던 엄폐물로 계속 간다
			else:
				var from_x := sq.cover.center_x() if sq.cover != null else anchor
				var limit := enemy_front - ((from_x - anchor) * float(fwd)) - ENEMY_KEEP_M
				var c := _find_cover(sq, bf, from_x, fwd, fwd, minf(LOOK_AHEAD_M, limit))
				if c != null:
					_take_cover(sq, c)
				elif contact:
					hold_in_place = sq.cover == null # 갈 곳이 없고 교전 중 — 지금 자리(엄폐물)에서 싸운다
				else:
					# 엄폐물도 없고 쏠 수도 없다 — 앞으로 나아간다(적에게 너무 붙지는 않게)
					_take_cover(sq, null)
					var step := minf(STEP_M, maxf(enemy_front - STANDOFF_M, 0.0))
					sq.goal_x = clampf(anchor + float(fwd) * step, 3.0, bf.length_m - 3.0)
		P_HOLD:
			if sq.cover == null:
				var c2 := _find_cover(sq, bf, anchor - float(fwd) * 6.0, fwd, fwd, 12.0)
				if c2 != null and (c2.center_x() - anchor) * float(fwd) < enemy_front - ENEMY_KEEP_M:
					_take_cover(sq, c2)
				else:
					hold_in_place = true
		P_RETREAT:
			var c3 := _find_cover(sq, bf, anchor, -fwd, fwd, LOOK_AHEAD_M)
			if c3 != null:
				_take_cover(sq, c3)
			else:
				_take_cover(sq, null)
				sq.goal_x = clampf(anchor - float(fwd) * 15.0, 3.0, bf.length_m - 3.0)
	_assign(sq, act, fwd, hold_in_place)


## 엄폐물을 고른다. from_x 에서 search_dir 쪽으로 max_dist 안, protect_dir 쪽(적 쪽)에 벽이 있는 것 중 가장 가까운 것
static func _find_cover(sq: BattleSquad, bf: Battlefield, from_x: float, search_dir: int, protect_dir: int, max_dist: float) -> BattleCover:
	var best: BattleCover = null
	var best_d := INF
	for c in bf.covers:
		if c == sq.cover or not _usable(c, sq, protect_dir):
			continue
		var d := (c.center_x() - from_x) * float(search_dir)
		if d < 1.0 or d > max_dist:
			continue
		if d < best_d:
			best_d = d
			best = c
	return best


## 이 분대가 쓸 수 있는 엄폐물인가 — 적 쪽에 벽이 있고 · 적이 차지하고 있지 않고 · 빈 칸(또는 이미 내 칸)이 있다
static func _usable(c: BattleCover, sq: BattleSquad, protect_dir: int) -> bool:
	if not c.protects_from(protect_dir):
		return false
	var mine := 0
	for o in c.slot_owner:
		if o == null:
			continue
		if o.team != sq.team:
			return false
		if o.squad == sq:
			mine += 1
	return mine + c.free_count() > 0


## 분대의 엄폐물을 바꾼다(null = 엄폐 없이). 예전 엄폐물의 칸은 내놓는다
static func _take_cover(sq: BattleSquad, c: BattleCover) -> void:
	if sq.cover == c:
		return
	if sq.cover != null:
		for s in sq.members:
			if s.cover == sq.cover:
				sq.cover.release(s)
				s.cover = null
				s.slot = -1
	sq.cover = c
	if c != null:
		sq.goal_x = c.center_x()


## 병사별 자리 — 엄폐물이 있으면 칸을, 칸이 모자라거나 엄폐물이 없으면 목표 지점 둘레에 벌려 세운다
static func _assign(sq: BattleSquad, act: Array[BattleSoldier], fwd: int, hold_in_place: bool) -> void:
	var count := act.size()
	var queued := 0
	for i in count:
		var s := act[i]
		if sq.cover != null:
			if s.cover != sq.cover or s.slot < 0:
				if s.cover != null:
					s.cover.release(s)
				s.cover = sq.cover
				s.slot = sq.cover.take_slot(s)
				if s.slot < 0:
					s.cover = null
			if s.slot >= 0:
				s.goal_x = sq.cover.slot_x[s.slot]
				s.goal_depth = sq.cover.slot_depth[s.slot]
				continue
			# 칸을 못 얻었다 — 엄폐물 바로 뒤에 줄 선다
			var back_x := sq.cover.x0 if fwd > 0 else sq.cover.x1
			s.goal_x = back_x - float(fwd) * (1.2 + 0.9 * float(queued / 3) + STAGGER_M * float(sq.id % 5))
			s.goal_depth = (float(queued % 3) + 0.5) / 3.0
			queued += 1
			continue
		if s.cover != null:
			s.cover.release(s)
			s.cover = null
			s.slot = -1
		if hold_in_place:
			s.goal_x = s.x
		else:
			s.goal_x = sq.goal_x - float(fwd) * (float(i % 3) * 0.9 + STAGGER_M * float(sq.id % 5))
			s.goal_depth = (float(i) + 0.5) / float(count)
