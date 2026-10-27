@tool
extends DRPage
class_name DREquipPage

## ② 장비 탭(10-16, 3D 게임 정석) — 유닛 프리팹의 소켓 · 장비 편집기. 예전 ② 장비 굽기(2D 세트별 무기 그림 · DREquipWindow)를 갈음한다.
## 사용자(10-16): "2번 탭은 장비 3D 모델 하이어라키에 접근해 맞추는 방식, 즉 3D 게임 방식의 정석으로. 나중에 헬멧도 모델링 head 에 꽂으면 되고."
##   소켓 = 유닛 씬의 BoneAttachment3D(뼈를 따라감) · 장비 = 소켓 아래 모델 씬 인스턴스(자리 · 회전 = 소켓 기준 고정)
##   · 왼손 표지 = 장비 아래 DRHandTarget3D(왼팔 두 마디 IK 의 목표 — DRCharacter3D 가 조립 때 붙인다)
## 이 탭과 씬 독 · 인스펙터 · 3D 화면 기즈모가 **같은 노드**를 고친다(에디터 = 열린 유닛 씬 · 되돌리기 Ctrl+Z, 에디터 밖 = 인스턴스를 바로).
##
##   왼쪽(하는 차례 — 10-21 사용자 "직관적인 UI/UX, 에디터로서 훌륭하게"): 1 무기 · 소켓(나무 · 모델 · + 소켓) → 2 잡기(오른손 · 왼손 · 양손 · 고정 ·
##     손 표지 = 모든 동작 공통) → 3 무기 자리(**적용 범위 스위치 하나** — 모든 동작 / 이 동작만 · [손에 맞추기] 하나 · 숫자 칸) → 4 조준(칸 · 표지 · 미리보기)
##   가운데: 도구 줄(기즈모 · 눈금 · 보기) · 미리보기 — 돌려 보기 + **유니티식 기즈모**(ui/transform_gizmo.gd, 10-16) / 도트 보기(게임과 같은 DRDotView3D) ·
##     이 동작만이면 주황 테두리 + 꼬리표 · 타임라인(재생 / 멈춤 Space · 동작 이름 · 프레임 · 초) · 상태 줄 · 손 ↔ 표지 거리
##     단축키(유니티와 같음): Q 보기 · W 이동 · E 회전 · R 크기 · Y 변환 · X 로컬/글로벌 · Z 피벗/중심 · F 고른 것 보기 · Ctrl 끌기 = 눈금 ·
##     Ctrl+Z / Ctrl+Y(Ctrl+Shift+Z) 되돌리기 / 다시 · Ctrl+S 저장. 카메라: 휠 · 가운데 끌기(옮기기) · 오른쪽 / Alt+왼쪽 끌기(돌려 보기) · Alt+오른쪽(확대)
##     미리보기를 누르면(끌지 않고) 그 자리의 왼손 표지 · 소켓 · 장비를 고른다(빈 곳 = 고르기 풀기). 기즈모를 놓으면 유닛 씬에 되돌리기 한 칸
##   오른쪽: 동작마다 왼손(IK 전 · 뒤 cm) · 왼손 IK 비중(0 = 동작 그대로 — 수류탄 · 장전 · 맨손 달리기 등) · 무기 자리 · 조준 비중
##   조준 IK(10-21): 왼쪽 "조준" 칸(켜기 · 위로 · 아래로 최대 ° · 빠르기 · 팔 몫 % + 설명 — 유닛 루트) · 가운데 [조준 미리보기](표적 높이를 끌면 팔이 견착점(노란 십자)
##     축으로 총을 들고 허리 · 가슴이 나머지 — 총구 선이 표적 십자로. 좌우는 없음) · 동작 표 "조준" 칸(그 동작의 조준 비중 — 기본 = 동작 표의 사격 · 조준 상태면 1)
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
var _cur_motion := ""                     # 미리보는 동작(오른쪽 표에서 고름 — 10-21 아래 동작 칸은 표와 겹쳐 뺐다)
var _motion_lbl: Label                    # 타임라인의 동작 이름
var _play_btn: Button
var _time_sl: HSlider
var _time_lbl: Label                      # 타임라인의 초(지금 / 길이)
var _view_btn: Button
var _playing := true
var _acc := 0.0
var _info: Label
var _live: Array = []                     # 미리보기 뼈대가 갱신될 때 잰 손마다(IK 뒤) [왼손, 오른손] — support_now
var _grip_btns: Array[Button] = []        # 잡기: 오른손 · 왼손 · 양손 · 고정(이 동작만이면 그 동작의 잡기 — 고정은 잠김)
var _grip_reset_btn: Button               # [↺ 이 동작 기본 잡기로](이 동작만일 때)
var _blend_sl: HSlider
var _blend_lbl: Label
var _grip_info: Label
# 동작 표
var _mt: Tree
var _mt_lock := false
var _last_rep: Array = []                 # 마지막으로 잰 동작별 수치(_measure — 동작마다 두 손 중 붙은 손의 나쁜 쪽)
var _rep_stale := false                   # 잰 뒤 무기 · 표지 자리가 바뀜(다시 재야 맞음)
# 동작별 무기 자리(10-19) · 동작마다 잡기(10-27)
var _per_motion := false                  # 2 잡기 · 3 무기 자리가 "이 동작만"을 고친다 — false = 모든 동작(기본 잡기 · 기본 자리)
var _pm_btns: Array[Button] = []          # 맨 위 적용 범위: 모든 동작 · 이 동작만(이 탭에서 범위를 바꾸는 곳은 여기 하나)
var _common_ctrls: Array[Control] = []    # 모든 동작 공통 값(무기 · 소켓 · 보간 · 조준 켜기)을 고치는 칸 — 이 동작만이면 잠김(10-27)
var _pm_banner: PanelContainer            # 미리보기 왼쪽 위 꼬리표(이 동작만일 때 — 단추 없음)
var _pm_label: Label
var _pm_frame: Panel                      # 미리보기 둘레 주황 테두리(이 동작만일 때)
var _scope_note: Label                    # 적용 범위 아래 — 지금 무엇을 고치는지 한 줄
var _pm_fit_btn: Button                   # [손에 맞추기] — 범위대로(모든 동작 = 기본 자리 · 이 동작만 = 그 동작 자리)
var _pm_reset_btn: Button
var _marker_btns: Array[Button] = []      # 표지(손 · 총구 · 견착 — 모든 동작 공통)를 고치는 단추 — 이 동작만이면 잠김
var _xf_note: Label                       # 숫자 칸 아래 — 동작별 자리 안내
var _mt_menu: PopupMenu                   # 동작 표 오른쪽 누름
var _mt_menu_motion := ""
var _offset_clip: Variant = null          # 복사한 동작별 자리(Transform3D)
# 조준 IK(10-21)
## [유닛 칸, 이름, 최소, 최대, 눈금, 풍선 도움말, (보이는 값 × 이 수 = 유닛 값)] — 이름 = 무엇을 바꾸는지 그대로(10-21 사용자 "위 한계는 이해가 가는데 각도 한계잖아?")
const AIM_FIELDS := [["aim_up_deg", "위로 최대 °", 0.0, 80.0, 1.0, "각도 한계 — 동작이 원래 겨눈 높이에서 총구를 위로 더 들 수 있는 최대 각. 표적이 더 높아도 여기서 멈춘다(크면 몸이 많이 젖혀짐)"],
	["aim_down_deg", "아래로 최대 °", 0.0, 80.0, 1.0, "각도 한계 — 동작이 원래 겨눈 높이에서 총구를 아래로 더 내릴 수 있는 최대 각"],
	["aim_speed_deg", "빠르기 °/s", 30.0, 1440.0, 10.0, "표적 높이가 바뀔 때 총구가 따라가는 속도(초당 각) — 240 이면 30° 를 0.13 초에"],
	["aim_arm_share", "팔 몫 %", 0.0, 100.0, 5.0, "드는 각 중 팔이 맡는 비율 — 개머리판을 어깨에 댄 채(견착점 = 노란 십자) 두 팔이 총을 들고 내린다. 나머지는 허리 · 가슴이 숙이고 젖힌다. " +
		"100 = 팔만 · 0 = 허리 · 가슴만", 0.01]]
const AIM_HELP := "사격 · 조준 동작에서 표적 높이에 맞춰 총구를 위아래로 든다(좌우는 동작 그대로).\n" + \
	"· 위로 · 아래로 최대: 동작이 원래 겨눈 높이에서 더 들 · 내릴 수 있는 최대 각도\n" + \
	"· 빠르기: 표적 높이가 바뀔 때 총구가 따라가는 속도(초당 °)\n" + \
	"· 팔 몫: 드는 각 중 팔이 맡는 비율(나머지는 허리 · 가슴)"
const AIM_MARK_M := 1.5                   # 미리보기 표적 십자 · 총구 선 길이(m)
var _aim_chk: CheckBox
var _aim_sp: Dictionary = {}              # 칸 이름 -> SpinBox
var _aim_lock := false
var _aim_btn: Button                      # 조준 미리보기
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

	# 왼쪽 — 하는 차례대로: 1 무기 · 소켓 → 2 잡기 → 3 무기 자리 → 4 조준(10-21 사용자 "직관적인 UI/UX — 에디터로서 훌륭하게").
	# 같은 일을 하는 단추는 한 곳에만 — 적용 범위(모든 동작 / 이 동작만) = 3 의 스위치 하나 · 손에 맞추기 = 3 의 단추 하나
	var lsc := ScrollContainer.new()
	lsc.custom_minimum_size = Vector2(370, 0)
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(lsc)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
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
	_btn(urow, "↻", "game/units 의 유닛 씬을 다시 찾는다", scan_units)
	_btn(urow, "씬 열기", "에디터에 이 유닛 씬을 연다", func() -> void:
		if _sel_path != "" and Engine.is_editor_hint():
			EditorInterface.open_scene_from_path(_sel_path))
	_btn(urow, "저장", "이 유닛 씬을 저장(Ctrl+S)", save_unit)

	# 적용 범위 — 이 탭 전체에 하나(10-21 3 무기 자리의 스위치 → 10-27 맨 위로). 사용자: "각 동작마다 어느 손이 잡기 기준인가 이런 것도 조작하고 싶은데
	# 전역으로 설정됨. 이 동작만 버튼 눌러도 … ux 적으로 일관적이지 않은 건가" — 2 잡기 · 3 무기 자리 = 범위대로, 모든 동작 공통인 것
	# (무기 · 소켓 · 받침대 · 보간 · 손 표지 · 조준 칸 · 조준 표지)은 이 동작만이면 잠긴다
	var prow := HBoxContainer.new()
	left.add_child(prow)
	var pl := Label.new()
	pl.text = "적용 범위"
	pl.add_theme_font_size_override("font_size", 15)
	prow.add_child(pl)
	var pg := ButtonGroup.new()
	for m in [[false, "모든 동작", "기본 — 2 잡기 = 기본 잡기(따로 정하지 않은 동작 모두) · 3 무기 자리 = 기본 자리.\n" +
				"지금 동작에 따로 자리가 있으면 보이는 자리 = 기본 자리 + 그 차이(옮기면 기본 자리가 바뀌고 차이는 그대로)"],
			[true, "✎ 이 동작만", "지금 동작(오른쪽 표에서 고른 것)만 — 2 잡기(어느 손이 총에 붙나) · 3 무기 자리(위치 · 회전). 기본 · 다른 동작은 그대로.\n" +
				"오른쪽 표에서 행을 두 번 눌러도 된다. 무기 · 소켓 · 받침대 · 보간 · 손 표지 · 조준 칸은 모든 동작 공통이라 이때는 잠긴다"]]:
		var b := Button.new()
		b.text = String(m[1])
		b.toggle_mode = true
		b.button_group = pg
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = String(m[2])
		var on: bool = m[0]
		b.pressed.connect(func() -> void: set_per_motion(on))
		prow.add_child(b)
		_pm_btns.append(b)
	_scope_note = _note(left, "", Color(0.72, 0.8, 0.9), 12)

	# 1 무기 · 소켓
	_section(left, "1", "무기 · 손", "손 기준 — 장비는 지금 동작에서 쥔 손 아래에 보인다. 장비를 끌어 다른 손에 놓으면 잡기(맨 위 범위대로) · " +
		"✋ 손을 고르면 기즈모로 그 손이 쥐는 자리만 옮김(총은 그대로)")
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.allow_search = false              # 글자를 치면 찾기로 먹어 버려 W · E · R 단축키가 안 간다
	_tree.custom_minimum_size = Vector2(0, 230)          # 손 줄 넷 + 장비 + 조준 표지가 스크롤 없이(10-27 손 기준 나무)
	_tree.item_selected.connect(_on_tree_selected)
	_tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM
	_tree.set_drag_forwarding(_tree_drag, _tree_can_drop, _tree_drop)   # 장비를 끌어 손에 놓으면 잡기(10-27)
	left.add_child(_tree)
	var mrow := HBoxContainer.new()
	left.add_child(mrow)
	_model_ob = OptionButton.new()
	_model_ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_model_ob.clip_text = true
	_model_ob.tooltip_text = "넣을 장비 모델(source3d/weapons/** 의 무기 씬 · glb). 무기 기본 자리(asset.json)가 있으면 그 자리 · 손 표지로 넣는다"
	mrow.add_child(_model_ob)
	_common(_btn(mrow, "넣기 · 바꾸기", "고른 소켓(또는 고른 장비의 소켓)에 이 모델을 넣는다. 이미 있으면 바꾼다 — 부모 유닛에서 온 장비는 지울 수 없어 숨긴다", func() -> void:
		put_model(String(_model_ob.get_item_metadata(_model_ob.selected)) if _model_ob.selected >= 0 else "")))
	_common(_btn(mrow, "빼기", "고른 장비(또는 소켓)를 뺀다 — 부모 유닛에서 온 것은 숨긴다", remove_selected))
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
	_common(_btn(srow, "+ 소켓", "고른 뼈에 소켓(BoneAttachment3D)을 더한다 — 유닛 씬에 노드로 들어간다", func() -> void:
		add_socket(_sock_name.text, String(_bone_ob.get_item_metadata(_bone_ob.selected)) if _bone_ob.selected >= 0 else "")))

	# 2 잡기 — 총에 붙을 손(10-16 사용자: "오른손 · 왼손 · 양손 — 조인트 느낌" · 10-27 "오른손이면 총기를 움직일 때 오른손이 붙여져 있는 상태로")
	_section(left, "2", "잡기", "총에 붙을 손 — 고른 손은 총의 손 표지를 쥐고(IK) 총을 옮기면 같이 따라옴, 안 고른 손은 동작 그대로. " +
		"맨 위 적용 범위대로: 모든 동작 = 기본 잡기(받침) · 이 동작만 = 그 동작의 잡기")
	var grow := HBoxContainer.new()
	left.add_child(grow)
	var gg := ButtonGroup.new()
	for g in [[0, "오른손", "오른손만 총에 붙음 — 총이 오른손 동작을 따라가고, 총을 옮기면 오른손이 같이 따라옴(IK). 왼손은 동작 그대로 — 권총처럼 한 손으로 드는 장비"],
			[1, "왼손", "왼손만 총에 붙음 — 총이 왼손 동작을 따라가고, 총을 옮기면 왼손이 같이 따라옴(IK). 오른손은 동작 그대로"],
			[2, "양손", "두 손이 다 총에 붙음 — 총이 두 손 사이(아래 보간)를 따라가고, 총을 옮기면 두 손이 같이 따라옴(IK) — 소총 · mp40 처럼 두 손으로 드는 무기"],
			[3, "고정", "총이 유닛(땅)에 고정 — 두 손이 총 표지를 쥠(IK). 받침대를 옮기면 총과 두 손이 같이 — 라페테(삼각대) 위 MG42 · 거치 무기"]]:
		var b := Button.new()
		b.text = String(g[1])
		b.toggle_mode = true
		b.button_group = gg
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = String(g[2]) + "\n모든 동작: 기본 잡기(받침)를 바꾼다 — 전에 쓰던 잡기로 돌아가면 그때 자리 그대로. 처음 가는 잡기는 지금 보이는 자리 그대로 받침만 바꾸고" + \
			"(붙을 손이 총에 있는 프레임에서 고르세요), 붙을 손의 표지가 없으면 그 손의 지금 자리로 만든다.\n이 동작만: 지금 동작에서 총에 붙을 손만 바꾼다(받침 · 다른 동작은 그대로" + \
			(" — 고정은 받침이라 모든 동작에서만)" if int(g[0]) == 3 else ")") + ". 되돌리기 한 칸"
		b.set_meta(&"tip", b.tooltip_text)
		var kv: int = g[0]
		b.pressed.connect(func() -> void: _on_grip_btn(kv))
		grow.add_child(b)
		_grip_btns.append(b)
	var grrow := HBoxContainer.new()
	left.add_child(grrow)
	_grip_reset_btn = _btn(grrow, "↺ 이 동작 기본 잡기로", "이 동작의 잡기를 지운다 — 기본 잡기(모든 동작)대로(되돌리기 한 칸)", func() -> void: set_motion_grip(current_motion(), -1))
	_grip_reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	_common(_blend_sl)
	_grip_info = _note(left, "", Color(0.72, 0.8, 0.9), 12)
	_note(left, "손 표지 — 총의 어디를 쥐나 · 모든 동작 공통", Color(0.88, 0.9, 0.94), 13)
	var frow := HFlowContainer.new()
	left.add_child(frow)
	_marker_btn(frow, "왼손 표지 ← 지금 손", "지금 프레임의 왼손(동작 그대로) 자리 · 회전을 고른 장비의 왼손 표지로(없으면 만든다) — 모든 동작에 쓰인다.\n" +
		"두 손이 총에 있는 프레임(예: Rifle_Aiming_Idle)에서 누르세요", func() -> void: make_hand_marker(0))
	_marker_btn(frow, "오른손 표지 ← 지금 손", "지금 프레임의 오른손(동작 그대로) 자리 · 회전을 고른 장비의 오른손 표지로(없으면 만든다) — 모든 동작에 쓰인다.\n" +
		"잡기가 오른손 · 양손 · 고정일 때 오른손이 이 표지를 쥔다", func() -> void: make_hand_marker(1))

	# 3 무기 자리 — 위 적용 범위대로 기즈모 · 숫자 칸 · 손에 맞추기(10-21 사용자 "전체 동작 · 이 동작만 — 버튼이 단일화")
	_section(left, "3", "무기 자리", "몸(소켓 · 두 손) 기준 총 위치 · 회전 — 맨 위 적용 범위대로(기즈모 · 숫자 칸 · [손에 맞추기])")
	var fitrow := HBoxContainer.new()
	left.add_child(fitrow)
	_pm_fit_btn = _btn(fitrow, "🤚 손에 맞추기", "", fit_to_hands)
	_pm_fit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pm_fit_btn.clip_text = true
	_pm_reset_btn = _btn(fitrow, "↺ 이 동작 기본으로", "이 동작의 따로 자리를 지운다(기본 자리로) — 되돌리기 한 칸", func() -> void: reset_motion_offset(current_motion()))
	_xf_title = Label.new()
	_xf_title.text = "고른 노드 —"
	_xf_title.clip_text = true
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
				(" — 크기는 장비만(손 표지 · 소켓은 없음)" if is_scl else "")
			sp.value_changed.connect(func(_v: float) -> void: _on_xf_changed())
			grid.add_child(sp)
			(row[1] as Array).append(sp)
	_xf_note = _note(left, "", Color(0.96, 0.7, 0.36), 12)
	_xf_note.visible = false
	var erow := HFlowContainer.new()
	left.add_child(erow)
	_btn(erow, "에디터에서 고르기", "이 노드를 에디터에서 골라 3D 화면 기즈모로 옮긴다(탭과 같은 노드)", _on_edit_in_editor)
	_btn(erow, "무기 기본 자리로 저장", "고른 장비의 자리 · 손 표지 · 동작별 비중 · 동작별 자리 · 조준 표지(총구 · 견착)를 모델 옆 asset.json(socket_hold)에 — 다른 유닛 소켓에 넣을 때 처음 자리", save_hold_default)

	# 4 조준 IK(10-21) — 유닛 루트 칸. 사용자: "사격할 때 적을 바라보는 벡터 기준으로 허리가 살짝 굽거나 — 총구가 적을 바라봐야 되니까"
	_section(left, "4", "조준", "사격 · 조준 동작에서 표적 높이로 총구를 듦 — 팔(견착점 축)이 주로, 나머지 허리 · 가슴. 좌우는 동작 그대로")
	_aim_chk = CheckBox.new()
	_aim_chk.text = "조준 IK 켜기"
	_aim_chk.focus_mode = Control.FOCUS_NONE
	_aim_chk.tooltip_text = "조준 IK — 사격 · 조준 동작에서 총구 높낮이가 표적(게임이 주는 적의 겨눌 곳)을 향하게 한다(좌우는 동작 그대로 — 횡스크롤).\n" + \
		"팔(개머리판을 어깨에 댄 채 견착점 축으로 총을 듦 — 팔 몫 %) + 허리 · 가슴(나머지). 두 손은 총 표지 IK 로 따라온다"
	_aim_chk.set_meta(&"tip", _aim_chk.tooltip_text)
	_aim_chk.toggled.connect(func(on: bool) -> void: set_aim_setting("aim_enabled", on))
	left.add_child(_aim_chk)
	_note(left, AIM_HELP, Color(0.62, 0.66, 0.72), 11)          # 칸 설명(10-21 사용자 "설명이 필요한 것 같아")
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
		var scale: float = f[6] if f.size() > 6 else 1.0          # 칸에 보이는 값 × scale = 유닛 값(팔 몫 % → 0 ~ 1)
		sp.set_meta(&"aim_scale", scale)
		sp.value_changed.connect(func(v: float) -> void: set_aim_setting(prop, v * scale))
		agrid.add_child(sp)
		_aim_sp[prop] = sp
	# 조준 표지(10-21) — 레이(총구 선)가 나가는 자리 · 팔 몫의 축을 기즈모로. 사용자: "그 위치를 조정할 수 있는 기즈모 기능 연동도 필요해"
	var amrow := HFlowContainer.new()
	left.add_child(amrow)
	_marker_btn(amrow, "총구 표지", "레이(총구 선)가 나가는 자리 · 방향 — 무기 아래 \"총구\" 표지를 만들고(없으면 지금 잰 총열 끝에) 고른다. 기즈모 W 이동 · E 회전(파란 축 = 방향)\n" +
		"유닛 씬에 저장 · [무기 기본 자리로 저장] 이면 asset.json 에도(다른 유닛에 넣을 때 따라감)", func() -> void: make_aim_marker(DRCharacter3D.MUZZLE_NAME))
	_marker_btn(amrow, "견착 표지", "팔 몫 조준의 축(개머리판을 어깨에 대는 점) — 무기 아래 \"견착\" 표지를 만들고(없으면 지금 잰 개머리판 끝에) 고른다. 기즈모 W 이동",
		func() -> void: make_aim_marker(DRCharacter3D.SHOULDER_NAME))
	_marker_btn(amrow, "표지 지우고 자동으로", "총구 · 견착 표지를 지운다 — 무기 메시에서 다시 잰다(총열 축 앞 끝 · 개머리판 끝 가운데). 되돌리기 한 칸", clear_aim_markers)
	# 조준 미리보기 — 표적 대신 높낮이로(총구 높낮이, 수평 0). 좌우는 없다(횡스크롤 — 사용자 "옆은 필요 없는 것 같아")
	var arow := HBoxContainer.new()
	left.add_child(arow)
	_aim_btn = Button.new()
	_aim_btn.text = "조준 미리보기"
	_aim_btn.toggle_mode = true
	_aim_btn.focus_mode = Control.FOCUS_NONE
	_aim_btn.tooltip_text = "미리보기 병사가 표적(분홍 십자)을 겨누게 한다 — 표적 높이를 끌어 팔 · 허리가 어떻게 움직이는지 본다(꺼진 채 끌어도 켜진다).\n" + \
		"총구 선: 초록 = 표적으로 · 주황 = 한계에서 멈춤 · 노란 십자 = 견착점(팔 몫의 축). 조준 비중이 0 인 동작(서기 · 걷기 · 장전 …)은 안 움직인다 — 오른쪽 표 \"조준\" 칸"
	_aim_btn.toggled.connect(set_aim_preview)
	arow.add_child(_aim_btn)
	var hl := Label.new()
	hl.text = "표적 높이"
	arow.add_child(hl)
	_aim_height_sl = HSlider.new()
	_aim_height_sl.min_value = -60.0
	_aim_height_sl.max_value = 60.0
	_aim_height_sl.step = 1.0
	_aim_height_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_aim_height_sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_aim_height_sl.tooltip_text = "총구에서 본 표적의 높낮이(수평 = 0, 위 +) — 높은 벽 위 · 참호 아래 · 엎드린 적. 좌우는 없다(횡스크롤)"
	_aim_height_sl.value_changed.connect(func(_v: float) -> void:
		if _aim_preview:
			_apply_aim_preview()
		else:
			set_aim_preview(true))               # 꺼진 채 끌면 켠다(끌어도 아무 일이 없는 함정 — 10-21 사용자 "변화 없는데?")
	arow.add_child(_aim_height_sl)
	_aim_lbl = _note(left, "", Color(0.85, 0.87, 0.9), 12)

	var right_split := HSplitContainer.new()
	right_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right_split)

	# 가운데 — 도구 줄 · 미리보기 · 타임라인 · 상태 줄
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.custom_minimum_size = Vector2(340, 0)
	right_split.add_child(mid)
	_build_gizmo_bar(mid)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.custom_minimum_size = Vector2(320, 320)
	stack.clip_contents = true               # 기즈모 손잡이가 화면 밖(무기가 미리보기 밖)이면 왼쪽 칸 위에 그려지던 것(10-21)
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
	# 이 동작만이면 미리보기 둘레 주황 테두리 + 왼쪽 위 꼬리표 — 지금 무엇을 고치는지 늘 보이게. 단추는 없다(범위는 왼쪽 "3 무기 자리" 한 곳에서만)
	_pm_frame = Panel.new()
	_pm_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pm_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fs := StyleBoxFlat.new()
	fs.draw_center = false
	fs.set_border_width_all(3)
	fs.border_color = Color(0.95, 0.6, 0.18)
	_pm_frame.add_theme_stylebox_override("panel", fs)
	_pm_frame.visible = false
	stack.add_child(_pm_frame)
	_pm_banner = PanelContainer.new()
	_pm_banner.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_pm_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pbs := StyleBoxFlat.new()
	pbs.bg_color = Color(0.95, 0.6, 0.18)
	pbs.content_margin_left = 8
	pbs.content_margin_right = 8
	pbs.content_margin_top = 2
	pbs.content_margin_bottom = 3
	pbs.corner_radius_bottom_right = 4
	_pm_banner.add_theme_stylebox_override("panel", pbs)
	_pm_banner.visible = false
	_pm_label = Label.new()
	_pm_label.add_theme_color_override("font_color", Color(0.12, 0.07, 0.02))
	_pm_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pm_banner.add_child(_pm_label)
	stack.add_child(_pm_banner)
	_sync_gizmo_bar()
	# 타임라인 — 미리보는 동작(오른쪽 표에서 고름) · 재생 / 멈춤(Space) · 프레임(멈춘 채 끌어 자세를 고름 — 손에 맞추기 · 손 표지 · 처음 가는 잡기의 기준)
	var tl := HBoxContainer.new()
	mid.add_child(tl)
	_play_btn = Button.new()
	_play_btn.text = "⏸"
	_play_btn.focus_mode = Control.FOCUS_NONE
	_play_btn.custom_minimum_size = Vector2(34, 0)
	_play_btn.tooltip_text = "재생 · 멈춤(Space)"
	_play_btn.pressed.connect(toggle_play)
	tl.add_child(_play_btn)
	_motion_lbl = Label.new()
	_motion_lbl.custom_minimum_size = Vector2(150, 0)
	_motion_lbl.clip_text = true
	_motion_lbl.tooltip_text = "미리보는 동작 — 오른쪽 표에서 행을 눌러 고른다"
	_motion_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	tl.add_child(_motion_lbl)
	_time_sl = HSlider.new()
	_time_sl.min_value = 0.0
	_time_sl.max_value = 1.0
	_time_sl.step = 0.001
	_time_sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_time_sl.tooltip_text = "프레임 — 끌면 멈추고 그 자세를 본다. [손에 맞추기] · 손 표지 · 처음 가는 잡기가 이 프레임의 자세를 기준으로 쓴다"
	_time_sl.value_changed.connect(_on_time)
	tl.add_child(_time_sl)
	_time_lbl = Label.new()
	_time_lbl.custom_minimum_size = Vector2(96, 0)
	_time_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time_lbl.add_theme_font_size_override("font_size", 12)
	tl.add_child(_time_lbl)
	# 상태 줄 — 방금 한 일 · 경고(왼쪽 칸 맨 아래에 있으면 스크롤에 가려 안 보였다)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(0.93, 0.86, 0.6))
	mid.add_child(_status)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 11)
	_info.add_theme_color_override("font_color", Color(0.66, 0.69, 0.74))
	mid.add_child(_info)

	# 오른쪽 — 동작마다 손 · 무기 자리
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(470, 0)
	right_split.add_child(right)
	var rrow := HBoxContainer.new()
	right.add_child(rrow)
	var rl := Label.new()
	rl.text = "동작마다 잡기 · 무기 자리"
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rrow.add_child(rl)
	_btn(rrow, "모든 동작 재기", "동작마다 8 시점에서 두 손바닥 ↔ 표지 거리(IK 전 = 동작 그대로 · IK 뒤) — 미리보기 사본으로 잰다. 칸 = 그 동작에서 총에 붙은 손 중 먼 쪽", measure_all)
	_mt = Tree.new()
	# 칸: 동작 | 손 ↔ 표지(IK 전 → 뒤 평균 — 최대는 풍선 도움말) | 잡기 | 무기 자리 | 조준. 10-19 무기 자리 칸을 넣으며 IK 전 · 뒤 두 칸을 하나로(탭 기본 크기에서 가로로 안 넘치게).
	# 10-27 [왼손 ▼] + IK 비중 칸 → 잡기 칸 하나(사용자 "각 동작마다 어느 손이 잡기 기준인가 이런 것도 조작하고 싶은데" — 같은 값을 두 손 따로 숫자로 보던 것)
	_mt.columns = 5
	_mt.hide_root = true
	_mt.column_titles_visible = true
	_mt.set_column_title(0, "동작")
	_mt.set_column_title(1, "손↔표지 cm")
	_mt.set_column_title(2, "잡기")
	_mt.set_column_title(3, "무기 자리")
	_mt.set_column_title(4, "조준")
	_mt.set_column_title_tooltip_text(1, "총에 붙은 손바닥 ↔ 표지 거리(두 손이면 먼 쪽), 8 시점 평균: 동작 그대로(IK 전) → IK 뒤. 손마다 · 최대는 칸의 풍선 도움말 — [모든 동작 재기]")
	_mt.set_column_title_tooltip_text(2, "그 동작에서 총에 붙는 손(눌러서 고름) — 기본(…) = 2 잡기의 기본 잡기대로 · 주황 = 이 동작만 따로.\n" +
		"이 동작만 범위에서 2 잡기 단추로도 바꾼다. 붙지 않는 손은 동작 그대로(수류탄 · 장전 · 맨손 달리기처럼 총을 놓는 동작)")
	_mt.set_column_title_tooltip_text(3, "그 동작의 무기 위치 · 회전 — ● 따로 둠(기본 자리에서 거리 · 각) · ↳ 상하체 합성의 상체 동작 것 · 기본")
	_mt.set_column_title_tooltip_text(4, "그 동작의 조준 비중(0 = 동작 그대로 · 1 = 총구가 표적으로) — 흐린 값 = 기본(동작 표의 사격 · 조준 상태면 1)")
	_mt.set_column_expand(0, true)
	_mt.set_column_clip_content(0, true)        # 좁으면 동작 이름을 줄여서(다른 칸이 밀려나지 않게)
	for cw in [[1, 88], [2, 92], [3, 100], [4, 56]]:
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
	help.text = "행 누름 = 그 동작 보기 · 두 번 누름 = 그 동작만 고치기(적용 범위 = 이 동작만) · 오른쪽 누름 = 손에 맞추기 · 복사 · 붙여넣기 · 기본으로.\n" + \
		"잡기 = 그 동작에서 총에 붙는 손(주황 = 따로 · 기본(…) = 2 잡기대로 — 수류탄 · 장전 · 맨손 달리기처럼 한 손을 놓는 동작은 오른손 등). " + \
		"무기 자리 = ● 따로 둠 · ↳ 상하체 합성의 상체 동작 것 · 기본. 조준 = 사격 때 총구를 표적 높이로(흐림 = 기본)."
	right.add_child(help)
	_fill_bones(PackedStringArray())
	_fill_models()
	_dots.visible = false
	_update_cam()


## 왼쪽 칸 단계 머리 — 번호 · 이름 · 한 줄 설명(무엇을 하는 곳인지 먼저 보이게)
func _section(parent: Control, num: String, title: String, sub: String) -> void:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.2, 0.24, 0.3)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 4
	sb.set_corner_radius_all(3)
	pc.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	pc.add_child(v)
	var t := Label.new()
	t.text = "%s   %s" % [num, title]
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	v.add_child(t)
	_note(v, sub, Color(0.7, 0.76, 0.84), 11)
	parent.add_child(pc)


## 작은 설명 글(줄 바꿈)
func _note(parent: Control, text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


## 모든 동작 공통 값(무기 · 소켓 · 보간)을 고치는 칸 — 적용 범위가 "이 동작만"이면 잠근다(_update_pm_ui, 10-27)
func _common(c: Control) -> Control:
	c.set_meta(&"tip", c.tooltip_text)
	_common_ctrls.append(c)
	return c


## 표지(손 · 총구 · 견착 — 모든 동작 공통)를 고치는 단추 — 적용 범위가 "이 동작만"이면 잠근다(_update_pm_ui)
func _marker_btn(parent: Control, text: String, tip: String, cb: Callable) -> Button:
	var b := _btn(parent, text, tip, cb)
	b.set_meta(&"tip", tip)
	_marker_btns.append(b)
	return b


## 미리보기 위 도구 줄 — 유니티 툴바와 같은 자리 · 같은 단축키. 끝에 보기(돌려 보기 ↔ 도트 · 손 · 전신)
func _build_gizmo_bar(parent: Control) -> void:
	var bar := HFlowContainer.new()
	parent.add_child(bar)
	var group := ButtonGroup.new()
	for t in [[TransformGizmo.Tool.VIEW, "✋ Q", "Q — 보기: 손잡이 없음. 왼쪽 끌기 = 화면 옮기기"],
			[TransformGizmo.Tool.MOVE, "✥ W 이동", "W — 이동: 축 화살표 · 평면 네모 · 가운데 네모(화면 평면)"],
			[TransformGizmo.Tool.ROTATE, "⟳ E 회전", "E — 회전: 축 고리(고리를 따라 끈다) · 바깥 고리(화면 축) · 안쪽(자유)"],
			[TransformGizmo.Tool.SCALE, "⤢ R 크기", "R — 크기: 축 끝 네모(로컬 축) · 가운데(전체 — 오른쪽 · 위로 끌면 커짐). 손 표지 · 소켓은 크기 없음"],
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
	bar.add_child(VSeparator.new())
	_view_btn = _btn(bar, "도트 보기", "돌려 보기(가까이 · 기즈모) ↔ 도트 보기(게임 화면과 같은 저해상도 · 외곽선)", func() -> void: set_dot_mode(not _dot_mode))
	_btn(bar, "손", "두 손 · 무기를 가까이", func() -> void: focus_hands())
	_btn(bar, "전신", "몸 전체", func() -> void: focus_body())


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
	if _per_motion and ((_is_marker(n) and not _is_hand_marker(n)) or n is DRGripMount3D):   # 조준 표지 · 고정 받침대는 모든 동작 공통(10-21 "전부 다 뒤틀려") — 손 표지는 그 동작 자리로(10-27)
		return null
	return _prev_node(n) as Node3D


## 손 표지(크기가 뜻이 없음) — DRHandTarget3D 또는 장비 아래 이름이 "왼손" · "오른손" 인 Node3D(받침은 빼고)
static func _is_marker(n: Node) -> bool:
	return n is DRHandTarget3D or (n is Node3D and not _is_anchor(n) and (DRCharacter3D.SIDE_NAMES.has(String(n.name)) or _is_aim_marker(n)))


## 조준 표지(10-21) — 장비 아래 이름이 "총구" · "견착" 인 Node3D(받침은 빼고)
static func _is_aim_marker(n: Node) -> bool:
	return n is Node3D and not _is_anchor(n) and (String(n.name) == DRCharacter3D.MUZZLE_NAME or String(n.name) == DRCharacter3D.SHOULDER_NAME)


## 기즈모로 끄는 중 — 미리보기 사본만(왼손 IK 목표 · 숫자 칸이 따라온다). 유닛 씬은 놓을 때
func _on_giz_changed(pn: Node3D) -> void:
	if _prev != null:
		_prev.sync_support()
		if _is_aim_marker(pn):
			_prev.refresh_muzzle()               # 끄는 동안에도 레이 · 견착점이 따라오게
		_force_pose()
	_show_xform_of(pn)


## 기즈모를 놓았다 — 미리보기에서 옮긴 자리를 유닛 씬의 같은 노드에(에디터 = 되돌리기 한 칸 · Ctrl+Z).
## 장비: 이 동작만이면 그 동작의 동작별 자리로, 모든 동작이면 지금 얹힌 이 동작 차이를 빼고 기본 자리로(보이는 자리 = 기본 × 차이)
func _on_giz_end(pn: Node3D, _before: Transform3D) -> void:
	var n := _node(_sel) as Node3D
	if n == null or pn == null or _prev_node(n) != pn:
		return
	var after := pn.transform
	if _is_posed(n) and _prev != null:
		if _per_motion:
			var mo := current_motion()
			if mo == "":
				_set_status("동작을 고르세요 — 이 동작만 자리는 동작마다 저장된다")
				_sync_preview()
				return
			var what0 := String(TransformGizmo.TOOL_NAMES[_giz.tool_mode])
			set_motion_offset(n, mo, n.transform.affine_inverse() * after, "%s: %s %s 자리 %s(이 동작만)" % ["손" if _is_hand_marker(n) else "장비", n.name, mo, what0])
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
		var mks: Array[Node3D] = [DRCharacter3D.find_hand_marker(e, 0), DRCharacter3D.find_hand_marker(e, 1),
			DRCharacter3D.find_aim_marker(e, DRCharacter3D.MUZZLE_NAME), DRCharacter3D.find_aim_marker(e, DRCharacter3D.SHOULDER_NAME)]
		for mk in mks:
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
		KEY_SPACE:
			toggle_play()
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


## 장비의 잡는 방식(= 장비에 붙는 손 — 총을 옮기면 같이 따라옴, 10-27) — 0 = 오른손(한 손 받침대 · 오른손만 붙음) · 1 = 왼손 · 2 = 양손(두 손 사이 받침대) ·
## 3 = 고정(땅 받침대) · 4 = 뼈 소켓(장비가 그 뼈에 고정 — 손 뼈면 그 손은 장비를 들고 다른 손만 표지를 따라감 · 머리 · 가슴 …) · -1 = 없음
static func grip_kind(e: Node) -> int:
	var a := e.get_parent() if e != null else null
	if a is DRGripMount3D:
		return grip_kind_of_mount(a as DRGripMount3D)
	if a is BoneAttachment3D:
		return 4
	return -1


## 받침대의 잡는 방식(0 = 오른손 · 1 = 왼손 · 2 = 양손 · 3 = 고정)
static func grip_kind_of_mount(gm: DRGripMount3D) -> int:
	if gm.mode == DRGripMount3D.Mode.FIXED:
		return 3
	return [2, 0, 1][int(gm.hold)]


## 손 뼈 소켓 쪽(0 = 왼손 · 1 = 오른손) — 장비가 그 손 뼈에 고정(그 손은 장비를 듦). 아니면 -1
static func socket_hand(e: Node) -> int:
	var a := e.get_parent() as BoneAttachment3D if e != null else null
	return DRCharacter3D.HAND_BONES.find(String(a.bone_name)) if a != null else -1


## 장비에 그 손이 붙나(표지 IK — 총을 옮기면 따라옴)
static func hand_grips(e: Node, side: int) -> bool:
	return e != null and e.get_parent() != null and DRCharacter3D.anchor_grips(e.get_parent(), side)


## 손 표지(DRHandTarget3D · 장비 아래 이름이 "왼손" · "오른손" 인 Node3D — 받침은 빼고)
static func _is_hand_marker(n: Node) -> bool:
	return n is DRHandTarget3D or (n is Node3D and not _is_anchor(n) and DRCharacter3D.SIDE_NAMES.has(String(n.name)))


## 손 표지의 손(0 = 왼손 · 1 = 오른손) — DRHandTarget3D 는 side, 이름만 표지는 이름으로
static func _marker_side(n: Node) -> int:
	if n is DRHandTarget3D:
		return (n as DRHandTarget3D).side
	return maxi(0, DRCharacter3D.SIDE_NAMES.find(String(n.name)))


## 동작별 자리를 얹는 노드 — 장비 · 손 표지(10-27 사용자 "오른손 왼손도 기즈모로 움직여서 살짝 조정")
func _is_posed(n: Node) -> bool:
	return n != null and (_is_equip(n) or _is_hand_marker(n))


## 이 동작만 자리를 고칠 노드 — 고른 것이 손 표지면 그 손, 아니면 무기(장비)
func _offset_node() -> Node3D:
	var n := _node(_sel)
	if _is_hand_marker(n):
		return n as Node3D
	return _offset_equip()


## 손에 맞추기를 할 수 있는 받침 — 한 손 · 양손 받침대 · 손 뼈 소켓(고정 받침대 · 손이 아닌 뼈 소켓은 기즈모로)
static func can_fit_hands(e: Node) -> bool:
	var k := grip_kind(e)
	return (k >= 0 and k <= 2) or socket_hand(e) >= 0


# ───────────── 나무 · 칸 ─────────────

func _refresh_all() -> void:
	_fill_tree()
	_rebuild_preview()
	_struct_sig = _make_struct_sig()
	_xform_sig = _make_xform_sig()
	_show_xform()
	_show_aim_settings()


## 손 기준 나무(10-27) — 사용자: "왼손 잡기인데 오른손에 붙어 있고 … 이 무기 소켓 하이어라키에서 드래그해서 자식으로 지정해 놓는 행위를 하면 2. 잡기도
## 그거에 반영돼서 동기화" · "오른손 왼손도 기즈모로 움직여서 살짝 조정". 맨 위 = 몸의 손 · 뼈(✋ 오른손 · ✋ 왼손 · 🤝 양손 · 📌 땅 · 🦴 그 밖의 뼈 소켓)로
## 고정하고, 장비는 **지금 보는 동작에서 쥔 곳** 아래에 보인다(이 동작만 따로 = 주황) — 부모는 하나뿐이라 애니메이션마다 부모를 바꾸는 것은 하이어라키로
## 못 한다(유니티도 Parent Constraint 비중으로) → 나무가 지금 동작의 진실을 보여 준다. 장비를 끌어 다른 손에 놓으면 잡기(적용 범위대로 — 2 잡기 단추 · 표 잡기 칸과
## 같은 데이터). 손 줄을 고르면 그 손 표지(총의 어디를 쥐나)를 고른다 — 기즈모로 그 손만 옮김(총은 그대로). 받침 노드(DRGripMount3D · 손 뼈 소켓)는 씬 독에만 보인다
const TREE_GRIPS := [[0, "✋ 오른손"], [1, "✋ 왼손"], [2, "🤝 양손 (두 손 사이)"], [3, "📌 땅 (고정)"]]


func _fill_tree() -> void:
	_tree.clear()
	var top := _tree.create_item()
	if _root == null:
		return
	var w := _weapon_equip()
	var mo := current_motion()
	var rows := {}                              # 잡기(0 오른손 · 1 왼손 · 2 양손 · 3 땅) → 줄
	for g in TREE_GRIPS:
		var k: int = g[0]
		var gi := _tree.create_item(top)
		gi.set_meta(&"grip", k)
		gi.set_metadata(0, NodePath())
		gi.set_text(0, String(g[1]))
		gi.set_tooltip_text(0, "장비를 여기로 끌어 놓으면 %s 잡기 — 적용 범위가 모든 동작이면 기본 잡기, 이 동작만이면 그 동작만%s" % [GRIP_NAMES[k],
			"(땅 = 받침이라 모든 동작에서만)" if k == 3 else ""])
		rows[k] = gi
		if k <= 1:
			_fill_hand_row(gi, 1 - k, w, mo)
	for a in _anchors():
		var bs := a as BoneAttachment3D
		var hand_sock := bs != null and DRCharacter3D.HAND_BONES.has(String(bs.bone_name))
		var srow: TreeItem = null
		if bs != null and not hand_sock:          # 머리 · 등 … 손이 아닌 뼈 소켓
			srow = _tree.create_item(top)
			srow.set_text(0, "🦴 %s  (뼈 %s)" % [a.name, bs.bone_name])
			srow.set_tooltip_text(0, "소켓(BoneAttachment3D) — 뼈 %s 를 따라간다%s" % [bs.bone_name, " · 부모 유닛에서 옴" if _is_inherited(a) else ""])
			srow.set_metadata(0, _root.get_path_to(a))
		for c in a.get_children():
			if not (c is Node3D):
				continue
			var e := c as Node3D
			var parent_row: TreeItem = srow
			if parent_row == null:
				var gk := grip_kind(e)
				var g2 := 3 if gk == 3 else motion_grip(e, mo)
				if g2 < 0:
					g2 = motion_grip(e, "")
				parent_row = rows.get(g2, rows[0])
				if (gk == 2 or gk == 3) and parent_row.get_metadata(0) == NodePath():
					parent_row.set_metadata(0, _root.get_path_to(a))     # 양손 · 땅 줄 = 그 받침대(땅 받침대는 기즈모로 옮김)
			_fill_equip_row(parent_row, e, mo)
	for it in _all_items(top):
		if (it.get_metadata(0) as NodePath) == _sel and _sel != NodePath():
			it.select(0)


## 손 줄 — 그 손이 지금 동작에서 쥐나 · 무기의 그 손 표지(고르면 기즈모로 그 손만 옮김)
func _fill_hand_row(gi: TreeItem, side: int, w: Node3D, mo: String) -> void:
	var nm := String(DRCharacter3D.SIDE_NAMES[side])
	var mk := DRCharacter3D.find_hand_marker(w, side) if w != null else null
	if w == null:
		return
	if mk == null:
		gi.set_text(0, "✋ %s  — 표지 없음" % nm)
		gi.set_tooltip_text(0, gi.get_tooltip_text(0) + "\n%s 표지(총의 어디를 쥐나)가 없다 — 2 잡기의 [%s 표지 ← 지금 손]" % [nm, nm])
		return
	gi.set_metadata(0, _root.get_path_to(mk))
	var on := socket_hand(w) == side or DRCharacter3D.hand_weight_for(w, side, mo) > 0.001
	var po := DRCharacter3D.motion_offsets(mk).size()
	gi.set_text(0, "✋ %s  — %s%s" % [nm, "쥠" if on else "놓음(이 동작)", "  · 동작별 자리 %d" % po if po > 0 else ""])
	gi.set_tooltip_text(0, ("%s — 누르면 이 손이 총을 쥐는 자리(%s 표지)를 고른다: 기즈모로 이동 · 회전하면 손만 움직이고 총은 그대로.\n" +
		"적용 범위가 모든 동작이면 기본 자리, 이 동작만이면 그 동작만(동작별 자리). 장비를 여기로 끌어 놓으면 %s 잡기") % [nm, nm, nm])
	if not on:
		gi.set_custom_color(0, Color(0.55, 0.57, 0.6))


## 장비 줄(끌어 놓을 수 있다) — 이 동작만 따로 정한 잡기면 주황 · 아래에 조준 표지(손 표지는 위 손 줄)
func _fill_equip_row(parent_row: TreeItem, e: Node3D, mo: String) -> void:
	var ei := _tree.create_item(parent_row)
	ei.set_meta(&"equip", true)
	var src := e.scene_file_path.get_file() if e.scene_file_path != "" else e.get_class()
	var po := DRCharacter3D.motion_offsets(e).size()
	var own := motion_grip_own(e, mo)
	ei.set_text(0, "%s%s  (%s)%s%s" % ["⊘ " if not e.visible else "", e.name, src, "  · 동작별 자리 %d" % po if po > 0 else "",
		"  ● %s 만 (기본 = %s)" % [mo, _grip_name(motion_grip(e, ""))] if own else ""])
	ei.set_metadata(0, _root.get_path_to(e))
	ei.set_tooltip_text(0, "장비 — 끌어서 ✋ 오른손 · ✋ 왼손 · 🤝 양손 · 📌 땅 에 놓으면 잡기(적용 범위대로)%s%s%s" % [" · 숨김(게임에서는 지운다)" if not e.visible else "",
		" · 부모 유닛에서 옴" if _is_inherited(e) else "", "\n동작별 자리: " + ", ".join(PackedStringArray(DRCharacter3D.motion_offsets(e).keys())) if po > 0 else ""])
	if not e.visible:
		ei.set_custom_color(0, Color(0.55, 0.57, 0.6))
	elif own:
		ei.set_custom_color(0, Color(1.0, 0.68, 0.32))
	for an in [DRCharacter3D.MUZZLE_NAME, DRCharacter3D.SHOULDER_NAME]:   # 조준 표지(10-21)
		var am := DRCharacter3D.find_aim_marker(e, an)
		if am == null:
			continue
		var ai := _tree.create_item(ei)
		var muzzle: bool = an == DRCharacter3D.MUZZLE_NAME
		ai.set_text(0, "%s %s  (%s)" % ["🎯" if muzzle else "📍", am.name, "총구 표지 — 레이가 나가는 곳 · 파란 축 = 방향" if muzzle else "견착 표지 — 팔 몫 조준의 축(개머리판 끝)"])
		ai.set_metadata(0, _root.get_path_to(am))
		ai.set_tooltip_text(0, ("총구 표지: 원점 = 총구 선(레이)이 나가는 자리, +Z(파란 축) = 방향. 기즈모 W 이동 · E 회전" if muzzle
			else "견착 표지: 조준할 때 팔이 총을 드는 축 — 개머리판을 어깨에 대는 점. 기즈모 W 이동") + "\n지우면(빼기 · [자동으로]) 무기 메시에서 다시 잰다")


## 나무 끌기 — 장비 줄만 끈다
func _tree_drag(at: Vector2) -> Variant:
	var it := _tree.get_item_at_position(at)
	if it == null or not it.has_meta(&"equip"):
		return null
	var l := Label.new()
	l.text = "✋ " + it.get_text(0).get_slice("  ", 0) + " — 손에 놓기"
	_tree.set_drag_preview(l)
	return {"dr_equip": it.get_metadata(0)}


## 끌어 놓을 잡기 줄 — 놓은 줄에서 위로 올라가 맨 위 잡기 줄(✋ 오른손 · ✋ 왼손 · 🤝 양손 · 📌 땅). 없으면 -1
func _drop_grip(it: TreeItem) -> int:
	while it != null:
		if it.has_meta(&"grip"):
			return int(it.get_meta(&"grip"))
		it = it.get_parent()
	return -1


func _tree_can_drop(at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and (data as Dictionary).has("dr_equip")):
		return false
	var k := _drop_grip(_tree.get_item_at_position(at))
	return k >= 0 and not (_per_motion and k == 3)


## 장비를 잡기 줄에 놓았다 — 2 잡기 단추와 같은 길(적용 범위대로: 모든 동작 = 기본 잡기 · 이 동작만 = 그 동작의 잡기)
func _tree_drop(at: Vector2, data: Variant) -> void:
	var k := _drop_grip(_tree.get_item_at_position(at))
	if k < 0 or not (data is Dictionary):
		return
	drop_equip_on_grip((data as Dictionary).get("dr_equip", NodePath()), k)


## 장비 p 를 잡기 k(0 오른손 · 1 왼손 · 2 양손 · 3 땅)에 — 나무 끌어 놓기 · 검사가 부른다. 나무는 신호 안이라 미뤄서 다시 채운다
func drop_equip_on_grip(p: NodePath, k: int) -> void:
	if _root == null or _root.get_node_or_null(p) == null:
		return
	if _per_motion and k == 3:
		_set_status("땅(고정)은 받침이라 모든 동작에서만 — 적용 범위를 [모든 동작]으로")
		return
	_sel = p
	_on_grip_btn(k)
	_fill_tree.call_deferred()


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
	if _per_motion and _is_posed(n) and _prev_node(n) is Node3D:
		_show_xform_of(_prev_node(n) as Node3D)
		_xf_title.text = "%s — %s 만(부모 %s 기준)" % [n.name, current_motion() if current_motion() != "" else "동작 없음", n.get_parent().name]
		for sp in _scl:
			sp.editable = false                  # 동작별 자리는 위치 · 회전만
	elif _per_motion and (_is_marker(n) or n is DRGripMount3D):
		_show_xform_of(n)
		for sp in _pos + _rot + _scl:
			sp.editable = false
		_xf_title.text = "%s — %s는 모든 동작 공통이라 잠김(적용 범위 [모든 동작]에서 고침)" % [n.name, "받침대" if n is DRGripMount3D else "표지"]
	else:
		_show_xform_of(n)
	_update_grip_ui()
	_update_pm_ui()


const GRIP_NAMES := ["오른손", "왼손", "양손", "고정", "뼈"]
## 이 동작만일 때 잠긴 칸의 풍선 도움말 꼬리
const LOCK_TIP := "\n— 잠김: 적용 범위가 \"이 동작만\". 모든 동작 공통 값이라 [모든 동작]에서 고친다"
## 잡기마다 마지막 자리(10-21) — 장비 노드의 메타 칸. 값 = {받침 경로(유닛 루트 기준): 그 받침 아래 장비 자리}.
## 사용자: "잡기 오른손 · 왼손 · 양손을 엄청 번갈아 움직이면 세팅된 게 전부 망가져" — 바꿀 때마다 그때 보이는 동작 · 시점으로 새로 계산해
## 동작을 바꿔 가며 4 바퀴 오가니 무기가 1.9 m · 180° 어긋났다. 이제 떠나는 받침의 자리를 적어 두고, 다시 오면 그대로 되돌린다(받침대 값도 안 덮음)
const GRIP_MEMORY_META := &"dr_grip_memory"


## 잡기 줄 — 고른 장비(없으면 무기)의 잡기 단추 · 양손 보간 · 손마다 무엇을 하나. 적용 범위가 이 동작만이면 단추 = 지금 동작의 잡기(10-27)
func _update_grip_ui() -> void:
	if _grip_btns.is_empty():
		return
	var e := _equip_from(_node(_sel))
	if e == null:
		e = _weapon_equip()
	var kind := grip_kind(e) if e != null else -1
	var mo := current_motion()
	var per := _per_motion and e != null and mo != ""
	var shown := motion_grip(e, mo) if per else kind               # 눌린 단추 — 이 동작만이면 그 동작의 잡기
	var own := per and motion_grip_own(e, mo)
	for i in _grip_btns.size():
		var b := _grip_btns[i]
		b.set_pressed_no_signal(i == shown)
		var why := ""
		if per and i == 3:
			why = "고정은 받침(땅)이라 모든 동작에서만 바꾼다"
		elif per and not _motion_grip_ok(e, i):
			why = "%s 뼈 소켓(옛 방식)이라 %s은 늘 총을 듦 — 이 잡기는 [모든 동작]에서 받침을 바꾼 뒤" % [DRCharacter3D.SIDE_NAMES[socket_hand(e)], DRCharacter3D.SIDE_NAMES[socket_hand(e)]]
		b.disabled = e == null or why != ""
		b.self_modulate = Color(1.0, 0.68, 0.32) if own and i == shown else Color.WHITE      # 이 동작만 따로 정한 잡기 = 주황(미리보기 테두리와 같은 색)
		b.tooltip_text = String(b.get_meta(&"tip", "")) + ("\n— 잠김: " + why if why != "" else "")
	_grip_reset_btn.get_parent().visible = _per_motion
	_grip_reset_btn.disabled = not own
	_grip_reset_btn.text = "↺ %s 기본 잡기로(%s)" % [mo, _grip_name(motion_grip(e, ""))] if per else "↺ 이 동작 기본 잡기로"
	var gm := e.get_parent() as DRGripMount3D if e != null else null
	var both := kind == 2
	_blend_sl.get_parent().visible = both
	if both:
		_blend_sl.set_value_no_signal(gm.blend)
		_blend_lbl.text = "보간 오른손 %d%% · 왼손 %d%%" % [int(round((1.0 - gm.blend) * 100.0)), int(round(gm.blend * 100.0))]
	if e == null:
		_grip_info.text = "장비(무기)를 고르세요"
		return
	var hand_txt := PackedStringArray()
	for side in 2:
		var nm := String(DRCharacter3D.SIDE_NAMES[side])
		var on := DRCharacter3D.hand_weight_for(e, side, mo if per else "") > 0.001
		if socket_hand(e) == side:
			hand_txt.append("%s = %s" % [nm, _rest_why(e, side)])
		elif on:
			hand_txt.append("%s = 총에 붙음(총을 옮기면 따라옴)" % nm)
		elif DRCharacter3D.find_hand_marker(e, side) == null and (hand_grips(e, side) or per):
			hand_txt.append("%s = 표지 없음 — 동작 그대로(아래 [%s 표지 ← 지금 손])" % [nm, nm])
		else:
			hand_txt.append("%s = 총에 안 붙음 — 동작 그대로" % nm)
	if per:
		var base := motion_grip(e, "")
		_grip_info.text = "%s — %s 만: %s 잡기%s · 기본(모든 동작) = %s · 받침 %s · %s" % [e.name, mo, _grip_name(shown),
			"(따로 정함)" if own else "(기본대로)", _grip_name(base), e.get_parent().name, " · ".join(hand_txt)]
		return
	var where := ""
	match kind:
		0, 1:
			where = "%s 잡기 — 총이 %s 동작을 따라감(%s)" % [GRIP_NAMES[kind], GRIP_NAMES[kind], e.get_parent().name]
		2:
			where = "양손 잡기 — 두 손 사이 받침대(%s)" % e.get_parent().name
		3:
			where = "고정 — 유닛(땅) 받침대(%s)" % e.get_parent().name
		_:
			var sh := socket_hand(e)
			where = ("%s 뼈 소켓(%s) — 옛 방식: 총이 %s 뼈에 고정 · 위 [%s]을 누르면 %s이 총에 붙는 방식으로" % [DRCharacter3D.SIDE_NAMES[sh], e.get_parent().name,
				DRCharacter3D.SIDE_NAMES[sh], GRIP_NAMES[1 - sh], GRIP_NAMES[1 - sh]]) if sh >= 0 else \
				"뼈 %s 소켓" % ((e.get_parent() as BoneAttachment3D).bone_name if e.get_parent() is BoneAttachment3D else "-")
	var owns := PackedStringArray()
	if _prev != null:
		for n in _prev.motion_names():
			if motion_grip_own(e, n):
				owns.append("%s %s" % [n, _grip_name(motion_grip(e, n))])
	_grip_info.text = "%s — %s · %s%s" % [e.name, where, " · ".join(hand_txt),
		"" if owns.is_empty() else " · 동작마다 따로 %d개(%s)" % [owns.size(), ", ".join(owns.slice(0, 3)) + (" …" if owns.size() > 3 else "")]]


## 잡기 단추 — 적용 범위대로(모든 동작 = 받침 · 기본 잡기 · 이 동작만 = 그 동작의 잡기)
func _on_grip_btn(kind: int) -> void:
	if _per_motion:
		set_motion_grip(current_motion(), kind)
	else:
		set_grip(kind)


## 잡기 이름 — 0 오른손 · 1 왼손 · 2 양손 · 3 고정 · -2 안 붙음
static func _grip_name(k: int) -> String:
	return "안 붙음" if k == -2 else (String(GRIP_NAMES[k]) if k >= 0 and k < GRIP_NAMES.size() else "-")


## 그 동작에서 총에 붙은 손(10-27 동작마다 잡기) — 0 = 오른손 · 1 = 왼손 · 2 = 양손 · -2 = 안 붙음. 손 뼈 소켓의 그 손은 늘 총을 듦(붙은 것으로 셈).
## motion = "" 이면 기본 잡기(동작별 비중이 없는 동작)
static func motion_grip(e: Node, motion: String) -> int:
	if e == null:
		return -1
	var on := [false, false]
	for side in 2:
		on[side] = socket_hand(e) == side or DRCharacter3D.hand_weight_for(e, side, motion) > 0.001
	if on[0] and on[1]:
		return 2
	return 0 if on[1] else (1 if on[0] else -2)


## 그 동작의 잡기를 따로 정했나(두 손 표지 중 하나라도 그 동작 비중이 있음 — 기본과 다름)
static func motion_grip_own(e: Node, motion: String) -> bool:
	if e == null or motion == "":
		return false
	for side in 2:
		var mk := DRCharacter3D.find_hand_marker(e, side)
		if mk is DRHandTarget3D and (mk as DRHandTarget3D).motion_weights.has(motion):
			return true
	return false


## 이 받침에서 그 동작 잡기(0 오른손 · 1 왼손 · 2 양손 · -2 안 붙음)를 고를 수 있나 — 손 뼈 소켓의 그 손은 늘 총을 들어 그 손을 뺀 잡기는 안 됨
static func _motion_grip_ok(e: Node, kind: int) -> bool:
	if kind == -1:
		return true
	if kind < -2 or kind > 2:
		return false
	var sh := socket_hand(e)
	return sh < 0 or _grip_hands(kind)[sh]


## 잡기의 [왼손, 오른손] 붙음
static func _grip_hands(kind: int) -> Array:
	return [[false, true], [true, false], [true, true]][kind] if kind >= 0 and kind <= 2 else [false, false]


## 그 동작의 잡기(10-27) — 사용자: "각 동작마다 어느 손이 기준 잡기 기준인가 이런 것도 조작하고 싶은데 전역으로 설정됨. 이 동작만 버튼 눌러도".
## kind 0 = 오른손 · 1 = 왼손 · 2 = 양손 · -2 = 안 붙음 · -1 = 기본(받침의 잡기)대로. 두 손 표지의 동작별 비중(motion_weights)에 1 · 0 으로 둘 다 쓴다
## (기본 잡기를 나중에 바꿔도 이 동작은 그대로 — 기본대로 = 둘 다 지움). 받침(총이 무엇을 따라가나)은 그대로 — 한 손만 붙는 동작은 받침대가 그 손 쪽을 따라간다(DRCharacter3D.mount_t).
## 붙을 손의 표지가 없으면 지금 손 자리로 만든다(표지는 모든 동작 공통 — 상태 줄에 알림). 되돌리기 한 칸
func set_motion_grip(motion: String, kind: int) -> void:
	var e := _offset_equip()
	if e == null or motion == "" or _root == null:
		_set_status("동작마다 잡기 — 무기와 동작을 고르세요")
		return
	if not _motion_grip_ok(e, kind):
		var sh := socket_hand(e)
		_set_status("%s 은 %s 뼈 소켓(옛 방식)이라 %s이 늘 총을 듭니다 — %s 잡기는 적용 범위 [모든 동작]에서 받침을 바꾼 뒤(2 잡기)" % [e.name,
			DRCharacter3D.SIDE_NAMES[sh], DRCharacter3D.SIDE_NAMES[sh], _grip_name(kind)])
		_update_grip_ui()
		_fill_motion_table.call_deferred()                 # 표에서 고른 칸을 되돌려 보인다
		return
	var anchor := e.get_parent()
	var want: Array = _grip_hands(kind)
	var ops := []                                          # [표지, 새 motion_weights]
	var new_marks := {}
	for side in 2:
		if not DRCharacter3D.anchor_can_grip(anchor, side):
			continue
		var mk := DRCharacter3D.find_hand_marker(e, side)
		if mk == null:
			if kind >= 0 and want[side]:
				var hx: Variant = _hand_xform_on(e, side)
				if hx != null:
					new_marks[side] = [hx, {motion: 1.0}]
			continue
		if not (mk is DRHandTarget3D):
			continue                                       # 이름만 표지(Marker3D) — 동작별 비중이 없다(늘 기본)
		var t := mk as DRHandTarget3D
		var mw: Dictionary[String, float] = t.motion_weights.duplicate()
		if kind == -1:
			mw.erase(motion)
		else:
			mw[motion] = 1.0 if want[side] else 0.0          # 두 손 다 적는다 — 기본과 같은 손을 지우면 기본 잡기를 바꿀 때 이 동작도 바뀐다
		if mw != t.motion_weights:
			ops.append([t, mw])
	if ops.is_empty() and new_marks.is_empty():
		_update_grip_ui()
		_fill_motion_table.call_deferred()
		return
	var was_stale := _rep_stale
	_begin("장비: %s %s 잡기 = %s" % [e.name, motion, "기본대로" if kind == -1 else _grip_name(kind)])
	for o in ops:
		_op_prop(o[0], "motion_weights", o[1])
	for side in new_marks.keys():
		var mk := _new_marker(new_marks[side][0], new_marks[side][1], int(side))
		_op_add(e, mk, [mk])
	_end(not new_marks.is_empty())
	_rep_stale = was_stale                                 # 잡기는 자리를 안 바꾼다 — 그 동작만 다시 잰다
	_remeasure(motion)
	_update_grip_ui()
	_fill_tree.call_deferred()                             # 손 기준 나무(장비가 쥔 손 아래로)
	_fill_motion_table.call_deferred()                     # 미뤄서 — 동작 표의 칸 고치기 신호에서도 불린다
	var g := motion_grip(e, motion)
	_set_status("%s — %s 잡기 = %s%s · 기본(모든 동작) = %s%s" % [e.name, motion, _grip_name(g), "(기본대로)" if kind == -1 else "",
		_grip_name(motion_grip(e, "")), " · 새 표지 %s(모든 동작 공통 — 지금 손 자리)" % ", ".join(new_marks.keys().map(func(s): return String(DRCharacter3D.SIDE_NAMES[s])))
		if not new_marks.is_empty() else ""])


## 그 손이 장비에 안 붙는 까닭 — 손 뼈 소켓이면 "총을 듦(소켓)", 한 손 잡기의 다른 손이면 "동작 그대로"
func _rest_why(e: Node, side: int) -> String:
	if socket_hand(e) == side:
		return "총이 이 손 뼈에 고정(총을 옮기면 손 안에서 움직임)"
	return "총에 안 붙음 — 동작 그대로(%s 잡기)" % GRIP_NAMES[grip_kind(e)] if grip_kind(e) >= 0 and grip_kind(e) <= 1 else "총에 안 붙음 — 동작 그대로"


## 받침대 한 줄 — "오른손 — 오른손만 붙음" · "양손 — 두 손 사이 50%" · "고정 — 유닛(땅) 기준"
static func _mount_text(gm: DRGripMount3D) -> String:
	if gm.mode == DRGripMount3D.Mode.FIXED:
		return "고정 — 유닛(땅) 기준"
	match gm.hold:
		DRGripMount3D.Hold.RIGHT:
			return "오른손 — 오른손만 붙음"
		DRGripMount3D.Hold.LEFT:
			return "왼손 — 왼손만 붙음"
	return "양손 — 두 손 사이 %d%%" % int(round(gm.blend * 100.0))


static func _mount_tip(gm: DRGripMount3D) -> String:
	if gm.mode == DRGripMount3D.Mode.FIXED:
		return "유닛(땅)에 고정(라페테 MG42 등), 두 손이 표지에 IK"
	match gm.hold:
		DRGripMount3D.Hold.RIGHT:
			return "오른손 동작을 따라가고 오른손이 표지에 IK(총을 옮기면 오른손이 따라옴) · 왼손은 동작 그대로"
		DRGripMount3D.Hold.LEFT:
			return "왼손 동작을 따라가고 왼손이 표지에 IK(총을 옮기면 왼손이 따라옴) · 오른손은 동작 그대로"
	return "두 손 사이(오른손 ↔ 왼손 %d%%)를 따라가고 두 손이 표지에 IK" % int(round(gm.blend * 100.0))


## 양손 받침대의 보간(0 = 오른손 쪽 · 1 = 왼손 쪽) — 슬라이더
func set_blend(v: float) -> void:
	var e := _equip_from(_node(_sel))
	if e == null:
		e = _weapon_equip()
	var gm := e.get_parent() as DRGripMount3D if e != null else null
	if gm == null or grip_kind_of_mount(gm) != 2:
		return
	_set_props_merged("장비: 양손 보간", [[gm, "blend", clampf(v, 0.0, 1.0)]])


## 고른 장비에 붙을 손(조인트 느낌 — 사용자 10-16) — 0 = 오른손 · 1 = 왼손(총이 그 손 동작을 따라가고 그 손만 표지에 IK — 총을 옮기면 그 손이 따라옴,
## 다른 손은 동작 그대로) · 2 = 양손(두 손 사이 · 두 손 IK) · 3 = 고정(땅 받침대 · 두 손 IK). 이것은 기본 잡기 — 동작마다 다른 손은 set_motion_grip.
## (10-16 에는 오른손 = 오른손 뼈 소켓으로 반대였다 — 02 U49.)
## 10-27: 오른손 · 왼손 · 양손은 무기마다 **손 받침대 하나**(DRGripMount3D 손 기준) — 이미 손 받침대에 있으면 붙는 손(hold)만 바꾼다(받침 · 무기 자리 그대로).
##   사용자 "왼손 잡기인데 오른손에 붙어 있고 … 하이어라키에서 드래그해서 자식으로 지정 → 2. 잡기 동기화" — 잡기를 누를 때마다 받침을 새로 만들어
##   오른손 · 오른손잡기 · 왼손소켓 · 왼손잡기 · 양손이 쌓였었다. 이제 바꿀 때 비어 있는 손 받침대 · 손 뼈 소켓은 지운다(떠나는 받침대는 다시 올 수 있어 남김).
## 손 받침대 ↔ 고정 받침대 · 옛 소켓을 오가면 전에 쓰던 받침의 그때 자리 그대로(GRIP_MEMORY_META — 받침대 값도 안 덮음), 처음 가는 받침이면 지금 보이는
## 자리 그대로 받침만 바꾼다(유니티 "자리 유지하며 부모 바꾸기" — 동작별 자리 · 조준 미리보기 뺌). 붙을 손의 표지가 없으면 그 손의 지금 자리로 만든다. 되돌리기 한 칸
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
	var follow: Array = [[1], [0], [0, 1], [0, 1]][kind]
	if _aim_preview:
		_prev.clear_aim_target(true)                       # 조준으로 돌린 자세를 기본 자리에 굳히지 않게(끝에 다시 켬)
	var new_marks := {}                                    # 붙을 손인데 표지가 없으면 — 지금 그 손 자리(장비 기준, 받침을 바꿔도 같다)
	var jumps := PackedStringArray()                       # 붙을 손의 표지가 지금 손에서 떨어져 있으면 — 손이 표지로 옮겨 간다(표지는 안 덮음 — 사용자가 정한 쥐는 곳)
	for side in follow:
		var hx: Variant = _hand_xform_on(e, side)
		var mk := DRCharacter3D.find_hand_marker(e, side)
		if mk == null:
			if hx != null:
				new_marks[side] = hx
		elif hx != null and not hand_grips(e, side) and _prev_node(mk) is Node3D:
			var pmk := _prev_node(mk) as Node3D
			var d := (pe.global_transform * (hx as Transform3D).origin).distance_to(pmk.global_position)
			var deg := rad_to_deg((pe.global_transform.basis * (hx as Transform3D).basis).orthonormalized().get_rotation_quaternion().angle_to(
				pmk.global_basis.orthonormalized().get_rotation_quaternion()))
			if d > 0.01 or deg > 5.0:
				var nm := String(DRCharacter3D.SIDE_NAMES[side])
				jumps.append("%s이 %s 표지로 %.1f cm · %.0f° 옮겨감(지금 손 자리로 쥐려면 [%s 표지 ← 지금 손])" % [nm, nm, d * 100.0, deg, nm])
	var hold_v: int = [DRGripMount3D.Hold.RIGHT, DRGripMount3D.Hold.LEFT, DRGripMount3D.Hold.BOTH, DRGripMount3D.Hold.BOTH][kind]
	var mo := current_motion()
	var mem: Dictionary = (e.get_meta(GRIP_MEMORY_META) as Dictionary).duplicate() if e.has_meta(GRIP_MEMORY_META) and e.get_meta(GRIP_MEMORY_META) is Dictionary else {}
	var mem_old: Variant = e.get_meta(GRIP_MEMORY_META) if e.has_meta(GRIP_MEMORY_META) else null
	var cur := e.get_parent() as DRGripMount3D
	if kind <= 2 and cur != null and cur.mode == DRGripMount3D.Mode.HANDS:
		# 이미 손 받침대 — 붙는 손만 바꾼다(받침 · 무기 자리 · 받침대 두 손 자리 그대로)
		var removes := _empty_hand_anchors([cur], e)
		_begin("장비: %s 잡기 = %s" % [e.name, GRIP_NAMES[kind]])
		_op_remove_undo_first(removes)
		_op_prop(cur, "hold", hold_v)
		var rn := _rename_grip_mount(cur)
		if not rn.is_empty() and mem.has(rn[0]):
			mem[rn[1]] = mem[rn[0]]
			mem.erase(rn[0])
			_op_meta(e, GRIP_MEMORY_META, mem, mem_old)
		for side in new_marks.keys():
			var mk := _new_marker(new_marks[side], {}, int(side))
			_op_add(e, mk, [mk])
		_op_remove_do_last(removes)
		_end(true)
		_select_node(_root.get_path_to(e))
		if _aim_preview:
			_apply_aim_preview()
		_set_status("%s 잡기 = %s · 받침 그대로(붙는 손만 바꿈)%s%s%s" % [e.name, GRIP_NAMES[kind],
			" · 빈 받침 %d개 정리" % removes.size() if not removes.is_empty() else "",
			" · 새 표지 %s" % ", ".join(new_marks.keys().map(func(s): return String(DRCharacter3D.SIDE_NAMES[s]))) if not new_marks.is_empty() else "",
			" · " + " · ".join(jumps) if not jumps.is_empty() else ""])
		return
	_force_pose()
	var sk := _prev.get_skeleton()
	var root_inv := _prev.global_transform.affine_inverse()
	var e_unit := root_inv * pe.global_transform * _prev.get_equip_offset(pe).affine_inverse()   # 기본 자리가 지금 보이는 곳(유닛 기준 — 동작별 자리 뺌)
	var want_mode := DRGripMount3D.Mode.FIXED if kind == 3 else DRGripMount3D.Mode.HANDS
	var anchor: Node3D = null
	var make := false
	for a in _anchors():                                   # 비어 있는 같은 방식 받침대는 다시 쓴다 — 잡기 기억에 있는 것 먼저
		if a is DRGripMount3D and (a as DRGripMount3D).mode == want_mode and _equip_of(a) == null and not _is_inherited(a):
			if anchor == null or mem.has(String(_root.get_path_to(a))):
				anchor = a
	if anchor == null:
		var m := DRGripMount3D.new()
		m.name = _unique_name("고정" if kind == 3 else "잡기")
		m.mode = want_mode
		m.hold = hold_v
		anchor = m
		make = true
	mem[String(_root.get_path_to(e.get_parent()))] = e.transform           # 떠나는 받침의 자리
	var back: Variant = null if make else mem.get(String(_root.get_path_to(anchor)))
	var a_unit := Transform3D.IDENTITY
	var props := {}
	if not make and (anchor as DRGripMount3D).hold != hold_v:
		props["hold"] = hold_v
	if not (back is Transform3D):                          # 처음 가는 받침 — 받침대 = 장비가 지금 있는 자리(배율 뺌), 장비 로컬엔 배율만
		a_unit = Transform3D(e_unit.basis.orthonormalized(), e_unit.origin)
		props["transform"] = a_unit
		if kind <= 2:                                       # 맞춘 자세: 손 쪽 자리가 지금 받침대 자리와 같게(한 손이면 그 손 쪽만 쓴다)
			var g := _prev.global_transform * a_unit
			props["right_offset"] = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(String(DRCharacter3D.HAND_BONES[1])))).affine_inverse() * g
			props["left_offset"] = (sk.global_transform * sk.get_bone_global_pose(sk.find_bone(String(DRCharacter3D.HAND_BONES[0])))).affine_inverse() * g
	var e_local: Transform3D = back if back is Transform3D else a_unit.affine_inverse() * e_unit
	var warn := ""                                         # 처음 가는 받침대를 붙을 손이 총에 없는 자세에서 맞추면 다른 동작이 다 어긋난다
	if not (back is Transform3D) and mo != "":
		for side in follow:
			var mk := DRCharacter3D.find_hand_marker(e, side)
			if mk is DRHandTarget3D and (mk as DRHandTarget3D).motion_weights.has(mo) and float((mk as DRHandTarget3D).motion_weights[mo]) <= 0.001:
				warn = " — ⚠ 지금 동작 %s 은 %s 이 총을 놓는 동작(이 동작 잡기에서 뺌): 붙을 손이 총에 있는 동작에서 다시 바꾸세요(Ctrl+Z)" % [mo, DRCharacter3D.SIDE_NAMES[side]]
	var keep: Array = [anchor]
	if e.get_parent() is DRGripMount3D:
		keep.append(e.get_parent())                        # 떠나는 받침대는 다시 올 수 있어 남긴다(잡기 기억)
	var removes := _empty_hand_anchors(keep, e)
	_begin("장비: %s 잡기 = %s" % [e.name, GRIP_NAMES[kind]])
	_op_remove_undo_first(removes)                         # 되돌리기: 지운 받침을 먼저 되살려야 장비가 옛 받침으로 돌아간다
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
		var rn := _rename_grip_mount(anchor as DRGripMount3D)
		if not rn.is_empty() and mem.has(rn[0]):
			mem[rn[1]] = mem[rn[0]]
			mem.erase(rn[0])
	_op_reparent(e, anchor, e_local)
	_op_meta(e, GRIP_MEMORY_META, mem, mem_old)
	for side in new_marks.keys():
		var mk := _new_marker(new_marks[side], {}, int(side))
		_op_add(e, mk, [mk])
	if make and _ur != null:
		_ur.add_undo_method(_root, "remove_child", anchor)  # 장비를 원래 받침으로 되돌린 다음에(되돌리기는 넣은 차례대로 돈다)
	_op_remove_do_last(removes)                            # 하기: 장비를 옮긴 뒤에 빈 받침을 지운다
	_end(true)
	_select_node(_root.get_path_to(e))
	if _aim_preview:
		_apply_aim_preview()
	_set_status("%s 잡기 = %s%s%s%s%s%s%s" % [e.name, GRIP_NAMES[kind], " · 새 받침 %s" % anchor.name if make else "",
		" · 전에 쓰던 자리로" if back is Transform3D else " · 지금 자세(%s %d%%)에서 맞춤" % [mo, int(_time_sl.value * 100.0)],
		" · 빈 받침 %d개 정리" % removes.size() if not removes.is_empty() else "",
		" · 새 표지 %s" % ", ".join(new_marks.keys().map(func(s): return String(DRCharacter3D.SIDE_NAMES[s]))) if not new_marks.is_empty() else "",
		" · " + " · ".join(jumps) if not jumps.is_empty() else "", warn])


## 잡기를 바꿀 때 지울 빈 받침(10-27 — 잡기를 누를 때마다 받침이 쌓여 헷갈렸다): 이 유닛의(부모 유닛에서 안 온) 받침대 · 손 뼈 소켓 중 장비가 없는 것.
## keep = 남길 것(옮겨 갈 받침 · 다시 올 수 있는 떠나는 받침대). moving = 지금 옮기는 장비(떠나는 받침의 자식으로 안 셈). 머리 · 등 같은 다른 뼈 소켓은 안 지운다
func _empty_hand_anchors(keep: Array, moving: Node) -> Array:
	var out := []
	for a in _anchors():
		if keep.has(a) or a.owner != _root or _is_inherited(a):
			continue
		var hand_sock := a is BoneAttachment3D and DRCharacter3D.HAND_BONES.has(String((a as BoneAttachment3D).bone_name))
		if not (a is DRGripMount3D or hand_sock):
			continue
		var busy := false
		for c in a.get_children():
			if c != moving and c is Node3D:
				busy = true
		if not busy:
			out.append(a)
	out.sort_custom(func(x, y): return (x as Node).get_index() < (y as Node).get_index())
	return out


## 받침 지우기 — 되돌리기 몫을 먼저 넣는다(되돌리기는 넣은 차례대로 돈다: 받침을 먼저 되살려야 장비가 그리로 돌아간다)
func _op_remove_undo_first(nodes: Array) -> void:
	if _ur == null:
		return
	for a in nodes:
		var n0 := a as Node
		var parent := n0.get_parent()
		_ur.add_undo_method(parent, "add_child", n0, true)
		_ur.add_undo_method(parent, "move_child", n0, n0.get_index())
		var stack: Array[Node] = [n0]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n.owner == _root:
				_ur.add_undo_method(n, "set_owner", _root)
			stack.append_array(n.get_children())
		_ur.add_undo_reference(n0)


## 받침 지우기 — 하기 몫은 나중에(장비를 옮긴 뒤 — 장비가 아직 그 받침 아래면 같이 지워진다)
func _op_remove_do_last(nodes: Array) -> void:
	for a in nodes:
		var n0 := a as Node
		if _ur != null:
			_ur.add_do_method(n0.get_parent(), "remove_child", n0)
		else:
			n0.get_parent().remove_child(n0)
			n0.queue_free()


## 손 받침대 이름이 옛 잡기 이름(오른손잡기 · 왼손잡기 · 양손)이면 "잡기" 로 — 붙는 손은 바뀌므로 이름에 손을 안 넣는다. 돌려주는 값 = [옛 경로, 새 경로](안 바꾸면 [])
func _rename_grip_mount(m: DRGripMount3D) -> Array:
	if m == null or m.mode != DRGripMount3D.Mode.HANDS:
		return []
	var nm := String(m.name)
	if not (nm.begins_with("오른손잡기") or nm.begins_with("왼손잡기") or nm.begins_with("양손")):
		return []
	var new_name := _unique_name("잡기")
	var old_path := String(_root.get_path_to(m))
	var base := old_path.get_base_dir()
	_op_prop(m, "name", new_name)
	return [old_path, new_name if base == "" else base + "/" + new_name]


## 메타 칸 바꾸기(되돌리기 한 칸 안에서) — 값이 null 이면 지운다
func _op_meta(n: Object, key: StringName, value: Variant, old: Variant) -> void:
	if _ur != null:
		_ur.add_do_method(n, "set_meta", key, value)
		_ur.add_undo_method(n, "set_meta", key, old)
	else:
		n.set_meta(key, value)


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
	if _per_motion and _is_posed(n):           # 이 동작만 — 칸 값 = 그 동작의 자리(크기는 기본 자리 것) → 동작별 자리(장비 · 손 표지)
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
		for an in (hold.get("aim_markers", {}) as Dictionary).keys():      # 조준 표지(총구 · 견착, 10-21)
			var am := Marker3D.new()
			am.name = String(an)
			am.gizmo_extents = 0.05
			am.transform = hold["aim_markers"][an]
			n.add_child(am)
			owned.append(am)
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
	if _marker_locked():
		return null
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
		var pm := _prev_node(cur) as Node3D                 # 지금 동작에 이 손의 동작별 자리가 있으면 그 차이를 뺀 기본 자리로(보이는 손 = 지금 손)
		var moff := _prev.get_equip_offset(pm) if pm != null else Transform3D.IDENTITY
		_op_prop(cur, "transform", _in_parent_of(cur, e, m) * moff.affine_inverse())
	else:
		var mk := _new_marker(m, {}, side)
		_op_add(e, mk, [mk])
		cur = mk
		added = true
	_end(added)
	_select_node(_root.get_path_to(cur))
	_set_status("%s 표지 = %s %d%% 의 %s(동작 그대로)%s" % [nm, current_motion(), int(_time_sl.value * 100.0), nm,
		" — 지금은 쉬는 표지: %s(잡기를 바꾸면 씀)" % _rest_why(e, side) if not hand_grips(e, side) else ""])
	return cur


## 표지(모든 동작 공통)를 고치려는데 적용 범위가 이 동작만 — 안내하고 막는다
func _marker_locked() -> bool:
	if not _per_motion:
		return false
	_set_status("표지(손 · 총구 · 견착)는 모든 동작 공통이라 \"이 동작만\" 범위에서는 잠깁니다 — 3 무기 자리의 적용 범위를 [모든 동작]으로 바꾸고 고치세요")
	return true


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


## 동작 하나의 그 손 IK 비중(0 ~ 1 — 잡기보다 잘게. 화면에서는 동작 표 잡기 칸 · 2 잡기가 0 · 1 로 쓴다, 인스펙터 motion_weights 와 같은 값) —
## 그 손 표지(DRHandTarget3D)의 motion_weights 를 통째로 바꿔 넣는다(기본과 같으면 지움 · 되돌리기 한 칸)
func set_motion_weight(motion: String, w: float, side: int = 0) -> void:
	var nm := String(DRCharacter3D.SIDE_NAMES[side])
	var e := _offset_equip()
	var mk := DRCharacter3D.find_hand_marker(e, side) if e != null else null
	if mk == null or not (mk is DRHandTarget3D):
		_set_status("%s 표지(DRHandTarget3D)가 없습니다" % nm)
		return
	var t := mk as DRHandTarget3D
	var mw: Dictionary[String, float] = t.motion_weights.duplicate()
	var base := t.weight * (1.0 if DRCharacter3D.anchor_grips(e.get_parent(), side) else 0.0)
	if absf(w - base) < 0.001:
		mw.erase(motion)
	else:
		mw[motion] = clampf(w, 0.0, 1.0)
	var was_stale := _rep_stale
	_begin("장비: %s 비중 %s" % [nm, motion])
	_op_prop(t, "motion_weights", mw)
	_end(false)
	_rep_stale = was_stale                  # 비중은 자리를 안 바꾼다 — 그 동작만 다시 재서 표에 넣는다
	_remeasure(motion)
	_update_grip_ui()
	_fill_tree.call_deferred()
	_fill_motion_table.call_deferred()      # 미뤄서 — 이 함수는 표의 칸 고치기 신호에서도 불린다


## 잰 수치가 있으면 그 동작만 다시 재서 바꿔 넣는다(비중 · 잡기를 바꾼 뒤 — 자리는 그대로라 다른 동작 수치는 맞다)
func _remeasure(motion: String) -> void:
	if _prev == null or _last_rep.is_empty():
		return
	var keep := current_motion()
	var kt := _time_sl.value
	var one := _measure(PackedStringArray([motion]))
	for i in _last_rep.size():
		if not one.is_empty() and String((_last_rep[i] as Dictionary)["motion"]) == motion:
			_last_rep[i] = one[0]
	play_motion(keep)
	_seek(kt)


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
	var bone := String(sock.bone_name) if sock != null else ""
	var local := e.transform
	var gm := e.get_parent() as DRGripMount3D
	if sock == null and gm != null and grip_kind(e) <= 1:      # 한 손 잡기(10-27) — 그 손 뼈 기준 자리로(다른 유닛 손 소켓에 넣어도 같은 자리)
		bone = String(DRCharacter3D.HAND_BONES[1 if grip_kind(e) == 0 else 0])
		local = (gm.right_offset if grip_kind(e) == 0 else gm.left_offset) * e.transform
	if bone == "":
		_set_status("무기 기본 자리는 소켓(손 · 뼈) · 한 손 잡기의 무기만 — 받침대(양손 · 고정) 자리는 유닛 씬에 저장된다")
		return
	var mk := DRCharacter3D.find_support(e)
	var aims := {}                                # 조준 표지(무기 기준 — 10-21)
	for an in [DRCharacter3D.MUZZLE_NAME, DRCharacter3D.SHOULDER_NAME]:
		var am := DRCharacter3D.find_aim_marker(e, an)
		if am != null:
			aims[an] = DRCharacter3D.rel_xform(e, am)
	var ok := DREquipHold.write_hold(asset, bone, e.scene_file_path, local, mk.transform if mk != null else null,
		(mk as DRHandTarget3D).motion_weights if mk is DRHandTarget3D else {}, DRCharacter3D.motion_offsets(e), aims)
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
	if _aim_lock or _root == null or _root.get(prop) == value or (value is float and is_equal_approx(float(_root.get(prop)), value)):
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
	_aim_chk.disabled = not on or _per_motion            # 유닛 값(모든 동작 공통) — 이 동작만이면 잠김(10-27)
	_aim_chk.button_pressed = _root.aim_enabled if on else false
	_aim_chk.tooltip_text = String(_aim_chk.get_meta(&"tip", _aim_chk.tooltip_text)) + (LOCK_TIP if _per_motion else "")
	for prop in _aim_sp:
		var sp := _aim_sp[prop] as SpinBox
		sp.editable = on and _root.aim_enabled and not _per_motion
		if on:
			sp.value = float(_root.get(prop)) / float(sp.get_meta(&"aim_scale", 1.0))
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


## 조준 표지(총구 · 견착, 10-21)를 무기 아래에 만들고 고른다 — 이미 있으면 고르기만. 처음 자리 = 무기 메시에서 잰 자리
## (총구 = 총열 축 앞 끝 · +Z = 방향, 견착 = 개머리판 끝 가운데). 기즈모로 옮기면 레이 · 팔 몫의 축이 바로 따라온다(되돌리기 한 칸)
func make_aim_marker(kind: String) -> Node3D:
	if _marker_locked():
		return null
	var e := _equip_from(_node(_sel))
	if e == null:
		e = _weapon_equip()
	if e == null:
		_set_status("무기(장비)를 고르세요")
		return null
	var cur := DRCharacter3D.find_aim_marker(e, kind)
	if cur == null:
		var mz := DRCharacter3D.find_muzzle(e)
		if mz.is_empty():
			_set_status("이 장비는 메시가 없어 %s 자리를 못 잽니다" % kind)
			return null
		var mk := Marker3D.new()
		mk.name = kind
		mk.gizmo_extents = 0.05
		var muzzle := kind == DRCharacter3D.MUZZLE_NAME
		var dir: Vector3 = mz[1]
		var b := Basis.IDENTITY if not muzzle or dir.is_equal_approx(Vector3.BACK) else Basis.looking_at(-dir, Vector3.UP)   # +Z = 레이 방향
		mk.transform = Transform3D(b, mz[0] if muzzle else mz[2])
		_begin("장비: %s 표지" % kind)
		_op_add(e, mk, [mk])
		_end(true)
		cur = mk
	_select_node(_root.get_path_to(cur))
	if _giz.tool_mode == TransformGizmo.Tool.VIEW:
		set_tool(TransformGizmo.Tool.MOVE)
	_set_status("%s 표지 — 기즈모로 옮기세요(W 이동%s). 하늘색 선 = 레이 · 노란 십자 = 견착점" % [kind, " · E 회전, 파란 축 = 방향" if kind == DRCharacter3D.MUZZLE_NAME else ""])
	return cur


## 총구 · 견착 표지를 지운다 — 무기 메시에서 다시 잰다(부모 유닛에서 온 표지는 숨김)
func clear_aim_markers() -> void:
	if _marker_locked():
		return
	var e := _equip_from(_node(_sel))
	if e == null:
		e = _weapon_equip()
	var ms: Array[Node3D] = []
	for kind in [DRCharacter3D.MUZZLE_NAME, DRCharacter3D.SHOULDER_NAME]:
		var m := DRCharacter3D.find_aim_marker(e, kind) if e != null else null
		if m != null and (m.owner == _root or _is_inherited(m)):
			ms.append(m)
	if ms.is_empty():
		_set_status("조준 표지가 없습니다 — 이미 무기 메시에서 잰 자리")
		return
	_begin("장비: 조준 표지 지움(자동으로)")
	for m in ms:
		if _root.get_path_to(m) == _sel:           # 빼기 전에(빼면 경로가 없다)
			_sel = NodePath()
		if _is_inherited(m):
			_op_prop(m, "visible", false)
		else:
			_op_remove(m)
	_end(true)
	_set_status("조준 표지를 지움 — 총구 · 견착점을 무기 메시에서 다시 잼")


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
	var mw := _prev.muzzle_world()
	var tp: Vector3 = (mw[0] as Vector3 if not mw.is_empty() else g * (ar["muzzle"] as Vector3)) + (g.basis * (ar["aim_dir"] as Vector3)).normalized() * AIM_MARK_M
	_target = (body + tp) * 0.5
	_dist = clampf(body.distance_to(tp) * 2.4 + 1.4, 3.3, 7.0)
	_update_cam()


func _apply_aim_preview() -> void:
	var height := _aim_height_sl.value if _aim_height_sl != null else 0.0
	_update_aim_label()
	if _prev == null:
		return
	if _aim_preview:
		_prev.set_aim_elevation(height, true)
	else:
		_prev.clear_aim_target(true)
	_force_pose()


## 끌기 막대 옆 글자 — 각 + (조준 미리보기 중인데 안 도는 까닭이 있으면) 주황 경고. 보는 곳(막대) 바로 옆에 둔다 — 아래 정보 줄 끝은 안 읽힌다(10-21)
func _update_aim_label() -> void:
	if _aim_lbl == null:
		return
	var t := "%+d°" % int(_aim_height_sl.value if _aim_height_sl != null else 0.0)
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
	if _prev == null:
		_cur_motion = ""
		return
	var names := _prev.motion_names()
	names.sort()
	var want := keep if names.has(keep) else (DEFAULT_MOTION if names.has(DEFAULT_MOTION) else (names[0] if not names.is_empty() else ""))
	_fill_motion_table()
	if want != "":
		play_motion(want)


func current_motion() -> String:
	return _cur_motion


## 미리보기에서 그 동작을 튼다(섞기 없이 — 그 동작의 손 IK 비중 · 동작별 무기 자리)
func play_motion(motion: String) -> void:
	if _prev == null or motion == "":
		return
	_cur_motion = motion
	_motion_lbl.text = motion
	_prev.play_motion(motion, 0.0)
	_acc = 0.0
	_update_aim_label()                          # 조준 비중 0 동작이면 막대 옆 경고
	if _per_motion:
		_show_xform()                          # 숫자 칸 = 이 동작 자리 · 띠 = 이 동작 이름
	else:
		_update_pm_ui()
	_mark_motion_row(motion)
	_fill_tree.call_deferred()                 # 손 기준 나무 = 지금 동작에서 쥔 곳(10-27) — 표 신호 안일 수 있어 미룸


func _seek(frac: float) -> void:
	if _prev == null:
		return
	var ap := _prev.get_animation_player()
	if ap.current_animation == "":
		return
	ap.seek(ap.get_animation(ap.current_animation).length * clampf(frac, 0.0, 1.0), true)
	_time_sl.set_value_no_signal(clampf(frac, 0.0, 1.0))
	_update_time_lbl()


## 타임라인을 끌면 멈추고 그 프레임으로(끄는 동안 재생이 프레임을 덮지 않게)
func _on_time(v: float) -> void:
	if _playing:
		toggle_play()
	_seek(v)


## 재생 ↔ 멈춤(타임라인 단추 · Space)
func toggle_play() -> void:
	_playing = not _playing
	_play_btn.text = "⏸" if _playing else "▶"


## 타임라인 초 = 지금 / 동작 길이
func _update_time_lbl() -> void:
	if _time_lbl == null or _prev == null:
		return
	var ap := _prev.get_animation_player()
	if ap.current_animation == "":
		_time_lbl.text = ""
		return
	var ln := ap.get_animation(ap.current_animation).length
	_time_lbl.text = "%.2f / %.2f 초" % [_time_sl.value * ln, ln]


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
		if mm.button_mask == 0:
			_drag = 0                              # 뗌을 못 받았다(기즈모가 삼킴 · 창 밖) — 단추 없이 움직이는데 카메라가 돌지 않게(10-27)
			return
		if _drag == 1:
			_yaw -= mm.relative.x * 0.4
			_pitch = clampf(_pitch + mm.relative.y * 0.4, -85.0, 85.0)
		elif _drag == 2:
			var b := DRBaker.view_basis(_yaw, _pitch)
			_target += (b.x * -mm.relative.x + b.y * mm.relative.y) * _dist * 0.0022
		else:
			_dist = clampf(_dist * exp((mm.relative.y - mm.relative.x) * 0.006), 0.2, 10.0)
		_update_cam()


## 창을 바꾸면 카메라 끌기를 푼다(뗌이 안 온다 — 돌아왔을 때 단추 없이도 돌지 않게, 10-27)
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_drag = 0


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
				_update_time_lbl()
	var pt := "⏸" if _playing else "▶"
	if _play_btn.text != pt:                    # 검사 · 다른 길이 _playing 을 바로 바꿔도 단추가 따라오게
		_play_btn.text = pt
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
		parts.append("S%s>%s" % [_root.get_path_to(s), (s as BoneAttachment3D).bone_name if s is BoneAttachment3D else
			"mount%d.%d" % [int((s as DRGripMount3D).mode), int((s as DRGripMount3D).hold)]])
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
			if _is_posed(n):
				parts.append(str(DRCharacter3D.motion_offsets(n)))    # 동작별 자리(10-19 — 되돌리기 · 인스펙터 메타로 바뀐 것도 따라간다 · 손 표지도 10-27)
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
		if w != null and socket_hand(w) == side:
			parts.append("%s: %s" % [nm, _rest_why(w, side)])
			continue
		if w != null and _prev.get_hand_marker(side) != null and _prev.get_ik_weight(side) <= 0.001:
			parts.append("%s: 총에 안 붙음 — 동작 그대로(이 동작 잡기 = %s)" % [nm, _grip_name(motion_grip(_offset_equip(), current_motion()))])
			continue
		if _prev.get_hand_marker(side) == null:
			parts.append("%s: 표지 없음 — 동작 그대로%s" % [nm, " · [%s 표지 ← 지금 손]" % nm if kind >= 0 else ""])
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
	return "조준 %d %% · 총구를 %+.0f° 듦(팔 %+.0f° · 허리 · 가슴 %+.0f°)%s — 동작이 원래 겨눈 높이 %+.0f°" % [roundi(w * 100.0), float(r["pitch"]),
		float(r["arm_pitch"]), float(r["body_pitch"]), " · 한계에서 멈춤" if bool(r["clamped"]) else "", float(r["base_pitch"])]


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
	# 조준: 표적(분홍 — 겨눌 방향) · 총구 선 = 레이(초록 = 표적으로 · 주황 = 한계 · 하늘 = 조준 표지를 고르는 중) · 견착점(노랑 — 팔 몫의 축)
	# 조준 표지(총구 · 견착)를 고르면 미리보기를 안 켜도 레이 · 견착점을 그린다 — 기즈모로 옮기며 보게(10-21)
	var aim_sel := _is_aim_marker(_node(_sel))
	if _aim_preview or aim_sel:
		var ar := _prev.aim_report() if _aim_preview else {}
		var mw := _prev.muzzle_world()
		if not mw.is_empty() and (aim_sel or not ar.is_empty()):
			if not ar.is_empty():
				var tp: Vector3 = (mw[0] as Vector3) + (_prev.global_transform.basis * (ar["aim_dir"] as Vector3)).normalized() * AIM_MARK_M
				_cross(tp, 0.06, Color(1.0, 0.35, 0.85))
			var sw := _prev.shoulder_world()
			if sw != Vector3.INF:
				_cross(sw, 0.035, Color(1.0, 0.9, 0.2))
			var col := Color(0.4, 0.85, 1.0) if ar.is_empty() else (Color(1.0, 0.6, 0.2) if bool(ar["clamped"]) else Color(0.35, 1.0, 0.45))
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


# ───────────── 동작 표(동작마다 잡기 · 무기 자리 · 조준) ─────────────

## 잡기 칸의 고를 거리 차례 — 기본(…) · 오른손 · 왼손 · 양손(· 안 붙음 — 그 동작이 지금 그럴 때만)
const MT_GRIP_KINDS := [-1, 0, 1, 2, -2]


func _fill_motion_table(report: Array = []) -> void:
	if not report.is_empty():
		_last_rep = report
		_rep_stale = false
	_mt_lock = true
	_mt.clear()
	var top := _mt.create_item()
	var e := _offset_equip()
	var by := {}
	for r in _last_rep:
		by[String((r as Dictionary)["motion"])] = r
	_mt.set_column_title(1, "손↔표지 cm" + (" (지난)" if _rep_stale else ""))
	var base := motion_grip(e, "") if e != null else -1
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
				var tip := String(d.get("tip", ""))
				if _rep_stale:
					it.set_custom_color(1, Color(0.5, 0.52, 0.56))
					it.set_tooltip_text(1, tip + "\n잰 뒤 무기 · 표지 자리가 바뀜 — [모든 동작 재기]")
				elif float(d["ik_max"]) > 0.05 and float(d["weight"]) > 0.0:
					it.set_custom_color(1, Color(0.95, 0.65, 0.3))
					it.set_tooltip_text(1, tip + "\n팔이 표지에 안 닿는 시점이 있음(어깨 → 손목 목표 / 팔 길이 최대 %.2f) — 행을 두 번 눌러(이 동작만) [손에 맞추기] 나 기즈모로" % float(d["reach_max"]))
				else:
					it.set_tooltip_text(1, tip)
			else:
				it.set_text(1, "-")
				it.set_tooltip_text(1, "[모든 동작 재기] 를 누르면 동작마다 잰다")
			_fill_grip_cell(it, n, e, base)
			_fill_offset_cell(it, n)
			_fill_aim_cell(it, n)
			if n == current_motion():
				it.select(0)                     # 지금 동작 행(잠금 중이라 다시 틀지 않음)
	_mt_lock = false


## 잡기 칸 — 눌러서 고름(기본(…) · 오른손 · 왼손 · 양손). 따로 정한 동작 = 주황. 0 · 1 이 아닌 비중(인스펙터로 넣은 것)은 풍선 도움말에
func _fill_grip_cell(it: TreeItem, motion: String, e: Node3D, base: int) -> void:
	if e == null or e.get_parent() == null:
		it.set_text(2, "-")
		return
	var g := motion_grip(e, motion)
	var own := motion_grip_own(e, motion)
	var opts := PackedStringArray(["기본(%s)" % _grip_name(base), "오른손", "왼손", "양손"])
	if own and g == -2:
		opts.append("안 붙음")
	it.set_cell_mode(2, TreeItem.CELL_MODE_RANGE)
	it.set_text(2, ",".join(opts))
	it.set_range_config(2, 0.0, float(opts.size() - 1), 1.0)
	it.set_range(2, float(MT_GRIP_KINDS.find(g)) if own else 0.0)
	it.set_editable(2, true)
	var frac := PackedStringArray()
	for side in 2:
		var w := DRCharacter3D.hand_weight_for(e, side, motion)
		if w > 0.001 and w < 0.999:
			frac.append("%s %d%%" % [DRCharacter3D.SIDE_NAMES[side], roundi(w * 100.0)])
	if own:
		it.set_custom_color(2, Color(1.0, 0.68, 0.32))
	it.set_tooltip_text(2, "%s — %s%s\n눌러서 고름 — 기본(2 잡기의 기본 잡기대로) · 오른손 · 왼손 · 양손. 받침(총이 무엇을 따라가나)은 그대로 — 한 손만 붙는 동작은 총이 그 손 쪽을 따라간다" % [
		motion, ("이 동작만 %s 잡기" % _grip_name(g)) if own else ("기본 잡기대로(%s)" % _grip_name(base)), " · 붙는 정도 " + ", ".join(frac) if not frac.is_empty() else ""])


func _on_mt_edited() -> void:
	if _mt_lock:
		return
	var it := _mt.get_edited()
	if it == null:
		return
	if _mt.get_edited_column() == 2:
		var i := int(it.get_range(2))
		set_motion_grip(it.get_text(0), int(MT_GRIP_KINDS[i]) if i >= 0 and i < MT_GRIP_KINDS.size() else -1)
	elif _mt.get_edited_column() == 4:
		set_aim_weight(it.get_text(0), it.get_range(4))


## 동작마다 손바닥 ↔ 표지(IK 전 · 뒤) — 미리보기 사본으로 8 시점씩 두 손을 재서 동작마다 한 줄: 그 동작에서 총에 붙은 손(IK 비중 > 0) 중 IK 뒤가 먼 쪽
## (붙은 손이 없으면 왼손). 줄 = DREquipHold.motion_report 의 줄 + side · tip(손마다 수치)
func _measure(motions: PackedStringArray) -> Array:
	var per := [{}, {}]
	for side in 2:
		for r in DREquipHold.motion_report(_prev, motions, 8, side):
			(per[side] as Dictionary)[String((r as Dictionary)["motion"])] = r
	var out := []
	for mo in motions:
		var pick := {}
		var tips := PackedStringArray()
		for side in 2:
			var d: Dictionary = (per[side] as Dictionary).get(mo, {})
			if d.is_empty():
				continue
			tips.append("%s(붙는 정도 %.1f): 동작 그대로 평균 %.1f / 최대 %.0f cm → IK 뒤 평균 %.1f / 최대 %.1f cm" % [DRCharacter3D.SIDE_NAMES[side], float(d["weight"]),
				float(d["raw_avg"]) * 100.0, float(d["raw_max"]) * 100.0, float(d["ik_avg"]) * 100.0, float(d["ik_max"]) * 100.0])
			if pick.is_empty() or (float(d["weight"]) > 0.0 and (float(pick["weight"]) <= 0.0 or float(d["ik_max"]) > float(pick["ik_max"]))):
				pick = d.duplicate()
				pick["side"] = side
		if pick.is_empty():
			continue
		pick["tip"] = "\n".join(tips) + " (8 시점)"
		out.append(pick)
	return out


## 모든 동작을 잰다(_measure) — 표에 넣고 돌려준다
func measure_all() -> Array:
	if _prev == null:
		return []
	var keep := current_motion()
	var t := _time_sl.value
	var rep := _measure(_prev.motion_names())
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
			worst = "%s(%s)" % [d["motion"], DRCharacter3D.SIDE_NAMES[int(d["side"])]]
	_set_status("동작 %d개 잼(두 손) — 총에 붙은 손 중 가장 먼 것: %s %.1f cm" % [rep.size(), worst, wv * 100.0] if worst != "" else "동작 %d개 잼" % rep.size())
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
	_show_aim_settings()                       # 조준 칸(유닛 값 — 이 동작만이면 잠김)
	_fill_motion_table()
	if on:
		var e2 := _offset_equip()
		_set_status("적용 범위 = 이 동작만 — %s 의 잡기 · %s 자리만 고칩니다. 다른 동작 · 기본은 그대로 · 무기 · 소켓 · 받침 · 표지 · 조준 칸은 잠김" % [current_motion(), e2.name if e2 != null else "무기"]
			if current_motion() != "" else "적용 범위 = 이 동작만 — 오른쪽 표에서 동작을 고르세요")
	else:
		_set_status("적용 범위 = 모든 동작 — 기본 잡기 · 기본 자리를 고칩니다")


## 적용 범위 스위치 · 범위 한 줄 · [손에 맞추기] · 미리보기 테두리 · 꼬리표 · 표지 단추 잠금 · 숫자 칸 아래 안내를 지금 상태로
func _update_pm_ui() -> void:
	if _pm_banner == null:
		return
	_update_grip_ui()
	for i in _pm_btns.size():
		_pm_btns[i].set_pressed_no_signal(i == (1 if _per_motion else 0))
	if _pm_btns.size() > 1:                     # 눌린 "이 동작만" = 미리보기 테두리와 같은 주황(테마 여백은 그대로 — 틀을 덮으면 글자가 잘렸다)
		_pm_btns[1].self_modulate = Color(1.0, 0.68, 0.32) if _per_motion else Color.WHITE
	var e := _offset_equip()
	var on := _offset_node()                    # 고친 자리를 보일 노드 — 손을 골랐으면 그 손(10-27), 아니면 무기
	var hand := _is_hand_marker(on)
	var mo := current_motion()
	var key := DRCharacter3D.offset_key(on, mo) if on != null else ""
	var own: Array = DRCharacter3D.motion_offsets(e).keys() if e != null else []
	var can_fit := e != null and mo != "" and can_fit_hands(e)
	_pm_banner.visible = _per_motion
	_pm_frame.visible = _per_motion
	var fit_tip := ""
	if _per_motion:
		var now := ""
		if on == null:
			_pm_label.text = "✎ 이 동작만 — 무기(장비)를 고르세요"
		elif mo == "":
			_pm_label.text = "✎ 이 동작만 — 오른쪽 표에서 동작을 고르세요"
		else:
			now = _offset_text(on, mo) if key == mo else ("아직 따로 없음 — " + _offset_text(on, mo)) if key != "" else "아직 기본 자리와 같음"
			_pm_label.text = "✎ 이 동작만 — %s · %s%s" % [mo, "%s 자리 " % on.name if hand else "", now]
		_scope_note.text = "%s 만 — 2 잡기(지금 %s%s) · 3 %s 자리(%s). 기본 · 다른 동작은 그대로 · 모든 동작 공통(무기 · 소켓 · 받침 · 보간 · 조준 칸 · 조준 표지)은 잠김" % [
			mo if mo != "" else "고른 동작", _grip_name(motion_grip(e, mo)) if e != null and mo != "" else "-",
			"(따로)" if motion_grip_own(e, mo) else "(기본대로)", on.name if hand else "무기", now if now != "" else "-"]
		_pm_fit_btn.text = "🤚 손에 맞추기 — %s 만" % mo if mo != "" else "🤚 손에 맞추기 — 이 동작만"
		fit_tip = "지금 프레임에서 손이 총의 손 표지에 닿게 이 동작(%s)의 무기 자리를 자동으로 잡는다 — 이 동작에만 저장(되돌리기 한 칸)." % mo
	else:
		_scope_note.text = "모든 동작 — 2 잡기 = 기본 잡기(받침) · 3 무기 자리 = 기본 자리%s. 동작마다 따로 하려면 [✎ 이 동작만](오른쪽 표 행 두 번 누름)" % (
			"" if own.is_empty() else " — 따로 자리를 둔 동작 %d개(%s)는 그 차이를 그대로 얹음" % [own.size(), ", ".join(PackedStringArray(own.slice(0, 3))) + (" …" if own.size() > 3 else "")])
		_pm_fit_btn.text = "🤚 손에 맞추기 — 모든 동작"
		fit_tip = "지금 프레임(%s)에서 손이 총의 손 표지에 닿게 기본 자리(모든 동작)를 자동으로 잡는다(되돌리기 한 칸)." % (mo if mo != "" else "동작 없음")
	_pm_fit_btn.tooltip_text = fit_tip + "\n손에 든 무기 = 든 손을 축으로 돌려 다른 손이 표지에 닿게(쥔 손에서 안 미끄러짐) · 양손 = 두 표지의 가운데 · 방향을 두 손바닥에." + \
		"\n두 손이 총에 있는 프레임에서 누르세요(타임라인을 멈추고 끌어 고름). 잘 안 맞으면 기즈모로 다듬기" + \
		("\n— 고정(땅) 받침대 · 손 아닌 뼈 소켓의 장비는 자동이 없음(기즈모로)" if e != null and not can_fit and not can_fit_hands(e) else "")
	_pm_fit_btn.disabled = not can_fit
	_pm_reset_btn.visible = _per_motion
	_pm_reset_btn.disabled = on == null or key != mo
	_pm_reset_btn.text = "↺ %s 이 동작 기본으로" % on.name if hand else "↺ 이 동작 기본으로"
	for b in _marker_btns:
		b.disabled = _per_motion
		b.tooltip_text = String(b.get_meta(&"tip", "")) + ("\n— 잠김: 적용 범위가 \"이 동작만\". 표지는 모든 동작 공통이라 [모든 동작]에서 고친다" if _per_motion else "")
	for c in _common_ctrls:                     # 무기 · 소켓 · 보간(모든 동작 공통, 10-27)
		if c is BaseButton:
			(c as BaseButton).disabled = _per_motion
		elif c is Slider:
			(c as Slider).editable = not _per_motion
			c.modulate.a = 0.45 if _per_motion else 1.0   # 끌 수 없는 막대는 흐리게(단추처럼 잠긴 게 보이게)
		c.tooltip_text = String(c.get_meta(&"tip", "")) + (LOCK_TIP if _per_motion else "")
	var note := ""
	if on != null and mo != "" and _is_posed(_node(_sel)):
		var what := "%s 자리(총의 어디를 쥐나)" % on.name if hand else "무기 자리"
		if _per_motion:
			note = "숫자 칸 = %s 의 %s(위치 · 회전만, 크기는 기본 자리). %s" % [mo, what, "지금 " + _offset_text(on, mo) if key != "" else "아직 기본 자리와 같음"]
		elif key != "":
			note = "지금 동작(%s)은 따로 %s가 있어 미리보기 = 기본 + %s. 기즈모로 옮기면 기본이 바뀌고 이 차이는 그대로" % [mo, what, _offset_text(on, mo)]
		if hand and e != null and DRCharacter3D.hand_weight_for(e, _marker_side(on), mo) <= 0.001:
			note += "%s⚠ %s 에서 %s은 총을 놓음(잡기) — 옮겨도 손은 그대로. 2 잡기에서 %s을 붙이면 보인다" % ["
" if note != "" else "", mo, on.name, on.name]
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
	var e := _offset_node()
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
## [손에 맞추기] — 적용 범위대로: 이 동작만 = 그 동작의 자리 · 모든 동작 = 기본 자리
func fit_to_hands() -> Dictionary:
	return fit_motion_offset(not _per_motion)


## 지금 프레임에서 손이 총의 손 표지에 닿게 무기 자리를 잡는다 — to_base = 기본 자리(모든 동작) · 아니면 지금 동작의 동작별 자리
func fit_motion_offset(to_base := false) -> Dictionary:
	var e := _offset_equip()
	var pe := _prev_node(e) as Node3D
	var mo := current_motion()
	if e == null or pe == null or _prev == null or mo == "":
		_set_status("무기와 동작을 고르세요")
		return {}
	if not can_fit_hands(e):
		_set_status("%s — 고정(땅) 받침대 · 손이 아닌 뼈 소켓의 장비는 자동 맞추기가 없습니다(기즈모로)" % e.name)
		return {}
	var hold := socket_hand(e)                                      # 무기를 든 손(손 뼈 소켓 — 옛 방식) — 받침대면 없음
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
		if side == hold or palms[side] == null or DRCharacter3D.hand_weight_for(e, side, mo) <= 0.001:
			continue                                                # 이 동작에서 총에 안 붙는 손(잡기 · 비중 0)
		var mk := DRCharacter3D.find_hand_marker(pe, side)
		if mk == null:
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
	var l2: Transform3D = anchor_p.global_transform.affine_inverse() * (c * pe.global_transform)     # 받침 기준 새 자리(보이는 자리)
	if to_base:
		_begin("장비: %s 기본 자리 손에 맞추기(%s)" % [e.name, mo])
		_op_prop(e, "transform", l2 * _prev.get_equip_offset(pe).affine_inverse())     # 이 동작에 따로 자리가 있으면 그 차이를 뺀 기본 자리
		_end(false)
	else:
		set_motion_offset(e, mo, e.transform.affine_inverse() * l2, "장비: %s %s 자리 맞추기" % [e.name, mo])
	_seek(t)
	var after := _hand_dists()
	var txt := PackedStringArray()
	for side in follow:
		txt.append("%s 동작 그대로 %.1f → %.1f cm(IK 뒤 %.1f → %.1f)" % [DRCharacter3D.SIDE_NAMES[side], (before["raw"] as Array)[side], (after["raw"] as Array)[side],
			(before["ik"] as Array)[side], (after["ik"] as Array)[side]])
	_set_status("손에 맞춤 — %s · %s %d%% · %s · %s" % ["모든 동작(기본 자리)" if to_base else mo + " 만", mo, int(t * 100.0),
		"기본 자리" if to_base else _offset_text(e, mo), " · ".join(txt)])
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
	_mt_menu.add_item("손에 맞추기 — 이 동작만", 1)
	_mt_menu.set_item_disabled(1, not can_fit_hands(e))
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
