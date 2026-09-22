@tool
extends Window
class_name DREquipWindow

## Dot Rigger — 장비(무기·헬멧) 굽기 창.  프로젝트 > 도구 > Dot Rigger — 장비 굽기.
##
## 왼쪽: 1 캐릭터 프리셋 · sets.json · 무기 모델 → 2 무기 파트 보이기/숨기기 → 3 잡는 법(자동 그립 + 기즈모 조정)
##       → 4 총의 기본 자리(앞 조각은 자동) → 바닥의 굽기.
## 오른쪽: 2D 미리보기 — 실제 구운 퍼펫(DRPuppetSet)에 지금 그립으로 임시로 구운 무기를 장착해 재생·조준.
##         그 위의 **기즈모**(이동 2축 + 회전 링)로 그립을 맞춘다. 3D 보기는 깊이를 확인할 때만 켠다.
## 그립은 한 번(자동 + 공통 조정)이면 모든 자세에 따라가고, 자세마다 조금 다르게 잡을 땐 `이 자세만`.
## 굽기 결과 <출력 폴더>/<장비 이름>/ 의 equip.json 은 `구운 장비 열기…` 로 다시 열어 고칠 수 있다.

const WEAPON_FILTER := "*.glb, *.gltf, *.fbx, *.obj, *.tscn, *.scn ; 3D 무기 모델"
const PRESET_FILTER := "*.tres ; 캐릭터 프리셋"
const SETS_FILTER := "sets.json ; 세트 목록"
const EQUIP_FILTER := "equip.json ; 구운 장비"
const PV2_DEBOUNCE := 0.35     # 조정을 바꾸는 동안은 기다렸다가 2D 미리보기를 다시 굽는다(초)
const ANGLE_NAMES := ["굽는 시점", "정측면", "정면", "위에서", "뒤에서"]
const GZ_FINE := 0.1           # Shift 를 누르고 끌면 이동·회전이 이만큼 줄어든다


## 2D 미리보기 위의 기즈모 — 손(기준) 자리에 이동 화살표 2개(빨강 = 화면 좌우, 초록 = 위아래)와 회전 링(파랑)
class GizmoNode:
	extends Node2D
	const R_RING := 64.0
	const L_ARROW := 52.0
	var pivot := Vector2.ZERO
	var hot := ""       # 마우스가 올라간 손잡이: x · y · xy · rot
	var active := ""    # 끌고 있는 손잡이
	var label := ""

	func _draw() -> void:
		var cx := Color(0.95, 0.35, 0.35)
		var cy := Color(0.4, 0.9, 0.4)
		var cr := Color(0.45, 0.7, 1.0)
		var hl := Color(1, 1, 1)
		var on_rot := hot == "rot" or active == "rot"
		draw_arc(pivot, R_RING, 0.0, TAU, 72, hl if on_rot else cr, 3.0 if on_rot else 2.0, true)
		var on_x := hot == "x" or active == "x" or hot == "xy" or active == "xy"
		var on_y := hot == "y" or active == "y" or hot == "xy" or active == "xy"
		var ex := pivot + Vector2(L_ARROW, 0)
		var ey := pivot + Vector2(0, -L_ARROW)
		draw_line(pivot, ex, hl if on_x else cx, 3.0, true)
		draw_polygon(PackedVector2Array([ex + Vector2(10, 0), ex + Vector2(-2, -6), ex + Vector2(-2, 6)]), PackedColorArray([hl if on_x else cx]))
		draw_line(pivot, ey, hl if on_y else cy, 3.0, true)
		draw_polygon(PackedVector2Array([ey + Vector2(0, -10), ey + Vector2(-6, 2), ey + Vector2(6, 2)]), PackedColorArray([hl if on_y else cy]))
		draw_circle(pivot, 7.0, hl if (hot == "xy" or active == "xy") else Color(0.9, 0.9, 0.9))
		draw_circle(pivot, 4.0, Color(0.1, 0.1, 0.1))
		if label != "":
			draw_string(ThemeDB.fallback_font, pivot + Vector2(12, -R_RING - 8), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1))

	## 손잡이 맞추기(뷰포트 좌표)
	func hit(p: Vector2) -> String:
		var d := p - pivot
		if d.length() < 11.0:
			return "xy"
		if absf(d.y) < 8.0 and d.x > 0.0 and d.x < L_ARROW + 12.0:
			return "x"
		if absf(d.x) < 8.0 and d.y < 0.0 and d.y > -(L_ARROW + 12.0):
			return "y"
		if absf(d.length() - R_RING) < 9.0:
			return "rot"
		return ""


var baker: DRBaker
var eb: DREquipBaker
var _sets: Array = []
var _grip_set_name := ""       # 자동 그립을 잡는 자세(소총 든 세트)
var _loaded := false
var _busy := false             # 불러오기 · 굽기 · 2D 미리보기 굽기 중
var _filling := false          # 칸을 코드로 채우는 중(신호 무시)
var _pv2_dirty := false
var _pv2_timer := 0.0
var _last_baked: Dictionary = {}
var _restore: Dictionary = {}  # `구운 장비 열기…` 로 읽은 equip.json — 불러온 뒤 되돌린다

# 1
var _preset_edit: LineEdit
var _sets_edit: LineEdit
var _weapon_edit: LineEdit
var _id_edit: LineEdit
var _slot_edit: LineEdit
var _scale: SpinBox
var _load_btn: Button
var _open_btn: Button
var _load_status: Label
# 2
var _node_hint: Label
var _node_box: VBoxContainer
var _node_checks: Dictionary = {}
var _scene_import_btn: Button
# 3
var _attach: OptionButton
var _support: OptionButton
var _forward: OptionButton
var _grip_node: OptionButton
var _auto_btn: Button
var _gz_attach: CheckBox       # 기즈모 기준: 붙일 손
var _gz_support: CheckBox      # 기즈모 기준: 받치는 손
var _gz_set_only: CheckBox     # 이 자세만
var _gz_show: CheckBox
var _gz_reset: Button
var _num_fold: FoldableContainer
var _adj_pos: Array = []       # SpinBox 3 (cm)
var _adj_rot: Array = []       # SpinBox 3 (도)
var _adj_clear: Button
var _set_title: Label
var _set_pos: Array = []
var _set_rot: Array = []
var _set_clear: Button
# 4
var _z_common: OptionButton
var _z_set: OptionButton
var _front_on: CheckBox
var _front_status: Label
# 바닥
var _out_edit: LineEdit
var _bake_btn: Button
var _progress: ProgressBar
var _status: Label
# 오른쪽 위 바
var _view_set: OptionButton
var _pv2_anim: OptionButton
var _pv2_play: CheckBox
var _pv2_aim: HSlider
var _pv2_aim_lbl: Label
var _pv2_zoom: HSlider
var _show3d: CheckBox
# 2D
var _vp2: SubViewport
var _soldier: DRPuppetSet
var _pv2: TextureRect
var _pv2_msg: Label
var _gizmo: GizmoNode
# 3D(기본 숨김)
var _panel3d: VBoxContainer
var _view_angle: OptionButton
var _view_zoom: HSlider
var _view_zoom_lbl: Label
var _show_char: CheckBox
var _pv3: TextureRect
# 기즈모 드래그
var _gz_active := ""
var _gz_start_vp := Vector2.ZERO
var _gz_pivot_vp := Vector2.ZERO
var _gz_spr_pos := Vector2.ZERO
var _gz_spr_rot := 0.0
var _gz_delta_px := Vector2.ZERO   # 캔버스 px
var _gz_dtheta := 0.0


func _init() -> void:
	title = "Dot Rigger — 장비 굽기 (무기·헬멧)"
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # 동작 이름 "Idle" 이 "대기" 로 번역돼 보이지 않게
	size = Vector2i(1240, 800)
	min_size = Vector2i(1000, 640)
	exclusive = false
	close_requested.connect(func(): hide())
	_build_ui()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_teardown()


# ---------------------------------------------------------------- UI 구성

func _build_ui() -> void:
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.split_offset = 420
	add_child(split)

	# 왼쪽: 스크롤 + 바닥
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	split.add_child(left)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	scroll.add_child(col)

	_build_section_source(col)
	_build_section_nodes(col)
	_build_section_grip(col)
	_build_section_order(col)
	_build_footer(left)

	# 오른쪽: 바 + (2D | 3D)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_build_right_bar(right)
	var views := HSplitContainer.new()
	views.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(views)
	_build_preview2d(views)
	_build_preview3d(views)
	_pv2_msg = _hint(right, "", 300.0)


func _section(col: Control, t: String, folded: bool = false) -> VBoxContainer:
	var f := FoldableContainer.new()
	f.title = t
	f.folded = folded
	col.add_child(f)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	f.add_child(v)
	return v


func _tip(c: Control, text: String) -> void:
	c.tooltip_text = text
	c.mouse_filter = Control.MOUSE_FILTER_STOP if c is Label else c.mouse_filter


func _hint(parent: Control, text: String, min_w: float = 340.0) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(min_w, 0)   # 줄바꿈 라벨은 최소 너비가 없으면 창이 세로로 폭주한다(02 U13)
	l.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	parent.add_child(l)
	return l


func _path_row(parent: Control, label: String, tip: String, browse: Callable) -> LineEdit:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(110, 0)
	_tip(l, tip)
	row.add_child(l)
	var e := LineEdit.new()
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tip(e, tip)
	row.add_child(e)
	var b := Button.new()
	b.text = "…"
	b.pressed.connect(browse)
	row.add_child(b)
	parent.add_child(row)
	return e


func _opt(parent: Control, label: String, tip: String) -> OptionButton:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(110, 0)
	_tip(l, tip)
	row.add_child(l)
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.fit_to_longest_item = false
	_tip(o, tip)
	row.add_child(o)
	parent.add_child(row)
	return o


## 한 줄에 스핀 3개(좌우 · 위아래 · 앞뒤 같은 벡터)
func _vec_row(parent: Control, label: String, names: Array, lo: float, hi: float, step: float, tip: String, on_change: Callable) -> Array:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var l := Label.new()
	l.text = label
	_tip(l, tip)
	v.add_child(l)
	var row := HBoxContainer.new()
	var out := []
	for i in 3:
		var sub := VBoxContainer.new()
		sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sub.add_theme_constant_override("separation", 0)
		var nl := Label.new()
		nl.text = String(names[i])
		nl.add_theme_font_size_override("font_size", 11)
		nl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		sub.add_child(nl)
		var sb := SpinBox.new()
		sb.min_value = lo
		sb.max_value = hi
		sb.step = step
		sb.allow_greater = true
		sb.allow_lesser = true
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tip(sb, tip)
		sb.value_changed.connect(func(_v): on_change.call())
		sub.add_child(sb)
		row.add_child(sub)
		out.append(sb)
	v.add_child(row)
	parent.add_child(v)
	return out


func _build_section_source(col: Control) -> void:
	var s := _section(col, "1. 캐릭터 · 세트 · 무기")
	_hint(s, "세트를 구울 때 쓴 캐릭터 프리셋과 sets.json, 그리고 무기 3D 모델을 고르고 `불러오기`. 무기는 병사와 같은 카메라·같은 레스트 자세로 자세(세트)마다 한 장씩 구워진다.")
	_preset_edit = _path_row(s, "캐릭터 프리셋", "메인 창의 `0. 프리셋` 으로 저장한 .tres — 모델·추가 동작 폴더·도트화 값(명암 단계 등)을 세트를 구울 때와 같게 맞추려고 읽는다.", _on_browse_preset)
	_preset_edit.text = _default_preset()
	_sets_edit = _path_row(s, "세트 목록", "세트 굽기가 남긴 sets.json. 여기 적힌 세트마다 무기 그림이 한 장씩 나온다.", _on_browse_sets)
	_sets_edit.text = "res://puppet/sets.json"
	_weapon_edit = _path_row(s, "무기 모델", "3D 무기 파일. OBJ 는 가져오기 형식이 Mesh(기본)면 한 덩어리로 들어온다 — 파트별로 숨기려면 2번의 안내대로 Scene 으로.", _on_browse_weapon)
	var row := HBoxContainer.new()
	var l1 := Label.new()
	l1.text = "장비 이름"
	l1.custom_minimum_size = Vector2(110, 0)
	_tip(l1, "출력 폴더 이름이자 게임에서 부르는 이름(DREquipSet.id). 예: kar98k")
	row.add_child(l1)
	_id_edit = LineEdit.new()
	_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_id_edit.placeholder_text = "비우면 파일 이름"
	row.add_child(_id_edit)
	var l2 := Label.new()
	l2.text = " 슬롯"
	_tip(l2, "한 슬롯에는 하나만 들린다. 무기는 weapon, 헬멧은 helmet 처럼.")
	row.add_child(l2)
	_slot_edit = LineEdit.new()
	_slot_edit.text = "weapon"
	_slot_edit.custom_minimum_size = Vector2(90, 0)
	row.add_child(_slot_edit)
	s.add_child(row)
	var row2 := HBoxContainer.new()
	var l3 := Label.new()
	l3.text = "크기 배율"
	l3.custom_minimum_size = Vector2(110, 0)
	_tip(l3, "무기 모델의 단위가 캐릭터와 다를 때(cm 로 만든 모델 = 0.01). 바꾸면 자동 그립을 다시 잡는다.")
	row2.add_child(l3)
	_scale = SpinBox.new()
	_scale.min_value = 0.001
	_scale.max_value = 1000.0
	_scale.step = 0.01
	_scale.value = 1.0
	_scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale.value_changed.connect(func(_v): _on_grip_inputs_changed())
	row2.add_child(_scale)
	s.add_child(row2)
	var row3 := HBoxContainer.new()
	_load_btn = Button.new()
	_load_btn.text = "불러오기"
	_load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_btn.pressed.connect(_on_load)
	row3.add_child(_load_btn)
	_open_btn = Button.new()
	_open_btn.text = "구운 장비 열기…"
	_tip(_open_btn, "전에 구운 <출력 폴더>/<장비 이름>/equip.json 을 열어 그립·조정·숨긴 파트를 그대로 되돌린다.")
	_open_btn.pressed.connect(_on_open_equip)
	row3.add_child(_open_btn)
	s.add_child(row3)
	_load_status = _hint(s, "")


func _build_section_nodes(col: Control) -> void:
	var s := _section(col, "2. 무기 파트 (보이기 / 숨기기)")
	_node_hint = _hint(s, "무기를 불러오면 하위 파트가 여기 나온다. 끄면 그 파트는 안 찍힌다(탄 클립 등).")
	_node_box = VBoxContainer.new()
	_node_box.add_theme_constant_override("separation", 2)
	s.add_child(_node_box)
	_scene_import_btn = Button.new()
	_scene_import_btn.text = "가져오기 형식을 Scene 으로 바꾸고 다시 불러오기"
	_tip(_scene_import_btn, "OBJ 를 파트별 노드로 가져온다(.import 의 importer 를 scene 으로 바꾸고 다시 가져오기). 파일시스템 독 > 가져오기 탭에서 손으로 해도 같다.")
	_scene_import_btn.pressed.connect(_on_make_scene_import)
	_scene_import_btn.visible = false
	s.add_child(_scene_import_btn)


func _build_section_grip(col: Control) -> void:
	var s := _section(col, "3. 잡는 법 (그립)")
	_hint(s, "불러오면 자동으로 잡힌다: 소총을 든 자세(레스트 이름에 rifle·aim 이 든 세트)에서 총열 = 붙일 손 → 받치는 손, 손이 잡는 자리를 붙일 손 손바닥에. 그 위에 오른쪽 2D 의 기즈모로 조정한다.")
	_attach = _opt(s, "붙일 손", "무기가 붙는 파트. 2D 에서 이 파트를 따라 움직인다. 보통 R_Hand(방아쇠 손).")
	_attach.item_selected.connect(func(_i): _on_grip_inputs_changed())
	_support = _opt(s, "받치는 손", "자동 그립에서 총열이 향할 파트. 보통 L_Hand(총열 받치는 손). 권총이면 붙일 손과 같은 쪽 팔꿈치 등.")
	_support.item_selected.connect(func(_i): _on_grip_inputs_changed())
	_forward = _opt(s, "총구 쪽 축", "무기 모델에서 총구가 향한 축. 총구가 뒤를 보면 부호를 바꾼다.")
	for k in DREquipBaker.AXES.keys():
		_forward.add_item(String(k))
	_forward.item_selected.connect(func(_i): _on_grip_inputs_changed())
	_grip_node = _opt(s, "손이 잡는 자리", "무기의 이 파트 중심이 붙일 손 손바닥에 온다(방아쇠·손잡이 노드). 없으면 경계 상자에서 어림(뒤에서 35%, 아래 1/3).")
	_grip_node.item_selected.connect(func(_i): _on_grip_inputs_changed())
	_auto_btn = Button.new()
	_auto_btn.text = "자동으로 다시 잡기"
	_tip(_auto_btn, "위 값으로 자동 그립을 다시 잡는다(조정은 그대로 둔다). 값을 바꾸면 알아서 다시 잡히므로 보통 누를 일이 없다.")
	_auto_btn.pressed.connect(_on_grip_inputs_changed)
	s.add_child(_auto_btn)

	var t1 := Label.new()
	t1.text = "기즈모 조정 (오른쪽 2D 미리보기에서 끌기)"
	s.add_child(t1)
	_hint(s, "화살표 = 화면 좌우·위아래로 옮기기, 가운데 점 = 자유 이동, 링 = 기준 손을 중심으로 돌리기. Shift 를 누르면 1/10 로 미세하게. 놓으면 그 값이 조정에 들어가고 잠시 뒤 다시 구워진다.")
	var grp := ButtonGroup.new()
	var row := HBoxContainer.new()
	_gz_attach = CheckBox.new()
	_gz_attach.text = "붙일 손 기준"
	_gz_attach.button_group = grp
	_gz_attach.button_pressed = true
	_tip(_gz_attach, "기즈모가 붙일 손(방아쇠 손)에 뜨고, 회전은 그 손을 중심으로 — 총구 쪽이 움직인다.")
	_gz_attach.toggled.connect(func(_on): _gizmo_refresh())
	row.add_child(_gz_attach)
	_gz_support = CheckBox.new()
	_gz_support.text = "받치는 손 기준"
	_gz_support.button_group = grp
	_tip(_gz_support, "기즈모가 받치는 손(총열 잡은 손)에 뜨고, 회전은 그 손을 중심으로 — 개머리판 쪽이 움직인다.")
	_gz_support.toggled.connect(func(_on): _gizmo_refresh())
	row.add_child(_gz_support)
	s.add_child(row)
	var row2 := HBoxContainer.new()
	_gz_set_only = CheckBox.new()
	_gz_set_only.text = "이 자세만"
	_tip(_gz_set_only, "켜면 기즈모 조정이 오른쪽 `자세` 에서 고른 세트에만 더해진다(다른 자세는 그대로). 끄면 모든 자세 공통.")
	_gz_set_only.toggled.connect(func(_on): _gizmo_refresh())
	row2.add_child(_gz_set_only)
	_gz_reset = Button.new()
	_gz_reset.text = "조정 리셋"
	_tip(_gz_reset, "`이 자세만` 이 켜져 있으면 이 자세의 조정만, 아니면 공통 조정을 0 으로.")
	_gz_reset.pressed.connect(_on_gizmo_reset)
	row2.add_child(_gz_reset)
	_gz_show = CheckBox.new()
	_gz_show.text = "기즈모 보이기"
	_gz_show.button_pressed = true
	_gz_show.toggled.connect(func(_on): _gizmo_refresh())
	row2.add_child(_gz_show)
	s.add_child(row2)

	_num_fold = FoldableContainer.new()
	_num_fold.title = "숫자로 보기 / 고치기"
	_num_fold.folded = true
	s.add_child(_num_fold)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", 6)
	_num_fold.add_child(nv)
	var t2 := Label.new()
	t2.text = "모든 자세 공통 조정"
	nv.add_child(t2)
	_adj_pos = _vec_row(nv, "이동 (cm)", ["좌우", "위아래", "앞뒤(총열)"], -100.0, 100.0, 0.5,
		"무기 축 기준 이동. 앞뒤 + = 총구 쪽으로(손이 뒤를 잡음), 위아래 + = 위, 좌우 + = 총열 왼쪽(카메라 앞뒤 — 기즈모로는 못 움직이는 축).", _on_adj_changed)
	_adj_rot = _vec_row(nv, "회전 (°)", ["총구 위/아래", "좌우 틀기", "굴리기"], -180.0, 180.0, 1.0,
		"손이 잡는 자리를 중심으로 돈다. 총구 위/아래 + = 총구가 올라감. 좌우 틀기 = 총구를 카메라 쪽/반대쪽으로. 굴리기 = 총열을 축으로.", _on_adj_changed)
	_adj_clear = Button.new()
	_adj_clear.text = "공통 조정 지우기"
	_adj_clear.pressed.connect(func():
		_set_vec(_adj_pos, Vector3.ZERO)
		_set_vec(_adj_rot, Vector3.ZERO)
		_on_adj_changed())
	nv.add_child(_adj_clear)
	_set_title = Label.new()
	_set_title.text = "이 자세만 더 조정"
	_tip(_set_title, "오른쪽 `자세` 에서 고른 세트에만 더해지는 조정. 앉기에서 총을 더 눕히는 식.")
	nv.add_child(_set_title)
	_set_pos = _vec_row(nv, "이동 (cm)", ["좌우", "위아래", "앞뒤(총열)"], -100.0, 100.0, 0.5, "이 자세에만 더하는 이동.", _on_set_adj_changed)
	_set_rot = _vec_row(nv, "회전 (°)", ["총구 위/아래", "좌우 틀기", "굴리기"], -180.0, 180.0, 1.0, "이 자세에만 더하는 회전.", _on_set_adj_changed)
	_set_clear = Button.new()
	_set_clear.text = "이 자세 조정 지우기"
	_set_clear.pressed.connect(func():
		_set_vec(_set_pos, Vector3.ZERO)
		_set_vec(_set_rot, Vector3.ZERO)
		if _z_set.item_count > 0:
			_z_set.select(0)
		_on_set_adj_changed())
	nv.add_child(_set_clear)


func _build_section_order(col: Control) -> void:
	var s := _section(col, "4. 총의 기본 자리 · 앞 조각")
	_hint(s, "기본 자리 = 퍼펫의 그리기 순서(뒤 → 앞) 어디에 무기를 둘지. 그 뒤에 그려지는 파트 중 3D 에서 무기보다 앞에 있는 부분(총열을 감싼 손가락 등)은 `앞 조각` 으로 따로 찍혀 무기 위에 자동으로 얹힌다 — 손을 앞뒤로 나누는 Spine 방식을 자동으로.")
	_z_common = _opt(s, "기본 자리", "모든 자세에 쓰는 자리. `X 바로 앞` = X 는 가리고 X 보다 앞 파트에는 가려진다(앞 조각 제외).")
	_z_common.item_selected.connect(func(_i): _on_z_changed())
	_z_set = _opt(s, "이 자세만", "오른쪽 `자세` 에서 고른 세트에만 다르게. `(공통과 같게)` 가 기본.")
	_z_set.item_selected.connect(func(_i): _on_set_adj_changed())
	_front_on = CheckBox.new()
	_front_on.text = "앞 조각 자동 굽기"
	_front_on.button_pressed = true
	_tip(_front_on, "끄면 무기가 기본 자리에만 그려진다(손가락이 총 뒤로 들어간다).")
	_front_on.toggled.connect(func(on):
		if _loaded and not _filling:
			eb.front_pieces = on
			_mark_pv2())
	s.add_child(_front_on)
	_front_status = _hint(s, "")


func _build_footer(left: Control) -> void:
	var foot := VBoxContainer.new()
	foot.add_theme_constant_override("separation", 4)
	left.add_child(foot)
	foot.add_child(HSeparator.new())
	_out_edit = _path_row(foot, "출력 폴더", "여기 아래 <장비 이름>/ 에 세트별 PNG · 앞 조각 PNG · equip.json 이 생긴다.", _on_browse_out)
	_out_edit.text = "res://equip"
	var row := HBoxContainer.new()
	_bake_btn = Button.new()
	_bake_btn.text = "굽기 (모든 자세)"
	_bake_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bake_btn.disabled = true
	_tip(_bake_btn, "sets.json 의 모든 세트에 대해 지금 그립으로 굽고 파일로 남긴다. 게임: soldier.equip(DREquipSet.load_json(\"…/equip.json\"))")
	_bake_btn.pressed.connect(_on_bake)
	row.add_child(_bake_btn)
	foot.add_child(row)
	_progress = ProgressBar.new()
	_progress.min_value = 0
	_progress.max_value = 1
	_progress.value = 0
	foot.add_child(_progress)
	_status = _hint(foot, "먼저 1번에서 `불러오기`.")


func _build_right_bar(parent: Control) -> void:
	var bar := HFlowContainer.new()
	parent.add_child(bar)
	var l0 := Label.new()
	l0.text = "자세"
	_tip(l0, "어느 세트(자세)를 볼지. `이 자세만` 조정과 `이 자세만` 자리는 여기서 고른 자세에 붙는다.")
	bar.add_child(l0)
	_view_set = OptionButton.new()
	_view_set.item_selected.connect(func(_i): _on_view_set_changed())
	bar.add_child(_view_set)
	var l1 := Label.new()
	l1.text = " 동작"
	bar.add_child(l1)
	_pv2_anim = OptionButton.new()
	_pv2_anim.item_selected.connect(func(i): _on_anim_selected(i))
	bar.add_child(_pv2_anim)
	_pv2_play = CheckBox.new()
	_pv2_play.text = "재생"
	_pv2_play.button_pressed = true
	_pv2_play.toggled.connect(func(on):
		if _soldier != null:
			_soldier.speed_scale = 1.0 if on else 0.0)
	bar.add_child(_pv2_play)
	var l2 := Label.new()
	l2.text = " 조준"
	bar.add_child(l2)
	_pv2_aim = HSlider.new()
	_pv2_aim.min_value = -35.0
	_pv2_aim.max_value = 35.0
	_pv2_aim.step = 1.0
	_pv2_aim.value = 0.0
	_pv2_aim.custom_minimum_size = Vector2(110, 0)
	_tip(_pv2_aim, "게임의 마우스 조준처럼 몸통을 돌려 본다(0 = 끔). 무기가 손을 따라 같이 도는지 확인.")
	_pv2_aim.value_changed.connect(func(vv): _pv2_aim_lbl.text = "%+d°" % int(vv))
	bar.add_child(_pv2_aim)
	_pv2_aim_lbl = Label.new()
	_pv2_aim_lbl.text = "+0°"
	bar.add_child(_pv2_aim_lbl)
	var l3 := Label.new()
	l3.text = " 확대"
	bar.add_child(l3)
	_pv2_zoom = HSlider.new()
	_pv2_zoom.min_value = 0.5
	_pv2_zoom.max_value = 4.0
	_pv2_zoom.step = 0.25
	_pv2_zoom.value = 1.5
	_pv2_zoom.custom_minimum_size = Vector2(90, 0)
	_pv2_zoom.value_changed.connect(func(vv):
		if _soldier != null:
			_soldier.scale = Vector2(vv, vv))
	bar.add_child(_pv2_zoom)
	_show3d = CheckBox.new()
	_show3d.text = "3D 보기"
	_tip(_show3d, "깊이(무기가 손 앞인지 뒤인지)를 확인할 때만. 굽기·기즈모에는 영향 없음.")
	_show3d.toggled.connect(func(on):
		_panel3d.visible = on
		_apply_3d_view())
	bar.add_child(_show3d)


func _build_preview2d(parent: Control) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(320, 0)
	parent.add_child(panel)
	_pv2 = TextureRect.new()
	_pv2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pv2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pv2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pv2.mouse_filter = Control.MOUSE_FILTER_STOP
	_tip(_pv2, "실제로 구운 퍼펫(sets.json)에 지금 그립으로 임시로 구운 무기를 장착한 모습 — 게임에서 보이는 그대로. 기즈모를 끌어 그립을 맞춘다.")
	_pv2.gui_input.connect(_on_pv2_input)
	panel.add_child(_pv2)
	# 2D 미리보기 뷰포트
	_vp2 = SubViewport.new()
	_vp2.size = Vector2i(560, 600)
	_vp2.transparent_bg = false
	_vp2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp2)
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.42, 0.36)
	bg.size = Vector2(_vp2.size)
	_vp2.add_child(bg)
	_gizmo = GizmoNode.new()
	_gizmo.name = "Gizmo"
	_gizmo.z_index = 4000
	_gizmo.visible = false
	_vp2.add_child(_gizmo)
	_pv2.texture = _vp2.get_texture()


func _build_preview3d(parent: Control) -> void:
	_panel3d = VBoxContainer.new()
	_panel3d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel3d.custom_minimum_size = Vector2(280, 0)
	_panel3d.visible = false
	parent.add_child(_panel3d)
	var bar := HFlowContainer.new()
	_panel3d.add_child(bar)
	var l1 := Label.new()
	l1.text = "3D  보는 각도"
	bar.add_child(l1)
	_view_angle = OptionButton.new()
	for n in ANGLE_NAMES:
		_view_angle.add_item(String(n))
	_tip(_view_angle, "굽는 시점 = 실제로 찍히는 각도. 다른 각도는 그립을 맞출 때 보는 용도(굽기에는 영향 없음).")
	_view_angle.item_selected.connect(func(_i): _apply_3d_view())
	bar.add_child(_view_angle)
	var l2 := Label.new()
	l2.text = " 확대"
	bar.add_child(l2)
	_view_zoom = HSlider.new()
	_view_zoom.min_value = 1.0
	_view_zoom.max_value = 8.0
	_view_zoom.step = 0.5
	_view_zoom.value = 1.0
	_view_zoom.custom_minimum_size = Vector2(120, 0)
	_tip(_view_zoom, "붙일 손 주변을 확대해 본다.")
	_view_zoom.value_changed.connect(func(vv):
		_view_zoom_lbl.text = "×%.1f" % vv
		_apply_3d_view())
	bar.add_child(_view_zoom)
	_view_zoom_lbl = Label.new()
	_view_zoom_lbl.text = "×1.0"
	bar.add_child(_view_zoom_lbl)
	_show_char = CheckBox.new()
	_show_char.text = "캐릭터 보이기"
	_show_char.button_pressed = true
	_show_char.toggled.connect(func(_on): _apply_3d_view())
	bar.add_child(_show_char)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel3d.add_child(panel)
	_pv3 = TextureRect.new()
	_pv3.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pv3.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pv3.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tip(_pv3, "그 자세의 레스트(파트 그림을 찍는 자세)에 무기를 든 3D.")
	panel.add_child(_pv3)


# ---------------------------------------------------------------- 파일 고르기

func _file_dialog(filter: String, title_text: String, dir_mode: bool, on_selected: Callable) -> void:
	var efd := EditorFileDialog.new()
	var dlg: Window = efd
	if efd != null:
		efd.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR if dir_mode else EditorFileDialog.FILE_MODE_OPEN_FILE
		efd.access = EditorFileDialog.ACCESS_RESOURCES
		if not dir_mode:
			efd.filters = PackedStringArray([filter])
	else:
		var f := FileDialog.new()
		f.file_mode = FileDialog.FILE_MODE_OPEN_DIR if dir_mode else FileDialog.FILE_MODE_OPEN_FILE
		f.access = FileDialog.ACCESS_RESOURCES
		f.use_native_dialog = false
		if not dir_mode:
			f.filters = PackedStringArray([filter])
		dlg = f
	dlg.title = title_text
	dlg.connect("dir_selected" if dir_mode else "file_selected", func(p):
		var picked := String(p)
		dlg.queue_free()
		on_selected.call(picked))
	dlg.connect("canceled", func(): dlg.queue_free())
	add_child(dlg)
	if efd != null:
		efd.popup_file_dialog()
	else:
		dlg.popup_centered_ratio(0.6)


func _on_browse_preset() -> void:
	_file_dialog(PRESET_FILTER, "캐릭터 프리셋 — Dot Rigger", false, func(p): _preset_edit.text = p)


func _on_browse_sets() -> void:
	_file_dialog(SETS_FILTER, "세트 목록(sets.json) — Dot Rigger", false, func(p): _sets_edit.text = p)


func _on_browse_weapon() -> void:
	_file_dialog(WEAPON_FILTER, "무기 모델 — Dot Rigger", false, func(p):
		_weapon_edit.text = p
		if _id_edit.text.strip_edges() == "":
			_id_edit.text = p.get_file().get_basename().to_lower()
		_on_load())


func _on_browse_out() -> void:
	_file_dialog("", "출력 폴더 — Dot Rigger", true, func(p): _out_edit.text = p)


func _on_open_equip() -> void:
	_file_dialog(EQUIP_FILTER, "구운 장비(equip.json) 열기 — Dot Rigger", false, func(p): _open_json(p))


## equip.json 을 읽어 칸을 채우고 불러온다 — 불러온 뒤 그립·조정을 되돌린다
func _open_json(path: String) -> void:
	var d := DREquipBaker._read_json(path)
	if d.is_empty():
		_status.text = "읽을 수 없습니다: %s" % path
		return
	_restore = d
	if d.has("source"):
		_weapon_edit.text = String(d["source"])
	if d.has("sets_json"):
		_sets_edit.text = String(d["sets_json"])
	_id_edit.text = String(d.get("id", _id_edit.text))
	_slot_edit.text = String(d.get("slot", _slot_edit.text))
	_scale.set_value_no_signal(float(d.get("weapon_scale", 1.0)))
	_out_edit.text = path.get_base_dir().get_base_dir()
	_on_load()


static func _default_preset() -> String:
	for f in DirAccess.get_files_at("res://"):
		if String(f).ends_with("_preset.tres"):
			return "res://" + String(f)
	return ""


# ---------------------------------------------------------------- 불러오기

func _fail(msg: String) -> void:
	_load_status.text = "⚠ " + msg
	_status.text = "⚠ " + msg
	_busy = false
	_loaded = false
	_bake_btn.disabled = true


func _teardown() -> void:
	if eb != null:
		eb.remove_weapon()
	if baker != null:
		baker.cleanup()
	baker = null
	eb = null
	if is_instance_valid(_soldier):
		_soldier.queue_free()
	_soldier = null
	_last_baked = {}
	_loaded = false
	if _gizmo != null:
		_gizmo.visible = false


func _on_load() -> void:
	if _busy:
		return
	_busy = true
	_bake_btn.disabled = true
	_load_status.text = "불러오는 중…"
	var opts := DRBaker.Options.new()
	var model_path := ""
	var preset_path := _preset_edit.text.strip_edges()
	if preset_path != "":
		var p := load(preset_path) as DRPreset
		if p == null:
			_fail("프리셋을 열 수 없습니다: %s" % preset_path)
			return
		model_path = p.model_path
		opts.extra_anim_dir = p.extra_anim_dir
		opts.light_bands = p.light_bands
		opts.ambient = p.ambient
		opts.alpha_threshold = p.alpha_threshold
		opts.color_levels = p.color_levels
		opts.bleed_rings = p.bleed_rings
		opts.composites = p.composites.duplicate(true)
		opts.composite_upper_parts = p.composite_upper_parts
	if model_path == "":
		_fail("캐릭터 프리셋에 모델 경로가 없습니다(메인 창에서 모델을 불러온 뒤 프리셋을 저장할 것)")
		return
	var scene := load(model_path) as PackedScene
	if scene == null:
		_fail("캐릭터 모델을 열 수 없습니다: %s" % model_path)
		return
	var wpath := _weapon_edit.text.strip_edges()
	var wres: Resource = load(wpath) if wpath != "" else null
	if wres == null or not (wres is PackedScene or wres is Mesh):
		_fail("무기 모델을 열 수 없습니다: %s" % wpath)
		return
	_teardown()
	baker = DRBaker.new()
	if not baker.setup(self, scene, DRPartProfile.humanoid(), opts):
		_fail("캐릭터를 세울 수 없습니다(출력 창 참고)")
		baker = null
		return
	await get_tree().process_frame
	eb = DREquipBaker.new()
	eb.baker = baker
	eb.sets_json = _sets_edit.text.strip_edges()
	eb.set_weapon(wres, wpath)
	eb.id = _id_edit.text.strip_edges() if _id_edit.text.strip_edges() != "" else wpath.get_file().get_basename().to_lower()
	_id_edit.text = eb.id
	eb.slot = _slot_edit.text.strip_edges()
	eb.weapon_scale = _scale.value
	eb.front_pieces = _front_on.button_pressed
	_sets = eb.read_sets()
	if _sets.is_empty():
		_fail("sets.json 에서 세트를 읽지 못했습니다: %s" % eb.sets_json)
		return
	if not baker.rig.parts.has("R_Hand"):
		_load_status.text = "⚠ R_Hand 파트가 없습니다 — 붙일 손을 직접 고르세요"
	_fill_parts()
	_fill_weapon_nodes()
	_fill_view_sets()
	var gs := DREquipBaker.pick_grip_set(_sets)
	_grip_set_name = String(gs["name"])
	if not _restore.is_empty():
		eb.from_dict(_restore)
		_restore = {}
		eb.sets_json = _sets_edit.text.strip_edges()
		eb.id = _id_edit.text.strip_edges()
		eb.slot = _slot_edit.text.strip_edges()
		if not (eb.weapon_res is PackedScene) and not (eb.weapon_res is Mesh):
			eb.set_weapon(wres, wpath)
		_fill_weapon_nodes()
	else:
		eb.attach_part = "R_Hand" if baker.rig.parts.has("R_Hand") else String(baker.rig.order[0])
		eb.support_part = "L_Hand" if baker.rig.parts.has("L_Hand") else eb.attach_part
		eb.z_after_part = "Torso" if baker.rig.parts.has("Torso") else ""
		if not eb.apply_set(gs):
			_fail("그립을 잡을 자세를 세울 수 없습니다: " + ", ".join(eb.warnings))
			return
		eb.auto_grip()
	_fill_from_eb()
	var vi := _set_index(_grip_set_name)
	_view_set.select(maxi(vi, 0))
	_pv3.texture = baker.viewport.get_texture()
	_loaded = true
	await _build_soldier()
	_load_status.text = "세트 %d개 · 무기 파트 %d개 · 자동 그립 기준 자세: %s" % [_sets.size(), eb.weapon_node_names().size(), _grip_set_name]
	if eb.warnings.size() > 0:
		_load_status.text += "\n⚠ " + "\n⚠ ".join(eb.warnings)
	_status.text = "준비됨 — 오른쪽 2D 에서 기즈모로 맞추고 `굽기`."
	# 여기서야 손을 뗀다(그 전에 풀면 병사를 만드는 사이에 보기 조작이 끼어든다)
	_busy = false
	_bake_btn.disabled = false
	_on_view_set_changed()
	_pv2_dirty = true
	_pv2_timer = 0.0


func _set_index(set_name: String) -> int:
	for i in _sets.size():
		if String((_sets[i] as Dictionary)["name"]) == set_name:
			return i
	return -1


func _cur_set() -> Dictionary:
	var i := _view_set.selected
	if i < 0 or i >= _sets.size():
		return {}
	return _sets[i]


func _cur_set_name() -> String:
	var s := _cur_set()
	return String(s.get("name", ""))


func _fill_parts() -> void:
	_filling = true
	for o in [_attach, _support]:
		(o as OptionButton).clear()
		for pn in baker.rig.order:
			(o as OptionButton).add_item(String(pn))
	_filling = false


func _fill_weapon_nodes() -> void:
	for c in _node_box.get_children():
		c.queue_free()
	_node_checks.clear()
	var names := eb.weapon_node_names()
	for n in names:
		var cb := CheckBox.new()
		cb.text = String(n)
		cb.button_pressed = not eb.hidden_nodes.has(String(n))
		cb.toggled.connect(func(_on):
			var hn := PackedStringArray()
			for k in _node_checks.keys():
				if not (_node_checks[k] as CheckBox).button_pressed:
					hn.append(String(k))
			eb.hidden_nodes = hn
			eb.apply_hidden()
			_on_grip_inputs_changed())
		_node_box.add_child(cb)
		_node_checks[String(n)] = cb
	_filling = true
	_grip_node.clear()
	_grip_node.add_item("(경계 상자에서 어림)")
	for n in names:
		_grip_node.add_item(String(n))
	_filling = false
	if eb.weapon_is_split():
		_node_hint.text = "파트 %d개. 끄면 그 파트는 안 찍힌다(탄 클립 등)." % names.size()
		_scene_import_btn.visible = false
	else:
		_node_hint.text = "⚠ 한 덩어리(Mesh)로 가져온 모델이라 파트별로 숨길 수 없습니다. OBJ 라면 가져오기 형식을 Scene 으로 바꾸면 파트가 나뉩니다."
		_scene_import_btn.visible = eb.weapon_path.get_extension().to_lower() == "obj"


func _fill_view_sets() -> void:
	_filling = true
	_view_set.clear()
	for s in _sets:
		_view_set.add_item(String((s as Dictionary)["name"]))
	_filling = false


## 그리기 순서 목록 — 그 세트의 layer_order(뒤 → 앞)
func _fill_z_items(opt: OptionButton, with_same: bool, set_info: Dictionary) -> void:
	opt.clear()
	if with_same:
		opt.add_item("(공통과 같게)")
		opt.set_item_metadata(opt.item_count - 1, {"same": true})
	opt.add_item("맨 뒤")
	opt.set_item_metadata(opt.item_count - 1, {"after": "", "z": DREquipBaker.Z_BACK})
	var order: Array = []
	if not set_info.is_empty():
		order = Array((set_info["rig"] as Dictionary).get("layer_order", []))
	if order.is_empty():
		order = Array(baker.rig.order)
	for pn in order:
		opt.add_item("%s 바로 앞" % String(pn))
		opt.set_item_metadata(opt.item_count - 1, {"after": String(pn), "z": DREquipBaker.Z_FRONT})
	opt.add_item("맨 앞")
	opt.set_item_metadata(opt.item_count - 1, {"after": "", "z": DREquipBaker.Z_FRONT})


func _z_select(opt: OptionButton, after: String, z: int) -> void:
	for i in opt.item_count:
		var m: Variant = opt.get_item_metadata(i)
		if not (m is Dictionary) or (m as Dictionary).has("same"):
			continue
		var md: Dictionary = m
		if after != "":
			if String(md["after"]) == after:
				opt.select(i)
				return
		elif String(md["after"]) == "" and ((z < 10) == (int(md["z"]) < 10)):
			opt.select(i)
			return
	opt.select(0)


func _select_text(opt: OptionButton, text: String) -> void:
	for i in opt.item_count:
		if opt.get_item_text(i) == text:
			opt.select(i)
			return


func _set_vec(spins: Array, v: Vector3) -> void:
	for i in 3:
		(spins[i] as SpinBox).set_value_no_signal(v[i])


func _get_vec(spins: Array) -> Vector3:
	return Vector3((spins[0] as SpinBox).value, (spins[1] as SpinBox).value, (spins[2] as SpinBox).value)


## eb 의 값으로 칸을 채운다
func _fill_from_eb() -> void:
	_filling = true
	_select_text(_attach, eb.attach_part)
	_select_text(_support, eb.support_part)
	for i in _forward.item_count:
		if (DREquipBaker.AXES[_forward.get_item_text(i)] as Vector3).is_equal_approx(eb.forward):
			_forward.select(i)
	_select_text(_grip_node, eb.grip_node if eb.grip_node != "" else "(경계 상자에서 어림)")
	_scale.set_value_no_signal(eb.weapon_scale)
	_front_on.set_pressed_no_signal(eb.front_pieces)
	for k in _node_checks.keys():
		(_node_checks[k] as CheckBox).set_pressed_no_signal(not eb.hidden_nodes.has(String(k)))
	_set_vec(_adj_pos, eb.adj_pos * 100.0)
	_set_vec(_adj_rot, eb.adj_rot)
	_fill_z_items(_z_common, false, _sets[maxi(_set_index(_grip_set_name), 0)])
	_z_select(_z_common, eb.z_after_part, eb.z_index)
	_filling = false
	_fill_set_adjust()


## 지금 보는 자세의 세트별 조정 칸
func _fill_set_adjust() -> void:
	_filling = true
	var s := _cur_set()
	var name := String(s.get("name", ""))
	_set_title.text = "이 자세만 더 조정 — %s" % name if name != "" else "이 자세만 더 조정"
	var a := eb.adjust_of(name)
	_set_vec(_set_pos, Vector3(a["pos"]) * 100.0)
	_set_vec(_set_rot, Vector3(a["rot"]))
	_fill_z_items(_z_set, true, s)
	if bool(a["z_override"]):
		_z_select(_z_set, String(a["z_after_part"]), int(a["z_index"]))
	else:
		_z_set.select(0)
	_filling = false


# ---------------------------------------------------------------- 값 바뀜

## 붙일 손 · 받치는 손 · 총구 축 · 잡는 자리 · 배율 · 숨긴 파트가 바뀜 → 자동 그립을 다시 잡는다(조정은 유지)
func _on_grip_inputs_changed() -> void:
	if not _loaded or _filling or _busy:
		return
	if _attach.selected >= 0:
		eb.attach_part = _attach.get_item_text(_attach.selected)
	if _support.selected >= 0:
		eb.support_part = _support.get_item_text(_support.selected)
	if _forward.selected >= 0:
		eb.forward = DREquipBaker.AXES[_forward.get_item_text(_forward.selected)]
	eb.grip_node = "" if _grip_node.selected <= 0 else _grip_node.get_item_text(_grip_node.selected)
	eb.weapon_scale = _scale.value
	var gi := _set_index(_grip_set_name)
	if gi >= 0 and eb.apply_set(_sets[gi]):
		eb.warnings = PackedStringArray()
		if not eb.auto_grip():
			_status.text = "⚠ " + ", ".join(eb.warnings)
	_apply_3d_view()
	_mark_pv2()


func _on_adj_changed() -> void:
	if not _loaded or _filling:
		return
	eb.adj_pos = _get_vec(_adj_pos) / 100.0
	eb.adj_rot = _get_vec(_adj_rot)
	_grip_changed()


func _on_set_adj_changed() -> void:
	if not _loaded or _filling:
		return
	var name := _cur_set_name()
	if name == "":
		return
	var z_over := false
	var z_after := ""
	var z_idx := eb.z_index
	if _z_set.selected > 0:
		var md: Dictionary = _z_set.get_item_metadata(_z_set.selected)
		z_over = true
		z_after = String(md["after"])
		z_idx = int(md["z"])
	eb.set_adjust_of(name, _get_vec(_set_pos) / 100.0, _get_vec(_set_rot), z_over, z_after, z_idx)
	_grip_changed()


func _on_z_changed() -> void:
	if not _loaded or _filling or _z_common.selected < 0:
		return
	var md: Dictionary = _z_common.get_item_metadata(_z_common.selected)
	eb.z_after_part = String(md["after"])
	eb.z_index = int(md["z"])
	_mark_pv2()   # 자리가 바뀌면 앞 조각 후보도 바뀌므로 다시 굽는다


## 그립이 바뀜 → 3D 에 바로, 2D 는 잠시 뒤 다시 굽는다
func _grip_changed() -> void:
	if _busy:
		_mark_pv2()
		return
	eb.place_weapon(_cur_set_name())
	_mark_pv2()


func _mark_pv2() -> void:
	_pv2_dirty = true
	_pv2_timer = PV2_DEBOUNCE


func _on_gizmo_reset() -> void:
	if not _loaded:
		return
	if _gz_set_only.button_pressed:
		_set_clear.pressed.emit()
	else:
		_adj_clear.pressed.emit()


func _on_view_set_changed() -> void:
	if not _loaded or _filling:
		return
	_fill_set_adjust()
	_apply_3d_view()
	# 2D 도 같은 자세의 동작으로(이미 그 자세의 동작이면 그대로)
	if _soldier != null:
		var s := _cur_set()
		var cur := String(_soldier.current_animation())
		var cur_set := String(_soldier.current_set())
		if cur_set != String(s.get("name", "")):
			for e in _soldier._entries:
				if String((e as Dictionary)["name"]) == String(s.get("name", "")):
					var first: PackedStringArray = (e as Dictionary)["anims"]
					if first.size() > 0:
						_soldier.play(first[0])
						_filling = true
						_select_text(_pv2_anim, String(first[0]))
						_filling = false
					break
	_gizmo_refresh()


func _on_anim_selected(i: int) -> void:
	if _filling or _soldier == null or i < 0:
		return
	var an := _pv2_anim.get_item_text(i)
	_soldier.play(an)
	# 그 동작이 든 세트를 `자세` 로
	var set_name := String(_soldier.current_set())
	var si := _set_index(set_name)
	if si >= 0 and si != _view_set.selected:
		_filling = true
		_view_set.select(si)
		_filling = false
		_on_view_set_changed()


## 3D: 고른 자세의 레스트 + 무기. 3D 보기가 꺼져 있으면 굽는 카메라 그대로(기즈모 계산용), 켜져 있으면 보는 각도·확대
func _apply_3d_view() -> void:
	if not _loaded or _busy:
		return
	var s := _cur_set()
	if s.is_empty():
		return
	if not eb.apply_set(s):
		_status.text = "⚠ " + ", ".join(eb.warnings)
		return
	eb.show_character(_show_char.button_pressed if _panel3d.visible else true)
	eb.place_weapon(String(s["name"]))
	if not _panel3d.visible:
		return
	var zoom := _view_zoom.value
	var view: Dictionary = (s["rig"] as Dictionary).get("view", {})
	var yaw := float(view.get("yaw", -55.0))
	match _view_angle.selected:
		1:
			eb.view_hand(zoom, -90.0 if yaw < 0.0 else 90.0, 0.0)
		2:
			eb.view_hand(zoom, 0.0, 0.0)
		3:
			eb.view_hand(zoom, yaw, 85.0)
		4:
			eb.view_hand(zoom, yaw + 180.0, 0.0)
		_:
			eb.view_hand(zoom)


# ---------------------------------------------------------------- 2D 미리보기

func _build_soldier() -> void:
	if is_instance_valid(_soldier):
		_soldier.queue_free()
	_soldier = DRPuppetSet.new()
	_soldier.name = "PreviewSoldier"
	_soldier.run_in_editor = true
	_soldier.force_loop = true
	_soldier.sets_json = eb.sets_json
	_soldier.position = Vector2(_vp2.size.x * 0.5, _vp2.size.y * 0.85)
	_soldier.scale = Vector2(_pv2_zoom.value, _pv2_zoom.value)
	_soldier.speed_scale = 1.0 if _pv2_play.button_pressed else 0.0
	_vp2.add_child(_soldier)
	_vp2.move_child(_gizmo, _vp2.get_child_count() - 1)
	await get_tree().process_frame
	_filling = true
	_pv2_anim.clear()
	for an in _soldier.get_animations():
		_pv2_anim.add_item(String(an))
	_filling = false
	# 옛 방식(z 간격 1)으로 구운 세트는 무기를 파트 사이에 못 끼운다
	var old := PackedStringArray()
	for e in _soldier._entries:
		var pup := (e as Dictionary)["puppet"] as DRPuppet
		if pup != null and pup._z_gap() == 0:
			old.append(String((e as Dictionary)["name"]))
	if old.size() > 0:
		_pv2_msg.text = "⚠ 옛 방식(파트 z 간격 1)으로 구운 세트라 무기 자리가 정확히 안 보입니다: %s — 메인 창에서 세트를 다시 구우세요." % ", ".join(old)
	else:
		_pv2_msg.text = ""


func _refresh_pv2() -> void:
	if not _loaded or eb == null:
		return
	_busy = true
	var keep_msg := _pv2_msg.text
	_status.text = "2D 미리보기 굽는 중…"
	eb.warnings = PackedStringArray()
	var baked: Dictionary = await eb.bake_all(_sets)
	_last_baked = baked
	if is_instance_valid(_soldier):
		_soldier.equip(eb.build_equip_set(baked))
	_busy = false
	_apply_3d_view()
	var msg := "준비됨 — 오른쪽 2D 에서 기즈모로 맞추고 `굽기`."
	if eb.warnings.size() > 0:
		msg = "⚠ " + "\n⚠ ".join(eb.warnings)
	_status.text = msg
	_pv2_msg.text = keep_msg
	# 앞 조각 요약
	var lines := PackedStringArray()
	for k in baked.keys():
		var r: Dictionary = baked[k]
		var ovs: Array = r.get("overlays", [])
		if ovs.is_empty():
			lines.append("%s: 없음" % k)
		else:
			var parts := PackedStringArray()
			for o in ovs:
				parts.append("%s %dpx" % [String((o as Dictionary)["part"]), int((o as Dictionary).get("pixels", 0))])
			lines.append("%s: %s" % [k, ", ".join(parts)])
	_front_status.text = ("앞 조각 — " + " · ".join(lines)) if eb.front_pieces else "앞 조각 꺼짐"
	_gizmo_refresh()


func _process(delta: float) -> void:
	if not visible or not _loaded:
		return
	if _pv2_dirty and not _busy and _gz_active == "":
		_pv2_timer -= delta
		if _pv2_timer <= 0.0:
			_pv2_dirty = false
			_refresh_pv2()
	if is_instance_valid(_soldier):
		var a := _pv2_aim.value
		_soldier.aim_enabled = absf(a) > 0.5
		if _soldier.aim_enabled:
			var pup := _soldier.get_puppet()
			var b: Bone2D = pup.get_bone(_soldier.aim_part) if pup != null else null
			if b != null:
				var r := deg_to_rad(a)
				_soldier.aim_target = b.global_position + Vector2(cos(r), -sin(r)) * 400.0
		if _gizmo.visible and _gz_active == "":
			_gizmo.pivot = _pivot_vp()
			_gizmo.queue_redraw()


# ---------------------------------------------------------------- 기즈모

func _gizmo_refresh() -> void:
	if _gizmo == null:
		return
	_gizmo.visible = _loaded and _gz_show.button_pressed and is_instance_valid(_soldier)
	if _gizmo.visible:
		_gizmo.label = ("받치는 손" if _gz_support.button_pressed else "붙일 손") + (" · 이 자세만" if _gz_set_only.button_pressed else "")
		_gizmo.pivot = _pivot_vp()
		_gizmo.queue_redraw()


func _gz_part() -> String:
	return eb.support_part if _gz_support.button_pressed else eb.attach_part


## 기준 손의 손바닥 — 지금 자세의 퍼펫 뼈를 따라(뷰포트 좌표)
func _pivot_vp() -> Vector2:
	if not is_instance_valid(_soldier):
		return Vector2.ZERO
	var pup := _soldier.get_puppet()
	if pup == null:
		return Vector2.ZERO
	var part := _gz_part()
	var b := pup.get_bone(part)
	if b == null:
		return Vector2.ZERO
	var baked: Dictionary = _last_baked.get(String(_soldier.current_set()), {})
	var pc: Vector2 = baked.get("palm_support" if _gz_support.button_pressed else "palm_attach", Vector2.ZERO)
	var head := pup.get_rest_head(part)
	if pc == Vector2.ZERO:
		pc = head
	return b.to_global((pc - head).rotated(-b.get_bone_angle()))


## TextureRect 좌표 → 뷰포트 좌표(KEEP_ASPECT_CENTERED)
func _pv2_to_vp(p: Vector2) -> Vector2:
	var rs := _pv2.size
	var vs := Vector2(_vp2.size)
	var sc := minf(rs.x / vs.x, rs.y / vs.y)
	var off := (rs - vs * sc) * 0.5
	return (p - off) / sc


func _on_pv2_input(ev: InputEvent) -> void:
	if not _loaded or not _gizmo.visible or _busy:
		return
	if ev is InputEventMouseMotion:
		var vp := _pv2_to_vp((ev as InputEventMouseMotion).position)
		if _gz_active == "":
			var h := _gizmo.hit(vp)
			if h != _gizmo.hot:
				_gizmo.hot = h
				_gizmo.queue_redraw()
			_pv2.mouse_default_cursor_shape = Control.CURSOR_ARROW if h == "" else (Control.CURSOR_CROSS if h == "rot" else Control.CURSOR_MOVE)
		else:
			_gz_update(vp, (ev as InputEventMouseMotion).shift_pressed)
			_pv2.accept_event()
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := ev as InputEventMouseButton
		var vp := _pv2_to_vp(mb.position)
		if mb.pressed:
			var h := _gizmo.hit(vp)
			if h != "":
				_gz_begin(h, vp)
				_pv2.accept_event()
		elif _gz_active != "":
			_gz_end()
			_pv2.accept_event()


func _gz_begin(handle: String, vp: Vector2) -> void:
	var spr := _cur_weapon_sprite()
	if spr == null:
		return
	_gz_active = handle
	_gizmo.active = handle
	_gz_start_vp = vp
	_gz_pivot_vp = _gizmo.pivot
	_gz_spr_pos = spr.position
	_gz_spr_rot = spr.rotation
	_gz_delta_px = Vector2.ZERO
	_gz_dtheta = 0.0
	_gizmo.queue_redraw()


func _cur_weapon_sprite() -> Sprite2D:
	if not is_instance_valid(_soldier):
		return null
	var pup := _soldier.get_puppet()
	return pup.get_equipped(eb.slot) if pup != null else null


## 끄는 동안: 화면의 무기 그림을 바로 옮겨 보여 준다(놓으면 조정값으로 바꿔 다시 굽는다)
func _gz_update(vp: Vector2, fine: bool) -> void:
	var spr := _cur_weapon_sprite()
	if spr == null:
		return
	var k := GZ_FINE if fine else 1.0
	var host := spr.get_parent() as Node2D
	var d := (vp - _gz_start_vp) * k
	match _gz_active:
		"x":
			d.y = 0.0
		"y":
			d.x = 0.0
		"rot":
			d = Vector2.ZERO
	var dtheta := 0.0
	if _gz_active == "rot":
		var a0 := (_gz_start_vp - _gz_pivot_vp).angle()
		var a1 := (vp - _gz_pivot_vp).angle()
		dtheta = wrapf(a1 - a0, -PI, PI) * k
	var sc := absf(_soldier.scale.x)
	_gz_delta_px = d / maxf(sc, 0.0001)
	_gz_dtheta = dtheta
	# 그림 미리 옮기기(호스트 로컬)
	var d_local := host.global_transform.basis_xform_inv(d)
	var pivot_local := host.to_local(_gz_pivot_vp)
	spr.position = pivot_local + (_gz_spr_pos - pivot_local).rotated(dtheta) + d_local
	spr.rotation = _gz_spr_rot + dtheta
	_gizmo.pivot = _gz_pivot_vp
	_gizmo.queue_redraw()


func _gz_end() -> void:
	var handle := _gz_active
	_gz_active = ""
	_gizmo.active = ""
	_gizmo.queue_redraw()
	if handle == "":
		return
	if _gz_delta_px.length() < 0.01 and absf(_gz_dtheta) < 0.0001:
		return
	_commit_gizmo(_gz_delta_px, _gz_dtheta)


## 화면 이동(캔버스 px)·회전을 조정값으로 바꿔 넣는다
func _commit_gizmo(delta_px: Vector2, dtheta: float) -> void:
	var s := _cur_set()
	if s.is_empty() or not eb.apply_set(s):
		return
	var name := String(s["name"])
	eb.place_weapon(name)
	var pivot := eb.palm_world(_gz_part())
	var total: Dictionary = eb.nudge_to_adjust(name, delta_px, dtheta, pivot)
	var a := eb.adjust_of(name)
	if _gz_set_only.button_pressed:
		eb.set_adjust_of(name, Vector3(total["pos"]) - eb.adj_pos, Vector3(total["rot"]) - eb.adj_rot,
			bool(a["z_override"]), String(a["z_after_part"]), int(a["z_index"]))
	else:
		eb.adj_pos = Vector3(total["pos"]) - Vector3(a["pos"])
		eb.adj_rot = Vector3(total["rot"]) - Vector3(a["rot"])
	_filling = true
	_set_vec(_adj_pos, eb.adj_pos * 100.0)
	_set_vec(_adj_rot, eb.adj_rot)
	_filling = false
	_fill_set_adjust()
	_grip_changed()


# ---------------------------------------------------------------- 굽기 · 가져오기 형식

func _on_bake() -> void:
	if not _loaded or _busy:
		return
	_busy = true
	_bake_btn.disabled = true
	eb.out_dir = _out_edit.text.strip_edges()
	eb.id = _id_edit.text.strip_edges() if _id_edit.text.strip_edges() != "" else eb.id
	eb.slot = _slot_edit.text.strip_edges()
	var cb := func(i, n, name):
		_progress.max_value = n
		_progress.value = i + 1
		_status.text = "굽는 중 %d/%d — %s" % [i + 1, n, name]
	eb.progress.connect(cb)
	var res: Dictionary = await eb.run()
	eb.progress.disconnect(cb)
	_busy = false
	_bake_btn.disabled = false
	_progress.value = 0
	_apply_3d_view()
	if bool(res.get("ok", false)):
		var n := (res["sets"] as Dictionary).size()
		var n_ov := 0
		for k in (res["sets"] as Dictionary).keys():
			n_ov += ((res["sets"] as Dictionary)[k] as Dictionary).get("overlays", []).size()
		_status.text = "완료 — 자세 %d개 · 앞 조각 %d개 → %s\n게임: soldier.equip(DREquipSet.load_json(\"%s\"))" % [n, n_ov, String(res["json"]).get_base_dir(), String(res["json"])]
		var ws: PackedStringArray = res.get("warnings", PackedStringArray())
		if ws.size() > 0:
			_status.text += "\n⚠ " + "\n⚠ ".join(ws)
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().scan()
	else:
		_status.text = "⚠ 굽기 실패: %s" % String(res.get("error", "?"))


## OBJ 의 가져오기 형식을 Scene 으로 바꾸고 다시 가져와서(파트별 노드) 다시 불러온다 — 에디터에서만
func _on_make_scene_import() -> void:
	var p := _weapon_edit.text.strip_edges()
	var imp := p + ".import"
	if not FileAccess.file_exists(imp):
		_status.text = "⚠ .import 파일이 없습니다: %s" % imp
		return
	var cf := ConfigFile.new()
	if cf.load(imp) != OK:
		_status.text = "⚠ .import 를 읽을 수 없습니다"
		return
	cf.set_value("remap", "importer", "scene")
	cf.set_value("remap", "type", "PackedScene")
	if cf.has_section("params"):
		cf.erase_section("params")
	cf.save(imp)
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		fs.reimport_files(PackedStringArray([p]))
		while fs.is_scanning():
			await get_tree().process_frame
		await get_tree().process_frame
	_on_load()
