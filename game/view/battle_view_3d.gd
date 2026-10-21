extends BattleView
class_name BattleView3D

## 전투 화면 3D 판(10-15, 3D 노선) — BattleView(2D 퍼펫)와 같은 일을 하되 병사를 3D 캐릭터로 그린다.
## 땅 · 엄폐물 · 판정 상자 · 글자 · 총알 자국 · 마우스 판정은 BattleView 의 2D 그대로 물려받는다. 3D 는 DRDotView3D 가
## 2D 좌표와 정확히 같은 자리에 그려 주므로(to_canvas 와 같은 점) 시험장(battle_test)은 화면만 바꿔 끼우면 된다.
##
## 병사의 모습 = 병종(SoldierType)의 유닛 프리팹(prefab — 루트가 DRCharacter3D 인 씬: 몸 · 상의 · 하의 · 무기 · 동작 표 · 키, 10-16).
## 기본형 군인 = game/units/soldier_base.tscn, 다른 유닛 = 그 씬을 상속한 자식 씬. 이 화면은 프리팹을 꺼내 자리 · 방향 · 동작만 정한다.
##
## 하는 일
##   - 병사 기록 → 캐릭터 자리 · 방향(좌우 + 카메라 쪽으로 face_turn_deg) · 동작(동작 표에서 비중대로 — 반복 동작은 한 바퀴마다 다시)
##   - 캐릭터는 프리팹마다 미리 만들어 두고 돌려 쓴다(prewarm). 메시 · 재질 · 스킨 · 무기 그립은 DRCharacter3D 가 병사끼리 공유 · 캐시
##   - 동작은 초당 step_hz 번만 새로 그린다(12 = 2D 퍼펫의 초당 12장과 같은 끊는 맛 — 도트 느낌). 화면 밖 병사는 안 돌린다
##   - 겹침 순서는 3D 깊이 버퍼가 맡는다(2D 의 z 띠가 필요 없다) · 저해상도 그리기 · 외곽선 = DRDotView3D
##   - 복장 보기(wear_mode): 유닛 복장 / 상의만 / 하의만 / 내복 — 상의 · 하의를 따로 입히는 3D 슬롯이 도는지 바로 본다
##   - 조준 IK(10-21): 쏘는 표적(Ballistics.aim_point — 두뇌가 고른 적의 겨눌 곳) · 조종 중이면 조준점을 캐릭터에 준다 —
##     사격 · 조준 동작에서 팔(견착) · 허리로 총구 높낮이가 표적으로(DRCharacter3D.set_aim_target — 좌우는 동작 그대로)
## 연산: 노드 · 셰이더 값은 바뀔 때만 넣는다(자리 · 방향 · 사라지기 단계). 무거운 것(슬롯 나누기 · 동작별 그립)은 캐릭터를 만들 때 한 번 · 캐시.

## 도트 느낌(외곽선 · 픽셀 퍼펙트 · 명암 · 도트 크기 · 각도 · 초당 장수) — Dot Rigger ① 유닛 탭이 고치는 것과 같은 파일.
## 비우면 기본 파일(DRDotStyle.DEFAULT_PATH = res://game/dot_style.tres). 화면을 만들 때 아래 dot_px · pitch_deg · step_hz 도 이 값으로 맞춘다
@export var dot_style: DRDotStyle

## 3D 를 저해상도로 그리는 배율 — 도트 하나가 화면 몇 픽셀인가(1 = 도트화 끔). 화면 기준이라 확대하면 캐릭터가 더 촘촘해진다
@export_range(1, 6, 1) var dot_px := 2:
	set(v):
		dot_px = v
		if _dot != null:
			_dot.dot_px = v
## 카메라가 내려다보는 각(도). 깊이(0~1)가 3D 의 앞뒤 거리가 되려면 0 보다 커야 한다
@export_range(1.0, 45.0, 0.5) var pitch_deg := 15.0:
	set(v):
		pitch_deg = maxf(v, 1.0)
		if _dot != null:
			_dot.pitch_deg = pitch_deg
## 좌우를 볼 때 카메라 쪽으로 더 돌리는 각(도) — 0 = 완전 옆모습, 35 쯤이면 3/4(2D 퍼펫과 비슷하게 앞가슴 · 총이 보인다)
@export_range(0.0, 80.0, 1.0) var face_turn_deg := 35.0
## 돌아서는 빠르기(도/초) — 오른쪽 ↔ 왼쪽을 카메라 쪽(정면)을 거쳐 돈다
@export var turn_speed_deg := 720.0
## 3D 동작을 초당 몇 번 새로 그리나(0 = 매 프레임)
@export var step_hz := 12.0
## 동작이 바뀔 때 섞는 시간(초) — 무기 그립도 이 시간 동안 새 동작의 그립으로 옮긴다(DRCharacter3D.play_motion)
@export var blend_sec := 0.1

enum Wear { TYPE, TOP_ONLY, BOTTOM_ONLY, NONE }
const WEAR_NAMES := ["유닛 복장", "상의만", "하의만", "내복"]
const CORPSE_TINT := Color(0.55, 0.55, 0.55, 1.0)
const LIE_LIFT_M := 0.12            # 사망 동작이 없어 눕힐 때 땅에 반쯤 묻히지 않게 올리는 높이(m)
const FADE_STEPS := 16              # 사라지기 단계 — 셰이더의 4x4 디더 문턱이 16 개라 그 사이 값은 화면이 안 바뀐다
const SHADOW_R_M := 0.4             # 발밑 그림자 반지름(m)
const SHADOW_FLAT := 0.3            # 그림자 세로 납작함(땅을 비스듬히 내려다보니까)
const SHADOW_ALPHA := 0.3


## 병사 한 명의 3D 쪽 정보 — BattleView.Entry 에 캐릭터 몫을 더한 것(2D 화면 코드는 건드리지 않는다)
class Entry3D extends BattleView.Entry:
	var ch: DRCharacter3D = null
	var table: DRMotionTable = null          # 이 캐릭터의 동작 표(프리팹의 것, 없으면 병종의 것)
	var yaw := 0.0                          # 지금 보는 방향(라디안 — 돌아서는 중간값)
	var pos := Vector3.INF                  # 마지막으로 넣은 자리(같으면 다시 안 넣는다)
	var fade_q := 16                        # 마지막으로 넣은 사라지기 단계(FADE_STEPS = 다 보임)
	var state := ""                         # 지금 동작을 고른 동작 표의 상태
	var reroll := false                     # 그 상태에 고를 동작이 여럿 — 반복 동작이 한 바퀴 돌면 다시 고른다


## 복장 보기 — 바꾸면 화면의 모든 병사(쉬는 캐릭터 포함)를 다시 입힌다
var wear_mode: int = Wear.TYPE:
	set(v):
		wear_mode = clampi(v, 0, WEAR_NAMES.size() - 1)
		_redress_all()

var _dot: DRDotView3D = null
var _pool3d: Dictionary = {}         # 프리팹 경로 -> Array[DRCharacter3D] (쉬는 캐릭터)
var _avail3d: Dictionary = {}        # 프리팹 경로 -> 동작 이름들(같은 프리팹 캐릭터는 같은 동작 묶음을 같이 쓴다)
var _warned: Dictionary = {}         # 이미 경고한 것(같은 경고를 병사마다 되풀이하지 않게)


func _ready() -> void:
	_ensure_dot()


# ───────────── 바깥에서 부르는 것 ─────────────

## 그 병종의 캐릭터를 count 개까지 미리 만들어 숨겨 둔다(투입할 때 끊기지 않게 — 로딩 때 부른다)
func prewarm(type: SoldierType, count: int) -> void:
	if type == null or type.prefab == null:
		return
	_ensure_dot()
	var idle := _pool_of(type)
	while idle.size() < count:
		var ch := _make_character(type)
		if ch == null:
			return
		idle.append(ch)


## 화면 상태 한 줄(시험장 글자용)
func status_text() -> String:
	var units := PackedStringArray()
	for key in _avail3d.keys():
		units.append("%s 동작 %d개" % [String(key).get_file().get_basename(), (_avail3d[key] as PackedStringArray).size()])
	return "3D · 도트 %d px · 복장 %s · %s" % [dot_px, WEAR_NAMES[wear_mode], " · ".join(units) if not units.is_empty() else "유닛 프리팹 아직 안 읽음"]


# ───────────── 캐릭터 풀 ─────────────

func _ensure_dot() -> void:
	if _dot != null:
		return
	_dot = DRDotView3D.new()
	_dot.name = "Dot3D"
	if dot_style == null:
		dot_style = DRDotStyle.load_default()
	dot_style.apply_to(_dot)                 # 외곽선 · 픽셀 퍼펙트 · 도트 · 각도
	dot_style.apply_shading()                # 명암(병사 재질 공통)
	dot_px = dot_style.dot_px
	pitch_deg = dot_style.pitch_deg
	step_hz = dot_style.step_hz
	_sync_dot()
	_puppet_root.add_child(_dot)            # 땅(z 최소)과 상자 · 글자(z 최대) 사이


## 2D 좌표 설정(ppm · ground_y)을 3D 창에 옮긴다 — 3D 점이 to_canvas 와 같은 자리에 그려지게
func _sync_dot() -> void:
	_dot.px_per_m = ppm
	_dot.origin = Vector2(0.0, ground_y)


static func _prefab_key(t: SoldierType) -> String:
	return t.prefab.resource_path if t.prefab.resource_path != "" else "prefab#%d" % t.prefab.get_instance_id()


func _pool_of(t: SoldierType) -> Array:
	var key := _prefab_key(t)
	if not _pool3d.has(key):
		_pool3d[key] = []
	return _pool3d[key]


## 프리팹 하나를 꺼내 조립(씬에 넣는 순간 DRCharacter3D._ready 가 칸대로 조립)하고, 동작을 손으로 돌리게 · 그립을 미리 계산해 둔다
func _make_character(t: SoldierType) -> DRCharacter3D:
	var ch := t.prefab.instantiate() as DRCharacter3D
	if ch == null:
		_warn_once("prefab:" + _prefab_key(t), "유닛 프리팹의 루트가 DRCharacter3D 가 아닙니다: %s" % _prefab_key(t))
		return null
	_dot.world.add_child(ch)
	var ap := ch.get_animation_player()
	if ap == null:
		_warn_once("body:" + _prefab_key(t), "유닛 프리팹을 조립하지 못했습니다(몸 모델): %s" % _prefab_key(t))
	else:
		# 스스로 도는 것을 끈다 — 동작은 _advance 가 step_hz 에 맞춰 대신 돌린다(화면 밖이면 안 돌린다)
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		ch.precompute_grips()
		if ap.get_animation_list().size() <= 1:
			_warn_once("lib:" + _prefab_key(t), "3D 동작 묶음이 비었습니다(%s) — 동작 표 인스펙터의 [3D 동작 내보내기]" % _prefab_key(t))
	var key := _prefab_key(t)
	if not _avail3d.has(key):
		_avail3d[key] = ch.motion_names()
	_dress(ch)
	ch.visible = false
	return ch


func _take_character(t: SoldierType) -> DRCharacter3D:
	var idle := _pool_of(t)
	if idle.is_empty():
		return _make_character(t)
	return idle.pop_back() as DRCharacter3D


## 복장 보기(wear_mode)대로 — 유닛의 상의 · 하의를 입히거나 벗긴다
func _dress(ch: DRCharacter3D) -> void:
	ch.dress(wear_mode == Wear.TYPE or wear_mode == Wear.TOP_ONLY, wear_mode == Wear.TYPE or wear_mode == Wear.BOTTOM_ONLY)


func _redress_all() -> void:
	for v in _entries.values():
		var e := v as Entry3D
		if e.ch != null:
			_dress(e.ch)
	for key in _pool3d.keys():
		for c in (_pool3d[key] as Array):
			_dress(c as DRCharacter3D)


func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("[BattleView3D] " + msg)


## 오른쪽(+1) · 왼쪽(−1)을 볼 때의 몸 방향(Y 회전, 라디안). 모델은 +Z 를 보고 카메라는 +Z 쪽에 있다 →
## 90° 면 완전 옆모습, 거기서 face_turn_deg 만큼 카메라 쪽으로 덜 돌린다
func _face_yaw(facing: int) -> float:
	return float(facing if facing != 0 else 1) * deg_to_rad(90.0 - face_turn_deg)


# ───────────── BattleView 의 퍼펫 자리를 3D 로 바꿔 끼운다 ─────────────

func _attach(s: BattleSoldier) -> void:
	if s == null or _entries.has(s.id):
		return
	_ensure_dot()
	var e := Entry3D.new()
	e.s = s
	e.acc = randf() / maxf(step_hz, 1.0)       # 병사마다 갱신 박자를 다르게(한 프레임에 몰리지 않게)
	var t := s.type
	if t != null and t.prefab != null:
		var ch := _take_character(t)
		if ch != null:
			e.ch = ch
			e.pool_key = _prefab_key(t)
			e.avail = _avail3d.get(e.pool_key, PackedStringArray())
			e.table = ch.motions if ch.motions != null else t.motions
			e.yaw = _face_yaw(s.facing)
			ch.rotation = Vector3(0.0, e.yaw, 0.0)
			ch.visible = show_puppets
	_entries[s.id] = e


func _recycle(e: Entry) -> void:
	var e3 := e as Entry3D
	var ch := e3.ch
	if ch != null and is_instance_valid(ch):
		ch.visible = false
		ch.rotation = Vector3.ZERO
		ch.set_tint(Color.WHITE)
		ch.set_fade(1.0)
		ch.clear_aim_target(true)
		var ap := ch.get_animation_player()
		if ap != null:
			ap.stop()
			ap.speed_scale = 1.0
		if _pool3d.has(e3.pool_key):
			(_pool3d[e3.pool_key] as Array).append(ch)
		else:
			ch.queue_free()
	e3.ch = null
	_entries.erase(e3.s.id)


func _on_died(s: BattleSoldier) -> void:
	var e := _entries.get(s.id, null) as Entry3D
	if e == null:
		return
	e.dead_t = 0.0
	e.label = ""
	e.cands = _death_keys(s.stance)
	var had_motion := e.motion != ""
	e.motion = ""
	e.reroll = false
	if e.ch == null:
		return
	e.ch.set_tint(CORPSE_TINT)
	e.ch.clear_aim_target(true)
	# 죽을 때의 자세에 맞는 사망 동작(기본 동작으로 내려가면 안 되므로 pick 이 아니라 상태마다 pick_state — 2D 와 같은 규칙)
	var m := ""
	if e.table != null:
		for key in e.cands:
			m = e.table.pick_state(key, e.avail)
			if m != "":
				break
	if m != "":
		e.ch.get_animation_player().speed_scale = 1.0
		e.ch.play_motion(m, blend_sec if had_motion else 0.0)
		e.motion = m
	elif s.stance != BattleBody.Stance.PRONE:
		# 임시 표현: 등을 대고 누운 모습(몸의 옆 축으로 −90°). 엎드린 채 죽으면 그 자세 그대로 둔다(2D 와 같은 이유)
		e.ch.rotation = Vector3(-PI * 0.5, e.yaw, 0.0)
		e.ch.position.y += LIE_LIFT_M


func _process(delta: float) -> void:
	if _dot != null:
		_sync_dot()
		_dot.visible = show_puppets
	super(delta)


func _update_soldier(e: Entry, delta: float, _step: float) -> void:
	var e3 := e as Entry3D
	var s := e3.s
	# 몸 상태를 한 수로 — 바뀐 프레임에만 동작 후보 · 글자를 다시 만든다(BattleView 와 같다)
	var sig := s.override | (s.move_state << 3) | (s.act_state << 6) | (s.stance << 9)
	if sig != e3.sig or s.intent_name != e3.last_intent:
		e3.last_intent = s.intent_name
		e3.label = _label_for(s)
	if sig != e3.sig:
		e3.sig = sig
		_pick_motion(e3)
	var ch := e3.ch
	if ch == null:
		return
	if ch.visible != show_puppets:
		ch.visible = show_puppets
	if not show_puppets:
		return
	var foot := to_canvas(s.x, 0.0, s.depth)
	var p := _dot.ground_to_world(foot)                                 # 깊이 → 3D 앞뒤
	if p != e3.pos:
		e3.pos = p
		ch.position = p
	var want := _face_yaw(s.facing)
	if e3.yaw != want:
		e3.yaw = move_toward(e3.yaw, want, deg_to_rad(turn_speed_deg) * delta)
		ch.rotation = Vector3(0.0, e3.yaw, 0.0)
	if e3.motion != "" and foot.x > _vis_x0 and foot.x < _vis_x1:       # 맞는 동작이 없거나 화면 밖이면 진행시키지 않는다
		_advance(e3, delta, true)


func _update_corpse(e: Entry, delta: float, _step: float) -> bool:
	var e3 := e as Entry3D
	e3.dead_t += delta
	var left := corpse_seconds - e3.dead_t
	var ch := e3.ch
	if ch == null:
		return left <= 0.0
	if ch.visible != show_puppets:
		ch.visible = show_puppets
	if e3.motion != "":
		_advance(e3, delta)
	if left < CORPSE_FADE_SEC:
		# 도트식으로 듬성듬성 사라진다(셰이더 디더) — 단계가 바뀔 때만 넣는다
		var q := ceili(clampf(left / CORPSE_FADE_SEC, 0.0, 1.0) * float(FADE_STEPS))
		if q != e3.fade_q:
			e3.fade_q = q
			ch.set_fade(float(q) / float(FADE_STEPS))
	return left <= 0.0


## 동작을 모았다가 step_hz 에 맞춰 한 번에 진행시킨다(무기 그립 섞기도 같은 박자로 — DRCharacter3D.step_motion). aim = 그 박자에 조준 표적도 새로
func _advance(e: Entry3D, delta: float, aim := false) -> void:
	e.acc += delta
	var step := 1.0 / step_hz if step_hz > 0.0 else 0.0
	if e.acc < step:
		return
	if aim:
		_aim(e)
	if e.ch.step_motion(e.acc) and e.reroll:
		_reroll(e)                                   # 반복 동작이 한 바퀴 돌았다 — 그 상태의 동작 중에서 비중대로 다시
	e.acc = 0.0


## 조준 IK 표적(10-21) — 조종 중이면 조준점, 아니면 두뇌가 고른 적의 겨눌 곳(Ballistics.aim_point — 총알이 가는 곳과 같다). 없으면 거둔다.
## 높낮이만 겨누므로(횡스크롤 — 좌우는 동작 그대로) 표적의 깊이(앞뒤 줄)는 쏘는 병사 줄로 둔다 — 높낮이 = 좌우 거리 대 높이 차(Ballistics 와 같은 뜻)
func _aim(e: Entry3D) -> void:
	var s := e.s
	var a := Vector3.INF
	if s.controller != 0:
		a = Vector3(s.aim_x, s.aim_h, s.aim_depth)
	elif s.target != null and s.target.alive:
		a = Ballistics.aim_point(s, s.target)
	if a == Vector3.INF:
		if e.ch.has_aim_target():
			e.ch.clear_aim_target()
		return
	e.ch.set_aim_target(_dot.ground_to_world(to_canvas(a.x, 0.0, s.depth)) + Vector3(0.0, a.y, 0.0))


func _pick_motion(e: Entry) -> void:
	var e3 := e as Entry3D
	var s := e3.s
	e3.cands = _candidates(s)
	var mt := e3.table
	if e3.ch == null or mt == null:
		e3.motion = ""
		return
	var ap := e3.ch.get_animation_player()
	var st := mt.state_of(e3.cands, e3.avail)
	var m := ""
	if st != "" and st == e3.state and e3.motion != "" and mt.has_motion(st, e3.motion) and String(ap.current_animation) == e3.motion:
		m = e3.motion                             # 고른 표 상태가 그대로 — 틀던 동작을 이어 간다(바꾸기는 한 바퀴 돌 때 _reroll)
	else:
		m = mt.pick_state(st, e3.avail) if st != "" else mt.pick(e3.cands, e3.avail)   # 동작이 여럿이면 비중(%)대로
	e3.state = st
	e3.reroll = st != "" and mt.variant_count(st, e3.avail) > 1
	if m != "" and (m != e3.motion or String(ap.current_animation) != m):
		e3.ch.play_motion(m, blend_sec if e3.motion != "" else 0.0)
	e3.motion = m
	# 걷기에 달리기 동작을 빌려 쓰는 동안은 걷는 속도만큼 느리게(BattleView 와 같다)
	var spd := 1.0
	if s.move_state == BattleBody.Move.WALK and m != "" and not mt.has_motion("걷기", m) and mt.has_motion("달리기", m):
		spd = s.type.walk_speed / maxf(s.type.run_speed, 0.01)
		if s.stance == BattleBody.Stance.CROUCH:
			spd *= s.type.crouch_move_mult
	ap.speed_scale = clampf(spd, 0.1, 1.0)


## 반복 동작이 한 바퀴 돌았을 때 — 그 표 상태의 동작 중에서 비중대로 다시 고른다(같은 것이 나오면 그대로 이어 감).
## 예: 서기 = Rifle_Idle 70 % · Idle_LookAround 30 % 면 대기 중인 병사가 가끔 두리번거린다
func _reroll(e: Entry3D) -> void:
	if e.table == null or e.state == "":
		return
	var m := e.table.pick_state(e.state, e.avail)
	if m != "" and m != e.motion:
		e.ch.play_motion(m, blend_sec)
		e.motion = m


## 3D 는 깊이 버퍼가 겹침을 맡는다 — z 띠를 매기지 않는다
func _reorder() -> void:
	_bands_used = 1 if not _entries.is_empty() else 0


## 땅 · 엄폐물(BattleView) 위에 병사 발밑 그림자 — 그림자가 없으면 3D 캐릭터가 2D 땅 위에 떠 보인다(C 시험 장면과 같은 표현)
func _draw_ground() -> void:
	super()
	if _bf == null or not is_instance_valid(_bf) or not show_puppets:
		return
	var r := SHADOW_R_M * ppm
	var col := Color(0.0, 0.0, 0.0, SHADOW_ALPHA)
	for v in _entries.values():
		var e := v as Entry3D
		# 쓰러진 병사는 그림자를 안 그린다 — 사망 동작이 몸을 1.2 m 쯤 뒤로 밀어(Stand_Rifle_Hit_To_Back) 기록 자리와 어긋난다
		if e.ch == null or e.dead_t >= 0.0:
			continue
		_bg.draw_set_transform(to_canvas(e.s.x, 0.0, e.s.depth), 0.0, Vector2(1.0, SHADOW_FLAT))
		_bg.draw_circle(Vector2.ZERO, r, col)
	_bg.draw_set_transform(Vector2.ZERO)
