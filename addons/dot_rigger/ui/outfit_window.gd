@tool
extends Window
class_name DROutfitWindow

## Dot Rigger — 복장 굽기 창(옷만 갈아입히기).  프로젝트 > 도구 > Dot Rigger — 복장 굽기.
##
## 왼쪽: 1 기본 몸 프리셋 · sets.json · 옷 모델 → 불러오기
##       2 옷 모델 새로 만들기 — AI 원본(Tripo 등)을 기본 뼈대에 붙인다(Blender 를 대신 돌림)
##       3 부위 칠하기 — 어느 정점을 어느 조각(파트)으로 자를지 붓으로 고친다(상의 자락 → 몸통 등)
##       4 슬롯 — 파트마다 상의 · 하의 · 신발 · 안 씀
##       바닥: 복장 굽기 → <출력 폴더>/<복장 이름>/outfit.json
## 오른쪽: 2D 미리보기 — 기본 몸 퍼펫(DRPuppetSet)에 지금 상태로 임시로 구운 옷을 입혀 재생(상의 · 하의 · 신발 켜고 끄기)
##         3D 부위 칠하기 — 옷 모델(T-포즈)을 부위 색으로 보고 왼쪽 버튼으로 칠한다
##
## 옷은 3D 메시를 떼는 게 아니다: 옷 입은 모델을 기본 몸 세트와 같은 카메라 · 같은 자세로 부위별 2D 그림으로 굽고,
## 퍼펫의 그 부위 그림만 바꿔 끼운다. 부위 경계는 정점마다 웨이트가 가장 센 뼈로 정해지고, 칠하기로 바꿀 수 있다.

const MODEL_FILTER := "*.glb, *.gltf, *.tscn, *.scn ; 뼈대에 붙인 옷 모델"
const RAW_FILTER := "*.glb, *.gltf ; AI 원본(Tripo 등)"
const PRESET_FILTER := "*.tres ; 기본 몸 프리셋"
const SETS_FILTER := "*.json ; 세트 목록(sets.json)"
const OUTFIT_FILTER := "*.json ; 구운 복장(outfit.json)"
const BLENDER_DEFAULT := "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
const BLENDER_SETTING := "dot_rigger/blender_path"
const BIND_SCRIPT := "res://pipeline/blender/bind_to_skeleton.py"
const WEIGHT_BASE_DEFAULT := "res://source3d/UAL1_humanoid.glb"
const PV_DEBOUNCE := 0.5
const SLOT_KEYS := ["top", "bottom", "shoes", ""]
const ERASE := ""                  # 칠할 부위 "" = 지우개(웨이트대로)
const PART_COLORS := {
	"Hips": Color(0.86, 0.74, 0.2), "Torso": Color(0.92, 0.33, 0.28), "Head": Color(0.98, 0.84, 0.66),
	"L_UpperArm": Color(0.25, 0.55, 0.98), "L_Forearm": Color(0.2, 0.82, 0.86), "L_Hand": Color(0.65, 0.92, 1.0),
	"R_UpperArm": Color(0.58, 0.32, 0.92), "R_Forearm": Color(0.86, 0.38, 0.9), "R_Hand": Color(0.97, 0.72, 0.97),
	"L_Thigh": Color(0.24, 0.72, 0.32), "L_Calf": Color(0.55, 0.86, 0.28), "L_Foot": Color(0.78, 0.96, 0.55),
	"R_Thigh": Color(0.96, 0.52, 0.16), "R_Calf": Color(0.98, 0.7, 0.34), "R_Foot": Color(1.0, 0.86, 0.56),
}

var baker: DRBaker
var ob: DROutfitBaker
var _scene_path := ""
var _loaded := false
var _busy := false
var _filling := false
var _pv_dirty := false
var _pv_timer := 0.0
var _resplit_dirty := false
var _resplit_timer := 0.0
var _outfit: DROutfit           # 미리보기용(메모리)
var _baked: Dictionary = {}
var _restore_slots: Dictionary = {}

# 칠하기 데이터
var _ov: DRPartOverrides
var _pm_pos := PackedVector3Array()     # 표시 메시 정점(바인드 자세 · 모든 서피스 이어 붙임)
var _pm_nrm := PackedVector3Array()
var _pm_auto := PackedStringArray()     # 웨이트대로의 파트
var _pm_surf: Array = []                # [{arrays, start, count, material}]
var _tri_a := PackedVector3Array()      # 고르기(광선)용 삼각형
var _tri_e1 := PackedVector3Array()
var _tri_e2 := PackedVector3Array()
var _pm_mesh: ArrayMesh
var _paint_part := "Torso"
var _painting := false
var _stroke: Dictionary = {}            # 이번 붓질에서 바뀐 키 -> 바뀌기 전 파트("" = 웨이트대로)
var _undo: Array = []
var _last_pick_px := Vector2(-999, -999)
var _brush_hit := false
var _brush_pos := Vector3.ZERO

# 1
var _preset_edit: LineEdit
var _sets_edit: LineEdit
var _model_edit: LineEdit
var _id_edit: LineEdit
var _load_btn: Button
var _open_btn: Button
var _load_status: Label
# 2 붙이기
var _raw_edit: LineEdit
var _wbase_edit: LineEdit
var _smooth_spin: SpinBox
var _hand_cb: CheckBox
var _thumb_cb: CheckBox
var _partfix_cb: CheckBox
var _blender_edit: LineEdit
var _bind_btn: Button
var _bind_status: Label
var _bind_thread: Thread
# 3 칠하기
var _part_btns: Dictionary = {}         # 파트(지우개 "") -> Button
var _brush_spin: SpinBox
var _front_only: CheckBox
var _undo_btn: Button
var _clear_btn: Button
var _paint_status: Label
# 4 슬롯
var _slot_grid: GridContainer
var _slot_opts: Dictionary = {}         # 파트 -> OptionButton
# 바닥
var _out_edit: LineEdit
var _bake_btn: Button
var _progress: ProgressBar
var _status: Label
# 2D
var _view_set: OptionButton
var _pv_anim: OptionButton
var _pv_play: CheckBox
var _wear_cb: Dictionary = {}           # slot -> CheckBox
var _pv_zoom: HSlider
var _vp2: SubViewport
var _pv2: TextureRect
var _soldier: DRPuppetSet
var _pv_msg: Label
# 3D
var _view_mode: OptionButton
var _vp3: SubViewport
var _pv3: TextureRect
var _cam3: Camera3D
var _pm_mi: MeshInstance3D
var _brush_mi: MeshInstance3D
var _mat_part: StandardMaterial3D
var _mat_tex: StandardMaterial3D
var _mat_mix: StandardMaterial3D
var _cam_target := Vector3(0, 0.9, 0)
var _cam_yaw := 0.0
var _cam_pitch := 0.0
var _cam_dist := 3.0
var _drag := ""                         # "orbit" · "pan"
var _drag_from := Vector2.ZERO


func _init() -> void:
	title = "Dot Rigger — 복장 굽기 (옷 갈아입히기)"
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	size = Vector2i(1360, 820)
	min_size = Vector2i(1100, 660)
	exclusive = false
	close_requested.connect(func(): hide())
	_build_ui()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_teardown()
		if _bind_thread != null and _bind_thread.is_started():
			_bind_thread.wait_to_finish()


# ---------------------------------------------------------------- UI 구성

func _build_ui() -> void:
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.split_offset = 430
	add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(400, 0)
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
	_build_section_bind(col)
	_build_section_paint(col)
	_build_section_slots(col)
	_build_footer(left)

	var right := HSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_build_preview2d(right)
	_build_preview3d(right)


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


func _hint(parent: Control, text: String, min_w: float = 360.0) -> Label:
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


func _check(parent: Control, text: String, on: bool, tip: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	_tip(c, tip)
	parent.add_child(c)
	return c


func _build_section_source(col: Control) -> void:
	var s := _section(col, "1. 기본 몸 · 세트 · 옷 모델")
	_hint(s, "기본 몸(민소매)으로 구운 세트에 옷을 입힌다. 옷 모델은 같은 뼈대에 붙인 것(2번에서 만들거나 이미 붙인 .glb). `불러오기` 하면 오른쪽에 입힌 모습과 3D 부위 색이 나온다.")
	_preset_edit = _path_row(s, "기본 몸 프리셋", "메인 창에서 기본 몸 세트를 구울 때 쓴 프리셋(.tres) — 도트화 값 · 추가 동작 폴더를 같게 맞추려고 읽는다(모델은 옷 모델로 바꿔 굽는다).", _on_browse_preset)
	_preset_edit.text = _default_preset()
	_sets_edit = _path_row(s, "세트 목록", "기본 몸으로 구운 sets.json. 세트마다 같은 카메라 · 같은 레스트 자세로 옷이 구워진다.", _on_browse_sets)
	_sets_edit.text = "res://puppet/sets.json"
	_model_edit = _path_row(s, "옷 모델", "기본 몸과 같은 뼈대에 붙인 옷 입은 모델(.glb). 머리 · 손은 굽지 않고 기본 몸 것을 쓴다.", _on_browse_model)
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "복장 이름"
	l.custom_minimum_size = Vector2(110, 0)
	row.add_child(l)
	_id_edit = LineEdit.new()
	_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_id_edit.placeholder_text = "예: m36"
	_tip(_id_edit, "결과 폴더 이름(<출력 폴더>/<복장 이름>/outfit.json). 2번 붙이기의 결과 이름으로도 쓴다.")
	row.add_child(_id_edit)
	s.add_child(row)
	var brow := HBoxContainer.new()
	_load_btn = Button.new()
	_load_btn.text = "불러오기"
	_load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_load_btn.pressed.connect(_on_load)
	brow.add_child(_load_btn)
	_open_btn = Button.new()
	_open_btn.text = "구운 복장 열기…"
	_tip(_open_btn, "출력 폴더의 <복장 이름>/outfit.json 을 골라 그때의 옷 모델 · 세트 · 슬롯으로 다시 연다.")
	_open_btn.pressed.connect(_on_open_outfit)
	brow.add_child(_open_btn)
	s.add_child(brow)
	_load_status = _hint(s, "")


func _build_section_bind(col: Control) -> void:
	var s := _section(col, "2. 옷 모델 새로 만들기 (AI 원본 → 뼈대에 붙이기)", true)
	_hint(s, "Tripo 등으로 뽑은 옷 입은 사람(.glb, 통짜)을 기본 뼈대에 붙인다 — 방향 맞추기 · 키 맞추기 · 웨이트 옮기기 · 손가락/엄지 맞추기 · 관절 경계 정리. Blender 를 뒤에서 돌리며 수십 초 걸린다. 결과는 res://source3d/characters/<복장 이름>/<복장 이름>.glb 이고 끝나면 1번 옷 모델로 들어가 불러온다.")
	_raw_edit = _path_row(s, "AI 원본", "AI 가 뽑은 .glb — 보통 pipeline/comfy/ 아래(이 폴더는 Godot 가 무시하므로 디스크 경로로 고른다).", _on_browse_raw)
	_wbase_edit = _path_row(s, "웨이트 원본 몸", "웨이트(어느 살이 어느 뼈를 따라가나)를 가져올 몸 — 기본은 뼈대의 주인인 UAL1 마네킹.", _on_browse_wbase)
	_wbase_edit.text = WEIGHT_BASE_DEFAULT
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "웨이트 부드럽게"
	l.custom_minimum_size = Vector2(110, 0)
	_tip(l, "관절 주변 웨이트를 이웃 정점 평균으로 몇 번 번지게 할지(0 = 마네킹처럼 칼같이). 클수록 관절이 부드럽게 휜다.")
	row.add_child(l)
	_smooth_spin = SpinBox.new()
	_smooth_spin.min_value = 0
	_smooth_spin.max_value = 40
	_smooth_spin.step = 1
	_smooth_spin.value = 12
	row.add_child(_smooth_spin)
	s.add_child(row)
	_hand_cb = _check(s, "손가락 맞춤", true, "AI 손이 마네킹 손과 크기 · 간격이 달라 손가락 웨이트가 한 칸씩 밀리는 것을 막는다.")
	_thumb_cb = _check(s, "엄지 맞춤", true, "AI 엄지를 엄지뼈 방향으로 돌려 놓고 웨이트를 옮긴다 — 주먹 쥘 때 엄지가 튀어나오지 않게.")
	_partfix_cb = _check(s, "관절 경계 정리", true, "어깨 · 팔꿈치 · 고관절 · 무릎에 평면을 세워 조각 경계를 관절에 맞춘다(겨드랑이 살이 팔 조각에 붙는 것 등). 더 고칠 곳은 3번 칠하기로.")
	_blender_edit = _path_row(s, "Blender", "blender.exe 경로", _on_browse_blender)
	_blender_edit.text = _blender_path()
	_blender_edit.text_changed.connect(func(t):
		if Engine.is_editor_hint():
			EditorInterface.get_editor_settings().set_setting(BLENDER_SETTING, t))
	_bind_btn = Button.new()
	_bind_btn.text = "뼈대에 붙이기"
	_bind_btn.pressed.connect(_on_bind)
	s.add_child(_bind_btn)
	_bind_status = _hint(s, "")


func _build_section_paint(col: Control) -> void:
	var s := _section(col, "3. 부위 칠하기")
	_hint(s, "오른쪽 3D 에서 왼쪽 버튼으로 칠한다(붓 = 공 모양 범위). 오른쪽 버튼 끌기 = 돌려 보기 · 가운데 끌기 = 옮기기 · 휠 = 확대 · F = 맞춤 · Ctrl+Z = 되돌리기. 칠한 정점은 웨이트 대신 칠한 부위의 조각으로 잘린다(3D 움직임은 그대로). 예: 상의 자락을 Torso 로 칠하면 상의와 같이 입고 벗는다.")
	var grid := GridContainer.new()
	grid.columns = 3
	s.add_child(grid)
	var group := ButtonGroup.new()
	var order := ["Head", "Torso", "Hips", "L_UpperArm", "L_Forearm", "L_Hand", "R_UpperArm", "R_Forearm", "R_Hand",
		"L_Thigh", "L_Calf", "L_Foot", "R_Thigh", "R_Calf", "R_Foot", ERASE]
	for pn in order:
		var cell := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(14, 14)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.color = PART_COLORS.get(pn, Color(0.35, 0.35, 0.35))
		cell.add_child(sw)
		var b := Button.new()
		b.text = String(pn) if pn != ERASE else "지우개"
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tip(b, "이 부위로 칠한다" if pn != ERASE else "칠한 것을 지운다(그 정점은 다시 웨이트대로)")
		var part_name: String = pn
		b.pressed.connect(func(): _paint_part = part_name)
		cell.add_child(b)
		grid.add_child(cell)
		_part_btns[pn] = b
	(_part_btns["Torso"] as Button).button_pressed = true
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "붓 크기(cm)"
	row.add_child(l)
	_brush_spin = SpinBox.new()
	_brush_spin.min_value = 0.5
	_brush_spin.max_value = 40.0
	_brush_spin.step = 0.5
	_brush_spin.value = 4.0
	_brush_spin.value_changed.connect(func(_v): _update_brush())
	row.add_child(_brush_spin)
	_front_only = CheckBox.new()
	_front_only.text = "보이는 면만"
	_tip(_front_only, "카메라 쪽을 보는 정점만 칠한다(얇은 천의 뒤쪽까지 칠해지지 않게). 끄면 붓 범위 안을 모두.")
	row.add_child(_front_only)
	s.add_child(row)
	var brow := HBoxContainer.new()
	_undo_btn = Button.new()
	_undo_btn.text = "되돌리기 (Ctrl+Z)"
	_undo_btn.pressed.connect(_on_undo)
	brow.add_child(_undo_btn)
	_clear_btn = Button.new()
	_clear_btn.text = "칠한 것 모두 지우기"
	_clear_btn.pressed.connect(_on_clear_paint)
	brow.add_child(_clear_btn)
	s.add_child(brow)
	_paint_status = _hint(s, "")


func _build_section_slots(col: Control) -> void:
	var s := _section(col, "4. 슬롯 (어느 옷으로 쓸지)")
	_hint(s, "파트마다 상의 · 하의 · 신발 · 안 씀. 게임에서 상의만 / 하의만 따로 입힐 때 이 묶음을 쓴다(시험장 O · P 키). 안 씀(머리 · 손)은 굽지 않고 기본 몸 그대로.")
	_slot_grid = GridContainer.new()
	_slot_grid.columns = 4
	s.add_child(_slot_grid)
	var order := ["Torso", "Hips", "Head", "L_UpperArm", "R_UpperArm", "L_Forearm", "R_Forearm", "L_Hand", "R_Hand",
		"L_Thigh", "R_Thigh", "L_Calf", "R_Calf", "L_Foot", "R_Foot"]
	for pn in order:
		var l := Label.new()
		l.text = String(pn)
		_slot_grid.add_child(l)
		var o := OptionButton.new()
		for k in SLOT_KEYS:
			o.add_item(String(DROutfitBaker.SLOT_NAMES[k]))
		o.select(SLOT_KEYS.find(String(DROutfitBaker.DEFAULT_SLOTS.get(pn, ""))))
		var part_name: String = pn
		o.item_selected.connect(func(i): _on_slot_changed(part_name, i))
		_slot_grid.add_child(o)
		_slot_opts[pn] = o


func _build_footer(left: Control) -> void:
	var foot := VBoxContainer.new()
	foot.add_theme_constant_override("separation", 4)
	left.add_child(foot)
	foot.add_child(HSeparator.new())
	_out_edit = _path_row(foot, "출력 폴더", "여기 아래 <복장 이름>/ 에 세트별 파트 PNG 와 outfit.json 이 생긴다.", _on_browse_out)
	_out_edit.text = "res://outfits"
	_bake_btn = Button.new()
	_bake_btn.text = "복장 굽기 (모든 자세)"
	_bake_btn.disabled = true
	_tip(_bake_btn, "sets.json 의 모든 세트에 지금 칠하기 · 슬롯으로 굽고 파일로 남긴다. 게임: soldier.wear(DROutfit.load_json(\"…/outfit.json\"))")
	_bake_btn.pressed.connect(_on_bake)
	foot.add_child(_bake_btn)
	_progress = ProgressBar.new()
	_progress.min_value = 0
	_progress.max_value = 1
	foot.add_child(_progress)
	_status = _hint(foot, "먼저 1번에서 `불러오기`.")


func _build_preview2d(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(340, 0)
	parent.add_child(box)
	var bar := HFlowContainer.new()
	box.add_child(bar)
	var l0 := Label.new()
	l0.text = "2D  자세"
	bar.add_child(l0)
	_view_set = OptionButton.new()
	_view_set.item_selected.connect(func(_i): _on_view_set_changed())
	bar.add_child(_view_set)
	_pv_anim = OptionButton.new()
	_pv_anim.item_selected.connect(func(i): _on_anim_selected(i))
	bar.add_child(_pv_anim)
	_pv_play = CheckBox.new()
	_pv_play.text = "재생"
	_pv_play.button_pressed = true
	_pv_play.toggled.connect(func(on):
		if _soldier != null:
			_soldier.speed_scale = 1.0 if on else 0.0)
	bar.add_child(_pv_play)
	for k in ["top", "bottom", "shoes"]:
		var c := CheckBox.new()
		c.text = String(DROutfitBaker.SLOT_NAMES[k])
		c.button_pressed = true
		_tip(c, "미리보기에서 이 슬롯을 입힌다/벗긴다(굽기에는 영향 없음)")
		c.toggled.connect(func(_on): _apply_wear())
		bar.add_child(c)
		_wear_cb[k] = c
	var l3 := Label.new()
	l3.text = " 확대"
	bar.add_child(l3)
	_pv_zoom = HSlider.new()
	_pv_zoom.min_value = 0.3
	_pv_zoom.max_value = 3.0
	_pv_zoom.step = 0.05
	_pv_zoom.value = 1.0
	_pv_zoom.custom_minimum_size = Vector2(80, 0)
	_pv_zoom.value_changed.connect(func(vv):
		if _soldier != null:
			_soldier.scale = Vector2(vv, vv))
	bar.add_child(_pv_zoom)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(panel)
	_pv2 = TextureRect.new()
	_pv2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pv2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pv2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tip(_pv2, "기본 몸으로 구운 퍼펫에 지금 칠하기 · 슬롯으로 임시로 구운 옷을 입힌 모습 — 게임에서 보이는 그대로.")
	panel.add_child(_pv2)
	_vp2 = SubViewport.new()
	_vp2.size = Vector2i(460, 620)
	_vp2.transparent_bg = false
	_vp2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp2)
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.42, 0.36)
	bg.size = Vector2(_vp2.size)
	_vp2.add_child(bg)
	_pv2.texture = _vp2.get_texture()
	_pv_msg = _hint(box, "", 300.0)


func _build_preview3d(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(340, 0)
	parent.add_child(box)
	var bar := HFlowContainer.new()
	box.add_child(bar)
	var l1 := Label.new()
	l1.text = "3D 부위 칠하기  보기"
	bar.add_child(l1)
	_view_mode = OptionButton.new()
	for n in ["부위 색", "원래 텍스처", "섞어서"]:
		_view_mode.add_item(n)
	_view_mode.item_selected.connect(func(_i): _apply_view_mode())
	bar.add_child(_view_mode)
	for pair in [["정면", 0.0], ["옆", 90.0], ["뒤", 180.0], ["반대 옆", -90.0]]:
		var b := Button.new()
		b.text = String(pair[0])
		var yaw_deg: float = pair[1]
		b.pressed.connect(func():
			_cam_yaw = deg_to_rad(yaw_deg)
			_cam_pitch = 0.0
			_update_cam())
		bar.add_child(b)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(panel)
	_pv3 = TextureRect.new()
	_pv3.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pv3.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pv3.mouse_filter = Control.MOUSE_FILTER_STOP
	_pv3.focus_mode = Control.FOCUS_ALL
	_pv3.gui_input.connect(_on_pv3_input)
	_pv3.resized.connect(func():
		if _vp3 != null:
			_vp3.size = Vector2i(maxi(64, int(_pv3.size.x)), maxi(64, int(_pv3.size.y))))
	panel.add_child(_pv3)
	_vp3 = SubViewport.new()
	_vp3.size = Vector2i(460, 620)
	_vp3.own_world_3d = true
	_vp3.transparent_bg = false
	_vp3.msaa_3d = Viewport.MSAA_4X
	_vp3.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp3)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.21, 0.24)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = env
	_vp3.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-35), deg_to_rad(-30), 0)
	sun.light_energy = 0.8
	_vp3.add_child(sun)
	_cam3 = Camera3D.new()
	_cam3.fov = 30.0
	_vp3.add_child(_cam3)
	_pm_mi = MeshInstance3D.new()
	_vp3.add_child(_pm_mi)
	_brush_mi = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	_brush_mi.mesh = sph
	var bm := StandardMaterial3D.new()
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(1, 1, 1, 0.25)
	bm.no_depth_test = true
	_brush_mi.material_override = bm
	_brush_mi.visible = false
	_vp3.add_child(_brush_mi)
	_mat_part = StandardMaterial3D.new()
	_mat_part.vertex_color_use_as_albedo = true
	_mat_part.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_tex = StandardMaterial3D.new()
	_mat_tex.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_mix = StandardMaterial3D.new()
	_mat_mix.vertex_color_use_as_albedo = true
	_mat_mix.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pv3.texture = _vp3.get_texture()
	_hint(box, "왼쪽 버튼 = 칠하기 · 오른쪽 끌기 = 돌리기 · 가운데 끌기 = 옮기기 · 휠 = 확대 · F = 맞춤 · Ctrl+Z = 되돌리기", 300.0)


# ---------------------------------------------------------------- 파일 고르기

func _file_dialog(filter: String, title_text: String, dir_mode: bool, on_selected: Callable, disk: bool = false, start_dir: String = "") -> void:
	var efd := EditorFileDialog.new()
	var dlg: Window = efd
	if efd != null:
		efd.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR if dir_mode else EditorFileDialog.FILE_MODE_OPEN_FILE
		efd.access = EditorFileDialog.ACCESS_FILESYSTEM if disk else EditorFileDialog.ACCESS_RESOURCES
		if not dir_mode and filter != "":
			efd.filters = PackedStringArray([filter])
		if start_dir != "":
			efd.current_dir = start_dir
	else:
		var f := FileDialog.new()
		f.file_mode = FileDialog.FILE_MODE_OPEN_DIR if dir_mode else FileDialog.FILE_MODE_OPEN_FILE
		f.access = FileDialog.ACCESS_FILESYSTEM if disk else FileDialog.ACCESS_RESOURCES
		f.use_native_dialog = false
		if not dir_mode and filter != "":
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
	_file_dialog(PRESET_FILTER, "기본 몸 프리셋 — Dot Rigger", false, func(p): _preset_edit.text = p)


func _on_browse_sets() -> void:
	_file_dialog(SETS_FILTER, "세트 목록(sets.json) — Dot Rigger", false, func(p): _sets_edit.text = p)


func _on_browse_model() -> void:
	_file_dialog(MODEL_FILTER, "옷 모델 — Dot Rigger", false, func(p):
		_model_edit.text = p
		if _id_edit.text.strip_edges() == "":
			_id_edit.text = p.get_file().get_basename().to_lower()
		_on_load())


func _on_browse_raw() -> void:
	_file_dialog(RAW_FILTER, "AI 원본(.glb) — Dot Rigger", false, func(p):
		_raw_edit.text = p
		if _id_edit.text.strip_edges() == "":
			_id_edit.text = p.get_file().get_basename().to_lower().get_slice("_", 0) + "_" + p.get_file().get_basename().to_lower().get_slice("_", 1)
	, true, ProjectSettings.globalize_path("res://pipeline/comfy"))


func _on_browse_wbase() -> void:
	_file_dialog(MODEL_FILTER, "웨이트 원본 몸 — Dot Rigger", false, func(p): _wbase_edit.text = p)


func _on_browse_blender() -> void:
	_file_dialog("*.exe ; Blender", "blender.exe — Dot Rigger", false, func(p): _blender_edit.text = p, true)


func _on_browse_out() -> void:
	_file_dialog("", "출력 폴더 — Dot Rigger", true, func(p): _out_edit.text = p)


func _on_open_outfit() -> void:
	var found := PackedStringArray()
	for base in [_out_edit.text.strip_edges(), "res://outfits"]:
		if base == "" or not DirAccess.dir_exists_absolute(base):
			continue
		for d in DirAccess.get_directories_at(base):
			var p := String(base).path_join(d).path_join("outfit.json")
			if FileAccess.file_exists(p) and not found.has(p):
				found.append(p)
	if found.is_empty():
		_file_dialog(OUTFIT_FILTER, "구운 복장(outfit.json) 열기 — Dot Rigger", false, func(p): _open_json(p))
		return
	var pm := PopupMenu.new()
	pm.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	for i in found.size():
		pm.add_item(found[i], i)
	pm.add_separator()
	pm.add_item("다른 파일…", found.size())
	pm.id_pressed.connect(func(id):
		pm.queue_free()
		if id >= 0 and id < found.size():
			_open_json(found[id])
		else:
			_file_dialog(OUTFIT_FILTER, "구운 복장(outfit.json) 열기 — Dot Rigger", false, func(p): _open_json(p)))
	pm.popup_hide.connect(func(): pm.queue_free.call_deferred())
	add_child(pm)
	var r := _open_btn.get_global_rect()
	pm.popup(Rect2i(Vector2i(r.position + Vector2(0, r.size.y)) + position, Vector2i(int(r.size.x), 0)))


## outfit.json 의 옷 모델 · 세트 · 슬롯으로 다시 연다
func _open_json(path: String) -> void:
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not (v is Dictionary):
		_status.text = "⚠ 읽을 수 없습니다: %s" % path
		return
	var d: Dictionary = v
	if String(d.get("model", "")) != "":
		_model_edit.text = String(d["model"])
	if String(d.get("sets_json", "")) != "":
		_sets_edit.text = String(d["sets_json"])
	_id_edit.text = String(d.get("id", path.get_base_dir().get_file()))
	_out_edit.text = path.get_base_dir().get_base_dir()
	_restore_slots = (d.get("slots", {}) as Dictionary).duplicate()
	_on_load()


static func _default_preset() -> String:
	if FileAccess.file_exists("res://human.tres"):
		return "res://human.tres"
	for f in DirAccess.get_files_at("res://"):
		if String(f).ends_with("_preset.tres") or String(f).ends_with(".tres"):
			var p := load("res://" + String(f))
			if p is DRPreset:
				return "res://" + String(f)
	return ""


static func _blender_path() -> String:
	if Engine.is_editor_hint():
		var es := EditorInterface.get_editor_settings()
		if es.has_setting(BLENDER_SETTING):
			return String(es.get_setting(BLENDER_SETTING))
	return BLENDER_DEFAULT


# ---------------------------------------------------------------- 불러오기

func _fail(msg: String) -> void:
	_load_status.text = "⚠ " + msg
	_status.text = "⚠ " + msg
	_busy = false
	_loaded = false
	_bake_btn.disabled = true


func _teardown() -> void:
	if baker != null:
		baker.cleanup()
	baker = null
	ob = null
	if is_instance_valid(_soldier):
		_soldier.queue_free()
	_soldier = null
	_outfit = null
	_baked = {}
	_loaded = false
	if _pm_mi != null:
		_pm_mi.mesh = null
	_undo.clear()
	_stroke.clear()


func _on_load() -> void:
	if _busy:
		return
	_busy = true
	_bake_btn.disabled = true
	_load_status.text = "불러오는 중…"
	var opts := DRBaker.Options.new()
	var preset_path := _preset_edit.text.strip_edges()
	if preset_path != "":
		var p := load(preset_path) as DRPreset
		if p == null:
			_fail("프리셋을 열 수 없습니다: %s" % preset_path)
			return
		opts.extra_anim_dir = p.extra_anim_dir
		opts.light_bands = p.light_bands
		opts.ambient = p.ambient
		opts.alpha_threshold = p.alpha_threshold
		opts.color_levels = p.color_levels
		opts.bleed_rings = p.bleed_rings
		opts.composites = p.composites.duplicate(true)
		opts.composite_upper_parts = p.composite_upper_parts
	var mpath := _model_edit.text.strip_edges()
	var scene := load(mpath) as PackedScene if mpath != "" and ResourceLoader.exists(mpath) else null
	if scene == null:
		_fail("옷 모델을 열 수 없습니다: %s (가져오기가 끝났는지 확인)" % mpath)
		return
	_teardown()
	_scene_path = mpath
	baker = DRBaker.new()
	if not baker.setup(self, scene, DRPartProfile.humanoid(), opts):
		_fail("옷 모델을 세울 수 없습니다(출력 창 참고 — 뼈대에 붙인 모델인지)")
		baker = null
		return
	await get_tree().process_frame
	ob = DROutfitBaker.new()
	ob.baker = baker
	if not ob.setup(_sets_edit.text.strip_edges()):
		_fail("sets.json 에서 세트를 읽지 못했습니다: %s" % _sets_edit.text)
		return
	if _id_edit.text.strip_edges() == "":
		_id_edit.text = mpath.get_file().get_basename().to_lower()
	# 슬롯: 구운 복장을 연 경우 그때 것, 아니면 창의 칸
	_filling = true
	for pn in _slot_opts.keys():
		var want: String = SLOT_KEYS[(_slot_opts[pn] as OptionButton).selected]
		if not _restore_slots.is_empty():
			want = String(_restore_slots.get(pn, ""))
		(_slot_opts[pn] as OptionButton).select(SLOT_KEYS.find(want))
		ob.slots[pn] = want
	_filling = false
	_restore_slots = {}
	_ov = baker.part_overrides
	_build_paint_mesh()
	_fill_view_sets()
	_loaded = true
	await _build_soldier()
	_load_status.text = "세트 %d개 · 옷 모델 정점 %d · 칠한 자리 %d곳" % [ob.sets.size(), _pm_pos.size(), _ov.size()]
	if ob.warnings.size() > 0:
		_load_status.text += "\n⚠ " + "\n⚠ ".join(ob.warnings)
	if baker.extra_anim_warnings.size() > 0:
		_load_status.text += "\n(추가 동작 경고 %d건 — 출력 창)" % baker.extra_anim_warnings.size()
	_update_paint_status()
	_busy = false
	_bake_btn.disabled = false
	_pv_dirty = true
	_pv_timer = 0.0


func _fill_view_sets() -> void:
	_filling = true
	_view_set.clear()
	for s in ob.sets:
		_view_set.add_item(String((s as Dictionary)["name"]))
	_filling = false


func _set_index(set_name: String) -> int:
	for i in ob.sets.size():
		if String((ob.sets[i] as Dictionary)["name"]) == set_name:
			return i
	return -1


# ---------------------------------------------------------------- 2D 미리보기

func _build_soldier() -> void:
	if is_instance_valid(_soldier):
		_soldier.queue_free()
	_soldier = DRPuppetSet.new()
	_soldier.name = "PreviewSoldier"
	_soldier.run_in_editor = true
	_soldier.force_loop = true
	_soldier.sets_json = ob.sets_json
	_soldier.position = Vector2(_vp2.size.x * 0.5, _vp2.size.y * 0.9)
	_soldier.scale = Vector2(_pv_zoom.value, _pv_zoom.value)
	_soldier.speed_scale = 1.0 if _pv_play.button_pressed else 0.0
	_vp2.add_child(_soldier)
	await get_tree().process_frame
	# 세트 캔버스가 크면(384px 등) 처음 한 번 칸에 맞춘다
	if ob.sets.size() > 0:
		var vs: Array = ((ob.sets[0] as Dictionary)["rig"] as Dictionary).get("view", {}).get("size", [192, 192])
		var fit := clampf(float(_vp2.size.y) * 0.92 / float(vs[1]), 0.3, 3.0)
		_pv_zoom.value = fit
	_filling = true
	_pv_anim.clear()
	for an in _soldier.get_animations():
		_pv_anim.add_item(String(an))
	_filling = false


func _on_view_set_changed() -> void:
	if not _loaded or _filling or _soldier == null:
		return
	var i := _view_set.selected
	if i < 0 or i >= ob.sets.size():
		return
	var sname := String((ob.sets[i] as Dictionary)["name"])
	for e in _soldier._entries:
		if String((e as Dictionary)["name"]) == sname:
			var first: PackedStringArray = (e as Dictionary)["anims"]
			if first.size() > 0:
				_soldier.play(first[0])
				_filling = true
				for k in _pv_anim.item_count:
					if _pv_anim.get_item_text(k) == String(first[0]):
						_pv_anim.select(k)
				_filling = false
			break


func _on_anim_selected(i: int) -> void:
	if _filling or _soldier == null or i < 0:
		return
	_soldier.play(_pv_anim.get_item_text(i))
	var si := _set_index(String(_soldier.current_set()))
	if si >= 0 and si != _view_set.selected:
		_filling = true
		_view_set.select(si)
		_filling = false


## 지금 칠하기 · 슬롯으로 모든 세트를 임시로 굽고 입힌다
func _refresh_preview() -> void:
	if not _loaded or ob == null:
		return
	_busy = true
	_status.text = "2D 미리보기 굽는 중…"
	ob.warnings = PackedStringArray()
	_baked = await ob.bake_all()
	_outfit = ob.to_outfit(_baked, _id_edit.text.strip_edges())
	_apply_wear()
	_busy = false
	var n := 0
	for k in _baked.keys():
		n += (_baked[k] as Dictionary).size()
	_status.text = "준비됨 — 세트 %d개 · 파트 그림 %d장. 칠하거나 슬롯을 바꾸면 다시 굽는다. 다 됐으면 `복장 굽기`." % [_baked.size(), n]
	if ob.warnings.size() > 0:
		_status.text += "\n⚠ " + "\n⚠ ".join(ob.warnings)


## 미리보기 슬롯 체크대로 입힌다
func _apply_wear() -> void:
	if not is_instance_valid(_soldier) or _outfit == null:
		return
	var only: Array = []
	for k in _wear_cb.keys():
		if (_wear_cb[k] as CheckBox).button_pressed:
			only += _outfit.slot_parts(String(k))
	_soldier.take_off()
	if only.size() > 0:
		_soldier.wear(_outfit, only)


func _on_slot_changed(part: String, i: int) -> void:
	if _filling or ob == null:
		return
	ob.slots[part] = SLOT_KEYS[i]
	_pv_dirty = true
	_pv_timer = PV_DEBOUNCE


# ---------------------------------------------------------------- 3D 부위 칠하기

## 옷 모델 원본 메시(바인드 자세)를 부위 색 표시용으로 복사하고, 고르기용 삼각형을 준비한다
func _build_paint_mesh() -> void:
	_pm_pos = PackedVector3Array()
	_pm_nrm = PackedVector3Array()
	_pm_auto = PackedStringArray()
	_pm_surf = []
	_tri_a = PackedVector3Array()
	_tri_e1 = PackedVector3Array()
	_tri_e2 = PackedVector3Array()
	var mi := baker.source_mesh_instance
	var src := mi.mesh as ArrayMesh
	if src == null:
		return
	var binds := DRMeshSplitter._bind_map(mi, baker.skeleton)
	var tex: Texture2D = null
	for si in src.get_surface_count():
		if src.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var vcount := verts.size()
		var bpv := int(bones.size() / float(maxi(vcount, 1)))
		var start := _pm_pos.size()
		for v in vcount:
			var best_w := -1.0
			var best_b := -1
			for k in bpv:
				var w := weights[v * bpv + k]
				if w > best_w:
					best_w = w
					best_b = bones[v * bpv + k]
			var skel_b := binds[best_b] if best_b >= 0 and best_b < binds.size() else -1
			_pm_auto.append(String(baker.split.bone_part.get(skel_b, "")))
			_pm_pos.append(verts[v])
			_pm_nrm.append(nrm[v] if nrm.size() == vcount else Vector3.UP)
		for t in int(idx.size() / 3):
			var a := verts[idx[t * 3]]
			_tri_a.append(a)
			_tri_e1.append(verts[idx[t * 3 + 1]] - a)
			_tri_e2.append(verts[idx[t * 3 + 2]] - a)
		var mat := mi.get_active_material(si)
		if tex == null and mat is BaseMaterial3D:
			tex = (mat as BaseMaterial3D).albedo_texture
		_pm_surf.append({"arrays": arrays, "start": start, "count": vcount})
	_mat_tex.albedo_texture = tex
	_mat_mix.albedo_texture = tex
	_recolor()
	_apply_view_mode()
	_cam_yaw = 0.0
	_cam_pitch = 0.0
	_frame_cam()
	_update_brush()


## 모델 전체(T-포즈 팔 끝까지)가 칸에 들어오게 — 칸의 가로세로 비율까지 따진다(F 키)
func _frame_cam() -> void:
	var m := _pm_mesh if _pm_mesh != null else null
	if m == null:
		return
	var aabb := m.get_aabb()
	_cam_target = aabb.get_center()
	var half := tan(deg_to_rad(_cam3.fov * 0.5))
	var aspect := float(_vp3.size.x) / float(maxi(_vp3.size.y, 1))
	var need_h := aabb.size.y / (2.0 * half)
	var need_w := maxf(aabb.size.x, aabb.size.z) / (2.0 * half * maxf(aspect, 0.1))
	_cam_dist = maxf(need_h, need_w) * 1.12 + aabb.size.z * 0.5
	_update_cam()


func _part_color(part: String) -> Color:
	return PART_COLORS.get(part, Color(0.35, 0.35, 0.35))


## 부위 색 다시 칠하기(칠한 정점은 조금 밝게)
func _recolor() -> void:
	if _pm_surf.is_empty():
		return
	var m := ArrayMesh.new()
	for s in _pm_surf:
		var sd: Dictionary = s
		var src: Array = sd["arrays"]
		var start: int = sd["start"]
		var count: int = sd["count"]
		var cols := PackedColorArray()
		cols.resize(count)
		for v in count:
			var p := _pm_pos[start + v]
			var painted := _ov.part_at(p) if _ov != null else ""
			var part := painted if painted != "" else _pm_auto[start + v]
			var c := _part_color(part)
			cols[v] = c.lerp(Color.WHITE, 0.3) if painted != "" else c
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = src[Mesh.ARRAY_VERTEX]
		arr[Mesh.ARRAY_NORMAL] = src[Mesh.ARRAY_NORMAL]
		arr[Mesh.ARRAY_TEX_UV] = src[Mesh.ARRAY_TEX_UV]
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = src[Mesh.ARRAY_INDEX]
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_pm_mesh = m
	_pm_mi.mesh = m
	_apply_view_mode()


func _apply_view_mode() -> void:
	if _pm_mi == null:
		return
	match _view_mode.selected:
		1:
			_pm_mi.material_override = _mat_tex
		2:
			_pm_mi.material_override = _mat_mix
		_:
			_pm_mi.material_override = _mat_part


func _update_cam() -> void:
	if _cam3 == null:
		return
	var b := Basis.from_euler(Vector3(-_cam_pitch, _cam_yaw, 0.0))
	_cam3.position = _cam_target + b * Vector3(0, 0, _cam_dist)
	_cam3.look_at(_cam_target, Vector3.UP)
	_cam3.near = 0.01
	_cam3.far = _cam_dist * 10.0


func _update_brush() -> void:
	if _brush_mi == null:
		return
	var r := _brush_spin.value * 0.01
	_brush_mi.scale = Vector3(r, r, r)


## TextureRect 좌표 → 뷰포트 좌표(가운데 맞춤 · 비율 유지)
func _to_vp(rect: TextureRect, vp: SubViewport, p: Vector2) -> Vector2:
	var rs := rect.size
	var vs := Vector2(vp.size)
	if vs.x <= 0.0 or vs.y <= 0.0:
		return p
	var s := minf(rs.x / vs.x, rs.y / vs.y)
	var off := (rs - vs * s) * 0.5
	return (p - off) / s


## 화면 점 → 모델 표면의 점(광선과 가장 가까운 삼각형). 못 맞히면 {hit: false}
func pick(vp_pos: Vector2) -> Dictionary:
	if _tri_a.is_empty():
		return {"hit": false}
	var o := _cam3.project_ray_origin(vp_pos)
	var d := _cam3.project_ray_normal(vp_pos)
	var best := INF
	for t in _tri_a.size():
		var e1 := _tri_e1[t]
		var e2 := _tri_e2[t]
		var pv := d.cross(e2)
		var det := e1.dot(pv)
		if absf(det) < 1e-12:
			continue
		var inv := 1.0 / det
		var tv := o - _tri_a[t]
		var u := tv.dot(pv) * inv
		if u < 0.0 or u > 1.0:
			continue
		var qv := tv.cross(e1)
		var w := d.dot(qv) * inv
		if w < 0.0 or u + w > 1.0:
			continue
		var dist := e2.dot(qv) * inv
		if dist > 1e-5 and dist < best:
			best = dist
	if best == INF:
		return {"hit": false}
	return {"hit": true, "pos": o + d * best}


## 붓질 한 번: 붓 범위 안의 정점을 part 로(part = "" 이면 지움). 바뀐 정점 수
func paint_at(hit: Vector3, part: String, radius: float = -1.0) -> int:
	if _ov == null:
		return 0
	var r := radius if radius > 0.0 else _brush_spin.value * 0.01
	var r2 := r * r
	var view_dir := (_cam3.global_position - hit).normalized()
	var changed := 0
	var done := {}
	for i in _pm_pos.size():
		var p := _pm_pos[i]
		if p.distance_squared_to(hit) > r2:
			continue
		if _front_only.button_pressed and _pm_nrm[i].dot(view_dir) < 0.0:
			continue
		var k := DRPartOverrides.key_of(p)
		if done.has(k):
			continue
		done[k] = true
		var prev := String(_ov.map.get(k, ""))
		if prev == part:
			continue
		if not _stroke.has(k):
			_stroke[k] = prev
		if part == "":
			_ov.map.erase(k)
		else:
			_ov.map[k] = part
		changed += 1
	if changed > 0:
		_recolor()
		_update_paint_status()
	return changed


## 붓질이 끝나면 저장하고, 잠시 뒤 다시 잘라 미리보기를 다시 굽는다
func end_stroke() -> void:
	_painting = false
	if _stroke.is_empty():
		return
	_undo.append(_stroke)
	_stroke = {}
	_after_paint_change()


func _after_paint_change() -> void:
	if _ov != null:
		_ov.save()
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().update_file(DRPartOverrides.path_for(_scene_path))
	_resplit_dirty = true
	_resplit_timer = PV_DEBOUNCE
	_update_paint_status()


func _on_undo() -> void:
	if _undo.is_empty() or _ov == null:
		return
	var last: Dictionary = _undo.pop_back()
	for k in last.keys():
		var prev := String(last[k])
		if prev == "":
			_ov.map.erase(k)
		else:
			_ov.map[k] = prev
	_recolor()
	_after_paint_change()


func _on_clear_paint() -> void:
	if _ov == null or _ov.is_empty():
		return
	var snap := {}
	for k in _ov.map.keys():
		snap[k] = String(_ov.map[k])
	_undo.append(snap)
	_ov.map.clear()
	_recolor()
	_after_paint_change()


func _update_paint_status() -> void:
	if _paint_status == null:
		return
	if _ov == null:
		_paint_status.text = ""
		return
	_paint_status.text = "칠한 자리 %d곳 · 되돌리기 %d번 가능 · 저장: %s" % [_ov.size(), _undo.size(), DRPartOverrides.path_for(_scene_path)]
	_undo_btn.disabled = _undo.is_empty()


func _on_pv3_input(ev: InputEvent) -> void:
	if not _loaded:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		_pv3.grab_focus()
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_painting = true
				_stroke = {}
				_paint_from_screen(mb.position)
			else:
				end_stroke()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = "orbit" if mb.pressed else ""
			_drag_from = mb.position
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = "pan" if mb.pressed else ""
			_drag_from = mb.position
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(_cam_dist * 0.88, 0.05)
			_update_cam()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(_cam_dist / 0.88, 50.0)
			_update_cam()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if _drag == "orbit":
			var dd := mm.position - _drag_from
			_drag_from = mm.position
			_cam_yaw -= dd.x * 0.01
			_cam_pitch = clampf(_cam_pitch + dd.y * 0.01, -1.45, 1.45)
			_update_cam()
		elif _drag == "pan":
			var dd2 := mm.position - _drag_from
			_drag_from = mm.position
			var k := _cam_dist * 0.0015
			_cam_target += (-_cam3.global_transform.basis.x * dd2.x + _cam3.global_transform.basis.y * dd2.y) * k
			_update_cam()
		elif _painting:
			if mm.position.distance_to(_last_pick_px) >= 3.0:
				_paint_from_screen(mm.position)
		elif mm.position.distance_to(_last_pick_px) >= 6.0:
			_hover(mm.position)
	elif ev is InputEventKey and (ev as InputEventKey).pressed:
		var ke := ev as InputEventKey
		if ke.keycode == KEY_F:
			_frame_cam()
		elif ke.keycode == KEY_Z and ke.ctrl_pressed:
			_on_undo()


func _paint_from_screen(p: Vector2) -> void:
	_last_pick_px = p
	var h := pick(_to_vp(_pv3, _vp3, p))
	_brush_hit = bool(h.get("hit", false))
	_brush_mi.visible = _brush_hit
	if _brush_hit:
		_brush_pos = h["pos"]
		_brush_mi.position = _brush_pos
		paint_at(_brush_pos, _paint_part)


func _hover(p: Vector2) -> void:
	_last_pick_px = p
	var h := pick(_to_vp(_pv3, _vp3, p))
	_brush_hit = bool(h.get("hit", false))
	_brush_mi.visible = _brush_hit
	if _brush_hit:
		_brush_mi.position = h["pos"]


# ---------------------------------------------------------------- 뼈대에 붙이기(Blender)

func _on_bind() -> void:
	if _bind_thread != null and _bind_thread.is_started():
		return
	var raw := _raw_edit.text.strip_edges()
	if raw == "" or not FileAccess.file_exists(raw if raw.is_absolute_path() and not raw.begins_with("res://") else ProjectSettings.globalize_path(raw)):
		_bind_status.text = "⚠ AI 원본 파일이 없습니다: %s" % raw
		return
	var id := _id_edit.text.strip_edges()
	if id == "":
		_bind_status.text = "⚠ 1번의 복장 이름을 먼저 적어 주세요(결과 폴더 이름)"
		return
	var blender := _blender_edit.text.strip_edges()
	if not FileAccess.file_exists(blender):
		_bind_status.text = "⚠ Blender 를 찾을 수 없습니다: %s" % blender
		return
	var out_res := "res://source3d/characters/%s/%s.glb" % [id, id]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_res.get_base_dir()))
	var args := PackedStringArray(["-b", "--factory-startup", "-P", ProjectSettings.globalize_path(BIND_SCRIPT), "--",
		"--base", ProjectSettings.globalize_path(_wbase_edit.text.strip_edges()),
		"--src", ProjectSettings.globalize_path(raw),
		"--out", ProjectSettings.globalize_path(out_res),
		"--smooth", str(int(_smooth_spin.value)),
		"--hand_fit", "1" if _hand_cb.button_pressed else "0",
		"--thumb_fit", "1" if _thumb_cb.button_pressed else "0",
		"--part_fix", "1" if _partfix_cb.button_pressed else "0"])
	_bind_btn.disabled = true
	_bind_status.text = "붙이는 중… (Blender, 수십 초)"
	_bind_thread = Thread.new()
	_bind_thread.start(_bind_worker.bind(blender, args, out_res))


func _bind_worker(exe: String, args: PackedStringArray, out_res: String) -> void:
	var out: Array = []
	var code := OS.execute(exe, args, out, true)
	call_deferred("_on_bind_done", code, "\n".join(PackedStringArray(out)), out_res)


func _on_bind_done(code: int, log_text: String, out_res: String) -> void:
	if _bind_thread != null:
		_bind_thread.wait_to_finish()
		_bind_thread = null
	_bind_btn.disabled = false
	var line := ""
	for l in log_text.split("\n"):
		if l.begins_with("BIND_RESULT "):
			line = l.substr(12)
	var v: Variant = JSON.parse_string(line) if line != "" else null
	if not (v is Dictionary) or not bool((v as Dictionary).get("ok", false)):
		var tail := log_text.substr(maxi(0, log_text.length() - 600))
		_bind_status.text = "⚠ 붙이기 실패(코드 %d)\n%s" % [code, tail]
		return
	var r: Dictionary = v
	_bind_status.text = "붙임 → %s\n방향 %s° · 키 배율 %.3f · 웨이트 없는 정점 %d · 엄지 %s · 관절 경계 %s" % [out_res, str(r.get("turned_deg", 0)),
		float(r.get("scale", 1.0)), int(r.get("unweighted_vertices", 0)), str(r.get("thumb_fit_deg", {})), str(r.get("part_fix", {}))]
	_model_edit.text = out_res
	if Engine.is_editor_hint():
		var fs := EditorInterface.get_resource_filesystem()
		fs.scan()
		while fs.is_scanning():
			await get_tree().process_frame
		if ResourceLoader.exists(out_res):
			fs.reimport_files(PackedStringArray([out_res]))
			while fs.is_scanning():
				await get_tree().process_frame
		await get_tree().process_frame
	_on_load()


# ---------------------------------------------------------------- 굽기 · 매 프레임

func _process(delta: float) -> void:
	if not visible or not _loaded:
		return
	if _resplit_dirty and not _busy and not _painting:
		_resplit_timer -= delta
		if _resplit_timer <= 0.0:
			_resplit_dirty = false
			baker.resplit(_ov)
			_pv_dirty = true
			_pv_timer = 0.0
	if _pv_dirty and not _busy and not _painting:
		_pv_timer -= delta
		if _pv_timer <= 0.0:
			_pv_dirty = false
			_refresh_preview()


func _on_bake() -> void:
	if not _loaded or _busy:
		return
	var id := _id_edit.text.strip_edges()
	if id == "":
		_status.text = "⚠ 복장 이름을 적어 주세요"
		return
	if _resplit_dirty:
		_resplit_dirty = false
		baker.resplit(_ov)
	_busy = true
	_bake_btn.disabled = true
	var cb := func(i, n, nm):
		_progress.max_value = n
		_progress.value = i + 1
		_status.text = "굽는 중 %d/%d — %s" % [i + 1, n, nm]
	ob.progress.connect(cb)
	var res: Dictionary = await ob.run(_out_edit.text.strip_edges(), id, _scene_path)
	ob.progress.disconnect(cb)
	_busy = false
	_bake_btn.disabled = false
	_progress.value = 0
	if bool(res.get("ok", false)):
		_status.text = "완료 — 세트 %d개 → %s\n게임: soldier.wear(DROutfit.load_json(\"%s\")) · 시험장 F6 의 O(상의) · P(하의)" % [(res["sets"] as Array).size(), String(res["json"]).get_base_dir(), String(res["json"])]
		var ws: PackedStringArray = res.get("warnings", PackedStringArray())
		if ws.size() > 0:
			_status.text += "\n⚠ " + "\n⚠ ".join(ws)
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().scan()
	else:
		_status.text = "⚠ 굽기 실패: %s" % String(res.get("error", "?"))
