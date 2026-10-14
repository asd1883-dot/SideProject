extends Node2D

## 부하 시험 — 퍼펫 N 개를 한 화면에 띄워 화면 속도를 잰다.  (Docs/게임설계/보병_추상화.md §4-1 · 결과는 같은 폴더의 부하시험_결과.md)
##
## 에디터에서: 이 씬을 열고 F6.
##   ↑ / ↓   병사 수 ±25            O  복장 켬/끔
##   Z       겹칠 때 그리는 순서 — 같은 z(겹치면 조각이 섞임) / 병사마다 z 띠 / 깊이 줄 12개 / 겹치는 병사끼리만 다른 띠
##   A       애니 갱신 — 매 프레임 / 2프레임마다 / 3프레임마다 / 멈춤
##   H       그리기 숨김(애니 비용만 보기)      V  수직동기 켬/끔(꺼야 진짜 속도가 보인다)
##
## 명령줄(자동 측정 — 경우를 차례로 돌리고 결과를 적은 뒤 닫힌다):
##   Godot --path <프로젝트> --resolution 1920x1080 res://test/load_test.tscn -- --auto --out=<폴더> [--seconds=4] [--only-order=3]
##
## 왜 "순서"를 따로 재나: 퍼펫 조각은 z_index −1(외곽선 밑깔개) · 10~150(조각)을 쓴다. 병사를 그냥 띄우면 겹친 병사끼리
## 조각이 z 별로 섞여 그려진다(뒤 병사의 팔이 앞 병사의 몸통 위로). 바르게 하려면 병사마다 z 띠를 줘야 하는데,
## Godot 의 z 는 −4096 ~ 4096 뿐이라 조각 z 를 0,1,2… 로 다시 매겨(_compact_z) 띠 폭을 줄여야 100명 이상이 들어간다.
## 그리고 순서를 바르게 하면 같은 그림끼리 이어 그리지 못해 그리기 호출이 크게 늘어난다 — 그 값을 재려는 것.

const SETS_JSON := "res://puppet/sets.json"
const OUTFIT_JSON := "res://outfits/uniform_m36/outfit.json"
const PUPPET_PX := 256.0            # 구운 캔버스 높이
const ROWS := 12                    # 순서 방식 2 의 깊이 줄 수
const ORDER_NAMES := ["같은 z (겹치면 조각이 섞임)", "병사마다 z 띠 (정확 · 조각 z 다시 매김)", "깊이 줄 %d개" % ROWS, "겹치는 병사끼리만 다른 띠 (정확 · 구운 z 그대로)"]
const DIV_NAMES := {1: "매 프레임", 2: "2프레임마다", 3: "3프레임마다", 0: "멈춤"}

var n := 100
var order := 1                      # 0 같은 z · 1 병사마다 z 띠 · 2 깊이 줄 · 3 겹치는 병사끼리만 다른 띠
var outfit_on := true
var anim_div := 1                   # 1 매 프레임 · 2 · 3 · 0 멈춤
var hide_draw := false
var size_frac := 0.12               # 병사 캔버스 높이 / 화면 높이

var _root: Node2D
var _soldiers: Array[DRPuppetSet] = []
var _outfit: DROutfit = null
var _label: Label
var _frame := 0
var _last_usec := 0
var _spawn_ms := 0.0
var _z_span := 0
var _bands := 0                     # 순서 방식 3 이 쓴 띠 수
var _z_overflow := false            # 띠가 z 범위(−4096 ~ 4096)를 넘쳤다
var _vp: RID
var _canvas_info := -1              # RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS (없는 버전이면 −1)

# 측정
var _measuring := false
var _dts := PackedFloat64Array()    # 프레임 시간(usec)
var _cpu_sum := 0.0
var _gpu_sum := 0.0
var _draw_sum := 0.0
var _hud_acc := 0.0
var _hud_frames := 0
var _hud_ms := 0.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.36, 0.42, 0.36))
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	if ClassDB.class_has_integer_constant("RenderingServer", "VIEWPORT_RENDER_INFO_TYPE_CANVAS"):
		_canvas_info = ClassDB.class_get_integer_constant("RenderingServer", "VIEWPORT_RENDER_INFO_TYPE_CANVAS")
	_root = Node2D.new()
	_root.name = "Soldiers"
	add_child(_root)
	if FileAccess.file_exists(OUTFIT_JSON):
		_outfit = DROutfit.load_json(OUTFIT_JSON)
	var ui := CanvasLayer.new()
	add_child(ui)
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	ui.add_child(_label)
	_last_usec = Time.get_ticks_usec()
	var args := _user_args()
	if args.has("spawn-probe"):
		_label.visible = false
		_run_spawn_probe.call_deferred()
	elif args.has("auto"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		_label.visible = false
		_run_auto.call_deferred(args)
	else:
		spawn()


func _user_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var eq := s.find("=")
		if eq < 0:
			out[s] = "1"
		else:
			out[s.substr(0, eq)] = s.substr(eq + 1)
	return out


## 지금 설정(n · order · outfit_on · anim_div · hide_draw)대로 병사를 다시 만든다. 만든 시간(ms)을 _spawn_ms 에 남긴다.
func spawn() -> void:
	for s in _soldiers:
		s.queue_free()
	_soldiers.clear()
	var vs := get_viewport_rect().size
	var sc := size_frac * vs.y / PUPPET_PX
	var rng := RandomNumberGenerator.new()
	rng.seed = 1941
	var depths := PackedFloat32Array()
	var t0 := Time.get_ticks_usec()
	for i in n:
		var s := DRPuppetSet.new()
		s.name = "S%03d" % i
		s.force_loop = true
		s.sets_json = SETS_JSON
		_root.add_child(s)                      # _ready → reload() → 퍼펫 씬을 만든다
		if outfit_on and _outfit != null:
			s.wear(_outfit)
		var depth := rng.randf()
		depths.append(depth)
		s.position = Vector2(rng.randf_range(0.04, 0.96) * vs.x, lerpf(0.40, 0.97, depth) * vs.y)
		s.scale = Vector2(sc if rng.randf() < 0.5 else -sc, sc)   # 절반은 왼쪽을 본다(적)
		s.speed_scale = rng.randf_range(0.85, 1.15)
		var pl := s.get_animation_player()
		if pl != null:
			pl.seek(rng.randf() * 0.66, true)   # 발을 서로 다르게
		_soldiers.append(s)
	_spawn_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	# 겹칠 때 그리는 순서
	_z_span = 0
	_bands = 0
	_z_overflow = false
	if order == 3:
		_order_by_overlap(depths, absf(sc))
	elif order != 0:
		for s in _soldiers:
			_z_span = maxi(_z_span, _compact_z(s))
		if order == 1:
			var idx: Array = range(n)
			idx.sort_custom(func(a: int, b: int) -> bool: return depths[a] < depths[b])
			for r in n:
				_soldiers[int(idx[r])].z_index = mini(RenderingServer.CANVAS_ITEM_Z_MIN + 1 + r * _z_span, RenderingServer.CANVAS_ITEM_Z_MAX - _z_span)
		else:
			for i in n:
				_soldiers[i].z_index = mini(int(depths[i] * ROWS), ROWS - 1) * _z_span
	_apply_runtime()


## 순서 방식 3 — 구운 z 는 그대로 두고, **화면에서 겹치는 병사끼리만** 서로 다른 띠를 준다.
## 깊이 순으로 훑으며 "나와 겹치는 더 뒤 병사들의 띠 + 1" 을 받는다 → 필요한 띠 수 = 가장 길게 겹쳐 이어진 줄의 길이(병사 수가 아니다).
func _order_by_overlap(depths: PackedFloat32Array, sc: float) -> void:
	var zmin := 0
	var zmax := 0
	if _soldiers.size() > 0:
		var sprites: Array[Sprite2D] = []
		_collect_sprites(_soldiers[0], sprites)
		for sp in sprites:
			zmin = mini(zmin, sp.z_index)
			zmax = maxi(zmax, sp.z_index)
	_z_span = zmax - zmin + 2                 # 조각 z 폭 + 장비가 맨 위에 얹힐 자리 1
	var width := PUPPET_PX * sc * 0.9         # 이보다 가까우면 화면에서 겹친다고 본다
	var idx: Array = range(_soldiers.size())
	idx.sort_custom(func(a: int, b: int) -> bool: return depths[a] < depths[b])
	var band := PackedInt32Array()
	band.resize(_soldiers.size())
	for r in idx.size():
		var a := int(idx[r])
		var b := 0
		for q in r:
			var c := int(idx[q])
			if absf(_soldiers[a].position.x - _soldiers[c].position.x) < width:
				b = maxi(b, band[c] + 1)
		band[a] = b
		_bands = maxi(_bands, b + 1)
	var room := (RenderingServer.CANVAS_ITEM_Z_MAX - RenderingServer.CANVAS_ITEM_Z_MIN) / _z_span
	_z_overflow = _bands > room
	for i in _soldiers.size():
		_soldiers[i].z_index = clampi(RenderingServer.CANVAS_ITEM_Z_MIN - zmin + band[i] * _z_span, RenderingServer.CANVAS_ITEM_Z_MIN, RenderingServer.CANVAS_ITEM_Z_MAX - zmax - 1)


## 조각들의 z_index(−1 · 10 · 20 …)를 0 · 1 · 2 … 로 다시 매긴다 → 병사 한 명이 차지하는 z 폭이 152 → 16 으로 준다.
## 돌려주는 값 = 폭. (장비를 끼우려면 조각 사이에 자리가 더 필요하다 — 실제 게임에선 간격 2 = 폭 32 쯤)
func _compact_z(soldier: Node) -> int:
	var sprites: Array[Sprite2D] = []
	_collect_sprites(soldier, sprites)
	var zs: Array[int] = []
	for sp in sprites:
		if not zs.has(sp.z_index):
			zs.append(sp.z_index)
	zs.sort()
	for sp in sprites:
		sp.z_index = zs.find(sp.z_index)
	return zs.size()


func _collect_sprites(node: Node, out: Array[Sprite2D]) -> void:
	for c in node.get_children():
		if c is Sprite2D:
			out.append(c as Sprite2D)
		_collect_sprites(c, out)


## 다시 만들지 않고 바꿀 수 있는 것(애니 갱신 주기 · 숨김)
func _apply_runtime() -> void:
	_root.visible = not hide_draw
	for s in _soldiers:
		s.set_process(anim_div == 1)        # 1 이 아니면 아래 _process 가 대신 돌린다


func _process(delta: float) -> void:
	_frame += 1
	var now := Time.get_ticks_usec()
	var dt := float(now - _last_usec)
	_last_usec = now
	if anim_div > 1:
		# 먼 병사 · 화면 밖 병사의 갱신을 줄이는 것을 흉내: 병사를 anim_div 무리로 나눠 한 프레임에 한 무리만(시간은 그만큼 크게)
		for i in _soldiers.size():
			if (i + _frame) % anim_div == 0:
				_soldiers[i]._process(delta * float(anim_div))
	if _measuring:
		_dts.append(dt)
		_cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(_vp) + RenderingServer.get_frame_setup_time_cpu()
		_gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(_vp)
		_draw_sum += _draw_calls()
	if _label.visible:
		_hud_acc += dt
		_hud_frames += 1
		if _hud_acc >= 500000.0:
			_hud_ms = _hud_acc / float(_hud_frames) / 1000.0
			_hud_acc = 0.0
			_hud_frames = 0
			_update_hud()


func _draw_calls() -> float:
	if _canvas_info >= 0:
		return float(RenderingServer.viewport_get_render_info(_vp, _canvas_info, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
	return float(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))


func _update_hud() -> void:
	var vs := "끔" if DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED else "켬(화면 주사율에 묶임 — V 로 끄기)"
	_label.text = "\n".join(PackedStringArray([
		"병사 %d명   %.2f ms/프레임 = %.0f fps   그리기 호출 %d   노드 %d" % [n, _hud_ms, 1000.0 / maxf(_hud_ms, 0.001), int(_draw_calls()), int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))],
		"순서 [%s]   복장 [%s]   애니 [%s]   %s   수직동기 %s" % [ORDER_NAMES[order], "군복" if outfit_on else "맨몸", DIV_NAMES[anim_div], "그리기 숨김" if hide_draw else "그리는 중", vs],
		"만드는 데 %.0f ms (한 명 %.1f ms)   병사 z 폭 %d%s" % [_spawn_ms, _spawn_ms / float(maxi(n, 1)), _z_span,
			("   띠 %d개%s" % [_bands, " ⚠ z 범위 넘침" if _z_overflow else ""]) if order == 3 else ""],
		"↑↓ 병사 수 · O 복장 · Z 순서 · A 애니 갱신 · H 숨김 · V 수직동기",
	]))


func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not (ev as InputEventKey).pressed or (ev as InputEventKey).echo:
		return
	match (ev as InputEventKey).keycode:
		KEY_UP:
			n = mini(n + 25, 500)
			spawn()
		KEY_DOWN:
			n = maxi(n - 25, 25)
			spawn()
		KEY_O:
			outfit_on = not outfit_on
			spawn()
		KEY_Z:
			order = (order + 1) % ORDER_NAMES.size()
			spawn()
		KEY_A:
			anim_div = {1: 2, 2: 3, 3: 0, 0: 1}[anim_div]
			_apply_runtime()
		KEY_H:
			hide_draw = not hide_draw
			_apply_runtime()
		KEY_V:
			var off := DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if off else DisplayServer.VSYNC_DISABLED)


# ───────────────────────── 자동 측정 ─────────────────────────

func _cases() -> Array:
	var cs: Array = []
	for k in [50, 100, 150, 200, 300, 400]:
		cs.append({"id": "정확한 순서 %d명" % k, "n": k, "order": 1, "shot": "order1_%d" % k if k == 150 else ""})
	for k in [150, 300]:
		cs.append({"id": "같은 z %d명" % k, "n": k, "order": 0, "shot": "order0_%d" % k if k == 150 else ""})
		cs.append({"id": "깊이 줄 %d개 %d명" % [ROWS, k], "n": k, "order": 2, "shot": "order2_%d" % k if k == 150 else ""})
	for k in [150, 300, 400]:
		cs.append({"id": "겹치는 끼리만 띠 %d명" % k, "n": k, "order": 3, "shot": "order3_%d" % k if k == 150 else ""})
	cs.append({"id": "맨몸 150명", "n": 150, "order": 1, "outfit": false})
	cs.append({"id": "애니 멈춤 150명 (그리기만)", "n": 150, "order": 1, "div": 0})
	cs.append({"id": "숨김 150명 (애니만)", "n": 150, "order": 1, "hide_draw": true})
	cs.append({"id": "애니 2프레임마다 150명", "n": 150, "order": 1, "div": 2})
	cs.append({"id": "애니 3프레임마다 150명", "n": 150, "order": 1, "div": 3})
	cs.append({"id": "병사 없음 (빈 화면)", "n": 0, "order": 1})
	return cs


func _run_auto(args: Dictionary) -> void:
	var out_dir := String(args.get("out", "user://load_test"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	var seconds := float(args.get("seconds", "4"))
	var only := int(args.get("only-order", "-1"))        # 그 순서 방식의 경우만 다시 잴 때
	var results: Array = []
	for c in _cases():
		var cd: Dictionary = c
		if only >= 0 and (int(cd["order"]) != only or cd.size() > 4):
			continue
		n = int(cd["n"])
		order = int(cd["order"])
		outfit_on = bool(cd.get("outfit", true))
		anim_div = int(cd.get("div", 1))
		hide_draw = bool(cd.get("hide_draw", false))
		spawn()
		await get_tree().create_timer(1.2).timeout          # 셰이더 · 그림 올리기가 끝날 때까지
		_dts.clear()
		_cpu_sum = 0.0
		_gpu_sum = 0.0
		_draw_sum = 0.0
		_measuring = true
		await get_tree().create_timer(seconds).timeout
		_measuring = false
		var r := _summarize()
		r["id"] = String(cd["id"])
		r["n"] = n
		r["order"] = order
		r["spawn_ms"] = snappedf(_spawn_ms, 0.1)
		r["nodes"] = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		r["z_span"] = _z_span
		r["bands"] = _bands
		r["z_overflow"] = _z_overflow
		results.append(r)
		if order == 3:
			print("LOADTEST   └ 띠 %d개 × 폭 %d%s" % [_bands, _z_span, "  ⚠ z 범위 넘침" if _z_overflow else ""])
		print("LOADTEST | %-28s | %7.2f ms | %6.0f fps | 1%%낮은 %6.0f fps | 렌더CPU %6.2f ms | GPU %6.2f ms | 그리기 %5d | 노드 %6d | 만들기 %6.0f ms" % [
			r["id"], r["ms"], r["fps"], r["fps_low1"], r["render_cpu_ms"], r["gpu_ms"], r["draw_calls"], r["nodes"], r["spawn_ms"]])
		var shot := String(cd.get("shot", ""))
		if shot != "":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out_dir.path_join(shot + ".png"))
	n = 0
	spawn()
	var probe := _spawn_probe()
	print("LOADTEST 만들기 나눠 재기(한 명, ms) | 씬 만들기 %.2f | rig.json 읽기 %.2f (reload 가 두 번 읽음) | DRPuppetSet 전체 %.2f" % [probe["instantiate_ms"], probe["rig_json_ms"], probe["puppet_set_ms"]])
	var doc := {
		"spawn_probe": probe,
		"gpu": RenderingServer.get_video_adapter_name(),
		"renderer": String(ProjectSettings.get_setting("rendering/renderer/rendering_method")),
		"method": RenderingServer.get_current_rendering_method(),
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"cpu": OS.get_processor_name(),
		"window": [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y],
		"godot": Engine.get_version_info()["string"],
		"seconds": seconds,
		"results": results,
	}
	var f := FileAccess.open(out_dir.path_join("result.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	print("LOADTEST DONE ", out_dir.path_join("result.json"), "  ", doc["gpu"], " / ", doc["method"], " / ", doc["driver"], " / ", doc["window"])
	get_tree().quit()


## 만들기 시간이 조건에 따라 왜 달라지는지 가려내기(--spawn-probe). 100명씩, 한 명당 ms
func _run_spawn_probe() -> void:
	outfit_on = false
	order = 0
	var lines := PackedStringArray()
	for step in ["빈 화면에서", "앞 병사 100명이 아직 있는 채로 바로", "앞 병사가 사라진 뒤", "군복 입혀서(앞 병사 사라진 뒤)", "한 번 더(앞 병사 사라진 뒤)"]:
		if not String(step).begins_with("앞 병사 100명이"):
			n = 0
			spawn()
			for i in 4:
				await get_tree().process_frame
		outfit_on = String(step).begins_with("군복")
		n = 100
		spawn()
		lines.append("LOADTEST 만들기 | %-34s | 한 명 %.2f ms" % [step, _spawn_ms / 100.0])
		for i in 2:
			await get_tree().process_frame
		if String(step).begins_with("빈 화면"):
			pass
	# 화면에 보이는지에 따라
	n = 0
	spawn()
	for i in 4:
		await get_tree().process_frame
	_root.visible = false
	n = 100
	outfit_on = false
	var keep_hide := hide_draw
	hide_draw = true
	spawn()
	hide_draw = keep_hide
	lines.append("LOADTEST 만들기 | %-34s | 한 명 %.2f ms" % ["숨긴 채로(빈 화면에서)", _spawn_ms / 100.0])
	_root.visible = true
	# 자동 측정 끝의 "나눠 재기"에서는 2.4 ms 가 나왔다 — 바로 앞에 한 일(씬 100번 만들기 · rig.json 100번 읽기) 중 무엇 때문인지
	var ps := load(_first_set_path("scene")) as PackedScene
	for mode in ["rig.json 100번 읽은 직후", "퍼펫 씬 100개 만들어 둔 직후", "퍼펫 씬 100개 만들었다 지운 뒤"]:
		n = 0
		spawn()
		for i in 4:
			await get_tree().process_frame
		var raw: Array[Node] = []
		if String(mode).begins_with("rig.json"):
			for i in 100:
				JSON.parse_string(FileAccess.get_file_as_string(_first_set_path("rig")))
		else:
			for i in 100:
				var p := ps.instantiate()
				_root.add_child(p)
				raw.append(p)
			if String(mode).ends_with("지운 뒤"):
				for p in raw:
					p.queue_free()
				raw.clear()
				for i in 4:
					await get_tree().process_frame
		n = 100
		spawn()
		lines.append("LOADTEST 만들기 | %-34s | 한 명 %.2f ms" % [mode, _spawn_ms / 100.0])
		for p in raw:
			p.queue_free()
		for i in 2:
			await get_tree().process_frame
	for l in lines:
		print(l)
	print("LOADTEST DONE spawn-probe")
	get_tree().quit()


## sets.json 의 첫 세트에서 씬("scene") · 리그("rig") 파일 경로를 얻는다 — 세트 이름(폴더)을 바꿔 다시 구워도 이 시험이 따라가게
func _first_set_path(key: String) -> String:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETS_JSON)) if FileAccess.file_exists(SETS_JSON) else null
	if doc is Dictionary:
		for sd in (doc as Dictionary).get("sets", []):
			var rel := String((sd as Dictionary).get(key, ""))
			if rel != "":
				return SETS_JSON.get_base_dir().path_join(rel)
	push_error("[load_test] %s 에 세트가 없습니다 — 먼저 Dot Rigger ① 에서 세트를 구우세요" % SETS_JSON)
	return ""


## 병사 한 명을 만드는 시간이 어디서 드는지 — 씬 만들기 / rig.json 읽기 / DRPuppetSet 전체. 100번 평균(ms)
func _spawn_probe() -> Dictionary:
	var reps := 100
	var ps := load(_first_set_path("scene")) as PackedScene
	var made: Array[Node] = []
	var t0 := Time.get_ticks_usec()
	for i in reps:
		var p := ps.instantiate()
		_root.add_child(p)
		made.append(p)
	var inst := float(Time.get_ticks_usec() - t0) / 1000.0 / float(reps)
	for p in made:
		p.queue_free()
	t0 = Time.get_ticks_usec()
	for i in reps:
		JSON.parse_string(FileAccess.get_file_as_string(_first_set_path("rig")))
	var js := float(Time.get_ticks_usec() - t0) / 1000.0 / float(reps)
	n = reps
	order = 0
	outfit_on = false
	spawn()
	var full := _spawn_ms / float(reps)
	n = 0
	spawn()
	return {"instantiate_ms": snappedf(inst, 0.01), "rig_json_ms": snappedf(js, 0.01), "puppet_set_ms": snappedf(full, 0.01)}


func _summarize() -> Dictionary:
	var cnt := _dts.size()
	if cnt == 0:
		return {"ms": 0.0, "fps": 0.0, "fps_low1": 0.0, "render_cpu_ms": 0.0, "gpu_ms": 0.0, "draw_calls": 0, "frames": 0}
	var sum := 0.0
	for d in _dts:
		sum += d
	var sorted := _dts.duplicate()
	sorted.sort()
	var p99: float = sorted[int(0.99 * float(cnt - 1))]
	var avg := sum / float(cnt)
	return {
		"ms": snappedf(avg / 1000.0, 0.001),
		"fps": snappedf(1000000.0 / avg, 0.1),
		"fps_low1": snappedf(1000000.0 / p99, 0.1),
		"render_cpu_ms": snappedf(_cpu_sum / float(cnt), 0.001),
		"gpu_ms": snappedf(_gpu_sum / float(cnt), 0.001),
		"draw_calls": int(round(_draw_sum / float(cnt))),
		"frames": cnt,
	}
