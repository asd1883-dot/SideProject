@tool
extends DRPage
class_name DROutfitPage

## Dot Rigger 창 ③ 복장 탭(10-16, 3D 노선) — 예전 ③ 복장 굽기(ui/outfit_window.gd · 옷을 세트마다 2D 그림으로 굽던 것)를 갈음한다.
## 왜: 사용자 결정(10-15) "2D 스파인 리소스 관리가 힘들어서 3D 로" — 게임이 3D 캐릭터를 바로 쓰므로 옷도 굽지 않는다.
##   게임(DRCharacter3D.wear)은 outfit.json 의 옷 모델을 슬롯 표대로 슬롯 메시로 나눠(DRSlotMesh — 부위 칠하기 · 관절 경계 = <모델>.parts.json)
##   기본 몸의 그 슬롯과 바꿔 끼운다. 그래서 이 탭이 고치는 것 = 옷 모델 · parts.json · 슬롯 표 셋뿐이고, 미리보기는 게임과 같은 3D 도트 화면이다.
##
##   왼쪽: 1 복장(outfit.json) · 옷 모델(.glb) · 기본 몸 → 불러오기(에디터면 지난 값으로 탭을 열 때 저절로)
##         2 옷 모델 새로 만들기 — AI 원본을 기본 뼈대에 붙인다(Blender 를 뒤에서 돌림)
##         3 부위 경계(관절) — 목 · 손목 · 허리 … 의 슬롯 경계를 곧은 평면으로(옷 모델 · 기본 몸에 같이)
##         4 직접 고치기(고급) — 직선 · 사각형 · 붓
##         5 슬롯 — 파트마다 상의 · 하의 · 기본 몸
##         바닥: [저장] = outfit.json(id · model · slots — 다른 키는 그대로 둔다). parts.json 은 고칠 때마다 바로 저장(게임이 디스크에서 읽는다)
##   가운데: 3D 부위 칠하기(T-포즈) — 면마다 실제로 잘리는 부위 색 · 노란 판 = 고른 관절 경계
##   오른쪽: 3D 미리보기(DRDotView3D + DRCharacter3D — 게임과 같은 처리 · 초당 12번) — 차림 4가지 · 동작 · 이음매 확대 · 돌려 보기 · 뚜껑 · 무기.
##           슬롯 메시는 이 페이지가 메모리의 칠하기 · 슬롯 표로 직접 잘라 끼운다 — 저장 전 슬롯 · 뚜껑 끄기도 바로 보이게.
## 되돌리기는 예전 탭처럼 이 페이지의 스택(Ctrl+Z · 단추) — 에디터 안팎이 같다(검사는 함수를 바로 부른다).

const RAW_FILTER := "*.glb, *.gltf ; AI 원본(Tripo 등)"
const MODEL_FILTER := "*.glb, *.gltf ; 뼈대에 붙인 옷 모델"
const BODY_FILTER := "*.glb, *.gltf ; 기본 몸(사람 몸)"
const BLENDER_DEFAULT := "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
const BLENDER_SETTING := "dot_rigger/blender_path"
const META_SECTION := "dot_rigger_outfit"
const BIND_SCRIPT := "res://pipeline/blender/bind_to_skeleton.py"
## 웨이트 원본 몸 기본 = 사람 몸(10-15 사용자: "UAL 마네킹은 레거시"). 사람 몸이면 붙이기가 그 뼈대(팔꿈치 · 손목 · 비틀림 뼈)를 그대로 써서
## 옷 관절이 맨몸과 같아진다(bind_to_skeleton.py skeleton_from_base)
const WEIGHT_BASE_DEFAULT := "res://source3d/characters/human_base/human_base.glb"
## 예전 기본값 — 기억해 둔 값이 이것이면 새 기본값으로 바꿔 읽는다
const WEIGHT_BASE_LEGACY := "res://source3d/UAL1_humanoid.glb"
const OUTFITS_DIR := "res://outfits"
const MODELS_DIR := "res://source3d/characters"
## 미리보기 동작 = 게임이 쓰는 3D 동작 묶음(동작 표의 library_path 와 같은 파일)
const MOTIONS_LIB := "res://game/motions/rifleman_anims.res"
## 미리보기 무기 = 이 유닛 프리팹의 소켓 장비(② 장비 탭에서 맞춘 것 — 오른손 소켓 → 무기 → 왼손 표지)
const WEAPON_UNIT := "res://game/units/soldier_base.tscn"
## 기본 동작 — 앞손(왼손)이 총몸을 받쳐 손목이 크게 꺾이고 비틀리는 자세라 소매 끝 이음매가 가장 잘 드러난다(10-16 사용자 스크린샷 자세)
const DEFAULT_MOTION := "Crouch_Idle+Rifle_Aiming_Idle"
const PREVIEW_HEIGHT := 1.75
const STEP_HZ := 12.0
const JOINT_IDLE_SEC := 0.8
const RESPLIT_DELAY := 0.1
const SLOT_KEYS := ["top", "bottom", ""]
const SLOT_NAMES := {"top": "상의", "bottom": "하의", "": "기본 몸"}
const ALL_PARTS := ["Torso", "Hips", "Head", "L_UpperArm", "R_UpperArm", "L_Forearm", "R_Forearm", "L_Hand", "R_Hand",
	"L_Thigh", "R_Thigh", "L_Calf", "R_Calf", "L_Foot", "R_Foot"]
const ERASE := ""                  # 칠할 부위 "" = 지우개(웨이트대로)
const CUTS_KEY := "__cuts__"        # 되돌리기 기록에서 "자르기 목록 전체(바뀌기 전)"
const PART_COLORS := {
	"Hips": Color(0.86, 0.74, 0.2), "Torso": Color(0.92, 0.33, 0.28), "Head": Color(0.98, 0.84, 0.66),
	"L_UpperArm": Color(0.25, 0.55, 0.98), "L_Forearm": Color(0.2, 0.82, 0.86), "L_Hand": Color(0.65, 0.92, 1.0),
	"R_UpperArm": Color(0.58, 0.32, 0.92), "R_Forearm": Color(0.86, 0.38, 0.9), "R_Hand": Color(0.97, 0.72, 0.97),
	"L_Thigh": Color(0.24, 0.72, 0.32), "L_Calf": Color(0.55, 0.86, 0.28), "L_Foot": Color(0.78, 0.96, 0.55),
	"R_Thigh": Color(0.96, 0.52, 0.16), "R_Calf": Color(0.98, 0.7, 0.34), "R_Foot": Color(1.0, 0.86, 0.56),
}
## 미리보기 차림 [키, 이름, 설명] — 게임 시험장 F4 와 같은 네 가지
const LOOKS := [["full", "전체", "상의 · 하의 모두 이 옷"], ["top", "상의만", "상의 슬롯만 이 옷, 하의는 기본 몸(내복)"],
	["bottom", "하의만", "하의 슬롯만 이 옷, 상의는 기본 몸(내복)"], ["naked", "내복", "옷 없이 기본 몸 — 이음매 비교용"]]
## 이음매 보기 [키, 이름, 확대(1 m = px)] — 키 = 따라갈 자리(_focus_point)
const FOCUS := [["body", "전신", 0.0], ["neck", "목", 900.0], ["LeftHand", "왼 손목", 1100.0], ["RightHand", "오른 손목", 1100.0],
	["waist", "허리", 650.0]]
## 돌려 보기 [이름, 도] — 모델은 +Z(화면 앞)를 본다. 3/4 = 게임(좌우를 보되 카메라 쪽으로 35°)
const TURNS := [["앞", 0.0], ["3/4", 55.0], ["옆", 90.0], ["뒤", 180.0], ["반대 옆", -90.0], ["반대 3/4", -55.0]]
## 관절 → 이음매 보기(관절을 고르면 미리보기도 그 이음매로)
const JOINT_FOCUS := {"Head": "neck", "L_Hand": "LeftHand", "R_Hand": "RightHand", "Torso": "waist"}
const PV_BG_DEFAULT := Color(0.42, 0.47, 0.42)
const PAINT_BG_DEFAULT := Color(0.2, 0.21, 0.24)


## 칠할 대상 하나(옷 모델 · 기본 몸) — 모델 인스턴스 · 칠하기 · 표시 데이터. 예전 탭은 DRBaker(2D 굽기 도구)를 세웠지만 3D 는 메시 · 뼈대만 있으면 된다
class PaintTarget:
	extends RefCounted
	var kind := ""                     # "outfit" · "base"
	var glb := ""
	var inst: Node = null              # glb 인스턴스(트리 밖) — release() 가 free
	var skel: Skeleton3D = null
	var mi: MeshInstance3D = null      # 스킨드 원본 메시(바인드 = T-포즈)
	var split: DRMeshSplitter.SplitResult   # bone_part · part_bones 만 — 관절 목록(DRMeshCutter.joint_list)용
	var ov: DRPartOverrides
	var pos := PackedVector3Array()    # 정점(바인드 = T-포즈, 서피스 이어 붙임)
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var auto := PackedStringArray()    # 웨이트대로의 파트(다리 평면 포함 — DRSlotMesh 와 같은 규칙)
	var keys: Array = []               # 정점 → DRPartOverrides 키
	var tri := PackedInt32Array()      # 삼각형 → 정점 번호 3개
	var tri_a := PackedVector3Array()  # 고르기(광선)용
	var tri_e1 := PackedVector3Array()
	var tri_e2 := PackedVector3Array()
	var tex: Texture2D

	## 정점마다 지금 부위(칠한 것 우선, 자르기까지)
	func part_of(i: int) -> String:
		var p := String(ov.map.get(keys[i], "")) if ov != null else ""
		if p == "":
			p = auto[i]
		if ov != null and not ov.cuts.is_empty():
			p = ov.cut_part(pos[i], p)
		return p

	func painted(i: int) -> bool:
		return ov != null and ov.map.has(keys[i])

	func release() -> void:
		if inst != null and is_instance_valid(inst):
			inst.free()
		inst = null
		skel = null
		mi = null


## 칠하기 화면 위에 그리는 직선 · 사각형(직선 자르기 · 사각형 도구)
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


var _profile: DRPartProfile = DRPartProfile.humanoid()
var _loaded := false
var _busy := false
var _filling := false
var _active := true
var _auto_loaded := false
var _json_path := ""                    # 고치는 outfit.json(새 복장이면 아직 없음)
var _model_path := ""                   # 옷 모델 glb
var _body_path := DRCharacter3D.BODY_DEFAULT
var _slots: Dictionary = {}             # 파트 -> "top" · "bottom" · ""(기본 몸)
var _dirty_doc := false                 # 슬롯 표 · 옷 모델을 바꾸고 아직 outfit.json 에 저장 안 함
var _last_msg := ""

var _t_outfit: PaintTarget
var _t_base: PaintTarget
var _target: PaintTarget                # 칠하기 화면에 띄운 대상
var _target_kind := "both"              # 칠할 대상 단추: both · outfit · base
var _paint_both := true                 # 옷 모델에 칠하는 것을 기본 몸에도 같이

var _tool := "line"                     # line(직선 자르기) · rect(사각형) · brush(붓)
var _paint_part := "Torso"
var _painting := false
var _stroke: Dictionary = {}            # 이번 붓질: 대상(PaintTarget) -> {바뀐 키: 바뀌기 전 파트("" = 웨이트대로)}
var _undo: Array = []                   # 끝난 붓질 · 선 · 관절(_stroke 와 같은 모양) — 되돌리기
var _last_pick_px := Vector2(-999, -999)
var _line_on := false

# 1
var _outfit_ob: OptionButton
var _id_edit: LineEdit
var _model_ob: OptionButton
var _body_edit: LineEdit
var _load_btn: Button
var _load_status: Label
# 2 붙이기
var _raw_edit: LineEdit
var _wbase_edit: LineEdit
var _smooth_spin: SpinBox
var _hand_cb: CheckBox
var _thumb_cb: CheckBox
var _partfix_cb: CheckBox
var _limbfit_cb: CheckBox
var _blender_edit: LineEdit
var _bind_btn: Button
var _bind_status: Label
var _bind_thread: Thread
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
var _undo_btn: Button
var _clear_btn: Button
var _paint_status: Label
var _disp_dirty := false
# 4 칠하기
var _tgt_btns: Dictionary = {}          # "both" · "outfit" · "base" -> Button
var _tool_btns: Dictionary = {}         # "line" · "rect" · "brush" -> Button
var _part_btns: Dictionary = {}         # 파트(지우개 "") -> Button
var _brush_spin: SpinBox
var _front_only: CheckBox
# 5 슬롯
var _slot_opts: Dictionary = {}         # 파트 -> OptionButton
var _slot_warn: Label
# 바닥
var _save_btn: Button
var _status: Label
# 칠하기 화면(T-포즈)
var _view_mode: OptionButton
var _vp3: SubViewport
var _pv3: TextureRect
var _env3: Environment
var _line_ov: LineOverlay
var _hud3: Label
var _cam3: Camera3D
var _pm_mi: MeshInstance3D
var _brush_mi: MeshInstance3D
var _joint_mi: MeshInstance3D
var _mat_part: StandardMaterial3D
var _mat_tex: StandardMaterial3D
var _mat_mix: StandardMaterial3D
var _cam_target := Vector3(0, 0.9, 0)
var _cam_yaw := 0.0
var _cam_pitch := 0.0
var _cam_dist := 3.0
var _drag := ""                         # "orbit" · "pan"
var _drag_from := Vector2.ZERO
# 3D 미리보기
var _pv: TextureRect
var _pv_vp: SubViewport
var _pv_bg: ColorRect
var _ground: Node2D
var _dots: DRDotView3D
var _pv_ch: DRCharacter3D = null
var _look_btns: Dictionary = {}
var _focus_btns: Dictionary = {}
var _motion_ob: OptionButton
var _play_btn: Button
var _time_sl: HSlider
var _dot_ob: OptionButton
var _zoom_sl: HSlider
var _caps_cb: CheckBox
var _weapon_cb: CheckBox
var _weapon_socks: Array[Node] = []     # 미리보기 캐릭터에 꽂은 기본형 군인의 소켓(무기 끄면 뺀다)
var _pv_info: Label
var _look := "full"
var _focus := "body"
var _turn := 55.0
var _playing := true
var _acc := 0.0
var _cur_motion := ""
var _pv_drag := false
var _pv_drag_from := Vector2.ZERO
var _pv_resplit := false
var _pv_timer := 0.0
var _body_split: Dictionary = {}        # {meshes, skin, res} — 기본 몸을 기본 슬롯 표로 자른 것
var _outfit_split: Dictionary = {}      # 옷 모델을 지금 슬롯 표로 자른 것
var _body_key := ""
var _outfit_key := ""


func _init() -> void:
	page_title = "복장 (3D)"
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


## 탭이 처음 보이면(에디터) 지난 값으로 바로 불러온다(불러오기를 또 누르지 않게). 에디터 밖(검사)에서는 부른 쪽이 load_outfit 을 직접 부른다
func _on_shown() -> void:
	if not Engine.is_editor_hint() or not is_visible_in_tree() or _loaded or _busy or _auto_loaded:
		return
	_auto_loaded = true
	if _picked_model() != "" or _picked_json_existing() != "":
		_on_load()


func set_page_active(on: bool) -> void:
	super(on)
	_active = on
	if _dots != null:
		_dots.visible = on


## 탭 창 위 미리보기 배경(자홍이면 틈 · 비침이 잘 보인다) — 칠하기 화면 · 미리보기 둘 다
func set_preview_bg(c: Color) -> void:
	if _pv_bg != null:
		_pv_bg.color = c if c.a > 0.0 else PV_BG_DEFAULT
	if _env3 != null:
		_env3.background_color = c if c.a > 0.0 else PAINT_BG_DEFAULT


# ---------------------------------------------------------------- 지난 값 기억(에디터)

func _restore_fields() -> void:
	if not Engine.is_editor_hint():
		return
	var es := EditorInterface.get_editor_settings()
	# 기본값을 꼭 준다 — null 을 주면 값이 없을 때 에디터가 오류를 낸다(02 U18)
	var js := String(es.get_project_metadata(META_SECTION, "json", ""))
	var model := String(es.get_project_metadata(META_SECTION, "model", ""))
	var body := String(es.get_project_metadata(META_SECTION, "body", ""))
	var raw := String(es.get_project_metadata(META_SECTION, "raw", ""))
	var wbase := String(es.get_project_metadata(META_SECTION, "wbase", ""))
	if wbase == WEIGHT_BASE_LEGACY:
		wbase = WEIGHT_BASE_DEFAULT                 # 예전 기본값(UAL 마네킹) 그대로였으면 사람 몸으로
	if body != "" and ResourceLoader.exists(body):
		_body_edit.text = body
	if raw != "":
		_raw_edit.text = raw
	if wbase != "":
		_wbase_edit.text = wbase
	if js != "":
		_scan_outfits(js)
		_fill_from_doc(js)
	if model != "":
		_scan_models(model)


func _remember_fields() -> void:
	if not Engine.is_editor_hint():
		return
	var es := EditorInterface.get_editor_settings()
	es.set_project_metadata(META_SECTION, "json", _json_path)
	es.set_project_metadata(META_SECTION, "model", _model_path)
	es.set_project_metadata(META_SECTION, "body", _body_edit.text.strip_edges())
	es.set_project_metadata(META_SECTION, "raw", _raw_edit.text)
	es.set_project_metadata(META_SECTION, "wbase", _wbase_edit.text)


# ---------------------------------------------------------------- UI 구성

func _build_ui() -> void:
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(split)
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
	_build_section_bind(col)
	_build_section_joints(col)
	_build_section_paint(col)
	_build_section_slots(col)
	_build_footer(left)

	var right := HSplitContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_build_paint_view(right)
	_build_preview(right)


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


func _hint(parent: Control, text: String, min_w: float = 330.0) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(min_w, 0)   # 줄바꿈 라벨은 최소 너비가 없으면 창이 세로로 폭주한다(02 U13)
	l.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	parent.add_child(l)
	return l


func _label(parent: Control, text: String, min_w: float = 0.0, tip: String = "") -> Label:
	var l := Label.new()
	l.text = text
	if min_w > 0.0:
		l.custom_minimum_size = Vector2(min_w, 0)
	if tip != "":
		_tip(l, tip)
	parent.add_child(l)
	return l


func _path_row(parent: Control, label: String, tip: String, browse: Callable) -> LineEdit:
	var row := HBoxContainer.new()
	_label(row, label, 100.0, tip)
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


## 한 줄짜리 토글 단추 묶음(하나만 눌림, 줄을 꽉 채움) — items = [[키, 글, 설명], …]
func _toggle_row(parent: Control, label: String, items: Array, on_pick: Callable) -> Dictionary:
	var row := HBoxContainer.new()
	_label(row, label, 70.0)
	var out := _toggle_buttons(row, items, on_pick, true)
	parent.add_child(row)
	return out


## 토글 단추들(하나만 눌림)을 parent 에 바로 넣는다 — 접히는 줄(HFlowContainer)에 그대로 넣어야 단추마다 한 줄씩 쌓이지 않는다
func _toggle_buttons(parent: Container, items: Array, on_pick: Callable, expand: bool = false) -> Dictionary:
	var group := ButtonGroup.new()
	var out := {}
	for it in items:
		var b := Button.new()
		b.text = String(it[1])
		b.toggle_mode = true
		b.button_group = group
		if expand:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if (it as Array).size() > 2:
			_tip(b, String(it[2]))
		var key: String = it[0]
		b.pressed.connect(func(): on_pick.call(key))
		parent.add_child(b)
		out[key] = b
	return out


func _build_section_source(col: Control) -> void:
	var s := _section(col, "1. 복장 · 옷 모델")
	_hint(s, "복장(outfit.json) 하나 = 옷 모델(.glb) 하나 + 슬롯 표. 게임은 이 파일을 읽어 옷 모델을 슬롯 메시로 나눠 기본 몸에 입힌다(굽기 없음). 에디터에서 한 번 불러오면 다음에 탭을 열 때 저절로 불러온다.")
	var row := HBoxContainer.new()
	_label(row, "복장", 100.0, "res://outfits/<복장 이름>/outfit.json. `+ 새 복장` 이면 아래 이름으로 새로 만든다([저장] 때 파일이 생긴다)")
	_outfit_ob = OptionButton.new()
	_outfit_ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_outfit_ob.clip_text = true
	_outfit_ob.fit_to_longest_item = false
	_outfit_ob.item_selected.connect(func(i): _on_outfit_picked(i))
	row.add_child(_outfit_ob)
	var rb := Button.new()
	rb.text = "↻"
	rb.tooltip_text = "복장 · 옷 모델 목록을 다시 찾는다"
	rb.pressed.connect(_on_rescan)
	row.add_child(rb)
	s.add_child(row)
	var irow := HBoxContainer.new()
	_label(irow, "복장 이름", 100.0, "결과 폴더 이름(res://outfits/<복장 이름>/outfit.json). 2번 붙이기의 결과 이름으로도 쓴다.")
	_id_edit = LineEdit.new()
	_id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_id_edit.placeholder_text = "예: m40_jacket"
	irow.add_child(_id_edit)
	s.add_child(irow)
	var mrow := HBoxContainer.new()
	_label(mrow, "옷 모델", 100.0, "기본 몸과 같은 뼈대에 붙인 옷 입은 모델(.glb, source3d/characters 아래). 없으면 2번에서 AI 원본을 붙여 만든다.")
	_model_ob = OptionButton.new()
	_model_ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_ob.clip_text = true
	_model_ob.fit_to_longest_item = false
	_model_ob.item_selected.connect(func(_i):
		if not _filling and _loaded and _picked_model() != _model_path:
			_say("옷 모델을 바꿨습니다 — [불러오기] 를 눌러야 이 모델로 칠하기 · 미리보기가 바뀐다"))
	mrow.add_child(_model_ob)
	var mb := Button.new()
	mb.text = "…"
	mb.pressed.connect(_on_browse_model)
	mrow.add_child(mb)
	s.add_child(mrow)
	_body_edit = _path_row(s, "기본 몸", "옷을 안 입힌 슬롯 · 머리 · 손에 보이는 사람 몸(게임 유닛의 몸과 같게). 관절 경계는 이 몸 기준으로 옷 모델에도 같이 들어간다.",
		_on_browse_body)
	_body_edit.text = DRCharacter3D.BODY_DEFAULT
	_load_btn = Button.new()
	_load_btn.text = "불러오기"
	_load_btn.pressed.connect(_on_load)
	s.add_child(_load_btn)
	_load_status = _hint(s, "")
	_scan_models("")
	_scan_outfits("")
	_fill_from_doc(_picked_json_existing())


func _build_section_bind(col: Control) -> void:
	var s := _section(col, "2. 옷 모델 새로 만들기 (AI 원본 → 뼈대에 붙이기)", true)
	_hint(s, "Tripo 등으로 뽑은 옷 입은 사람(.glb, 통짜)을 기본 뼈대에 붙인다 — 방향 · 키 · 웨이트 · 관절 경계. Blender 를 뒤에서 돌리며 수십 초 걸린다. 결과 res://source3d/characters/<복장 이름>/<복장 이름>.glb 가 1번 옷 모델로 들어가 바로 불러온다.")
	_raw_edit = _path_row(s, "AI 원본", "AI 가 뽑은 .glb — 보통 pipeline/comfy/ 아래(이 폴더는 Godot 가 무시하므로 디스크 경로로 고른다).", _on_browse_raw)
	_wbase_edit = _path_row(s, "웨이트 원본 몸", "웨이트(어느 살이 어느 뼈를 따라가나)와 뼈대를 가져올 몸 — 기본은 사람 몸(human_base). 옷 관절이 맨몸과 같아진다.",
		_on_browse_wbase)
	_wbase_edit.text = WEIGHT_BASE_DEFAULT
	var row := HBoxContainer.new()
	_label(row, "웨이트 부드럽게", 100.0, "관절 주변 웨이트를 이웃 정점 평균으로 몇 번 번지게 할지(0 = 마네킹처럼 칼같이). 클수록 관절이 부드럽게 휜다. 사람 몸 뼈대로 붙이는 옷은 팔(윗팔 가운데부터 손까지)은 번지게 하지 않는다 — 맨몸 팔 웨이트를 그대로 옮겨야 소매 끝이 맨몸 손목과 같이 비틀린다(10-16).")
	_smooth_spin = SpinBox.new()
	_smooth_spin.min_value = 0
	_smooth_spin.max_value = 40
	_smooth_spin.step = 1
	_smooth_spin.value = 12
	row.add_child(_smooth_spin)
	s.add_child(row)
	_hand_cb = _check(s, "손가락 맞춤", true, "AI 손이 기본 손과 크기 · 간격이 달라 손가락 웨이트가 한 칸씩 밀리는 것을 막는다.")
	_thumb_cb = _check(s, "엄지 맞춤", true, "AI 엄지를 엄지뼈 방향으로 돌려 놓고 웨이트를 옮긴다 — 주먹 쥘 때 엄지가 튀어나오지 않게.")
	_partfix_cb = _check(s, "관절 경계 정리", true, "고관절 · 무릎에 평면을 세워 웨이트 조각 경계를 관절에 맞춘다(2D 때 것). 사람 몸 뼈대로 붙이는 옷은 팔에는 안 한다 — 비틀림 뼈를 모르는 채 손목 앞 정점을 아래팔 1.0 으로 덮어 3D 에서 가시가 생긴다(10-16). 슬롯 경계는 3번 관절 경계가 정한다.")
	_limbfit_cb = _check(s, "팔 · 소매 끝 맞춤 (옷)", true, "옷 팔 살을 기본 몸 팔 단면 중심에 옮기고(팔 맞춤) 소매 끝을 기본 몸 손목 + 0.6 cm 로 맞춘 뒤(소매 끝 맞춤) 웨이트를 옮긴다. 팔 웨이트는 번지게 하지 않는다(10-16 — 군복 손목이 꺾여 보이던 것: 소매가 뼈 축에서 2 ~ 3 cm 어긋나 손이 큰 검은 뚜껑 가장자리에서 나왔다). 웨이트 원본 몸이 사람 몸(human_base)일 때만 쓰인다.")
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
	_hint(s, "옷과 몸이 이어지는 자리(목 · 손목 · 허리)의 슬롯 경계를 곧게 정한다. 관절을 고르고 [곧게]를 켠 뒤 위치 · 기울기를 끌면 가운데 노란 판이 경계 — 손을 떼면 저장되고 오른쪽 미리보기(그 이음매 확대)가 다시 잘린다. 옷 모델 · 기본 몸에 똑같이 들어간다(기본 몸 경계는 모든 옷이 같이 쓴다).")
	var row := HBoxContainer.new()
	_label(row, "관절", 70.0)
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
	_label(row, label, 70.0, tip)
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


func _build_section_paint(col: Control) -> void:
	var s := _section(col, "4. 직접 고치기 (고급)", true)
	_hint(s, "관절 경계로 안 되는 곳만 — 예: 상의 자락을 Torso 로. 가운데 3D 의 색 = 실제로 잘리는 조각. 직선 = 선이 지나는 두 부위의 경계만, 사각형 = 화면에 보이는 부위만, 붓 = 보이는 면만(기본) — 뒤에 숨은 다른 부위는 안 건드린다.")
	_tgt_btns = _toggle_row(s, "칠할 대상", [
		["both", "둘 다 (기본)", "옷 모델에 칠하는 붓질 · 선이 기본 몸의 같은 자리에도 같이 들어간다. 슬롯 경계(목 · 손목 · 허리)는 옷 조각과 기본 몸 조각이 같은 자리에서 맞물려야 해서 둘을 같이 자른다"],
		["outfit", "옷 모델만", "옷 입은 모델의 조각 경계만 — 예: 상의 자락을 Torso 로"],
		["base", "기본 몸만", "가운데 3D 에 기본 몸을 띄워 그 조각 경계만 고친다(모든 옷이 같이 쓰는 몸)"]],
		func(k): _switch_target(k))
	(_tgt_btns["both"] as Button).button_pressed = true
	_tool_btns = _toggle_row(s, "도구", [
		["line", "직선 (L)", "3D 위에 선을 긋는다 — 선이 지나는 부위를 그 선 그대로 곧게 잘라, 고른 부위 쪽을 고른 부위로(앞뒤 함께). Shift = 수평 · 수직 · 45°"],
		["rect", "사각형 (R)", "3D 위에 사각형을 끈다 — 사각형 안(앞뒤 함께)이 고른 부위로, 가장자리가 사각형 그대로 곧다"],
		["brush", "붓 (B)", "왼쪽 버튼으로 문지른다 — 붓 범위 안의 정점이 고른 부위로. 정점 단위라 경계가 들쭉날쭉 — 곧은 경계는 직선 · 사각형으로"]],
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
	_label(row, "붓 크기(cm)")
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
	_hint(s, "파트마다 상의 · 하의 · 기본 몸. 게임에서 상의만 / 하의만 따로 입힐 때 이 묶음을 쓴다(시험장 F4). 기본 몸 = 그 파트는 늘 맨몸(머리 · 손). 바꾸면 미리보기에 바로 — 게임에는 [저장] 뒤.")
	var grid := GridContainer.new()
	grid.columns = 4
	s.add_child(grid)
	for pn in ALL_PARTS:
		_label(grid, String(pn))
		var o := OptionButton.new()
		for k in SLOT_KEYS:
			o.add_item(String(SLOT_NAMES[k]))
		o.select(SLOT_KEYS.find(String(DRSlotMesh.DEFAULT_SLOTS.get(pn, ""))))
		var part_name: String = pn
		o.item_selected.connect(func(i): _on_slot_changed(part_name, i))
		grid.add_child(o)
		_slot_opts[pn] = o
	_slot_warn = _hint(s, "")
	_slot_warn.add_theme_color_override("font_color", Color(0.95, 0.75, 0.35))


func _build_footer(left: Control) -> void:
	var foot := VBoxContainer.new()
	foot.add_theme_constant_override("separation", 4)
	left.add_child(foot)
	foot.add_child(HSeparator.new())
	_save_btn = Button.new()
	_save_btn.text = "저장"
	_save_btn.disabled = true
	_tip(_save_btn, "outfit.json(옷 모델 · 슬롯 표)을 저장한다 — 게임 · 유닛이 이 파일을 읽는다. 다른 키(2D 시험장용 sets 등)는 그대로 둔다. 부위 칠하기 · 관절(parts.json)은 고칠 때마다 바로 저장된다.")
	_save_btn.pressed.connect(func(): save_outfit())
	foot.add_child(_save_btn)
	_status = _hint(foot, "먼저 1번에서 `불러오기`.")


## 가운데 — T-포즈 부위 칠하기 화면(예전 탭의 3D 칠하기 그대로)
func _build_paint_view(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(300, 0)
	parent.add_child(box)
	var bar := HFlowContainer.new()
	box.add_child(bar)
	_label(bar, "부위 칠하기 (T-포즈)")
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
	_vp3.size = Vector2i(400, 600)
	_vp3.own_world_3d = true
	_vp3.transparent_bg = false
	_vp3.msaa_3d = Viewport.MSAA_4X
	_vp3.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp3)
	_env3 = Environment.new()
	_env3.background_mode = Environment.BG_COLOR
	_env3.background_color = PAINT_BG_DEFAULT
	_env3.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env3.ambient_light_color = Color(1, 1, 1)
	_env3.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.environment = _env3
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
	_hint(box, "노란 판 = 고른 관절 경계 · 왼쪽 버튼 = (4번 도구) 선 · 사각형 · 붓 · 오른쪽 끌기 = 돌리기 · 가운데 끌기 = 옮기기 · 휠 = 확대 · F = 맞춤 · L 직선 · R 사각형 · B 붓 · Ctrl+Z 되돌리기", 280.0)


## 오른쪽 — 게임과 같은 3D 도트 화면에 기본 몸 + 이 옷(unit_page 미리보기와 같은 짜임)
func _build_preview(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_stretch_ratio = 1.25                 # 칠하기 화면보다 조금 넓게(이음매를 크게 본다)
	box.custom_minimum_size = Vector2(320, 0)
	parent.add_child(box)
	var bar := HFlowContainer.new()
	box.add_child(bar)
	_label(bar, "미리보기 차림")
	_look_btns = _toggle_buttons(bar, LOOKS, func(k): set_look(k))
	(_look_btns["full"] as Button).button_pressed = true
	var bar2 := HFlowContainer.new()
	box.add_child(bar2)
	_label(bar2, "동작")
	_motion_ob = OptionButton.new()
	_motion_ob.custom_minimum_size = Vector2(170, 0)
	_motion_ob.clip_text = true
	_motion_ob.fit_to_longest_item = false
	_motion_ob.tooltip_text = "3D 동작 묶음(game/motions/rifleman_anims.res)의 동작 — 게임과 같은 처리(손 맞춤 · 비틀림 뼈 · 상하체 합성)"
	_motion_ob.item_selected.connect(func(i): play_motion(_motion_ob.get_item_text(i)))
	bar2.add_child(_motion_ob)
	_play_btn = Button.new()
	_play_btn.text = "⏸ 멈춤"
	_play_btn.tooltip_text = "재생 / 멈춤 — 멈추면 옆 막대로 그 동작의 한 순간을 고른다(같은 순간을 차림만 바꿔 비교)"
	_play_btn.pressed.connect(func(): _set_playing(not _playing))
	bar2.add_child(_play_btn)
	_time_sl = HSlider.new()
	_time_sl.min_value = 0.0
	_time_sl.max_value = 1.0
	_time_sl.step = 0.005
	_time_sl.custom_minimum_size = Vector2(110, 0)
	_time_sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_time_sl.tooltip_text = "동작 시각(0 ~ 100 %) — 움직이면 멈추고 그 순간을 보인다"
	_time_sl.value_changed.connect(func(v):
		if _playing:
			_set_playing(false)
		_seek(v))
	bar2.add_child(_time_sl)
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(panel)
	_pv = TextureRect.new()
	_pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pv.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pv.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pv.mouse_filter = Control.MOUSE_FILTER_STOP
	_pv.tooltip_text = "휠 = 확대 · 끌기 = 돌려 보기"
	_pv.gui_input.connect(_on_pv_input)
	_pv.resized.connect(func():
		if _pv_vp != null:
			_pv_vp.size = Vector2i(maxi(64, int(_pv.size.x)), maxi(64, int(_pv.size.y))))
	panel.add_child(_pv)
	_pv_vp = SubViewport.new()
	_pv_vp.size = Vector2i(400, 600)
	_pv_vp.transparent_bg = false
	_pv_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_pv_vp)
	_pv_bg = ColorRect.new()
	_pv_bg.color = PV_BG_DEFAULT
	_pv_bg.size = Vector2(8192, 8192)
	_pv_vp.add_child(_pv_bg)
	_ground = Node2D.new()
	_ground.draw.connect(_draw_ground)
	_pv_vp.add_child(_ground)
	_dots = DRDotView3D.new()
	DRDotStyle.load_default().apply_to(_dots)    # 게임 · ① 유닛 탭과 같은 도트 느낌(외곽선 · 픽셀 퍼펙트 — game/dot_style.tres)
	_dots.px_per_m = 250.0
	_pv_vp.add_child(_dots)
	_pv.texture = _pv_vp.get_texture()
	var bar3 := HFlowContainer.new()
	box.add_child(bar3)
	_label(bar3, "이음매")
	_focus_btns = _toggle_buttons(bar3, FOCUS.map(func(f): return [f[0], f[1], "그 자리를 가운데로 따라가며 확대(도트 1 px)" if f[0] != "body" else "몸 전체"]),
		func(k): set_focus(k))
	(_focus_btns["body"] as Button).button_pressed = true
	var bar4 := HFlowContainer.new()
	box.add_child(bar4)
	_label(bar4, "보기")
	for t in TURNS:
		var b := Button.new()
		b.text = String(t[0])
		var deg: float = t[1]
		b.tooltip_text = "캐릭터를 %+.0f° 돌린다(3/4 = 게임에서 보는 각)" % deg
		b.pressed.connect(func(): set_turn(deg))
		bar4.add_child(b)
	var bar5 := HFlowContainer.new()
	box.add_child(bar5)
	_label(bar5, "도트")
	_dot_ob = OptionButton.new()
	for i in range(1, 5):
		_dot_ob.add_item("%d px" % i, i)
	_dot_ob.select(1)
	_dot_ob.tooltip_text = "도트 하나 = 화면 몇 픽셀(1 = 도트화 끔 — 이음매 보기에 좋음). 게임 화면과 같은 처리"
	_dot_ob.item_selected.connect(func(i): _dots.dot_px = _dot_ob.get_item_id(i))
	bar5.add_child(_dot_ob)
	_label(bar5, "확대")
	_zoom_sl = HSlider.new()
	_zoom_sl.min_value = 60.0
	_zoom_sl.max_value = 2500.0
	_zoom_sl.step = 10.0
	_zoom_sl.value = 250.0
	_zoom_sl.custom_minimum_size = Vector2(100, 0)
	_zoom_sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_zoom_sl.tooltip_text = "확대(1 m = 몇 px)"
	_zoom_sl.value_changed.connect(func(v):
		_dots.px_per_m = v
		_ground.queue_redraw())
	bar5.add_child(_zoom_sl)
	_caps_cb = CheckBox.new()
	_caps_cb.text = "뚜껑"
	_caps_cb.button_pressed = true
	_caps_cb.tooltip_text = "슬롯 경계 구멍(목 · 손목 · 허리 단면)을 어두운 뚜껑으로 막는다(게임 = 켬). 끄면 소매 · 깃 속이 비어 배경이 비치는지 볼 수 있다"
	_caps_cb.toggled.connect(func(_on): _resplit_preview())
	bar5.add_child(_caps_cb)
	_weapon_cb = CheckBox.new()
	_weapon_cb.text = "무기"
	_weapon_cb.tooltip_text = "기본형 군인의 장비(② 장비 탭 — 오른손 소켓의 무기 · 왼손 IK)를 든다, 게임과 같게. 손목 이음매를 가리면 끈다"
	_weapon_cb.toggled.connect(func(on): _set_weapon(on))
	bar5.add_child(_weapon_cb)
	_pv_info = _hint(box, "", 300.0)
	_pv_info.add_theme_font_size_override("font_size", 12)


# ---------------------------------------------------------------- 파일 고르기 · 목록

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


func _on_browse_raw() -> void:
	_file_dialog(RAW_FILTER, "AI 원본(.glb) — Dot Rigger", false, func(p):
		_raw_edit.text = String(p)
		if _id_edit.text.strip_edges() == "":
			_id_edit.text = String(p).get_file().get_basename().to_lower()
	, true, ProjectSettings.globalize_path("res://pipeline/comfy"))


func _on_browse_model() -> void:
	_file_dialog(MODEL_FILTER, "옷 모델 — Dot Rigger", false, func(p):
		_scan_models(String(p))
		_on_load())


func _on_browse_body() -> void:
	_file_dialog(BODY_FILTER, "기본 몸 — Dot Rigger", false, func(p): _body_edit.text = String(p))


func _on_browse_wbase() -> void:
	_file_dialog(BODY_FILTER, "웨이트 원본 몸 — Dot Rigger", false, func(p): _wbase_edit.text = String(p))


func _on_browse_blender() -> void:
	_file_dialog("*.exe ; Blender", "blender.exe — Dot Rigger", false, func(p): _blender_edit.text = String(p), true)


func _on_rescan() -> void:
	_scan_outfits(_picked_json_existing())
	_scan_models(_picked_model())


## res://outfits/*/outfit.json 목록(+ 새 복장)을 채우고 want 를 고른다 — want 가 "" 면 첫 복장, 아직 없는 파일이면 `+ 새 복장`.
## 칸(이름 · 옷 모델)은 안 건드린다(사람이 복장을 고를 때만 _on_outfit_picked 가 채운다)
func _scan_outfits(want: String) -> void:
	if _outfit_ob == null:
		return
	_filling = true
	_outfit_ob.clear()
	var paths := PackedStringArray()
	if DirAccess.dir_exists_absolute(OUTFITS_DIR):
		for d in DirAccess.get_directories_at(OUTFITS_DIR):
			var p := OUTFITS_DIR.path_join(String(d)).path_join("outfit.json")
			if FileAccess.file_exists(p):
				paths.append(p)
	if want != "" and FileAccess.file_exists(want) and not paths.has(want):
		paths.append(want)
	var sel := -1
	for p in paths:
		_outfit_ob.add_item(String(p).get_base_dir().get_file())
		_outfit_ob.set_item_metadata(_outfit_ob.item_count - 1, p)
		_outfit_ob.set_item_tooltip(_outfit_ob.item_count - 1, p)
		if p == want:
			sel = _outfit_ob.item_count - 1
	_outfit_ob.add_item("+ 새 복장 (아래에 이름)")
	_outfit_ob.set_item_metadata(_outfit_ob.item_count - 1, "")
	if sel < 0:
		sel = 0 if want == "" and paths.size() > 0 else _outfit_ob.item_count - 1
	_outfit_ob.select(sel)
	if _id_edit != null:
		_id_edit.editable = _picked_json_existing() == ""
	_filling = false


## source3d/characters 아래 glb(기본 몸 빼고). want 를 고른다(목록에 없으면 ⚠ 로 덧붙임)
func _scan_models(want: String) -> void:
	if _model_ob == null:
		return
	_filling = true
	_model_ob.clear()
	var body := _body_edit.text.strip_edges() if _body_edit != null else DRCharacter3D.BODY_DEFAULT
	var paths := PackedStringArray()
	for p in _files_under(MODELS_DIR, ["glb", "gltf"]):
		if p != body:
			paths.append(p)
	var sel := -1
	for p in paths:
		_model_ob.add_item(_short(p))
		_model_ob.set_item_metadata(_model_ob.item_count - 1, p)
		_model_ob.set_item_tooltip(_model_ob.item_count - 1, p)
		if p == want:
			sel = _model_ob.item_count - 1
	if want != "" and sel < 0:
		_model_ob.add_item("⚠ " + _short(want))
		_model_ob.set_item_metadata(_model_ob.item_count - 1, want)
		_model_ob.set_item_tooltip(_model_ob.item_count - 1, want + "\n(source3d/characters 밖이거나 가져오기 전)")
		sel = _model_ob.item_count - 1
	if sel < 0 and _model_ob.item_count > 0:
		sel = 0
	if sel >= 0:
		_model_ob.select(sel)
	_filling = false


## 사람이 복장을 고르면 그 파일의 이름 · 옷 모델을 칸에 채운다. 새 복장이면 이름 칸을 비우고 연다
func _on_outfit_picked(_i: int) -> void:
	if _filling:
		return
	var p := _picked_json_existing()
	_id_edit.editable = p == ""
	if p == "":
		_id_edit.text = ""
		if _id_edit.is_inside_tree():
			_id_edit.grab_focus()
		return
	_fill_from_doc(p)


## 복장 파일의 이름 · 옷 모델을 칸에(파일이 없으면 그대로)
func _fill_from_doc(p: String) -> void:
	if p == "" or not FileAccess.file_exists(p):
		return
	var d := _read_doc(p)
	_id_edit.text = String(d.get("id", p.get_base_dir().get_file()))
	var m := String(d.get("model", ""))
	if m != "":
		_scan_models(m)


func _picked_json_existing() -> String:
	if _outfit_ob == null or _outfit_ob.selected < 0:
		return ""
	var md: Variant = _outfit_ob.get_item_metadata(_outfit_ob.selected)
	return String(md) if md != null else ""


## 고른 복장 파일 — 새 복장이면 이름 칸으로 res://outfits/<이름>/outfit.json(아직 없음)
func _picked_json() -> String:
	var p := _picked_json_existing()
	if p != "":
		return p
	var id := _clean_id(_id_edit.text)
	return OUTFITS_DIR.path_join(id).path_join("outfit.json") if id != "" else ""


func _picked_model() -> String:
	if _model_ob == null or _model_ob.selected < 0:
		return ""
	var md: Variant = _model_ob.get_item_metadata(_model_ob.selected)
	return String(md) if md != null else ""


static func _clean_id(s: String) -> String:
	var out := s.strip_edges()
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", " ", "."]:
		out = out.replace(ch, "_")
	return out


static func _read_doc(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return v if v is Dictionary else {}


static func _short(p: String) -> String:
	var parts := p.trim_prefix("res://").split("/")
	return "/".join(parts.slice(maxi(parts.size() - 2, 0)))


## 폴더 아래(하위 폴더까지) 확장자가 exts 인 파일
static func _files_under(dir: String, exts: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if exts.has(String(f).get_extension().to_lower()):
			out.append(dir.path_join(String(f)))
	for sub in d.get_directories():
		out.append_array(_files_under(dir.path_join(String(sub)), exts))
	return out


static func _blender_path() -> String:
	if Engine.is_editor_hint():
		var es := EditorInterface.get_editor_settings()
		if es.has_setting(BLENDER_SETTING):
			return String(es.get_setting(BLENDER_SETTING))
	return BLENDER_DEFAULT


# ---------------------------------------------------------------- 불러오기

func _on_load() -> void:
	load_outfit(_picked_json(), _picked_model(), _body_edit.text.strip_edges())


func _fail(msg: String) -> bool:
	_load_status.text = "⚠ " + msg
	_say("⚠ " + msg)
	_busy = false
	_loaded = false
	_save_btn.disabled = true
	return false


## 복장을 불러온다 — 옷 모델 · 기본 몸을 칠할 대상으로 세우고(parts.json 그대로) · 슬롯 표 · 관절 목록 · 미리보기 캐릭터.
## json_path 가 없는 파일이면 새 복장(기본 슬롯 표, [저장] 때 생김). model_path 가 "" 면 파일의 model. 돌려주는 값 = 성공
func load_outfit(json_path: String, model_path: String = "", body_path: String = "") -> bool:
	if _busy:
		return false
	_busy = true
	_save_btn.disabled = true
	_load_status.text = "불러오는 중…"
	if is_inside_tree():
		await get_tree().process_frame
	var doc := _read_doc(json_path)
	var mpath := model_path if model_path != "" else String(doc.get("model", ""))
	var bpath := body_path if body_path != "" else DRCharacter3D.BODY_DEFAULT
	if mpath == "":
		return _fail("옷 모델이 없습니다 — 1번 옷 모델을 고르거나 2번에서 붙여 만드세요")
	if mpath == bpath:
		return _fail("옷 모델 칸에 기본 몸(%s)이 들어 있습니다 — 옷 입은 모델을 고르세요. 기본 몸을 칠하려면 불러온 뒤 4번의 [기본 몸만]." % mpath.get_file())
	if not ResourceLoader.exists(mpath):
		return _fail("옷 모델을 열 수 없습니다: %s (가져오기가 끝났는지 확인)" % mpath)
	_teardown()
	_t_base = _make_target("base", bpath)
	if _t_base == null:
		return _fail("기본 몸을 세울 수 없습니다: %s (스킨드 메시 · 뼈대가 있는 glb 인지)" % bpath)
	_t_outfit = _make_target("outfit", mpath)
	if _t_outfit == null:
		return _fail("옷 모델을 세울 수 없습니다: %s (뼈대에 붙인 모델인지 — 2번)" % mpath)
	_json_path = json_path
	_model_path = mpath
	_body_path = bpath
	var id := String(doc.get("id", ""))
	if id == "":
		id = json_path.get_base_dir().get_file() if json_path != "" else _clean_id(mpath.get_file().get_basename().to_lower())
	if _id_edit.text.strip_edges() == "" or FileAccess.file_exists(json_path):
		_id_edit.text = id
	if _json_path == "":
		_json_path = OUTFITS_DIR.path_join(_clean_id(_id_edit.text)).path_join("outfit.json")
	# 슬롯 표: 파일 것(옛 "shoes" = 하의), 없으면 기본 표
	var sl: Dictionary = doc.get("slots", {})
	_slots = {}
	for pn in ALL_PARTS:
		var want := String(sl.get(pn, DRSlotMesh.DEFAULT_SLOTS.get(pn, ""))) if not sl.is_empty() else String(DRSlotMesh.DEFAULT_SLOTS.get(pn, ""))
		if want == "shoes":
			want = "bottom"
		_slots[pn] = want if SLOT_KEYS.has(want) else ""
	_fill_slot_opts()
	_loaded = true
	_fill_joints()
	var nj := _sync_joints_from_base()
	_switch_target("both")
	_build_preview_char()
	_dirty_doc = not FileAccess.file_exists(_json_path)
	var lines := PackedStringArray(["%s — 옷 모델 %s 정점 %d · 기본 몸 %s 정점 %d · 칠한 자리 %d / %d곳 · 관절 경계 %d / %d" % [
		_json_path.get_base_dir().get_file() if FileAccess.file_exists(_json_path) else "새 복장 " + _json_path.get_base_dir().get_file(),
		mpath.get_file(), _t_outfit.pos.size(), bpath.get_file(), _t_base.pos.size(), _t_outfit.ov.size(), _t_base.ov.size(),
		_count_joint_cuts(_t_outfit), _count_joint_cuts(_t_base)]])
	if nj > 0:
		lines.append("기본 몸에 정한 관절 경계를 이 옷에도 적용해 저장했습니다(두 모델의 슬롯 경계가 같은 자리에서 맞물리게).")
	_load_status.text = "\n".join(lines)
	_say("불러옴 — 고치면 미리보기에 바로. 슬롯 표 · 옷 모델은 [저장] 해야 게임에 들어간다." if not _dirty_doc else "새 복장 — [저장] 하면 %s 가 생긴다." % _json_path)
	_update_slot_warn()
	_update_paint_status()
	_remember_fields()
	_scan_outfits(_json_path)
	_scan_models(_model_path)
	_save_btn.disabled = false
	_busy = false
	return true


## 모델 하나로 칠할 대상 — 인스턴스(트리 밖) · 뼈 → 파트 · 칠하기 파일 · 표시 데이터
func _make_target(kind: String, glb: String) -> PaintTarget:
	if glb == "" or not ResourceLoader.exists(glb):
		return null
	var ps := load(glb) as PackedScene
	if ps == null:
		return null
	var inst := ps.instantiate()
	var skel := DRBaker._find_node(inst, "Skeleton3D") as Skeleton3D
	var mi := DRBaker._find_skinned_mesh(inst)
	if skel == null or mi == null:
		inst.free()
		return null
	var t := PaintTarget.new()
	t.kind = kind
	t.glb = glb
	t.inst = inst
	t.skel = skel
	t.mi = mi
	var sr := DRMeshSplitter.SplitResult.new()
	for bi in skel.get_bone_count():
		var part := _profile.part_for_bone(skel.get_bone_name(bi))
		if part == "":
			continue
		sr.bone_part[bi] = part
		var arr: PackedInt32Array = sr.part_bones.get(part, PackedInt32Array())
		arr.append(bi)
		sr.part_bones[part] = arr
	t.split = sr
	t.ov = DRPartOverrides.load_for(glb)
	_fill_target_mesh(t)
	return t


## 대상 모델의 원본 메시(바인드 자세)에서 정점 · 삼각형 · 웨이트대로의 파트를 읽는다(DRSlotMesh.split 2-1 과 같은 규칙)
func _fill_target_mesh(t: PaintTarget) -> void:
	var src := t.mi.mesh as ArrayMesh
	if src == null:
		return
	var binds := DRMeshSplitter._bind_map(t.mi, t.skel)
	var rules := DRMeshSplitter.leg_rules(t.mi, t.skel, t.split.part_bones, t.split.bone_part)
	for si in src.get_surface_count():
		if src.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(verts.size()))
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
			t.auto.append(DRMeshSplitter.leg_part(String(t.split.bone_part.get(skel_b, "")), verts[v], rules))
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
		var mat := t.mi.get_active_material(si)
		if t.tex == null and mat is BaseMaterial3D:
			t.tex = (mat as BaseMaterial3D).albedo_texture


func _teardown() -> void:
	for t in [_t_outfit, _t_base]:
		if t != null:
			(t as PaintTarget).release()
	_t_outfit = null
	_t_base = null
	_target = null
	_loaded = false
	_undo.clear()
	_stroke = {}
	_joint_active = false
	_joint_snap = {}
	_joints = {}
	_body_split = {}
	_outfit_split = {}
	_body_key = ""
	_outfit_key = ""
	if _joint_mi != null:
		_joint_mi.visible = false
	if _pm_mi != null:
		_pm_mi.mesh = null


static func _count_joint_cuts(t: PaintTarget) -> int:
	var n := 0
	if t != null and t.ov != null:
		for c in t.ov.cuts:
			if String((c as Dictionary).get("kind", "")) == "joint":
				n += 1
	return n


# ---------------------------------------------------------------- 관절 경계

## 관절 목록을 채운다(기본 몸 기준). 상자 크기는 두 모델의 자식 부위 정점으로
func _fill_joints() -> void:
	_joints = {}
	var src := _t_base if _t_base != null else _t_outfit
	if src == null:
		return
	for j in DRMeshCutter.joint_list(src.split, src.mi, src.skel):
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


## 관절을 고르면: 슬라이더를 그 경계 값으로, 칠하기 카메라를 관절로, 노란 판 표시 · 미리보기도 그 이음매로(목 · 손목 · 허리)
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
		if JOINT_FOCUS.has(_joint_sel):
			set_focus(String(JOINT_FOCUS[_joint_sel]))
	_update_joint_plane()


## 슬라이더 · 곧게 체크 → 두 모델의 관절 경계를 바꾼다. 움직이는 동안은 칠하기 화면만, 끝나면(_joint_commit) 저장 · 미리보기 다시 자르기
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
	elif commit_now and _joint_on.button_pressed and _joint_cut(_t_base if _t_base != null else _t_outfit, _joint_sel).is_empty() \
			and _joint_off.value == 0.0 and _joint_tilt.value == 0.0:
		_filling = true                     # 처음 켤 때는 그 관절의 시작 위치(목 +6 cm · 손목 −3 cm)
		_joint_off.value = float(DRMeshCutter.JOINT_DEFAULT_OFFSET.get(_joint_sel, 0.0)) * 100.0
		_filling = false
	_set_joint_on_targets(_joint_sel, _joint_on.button_pressed, _joint_off.value * 0.01, _joint_tilt.value)
	_update_joint_plane()
	_disp_dirty = true
	_joint_idle = 0.0 if commit_now else JOINT_IDLE_SEC


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


## 관절 경계 바꾼 것을 되돌리기 한 단계로 · 저장 · 미리보기 다시 자르기
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


## 관절 경계 하나를 바로 정한다(검사 · 다른 도구용) — 되돌리기 한 단계 · 저장 · 미리보기 다시 자르기. 없는 관절이면 false
func set_joint_cut(key: String, on: bool, offset_m: float, tilt_deg: float = 0.0) -> bool:
	if not _loaded or not _joints.has(key):
		return false
	_joint_commit()
	_joint_active = true
	_joint_snap = {}
	for tt in [_t_outfit, _t_base]:
		if tt != null and (tt as PaintTarget).ov != null:
			_joint_snap[tt] = (tt as PaintTarget).ov.cuts.duplicate(true)
	_set_joint_on_targets(key, on, offset_m, tilt_deg)
	_joint_commit()
	_refresh_display()
	if _joint_sel == key:
		_on_joint_selected(false)
	return true


## 기본 몸의 관절 경계를 옷 모델에도(캐릭터 하나에 경계 하나 — 옷 슬롯과 기본 몸 슬롯이 같은 자리에서 맞물려야 한다). 옮긴 관절 수(바뀐 게 없으면 0)
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


## 노란 판 = 고른 관절의 경계(꺼져 있으면 흐리게)
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


# ---------------------------------------------------------------- 칠할 대상 · 도구 · 칠하기 화면

## 칠할 대상 단추: both = 둘 다(화면에는 옷 모델, 같은 붓질 · 선을 기본 몸에도) · outfit = 옷 모델만 · base = 기본 몸만
func _switch_target(kind: String) -> void:
	if not _loaded:
		for k in _tgt_btns.keys():
			(_tgt_btns[k] as Button).set_pressed_no_signal(k == _target_kind)
		return
	if kind != "outfit" and _t_base == null:
		kind = "outfit"
	_target_kind = kind
	_paint_both = kind == "both"
	for k in _tgt_btns.keys():
		(_tgt_btns[k] as Button).set_pressed_no_signal(k == kind)
	_target = _t_base if kind == "base" else _t_outfit
	_show_target()


func _set_tool(kind: String) -> void:
	_tool = kind
	_brush_mi.visible = false
	_update_hud()


## 지금 대상을 칠하기 화면에 띄운다
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


func _part_color(part: String) -> Color:
	return PART_COLORS.get(part, Color(0.35, 0.35, 0.35))


## 면마다 한 색 — 그 면이 실제로 들어가는 조각(세 정점 중 둘 이상이 같은 부위면 그 부위). 붓으로 칠한 면은 조금 밝게.
## 자르기는 게임(DRSlotMesh)과 같은 방식으로 면을 평면에서 쪼개 보여 준다(겹침 없이) — 색 경계 = 실제로 잘리는 곧은 선.
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
## 두 모델은 같은 뼈대 · 같은 T-포즈라 같은 자리의 경계가 같은 곳을 자른다(그래야 슬롯을 서로 바꿔 끼울 때 이가 맞는다).
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


## 붓질 한 번: 붓 범위 안의 정점을 part 로(part = "" 이면 지움). 바뀐 정점 수(모든 대상 합). 끝은 end_stroke()
func paint_at(hit: Vector3, part: String, radius: float = -1.0) -> int:
	if _target == null:
		return 0
	var r := radius if radius > 0.0 else _brush_spin.value * 0.01
	var view_dir := (_cam3.global_position - hit).normalized() if _cam3.is_inside_tree() else Vector3.BACK
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


## 사각형 자르기: 화면의 사각형(뷰포트 좌표 a · b 대각) 안 = 칠할 부위(앞뒤 함께, 화면에 보이던 부위만). 가장자리가 사각형 그대로 곧다.
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


## 붓질 · 선 긋기가 끝나면: 되돌리기 한 단계 · 저장 · 미리보기 다시 자르기
func end_stroke() -> void:
	_painting = false
	if _stroke.is_empty():
		return
	var done := _stroke
	_stroke = {}
	_undo.append(done)
	for t in done.keys():
		_after_paint_change(t as PaintTarget)


## 칠하기 · 관절이 바뀐 뒤: parts.json 을 바로 저장(게임 · 유닛 탭이 디스크에서 읽는다) → 3D 캐시 비우기(다음에 불러오는 쪽이 새로 나누게) →
## 이 탭 미리보기의 슬롯 메시를 다시 자른다(잠깐 뒤 — 붓을 여러 번 떼도 한 번)
func _after_paint_change(t: PaintTarget) -> void:
	if t.ov != null:
		t.ov.save()
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().update_file(DRPartOverrides.path_for(t.glb))
	DRCharacter3D.clear_cache()
	_pv_resplit = true
	_pv_timer = RESPLIT_DELAY
	_update_paint_status()


## 되돌리기 — 마지막 붓질 · 선 · 관절 하나(둘 다에 들어간 것은 둘 다 되돌린다)
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


## 되돌리기(검사 · 바깥에서 부르는 이름)
func undo() -> void:
	_on_undo()


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
			var nj := _count_joint_cuts(t)
			lines.append("%s — 관절 경계 %d · 직접 자르기 %d · 붓 %d곳 (%s)" % ["기본 몸" if t.kind == "base" else "옷 모델", nj, t.ov.cuts.size() - nj, t.ov.size(), DRPartOverrides.path_for(t.glb).get_file()])
	lines.append("되돌리기 %d번 가능 · 고칠 때마다 parts.json 에 바로 저장" % _undo.size())
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
						_say("직선 · 사각형은 지우개로 못 씁니다 — 자르기를 없애려면 Ctrl+Z(되돌리기) 또는 `경계 · 칠한 것 모두 지우기`.")
						return
					if int(r.get("changed", 0)) > 0:
						var per: Dictionary = r.get("per", {})
						var detail := "옷 모델 %d곳" % int(per.get("outfit", 0)) if per.has("outfit") else ""
						if per.has("base"):
							detail += ("" if detail == "" else " · ") + "기본 몸 %d곳" % int(per.get("base", 0))
						_say("%s: %s → %s (%s)" % ["직선 자르기" if _tool == "line" else "사각형", String(r.get("source", "사각형 안")), _paint_part, detail])
					else:
						_say("바뀐 곳 없음 — 선은 부위 경계를 지나게, 사각형은 모델을 덮게 그어 주세요.")
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
		var used := true
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
		else:
			used = false
		if used:
			_pv3.accept_event()          # 에디터의 같은 단축키(Ctrl+Z 등)로 번지지 않게


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


# ---------------------------------------------------------------- 슬롯 · 저장

func _fill_slot_opts() -> void:
	_filling = true
	for pn in _slot_opts.keys():
		(_slot_opts[pn] as OptionButton).select(SLOT_KEYS.find(String(_slots.get(pn, ""))))
	_filling = false


func _on_slot_changed(part: String, i: int) -> void:
	if _filling or not _loaded:
		return
	set_slot(part, String(SLOT_KEYS[i]))


## 파트 하나의 슬롯을 바꾼다("top" · "bottom" · "" = 기본 몸) — 미리보기만 바로, 게임에는 [저장] 뒤
func set_slot(part: String, key: String) -> void:
	if not _loaded or not ALL_PARTS.has(part) or not SLOT_KEYS.has(key):
		return
	if String(_slots.get(part, "")) == key:
		return
	_slots[part] = key
	_filling = true
	(_slot_opts[part] as OptionButton).select(SLOT_KEYS.find(key))
	_filling = false
	_dirty_doc = true
	_pv_resplit = true
	_pv_timer = 0.0
	_update_slot_warn()
	_say("슬롯: %s → %s (저장 전 — 미리보기에만)" % [part, String(SLOT_NAMES[key])])


func get_slots() -> Dictionary:
	return _slots.duplicate()


## 기본 몸은 게임에서 기본 표(DRSlotMesh.DEFAULT_SLOTS)로 나뉜다 — 옷의 표가 다르면 상의만 / 하의만 차림에서 그 파트가 겹치거나 빈다
func _update_slot_warn() -> void:
	if _slot_warn == null:
		return
	var diff := PackedStringArray()
	for pn in ALL_PARTS:
		if DRSlotMesh.slot_of(pn, _slots) != DRSlotMesh.slot_of(pn, DRSlotMesh.DEFAULT_SLOTS):
			diff.append(pn)
	_slot_warn.text = "" if diff.is_empty() else "⚠ 기본 표와 다름: %s — 기본 몸은 기본 표로 나뉘어, 상의만 / 하의만 차림에서 이 파트가 겹치거나 빈다(미리보기로 확인)" % ", ".join(diff)


## [저장] — outfit.json(id · model · slots · version). 파일에 있던 다른 키(2D 시험장의 sets · sets_json 등)는 그대로 둔다.
## parts.json 은 고칠 때마다 이미 저장됐다(관절을 끄는 중이면 그것부터 마무리). 돌려주는 값 = 성공
func save_outfit() -> bool:
	if not _loaded:
		_say("⚠ 먼저 불러오세요")
		return false
	_joint_commit()
	if _painting:
		end_stroke()
	var id := _clean_id(_id_edit.text) if _id_edit.text.strip_edges() != "" else _json_path.get_base_dir().get_file()
	if id == "":
		_say("⚠ 복장 이름을 적어 주세요")
		return false
	if not FileAccess.file_exists(_json_path) and _picked_json_existing() == "":
		_json_path = OUTFITS_DIR.path_join(id).path_join("outfit.json")
	var doc := _read_doc(_json_path)
	doc["id"] = id
	doc["model"] = _model_path
	var sl := {}
	for pn in ALL_PARTS:
		sl[pn] = String(_slots.get(pn, ""))
	doc["slots"] = sl
	doc["version"] = maxi(int(doc.get("version", 1)), 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_json_path.get_base_dir()))
	var f := FileAccess.open(_json_path, FileAccess.WRITE)
	if f == null:
		_say("⚠ 저장 실패: %s" % _json_path)
		return false
	# JSON 은 숫자를 모두 실수로 읽는다 — 다른 키의 정수(2D 조각 crop 등)가 "104.0" 으로 바뀌지 않게 되돌려 쓴다
	f.store_string(JSON.stringify(_int_back(doc), "\t"))
	f.close()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(_json_path)
	DRCharacter3D.clear_cache()
	_dirty_doc = false
	_remember_fields()
	_scan_outfits(_json_path)
	_say("저장: %s (옷 모델 %s · 슬롯 %d개) — 게임 · ① 유닛 탭이 다음에 불러올 때 이대로" % [_json_path, _model_path.get_file(), sl.size()])
	return true


## 정수였던 실수(104.0)를 정수로 — JSON 으로 다시 쓸 때 원래 모양 그대로
static func _int_back(v: Variant) -> Variant:
	if v is Dictionary:
		var d := {}
		for k in (v as Dictionary).keys():
			d[k] = _int_back((v as Dictionary)[k])
		return d
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_int_back(x))
		return a
	if v is float and is_finite(v) and absf(v) < 9.0e15 and float(int(v)) == v:
		return int(v)
	return v


func _say(msg: String) -> void:
	_last_msg = msg
	if _status == null:
		return
	var lines := PackedStringArray()
	if _last_msg != "":
		lines.append(_last_msg)
	if _loaded and _dirty_doc:
		lines.append("● 저장 안 한 고침(슬롯 표 · 옷 모델) — [저장] 해야 게임에 들어간다")
	_status.text = "\n".join(lines)
	if _save_btn != null:
		_save_btn.text = "저장 *" if _loaded and _dirty_doc else "저장"


# ---------------------------------------------------------------- 3D 미리보기

## 미리보기 캐릭터(기본 몸 + 동작 묶음)를 새로 세운다 — 슬롯 메시는 _resplit_preview 가 이 페이지의 칠하기 · 슬롯 표로 잘라 끼운다
func _build_preview_char() -> bool:
	if _pv_ch != null and is_instance_valid(_pv_ch):
		if _pv_ch.get_parent() != null:
			_pv_ch.get_parent().remove_child(_pv_ch)
		_pv_ch.free()
	_pv_ch = null
	_weapon_socks.clear()                        # 캐릭터와 같이 지워졌다
	_body_key = ""
	_outfit_key = ""
	var ch := DRCharacter3D.new()
	ch.auto_build = false
	_dots.world.add_child(ch)
	if not ch.setup(_body_path):
		ch.queue_free()
		_pv_info.text = "⚠ 미리보기 몸을 세울 수 없습니다: %s" % _body_path
		return false
	ch.height_m = PREVIEW_HEIGHT                 # 게임과 같은 키
	if ResourceLoader.exists(MOTIONS_LIB):
		var lib := load(MOTIONS_LIB) as AnimationLibrary
		if lib != null:
			ch.set_motions(lib)
	var ap := ch.get_animation_player()
	if ap != null:
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL   # 초당 12번 손으로 돌린다(게임과 같게)
	_pv_ch = ch
	set_turn(_turn)
	if _weapon_cb.button_pressed:
		_set_weapon(true)
	_resplit_preview()
	_fill_motions()
	return true


## 미리보기 캐릭터(검사용)
func preview_character() -> DRCharacter3D:
	return _pv_ch


## 모델 하나를 슬롯 표대로 자른다(게임과 같은 DRSlotMesh.split — 메모리의 칠하기 · 관절 경계) + 공유 도트 재질
func _split_of(t: PaintTarget, table: Dictionary, caps: bool) -> Dictionary:
	var res := DRSlotMesh.split(t.mi, t.skel, _profile, table, t.ov, true, caps)
	for s in res.meshes.keys():
		var am: ArrayMesh = res.meshes[s]
		for si in am.get_surface_count():
			am.surface_set_material(si, DRCharacter3D.char_material(am.surface_get_material(si)))
	return {"meshes": res.meshes, "skin": t.mi.skin, "res": res}


## 자른 결과가 달라지는 것만 담은 열쇠 — 칠한 점 · 슬롯 나뉨에 영향 있는 자르기(needed_cuts) · 슬롯 표 · 뚜껑.
## 팔꿈치 · 무릎처럼 같은 슬롯 안 경계를 바꾼 것은 다시 자르지 않는다
func _split_key(t: PaintTarget, table: Dictionary, caps: bool) -> String:
	return "%s|%d|%d|%s|%s" % [t.glb, str(t.ov.map).hash(), JSON.stringify(DRSlotMesh.needed_cuts(t.ov.cuts, table)).hash(),
		_table_sig(table), "caps" if caps else "open"]


static func _table_sig(tbl: Dictionary) -> String:
	var out := PackedStringArray()
	for pn in ALL_PARTS:
		out.append("%s=%s" % [pn, DRSlotMesh.slot_of(String(pn), tbl)])
	return ",".join(out)


## 미리보기 슬롯 메시를 다시 자른다(바뀐 모델만) → 차림대로 끼운다
func _resplit_preview() -> void:
	_pv_resplit = false
	if _pv_ch == null or not is_instance_valid(_pv_ch) or not _loaded:
		return
	var caps := _caps_cb.button_pressed
	if _t_base != null:
		var bk := _split_key(_t_base, DRSlotMesh.DEFAULT_SLOTS, caps)
		if bk != _body_key:
			_body_split = _split_of(_t_base, DRSlotMesh.DEFAULT_SLOTS, caps)
			_body_key = bk
	if _t_outfit != null:
		var ok := _split_key(_t_outfit, _slots, caps)
		if ok != _outfit_key:
			_outfit_split = _split_of(_t_outfit, _slots, caps)
			_outfit_key = ok
	_apply_look()


## 검사용 — 기다리지 않고 지금 다시 자른다
func refresh_preview_now() -> void:
	_joint_commit()
	_resplit_preview()


## 지금 미리보기에 쓴 자르기 결과 {"outfit": DRSlotMesh.Result, "body": DRSlotMesh.Result}(검사용)
func split_results() -> Dictionary:
	return {"outfit": _outfit_split.get("res", null), "body": _body_split.get("res", null)}


## 차림: full = 상의 · 하의 모두 이 옷 · top = 상의만 · bottom = 하의만 · naked = 내복(기본 몸)
func set_look(look: String) -> void:
	_look = look
	for k in _look_btns.keys():
		(_look_btns[k] as Button).set_pressed_no_signal(k == look)
	_apply_look()


func _apply_look() -> void:
	if _pv_ch == null or not is_instance_valid(_pv_ch):
		return
	for s in DRCharacter3D.WEAR_SLOTS:
		var mi := _pv_ch.get_slot_node(String(s))
		if mi == null:
			continue
		var use := _look == "full" or _look == String(s)
		var src: Dictionary = _body_split
		if use and not _outfit_split.is_empty() and (_outfit_split["meshes"] as Dictionary).has(s):
			src = _outfit_split               # 그 슬롯이 없는 옷(예: 상의만 있는 옷)이면 기본 몸 그대로 — wear() 와 같다
		if src.is_empty():
			continue
		mi.mesh = (src["meshes"] as Dictionary).get(s, null)
		mi.skin = src["skin"]
	var bmi := _pv_ch.get_slot_node("base")
	if bmi != null and not _body_split.is_empty():
		bmi.mesh = (_body_split["meshes"] as Dictionary).get("base", null)
		bmi.skin = _body_split["skin"]
	_update_pv_info()


func _update_pv_info() -> void:
	if _pv_info == null:
		return
	var parts := PackedStringArray()
	var look_name := _look
	for l in LOOKS:
		if String(l[0]) == _look:
			look_name = String(l[1])
	parts.append("지금 %s · %s" % [_cur_motion if _cur_motion != "" else "-", look_name])
	var r: DRSlotMesh.Result = _outfit_split.get("res", null)
	if r != null:
		var sl := PackedStringArray()
		for s in ["top", "bottom"]:
			if r.tri_counts.has(s):
				sl.append("%s 정점 %d · 삼각형 %d(뚜껑 %d)" % [SLOT_NAMES[s], int(r.vert_counts.get(s, 0)), int(r.tri_counts.get(s, 0)), int(r.cap_tris.get(s, 0))])
		parts.append("옷 " + " · ".join(sl) + " · 나누기 %.0f ms" % r.ms)
		if r.cap_open > 0:
			parts.append("⚠ 못 막은 경계 %d" % r.cap_open)
	_pv_info.text = "   ".join(parts)


func _fill_motions() -> void:
	_motion_ob.clear()
	if _pv_ch == null:
		return
	var names := _pv_ch.motion_names()
	var want := _cur_motion
	if not names.has(want):
		want = DEFAULT_MOTION if names.has(DEFAULT_MOTION) else (names[0] if names.size() > 0 else "")
	for n in names:
		_motion_ob.add_item(n)
		if n == want:
			_motion_ob.select(_motion_ob.item_count - 1)
	if want == "":
		_pv_info.text = "⚠ 3D 동작 묶음이 없습니다(%s) — ① 유닛 탭 동작 표에서 [3D 동작 내보내기]" % MOTIONS_LIB
		return
	play_motion(want)


## 미리보기 동작을 튼다(멈춘 상태면 지금 시각 막대 자리를 보인다)
func play_motion(motion: String) -> void:
	_cur_motion = motion
	for i in _motion_ob.item_count:
		if _motion_ob.get_item_text(i) == motion and _motion_ob.selected != i:
			_motion_ob.select(i)
	if _pv_ch == null:
		return
	var ap := _pv_ch.get_animation_player()
	if ap != null and ap.has_animation(motion) and not ap.is_playing():
		ap.stop()
	_pv_ch.play_motion(motion, 0.0)
	_acc = 0.0
	if not _playing:
		_seek(_time_sl.value)
	_update_pv_info()


## 동작의 frac(0~1) 시각 자세로 멈춘다(검사 · 같은 순간 비교)
func pose_at(motion: String, frac: float) -> void:
	_set_playing(false)
	_time_sl.set_value_no_signal(clampf(frac, 0.0, 1.0))
	play_motion(motion)
	_seek(frac)


func _set_playing(on: bool) -> void:
	_playing = on
	_play_btn.text = "⏸ 멈춤" if on else "▶ 재생"
	_acc = 0.0


func _seek(frac: float) -> void:
	if _pv_ch == null or _cur_motion == "":
		return
	var ap := _pv_ch.get_animation_player()
	if ap == null or not ap.has_animation(_cur_motion):
		return
	if ap.current_animation != _cur_motion or not ap.is_playing():
		ap.stop()
		_pv_ch.play_motion(_cur_motion, 0.0)
	ap.seek(clampf(frac, 0.0, 1.0) * ap.get_animation(_cur_motion).length, true)
	ap.advance(0.0)                    # 손으로 돌리는 모드(MANUAL)라 자세를 바로 — DRGripFit.pose 와 같은 순서


## 이음매 보기 — 그 자리를 화면 가운데로 따라가며 확대(이음매는 도트 1 px · 전신은 2 px)
func set_focus(key: String) -> void:
	_focus = key
	for k in _focus_btns.keys():
		(_focus_btns[k] as Button).set_pressed_no_signal(k == key)
	var z := 0.0
	for f in FOCUS:
		if String(f[0]) == key:
			z = float(f[2])
	if z <= 0.0:                                 # 전신 = 화면 높이에 몸이 들어오게
		z = clampf(float(_pv_vp.size.y) * 0.75 / PREVIEW_HEIGHT, 100.0, 600.0)
	_zoom_sl.value = z
	_set_dot(1 if key != "body" else 2)


func _set_dot(px: int) -> void:
	_dots.dot_px = px
	for i in _dot_ob.item_count:
		if _dot_ob.get_item_id(i) == px:
			_dot_ob.select(i)


## 돌려 보기(도) — 0 = 앞, 55 = 게임(3/4)
func set_turn(deg: float) -> void:
	_turn = wrapf(deg, -180.0, 180.0)
	if _pv_ch != null and is_instance_valid(_pv_ch):
		_pv_ch.rotation = Vector3(0.0, deg_to_rad(_turn), 0.0)


## 무기 = 기본형 군인 프리팹의 받침 장비(소켓 · 받침대 → 무기 → 손 표지)를 빌려 미리보기 캐릭터에 꽂는다 — 게임 · ② 장비 탭과 같은 자리 · 같은 손 IK
func _set_weapon(on: bool) -> void:
	if _pv_ch == null or not is_instance_valid(_pv_ch):
		return
	for s in _weapon_socks:
		if is_instance_valid(s):
			s.get_parent().remove_child(s)
			s.free()
	_weapon_socks.clear()
	var ps := load(WEAPON_UNIT) as PackedScene if on and ResourceLoader.exists(WEAPON_UNIT) else null
	if ps != null:
		var unit := ps.instantiate()                 # 트리에 안 넣음 = 조립 안 함(받침 노드만 빌린다)
		for s in DRCharacter3D.find_anchors(unit):
			s.get_parent().remove_child(s)
			_pv_ch.add_child(s)
			_weapon_socks.append(s)
		unit.free()
	_pv_ch.refresh_equipment()
	if _cur_motion != "":
		var f := _time_sl.value
		var ap := _pv_ch.get_animation_player()
		if ap != null:
			ap.stop()
		_pv_ch.play_motion(_cur_motion, 0.0)
		if not _playing:
			_seek(f)


## 따라갈 자리(미리보기 3D 세상 좌표) — 손목은 자르는 자리(손목 관절에서 아래팔 쪽 3 cm, 관절 경계 기본값)
func _focus_point() -> Vector3:
	var sk := _pv_ch.get_skeleton() if _pv_ch != null else null
	if sk == null:
		return Vector3.ZERO
	match _focus:
		"neck":
			return (_bone_world(sk, "Neck") + _bone_world(sk, "Head")) * 0.5
		"waist":
			return _bone_world(sk, "Spine")
		"LeftHand", "RightHand":
			var h := _bone_world(sk, _focus)
			var f := _bone_world(sk, "LeftLowerArm" if _focus == "LeftHand" else "RightLowerArm")
			return h + (f - h).normalized() * 0.03 * sk.global_transform.basis.get_scale().x
	return (_bone_world(sk, "Hips") + _bone_world(sk, "Head")) * 0.5


static func _bone_world(sk: Skeleton3D, bone: String) -> Vector3:
	var bi := sk.find_bone(bone)
	if bi < 0:
		return sk.global_position
	return sk.global_transform * sk.get_bone_global_pose(bi).origin


## 따라갈 자리가 화면 가운데에 오게 DRDotView3D 원점을 옮긴다(원점 = 캐릭터 발밑이 그려지는 캔버스 자리)
func _sync_preview_origin() -> void:
	if _pv_vp == null or _dots == null:
		return
	var center := Vector2(_pv_vp.size) * 0.5
	var want := Vector2(center.x, float(_pv_vp.size.y) * 0.85)
	if _pv_ch != null and is_instance_valid(_pv_ch) and _pv_ch.get_skeleton() != null:
		want = _dots.origin + center - _dots.world_to_canvas(_focus_point())
	if _dots.origin.distance_squared_to(want) > 0.0001:
		_dots.origin = want
		_ground.queue_redraw()


func _draw_ground() -> void:
	if _dots == null:
		return
	var o := _dots.origin
	var k := _dots.px_per_m
	var top := o.y - k * 0.2
	_ground.draw_rect(Rect2(-100000.0, top, 200000.0, 100000.0), Color(0.31, 0.37, 0.3))
	_ground.draw_line(Vector2(-100000.0, top), Vector2(100000.0, top), Color(0.22, 0.27, 0.22), 1.0)
	_ground.draw_set_transform(o, 0.0, Vector2(1.0, 0.3))
	_ground.draw_circle(Vector2.ZERO, k * 0.4, Color(0.0, 0.0, 0.0, 0.3))
	_ground.draw_set_transform(Vector2.ZERO)


func _on_pv_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_sl.value = minf(_zoom_sl.value * 1.15, _zoom_sl.max_value)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_sl.value = maxf(_zoom_sl.value / 1.15, _zoom_sl.min_value)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_pv_drag = mb.pressed
			_pv_drag_from = mb.position
	elif ev is InputEventMouseMotion and _pv_drag:
		var mm := ev as InputEventMouseMotion
		set_turn(_turn + (mm.position.x - _pv_drag_from.x) * 0.5)
		_pv_drag_from = mm.position


# ---------------------------------------------------------------- 뼈대에 붙이기(Blender)

func _on_bind() -> void:
	if _bind_thread != null and _bind_thread.is_started():
		return
	var raw := _raw_edit.text.strip_edges()
	if raw == "" or not FileAccess.file_exists(raw if raw.is_absolute_path() and not raw.begins_with("res://") else ProjectSettings.globalize_path(raw)):
		_bind_status.text = "⚠ AI 원본 파일이 없습니다: %s" % raw
		return
	var id := _clean_id(_id_edit.text)
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
		"--part_fix", "1" if _partfix_cb.button_pressed else "0",
		"--limb_fit", "1" if _limbfit_cb.button_pressed else "0",
		"--cuff_fit", "1" if _limbfit_cb.button_pressed else "0"])
	_bind_btn.disabled = true
	_bind_status.text = "붙이는 중… (Blender, 수십 초)"
	_bind_thread = Thread.new()
	_bind_thread.start(_bind_worker.bind(blender, args, out_res))


## 붙이기 결과의 팔 맞춤 · 소매 끝 맞춤 한 줄(10-16) — 옮긴 정점 수 · 가장 많이 옮긴 거리(cm), 왼 / 오른
static func _fit_note(r: Dictionary) -> String:
	var parts := PackedStringArray()
	for pair in [["limb_fit", "팔 맞춤"], ["cuff_fit", "소매 끝 맞춤"]]:
		var d: Dictionary = r.get(String(pair[0]), {})
		if d.is_empty():
			continue
		var sides := PackedStringArray()
		for sd in ["l", "r"]:
			if d.has(sd):
				var e: Dictionary = d[sd]
				sides.append("%s %d곳 · 최대 %.1f cm" % ["왼" if sd == "l" else "오른", int(e.get("moved_vertices", 0)), float(e.get("max_move_cm", 0.0))])
		parts.append("%s(%s)" % [pair[1], ", ".join(sides)])
	return ("\n" + " · ".join(parts)) if not parts.is_empty() else ""


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
	_bind_status.text = "붙임 → %s\n방향 %s° · 키 배율 %.3f · 웨이트 없는 정점 %d · 엄지 %s · 관절 경계 %s%s" % [out_res, str(r.get("turned_deg", 0)),
		float(r.get("scale", 1.0)), int(r.get("unweighted_vertices", 0)), str(r.get("thumb_fit_deg", {})), str(r.get("part_fix", {})),
		_fit_note(r)]
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
	_scan_models(out_res)
	_on_load()


# ---------------------------------------------------------------- 매 프레임

func _process(delta: float) -> void:
	if not _active or not is_visible_in_tree():
		return
	_sync_preview_origin()
	_step_preview(delta)
	if not _loaded or _busy or _painting or _line_on:
		return
	if _joint_active:
		_joint_idle -= delta
		if _joint_idle <= 0.0:
			_joint_commit()
	if _disp_dirty:
		_disp_dirty = false
		_refresh_display()
	if _pv_resplit:
		_pv_timer -= delta
		if _pv_timer <= 0.0:
			_resplit_preview()


## 미리보기 동작을 초당 12번 진행(게임 BattleView3D 와 같은 끊는 맛). 한 번 도는 동작(사격 · 재장전)은 끝나면 처음부터
func _step_preview(delta: float) -> void:
	if _pv_ch == null or not is_instance_valid(_pv_ch) or not _playing or _cur_motion == "":
		return
	_acc += delta
	if _acc < 1.0 / STEP_HZ:
		return
	var ap := _pv_ch.get_animation_player()
	if ap == null:
		return
	if not ap.is_playing():
		ap.stop()
		_pv_ch.play_motion(_cur_motion, 0.0)
	else:
		_pv_ch.step_motion(_acc)
	_acc = 0.0
	if ap.has_animation(_cur_motion):
		var ln := ap.get_animation(_cur_motion).length
		if ln > 0.0:
			_time_sl.set_value_no_signal(clampf(ap.current_animation_position / ln, 0.0, 1.0))
