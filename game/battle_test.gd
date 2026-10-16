extends Node2D

## 전투 시험장 — 뼈대가 도는 것을 눈으로 보는 곳.  이 씬을 열고 F6.   (보병_추상화.md §4-3)
##
## 지휘(평소):
##   1 우리 편(왼쪽) 소총 분대 투입 · 2 적 분대 투입 · T 적 자동 투입 켬/끔
##   Q 전진 / W 정지 / E 후퇴 — 우리 편 모든 분대에 명령(강제가 아니라 가중치)
##   A · D 또는 ← · → 화면 이동 · 휠 확대/축소 · Space 멈춤
## 빙의(직접 조종): 우리 병사를 마우스 왼쪽 단추로 누르면 그 병사가 된다 · Esc 로 풀고 지휘로 돌아옴
##   A · D 이동 · Shift 달리기 · W · S 깊이(안쪽/앞쪽) · C 앉기 · Z 엎드림 · 마우스 조준 · 왼쪽 단추 사격 · R 장전
##   (빙의 병사도 제압이 넘치면 강제로 엎드려 조작이 잠깐 잠긴다 — 설계 §2-8)
## 보기: F1 판정 상자 · F2 상태 글자 · F3 병사 그림
##   3D 화면만: F4 복장 보기(병종 복장 → 상의만 → 하의만 → 내복) · F5 도트 크기(도트 하나 = 화면 1 ~ 4 픽셀)
##
## 화면: 기본은 3D(병사 = 3D 캐릭터, BattleView3D — 10-15 3D 노선). 이 노드의 use_3d 를 끄거나 명령줄 -- --view=2d 면 예전 2D 퍼펫(BattleView).
## 구조: 이 씬은 입력과 화면 배치만 한다. 논리 = Battlefield(game/sim) · 그리기 = BattleView / BattleView3D(game/view).
## 빙의 = 병사 기록의 "의도" 칸을 AI 두뇌 대신 여기서(키보드 · 마우스로) 채우는 것뿐이다.

const TYPE_PATH := "res://game/units/rifleman.tres"
const TestField := preload("res://game/tools/test_field.gd")
const AUTO_DEPLOY_EVERY := 25.0
const AUTO_DEPLOY_BELOW := 12            # 적이 이보다 적으면 새 분대를 보낸다
const HUD_SQUADS := 6                    # 화면 글자에 적는 분대 수(넘으면 "외 N개")

## 병사를 3D 캐릭터로 그린다(끄면 예전 2D 퍼펫). 명령줄 -- --view=2d / --view=3d 가 이보다 먼저
@export var use_3d := true

var bf: Battlefield
var view: BattleView
var cam: Camera2D
var _label: Label
var _type: SoldierType
var _possessed: BattleSoldier = null
var _stance := 0                          # 빙의 병사의 자세(BattleBody.Stance)
var _reload_req := false
var _fire_armed := false                  # 빙의하려고 누른 그 클릭으로 바로 쏘지 않게
var _auto_enemy := true
var _auto_timer := 6.0
var _cam_x := 20.0                        # 화면 가운데가 보는 x(m)
var _zoom := 1.0
var _shots: Array = []                    # 자동 캡처 시각들(--shot)
var _shot_dir := ""
var _quit_at := -1.0
var _start_squads := 2                    # 처음에 양쪽에 투입할 분대 수(--squads)
var _auto_possess := false                # 검사용: 8초에 우리 병사 하나를 빙의, 16초에 풀기(--possess)
var _frames := 0
var _wear_arg := -1                       # 검사용 --wear=type|top|bottom|none (3D 복장 보기)
var _dot_arg := 0                         # 검사용 --dot=N (3D 도트 크기)


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.42, 0.47, 0.42))
	_type = load(TYPE_PATH) as SoldierType
	_read_args()
	bf = Battlefield.new()
	bf.name = "Battlefield"
	TestField.build(bf)
	add_child(bf)
	view = BattleView3D.new() if use_3d else BattleView.new()
	view.name = "View"
	add_child(view)
	if view is BattleView3D:
		var v3 := view as BattleView3D
		if _dot_arg > 0:
			v3.dot_px = _dot_arg
		if _wear_arg >= 0:
			v3.wear_mode = _wear_arg
	view.setup(bf)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	var ui := CanvasLayer.new()
	add_child(ui)
	_label = Label.new()
	_label.position = Vector2(10, 6)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	ui.add_child(_label)
	if _type == null:
		_label.text = "병종 리소스가 없습니다: %s\nGodot --headless --path <프로젝트> --script res://game/tools/make_default_units.gd 를 먼저 돌리세요" % TYPE_PATH
		return
	view.prewarm(_type, _start_squads * 2 * _type.squad_size)
	for i in _start_squads:
		bf.deploy_squad(0, _type)
		bf.deploy_squad(1, _type)


## 명령줄(검사용): -- --shot=<폴더> [--seconds=30] [--cam=50] [--squads=2] [--possess] [--view=2d|3d] [--wear=type|top|bottom|none] [--dot=2]
## 6초마다 화면을 저장하고 닫힌다. --possess = 8초에 우리 병사 하나를 빙의했다가 16초에 푼다(빙의 길에 오류가 없는지)
func _read_args() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		if s.begins_with("view="):
			use_3d = s.substr(5) != "2d"
		elif s.begins_with("wear="):
			_wear_arg = maxi(["type", "top", "bottom", "none"].find(s.substr(5)), 0)
		elif s.begins_with("dot="):
			_dot_arg = clampi(int(s.substr(4)), 1, 6)
		elif s.begins_with("shot="):
			_shot_dir = s.substr(5)
			DirAccess.make_dir_recursive_absolute(_shot_dir)
		elif s.begins_with("seconds="):
			_quit_at = float(s.substr(8))
		elif s.begins_with("cam="):
			_cam_x = float(s.substr(4))
		elif s.begins_with("squads="):
			_start_squads = maxi(int(s.substr(7)), 1)
		elif s == "possess":
			_auto_possess = true
	if _shot_dir != "":
		if _quit_at < 0.0:
			_quit_at = 30.0
		var k := 1
		while float(k) * 6.0 <= _quit_at:
			_shots.append(float(k) * 6.0)
			k += 1


func _physics_process(delta: float) -> void:
	if _type == null:
		return
	# 적 자동 투입(안건 E: 적도 같은 규칙 — 맵 끝에서 분대 단위로)
	if _auto_enemy:
		_auto_timer -= delta
		if _auto_timer <= 0.0:
			_auto_timer = AUTO_DEPLOY_EVERY
			if bf.count_fighting(1) < AUTO_DEPLOY_BELOW:
				bf.deploy_squad(1, _type)
	if _auto_possess:
		if _possessed == null and bf.time >= 8.0 and bf.time < 16.0:
			for c in bf.soldiers:
				if c.team == 0 and c.can_fight():
					_possess(c)
					break
		elif _possessed != null and bf.time >= 16.0:
			_release()
			_auto_possess = false
	_drive_possessed()


## 빙의 병사의 "의도" 칸을 키보드 · 마우스로 채운다 — AI 두뇌가 하던 일을 대신한다(몸은 그대로)
func _drive_possessed() -> void:
	if _possessed == null:
		return
	var s := _possessed
	if not s.can_fight():                # 죽었거나 패닉 → 지휘로 돌아간다
		_release()
		return
	s.use_goal = false
	s.move_dir = int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A))
	s.want_run = Input.is_physical_key_pressed(KEY_SHIFT)
	var dd := int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W))
	s.goal_depth = clampf(s.depth + float(dd) * 0.1, 0.0, 1.0)
	s.want_stance = _stance
	var aim := view.aim_from_canvas(view.get_local_mouse_position(), s)
	s.aim_x = aim.x
	s.aim_h = aim.y
	s.aim_depth = aim.z
	var pressing := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not pressing:
		_fire_armed = true
	s.want_fire = pressing and _fire_armed
	if _reload_req and (s.act_state == BattleBody.Act.RELOAD or s.ammo >= s.type.weapon.mag_size):
		_reload_req = false
	s.want_reload = _reload_req
	if s.move_dir == 0 and absf(aim.x - s.x) > 0.3:
		s.facing = 1 if aim.x > s.x else -1


func _possess(s: BattleSoldier) -> void:
	if bf.possess(s):
		_possessed = s
		_stance = s.stance
		_reload_req = false
		_fire_armed = false


func _release() -> void:
	if _possessed != null:
		bf.release(_possessed)
	_possessed = null


func _process(delta: float) -> void:
	if _type == null:
		return
	_frames += 1
	# 화면
	if _possessed != null:
		_cam_x = lerpf(_cam_x, _possessed.x, 1.0 - exp(-delta * 6.0))
	else:
		var pan := int(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) \
				- int(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
		_cam_x += float(pan) * 30.0 * delta / _zoom
	_cam_x = clampf(_cam_x, 0.0, bf.length_m)
	cam.zoom = Vector2(_zoom, _zoom)
	cam.position = Vector2(_cam_x * view.ppm, view.ground_y - 110.0 / _zoom)
	_update_hud()
	# 자동 캡처
	if _shot_dir != "":
		if not _shots.is_empty() and bf.time >= float(_shots[0]):
			var stamp := int(_shots.pop_front())
			_capture.call_deferred("%s/battle_%03d.png" % [_shot_dir, stamp])
		if bf.time >= _quit_at and _shots.is_empty():
			_shot_dir = ""
			_finish.call_deferred()


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _finish() -> void:
	await RenderingServer.frame_post_draw
	print("BATTLE TEST DONE  %s  %.0f초  병사 기록 %d  평균 %.0f fps  z 띠 %d  총알 %d  맞음 %d  사살 %s  패닉 %s" % ["3D" if view is BattleView3D else "2D",
		bf.time, bf.soldiers.size(), float(_frames) / maxf(bf.time, 0.001), view.get_bands_used(), bf.stats["shots"], bf.stats["hits"],
		str(bf.stats["kills"]), str(bf.stats["panics"])])
	get_tree().quit()


func _update_hud() -> void:
	var lines := PackedStringArray()
	lines.append("%s   우리 %d명 · 적 %d명   총알 %d · 맞음 %d · 사살 %s   %.0f fps%s" % [
		"빙의 중" if _possessed != null else "지휘", bf.count_fighting(0), bf.count_fighting(1),
		bf.stats["shots"], bf.stats["hits"], str(bf.stats["kills"]), Engine.get_frames_per_second(),
		"" if bf.running else "   [멈춤]"])
	if _possessed != null:
		lines.append("A·D 이동  Shift 달리기  W·S 깊이  C 앉기  Z 엎드림  마우스 조준·사격  R 장전  Esc 풀기")
	else:
		lines.append("1 분대 투입  2 적 분대  T 적 자동(%s)  Q 전진  W 정지  E 후퇴  A·D 화면  휠 확대  병사 클릭 = 빙의" % ("켬" if _auto_enemy else "끔"))
	if view is BattleView3D:
		lines.append("%s   F4 복장 보기  F5 도트 크기" % (view as BattleView3D).status_text())
	var listed := 0
	var more := 0
	for sq in bf.squads:
		if sq.team != 0:
			continue
		var act := sq.active()
		if act.is_empty():
			continue
		if listed >= HUD_SQUADS:
			more += 1
			continue
		listed += 1
		lines.append("  분대%d  %d명  명령 %s → 태세 %s%s  사기 %.2f  제압 %.2f" % [sq.id, act.size(), BattleSquad.ORDER_NAMES[sq.order],
			BattleSquad.POSTURE_NAMES[sq.posture], " (패주)" if sq.routed else "", sq.morale, sq.avg_suppression()])
	if more > 0:
		lines.append("  … 외 %d개 분대" % more)
	# 실행 중 확인(§2-11): 빙의한 병사, 아니면 마우스 아래 병사의 상태
	var look := _possessed if _possessed != null else view.soldier_near(view.get_local_mouse_position(), -1, 40.0)
	if look != null:
		lines.append("")
		lines.append(view.describe(look))
	_label.text = "\n".join(lines)


func _unhandled_input(ev: InputEvent) -> void:
	if _type == null:
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = minf(_zoom * 1.1, 3.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = maxf(_zoom / 1.1, 0.35)
		elif mb.button_index == MOUSE_BUTTON_LEFT and _possessed == null:
			var s := view.soldier_near(view.get_local_mouse_position(), 0, 40.0)
			if s != null:
				_possess(s)
		return
	if not (ev is InputEventKey) or not (ev as InputEventKey).pressed or (ev as InputEventKey).echo:
		return
	var k := (ev as InputEventKey).physical_keycode
	match k:
		KEY_F1:
			view.show_boxes = not view.show_boxes
		KEY_F2:
			view.show_labels = not view.show_labels
		KEY_F3:
			view.show_puppets = not view.show_puppets
		KEY_F4:
			if view is BattleView3D:
				var v3 := view as BattleView3D
				v3.wear_mode = (v3.wear_mode + 1) % BattleView3D.WEAR_NAMES.size()
		KEY_F5:
			if view is BattleView3D:
				var v3 := view as BattleView3D
				v3.dot_px = v3.dot_px % 4 + 1
		KEY_SPACE:
			bf.running = not bf.running
		KEY_ESCAPE:
			_release()
	if _possessed != null:
		match k:
			KEY_C:
				_stance = BattleBody.Stance.STAND if _stance == BattleBody.Stance.CROUCH else BattleBody.Stance.CROUCH
			KEY_Z:
				_stance = BattleBody.Stance.STAND if _stance == BattleBody.Stance.PRONE else BattleBody.Stance.PRONE
			KEY_R:
				_reload_req = true
		return
	match k:
		KEY_1:
			bf.deploy_squad(0, _type)
		KEY_2:
			bf.deploy_squad(1, _type)
		KEY_T:
			_auto_enemy = not _auto_enemy
		KEY_Q:
			_order(BattleSquad.Order.ADVANCE)
		KEY_W:
			_order(BattleSquad.Order.HOLD)
		KEY_E:
			_order(BattleSquad.Order.RETREAT)


## 우리 편 모든 분대에 명령 — 분대 두뇌 점수의 가중치로 들어간다(바로 다시 판단하게 한다)
func _order(o: int) -> void:
	for sq in bf.squads:
		if sq.team == 0:
			sq.order = o
			sq.brain_timer = 0.0
