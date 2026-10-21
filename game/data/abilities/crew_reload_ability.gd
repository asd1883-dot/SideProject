extends Ability
class_name CrewReloadAbility

## 장비 장전 — 앉은 좌석의 운용 장비 탄을 채운다(부사수 좌석 · 장전 시간 = 장비 무기의 장전 시간, 부사수 효율이 붙음).  (보병_추상화.md §2-13)
## 대신 장전(backup = 켬, 사수 좌석): 장전 담당 좌석이 모두 비었을 때만 — 그때는 좌석이 "빈 좌석: 장전 × 2" 수정자를 붙여 둔다.
## 장전하는 동안 장비는 못 쏜다(장비의 reloader).

## 대신 장전 — 장전 담당 좌석(SeatData.loader)이 모두 비었을 때만 한다
@export var backup := false


func _init() -> void:
	display_name = "장비 장전"
	intent = "장전"
	priority = 1


static func _usable(s: BattleSoldier, backup_only: bool) -> bool:
	var eq := s.seat_eq
	if eq == null or eq.state != BattleEquipment.State.READY or not eq.at_seat(s):
		return false
	if eq.reloader != null and eq.reloader != s:
		return false
	return not (backup_only and eq.loader_present(s))


func score(s: BattleSoldier, _bf: Battlefield, c: BrainCtx) -> float:
	if not _usable(s, backup):
		return 0.0
	var eq := s.seat_eq
	if eq.ammo <= 0:
		return 0.9
	if eq.ammo * 10 < eq.mag_size() * 4 and not c.has_target:
		return 0.5
	return 0.0


func apply(s: BattleSoldier, _c: BrainCtx) -> void:
	s.want_reload = true


## 대기 중 — 표적이 없을 때만 덜 찬 탄을 채운다(사수가 쏘는 중에 장전으로 끊지 않게)
func idle(s: BattleSoldier, c: BrainCtx) -> void:
	if not c.has_target and _usable(s, backup) and s.seat_eq.ammo < s.seat_eq.mag_size():
		s.want_reload = true


func wants(s: BattleSoldier) -> bool:
	return s.want_reload and _usable(s, backup) and s.seat_eq.ammo < s.seat_eq.mag_size()


func begin(s: BattleSoldier, _bf: Battlefield) -> void:
	var eq := s.seat_eq
	eq.reloader = s
	s.phase = Phase.EXEC
	s.act_state = BattleBody.Act.RELOAD
	s.act_timer = s.stat(StatMod.RELOAD_TIME, eq.type.weapon.reload_time)


func step(s: BattleSoldier, _bf: Battlefield, dt: float) -> bool:
	if not _usable(s, false):
		return false
	s.act_timer -= dt
	if s.act_timer > 0.0:
		return true
	var eq := s.seat_eq
	eq.ammo = eq.mag_size()
	eq.burst_count = 0
	return false


func stop(s: BattleSoldier) -> void:
	if s.seat_eq != null and s.seat_eq.reloader == s:
		s.seat_eq.reloader = null
