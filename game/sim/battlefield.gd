extends Node
class_name Battlefield

## 전장 관리자 — 병사 · 분대 · 엄폐물 기록을 배열로 들고 논리를 돌린다. 병사마다 논리 노드를 두지 않는다.  (보병_추상화.md §2-6)
##
## 한 걸음(step)의 순서:
##   구역 나누기 → 분대(사기 · 패주 · 분대 두뇌) → 병사(병사 두뇌 → 몸) → 늦게 도착하는 총알 결과 적용
## 화면은 BattleView 가 이 기록을 읽어서 그린다. 여기엔 그림 코드가 없다.
##
## 단위: x = m(전선 방향, 0 ~ length_m) · 깊이 = 0 ~ 1 · 높이 = m(땅 = 0)

## 총알 한 발. {from: Vector3(x, 높이, 깊이), to: Vector3, flight: 초, team: int, hit: BattleSoldier 또는 null, blocked: bool}
signal shot_fired(shot: Dictionary)
signal soldier_spawned(s: BattleSoldier)
signal soldier_died(s: BattleSoldier)
signal soldier_panicked(s: BattleSoldier)

@export var length_m := 120.0
## 깊이 0 ~ 1 이 실제로 몇 m 인가(퍼짐 원을 깊이로 바꿀 때 · 근처를 지나간 총알의 거리)
@export var depth_width_m := 6.0
@export var running := true

const BUCKET_M := 4.0           # 조회용 x 구역 폭
const ROUT_BELOW := 0.15        # 사기가 이 아래면 패주
const RALLY_ABOVE := 0.45       # 이 위로 회복하면 재집결
const PANIC_ENEMY_M := 8.0      # 패주 중 적이 이만큼 가까우면 패닉
const PRUNE_EVERY := 5.0        # 이 주기로 죽은 병사 기록 · 빈 분대를 배열에서 뺀다

var time := 0.0
var soldiers: Array[BattleSoldier] = []
var squads: Array[BattleSquad] = []
var covers: Array[BattleCover] = []
var rng := RandomNumberGenerator.new()
## 디버그 통계
var stats := {"shots": 0, "hits": 0, "blocked": 0, "kills": [0, 0], "panics": [0, 0]}

var _buckets: Dictionary = {}       # 구역 번호 -> Array[BattleSoldier]
var _pending: Array = []            # 날아가는 중인 총알의 결과 [{t, target, dmg, shooter, near, power}]
var _next_id := 1
var _prune_timer := PRUNE_EVERY
var _next_squad_id := 1


func _physics_process(delta: float) -> void:
	if running:
		step(delta)


func step(dt: float) -> void:
	time += dt
	_rebuild_buckets()
	for sq in squads:
		_update_squad_state(sq, dt)
		SquadBrain.tick(sq, self, dt)
	for s in soldiers:
		if not s.alive:
			continue
		if s.controller == 0:
			SoldierBrain.tick(s, self, dt)
		BattleBody.step(s, self, dt)
	_apply_pending()
	_prune_timer -= dt
	if _prune_timer <= 0.0:
		_prune_timer = PRUNE_EVERY
		_prune()


## 죽은 병사 기록과 아무도 안 남은 분대를 배열에서 뺀다 — 오래 싸우면 기록이 끝없이 쌓여 매 걸음 훑는 값이 는다.
## (화면 쪽은 쓰러진 병사를 자기 목록에 따로 들고 있으므로 여기서 빼도 쓰러진 모습은 남는다)
func _prune() -> void:
	var kept: Array[BattleSoldier] = []
	for s in soldiers:
		if s.alive:
			kept.append(s)
	soldiers = kept
	var kept_sq: Array[BattleSquad] = []
	for sq in squads:
		var any := false
		for s in sq.members:
			if s.alive:
				any = true
				break
		if any:
			kept_sq.append(sq)
		else:
			sq.members.clear()
			sq.cover = null
	squads = kept_sq


## 기록끼리 서로 물고 있는 고리(병사 ↔ 분대 ↔ 엄폐물 · 표적)를 끊는다 — 안 끊으면 전장을 지워도 기록이 메모리에 남는다
func clear() -> void:
	for s in soldiers:
		s.squad = null
		s.cover = null
		s.target = null
	for sq in squads:
		sq.members.clear()
		sq.cover = null
	for c in covers:
		c.slot_owner.clear()
	_pending.clear()
	_buckets.clear()
	soldiers.clear()
	squads.clear()
	covers.clear()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		clear()


# ───────────── 기본 ─────────────

## 그 편의 "앞" 방향(+1 / −1)
func forward(team: int) -> int:
	return 1 if team == 0 else -1


## 그 편이 나오는 맵 끝의 x
func home_x(team: int) -> float:
	return 0.0 if team == 0 else length_m


## 엄폐물 놓기. wall_side: +1 = +x 쪽 끝에 벽 · −1 = −x 쪽 끝 · 0 = 양쪽(참호). slots = 0 이면 길이로 정한다
func add_cover(x0: float, x1: float, kind: int, wall_side: int, slots: int = 0) -> BattleCover:
	var c := BattleCover.new()
	c.id = covers.size() + 1
	c.x0 = minf(x0, x1)
	c.x1 = maxf(x0, x1)
	c.kind = kind
	c.wall_side = wall_side
	c.build_slots(slots)
	covers.append(c)
	return c


## 분대 투입 — 그 편의 맵 끝에서 분대째로 나온다(§2-7 고정 분대 · 안건 E)
func deploy_squad(team: int, type: SoldierType, order: int = BattleSquad.Order.ADVANCE) -> BattleSquad:
	var sq := BattleSquad.new()
	sq.id = _next_squad_id
	_next_squad_id += 1
	sq.team = team
	sq.type = type
	sq.order = order
	var fwd := forward(team)
	var base_x := home_x(team) + float(fwd) * 1.5
	var size := maxi(type.squad_size, 1)
	for i in size:
		var s := BattleSoldier.new()
		s.id = _next_id
		_next_id += 1
		s.team = team
		s.type = type
		s.squad = sq
		s.x = clampf(base_x + float(fwd) * rng.randf_range(0.0, 1.5), 0.0, length_m)
		s.depth = clampf((float(i) + 0.5) / float(size) + rng.randf_range(-0.04, 0.04), 0.03, 0.97)
		s.facing = fwd
		s.hp = type.max_hp
		s.ammo = type.weapon.mag_size
		s.goal_x = s.x
		s.goal_depth = s.depth
		s.brain_timer = rng.randf() * 0.4
		sq.members.append(s)
		soldiers.append(s)
		soldier_spawned.emit(s)
	sq.goal_x = base_x
	squads.append(sq)
	return sq


# ───────────── 조회 ─────────────

func _rebuild_buckets() -> void:
	_buckets.clear()
	for s in soldiers:
		if not s.alive:
			continue
		var k := int(floor(s.x / BUCKET_M))
		if _buckets.has(k):
			(_buckets[k] as Array).append(s)
		else:
			_buckets[k] = [s]


## x0 ~ x1 구간의 구역에 든 살아 있는 병사 전부(편 가리지 않음, 구간 밖 병사가 조금 섞일 수 있다)
func soldiers_between(x0: float, x1: float) -> Array:
	var out: Array = []
	var k0 := int(floor(minf(x0, x1) / BUCKET_M))
	var k1 := int(floor(maxf(x0, x1) / BUCKET_M))
	for k in range(k0, k1 + 1):
		if _buckets.has(k):
			out.append_array(_buckets[k])
	return out


## x 에서 range_m 안의 적(x 거리만 — §2-1). 패닉 병사는 표적이 아니므로 빠진다
func enemies_near(team: int, x: float, range_m: float) -> Array[BattleSoldier]:
	var out: Array[BattleSoldier] = []
	for e in soldiers_between(x - range_m, x + range_m):
		var es: BattleSoldier = e
		if es.team != team and es.can_fight() and absf(es.x - x) <= range_m:
			out.append(es)
	return out


## 가장 가까운 적까지의 x 거리(range_m 안에 없으면 INF)
func nearest_enemy_dist(team: int, x: float, range_m: float) -> float:
	var best := INF
	for e in enemies_near(team, x, range_m):
		best = minf(best, absf(e.x - x))
	return best


# ───────────── 사격 · 피해 ─────────────

## 병사가 한 발 쏜다(몸이 부른다). 퍼짐 원 + 경로 판정은 Ballistics
func fire(s: BattleSoldier) -> void:
	Ballistics.fire(self, s)


## 비행 시간 뒤에 적용할 결과를 걸어 둔다
func schedule_impact(flight: float, target: BattleSoldier, dmg: float, shooter: BattleSoldier, near: Array, power: float) -> void:
	_pending.append({"t": time + flight, "target": target, "dmg": dmg, "shooter": shooter, "near": near, "power": power})


func _apply_pending() -> void:
	var i := _pending.size() - 1
	while i >= 0:
		var p: Dictionary = _pending[i]
		if time >= float(p["t"]):
			_pending.remove_at(i)
			for n in (p["near"] as Array):
				add_suppression(n as BattleSoldier, float(p["power"]))
			if p["target"] != null:
				_hit(p["target"] as BattleSoldier, float(p["dmg"]), p["shooter"] as BattleSoldier)
		i -= 1


## 제압 쌓기 — 사기가 낮으면 더 빨리 쌓인다(§2-8)
func add_suppression(s: BattleSoldier, amount: float) -> void:
	if s == null or not s.can_fight():
		return
	var morale := s.squad.morale if (s.squad != null and not s.detached) else 0.6
	s.suppression = minf(BattleBody.SUPPRESS_MAX, s.suppression + amount / maxf(s.type.suppress_resist, 0.1) * lerpf(1.6, 0.8, morale))


func _hit(target: BattleSoldier, dmg: float, shooter: BattleSoldier) -> void:
	if not target.alive:
		return
	stats["hits"] += 1
	target.hp -= dmg
	if target.hp <= 0.0:
		_kill(target, shooter)
		return
	if target.override != BattleBody.Ovr.PANIC:
		target.override = BattleBody.Ovr.HIT
		target.ovr_timer = BattleBody.HIT_STUN
		BattleBody.stop_act(target)
		add_suppression(target, 0.5)


func _kill(s: BattleSoldier, shooter: BattleSoldier) -> void:
	var was_panic := s.override == BattleBody.Ovr.PANIC
	s.override = BattleBody.Ovr.DEAD
	BattleBody.stop_act(s)
	s.move_state = BattleBody.Move.IDLE
	s.want_fire = false
	s.target = null
	_leave_cover(s)
	if shooter != null:
		stats["kills"][shooter.team] += 1
		if shooter.squad != null and not shooter.detached:
			shooter.squad.morale = minf(1.0, shooter.squad.morale + 0.04)
	if s.squad != null and not s.detached and not was_panic:      # 패닉은 이미 사상자로 셌다
		s.squad.morale = maxf(0.0, s.squad.morale - 0.12)
	soldier_died.emit(s)


func _leave_cover(s: BattleSoldier) -> void:
	if s.cover != null:
		s.cover.release(s)
	s.cover = null
	s.slot = -1
	s.in_cover = false


## 패닉 — 그 자리에서 통제 불능. 표적 후보에서 빠지고(게임 흐름에선 무시) 날아온 총알엔 맞는다. 회복 없음(§2-8)
func panic(s: BattleSoldier) -> void:
	if not s.can_fight():
		return
	s.override = BattleBody.Ovr.PANIC
	BattleBody.stop_act(s)
	s.want_fire = false
	s.target = null
	_leave_cover(s)
	stats["panics"][s.team] += 1
	if s.squad != null:
		s.squad.morale = maxf(0.0, s.squad.morale - 0.08)       # 분대는 사상자처럼 센다
	soldier_panicked.emit(s)


# ───────────── 사기 · 패주 (§2-8) ─────────────

func _update_squad_state(sq: BattleSquad, dt: float) -> void:
	var act := sq.active()
	if act.is_empty():
		return
	var supp := sq.avg_suppression()
	var anchor := sq.anchor_x()
	if supp > 0.6:
		sq.morale -= 0.05 * supp * dt                       # 제압이 오래 이어짐
	elif nearest_enemy_dist(sq.team, anchor, 40.0) == INF:
		sq.morale += 0.04 * dt                              # 적과 떨어져 있으면 빨리 회복
	else:
		sq.morale += 0.015 * dt
	sq.morale = clampf(sq.morale, 0.0, 1.0)
	if not sq.routed and sq.morale < ROUT_BELOW:
		sq.routed = true
		sq.cover = null
		for s in act:
			_leave_cover(s)
	elif sq.routed and sq.morale > RALLY_ABOVE:
		sq.routed = false
	if sq.routed:
		for s in act:
			var at_edge := absf(s.x - home_x(s.team)) <= 1.0
			if at_edge or nearest_enemy_dist(s.team, s.x, PANIC_ENEMY_M) != INF:
				panic(s)


# ───────────── 빙의 (§2-3 · §2-7) ─────────────

## 플레이어가 이 병사를 직접 조종한다 — 조종자 칸만 바꾸고, 병사는 분대에서 빠진다
func possess(s: BattleSoldier) -> bool:
	if s == null or not s.can_fight():
		return false
	s.controller = 1
	s.detached = true
	s.use_goal = false
	s.move_dir = 0
	s.want_fire = false
	s.want_reload = false
	s.want_run = false
	s.target = null
	s.goal_depth = s.depth
	s.intent_name = "직접 조종"
	s.intent_scores = {}
	_leave_cover(s)
	return true


## 빙의를 푼다 — 원래 분대로 돌아간다(분대 두뇌가 다음 판단 때 자리를 준다)
func release(s: BattleSoldier) -> void:
	if s == null:
		return
	s.controller = 0
	s.detached = false
	s.use_goal = true
	s.move_dir = 0
	s.want_fire = false
	s.goal_x = s.x
	s.brain_timer = 0.0
	if s.squad != null:
		s.squad.brain_timer = 0.0


## 그 편의 살아서 싸울 수 있는 병사 수
func count_fighting(team: int) -> int:
	var k := 0
	for s in soldiers:
		if s.team == team and s.can_fight():
			k += 1
	return k
