extends SceneTree

## 화면 없이 논리만 돌려 보는 검사 — 양쪽 끝에서 분대를 투입해 정해진 시간만큼 전투를 돌리고, 일어난 일을 글로 찍는다.
##   Godot --headless --path <프로젝트> --script res://game/tools/sim_smoke.gd [-- --seconds=120 --squads=2 --seed=1941]
## 보는 것: 분대가 엄폐물로 가는가 · 쏘는가 · 맞는가 · 벽에 막히는가 · 제압/사기/패주/패닉이 생기는가 · 한 걸음 계산이 얼마나 드는가
##   + 참호 버전(10-28): 시뮬이 모래주머니 판과 같음(칸 · 벽 · 자세 · 총알 판정) · 그리는 도랑 깊이 · 구간(뒤 1.5 m · 깊이 전체) · 전투에서 참호 버전에 든다
## 마지막 줄이 "SIM SMOKE OK" 면 통과(기대한 일이 다 일어남), 아니면 무엇이 안 일어났는지 적는다.

const TYPE_PATH := "res://game/units/rifleman.tres"
const DT := 1.0 / 60.0
const TestField := preload("res://game/tools/test_field.gd")


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var eq := s.find("=")
		args[s if eq < 0 else s.substr(0, eq)] = "1" if eq < 0 else s.substr(eq + 1)
	var seconds := float(args.get("seconds", "120"))
	var squads_per_side := int(args.get("squads", "2"))
	var type := load(TYPE_PATH) as SoldierType
	if type == null:
		print("SIM SMOKE FAIL 병종 리소스가 없습니다: ", TYPE_PATH, " — make_default_units.gd 를 먼저 돌리세요")
		quit(1)
		return

	var bf := Battlefield.new()
	bf.running = false                     # 여기서 직접 step 을 부른다
	bf.rng.seed = int(args.get("seed", "1941"))
	TestField.build(bf)
	var seen := {"shots": 0, "suppressed": 0, "rout": 0, "in_cover": 0, "reload": 0, "trench": 0}
	bf.shot_fired.connect(func(_shot: Dictionary) -> void: seen["shots"] += 1)
	for i in squads_per_side:
		bf.deploy_squad(0, type)
		bf.deploy_squad(1, type)

	var steps := int(seconds / DT)
	var t0 := Time.get_ticks_usec()
	var next_report := 0.0
	var pos: BattleSoldier = null           # 빙의 검사에 쓸 병사
	var pos_notes := PackedStringArray()
	for k in steps:
		# 빙의 검사: 30초에 왼쪽편 병사 하나를 빙의 → 10초 동안 "의도"를 손으로 채움(앞으로 걷다가 가까운 적을 쏨) → 40초에 풀기
		if pos == null and bf.time >= 30.0 and bf.time < 40.0:
			for c in bf.soldiers:
				if c.team == 0 and c.can_fight():
					pos = c
					break
			if pos != null and bf.possess(pos):
				pos_notes.append("빙의 병사%d: 분대에서 빠짐 = %s" % [pos.id, str(not pos.squad.active().has(pos))])
		if pos != null and pos.controller == 1:
			if not pos.can_fight() or bf.time >= 40.0:
				var ammo_used := pos.type.weapon.mag_size - pos.ammo
				bf.release(pos)
				pos_notes.append("풀기: 조종자 AI 로 = %s · 분대로 복귀 = %s · 빙의 중 움직인 뒤 x=%.1f · 쏜 탄 %d" % [str(pos.controller == 0), str(pos.squad.active().has(pos) or not pos.can_fight()), pos.x, ammo_used])
			else:
				var foes := bf.enemies_near(0, pos.x, pos.type.weapon.range_m)
				pos.use_goal = false
				pos.move_dir = 1 if foes.is_empty() else 0
				pos.want_stance = BattleBody.Stance.CROUCH if not foes.is_empty() else BattleBody.Stance.STAND
				pos.want_fire = not foes.is_empty()
				if not foes.is_empty():
					var aim := Ballistics.aim_point(pos, foes[0])
					pos.aim_x = aim.x
					pos.aim_h = aim.y
					pos.aim_depth = aim.z
		bf.step(DT)
		for s in bf.soldiers:
			if s.override == BattleBody.Ovr.SUPPRESSED:
				seen["suppressed"] += 1
			if s.in_cover:
				seen["in_cover"] += 1
				if s.cover != null and s.cover.dug:
					seen["trench"] += 1
			if s.act_state == BattleBody.Act.RELOAD:
				seen["reload"] += 1
		for sq in bf.squads:
			if sq.routed:
				seen["rout"] += 1
		if bf.time >= next_report:
			next_report += 10.0
			_report(bf)
		# 한쪽이 다 쓰러지면 새 분대를 넣어 전투를 이어 간다
		for team in 2:
			if bf.count_fighting(team) == 0:
				bf.deploy_squad(team, type)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_report(bf)
	print("통계  총알 %d  맞음 %d  벽·땅에 막힘 %d  사살 [왼쪽편 %d · 오른쪽편 %d]  패닉 %s" % [bf.stats["shots"], bf.stats["hits"], bf.stats["blocked"], bf.stats["kills"][0], bf.stats["kills"][1], str(bf.stats["panics"])])
	print("계산  %d 걸음 %.0f ms → 한 걸음 %.3f ms (병사 %d명 기록)" % [steps, ms, ms / float(steps), bf.soldiers.size()])
	for note in pos_notes:
		print("빙의  ", note)
	var missing := PackedStringArray()
	if pos_notes.size() < 2 or pos_notes[0].ends_with("false") or pos_notes[1].contains("false"):
		missing.append("빙의 → 풀기")
	if seen["shots"] == 0:
		missing.append("사격")
	if int(bf.stats["hits"]) == 0:
		missing.append("명중")
	if int(bf.stats["blocked"]) == 0:
		missing.append("벽·땅에 막힘")
	if seen["in_cover"] == 0:
		missing.append("엄폐 도착")
	if seen["suppressed"] == 0:
		missing.append("제압")
	if seen["reload"] == 0:
		missing.append("장전")
	if seen["trench"] == 0:
		missing.append("참호 버전에 들어감")
	print("참호  전투 중 참호 버전 엄폐물에 든 병사 · 걸음 %d" % seen["trench"])
	missing.append_array(_trench_checks(type))
	if missing.is_empty():
		print("SIM SMOKE OK")
	else:
		print("SIM SMOKE FAIL 안 일어난 것: ", ", ".join(missing))
	bf.clear()
	bf.free()
	quit(0 if missing.is_empty() else 1)


func _report(bf: Battlefield) -> void:
	var lines := PackedStringArray()
	lines.append("── %5.1f 초   싸울 수 있는 병사 [왼쪽편 %d · 오른쪽편 %d]" % [bf.time, bf.count_fighting(0), bf.count_fighting(1)])
	for sq in bf.squads:
		var act := sq.active()
		if act.is_empty():
			continue
		var covered := 0
		for s in act:
			if s.in_cover:
				covered += 1
		lines.append("   분대%d(%s) %d명  x=%5.1f  태세 %s%s  사기 %.2f  제압 %.2f  엄폐 %d명  %s" % [
			sq.id, "왼" if sq.team == 0 else "오", act.size(), sq.anchor_x(), BattleSquad.POSTURE_NAMES[sq.posture],
			"(패주)" if sq.routed else "", sq.morale, sq.avg_suppression(), covered, str(sq.scores)])
	print("\n".join(lines))


## 참호 버전(10-28) — 시뮬은 모래주머니 판과 같고(칸 · 벽 · 자세 · 총알 판정) 모습만 땅을 판 것: 도랑 깊이 = 벽 − 모래주머니 0.3 m,
## 도랑 = 칸 구간 + 뒤 1.5 m · 깊이 전체(그 안을 화면이 내려 그린다 — Battlefield.draw_ground_h). 실패한 것의 이름들을 돌려준다
func _trench_checks(type: SoldierType) -> PackedStringArray:
	var fails := PackedStringArray()
	var bf := Battlefield.new()
	bf.running = false
	bf.length_m = 120.0
	var plain := bf.add_cover(30.0, 32.5, BattleCover.Kind.LOW, 1)
	var dug := bf.add_cover(60.0, 62.5, BattleCover.Kind.LOW, 1, 0, true)
	var high := bf.add_cover(90.0, 92.5, BattleCover.Kind.HIGH, -1, 0, true)
	var same := plain.slot_x.size() == dug.slot_x.size() and plain.fire_stance() == dug.fire_stance() and plain.hide_stance() == dug.hide_stance() 		and plain.wall_side == dug.wall_side and plain.wall_height() == dug.wall_height()
	for i in plain.slot_x.size():
		same = same and is_equal_approx(plain.slot_x[i] - plain.x0, dug.slot_x[i] - dug.x0) and is_equal_approx(plain.slot_depth[i], dug.slot_depth[i])
	_trench_line(fails, same, "같은 형식: 칸 %d개 · 자리 · 깊이 · 벽 쪽 · 벽 높이 %.1f m · 쏘는 / 숨는 자세가 모래주머니 판과 같음" % [dug.slot_x.size(), dug.wall_height()])
	var pit := dug.pit_depth()
	_trench_line(fails, is_equal_approx(pit, 0.7) and is_equal_approx(high.pit_depth(), 1.2) and is_equal_approx(pit + dug.sandbag_h(), dug.wall_height())
		and bf.draw_ground_h(61.0, 0.1) == -pit and bf.draw_ground_h(61.0, 0.9) == -pit and bf.draw_ground_h(59.0, 0.5) == -pit
		and bf.draw_ground_h(57.5, 0.5) == 0.0 and bf.draw_ground_h(63.0, 0.5) == 0.0 and bf.draw_ground_h(31.0, 0.5) == 0.0
		and bf.draw_ground_h(93.5, 0.5) == -1.2 and bf.draw_ground_h(89.5, 0.5) == 0.0,
		"그리는 도랑: 낮음 %.1f m · 높음 %.1f m · 모래주머니 %.1f m · 칸 구간 + 벽 반대쪽 %.1f m · 깊이 어디든 · 그 밖 · 벽 너머 · 모래주머니 판 0" % [
			pit, high.pit_depth(), dug.sandbag_h(), BattleCover.PIT_REAR])
	# 같은 자리 관계(적 쪽 18.6 m 에서 앉아 쏘기 표적의 머리 · 벽 높이 · 그 아래)로 쏘면 두 엄폐물의 총알 판정이 같다
	var tgt_sq := bf.deploy_squad(0, type)
	var sh_sq := bf.deploy_squad(1, type)
	for o in tgt_sq.members:
		o.x = 5.0
	for o in sh_sq.members:
		o.x = 115.0
	var sh := sh_sq.members[0]
	sh.depth = 0.3
	sh.stance = BattleBody.Stance.STAND
	var mh := type.muzzle_height(BattleBody.Stance.STAND)
	var res := PackedStringArray()
	for pair in [[plain, 31.0], [dug, 61.0]]:
		var c: BattleCover = pair[0]
		var t := tgt_sq.members[0]
		for o in tgt_sq.members:
			o.x = 5.0
		t.x = float(pair[1])
		t.depth = 0.3
		t.stance = c.fire_stance()
		sh.x = t.x + 19.0
		bf._rebuild_buckets()
		var mx := sh.x - Ballistics.MUZZLE_AHEAD_M
		var dist := mx - t.x
		var line := PackedStringArray()
		for h in [type.box(t.stance).y - 0.05, c.wall_height() - 0.2, 0.3]:
			var r := Ballistics.trace(bf, sh, mx, mh, sh.depth, -1, (h - mh) / dist, 0.0, 60.0, 0.5)
			line.append("%s%s" % ["맞음" if r["hit"] == t else "-", "/막힘" if bool(r["blocked"]) else ""])
		res.append(" ".join(line))
	_trench_line(fails, res[0] == res[1] and res[0].begins_with("맞음"), "총알 판정이 모래주머니 판과 같음: 모래주머니 [%s] · 참호 [%s](머리 · 벽 아래 · 다리)" % [res[0], res[1]])
	bf.clear()
	bf.free()
	return fails


func _trench_line(fails: PackedStringArray, ok: bool, what: String) -> void:
	print("참호  %s  %s" % ["OK  " if ok else "FAIL", what])
	if not ok:
		fails.append("참호: " + what)
