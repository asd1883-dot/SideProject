extends RefCounted
class_name Ballistics

## 명중 판정 — 퍼짐 원 + 경로 판정.  (보병_추상화.md §2-12, 사용자 안)
##
## 사수마다 퍼짐 원(각도)이 있고, 쏠 때마다 원 안의 한 점으로 총알 방향이 정해진다. "명중률" 숫자는 없다.
## 원 = 높이 × 깊이 → 총알은 (x, 높이, 깊이) 직선. 날아가다 **처음 닿는 것**에 맞는다:
##   적 병사의 몸 상자 → 히트 / 엄폐물의 벽 · 땅 → 박힘 / 아무것도 없으면 사거리 끝까지
## 총알을 움직이는 물체로 만들지 않는다. 쏘는 순간 경로를 구역 단위로 훑어 결과를 정해 두고,
## 비행 시간만큼 늦게 적용한다(Battlefield.schedule_impact). 화면엔 예광 그림만 날아간다.
##
## 규칙: 자기가 들어가 있는 엄폐물은 자기 총알을 막지 않는다 · 총알은 아군을 지나간다 ·
##       근처를 지나간 총알은 그 병사에게 제압을 쌓는다 · 패닉 병사는 표적이 아니지만 경로 위면 맞는다

const MUZZLE_AHEAD_M := 0.4         # 총구가 몸보다 앞에 있는 거리
const RANGE_OVERSHOOT := 1.5        # 빗나간 총알이 사거리의 몇 배까지 날아가나
const OWN_COVER_NEAR_M := 6.0       # 분대 엄폐물에서 이 안에 있으면 그 벽은 자기 총알을 안 막는다
const LEAN_M := 1.2                 # 총구에서 이 안에 있는 벽은 기대어 쏘는 것으로 본다


## 병사가 자기 무기(병종의 무기)로 한 발 — 사격 능력(FireAbility)이 부른다
static func fire(bf: Battlefield, s: BattleSoldier) -> void:
	var t := s.type
	var w := t.weapon
	var aim := aim_of(s)
	# 퍼짐 원(도) = 무기 기본 × 자세 × (걸으며 쏘면) × 제압 + 연사로 넓어진 양
	var moving := s.move_state == BattleBody.Move.WALK or s.move_state == BattleBody.Move.RUN or s.move_state == BattleBody.Move.CRAWL
	var spread := s.stat(StatMod.SPREAD, w.spread_deg) * t.spread_stance_mult(s.stance)
	if moving:
		spread *= w.spread_move_mult
	spread *= 1.0 + t.spread_suppressed_add * clampf(s.suppression, 0.0, 1.0)
	spread += s.bloom_deg
	shoot(bf, s, w, s.x, MUZZLE_AHEAD_M, t.muzzle_height(s.stance), s.depth, spread, aim)
	s.ammo -= 1
	s.bloom_deg += w.spread_per_shot_deg


## 조준점 — AI 는 표적의 드러난 부분 가운데, 플레이어는 커서(aim_*)
static func aim_of(s: BattleSoldier) -> Vector3:
	if s.controller == 0 and s.target != null:
		return aim_point(s, s.target)
	return Vector3(s.aim_x, s.aim_h, s.aim_depth)


## 한 발 — 쏘는 자리(ox: 몸 · 장비의 x, ahead: 총구가 앞에 있는 거리, mh: 총구 높이, md: 깊이)와 퍼짐 원(도)으로.
## 탄 · 연사 퍼짐은 부른 쪽(능력)이 줄이고 늘린다 — 병사의 소총이면 병사의 것, 운용 장비면 장비의 것
static func shoot(bf: Battlefield, s: BattleSoldier, w: WeaponData, ox: float, ahead: float, mh: float, md: float, spread: float, aim: Vector3) -> void:
	var dir := 1 if aim.x >= ox else -1
	var mx := ox + float(dir) * ahead
	var dist := maxf(absf(aim.x - mx), 0.5)
	# 원 안의 고른 한 점 → 방향의 어긋남(위아래 · 깊이)
	var ang := bf.rng.randf() * TAU
	var rad := sqrt(bf.rng.randf()) * deg_to_rad(spread)
	var slope_h := (aim.y - mh) / dist + tan(cos(ang) * rad)                        # x 1 m 에 높이가 얼마나 변하나
	var slope_d := (aim.z - md) / dist + tan(sin(ang) * rad) / bf.depth_width_m     # x 1 m 에 깊이(0~1)가 얼마나 변하나
	bf.stats["shots"] += 1

	var res := trace(bf, s, mx, mh, md, dir, slope_h, slope_d, w.range_m * RANGE_OVERSHOOT, w.suppress_radius_m)
	var travel := float(res["t"])
	var flight := travel / maxf(w.bullet_speed, 1.0)
	var hit: BattleSoldier = res["hit"]
	if bool(res["blocked"]):
		bf.stats["blocked"] += 1
	bf.schedule_impact(flight, hit, s.stat(StatMod.DAMAGE, w.damage), s, res["near"], w.suppress_power)
	bf.shot_fired.emit({
		"from": Vector3(mx, mh, md),
		"to": Vector3(mx + float(dir) * travel, mh + slope_h * travel, md + slope_d * travel),
		"flight": flight,
		"team": s.team,
		"hit": hit,
		"blocked": bool(res["blocked"]),
		"weapon": w,
	})


## 자기 총알을 막지 않는 엄폐물인가 — 들어가 있는 엄폐물, 또는 바로 뒤에 줄 선 분대 엄폐물
static func _is_own_cover(c: BattleCover, s: BattleSoldier) -> bool:
	if c == s.cover and s.in_cover:
		return true
	if s.seat_eq != null and c == s.seat_eq.cover:
		return true                                 # 운용 장비를 설치한 엄폐물 — 총구가 벽 위에 걸쳐 있다

	return s.squad != null and not s.detached and c == s.squad.cover and absf(s.x - c.center_x()) < OWN_COVER_NEAR_M


## 그 자세로 쏘면 조준점까지 가는 곧은 길이 벽에 막히나(퍼짐은 빼고). 두뇌가 쏘기 전에 본다 —
## 안 보면 칸을 못 얻고 뒤에 선 병사들이 아군 모래주머니에 대고 쏜다(10-13 시험: 1377발 중 15발 명중)
static func line_blocked(bf: Battlefield, s: BattleSoldier, stance: int, aim: Vector3) -> bool:
	return line_blocked_at(bf, s, s.x, MUZZLE_AHEAD_M, s.type.muzzle_height(stance), aim)


## line_blocked 의 쏘는 자리를 직접 주는 판 — 운용 장비(총구 = 장비 자리 · 장비의 총구 높이)
static func line_blocked_at(bf: Battlefield, s: BattleSoldier, ox: float, ahead: float, mh: float, aim: Vector3) -> bool:
	var dir := 1 if aim.x >= ox else -1
	var mx := ox + float(dir) * ahead
	var dist := maxf(absf(aim.x - mx), 0.5)
	var slope_h := (aim.y - mh) / dist
	for c in bf.covers:
		if _is_own_cover(c, s):
			continue
		for wx in c.wall_xs():
			var tw := (wx - mx) * float(dir)
			if tw <= LEAN_M or tw >= dist:
				continue
			if mh + slope_h * tw < c.wall_height():
				return true
	return false


## 표적의 어디를 겨누나 — 표적이 엄폐 뒤면 벽 위로 드러난 부분의 가운데. 다 숨었으면 벽 바로 위(제압 사격)
static func aim_point(s: BattleSoldier, e: BattleSoldier) -> Vector3:
	var top := e.type.box(e.stance).y
	var low := 0.0
	if e.in_cover and e.cover != null:
		for wx in e.cover.wall_xs():
			if (wx - s.x) * (e.x - wx) > 0.0:           # 그 벽이 나와 표적 사이에 있다
				low = maxf(low, e.cover.wall_height())
	var h := top * 0.6
	if low > 0.0:
		h = (low + top) * 0.5 if top > low + 0.05 else low + 0.15
	return Vector3(e.x, h, e.depth)


## 총알 경로를 훑는다. 돌려주는 것: {t: 날아간 x 거리(m), hit: 맞은 병사 또는 null, blocked: 벽 · 땅에 박혔나, near: 근처를 지나간 병사들}
static func trace(bf: Battlefield, s: BattleSoldier, mx: float, mh: float, md: float, dir: int, slope_h: float, slope_d: float, max_t: float, near_radius: float) -> Dictionary:
	var best_t := max_t
	var hit: BattleSoldier = null
	var blocked := false

	# 땅
	if slope_h < 0.0:
		var tg := mh / -slope_h
		if tg < best_t:
			best_t = tg
			blocked = true

	# 엄폐물의 벽 — 자기가 들어가 있는 엄폐물은 건너뛴다.
	# 칸을 못 얻어 분대 엄폐물 바로 뒤에 선 병사도 같다(안 그러면 앉아 쏘는 총알이 아군 모래주머니에 다 박힌다)
	for c in bf.covers:
		if _is_own_cover(c, s):
			continue
		for wx in c.wall_xs():
			var tw := (wx - mx) * float(dir)
			if tw <= LEAN_M or tw >= best_t:    # 바로 앞의 벽은 기대어 쏘는 것 — 막지 않는다(빙의 병사는 칸이 없어도 벽에 붙어 쏠 수 있다)
				continue
			var hw := mh + slope_h * tw
			if hw >= 0.0 and hw < c.wall_height():
				best_t = tw
				blocked = true

	# 병사 — 아군은 지나간다. 구역 단위로 근처만 본다
	var near_cands: Array = []          # [[t, 병사]] — 나중에 "맞은 곳보다 앞"인 것만 남긴다
	for o in bf.soldiers_between(mx, mx + float(dir) * best_t):
		var e: BattleSoldier = o
		if e.team == s.team or e == s:
			continue
		var tc := (e.x - mx) * float(dir)
		if tc <= 0.0:
			continue
		var box := e.type.box(e.stance)
		var t1 := maxf(tc - box.x * 0.5, 0.0)
		if t1 >= best_t:
			continue
		var t2 := tc + box.x * 0.5
		var h1 := mh + slope_h * t1
		var h2 := mh + slope_h * t2
		var d_at := md + slope_d * tc
		var d_gap := maxf(absf(d_at - e.depth) - e.type.body_depth, 0.0)
		if maxf(h1, h2) >= 0.0 and minf(h1, h2) <= box.y and d_gap <= 0.0:
			best_t = t1
			hit = e
			blocked = false
			continue
		if not e.can_fight():
			continue                    # 패닉 병사는 맞을 수는 있어도 제압은 안 쌓인다
		# 빗나갔다 — 몸 상자에서 얼마나 떨어져 지나갔나(m)
		var hc := mh + slope_h * tc
		var h_gap := maxf(maxf(hc - box.y, -hc), 0.0)
		var d_gap_m := d_gap * bf.depth_width_m
		if h_gap * h_gap + d_gap_m * d_gap_m <= near_radius * near_radius:
			near_cands.append([tc, e])

	var near: Array = []
	for nc in near_cands:
		if float(nc[0]) <= best_t + 0.5:
			near.append(nc[1])
	return {"t": best_t, "hit": hit, "blocked": blocked, "near": near}
