extends Ability
class_name ReloadAbility

## 장전 — 탄창을 갈아 끼운다(실행 = 장전 동작, 무기의 장전 시간). 끝나면 탄이 가득.  (보병_추상화.md §2-13)
## 두뇌 점수: 탄이 없으면 높게(0.9) · 표적이 없는데 40 % 아래면 조금(0.5). "대기" 때는 덜 찬 탄창을 채운다.

const S_CROUCH := BattleBody.Stance.CROUCH


func _init() -> void:
	display_name = "장전"
	intent = "장전"
	priority = 1


func score(s: BattleSoldier, _bf: Battlefield, c: BrainCtx) -> float:
	var mag := s.type.weapon.mag_size
	if s.ammo <= 0:
		return 0.9
	if s.ammo * 10 < mag * 4 and not c.has_target:
		return 0.5
	return 0.0


func apply(s: BattleSoldier, c: BrainCtx) -> void:
	s.want_reload = true
	s.want_stance = s.cover.hide_stance() if c.at_cover else S_CROUCH


func idle(s: BattleSoldier, _c: BrainCtx) -> void:
	s.want_reload = s.ammo < s.type.weapon.mag_size


func wants(s: BattleSoldier) -> bool:
	return s.want_reload and s.ammo < s.type.weapon.mag_size


func begin(s: BattleSoldier, _bf: Battlefield) -> void:
	s.phase = Phase.EXEC
	s.act_state = BattleBody.Act.RELOAD
	s.act_timer = s.type.weapon.reload_time


func step(s: BattleSoldier, _bf: Battlefield, dt: float) -> bool:
	s.act_timer -= dt
	if s.act_timer > 0.0:
		return true
	s.ammo = s.type.weapon.mag_size
	return false
