extends SceneTree

## 안건 F 검사 — 수정자 · 운용 장비(좌석) · 섞인 분대가 도는지 화면 없이 본다(10-21).  (보병_추상화.md §2-13)
##   Godot --headless --path <프로젝트> --script res://game/tools/equip_smoke.gd [-- --seconds=120 --seed=1941]
## 보는 것
##   [1] 수정자 쌓기 — 곱 · 더하기 · 시간이 다 되면 빠짐 · 꼬리표로 빼기
##   [2] 효율 — 숙련도 0 · 0.5 · 1 → 75 · 87.5 · 100 %, 좌석이 맡는 수치에만(사수 = 퍼짐 · 조준 · 선회, 부사수 = 장전, 몸 수치는 그대로)
##   [3] 빈 장전 좌석 — 부사수가 없으면 사수가 장전 × 2(수치 · 실제로 걸린 시간)
##   [4] 사수 사망 → 부사수가 사수로 · 남은 병사가 부사수로
##   [5] 버려진 장비 → 아군이 다시 운용(효율 75 %) → 또 버려짐 → 적이 다시 운용해서 그쪽으로 돌려 쏨
##   [6] 시험 전장에서 MG42 팀(기관총수 3 + MG42)이 운반 → 설치 → 실제로 쏘고 맞히는가
## 마지막 줄이 "EQUIP SMOKE OK" 면 통과.

const RIFLE_PATH := "res://game/units/rifleman.tres"
const TEAM_PATH := "res://game/units/mg42_team.tres"
const DT := 1.0 / 60.0
const TestField := preload("res://game/tools/test_field.gd")

var _fails := PackedStringArray()
var _notes := PackedStringArray()


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var eq := s.find("=")
		args[s if eq < 0 else s.substr(0, eq)] = "1" if eq < 0 else s.substr(eq + 1)
	var rifle := load(RIFLE_PATH) as SoldierType
	var team := load(TEAM_PATH) as SquadComp
	if rifle == null or team == null:
		print("EQUIP SMOKE FAIL 리소스가 없습니다 — make_default_units.gd 를 먼저 돌리세요")
		quit(1)
		return
	var seed_v := int(args.get("seed", "1941"))
	_mods_check(rifle)
	_efficiency_check(rifle, team)
	_crew_check(rifle, team, seed_v)
	_battle_check(rifle, team, seed_v, float(args.get("seconds", "120")))
	for n in _notes:
		print(n)
	if _fails.is_empty():
		print("EQUIP SMOKE OK")
	else:
		print("EQUIP SMOKE FAIL ", " · ".join(_fails))
	quit(0 if _fails.is_empty() else 1)


func _check(ok: bool, what: String, detail: String = "") -> void:
	_notes.append("  %s %s%s" % ["✓" if ok else "✗", what, ("  (" + detail + ")") if detail != "" else ""])
	if not ok:
		_fails.append(what)


# ───────────── [1] 수정자 ─────────────

func _mods_check(rifle: SoldierType) -> void:
	_notes.append("[1] 수정자 쌓기")
	var s := BattleSoldier.new()
	s.type = rifle
	var base := rifle.weapon.spread_deg
	s.add_mod(StatMod.make(StatMod.SPREAD, 1.1, 0.0, "버프 가", "t1"))
	s.add_mod(StatMod.make(StatMod.SPREAD, 1.2, 0.0, "버프 나", "t2"))
	s.add_mod(StatMod.make(StatMod.SPREAD, 1.0, 0.5, "버프 다", "t2"))
	var want := (base + 0.5) * 1.1 * 1.2
	_check(is_equal_approx(s.stat(StatMod.SPREAD, base), want), "곱 · 더하기 쌓기", "퍼짐 %.3f → %.3f, 기대 %.3f" % [base, s.stat(StatMod.SPREAD, base), want])
	_check(is_equal_approx(s.stat(StatMod.AIM_TIME, 0.6), 0.6), "다른 수치는 그대로")
	s.add_mod(StatMod.make(StatMod.AIM_TIME, 2.0, 0.0, "시간 디버프", "t3", 1.0))
	var during := s.stat(StatMod.AIM_TIME, 0.6)
	s.tick_mods(0.6)
	var still := s.stat(StatMod.AIM_TIME, 0.6)
	s.tick_mods(0.5)
	var after := s.stat(StatMod.AIM_TIME, 0.6)
	_check(is_equal_approx(during, 1.2) and is_equal_approx(still, 1.2) and is_equal_approx(after, 0.6), "시간이 다 되면 빠짐", "%.2f → %.2f → %.2f" % [during, still, after])
	var removed := s.remove_mods("t2")
	_check(removed == 2 and is_equal_approx(s.stat(StatMod.SPREAD, base), base * 1.1), "꼬리표로 빼기", "뺀 수 %d" % removed)


# ───────────── [2] [3] 효율 · 빈 좌석 ─────────────

func _efficiency_check(rifle: SoldierType, team: SquadComp) -> void:
	_notes.append("[2] 효율 · [3] 빈 장전 좌석(수치)")
	var et := team.equipment[0]
	_check(is_equal_approx(et.efficiency(0.0), 0.75) and is_equal_approx(et.efficiency(0.5), 0.875) and is_equal_approx(et.efficiency(1.0), 1.0),
		"효율 = 최소 + (1 − 최소) × 숙련도", "%.3f · %.3f · %.3f" % [et.efficiency(0.0), et.efficiency(0.5), et.efficiency(1.0)])
	var bf := Battlefield.new()
	bf.running = false
	var sq := bf.deploy_squad(0, rifle, BattleSquad.Order.HOLD)      # 숙련도 0 인 소총수들
	var eq := bf._add_equipment(sq, et)
	CrewBrain._set_up(bf, eq, eq.carrier, 1)
	var g := sq.members[0]
	CrewBrain.seat(g, eq, 0)
	CrewBrain.refresh_mods(eq)
	var w := et.weapon
	var sp := g.stat(StatMod.SPREAD, w.spread_deg)
	var tr := g.stat(StatMod.TRAVERSE, et.traverse_deg_s)
	var rl := g.stat(StatMod.RELOAD_TIME, w.reload_time)
	var wk := g.stat(StatMod.WALK_SPEED, rifle.walk_speed)
	_check(is_equal_approx(sp, w.spread_deg / 0.75) and is_equal_approx(tr, et.traverse_deg_s * 0.75), "사수(숙련도 0): 퍼짐 ÷ 75 % · 선회 × 75 %",
		"퍼짐 %.2f → %.2f · 선회 %.0f → %.1f" % [w.spread_deg, sp, et.traverse_deg_s, tr])
	_check(is_equal_approx(wk, rifle.walk_speed), "몸 수치(걷기 속도)는 그대로", "%.2f" % wk)
	_check(is_equal_approx(rl, w.reload_time * et.empty_loader_mult), "부사수 없음 → 사수 장전 × %s" % str(et.empty_loader_mult), "%.1f초 → %.1f초" % [w.reload_time, rl])
	var l := sq.members[1]
	CrewBrain.seat(l, eq, 1)
	CrewBrain.refresh_mods(eq)
	var rl_g := g.stat(StatMod.RELOAD_TIME, w.reload_time)
	var rl_l := l.stat(StatMod.RELOAD_TIME, w.reload_time)
	var sp_l := l.stat(StatMod.SPREAD, w.spread_deg)
	_check(is_equal_approx(rl_g, w.reload_time) and is_equal_approx(rl_l, w.reload_time / 0.75) and is_equal_approx(sp_l, w.spread_deg),
		"부사수가 앉음 → 사수 × 2 빠짐 · 부사수 장전 ÷ 75 %(퍼짐은 안 맡음)", "사수 %.2f · 부사수 %.2f초 · 부사수 퍼짐 %.2f" % [rl_g, rl_l, sp_l])
	var labels := PackedStringArray()
	for m in g.mods:
		labels.append(m.describe())
	_notes.append("    사수 수정자: " + " / ".join(labels))
	CrewBrain.unseat(g)
	_check(g.mods.is_empty(), "좌석에서 내리면 좌석 수정자도 빠짐")
	bf.clear()
	bf.free()


# ───────────── [3] [4] [5] 좌석 · 사망 · 버려짐 ─────────────

func _crew_check(rifle: SoldierType, team: SquadComp, seed_v: int) -> void:
	_notes.append("[3] 빈 장전 좌석(실제 시간) · [4] 사수 사망 → 재착석 · [5] 버려진 장비 → 다시 운용")
	var bf := Battlefield.new()
	bf.running = false
	bf.rng.seed = seed_v
	bf.length_m = 120.0
	var shots_by := {}
	var mw := team.equipment[0].weapon
	bf.shot_fired.connect(func(shot: Dictionary) -> void:
		if shot.get("weapon") == mw:
			var k := int(shot["team"])
			shots_by[k] = int(shots_by.get(k, 0)) + 1
	)
	var sq := bf.deploy_comp(0, team, BattleSquad.Order.HOLD)
	_place(sq, 40.0)
	var eq := sq.equipment[0]
	var t_setup := -1.0
	var t_ready := -1.0
	var states := PackedStringArray([BattleEquipment.STATE_NAMES[eq.state]])
	while bf.time < 30.0 and eq.state != BattleEquipment.State.READY:
		bf.step(DT)
		var nm: String = BattleEquipment.STATE_NAMES[eq.state]
		if states[states.size() - 1] != nm:
			states.append(nm)
		if eq.state == BattleEquipment.State.SETUP and t_setup < 0.0:
			t_setup = bf.time
	t_ready = bf.time
	_check(eq.state == BattleEquipment.State.READY, "MG42 팀: 운반 → 설치 → 준비", "%s · 설치 시작 %.1f초 → 준비 %.1f초" % [" → ".join(states), t_setup, t_ready])
	var gunner := eq.seats[0]
	var loader := eq.seats[1]
	var spare: BattleSoldier = null
	for s in sq.members:
		if s != gunner and s != loader:
			spare = s
	_check(gunner != null and loader != null and spare != null and spare.seat_eq == null, "좌석 둘 + 남는 한 명(소총)", eq.describe())

	# [4] 사수 사망
	bf._kill(gunner, null)
	_steps(bf, 1.5)
	_check(eq.seats[0] == loader and eq.seats[1] == spare, "사수 사망 → 부사수가 사수로 · 남은 병사가 부사수로",
		"사수 #%s · 부사수 #%s" % [str(eq.seats[0].id) if eq.seats[0] != null else "-", str(eq.seats[1].id) if eq.seats[1] != null else "-"])

	# [3] 부사수까지 쓰러짐 → 사수가 직접 장전 × 2
	bf._kill(spare, null)
	_steps(bf, 1.5)
	var g := eq.seats[0]
	var want := mw.reload_time * team.equipment[0].empty_loader_mult
	_check(g == loader and eq.seats[1] == null and is_equal_approx(g.stat(StatMod.RELOAD_TIME, mw.reload_time), want), "부사수 없음 → 사수 장전 시간 × 2",
		"%.1f초" % g.stat(StatMod.RELOAD_TIME, mw.reload_time))
	_steps(bf, 3.0)                      # 사수가 자리에 다시 앉을 때까지
	eq.ammo = 0
	var t0 := -1.0
	var t1 := -1.0
	var limit := bf.time + 30.0
	while bf.time < limit:
		bf.step(DT)
		if t0 < 0.0 and eq.reloader == g:
			t0 = bf.time
		if t0 >= 0.0 and eq.ammo == eq.mag_size():
			t1 = bf.time
			break
	var took := t1 - t0
	_check(t0 >= 0.0 and t1 > 0.0 and absf(took - want) < 0.1, "실제로 사수가 장전 — 걸린 시간", "%.2f초(기대 %.1f)" % [took, want])

	# [5] 전멸 → 버려짐 → 아군이 줍기
	bf._kill(g, null)
	_steps(bf, 0.2)
	_check(eq.squad == null and int(bf.stats["abandoned"]) >= 1 and eq.state == BattleEquipment.State.READY, "운용 분대가 없어짐 → 버려진 장비(설치된 채)", eq.describe())
	var ally := bf.deploy_squad(0, rifle, BattleSquad.Order.HOLD)
	_place(ally, 45.0)
	_steps(bf, 4.0)
	var ag := eq.seats[0]
	var al := eq.seats[1]
	_check(eq.squad == ally and ag != null and al != null and ag.squad == ally, "아군 소총 분대가 주워 운용", eq.describe())
	if ag != null and al != null:
		_check(is_equal_approx(ag.stat(StatMod.SPREAD, mw.spread_deg), mw.spread_deg / 0.75) and is_equal_approx(al.stat(StatMod.RELOAD_TIME, mw.reload_time), mw.reload_time / 0.75),
			"숙련도 0 → 효율 75 %(사수 퍼짐 · 부사수 장전)", "퍼짐 %.2f · 장전 %.2f초" % [ag.stat(StatMod.SPREAD, mw.spread_deg), al.stat(StatMod.RELOAD_TIME, mw.reload_time)])
	for s in ally.members:
		bf._kill(s, null)
	_steps(bf, 0.2)
	_check(eq.squad == null, "또 버려짐")

	# 적이 줍고 돌려 쏜다 — 우리 편 표적을 먼저 세워 두고(정지 · 장비에서 약 33 m: MG42 사거리 안 · 소총 사거리 밖 — 겨누는 동안 맞받아 쏘지 못하게), 적 분대를 장비 옆에
	var targets := bf.deploy_squad(0, rifle, BattleSquad.Order.HOLD)
	_place(targets, 5.0)
	var foe := bf.deploy_squad(1, rifle, BattleSquad.Order.HOLD)
	_place(foe, 44.0)
	var facing0 := eq.facing
	_steps(bf, 15.0)
	_check(eq.squad == foe and eq.team == 1, "적 분대가 주움(편이 바뀜)", eq.describe())
	_check(facing0 == 1 and eq.facing == -1, "적이 총구를 우리 쪽으로 돌림", "총구 %+d → %+d" % [facing0, eq.facing])
	_check(int(shots_by.get(1, 0)) > 0, "적이 MG42 로 쏨", "적 MG42 총알 %d · 우리 MG42 총알 %d" % [int(shots_by.get(1, 0)), int(shots_by.get(0, 0))])
	bf.clear()
	bf.free()


# ───────────── [6] 전장 ─────────────

func _battle_check(rifle: SoldierType, team: SquadComp, seed_v: int, seconds: float) -> void:
	_notes.append("[6] 시험 전장 — 우리 편 MG42 팀 + 소총 분대 대 적 소총 분대 2 (%d초)" % int(seconds))
	var bf := Battlefield.new()
	bf.running = false
	bf.rng.seed = seed_v
	TestField.build(bf)
	var mw := team.equipment[0].weapon
	var mg := {"shots": 0, "hits": 0, "near": 0}
	bf.shot_fired.connect(func(shot: Dictionary) -> void:
		if shot.get("weapon") == mw:
			mg["shots"] += 1
			if shot.get("hit") != null:
				mg["hits"] += 1
	)
	var sq := bf.deploy_comp(0, team)
	bf.deploy_squad(0, rifle)
	bf.deploy_squad(1, rifle)
	bf.deploy_squad(1, rifle)
	var eq := sq.equipment[0]
	var seen := {}
	var next := 0.0
	var steps := int(seconds / DT)
	for k in steps:
		bf.step(DT)
		seen[BattleEquipment.STATE_NAMES[eq.state]] = true
		if bf.time >= next:
			next += 20.0
			_notes.append("    %5.1f초  %s  x=%.1f  분대 %s" % [bf.time, eq.describe(), eq.x, ("#%d %s" % [eq.squad.id, BattleSquad.POSTURE_NAMES[eq.squad.posture]]) if eq.squad != null else "없음"])
		for team_i in 2:
			if bf.count_fighting(team_i) == 0:
				bf.deploy_squad(team_i, rifle)
	_notes.append("    지나온 상태 %s · MG42 총알 %d · 맞음 %d · 전체 총알 %d · 사살 %s · 주움 %d · 버려짐 %d" % [str(seen.keys()), mg["shots"], mg["hits"], bf.stats["shots"],
		str(bf.stats["kills"]), bf.stats["claims"], bf.stats["abandoned"]])
	_check(seen.has("설치 중") and seen.has("준비"), "전장에서 설치 → 준비")
	_check(int(mg["shots"]) > 0 and int(mg["hits"]) > 0, "MG42 팀이 실제로 쏘고 맞힘", "총알 %d · 맞음 %d" % [mg["shots"], mg["hits"]])
	bf.clear()
	bf.free()


# ───────────── 도움 ─────────────

func _steps(bf: Battlefield, sec: float) -> void:
	var n := int(sec / DT)
	for i in n:
		bf.step(DT)


## 분대를 그 x 로 옮겨 놓는다(시험용) — 목표도 그 자리, 들고 있는 장비도 같이
func _place(sq: BattleSquad, x0: float) -> void:
	for i in sq.members.size():
		var s := sq.members[i]
		s.x = x0 + float(i) * 0.6
		s.goal_x = s.x
	sq.goal_x = x0
	for eq in sq.equipment:
		if eq.carrier != null:
			eq.x = eq.carrier.x
			eq.depth = eq.carrier.depth
