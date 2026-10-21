extends Node2D
class_name BattleView

## 전투 화면(표현 층) — 전장 기록(Battlefield)을 **읽어서 그리기만** 한다.  (보병_추상화.md §2-2 표현 · §2-5 · §2-11)
## 논리를 바꾸지 않고 입력도 받지 않는다(입력은 시험 씬 · 빙의 조종이 맡는다). 그래서 이 층은 통째로 갈아 끼울 수 있다.
##
## 하는 일
##   - 병사 기록 → 퍼펫(DRPuppetSet) 자리 · 크기 · 좌우 · 동작. 퍼펫은 미리 만들어 두고 돌려 쓴다(부하시험_결과.md §5)
##   - 애니 갱신은 초당 anim_hz 번만, 자리 이동은 매 프레임(§3)
##   - 겹치는 병사끼리만 다른 z 띠(§4) — 구운 퍼펫의 조각 z 는 그대로 둔다
##   - 땅 · 엄폐물은 퍼펫 뒤, 판정 상자 · 상태 글자 · 총알 자국은 퍼펫 위
##
## 좌표: 이 노드의 로컬 좌표(px). x = m × ppm, 땅의 y = ground_y + (깊이 − 0.5) × depth_px(깊이 1 이 아래 = 화면 앞쪽),
##       높이는 위로(y 가 줄어든다). 마우스 자리를 넘길 때는 get_local_mouse_position() 을 쓴다.
## 주의: setup() · prewarm() 은 이 노드가 씬 트리에 들어간 뒤에 부른다(퍼펫은 트리에 들어가야 만들어진다).

## 1 m 가 화면 몇 px 인가
@export var ppm := 40.0
## 깊이 0.5 인 땅의 y
@export var ground_y := 430.0
## 깊이 0 → 1 이 화면 y 로 몇 px 인가
@export var depth_px := 150.0
## 퍼펫 애니를 초당 몇 번 갱신하나(구운 동작이 초당 12장이라 20~30 이면 충분 — 부하시험_결과.md §3)
@export var anim_hz := 24.0
## 판정 상자(자세별 몸 상자) 보이기
@export var show_boxes := true
## 머리 위 상태 글자 · 제압 막대 · 탄약 보이기
@export var show_labels := true
@export var show_puppets := true
## 쓰러진 병사를 화면에 두는 시간(초). 그 뒤 퍼펫을 풀로 돌려준다
@export var corpse_seconds := 8.0
## 모든 동작을 반복으로(반복 표시 없이 구운 동작을 계속 돌려 볼 때만 — 켜면 "사망"도 반복된다)
@export var puppet_force_loop := false

const EquipMarks := preload("res://game/view/equip_marks.gd")    # 운용 장비 자리 표시(모델이 생기기 전까지)
const OVERLAP_M := 1.2             # x 가 이보다 가까우면 화면에서 겹친다고 본다
const REORDER_SEC := 0.1           # z 띠를 다시 매기는 주기
const TRACER_MIN_SEC := 0.06       # 총알 자국이 보이는 최소 시간(실제 비행은 너무 짧아 안 보인다)
const TRACER_TAIL := 0.35          # 자국 꼬리 길이(경로의 비율)
const IMPACT_SEC := 0.1            # 도착 뒤 점이 남는 시간
const CORPSE_FADE_SEC := 1.5       # 사라지기 직전 흐려지는 시간
const LABEL_W := 140.0
const OFFSCREEN_MARGIN_PX := 150.0 # 화면 밖으로 이만큼까지는 애니를 계속 돌린다(들어올 때 튀지 않게)
## 이동 동작을 아직 안 구웠을 때 대신 쓸 것(앞에서부터). 앉아걷기가 없으면 앉은 채 미끄러지고, 그것도 없으면 서서 걷는다
const MOVE_FALLBACK := {
	"걷기": ["달리기"],
	"앉아걷기": ["앉기", "걷기", "달리기"],
	"포복": ["엎드림"],
}
const TEAM_FILL := [Color(0.25, 0.5, 1.0, 0.2), Color(1.0, 0.3, 0.25, 0.2)]
const TEAM_LINE := [Color(0.42, 0.66, 1.0, 0.95), Color(1.0, 0.46, 0.4, 0.95)]


## 병사 한 명의 화면 쪽 정보 — 병사 기록(BattleSoldier)에는 그림 정보를 넣지 않는다
class Entry:
	var s: BattleSoldier
	var puppet: DRPuppetSet = null
	var pool_key := ""                       # 돌려줄 풀(sets_json)
	var avail := PackedStringArray()         # 퍼펫이 가진 동작 이름
	var sig := -1                            # 몸 상태를 한 수로 묶은 것 — 바뀔 때만 동작 · 글자를 다시 정한다
	var cands := PackedStringArray()         # 동작 후보(구체적인 것부터)
	var motion := ""                         # 지금 재생 동작("" = 맞는 동작이 없어 멈춘 채)
	var acc := 0.0                           # 애니 갱신을 위해 모은 시간
	var label := ""
	var last_intent := ""
	var dead_t := -1.0                       # 쓰러진 뒤 지난 시간(−1 = 살아 있음)


var _bf: Battlefield = null
var _entries: Dictionary = {}                # 병사 id -> Entry
var _pool: Dictionary = {}                   # sets_json -> Array[DRPuppetSet] (쉬는 퍼펫)
var _held: Dictionary = {}                   # sets_json -> Array[PackedScene] — 붙들어 둬야 병사마다 씬 파일을 다시 읽지 않는다
var _outfits: Dictionary = {}                # outfit_json -> DROutfit(없으면 null) — 경로마다 한 번만 읽는다
var _tracers: Array = []                     # [{a: Vector2, b: Vector2, t0, dur, hit, blocked}]
var _clock := 0.0
var _band_timer := 0.0
var _vis_x0 := -INF                          # 지금 화면에 보이는 x 범위(이 노드의 로컬 px, 여유 포함) — 밖의 병사는 애니를 멈춘다
var _vis_x1 := INF
var _z_lo := 0                               # 퍼펫 조각 z 의 최소 · 최대(구운 값)
var _z_hi := 0
var _z_span := 0                             # 병사 한 명이 차지하는 z 폭(0 = 아직 안 쟀다)
var _bands_used := 0
var _bg: Node2D                              # 땅 · 엄폐물(퍼펫 뒤)
var _puppet_root: Node2D
var _fg: Node2D                              # 상자 · 글자 · 총알 자국(퍼펫 위)


func _init() -> void:
	# 그리는 층을 따로 둔다: 이 노드 자신의 z 를 낮추면 자식(퍼펫)까지 같이 내려가므로, z 를 절대값으로 가진 자식 둘에 나눠 그린다
	_bg = Node2D.new()
	_bg.name = "Ground"
	_bg.z_as_relative = false
	_bg.z_index = RenderingServer.CANVAS_ITEM_Z_MIN
	add_child(_bg)
	_bg.draw.connect(_draw_ground)
	_puppet_root = Node2D.new()
	_puppet_root.name = "Puppets"
	add_child(_puppet_root)
	_fg = Node2D.new()
	_fg.name = "Overlay"
	_fg.z_as_relative = false
	_fg.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	add_child(_fg)
	_fg.draw.connect(_draw_overlay)


# ───────────── 바깥에서 부르는 것 ─────────────

## 전장을 붙인다. 이미 있는 병사도 화면에 올린다
func setup(bf: Battlefield) -> void:
	_bf = bf
	if bf == null:
		return
	if not bf.soldier_spawned.is_connected(_on_spawned):
		bf.soldier_spawned.connect(_on_spawned)
		bf.soldier_died.connect(_on_died)
		bf.shot_fired.connect(_on_shot)
	for s in bf.soldiers:
		if s.alive:
			_attach(s)


## 그 병종의 퍼펫을 count 개까지 미리 만들어 숨겨 둔다(투입할 때 끊기지 않게 — 로딩 때 부른다)
func prewarm(type: SoldierType, count: int) -> void:
	if type == null or type.sets_json == "":
		return
	var idle := _pool_for(type.sets_json)
	while idle.size() < count:
		idle.append(_make_puppet(type.sets_json))
	if type.outfit_json != "":
		_outfit_for(type.outfit_json)


## (x m, 높이 m, 깊이 0~1) → 이 노드의 로컬 좌표
func to_canvas(x: float, h: float, depth: float) -> Vector2:
	return Vector2(x * ppm, ground_at(depth) - h * ppm)


## 그 깊이의 땅 y
func ground_at(depth: float) -> float:
	return ground_y + (depth - 0.5) * depth_px


func x_from_canvas(px: float) -> float:
	return px / maxf(ppm, 0.001)


## 그 자리에서 가장 가까운(몸 가운데 기준) 싸울 수 있는 병사. team −1 = 아무 편. radius_px 안에 없으면 null
func soldier_near(canvas_pos: Vector2, team: int = -1, radius_px: float = 40.0) -> BattleSoldier:
	if _bf == null:
		return null
	var best: BattleSoldier = null
	var best_d := radius_px
	for s in _bf.soldiers:
		if not s.can_fight() or (team >= 0 and s.team != team):
			continue
		var d := to_canvas(s.x, s.type.box(s.stance).y * 0.5, s.depth).distance_to(canvas_pos)
		if d <= best_d:
			best_d = d
			best = s
	return best


## 빙의 조준(§2-12) — 마우스는 깊이를 못 고르므로, 커서에 가장 가까운 적의 깊이를 원의 중심 깊이로 삼는다.
## 돌려주는 값 = Vector3(x m, 높이 m, 깊이). 적이 없으면 깊이 = 쏘는 병사의 깊이
func aim_from_canvas(canvas_pos: Vector2, shooter: BattleSoldier) -> Vector3:
	var depth := shooter.depth if shooter != null else 0.5
	if _bf != null and shooter != null:
		var best_d := INF
		for s in _bf.soldiers:
			if s.team == shooter.team or not s.can_fight():
				continue
			var d := to_canvas(s.x, s.type.box(s.stance).y * 0.5, s.depth).distance_squared_to(canvas_pos)
			if d < best_d:
				best_d = d
				depth = s.depth
	var h := maxf(0.0, (ground_at(depth) - canvas_pos.y) / maxf(ppm, 0.001))
	return Vector3(x_from_canvas(canvas_pos.x), h, depth)


## 지금 쓰는 z 띠 수(53 을 넘기면 띠가 모자란다 — 부하시험_결과.md §4)
func get_bands_used() -> int:
	return _bands_used


## 병사 하나의 상태를 여러 줄 글로 — 실행 중에 "지금 어느 상태 · 어느 동작"인지 확인하는 용도(§2-11)
func describe(s: BattleSoldier) -> String:
	if s == null:
		return ""
	var lines := PackedStringArray()
	lines.append("%s #%d  (편 %d)%s" % [s.type.display_name if s.type != null else "?", s.id, s.team, "  ★ 빙의 중" if s.controller == 1 else ""])
	var sq := s.squad
	if sq != null:
		lines.append("분대 %d   태세 %s · 명령 %s   사기 %.2f%s   (부릴 수 있는 병사 %d / %d)" % [sq.id, BattleSquad.POSTURE_NAMES[sq.posture],
			BattleSquad.ORDER_NAMES[sq.order], sq.morale, "  ⚠ 패주" if sq.routed else "", sq.active().size(), sq.members.size()])
	var sc := PackedStringArray()
	for k in s.intent_scores.keys():
		sc.append("%s %.2f" % [String(k), float(s.intent_scores[k])])
	lines.append("의도 [%s]   %s" % [s.intent_name, " · ".join(sc)])
	lines.append("몸: 이동 %s · 행동 %s · 덮어쓰기 %s · 자세 %s%s" % [BattleBody.MOVE_NAMES[s.move_state], BattleBody.ACT_NAMES[s.act_state],
		BattleBody.OVR_NAMES[s.override], BattleBody.STANCE_NAMES[s.stance], "   (엄폐 받는 중)" if s.in_cover else ""])
	var e := _entries.get(s.id, null) as Entry
	if e != null:
		lines.append("동작: %s   ← 후보 %s" % [e.motion if e.motion != "" else "(맞는 동작 없음 — 멈춘 채)", " → ".join(e.cands)])
	var mag := s.type.weapon.mag_size if (s.type != null and s.type.weapon != null) else 0
	lines.append("제압 %.2f / %.1f   체력 %.0f   탄약 %d / %d   연사 퍼짐 +%.1f°" % [s.suppression, BattleBody.SUPPRESS_ON, s.hp, s.ammo, mag, s.bloom_deg])
	if s.ability != null:
		lines.append("능력 [%s] %s" % [s.ability.display_name, Ability.PHASE_NAMES[clampi(s.phase, 0, 2)]])
	if s.seat_eq != null:
		lines.append("좌석: %s %s  — %s" % [s.seat_eq.type.seats[s.seat_idx].role, "(자리에 앉음)" if s.seat_eq.at_seat(s) else "(가는 중)", s.seat_eq.describe()])
	if s.carrying != null:
		lines.append("운반: %s" % s.carrying.type.display_name)
	for m in s.mods:
		lines.append("수정자  " + m.describe())
	if s.cover != null:
		lines.append("엄폐물 #%d (%s)  칸 %d" % [s.cover.id, BattleCover.KIND_NAMES[s.cover.kind], s.slot])
	if s.target != null:
		lines.append("표적 #%d  (x 거리 %.1f m)" % [s.target.id, absf(s.target.x - s.x)])
	return "\n".join(lines)


# ───────────── 퍼펫 풀 ─────────────

func _pool_for(sets_json: String) -> Array:
	if not _pool.has(sets_json):
		_pool[sets_json] = []
	return _pool[sets_json]


## sets.json 에 적힌 퍼펫 씬을 읽어 붙들어 둔다. DRPuppetSet.reload() 가 load(씬)을 부르는데,
## 아무도 붙들고 있지 않으면 병사마다 씬 파일을 디스크에서 다시 읽는다(한 명 7 ms → 붙들면 2.2 ms)
func _hold_scenes(sets_json: String) -> void:
	if _held.has(sets_json):
		return
	var kept: Array = []
	if FileAccess.file_exists(sets_json):
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(sets_json))
		if doc is Dictionary:
			var base := sets_json.get_base_dir()
			for sd in (doc as Dictionary).get("sets", []):
				var path := base.path_join(String((sd as Dictionary).get("scene", "")))
				if ResourceLoader.exists(path):
					var ps := load(path) as PackedScene
					if ps != null:
						kept.append(ps)
	_held[sets_json] = kept


func _make_puppet(sets_json: String) -> DRPuppetSet:
	_hold_scenes(sets_json)
	var p := DRPuppetSet.new()
	p.force_loop = puppet_force_loop
	p.sets_json = sets_json
	_puppet_root.add_child(p)                 # 트리 안이면 여기서 _ready → reload() 로 퍼펫이 만들어진다
	p.visible = false
	# 스스로 도는 것을 끈다 — 애니는 _update_soldier 가 anim_hz 에 맞춰 대신 돌린다.
	# 아직 트리 밖이면 READY 때 엔진이 _process 를 다시 켜므로, 그 뒤에 끈다
	if p.is_node_ready():
		p.set_process(false)
	else:
		p.ready.connect(p.set_process.bind(false), CONNECT_ONE_SHOT)
	return p


func _take_puppet(sets_json: String) -> DRPuppetSet:
	var idle := _pool_for(sets_json)
	if idle.is_empty():
		return _make_puppet(sets_json)
	return idle.pop_back() as DRPuppetSet


func _outfit_for(path: String) -> DROutfit:
	if not _outfits.has(path):
		_outfits[path] = DROutfit.load_json(path)
	return _outfits[path] as DROutfit


## 병사를 화면에 올린다
func _attach(s: BattleSoldier) -> void:
	if s == null or _entries.has(s.id):
		return
	var e := Entry.new()
	e.s = s
	e.acc = randf() / maxf(anim_hz, 1.0)      # 병사마다 갱신 박자를 다르게(한 프레임에 몰리지 않게)
	var t := s.type
	if t != null and t.sets_json != "":
		var p := _take_puppet(t.sets_json)
		e.puppet = p
		e.pool_key = t.sets_json
		e.avail = p.get_animations()
		p.take_off()
		if t.outfit_json != "":
			var o := _outfit_for(t.outfit_json)
			if o != null:
				p.wear(o)
		p.rotation = 0.0
		p.modulate = Color.WHITE
		p.speed_scale = 1.0
		p.visible = show_puppets
	_entries[s.id] = e


## 퍼펫을 처음 상태로 되돌려 풀에 넣는다
func _recycle(e: Entry) -> void:
	var p := e.puppet
	if p != null and is_instance_valid(p):
		p.visible = false
		p.rotation = 0.0
		p.modulate = Color.WHITE
		p.speed_scale = 1.0
		p.z_index = 0
		p.take_off()
		_pool_for(e.pool_key).append(p)
	e.puppet = null
	_entries.erase(e.s.id)


# ───────────── 신호 ─────────────

func _on_spawned(s: BattleSoldier) -> void:
	_attach(s)


func _on_died(s: BattleSoldier) -> void:
	var e := _entries.get(s.id, null) as Entry
	if e == null:
		return
	e.dead_t = 0.0
	e.label = ""
	e.cands = _death_keys(s.stance)
	e.motion = ""
	var p := e.puppet
	if p == null:
		return
	# 죽을 때의 자세에 맞는 사망 동작을 찾는다(기본 동작으로 내려가면 안 되므로 pick 이 아니라 상태마다 pick_state)
	var mt: MotionTable = s.type.motions if s.type != null else null
	var m := ""
	if mt != null:
		for key in e.cands:
			m = mt.pick_state(key, e.avail)
			if m != "":
				break
	if m != "":
		p.speed_scale = 1.0
		p.play(m, 0.1)
		e.motion = m
	elif s.stance == BattleBody.Stance.PRONE:
		pass    # 이미 엎드려 있다 — 그 자세로 멈춘 채 둔다(눕히기나 서서 쓰러지는 동작을 쓰면 벌떡 일어났다 쓰러진다)
	else:
		# 임시 표현: 뒤로 넘어져 누운 모습(90° 눕힘) + 어둡게. 몸 두께의 절반이 땅 밑으로 들어가므로 조금 올린다
		var face := float(s.facing if s.facing != 0 else 1)
		p.position = to_canvas(s.x, 0.2, s.depth)
		p.rotation = deg_to_rad(-90.0) * face
		p.modulate = Color(0.5, 0.5, 0.5, 1.0)


func _on_shot(shot: Dictionary) -> void:
	var a: Vector3 = shot.get("from", Vector3.ZERO)
	var b: Vector3 = shot.get("to", Vector3.ZERO)
	_tracers.append({
		"a": to_canvas(a.x, a.y, a.z),
		"b": to_canvas(b.x, b.y, b.z),
		"t0": _clock,
		"dur": maxf(float(shot.get("flight", 0.0)), TRACER_MIN_SEC),
		"hit": shot.get("hit", null) != null,
		"blocked": bool(shot.get("blocked", false)),
	})


# ───────────── 매 프레임 ─────────────

func _process(delta: float) -> void:
	if _bf == null or not is_instance_valid(_bf):
		return
	_clock += delta
	var step := 1.0 / anim_hz if anim_hz > 0.0 else 0.0
	# 화면에 보이는 범위(카메라 · 확대 반영). 화면 밖 병사는 자리만 옮기고 애니는 멈춘다(부하시험_결과.md "설계에 반영한 것" 2)
	var seen := get_global_transform_with_canvas().affine_inverse() * get_viewport_rect()
	_vis_x0 = seen.position.x - OFFSCREEN_MARGIN_PX
	_vis_x1 = seen.end.x + OFFSCREEN_MARGIN_PX
	var finished: Array = []
	for v in _entries.values():
		var e := v as Entry
		if e.dead_t >= 0.0:
			if _update_corpse(e, delta, step):
				finished.append(e)
		else:
			_update_soldier(e, delta, step)
	for e in finished:
		_recycle(e as Entry)
	_band_timer -= delta
	if _band_timer <= 0.0:
		_band_timer = REORDER_SEC
		_reorder()
	var i := _tracers.size() - 1
	while i >= 0:
		var tr: Dictionary = _tracers[i]
		if _clock > float(tr["t0"]) + float(tr["dur"]) + IMPACT_SEC:
			_tracers.remove_at(i)
		i -= 1
	_bg.queue_redraw()
	_fg.queue_redraw()


func _update_soldier(e: Entry, delta: float, step: float) -> void:
	var s := e.s
	# 몸 상태를 한 수로 — 바뀐 프레임에만 동작 후보 · 글자를 다시 만든다(매 프레임 문자열을 만들지 않게)
	var sig := s.override | (s.move_state << 3) | (s.act_state << 6) | (s.stance << 9)
	if sig != e.sig or s.intent_name != e.last_intent:
		e.last_intent = s.intent_name
		e.label = _label_for(s)
	if sig != e.sig:
		e.sig = sig
		_pick_motion(e)
	var p := e.puppet
	if p == null:
		return
	p.visible = show_puppets
	if not show_puppets:
		return
	var t := s.type
	var sc := t.height_m * ppm / maxf(t.puppet_body_px, 1.0)
	p.position = to_canvas(s.x, 0.0, s.depth)                       # 자리는 매 프레임(값이 거의 안 든다)
	p.scale = Vector2(sc * float(s.facing if s.facing != 0 else 1), sc)   # 퍼펫은 오른쪽을 보게 구워져 있다
	if e.motion != "" and p.position.x > _vis_x0 and p.position.x < _vis_x1:   # 맞는 동작이 없거나 화면 밖이면 진행시키지 않는다
		e.acc += delta
		if e.acc >= step:
			p._process(e.acc)                                       # 애니는 모았다가 anim_hz 에 맞춰 한 번에
			e.acc = 0.0


## 쓰러진 병사. 다 사라졌으면 true
func _update_corpse(e: Entry, delta: float, step: float) -> bool:
	e.dead_t += delta
	var left := corpse_seconds - e.dead_t
	var p := e.puppet
	if p == null:
		return left <= 0.0
	p.visible = show_puppets
	if e.motion != "":
		e.acc += delta
		if e.acc >= step:
			p._process(e.acc)
			e.acc = 0.0
	var c := p.modulate
	c.a = clampf(left / CORPSE_FADE_SEC, 0.0, 1.0)
	p.modulate = c
	return left <= 0.0


## 상태 → 동작 후보 이름(구체적인 것부터). 표에 없는 조합은 덜 구체적인 것으로 내려간다(MotionTable 참고)
func _candidates(s: BattleSoldier) -> PackedStringArray:
	var st: String = BattleBody.STANCE_NAMES[s.stance]
	match s.override:
		BattleBody.Ovr.DEAD:
			return _death_keys(s.stance)
		BattleBody.Ovr.PANIC:
			return PackedStringArray(["패닉", "앉기"])
		BattleBody.Ovr.SUPPRESSED:
			return PackedStringArray(["제압+" + st, "제압", st])
	var base := st
	var moving := true
	match s.move_state:
		BattleBody.Move.RUN:
			base = "달리기"
		BattleBody.Move.WALK:
			base = "앉아걷기" if s.stance == BattleBody.Stance.CROUCH else "걷기"
		BattleBody.Move.CRAWL:
			base = "포복"
		_:
			moving = false
	var fallback: Array = MOVE_FALLBACK.get(base, [])
	if s.override == BattleBody.Ovr.HIT:
		# 서 있을 때만 서서 움찔하는 동작을 쓴다. 앉기 · 엎드림은 그 자세용 피격이 없으면 그 자세 그대로(서기용을 쓰면 0.25초 동안 벌떡 일어선다)
		if s.stance == BattleBody.Stance.STAND:
			return PackedStringArray(["피격", base] + fallback)
		return PackedStringArray(["피격+" + st, st])
	if s.act_state == BattleBody.Act.NONE:
		return PackedStringArray([base] + fallback)
	var act: String = BattleBody.ACT_NAMES[s.act_state]
	var out := PackedStringArray([base + "+" + act])
	if moving:
		out.append(st + "+" + act)
	out.append(base)
	out.append_array(fallback)
	return out


## 죽을 때의 자세별 사망 동작 이름. 엎드림은 서기용 "사망"으로 내려가지 않는다(벌떡 일어났다 쓰러지므로)
func _death_keys(stance: int) -> PackedStringArray:
	match stance:
		BattleBody.Stance.CROUCH:
			return PackedStringArray(["사망+앉기", "사망"])
		BattleBody.Stance.PRONE:
			return PackedStringArray(["사망+엎드림"])
	return PackedStringArray(["사망"])


func _pick_motion(e: Entry) -> void:
	var s := e.s
	e.cands = _candidates(s)
	var p := e.puppet
	var mt: MotionTable = s.type.motions if s.type != null else null
	if p == null or mt == null:
		e.motion = ""
		return
	if e.avail.is_empty():
		e.avail = p.get_animations()
	var m := ""
	var st := mt.state_of(e.cands, e.avail)
	if st != "" and e.motion != "" and mt.has_motion(st, e.motion) and String(p.current_animation()) == e.motion:
		m = e.motion                          # 고른 표 상태의 동작을 이미 틀고 있다 — 이어 간다(같은 상태에서 다시 뽑아 바뀌지 않게)
	else:
		m = mt.pick(e.cands, e.avail)         # 상태에 동작이 여럿이면 비중(%)대로 하나
	if m != "" and (m != e.motion or String(p.current_animation()) != m):
		p.play(m, 0.1)
	e.motion = m
	# 걷기에 달리기 동작을 빌려 쓰는 동안은 걷는 속도만큼 느리게 돌린다(걷기 동작을 따로 구웠으면 그대로)
	var spd := 1.0
	if s.move_state == BattleBody.Move.WALK and m != "" and not mt.has_motion("걷기", m) and mt.has_motion("달리기", m):
		spd = s.type.walk_speed / maxf(s.type.run_speed, 0.01)
		if s.stance == BattleBody.Stance.CROUCH:
			spd *= s.type.crouch_move_mult
	p.speed_scale = clampf(spd, 0.1, 1.0)


func _label_for(s: BattleSoldier) -> String:
	var st := ""
	if s.override != BattleBody.Ovr.NONE:
		st = BattleBody.OVR_NAMES[s.override]
	elif s.act_state != BattleBody.Act.NONE:
		st = BattleBody.ACT_NAMES[s.act_state]
	var head := "★" if s.controller == 1 else s.intent_name
	if head == "":
		return st
	return head if st == "" else "%s · %s" % [head, st]


# ───────────── 겹침 순서 (부하시험_결과.md §4) ─────────────

## 구운 퍼펫의 조각 z 범위를 잰다(외곽선 밑깔개 −1 ~ 조각 150 쯤). 병사 한 명의 z 폭 = 최대 − 최소 + 2(장비가 맨 위에 얹힐 자리)
func _measure_z(p: DRPuppetSet) -> void:
	var lo := 0
	var hi := 0
	var stack: Array[Node] = [p]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		for c in nd.get_children():
			if c is Sprite2D:
				lo = mini(lo, (c as Sprite2D).z_index)
				hi = maxi(hi, (c as Sprite2D).z_index)
			stack.append(c)
	if hi > lo:
		_z_lo = mini(_z_lo, lo)
		_z_hi = maxi(_z_hi, hi)
		_z_span = _z_hi - _z_lo + 2


func _band_z(band: int) -> int:
	var base := RenderingServer.CANVAS_ITEM_Z_MIN - _z_lo
	return clampi(base + band * _z_span, base, RenderingServer.CANVAS_ITEM_Z_MAX - _z_hi - 1)


## 겹치는 병사끼리만 다른 z 띠: 깊이 순(뒤 → 앞)으로 훑으며 "x 가 OVERLAP_M 안인 더 뒤 병사의 띠 + 1".
## 필요한 띠 수 = 가장 길게 겹쳐 이어진 줄의 길이(병사 수가 아니다). 쓰러진 병사는 맨 아래 띠 0 에 모은다
func _reorder() -> void:
	var live: Array = []
	for v in _entries.values():
		var e := v as Entry
		if e.puppet == null:
			continue
		if _z_span == 0:
			_measure_z(e.puppet)
			if _z_span == 0:
				return                      # 퍼펫이 아직 안 만들어졌다
		if e.dead_t >= 0.0:
			e.puppet.z_index = _band_z(0)
		else:
			live.append(e)
	live.sort_custom(func(a: Entry, b: Entry) -> bool: return a.s.depth < b.s.depth)
	var cells: Dictionary = {}              # x 구역(OVERLAP_M 폭) -> Array[Vector2(x, 띠)] — 이웃 구역만 보면 된다
	var top := 0
	for v in live:
		var e := v as Entry
		var x := e.s.x
		var k := int(floor(x / OVERLAP_M))
		var band := 1
		for kk in range(k - 1, k + 2):
			if cells.has(kk):
				for it in (cells[kk] as Array):
					var q: Vector2 = it
					if absf(q.x - x) < OVERLAP_M:
						band = maxi(band, int(q.y) + 1)
		if cells.has(k):
			(cells[k] as Array).append(Vector2(x, band))
		else:
			cells[k] = [Vector2(x, band)]
		e.puppet.z_index = _band_z(band)
		top = maxi(top, band)
	_bands_used = top + 1


# ───────────── 그리기: 퍼펫 뒤(땅 · 엄폐물) ─────────────

func _draw_ground() -> void:
	if _bf == null or not is_instance_valid(_bf):
		return
	var font := ThemeDB.fallback_font
	var w := _bf.length_m * ppm
	var y0 := ground_at(0.0)
	var y1 := ground_at(1.0)
	_bg.draw_rect(Rect2(0.0, y0, w, y1 - y0), Color(0.31, 0.37, 0.3))
	_bg.draw_line(Vector2(0.0, y0), Vector2(w, y0), Color(0.22, 0.27, 0.22), 1.0)
	_bg.draw_line(Vector2(0.0, y1), Vector2(w, y1), Color(0.22, 0.27, 0.22), 1.0)
	# 맵 양 끝(그 편이 나오는 곳)
	for team in 2:
		var ex := _bf.home_x(team) * ppm
		var fwd := float(_bf.forward(team))
		_bg.draw_line(Vector2(ex, y0 - 2.0 * ppm), Vector2(ex, y1), TEAM_LINE[team], 2.0)
		_bg.draw_rect(Rect2(minf(ex, ex + 16.0 * fwd), y0 - 2.0 * ppm, 16.0, 10.0), TEAM_LINE[team])
	for c in _bf.covers:
		var cx0 := c.x0 * ppm
		var cx1 := c.x1 * ppm
		_bg.draw_rect(Rect2(cx0, y0, cx1 - cx0, y1 - y0), Color(0.25, 0.3, 0.23))          # 병사가 서는 구간
		var hpx := c.wall_height() * ppm
		for wx in c.wall_xs():
			# 벽은 깊이 전체를 덮는다 — 옆에서 보면 깊이 0 ~ 1 에 걸친 세로 막대, 높이만큼 위로 솟는다
			var px := wx * ppm
			_bg.draw_rect(Rect2(px - 2.5, y0 - hpx, 5.0, (y1 - y0) + hpx), Color(0.45, 0.38, 0.26))
			_bg.draw_rect(Rect2(px - 2.5, y0 - hpx, 5.0, 3.0), Color(0.66, 0.57, 0.4))
			_bg.draw_line(Vector2(px - 6.0, y1 - hpx), Vector2(px + 6.0, y1 - hpx), Color(0.66, 0.57, 0.4), 1.0)
		for i in c.slot_x.size():
			var owner_s := c.slot_owner[i]
			var col := Color(1.0, 1.0, 1.0, 0.22)
			if owner_s != null:
				col = TEAM_LINE[clampi(owner_s.team, 0, 1)]
			_bg.draw_circle(to_canvas(c.slot_x[i], 0.0, c.slot_depth[i]), 3.0, col)
		if font != null:
			_bg.draw_string(font, Vector2(cx0, y0 - hpx - 6.0), "%s #%d  칸 %d/%d" % [BattleCover.KIND_NAMES[c.kind], c.id,
				c.slot_owner.size() - c.free_count(), c.slot_owner.size()], HORIZONTAL_ALIGNMENT_LEFT, -1.0, 11, Color(1.0, 1.0, 1.0, 0.55))
	if not _bf.equipments.is_empty():
		EquipMarks.draw_ground(self, _bg, _bf)                  # 운용 장비 · 좌석 자리(§2-13 — 모델 없이 자리 표시만)


# ───────────── 그리기: 퍼펫 위(상자 · 글자 · 총알 자국) ─────────────

func _draw_overlay() -> void:
	if _bf == null or not is_instance_valid(_bf):
		return
	var font := ThemeDB.fallback_font
	if show_boxes or show_labels:
		for v in _entries.values():
			var e := v as Entry
			if e.dead_t >= 0.0:
				continue
			var s := e.s
			var box := s.type.box(s.stance)
			var wpx := box.x * ppm
			var hpx := box.y * ppm
			var gy := ground_at(s.depth)
			var cx := s.x * ppm
			if show_boxes:
				var r := Rect2(cx - wpx * 0.5, gy - hpx, wpx, hpx)
				var team := clampi(s.team, 0, 1)
				var fill: Color = TEAM_FILL[team]
				var line: Color = TEAM_LINE[team]
				var width := 1.0
				if s.override == BattleBody.Ovr.PANIC:
					fill = Color(0.6, 0.6, 0.6, 0.25)
					line = Color(0.75, 0.75, 0.75, 0.9)
				elif s.override == BattleBody.Ovr.SUPPRESSED:
					line = Color(1.0, 0.9, 0.2, 1.0)
					width = 2.0
				if s.controller == 1:
					line = Color.WHITE
					width = 2.0
				_fg.draw_rect(r, fill)
				_fg.draw_rect(r, line, false, width)
			if show_labels:
				var top := gy - hpx
				# 제압 막대(0 ~ SUPPRESS_MAX, SUPPRESS_ON 에 눈금) · 그 아래 탄약
				var bw := 30.0
				var bx := cx - bw * 0.5
				_fg.draw_rect(Rect2(bx, top - 7.0, bw, 3.0), Color(0.0, 0.0, 0.0, 0.55))
				var f := clampf(s.suppression / BattleBody.SUPPRESS_MAX, 0.0, 1.0)
				if f > 0.0:
					_fg.draw_rect(Rect2(bx, top - 7.0, bw * f, 3.0), Color(1.0, 0.85, 0.2) if s.suppression < BattleBody.SUPPRESS_ON else Color(1.0, 0.4, 0.15))
				var tick := bx + bw * BattleBody.SUPPRESS_ON / BattleBody.SUPPRESS_MAX
				_fg.draw_line(Vector2(tick, top - 8.0), Vector2(tick, top - 3.0), Color(1.0, 1.0, 1.0, 0.8), 1.0)
				var mag := s.type.weapon.mag_size if s.type.weapon != null else 0
				if mag > 0:
					_fg.draw_rect(Rect2(bx, top - 3.0, bw, 2.0), Color(0.0, 0.0, 0.0, 0.55))
					_fg.draw_rect(Rect2(bx, top - 3.0, bw * clampf(float(s.ammo) / float(mag), 0.0, 1.0), 2.0), Color(0.85, 0.9, 1.0, 0.9))
				if e.label != "" and font != null:
					var pos := Vector2(cx - LABEL_W * 0.5, top - 11.0)
					_fg.draw_string_outline(font, pos, e.label, HORIZONTAL_ALIGNMENT_CENTER, LABEL_W, 11, 3, Color(0.0, 0.0, 0.0, 0.85))
					_fg.draw_string(font, pos, e.label, HORIZONTAL_ALIGNMENT_CENTER, LABEL_W, 11, Color.WHITE)
	if not _bf.equipments.is_empty():
		EquipMarks.draw_overlay(self, _fg, _bf, font if show_labels else null)
	# 총알 자국 — from → to 로 날아가는 짧은 선, 도착 뒤 잠깐 점(맞음 = 붉은색 · 엄폐/땅에 막힘 = 흙색 · 빗나감 = 없음)
	for tr in _tracers:
		var d: Dictionary = tr
		var a: Vector2 = d["a"]
		var b: Vector2 = d["b"]
		var prog := (_clock - float(d["t0"])) / float(d["dur"])
		if prog < 1.0:
			_fg.draw_line(a.lerp(b, maxf(prog - TRACER_TAIL, 0.0)), a.lerp(b, clampf(prog, 0.0, 1.0)), Color(1.0, 0.95, 0.6, 0.9), 1.5)
		elif bool(d["hit"]):
			_fg.draw_circle(b, 3.0, Color(1.0, 0.25, 0.2, 0.95))
		elif bool(d["blocked"]):
			_fg.draw_circle(b, 2.5, Color(0.62, 0.5, 0.34, 0.95))
