extends RefCounted
class_name CrewBrain

## 장비 두뇌 — 분대의 운용 장비를 다룬다. 분대 두뇌(SquadBrain)가 판단할 때마다 부른다(병사 수가 아니라 분대 수만큼).  (보병_추상화.md §2-13)
##
##   좌석 채우기: 좌석 순서(사수 → 부사수 …)대로 — 숙련도가 높은 병사 · 이미 이 장비에 앉아 있던 병사 · 가까운 병사 순.
##               사수가 쓰러지면 부사수가 사수 좌석으로 올라가고, 빈 부사수 좌석은 분대의 다른 병사가 채운다(게이츠 오브 헬식).
##   설치 · 해체: 들고 가던 분대가 자리를 잡거나(운반병이 도착) 교전 중이면 설치. 분대가 다른 곳으로 가면(교전이 아닐 때) 해체 → 운반.
##   버려진 장비: 분대에 장비가 없으면 가까이(CLAIM_M) 있는 버려진 장비를 주워 운용한다 — 아군 · 적을 가리지 않는다.
## 좌석에 앉은 병사의 자리(goal_*)는 여기서 정한다 — 분대 두뇌의 칸 배정은 앉은 병사를 건너뛴다.
## 효율 수정자: 앉은 병사마다 좌석이 맡는 수치에 "좌석: 사수 · 숙련도 0 → 효율 75 %", 장전 담당이 비면 대신 장전하는 병사에 "빈 좌석 → 장전 ×2".

const CLAIM_M := 15.0           # 이 안의 버려진 장비를 줍는다
const PLACE_M := 4.0            # 장비가 분대 목표 지점에서 이만큼 안이면 "제자리"
const PICK_M := 0.5             # 놓인 장비를 이만큼 가까이에서 줍는다
const ARRIVED_M := 0.4


static func tick(sq: BattleSquad, bf: Battlefield, act: Array[BattleSoldier], contact: bool) -> void:
	if sq.equipment.is_empty():
		_claim(sq, bf)
	for eq in sq.equipment:
		_manage(sq, bf, eq, act, contact)


# ───────────── 판단 ─────────────

static func _manage(sq: BattleSquad, bf: Battlefield, eq: BattleEquipment, act: Array[BattleSoldier], contact: bool) -> void:
	var fwd := bf.forward(sq.team)
	var place_x := sq.cover.center_x() if sq.cover != null else sq.goal_x
	match eq.state:
		BattleEquipment.State.READY:
			if not contact and absf(eq.x - place_x) > PLACE_M:
				eq.state = BattleEquipment.State.TEARDOWN          # 분대가 다른 곳으로 간다 — 해체해서 들고 간다
				eq.timer = eq.type.teardown_time
			_fill_seats(sq, eq, act)
		BattleEquipment.State.SETUP, BattleEquipment.State.TEARDOWN:
			_fill_seats(sq, eq, act)
		BattleEquipment.State.CARRIED:
			var c := _carrier(sq, eq, act)
			if c == null:
				return
			if c.carrying != eq:
				c.carrying = eq
				BattleBody.stop_act(c)                              # 손이 찬다 — 소총을 못 쓴다
			if contact or (absf(c.goal_x - c.x) <= ARRIVED_M and absf(c.x - place_x) <= PLACE_M):
				_set_up(bf, eq, c, fwd)
				_fill_seats(sq, eq, act)
		BattleEquipment.State.DROPPED:
			if contact or absf(eq.x - place_x) <= PLACE_M:
				# 놓인 그 자리에 설치 — 장비가 쌓여 있을 뿐이라 총구를 분대의 앞으로 놓는다
				eq.facing = fwd
				_begin_setup(bf, eq)
				_fill_seats(sq, eq, act)
				return
			var p := _carrier(sq, eq, act)                          # 주우러 간다
			if p == null:
				return
			if absf(p.x - eq.x) <= PICK_M and absf(p.depth - eq.depth) <= 0.1:
				eq.state = BattleEquipment.State.CARRIED
				p.carrying = eq
				BattleBody.stop_act(p)
			else:
				p.goal_x = eq.x
				p.goal_depth = eq.depth


## 운반병 — 지금 운반병이 쓸 수 있으면 그대로, 아니면 숙련도 · 가까움 순으로 새로(앉은 병사 · 다른 장비를 든 병사는 빼고)
static func _carrier(sq: BattleSquad, eq: BattleEquipment, act: Array[BattleSoldier]) -> BattleSoldier:
	var c := eq.carrier
	if c != null and c.can_fight() and not c.detached and c.squad == sq:
		return c
	if c != null and c.carrying == eq:
		c.carrying = null
	var best: BattleSoldier = null
	var best_k := -INF
	for s in act:
		if s.seat_eq != null or (s.carrying != null and s.carrying != eq):
			continue
		var k := s.skill(eq.type.skill_key) * 10.0 - absf(s.x - eq.x) * 0.01
		if k > best_k:
			best_k = k
			best = s
	eq.carrier = best
	return best


## 운반병 자리에 설치 — 운반병(사수가 될 병사)의 자리가 사수 좌석이 되게 장비를 그 앞에 놓는다
static func _set_up(bf: Battlefield, eq: BattleEquipment, c: BattleSoldier, fwd: int) -> void:
	eq.facing = fwd
	var lead := eq.type.seats[0].offset.x if not eq.type.seats.is_empty() else 0.0
	eq.x = clampf(c.x - float(fwd) * lead, 0.0, bf.length_m)
	eq.depth = c.depth
	c.carrying = null
	eq.carrier = null
	_begin_setup(bf, eq)


static func _begin_setup(bf: Battlefield, eq: BattleEquipment) -> void:
	if eq.carrier != null and eq.carrier.carrying == eq:
		eq.carrier.carrying = null
	eq.carrier = null
	eq.state = BattleEquipment.State.SETUP
	eq.timer = eq.type.setup_time
	eq.cover = _cover_at(bf, eq.seat_x(0) if not eq.seats.is_empty() else eq.x, eq.facing)


## 그 x 를 덮는(총구 쪽에 벽이 있는) 엄폐물
static func _cover_at(bf: Battlefield, x: float, dir: int) -> BattleCover:
	for c in bf.covers:
		if x >= c.x0 - 0.3 and x <= c.x1 + 0.3 and c.protects_from(dir):
			return c
	return null


## 버려진 장비 줍기 — 분대의 자리에서 가장 가까운 것(CLAIM_M 안). 적이 버린 것도 줍는다
static func _claim(sq: BattleSquad, bf: Battlefield) -> void:
	if sq.routed or bf.equipments.is_empty():
		return
	var anchor := sq.anchor_x()
	var best: BattleEquipment = null
	var best_d := CLAIM_M
	for eq in bf.equipments:
		if eq.squad != null:
			continue
		var d := absf(eq.x - anchor)
		if d <= best_d:
			best_d = d
			best = eq
	if best == null:
		return
	best.squad = sq
	best.team = sq.team
	sq.equipment.append(best)
	if best.type.weapon != null:
		sq.range_m = maxf(sq.range_m, best.type.weapon.range_m)     # 분대가 장비의 사거리로 적을 본다
	bf.stats["claims"] += 1


# ───────────── 좌석 ─────────────

## 좌석 채우기 — 좌석 순서대로 가장 알맞은 병사(숙련도 → 이미 이 장비의 병사 → 같은 좌석 → 가까움). 앉은 병사의 자리도 정한다
static func _fill_seats(sq: BattleSquad, eq: BattleEquipment, act: Array[BattleSoldier]) -> void:
	var changed := false
	for i in eq.seats.size():
		var o := eq.seats[i]
		if o != null and (not o.can_fight() or o.detached or o.squad != sq):
			unseat(o)
			changed = true
	for i in eq.seats.size():
		var cur := eq.seats[i]
		var best := cur
		var best_k := _seat_key(cur, eq, i) if cur != null else -INF
		for s in act:
			if s == cur or s.carrying != null:
				continue
			if s.seat_eq != null and (s.seat_eq != eq or s.seat_idx <= i):
				continue                                            # 다른 장비에 앉았거나 이미 더 앞 좌석
			var k := _seat_key(s, eq, i)
			if k > best_k + 0.001:
				best_k = k
				best = s
		if best != cur:
			seat(best, eq, i)
			changed = true
	if changed:
		refresh_mods(eq)
	for i in eq.seats.size():
		var o := eq.seats[i]
		if o != null:
			o.goal_x = eq.seat_x(i)
			o.goal_depth = eq.seat_depth(i)
			o.cover = eq.cover                  # 분대 두뇌가 엄폐물을 바꾸며 지웠을 수 있다


static func _seat_key(s: BattleSoldier, eq: BattleEquipment, i: int) -> float:
	var k := s.skill(eq.type.skill_key) * 10.0
	if s.seat_eq == eq:
		k += 2.0 + (1.0 if s.seat_idx == i else 0.0)
	return k - absf(s.x - eq.seat_x(i)) * 0.01


## 좌석에 앉힌다 — 그 좌석에 있던 병사 · 이 병사가 있던 좌석은 비운다. 하던 능력(소총 사격 · 장전)은 끊는다
static func seat(s: BattleSoldier, eq: BattleEquipment, i: int) -> void:
	if s.seat_eq == eq and s.seat_idx == i:
		return
	unseat(s)
	var prev := eq.seats[i]
	if prev != null:
		unseat(prev)
	BattleBody.stop_act(s)
	if s.cover != null:
		s.cover.release(s)
	s.cover = eq.cover
	s.slot = -1
	s.in_cover = false
	s.seat_eq = eq
	s.seat_idx = i
	eq.seats[i] = s


## 좌석에서 내린다(쓰러짐 · 패닉 · 빙의 · 다른 좌석으로). 좌석 수정자도 뗀다
static func unseat(s: BattleSoldier) -> void:
	var eq := s.seat_eq
	if eq == null:
		return
	BattleBody.stop_act(s)
	if eq.reloader == s:
		eq.reloader = null
	if s.seat_idx >= 0 and s.seat_idx < eq.seats.size() and eq.seats[s.seat_idx] == s:
		eq.seats[s.seat_idx] = null
	s.seat_eq = null
	s.seat_idx = -1
	s.remove_mods(eq.mod_tag)
	if s.cover == eq.cover:
		s.cover = null
	s.in_cover = false


## 좌석 수정자를 다시 붙인다 — 효율(그 좌석이 맡는 수치에만) + 장전 담당이 비었으면 대신 장전하는 병사에 장전 × 빈 좌석 곱
static func refresh_mods(eq: BattleEquipment) -> void:
	var loader_empty := not eq.loader_present()
	for i in eq.seats.size():
		var o := eq.seats[i]
		if o == null:
			continue
		o.remove_mods(eq.mod_tag)
		var sd := eq.type.seats[i]
		var skill := o.skill(eq.type.skill_key)
		var eff := eq.type.efficiency(skill)
		var label := "좌석: %s · 숙련도 %d %% → 효율 %d %%" % [sd.role, roundi(skill * 100.0), roundi(eff * 100.0)]
		for st in sd.governs:
			o.add_mod(StatMod.make(st, StatMod.efficiency_mul(st, eff), 0.0, label, eq.mod_tag))
		if loader_empty and _has_backup_reload(sd):
			o.add_mod(StatMod.make(StatMod.RELOAD_TIME, eq.type.empty_loader_mult, 0.0,
				"빈 좌석: 장전 담당 없음 → 장전 ×%s" % str(eq.type.empty_loader_mult), eq.mod_tag))


static func _has_backup_reload(sd: SeatData) -> bool:
	for ab in sd.abilities:
		if ab is CrewReloadAbility and (ab as CrewReloadAbility).backup:
			return true
	return false


## 병사가 운용에서 빠진다(쓰러짐 · 패닉 · 빙의) — 좌석에서 내리고, 들고 있던 장비는 그 자리에 놓는다
static func release(s: BattleSoldier) -> void:
	var eq := s.seat_eq
	if eq != null:
		unseat(s)
		refresh_mods(eq)
	var c := s.carrying
	if c != null:
		drop(c)


## 들고 가던 장비를 운반병 자리에 놓는다
static func drop(eq: BattleEquipment) -> void:
	var c := eq.carrier
	if c != null and c.carrying == eq:          # 주우러 가던 병사(아직 안 든)면 장비는 제자리
		eq.x = c.x
		eq.depth = c.depth
		c.carrying = null
	eq.carrier = null
	if eq.state == BattleEquipment.State.CARRIED:
		eq.state = BattleEquipment.State.DROPPED


## 운용하던 분대가 없어졌다(전멸 · 패주) — 좌석을 비우고 버려진 장비로. 설치 중이면 놓인 채, 해체 중이면 설치된 채
static func abandon(bf: Battlefield, eq: BattleEquipment) -> void:
	for i in eq.seats.size():
		if eq.seats[i] != null:
			unseat(eq.seats[i])
	if eq.carrier != null:
		drop(eq)
	if eq.state == BattleEquipment.State.SETUP:
		eq.state = BattleEquipment.State.DROPPED
	elif eq.state == BattleEquipment.State.TEARDOWN:
		eq.state = BattleEquipment.State.READY
	if eq.squad != null:
		eq.squad.equipment.erase(eq)
	eq.squad = null
	bf.stats["abandoned"] += 1


## 해체가 끝났다 — 사수가 들고 간다(사수가 없으면 그 자리에 놓임)
static func pack(eq: BattleEquipment) -> void:
	var c: BattleSoldier = eq.seats[0] if not eq.seats.is_empty() else null
	for i in eq.seats.size():
		if eq.seats[i] != null:
			unseat(eq.seats[i])
	eq.cover = null
	eq.burst_count = 0
	if c != null and c.can_fight():
		eq.state = BattleEquipment.State.CARRIED
		eq.carrier = c
		c.carrying = eq
		BattleBody.stop_act(c)
	else:
		eq.state = BattleEquipment.State.DROPPED
