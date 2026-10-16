extends BattleView
class_name BattleView3D

## 전투 화면 3D 판(10-15, 3D 노선) — BattleView(2D 퍼펫)와 같은 일을 하되 병사를 3D 캐릭터(DRCharacter3D)로 그린다.
## 땅 · 엄폐물 · 판정 상자 · 글자 · 총알 자국 · 마우스 판정은 BattleView 의 2D 그대로 물려받는다. 3D 는 DRDotView3D 가
## 2D 좌표와 정확히 같은 자리에 그려 주므로(to_canvas 와 같은 점) 시험장(battle_test)은 화면만 바꿔 끼우면 된다.
##
## 하는 일
##   - 병사 기록 → 3D 캐릭터 자리 · 방향(좌우 + 카메라 쪽으로 face_turn_deg) · 동작(AnimationPlayer) · 무기 그립
##   - 캐릭터는 병종마다 미리 만들어 두고 돌려 쓴다(prewarm). 몸 · 복장 메시 · 재질 · 스킨은 DRCharacter3D 가 병사끼리 공유한다
##   - 동작은 초당 step_hz 번만 새로 그린다(12 = 2D 퍼펫의 초당 12장과 같은 끊는 맛 — 도트 느낌). 화면 밖 병사는 안 돌린다
##   - 겹침 순서는 3D 깊이 버퍼가 맡는다(2D 의 z 띠가 필요 없다) · 저해상도 그리기 · 외곽선 = DRDotView3D
##   - 복장 보기(wear_mode): 병종 복장 / 상의만 / 하의만 / 내복 — 상의 · 하의를 따로 입히는 3D 슬롯이 도는지 바로 본다
## 연산: 노드 · 셰이더 값은 바뀔 때만 넣는다(자리 · 방향 · 사라지기 단계). 무거운 것(슬롯 나누기 · 동작별 그립)은 캐릭터를 만들 때 한 번 · 캐시.
##
## 필요한 것(병종 SoldierType "외형 3D"): body_model(사람 몸 glb) · motion_library(동작 내보내기가 만든 AnimationLibrary)
##   동작 묶음 만들기: 에디터 프로젝트 > 도구 > "Dot Rigger — 3D 동작 내보내기" (또는 tools/export_motions_cli.gd)

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
## 동작이 바뀔 때 섞는 시간(초) — 무기 그립도 이 시간 동안 새 동작의 그립으로 옮긴다
@export var blend_sec := 0.1

enum Wear { TYPE, TOP_ONLY, BOTTOM_ONLY, NONE }
const WEAR_NAMES := ["병종 복장", "상의만", "하의만", "내복"]
const CORPSE_TINT := Color(0.55, 0.55, 0.55, 1.0)
const LIE_LIFT_M := 0.12            # 사망 동작이 없어 눕힐 때 땅에 반쯤 묻히지 않게 올리는 높이(m)
const FADE_STEPS := 16              # 사라지기 단계 — 셰이더의 4x4 디더 문턱이 16 개라 그 사이 값은 화면이 안 바뀐다
const SHADOW_R_M := 0.4             # 발밑 그림자 반지름(m)
const SHADOW_FLAT := 0.3            # 그림자 세로 납작함(땅을 비스듬히 내려다보니까)
const SHADOW_ALPHA := 0.3
const RESET_ANIM := "RESET"


## 병사 한 명의 3D 쪽 정보 — BattleView.Entry 에 캐릭터 몫을 더한 것(2D 화면 코드는 건드리지 않는다)
class Entry3D extends BattleView.Entry:
	var ch: DRCharacter3D = null
	var yaw := 0.0                          # 지금 보는 방향(라디안 — 돌아서는 중간값)
	var pos := Vector3.INF                  # 마지막으로 넣은 자리(같으면 다시 안 넣는다)
	var grip_from := Transform3D.IDENTITY   # 동작이 바뀔 때 무기 그립을 섞는 시작 · 끝(손 뼈 로컬)
	var grip_to := Transform3D.IDENTITY
	var grip_t := -1.0                      # 그립을 섞은 시간(−1 = 섞는 중 아님)
	var fade_q := 16                        # 마지막으로 넣은 사라지기 단계(FADE_STEPS = 다 보임)


## 복장 보기 — 바꾸면 화면의 모든 병사(쉬는 캐릭터 포함)를 다시 입힌다
var wear_mode: int = Wear.TYPE:
	set(v):
		wear_mode = clampi(v, 0, WEAR_NAMES.size() - 1)
		_redress_all()

var _dot: DRDotView3D = null
var _pool3d: Dictionary = {}         # 병종 키 -> Array[DRCharacter3D] (쉬는 캐릭터)
var _types: Dictionary = {}          # 병종 키 -> SoldierType
var _avail3d: Dictionary = {}        # 병종 키 -> 동작 이름들(그 병종 캐릭터는 같은 동작 묶음을 같이 쓴다)
var _libs: Dictionary = {}           # 동작 묶음 경로 -> AnimationLibrary(없으면 null) — 경로마다 한 번만 읽는다
var _warned: Dictionary = {}         # 이미 경고한 것(같은 경고를 병사마다 되풀이하지 않게)


func _ready() -> void:
	_ensure_dot()


# ───────────── 바깥에서 부르는 것 ─────────────

## 그 병종의 3D 캐릭터를 count 개까지 미리 만들어 숨겨 둔다(투입할 때 끊기지 않게 — 로딩 때 부른다)
func prewarm(type: SoldierType, count: int) -> void:
	if type == null or type.body_model == "":
		return
	_ensure_dot()
	var idle := _pool3d_for(type)
	while idle.size() < count:
		idle.append(_make_character(type))


## 화면 상태 한 줄(시험장 글자용)
func status_text() -> String:
	var libs := PackedStringArray()
	for path in _libs.keys():
		var lib := _libs[path] as AnimationLibrary
		libs.append("%s %s" % [String(path).get_file(), ("동작 %d개" % lib.get_animation_list().size()) if lib != null else "없음!"])
	return "3D · 도트 %d px · 복장 %s · %s" % [dot_px, WEAR_NAMES[wear_mode], " · ".join(libs) if not libs.is_empty() else "동작 묶음 아직 안 읽음"]


# ───────────── 캐릭터 풀 ─────────────

func _ensure_dot() -> void:
	if _dot != null:
		return
	_dot = DRDotView3D.new()
	_dot.name = "Dot3D"
	_dot.dot_px = dot_px
	_dot.pitch_deg = pitch_deg
	_sync_dot()
	_puppet_root.add_child(_dot)            # 땅(z 최소)과 상자 · 글자(z 최대) 사이


## 2D 좌표 설정(ppm · ground_y)을 3D 창에 옮긴다 — 3D 점이 to_canvas 와 같은 자리에 그려지게
func _sync_dot() -> void:
	_dot.px_per_m = ppm
	_dot.origin = Vector2(0.0, ground_y)


static func _type_key(t: SoldierType) -> String:
	return t.resource_path if t.resource_path != "" else "type#%d" % t.get_instance_id()


func _pool3d_for(t: SoldierType) -> Array:
	var key := _type_key(t)
	if not _pool3d.has(key):
		_pool3d[key] = []
		_types[key] = t
	return _pool3d[key]


func _lib_for(path: String) -> AnimationLibrary:
	if path == "":
		return null
	if not _libs.has(path):
		var lib: AnimationLibrary = null
		if ResourceLoader.exists(path):
			lib = load(path) as AnimationLibrary
		_libs[path] = lib
		if lib == null:
			_warn_once("lib:" + path, "3D 동작 묶음이 없습니다: %s — 에디터 도구 메뉴 \"Dot Rigger — 3D 동작 내보내기\" 로 만드세요" % path)
	return _libs[path] as AnimationLibrary


func _make_character(t: SoldierType) -> DRCharacter3D:
	var ch := DRCharacter3D.new()
	ch.name = "Soldier3D"
	_dot.world.add_child(ch)
	if not ch.setup(t.body_model):
		_warn_once("body:" + t.body_model, "3D 몸을 불러오지 못했습니다: %s" % t.body_model)
		ch.visible = false
		return ch
	_dress(ch, t)
	var lib := _lib_for(t.motion_library)
	if lib != null:
		ch.set_motions(lib)
	var ap := ch.get_animation_player()
	# 스스로 도는 것을 끈다 — 동작은 _advance 가 step_hz 에 맞춰 대신 돌린다(화면 밖이면 안 돌린다)
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if t.weapon != null and t.weapon.model_asset != "":
		if ch.attach_weapon(t.weapon.model_asset):
			_fit_grips(ch)
		else:
			_warn_once("weapon:" + t.weapon.model_asset, "3D 무기를 붙이지 못했습니다: %s" % t.weapon.model_asset)
	var key := _type_key(t)
	if not _avail3d.has(key):
		var names := PackedStringArray()
		for n in ap.get_animation_list():
			if String(n) != RESET_ANIM:
				names.append(String(n))
		_avail3d[key] = names
	ch.scale = Vector3.ONE * (t.height_m / maxf(ch.model_height(), 0.01))   # 이 병종의 키에 맞춘다(한 번)
	ch.visible = false
	return ch


## 동작마다 무기 그립을 미리 계산해 둔다. 장비 창의 저장 그립은 달리기 자세에서 잡힌 것이라 소총 동작에서 왼손이 총에 안 닿고
## (10-15 B 갈래 확인), Mixamo 동작마다 두 손 사이가 달라 한 그립으로는 다 못 맞춘다 → DRGripFit 이 동작별로 다시 맞춘다.
## 결과는 (몸 · 무기 · 동작 묶음 · 동작) 별 캐시라 병사 수와 상관없이 한 번. 처음 계산은 캐릭터 자세를 잠깐 바꿨다 되돌리므로
## 재생 중이 아닌 지금(만들 때) 해 두면 게임 중에는 캐시만 꺼낸다
func _fit_grips(ch: DRCharacter3D) -> void:
	for n in ch.get_animation_player().get_animation_list():
		if String(n) != RESET_ANIM:
			DRGripFit.fit_anim(ch, String(n))


func _take_character(t: SoldierType) -> DRCharacter3D:
	var idle := _pool3d_for(t)
	if idle.is_empty():
		return _make_character(t)
	return idle.pop_back() as DRCharacter3D


## 복장 보기(wear_mode)에 맞춰 입힌다. 병종에 상의 · 하의를 따로 적었으면(outfit_top_json · outfit_bottom_json) 그것을 섞어 입힌다
func _dress(ch: DRCharacter3D, t: SoldierType) -> void:
	ch.take_off()
	if wear_mode == Wear.NONE:
		return
	var top := t.outfit_top_json if t.outfit_top_json != "" else t.outfit_json
	var bottom := t.outfit_bottom_json if t.outfit_bottom_json != "" else t.outfit_json
	if top != "" and wear_mode != Wear.BOTTOM_ONLY:
		ch.wear(top, PackedStringArray(["top"]))
	if bottom != "" and wear_mode != Wear.TOP_ONLY:
		ch.wear(bottom, PackedStringArray(["bottom"]))


func _redress_all() -> void:
	for v in _entries.values():
		var e := v as Entry3D
		if e.ch != null and e.s.type != null:
			_dress(e.ch, e.s.type)
	for key in _pool3d.keys():
		var t := _types.get(key, null) as SoldierType
		if t == null:
			continue
		for c in (_pool3d[key] as Array):
			_dress(c as DRCharacter3D, t)


func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning("[BattleView3D] " + msg)


## 오른쪽(+1) · 왼쪽(−1)을 볼 때의 몸 방향(Y 회전, 라디안). 모델은 +Z 를 보고 카메라는 +Z 쪽에 있다 →
## 90° 면 완전 옆모습, 거기서 face_turn_deg 만큼 카메라 쪽으로 덜 돌린다
func _face_yaw(facing: int) -> float:
	return float(facing if facing != 0 else 1) * deg_to_rad(90.0 - face_turn_deg)


## 동작을 틀고 무기 그립을 그 동작 것으로 옮기기 시작한다. first = 처음 자세(섞지 않고 바로)
func _play(e: Entry3D, m: String, first: bool) -> void:
	var ap := e.ch.get_animation_player()
	ap.play(m, 0.0 if first else blend_sec)
	if first:
		ap.advance(0.0)                          # 처음 자세를 바로 — 안 그러면 다음 갱신까지 레스트(T자) 자세로 보인다
	if e.ch.get_weapon_node() == null:
		return
	var g := DRGripFit.fit_anim(e.ch, m)          # 만들 때 미리 계산해 둔 캐시
	if g.is_empty():
		return
	if first or blend_sec <= 0.0:
		e.ch.set_weapon_grip(g["grip"])
		e.grip_t = -1.0
	else:
		e.grip_from = e.ch.get_weapon_grip()
		e.grip_to = g["grip"]
		e.grip_t = 0.0


# ───────────── BattleView 의 퍼펫 자리를 3D 로 바꿔 끼운다 ─────────────

func _attach(s: BattleSoldier) -> void:
	if s == null or _entries.has(s.id):
		return
	_ensure_dot()
	var e := Entry3D.new()
	e.s = s
	e.acc = randf() / maxf(step_hz, 1.0)       # 병사마다 갱신 박자를 다르게(한 프레임에 몰리지 않게)
	var t := s.type
	if t != null and t.body_model != "":
		var ch := _take_character(t)
		e.ch = ch
		e.pool_key = _type_key(t)
		e.avail = _avail3d.get(e.pool_key, PackedStringArray())
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
		var ap := ch.get_animation_player()
		ap.stop()
		ap.speed_scale = 1.0
		var t := _types.get(e3.pool_key, null) as SoldierType
		if t != null:
			_pool3d_for(t).append(ch)
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
	if e.ch == null:
		return
	e.ch.set_tint(CORPSE_TINT)
	# 죽을 때의 자세에 맞는 사망 동작(기본 동작으로 내려가면 안 되므로 MotionTable.find 를 쓰지 않는다 — 2D 와 같은 규칙)
	var mt: MotionTable = s.type.motions if s.type != null else null
	var m := ""
	if mt != null:
		for key in e.cands:
			var cand := String(mt.motions.get(key, ""))
			if cand != "" and e.avail.has(cand):
				m = cand
				break
	if m != "":
		e.ch.get_animation_player().speed_scale = 1.0
		_play(e, m, not had_motion)
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
		_advance(e3, delta)


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


## 동작을 모았다가 step_hz 에 맞춰 한 번에 진행시킨다(무기 그립 섞기도 같은 박자로)
func _advance(e: Entry3D, delta: float) -> void:
	e.acc += delta
	var step := 1.0 / step_hz if step_hz > 0.0 else 0.0
	if e.acc < step:
		return
	e.ch.get_animation_player().advance(e.acc)
	if e.grip_t >= 0.0:
		e.grip_t += e.acc
		var k := clampf(e.grip_t / maxf(blend_sec, 0.001), 0.0, 1.0)
		e.ch.set_weapon_grip(e.grip_from.interpolate_with(e.grip_to, k))
		if k >= 1.0:
			e.grip_t = -1.0
	e.acc = 0.0


func _pick_motion(e: Entry) -> void:
	var e3 := e as Entry3D
	var s := e3.s
	e3.cands = _candidates(s)
	var mt: MotionTable = s.type.motions if s.type != null else null
	if e3.ch == null or mt == null:
		e3.motion = ""
		return
	var ap := e3.ch.get_animation_player()
	var m := mt.find(e3.cands, e3.avail)
	if m != "" and (m != e3.motion or String(ap.current_animation) != m):
		_play(e3, m, e3.motion == "")
	e3.motion = m
	# 걷기에 달리기 동작을 빌려 쓰는 동안은 걷는 속도만큼 느리게(BattleView 와 같다)
	var spd := 1.0
	if s.move_state == BattleBody.Move.WALK and m != "" and m == String(mt.motions.get("달리기", "")):
		spd = s.type.walk_speed / maxf(s.type.run_speed, 0.01)
		if s.stance == BattleBody.Stance.CROUCH:
			spd *= s.type.crouch_move_mult
	ap.speed_scale = clampf(spd, 0.1, 1.0)


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
