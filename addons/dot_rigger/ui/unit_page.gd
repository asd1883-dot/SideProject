@tool
extends DRPage
class_name DRUnitPage

## ① 유닛 탭(10-16, 3D 노선) — 예전 ① 캐릭터 굽기(2D 컷아웃)를 갈음한다.
## 유닛 = 유닛 프리팹(루트가 DRCharacter3D 인 씬). 기본형 군인(game/units/soldier_base.tscn)을 부모로, 다른 유닛은 그것을 상속한 자식 씬 —
## 자식은 바꾼 칸만 따로 갖고 나머지는 부모를 따라간다(유니티 프리팹 변형). 이 탭과 인스펙터는 **같은 것**(열린 유닛 씬의 루트)을 고친다.
##
##   왼쪽: 유닛 목록(부모 → 자식 나무) · [+ 자식 유닛] · [씬 열기] · [저장] · 모습 칸(몸 · 상의 · 하의 · 동작 표 · 키 — 자식은 "부모 값 / 바꿈" + ↺)
##         · 장비 요약(뼈 소켓 → 무기 · 헬멧 — 고치기는 ② 장비 탭 · 씬 독 · 기즈모. 예전 "무기" 칸(weapon_asset)은 10-16 소켓 방식으로 갈음)
##   가운데: 3D 도트 미리보기(게임과 같은 DRDotView3D · 초당 12번) — 세트 · 상태를 고르면 동작 표대로 비중을 뽑아 튼다 · 다시 고르기 · 좌우 · 도트 크기
##   오른쪽: 그 유닛의 동작 표(DRMotionTableEditor — 인스펙터와 같은 화면: 세트 → 상태 → 동작 · % · 상하체 합성 · 3D 동작 내보내기)
##
## 에디터에서는 유닛을 고르면 그 씬을 에디터에 열고, 칸을 바꾸면 되돌리기(Ctrl+Z)에 남긴다 → 씬에 * 표시, [저장] = 씬 저장.
## 인스펙터 · 되돌리기로 바뀐 것은 0.3 초마다 루트 값을 다시 읽어 이 탭에도 반영한다. 에디터 밖(검사)에서는 인스턴스를 바로 고친다.

const UNITS_DIR := "res://game/units"
const CHAR_SCRIPT := "res://addons/dot_rigger/runtime/dr_character_3d.gd"
const POLL_SEC := 0.3
## 모습 칸(루트 DRCharacter3D 의 칸) — 이름 · 보이는 이름 · 설명
const FIELDS := [
	["body_model", "몸", "기본 몸(사람 몸 glb). 옷을 안 입힌 슬롯은 이 몸(내복)"],
	["outfit_top", "상의", "상의 복장(③ 복장 탭이 만든 outfit.json). (내복) = 안 입힘"],
	["outfit_bottom", "하의", "하의 복장(outfit.json). (내복) = 안 입힘"],
	["motions", "동작 표", "세트 → 상태 → 동작(비중 % · 상하체 합성). 오른쪽에서 고친다"],
	["height_m", "키", "모델을 이 키(m)로 맞춘다"],
]

var _tree: Tree
var _units: Dictionary = {}          # 경로 -> {name, parent}
var _sel_path := ""
var _root: DRCharacter3D = null      # 고치는 유닛의 루트(에디터 = 열린 씬의 루트, 밖 = 인스턴스)
var _owns_root := false              # 밖에서 만든 인스턴스면 바꿀 때 지운다
var _parent_vals: Dictionary = {}    # 부모 유닛의 칸 값(자식이면) — 바꿈 표시 · ↺
var _fields: Dictionary = {}         # 칸 -> {ctl, mark, revert}
var _child_name: LineEdit
var _status: Label
var _equip_lbl: Label
var _sig := ""
var _xsig := ""                      # 장비 자리(기즈모 · ② 탭) — 바뀌면 미리보기 사본의 자리만 옮긴다
var _poll := 0.0
var _active := true
# 미리보기
var _pv_vp: SubViewport
var _ground: Node2D
var _dots: DRDotView3D
var _prev_ch: DRCharacter3D = null
var _state_ob: OptionButton
var _now: Label
var _play_btn: Button
var _size: HSlider
var _playing := true
var _facing := 1
var _acc := 0.0
var _pv_state := ""
var _pv_reroll := false
var _dot_ob: OptionButton
## 도트 느낌(게임과 같은 파일 — DRDotStyle.DEFAULT_PATH)
var _style: DRDotStyle
# 동작 표
var _motion_ed: DRMotionTableEditor


func _init() -> void:
	page_title = "유닛 (3D)"
	_style = DRDotStyle.load_default()
	_build_ui()
	_apply_style()


func _ready() -> void:
	scan_units()
	if _sel_path == "" and not _units.is_empty():
		var first := UNITS_DIR.path_join("soldier_base.tscn")
		select_unit(first if _units.has(first) else String(_units.keys()[0]))


func _exit_tree() -> void:
	_drop_root()


func set_page_active(on: bool) -> void:
	super(on)
	_active = on
	if _pv_vp != null:
		_pv_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if _dots != null:
		_dots.visible = on


# ───────────── 틀 ─────────────

func _build_ui() -> void:
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(split)

	# 왼쪽 — 유닛 목록 · 모습 칸
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	split.add_child(left)
	var t := Label.new()
	t.text = "유닛 프리팹 (부모 → 자식)"
	left.add_child(t)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.custom_minimum_size = Vector2(0, 170)
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(func() -> void:
		var it := _tree.get_selected()
		if it != null:
			select_unit(String(it.get_metadata(0))))
	left.add_child(_tree)
	var crow := HBoxContainer.new()
	left.add_child(crow)
	_child_name = LineEdit.new()
	_child_name.placeholder_text = "새 자식 유닛 이름(예: 기관총사수)"
	_child_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_child_name.text_submitted.connect(func(_t: String) -> void: new_child_unit(_child_name.text))
	crow.add_child(_child_name)
	var cb := Button.new()
	cb.text = "+ 자식 유닛"
	cb.tooltip_text = "고른 유닛을 부모로 상속한 새 유닛 씬을 만든다(바꾼 칸만 따로 갖고 나머지는 부모를 따라감)"
	cb.pressed.connect(func() -> void: new_child_unit(_child_name.text))
	crow.add_child(cb)
	var brow := HBoxContainer.new()
	left.add_child(brow)
	for b in [["씬 열기", "에디터에 이 유닛 씬을 연다(인스펙터에서도 같은 칸이 보인다)", _on_open_scene],
			["저장", "이 유닛 씬(과 동작 표)을 저장", _on_save],
			["다시 찾기", "game/units 의 유닛 씬을 다시 찾는다", scan_units]]:
		var btn := Button.new()
		btn.text = String(b[0])
		btn.tooltip_text = String(b[1])
		btn.pressed.connect(b[2])
		brow.add_child(btn)
	left.add_child(HSeparator.new())
	var mt := Label.new()
	mt.text = "모습"
	left.add_child(mt)
	var grid := GridContainer.new()
	grid.columns = 3
	left.add_child(grid)
	for f in FIELDS:
		_add_field(grid, String(f[0]), String(f[1]), String(f[2]))
	var el := Label.new()
	el.text = "장비"
	el.tooltip_text = "뼈 소켓(BoneAttachment3D)에 꽂은 장비 — 오른손 = 무기(왼손은 무기 위 표지에 IK), 머리 = 헬멧 …"
	grid.add_child(el)
	_equip_lbl = Label.new()
	_equip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_equip_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equip_lbl.custom_minimum_size = Vector2(180, 0)
	_equip_lbl.add_theme_font_size_override("font_size", 12)
	grid.add_child(_equip_lbl)
	var eb := Button.new()
	eb.text = "② 탭"
	eb.tooltip_text = "② 장비 탭에서 이 유닛의 소켓 · 장비를 고친다(같은 유닛을 고른 채로 연다)"
	eb.pressed.connect(_on_open_equip)
	grid.add_child(eb)
	var own := Button.new()
	own.text = "이 유닛만의 동작 표로 복사"
	own.tooltip_text = "지금 동작 표를 이 유닛 이름으로 복사해(game/units/<유닛>_motions.tres · 3D 동작 묶음도 따로) 이 유닛에만 쓴다 — 자식 유닛이 동작을 따로 갖고 싶을 때"
	own.pressed.connect(_on_own_table)
	left.add_child(own)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(0.7, 0.72, 0.75))
	left.add_child(_status)

	var right_split := HSplitContainer.new()
	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right_split)

	# 가운데 — 미리보기
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.custom_minimum_size = Vector2(320, 0)
	right_split.add_child(mid)
	var pvc := SubViewportContainer.new()
	pvc.stretch = true
	pvc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pvc.custom_minimum_size = Vector2(300, 300)
	mid.add_child(pvc)
	_pv_vp = SubViewport.new()
	_pv_vp.transparent_bg = false
	_pv_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	pvc.add_child(_pv_vp)
	var bg := ColorRect.new()
	bg.color = Color(0.42, 0.47, 0.42)
	bg.size = Vector2(4096, 4096)
	_pv_vp.add_child(bg)
	_ground = Node2D.new()
	_ground.draw.connect(_draw_ground)
	_pv_vp.add_child(_ground)
	_dots = DRDotView3D.new()
	_dots.px_per_m = 150.0
	_pv_vp.add_child(_dots)
	var ctl := HFlowContainer.new()
	mid.add_child(ctl)
	var sl := Label.new()
	sl.text = "상태"
	ctl.add_child(sl)
	_state_ob = OptionButton.new()
	_state_ob.custom_minimum_size = Vector2(150, 0)
	_state_ob.tooltip_text = "미리 볼 상태(동작 표의 세트 → 상태). 고르면 그 상태의 동작을 비중대로 하나 뽑아 튼다"
	_state_ob.item_selected.connect(func(i: int) -> void: play_state(_state_ob.get_item_text(i)))
	ctl.add_child(_state_ob)
	var again := Button.new()
	again.text = "다시 고르기"
	again.tooltip_text = "같은 상태에서 비중대로 다시 뽑기"
	again.pressed.connect(func() -> void: play_state(_pv_state))
	ctl.add_child(again)
	_play_btn = Button.new()
	_play_btn.text = "⏸ 멈춤"
	_play_btn.pressed.connect(func() -> void:
		_playing = not _playing
		_play_btn.text = "⏸ 멈춤" if _playing else "▶ 재생")
	ctl.add_child(_play_btn)
	var lf := Button.new()
	lf.text = "◀"
	lf.tooltip_text = "왼쪽 보기"
	lf.pressed.connect(func() -> void: _set_facing(-1))
	ctl.add_child(lf)
	var rf := Button.new()
	rf.text = "▶"
	rf.tooltip_text = "오른쪽 보기"
	rf.pressed.connect(func() -> void: _set_facing(1))
	ctl.add_child(rf)
	var dl := Label.new()
	dl.text = "도트"
	ctl.add_child(dl)
	_dot_ob = OptionButton.new()
	for i in range(1, 9):
		_dot_ob.add_item("%d px" % i, i)
	_dot_ob.tooltip_text = "도트 하나 = 화면 몇 픽셀(1 = 도트화 끔) — 도트 느낌 설정(게임과 같은 파일)"
	_dot_ob.item_selected.connect(func(i: int) -> void:
		_style.dot_px = _dot_ob.get_item_id(i)
		_apply_style())
	ctl.add_child(_dot_ob)
	_size = HSlider.new()
	_size.min_value = 60.0
	_size.max_value = 320.0
	_size.value = 150.0
	_size.custom_minimum_size = Vector2(110, 0)
	_size.tooltip_text = "미리보기 크기(1 m = 몇 px)"
	_size.value_changed.connect(func(v: float) -> void:
		_dots.px_per_m = v
		_ground.queue_redraw())
	ctl.add_child(_size)
	_now = Label.new()
	_now.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_now.add_theme_font_size_override("font_size", 12)
	mid.add_child(_now)
	_build_style_panel(mid)

	# 오른쪽 — 동작 표
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(430, 0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_split.add_child(sc)
	_motion_ed = DRMotionTableEditor.new()
	_motion_ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_motion_ed.exported.connect(_on_exported)
	sc.add_child(_motion_ed)


## 도트 느낌(10-16) — 예전 ① 탭의 도트화 · 외곽선 칸(픽셀 퍼펙트 등)을 3D 로. 게임 화면과 같은 파일(DRDotStyle.DEFAULT_PATH)
func _build_style_panel(parent: Control) -> void:
	var head := Button.new()
	head.flat = true
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.text = "▸ 도트 느낌(외곽선 · 픽셀 퍼펙트 · 명암) — 게임과 같은 설정"
	parent.add_child(head)
	var box := VBoxContainer.new()
	box.visible = false
	parent.add_child(box)
	head.pressed.connect(func() -> void:
		box.visible = not box.visible
		head.text = ("▾ " if box.visible else "▸ ") + head.text.substr(2))
	var g := GridContainer.new()
	g.columns = 4
	box.add_child(g)
	var s := _style
	_style_ctl(g, "외곽선", "외곽선 두께(도트, 0 = 없음)", _opt_ctl(["없음", "1 도트"], s.outline_px, func(i: int) -> void: s.outline_px = i))
	_style_ctl(g, "선 방식", "카툰 = 한 색 · 픽셀 퍼펙트 = 선 도트마다 바로 옆 몸 도트 색을 톤만큼 어둡게(예전 2D 와 같은 두 방식)",
		_opt_ctl(["카툰 (한 색)", "픽셀 퍼펙트"], s.outline_style, func(i: int) -> void: s.outline_style = i))
	var cp := ColorPickerButton.new()
	cp.color = s.outline_color
	cp.custom_minimum_size = Vector2(60, 0)
	cp.color_changed.connect(func(c: Color) -> void:
		s.outline_color = c
		_apply_style())
	_style_ctl(g, "선 색", "카툰일 때 선 색", cp)
	_style_ctl(g, "톤", "픽셀 퍼펙트일 때 어둡게 하는 정도(0 = 같은 색 · 1 = 검정)", _num_ctl(0.0, 1.0, 0.05, s.outline_tone, func(v: float) -> void: s.outline_tone = v))
	var inner := CheckBox.new()
	inner.text = "사이 선"
	inner.button_pressed = s.inner_outline
	inner.toggled.connect(func(on: bool) -> void:
		s.inner_outline = on
		_apply_style())
	_style_ctl(g, "겹침", "겹친 캐릭터 사이에도 선", inner)
	_style_ctl(g, "각도", "카메라가 내려다보는 각(도)", _num_ctl(1.0, 45.0, 0.5, s.pitch_deg, func(v: float) -> void: s.pitch_deg = v))
	_style_ctl(g, "초당 장수", "동작을 초당 몇 번 새로 그리나 — 12 = 예전 2D 퍼펫과 같은 끊는 맛(0 = 매 프레임)",
		_num_ctl(0.0, 60.0, 1.0, s.step_hz, func(v: float) -> void: s.step_hz = v))
	_style_ctl(g, "명암 단계", "명암 단계 수", _num_ctl(2.0, 8.0, 1.0, float(s.light_bands), func(v: float) -> void: s.light_bands = int(v)))
	_style_ctl(g, "어두운 면", "가장 어두운 면의 밝기(앰비언트)", _num_ctl(0.0, 1.0, 0.05, s.ambient, func(v: float) -> void: s.ambient = v))
	_style_ctl(g, "빛 감싸기", "빛이 옆면까지 감싸는 정도", _num_ctl(0.0, 1.0, 0.05, s.light_wrap, func(v: float) -> void: s.light_wrap = v))
	_style_ctl(g, "가장자리 빛", "림 라이트(0 = 끔)", _num_ctl(0.0, 1.0, 0.05, s.rim, func(v: float) -> void: s.rim = v))
	_style_ctl(g, "옷 속 밝기", "소매 · 깃 속(안쪽 면) 밝기", _num_ctl(0.0, 1.0, 0.05, s.inside_shade, func(v: float) -> void: s.inside_shade = v))
	for axis in 3:
		var a := axis
		_style_ctl(g, "빛 %s" % ["X", "Y", "Z"][a], "빛이 오는 쪽(세상 좌표, +Z = 화면 앞쪽)",
			_num_ctl(-1.0, 1.0, 0.05, s.light_dir[a], func(v: float) -> void: s.light_dir[a] = v))
	var row := HBoxContainer.new()
	box.add_child(row)
	var sv := Button.new()
	sv.text = "도트 느낌 저장"
	sv.tooltip_text = "게임 화면도 이 값으로(%s)" % DRDotStyle.DEFAULT_PATH
	sv.pressed.connect(func() -> void:
		var err := ResourceSaver.save(_style, DRDotStyle.DEFAULT_PATH)
		if Engine.is_editor_hint() and err == OK:
			EditorInterface.get_resource_filesystem().update_file(DRDotStyle.DEFAULT_PATH)
		_status.text = ("도트 느낌 저장: %s" % DRDotStyle.DEFAULT_PATH) if err == OK else "저장 실패(%s)" % error_string(err))
	row.add_child(sv)


func _style_ctl(g: GridContainer, label: String, tip: String, ctl: Control) -> void:
	var l := Label.new()
	l.text = label
	l.tooltip_text = tip
	l.add_theme_font_size_override("font_size", 12)
	g.add_child(l)
	ctl.tooltip_text = tip
	g.add_child(ctl)


func _opt_ctl(items: Array, cur: int, on_pick: Callable) -> OptionButton:
	var ob := OptionButton.new()
	for it in items:
		ob.add_item(String(it))
	ob.select(clampi(cur, 0, items.size() - 1))
	ob.item_selected.connect(func(i: int) -> void:
		on_pick.call(i)
		_apply_style())
	return ob


func _num_ctl(lo: float, hi: float, step: float, cur: float, on_set: Callable) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = lo
	sp.max_value = hi
	sp.step = step
	sp.custom_minimum_size = Vector2(76, 0)
	sp.set_value_no_signal(cur)
	sp.value_changed.connect(func(v: float) -> void:
		on_set.call(v)
		_apply_style())
	return sp


## 도트 느낌을 미리보기 도트 창 · 캐릭터 재질(공유)에 넣는다
func _apply_style() -> void:
	if _style == null:
		return
	_style.apply_to(_dots)
	_style.apply_shading()
	if _dot_ob != null:
		for i in _dot_ob.item_count:
			if _dot_ob.get_item_id(i) == _style.dot_px:
				_dot_ob.select(i)


func _add_field(grid: GridContainer, prop: String, label: String, tip: String) -> void:
	var l := Label.new()
	l.text = label
	l.tooltip_text = tip
	grid.add_child(l)
	var ctl: Control
	if prop == "height_m":
		var sp := SpinBox.new()
		sp.min_value = 0.5
		sp.max_value = 2.5
		sp.step = 0.01
		sp.suffix = "m"
		sp.value_changed.connect(func(v: float) -> void: _set_prop(prop, v))
		ctl = sp
	else:
		var ob := OptionButton.new()
		ob.fit_to_longest_item = false
		ob.clip_text = true
		ob.item_selected.connect(func(i: int) -> void: _on_pick(prop, ob, i))
		ctl = ob
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctl.custom_minimum_size = Vector2(180, 0)
	ctl.tooltip_text = tip
	grid.add_child(ctl)
	var hb := HBoxContainer.new()
	var mark := Label.new()
	mark.add_theme_font_size_override("font_size", 11)
	hb.add_child(mark)
	var rv := Button.new()
	rv.text = "↺"
	rv.flat = true
	rv.tooltip_text = "부모 값으로 되돌리기"
	rv.pressed.connect(func() -> void: _set_prop(prop, _parent_vals.get(prop)))
	hb.add_child(rv)
	grid.add_child(hb)
	_fields[prop] = {"ctl": ctl, "mark": mark, "revert": rv}


# ───────────── 유닛 목록 ─────────────

## game/units 의 유닛 씬(루트가 DRCharacter3D 이거나 유닛을 상속한 씬)을 찾아 부모 → 자식 나무로
func scan_units() -> void:
	_units = {}
	var infos := {}
	var d := DirAccess.open(UNITS_DIR)
	if d != null:
		for f in d.get_files():
			if String(f).get_extension() == "tscn":
				var p := UNITS_DIR.path_join(String(f))
				var inf := scene_info(p)
				if not inf.is_empty():
					infos[p] = inf
	for p in infos.keys():
		if _is_unit(p, infos, 0):
			_units[p] = infos[p]
	_fill_tree()


static func _is_unit(p: String, infos: Dictionary, depth: int) -> bool:
	if not infos.has(p) or depth > 16:
		return false
	var inf: Dictionary = infos[p]
	if bool(inf["is_char"]):
		return true
	var par := String(inf["parent"])
	return par != "" and _is_unit(par, infos, depth + 1)


## 씬 파일의 루트 이름 · 부모 씬(상속이면) · 루트 스크립트가 DRCharacter3D 인지 — 글로 읽는다(씬을 만들지 않고)
static func scene_info(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var ext := {}
	var re := RegEx.new()
	re.compile("\\[ext_resource[^\\]]*?path=\"([^\"]+)\"[^\\]]*?id=\"([^\"]+)\"")
	for m in re.search_all(txt):
		ext[m.get_string(2)] = m.get_string(1)
	var rn := RegEx.new()
	rn.compile("\\[node name=\"([^\"]+)\"([^\\]]*)\\]")
	var mn := rn.search(txt)
	if mn == null:
		return {}
	var parent := ""
	var ri := RegEx.new()
	ri.compile("instance=ExtResource\\(\"([^\"]+)\"\\)")
	var mi := ri.search(mn.get_string(2))
	if mi != null:
		parent = String(ext.get(mi.get_string(1), ""))
	var body := txt.substr(mn.get_end())
	var cut := body.find("\n[")
	var root_body := body.substr(0, cut) if cut >= 0 else body
	var rs := RegEx.new()
	rs.compile("script = ExtResource\\(\"([^\"]+)\"\\)")
	var ms := rs.search(root_body)
	var is_char := ms != null and String(ext.get(ms.get_string(1), "")) == CHAR_SCRIPT
	return {"name": mn.get_string(1), "parent": parent, "is_char": is_char}


func _fill_tree() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var items := {}
	var paths := _units.keys()
	paths.sort()
	var guard := 0
	while items.size() < paths.size() and guard < 32:     # 부모가 먼저 들어가게 여러 번 훑는다
		guard += 1
		for p in paths:
			if items.has(p):
				continue
			var par := String((_units[p] as Dictionary)["parent"])
			if par != "" and _units.has(par) and not items.has(par):
				continue
			var it := _tree.create_item(items[par] if items.has(par) else root)
			it.set_text(0, "%s   (%s)" % [(_units[p] as Dictionary)["name"], String(p).get_file()])
			it.set_metadata(0, p)
			it.set_tooltip_text(0, p + ("\n부모: " + par if par != "" else "\n맨 위 부모"))
			items[p] = it
			if p == _sel_path:
				it.select(0)


# ───────────── 고르기 · 칸 ─────────────

## 그 유닛을 고른다 — 에디터면 그 씬을 에디터에 열고 열린 루트를 고친다
func select_unit(path: String) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	_drop_root()
	_sel_path = path
	var root: DRCharacter3D = null
	if Engine.is_editor_hint() and is_inside_tree():
		EditorInterface.open_scene_from_path(path)
		var er := EditorInterface.get_edited_scene_root()
		if er != null and er.scene_file_path == path:
			root = er as DRCharacter3D
	if root == null:
		var ps := load(path) as PackedScene
		root = ps.instantiate(PackedScene.GEN_EDIT_STATE_MAIN) as DRCharacter3D if ps != null else null
		_owns_root = root != null
	_root = root
	if _root == null:
		_status.text = "⚠ 유닛 루트가 DRCharacter3D 가 아닙니다: " + path
		return
	_parent_vals = _values_of_parent(path)
	_sig = ""
	_refresh_all()
	for it in _all_items(_tree.get_root()):
		if String(it.get_metadata(0)) == path:
			it.select(0)
	_status.text = "%s — %s" % [path.get_file(), ("부모 %s 를 상속" % String((_units.get(path, {}) as Dictionary).get("parent", "")).get_file()) if not _parent_vals.is_empty() else "맨 위 부모(기본형)"]


func _all_items(it: TreeItem) -> Array:
	var out: Array = []
	if it == null:
		return out
	var c := it.get_first_child()
	while c != null:
		out.append(c)
		out.append_array(_all_items(c))
		c = c.get_next()
	return out


func _drop_root() -> void:
	if _owns_root and _root != null and is_instance_valid(_root):
		_root.free()
	_root = null
	_owns_root = false


## 부모 유닛의 칸 값(자식일 때만) — 부모 씬을 만들기만 하고(트리에 안 넣어 조립 안 함) 값을 읽는다
func _values_of_parent(path: String) -> Dictionary:
	var par := String((_units.get(path, {}) as Dictionary).get("parent", ""))
	if par == "" or not ResourceLoader.exists(par):
		return {}
	var inst := (load(par) as PackedScene).instantiate()
	var out := {}
	for f in FIELDS:
		out[String(f[0])] = inst.get(String(f[0]))
	inst.free()
	return out


func _root_sig() -> String:
	if _root == null or not is_instance_valid(_root):
		return ""
	var m: Resource = _root.motions
	return "%s|%s|%s|%s|%.3f|%s" % [_root.body_model, _root.outfit_top, _root.outfit_bottom,
		str(m.get_instance_id()) if m != null else "-", _root.height_m, _equip_walk(false)]


## 유닛의 받침(소켓 · 받침대) · 장비 노드(루트가 가진 것 — 안에서 조립한 몸은 주인이 없어 빠진다)를 훑어
## xform = false → 구조(경로 · 뼈 · 받침 방식 · 모델 씬 · 보이기 · 표지 손 — 바뀌면 다시 조립), true → 자리 · 손 비중 · 보간(바뀌면 사본 자리만)
func _equip_walk(xform: bool) -> String:
	var parts := PackedStringArray()
	for s in DRCharacter3D.find_anchors(_root):
		if s.owner != _root:
			continue
		var stack: Array[Node] = [s]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n.owner != _root:
				continue
			var gm := n as DRGripMount3D
			if xform:
				# 소켓 자리는 뼈가, 두 손 사이 받침대 자리는 두 손이 정한다(에디터에서 유닛 씬이 동작을 틀면 계속 바뀜) — 장비 · 표지 · 고정 받침대 자리만
				var driven := n is BoneAttachment3D or (gm != null and gm.mode == DRGripMount3D.Mode.HANDS)
				parts.append(str((n as Node3D).transform) if n is Node3D and not driven else "")
				if gm != null:
					parts.append("%s|%s|%s" % [str(gm.blend), str(gm.right_offset), str(gm.left_offset)])
				if n is DRHandTarget3D:
					parts.append(str((n as DRHandTarget3D).motion_weights) + str((n as DRHandTarget3D).weight))
			else:
				parts.append("%s|%s|%s|%s|%s" % [_root.get_path_to(n), (n as BoneAttachment3D).bone_name if n is BoneAttachment3D else ("mount%d" % int(gm.mode) if gm != null else ""),
					n.scene_file_path, str((n as Node3D).visible) if n is Node3D else "", str((n as DRHandTarget3D).side) if n is DRHandTarget3D else ""])
			stack.append_array(n.get_children())
	return ";".join(parts)


## 장비 요약 한 줄씩 — "오른손(RightHand) → kar98k · 왼손 표지" · "양손(두 손 사이) → mg42 · 왼손 · 오른손 표지". 숨긴 장비(자식 유닛이 부모 것을 가린 것)는 뺀다
func _equip_summary() -> String:
	var lines := PackedStringArray()
	for s in DRCharacter3D.find_anchors(_root):
		if s.owner != _root:
			continue
		var items := PackedStringArray()
		for c in s.get_children():
			if c is Node3D and (c as Node3D).visible:
				var marks := PackedStringArray()
				for side in 2:
					if DRCharacter3D.find_hand_marker(c, side) != null:
						marks.append(String(DRCharacter3D.SIDE_NAMES[side]))
				items.append(String(c.name) + (" · %s 표지" % " · ".join(marks) if not marks.is_empty() else ""))
		var where := (s as BoneAttachment3D).bone_name if s is BoneAttachment3D else \
			("두 손 사이" if (s as DRGripMount3D).mode == DRGripMount3D.Mode.HANDS else "땅 고정")
		lines.append("%s(%s) → %s" % [s.name, where, ", ".join(items) if not items.is_empty() else "(비어 있음)"])
	return "\n".join(lines) if not lines.is_empty() else "(없음 — 맨손)"


func _refresh_all() -> void:
	_sig = _root_sig()
	_xsig = _equip_walk(true)
	_fill_fields()
	_motion_ed.set_table(_root.motions)
	_rebuild_preview()


func _fill_fields() -> void:
	_fill_option("body_model", _files("res://source3d/characters", "glb"), "")
	_fill_option("outfit_top", _named_files("res://outfits", "outfit.json"), "(내복)")
	_fill_option("outfit_bottom", _named_files("res://outfits", "outfit.json"), "(내복)")
	_equip_lbl.text = _equip_summary()
	_fill_tables()
	var sp := _fields["height_m"]["ctl"] as SpinBox
	sp.set_value_no_signal(_root.height_m)
	for f in FIELDS:
		var prop := String(f[0])
		var mark := _fields[prop]["mark"] as Label
		var rv := _fields[prop]["revert"] as Button
		if _parent_vals.is_empty():
			mark.text = ""
			rv.visible = false
			continue
		var same := _same(_root.get(prop), _parent_vals.get(prop))
		mark.text = "부모 값" if same else "바꿈"
		mark.add_theme_color_override("font_color", Color(0.6, 0.62, 0.66) if same else Color(0.95, 0.75, 0.35))
		rv.visible = not same


static func _same(a: Variant, b: Variant) -> bool:
	if a is Resource or b is Resource:
		return a == b or (a != null and b != null and (a as Resource).resource_path == (b as Resource).resource_path and (a as Resource).resource_path != "")
	if a is float or b is float:
		return absf(float(a) - float(b)) < 0.0005
	return a == b


func _fill_option(prop: String, paths: PackedStringArray, empty_label: String) -> void:
	var ob := _fields[prop]["ctl"] as OptionButton
	ob.clear()
	var cur := String(_root.get(prop))
	if empty_label != "":
		ob.add_item(empty_label)
		ob.set_item_metadata(0, "")
	var found := cur == "" and empty_label != ""
	for p in paths:
		ob.add_item(_short(p))
		ob.set_item_metadata(ob.item_count - 1, p)
		ob.set_item_tooltip(ob.item_count - 1, p)
	if cur != "" and not paths.has(cur):
		ob.add_item("⚠ " + _short(cur))
		ob.set_item_metadata(ob.item_count - 1, cur)
	for i in ob.item_count:
		if String(ob.get_item_metadata(i)) == cur:
			ob.select(i)
			found = true
	if not found and ob.item_count > 0:
		ob.select(0)


func _fill_tables() -> void:
	var ob := _fields["motions"]["ctl"] as OptionButton
	ob.clear()
	var cur: Resource = _root.motions
	ob.add_item("(없음)")
	ob.set_item_metadata(0, "")
	var sel := 0
	var d := DirAccess.open(UNITS_DIR)
	if d != null:
		for f in d.get_files():
			var p := UNITS_DIR.path_join(String(f))
			if String(f).get_extension() != "tres":
				continue
			var r := load(p)
			if not (r is DRMotionTable):
				continue
			ob.add_item(String(f).get_basename())
			ob.set_item_metadata(ob.item_count - 1, p)
			if cur != null and cur.resource_path == p:
				sel = ob.item_count - 1
	if cur != null and sel == 0:
		ob.add_item("⚠ " + (cur.resource_path.get_file() if cur.resource_path != "" else "(내장 표)"))
		ob.set_item_metadata(ob.item_count - 1, cur.resource_path)
		sel = ob.item_count - 1
	ob.select(sel)


static func _short(p: String) -> String:
	var parts := p.trim_prefix("res://").split("/")
	return "/".join(parts.slice(maxi(parts.size() - 2, 0)))


## 폴더 아래(하위 폴더까지) 확장자 ext 파일
static func _files(dir: String, ext: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if String(f).get_extension().to_lower() == ext:
			out.append(dir.path_join(String(f)))
	for sub in d.get_directories():
		out.append_array(_files(dir.path_join(String(sub)), ext))
	return out


## 폴더 아래 이름이 file_name 인 파일(outfits/*/outfit.json)
static func _named_files(dir: String, file_name: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	if d.file_exists(file_name):
		out.append(dir.path_join(file_name))
	for sub in d.get_directories():
		out.append_array(_named_files(dir.path_join(String(sub)), file_name))
	return out


func _on_pick(prop: String, ob: OptionButton, i: int) -> void:
	var v: Variant = String(ob.get_item_metadata(i))
	if prop == "motions":
		v = load(String(v)) if String(v) != "" else null
	_set_prop(prop, v)


## 칸 하나 바꾸기 — 에디터면 되돌리기(Ctrl+Z) 한 칸(씬에 * 표시), 아니면 바로
func _set_prop(prop: String, value: Variant) -> void:
	if _root == null or not is_instance_valid(_root):
		return
	var old: Variant = _root.get(prop)
	if _same(old, value):
		return
	if Engine.is_editor_hint() and _root.is_inside_tree():
		var ur := EditorInterface.get_editor_undo_redo()
		ur.create_action("유닛: %s" % prop, UndoRedo.MERGE_DISABLE, _root)
		ur.add_do_property(_root, prop, value)
		ur.add_undo_property(_root, prop, old)
		ur.commit_action()
	else:
		_root.set(prop, value)
	_refresh_all()


# ───────────── 버튼 ─────────────

## 고른 유닛을 부모로 상속한 새 유닛 씬 — 바꾼 칸만 따로 갖는다(유니티 프리팹 변형)
func new_child_unit(display_name: String) -> String:
	var nm := display_name.strip_edges()
	if _sel_path == "":
		_status.text = "부모로 쓸 유닛을 먼저 고르세요"
		return ""
	if nm == "":
		_status.text = "새 자식 유닛 이름을 적으세요(예: 기관총사수)"
		return ""
	var fname := nm
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", " ", "."]:
		fname = fname.replace(ch, "_")
	var node_name := nm
	for ch in [".", ":", "@", "/", "\"", "%"]:
		node_name = node_name.replace(ch, "_")
	var path := UNITS_DIR.path_join(fname + ".tscn")
	if FileAccess.file_exists(path):
		_status.text = "같은 이름의 유닛 파일이 있습니다: " + path
		return ""
	var txt := "[gd_scene load_steps=2 format=3]\n\n[ext_resource type=\"PackedScene\" path=\"%s\" id=\"1_parent\"]\n\n[node name=\"%s\" instance=ExtResource(\"1_parent\")]\n" % [_sel_path, node_name]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_status.text = "파일을 만들 수 없습니다: " + path
		return ""
	f.store_string(txt)
	f.close()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(path)
	var parent := _sel_path
	_child_name.text = ""
	scan_units()
	select_unit(path)
	_status.text = "새 자식 유닛 %s — 부모 %s 의 칸을 그대로 따라감. 바꿀 칸만 바꾸고 [저장]" % [path.get_file(), parent.get_file()]
	return path


func _on_open_scene() -> void:
	if _sel_path != "" and Engine.is_editor_hint():
		EditorInterface.open_scene_from_path(_sel_path)


## 탭 창의 Ctrl+Z · Ctrl+Y(Ctrl+Shift+Z) · Ctrl+S — 유닛 씬의 되돌리기 · 다시 · 저장(에디터 창과 같은 기록, ② 탭과 같은 방식).
## 칸에 글자를 치는 중이면 칸이 먼저 먹으므로 여기 안 온다
func _unhandled_key_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed or k.echo or not _active or not is_visible_in_tree() or not (k.ctrl_pressed or k.meta_pressed):
		return
	match k.keycode:
		KEY_Z, KEY_Y:
			if not (Engine.is_editor_hint() and _root != null and is_instance_valid(_root) and _root.is_inside_tree()):
				return
			var m := EditorInterface.get_editor_undo_redo()
			var ur := m.get_history_undo_redo(m.get_object_history_id(_root))
			var undo := k.keycode == KEY_Z and not k.shift_pressed
			var nm := ur.get_current_action_name()
			var ok := ur.undo() if undo else ur.redo()
			if not undo:
				nm = ur.get_current_action_name()
			_status.text = (("되돌림: %s" if undo else "다시: %s") % nm) if ok else ("되돌릴 것 없음" if undo else "다시 할 것 없음")
			_poll = 0.0                          # 다음 프레임에 칸 · 미리보기를 따라오게
		KEY_S:
			_on_save()
		_:
			return
	get_viewport().set_input_as_handled()


## ② 장비 탭을 같은 유닛을 고른 채로 연다(탭 창 안일 때)
func _on_open_equip() -> void:
	var hub := get_window() as DRHubWindow
	if hub == null:
		return
	hub.open_page("equip")
	var ep := hub.page("equip") as DREquipPage
	if ep != null and _sel_path != "" and ep._sel_path != _sel_path:
		ep.select_unit(_sel_path)


func _on_save() -> void:
	if _root == null:
		return
	var msg := PackedStringArray()
	if Engine.is_editor_hint() and _root.is_inside_tree():
		if EditorInterface.get_edited_scene_root() != _root:
			EditorInterface.open_scene_from_path(_sel_path)
		EditorInterface.save_scene()
		msg.append("씬 저장: " + _sel_path.get_file())
	else:
		var ps := PackedScene.new()
		if ps.pack(_root) == OK and ResourceSaver.save(ps, _sel_path) == OK:
			msg.append("씬 저장: " + _sel_path.get_file())
	var m: Resource = _root.motions
	if m != null and m.resource_path != "" and not m.resource_path.contains("::"):
		ResourceSaver.save(m, m.resource_path)
		msg.append("동작 표 저장: " + m.resource_path.get_file())
	_status.text = " · ".join(msg)


## 지금 동작 표를 이 유닛 이름으로 복사해 이 유닛에만 쓴다(3D 동작 묶음 경로도 따로)
func _on_own_table() -> void:
	if _root == null or _root.motions == null or _sel_path == "":
		return
	var base := _sel_path.get_file().get_basename()
	var tpath := UNITS_DIR.path_join(base + "_motions.tres")
	if FileAccess.file_exists(tpath):
		_status.text = "이미 있음: %s — 동작 표 칸에서 고르세요" % tpath.get_file()
		return
	var t2 := _root.motions.duplicate(true) as DRMotionTable
	t2.library_path = "res://game/motions/%s_anims.res" % base
	if ResourceSaver.save(t2, tpath) != OK:
		_status.text = "저장 실패: " + tpath
		return
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(tpath)
	_set_prop("motions", load(tpath))
	_status.text = "이 유닛만의 동작 표: %s(3D 동작 묶음 %s — [3D 동작 내보내기] 로 만든다)" % [tpath.get_file(), t2.library_path.get_file()]


## 동작 표가 3D 동작 묶음을 새로 내보냈다 — 캐시를 바꿔 끼우고 미리보기를 다시 조립
func _on_exported() -> void:
	if _root != null and _root.motions != null and _root.motions.library_path != "" and ResourceLoader.exists(_root.motions.library_path):
		ResourceLoader.load(_root.motions.library_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	_rebuild_preview()


# ───────────── 미리보기 ─────────────

## 유닛을 통째로 묶은 사본(저장 안 한 고침까지 — 칸 · 소켓 · 장비 · 왼손 표지)으로 미리보기 캐릭터를 새로 조립. 편집 중인 씬은 안 건드린다
func _rebuild_preview() -> void:
	if _prev_ch != null and is_instance_valid(_prev_ch):
		_prev_ch.queue_free()
	_prev_ch = null
	if _root == null:
		return
	var ps := PackedScene.new()
	if ps.pack(_root) != OK:
		_now.text = "⚠ 유닛을 묶지 못함(pack)"
		return
	var ch := ps.instantiate() as DRCharacter3D
	if ch == null:
		return
	ch.preview_playing = false
	ch.preview_motion = ""
	_dots.world.add_child(ch)                      # 여기서 조립된다(auto_build)
	if ch.get_skeleton() == null:
		_now.text = "⚠ 조립 실패(몸 모델을 확인)"
		ch.queue_free()
		return
	var ap := ch.get_animation_player()
	if ap != null:
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ch.precompute_grips()
	_prev_ch = ch
	_set_facing(_facing)
	_fill_states()


func _set_facing(f: int) -> void:
	_facing = f
	if _prev_ch != null:
		_prev_ch.rotation = Vector3(0.0, float(f) * deg_to_rad(55.0), 0.0)     # 게임과 같은 3/4(좌우 + 카메라 쪽 35°)


func _fill_states() -> void:
	_state_ob.clear()
	var t := _root.motions if _root != null else null
	if t == null:
		_now.text = "동작 표가 없습니다"
		return
	var listed := {}
	for s in t.effective_sets():
		var any := false
		for st in s.states:
			if t.clips_of(st).is_empty():
				continue
			if not any:
				_state_ob.add_separator(s.name)
				any = true
			_state_ob.add_item(st)
			listed[st] = true
	for c in t.clips:
		if c != null and not listed.has(c.state):
			_state_ob.add_item(c.state)
			listed[c.state] = true
	var want := _pv_state if listed.has(_pv_state) else ""
	if want == "":
		want = "서기" if listed.has("서기") else (String(listed.keys()[0]) if not listed.is_empty() else "")
	for i in _state_ob.item_count:
		if not _state_ob.is_item_separator(i) and _state_ob.get_item_text(i) == want:
			_state_ob.select(i)
	if want != "":
		play_state(want)


## 미리보기 캐릭터에게 그 상태를 틀게 한다 — 동작 표에서 비중대로 하나(게임과 같은 규칙)
func play_state(st: String) -> void:
	_pv_state = st
	if _prev_ch == null or _root == null or _root.motions == null:
		return
	var t := _root.motions
	var avail := _prev_ch.motion_names()
	var m := t.pick_state(st, avail)
	_pv_reroll = t.variant_count(st, avail) > 1
	if m == "":
		_now.text = "⚠ %s — 3D 동작 묶음에 이 상태의 동작이 없음(오른쪽 [3D 동작 내보내기])" % st
		return
	_prev_ch.play_motion(m, 0.15)
	var w := 0.0
	for c in t.clips_of(st):
		if c.play_name() == m:
			w = c.weight
	_now.text = "지금: %s   · 상태 %s(%s 세트) · 비중 %s%s" % [m, st, t.set_of(st) if t.set_of(st) != "" else "-",
		DRMotionTableEditor._pct_text(w), "  · 반복이 한 바퀴 돌면 다시 뽑음" if _pv_reroll else ""]


func _process(delta: float) -> void:
	if not _active or not is_visible_in_tree():
		return
	if _pv_vp != null and _dots != null:
		var sz := Vector2(_pv_vp.size)
		var o := Vector2(sz.x * 0.5, sz.y * 0.82)
		if _dots.origin != o:
			_dots.origin = o
			_ground.queue_redraw()
	if _prev_ch != null and _playing:
		_acc += delta
		if _acc >= (1.0 / _style.step_hz if _style.step_hz > 0.0 else 0.0):
			if _prev_ch.step_motion(_acc) and _pv_reroll:
				play_state(_pv_state)
			_acc = 0.0
	# 인스펙터 · 되돌리기로 루트 값이 바뀌었으면 따라간다
	_poll -= delta
	if _poll <= 0.0:
		_poll = POLL_SEC
		if _root != null and not is_instance_valid(_root):
			_root = null
			_owns_root = false
		var sig := _root_sig()
		if sig != _sig and _root != null:
			_refresh_all()
		elif _root != null:
			var xs := _equip_walk(true)
			if xs != _xsig:
				_xsig = xs
				_sync_equip()


## 장비 자리 · 손 비중 · 보간만 바뀌었다(기즈모 · ② 탭) — 다시 조립하지 않고 미리보기 사본의 같은 노드만 맞춘다
func _sync_equip() -> void:
	if _prev_ch == null or not is_instance_valid(_prev_ch):
		return
	for s in DRCharacter3D.find_anchors(_root):
		var stack: Array[Node] = [s]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n.owner == _root:
				var pn := _prev_ch.get_node_or_null(_root.get_path_to(n))
				# 소켓은 뼈가, 두 손 사이 받침대는 두 손이 자리를 정한다(덮으면 원점으로 튐)
				var driven := n is BoneAttachment3D or (n is DRGripMount3D and (n as DRGripMount3D).mode == DRGripMount3D.Mode.HANDS)
				if pn is Node3D and n is Node3D and not driven:
					(pn as Node3D).transform = (n as Node3D).transform
				if pn is DRHandTarget3D and n is DRHandTarget3D:
					(pn as DRHandTarget3D).motion_weights = (n as DRHandTarget3D).motion_weights.duplicate()
					(pn as DRHandTarget3D).weight = (n as DRHandTarget3D).weight
				if pn is DRGripMount3D and n is DRGripMount3D:
					for k in ["blend", "right_offset", "left_offset"]:
						pn.set(k, n.get(k))
			stack.append_array(n.get_children())
	_prev_ch.sync_support()
	var mo := _prev_ch.current_motion()
	if mo != "":
		_prev_ch.play_motion(mo, 0.0)                  # 손 비중을 지금 동작 것으로 다시


func _draw_ground() -> void:
	if _dots == null:
		return
	var o := _dots.origin
	_ground.draw_rect(Rect2(0.0, o.y - 30.0, 4096.0, 4096.0), Color(0.31, 0.37, 0.3))
	_ground.draw_line(Vector2(0.0, o.y - 30.0), Vector2(4096.0, o.y - 30.0), Color(0.22, 0.27, 0.22), 1.0)
	_ground.draw_set_transform(o, 0.0, Vector2(1.0, 0.3))
	_ground.draw_circle(Vector2.ZERO, _dots.px_per_m * 0.4, Color(0.0, 0.0, 0.0, 0.3))
	_ground.draw_set_transform(Vector2.ZERO)
