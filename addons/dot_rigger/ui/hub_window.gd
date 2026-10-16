@tool
extends Window
class_name DRHubWindow

## Dot Rigger 창 — 한 창에 탭 페이지.  프로젝트 > 도구 > Dot Rigger.
##
##   [ Dot Rigger | ① 유닛 | ② 장비 굽기 | ③ 복장 굽기 ]        Ctrl+1 · 2 · 3
##   (10-16: ① 은 3D 유닛 탭 — 예전 2D 캐릭터 굽기 페이지(main_window.gd)는 사용자 지시로 뺐다)
##   ┌───────────────────────── 고른 페이지 ─────────────────────────┐
##
## - 페이지는 처음 눌렀을 때 만든다(창이 빨리 뜨고, 안 쓰는 페이지는 비용이 없다). 한 번 만든 페이지는 탭을 바꿔도
##   그대로 살아 있어 불러온 모델 · 조정 · 칠하기가 유지된다.
## - 안 보이는 페이지의 미리보기 뷰포트는 멈춰 둔다(DRPage.set_page_active).
## - 마지막에 보던 탭을 기억한다(에디터 프로젝트 메타데이터).
## - 페이지 추가 = PAGES 에 한 줄(DRPage 를 상속한 클래스).
## - **공통 설정**(탭 줄 아래): 캐릭터 프리셋 · 세트 목록(sets.json)을 한 번만 고르면 세 탭이 같이 쓴다.
##   캐릭터 탭에서 프리셋을 저장/불러오거나 세트를 구우면 여기와 다른 탭에 바로 전해진다(DRPage.context_changed → apply_context).

const META_SECTION := "dot_rigger_hub"
const PAGES := [
	{"key": "unit", "title": "① 유닛", "tip": "유닛 프리팹(3D) — 몸 · 복장 · 무기 · 세트별 동작 표 · 3D 도트 미리보기 · 새 자식 유닛(상속)"},
	{"key": "equip", "title": "② 장비 굽기", "tip": "무기 · 헬멧을 퍼펫의 세트마다 맞춰 굽기(그립 · 그리기 순서)"},
	{"key": "outfit", "title": "③ 복장 굽기", "tip": "옷 갈아입히기 — 뼈대에 붙이기 · 부위 칠하기 · 상의/하의 굽기"},
]

var _pages: Dictionary = {}      # key -> DRPage (만든 것만)
var _buttons: Dictionary = {}    # key -> Button
var _body: Control
var _current := ""
var _ctx := {"preset": "", "sets": ""}   # 세 탭이 같이 쓰는 설정
var _preset_edit: LineEdit
var _sets_edit: LineEdit
var _ctx_note: Label
var _bg_pick: ColorPickerButton
var _preview_bg := Color(0, 0, 0, 0)   # a == 0 = 기본(탭마다 원래 색)
var _bg_restored := false


func _init() -> void:
	title = "Dot Rigger"
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	size = Vector2i(1400, 860)
	min_size = Vector2i(1100, 680)
	exclusive = false
	# 창(Window)은 기본이 `보임` 이라 트리에 넣는 순간 기본 자리(첫 모니터의 왼쪽 위 — 제목줄이 화면 밖)에 떠 버린다.
	# 10-06: 그래서 가운데로 옮기는 코드가 건너뛰어져 다른 모니터 구석에 떴고 끌 수도 닫을 수도 없었다 → 숨긴 채로 만들고 open() 이 띄운다.
	visible = false
	close_requested.connect(_on_close)
	window_input.connect(_on_window_input)
	_build_ui()


static func _make_page(key: String) -> DRPage:
	match key:
		"unit":
			return DRUnitPage.new()
		"equip":
			return DREquipWindow.new()
		"outfit":
			return DROutfitWindow.new()
	return null


func _accent() -> Color:
	if Engine.is_editor_hint():
		var th := EditorInterface.get_editor_theme()
		if th != null and th.has_color("accent_color", "Editor"):
			return th.get_color("accent_color", "Editor")
	return Color(0.44, 0.73, 0.98)


func _flat(bg: Color, underline: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	if underline.a > 0.0:
		sb.border_width_bottom = 3
		sb.border_color = underline
	return sb


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.14, 0.16)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# 탭 줄 — 납작한 탭 + 고른 탭 아래 강조선(옛 탭 컨트롤의 현대식)
	var header := PanelContainer.new()
	var hb := StyleBoxFlat.new()
	hb.bg_color = Color(0.1, 0.11, 0.13)
	hb.content_margin_left = 12
	hb.content_margin_right = 12
	hb.content_margin_top = 6
	hb.border_width_bottom = 1
	hb.border_color = Color(0.24, 0.26, 0.3)
	header.add_theme_stylebox_override("panel", hb)
	root.add_child(header)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	header.add_child(bar)
	var brand := Label.new()
	brand.text = "Dot Rigger"
	brand.add_theme_font_size_override("font_size", 17)
	brand.add_theme_color_override("font_color", Color(0.92, 0.93, 0.95))
	bar.add_child(brand)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(18, 0)
	bar.add_child(gap)
	var accent := _accent()
	var group := ButtonGroup.new()
	for p in PAGES:
		var pd: Dictionary = p
		var b := Button.new()
		b.text = String(pd["title"])
		b.tooltip_text = String(pd["tip"])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_stylebox_override("normal", _flat(Color(0, 0, 0, 0)))
		b.add_theme_stylebox_override("hover", _flat(Color(1, 1, 1, 0.06)))
		b.add_theme_stylebox_override("pressed", _flat(Color(1, 1, 1, 0.09), accent))
		b.add_theme_stylebox_override("hover_pressed", _flat(Color(1, 1, 1, 0.12), accent))
		b.add_theme_color_override("font_color", Color(0.66, 0.69, 0.74))
		b.add_theme_color_override("font_hover_color", Color(0.9, 0.92, 0.95))
		b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
		b.add_theme_color_override("font_hover_pressed_color", Color(1, 1, 1))
		var key := String(pd["key"])
		b.pressed.connect(func(): open_page(key))
		bar.add_child(b)
		_buttons[key] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var hint := Label.new()
	hint.text = "Ctrl+1 · 2 · 3  탭 바꾸기"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.5, 0.53, 0.58))
	bar.add_child(hint)

	# 공통 설정 줄 — 세 탭이 같이 쓰는 캐릭터 프리셋 · 세트 목록
	var ctx_panel := PanelContainer.new()
	var cb := StyleBoxFlat.new()
	cb.bg_color = Color(0.15, 0.16, 0.19)
	cb.content_margin_left = 12
	cb.content_margin_right = 12
	cb.content_margin_top = 5
	cb.content_margin_bottom = 5
	ctx_panel.add_theme_stylebox_override("panel", cb)
	root.add_child(ctx_panel)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 6)
	ctx_panel.add_child(crow)
	var cl := Label.new()
	cl.text = "공통 설정"
	cl.add_theme_color_override("font_color", accent)
	cl.tooltip_text = "세 탭이 같이 쓰는 설정. 여기서 한 번 고르면 캐릭터 · 장비 · 복장 탭이 모두 이 캐릭터와 이 세트를 본다."
	cl.mouse_filter = Control.MOUSE_FILTER_STOP
	crow.add_child(cl)
	_preset_edit = _ctx_field(crow, "캐릭터 프리셋", "캐릭터 모델 · 도트화 값 · 동작 세트가 든 프리셋(.tres). 캐릭터 탭에서 저장/불러오면 여기도 바뀐다. 바꾸면 그 프리셋의 출력 폴더에서 세트 목록도 찾아 넣는다.",
		"*.tres ; 캐릭터 프리셋", func(p): set_context({"preset": p}))
	_sets_edit = _ctx_field(crow, "세트 목록", "캐릭터 탭이 세트를 구울 때 만드는 sets.json. 장비 · 복장은 이 세트들에 맞춰 굽는다.",
		"*.json ; 세트 목록(sets.json)", func(p): set_context({"sets": p}))
	_ctx_note = Label.new()
	_ctx_note.add_theme_font_size_override("font_size", 12)
	_ctx_note.add_theme_color_override("font_color", Color(0.62, 0.65, 0.7))
	_ctx_note.clip_text = true
	_ctx_note.custom_minimum_size = Vector2(160, 0)
	_ctx_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(_ctx_note)
	# 미리보기 배경(10-08 사용자 요청) — ① ② ③ 미리보기에 같이. 자홍이면 조각 사이 구멍 · 비침이 잘 보인다
	var bl := Label.new()
	bl.text = "미리보기 배경"
	bl.tooltip_text = "① 캐릭터 · ② 장비 · ③ 복장 미리보기의 바탕색. 자홍처럼 튀는 색으로 두면 조각 사이 구멍 · 비침이 잘 보인다. 굽는 그림에는 안 들어간다."
	bl.mouse_filter = Control.MOUSE_FILTER_STOP
	crow.add_child(bl)
	_bg_pick = ColorPickerButton.new()
	_bg_pick.custom_minimum_size = Vector2(36, 0)
	_bg_pick.edit_alpha = false
	_bg_pick.tooltip_text = bl.tooltip_text
	_bg_pick.color = Color(0.36, 0.42, 0.36)
	_bg_pick.color_changed.connect(func(c): set_preview_bg(c))
	crow.add_child(_bg_pick)
	for preset in [["자홍", Color(1, 0, 1)], ["기본", Color(0, 0, 0, 0)]]:
		var pb := Button.new()
		pb.text = String(preset[0])
		pb.flat = true
		pb.tooltip_text = "미리보기 배경을 %s 으로" % preset[0] if preset[0] != "기본" else "미리보기 배경을 원래 색으로"
		var pc: Color = preset[1]
		pb.pressed.connect(func(): set_preview_bg(pc))
		crow.add_child(pb)

	var margin := MarginContainer.new()
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	root.add_child(margin)
	_body = Control.new()
	_body.clip_contents = true
	margin.add_child(_body)


func _ctx_field(parent: Control, label: String, tip: String, filter: String, on_pick: Callable) -> LineEdit:
	var l := Label.new()
	l.text = "  " + label
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(l)
	var e := LineEdit.new()
	e.custom_minimum_size = Vector2(250, 0)
	e.tooltip_text = tip
	e.text_submitted.connect(func(t): on_pick.call(String(t).strip_edges()))
	e.focus_exited.connect(func(): on_pick.call(e.text.strip_edges()))
	parent.add_child(e)
	var b := Button.new()
	b.text = "…"
	b.tooltip_text = "고르기"
	b.pressed.connect(func(): _pick_file(filter, label, on_pick))
	parent.add_child(b)
	return e


func _pick_file(filter: String, title_text: String, on_pick: Callable) -> void:
	if not Engine.is_editor_hint():
		return
	var dlg := EditorFileDialog.new()
	dlg.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dlg.access = EditorFileDialog.ACCESS_RESOURCES
	dlg.filters = PackedStringArray([filter])
	dlg.title = "%s — Dot Rigger" % title_text
	dlg.file_selected.connect(func(p):
		dlg.queue_free()
		on_pick.call(String(p)))
	dlg.canceled.connect(func(): dlg.queue_free())
	add_child(dlg)
	dlg.popup_file_dialog()


# ---------------------------------------------------------------- 공통 설정

## 처음 한 번: 지난번 값 → 없으면 프로젝트에서 찾은 프리셋 · 그 출력 폴더의 sets.json
## 미리보기 배경 — 만든 탭 모두에 적용하고 기억한다(c.a == 0 = 기본)
func set_preview_bg(c: Color) -> void:
	_preview_bg = c
	if _bg_pick != null and c.a > 0.0:
		_bg_pick.color = c
	for k in _pages.keys():
		(_pages[k] as DRPage).set_preview_bg(c)
	if Engine.is_editor_hint():
		EditorInterface.get_editor_settings().set_project_metadata(META_SECTION, "preview_bg", c.to_html(true) if c.a > 0.0 else "")


## 지난번 미리보기 배경 불러오기(open 때)
func _restore_preview_bg() -> void:
	if not Engine.is_editor_hint():
		return
	var h := String(EditorInterface.get_editor_settings().get_project_metadata(META_SECTION, "preview_bg", ""))
	if h != "" and Color.html_is_valid(h):
		set_preview_bg(Color.html(h))


func _init_context() -> void:
	var preset := ""
	var sets := ""
	if Engine.is_editor_hint():
		var es := EditorInterface.get_editor_settings()
		preset = String(es.get_project_metadata(META_SECTION, "preset", ""))
		sets = String(es.get_project_metadata(META_SECTION, "sets", ""))
	if preset == "" or not FileAccess.file_exists(preset):
		preset = DROutfitWindow._default_preset()
	if sets == "" or not FileAccess.file_exists(sets):
		sets = _sets_for_preset(preset)
	_ctx = {"preset": preset, "sets": sets}
	_show_context()


## 프리셋의 출력 폴더에 있는 sets.json (없으면 res://puppet/sets.json)
static func _sets_for_preset(preset: String) -> String:
	if preset != "" and FileAccess.file_exists(preset):
		var p := load(preset) as DRPreset
		if p != null and p.out_dir != "":
			return p.out_dir.path_join("sets.json")
	return "res://puppet/sets.json"


func get_context() -> Dictionary:
	return _ctx.duplicate()


## 공통 설정을 바꾼다(창의 칸 · 페이지가 알린 것). 바뀐 것이 있으면 기억하고 모든 페이지에 전한다(from 은 빼고).
func set_context(delta: Dictionary, from: DRPage = null) -> void:
	var changed := PackedStringArray()
	if delta.has("preset") and String(delta["preset"]) != "" and String(delta["preset"]) != String(_ctx["preset"]):
		_ctx["preset"] = String(delta["preset"])
		changed.append("preset")
		if not delta.has("sets"):      # 프리셋이 바뀌면 그 프리셋의 세트 목록으로
			var s := _sets_for_preset(String(_ctx["preset"]))
			if s != String(_ctx["sets"]) and FileAccess.file_exists(s):
				_ctx["sets"] = s
				changed.append("sets")
	if delta.has("sets") and String(delta["sets"]) != "" and String(delta["sets"]) != String(_ctx["sets"]):
		_ctx["sets"] = String(delta["sets"])
		changed.append("sets")
	if bool(delta.get("rebaked", false)):
		changed.append("rebaked")
	_show_context()
	if changed.is_empty():
		return
	if Engine.is_editor_hint():
		var es := EditorInterface.get_editor_settings()
		es.set_project_metadata(META_SECTION, "preset", _ctx["preset"])
		es.set_project_metadata(META_SECTION, "sets", _ctx["sets"])
	for k in _pages.keys():
		var pg := _pages[k] as DRPage
		if pg != from:
			pg.apply_context(_ctx.duplicate(), changed)


func _show_context() -> void:
	if _preset_edit == null:
		return
	_preset_edit.text = String(_ctx["preset"])
	_sets_edit.text = String(_ctx["sets"])
	var notes := PackedStringArray()
	var preset := String(_ctx["preset"])
	if preset == "" or not FileAccess.file_exists(preset):
		notes.append("⚠ 프리셋이 없습니다 — ① 캐릭터 탭에서 모델을 불러와 `프리셋 저장`")
	else:
		var p := load(preset) as DRPreset
		if p != null:
			notes.append("모델 %s" % p.model_path.get_file())
	var sets := String(_ctx["sets"])
	if sets == "" or not FileAccess.file_exists(sets):
		notes.append("⚠ 세트 목록이 없습니다 — ① 캐릭터 탭에서 세트로 담고 굽기")
	else:
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(sets))
		if v is Dictionary:
			var names := PackedStringArray()
			for s in (v as Dictionary).get("sets", []):
				names.append(String((s as Dictionary).get("name", "")))
			notes.append("세트 %d개 (%s)" % [names.size(), ", ".join(names)])
	_ctx_note.text = "   " + " · ".join(notes)
	_ctx_note.tooltip_text = _ctx_note.text.strip_edges()


## 창을 띄운다 — key 를 안 주면 마지막에 보던 탭(처음이면 ① 유닛). 예전에 기억한 "rig"(2D 캐릭터 굽기)는 ① 유닛으로
func open(key: String = "") -> void:
	if key == "":
		key = _current
	if key == "" and Engine.is_editor_hint():
		key = String(EditorInterface.get_editor_settings().get_project_metadata(META_SECTION, "page", "unit"))
	if not _buttons.has(key):
		key = "unit"
	if not visible:
		_show_window()
	else:
		if mode == Window.MODE_MINIMIZED:
			mode = Window.MODE_WINDOWED
		_rescue_if_offscreen()
		grab_focus()
	if not _bg_restored:
		_bg_restored = true
		_restore_preview_bg()
	open_page(key)


# ---------------------------------------------------------------- 창 자리

## 닫기 = 숨기기(작업 유지). 자리 · 크기 · 최대화 여부를 기억해 다음에 같은 모습으로 뜬다.
func _on_close() -> void:
	_save_placement()
	hide()


func _save_placement() -> void:
	if not Engine.is_editor_hint():
		return
	var es := EditorInterface.get_editor_settings()
	es.set_project_metadata(META_SECTION, "maximized", mode == Window.MODE_MAXIMIZED)
	if mode == Window.MODE_WINDOWED:
		es.set_project_metadata(META_SECTION, "rect", [position.x, position.y, size.x, size.y])


## 제목줄을 잡을 수 있는 자리인가 — 창 위쪽 가운데가 어느 모니터의 쓸 수 있는 영역 안에 있고, 제목줄(창 위 약 30px)이 그 위로 안 넘어가야 한다
static func _reachable(rect: Rect2i) -> bool:
	if rect.size.x < 200 or rect.size.y < 150:
		return false
	var grab := Vector2i(rect.position.x + rect.size.x / 2, rect.position.y)
	for s in DisplayServer.get_screen_count():
		var u := DisplayServer.screen_get_usable_rect(s)
		if u.has_point(grab) and rect.position.y - 30 >= u.position.y - 4:
			return true
	return false


## 띄우기 — 지난번 자리(잡을 수 있는 자리일 때만), 아니면 에디터가 있는 모니터 가운데
func _show_window() -> void:
	var rect := Rect2i()
	var was_max := false
	if Engine.is_editor_hint():
		var es := EditorInterface.get_editor_settings()
		var r: Array = es.get_project_metadata(META_SECTION, "rect", [])
		if r.size() == 4:
			rect = Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		was_max = bool(es.get_project_metadata(META_SECTION, "maximized", false))
	if _reachable(rect):
		popup(rect)
	else:
		popup_centered(size)
	_rescue_if_offscreen()
	if was_max:
		mode = Window.MODE_MAXIMIZED


## 그래도 제목줄을 못 잡는 자리면 에디터 창이 있는 모니터 가운데로 옮긴다(모니터 구성이 바뀌었을 때 등)
func _rescue_if_offscreen() -> void:
	if mode != Window.MODE_WINDOWED or _reachable(Rect2i(position, size)):
		return
	var u := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var par := get_parent()
	if par != null and par.get_window() != null:
		u = DisplayServer.screen_get_usable_rect(par.get_window().current_screen)
	var sz := Vector2i(mini(size.x, u.size.x - 40), mini(size.y, u.size.y - 80))
	size = sz
	position = u.position + (u.size - sz) / 2 + Vector2i(0, 15)


## 탭 바꾸기 — 처음 여는 페이지는 여기서 만든다
func open_page(key: String) -> void:
	if not _buttons.has(key):
		return
	for bk in _buttons.keys():      # 고른 탭만 눌린 모양(신호 없이 누르면 묶음이 나머지를 안 풀어 준다)
		(_buttons[bk] as Button).set_pressed_no_signal(bk == key)
	if not _pages.has(key):
		var page := _make_page(key)
		if page == null:
			return
		page.visible = false
		page.hosted = true
		_body.add_child(page)
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # 페이지가 창 안을 꽉 채우게(넣은 뒤에 해야 먹는다)
		_pages[key] = page
		page.context_changed.connect(func(d): set_context(d, page))
		if String(_ctx["preset"]) == "" and String(_ctx["sets"]) == "":
			_init_context()
		page.apply_context(_ctx.duplicate(), PackedStringArray(["preset", "sets"]))
		page.set_preview_bg(_preview_bg)
	for k in _pages.keys():
		var pg := _pages[k] as DRPage
		var on: bool = k == key
		if on:
			pg.set_page_active(true)
		pg.visible = on
		if not on:
			pg.set_page_active(false)
	_current = key
	title = "Dot Rigger — %s" % String((_pages[key] as DRPage).page_title)
	if Engine.is_editor_hint():
		EditorInterface.get_editor_settings().set_project_metadata(META_SECTION, "page", key)


func current_page() -> DRPage:
	return _pages.get(_current, null) as DRPage


func page(key: String) -> DRPage:
	return _pages.get(key, null) as DRPage


## Ctrl+1 · 2 · 3 = 탭 · Ctrl+Tab = 다음 탭
func _on_window_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed or k.echo or not k.ctrl_pressed or k.alt_pressed:
		return
	var idx := -1
	if k.keycode >= KEY_1 and k.keycode < KEY_1 + PAGES.size():
		idx = int(k.keycode - KEY_1)
	elif k.keycode == KEY_TAB:
		var cur := 0
		for i in PAGES.size():
			if String((PAGES[i] as Dictionary)["key"]) == _current:
				cur = i
		idx = (cur + (PAGES.size() - 1 if k.shift_pressed else 1)) % PAGES.size()
	if idx >= 0:
		open_page(String((PAGES[idx] as Dictionary)["key"]))
		set_input_as_handled()
