extends Node2D

## DRDotView3D 시험장 — 사람 몸(human_base, 내복 군인) 여러 명을 3D 도트 창에 세우고 2D 땅 · 십자와 맞는지 본다.  (10-15)
## 이 씬을 열고 F6.
##
## 조작: A·D / ← → 좌우 이동 · W·S / ↑ ↓ 위아래 · 휠 또는 + − 확대 · 1 ~ 4 도트 크기(dot_px)
##       O 외곽선(끔 → 카툰 → 픽셀 퍼펙트) · I 겹친 캐릭터 사이 선 · [ ] 내려다보는 각 ∓5° · L 명암 바꾸기
##       P 동작 멈춤 · M 정렬 십자 · F 땅 · G 도트 스냅(끄면 떨림 비교) · R 처음 자리
## 명령줄(검사): -- --shot=<폴더> [--compare=<png>]  정해진 시나리오를 찍고 스스로 닫힌다.
##   확대 0.5 / 1 / 1.37 / 2 · 카메라 이동 중 · 창 크기 변경 · dot_px 1 / 2 / 3 · 외곽선 끔 / 카툰 / 픽셀 퍼펙트 ·
##   선 검사(3D 창 텍스처 lines/) · 떨림 연속 장면(jitter/) · 비교 그림.
##   정렬 = 3D 표지 상자(자홍)의 화면 무게중심 ↔ world_to_canvas 로 계산한 자리. 실제 화면 픽셀로 재서 report.txt 에 적는다.
##   창은 주 모니터를 가리지 않게 --screen 0 으로 띄운다(--position 은 Godot 이 모니터 좌표를 옮겨 써서 음수가 주 모니터로 간다).
##
## 전장 좌표는 game/view/battle_view.gd 와 같다: to_canvas(x, h, 깊이) = (x·ppm, ground_y + (깊이 − 0.5)·depth_px − h·ppm).
## 병사 자리 = dots.ground_to_world(to_canvas(x, 0, 깊이)) — 메인이 battle_view 에 붙일 때 쓰는 그대로.

const MODEL_PATH := "res://source3d/characters/human_base/human_base.glb"
const PPM := 40.0
const GROUND_Y := 430.0
const DEPTH_PX := 150.0
const FIELD_M := 30.0
## 옆(±X)을 보되 카메라 쪽으로 돌리는 각 — 3/4 가 보이게
const TURN_DEG := 35.0
## 정렬 표지 상자 한 변(m)과 높이들
const MARK_M := 0.2
const MARK_HEIGHTS := [0.0, 1.75]
## 병사: x(m), 깊이(0 ~ 1), 보는 쪽(+1 오른쪽 · −1 왼쪽), 동작. 일부러 겹치게 세운다
const SOLDIERS := [
	[9.0, 0.30, 1, "Idle"],
	[9.7, 0.52, -1, "Sprint"],
	[10.5, 0.72, 1, "Crouch_Idle"],
	[11.7, 0.40, -1, "Walk"],
	[12.2, 0.82, 1, "Idle"],
	[13.3, 0.22, -1, "Crouch_Idle"],
	[14.1, 0.60, 1, "Walk"],
]
## 정렬 표지: x(m), 깊이 — 높이 0 과 1.75 m 에 하나씩(병사와 안 겹치고, 확대 0.5 에서도 표지끼리 30 px 넘게 떨어진 자리)
const MARKS := [[6.6, 0.12], [8.0, 0.92], [15.3, 0.32], [16.9, 0.95]]
const HOME_X := 11.6
const LIGHTS := [
	{"name": "기본 (왼쪽 위 앞 · 3단)", "dir": Vector3(-0.4, 0.7, 0.6), "bands": 3, "ambient": 0.45, "wrap": 0.25},
	{"name": "2단", "dir": Vector3(-0.4, 0.7, 0.6), "bands": 2, "ambient": 0.45, "wrap": 0.25},
	{"name": "4단 · 그늘 짙게", "dir": Vector3(-0.4, 0.7, 0.6), "bands": 4, "ambient": 0.35, "wrap": 0.25},
	{"name": "오른쪽 위 빛", "dir": Vector3(0.45, 0.75, 0.5), "bands": 3, "ambient": 0.45, "wrap": 0.25},
	{"name": "정면 빛 · 밝게", "dir": Vector3(-0.2, 0.45, 0.87), "bands": 3, "ambient": 0.55, "wrap": 0.35},
]
const OUTLINE_NAMES := ["끔", "카툰", "픽셀 퍼펙트"]

@onready var cam: Camera2D = $Camera2D
@onready var dots: DRDotView3D = $DotView
@onready var ground: Node2D = $Ground
@onready var marks: Node2D = $Marks

var _bodies: Array[Node3D] = []
var _players: Array[AnimationPlayer] = []
var _mark_nodes: Array[MeshInstance3D] = []
var _mark_specs: Array = []                 # [x, h, 깊이]
var _zoom := 1.0
var _cam_pos := Vector2.ZERO
var _paused := false
var _light_i := 0
var _hud: Label
var _cell_label: Label
var _shot_dir := ""
var _compare_path := ""
var _log := PackedStringArray()


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.42, 0.47, 0.42))
	ground.draw.connect(_draw_ground)
	marks.draw.connect(_draw_marks)
	var ui := CanvasLayer.new()
	add_child(ui)
	_hud = Label.new()
	_hud.position = Vector2(10, 6)
	_hud.add_theme_font_size_override("font_size", 13)
	_hud.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud.add_theme_constant_override("outline_size", 4)
	ui.add_child(_hud)
	_cell_label = Label.new()
	_cell_label.add_theme_font_size_override("font_size", 15)
	_cell_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_cell_label.add_theme_constant_override("outline_size", 5)
	_cell_label.visible = false
	ui.add_child(_cell_label)
	_spawn_soldiers()
	_spawn_marks()
	_place_all()
	_cam_pos = _home()
	_apply_cam()
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		if s.begins_with("shot="):
			_shot_dir = s.substr(5)
		elif s.begins_with("compare="):
			_compare_path = s.substr(8)
	if _shot_dir != "":
		DirAccess.make_dir_recursive_absolute(_shot_dir)
		if _compare_path == "":
			_compare_path = _shot_dir.path_join("dotview_compare.png")
		_run_shots()


# ───────────── 전장 좌표(battle_view 와 같다) ─────────────

func ground_at(depth: float) -> float:
	return GROUND_Y + (depth - 0.5) * DEPTH_PX


func to_canvas(x: float, h: float, depth: float) -> Vector2:
	return Vector2(x * PPM, ground_at(depth) - h * PPM)


# ───────────── 장면 만들기 ─────────────

func _spawn_soldiers() -> void:
	var ps := load(MODEL_PATH) as PackedScene
	for i in SOLDIERS.size():
		var sd: Array = SOLDIERS[i]
		var body := ps.instantiate() as Node3D
		body.name = "Soldier%d" % i
		dots.world.add_child(body)
		dots.apply_dot_material(body)
		var ap := body.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		ap.play(String(sd[3]))
		ap.seek(fmod(0.37 * float(i), ap.current_animation_length), true)
		_bodies.append(body)
		_players.append(ap)


func _spawn_marks() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.0, 1.0)
	var box := BoxMesh.new()
	box.size = Vector3.ONE * MARK_M
	for m in MARKS:
		for h in MARK_HEIGHTS:
			var mi := MeshInstance3D.new()
			mi.mesh = box
			mi.material_override = mat
			dots.world.add_child(mi)
			_mark_nodes.append(mi)
			_mark_specs.append([float(m[0]), float(h), float(m[1])])


## 3D 자리를 전장 좌표에서 다시 계산한다(내려다보는 각이 바뀌면 같은 캔버스 자리라도 3D 자리가 바뀐다)
func _place_all() -> void:
	for i in _bodies.size():
		var sd: Array = SOLDIERS[i]
		_bodies[i].position = dots.ground_to_world(to_canvas(sd[0], 0.0, sd[1]))
		_bodies[i].rotation.y = deg_to_rad(90.0 - TURN_DEG) * float(sd[2])
	for j in _mark_nodes.size():
		var ms: Array = _mark_specs[j]
		_mark_nodes[j].position = dots.ground_to_world(to_canvas(ms[0], ms[1], ms[2]), ms[1])
	marks.queue_redraw()
	ground.queue_redraw()


func _home() -> Vector2:
	return Vector2(HOME_X * PPM, GROUND_Y - 40.0)


func _apply_cam() -> void:
	cam.zoom = Vector2(_zoom, _zoom)
	cam.position = _cam_pos
	marks.queue_redraw()


func _set_light(i: int) -> void:
	_light_i = posmod(i, LIGHTS.size())
	var l: Dictionary = LIGHTS[_light_i]
	dots.light_dir = l["dir"]
	dots.light_bands = l["bands"]
	dots.light_ambient = l["ambient"]
	dots.light_wrap = l["wrap"]


func _set_outline(mode: int) -> void:
	dots.outline_px = 0 if mode == 0 else 1
	dots.outline_style = 1 if mode == 2 else 0


func _outline_mode() -> int:
	if dots.outline_px == 0:
		return 0
	return 2 if dots.outline_style == 1 else 1


func _pause(on: bool) -> void:
	_paused = on
	for ap in _players:
		if on:
			ap.pause()
		else:
			ap.play()


# ───────────── 그리기(2D) ─────────────

func _draw_ground() -> void:
	var w := FIELD_M * PPM
	var y0 := ground_at(0.0)
	var y1 := ground_at(1.0)
	ground.draw_rect(Rect2(0.0, y0, w, y1 - y0), Color(0.31, 0.37, 0.3))
	for k in [0.25, 0.5, 0.75]:
		ground.draw_line(Vector2(0.0, ground_at(k)), Vector2(w, ground_at(k)), Color(1.0, 1.0, 1.0, 0.07), 1.0)
	ground.draw_line(Vector2(0.0, y0), Vector2(w, y0), Color(0.22, 0.27, 0.22), 1.0)
	ground.draw_line(Vector2(0.0, y1), Vector2(w, y1), Color(0.22, 0.27, 0.22), 1.0)
	for xm in int(FIELD_M) + 1:
		ground.draw_line(Vector2(xm * PPM, y1), Vector2(xm * PPM, y1 + 6.0), Color(0.22, 0.27, 0.22), 1.0)
	# 병사 발밑 그림자(2D) — 3D 발이 2D 땅 자리에 서는지 눈으로 본다
	for sd in SOLDIERS:
		ground.draw_set_transform(to_canvas(sd[0], 0.0, sd[1]), 0.0, Vector2(1.0, 0.3))
		ground.draw_circle(Vector2.ZERO, 16.0, Color(0.0, 0.0, 0.0, 0.3))
	ground.draw_set_transform(Vector2.ZERO)


## 정렬 십자(2D, 3D 위) — 표지 상자 자리를 world_to_canvas 로 계산해 그린다. 병사 발 자리는 노란 점
func _draw_marks() -> void:
	var r := 7.0 / _zoom
	for mi in _mark_nodes:
		var c := dots.world_to_canvas(mi.position)
		marks.draw_line(c - Vector2(r, 0.0), c + Vector2(r, 0.0), Color(0.2, 1.0, 1.0), -1.0)
		marks.draw_line(c - Vector2(0.0, r), c + Vector2(0.0, r), Color(0.2, 1.0, 1.0), -1.0)
	for sd in SOLDIERS:
		var f := to_canvas(sd[0], 0.0, sd[1])
		marks.draw_line(f - Vector2(r * 0.6, 0.0), f + Vector2(r * 0.6, 0.0), Color(1.0, 0.9, 0.2), -1.0)


# ───────────── 직접 볼 때 ─────────────

func _process(delta: float) -> void:
	if _shot_dir == "":
		var mx := int(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) \
				- int(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		var my := int(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) \
				- int(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
		if mx != 0 or my != 0:
			_cam_pos += Vector2(mx, my) * 240.0 * delta / _zoom
			_apply_cam()
	_hud.text = "확대 %.2f   dot_px %d (도트 = 캔버스 %.2f)   외곽선 %s%s   pitch %.0f°   명암 %s%s%s\n뷰포트 %s   %.0f fps\nA·D·W·S 이동  휠/+− 확대  1~4 dot_px  O 외곽선  I 사이 선  [ ] 각도  L 명암  P 멈춤  M 십자  F 땅  G 스냅  R 처음" % [
		_zoom, dots.dot_px, dots.get_dot_size(), OUTLINE_NAMES[_outline_mode()], " + 사이 선" if dots.inner_outline and dots.outline_px > 0 else "",
		dots.pitch_deg, LIGHTS[_light_i]["name"], "   [멈춤]" if _paused else "", "   [스냅 끔]" if not dots.snap_to_dots else "",
		str(dots.get_subviewport().size), Engine.get_frames_per_second()]


func _unhandled_input(ev: InputEvent) -> void:
	if _shot_dir != "":
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = minf(_zoom * 1.1, 6.0)
			_apply_cam()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = maxf(_zoom / 1.1, 0.25)
			_apply_cam()
		return
	if not (ev is InputEventKey) or not (ev as InputEventKey).pressed or (ev as InputEventKey).echo:
		return
	match (ev as InputEventKey).physical_keycode:
		KEY_EQUAL, KEY_KP_ADD:
			_zoom = minf(_zoom * 1.1, 6.0)
			_apply_cam()
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom = maxf(_zoom / 1.1, 0.25)
			_apply_cam()
		KEY_1:
			dots.dot_px = 1
		KEY_2:
			dots.dot_px = 2
		KEY_3:
			dots.dot_px = 3
		KEY_4:
			dots.dot_px = 4
		KEY_O:
			_set_outline((_outline_mode() + 1) % 3)
		KEY_I:
			dots.inner_outline = not dots.inner_outline
		KEY_BRACKETLEFT:
			dots.pitch_deg -= 5.0
			_place_all()
		KEY_BRACKETRIGHT:
			dots.pitch_deg += 5.0
			_place_all()
		KEY_L:
			_set_light(_light_i + 1)
		KEY_P:
			_pause(not _paused)
		KEY_M:
			marks.visible = not marks.visible
		KEY_F:
			ground.visible = not ground.visible
		KEY_G:
			dots.snap_to_dots = not dots.snap_to_dots
		KEY_R:
			_zoom = 1.0
			_cam_pos = _home()
			_apply_cam()


# ───────────── 검사 시나리오(--shot) ─────────────

func _run_shots() -> void:
	await _wait(45)                         # 셰이더 컴파일 · 첫 프레임들
	var first := await _grab()
	_say("화면 그림 %s · 창 %s · 모니터 %d · 2D 기준 %s · 스트레치 배율 %.3f" % [str(first.get_size()), str(get_window().size),
		DisplayServer.window_get_current_screen(), str(get_viewport_rect().size), get_viewport().get_final_transform().x.length()])

	# 1) 확대율별 정렬 + 그림(1.37 = 정수가 아닌 배율)
	for z in [0.5, 1.0, 1.37, 2.0]:
		_zoom = z
		_cam_pos = _home()
		_apply_cam()
		await _wait(2)
		await _measure("확대 %.2f" % z)
		await _save("zoom_%03d.png" % int(round(z * 100.0)))

	# 2) 카메라가 움직이는 동안(매 프레임 정수가 아닌 걸음) 정렬 — 확대 1 과 1.37
	for z in [1.0, 1.37]:
		_zoom = z
		var worst := 0.0
		for i in 30:
			_cam_pos = _home() + Vector2(7.31 * float(i), 6.0 * sin(float(i) * 0.7))
			_apply_cam()
			worst = maxf(worst, await _measure("이동 %d" % i, false))
		_say("ALIGN 이동 중 30 프레임(확대 %.2f) 최대 %.2f px = %.2f 도트" % [z, worst, worst / float(dots.dot_px)])
	_zoom = 1.0
	_cam_pos = _home() + Vector2(7.31 * 13.0, 0.0)
	_apply_cam()
	await _save("pan_mid.png")

	# 창 크기를 바꿔도 따라가는지(스트레치 배율이 1 보다 작아진다)
	var keep := get_window().size
	get_window().size = Vector2i(1100, 640)
	_cam_pos = _home()
	_apply_cam()
	await _wait(6)
	await _measure("창 1100x640")
	await _save("resize_1100x640.png")
	get_window().size = keep
	await _wait(6)

	# 3) dot_px 1 / 2 / 3(확대 2)
	_zoom = 2.0
	_cam_pos = _home() + Vector2(-50.0, 0.0)
	_apply_cam()
	for dp in [1, 2, 3]:
		dots.dot_px = dp
		await _wait(2)
		await _measure("dot_px %d" % dp)
		await _save("dotpx_%d.png" % dp)
	dots.dot_px = 2

	# 4) 외곽선 끔 / 카툰 / 픽셀 퍼펙트 / 픽셀 퍼펙트(사이 선 끔)
	for mode in 3:
		_set_outline(mode)
		await _wait(2)
		await _save("outline_%d_%s.png" % [mode, ["off", "cartoon", "pixel"][mode]])
	dots.inner_outline = false
	await _wait(2)
	await _save("outline_3_pixel_noinner.png")
	dots.inner_outline = true
	marks.visible = false
	ground.visible = false
	await _wait(2)
	await _save("outline_bg_check.png")          # 땅 없이 — 배경이 투명하게 남는지(바깥은 기본 배경색이어야)
	marks.visible = true
	ground.visible = true
	await _line_check()

	# 5) 떨림: 동작을 멈추고 카메라를 도트보다 작게 옮기며 연속으로 — 판정은 _probe 의 파이썬이 한다
	await _jitter()

	# 6) 비교 그림
	await _compare()

	var f := FileAccess.open(_shot_dir.path_join("report.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_log) + "\n")
		f.close()
	print("DOTVIEW SHOTS DONE")
	get_tree().quit()


## 선 검사: 동작을 멈추고 3D 창 텍스처(저해상도 · 알파 포함)를 선 끔 / 바깥 선만 / 바깥 + 사이 선 세 장으로 저장 — 판정은 _probe 의 파이썬
func _line_check() -> void:
	var ldir := _shot_dir.path_join("lines")
	DirAccess.make_dir_recursive_absolute(ldir)
	_pause(true)
	_zoom = 2.0
	_cam_pos = Vector2(10.9 * PPM, GROUND_Y - 30.0)
	_apply_cam()
	for st in [["a_off", 0, false], ["b_outer", 2, false], ["c_inner", 2, true], ["d_cartoon_inner", 1, true]]:
		_set_outline(int(st[1]))
		dots.inner_outline = bool(st[2])
		await _wait(2)
		var shot := await _grab()
		dots.get_subviewport().get_texture().get_image().save_png(ldir.path_join("%s.png" % st[0]))
		shot.save_png(ldir.path_join("%s_screen.png" % st[0]))
	_set_outline(2)
	dots.inner_outline = true
	_pause(false)


func _jitter() -> void:
	var jdir := _shot_dir.path_join("jitter")
	DirAccess.make_dir_recursive_absolute(jdir)
	_pause(true)
	marks.visible = false
	ground.visible = false
	_hud.visible = false
	var size := (await _grab()).get_size()
	var crop := Rect2i(size / 2 - Vector2i(340, 190), Vector2i(680, 380))
	for run in [["snap_z100", 1.0, true], ["nosnap_z100", 1.0, false], ["snap_z137", 1.37, true]]:
		_zoom = float(run[1])
		dots.snap_to_dots = bool(run[2])
		for i in 24:
			_cam_pos = _home() + Vector2(0.37 * float(i), 0.23 * float(i))   # 한 걸음 = 0.4 화면 px 쯤(도트 2 px 보다 작게)
			_apply_cam()
			var img := await _grab()
			img.get_region(crop).save_png(jdir.path_join("%s_%02d.png" % [run[0], i]))
	dots.snap_to_dots = true
	_pause(false)
	marks.visible = true
	ground.visible = true
	_hud.visible = true


## 비교 그림: 같은 장면(동작 멈춤)을 설정만 바꿔 같은 화면 영역을 잘라 4 열로 붙인다(줄마다 바꾸는 것 하나)
func _compare() -> void:
	_hud.visible = false
	marks.visible = false
	_pause(true)
	for k in _players.size():
		_players[k].seek(0.45 + 0.2 * float(k), true)
	_zoom = 2.0
	_cam_pos = Vector2(10.9 * PPM, GROUND_Y - 30.0)
	_apply_cam()
	var rows := [
		[{"t": "pitch 8°", "pitch": 8.0}, {"t": "pitch 15° (기본)", "pitch": 15.0}, {"t": "pitch 25°", "pitch": 25.0}, {"t": "pitch 35°", "pitch": 35.0}],
		[{"t": "dot_px 1 (도트화 끔)", "dot": 1}, {"t": "dot_px 2 (기본)", "dot": 2}, {"t": "dot_px 3", "dot": 3}, {"t": "dot_px 4", "dot": 4}],
		[{"t": "외곽선 끔", "ol": 0}, {"t": "카툰", "ol": 1}, {"t": "픽셀 퍼펙트 (기본)", "ol": 2}, {"t": "픽셀 퍼펙트 · 사이 선 끔", "ol": 2, "inner": false}],
		[{"t": "명암 2단", "light": 1}, {"t": "명암 기본 (3단)", "light": 0}, {"t": "4단 · 그늘 짙게", "light": 2}, {"t": "오른쪽 위 빛", "light": 3}],
		[{"t": "정면 빛 · 밝게", "light": 4}, {"t": "카툰 · 2단", "ol": 1, "light": 1}, {"t": "pitch 25° · dot 3", "pitch": 25.0, "dot": 3}, {"t": "pitch 10° · 톤 0.6", "pitch": 10.0, "tone": 0.6}],
	]
	var stretch := get_viewport().get_final_transform()
	var cell := Vector2i(440, 330)
	var screen := (await _grab()).get_size()        # get_texture().get_size() 는 이 PC 에서 실제 그림(1280x720)과 다른 값(1423x801)을 돌려줘서 그림 크기로
	var crop := Rect2i((screen - cell) / 2 + Vector2i(0, -10), cell)
	var out := Image.create(cell.x * 4, cell.y * rows.size(), false, Image.FORMAT_RGBA8)
	_cell_label.visible = true
	_cell_label.position = stretch.affine_inverse() * Vector2(crop.position) + Vector2(6.0, 2.0)
	for r in rows.size():
		for c in 4:
			var v: Dictionary = rows[r][c]
			dots.pitch_deg = float(v.get("pitch", 15.0))
			dots.dot_px = int(v.get("dot", 2))
			_set_outline(int(v.get("ol", 2)))
			dots.inner_outline = bool(v.get("inner", true))
			dots.outline_tone = float(v.get("tone", 0.45))
			_set_light(int(v.get("light", 0)))
			_place_all()
			_cell_label.text = String(v["t"])
			await _wait(2)
			var img := await _grab()
			img.convert(Image.FORMAT_RGBA8)
			out.blit_rect(img, crop, Vector2i(c * cell.x, r * cell.y))
	# 칸 경계선
	for r in rows.size():
		out.fill_rect(Rect2i(0, r * cell.y, out.get_width(), 1), Color(0.1, 0.1, 0.1))
	for c in 4:
		out.fill_rect(Rect2i(c * cell.x, 0, 1, out.get_height()), Color(0.1, 0.1, 0.1))
	out.save_png(_compare_path)
	_say("비교 그림: %s" % _compare_path)
	_cell_label.visible = false
	dots.pitch_deg = 15.0
	dots.dot_px = 2
	_set_outline(2)
	dots.inner_outline = true
	dots.outline_tone = 0.45
	_set_light(0)
	_place_all()
	_pause(false)
	marks.visible = true
	_hud.visible = true


## 정렬 재기: 십자를 숨긴 한 장에서 표지 상자(자홍)의 무게중심을 찾아 world_to_canvas 자리와 비교한다(실제 화면 픽셀).
## 상자가 가운데 대칭이라 직교 투영의 무게중심 = 중심점의 투영이다
func _measure(tag: String, loud: bool = true) -> float:
	var was := marks.visible
	marks.visible = false
	var img := await _grab()
	marks.visible = was
	var fx := get_viewport().get_final_transform() * dots.get_global_transform_with_canvas()
	var reach := int(ceil(MARK_M * 1.6 * dots.px_per_m * fx.x.length())) + dots.dot_px * 3 + 4
	var worst := 0.0
	var found := 0
	var parts := PackedStringArray()
	for mi in _mark_nodes:
		var e: Vector2 = fx * dots.world_to_canvas(mi.position)
		if e.x < reach or e.y < reach or e.x > img.get_width() - reach or e.y > img.get_height() - reach:
			continue                    # 화면 가장자리에 걸린 표지는 무게중심이 치우친다
		var cen: Variant = _centroid(img, e, reach)
		if cen == null:
			parts.append("(없음)")
			continue
		var err: Vector2 = (cen as Vector2) - e
		worst = maxf(worst, err.length())
		found += 1
		parts.append("(%+.2f,%+.2f)" % [err.x, err.y])
	var line := "ALIGN %-10s 확대 %.2f dot_px %d  표지 %d개  최대 %.2f px = %.2f 도트   %s" % [tag, _zoom, dots.dot_px, found,
		worst, worst / float(dots.dot_px), " ".join(parts)]
	if loud:
		_say(line)
	else:
		_log.append(line)
	return worst


## e 에 가장 가까운 자홍 픽셀에서 이어진 덩어리(상하좌우)만의 무게중심 — 창 안에 다른 표지가 들어와도 섞이지 않게
func _centroid(img: Image, e: Vector2, reach: int) -> Variant:
	var x0 := maxi(int(e.x) - reach, 0)
	var x1 := mini(int(e.x) + reach, img.get_width() - 1)
	var y0 := maxi(int(e.y) - reach, 0)
	var y1 := mini(int(e.y) + reach, img.get_height() - 1)
	var seed := Vector2i(-1, -1)
	var best := INF
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if _is_mark(img, x, y):
				var dd := Vector2(float(x) + 0.5, float(y) + 0.5).distance_squared_to(e)
				if dd < best:
					best = dd
					seed = Vector2i(x, y)
	if seed.x < 0:
		return null
	var seen := {seed: true}
	var stack: Array[Vector2i] = [seed]
	var sx := 0.0
	var sy := 0.0
	var n := 0
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		sx += float(p.x) + 0.5
		sy += float(p.y) + 0.5
		n += 1
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + o
			if q.x < x0 or q.x > x1 or q.y < y0 or q.y > y1 or seen.has(q) or not _is_mark(img, q.x, q.y):
				continue
			seen[q] = true
			stack.append(q)
	if n < 3:
		return null
	return Vector2(sx / float(n), sy / float(n))


func _is_mark(img: Image, x: int, y: int) -> bool:
	var c := img.get_pixel(x, y)
	return c.r > 0.85 and c.g < 0.2 and c.b > 0.85


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _grab() -> Image:
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _save(file: String) -> void:
	var img := await _grab()
	img.save_png(_shot_dir.path_join(file))


func _say(line: String) -> void:
	print(line)
	_log.append(line)
