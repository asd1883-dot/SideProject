extends Ability
class_name CrewFireAbility

## 장비 사격 — 앉은 좌석의 운용 장비(BattleEquipment)로 쏜다: 장비의 무기 수치 · 탄 · 총구 자리 · 연사 퍼짐.  (보병_추상화.md §2-13)
## 사수 좌석이 준다. 장비가 "준비"(설치 끝)이고 사수가 좌석 자리에 있고 장전 중이 아닐 때만.
## 효율: 사수 좌석이 맡는 수치(퍼짐 · 조준 시간 · 선회)에 좌석 수정자가 붙어 있다 — 여기선 stat() 으로 읽기만 한다.
## 표적이 총구 반대쪽이면 선회(180° ÷ 선회 빠르기)만큼 더 겨눈다. 장비는 사수 자리를 축으로 돈다(좌석 자리가 그대로).
## 점사: 무기의 burst 발을 쏘면 burst_pause 쉰다 — 점사 중엔 사격 자세, 쉬는 동안엔 조준 자세.


func _init() -> void:
	display_name = "장비 사격"
	intent = "사격"
	priority = 0


static func _ready_gun(s: BattleSoldier) -> bool:
	var eq := s.seat_eq
	return eq != null and eq.state == BattleEquipment.State.READY and eq.at_seat(s) and eq.reloader == null and eq.ammo > 0


func score(s: BattleSoldier, bf: Battlefield, c: BrainCtx) -> float:
	var eq := s.seat_eq
	if eq == null or not c.has_target:
		return 0.0
	var aim := Ballistics.aim_point(s, s.target)
	var dir := 1 if aim.x >= eq.x else -1
	var ox := eq.x if dir == eq.facing else eq.seat_x(s.seat_idx) - float(dir) * eq.type.seats[s.seat_idx].offset.x   # 돌고 난 뒤의 장비 자리
	var clear := not Ballistics.line_blocked_at(bf, s, ox, eq.type.muzzle_ahead_m, eq.type.muzzle_height, aim)
	var setting := eq.state == BattleEquipment.State.SETUP or eq.state == BattleEquipment.State.READY
	c.engage = setting and (clear or eq.ammo <= 0)                     # 설치 중이어도 교전 중(분대가 자리를 지킨다)
	if not clear or not _ready_gun(s):
		return 0.0
	return (0.85 if c.arrived else 0.45) - 0.35 * c.supp + (0.4 if c.near_enemy else 0.0)


func apply(s: BattleSoldier, _c: BrainCtx) -> void:
	s.want_fire = true


func wants(s: BattleSoldier) -> bool:
	return s.want_fire and _ready_gun(s)


func begin(s: BattleSoldier, _bf: Battlefield) -> void:
	var eq := s.seat_eq
	s.phase = Phase.PREP
	s.act_state = BattleBody.Act.AIM
	s.act_timer = s.stat(StatMod.AIM_TIME, eq.type.weapon.aim_time)
	_turn(s, eq)


func step(s: BattleSoldier, bf: Battlefield, dt: float) -> bool:
	if not s.want_fire or not _ready_gun(s):
		return false
	var eq := s.seat_eq
	var w := eq.type.weapon
	_turn(s, eq)
	s.act_timer -= dt
	if s.act_timer > 0.0 or eq.fire_cooldown > 0.0:
		# 점사 사이 쉼 — 마지막 발의 사격 자세를 잠깐 보인 뒤 겨눈 자세로
		if s.phase == Phase.EXEC and eq.burst_count == 0 and eq.fire_cooldown < w.burst_pause - BattleBody.FIRE_POSE:
			s.phase = Phase.PREP
			s.act_state = BattleBody.Act.AIM
		return true
	_shoot(s, bf, eq, w)
	s.phase = Phase.EXEC
	s.act_state = BattleBody.Act.FIRE
	s.act_timer = 0.0                       # 점사 중 다음 발은 연사 간격(장비의 fire_cooldown)만 기다린다
	return true


## 표적이 총구 반대쪽이면 돈다 — 사수 자리를 축으로(좌석 자리가 그대로라 병사가 안 옮겨도 된다), 선회 시간만큼 더 겨눈다
static func _turn(s: BattleSoldier, eq: BattleEquipment) -> void:
	var aim := Ballistics.aim_of(s)
	var dir := 1 if aim.x >= eq.x else -1
	if dir == eq.facing:
		return
	var pivot := eq.seat_x(s.seat_idx)
	eq.facing = dir
	eq.x = pivot - float(dir) * eq.type.seats[s.seat_idx].offset.x
	eq.burst_count = 0
	s.phase = Phase.PREP
	s.act_state = BattleBody.Act.AIM
	s.act_timer = maxf(s.act_timer, 0.0) + 180.0 / maxf(s.stat(StatMod.TRAVERSE, eq.type.traverse_deg_s), 1.0)


static func _shoot(s: BattleSoldier, bf: Battlefield, eq: BattleEquipment, w: WeaponData) -> void:
	# 퍼짐 원 = 무기 기본(좌석 효율 반영) × 제압 + 연사로 넓어진 양. 땅에 놓인 장비라 자세 · 걸음 곱은 없다
	var spread := s.stat(StatMod.SPREAD, w.spread_deg) * (1.0 + s.type.spread_suppressed_add * clampf(s.suppression, 0.0, 1.0)) + eq.bloom_deg
	Ballistics.shoot(bf, s, w, eq.x, eq.type.muzzle_ahead_m, eq.type.muzzle_height, eq.depth, spread, Ballistics.aim_of(s))
	eq.ammo -= 1
	eq.bloom_deg += w.spread_per_shot_deg
	eq.burst_count += 1
	if w.burst > 0 and eq.burst_count >= w.burst:
		eq.burst_count = 0
		eq.fire_cooldown = w.burst_pause
	else:
		eq.fire_cooldown = s.stat(StatMod.FIRE_INTERVAL, w.fire_interval)
