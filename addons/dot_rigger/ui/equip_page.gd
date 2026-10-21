@tool
extends DRPage
class_name DREquipPage

## ② 장비 탭(10-16, 3D 게임 정석) — 유닛 프리팹의 소켓 · 장비 편집기. 예전 ② 장비 굽기(2D 세트별 무기 그림 · DREquipWindow)를 갈음한다.
## 사용자(10-16): "2번 탭은 장비 3D 모델 하이어라키에 접근해 맞추는 방식, 즉 3D 게임 방식의 정석으로. 나중에 헬멧도 모델링 head 에 꽂으면 되고."
##   소켓 = 유닛 씬의 BoneAttachment3D(뼈를 따라감) · 장비 = 소켓 아래 모델 씬 인스턴스(자리 · 회전 = 소켓 기준 고정)
##   · 왼손 표지 = 장비 아래 DRHandTarget3D(왼팔 두 마디 IK 의 목표 — DRCharacter3D 가 조립 때 붙인다)
## 이 탭과 씬 독 · 인스펙터 · 3D 화면 기즈모가 **같은 노드**를 고친다(에디터 = 열린 유닛 씬 · 되돌리기 Ctrl+Z, 에디터 밖 = 인스턴스를 바로).
##
##   왼쪽: 유닛 · 소켓 나무(소켓 → 장비 → 표지) · 소켓 더하기(뼈) · 장비 넣기/바꾸기/빼기 · 고른 노드 자리(cm · ° · 크기) · 맞추기 · 저장
##   가운데: 미리보기 — 돌려 보기 + **유니티식 기즈모**(ui/transform_gizmo.gd, 10-16) / 도트 보기(게임과 같은 DRDotView3D) · 동작 재생 · 손 ↔ 표지 거리
##     단축키(유니티와 같음): Q 보기 · W 이동 · E 회전 · R 크기 · Y 변환 · X 로컬/글로벌 · Z 피벗/중심 · F 고른 것 보기 · Ctrl 끌기 = 눈금 ·
##     Ctrl+Z / Ctrl+Y(Ctrl+Shift+Z) 되돌리기 / 다시 · Ctrl+S 저장. 카메라: 휠 · 가운데 끌기(옮기기) · 오른쪽 / Alt+왼쪽 끌기(돌려 보기) · Alt+오른쪽(확대)
##     미리보기를 누르면(끌지 않고) 그 자리의 왼손 표지 · 소켓 · 장비를 고른다(빈 곳 = 고르기 풀기). 기즈모를 놓으면 유닛 씬에 되돌리기 한 칸
##   오른쪽: 동작마다 왼손(IK 전 · 뒤 cm) · 왼손 IK 비중(0 = 동작 그대로 — 수류탄 · 장전 · 맨손 달리기 등) · 무기 자리 · 조준 비중
##   조준 IK(10-21): 왼쪽 "조준" 칸(켜기 · 위 · 아래 · 옆 한계 · 빠르기 — 유닛 루트) · 가운데 [조준 미리보기](옆 · 높낮이를 끌면 허리 · 가슴이 돌아
##     총구 선이 표적 십자로) · 동작 표 "조준" 칸(그 동작의 조준 비중 — 기본 = 동작 표의 사격 · 조준 상태면 1)
## 미리보기는 유닛을 pack 한 사본(저장 안 한 고침까지)이라 편집 중인 씬을 건드리지 않는다. 자리만 바뀌면 사본의 노드 자리만 옮긴다.

const UNITS_DIR := "res://game/units"
const STEP_HZ := 12.0
const POLL_SEC := 0.3
const DEFAULT_MOTION := "Rifle_Aiming_Idle"
## 소켓 뼈 고르기 — 자주 쓰는 것 먼저(그 아래 몸의 모든 뼈). [뼈, 보이는 이름, 소켓 기본 이름]
## 왼손 소켓 이름은 "왼손소켓" — "왼손" 은 왼손 표지(DRHandTarget3D) 이름이라 헷갈리지 않게
const BONE_CHOICES := [["RightHand", "오른손 — 무기", "오른손"], ["Head", "머리 — 헬멧", "머리"], ["LeftHand", "왼손", "왼손소켓"],
	["UpperChest", "등 · 가슴", "등"], ["Hips", "허리", "허리"], ["RightUpperLeg", "오른 허벅지", "오른허벅지"], ["LeftUpperLeg", "왼 허벅지", "왼허벅지"]]
const BG_3D := Color(0.42, 0.47, 0.42)
## 유니티식 변환 기즈모(class_name 없이 — 에디터를 다시 켜지 않고 "개발 내용 갱신"으로 바뀐다)
const TransformGizmo := preload("res://addons/dot_rigger/ui/transform_gizmo.gd")

var _unit_ob: OptionButton
var _units: Dictionary = {}               # 경로 -> {name, parent}
var _sel_path := ""
var _root: DRCharacter3D = null           # 고치는 유닛의 루트(에디터 = 열린 씬의 루트, 밖 = 인스턴스)
var _owns_root := false
var _base_paths: Dictionary = {}          # 부모 유닛 씬에서 온 노드(루트 기준 경로) — 지울 수 없어 숨긴다
var _tree: Tree
var _sel := NodePath()                    # 고른 노드(루트 기준)
var _sock_name: LineEdit
var _bone_ob: OptionButton
var _model_ob: OptionButton
var _pos: Array[SpinBox] = []
var _rot: Array[SpinBox] = []
var _scl: Array[SpinBox] = []
var _giz: TransformGizmo
var _tool_btns: Array[Button] = []
var _pivot_btn: Button
var _space_btn: Button
var _snap_sp: Array[SpinBox] = []         # Ctrl 눈금: 이동 cm · 회전 ° · 크기
var _xf_title: Label
var _status: Label
var _xf_lock := false
var _ur: EditorUndoRedoManager = null     # 열린 되돌리기 동작(_begin ~ _end)
var _struct_sig := ""
var _xform_sig := ""
var _poll := 0.0
var _active := true
# 미리보기
var _prev: DRCharacter3D = null
var _view3d: SubViewportContainer
var _vp3d: SubViewport
var _world3d: Node3D
var _cam: Camera3D
var _env: Environment
var _imesh: ImmediateMesh
var _dotc: SubViewportContainer
var _dot_vp: SubViewport
var _dot_bg: ColorRect
var _dots: DRDotView3D
var _ground: Node2D
var _dot_mode := false
var _yaw := -40.0
var _pitch := 10.0
var _dist := 1.0
var _target := Vector3(0.0, 1.25, 0.15)
var _drag := 0
var _motion_ob: OptionButton
var _play_btn: Button
var _time_sl: HSlider
var _view_btn: Button
var _playing := true
var _acc := 0.0
var _info: Label
var _live: Array = []                     # 미리보기 뼈대가 갱신될 때 잰 손마다(IK 뒤) [왼손, 오른손] — support_now
var _mt_side := 0                         # 동작 표가 보이는 손(0 = 왼손 · 1 = 오른손)
var _rep_side := 0                        # 마지막으로 잰 수치의 손
var _mt_side_ob: OptionButton
var _grip_btns: Array[Button] = []        # 잡기: 오른손 · 왼손 · 양손 · 고정
var _blend_sl: HSlider
var _blend_lbl: Label
var _grip_info: Label
# 동작 표
var _mt: Tree
var _mt_lock := false
var _last_rep: Array = []                 # 마지막으로 잰 동작별 수치(DREquipHold.motion_report)
var _rep_stale := false                   # 잰 뒤 무기 · 표지 자리가 바뀜(다시 재야 맞음)
# 동작별 무기 자리(10-19)
var _per_motion := false                  # 기즈모 · 숫자 칸이 "이 동작만"(동작별 자리)을 고친다 — false = 모든 동작(기본 자리)
var _pm_btns: Array[Button] = []          # 무기 자리: 모든 동작 · 이 동작만
var _pm_banner: PanelContainer            # 미리보기 위 띠(이 동작만일 때)
var _pm_label: Label
var _pm_fit_btn: Button
var _pm_reset_btn: Button
var _xf_note: Label                       # 숫자 칸 아래 — 동작별 자리 안내
var _mt_menu: PopupMenu                   # 동작 표 오른쪽 누름
var _mt_menu_motion := ""
var _offset_clip: Variant = null          # 복사한 동작별 자리(Transform3D)
# 조준 IK(10-21)
const AIM_FIELDS := [["aim_up_deg", "위 한계 °", 0.0, 80.0, 1.0, "총구를 위로 더 돌릴 수 있는 각(그 동작이 원래 겨눈 높낮이에서) — 표적이 더 높으면 여기서 멈춘다"],
	["aim_down_deg", "아래 한계 °", 0.0, 80.0, 1.0, "아래로 더 돌릴 수 있는 각"],
	["aim_side_deg", "옆 한계 °", 0.0, 60.0, 1.0, "옆으로(앞뒤 줄의 표적) 더 돌릴 수 있는 각 — 0 이면 높낮이만 맞춘다"],
	["aim_speed_deg", "빠르기 °/s", 30.0, 1440.0, 10.0, "표적이 바뀔 때 허리를 돌리는 빠르기(초당 각)"]]
const AIM_MARK_M := 1.5                   # 미리보기 표적 십자 · 총구 선 길이(m)
var _aim_chk: CheckBox
var _aim_sp: Dictionary = {}              # 칸 이름 -> SpinBox
var _aim_lock := false
var _aim_btn: Button                      # 조준 미리보기
var _aim_side_sl: HSlider
var _aim_height_sl: HSlider
var _aim_lbl: Label
var _aim_preview := false


func _init() -> void:
	page_title = "장비 (3D)"
	_build_ui()


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
	if _vp3d != null:
		_vp3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on and not _dot_mode else SubViewport.UPDATE_DISABLED
	if _dot_vp != null:
		_dot_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on and _dot_mode else SubViewport.UPDATE_DISABLED
	if _dots != null:
		_dots.visible = on and _dot_mode       # 도트 창 안의 3D 렌더도 멈춘다(DRDotView3D 는 숨기면 자기 뷰포트를 끈다)


func set_preview_bg(c: Color) -> void:
	var col := c if c.a > 0.0 else BG_3D
	if _env != null:
		_env.background_color = col
	if _dot_bg != null:
		_dot_bg.color = col


# ───────────── 틀 ─────────────

func _build_ui() -> void:
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(split)

	# 왼쪽 — 유닛 · 소켓 · 장비 · 자리
	var lsc := ScrollContainer.new()
	lsc.custom_minimum_size = Vector2(370, 0)
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(lsc)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lsc.add_child(left)
	var urow := HBoxContainer.new()
	left.add_child(urow)
	var ul := Label.new()
	ul.text = "유닛"
	urow.add_child(ul)
	_unit_ob = OptionButton.new()
	_unit_ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_unit_ob.clip_text = true
	_unit_ob.tooltip_text = "소켓 · 장비를 고칠 유닛 프리팹(game/units — ① 유닛 탭과 같은 목록)"
	_unit_ob.item_selected.connect(func(i: int) -> void: select_unit(String(_unit_ob.get_item_metadata(i))))
	urow.add_child(_unit_ob)
	_btn(urow, "다시 찾기", "game/units 의 유닛 씬을 다시 찾는다", scan_units)
	var tl := Label.new()
	tl.text = "소켓 → 장비 → 왼손 표지 (씬 독과 같은 노드)"
	left.add_child(tl)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.allow_search = false              # 글자를 치면 찾기로 먹어 버려 W · E · R 단축키가 안 간다
	_tree.custom_minimum_size = Vector2(0, 170)
	_tree.item_selected.connect(_on_tree_selected)
	left.add_child(_tree)
	var srow := HBoxContainer.new()
	left.add_child(srow)
	_sock_name = LineEdit.new()
	_sock_name.placeholder_text = "새 소켓 이름(비우면 뼈 이름)"
	_sock_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	srow.add_child(_sock_name)
	_bone_ob = OptionButton.new()
	_bone_ob.custom_minimum_size = Vector2(120, 0)
	_bone_ob.clip_text = true
	_bone_ob.tooltip_text = "소켓이 따라갈 뼈"
	srow.add_child(_bone_ob)
	_btn(srow, "+ 소켓", "고른 뼈에 소켓(BoneAttachment3D)을 더한다 — 유닛 씬에 노드로 들어간다", func() -> void:
		add_socket(_sock_name.text, String(_bone_ob.get_item_metadata(_bone_ob.selected)) if _bone_ob.selected >= 0 else ""))
	var mrow := HBoxContainer.new()
	left.add_child(mrow)
	_model_ob = OptionButton.new()
	_model_ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_ob.clip_text = true
	_model_ob.tooltip_text = "넣을 장비 모델(source3d/weapons/** 의 무기 씬 · glb). 무기 기본 자리(asset.json)가 있으면 그 자리 · 왼손 표지로 넣는다"
	mrow.add_child(_model_ob)
	_btn(mrow, "넣기 · 바꾸기", "고른 소켓(또는 고른 장비의 소켓)에 이 모델을 넣는다. 이미 있으면 바꾼다 — 부모 유닛에서 온 장비는 지울 수 없어 숨긴다", func() -> void:
		put_model(String(_model_ob.get_item_metadata(_model_ob.selected)) if _model_ob.selected >= 0 else ""))
	_btn(mrow, "빼기", "고른 장비(또는 소켓)를 뺀다 — 부모 유닛에서 온 것은 숨긴다", remove_selected)
	# 잡기 — 고정할 곳(10-16 사용자: "오른손 · 왼손 · 양손 — 조인트 느낌, 어느 부분(소켓)을 고정할지")
	var gl := Label.new()
	gl.text = "잡기 — 무기를 고정할 곳(나머지 손은 표지를 따라감)"
	left.add_child(gl)
	var grow := HBoxContainer.new()
	left.add_child(grow)
	var gg := ButtonGroup.new()
	for g in [[0, "오른손", "무기가 오른손을 따라가고 왼손이 무기를 따라감(IK) — 소총 · kar98k(지금 기본형 군인)"],
			[1, "왼손", "무기가 왼손을 따라가고 오른손이 무기를 따라감(IK)"],
			[2, "양손", "무기가 두 손 사이(아래 보간)를 따라가고 두 손이 무기 표지를 따라감(IK) — mp40 처럼 두 손으로 드는 무기"],
			[3, "고정", "무기가 유닛(땅)에 고정되고 두 손이 무기 표지를 따라감(IK) — 라페테(삼각대) 위 MG42 · 거치 무기"]]:
		var b := Button.new()
		b.text = String(g[1])
		b.toggle_mode = true
		b.button_group = gg
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = String(g[2]) + "\n지금 미리보기에 보이는 자리 그대로 받침만 바꾼다. 따라갈 손의 표지가 없으면 그 손의 지금 자리로 만든다(되돌리기 한 칸)"
		var kv: int = g[0]
		b.pressed.connect(func() -> void: set_grip(kv))
		grow.add_child(b)
		_grip_btns.append(b)
	var brow2 := HBoxContainer.new()
	left.add_child(brow2)
	_blend_lbl = Label.new()
	_blend_lbl.text = "보간"
	_blend_lbl.custom_minimum_size = Vector2(150, 0)
	brow2.add_child(_blend_lbl)
	_blend_sl = HSlider.new()
	_blend_sl.min_value = 0.0
	_blend_sl.max_value = 1.0
	_blend_sl.step = 0.05
	_blend_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_blend_sl.tooltip_text = "양손 — 무기가 두 손 사이 어디를 따라갈지(0 % = 오른손 쪽 · 100 % = 왼손 쪽). 그 동작에서 총을 놓은 손(IK 비중 0)은 빼고 잡은 손만 따른다"
	_blend_sl.value_changed.connect(set_blend)
	brow2.add_child(_blend_sl)
	_grip_info = Label.new()
	_grip_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_grip_info.add_theme_font_size_override("font_size", 12)
	_grip_info.add_theme_color_override("font_color", Color(0.72, 0.8, 0.9))
	left.add_child(_grip_info)
	var frow := HFlowContainer.new()
	left.add_child(frow)
	_btn(frow, "지금 자세로 왼손 표지", "미리보기의 지금 동작 · 시점에서 왼손(동작 그대로) 자리 · 회전을 고른 장비의 왼손 표지로(없으면 만든다)", func() -> void: make_hand_marker(0))
	_btn(frow, "지금 자세로 오른손 표지", "미리보기의 지금 동작 · 시점에서 오른손(동작 그대로) 자리 · 회전을 고른 장비의 오른손 표지로(없으면 만든다) — 무기가 왼손 · 양손 · 고정일 때 오른손이 따라감", func() -> void: make_hand_marker(1))
	_btn(frow, "지금 동작으로 무기 맞추기", "지금 동작 · 시점의 두 손바닥으로 무기 방향을 다시 잡는다(쥐는 점 = 지금 오른 손바닥 자리, 표지가 있으면 그 점이 왼손 쪽) — 손 소켓에 든 무기만", fit_weapon)
	# 조준 IK(10-21) — 유닛 루트 칸. 사용자: "사격할 때 적을 바라보는 벡터 기준으로 허리가 살짝 굽거나 — 총구가 적을 바라봐야 되니까"
	left.add_child(HSeparator.new())
	var arow0 := HBoxContainer.new()
	left.add_child(arow0)
	_aim_chk = CheckBox.new()
	_aim_chk.text = "조준"
	_aim_chk.focus_mode = Control.FOCUS_NONE
	_aim_chk.tooltip_text = "조준 IK — 사격 · 조준 동작에서 허리 · 가슴(Spine · Chest · UpperChest)을 돌려 총구가 표적(게임이 주는 적의 겨눌 곳)을 향하게 한다.\n" + \
		"높낮이는 정확히 · 옆은 몸 정면에서 표적이 벗어난 만큼만(동작이 원래 겨눈 옆 방향은 그대로). 손 · 무기는 몸을 따라오고 손 IK 가 다시 잡는다"
	_aim_chk.toggled.connect(func(on: bool) -> void: set_aim_setting("aim_enabled", on))
	arow0.add_child(_aim_chk)
	var anote := Label.new()
	anote.text = "사격 때 허리 · 가슴을 돌려 총구를 표적으로"
	anote.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	anote.clip_text = true
	anote.add_theme_font_size_override("font_size", 12)
	anote.add_theme_color_override("font_color", Color(0.72, 0.8, 0.9))
	arow0.add_child(anote)
	var agrid := GridContainer.new()
	agrid.columns = 4
	left.add_child(agrid)
	for f in AIM_FIELDS:
		var al := Label.new()
		al.text = String(f[1])
		al.tooltip_text = String(f[5])
		al.mouse_filter = Control.MOUSE_FILTER_PASS
		agrid.add_child(al)
		var sp := SpinBox.new()
		sp.min_value = float(f[2])
		sp.max_value = float(f[3])
		sp.step = float(f[4])
		sp.custom_minimum_size = Vector2(84, 0)
		sp.tooltip_text = String(f[5])
		var prop := String(f[0])
		sp.value_changed.connect(func(v: float) -> void: set_aim_setting(prop, v))
		agrid.add_child(sp)
		_aim_sp[prop] = sp
	left.add_child(HSeparator.new())
	_xf_title = Label.new()
	_xf_title.text = "고른 노드 —"
	left.add_child(_xf_title)
	var grid := GridContainer.new()
	grid.columns = 4
	left.add_child(grid)
	for row in [["위치 cm", _pos, 0.1, -500.0, 500.0], ["회전 °", _rot, 0.5, -360.0, 360.0], ["크기", _scl, 0.01, 0.01, 100.0]]:
		var l := Label.new()
		l.text = String(row[0])
		grid.add_child(l)
		for k in 3:
			var sp := SpinBox.new()
			sp.step = float(row[2])
			sp.min_value = float(row[3])
			sp.max_value = float(row[4])
			var is_scl := is_same(row[1], _scl)     # 빈 배열끼리는 == 가 참이라 같은 배열인지로
			sp.allow_greater = true
			sp.allow_lesser = not is_scl
			sp.custom_minimum_size = Vector2(88, 0)
			sp.prefix = ["x", "y", "z"][k]
			sp.tooltip_text = "부모 기준(소켓 아래 장비 = 손 뼈 기준, 표지 = 장비 기준). 인스펙터의 position · rotation_degrees · scale 과 같은 값" + \
				(" — 크기는 장비만(왼손 표지 · 소켓은 없음)" if is_scl else "")
			sp.value_changed.connect(func(_v: float) -> void: _on_xf_changed())
			grid.add_child(sp)
			(row[1] as Array).append(sp)
	_xf_note = Label.new()
	_xf_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_xf_note.add_theme_font_size_override("font_size", 12)
	_xf_note.add_theme_color_override("font_color", Color(0.96, 0.7, 0.36))
	_xf_note.visible = false
	left.add_child(_xf_note)
	var erow := HBoxContainer.new()
	left.add_child(erow)
	_btn(erow, "에디터에서 고르기", "이 노드를 에디터에서 골라 3D 화면 기즈모로 옮긴다(탭과 같은 노드)", _on_edit_in_editor)
	_btn(erow, "무기 기본 자리로 저장", "고른 장비의 자리 · 왼손 표지 · 동작별 비중을 모델 옆 asset.json(socket_hold)에 — 다른 유닛 소켓에 넣을 때 처음 자리", save_hold_default)
	var brow := HBoxContainer.new()
	left.add_child(brow)
	_btn(brow, "씬 열기", "에디터에 이 유닛 씬을 연다", func() -> void:
		if _sel_path != "" and Engine.is_editor_hint():
			EditorInterface.open_scene_from_path(_sel_path))
	_btn(brow, "저장", "이 유닛 씬을 저장", save_unit)
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
	mid.custom_minimum_size = Vector2(340, 0)
	right_split.add_child(mid)
	_build_gizmo_bar(mid)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.custom_minimum_size = Vector2(320, 320)
	mid.add_child(stack)
	_view3d = SubViewportContainer.new()
	_view3d.stretch = true
	_view3d.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view3d.mouse_filter = Control.MOUSE_FILTER_IGNORE     # 마우스는 위에 겹친 기즈모 층이 받아 카메라 몫은 _on_view_input 으로 넘긴다
	stack.add_child(_view3d)
	_vp3d = SubViewport.new()
	_vp3d.own_world_3d = true
	_vp3d.world_3d = World3D.new()
	_vp3d.msaa_3d = Viewport.MSAA_2X
	_vp3d.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view3d.add_child(_vp3d)
	_world3d = Node3D.new()
	_world3d.name = "World"
	_vp3d.add_child(_world3d)
	_cam = Camera3D.new()
	_cam.fov = 35.0
	_cam.near = 0.02
	_cam.far = 60.0
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = BG_3D
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_cam.environment = _env
	_vp3d.add_child(_cam)
	_cam.current = true
	_imesh = ImmediateMesh.new()
	var lines := MeshInstance3D.new()
	lines.mesh = _imesh
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.vertex_color_use_as_albedo = true
	lm.no_depth_test = true
	lm.render_priority = Material.RENDER_PRIORITY_MAX
	lines.material_override = lm
	_vp3d.add_child(lines)
	_dotc = SubViewportContainer.new()
	_dotc.stretch = true
	_dotc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dotc.visible = false
	stack.add_child(_dotc)
	_dot_vp = SubViewport.new()
	_dot_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_dotc.add_child(_dot_vp)
	_dot_bg = ColorRect.new()
	_dot_bg.color = BG_3D
	_dot_bg.size = Vector2(4096, 4096)
	_dot_vp.add_child(_dot_bg)
	_ground = Node2D.new()
	_ground.draw.connect(_draw_ground)
	_dot_vp.add_child(_ground)
	_dots = DRDotView3D.new()
	_dots.px_per_m = 170.0
	_dot_vp.add_child(_dots)
	_apply_dot_style()
	_giz = TransformGizmo.new()
	_giz.camera = _cam
	_giz.view_input.connect(_on_view_input)
	_giz.clicked.connect(_on_view_click)
	_giz.transform_changed.connect(_on_giz_changed)
	_giz.transform_end.connect(_on_giz_end)
	stack.add_child(_giz)                    # 맨 위(돌려 보기에서만 보임 — set_dot_mode)
	# 이 동작만 띠 — 지금 무엇을 고치는지 늘 보이게(기본 자리를 고치는 줄 알고 끄는 일이 없게) + 그 자리에서 맞추기 · 기본으로 · 끝
	_pm_banner = PanelContainer.new()
	_pm_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	var pbs := StyleBoxFlat.new()
	pbs.bg_color = Color(0.86, 0.52, 0.14, 0.92)
	pbs.content_margin_left = 10
	pbs.content_margin_right = 6
	pbs.content_margin_top = 3
	pbs.content_margin_bottom = 3
	_pm_banner.add_theme_stylebox_override("panel", pbs)
	_pm_banner.visible = false
	var pbh := HBoxContainer.new()
	_pm_banner.add_child(pbh)
	_pm_label = Label.new()
	_pm_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pm_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_pm_label.add_theme_color_override("font_color", Color(0.12, 0.07, 0.02))
	_pm_label.mouse_filter = Control.MOUSE_FILTER_PASS
	pbh.add_child(_pm_label)
	_pm_fit_btn = _btn(pbh, "맞추기", "이 동작에 맞추기(자동) — 지금 동작 · 시점의 손(동작 그대로)에 무기 표지가 오게 이 동작 자리를 잡는다. 손 소켓 무기는 든 손을 축으로 돌리고, " +
		"양손(두 손 사이) 무기는 두 표지의 가운데 · 방향을 두 손바닥에 맞춘다. 잘 안 맞으면 다른 시점에서 다시 · 기즈모로 다듬기", fit_motion_offset)
	_pm_reset_btn = _btn(pbh, "기본으로", "이 동작의 따로 자리를 지운다(기본 자리로) — 되돌리기 한 칸", func() -> void: reset_motion_offset(current_motion()))
	_btn(pbh, "끝", "모든 동작(기본 자리) 고치기로 돌아간다", func() -> void: set_per_motion(false))
	stack.add_child(_pm_banner)
	_sync_gizmo_bar()
	var ctl := HFlowContainer.new()
	mid.add_child(ctl)
	var ml := Label.new()
	ml.text = "동작"
	ctl.add_child(ml)
	_motion_ob = OptionButton.new()
	_motion_ob.custom_minimum_size = Vector2(190, 0)
	_motion_ob.clip_text = true
	_motion_ob.tooltip_text = "미리 볼 동작(이 유닛 동작 표의 3D 동작 묶음)"
	_motion_ob.item_selected.connect(func(i: int) -> void: play_motion(_motion_ob.get_item_text(i)))
	ctl.add_child(_motion_ob)
	_play_btn = Button.new()
	_play_btn.text = "⏸ 멈춤"
	_play_btn.pressed.connect(func() -> void:
		_playing = not _playing
		_play_btn.text = "⏸ 멈춤" if _playing else "▶ 재생")
	ctl.add_child(_play_btn)
	_time_sl = HSlider.new()
	_time_sl.min_value = 0.0
	_time_sl.max_value = 1.0
	_time_sl.step = 0.001
	_time_sl.custom_minimum_size = Vector2(140, 0)
	_time_sl.tooltip_text = "동작의 시점(멈춘 채 끌어서 자세를 고른다)"
	_time_sl.value_changed.connect(_on_time)
	ctl.add_child(_time_sl)
	_view_btn = _btn(ctl, "도트 보기", "돌려 보기(가까이 · 기준점 맞추기) ↔ 도트 보기(게임 화면과 같은 저해상도 · 외곽선)", func() -> void: set_dot_mode(not _dot_mode))
	_btn(ctl, "손", "두 손 · 무기를 가까이", func() -> void: focus_hands())
	_btn(ctl, "전신", "몸 전체", func() -> void: focus_body())
	# 조준 미리보기(10-21) — 표적 대신 각으로: 옆 = 동작이 원래 겨눈 옆 방향에서 · 높낮이 = 총구 높낮이(수평 0)
	var arow := HFlowContainer.new()
	mid.add_child(arow)
	_aim_btn = Button.new()
	_aim_btn.text = "조준 미리보기"
	_aim_btn.toggle_mode = true
	_aim_btn.focus_mode = Control.FOCUS_NONE
	_aim_btn.tooltip_text = "미리보기 병사가 표적(분홍 십자)을 겨누게 한다 — 옆 · 높낮이를 끌어 허리 · 가슴이 어떻게 도는지 본다.\n" + \
		"총구 선: 초록 = 표적으로 · 주황 = 한계에서 멈춤. 조준 비중이 0 인 동작(서기 · 걷기 · 장전 …)은 돌지 않는다 — 오른쪽 표 \"조준\" 칸"
	_aim_btn.toggled.connect(set_aim_preview)
	arow.add_child(_aim_btn)
	for sd in [["옆", -45.0, 45.0, "동작이 원래 겨눈 옆 방향에서 표적이 벗어난 각(앞뒤 줄의 적)"], ["높낮이", -60.0, 60.0, "총구에서 본 표적의 높낮이(수평 = 0, 위 +) — 높은 벽 위 · 참호 아래 · 엎드린 적"]]:
		var sl := Label.new()
		sl.text = String(sd[0])
		arow.add_child(sl)
		var hs := HSlider.new()
		hs.min_value = float(sd[1])
		hs.max_value = float(sd[2])
		hs.step = 1.0
		hs.custom_minimum_size = Vector2(110, 0)
		hs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hs.tooltip_text = String(sd[3])
		hs.value_changed.connect(func(_v: float) -> void:
			if _aim_preview:
				_apply_aim_preview()
			else:
				set_aim_preview(true))           # 꺼진 채 끌면 켠다(끌어도 아무 일이 없는 함정 — 10-21 사용자 "변화 없는데?")
		arow.add_child(hs)
		if sd[0] == "옆":
			_aim_side_sl = hs
		else:
			_aim_height_sl = hs
	_aim_lbl = Label.new()
	_aim_lbl.add_theme_font_size_override("font_size", 12)
	arow.add_child(_aim_lbl)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 12)
	mid.add_child(_info)

	# 오른쪽 — 동작마다 손 · 무기 자리
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(470, 0)
	right_split.add_child(right)
	var rrow := HBoxContainer.new()
	right.add_child(rrow)
	var rl := Label.new()
	rl.text = "동작마다 손 · 무기 자리"
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rrow.add_child(rl)
	_mt_side_ob = OptionButton.new()
	_mt_side_ob.add_item("왼손", 0)
	_mt_side_ob.add_item("오른손", 1)
	_mt_side_ob.tooltip_text = "표가 보이는 손 — 그 손 표지의 동작별 IK 비중 · 수치(오른손은 무기가 왼손 · 양손 · 고정 받침일 때 IK)"
	_mt_side_ob.item_selected.connect(func(i: int) -> void:
		_mt_side = _mt_side_ob.get_item_id(i)
		_fill_motion_table())
	rrow.add_child(_mt_side_ob)
	_btn(rrow, "모든 동작 재기", "동작마다 8 시점에서 그 손바닥 ↔ 표지 거리(IK 전 = 동작 그대로 · IK 뒤) — 미리보기 사본으로 잰다", measure_all)
	_mt = Tree.new()
	# 칸: 동작 | 손 ↔ 표지(IK 전 → 뒤 평균 — 최대는 풍선 도움말) | IK 비중 | 무기 자리 | 조준. 10-19 무기 자리 칸을 넣으며 IK 전 · 뒤 두 칸을 하나로(탭 기본 크기에서 가로로 안 넘치게)
	_mt.columns = 5
	_mt.hide_root = true
	_mt.column_titles_visible = true
	_mt.set_column_title(0, "동작")
	_mt.set_column_title(1, "손↔표지 cm")
	_mt.set_column_title(2, "IK 비중")
	_mt.set_column_title(3, "무기 자리")
	_mt.set_column_title(4, "조준")
	_mt.set_column_title_tooltip_text(1, "그 손바닥 ↔ 표지 거리, 8 시점 평균: 동작 그대로(IK 전) → IK 뒤. 최대는 칸의 풍선 도움말 — [모든 동작 재기]")
	_mt.set_column_title_tooltip_text(2, "그 손을 표지에 붙이는 정도(0 = 동작 그대로 — 총을 놓는 동작)")
	_mt.set_column_title_tooltip_text(3, "그 동작의 무기 위치 · 회전 — ● 따로 둠(기본 자리에서 거리 · 각) · ↳ 상하체 합성의 상체 동작 것 · 기본")
	_mt.set_column_title_tooltip_text(4, "그 동작의 조준 비중(0 = 동작 그대로 · 1 = 총구가 표적으로) — 흐린 값 = 기본(동작 표의 사격 · 조준 상태면 1)")
	_mt.set_column_expand(0, true)
	_mt.set_column_clip_content(0, true)        # 좁으면 동작 이름을 줄여서(다른 칸이 밀려나지 않게)
	for cw in [[1, 88], [2, 64], [3, 100], [4, 56]]:
		_mt.set_column_expand(cw[0], false)
		_mt.set_column_custom_minimum_width(cw[0], cw[1])
	_mt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mt.allow_rmb_select = true
	_mt.item_edited.connect(_on_mt_edited)
	_mt.item_selected.connect(func() -> void:
		var it := _mt.get_selected()
		if it != null and not _mt_lock:
			play_motion(it.get_text(0)))
	_mt.item_activated.connect(func() -> void:          # 두 번 누름 = 그 동작만 고치기
		var it := _mt.get_selected()
		if it != null:
			play_motion(it.get_text(0))
			set_per_motion(true))
	_mt.item_mouse_selected.connect(_on_mt_mouse)
	right.add_child(_mt)
	_mt_menu = PopupMenu.new()
	_mt_menu.id_pressed.connect(_on_mt_menu)
	add_child(_mt_menu)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 11)
	help.add_theme_color_override("font_color", Color(0.6, 0.63, 0.67))
	help.text = "IK 전 · 뒤 = 평균 / 최대. IK 비중 0 = 그 동작은 그 손을 표지에 안 붙인다(수류탄 던지기 · 장전 · 맨손 달리기처럼 총을 놓는 동작 — 손 표지의 motion_weights). " + \
		"무기 자리 = 그 동작의 무기 위치 · 회전(● 따로 둠 · ↳ 상하체 합성의 상체 동작 것 · 기본). 조준 = 사격 때 허리 · 가슴을 돌리는 정도(흐림 = 기본). " + \
		"행 누름 = 그 동작 틀기 · 두 번 누름 = 이 동작만 고치기 · 오른쪽 누름 = 맞추기 · 복사 · 붙여넣기 · 기본으로."
	right.add_child(help)
	_fill_bones(PackedStringArray())
	_fill_models()
	_dots.visible = false
	_update_cam()


## 미리보기 위 기즈모 도구 줄 — 유니티 툴바와 같은 자리 · 같은 단축키
func _build_gizmo_bar(parent: Control) -> void:
	var bar := HFlowContainer.new()
	parent.add_child(bar)
	var group := ButtonGroup.new()
	for t in [[TransformGizmo.Tool.VIEW, "✋ Q", "Q — 보기: 손잡이 없음. 왼쪽 끌기 = 화면 옮기기"],
			[TransformGizmo.Tool.MOVE, "✥ W 이동", "W — 이동: 축 화살표 · 평면 네모 · 가운데 네모(화면 평면)"],
			[TransformGizmo.Tool.ROTATE, "⟳ E 회전", "E — 회전: 축 고리(고리를 따라 끈다) · 바깥 고리(화면 축) · 안쪽(자유)"],
			[TransformGizmo.Tool.SCALE, "⤢ R 크기", "R — 크기: 축 끝 네모(로컬 축) · 가운데(전체 — 오른쪽 · 위로 끌면 커짐). 왼손 표지 · 소켓은 크기 없음"],
			[TransformGizmo.Tool.TRANSFORM, "▣ Y 변환", "Y — 변환: 이동 화살표 · 평면 + 회전 고리 + 가운데(전체 크기)"]]:
		var b := Button.new()
		b.text = String(t[1])
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = String(t[2]) + "\n끄는 중 Ctrl = 눈금 · 오른쪽 누름 = 취소 · 놓으면 유닛 씬에 되돌리기 한 칸(Ctrl+Z)"
		var tv: int = t[0]
		b.pressed.connect(func() -> void: set_tool(tv))
		bar.add_child(b)
		_tool_btns.append(b)
	bar.add_child(VSeparator.new())
	_pivot_btn = _btn(bar, "피벗", "Z — 기즈모 자리: 피벗(노드 원점) ↔ 중심(보이는 메시 가운데). 회전 · 크기의 중심도 이것", func() -> void: set_pivot_mode(not _giz.pivot_mode))
	_space_btn = _btn(bar, "로컬", "X — 손잡이 방향: 로컬(노드 축) ↔ 글로벌(세상 축). 크기 손잡이는 늘 로컬", func() -> void: set_local_space(not _giz.local_space))
	_pivot_btn.focus_mode = Control.FOCUS_NONE
	_space_btn.focus_mode = Control.FOCUS_NONE
	bar.add_child(VSeparator.new())
	var sl := Label.new()
	sl.text = "Ctrl 눈금"
	sl.tooltip_text = "Ctrl 을 누른 채 끌면 이 눈금으로 끊어 움직인다(유니티 증분 스냅)"
	sl.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.add_child(sl)
	for s in [["cm", 0.1, 50.0, 0.1, 1.0, "이동 눈금(cm)"], ["°", 1.0, 90.0, 1.0, 15.0, "회전 눈금(°)"], ["배", 0.01, 1.0, 0.01, 0.1, "크기 눈금(배율)"]]:
		var sp := SpinBox.new()
		sp.min_value = float(s[1])
		sp.max_value = float(s[2])
		sp.step = float(s[3])
		sp.value = float(s[4])
		sp.suffix = String(s[0])
		sp.tooltip_text = String(s[5])
		sp.custom_minimum_size = Vector2(76, 0)
		sp.value_changed.connect(func(_v: float) -> void: _apply_snap())
		bar.add_child(sp)
		_snap_sp.append(sp)
	# 무기 자리 — 모든 동작(기본 자리) ↔ 이 동작만(동작별 자리, 10-19)
	bar.add_child(VSeparator.new())
	var pl := Label.new()
	pl.text = "무기 자리"
	pl.tooltip_text = "기즈모 · 숫자 칸이 고치는 무기 자리 — 모든 동작(기본 자리) 또는 지금 동작만(동작별 자리)"
	pl.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.add_child(pl)
	var pg := ButtonGroup.new()
	for m in [[false, "모든 동작", "기본 자리 — 따로 자리를 안 둔 동작은 모두 이 자리.\n지금 동작에 따로 자리가 있으면 보이는 자리 = 기본 자리 + 그 차이(옮기면 기본 자리가 바뀌고 차이는 그대로)"],
			[true, "이 동작만", "지금 동작(동작 칸 · 오른쪽 표에서 고른 것)의 무기 자리만 — 기본 자리 · 다른 동작은 그대로. 위치 · 회전만(크기는 기본 자리 것)\n오른쪽 동작 표에서 행을 두 번 눌러도 된다. 게임에서는 동작이 바뀔 때 손 IK 비중과 함께 섞어 옮긴다"]]:
		var b := Button.new()
		b.text = String(m[1])
		b.toggle_mode = true
		b.button_group = pg
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = String(m[2])
		var on: bool = m[0]
		b.pressed.connect(func() -> void: set_per_motion(on))
		bar.add_child(b)
		_pm_btns.append(b)


## 도구 줄 단추 · 기즈모 칸을 지금 값으로
func _sync_gizmo_bar() -> void:
	if _giz == null:
		return
	for i in _tool_btns.size():
		_tool_btns[i].set_pressed_no_signal(i == _giz.tool_mode)
	_pivot_btn.text = "피벗" if _giz.pivot_mode else "중심"
	_space_btn.text = "로컬" if _giz.local_space else "글로벌"
	_apply_snap()
	_giz.queue_redraw()


func _apply_snap() -> void:
	if _giz == null or _snap_sp.size() < 3:
		return
	_giz.snap_move = _snap_sp[0].value / 100.0
	_giz.snap_rotate = _snap_sp[1].value
	_giz.snap_scale = _snap_sp[2].value


## 기즈모 도구(유니티 Q W E R Y)
func set_tool(t: int) -> void:
	if _giz.is_dragging():
		_giz.cancel_drag()
	_giz.tool_mode = t
	_sync_gizmo_bar()


func set_pivot_mode(on: bool) -> void:
	_giz.pivot_mode = on
	_sync_gizmo_bar()


func set_local_space(on: bool) -> void:
	_giz.local_space = on
	_sync_gizmo_bar()


## 기즈모를 걸 미리보기 노드 — 고른 장비 · 표지 · 고정 받침대(소켓은 뼈가, 두 손 사이 받침대는 두 손이 자리를 정하므로 없음)
func _gizmo_target() -> Node3D:
	var n := _node(_sel)
	if n == null or not (n is Node3D) or n is BoneAttachment3D:
		return null
	if n is DRGripMount3D and (n as DRGripMount3D).mode == DRGripMount3D.Mode.HANDS:
		return null
	return _prev_node(n) as Node3D


## 손 표지(크기가 뜻이 없음) — DRHandTarget3D 또는 장비 아래 이름이 "왼손" · "오른손" 인 Node3D(받침은 빼고)
static func _is_marker(n: Node) -> bool:
	return n is DRHandTarget3D or (n is Node3D and not _is_anchor(n) and DRCharacter3D.SIDE_NAMES.has(String(n.name)))


## 기즈모로 끄는 중 — 미리보기 사본만(왼손 IK 목표 · 숫자 칸이 따라온다). 유닛 씬은 놓을 때
func _on_giz_changed(pn: Node3D) -> void:
	if _prev != null:
		_prev.sync_support()
		_force_pose()
	_show_xform_of(pn)


## 기즈모를 놓았다 — 미리보기에서 옮긴 자리를 유닛 씬의 같은 노드에(에디터 = 되돌리기 한 칸 · Ctrl+Z).
## 장비: 이 동작만이면 그 동작의 동작별 자리로, 모든 동작이면 지금 얹힌 이 동작 차이를 빼고 기본 자리로(보이는 자리 = 기본 × 차이)
func _on_giz_end(pn: Node3D, _before: Transform3D) -> void:
	var n := _node(_sel) as Node3D
	if n == null or pn == null or _prev_node(n) != pn:
		return
	var after := pn.transform
	if _is_equip(n) and _prev != null:
		if _per_motion:
			var mo := current_motion()
			if mo == "":
				_set_status("동작을 고르세요 — 이 동작만 자리는 동작마다 저장된다")
				_sync_preview()
				return
			var what0 := String(TransformGizmo.TOOL_NAMES[_giz.tool_mode])
			set_motion_offset(n, mo, n.transform.affine_inverse() * after, "장비: %s %s 자리 %s(이 동작만)" % [n.name, mo, what0])
			_set_status("%s — %s 만 %s %s · %s" % [n.name, mo, what0, _offset_text(n, mo), "Ctrl+Z 로 되돌리기" if _editing() else "적용"])
			return
		after = after * _prev.get_equip_offset(pn).affine_inverse()
	if after.is_equal_approx(n.transform):
		_show_xform()
		return
	var what := String(TransformGizmo.TOOL_NAMES[_giz.tool_mode])
	_begin("장비: %s %s(기즈모)" % [n.name, what])
	_op_prop(n, "transform", after)
	_end(false)
	_set_status("%s %s — %s" % [n.name, what, "Ctrl+Z 로 되돌리기" if _editing() else "적용"])


## 미리보기를 눌렀다(끌지 않고) — 그 자리의 왼손 표지 · 소켓 · 장비를 고른다. 빈 곳 = 고르기 풀기(유니티와 같음)
func _on_view_click(pos: Vector2) -> void:
	if _prev == null or _root == null:
		return
	var pn := pick_in_preview(pos)
	var p := _prev.get_path_to(pn) if pn != null else NodePath()
	if pn == null or _root.get_node_or_null(p) == null:
		_sel = NodePath()
		_tree.deselect_all()
		_show_xform()
		_fill_motion_table()
		return
	_select_node(p)


## 화면 점 아래의 미리보기 노드 — 손 표지(14 px 안) → 받침(10 px 안) → 장비 메시(광선 ↔ 메시마다 로컬 경계 상자, 가장 가까운 것)
func pick_in_preview(pos: Vector2) -> Node3D:
	if _prev == null:
		return null
	var equips: Array[Node3D] = []
	for s in _prev.get_anchors():
		for c in s.get_children():
			if c is Node3D and (c as Node3D).visible:
				equips.append(c as Node3D)
	var best: Node3D = null
	var bd := 14.0
	for e in equips:
		for side in 2:
			var mk := DRCharacter3D.find_hand_marker(e, side)
			if mk != null and not _cam.is_position_behind(mk.global_position):
				var d := pos.distance_to(_cam.unproject_position(mk.global_position))
				if d < bd:
					bd = d
					best = mk
	if best != null:
		return best
	bd = 10.0
	for s in _prev.get_anchors():
		if not _cam.is_position_behind(s.global_position):
			var d := pos.distance_to(_cam.unproject_position(s.global_position))
			if d < bd:
				bd = d
				best = s
	if best != null:
		return best
	var ro := _cam.project_ray_origin(pos)
	var rd := _cam.project_ray_normal(pos)
	var near := INF
	for e in equips:
		var meshes: Array[Node] = [e]
		meshes.append_array(e.find_children("*", "MeshInstance3D", true, false))
		for m in meshes:
			var mi := m as MeshInstance3D
			if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var inv := mi.global_transform.affine_inverse()
			var hit: Variant = mi.get_aabb().intersects_ray(inv * ro, inv.basis * rd)
			if hit == null:
				continue
			var dist := ro.distance_to(mi.global_transform * (hit as Vector3))
			if dist < near:
				near = dist
				best = e
	return best


## F — 고른 것을 화면 가운데로(장비 = 메시 경계 상자가 들어오게, 표지 · 소켓 = 가까이). 없으면 두 손
func frame_selected() -> void:
	var n := _node(_sel)
	var pn := _prev_node(n) as Node3D if n != null else null
	if pn == null:
		focus_hands()
		return
	var bb := TransformGizmo.world_aabb(pn)
	if bb.size == Vector3.ZERO:
		_target = pn.global_position
		_dist = 0.6
	else:
		_target = bb.get_center()
		_dist = clampf(bb.size.length() * 1.5, 0.4, 6.0)
	_update_cam()


## 탭 창의 단축키(유니티와 같음) — 칸에 글자를 치는 중이면 칸이 먼저 먹으므로 여기 안 온다
func _unhandled_key_input(ev: InputEvent) -> void:
	var k := ev as InputEventKey
	if k == null or not k.pressed or k.echo or not _active or not is_visible_in_tree():
		return
	if k.ctrl_pressed or k.meta_pressed:
		match k.keycode:
			KEY_Z:
				_editor_undo(not k.shift_pressed)
			KEY_Y:
				_editor_undo(false)
			KEY_S:
				save_unit()
			_:
				return
		get_viewport().set_input_as_handled()
		return
	if k.alt_pressed:
		return
	match k.keycode:
		KEY_Q:
			set_tool(TransformGizmo.Tool.VIEW)
		KEY_W:
			set_tool(TransformGizmo.Tool.MOVE)
		KEY_E:
			set_tool(TransformGizmo.Tool.ROTATE)
		KEY_R:
			set_tool(TransformGizmo.Tool.SCALE)
		KEY_Y:
			set_tool(TransformGizmo.Tool.TRANSFORM)
		KEY_X:
			set_local_space(not _giz.local_space)
		KEY_Z:
			set_pivot_mode(not _giz.pivot_mode)
		KEY_F:
			frame_selected()
		KEY_ESCAPE:
			if not _giz.is_dragging():
				return
			_giz.cancel_drag()
		_:
			return
	get_viewport().set_input_as_handled()


## Ctrl+Z · Ctrl+Y — 탭 창에서도 유닛 씬의 되돌리기(에디터 창과 같은 기록). EditorUndoRedoManager 에는 스크립트용 undo() 가 없어
## 그 씬 기록의 UndoRedo 를 바로 부른다(에디터 창 Undo 알림의 이름만 한 칸 어긋날 수 있음 — 되돌리는 차례는 같다)
func _editor_undo(undo: bool) -> void:
	if not _editing():
		return
	var m := EditorInterface.get_editor_undo_redo()
	var ur := m.get_history_undo_redo(m.get_object_history_id(_root))
	if ur == null:
		return
	var nm := ur.get_current_action_name()
	var ok := ur.undo() if undo else ur.redo()
	if not undo:
		nm = ur.get_current_action_name()
	_follow_root()
	_set_status(("되돌림: %s" if undo else "다시: %s") % nm if ok else ("되돌릴 것 없음" if undo else "다시 할 것 없음"))


## 도트 보기에 게임과 같은 도트 · 외곽선 값(DRDotStyle.load_default().apply_to). 명암(재질 공통)은 게임 화면 · ① 탭이 넣으므로 건드리지 않는다
func _apply_dot_style() -> void:
	DRDotStyle.load_default().apply_to(_dots)    # 게임 · ① ③ 탭과 같은 도트 느낌(game/dot_style.tres)


func _btn(parent: Control, text: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _set_status(t: String) -> void:
	_status.text = t


# ───────────── 유닛 ─────────────

## game/units 의 유닛 씬(루트가 DRCharacter3D 이거나 유닛을 상속한 씬)
func scan_units() -> void:
	_units = {}
	var infos := {}
	var d := DirAccess.open(UNITS_DIR)
	if d != null:
		for f in d.get_files():
			if String(f).get_extension() == "tscn":
				var p := UNITS_DIR.path_join(String(f))
				var inf := DRUnitPage.scene_info(p)
				if not inf.is_empty():
					infos[p] = inf
	for p in infos.keys():
		var q := String(p)
		for i in 16:
			if not infos.has(q):
				break
			if bool((infos[q] as Dictionary)["is_char"]):
				_units[p] = infos[p]
				break
			q = String((infos[q] as Dictionary)["parent"])
	_unit_ob.clear()
	var keys := _units.keys()
	keys.sort()
	for p in keys:
		var inf: Dictionary = _units[p]
		_unit_ob.add_item("%s   (%s)" % [inf["name"], String(p).get_file()])
		_unit_ob.set_item_metadata(_unit_ob.item_count - 1, p)
		_unit_ob.set_item_tooltip(_unit_ob.item_count - 1, String(p) + ("\n부모: " + String(inf["parent"]) if String(inf["parent"]) != "" else ""))
		if p == _sel_path:
			_unit_ob.select(_unit_ob.item_count - 1)


## 그 유닛을 고른다 — 에디터면 그 씬을 에디터에 열고 열린 루트를 고친다(씬 독 · 인스펙터와 같은 노드)
func select_unit(path: String) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	_drop_root()
	_sel_path = path
	_sel = NodePath()
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
	for i in _unit_ob.item_count:
		if String(_unit_ob.get_item_metadata(i)) == path:
			_unit_ob.select(i)
	if _root == null:
		_set_status("⚠ 유닛 루트가 DRCharacter3D 가 아닙니다: " + path)
		return
	_base_paths = _collect_base_paths(path)
	_refresh_all()
	var w := _weapon_equip()
	if w != null:
		_select_node(_root.get_path_to(w))
	_set_status("%s — 소켓 %d개%s" % [path.get_file(), _sockets().size(), " · 부모 유닛에서 온 노드는 지울 수 없어 숨긴다" if not _base_paths.is_empty() else ""])


func _drop_root() -> void:
	if _owns_root and _root != null and is_instance_valid(_root):
		_root.free()
	_root = null
	_owns_root = false


## 부모 유닛 씬(상속이면)에서 온 노드 경로들 — 부모 씬을 트리 밖에서 만들어(조립 안 함) 그 씬이 가진 노드를 모은다
func _collect_base_paths(path: String) -> Dictionary:
	var out := {}
	var par := String((_units.get(path, {}) as Dictionary).get("parent", ""))
	if par == "" or not ResourceLoader.exists(par):
		return out
	var inst := (load(par) as PackedScene).instantiate()
	var stack: Array[Node] = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == inst or n.owner == inst:
			out[String(inst.get_path_to(n))] = true
		stack.append_array(n.get_children())
	inst.free()
	return out


func _is_inherited(n: Node) -> bool:
	return _base_paths.has(String(_root.get_path_to(n)))


## 유닛의 받침(루트가 가진 소켓 BoneAttachment3D · 받침대 DRGripMount3D — 안에서 조립한 몸은 주인이 없어 빠진다)
func _anchors() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if _root == null:
		return out
	for a in DRCharacter3D.find_anchors(_root):
		if a.owner == _root:
			out.append(a)
	return out


## 유닛의 소켓만(뼈 받침)
func _sockets() -> Array[BoneAttachment3D]:
	var out: Array[BoneAttachment3D] = []
	for a in _anchors():
		if a is BoneAttachment3D:
			out.append(a as BoneAttachment3D)
	return out


static func _is_anchor(n: Node) -> bool:
	return n is BoneAttachment3D or n is DRGripMount3D


## 받침의 보이는 장비(첫 것)
static func _equip_of(s: Node) -> Node3D:
	for c in s.get_children():
		if c is Node3D and (c as Node3D).visible:
			return c as Node3D
	return null


## 무기 — 손 표지가 있는 장비가 먼저(받침 어디든), 없으면 오른손 소켓의 장비
func _weapon_equip() -> Node3D:
	var fallback: Node3D = null
	for a in _anchors():
		for c in a.get_children():
			var e := c as Node3D
			if e == null or not e.visible:
				continue
			if DRCharacter3D.find_hand_marker(e, 0) != null or DRCharacter3D.find_hand_marker(e, 1) != null:
				return e
			if fallback == null and a is BoneAttachment3D and (a as BoneAttachment3D).bone_name == DRCharacter3D.WEAPON_BONE:
				fallback = e
	return fallback


func _node(p: NodePath) -> Node:
	if _root == null or p.is_empty():
		return null
	return _root.get_node_or_null(p)


## 고른 노드가 든 받침(고른 것이 받침이면 그것, 장비 · 표지면 위로 올라가며)
func _socket_of(n: Node) -> Node3D:
	while n != null and n != _root:
		if _is_anchor(n):
			return n as Node3D
		n = n.get_parent()
	return null


## 고른 노드가 속한 장비(받침 바로 아래 노드)
func _equip_from(n: Node) -> Node3D:
	while n != null and n != _root:
		if _is_anchor(n.get_parent()):
			return n as Node3D
		n = n.get_parent()
	return null


## 장비의 잡는 방식 — 0 = 오른손(무기가 오른손을 따라감) · 1 = 왼손 · 2 = 양손(두 손 사이 받침대) · 3 = 고정(땅 받침대) · 4 = 그 밖의 뼈(머리 · 가슴 …) · -1 = 없음
static func grip_kind(e: Node) -> int:
	var a := e.get_parent() if e != null else null
	if a is DRGripMount3D:
		return 2 if (a as DRGripMount3D).mode == DRGripMount3D.Mode.HANDS else 3
	if a is BoneAttachment3D:
		var b := (a as BoneAttachment3D).bone_name
		return 0 if b == DRCharacter3D.HAND_BONES[1] else (1 if b == DRCharacter3D.HAND_BONES[0] else 4)
	return -1


# ───────────── 나무 · 칸 ─────────────

func _refresh_all() -> void:
	_fill_tree()
	_rebuild_preview()
	_struct_sig = _make_struct_sig()
	_xform_sig = _make_xform_sig()
	_show_xform()
	_show_aim_settings()


func _fill_tree() -> void:
	_tree.clear()
	var top := _tree.create_item()
	if _root == null:
		return
	for s in _anchors():
		var si := _tree.create_item(top)
		if s is DRGripMount3D:
			var gm := s as DRGripMount3D
			var hands := gm.mode == DRGripMount3D.Mode.HANDS
			si.set_text(0, "⚓ %s  (%s)" % [s.name, ("양손 — 두 손 사이 %d%%" % int(round(gm.blend * 100.0))) if hands else "고정 — 유닛(땅) 기준"])
			si.set_tooltip_text(0, ("받침대(DRGripMount3D) — 두 손 사이(오른손 ↔ 왼손 %d%%)에 고정, 두 손이 표지에 IK" % int(round(gm.blend * 100.0)) if hands
				else "받침대(DRGripMount3D) — 유닛(땅)에 고정(라페테 MG42 등), 두 손이 표지에 IK") + (" · 부모 유닛에서 옴" if _is_inherited(s) else ""))
		else:
			var bs := s as BoneAttachment3D
			si.set_text(0, "🦴 %s  (뼈 %s)" % [s.name, bs.bone_name])
			si.set_tooltip_text(0, "소켓(BoneAttachment3D) — 뼈 %s 를 따라간다%s" % [bs.bone_name, " · 부모 유닛에서 옴" if _is_inherited(s) else ""])
		si.set_metadata(0, _root.get_path_to(s))
		for c in s.get_children():
			if not (c is Node3D):
				continue
			var e := c as Node3D
			var ei := _tree.create_item(si)
			var src := e.scene_file_path.get_file() if e.scene_file_path != "" else e.get_class()
			var po := DRCharacter3D.motion_offsets(e).size()
			ei.set_text(0, "%s%s  (%s)%s" % ["⊘ " if not e.visible else "", e.name, src, "  · 동작별 자리 %d" % po if po > 0 else ""])
			ei.set_metadata(0, _root.get_path_to(e))
			ei.set_tooltip_text(0, "장비%s%s%s" % [" — 숨김(게임에서는 지운다)" if not e.visible else "", " · 부모 유닛에서 옴" if _is_inherited(e) else "",
				"\n동작별 자리: " + ", ".join(PackedStringArray(DRCharacter3D.motion_offsets(e).keys())) if po > 0 else ""])
			if not e.visible:
				ei.set_custom_color(0, Color(0.55, 0.57, 0.6))
			var kind := grip_kind(e)
			for side in 2:
				var m := DRCharacter3D.find_hand_marker(e, side)
				if m == null:
					continue
				var side_name := String(DRCharacter3D.SIDE_NAMES[side])
				var idle := kind == (1 if side == 0 else 0)            # 받침이 그 손 — 무기가 그 손을 따라가므로 이 표지는 안 쓴다
				var mi := _tree.create_item(ei)
				mi.set_text(0, "✋ %s  (%s 표지%s%s)" % [m.name, side_name, "" if m is DRHandTarget3D else " — 비중 없는 Marker3D", " — 쉼: 받침이 " + side_name if idle else ""])
				mi.set_metadata(0, _root.get_path_to(m))
				mi.set_tooltip_text(0, "%s IK 목표: 원점 = 손바닥 자리, 회전 = 그 손 뼈 회전%s" % [side_name, "\n무기가 이 손 소켓에 있어 이 손은 IK 안 함(무기가 따라감)" if idle else ""])
				if idle:
					mi.set_custom_color(0, Color(0.55, 0.57, 0.6))
	for it in _all_items(top):
		if (it.get_metadata(0) as NodePath) == _sel:
			it.select(0)


func _all_items(it: TreeItem) -> Array[TreeItem]:
	var out: Array[TreeItem] = []
	var c := it.get_first_child()
	while c != null:
		out.append(c)
		out.append_array(_all_items(c))
		c = c.get_next()
	return out


func _on_tree_selected() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	_sel = it.get_metadata(0) as NodePath
	_show_xform()
	_fill_motion_table()


func _select_node(p: NodePath) -> void:
	_sel = p
	for it in _all_items(_tree.get_root()):
		if (it.get_metadata(0) as NodePath) == p:
			it.select(0)
	_show_xform()
	_fill_motion_table()


func _fill_bones(names: PackedStringArray) -> void:
	_bone_ob.clear()
	for b in BONE_CHOICES:
		_bone_ob.add_item(String(b[1]))
		_bone_ob.set_item_metadata(_bone_ob.item_count - 1, String(b[0]))
	if not names.is_empty():
		_bone_ob.add_separator("몸의 모든 뼈")
		for n in names:
			_bone_ob.add_item(n)
			_bone_ob.set_item_metadata(_bone_ob.item_count - 1, n)
	_bone_ob.select(0)


func _fill_models() -> void:
	_model_ob.clear()
	for p in DREquipHold.list_models():
		var hold := not DREquipHold.read_hold(DREquipHold.asset_for_model(p)).is_empty()
		_model_ob.add_item("%s%s" % [p.trim_prefix("res://source3d/"), "  ★기본 자리" if hold else ""])
		_model_ob.set_item_metadata(_model_ob.item_count - 1, p)
		_model_ob.set_item_tooltip(_model_ob.item_count - 1, p + ("\n무기 기본 자리(asset.json socket_hold) 있음" if hold else ""))
	_model_ob.add_item(DREquipHold.PLACEHOLDER_HELMET)
	_model_ob.set_item_metadata(_model_ob.item_count - 1, DREquipHold.PLACEHOLDER_HELMET)
	if _model_ob.item_count > 0:
		_model_ob.select(0)


## 숫자 칸 — 고른 노드(부모 기준). 이 동작만 + 장비면 그 동작의 자리(미리보기 사본 = 기본 × 동작별 자리)
func _show_xform() -> void:
	var n := _node(_sel) as Node3D
	if _per_motion and _is_equip(n) and _prev_node(n) is Node3D:
		_show_xform_of(_prev_node(n) as Node3D)
		_xf_title.text = "%s — %s 만(부모 %s 기준)" % [n.name, current_motion() if current_motion() != "" else "동작 없음", n.get_parent().name]
		for sp in _scl:
			sp.editable = false                  # 동작별 자리는 위치 · 회전만
	else:
		_show_xform_of(n)
	_update_grip_ui()
	_update_pm_ui()


const GRIP_NAMES := ["오른손", "왼손", "양손", "고정", "뼈"]


## 잡기 줄 — 고른 장비(없으면 무기)의 받침 방식 단추 · 양손 보간 · 손마다 무엇을 하나
func _update_grip_ui() -> void:
	if _grip_btns.is_empty():
		return
	var e := _equip_from(_node(_sel))
	if e == null:
		e = _weapon_equip()
	var kind := grip_kind(e) if e != null else -1
	for i in _grip_btns.size():
		_grip_btns[i].set_pressed_no_signal(i == kind)
		_grip_btns[i].disabled = e == null
	var gm := e.get_parent() as DRGripMount3D if e != null else null
	var hands := gm != null and gm.mode == DRGripMount3D.Mode.HANDS
	_blend_sl.get_parent().visible = hands
	if hands:
		_blend_sl.set_value_no_signal(gm.blend)
		_blend_lbl.text = "보간 오른손 %d%% · 왼손 %d%%" % [int(round((1.0 - gm.blend) * 100.0)), int(round(gm.blend * 100.0))]
	if e == null:
		_grip_info.text = "장비(무기)를 고르세요"
		return
	var hand_txt := PackedStringArray()
	for side in 2:
		var nm := String(DRCharacter3D.SIDE_NAMES[side])
		if kind == (1 if side == 0 else 0):
			hand_txt.append("%s = 무기를 듦(받침)" % nm)
		elif DRCharacter3D.find_hand_marker(e, side) != null:
			hand_txt.append("%s = 표지를 따라감(IK)" % nm)
		else:
			hand_txt.append("%s = 동작 그대로(표지 없음)" % nm)
	var where := ""
	match kind:
		0, 1:
			where = "%s 소켓" % GRIP_NAMES[kind]
		2:
			where = "두 손 사이 받침대(%s)" % e.get_parent().name
		3:
			where = "유닛(땅) 고정 받침대(%s)" % e.get_parent().name
		_:
			where = "뼈 %s 소켓" % ((e.get_parent() as BoneAttachment3D).bone_name if e.get_parent() is BoneAttachment3D else "-")
	_grip_info.text = "%s — %s · %s" % [e.name, where, " · ".join(hand_txt)]


## 양손 받침대의 보간(0 = 오른손 쪽 · 1 = 왼손 쪽) — 슬라이더
func set_blend(v: float) -> void:
	var e := _equip_from(_node(_sel))
	if e == null:
		e = _weapon_equip()
	var gm := e.get_parent() as DRGripMount3D if e != null else null
	if gm == null or gm.mode != DRGripMount3D.Mode.HANDS:
		return
	_set_props_merged("장비: 양손 보간", [[gm, "blend", clampf(v, 0.0, 1.0)]])


## 고른 장비를 어디에 고정할지(조인트 느낌 — 사용자 10-16) — 0 = 오른손 · 1 = 왼손 · 2 = 양손(두 손 사이 받침대) · 3 = 고정(땅 받침대).
## 지금 미리보기 자세에서 장비가 보이는 자리 그대로 받침만 바꾸고(유니티 "자리 유지하며 부모 바꾸기"), 따라갈 손의 표지가 없으면
## 그 손의 지금 자리로 만든다(손이 튀지 않게). 받침이 없으면 만든다(같은 방식의 빈 받침대는 다시 씀). 되돌리기 한 칸
func set_grip(kind: int) -> void:
	var e := _equip_from(_node(_sel))
	if e == null:
		e = _weapon_equip()
	var pe := _prev_node(e) as Node3D
	if e == null or pe == null or _prev == null or kind < 0 or kind > 3:
		_set_status("잡기를 바꿀 장비(무기)를 고르세요")
		return
	if grip_kind(e) == kind:
		_update_grip_ui()
		return
	if _is_inherited(e):
		_set_status("부모 유닛에서 온 장비는 받침을 바꿀 수 없습니다 — 이 유닛에 장비를 넣고(부모 것은 숨김) 바꾸세요")
		_update_grip_ui()
		return
	var follow: Array = [[0], [1], [0, 1], [0, 1]][kind]
	var new_marks := {}                                    # 따라갈 손인데 표지가 없으면 — 지금 그 손 자리(장비 기준, 받침을 바꿔도 같다)
	for side in follow:
		if DRCharacter3D.find_hand_marker(e, side) == null:
			var hx: Variant = _hand_xform_on(e, side)
			if hx != null:
				new_marks[side] = hx
	_force_pose()
	var sk := _prev.get_skeleton()
	var root_inv := _prev.global_transform.affine_inverse()
	var e_unit := root_inv * pe.global_transform           # 지금 보이는 자리(유닛 기준)
	var anchor: Node3D = null
	var make := false
	if kind <= 1:
		var bone := String(DRCharacter3D.HAND_BONES[1 if kind == 0 else 0])
		for s in _sockets():
			if s.bone_name == bone:
				anchor = s
				break
		if anchor == null:
			var s := BoneAttachment3D.new()
			s.name = _unique_name("오른손" if kind == 0 else "왼손소켓")
			s.bone_name = bone
			s.use_external_skeleton = true
			anchor = s
			make = true
	else:
		var mode := DRGripMount3D.Mode.HANDS if kind == 2 else DRGripMount3D.Mode.FIXED
		for a in _anchors():
			if a is DRGripMount3D and (a as DRGripMount3D).mode == mode and _equip_of(a) == null:
				anchor = a                                 # 비어 있는 같은 방식 받침대는 다시 쓴다
				break
		if anchor == null:
			var m := DRGripMount3D.new()
			m.name = _unique_name("양손" if kind == 2 else "고정")
			m.mode = mode
			anchor = m
			make = true
	var a_unit := Transform3D.IDENTITY
	var props := {}
	if anchor is BoneAttachment3D:
		a_unit = root_inv * sk.global_transform * sk.get_bone_global_pose(sk.find_bone((anchor as BoneAttachment3D).bone_name))
	else:
		a_unit = Transform3D(e_unit.basis.orthonormalized(), e_unit.origin)     # 받침대 = 장비가 지금 있는 자리(배율 뺌) — 장비 로컬엔 배율만
		props["transform"] = a_unit
		if kind == 2:                                       # 맞춘 자세: 두 손 쪽 자리가 지금 받침대 자리와 같게
			var g := _prev.global_transform * a_unit
			props["right_offset"] = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(String(DRCharacter3D.HAND_BONES[1])))).affine_inverse() * g
			props["left_offset"] = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(String(DRCharacter3D.HAND_BONES[0])))).affine_inverse() * g
	var e_local := a_unit.affine_inverse() * e_unit
	_begin("장비: %s 잡기 = %s" % [e.name, GRIP_NAMES[kind]])
	if make:
		for k in props.keys():
			anchor.set(k, props[k])
		if _ur != null:
			_ur.add_do_method(_root, "add_child", anchor, true)
			_ur.add_do_method(anchor, "set_owner", _root)
			_ur.add_do_reference(anchor)
		else:
			_root.add_child(anchor, true)
			anchor.owner = _root
	else:
		for k in props.keys():
			_op_prop(anchor, k, props[k])
	_op_reparent(e, anchor, e_local)
	for side in new_marks.keys():
		var mk := _new_marker(new_marks[side], {}, int(side))
		_op_add(e, mk, [mk])
	if make and _ur != null:
		_ur.add_undo_method(_root, "remove_child", anchor)  # 장비를 원래 받침으로 되돌린 다음에(되돌리기는 넣은 차례대로 돈다)
	_end(true)
	_select_node(_root.get_path_to(e))
	_set_status("%s 잡기 = %s%s%s" % [e.name, GRIP_NAMES[kind], " · 새 받침 %s" % anchor.name if make else "",
		" · 새 표지 %s" % ", ".join(new_marks.keys().map(func(s): return String(DRCharacter3D.SIDE_NAMES[s]))) if not new_marks.is_empty() else ""])


## 루트 아래에서 안 겹치는 이름
func _unique_name(base: String) -> String:
	var nm := base
	var i := 2
	while _root.has_node(NodePath(nm)):
		nm = "%s%d" % [base, i]
		i += 1
	return nm


## 부모 바꾸기(자리 = local) — 주인은 그대로(reparent 가 지킨다). 되돌리기 = 원래 부모 · 차례 · 자리
func _op_reparent(n: Node3D, parent: Node, local: Transform3D) -> void:
	var old_parent := n.get_parent()
	var old_local := n.transform
	var idx := n.get_index()
	if _ur != null:
		_ur.add_do_method(n, "reparent", parent, false)
		_ur.add_do_property(n, "transform", local)
		_ur.add_undo_method(n, "reparent", old_parent, false)
		_ur.add_undo_method(old_parent, "move_child", n, idx)
		_ur.add_undo_property(n, "transform", old_local)
	else:
		n.reparent(parent, false)
		n.transform = local


## 숫자 칸에 노드 n 의 자리 · 회전 · 크기(부모 기준) — 기즈모로 끄는 중에는 미리보기 사본 노드(같은 부모 기준이라 값이 같다)
func _show_xform_of(n: Node3D) -> void:
	_xf_lock = true
	var on := n != null and not (n is BoneAttachment3D)
	for sp in _pos + _rot:
		sp.editable = on
	for sp in _scl:
		sp.editable = on and not _is_marker(n)
	if n == null:
		_xf_title.text = "고른 노드 — 없음(나무 · 미리보기에서 장비 · 표지를 고르세요)"
	elif n is BoneAttachment3D:
		_xf_title.text = "소켓 %s — 뼈를 따라가므로 자리는 장비 · 표지에서" % n.name
	else:
		_xf_title.text = "%s — 부모(%s) 기준" % [n.name, n.get_parent().name]
		for k in 3:
			_pos[k].set_value_no_signal(snappedf(n.position[k] * 100.0, 0.01))
			_rot[k].set_value_no_signal(snappedf(n.rotation_degrees[k], 0.01))
			_scl[k].set_value_no_signal(snappedf(n.scale[k], 0.001))
	_xf_lock = false


func _on_xf_changed() -> void:
	if _xf_lock:
		return
	var n := _node(_sel) as Node3D
	if n == null or n is BoneAttachment3D:
		return
	var p := Vector3(_pos[0].value, _pos[1].value, _pos[2].value) / 100.0
	var r := Vector3(_rot[0].value, _rot[1].value, _rot[2].value)
	if _per_motion and _is_equip(n):           # 이 동작만 — 칸 값 = 그 동작의 자리(크기는 기본 자리 것) → 동작별 자리
		var mo := current_motion()
		if mo == "":
			return
		var tmp := Node3D.new()                # Node3D 와 같은 오일러 순서 · 크기 곱으로 변환을 만든다
		tmp.position = p
		tmp.rotation_degrees = r
		tmp.scale = n.scale
		var l := tmp.transform
		tmp.free()
		var d := DRCharacter3D.motion_offsets(n).duplicate()
		var off := _rigid(n.transform.affine_inverse() * l)
		if off.is_equal_approx(Transform3D.IDENTITY):
			d.erase(mo)
		else:
			d[mo] = off
		_set_offsets(n, d, "장비: %s %s 자리(이 동작만)" % [n.name, mo], true)
		return
	var changes := [[n, "position", p], [n, "rotation_degrees", r]]
	var s := Vector3(_scl[0].value, _scl[1].value, _scl[2].value)
	if not _is_marker(n) and not s.is_equal_approx(n.scale.snapped(Vector3.ONE * 0.001)):
		changes.append([n, "scale", s])     # 크기 칸을 안 건드렸으면 넣지 않는다(칸의 반올림 값으로 덮지 않게)
	_set_props_merged("장비: %s 자리" % n.name, changes)


# ───────────── 고치기(에디터 = 되돌리기 한 칸 · 밖 = 바로) ─────────────

func _editing() -> bool:
	return Engine.is_editor_hint() and _root != null and _root.is_inside_tree()


func _begin(label: String) -> void:
	_ur = null
	if _editing():
		_ur = EditorInterface.get_editor_undo_redo()
		_ur.create_action(label, UndoRedo.MERGE_DISABLE, _root)


func _end(structural: bool) -> void:
	if _ur != null:
		_ur.commit_action()
		_ur = null
	_after_change(structural)


func _op_prop(obj: Object, prop: String, value: Variant) -> void:
	if _ur != null:
		_ur.add_do_property(obj, prop, value)
		_ur.add_undo_property(obj, prop, obj.get(prop))
	else:
		obj.set(prop, value)


## node(아래에 owned 노드들) 를 parent 아래에 — 주인 = 유닛 루트(씬에 저장)
func _op_add(parent: Node, node: Node, owned: Array) -> void:
	if _ur != null:
		_ur.add_do_method(parent, "add_child", node, true)
		for n in owned:
			_ur.add_do_method(n, "set_owner", _root)
		_ur.add_do_reference(node)
		_ur.add_undo_method(parent, "remove_child", node)
	else:
		parent.add_child(node, true)
		for n in owned:
			(n as Node).owner = _root


func _op_remove(node: Node) -> void:
	var parent := node.get_parent()
	var owned: Array = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.owner == _root:
			owned.append(n)
		stack.append_array(n.get_children())
	if _ur != null:
		_ur.add_do_method(parent, "remove_child", node)
		_ur.add_undo_method(parent, "add_child", node, true)
		_ur.add_undo_method(parent, "move_child", node, node.get_index())
		for n in owned:
			_ur.add_undo_method(n, "set_owner", _root)
		_ur.add_undo_reference(node)
	else:
		parent.remove_child(node)
		node.queue_free()


## 숫자 칸처럼 잇달아 바뀌는 값 — 에디터에서는 같은 이름이면 되돌리기 한 칸으로 합친다
func _set_props_merged(label: String, changes: Array) -> void:
	if _editing():
		var ur := EditorInterface.get_editor_undo_redo()
		ur.create_action(label, UndoRedo.MERGE_ENDS, _root)
		for c in changes:
			ur.add_do_property(c[0], c[1], c[2])
			ur.add_undo_property(c[0], c[1], (c[0] as Object).get(c[1]))
		ur.commit_action()
	else:
		for c in changes:
			(c[0] as Object).set(c[1], c[2])
	_after_change(false)


## 고친 뒤: 편집 중인 유닛을 다시 잇고(조립돼 있으면) · 나무 · 미리보기(구조가 바뀌면 다시 조립, 자리만이면 사본 노드만 옮김)
func _after_change(structural: bool) -> void:
	if _root != null and _root.is_inside_tree():
		_root.refresh_equipment()
	_fill_tree()
	if structural:
		_rebuild_preview()
	else:
		_sync_preview()
	_struct_sig = _make_struct_sig()
	_xform_sig = _make_xform_sig()
	_show_xform()
	_show_aim_settings()


## 소켓 더하기 — 유닛 씬에 BoneAttachment3D(use_external_skeleton — 뼈대는 DRCharacter3D 가 조립 뒤 이어 준다)
func add_socket(display_name: String, bone: String) -> BoneAttachment3D:
	if _root == null or bone == "":
		_set_status("유닛과 뼈를 고르세요")
		return null
	var nm := display_name.strip_edges()
	if nm == "":
		nm = bone
		for b in BONE_CHOICES:
			if String(b[0]) == bone:
				nm = String(b[2])
	for ch in [".", ":", "@", "/", "\"", "%"]:
		nm = nm.replace(ch, "_")
	var s := BoneAttachment3D.new()
	s.name = nm
	s.bone_name = bone
	s.use_external_skeleton = true
	_begin("장비: 소켓 더하기 %s" % nm)
	_op_add(_root, s, [s])
	_end(true)
	_sock_name.text = ""
	_select_node(_root.get_path_to(s))
	_set_status("소켓 %s(뼈 %s) — 이제 장비를 넣으세요" % [s.name, bone])
	return s


## 고른 소켓(또는 고른 장비 · 표지의 소켓)에 모델을 넣는다. 이미 장비가 있으면 바꾼다(부모에서 온 것은 숨김).
## 모델 옆 asset.json 에 무기 기본 자리(socket_hold)가 있고 뼈가 같으면 그 자리 · 왼손 표지 · 동작별 비중으로
func put_model(model_path: String) -> Node3D:
	if _root == null or model_path == "":
		return null
	var sock := _socket_of(_node(_sel))
	if sock == null:
		var socks := _anchors()
		sock = socks[0] if not socks.is_empty() else null
	if sock == null:
		_set_status("소켓이 없습니다 — 먼저 [+ 소켓]")
		return null
	var n := DREquipHold.instantiate_model(model_path)
	if n == null:
		_set_status("모델을 열 수 없습니다: " + model_path)
		return null
	var owned: Array = [n]
	var hold := DREquipHold.read_hold(DREquipHold.asset_for_model(model_path))
	var used_hold := false
	if not hold.is_empty() and sock is BoneAttachment3D and String(hold["bone"]) == (sock as BoneAttachment3D).bone_name:
		n.transform = hold["weapon"]
		if hold.has("support"):
			var mk := _new_marker(hold["support"], hold["motion_weights"])
			n.add_child(mk)
			owned.append(mk)
		if not (hold["motion_offsets"] as Dictionary).is_empty():
			n.set_meta(DRCharacter3D.MOTION_OFFSETS_META, (hold["motion_offsets"] as Dictionary).duplicate())   # 동작별 자리(무기 축 기준 — 받침이 같으니 그대로)
		used_hold = true
	_begin("장비: %s 넣기" % n.name)
	for c in sock.get_children():
		if c is Node3D and (c as Node3D).visible:
			if _is_inherited(c):
				_op_prop(c, "visible", false)     # 부모 유닛에서 온 장비 — 지울 수 없어 숨긴다(게임에서는 지운다)
			else:
				_op_remove(c)
	_op_add(sock, n, owned)
	_end(true)
	_select_node(_root.get_path_to(n))
	_set_status("%s 를 소켓 %s 에 넣음%s" % [n.name, sock.name, " — 무기 기본 자리(asset.json) 그대로" if used_hold else " — 기본 자리가 없어 소켓 원점. [지금 동작으로 무기 맞추기] → [지금 자세로 왼손 표지]"])
	return n


## 장비(e) 기준 변환 xf 를 n 의 부모 기준으로(표지가 장비 바로 아래가 아니라 모델 씬 속에 있어도 맞게)
static func _in_parent_of(n: Node3D, e: Node3D, xf: Transform3D) -> Transform3D:
	return DREquipHold.xform_to(e, n.get_parent()).affine_inverse() * xf


func _new_marker(xf: Transform3D, weights: Dictionary, side: int = 0) -> DRHandTarget3D:
	var mk := DRHandTarget3D.new()
	mk.name = String(DRCharacter3D.SIDE_NAMES[side])
	mk.side = side
	mk.transform = xf
	var mw: Dictionary[String, float] = {}
	for k in weights.keys():
		mw[String(k)] = float(weights[k])
	mk.motion_weights = mw
	return mk


## 고른 장비(소켓이면 그 장비 · 표지면 그 표지)를 뺀다 — 부모 유닛에서 온 것은 숨긴다
func remove_selected() -> void:
	var n := _node(_sel)
	if n == null or n == _root:
		_set_status("뺄 장비 · 소켓 · 표지를 나무에서 고르세요")
		return
	var nm := String(n.name)
	var inherited := _is_inherited(n)
	_begin("장비: %s 빼기" % nm)
	if inherited:
		_op_prop(n, "visible", false)
	else:
		_op_remove(n)
	_sel = NodePath()
	_end(true)
	_set_status("%s %s" % [nm, "숨김(부모 유닛에서 옴 — 게임에서는 지운다)" if inherited else "뺌"])


## 미리보기의 지금 동작 · 시점에서 왼손(동작 그대로 — IK 전) 자리 · 회전을 고른 장비의 왼손 표지로(없으면 만든다)
func make_support_marker() -> Node3D:
	return make_hand_marker(0)


## 그 손(0 = 왼손 · 1 = 오른손)의 지금 동작 · 시점 자리 · 회전(동작 그대로 — IK 전)을 고른 장비의 그 손 표지로(없으면 만든다)
func make_hand_marker(side: int) -> Node3D:
	var e := _equip_from(_node(_sel))
	if e == null:
		e = _weapon_equip()
	var m: Variant = _hand_xform_on(e, side)
	if m == null:
		_set_status("장비(무기)를 고르세요")
		return null
	var nm := String(DRCharacter3D.SIDE_NAMES[side])
	var cur := DRCharacter3D.find_hand_marker(e, side)
	var added := false
	_begin("장비: %s 표지" % nm)
	if cur != null and cur.owner == _root:
		_op_prop(cur, "transform", _in_parent_of(cur, e, m))
	else:
		var mk := _new_marker(m, {}, side)
		_op_add(e, mk, [mk])
		cur = mk
		added = true
	_end(added)
	_select_node(_root.get_path_to(cur))
	_set_status("%s 표지 = %s %d%% 의 %s(동작 그대로)%s" % [nm, current_motion(), int(_time_sl.value * 100.0), nm,
		" — 지금은 무기가 %s 을 따라가 쉬는 표지(잡기를 바꾸면 씀)" % nm if grip_kind(e) == (1 if side == 0 else 0) else ""])
	return cur


## 지금 미리보기 자세에서 그 손바닥 자리 · 손 회전을 장비 e 기준으로(손 표지 자리) — 못 구하면 null
func _hand_xform_on(e: Node3D, side: int) -> Variant:
	var pe := _prev_node(e) as Node3D
	if e == null or pe == null or _prev == null:
		return null
	var rig: DRRigModel = _prev.get_body_entry()["rig"]
	var part: DRRigModel.Part = rig.parts.get(String(DRCharacter3D.PALM_PARTS[side]), null)
	if part == null:
		return null
	_force_pose()                                           # 받침(소켓 · 받침대) 자리를 지금 자세로 — 갱신 뒤 뼈 자세는 동작 그대로로 돌아온다
	var sk := _prev.get_skeleton()
	var hp := sk.get_bone_global_pose(part.root_bone)       # 갱신 밖 = 동작 자세(IK 전)
	var w_skel := sk.global_transform.affine_inverse() * pe.global_transform
	var m := w_skel.affine_inverse() * Transform3D(hp.basis.orthonormalized(), hp * (part.tail_local * 0.5))
	m.basis = m.basis.orthonormalized()
	return m


## 지금 동작 · 시점의 두 손바닥으로 무기 방향을 다시 잡는다(DREquipHold.fit). 쥐는 점 = 지금 오른 손바닥이 닿은 무기 자리(무기 근처일 때,
## 아니면 어림), 표지가 있으면 그 점이 왼손 쪽(표지 자리 그대로) — 없으면 표지를 그 자세의 왼손으로 만든다
func fit_weapon() -> void:
	var e := _equip_from(_node(_sel))
	if e == null:
		e = _weapon_equip()
	var pe := _prev_node(e)
	var sock := _socket_of(e) as BoneAttachment3D
	if e == null or pe == null or _prev == null:
		_set_status("무기를 고르세요")
		return
	if sock == null:
		_set_status("받침대(양손 · 고정)에 든 무기는 기즈모로 맞추세요 — [지금 동작으로 무기 맞추기]는 소켓(손)에 든 무기만")
		return
	var sk := _prev.get_skeleton()
	var rig: DRRigModel = _prev.get_body_entry()["rig"]
	var rp: DRRigModel.Part = rig.parts.get("R_Hand", null)
	var w_skel := sk.get_bone_global_pose(sk.find_bone(sock.bone_name)) * DREquipHold.xform_to(_prev_node(sock), pe)
	var palm_w := w_skel.affine_inverse() * (sk.get_bone_global_pose(rp.root_bone) * (rp.tail_local * 0.5))
	var box := DREquipHold.model_aabb(pe).grow(0.05)
	var gp := palm_w if box.has_point(palm_w) else DREquipHold.grip_point_guess(pe)
	var mk := DRCharacter3D.find_support(e)
	var sp: Variant = DREquipHold.xform_to(e, mk).origin if mk != null else null
	var mo := current_motion()
	var t := _time_sl.value
	var r := DREquipHold.fit(_prev, sock.bone_name, mo, t, gp, e.scale, sp)
	play_motion(mo)
	_seek(t)
	if r.is_empty():
		_set_status("맞추기 실패 — 동작 · 손 뼈를 확인하세요")
		return
	_begin("장비: 무기 맞추기")
	_op_prop(e, "transform", r["weapon"])
	var structural := false
	if mk == null:
		var nm := _new_marker(r["support"], {})
		_op_add(e, nm, [nm])
		structural = true
	elif mk.owner == _root:
		_op_prop(mk, "transform", _in_parent_of(mk, e, r["support"]))
	_end(structural)
	_set_status("무기 맞춤 — %s %d%% · 쥐는 점(무기 기준) (%.1f, %.1f, %.1f) cm · 두 손바닥 %.0f cm" % [mo, int(t * 100.0), gp.x * 100.0, gp.y * 100.0, gp.z * 100.0, float(r["gap"]) * 100.0])


## 동작 하나의 손 IK 비중(동작 표가 보이는 손) — 그 손 표지(DRHandTarget3D)의 motion_weights 를 통째로 바꿔 넣는다(되돌리기 한 칸)
func set_motion_weight(motion: String, w: float) -> void:
	var nm := String(DRCharacter3D.SIDE_NAMES[_mt_side])
	var mk := _support_marker()
	if mk == null or not (mk is DRHandTarget3D):
		_set_status("%s 표지(DRHandTarget3D)가 없습니다" % nm)
		return
	var t := mk as DRHandTarget3D
	var mw: Dictionary[String, float] = t.motion_weights.duplicate()
	if absf(w - t.weight) < 0.001:
		mw.erase(motion)
	else:
		mw[motion] = clampf(w, 0.0, 1.0)
	var was_stale := _rep_stale
	_begin("장비: %s 비중 %s" % [nm, motion])
	_op_prop(t, "motion_weights", mw)
	_end(false)
	_rep_stale = was_stale                  # 비중은 자리를 안 바꾼다 — 그 동작만 다시 재서 표에 넣는다
	if _prev != null and not _last_rep.is_empty() and _rep_side == _mt_side:
		var keep := current_motion()
		var kt := _time_sl.value
		var one := DREquipHold.motion_report(_prev, PackedStringArray([motion]), 8, _mt_side)
		for i in _last_rep.size():
			if not one.is_empty() and String((_last_rep[i] as Dictionary)["motion"]) == motion:
				_last_rep[i] = one[0]
		play_motion(keep)
		_seek(kt)
	_fill_motion_table.call_deferred()      # 미뤄서 — 이 함수는 표의 칸 고치기 신호에서도 불린다


## 고른 장비의(없으면 무기의) 손 표지 — 동작 표가 보이는 손
func _support_marker() -> Node3D:
	var e := _equip_from(_node(_sel))
	if e == null:
		e = _weapon_equip()
	return DRCharacter3D.find_hand_marker(e, _mt_side) if e != null else null


func save_unit() -> void:
	if _root == null:
		return
	if _editing():
		if EditorInterface.get_edited_scene_root() != _root:
			EditorInterface.open_scene_from_path(_sel_path)
		EditorInterface.save_scene()
		_set_status("씬 저장: " + _sel_path.get_file())
		return
	var ps := PackedScene.new()
	if ps.pack(_root) == OK and ResourceSaver.save(ps, _sel_path) == OK:
		_set_status("씬 저장: " + _sel_path.get_file())
	else:
		_set_status("⚠ 저장 실패: " + _sel_path)


## 고른 장비의 자리 · 왼손 표지 · 동작별 비중 · 동작별 자리를 모델 옆 asset.json(socket_hold)에
func save_hold_default() -> void:
	var e := _equip_from(_node(_sel))
	if e == null:
		e = _weapon_equip()
	var sock := _socket_of(e) as BoneAttachment3D
	var asset := DREquipHold.asset_for_model(e.scene_file_path) if e != null else ""
	if e == null or asset == "":
		_set_status("모델 옆에 asset.json 이 있는 장비를 고르세요")
		return
	if sock == null:
		_set_status("무기 기본 자리는 소켓(손 · 뼈)에 든 무기만 — 받침대(양손 · 고정) 자리는 유닛 씬에 저장된다")
		return
	var mk := DRCharacter3D.find_support(e)
	var ok := DREquipHold.write_hold(asset, sock.bone_name, e.scene_file_path, e.transform, mk.transform if mk != null else null,
		(mk as DRHandTarget3D).motion_weights if mk is DRHandTarget3D else {}, DRCharacter3D.motion_offsets(e))
	if ok and Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().update_file(asset)
	_fill_models()
	_set_status("무기 기본 자리 %s → %s" % ["저장" if ok else "⚠ 저장 실패", asset])


func _on_edit_in_editor() -> void:
	var n := _node(_sel)
	if n == null or not Engine.is_editor_hint():
		return
	EditorInterface.set_main_screen_editor("3D")
	EditorInterface.edit_node(n)


# ───────────── 조준 IK(10-21) ─────────────

## 유닛 루트의 조준 칸(aim_enabled · aim_up_deg …) — 되돌리기 한 칸(숫자 칸을 잇달아 바꾸면 한 칸으로 합침)
func set_aim_setting(prop: String, value: Variant) -> void:
	if _aim_lock or _root == null or _root.get(prop) == value:
		return
	if value is bool:
		_begin("장비: 조준 %s" % ("켬" if value else "끔"))
		_op_prop(_root, prop, value)
		_end(false)
	else:
		_set_props_merged("장비: 조준 " + prop, [[_root, prop, value]])
	_fill_motion_table.call_deferred()      # 켜고 끄면 조준 칸이 바뀐다
	_update_aim_label()


## 왼쪽 조준 칸 = 유닛 루트 값(되돌리기 · 인스펙터로 바뀐 것도)
func _show_aim_settings() -> void:
	if _aim_chk == null:
		return
	_aim_lock = true
	var on := _root != null
	_aim_chk.disabled = not on
	_aim_chk.button_pressed = _root.aim_enabled if on else false
	for prop in _aim_sp:
		var sp := _aim_sp[prop] as SpinBox
		sp.editable = on and _root.aim_enabled
		if on:
			sp.value = float(_root.get(prop))
	_aim_lock = false


## 그 동작의 조준 비중을 따로(w = null 이면 지워서 기본으로) — 유닛 루트 aim_motion_weights, 되돌리기 한 칸
func set_aim_weight(motion: String, w: Variant) -> void:
	if _root == null or motion == "":
		return
	var d: Dictionary[String, float] = _root.aim_motion_weights.duplicate()
	d.erase(motion)
	var plus := motion.rfind("+")
	var fallback: float = d[motion.substr(plus + 1)] if plus > 0 and d.has(motion.substr(plus + 1)) else _root.aim_default_weight(motion)   # 따로 안 두면 쓰는 값
	if w != null and absf(float(w) - fallback) >= 0.001:
		d[motion] = clampf(float(w), 0.0, 1.0)
	if d == _root.aim_motion_weights:
		return
	_begin("장비: 조준 비중 %s" % motion)
	_op_prop(_root, "aim_motion_weights", d)
	_end(false)
	_fill_motion_table.call_deferred()      # 미뤄서 — 표의 칸 고치기 신호에서도 불린다
	_update_aim_label()


## 조준 미리보기 켜고 끄기 — 미리보기 병사가 옆 · 높낮이 각을 겨눈다(표적 대신 각 — set_aim_angles)
func set_aim_preview(on: bool) -> void:
	_aim_preview = on
	if _aim_btn != null:
		_aim_btn.set_pressed_no_signal(on)
		_aim_btn.self_modulate = Color(1.0, 0.55, 0.85) if on else Color.WHITE   # 켜져 있음이 보이게(표적 십자와 같은 분홍)
	if on:
		# 지금 동작이 조준 비중 0 이면(서기 · 장전 … 또는 동작 표에서 조준 상태를 지운 Rifle_Aiming_Idle) 켜도 아무 변화가 없다 → 조준하는 동작으로
		var cur := current_motion()
		var am := _aim_motion()
		if am != cur:
			play_motion(am)
			_set_status("조준 미리보기 — %s 은(는) 조준 비중이 0 이라 %s 로 바꿈(그 동작도 돌게 하려면 오른쪽 표 \"조준\" 칸)" % [cur, am])
	_apply_aim_preview()
	if on and not _dot_mode:
		focus_aim()                          # 허리가 도는 것 · 표적 십자가 다 보이게


## 몸과 표적 십자가 다 들어오게(조준 미리보기를 켤 때 · 돌려 보기)
func focus_aim() -> void:
	if _prev == null:
		return
	var ar := _prev.aim_report()
	if ar.is_empty():
		focus_body()
		return
	var g := _prev.global_transform
	var body := g * Vector3(0.0, 1.0, 0.0)
	var tp: Vector3 = g * (ar["muzzle"] as Vector3) + (g.basis * (ar["aim_dir"] as Vector3)).normalized() * AIM_MARK_M
	_target = (body + tp) * 0.5
	_dist = clampf(body.distance_to(tp) * 2.4 + 1.4, 3.3, 7.0)
	_update_cam()


func _apply_aim_preview() -> void:
	var side := _aim_side_sl.value if _aim_side_sl != null else 0.0
	var height := _aim_height_sl.value if _aim_height_sl != null else 0.0
	_update_aim_label()
	if _prev == null:
		return
	if _aim_preview:
		_prev.set_aim_angles(side, height, true)
	else:
		_prev.clear_aim_target(true)
	_force_pose()


## 끌기 막대 옆 글자 — 각 + (조준 미리보기 중인데 안 도는 까닭이 있으면) 주황 경고. 보는 곳(막대) 바로 옆에 둔다 — 아래 정보 줄 끝은 안 읽힌다(10-21)
func _update_aim_label() -> void:
	if _aim_lbl == null:
		return
	var t := "옆 %+d° · 높낮이 %+d°" % [int(_aim_side_sl.value if _aim_side_sl != null else 0.0), int(_aim_height_sl.value if _aim_height_sl != null else 0.0)]
	var warn := ""
	if _aim_preview and _prev != null:
		if _prev.get_weapon_node() == null:
			warn = "⚠ 무기 없음"
		elif not _prev.aim_enabled:
			warn = "⚠ 조준 꺼짐(왼쪽 [조준])"
		elif _prev.aim_weight_for(current_motion()) <= 0.0:
			warn = "⚠ 이 동작은 조준 0 % — 오른쪽 표 \"조준\" 칸"
	_aim_lbl.text = t + ("   " + warn if warn != "" else "")
	_aim_lbl.add_theme_color_override("font_color", Color(1.0, 0.62, 0.25) if warn != "" else Color(0.92, 0.94, 0.96))
	_aim_lbl.modulate = Color.WHITE if _aim_preview else Color(1, 1, 1, 0.45)


## 조준 미리보기에 쓸 동작 — 지금 동작의 조준 비중이 있으면 그대로, 없으면 Firing_Rifle(비중이 있으면) → 비중이 있는 첫 동작 → 그대로
func _aim_motion() -> String:
	var cur := current_motion()
	if _prev == null or _prev.aim_weight_for(cur) > 0.0:
		return cur
	var names := _prev.motion_names()
	names.sort()
	if names.has("Firing_Rifle") and _prev.aim_weight_for("Firing_Rifle") > 0.0:
		return "Firing_Rifle"
	for n in names:
		if _prev.aim_weight_for(n) > 0.0:
			return n
	return cur


## 동작 표 조준 칸 — 기본(동작 표 상태로 정한 값)은 흐리게
func _fill_aim_cell(it: TreeItem, motion: String) -> void:
	const C := 4
	if _root == null:
		it.set_text(C, "-")
		return
	var own := _root.aim_motion_weights.has(motion)
	var plus := motion.rfind("+")
	var upper := motion.substr(plus + 1) if plus > 0 and not own and _root.aim_motion_weights.has(motion.substr(plus + 1)) else ""
	it.set_cell_mode(C, TreeItem.CELL_MODE_RANGE)
	it.set_range_config(C, 0.0, 1.0, 0.05)
	it.set_range(C, _root.aim_weight_for(motion) if _root.aim_enabled else 0.0)
	it.set_editable(C, _root.aim_enabled)
	var tip := "조준 비중 — 사격 때 허리 · 가슴을 돌려 총구를 표적으로 하는 정도(0 = 동작 그대로)"
	if not _root.aim_enabled:
		it.set_custom_color(C, Color(0.45, 0.47, 0.5))
		tip += "\n조준이 꺼져 있다(왼쪽 [조준])"
	elif own:
		it.clear_custom_color(C)
		tip += "\n이 동작만 따로 둔 값 — 오른쪽 누름 → 조준 비중 기본으로"
	elif upper != "":
		it.set_custom_color(C, Color(0.55, 0.76, 0.96))
		tip += "\n상하체 합성 — 상체 동작 %s 의 값" % upper
	else:
		it.set_custom_color(C, Color(0.55, 0.57, 0.6))
		tip += "\n기본 — 동작 표의 사격 · 조준 상태에 든 동작이면 1, 아니면 0. 바꾸면 이 동작만 따로"
	it.set_tooltip_text(C, tip)


# ───────────── 미리보기 ─────────────

## 유닛을 pack 한 사본으로 미리보기 캐릭터를 다시 만든다(저장 안 한 고침까지 — 편집 중인 씬은 안 건드림)
func _rebuild_preview() -> void:
	var keep := current_motion()
	var keep_t := _time_sl.value if _time_sl != null else 0.0
	if _prev != null and is_instance_valid(_prev):
		if _prev.get_parent() != null:
			_prev.get_parent().remove_child(_prev)
		_prev.queue_free()
	_prev = null
	_live = []
	_last_rep = []                          # 구조가 바뀌었으니 잰 수치는 버린다
	_rep_stale = false
	if _root == null:
		return
	var ps := PackedScene.new()
	if ps.pack(_root) != OK:
		_info.text = "⚠ 유닛을 묶지 못함(pack)"
		return
	var ch := ps.instantiate() as DRCharacter3D
	if ch == null:
		return
	ch.preview_playing = false
	ch.preview_motion = ""
	(_dots.world if _dot_mode else _world3d).add_child(ch)
	if ch.get_skeleton() == null:
		_info.text = "⚠ 조립 실패(몸 모델을 확인)"
		ch.queue_free()
		return
	ch.get_animation_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ch.get_skeleton().skeleton_updated.connect(_on_prev_updated)
	ch.rotation.y = deg_to_rad(55.0) if _dot_mode else 0.0
	_prev = ch
	var names := PackedStringArray()
	var sk := ch.get_skeleton()
	for i in sk.get_bone_count():
		names.append(sk.get_bone_name(i))
	var keep_bone := _bone_ob.selected
	_fill_bones(names)
	if keep_bone >= 0 and keep_bone < _bone_ob.item_count:
		_bone_ob.select(keep_bone)
	_fill_motions(keep)
	if keep != "" and keep == current_motion():
		_seek(keep_t)
	elif keep == "":
		focus_hands.call_deferred()             # 처음 — 두 손 · 무기를 가까이(소켓이 뼈를 따라간 뒤에)
	_apply_aim_preview()                         # 새 사본도 조준 미리보기 그대로


func _on_prev_updated() -> void:
	if _prev != null:
		_live = [_prev.support_now(0), _prev.support_now(1)]       # 신호 안 = IK 뒤(손마다)


## 미리보기 사본의 노드 자리 · 보이기 · 비중 · 동작별 자리를 유닛 것으로(구조가 같을 때 — 다시 조립하지 않고. DRCharacter3D.sync_from —
## 소켓은 뼈가, 두 손 사이 받침대는 두 손이 자리를 정하므로 안 덮는다 · 장비는 기본 자리 + 지금 동작의 동작별 자리)
func _sync_preview() -> void:
	if _prev == null or _root == null:
		return
	_prev.sync_from(_root)
	if not _last_rep.is_empty() and not _rep_stale:
		_rep_stale = true                     # 자리가 바뀌었으니 잰 수치는 지난 값
		_fill_motion_table.call_deferred()    # 미뤄서 — 표의 칸을 고치는 신호 안에서 표를 비우지 않게
	var mo := current_motion()
	if mo != "":
		var t := _time_sl.value
		_prev.play_motion(mo, 0.0)
		_seek(t)


func _prev_node(n: Node) -> Node:
	if n == null or _prev == null or _root == null:
		return null
	return _prev.get_node_or_null(_root.get_path_to(n))


func _fill_motions(keep: String) -> void:
	_motion_ob.clear()
	if _prev == null:
		return
	var names := _prev.motion_names()
	names.sort()
	for n in names:
		_motion_ob.add_item(n)
	var want := keep if names.has(keep) else (DEFAULT_MOTION if names.has(DEFAULT_MOTION) else (names[0] if not names.is_empty() else ""))
	_fill_motion_table()
	if want != "":
		play_motion(want)


func current_motion() -> String:
	if _motion_ob == null or _motion_ob.selected < 0:
		return ""
	return _motion_ob.get_item_text(_motion_ob.selected)


## 미리보기에서 그 동작을 튼다(섞기 없이 — 그 동작의 손 IK 비중 · 동작별 무기 자리)
func play_motion(motion: String) -> void:
	if _prev == null or motion == "":
		return
	for i in _motion_ob.item_count:
		if _motion_ob.get_item_text(i) == motion:
			_motion_ob.select(i)
	_prev.play_motion(motion, 0.0)
	_acc = 0.0
	_update_aim_label()                          # 조준 비중 0 동작이면 막대 옆 경고
	if _per_motion:
		_show_xform()                          # 숫자 칸 = 이 동작 자리 · 띠 = 이 동작 이름
	else:
		_update_pm_ui()
	_mark_motion_row(motion)


func _seek(frac: float) -> void:
	if _prev == null:
		return
	var ap := _prev.get_animation_player()
	if ap.current_animation == "":
		return
	ap.seek(ap.get_animation(ap.current_animation).length * clampf(frac, 0.0, 1.0), true)
	_time_sl.set_value_no_signal(clampf(frac, 0.0, 1.0))


func _on_time(v: float) -> void:
	_seek(v)


## 돌려 보기 ↔ 도트 보기(게임과 같은 3/4 방향 · 저해상도 · 외곽선). 기즈모는 돌려 보기에서만
func set_dot_mode(on: bool) -> void:
	_dot_mode = on
	if _giz.is_dragging():
		_giz.cancel_drag()
	_view3d.visible = not on
	_dotc.visible = on
	_giz.visible = not on
	_view_btn.text = "돌려 보기" if on else "도트 보기"
	set_page_active(_active)
	if _prev != null:
		var keep := current_motion()
		var t := _time_sl.value
		_prev.get_parent().remove_child(_prev)
		(_dots.world if on else _world3d).add_child(_prev)
		_prev.rotation.y = deg_to_rad(55.0) if on else 0.0
		if keep != "":
			_prev.play_motion(keep, 0.0)
			_seek(t)


func focus_hands() -> void:
	_force_pose()
	var a := _hands_center()
	_dist = 0.9
	if a != Vector3.INF:
		_target = a
		var sk := _prev.get_skeleton()
		var hl := sk.find_bone(String(DRCharacter3D.HAND_BONES[0]))
		var hr := sk.find_bone(String(DRCharacter3D.HAND_BONES[1]))
		if hl >= 0 and hr >= 0:
			var d := (sk.global_transform * sk.get_bone_global_pose(hl).origin).distance_to(sk.global_transform * sk.get_bone_global_pose(hr).origin)
			_dist = maxf(0.9, d * 2.6)            # 두 손이 다 들어오게(화각 35°)
	_update_cam()


func focus_body() -> void:
	_target = Vector3(0.0, 0.95, 0.0)
	_dist = 3.3
	_update_cam()


## 미리보기 뼈대를 지금 바로 갱신(소켓이 뼈를 따라오게) — 자세를 바꾼 같은 프레임에 자리를 잴 때. 보통은 프레임 끝에 저절로 된다
func _force_pose() -> void:
	if _prev == null or _prev.get_skeleton() == null:
		return
	var sk := _prev.get_skeleton()
	sk.set_bone_pose_rotation(0, sk.get_bone_pose_rotation(0))     # 갱신할 거리를 만든다(값은 그대로)
	sk.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)


## 미리보기 세상 좌표의 두 손 가운데(두 손 뼈 — 갱신 뒤라 IK 가 걸린 손은 표지 쪽)
func _hands_center() -> Vector3:
	if _prev == null or _prev.get_skeleton() == null:
		return Vector3.INF
	var sk := _prev.get_skeleton()
	var hl := sk.find_bone(String(DRCharacter3D.HAND_BONES[0]))
	var hr := sk.find_bone(String(DRCharacter3D.HAND_BONES[1]))
	if hl < 0 or hr < 0:
		return Vector3.INF
	var pl := sk.global_transform * sk.get_bone_global_pose(hl).origin
	var pr := sk.global_transform * sk.get_bone_global_pose(hr).origin
	for side in 2:                                        # 표지가 있으면 그 자리(손이 갈 곳)
		var mk := _prev.get_hand_marker(side)
		if mk != null:
			if side == 0:
				pl = mk.global_position
			else:
				pr = mk.global_position
	return (pl + pr) * 0.5


func _update_cam() -> void:
	var b := DRBaker.view_basis(_yaw, _pitch)
	_cam.transform = Transform3D(b, _target + b * Vector3(0.0, 0.0, _dist))   # 부모가 뷰포트라 로컬 = 세상(트리 밖에서도 된다)


## 미리보기 카메라 — 기즈모 층이 기즈모 밖 입력을 넘겨준다(유니티 장면 창 손): 휠 = 확대 · 가운데 끌기 = 옮기기 ·
## 오른쪽 끌기 · Alt+왼쪽 끌기 = 돌려 보기 · Alt+오른쪽 끌기 = 확대 · 보기 도구(Q) · Shift 의 왼쪽 끌기 = 옮기기 · 다른 도구의 빈 곳 왼쪽 끌기 = 돌려 보기
func _on_view_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null:
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(0.2, _dist * 0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(10.0, _dist * 1.1)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			if not mb.pressed:
				_drag = 0
			elif mb.button_index == MOUSE_BUTTON_MIDDLE:
				_drag = 2
			elif mb.button_index == MOUSE_BUTTON_RIGHT:
				_drag = 3 if mb.alt_pressed else 1
			elif mb.alt_pressed:
				_drag = 1
			else:
				_drag = 2 if mb.shift_pressed or _giz.tool_mode == TransformGizmo.Tool.VIEW else 1
		_update_cam()
		return
	var mm := ev as InputEventMouseMotion
	if mm != null and _drag != 0:
		if _drag == 1:
			_yaw -= mm.relative.x * 0.4
			_pitch = clampf(_pitch + mm.relative.y * 0.4, -85.0, 85.0)
		elif _drag == 2:
			var b := DRBaker.view_basis(_yaw, _pitch)
			_target += (b.x * -mm.relative.x + b.y * mm.relative.y) * _dist * 0.0022
		else:
			_dist = clampf(_dist * exp((mm.relative.y - mm.relative.x) * 0.006), 0.2, 10.0)
		_update_cam()


func _process(delta: float) -> void:
	if not _active or not is_visible_in_tree():
		return
	if _dot_mode and _dot_vp != null:
		var sz := Vector2(_dot_vp.size)
		var o := Vector2(sz.x * 0.5, sz.y * 0.85)
		if _dots.origin != o:
			_dots.origin = o
			_ground.queue_redraw()
	var dragging := _giz.is_dragging()
	if _prev != null and _playing and not dragging:     # 끄는 동안은 자세를 멈춘다(손이 움직이면 놓은 자리가 손 기준으로 어긋남)
		_acc += delta
		if _acc >= 1.0 / STEP_HZ:
			_prev.step_motion(_acc)
			_acc = 0.0
			var ap := _prev.get_animation_player()
			if ap.current_animation != "":
				_time_sl.set_value_no_signal(ap.current_animation_position / maxf(ap.get_animation(ap.current_animation).length, 0.001))
	if not _dot_mode:
		var gt := _gizmo_target()
		if _giz.target != gt:
			_giz.cancel_drag()
			_giz.target = gt
		_giz.allow_scale = gt != null and not _is_marker(gt) and not (_per_motion and _is_equip(gt))    # 동작별 자리는 위치 · 회전만
		_giz.queue_redraw()                    # 동작을 따라 손잡이도 움직인다
	_draw_marks()
	_update_info()
	_poll -= delta
	if _poll <= 0.0 and not dragging:
		_poll = POLL_SEC
		_follow_root()


## 인스펙터 · 기즈모 · 되돌리기로 유닛 노드가 바뀌었으면 따라간다(구조 = 다시 조립, 자리만 = 사본 노드만)
func _follow_root() -> void:
	if _root != null and not is_instance_valid(_root):
		_root = null
		_owns_root = false
	if _root == null:
		return
	var ss := _make_struct_sig()
	if ss != _struct_sig:
		_struct_sig = ss
		_fill_tree()
		_rebuild_preview()
		_xform_sig = _make_xform_sig()
		_show_xform()
		_show_aim_settings()
		return
	var xs := _make_xform_sig()
	if xs != _xform_sig:
		_xform_sig = xs
		_sync_preview()
		_fill_tree()                             # 동작별 자리 개수(되돌리기 · 인스펙터로 바뀐 것도)
		_show_xform()
		_show_aim_settings()                     # 조준 칸(되돌리기 · 인스펙터)
		_fill_motion_table()


func _make_struct_sig() -> String:
	if _root == null:
		return ""
	var parts := PackedStringArray([_root.body_model, _root.outfit_top, _root.outfit_bottom, str(_root.motions.get_instance_id()) if _root.motions != null else "-"])
	for s in _anchors():
		parts.append("S%s>%s" % [_root.get_path_to(s), (s as BoneAttachment3D).bone_name if s is BoneAttachment3D else "mount%d" % int((s as DRGripMount3D).mode)])
		var stack: Array[Node] = []
		stack.append_array(s.get_children())
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n.owner != _root:
				continue
			parts.append("%s|%s|%s|%s|%s" % [_root.get_path_to(n), n.scene_file_path, n.get_class(), str((n as Node3D).visible) if n is Node3D else "",
				str((n as DRHandTarget3D).side) if n is DRHandTarget3D else ""])
			stack.append_array(n.get_children())
	return ";".join(parts)


func _make_xform_sig() -> String:
	if _root == null:
		return ""
	var parts := PackedStringArray([str(_root.aim_motion_weights)])   # 조준 칸(10-21 — 되돌리기 · 인스펙터로 바뀐 것도 미리보기 사본에)
	for k in DRCharacter3D.AIM_PROPS:
		parts.append(str(_root.get(k)))
	for s in _anchors():
		if s is DRGripMount3D:                  # 받침대: 고정이면 자리 · 두 손 사이면 보간 비율 · 맞춘 자세
			var gm := s as DRGripMount3D
			parts.append("%s|%s|%s|%s" % [str(gm.transform) if gm.mode == DRGripMount3D.Mode.FIXED else "", str(gm.blend), str(gm.right_offset), str(gm.left_offset)])
		var stack: Array[Node] = []
		stack.append_array(s.get_children())
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n.owner != _root:
				continue
			if n is Node3D:
				parts.append(str((n as Node3D).transform))
			if _is_equip(n):
				parts.append(str(DRCharacter3D.motion_offsets(n)))    # 동작별 자리(10-19 — 되돌리기 · 인스펙터 메타로 바뀐 것도 따라간다)
			if n is DRHandTarget3D:
				parts.append(str((n as DRHandTarget3D).motion_weights) + str((n as DRHandTarget3D).weight))
			stack.append_array(n.get_children())
	return ";".join(parts)


## 손마다 표지 거리 — "왼손: IK 비중 1.00 · IK 뒤 0.0 cm(동작 그대로 0.5) · 오른손: 무기를 듦(고정)"
func _update_info() -> void:
	if _prev == null:
		_info.text = ""
		return
	var w := _prev.get_weapon_node()
	var kind := grip_kind(w)
	var parts := PackedStringArray([current_motion()])
	for side in 2:
		var nm := String(DRCharacter3D.SIDE_NAMES[side])
		if kind == (1 if side == 0 else 0):
			parts.append("%s: 무기를 듦(받침)" % nm)
			continue
		if _prev.get_hand_marker(side) == null:
			parts.append("%s: 표지 없음 — 동작 그대로%s" % [nm, " · [지금 자세로 %s 표지]" % nm if kind >= 0 else ""])
			continue
		var live: Dictionary = _live[side] if _live is Array and (_live as Array).size() > side else {}
		var raw := _prev.support_now(side)         # 갱신 밖 = 동작 그대로
		parts.append("%s: IK 비중 %.2f · 손바닥 ↔ 표지 IK 뒤 %.1f cm(동작 그대로 %.1f) · 회전 차 %.0f°" % [nm, _prev.get_ik_weight(side),
			float(live.get("dist", 0.0)) * 100.0, float(raw.get("dist", 0.0)) * 100.0, float(live.get("rot", 0.0))])
	var oe := _offset_equip()
	if oe != null and DRCharacter3D.offset_key(oe, current_motion()) != "":
		parts.append("무기 = 이 동작 자리(%s)" % _offset_text(oe, current_motion()))
	if _aim_preview:
		parts.append(_aim_text())
	_info.text = " · ".join(parts)


## 조준 미리보기 상태 한 줄
func _aim_text() -> String:
	if _prev == null or _prev.get_weapon_node() == null:
		return "조준: 무기 없음"
	if not _prev.aim_enabled:
		return "조준: 꺼짐(왼쪽 [조준])"
	if _prev.get_weapon_node().get_parent() is DRGripMount3D and (_prev.get_weapon_node().get_parent() as DRGripMount3D).mode == DRGripMount3D.Mode.FIXED:
		return "조준: 고정 받침대 — 몸으로 겨누지 않음"
	var w := _prev.aim_weight_for(current_motion())
	if w <= 0.0:
		return "조준: 이 동작은 0 % — 오른쪽 표 \"조준\" 칸을 올리거나 사격 동작(Firing_Rifle 등)을 고르세요"
	var r := _prev.aim_report()
	if r.is_empty():
		return "조준 %d %%" % roundi(w * 100.0)
	return "조준 %d %% · 허리 · 가슴 돌림 옆 %+.0f° · 위아래 %+.0f°%s (동작이 원래 겨눈 높낮이 %+.0f°)" % [roundi(w * 100.0), float(r["yaw"]), float(r["pitch"]),
		" — 한계에서 멈춤" if bool(r["clamped"]) else "", float(r["base_pitch"])]


## 미리보기에 표시: 손 표지(초록 — 왼손 · 하늘 — 오른손) · IK 뒤 손바닥(빨강) · 소켓(노랑) · 받침대(주황) ·
## 고른 노드 축(빨 x · 초 y · 파 z — 보기 도구(Q)일 때만, 다른 도구는 기즈모가 보인다)
func _draw_marks() -> void:
	_imesh.clear_surfaces()
	if _prev == null or _dot_mode:
		return
	var sk := _prev.get_skeleton()
	if sk == null:
		return
	_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var any := false
	if _live is Array:
		var g := sk.global_transform
		for side in mini((_live as Array).size(), 2):
			var lv: Dictionary = _live[side]
			if lv.is_empty():
				continue
			_cross(g * (lv["target"] as Vector3), 0.025, Color(0.2, 1.0, 0.3) if side == 0 else Color(0.3, 0.85, 1.0))
			_cross(g * (lv["palm"] as Vector3), 0.015, Color(1.0, 0.25, 0.2))
			any = true
	for s in _prev.get_anchors():
		_cross(s.global_position, 0.02, Color(1.0, 0.9, 0.2) if s is BoneAttachment3D else Color(1.0, 0.55, 0.15))
		any = true
	if _aim_preview:                             # 조준: 표적(분홍 — 겨눌 방향) · 총구 선(초록 = 표적으로 · 주황 = 한계)
		var ar := _prev.aim_report()
		var mw := _prev.muzzle_world()
		if not ar.is_empty() and not mw.is_empty():
			var g := _prev.global_transform
			var tp: Vector3 = g * (ar["muzzle"] as Vector3) + (g.basis * (ar["aim_dir"] as Vector3)).normalized() * AIM_MARK_M
			_cross(tp, 0.06, Color(1.0, 0.35, 0.85))
			var col := Color(1.0, 0.6, 0.2) if bool(ar["clamped"]) else Color(0.35, 1.0, 0.45)
			_imesh.surface_set_color(col)
			_imesh.surface_add_vertex(mw[0])
			_imesh.surface_set_color(col)
			_imesh.surface_add_vertex((mw[0] as Vector3) + (mw[1] as Vector3) * AIM_MARK_M)
			any = true
	var pn := _prev_node(_node(_sel)) as Node3D
	if pn != null and (_giz.tool_mode == TransformGizmo.Tool.VIEW or (_giz.tool_mode == TransformGizmo.Tool.SCALE and not _giz.allow_scale)):
		var t := pn.global_transform
		for k in 3:
			var col := [Color(1, 0.3, 0.3), Color(0.3, 1, 0.3), Color(0.35, 0.55, 1)][k] as Color
			_imesh.surface_set_color(col)
			_imesh.surface_add_vertex(t.origin)
			_imesh.surface_set_color(col)
			_imesh.surface_add_vertex(t.origin + t.basis[k].normalized() * 0.09)
		any = true
	if not any:
		_imesh.surface_add_vertex(Vector3.ZERO)
		_imesh.surface_add_vertex(Vector3.ZERO)
	_imesh.surface_end()


func _cross(p: Vector3, r: float, c: Color) -> void:
	for a in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(p - a * r)
		_imesh.surface_set_color(c)
		_imesh.surface_add_vertex(p + a * r)


func _draw_ground() -> void:
	if _dots == null:
		return
	var o := _dots.origin
	_ground.draw_rect(Rect2(0.0, o.y - 30.0, 4096.0, 4096.0), Color(0.31, 0.37, 0.3))
	_ground.draw_set_transform(o, 0.0, Vector2(1.0, 0.3))
	_ground.draw_circle(Vector2.ZERO, _dots.px_per_m * 0.4, Color(0.0, 0.0, 0.0, 0.3))
	_ground.draw_set_transform(Vector2.ZERO)


# ───────────── 동작 표(동작마다 왼손) ─────────────

func _fill_motion_table(report: Array = []) -> void:
	if not report.is_empty():
		_last_rep = report
		_rep_stale = false
	_mt_lock = true
	_mt.clear()
	var top := _mt.create_item()
	var mk := _support_marker()
	var by := {}
	if _rep_side == _mt_side:                  # 다른 손을 잰 수치는 안 보인다(그 손으로 다시 재기)
		for r in _last_rep:
			by[String((r as Dictionary)["motion"])] = r
	_mt.set_column_title(1, "손↔표지 cm" + (" (지난)" if _rep_stale else ""))
	if _prev != null:
		var names := _prev.motion_names()
		names.sort()
		for n in names:
			var it := _mt.create_item(top)
			it.set_text(0, n)
			it.set_tooltip_text(0, n)
			if by.has(n):
				var d: Dictionary = by[n]
				it.set_text(1, "%.1f → %.1f" % [float(d["raw_avg"]) * 100.0, float(d["ik_avg"]) * 100.0])
				var tip := "동작 그대로(IK 전) 평균 %.1f / 최대 %.0f cm → IK 뒤 평균 %.1f / 최대 %.1f cm (8 시점)" % [float(d["raw_avg"]) * 100.0, float(d["raw_max"]) * 100.0,
					float(d["ik_avg"]) * 100.0, float(d["ik_max"]) * 100.0]
				if _rep_stale:
					it.set_custom_color(1, Color(0.5, 0.52, 0.56))
					it.set_tooltip_text(1, tip + "\n잰 뒤 무기 · 표지 자리가 바뀜 — [모든 동작 재기]")
				elif float(d["ik_max"]) > 0.05 and float(d["weight"]) > 0.0:
					it.set_custom_color(1, Color(0.95, 0.65, 0.3))
					it.set_tooltip_text(1, tip + "\n팔이 표지에 안 닿는 시점이 있음(어깨 → 손목 목표 / 팔 길이 최대 %.2f) — [이 동작만] 으로 무기 자리를 옮기거나 [맞추기]" % float(d["reach_max"]))
				else:
					it.set_tooltip_text(1, tip)
			else:
				it.set_text(1, "-")
				it.set_tooltip_text(1, "[모든 동작 재기] 를 누르면 동작마다 잰다")
			if mk is DRHandTarget3D:
				it.set_cell_mode(2, TreeItem.CELL_MODE_RANGE)
				it.set_range_config(2, 0.0, 1.0, 0.05)
				it.set_range(2, (mk as DRHandTarget3D).weight_for(n))
				it.set_editable(2, true)
			else:
				it.set_text(2, "표지 없음" if mk == null else "1(늘)")
			_fill_offset_cell(it, n)
			_fill_aim_cell(it, n)
			if n == current_motion():
				it.select(0)                     # 지금 동작 행(잠금 중이라 다시 틀지 않음)
	_mt_lock = false


func _on_mt_edited() -> void:
	if _mt_lock:
		return
	var it := _mt.get_edited()
	if it == null:
		return
	if _mt.get_edited_column() == 2:
		set_motion_weight(it.get_text(0), it.get_range(2))
	elif _mt.get_edited_column() == 4:
		set_aim_weight(it.get_text(0), it.get_range(4))


## 동작마다 그 손바닥 ↔ 표지(IK 전 · 뒤, 동작 표가 보이는 손) — 미리보기 사본으로 8 시점씩. 돌려주는 값 = DREquipHold.motion_report
func measure_all() -> Array:
	if _prev == null:
		return []
	var keep := current_motion()
	var t := _time_sl.value
	var rep := DREquipHold.motion_report(_prev, _prev.motion_names(), 8, _mt_side)
	_rep_side = _mt_side
	_fill_motion_table(rep)
	if keep != "":
		play_motion(keep)
		_seek(t)
	var worst := ""
	var wv := 0.0
	for r in rep:
		var d: Dictionary = r
		if float(d["weight"]) > 0.0 and float(d["ik_max"]) > wv:
			wv = float(d["ik_max"])
			worst = String(d["motion"])
	_set_status("동작 %d개 잼 — IK 를 켠 동작 중 가장 먼 것: %s %.1f cm" % [rep.size(), worst, wv * 100.0] if worst != "" else "동작 %d개 잼" % rep.size())
	return rep


# ───────────── 동작별 무기 자리(10-19) ─────────────
# 사용자(10-16): "2번 탭은 애니메이션별로 양손이든 왼손이든 오른손이든 총기 위치 회전 오프셋을 지정해 둘 수 있는 리소스 툴인 거지?" → 10-19 "2번 작업도 시행. ui / ux 잘 신경 써 줘"
# 저장 = 장비 노드 메타(DRCharacter3D.MOTION_OFFSETS_META — {동작: 장비 축 기준 차이}, 유닛 씬에 저장 · 되돌리기 한 칸). 게임은 동작이 바뀔 때 손 IK 비중과
# 같은 시간 동안 섞어 옮긴다. 고치는 길: 위 도구 줄 [이 동작만](또는 동작 표 행 두 번 누름) → 기즈모 · 숫자 칸 · 띠의 [맞추기], 동작 표 오른쪽 누름 메뉴.

## 받침 바로 아래 노드(장비)인가 — 동작별 자리는 장비에만
static func _is_equip(n: Node) -> bool:
	return n is Node3D and n.get_parent() != null and _is_anchor(n.get_parent())


## 크기 · 기울임을 뺀 변환(동작별 자리는 위치 · 회전만)
static func _rigid(t: Transform3D) -> Transform3D:
	return Transform3D(t.basis.orthonormalized(), t.origin)


## 동작별 자리를 고칠 장비 — 고른 노드가 든 장비(표지 · 받침을 골라도 그 장비), 없으면 무기
func _offset_equip() -> Node3D:
	var e := _equip_from(_node(_sel))
	return e if e != null else _weapon_equip()


## "차이 2.3 cm · 4°" · "기본 자리" · "상체 Firing_Rifle 자리(차이 …)" — e = 유닛 씬의 장비(transform = 기본 자리)
func _offset_text(e: Node3D, motion: String) -> String:
	if e == null or motion == "":
		return ""
	var key := DRCharacter3D.offset_key(e, motion)
	if key == "":
		return "기본 자리"
	var sz := DRCharacter3D.offset_size(e.transform, DRCharacter3D.offset_for(e, motion))
	var t := "차이 %.1f cm · %.0f°" % [sz.x * 100.0, sz.y]
	return t if key == motion else "상체 %s 자리 — %s" % [key, t]


## 기즈모 · 숫자 칸이 고치는 무기 자리 — false = 모든 동작(기본 자리) · true = 지금 동작만(동작별 자리).
## 켤 때 표지 · 받침을 골라 두었으면 그 장비로 바꿔 고른다(동작별 자리는 장비에만)
func set_per_motion(on: bool) -> void:
	if _giz != null and _giz.is_dragging():
		_giz.cancel_drag()
	_per_motion = on
	if on and _root != null:
		var e := _offset_equip()
		if e != null and _node(_sel) != e:
			_select_node(_root.get_path_to(e))
	_show_xform()
	_fill_motion_table()
	if on:
		var e2 := _offset_equip()
		_set_status("이 동작만 — %s 의 %s 자리를 고칩니다(기즈모 · 숫자 칸 · 띠의 [맞추기]). 다른 동작 · 기본 자리는 그대로" % [current_motion(), e2.name if e2 != null else "무기"]
			if current_motion() != "" else "이 동작만 — 동작을 고르세요")
	else:
		_set_status("모든 동작 — 기본 자리를 고칩니다")


## 위 도구 줄 단추 · 미리보기 띠 · 숫자 칸 아래 안내를 지금 상태로
func _update_pm_ui() -> void:
	if _pm_banner == null:
		return
	for i in _pm_btns.size():
		_pm_btns[i].set_pressed_no_signal(i == (1 if _per_motion else 0))
	if _pm_btns.size() > 1:                     # 눌린 "이 동작만" = 미리보기 띠와 같은 주황(테마 여백은 그대로 — 틀을 덮으면 글자가 잘렸다)
		_pm_btns[1].self_modulate = Color(1.0, 0.68, 0.32) if _per_motion else Color.WHITE
	var e := _offset_equip()
	var mo := current_motion()
	var key := DRCharacter3D.offset_key(e, mo) if e != null else ""
	_pm_banner.visible = _per_motion
	if _per_motion:
		if e == null:
			_pm_label.text = "✎ 이 동작만 — 무기(장비)를 고르세요"
			_pm_label.tooltip_text = _pm_label.text
		elif mo == "":
			_pm_label.text = "✎ 이 동작만 — 동작을 고르세요"
			_pm_label.tooltip_text = _pm_label.text
		else:
			var now := _offset_text(e, mo) if key == mo else ("아직 따로 없음 — " + _offset_text(e, mo)) if key != "" else "아직 기본 자리"
			_pm_label.text = "✎ %s — %s" % [mo, now]             # 좁은 띠에서도 동작 · 차이가 먼저 보이게(장비 이름 · 설명은 풍선 도움말)
			_pm_label.tooltip_text = "이 동작만 고치는 중: %s 의 %s 자리 — %s\n기즈모 · 숫자 칸 · [맞추기] 가 이 동작에만 저장된다. 기본 자리 · 다른 동작은 그대로" % [mo, e.name, now]
		_pm_reset_btn.disabled = e == null or key != mo
		_pm_fit_btn.disabled = e == null or mo == "" or grip_kind(e) == 3 or grip_kind(e) == 4
	var note := ""
	if e != null and mo != "" and _is_equip(_node(_sel)):
		if _per_motion:
			note = "숫자 칸 = %s 의 무기 자리(위치 · 회전만, 크기는 기본 자리). %s" % [mo, "지금 " + _offset_text(e, mo) if key != "" else "아직 기본 자리와 같음"]
		elif key != "":
			note = "지금 동작(%s)은 따로 자리가 있어 미리보기 = 기본 자리 + %s. 기즈모로 옮기면 기본 자리가 바뀌고 이 차이는 그대로" % [mo, _offset_text(e, mo)]
	_xf_note.text = note
	_xf_note.visible = note != ""


## 장비 e 의 그 동작 자리 차이(장비 축 기준 — 기본 자리 × off)를 넣는다. null · IDENTITY 면 뺀다(기본 자리로). 되돌리기 한 칸
func set_motion_offset(e: Node3D, motion: String, off: Variant, label: String = "") -> void:
	if e == null or motion == "":
		return
	var d := DRCharacter3D.motion_offsets(e).duplicate()
	if off is Transform3D and not _rigid(off).is_equal_approx(Transform3D.IDENTITY):
		d[motion] = _rigid(off)
	else:
		d.erase(motion)
	_set_offsets(e, d, label if label != "" else "장비: %s %s 자리" % [e.name, motion], false)


## 장비 e 의 동작별 자리 통째로(빈 것 = 메타를 지움) — set_meta(이름, null) 이 메타를 지운다(set("metadata/…", null) 은 null 값으로 남아 10-19 확인).
## merge = 숫자 칸처럼 잇달아 바뀌면 되돌리기 한 칸으로 합친다
func _set_offsets(e: Node3D, d: Dictionary, label: String, merge: bool) -> void:
	var nm := DRCharacter3D.MOTION_OFFSETS_META
	var old: Variant = (e.get_meta(nm) as Dictionary).duplicate() if e.has_meta(nm) and e.get_meta(nm) is Dictionary else null
	var nv: Variant = d if not d.is_empty() else null
	if _editing():
		var ur := EditorInterface.get_editor_undo_redo()
		ur.create_action(label, UndoRedo.MERGE_ENDS if merge else UndoRedo.MERGE_DISABLE, _root)
		ur.add_do_method(e, "set_meta", nm, nv)
		ur.add_undo_method(e, "set_meta", nm, old)
		ur.commit_action()
	else:
		e.set_meta(nm, nv)
	_after_change(false)
	_fill_motion_table.call_deferred()      # 미뤄서 — 표의 신호 안에서 불릴 수 있다


## 그 동작의 따로 자리를 지운다(기본 자리로)
func reset_motion_offset(motion: String) -> void:
	var e := _offset_equip()
	if e == null or DRCharacter3D.offset_key(e, motion) != motion:
		_set_status("%s 은 따로 자리가 없습니다" % motion)
		return
	set_motion_offset(e, motion, null, "장비: %s %s 자리 지우기" % [e.name, motion])
	_set_status("%s — %s 은 기본 자리로" % [e.name, motion])


func copy_motion_offset(motion: String) -> void:
	var e := _offset_equip()
	if e == null:
		return
	_offset_clip = DRCharacter3D.offset_for(e, motion)
	_set_status("복사: %s 의 무기 자리(%s) — 다른 동작 행에서 오른쪽 누름 → 붙여넣기" % [motion, _offset_text(e, motion)])


func paste_motion_offset(motion: String) -> void:
	var e := _offset_equip()
	if e == null or not (_offset_clip is Transform3D):
		_set_status("붙여 넣을 무기 자리가 없습니다 — 먼저 복사")
		return
	set_motion_offset(e, motion, _offset_clip, "장비: %s %s 자리 붙여넣기" % [e.name, motion])
	_set_status("붙여넣기: %s 의 무기 자리 = %s" % [motion, _offset_text(e, motion)])


## 이 동작에 맞추기(자동) — 지금 동작 · 시점의 손(동작 그대로 = IK 전)에 무기 표지가 오게 그 동작 자리를 잡는다.
##   손 소켓(오른손 · 왼손) 무기: 든 손바닥을 축으로 돌려 따라가는 손 표지를 그 손바닥 쪽으로(무기가 쥔 손에서 안 미끄러진다)
##   두 손 사이(양손) 무기: 두 표지의 가운데 · 방향을 두 손바닥의 가운데 · 방향으로(남는 길이 차는 두 손 IK 가 나눠 진다)
##   그 동작에서 한 손만 잡으면(다른 손 IK 비중 0) 그 손 표지를 손바닥 자리로 옮긴다. 고정(땅) · 손 아닌 뼈 소켓은 안 함(무기가 손을 안 따라감)
## 돌려주는 값 {motion, before: [왼손 cm, 오른손 cm], after: [...]} — 따라가는 손의 IK 뒤 손바닥 ↔ 표지(-1 = 안 따라감). 못 하면 {}
func fit_motion_offset() -> Dictionary:
	var e := _offset_equip()
	var pe := _prev_node(e) as Node3D
	var mo := current_motion()
	if e == null or pe == null or _prev == null or mo == "":
		_set_status("무기와 동작을 고르세요")
		return {}
	var kind := grip_kind(e)
	if kind < 0 or kind >= 3:
		_set_status("%s — 고정(땅) 받침대 · 손이 아닌 뼈 소켓의 장비는 자동 맞추기가 없습니다(기즈모로)" % e.name)
		return {}
	var hold := 1 if kind == 0 else (0 if kind == 1 else -1)          # 무기를 든 손(받침인 손) — 양손이면 없음
	var t := _time_sl.value
	_force_pose()
	var sk := _prev.get_skeleton()
	var rig: DRRigModel = _prev.get_body_entry()["rig"]
	var palms: Array = [null, null]                                 # 손바닥(세상) — 갱신 밖이라 동작 그대로(IK 전)
	for side in 2:
		var part: DRRigModel.Part = rig.parts.get(String(DRCharacter3D.PALM_PARTS[side]), null)
		if part != null:
			palms[side] = sk.global_transform * (sk.get_bone_global_pose(part.root_bone) * (part.tail_local * 0.5))
	var follow: Array[int] = []
	var marks: Array[Vector3] = []
	for side in 2:
		if side == hold or palms[side] == null:
			continue
		var mk := DRCharacter3D.find_hand_marker(pe, side)
		if mk == null:
			continue
		if (mk is DRHandTarget3D and (mk as DRHandTarget3D).weight_for(mo) <= 0.001):
			continue
		follow.append(side)
		marks.append(mk.global_position)
	if follow.is_empty():
		_set_status("%s 에서 무기를 따라가는 손이 없습니다(표지 없음 · IK 비중 0) — 기즈모로" % mo)
		return {}
	var before := _hand_dists()
	var c := Transform3D.IDENTITY                                   # 세상 공간 고침
	if hold >= 0:
		var pivot: Vector3 = palms[hold]
		var v1 := marks[0] - pivot
		var v2: Vector3 = palms[follow[0]] - pivot
		if v1.length() < 0.01 or v2.length() < 0.01:
			_set_status("손이 무기 쥔 점과 겹쳐 방향을 못 잡습니다 — 다른 시점에서")
			return {}
		c = Transform3D(Basis.IDENTITY, pivot) * Transform3D(Basis(Quaternion(v1.normalized(), v2.normalized())), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot)
	elif follow.size() >= 2:
		var cm := (marks[0] + marks[1]) * 0.5
		var cp: Vector3 = (palms[follow[0]] + palms[follow[1]]) * 0.5
		var d1 := marks[1] - marks[0]
		var d2: Vector3 = palms[follow[1]] - palms[follow[0]]
		var q := Quaternion(d1.normalized(), d2.normalized()) if d1.length() > 0.01 and d2.length() > 0.01 else Quaternion.IDENTITY
		c = Transform3D(Basis.IDENTITY, cp) * Transform3D(Basis(q), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -cm)
	else:
		c = Transform3D(Basis.IDENTITY, palms[follow[0]] - marks[0])
	var anchor_p := pe.get_parent() as Node3D
	var l2: Transform3D = anchor_p.global_transform.affine_inverse() * (c * pe.global_transform)     # 받침 기준 새 자리
	set_motion_offset(e, mo, e.transform.affine_inverse() * l2, "장비: %s %s 자리 맞추기" % [e.name, mo])
	_seek(t)
	var after := _hand_dists()
	var txt := PackedStringArray()
	for side in follow:
		txt.append("%s 동작 그대로 %.1f → %.1f cm(IK 뒤 %.1f → %.1f)" % [DRCharacter3D.SIDE_NAMES[side], (before["raw"] as Array)[side], (after["raw"] as Array)[side],
			(before["ik"] as Array)[side], (after["ik"] as Array)[side]])
	_set_status("맞춤 — %s %d%% · %s · %s" % [mo, int(t * 100.0), _offset_text(e, mo), " · ".join(txt)])
	return {"motion": mo, "before": before["ik"], "after": after["ik"], "raw_before": before["raw"], "raw_after": after["raw"]}


## 손마다 손바닥 ↔ 표지(cm, 지금 자세) — {raw: 동작 그대로(IK 전), ik: IK 뒤}. 그 손이 무기를 안 따라가면 -1
func _hand_dists() -> Dictionary:
	var raw := [-1.0, -1.0]
	var ik := [-1.0, -1.0]
	if _prev != null:
		for side in 2:
			var r := _prev.support_report(side)
			if not r.is_empty():
				raw[side] = float(r["raw"]) * 100.0
				ik[side] = float(r["ik"]) * 100.0
	return {"raw": raw, "ik": ik}


## 동작 표의 무기 자리 칸 — ● 따로 · ↳ 상체 동작 것 · 기본
func _fill_offset_cell(it: TreeItem, motion: String) -> void:
	const C := 3                                # 무기 자리 칸
	var e := _offset_equip()
	if e == null:
		it.set_text(C, "-")
		return
	var key := DRCharacter3D.offset_key(e, motion)
	var hint := "\n두 번 누름 = 이 동작만 고치기 · 오른쪽 누름 = 맞추기 · 복사 · 붙여넣기 · 기본으로"
	if key == motion:
		var sz := DRCharacter3D.offset_size(e.transform, DRCharacter3D.offset_for(e, motion))
		it.set_text(C, "● %.1f cm · %.0f°" % [sz.x * 100.0, sz.y])
		it.set_custom_color(C, Color(0.96, 0.66, 0.3))
		it.set_tooltip_text(C, "%s — %s 은 따로 자리(기본 자리에서 %.1f cm · %.0f°)%s" % [e.name, motion, sz.x * 100.0, sz.y, hint])
	elif key != "":
		it.set_text(C, "↳ %s" % key)
		it.set_custom_color(C, Color(0.55, 0.76, 0.96))
		it.set_tooltip_text(C, "상하체 합성 — 상체 동작 %s 의 자리를 쓴다(%s). 이 동작만 따로 두려면 두 번 누름%s" % [key, _offset_text(e, motion), hint])
	else:
		it.set_text(C, "기본")
		it.set_custom_color(C, Color(0.55, 0.57, 0.6))
		it.set_tooltip_text(C, "%s — 기본 자리%s" % [e.name, hint])


## 동작 표에서 그 동작 행을 고른 모양으로(다시 틀지 않음)
func _mark_motion_row(motion: String) -> void:
	if _mt == null or _mt.get_root() == null:
		return
	var it := _mt.get_root().get_first_child()
	_mt_lock = true
	while it != null:
		if it.get_text(0) == motion:
			if not it.is_selected(0):
				it.select(0)
			_mt.scroll_to_item(it)
			break
		it = it.get_next()
	_mt_lock = false


## 동작 표 오른쪽 누름 — 그 행의 무기 자리 메뉴
func _on_mt_mouse(_pos: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_RIGHT:
		return
	var it := _mt.get_selected()
	var e := _offset_equip()
	if it == null or e == null:
		return
	_mt_menu_motion = it.get_text(0)
	var own := DRCharacter3D.offset_key(e, _mt_menu_motion) == _mt_menu_motion
	_mt_menu.clear()
	_mt_menu.add_item("이 동작만 고치기", 0)
	_mt_menu.add_item("이 동작에 맞추기(자동)", 1)
	_mt_menu.set_item_disabled(1, grip_kind(e) < 0 or grip_kind(e) >= 3)
	_mt_menu.add_separator()
	_mt_menu.add_item("무기 자리 복사", 2)
	_mt_menu.add_item("무기 자리 붙여넣기", 3)
	_mt_menu.set_item_disabled(3, not (_offset_clip is Transform3D))
	_mt_menu.add_item("기본 자리로(따로 자리 지우기)", 4)
	_mt_menu.set_item_disabled(4, not own)
	_mt_menu.add_separator()
	_mt_menu.add_item("조준 미리보기(이 동작)", 5)
	_mt_menu.add_item("조준 비중 기본으로", 6)
	_mt_menu.set_item_disabled(6, _root == null or not _root.aim_motion_weights.has(_mt_menu_motion))
	_mt_menu.reset_size()
	_mt_menu.popup_on_parent(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))


func _on_mt_menu(id: int) -> void:
	var mo := _mt_menu_motion
	if mo == "":
		return
	if mo != current_motion():
		play_motion(mo)
	match id:
		0:
			set_per_motion(true)
		1:
			fit_motion_offset()
		2:
			copy_motion_offset(mo)
		3:
			paste_motion_offset(mo)
		4:
			reset_motion_offset(mo)
		5:
			set_aim_preview(true)
		6:
			set_aim_weight(mo, null)
