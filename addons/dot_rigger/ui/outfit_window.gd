@tool
extends DRPage
class_name DROutfitWindow

## Dot Rigger — 복장 굽기 페이지(옷만 갈아입히기, Dot Rigger 창의 ③ 탭).  프로젝트 > 도구 > Dot Rigger.
## (이름은 창 시절 그대로 DROutfitWindow. 창 안에서는 프리셋 · 세트 목록을 위의 `공통 설정` 줄에서 받는다)
##
## 왼쪽: 1 기본 몸 프리셋 · sets.json · 옷 모델 → 불러오기(창이 지난 값을 기억하고 열 때 자동으로 불러온다)
##       2 옷 모델 새로 만들기 — AI 원본(Tripo 등)을 기본 뼈대에 붙인다(Blender 를 대신 돌림)
##       3 부위 칠하기 — 칠할 대상(옷 모델 / 기본 몸) · 도구(붓 / 직선 나누기) · 부위
##       4 슬롯 — 파트마다 상의 · 하의 · 안 씀(옷은 상의 · 하의 두 가지)
##       바닥: 굽기 → 기본 몸을 칠했으면 기본 몸 세트에 먼저 넣고, 복장을 <출력 폴더>/<복장 이름>/outfit.json 으로
## 오른쪽: 2D 미리보기 — 기본 몸 퍼펫에 지금 상태(기본 몸 칠한 것 포함)로 임시로 구운 옷을 입혀 재생
##         3D 부위 칠하기 — 면마다 실제로 잘리는 부위 색. 붓 · 직선으로 고친다
##
## 옷은 3D 메시를 떼는 게 아니다: 옷 입은 모델을 기본 몸 세트와 같은 카메라 · 같은 자세로 부위별 2D 그림으로 굽고,
## 퍼펫의 그 부위 그림만 바꿔 끼운다. 부위 경계는 정점마다 웨이트가 가장 센 뼈로 정해지고, 칠하기로 바꾼다.

const MODEL_FILTER := "*.glb, *.gltf, *.tscn, *.scn ; 뼈대에 붙인 옷 모델"
const RAW_FILTER := "*.glb, *.gltf ; AI 원본(Tripo 등)"
const PRESET_FILTER := "*.tres ; 기본 몸 프리셋"
const SETS_FILTER := "*.json ; 세트 목록(sets.json)"
const OUTFIT_FILTER := "*.json ; 구운 복장(outfit.json)"
const BLENDER_DEFAULT := "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
const BLENDER_SETTING := "dot_rigger/blender_path"
const META_SECTION := "dot_rigger_outfit"
const BIND_SCRIPT := "res://pipeline/blender/bind_to_skeleton.py"
## 웨이트 원본 몸 기본 = 사람 몸(10-15 사용자: "UAL 마네킹은 레거시, 복장 창 웨이트 원본 몸도 사람 몸"). 사람 몸이면 붙이기가 그 뼈대
## (팔꿈치 · 손목 · 비틀림 뼈)를 그대로 써서 옷 관절이 맨몸과 같아진다(bind_to_skeleton.py skeleton_from_base).
const WEIGHT_BASE_DEFAULT := "res://source3d/characters/human_base/human_base.glb"
## 예전 기본값 — 기억해 둔 값이 이것이면 새 기본값으로 바꿔 읽는다
const WEIGHT_BASE_LEGACY := "res://source3d/UAL1_humanoid.glb"
const PV_DEBOUNCE := 0.5
const SLOT_KEYS := ["top", "bottom", ""]
const ERASE := ""                  # 칠할 부위 "" = 지우개(웨이트대로)
const CUTS_KEY := "__cuts__"        # 되돌리기 기록에서 "자르기 목록 전체(바뀌기 전)"
const PART_COLORS := {
	"Hips": Color(0.86, 0.74, 0.2), "Torso": Color(0.92, 0.33, 0.28), "Head": Color(0.98, 0.84, 0.66),
	"L_UpperArm": Color(0.25, 0.55, 0.98), "L_Forearm": Color(0.2, 0.82, 0.86), "L_Hand": Color(0.65, 0.92, 1.0),
	"R_UpperArm": Color(0.58, 0.32, 0.92), "R_Forearm": Color(0.86, 0.38, 0.9), "R_Hand": Color(0.97, 0.72, 0.97),
	"L_Thigh": Color(0.24, 0.72, 0.32), "L_Calf": Color(0.55, 0.86, 0.28), "L_Foot": Color(0.78, 0.96, 0.55),
	"R_Thigh": Color(0.96, 0.52, 0.16), "R_Calf": Color(0.98, 0.7, 0.34), "R_Foot": Color(1.0, 0.86, 0.56),
}


## 칠할 대상 하나(옷 모델 · 기본 몸) — 모델 · 칠하기 · 표시 · 되돌리기를 따로 갖는다
class PaintTarget:
	extends RefCounted
	var kind := ""                     # "outfit" · "base"
	var baker: DRBaker
	var ob: DROutfitBaker
	var scene_path := ""
	var ov: DRPartOverrides
	var pos := PackedVector3Array()    # 정점(바인드 = T-포즈, 서피스 이어 붙임)
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var auto := PackedStringArray()    # 웨이트대로의 파트
	var keys: Array = []               # 정점 → DRPartOverrides 키
	var tri := PackedInt32Array()      # 삼각형 → 정점 번호 3개
	var tri_a := PackedVector3Array()  # 고르기(광선)용
	var tri_e1 := PackedVector3Array()
	var tri_e2 := PackedVector3Array()
	var tex: Texture2D
	var undo: Array = []
	var resplit_dirty := false

	## 정점마다 지금 부위(칠한 것 우선)
	func part_of(i: int) -> String:
		var p := String(ov.map.get(keys[i], "")) if ov != null else ""
		if p == "":
			p = auto[i]
		if ov != null and not ov.cuts.is_empty():
			p = ov.cut_part(pos[i], p)
		return p

	func painted(i: int) -> bool:
		return ov != null and ov.map.has(keys[i])


## 2D 화면 위에 그리는 직선(직선 나누기 도구)
class LineOverlay:
	extends Control
	var a := Vector2.ZERO
	var b := Vector2.ZERO
	var on := false
	var rect := false

	func _draw() -> void:
		if not on:
			return
		if rect:
			var r := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())
			draw_rect(r, Color(1.0, 0.85, 0.2, 0.12), true)
			draw_rect(r, Color(1.0, 0.85, 0.2), false, 2.0)
			return
		draw_line(a, b, Color(1.0, 0.85, 0.2), 2.0, true)
		draw_circle(a, 4.0, Color(1.0, 0.85, 0.2))
		draw_circle(b, 4.0, Color(1.0, 0.85, 0.2))


const PV_BG_DEFAULT := Color(0.36, 0.42, 0.36)   # 2D 미리보기 기본 배경
var _pv_bg2: ColorRect                          # 2D 미리보기 배경(공통 설정 줄의 "미리보기 배경")
var baker: DRBaker                      # 옷 모델
var ob: DROutfitBaker
var _scene_path := ""
var _loaded := false
var _busy := false
var _filling := false
var _pv_dirty := false
var _pv_timer := 0.0
var _outfit: DROutfit                   # 미리보기용 복장(메모리)
var _baked: Dictionary = {}
var _restore_slots: Dictionary = {}
var _auto_loaded := false

var _t_outfit: PaintTarget
var _t_base: PaintTarget
var _target: PaintTarget                # 지금 칠하는 대상
var _base_outfit: DROutfit              # 기본 몸을 칠한 뒤 다시 자른 그림(미리보기) — 세트에 넣으면 null
var _base_baked: Dictionary = {}
var _base_dirty := false                # 기본 몸 칠한 것이 아직 세트에 안 들어감
var _base_pv_dirty := false

var _tool := "line"                     # line(직선 자르기) · rect(사각형) · brush(붓)
var _paint_part := "Torso"
var _painting := false
var _stroke: Dictionary = {}            # 이번 붓질: 대상(PaintTarget) -> {바뀐 키: 바뀌기 전 파트("" = 웨이트대로)}
var _undo: Array = []                   # 끝난 붓질 · 선들(_stroke 와 같은 모양) — 되돌리기
var _target_kind := "both"              # 칠할 대상 단추: both · outfit · base
var _paint_both := false                # 옷 모델에 칠하는 것을 기본 몸에도 같이
var _last_pick_px := Vector2(-999, -999)
var _line_on := false

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
var _tgt_btns: Dictionary = {}          # "outfit" · "base" -> Button
var _tool_btns: Dictionary = {}         # "brush" · "line" -> Button
var _part_btns: Dictionary = {}         # 파트(지우개 "") -> Button
var _brush_spin: SpinBox
var _front_only: CheckBox
var _undo_btn: Button
var _clear_btn: Button
var _paint_status: Label
# 3 관절 경계
var _joint_opt: OptionButton
var _joint_on: CheckBox
var _joint_off: HSlider
var _joint_tilt: HSlider
var _joints: Dictionary = {}            # 자식 부위 -> {key, from, to, label, c, d, h}
var _joint_sel := ""
var _joint_active := false              # 슬라이더를 움직이는 중(아직 되돌리기 · 저장 전)
var _joint_snap: Dictionary = {}        # 대상 -> 움직이기 전 자르기 목록
var _joint_idle := 0.0
var _joint_mi: MeshInstance3D
var _disp_dirty := false
# 5 슬롯
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
var _line_ov: LineOverlay
var _hud3: Label
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
	page_title = "복장 굽기 (옷 갈아입히기)"
	_build_ui()
	visibility_changed.connect(_on_shown)


func _ready() -> void:
	_restore_fields()
	_on_shown.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_teardown()
		if _bind_thread != null and _bind_thread.is_started():
			_bind_thread.wait_to_finish()


## 창이 처음 뜨면 지난 값으로 바로 불러온다(불러오기 버튼을 또 누르지 않게)
func _on_shown() -> void:
	if not is_visible_in_tree() or _loaded or _busy:
		return
	if _ctx_stale:
		_ctx_stale = false
	elif _auto_loaded:
		return
	_auto_loaded = true
	var m := _model_edit.text.strip_edges()
	if m != "" and ResourceLoader.exists(m) and _preset_edit.text.strip_edges() != "":
		_on_load.call_deferred()


# ---------------------------------------------------------------- 공통 설정 · 지난 값 기억

## 창의 공통 설정(프리셋 · 세트 목록)을 받는다. 이미 불러온 상태에서 바뀌면(세트를 다시 구웠을 때 포함) 이 탭이 보일 때 다시 불러온다.
## 칠한 것은 파일(<모델>.parts.json)에, 슬롯은 칸에 남아 있어 다시 불러와도 그대로다.
var _ctx_stale := false

func set_preview_bg(c: Color) -> void:
	if _pv_bg2 != null:
		_pv_bg2.color = c if c.a > 0.0 else PV_BG_DEFAULT


func apply_context(ctx: Dictionary, changed: PackedStringArray) -> void:
	if hosted:
		_preset_edit.get_parent().visible = false
		_sets_edit.get_parent().visible = false
	var dirty := changed.has("rebaked")
	var p := String(ctx.get("preset", ""))
	if p != "" and p != _preset_edit.text:
		_preset_edit.text = p
		dirty = true
	var s := String(ctx.get("sets", ""))
	if s != "" and s != _sets_edit.text:
		_sets_edit.text = s
		dirty = true
	if dirty and _loaded:
		_ctx_stale = true
	elif dirty and not _loaded and is_visible_in_tree():
		_auto_loaded = false
		_on_shown.call_deferred()



func _restore_fields() -> void:
	if not Engine.is_editor_hint():
		return
	var es := EditorInterface.get_editor_settings()
	for pair in [["preset", _preset_edit], ["sets", _sets_edit], ["model", _model_edit], ["id", _id_edit], ["out", _out_edit],
			["raw", _raw_edit], ["wbase", _wbase_edit]]:
		# 기본값을 꼭 준다 — null 을 주면 값이 없을 때 에디터가 오류를 낸다(10-06: ③ 탭을 열 때 빨간 오류 7줄)
		var v := String(es.get_project_metadata(META_SECTION, String(pair[0]), ""))
		if String(pair[0]) == "wbase" and v == WEIGHT_BASE_LEGACY:
			v = WEIGHT_BASE_DEFAULT                     # 예전 기본값(UAL 마네킹) 그대로였으면 사람 몸으로
		if v != "":
			(pair[1] as LineEdit).text = v


func _remember_fields() -> void:
	if not Engine.is_editor_hint():
		return
	var es := EditorInterface.get_editor_settings()
	for pair in [["preset", _preset_edit], ["sets", _sets_edit], ["model", _model_edit], ["id", _id_edit], ["out", _out_edit],
			["raw", _raw_edit], ["wbase", _wbase_edit]]:
		es.set_project_metadata(META_SECTION, String(pair[0]), (pair[1] as LineEdit).text)


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
	_build_section_joints(col)
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


## 한 줄짜리 토글 단추 묶음(하나만 눌림)
func _toggle_row(parent: Control, label: String, items: Array, on_pick: Callable) -> Dictionary:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	var group := ButtonGroup.new()
	var out := {}
	for it in items:
		var b := Button.new()
		b.text = String(it[1])
		b.toggle_mode = true
		b.button_group = group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tip(b, String(it[2]))
		var key: String = it[0]
		b.pressed.connect(func(): on_pick.call(key))
		row.add_child(b)
		out[key] = b
	parent.add_child(row)
	return out


func _build_section_source(col: Control) -> void:
	var s := _section(col, "1. 기본 몸 · 세트 · 옷 모델")
	_hint(s, "기본 몸(민소매)으로 구운 세트에 옷을 입힌다. 옷 모델 = 같은 뼈대에 붙인 옷 입은 사람(.glb). 한 번 불러오면 다음에 창을 열 때 자동으로 불러온다.")
	_preset_edit = _path_row(s, "기본 몸 프리셋", "메인 창에서 기본 몸 세트를 구울 때 쓴 프리셋(.tres) — 기본 몸 모델 · 도트화 값 · 추가 동작 폴더를 여기서 읽는다.", _on_browse_preset)
	_preset_edit.text = _default_preset()
	_sets_edit = _path_row(s, "세트 목록", "기본 몸으로 구운 sets.json. 세트마다 같은 카메라 · 같은 레스트 자세로 옷이 구워진다.", _on_browse_sets)
	_sets_edit.text = "res://puppet/sets.json"
	_model_edit = _path_row(s, "옷 모델", "기본 몸과 같은 뼈대에 붙인 옷 입은 모델(.glb). 기본 몸 자체를 칠하려면 여기 말고 3번의 [기본 몸] 단추.", _on_browse_model)
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
	_hint(s, "Tripo 등으로 뽑은 옷 입은 사람(.glb, 통짜)을 기본 뼈대에 붙인다 — 방향 · 키 · 웨이트 · 손가락/엄지 · 관절 경계. Blender 를 뒤에서 돌리며 수십 초 걸린다. 결과 res://source3d/characters/<복장 이름>/<복장 이름>.glb 가 1번 옷 모델로 들어가 바로 불러온다.")
	_raw_edit = _path_row(s, "AI 원본", "AI 가 뽑은 .glb — 보통 pipeline/comfy/ 아래(이 폴더는 Godot 가 무시하므로 디스크 경로로 고른다).", _on_browse_raw)
	_wbase_edit = _path_row(s, "웨이트 원본 몸", "웨이트(어느 살이 어느 뼈를 따라가나)와 뼈대를 가져올 몸 — 기본은 사람 몸(human_base). 옷 관절이 맨몸과 같아진다.", _on_browse_wbase)
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
	_partfix_cb = _check(s, "관절 경계 정리", true, "어깨 · 팔꿈치 · 고관절 · 무릎에 평면을 세워 조각 경계를 관절에 맞춘다. 더 고칠 곳은 3번 칠하기로.")
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


func _build_section_joints(col: Control) -> void:
	var s := _section(col, "3. 부위 경계 (관절)")
	_hint(s, "옷과 몸이 이어지는 자리(목 · 손목 …)의 경계를 곧게 정한다. 관절을 고르고 [곧게]를 켠 뒤 위치 · 기울기를 끌면 3D 의 노란 판이 경계, 2D 가 바로 바뀐다. 그 관절의 두 부위만 자르고(다른 부위는 안 건드림) 옷 모델 · 기본 몸에 똑같이 들어간다 — 기본 몸에 정한 경계는 다른 옷을 불러와도 그대로 따라간다.")
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "관절"
	l.custom_minimum_size = Vector2(70, 0)
	row.add_child(l)
	_joint_opt = OptionButton.new()
	_joint_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_joint_opt.item_selected.connect(func(_i): _on_joint_selected())
	row.add_child(_joint_opt)
	_joint_on = CheckBox.new()
	_joint_on.text = "곧게"
	_tip(_joint_on, "이 관절의 경계를 곧은 평면으로 자른다(끄면 뼈 웨이트대로 — 들쭉날쭉)")
	_joint_on.toggled.connect(func(_v): _on_joint_edit(true))
	row.add_child(_joint_on)
	s.add_child(row)
	_joint_off = _joint_slider(s, "위치", -12.0, 12.0, 0.5, "cm", "관절에서 뼈 방향으로 경계를 옮긴다(+ = 자식 쪽: 목이면 위, 손목이면 손 쪽)")
	_joint_tilt = _joint_slider(s, "기울기", -60.0, 60.0, 1.0, "°", "경계를 앞뒤로 기울인다(목: 깃처럼 앞이 낮게)")
	var brow := HBoxContainer.new()
	var b1 := Button.new()
	b1.text = "목 · 손목 곧게"
	_tip(b1, "자주 쓰는 경계(목 · 두 손목)를 한 번에 켠다 — 목 +6 cm(깃 위), 손목 −3 cm(소매 끝)")
	b1.pressed.connect(func(): _enable_joints(["Head", "L_Hand", "R_Hand"]))
	brow.add_child(b1)
	var b2 := Button.new()
	b2.text = "모든 관절 곧게"
	_tip(b2, "켜지 않은 모든 관절 경계를 시작 위치로 켠다(목 +6 cm, 손목 −3 cm, 나머지 0). 엉덩이는 없음 — 고관절은 평면으로 자르면 조각이 찢긴다")
	b2.pressed.connect(func(): _enable_joints(DRMeshCutter.JOINT_ORDER))
	brow.add_child(b2)
	s.add_child(brow)
	var urow := HBoxContainer.new()
	_undo_btn = Button.new()
	_undo_btn.text = "되돌리기 (Ctrl+Z)"
	_undo_btn.pressed.connect(_on_undo)
	urow.add_child(_undo_btn)
	_clear_btn = Button.new()
	_clear_btn.text = "경계 · 칠한 것 모두 지우기"
	_tip(_clear_btn, "칠할 대상(둘 다면 두 모델)의 관절 경계 · 자르기 · 붓 칠한 것을 모두 지운다(되돌리기 가능)")
	_clear_btn.pressed.connect(_on_clear_paint)
	urow.add_child(_clear_btn)
	s.add_child(urow)
	_paint_status = _hint(s, "")


func _joint_slider(parent: Control, label: String, lo: float, hi: float, step: float, unit: String, tip: String) -> HSlider:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(70, 0)
	_tip(l, tip)
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = 0.0
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tip(sl, tip)
	row.add_child(sl)
	var v := Label.new()
	v.custom_minimum_size = Vector2(60, 0)
	v.text = "0 " + unit
	row.add_child(v)
	var fmt := "%+.1f " if step < 1.0 else "%+.0f "
	sl.value_changed.connect(func(x):
		v.text = fmt % x + unit
		_on_joint_edit(false))
	sl.drag_ended.connect(func(_c): _joint_commit())
	parent.add_child(row)
	return sl


## 관절 목록을 채운다(기본 몸 기준 — 없으면 옷 모델). 상자 크기는 두 모델의 자식 부위 정점으로
func _fill_joints() -> void:
	_joints = {}
	var src := _t_base if _t_base != null else _t_outfit
	if src == null:
		return
	for j in DRMeshCutter.joint_list(src.baker.split, src.baker.source_mesh_instance, src.baker.skeleton):
		var pts := PackedVector3Array()
		for tt in [_t_outfit, _t_base]:
			var t := tt as PaintTarget
			if t == null:
				continue
			for i in t.pos.size():
				if t.auto[i] == String(j["to"]):
					pts.append(t.pos[i])
		j["h"] = DRMeshCutter.joint_box(pts, j["c"], j["d"])
		_joints[String(j["key"])] = j
	var keep := _joint_sel
	_filling = true
	_joint_opt.clear()
	for k in DRMeshCutter.JOINT_ORDER:
		if _joints.has(k):
			_joint_opt.add_item(String((_joints[k] as Dictionary)["label"]))
			_joint_opt.set_item_metadata(_joint_opt.item_count - 1, k)
	_filling = false
	_refresh_joint_labels()
	var idx := 0
	for i in _joint_opt.item_count:
		if String(_joint_opt.get_item_metadata(i)) == keep:
			idx = i
	if _joint_opt.item_count > 0:
		_joint_opt.select(idx)
		_on_joint_selected(false)


func _refresh_joint_labels() -> void:
	var src := _t_base if _t_base != null else _t_outfit
	for i in _joint_opt.item_count:
		var k := String(_joint_opt.get_item_metadata(i))
		var cut := _joint_cut(src, k)
		var lab := String((_joints[k] as Dictionary)["label"])
		if cut.is_empty():
			_joint_opt.set_item_text(i, lab)
		else:
			_joint_opt.set_item_text(i, "✓ %s  (%+.1f cm, %+.0f°)" % [lab, float(cut.get("offset", 0.0)) * 100.0, float(cut.get("tilt", 0.0))])


func _joint_cut(t: PaintTarget, key: String) -> Dictionary:
	if t == null or t.ov == null:
		return {}
	for c in t.ov.cuts:
		if String((c as Dictionary).get("kind", "")) == "joint" and String((c as Dictionary).get("joint", "")) == key:
			return c
	return {}


## 관절을 고르면: 슬라이더를 그 경계 값으로, 3D 카메라를 관절로, 노란 판 표시
func _on_joint_selected(focus: bool = true) -> void:
	if _filling or _joint_opt.selected < 0:
		return
	_joint_commit()
	_joint_sel = String(_joint_opt.get_item_metadata(_joint_opt.selected))
	var cut := _joint_cut(_t_base if _t_base != null else _t_outfit, _joint_sel)
	_filling = true
	_joint_on.button_pressed = not cut.is_empty()
	_joint_off.value = float(cut.get("offset", 0.0)) * 100.0
	_joint_tilt.value = float(cut.get("tilt", 0.0))
	_filling = false
	if focus and _joints.has(_joint_sel):
		_cam_target = (_joints[_joint_sel] as Dictionary)["c"]
		_cam_dist = 0.75
		_update_cam()
	_update_joint_plane()


## 슬라이더 · 곧게 체크 → 두 모델의 관절 경계를 바꾼다. 움직이는 동안은 3D 만, 끝나면(_joint_commit) 저장 · 2D
func _on_joint_edit(commit_now: bool) -> void:
	if _filling or not _loaded or _joint_sel == "" or not _joints.has(_joint_sel):
		return
	if not _joint_active:
		_joint_active = true
		_joint_snap = {}
		for tt in [_t_outfit, _t_base]:
			if tt != null and (tt as PaintTarget).ov != null:
				_joint_snap[tt] = (tt as PaintTarget).ov.cuts.duplicate(true)
	if not commit_now and not _joint_on.button_pressed:
		_filling = true
		_joint_on.button_pressed = true     # 위치 · 기울기를 움직이면 켜진다
		_filling = false
	elif commit_now and _joint_on.button_pressed and _joint_cut(_t_base if _t_base != null else _t_outfit, _joint_sel).is_empty() 			and _joint_off.value == 0.0 and _joint_tilt.value == 0.0:
		_filling = true                     # 처음 켤 때는 그 관절의 시작 위치(목 +6 cm)
		_joint_off.value = float(DRMeshCutter.JOINT_DEFAULT_OFFSET.get(_joint_sel, 0.0)) * 100.0
		_filling = false
	_set_joint_on_targets(_joint_sel, _joint_on.button_pressed, _joint_off.value * 0.01, _joint_tilt.value)
	_update_joint_plane()
	_disp_dirty = true
	_joint_idle = 0.0 if commit_now else 0.8


func _set_joint_on_targets(key: String, on: bool, offset: float, tilt: float) -> void:
	var j: Dictionary = _joints[key]
	var cut := {"kind": "joint", "joint": key, "from": j["from"], "to": j["to"],
		"offset": snappedf(offset, 0.0001), "tilt": snappedf(tilt, 0.01), "h": snappedf(float(j["h"]), 0.0001),
		"planes": DRMeshCutter.joint_planes(j["c"], j["d"], offset, tilt, float(j["h"]))}
	for tt in [_t_outfit, _t_base]:
		var t := tt as PaintTarget
		if t == null or t.ov == null:
			continue
		var at := -1
		var first_other := t.ov.cuts.size()
		for i in t.ov.cuts.size():
			var c := t.ov.cuts[i] as Dictionary
			if String(c.get("kind", "")) == "joint":
				if String(c.get("joint", "")) == key:
					at = i
			elif first_other == t.ov.cuts.size():
				first_other = i
		if at >= 0:
			if on:
				t.ov.cuts[at] = cut.duplicate(true)
			else:
				t.ov.cuts.remove_at(at)
		elif on:
			t.ov.cuts.insert(first_other, cut.duplicate(true))   # 관절 경계는 직접 자르기보다 앞(먼저 적용)


## 관절 경계 바꾼 것을 되돌리기 한 단계로 · 저장 · 다시 자르기 · 2D
func _joint_commit() -> void:
	if not _joint_active:
		return
	_joint_active = false
	var entry := {}
	for t in _joint_snap.keys():
		if (t as PaintTarget).ov.cuts != _joint_snap[t]:
			entry[t] = {CUTS_KEY: _joint_snap[t]}
	_joint_snap = {}
	if entry.is_empty():
		return
	_undo.append(entry)
	for t in entry.keys():
		_after_paint_change(t as PaintTarget)
	_refresh_joint_labels()
	_update_paint_status()


func _enable_joints(keys: Array) -> void:
	if not _loaded:
		return
	_joint_commit()
	_joint_active = true
	_joint_snap = {}
	for tt in [_t_outfit, _t_base]:
		if tt != null and (tt as PaintTarget).ov != null:
			_joint_snap[tt] = (tt as PaintTarget).ov.cuts.duplicate(true)
	var src := _t_base if _t_base != null else _t_outfit
	for k in keys:
		if _joints.has(k) and _joint_cut(src, k).is_empty():
			_set_joint_on_targets(k, true, float(DRMeshCutter.JOINT_DEFAULT_OFFSET.get(k, 0.0)), 0.0)
	_joint_commit()
	_on_joint_selected(false)
	_refresh_display()


## 저장된 복장(<출력 폴더>/<복장 이름>/outfit.json)이 지금 세트와 다른 설정으로 구운 것인가 — 맞으면 "", 아니면 알림 문장.
## 세트를 ① 탭에서 다시 구우면(해상도 등) 저장된 복장은 게임 · F6 에서 안 입혀진다(10-08). 미리보기는 그때그때 새로 구워 멀쩡해 보인다.
func _saved_outfit_stale() -> String:
	var jp := _out_edit.text.strip_edges().path_join(_id_edit.text.strip_edges()).path_join("outfit.json")
	if ob == null or not FileAccess.file_exists(jp):
		return ""
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(jp))
	if not (v is Dictionary):
		return ""
	var saved: Dictionary = (v as Dictionary).get("sets", {})
	var bad: Array = []
	for s in ob.sets:
		var sname := String((s as Dictionary)["name"])
		if not saved.has(sname):
			bad.append("%s(없음)" % sname)
			continue
		var was := String((saved[sname] as Dictionary).get("view", ""))
		var now := DROutfit.view_sig(((s as Dictionary).get("rig", {}) as Dictionary).get("view", {}))
		if was != "" and now != "" and was != now:
			bad.append("%s(%s → %s)" % [sname, was.get_slice("|", 0), now.get_slice("|", 0)])
	if bad.is_empty():
		return ""
	return "저장된 복장 %s 이 지금 세트와 다르게 구운 것입니다: %s — [굽기]로 다시 구우세요(안 그러면 게임 · F6 에서 안 입혀짐)." % [jp.get_file(), ", ".join(PackedStringArray(bad))]


## 기본 몸의 관절 경계를 옷 모델에도(캐릭터 하나에 경계 하나 — 옷마다 다시 정하지 않게). 옮긴 관절 수(바뀐 게 없으면 0)
func _sync_joints_from_base() -> int:
	if _t_base == null or _t_outfit == null or _t_base.ov == null or _t_outfit.ov == null:
		return 0
	var want: Array = []
	for c in _t_base.ov.cuts:
		if String((c as Dictionary).get("kind", "")) == "joint":
			want.append((c as Dictionary).duplicate(true))
	var have: Array = []
	var rest: Array = []
	for c in _t_outfit.ov.cuts:
		if String((c as Dictionary).get("kind", "")) == "joint":
			have.append(c)
		else:
			rest.append(c)
	if have == want:
		return 0
	_t_outfit.ov.cuts = want + rest
	_after_paint_change(_t_outfit)
	return maxi(want.size(), 1)


## 3D 의 노란 판 = 고른 관절의 경계(꺼져 있으면 흐리게)
func _update_joint_plane() -> void:
	if _joint_mi == null:
		return
	if not _loaded or _joint_sel == "" or not _joints.has(_joint_sel):
		_joint_mi.visible = false
		return
	var j: Dictionary = _joints[_joint_sel]
	var pl: Array = DRMeshCutter.joint_planes(j["c"], j["d"], _joint_off.value * 0.01, _joint_tilt.value, float(j["h"]))
	var n := Vector3(pl[0][0], pl[0][1], pl[0][2])
	var a := Vector3(pl[1][0], pl[1][1], pl[1][2])
	var y := n.cross(a).normalized()
	var x := y.cross(n).normalized()
	var h := float(j["h"])
	_joint_mi.transform = Transform3D(Basis(x * h * 2.0, y * h * 2.0, n), (j["c"] as Vector3) + (j["d"] as Vector3) * _joint_off.value * 0.01)
	var m := _joint_mi.material_override as StandardMaterial3D
	m.albedo_color = Color(1.0, 0.85, 0.2, 0.45 if _joint_on.button_pressed else 0.15)
	_joint_mi.visible = true


func _build_section_paint(col: Control) -> void:
	var s := _section(col, "4. 직접 고치기 (고급)", true)
	_hint(s, "관절 경계로 안 되는 곳만 — 예: 상의 자락을 Torso 로. 오른쪽 3D 의 색 = 실제로 잘리는 조각. 직선 = 선이 지나는 두 부위의 경계만, 사각형 = 화면에 보이는 부위만, 붓 = 보이는 면만(기본) — 뒤에 숨은 다른 부위는 안 건드린다.")
	_tgt_btns = _toggle_row(s, "칠할 대상", [
		["both", "둘 다 (기본)", "옷 모델에 칠하는 붓질 · 선이 기본 몸(민소매)의 같은 자리에도 같이 들어간다. 머리 · 손처럼 기본 몸 그림을 그대로 쓰는 조각은 옷 그림 위에 그려지므로, 경계를 옷에만 옮기면 화면이 안 바뀐다(목 · 손목) — 그래서 둘을 같이 자른다"],
		["outfit", "옷 모델만", "옷 입은 모델의 조각 경계만 — 예: 상의 자락을 Torso 로"],
		["base", "기본 몸만", "3D 에 기본 몸(민소매)을 띄워 그 조각 경계만 고친다. 굽기 때 기본 몸 세트에 자동으로 들어간다"]],
		func(k): _switch_target(k))
	(_tgt_btns["both"] as Button).button_pressed = true
	_tool_btns = _toggle_row(s, "도구", [
		["line", "직선 자르기 (L)", "3D 위에 선을 긋는다 — 선이 지나는 부위를 그 선 그대로 곧게 잘라, 고른 부위 쪽을 고른 부위로(앞뒤 함께). 목선 · 손목선 · 허리선. Shift = 수평 · 수직 · 45°"],
		["rect", "사각형 (R)", "3D 위에 사각형을 끈다 — 사각형 안(앞뒤 함께)이 고른 부위로, 가장자리가 사각형 그대로 곧다"],
		["brush", "붓 (B)", "왼쪽 버튼으로 문지른다 — 붓 범위 안의 정점이 고른 부위로. 정점 단위라 경계가 삼각형을 따라 들쭉날쭉 — 곧은 경계는 직선 · 사각형으로"]],
		func(k): _set_tool(k))
	(_tool_btns["line"] as Button).button_pressed = true
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
		b.pressed.connect(func():
			_paint_part = part_name
			_update_hud())
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
	_brush_spin.value = 3.0
	_brush_spin.value_changed.connect(func(_v): _update_brush())
	row.add_child(_brush_spin)
	_front_only = CheckBox.new()
	_front_only.text = "보이는 면만"
	_front_only.button_pressed = true
	_tip(_front_only, "붓: 카메라 쪽을 보는 정점만 칠한다(얇은 천의 뒤쪽까지 칠해지지 않게).")
	row.add_child(_front_only)
	s.add_child(row)


func _build_section_slots(col: Control) -> void:
	var s := _section(col, "5. 슬롯 (상의 · 하의)")
	_hint(s, "파트마다 상의 · 하의 · 안 씀. 게임에서 상의만 / 하의만 따로 입힐 때 이 묶음을 쓴다(시험장 O · P 키). 안 씀(머리 · 손)은 굽지 않고 기본 몸 그대로. 발은 하의.")
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
	_bake_btn.text = "굽기 (모든 자세)"
	_bake_btn.disabled = true
	_tip(_bake_btn, "기본 몸을 칠했으면 먼저 기본 몸 세트(sets.json 의 세트들)에 새 조각 그림을 넣고, 이어서 복장을 모든 세트에 굽는다. 게임: soldier.wear(DROutfit.load_json(\"…/outfit.json\"))")
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
	for k in ["top", "bottom"]:
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
	_tip(_pv2, "기본 몸 퍼펫에 지금 칠하기 · 슬롯으로 임시로 구운 옷을 입힌 모습 — 게임에서 보이는 그대로. 기본 몸을 칠한 것도 바로 보인다.")
	panel.add_child(_pv2)
	_vp2 = SubViewport.new()
	_vp2.size = Vector2i(460, 620)
	_vp2.transparent_bg = false
	_vp2.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp2)
	_pv_bg2 = ColorRect.new()
	_pv_bg2.color = PV_BG_DEFAULT
	_pv_bg2.size = Vector2(_vp2.size)
	# 퍼펫의 외곽선 밑깔개(z −1)보다 아래 — z 0 이면 배경이 외곽선을 덮어 실루엣 선이 사라지고 관절 틈마다 배경이 비쳤다(10-08 "3번 탭에 몸이 뚫려 보임")
	_pv_bg2.z_index = RenderingServer.CANVAS_ITEM_Z_MIN
	_vp2.add_child(_pv_bg2)
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
	_line_ov = LineOverlay.new()
	_line_ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	_line_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pv3.add_child(_line_ov)
	_hud3 = Label.new()
	_hud3.position = Vector2(8, 6)
	_hud3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud3.add_theme_color_override("font_outline_color", Color.BLACK)
	_hud3.add_theme_constant_override("outline_size", 4)
	_pv3.add_child(_hud3)
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
	_joint_mi = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	_joint_mi.mesh = qm
	var jm := StandardMaterial3D.new()
	jm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	jm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	jm.cull_mode = BaseMaterial3D.CULL_DISABLED
	jm.albedo_color = Color(1.0, 0.85, 0.2, 0.45)
	_joint_mi.material_override = jm
	_joint_mi.visible = false
	_vp3.add_child(_joint_mi)
	_mat_part = StandardMaterial3D.new()
	_mat_part.vertex_color_use_as_albedo = true
	_mat_part.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_tex = StandardMaterial3D.new()
	_mat_tex.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_mix = StandardMaterial3D.new()
	_mat_mix.vertex_color_use_as_albedo = true
	_mat_mix.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pv3.texture = _vp3.get_texture()
	_hint(box, "노란 판 = 고른 관절 경계 · 왼쪽 버튼 = (고급 도구) 선 긋기 · 사각형 · 붓 · 오른쪽 끌기 = 돌리기 · 가운데 끌기 = 옮기기 · 휠 = 확대 · F = 맞춤 · L 직선 · R 사각형 · B 붓 · Ctrl+Z 되돌리기", 300.0)


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
		_id_edit.text = p.get_file().get_basename().to_lower()
		_on_load())


func _on_browse_raw() -> void:
	_file_dialog(RAW_FILTER, "AI 원본(.glb) — Dot Rigger", false, func(p):
		_raw_edit.text = p
		if _id_edit.text.strip_edges() == "":
			_id_edit.text = p.get_file().get_basename().to_lower()
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
	pm.popup(Rect2i(Vector2i(r.position + Vector2(0, r.size.y)) + window_origin(), Vector2i(int(r.size.x), 0)))


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
		if String(f).ends_with(".tres"):
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
	for t in [_t_outfit, _t_base]:
		if t != null and (t as PaintTarget).baker != null:
			(t as PaintTarget).baker.cleanup()
	_t_outfit = null
	_t_base = null
	_target = null
	baker = null
	ob = null
	if is_instance_valid(_soldier):
		_soldier.queue_free()
	_soldier = null
	_outfit = null
	_base_outfit = null
	_base_baked = {}
	_base_dirty = false
	_baked = {}
	_loaded = false
	_undo.clear()
	_stroke = {}
	_paint_both = false
	_joint_active = false
	_joint_snap = {}
	_joints = {}
	if _joint_mi != null:
		_joint_mi.visible = false
	if _pm_mi != null:
		_pm_mi.mesh = null


## 프리셋에서 굽기 설정(도트화 값 · 추가 동작 폴더 · 합성)을 읽는다. 기본 몸 모델 경로도 돌려준다
func _opts_from_preset() -> Dictionary:
	var opts := DRBaker.Options.new()
	var preset_path := _preset_edit.text.strip_edges()
	var base_model := ""
	if preset_path != "":
		var p := load(preset_path) as DRPreset
		if p == null:
			return {"error": "프리셋을 열 수 없습니다: %s" % preset_path}
		base_model = p.model_path
		opts.extra_anim_dir = p.extra_anim_dir
		opts.light_bands = p.light_bands
		opts.ambient = p.ambient
		opts.alpha_threshold = p.alpha_threshold
		opts.color_levels = p.color_levels
		opts.bleed_rings = p.bleed_rings
		opts.composites = p.composites.duplicate(true)
		opts.composite_upper_parts = p.composite_upper_parts
		opts.in_place = p.in_place
	return {"opts": opts, "base_model": base_model}


## 모델 하나로 칠할 대상 만들기(굽는 도구 · 세트 · 표시 데이터)
func _make_target(kind: String, model_path: String, opts: DRBaker.Options) -> PaintTarget:
	var scene := load(model_path) as PackedScene if model_path != "" and ResourceLoader.exists(model_path) else null
	if scene == null:
		return null
	var t := PaintTarget.new()
	t.kind = kind
	t.scene_path = model_path
	t.baker = DRBaker.new()
	if not t.baker.setup(self, scene, DRPartProfile.humanoid(), opts):
		return null
	await get_tree().process_frame
	t.ob = DROutfitBaker.new()
	t.ob.baker = t.baker
	if not t.ob.setup(_sets_edit.text.strip_edges()):
		t.baker.cleanup()
		return null
	if kind == "base":
		for pn in DROutfitBaker.ALL_PARTS:     # 기본 몸은 파트 전부(머리 · 손 포함)를 다시 굽는다
			t.ob.slots[pn] = "base"
	t.ov = t.baker.part_overrides
	_fill_target_mesh(t)
	return t


func _on_load() -> void:
	if _busy:
		return
	_busy = true
	_bake_btn.disabled = true
	_load_status.text = "불러오는 중…"
	var po := _opts_from_preset()
	if po.has("error"):
		_fail(String(po["error"]))
		return
	var mpath := _model_edit.text.strip_edges()
	if mpath != "" and mpath == String(po["base_model"]):
		_fail("옷 모델 칸에 기본 몸(%s)이 들어 있습니다 — 옷 입은 모델을 고르세요. 기본 몸을 칠하려면 불러온 뒤 3번의 [기본 몸] 단추." % mpath)
		return
	_teardown()
	_t_outfit = await _make_target("outfit", mpath, po["opts"])
	if _t_outfit == null:
		_fail("옷 모델을 세울 수 없습니다: %s (가져오기가 끝났는지 · 뼈대에 붙인 모델인지 · sets.json 확인)" % mpath)
		return
	baker = _t_outfit.baker
	ob = _t_outfit.ob
	_scene_path = mpath
	if _id_edit.text.strip_edges() == "":
		_id_edit.text = mpath.get_file().get_basename().to_lower()
	# 슬롯: 구운 복장을 연 경우 그때 것, 아니면 창의 칸
	_filling = true
	for pn in _slot_opts.keys():
		var want: String = SLOT_KEYS[maxi((_slot_opts[pn] as OptionButton).selected, 0)]
		if not _restore_slots.is_empty():
			want = String(_restore_slots.get(pn, ""))
			if want == "shoes":
				want = "bottom"
		(_slot_opts[pn] as OptionButton).select(SLOT_KEYS.find(want))
		ob.slots[pn] = want
	_filling = false
	_restore_slots = {}
	_fill_view_sets()
	_loaded = true
	_target = _t_outfit
	_show_target()
	await _build_soldier()
	_load_status.text = "세트 %d개 · 옷 모델 정점 %d · 칠한 자리 %d곳" % [ob.sets.size(), _t_outfit.pos.size(), _t_outfit.ov.size()]
	if ob.warnings.size() > 0:
		_load_status.text += "\n⚠ " + "\n⚠ ".join(ob.warnings)
	_remember_fields()
	_busy = false
	# 기본은 `둘 다` — 기본 몸도 불러 둔다. 기본 몸을 칠해 놓고 세트에 안 넣은 것이 있으면 미리보기에 반영하고 굽기 때 넣는다
	await _switch_target("both")
	_fill_joints()
	var stale := _saved_outfit_stale()
	if stale != "":
		_load_status.text += "\n⚠ " + stale
	var nj := _sync_joints_from_base()
	if nj > 0:
		_load_status.text += "\n기본 몸에 정한 관절 경계를 이 옷에도 적용했습니다."
	if _t_base != null and _base_paint_newer_than_sets():
		_base_dirty = true
		_base_pv_dirty = true
		_load_status.text += "\n기본 몸을 칠한 것(%d곳)이 아직 세트에 안 들어가 있어 미리보기에 반영했습니다 — `굽기` 때 세트에 들어갑니다." % _t_base.ov.size()
	_update_paint_status()
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


# ---------------------------------------------------------------- 칠할 대상 · 도구

## 칠할 대상 단추: both = 둘 다(3D 에는 옷 모델을 띄우고 같은 붓질 · 선을 기본 몸에도) · outfit = 옷 모델만 · base = 기본 몸만
func _switch_target(kind: String) -> void:
	if not _loaded or _busy:
		(_tgt_btns[_target_kind] as Button).set_pressed_no_signal(true)
		for k in _tgt_btns.keys():
			if k != _target_kind:
				(_tgt_btns[k] as Button).set_pressed_no_signal(false)
		return
	if kind != "outfit" and not await _ensure_base():
		kind = "outfit"
	_target_kind = kind
	_paint_both = kind == "both"
	for k in _tgt_btns.keys():
		(_tgt_btns[k] as Button).set_pressed_no_signal(k == kind)
	_target = _t_base if kind == "base" else _t_outfit
	_show_target()


## 기본 몸(프리셋의 모델)을 칠할 대상으로 불러 둔다. 이미 있으면 그대로
func _ensure_base() -> bool:
	if _t_base != null:
		return true
	_busy = true
	var keep := _status.text
	_status.text = "기본 몸 불러오는 중…"
	var po := _opts_from_preset()
	var bm := String(po.get("base_model", ""))
	if bm != "" and not po.has("error"):
		_t_base = await _make_target("base", bm, po["opts"])
	_busy = false
	if _t_base == null:
		_status.text = "⚠ 기본 몸을 불러올 수 없습니다(프리셋의 모델: %s) — 옷 모델만 칠합니다" % bm
		return false
	_status.text = keep
	return true


## 기본 몸을 칠한 파일이 구워 둔 세트보다 새것인가 — 칠해 놓고 세트에는 아직 안 들어간 상태(예전 창에서 칠했거나 굽기 전에 닫음)
func _base_paint_newer_than_sets() -> bool:
	var po := _opts_from_preset()
	var pj := DRPartOverrides.path_for(String(po.get("base_model", "")))
	if not FileAccess.file_exists(pj) or ob == null:
		return false
	var t_paint := FileAccess.get_modified_time(pj)
	var base := ob.sets_json.get_base_dir()
	for s in ob.sets:
		var scene := base.path_join(String((s as Dictionary).get("dir", ""))).path_join("puppet.tscn")
		if FileAccess.file_exists(scene) and FileAccess.get_modified_time(scene) < t_paint:
			return true
	return false


func _set_tool(kind: String) -> void:
	_tool = kind
	_brush_mi.visible = false
	_update_hud()


## 지금 대상을 3D 에 띄운다
func _show_target() -> void:
	if _target == null:
		return
	_mat_tex.albedo_texture = _target.tex
	_mat_mix.albedo_texture = _target.tex
	_refresh_display()
	_cam_yaw = 0.0
	_cam_pitch = 0.0
	_frame_cam()
	_update_brush()
	_update_paint_status()
	_update_hud()


func _update_hud() -> void:
	if _hud3 == null:
		return
	var who := "기본 몸" if _target != null and _target.kind == "base" else "옷 모델"
	if _paint_both:
		who = "옷 모델 + 기본 몸(둘 다)"
	var tool := String({"brush": "붓", "line": "직선 자르기", "rect": "사각형"}.get(_tool, _tool))
	var part := _paint_part if _paint_part != "" else "지우개"
	_hud3.text = "%s · %s · %s" % [who, tool, part]


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
	if ob.sets.size() > 0:
		var vs: Array = ((ob.sets[0] as Dictionary)["rig"] as Dictionary).get("view", {}).get("size", [192, 192])
		_pv_zoom.value = clampf(float(_vp2.size.y) * 0.92 / float(vs[1]), 0.3, 3.0)
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


## 옷(지금 칠하기 · 슬롯)을 모든 세트에 임시로 굽고, 기본 몸을 칠했으면 기본 몸도 다시 구워 같이 입힌다
func _refresh_preview() -> void:
	if not _loaded or ob == null:
		return
	_busy = true
	_status.text = "2D 미리보기 굽는 중…"
	if _base_pv_dirty and _t_base != null:
		_base_pv_dirty = false
		_base_baked = await _t_base.ob.bake_all()
		_base_outfit = _t_base.ob.to_outfit(_base_baked, "base")
	ob.warnings = PackedStringArray()
	_baked = await ob.bake_all()
	_outfit = ob.to_outfit(_baked, _id_edit.text.strip_edges())
	_apply_wear()
	_busy = false
	var n := 0
	for k in _baked.keys():
		n += (_baked[k] as Dictionary).size()
	_status.text = "준비됨 — 세트 %d개 · 옷 그림 %d장.%s 다 됐으면 `굽기`." % [_baked.size(), n,
		" 기본 몸 칠한 것은 굽기 때 세트에 들어간다." if _base_dirty else ""]
	if ob.warnings.size() > 0:
		_status.text += "\n⚠ " + "\n⚠ ".join(ob.warnings)


## 미리보기: 기본 몸(다시 자른 것이 있으면) 위에 체크한 슬롯의 옷
func _apply_wear() -> void:
	if not is_instance_valid(_soldier):
		return
	_soldier.take_off()
	if _base_outfit != null:
		_soldier.wear(_base_outfit, [], false)
	if _outfit == null:
		return
	var only: Array = []
	for k in _wear_cb.keys():
		if (_wear_cb[k] as CheckBox).button_pressed:
			only += _outfit.slot_parts(String(k))
	if only.size() > 0:
		_soldier.wear(_outfit, only, false)


func _on_slot_changed(part: String, i: int) -> void:
	if _filling or ob == null:
		return
	ob.slots[part] = SLOT_KEYS[i]
	_pv_dirty = true
	_pv_timer = PV_DEBOUNCE


# ---------------------------------------------------------------- 3D 부위 칠하기

## 대상 모델의 원본 메시(바인드 자세)에서 정점 · 삼각형 · 웨이트대로의 파트를 읽는다
func _fill_target_mesh(t: PaintTarget) -> void:
	var mi := t.baker.source_mesh_instance
	var src := mi.mesh as ArrayMesh
	if src == null:
		return
	var binds := DRMeshSplitter._bind_map(mi, t.baker.skeleton)
	var leg_rules := DRMeshSplitter.leg_rules(mi, t.baker.skeleton, t.baker.split.part_bones, t.baker.split.bone_part)
	for si in src.get_surface_count():
		if src.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] != null else PackedInt32Array()
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] != null else PackedFloat32Array()
		var nrm: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var vcount := verts.size()
		var bpv := int(bones.size() / float(maxi(vcount, 1)))
		var start := t.pos.size()
		for v in vcount:
			var best_w := -1.0
			var best_b := -1
			for k in bpv:
				var w := weights[v * bpv + k]
				if w > best_w:
					best_w = w
					best_b = bones[v * bpv + k]
			var skel_b := binds[best_b] if best_b >= 0 and best_b < binds.size() else -1
			t.auto.append(DRMeshSplitter.leg_part(String(t.baker.split.bone_part.get(skel_b, "")), verts[v], leg_rules))   # 굽기와 같은 다리 규칙
			t.pos.append(verts[v])
			t.nrm.append(nrm[v] if nrm.size() == vcount else Vector3.UP)
			t.uv.append(uvs[v] if uvs.size() == vcount else Vector2.ZERO)
			t.keys.append(DRPartOverrides.key_of(verts[v]))
		for k in idx.size():
			t.tri.append(start + idx[k])
		for tt in int(idx.size() / 3):
			var a := verts[idx[tt * 3]]
			t.tri_a.append(a)
			t.tri_e1.append(verts[idx[tt * 3 + 1]] - a)
			t.tri_e2.append(verts[idx[tt * 3 + 2]] - a)
		var mat := mi.get_active_material(si)
		if t.tex == null and mat is BaseMaterial3D:
			t.tex = (mat as BaseMaterial3D).albedo_texture


func _part_color(part: String) -> Color:
	return PART_COLORS.get(part, Color(0.35, 0.35, 0.35))


## 면마다 한 색 — 그 면이 실제로 들어가는 조각(세 정점 중 둘 이상이 같은 부위면 그 부위). 붓으로 칠한 면은 조금 밝게.
## 자르기는 굽기와 같은 방식으로 면을 평면에서 쪼개 보여 준다(겹침 없이) — 3D 의 색 경계 = 실제로 잘리는 곧은 선.
func _refresh_display() -> void:
	var t := _target
	if t == null or t.pos.is_empty():
		_pm_mi.mesh = null
		return
	var n0 := t.pos.size()
	var vpart := PackedStringArray()
	vpart.resize(n0)
	var vpaint := PackedByteArray()
	vpaint.resize(n0)
	for i in n0:
		var p := String(t.ov.map.get(t.keys[i], "")) if t.ov != null else ""
		vpaint[i] = 1 if p != "" else 0
		vpart[i] = p if p != "" else t.auto[i]
	var part_tris := {}
	for k in int(t.tri.size() / 3):
		var i0 := t.tri[k * 3]
		var i1 := t.tri[k * 3 + 1]
		var i2 := t.tri[k * 3 + 2]
		var p0 := vpart[i0]
		var p1 := vpart[i1]
		var p2 := vpart[i2]
		var main := p0 if (p0 == p1 or p0 == p2) else (p1 if p1 == p2 else p0)
		if not part_tris.has(main):
			part_tris[main] = PackedInt32Array()
		var arr: PackedInt32Array = part_tris[main]
		arr.append(i0)
		arr.append(i1)
		arr.append(i2)
		part_tris[main] = arr
	var pp := t.pos
	var pn := t.nrm
	var pu := t.uv
	if t.ov != null and not t.ov.cuts.is_empty():
		var src := []
		src.resize(Mesh.ARRAY_MAX)
		src[Mesh.ARRAY_VERTEX] = t.pos
		src[Mesh.ARRAY_NORMAL] = t.nrm
		src[Mesh.ARRAY_TEX_UV] = t.uv
		var pool := DRMeshCutter.VertexPool.new(src)
		var allp := {}
		for k in PART_COLORS.keys():
			allp[k] = true
		for k in part_tris.keys():
			allp[k] = true
		DRMeshCutter.apply_cuts(part_tris, t.ov.cuts, pool, allp, 0.0)
		pp = pool.pos
		pn = pool.nrm
		pu = pool.uv
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var us := PackedVector2Array()
	var cs := PackedColorArray()
	for part in part_tris.keys():
		var tris: PackedInt32Array = part_tris[part]
		var base_c := _part_color(String(part))
		for k in int(tris.size() / 3):
			var c := base_c
			for j in 3:
				var vi := tris[k * 3 + j]
				if vi < n0 and vpaint[vi] == 1 and vpart[vi] == part:
					c = base_c.lerp(Color.WHITE, 0.3)
					break
			for j in 3:
				var vi2 := tris[k * 3 + j]
				vs.append(pp[vi2])
				ns.append(pn[vi2])
				us.append(pu[vi2])
				cs.append(c)
	if vs.is_empty():
		_pm_mi.mesh = null
		return
	var arr2 := []
	arr2.resize(Mesh.ARRAY_MAX)
	arr2[Mesh.ARRAY_VERTEX] = vs
	arr2[Mesh.ARRAY_NORMAL] = ns
	arr2[Mesh.ARRAY_TEX_UV] = us
	arr2[Mesh.ARRAY_COLOR] = cs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
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


## 모델 전체(T-포즈 팔 끝까지)가 칸에 들어오게 — 칸의 가로세로 비율까지 따진다(F 키)
func _frame_cam() -> void:
	var m := _pm_mi.mesh
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
	var t := _target
	if t == null or t.tri_a.is_empty():
		return {"hit": false}
	var o := _cam3.project_ray_origin(vp_pos)
	var d := _cam3.project_ray_normal(vp_pos)
	var best := INF
	var best_k := -1
	for k in t.tri_a.size():
		var e1 := t.tri_e1[k]
		var e2 := t.tri_e2[k]
		var pv := d.cross(e2)
		var det := e1.dot(pv)
		if absf(det) < 1e-12:
			continue
		var inv := 1.0 / det
		var tv := o - t.tri_a[k]
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
			best_k = k
	if best == INF:
		return {"hit": false}
	return {"hit": true, "pos": o + d * best, "tri": best_k}


## 지금 칠해지는 대상들 — `둘 다` 면 옷 모델과 기본 몸에 같은 붓질 · 같은 선이 들어간다.
## 두 모델은 같은 뼈대 · 같은 T-포즈라 같은 자리의 경계가 같은 곳을 자른다(그래야 조각을 서로 바꿔 끼울 때 이가 맞는다).
func _paint_targets() -> Array:
	var out: Array = []
	if _target != null:
		out.append(_target)
	if _paint_both:
		for t in [_t_outfit, _t_base]:
			if t != null and not out.has(t):
				out.append(t)
	return out


## 정점 하나를 part 로(이번 붓질의 되돌리기 기록 포함). 바뀌었으면 true
func _set_vertex(t: PaintTarget, i: int, part: String) -> bool:
	var k = t.keys[i]
	var prev := String(t.ov.map.get(k, ""))
	if prev == part:
		return false
	if not _stroke.has(t):
		_stroke[t] = {}
	if not (_stroke[t] as Dictionary).has(k):
		_stroke[t][k] = prev
	if part == "":
		t.ov.map.erase(k)
	else:
		t.ov.map[k] = part
	return true


## 붓질 한 번: 붓 범위 안의 정점을 part 로(part = "" 이면 지움). 바뀐 정점 수(모든 대상 합)
func paint_at(hit: Vector3, part: String, radius: float = -1.0) -> int:
	if _target == null:
		return 0
	var r := radius if radius > 0.0 else _brush_spin.value * 0.01
	var view_dir := (_cam3.global_position - hit).normalized()
	var changed := 0
	for tt in _paint_targets():
		var t := tt as PaintTarget
		if t.ov == null:
			continue
		# 화면에 안 보이는 쪽(옷 속의 몸 등)은 표면이 조금 안쪽이라 붓을 넉넉히
		var rr := r if t == _target else r * 1.5 + 0.015
		var r2 := rr * rr
		for i in t.pos.size():
			if t.pos[i].distance_squared_to(hit) > r2:
				continue
			if t == _target and _front_only.button_pressed and t.nrm[i].dot(view_dir) < 0.0:
				continue
			if _set_vertex(t, i, part):
				changed += 1
	if changed > 0:
		_refresh_display()
		_update_paint_status()
	return changed


## 직선 자르기: 화면의 선 a → b(뷰포트 좌표)로 자른다 — 삼각형을 평면에서 쪼개므로 경계가 그은 선 그대로 곧다(DRMeshCutter).
## 선 근처에서 가장 많이 걸린 부위(칠할 부위 말고)를 "자를 부위"로 잡고, 카메라와 선이 이루는 평면으로 그 부위를 둘로 나눠
## 칠할 부위가 이미 있는 쪽(없으면 작은 쪽)을 칠할 부위로. 선의 양 끝 사이(화면 기준)만 — 앞뒤는 함께 잘린다.
## `둘 다` 면 같은 자르기(같은 평면 · 같은 자를 부위)를 다른 대상에도 넣는다.
## 돌려주는 값: {changed(부위가 바뀐 정점 수 합), source, per: {kind: 바뀐 수}}
func split_line(a: Vector2, b: Vector2, part: String) -> Dictionary:
	var t := _target
	if t == null or t.ov == null or a.distance_to(b) < 6.0:
		return {"changed": 0}
	if part == ERASE:
		return {"changed": 0, "erase": true}
	# 선 끝을 조금 늘린다 — 끝이 모델 가장자리에 살짝 못 미치거나, `둘 다` 에서 옷 속의 몸이 옷보다 조금 삐져 있어도 끝까지 잘리게
	var ext := (b - a).normalized() * ((b - a).length() * 0.08 + 10.0)
	var a2 := a - ext
	var b2 := b + ext
	var o := _cam3.project_ray_origin(a2)
	var na := _cam3.project_ray_normal(a2)
	var nb := _cam3.project_ray_normal(b2)
	var n := na.cross(nb).normalized()
	var seg := b2 - a2
	var seg_len := seg.length()
	var u := seg / seg_len
	var near_count := {}
	var cand: Array = []                    # [쪽(+1/−1), 지금 부위]
	for i in t.pos.size():
		var p := t.pos[i]
		if _cam3.is_position_behind(p):
			continue
		var s := _cam3.unproject_position(p)
		var tt := (s - a2).dot(u) / seg_len
		if tt < 0.0 or tt > 1.0:
			continue
		var cur := t.part_of(i)
		cand.append([1 if n.dot(p - o) >= 0.0 else -1, cur])
		if absf((s - a2).dot(Vector2(-u.y, u.x))) < 14.0 and cur != part:
			near_count[cur] = int(near_count.get(cur, 0)) + 1
	if near_count.is_empty():
		return {"changed": 0}
	var source := ""
	var best := -1
	for k in near_count.keys():
		if int(near_count[k]) > best:
			best = int(near_count[k])
			source = String(k)
	# 칠할 부위가 이미 있는 쪽 = 그 쪽으로 넓힌다. 없으면 자를 부위의 작은 쪽
	var tgt_side := {1: 0, -1: 0}
	var src_side := {1: 0, -1: 0}
	for c in cand:
		if String(c[1]) == part:
			tgt_side[c[0]] += 1
		elif String(c[1]) == source:
			src_side[c[0]] += 1
	var pick_side := 1
	if tgt_side[1] != tgt_side[-1]:
		pick_side = 1 if tgt_side[1] > tgt_side[-1] else -1
	else:
		pick_side = 1 if src_side[1] <= src_side[-1] else -1
	if pick_side < 0:
		n = -n
	# 선의 양 끝 = 카메라 광선을 품은 두 평면(안쪽을 보게)
	var sa := na.cross(n).normalized()
	if sa.dot(nb) < 0.0:
		sa = -sa
	var sb := nb.cross(n).normalized()
	if sb.dot(na) < 0.0:
		sb = -sb
	var planes := [_plane(n, o), _plane(sa, o), _plane(sb, o)]
	var r := _add_cut({"to": part, "from": source, "planes": planes, "kind": "line"})
	r["source"] = source
	return r


## 사각형 자르기: 화면의 사각형(뷰포트 좌표 a · b 대각) 안 = 칠할 부위(앞뒤 함께, 어느 부위든). 가장자리가 사각형 그대로 곧다.
func rect_cut(a: Vector2, b: Vector2, part: String) -> Dictionary:
	if _target == null or _target.ov == null:
		return {"changed": 0}
	if part == ERASE:
		return {"changed": 0, "erase": true}
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	if hi.x - lo.x < 4.0 or hi.y - lo.y < 4.0:
		return {"changed": 0}
	# 사각형 안에서 화면에 보이는(맨 앞) 부위만 — 뒤에 숨은 다른 부위(반대쪽 팔 · 몸 뒤)는 안 건드린다
	var only := {}
	for gy in 9:
		for gx in 9:
			var h := pick(lo + (hi - lo) * Vector2((gx + 0.5) / 9.0, (gy + 0.5) / 9.0))
			if not bool(h.get("hit", false)):
				continue
			var k := int(h["tri"])
			var vp := _target.part_of(_target.tri[k * 3])
			var vp1 := _target.part_of(_target.tri[k * 3 + 1])
			var vp2 := _target.part_of(_target.tri[k * 3 + 2])
			var main := vp if (vp == vp1 or vp == vp2) else (vp1 if vp1 == vp2 else vp)
			if main != part:
				only[main] = true
	if only.is_empty():
		return {"changed": 0}
	var corners := [lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)]
	var o := _cam3.project_ray_origin(lo)
	var mid := _cam3.project_ray_normal((lo + hi) * 0.5)
	var planes: Array = []
	for i in 4:
		var ra := _cam3.project_ray_normal(corners[i])
		var rb := _cam3.project_ray_normal(corners[(i + 1) % 4])
		var nn := ra.cross(rb).normalized()
		if nn.dot(mid) < 0.0:
			nn = -nn
		planes.append(_plane(nn, o))
	var r := _add_cut({"to": part, "from": "*", "only": only.keys(), "planes": planes, "kind": "rect"})
	r["source"] = ", ".join(PackedStringArray(only.keys()))
	return r


func _plane(nv: Vector3, o: Vector3) -> Array:
	return [snappedf(nv.x, 0.000001), snappedf(nv.y, 0.000001), snappedf(nv.z, 0.000001), snappedf(nv.dot(o), 0.000001)]


## 자르기 하나를 칠하는 대상(들)에 넣는다(되돌리기 기록 포함). 부위가 바뀐 정점 수를 센다
func _add_cut(cut: Dictionary) -> Dictionary:
	var per := {}
	var total := 0
	for tt in _paint_targets():
		var t := tt as PaintTarget
		if t.ov == null:
			continue
		var before := PackedStringArray()
		before.resize(t.pos.size())
		for i in t.pos.size():
			before[i] = t.part_of(i)
		if not _stroke.has(t):
			_stroke[t] = {}
		if not (_stroke[t] as Dictionary).has(CUTS_KEY):
			_stroke[t][CUTS_KEY] = t.ov.cuts.duplicate(true)
		t.ov.cuts.append(cut.duplicate(true))
		var ch := 0
		for i in t.pos.size():
			if t.part_of(i) != before[i]:
				ch += 1
		per[t.kind] = ch
		total += ch
	_refresh_display()
	_update_paint_status()
	return {"changed": total, "per": per}


## 붓질 · 선 긋기가 끝나면 저장하고, 잠시 뒤 다시 잘라 2D 를 다시 굽는다
func end_stroke() -> void:
	_painting = false
	if _stroke.is_empty():
		return
	var done := _stroke
	_stroke = {}
	_undo.append(done)
	for t in done.keys():
		_after_paint_change(t as PaintTarget)


func _after_paint_change(t: PaintTarget) -> void:
	if t.ov != null:
		t.ov.save()
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().update_file(DRPartOverrides.path_for(t.scene_path))
	t.resplit_dirty = true
	if t.kind == "base":
		_base_dirty = true
		_base_pv_dirty = true
	_pv_dirty = true
	_pv_timer = PV_DEBOUNCE
	_update_paint_status()


## 되돌리기 — 마지막 붓질 · 선 하나(둘 다에 들어간 것은 둘 다 되돌린다)
func _on_undo() -> void:
	_joint_commit()        # 관절 슬라이더를 움직이던 중이면 그것부터 한 단계로
	if _undo.is_empty():
		return
	var last: Dictionary = _undo.pop_back()
	for tt in last.keys():
		var t := tt as PaintTarget
		if t == null or t.ov == null:
			continue
		var ch: Dictionary = last[tt]
		for k in ch.keys():
			if k is String and k == CUTS_KEY:
				t.ov.cuts = (ch[k] as Array).duplicate(true)
				continue
			var prev := String(ch[k])
			if prev == "":
				t.ov.map.erase(k)
			else:
				t.ov.map[k] = prev
		_after_paint_change(t)
	_refresh_display()
	_after_cuts_reset()


## 되돌리기 · 모두 지우기 뒤: 관절 칸(체크 · 슬라이더 · 목록 표시)을 지금 경계에 맞춘다
func _after_cuts_reset() -> void:
	_joint_active = false
	_joint_snap = {}
	if _joint_opt != null and _joint_opt.item_count > 0:
		_refresh_joint_labels()
		_on_joint_selected(false)


## 지금 칠하는 대상(들)의 칠한 것을 모두 지운다(되돌리기 가능)
func _on_clear_paint() -> void:
	var snap := {}
	for tt in _paint_targets():
		var t := tt as PaintTarget
		if t.ov == null or t.ov.is_empty():
			continue
		var s := {}
		for k in t.ov.map.keys():
			s[k] = String(t.ov.map[k])
		s[CUTS_KEY] = t.ov.cuts.duplicate(true)
		snap[t] = s
		t.ov.map.clear()
		t.ov.cuts.clear()
	if snap.is_empty():
		return
	_undo.append(snap)
	for t in snap.keys():
		_after_paint_change(t as PaintTarget)
	_refresh_display()
	_after_cuts_reset()


func _update_paint_status() -> void:
	if _paint_status == null:
		return
	if _target == null:
		_paint_status.text = ""
		return
	var lines := PackedStringArray()
	for tt in [_t_outfit, _t_base]:
		var t := tt as PaintTarget
		if t != null and t.ov != null:
			var nj := 0
			for c in t.ov.cuts:
				if String((c as Dictionary).get("kind", "")) == "joint":
					nj += 1
			lines.append("%s — 관절 경계 %d · 직접 자르기 %d · 붓 %d곳 (%s)" % ["기본 몸" if t.kind == "base" else "옷 모델", nj, t.ov.cuts.size() - nj, t.ov.size(), DRPartOverrides.path_for(t.scene_path).get_file()])
	lines.append("되돌리기 %d번 가능" % _undo.size())
	if _base_dirty:
		lines.append("기본 몸 칠한 것은 `굽기` 때 기본 몸 세트에 같이 들어갑니다(① 탭에서 다시 구울 필요 없음).")
	_paint_status.text = "\n".join(lines)
	_undo_btn.disabled = _undo.is_empty()


func _on_pv3_input(ev: InputEvent) -> void:
	if not _loaded or _target == null:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		_pv3.grab_focus()
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _tool == "line" or _tool == "rect":
				if mb.pressed:
					_line_on = true
					_line_ov.on = true
					_line_ov.rect = _tool == "rect"
					_line_ov.a = mb.position
					_line_ov.b = mb.position
					_line_ov.queue_redraw()
				elif _line_on:
					_line_on = false
					_line_ov.on = false
					_line_ov.queue_redraw()
					var end_pt := _line_ov.b if _tool == "line" else mb.position
					_stroke = {}
					var va := _to_vp(_pv3, _vp3, _line_ov.a)
					var vb := _to_vp(_pv3, _vp3, end_pt)
					var r := split_line(va, vb, _paint_part) if _tool == "line" else rect_cut(va, vb, _paint_part)
					end_stroke()
					if bool(r.get("erase", false)):
						_status.text = "직선 · 사각형은 지우개로 못 씁니다 — 자르기를 없애려면 Ctrl+Z(되돌리기) 또는 `칠한 것 · 자르기 모두 지우기`."
						return
					if int(r.get("changed", 0)) > 0:
						var per: Dictionary = r.get("per", {})
						var detail := "옷 모델 %d곳" % int(per.get("outfit", 0)) if per.has("outfit") else ""
						if per.has("base"):
							detail += ("" if detail == "" else " · ") + "기본 몸 %d곳" % int(per.get("base", 0))
						_status.text = "%s: %s → %s (%s)" % ["직선 자르기" if _tool == "line" else "사각형", String(r.get("source", "사각형 안")), _paint_part, detail]
					else:
						_status.text = "바뀐 곳 없음 — 선은 부위 경계를 지나게, 사각형은 모델을 덮게 그어 주세요."
			elif mb.pressed:
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
		elif _line_on:
			var pb := mm.position
			if _tool == "line" and mm.shift_pressed:      # Shift = 수평 · 수직 · 45°
				var dv := pb - _line_ov.a
				pb = _line_ov.a + Vector2.from_angle(snappedf(dv.angle(), PI / 4.0)) * dv.length()
			_line_ov.b = pb
			_line_ov.queue_redraw()
		elif _painting:
			if mm.position.distance_to(_last_pick_px) >= 3.0:
				_paint_from_screen(mm.position)
		elif _tool == "brush" and mm.position.distance_to(_last_pick_px) >= 6.0:
			_hover(mm.position)
	elif ev is InputEventKey and (ev as InputEventKey).pressed:
		var ke := ev as InputEventKey
		if ke.keycode == KEY_F:
			_frame_cam()
		elif ke.keycode == KEY_Z and ke.ctrl_pressed:
			_on_undo()
		elif ke.keycode == KEY_B:
			(_tool_btns["brush"] as Button).button_pressed = true
			_set_tool("brush")
		elif ke.keycode == KEY_L:
			(_tool_btns["line"] as Button).button_pressed = true
			_set_tool("line")
		elif ke.keycode == KEY_R:
			(_tool_btns["rect"] as Button).button_pressed = true
			_set_tool("rect")


func _paint_from_screen(p: Vector2) -> void:
	_last_pick_px = p
	var h := pick(_to_vp(_pv3, _vp3, p))
	_brush_mi.visible = bool(h.get("hit", false))
	if _brush_mi.visible:
		_brush_mi.position = h["pos"]
		paint_at(h["pos"], _paint_part)


func _hover(p: Vector2) -> void:
	_last_pick_px = p
	var h := pick(_to_vp(_pv3, _vp3, p))
	_brush_mi.visible = bool(h.get("hit", false))
	if _brush_mi.visible:
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
	if not is_visible_in_tree() or not _loaded:
		return
	if _busy or _painting or _line_on:
		return
	if _joint_active:
		_joint_idle -= delta
		if _joint_idle <= 0.0:
			_joint_commit()
	if _disp_dirty:
		_disp_dirty = false
		_refresh_display()
	if _ctx_stale:
		_ctx_stale = false
		_on_load()
		return
	for t in [_t_outfit, _t_base]:
		var pt := t as PaintTarget
		if pt != null and pt.resplit_dirty:
			pt.resplit_dirty = false
			pt.baker.resplit(pt.ov)
	if _pv_dirty:
		_pv_timer -= delta
		if _pv_timer <= 0.0:
			_pv_dirty = false
			_refresh_preview()


## 굽기: 기본 몸을 칠했으면 기본 몸 세트에 먼저 넣고, 이어서 복장을 모든 세트에
func _on_bake() -> void:
	if not _loaded or _busy:
		return
	var id := _id_edit.text.strip_edges()
	if id == "":
		_status.text = "⚠ 복장 이름을 적어 주세요"
		return
	for t in [_t_outfit, _t_base]:
		var pt := t as PaintTarget
		if pt != null and pt.resplit_dirty:
			pt.resplit_dirty = false
			pt.baker.resplit(pt.ov)
	_busy = true
	_bake_btn.disabled = true
	var msg := PackedStringArray()
	if _base_dirty and _t_base != null:
		_status.text = "기본 몸 세트 다시 굽는 중…"
		_base_baked = await _t_base.ob.bake_all()
		var done := _t_base.ob.write_base_sets(_base_baked)
		msg.append("기본 몸 세트 %d개에 새 조각 그림 넣음 (%s)" % [done.size(), ", ".join(done)])
		for w in _t_base.ob.warnings:
			msg.append("⚠ " + w)
		_base_dirty = false
		_base_pv_dirty = false
		_base_outfit = null
		if is_instance_valid(_soldier):
			_soldier.reload()
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().scan()
	var cb := func(i, n, nm):
		_progress.max_value = n
		_progress.value = i + 1
		_status.text = "복장 굽는 중 %d/%d — %s" % [i + 1, n, nm]
	ob.progress.connect(cb)
	var res: Dictionary = await ob.run(_out_edit.text.strip_edges(), id, _scene_path)
	ob.progress.disconnect(cb)
	_busy = false
	_bake_btn.disabled = false
	_progress.value = 0
	if bool(res.get("ok", false)):
		msg.append("복장 완료 — 세트 %d개 → %s · 시험장 F6 의 O(상의) · P(하의)" % [(res["sets"] as Array).size(), String(res["json"]).get_base_dir()])
		for w in res.get("warnings", PackedStringArray()):
			msg.append("⚠ " + String(w))
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().scan()
		_remember_fields()
	else:
		msg.append("⚠ 복장 굽기 실패: %s" % String(res.get("error", "?")))
	_status.text = "\n".join(msg)
	_update_paint_status()
	_apply_wear()
