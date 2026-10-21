extends RefCounted
class_name BattleBody

## 몸 — "어떻게 움직이나". 상태머신 두 영역(이동 · 행동)이 동시에 돌고, 그 위에 덮어쓰기가 있다.  (보병_추상화.md §2-4)
##
##   이동 영역:  서 있음 · 걷기 · 달리기 · 포복 · 엄폐 중
##   행동 영역:  지금 하는 능력(Ability — 사격 · 장전 …)과 그 단계. 동작 표에 내는 이름 = 없음 · 조준 · 사격 · 장전 · 투척 · 근접
##   덮어쓰기:   피격 · 제압 · 패닉 · 사망   (두 영역 위에서 강제로 — 두뇌 · 플레이어 조작보다 위)
##   자세(서기 · 앉기 · 엎드림)는 상태가 아니라 속성
##
## 상태 객체를 병사마다 만들지 않는다. 이 스크립트의 함수가 모든 병사 기록(BattleSoldier)에 같이 쓰인다.
## 조종자(AI 두뇌 · 플레이어)가 채운 "의도"(want_* · goal_* · move_dir)를 읽어 실제 움직임으로 바꾼다.

enum Move { IDLE, WALK, RUN, CRAWL, COVER }
enum Act { NONE, AIM, FIRE, RELOAD, THROW, MELEE }
enum Ovr { NONE, HIT, SUPPRESSED, PANIC, DEAD }
enum Stance { STAND, CROUCH, PRONE }

const MOVE_NAMES := ["서 있음", "걷기", "달리기", "포복", "엄폐 중"]
const ACT_NAMES := ["없음", "조준", "사격", "장전", "투척", "근접"]
const OVR_NAMES := ["없음", "피격", "제압", "패닉", "사망"]
const STANCE_NAMES := ["서기", "앉기", "엎드림"]

const SUPPRESS_ON := 1.0        # 이만큼 쌓이면 제압
const SUPPRESS_OFF := 0.5       # 이 아래로 빠지면 풀린다(경계에서 깜빡이지 않게 간격을 둔다)
const SUPPRESS_MAX := 1.5
const SUPPRESS_DECAY := 0.35    # 초당 빠지는 양(사기가 보통일 때)
const HIT_STUN := 0.25          # 피격 경직(초)
const FIRE_POSE := 0.18         # 한 발 쏜 뒤 사격 동작이 보이는 시간
const ARRIVE_M := 0.2           # 목표 자리에 이만큼 가까우면 도착
const DEPTH_SPEED := 0.35       # 깊이를 옮기는 빠르기(초당)


static func step(s: BattleSoldier, bf: Battlefield, dt: float) -> void:
	if s.override == Ovr.DEAD:
		return
	var t := s.type
	var w := t.weapon

	# 저절로 돌아오는 수치 — 사기가 낮으면 제압이 늦게 빠진다(§2-8). 빙의 병사는 분대 사기와 무관(보통 기준)
	var morale := s.squad.morale if (s.squad != null and not s.detached) else 0.6
	s.suppression = maxf(0.0, s.suppression - SUPPRESS_DECAY * lerpf(0.5, 1.2, morale) * dt)
	s.bloom_deg = maxf(0.0, s.bloom_deg - w.spread_recover_deg * dt)
	s.fire_cooldown = maxf(0.0, s.fire_cooldown - dt)

	# ── 덮어쓰기 ──
	if s.override == Ovr.PANIC:
		_halt(s)
		s.stance = Stance.CROUCH                    # 그 자리에 웅크림. 회복 없음
		return
	if s.override == Ovr.HIT:
		s.ovr_timer -= dt
		if s.ovr_timer > 0.0:
			_halt(s)
			return
		s.override = Ovr.NONE
	if s.override == Ovr.NONE and s.suppression >= SUPPRESS_ON:
		s.override = Ovr.SUPPRESSED
	elif s.override == Ovr.SUPPRESSED and s.suppression < SUPPRESS_OFF:
		s.override = Ovr.NONE
	if s.override == Ovr.SUPPRESSED:
		# 제압 = 숨는 자세로 강제(§2-9). 못 쏘고 못 움직인다 — AI 든 플레이어든 같다
		_halt(s)
		s.in_cover = at_slot(s)
		s.stance = s.cover.hide_stance() if s.in_cover else Stance.PRONE
		s.move_state = Move.COVER if s.in_cover else Move.IDLE
		return

	# ── 자세(속성) ──
	s.stance = s.want_stance

	# ── 행동 영역 — 지금 능력의 단계(준비 → 실행 → 마무리, §2-13). 기능 코드는 능력 파일(Ability)에 있다 ──
	if s.ability != null:
		if not s.ability.step(s, bf, dt):
			stop_act(s)
	else:
		var next := _pick_ability(s)
		if next != null:
			s.ability = next
			next.begin(s, bf)

	# ── 이동 영역 ──
	var dir := 0
	var remain := INF
	if s.use_goal:
		var dx := s.goal_x - s.x
		remain = absf(dx)
		if remain > ARRIVE_M:
			dir = 1 if dx > 0.0 else -1
	else:
		dir = s.move_dir
	var busy := s.act_state != Act.NONE
	# 규칙 하나: 행동 중이면 이동은 정지. "걸으며 쏘기" 특성이 있으면 조준 · 사격 중에도 걷는다(장전은 멈춰서)
	var may_move := not busy or (t.fire_while_walking and s.act_state != Act.RELOAD)
	if dir != 0 and may_move:
		var speed := t.walk_speed
		if s.stance == Stance.PRONE:
			speed = t.crawl_speed
			s.move_state = Move.CRAWL
		elif s.stance == Stance.CROUCH:
			speed = t.walk_speed * t.crouch_move_mult
			s.move_state = Move.WALK
		elif s.want_run and not busy:
			speed = t.run_speed
			s.move_state = Move.RUN
		else:
			s.move_state = Move.WALK
		s.x = clampf(s.x + float(dir) * minf(speed * dt, remain), 0.0, bf.length_m)
		s.in_cover = false
		if not busy:
			s.facing = dir
	else:
		s.in_cover = at_slot(s)
		s.move_state = Move.COVER if s.in_cover else Move.IDLE
	s.depth = move_toward(s.depth, clampf(s.goal_depth, 0.0, 1.0), DEPTH_SPEED * dt)

	# 바라보는 쪽 — 겨누는 중이면 표적 쪽, 가만히 있으면 앞(AI). 플레이어는 마지막 방향 그대로
	if busy and s.act_state != Act.RELOAD:
		var ax := s.target.x if (s.target != null and s.controller == 0) else s.aim_x
		if absf(ax - s.x) > 0.05:
			s.facing = 1 if ax > s.x else -1
	elif dir == 0 and s.controller == 0:
		s.facing = bf.forward(s.team)


## 배정된 엄폐 칸에 도착해 있나
static func at_slot(s: BattleSoldier) -> bool:
	if s.cover == null or s.slot < 0 or s.slot >= s.cover.slot_x.size():
		return false
	return absf(s.x - s.cover.slot_x[s.slot]) <= ARRIVE_M * 1.5


## 하고 싶은(의도 칸) 능력 중 우선순위가 가장 큰 것. 없으면 null
static func _pick_ability(s: BattleSoldier) -> Ability:
	var best: Ability = null
	for ab in s.abilities():
		if (best == null or ab.priority > best.priority) and ab.wants(s):
			best = ab
	return best


## 하던 능력을 끊는다(끝남 · 피격 · 제압 · 패닉 · 사망 · 좌석 바뀜)
static func stop_act(s: BattleSoldier) -> void:
	if s.ability != null:
		var ab := s.ability
		s.ability = null
		ab.stop(s)
	s.phase = 0
	s.act_state = Act.NONE


static func _halt(s: BattleSoldier) -> void:
	stop_act(s)
	s.move_state = Move.IDLE
