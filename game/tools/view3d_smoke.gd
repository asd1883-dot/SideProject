extends SceneTree

## 3D 화면(BattleView3D) 검사 — 창 없이(--headless) 전투를 돌리며 3D 캐릭터 쪽 논리가 도는지 본다(10-16).
##   Godot --headless --path <프로젝트> --script res://game/tools/view3d_smoke.gd [-- --seconds=60 --squads=2 --seed=1941]
## 보는 것: 병사마다 캐릭터가 붙는가 · 상태에 맞는 동작이 나오는가(멈춘 채인 병사 비율) · 쓰러진 병사가 풀로 돌아가 다시 쓰이는가 ·
##          무기(뼈 소켓 · 10-16)의 왼손 IK 비중이 동작마다 바뀌는가(조준 = 붙임 · 장전 · 수류탄 = 놓음) · 복장 보기 4가지(병종 복장 / 상의만 / 하의만 / 내복)가 슬롯을 바꾸는가 ·
##          사격하는 병사에게 조준 표적이 가고 허리 · 가슴이 표적으로 도는가(조준 IK, 10-21).
## 그림은 안 본다(렌더 없음) — 모양은 창으로 보는 시험장(battle_test.tscn)에서. 마지막 줄이 "VIEW3D SMOKE OK" 면 통과.

const TYPE_PATH := "res://game/units/rifleman.tres"
const DT := 1.0 / 60.0
const TestField := preload("res://game/tools/test_field.gd")


func _initialize() -> void:
	_run.call_deferred()        # 뿌리 창이 트리에 들어간 뒤에 — 화면(BattleView)이 보이는 범위를 재려면 트리 안이어야 한다


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var eq := s.find("=")
		args[s if eq < 0 else s.substr(0, eq)] = "1" if eq < 0 else s.substr(eq + 1)
	var seconds := float(args.get("seconds", "60"))
	var squads := int(args.get("squads", "2"))
	var type := load(TYPE_PATH) as SoldierType
	if type == null:
		print("VIEW3D SMOKE FAIL 병종 리소스가 없습니다: ", TYPE_PATH)
		quit(1)
		return
	var fails := PackedStringArray()

	var bf := Battlefield.new()
	bf.running = false                     # 여기서 직접 step 을 부른다
	bf.rng.seed = int(args.get("seed", "1941"))
	TestField.build(bf)
	root.add_child(bf)
	var view := BattleView3D.new()
	root.add_child(view)
	view.setup(bf)

	# 1) 미리 만들기 — 캐릭터 · 슬롯 · 무기 · 동작 묶음
	var t0 := Time.get_ticks_usec()
	view.prewarm(type, squads * 2 * type.squad_size)
	var prewarm_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	if type.prefab == null:
		fails.append("병종에 유닛 프리팹이 없음")
	var pool: Array = view._pool3d.get(BattleView3D._prefab_key(type), []) if type.prefab != null else []
	if pool.size() != squads * 2 * type.squad_size:
		fails.append("미리 만든 캐릭터 수 %d" % pool.size())
	if not pool.is_empty():
		var ch := pool[0] as DRCharacter3D
		var ap := ch.get_animation_player()
		var w := ch.get_weapon_node()
		print("캐릭터  프리팹 %s · 슬롯 %s · 무기 %s(소켓 %s · 왼팔 IK %s) · 동작 %d개 · 키 %.2f m(모델 %.3f) · 상의 %s · 하의 %s · 미리 만들기 %d명 %.0f ms" % [
			type.prefab.resource_path.get_file(),
			str(DRCharacter3D.SLOTS.map(func(sl): return ch.get_slot_node(sl) != null and ch.get_slot_node(sl).mesh != null)),
			String(w.name) if w != null else "없음", String(w.get_parent().name) if w != null else "-", str(ch.get_left_arm_ik() != null),
			ap.get_animation_list().size(), ch.height_m, ch.model_height(),
			ch.worn("top").get_file(), ch.worn("bottom").get_file(), pool.size(), prewarm_ms])
		if w == null or not (w.get_parent() is BoneAttachment3D):
			fails.append("무기가 소켓에 안 붙음")
		elif ch.get_left_arm_ik() == null:
			fails.append("왼팔 IK 없음(무기 위 왼손 표지)")
		if ap.get_animation_list().size() < 2:
			fails.append("동작 묶음 안 들어감(%s)" % (ch.motions.library_path if ch.motions != null else "동작 표 없음"))
		if ch.worn("top") == "" or ch.worn("bottom") == "":
			fails.append("프리팹 복장이 안 입혀짐")

	# 2) 전투 — 동작 고르기 · 쓰러짐 · 풀 돌려쓰기 · 그립
	for i in squads:
		bf.deploy_squad(0, type)
		bf.deploy_squad(1, type)
	var played := {}                       # 동작 이름 -> 고른 횟수
	var frozen := 0                        # 살아 있는데 맞는 동작이 없는 병사 · 프레임
	var alive_frames := 0
	var recycled := 0
	var ik_moves := 0                      # 동작이 바뀌어 왼손 IK 비중이 새 동작 것으로 옮겨 간 횟수(붙임 ↔ 놓음)
	var max_entries := 0
	var last_motion := {}                  # 병사 id -> 동작
	var last_ik := {}                      # 병사 id -> 마지막 목표 IK 비중
	var view_us := 0
	var steps := int(seconds / DT)
	for k in steps:
		bf.step(DT)
		var tv := Time.get_ticks_usec()
		var before := view._entries.size()
		view._process(DT)
		view_us += Time.get_ticks_usec() - tv
		if view._entries.size() < before:
			recycled += before - view._entries.size()
		max_entries = maxi(max_entries, view._entries.size())
		for v in view._entries.values():
			var e := v as BattleView3D.Entry3D
			if e.dead_t >= 0.0 or e.ch == null:
				continue
			alive_frames += 1
			if e.motion == "":
				frozen += 1
			elif String(last_motion.get(e.s.id, "")) != e.motion:
				last_motion[e.s.id] = e.motion
				played[e.motion] = int(played.get(e.motion, 0)) + 1
			var ikt: float = e.ch.ik_target_weight(0)
			if e.ch._grip_t >= 0.0 and float(last_ik.get(e.s.id, -1.0)) != ikt:
				if last_ik.has(e.s.id):
					ik_moves += 1
				last_ik[e.s.id] = ikt
		for team in 2:
			if bf.count_fighting(team) == 0:
				bf.deploy_squad(team, type)
	var frozen_pct := 100.0 * float(frozen) / maxf(float(alive_frames), 1.0)
	print("전투  %.0f초 · 화면 병사 최대 %d · 쓰러져 풀로 돌아감 %d · 사살 %s · 멈춘 채 %.1f %% · 왼손 IK 붙임↔놓음 %d번" % [
		bf.time, max_entries, recycled, str(bf.stats["kills"]), frozen_pct, ik_moves])
	var names := played.keys()
	names.sort_custom(func(a, b): return int(played[a]) > int(played[b]))
	var parts := PackedStringArray()
	for n in names:
		parts.append("%s %d" % [n, int(played[n])])
	print("나온 동작 %d개  %s" % [names.size(), " · ".join(parts)])
	print("계산  화면 갱신 한 번 평균 %.3f ms (병사 %d명 안팎, 렌더 제외)" % [float(view_us) / 1000.0 / float(steps), max_entries])
	if max_entries == 0:
		fails.append("화면에 병사가 없음")
	if frozen_pct > 5.0:
		fails.append("맞는 동작 없이 멈춘 병사 %.1f %%" % frozen_pct)
	if names.size() < 4:
		fails.append("나온 동작이 %d개뿐" % names.size())
	if recycled == 0:
		fails.append("쓰러진 병사가 풀로 안 돌아감")
	if ik_moves == 0:
		fails.append("왼손 IK 비중이 동작 따라 안 바뀜")

	# 2-2) 조준 IK(10-21) — 화면을 줄여 전장 전체가 보이게(화면 밖 병사는 동작 · 표적을 안 돌린다) 20 초 더. 위 수치와 따로
	view.scale = Vector2(0.25, 0.25)
	var aim_want := 0                      # 적을 겨눈(두뇌 표적) 채 조준 비중이 있는 동작(사격 · 조준)인 병사 · 프레임
	var aim_frames := 0                    # 그중 캐릭터에 조준 표적이 간 것(표적은 동작 박자 — 초당 step_hz 번 — 에 넣는다)
	var aim_solved := 0                    # 1 초마다 조준하던 병사의 뼈대를 바로 갱신해 잰 수(이 검사는 프레임을 안 넘겨 뼈대 갱신이 미뤄져 있다)
	var aim_err := 0.0                     # 그때 돌린 총구 기준 ↔ 겨눌 방향 최대(한계에 걸린 것 빼고)
	var aim_clamped := 0
	var aim_pitch := 0.0                   # 돌린 위아래 각 최대(절댓값)
	for k in int(20.0 / DT):
		bf.step(DT)
		view._process(DT)
		var probe_now := k % 60 == 59
		for v in view._entries.values():
			var e := v as BattleView3D.Entry3D
			if e.dead_t >= 0.0 or e.ch == null or e.s.target == null or not e.s.target.alive or e.ch.aim_weight_for(e.motion) <= 0.0:
				continue
			var fx := view.to_canvas(e.s.x, 0.0, e.s.depth).x
			if fx <= view._vis_x0 or fx >= view._vis_x1:
				continue
			aim_want += 1
			if not e.ch.has_aim_target():
				continue
			aim_frames += 1
			if probe_now:
				var sk := e.ch.get_skeleton()
				sk.set_bone_pose_rotation(0, sk.get_bone_pose_rotation(0))
				sk.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
				var ar := e.ch.aim_report()
				if ar.is_empty():
					continue
				aim_solved += 1
				aim_pitch = maxf(aim_pitch, absf(float(ar["pitch"])))
				if bool(ar["clamped"]):
					aim_clamped += 1
				else:
					aim_err = maxf(aim_err, float(ar["err"]))
		for team in 2:
			if bf.count_fighting(team) == 0:
				bf.deploy_squad(team, type)
	view.scale = Vector2.ONE
	var aim_pct := 100.0 * float(aim_frames) / maxf(float(aim_want), 1.0)
	print("조준  사격 · 조준 동작 병사 · 프레임 %d 중 조준 표적 %.1f %% · 1 초마다 잰 %d번: 겨눌 방향과 최대 %.2f° · 위아래 돌림 최대 %.1f° · 한계 걸림 %d" % [
		aim_want, aim_pct, aim_solved, aim_err, aim_pitch, aim_clamped])
	if aim_solved == 0 or aim_err > 1.0:
		fails.append("조준 IK 가 표적으로 안 돌림(잰 %d번 · 최대 %.2f°)" % [aim_solved, aim_err])
	if aim_want == 0:
		fails.append("사격 · 조준하는 병사가 없음")
	elif aim_pct < 80.0:
		fails.append("사격 중 조준 표적이 간 병사 %.1f %%" % aim_pct)

	# 3) 복장 보기 — 슬롯마다 입은 복장
	var probe: DRCharacter3D = null
	for v in view._entries.values():
		if (v as BattleView3D.Entry3D).ch != null:
			probe = (v as BattleView3D.Entry3D).ch
			break
	if probe == null and not pool.is_empty():
		probe = pool[0] as DRCharacter3D
	var wear_lines := PackedStringArray()
	var want := [["o", "o"], ["o", ""], ["", "o"], ["", ""]]     # 병종 복장 · 상의만 · 하의만 · 내복 → 상의 · 하의를 입었나
	for m in BattleView3D.WEAR_NAMES.size():
		view.wear_mode = m
		var top := probe.worn("top") if probe != null else "?"
		var bottom := probe.worn("bottom") if probe != null else "?"
		wear_lines.append("%s: 상의 %s · 하의 %s" % [BattleView3D.WEAR_NAMES[m], top.get_file() if top != "" else "내복", bottom.get_file() if bottom != "" else "내복"])
		if (top != "") != (want[m][0] != "") or (bottom != "") != (want[m][1] != ""):
			fails.append("복장 보기 %s 가 슬롯을 잘못 입힘" % BattleView3D.WEAR_NAMES[m])
	view.wear_mode = 0
	print("복장  ", " | ".join(wear_lines))

	if fails.is_empty():
		print("VIEW3D SMOKE OK")
	else:
		print("VIEW3D SMOKE FAIL ", ", ".join(fails))
	view.queue_free()
	bf.clear()
	bf.queue_free()
	quit(0 if fails.is_empty() else 1)
