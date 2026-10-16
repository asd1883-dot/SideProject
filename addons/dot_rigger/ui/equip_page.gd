@tool
extends DRPage
class_name DREquipPage

## ② 장비 탭(10-16, 3D 게임 정석) — 유닛 프리팹의 소켓 · 장비 편집기. 예전 ② 장비 굽기(2D 세트별 무기 그림 · DREquipWindow)를 갈음한다.
## 사용자(10-16): "2번 탭은 장비 3D 모델 하이어라키에 접근해 맞추는 방식, 즉 3D 게임 방식의 정석으로. 나중에 헬멧도 모델링 head 에 꽂으면 되고."
##   소켓 = 유닛 씬의 BoneAttachment3D(뼈를 따라감) · 장비 = 소켓 아래 모델 씬 인스턴스(자리 · 회전 = 소켓 기준 고정)
##   · 왼손 표지 = 장비 아래 DRHandTarget3D(왼팔 두 마디 IK 의 목표 — DRCharacter3D 가 조립 때 붙인다)
## 이 탭과 씬 독 · 인스펙터 · 3D 화면 기즈모가 **같은 노드**를 고친다(에디터 = 열린 유닛 씬 · 되돌리기 Ctrl+Z, 에디터 밖 = 인스턴스를 바로).
##
##   왼쪽: 유닛 · 소켓 나무(소켓 → 장비 → 표지) · 소켓 더하기(뼈) · 장비 넣기/바꾸기/빼기 · 고른 노드 자리(cm · °) · 맞추기 · 저장
##   가운데: 미리보기 — 돌려 보기(끌기 = 돌리기 · 휠 = 확대 · 가운데/Shift 끌기 = 옮기기) / 도트 보기(게임과 같은 DRDotView3D) · 동작 재생 · 손 ↔ 표지 거리
##   오른쪽: 동작마다 왼손(IK 전 · 뒤 cm) · 왼손 IK 비중(0 = 동작 그대로 — 수류탄 · 장전 · 맨손 달리기 등)
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
var _live := {}                           # 미리보기 뼈대가 갱신될 때 잰 왼손(IK 뒤)
# 동작 표
var _mt: Tree
var _mt_lock := false
var _last_rep: Array = []                 # 마지막으로 잰 동작별 수치(DREquipHold.motion_report)
var _rep_stale := false                   # 잰 뒤 무기 · 표지 자리가 바뀜(다시 재야 맞음)


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
	var frow := HBoxContainer.new()
	left.add_child(frow)
	_btn(frow, "지금 자세로 왼손 표지", "미리보기의 지금 동작 · 시점에서 왼손(동작 그대로) 자리 · 회전을 고른 장비의 왼손 표지로(없으면 만든다)", make_support_marker)
	_btn(frow, "지금 동작으로 무기 맞추기", "지금 동작 · 시점의 두 손바닥으로 무기 방향을 다시 잡는다(쥐는 점 = 지금 오른 손바닥 자리, 표지가 있으면 그 점이 왼손 쪽)", fit_weapon)
	left.add_child(HSeparator.new())
	_xf_title = Label.new()
	_xf_title.text = "고른 노드 —"
	left.add_child(_xf_title)
	var grid := GridContainer.new()
	grid.columns = 4
	left.add_child(grid)
	for row in [["위치 cm", _pos, 0.1, -500.0, 500.0], ["회전 °", _rot, 0.5, -360.0, 360.0]]:
		var l := Label.new()
		l.text = String(row[0])
		grid.add_child(l)
		for k in 3:
			var sp := SpinBox.new()
			sp.step = float(row[2])
			sp.min_value = float(row[3])
			sp.max_value = float(row[4])
			sp.allow_greater = true
			sp.allow_lesser = true
			sp.custom_minimum_size = Vector2(88, 0)
			sp.prefix = ["x", "y", "z"][k]
			sp.tooltip_text = "부모 기준(소켓 아래 장비 = 손 뼈 기준, 표지 = 장비 기준). 인스펙터의 position · rotation_degrees 와 같은 값"
			sp.value_changed.connect(func(_v: float) -> void: _on_xf_changed())
			grid.add_child(sp)
			(row[1] as Array).append(sp)
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
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.custom_minimum_size = Vector2(320, 320)
	mid.add_child(stack)
	_view3d = SubViewportContainer.new()
	_view3d.stretch = true
	_view3d.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view3d.mouse_filter = Control.MOUSE_FILTER_STOP
	_view3d.gui_input.connect(_on_view_input)
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
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.add_theme_font_size_override("font_size", 12)
	mid.add_child(_info)

	# 오른쪽 — 동작마다 왼손
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(380, 0)
	right_split.add_child(right)
	var rrow := HBoxContainer.new()
	right.add_child(rrow)
	var rl := Label.new()
	rl.text = "동작마다 왼손(표지 ↔ 손바닥)"
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rrow.add_child(rl)
	_btn(rrow, "모든 동작 재기", "동작마다 8 시점에서 왼 손바닥 ↔ 표지 거리(IK 전 = 동작 그대로 · IK 뒤) — 미리보기 사본으로 잰다", measure_all)
	_mt = Tree.new()
	_mt.columns = 4
	_mt.hide_root = true
	_mt.column_titles_visible = true
	_mt.set_column_title(0, "동작")
	_mt.set_column_title(1, "IK 전 cm")
	_mt.set_column_title(2, "IK 뒤 cm")
	_mt.set_column_title(3, "IK 비중")
	_mt.set_column_expand(0, true)
	for c in [1, 2, 3]:
		_mt.set_column_expand(c, false)
		_mt.set_column_custom_minimum_width(c, 78)
	_mt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mt.item_edited.connect(_on_mt_edited)
	_mt.item_selected.connect(func() -> void:
		var it := _mt.get_selected()
		if it != null:
			play_motion(it.get_text(0)))
	right.add_child(_mt)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 11)
	help.add_theme_color_override("font_color", Color(0.6, 0.63, 0.67))
	help.text = "평균 / 최대. IK 비중 0 = 그 동작은 왼손을 표지에 안 붙인다(수류탄 던지기 · 장전 · 맨손 달리기처럼 왼손이 총을 놓는 동작). 비중은 왼손 표지(DRHandTarget3D)의 motion_weights 에 저장된다. 행을 누르면 그 동작을 튼다."
	right.add_child(help)
	_fill_bones(PackedStringArray())
	_fill_models()
	_dots.visible = false
	_update_cam()


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


## 유닛의 소켓(루트가 가진 BoneAttachment3D — 안에서 조립한 몸은 주인이 없어 빠진다)
func _sockets() -> Array[BoneAttachment3D]:
	var out: Array[BoneAttachment3D] = []
	if _root == null:
		return out
	for s in DRCharacter3D.find_sockets(_root):
		if s.owner == _root:
			out.append(s)
	return out


## 소켓의 보이는 장비(첫 것)
static func _equip_of(s: BoneAttachment3D) -> Node3D:
	for c in s.get_children():
		if c is Node3D and (c as Node3D).visible:
			return c as Node3D
	return null


## 오른손 소켓의 무기
func _weapon_equip() -> Node3D:
	for s in _sockets():
		if s.bone_name == DRCharacter3D.WEAPON_BONE:
			return _equip_of(s)
	return null


func _node(p: NodePath) -> Node:
	if _root == null or p.is_empty():
		return null
	return _root.get_node_or_null(p)


## 고른 노드가 든 소켓(고른 것이 소켓이면 그것, 장비 · 표지면 위로 올라가며)
func _socket_of(n: Node) -> BoneAttachment3D:
	while n != null and n != _root:
		if n is BoneAttachment3D:
			return n as BoneAttachment3D
		n = n.get_parent()
	return null


## 고른 노드가 속한 장비(소켓 바로 아래 노드)
func _equip_from(n: Node) -> Node3D:
	while n != null and n != _root:
		if n.get_parent() is BoneAttachment3D:
			return n as Node3D
		n = n.get_parent()
	return null


# ───────────── 나무 · 칸 ─────────────

func _refresh_all() -> void:
	_fill_tree()
	_rebuild_preview()
	_struct_sig = _make_struct_sig()
	_xform_sig = _make_xform_sig()
	_show_xform()


func _fill_tree() -> void:
	_tree.clear()
	var top := _tree.create_item()
	if _root == null:
		return
	for s in _sockets():
		var si := _tree.create_item(top)
		si.set_text(0, "🦴 %s  (뼈 %s)" % [s.name, s.bone_name])
		si.set_metadata(0, _root.get_path_to(s))
		si.set_tooltip_text(0, "소켓(BoneAttachment3D) — 뼈 %s 를 따라간다%s" % [s.bone_name, " · 부모 유닛에서 옴" if _is_inherited(s) else ""])
		for c in s.get_children():
			if not (c is Node3D):
				continue
			var e := c as Node3D
			var ei := _tree.create_item(si)
			var src := e.scene_file_path.get_file() if e.scene_file_path != "" else e.get_class()
			ei.set_text(0, "%s%s  (%s)" % ["⊘ " if not e.visible else "", e.name, src])
			ei.set_metadata(0, _root.get_path_to(e))
			ei.set_tooltip_text(0, "장비%s%s" % [" — 숨김(게임에서는 지운다)" if not e.visible else "", " · 부모 유닛에서 옴" if _is_inherited(e) else ""])
			if not e.visible:
				ei.set_custom_color(0, Color(0.55, 0.57, 0.6))
			var m := DRCharacter3D.find_support(e)
			if m != null:
				var mi := _tree.create_item(ei)
				mi.set_text(0, "✋ %s  (왼손 표지%s)" % [m.name, "" if m is DRHandTarget3D else " — 비중 없는 Marker3D"])
				mi.set_metadata(0, _root.get_path_to(m))
				mi.set_tooltip_text(0, "왼손 IK 목표: 원점 = 왼 손바닥 자리, 회전 = 왼손 뼈 회전")
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


func _show_xform() -> void:
	var n := _node(_sel) as Node3D
	_xf_lock = true
	var on := n != null and not (n is BoneAttachment3D)
	for sp in _pos + _rot:
		sp.editable = on
	if n == null:
		_xf_title.text = "고른 노드 — 없음(나무에서 장비 · 표지를 고르세요)"
	elif n is BoneAttachment3D:
		_xf_title.text = "소켓 %s — 뼈를 따라가므로 자리는 장비 · 표지에서" % n.name
	else:
		_xf_title.text = "%s — 부모(%s) 기준" % [n.name, n.get_parent().name]
		for k in 3:
			_pos[k].set_value_no_signal(snappedf(n.position[k] * 100.0, 0.01))
			_rot[k].set_value_no_signal(snappedf(n.rotation_degrees[k], 0.01))
	_xf_lock = false


func _on_xf_changed() -> void:
	if _xf_lock:
		return
	var n := _node(_sel) as Node3D
	if n == null or n is BoneAttachment3D:
		return
	var p := Vector3(_pos[0].value, _pos[1].value, _pos[2].value) / 100.0
	var r := Vector3(_rot[0].value, _rot[1].value, _rot[2].value)
	_set_props_merged("장비: %s 자리" % n.name, [[n, "position", p], [n, "rotation_degrees", r]])


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
		var socks := _sockets()
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
	if not hold.is_empty() and String(hold["bone"]) == sock.bone_name:
		n.transform = hold["weapon"]
		if hold.has("support"):
			var mk := _new_marker(hold["support"], hold["motion_weights"])
			n.add_child(mk)
			owned.append(mk)
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


func _new_marker(xf: Transform3D, weights: Dictionary) -> DRHandTarget3D:
	var mk := DRHandTarget3D.new()
	mk.name = DRCharacter3D.SUPPORT_NAME
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
	var e := _equip_from(_node(_sel))
	if e == null:
		e = _weapon_equip()
	var pe := _prev_node(e)
	if e == null or pe == null or _prev == null:
		_set_status("장비(무기)를 고르세요")
		return null
	var sk := _prev.get_skeleton()
	var rig: DRRigModel = _prev.get_body_entry()["rig"]
	var lp: DRRigModel.Part = rig.parts.get("L_Hand", null)
	var sock := _socket_of(e)
	if lp == null or sock == null:
		return null
	var hl := sk.get_bone_global_pose(lp.root_bone)        # 갱신 밖 = 동작 자세(IK 전)
	var w_skel := sk.get_bone_global_pose(sk.find_bone(sock.bone_name)) * DREquipHold.xform_to(_prev_node(sock), pe)
	var m := w_skel.affine_inverse() * Transform3D(hl.basis.orthonormalized(), hl * (lp.tail_local * 0.5))
	m.basis = m.basis.orthonormalized()
	var cur := DRCharacter3D.find_support(e)
	var added := false
	_begin("장비: 왼손 표지")
	if cur != null and cur.owner == _root:
		_op_prop(cur, "transform", _in_parent_of(cur, e, m))
	else:
		var mk := _new_marker(m, {})
		_op_add(e, mk, [mk])
		cur = mk
		added = true
	_end(added)
	_select_node(_root.get_path_to(cur))
	_set_status("왼손 표지 = %s %d%% 의 왼손(동작 그대로)" % [current_motion(), int(_time_sl.value * 100.0)])
	return cur


## 지금 동작 · 시점의 두 손바닥으로 무기 방향을 다시 잡는다(DREquipHold.fit). 쥐는 점 = 지금 오른 손바닥이 닿은 무기 자리(무기 근처일 때,
## 아니면 어림), 표지가 있으면 그 점이 왼손 쪽(표지 자리 그대로) — 없으면 표지를 그 자세의 왼손으로 만든다
func fit_weapon() -> void:
	var e := _equip_from(_node(_sel))
	if e == null:
		e = _weapon_equip()
	var pe := _prev_node(e)
	var sock := _socket_of(e)
	if e == null or pe == null or sock == null or _prev == null:
		_set_status("무기를 고르세요")
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


## 동작 하나의 왼손 IK 비중 — 왼손 표지(DRHandTarget3D)의 motion_weights 를 통째로 바꿔 넣는다(되돌리기 한 칸)
func set_motion_weight(motion: String, w: float) -> void:
	var mk := _support_marker()
	if mk == null or not (mk is DRHandTarget3D):
		_set_status("왼손 표지(DRHandTarget3D)가 없습니다")
		return
	var t := mk as DRHandTarget3D
	var mw: Dictionary[String, float] = t.motion_weights.duplicate()
	if absf(w - t.weight) < 0.001:
		mw.erase(motion)
	else:
		mw[motion] = clampf(w, 0.0, 1.0)
	var was_stale := _rep_stale
	_begin("장비: 왼손 비중 %s" % motion)
	_op_prop(t, "motion_weights", mw)
	_end(false)
	_rep_stale = was_stale                  # 비중은 자리를 안 바꾼다 — 그 동작만 다시 재서 표에 넣는다
	if _prev != null and not _last_rep.is_empty():
		var keep := current_motion()
		var kt := _time_sl.value
		var one := DREquipHold.motion_report(_prev, PackedStringArray([motion]), 8)
		for i in _last_rep.size():
			if not one.is_empty() and String((_last_rep[i] as Dictionary)["motion"]) == motion:
				_last_rep[i] = one[0]
		play_motion(keep)
		_seek(kt)
	_fill_motion_table.call_deferred()      # 미뤄서 — 이 함수는 표의 칸 고치기 신호에서도 불린다


## 고른 장비의(없으면 무기의) 왼손 표지
func _support_marker() -> Node3D:
	var e := _equip_from(_node(_sel))
	if e == null:
		e = _weapon_equip()
	return DRCharacter3D.find_support(e) if e != null else null


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


## 고른 장비의 자리 · 왼손 표지 · 동작별 비중을 모델 옆 asset.json(socket_hold)에
func save_hold_default() -> void:
	var e := _equip_from(_node(_sel))
	if e == null:
		e = _weapon_equip()
	var sock := _socket_of(e)
	var asset := DREquipHold.asset_for_model(e.scene_file_path) if e != null else ""
	if e == null or sock == null or asset == "":
		_set_status("모델 옆에 asset.json 이 있는 장비를 고르세요")
		return
	var mk := DRCharacter3D.find_support(e)
	var ok := DREquipHold.write_hold(asset, sock.bone_name, e.scene_file_path, e.transform, mk.transform if mk != null else null,
		(mk as DRHandTarget3D).motion_weights if mk is DRHandTarget3D else {})
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
	_live = {}
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


func _on_prev_updated() -> void:
	if _prev != null:
		_live = _prev.support_now()        # 신호 안 = IK 뒤


## 미리보기 사본의 노드 자리 · 보이기 · 비중을 유닛 것으로(구조가 같을 때 — 다시 조립하지 않고)
func _sync_preview() -> void:
	if _prev == null or _root == null:
		return
	for s in _sockets():
		var stack: Array[Node] = [s]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n.owner == _root:
				var pn := _prev.get_node_or_null(_root.get_path_to(n))
				if pn is Node3D and n is Node3D:
					(pn as Node3D).transform = (n as Node3D).transform
				if pn is DRHandTarget3D and n is DRHandTarget3D:
					(pn as DRHandTarget3D).motion_weights = (n as DRHandTarget3D).motion_weights.duplicate()
					(pn as DRHandTarget3D).weight = (n as DRHandTarget3D).weight
			stack.append_array(n.get_children())
	_prev.sync_support()
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


## 미리보기에서 그 동작을 튼다(섞기 없이 — 그 동작의 왼손 IK 비중)
func play_motion(motion: String) -> void:
	if _prev == null or motion == "":
		return
	for i in _motion_ob.item_count:
		if _motion_ob.get_item_text(i) == motion:
			_motion_ob.select(i)
	_prev.play_motion(motion, 0.0)
	_acc = 0.0


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


## 돌려 보기 ↔ 도트 보기(게임과 같은 3/4 방향 · 저해상도 · 외곽선)
func set_dot_mode(on: bool) -> void:
	_dot_mode = on
	_view3d.visible = not on
	_dotc.visible = on
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
		var m := _prev.get_weapon_mount()
		var mk := _prev.get_support_marker()
		if m != null and mk != null:
			_dist = maxf(0.9, m.global_position.distance_to(mk.global_position) * 2.6)   # 두 손이 다 들어오게(화각 35°)
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


## 미리보기 세상 좌표의 두 손 가운데(오른손 소켓 · 왼손 표지)
func _hands_center() -> Vector3:
	if _prev == null:
		return Vector3.INF
	var m := _prev.get_weapon_mount()
	var mk := _prev.get_support_marker()
	if m == null:
		return Vector3.INF
	return (m.global_position + (mk.global_position if mk != null else m.global_position)) * 0.5


func _update_cam() -> void:
	var b := DRBaker.view_basis(_yaw, _pitch)
	_cam.transform = Transform3D(b, _target + b * Vector3(0.0, 0.0, _dist))   # 부모가 뷰포트라 로컬 = 세상(트리 밖에서도 된다)


func _on_view_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null:
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = maxf(0.2, _dist * 0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = minf(10.0, _dist * 1.1)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			_drag = (2 if mb.button_index != MOUSE_BUTTON_LEFT or mb.shift_pressed else 1) if mb.pressed else 0
		_update_cam()
		accept_event()
		return
	var mm := ev as InputEventMouseMotion
	if mm != null and _drag != 0:
		if _drag == 1:
			_yaw -= mm.relative.x * 0.4
			_pitch = clampf(_pitch + mm.relative.y * 0.4, -85.0, 85.0)
		else:
			var b := DRBaker.view_basis(_yaw, _pitch)
			_target += (b.x * -mm.relative.x + b.y * mm.relative.y) * _dist * 0.0022
		_update_cam()
		accept_event()


func _process(delta: float) -> void:
	if not _active or not is_visible_in_tree():
		return
	if _dot_mode and _dot_vp != null:
		var sz := Vector2(_dot_vp.size)
		var o := Vector2(sz.x * 0.5, sz.y * 0.85)
		if _dots.origin != o:
			_dots.origin = o
			_ground.queue_redraw()
	if _prev != null and _playing:
		_acc += delta
		if _acc >= 1.0 / STEP_HZ:
			_prev.step_motion(_acc)
			_acc = 0.0
			var ap := _prev.get_animation_player()
			if ap.current_animation != "":
				_time_sl.set_value_no_signal(ap.current_animation_position / maxf(ap.get_animation(ap.current_animation).length, 0.001))
	_draw_marks()
	_update_info()
	_poll -= delta
	if _poll <= 0.0:
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
		return
	var xs := _make_xform_sig()
	if xs != _xform_sig:
		_xform_sig = xs
		_sync_preview()
		_show_xform()


func _make_struct_sig() -> String:
	if _root == null:
		return ""
	var parts := PackedStringArray([_root.body_model, _root.outfit_top, _root.outfit_bottom, str(_root.motions.get_instance_id()) if _root.motions != null else "-"])
	for s in _sockets():
		parts.append("S%s>%s" % [_root.get_path_to(s), s.bone_name])
		var stack: Array[Node] = []
		stack.append_array(s.get_children())
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n.owner != _root:
				continue
			parts.append("%s|%s|%s|%s" % [_root.get_path_to(n), n.scene_file_path, n.get_class(), str((n as Node3D).visible) if n is Node3D else ""])
			stack.append_array(n.get_children())
	return ";".join(parts)


func _make_xform_sig() -> String:
	if _root == null:
		return ""
	var parts := PackedStringArray()
	for s in _sockets():
		var stack: Array[Node] = []
		stack.append_array(s.get_children())
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n.owner != _root:
				continue
			if n is Node3D:
				parts.append(str((n as Node3D).transform))
			if n is DRHandTarget3D:
				parts.append(str((n as DRHandTarget3D).motion_weights) + str((n as DRHandTarget3D).weight))
			stack.append_array(n.get_children())
	return ";".join(parts)


## 손 ↔ 표지 거리
func _update_info() -> void:
	if _prev == null:
		_info.text = ""
		return
	var mo := current_motion()
	var w := _prev.get_ik_weight()
	if _prev.get_support_marker() == null:
		_info.text = "%s · 왼손 표지 없음 — 무기를 고르고 [지금 자세로 왼손 표지] · 오른손 = 소켓 고정" % mo
		return
	var raw := _prev.support_now()                 # 갱신 밖 = 동작 그대로
	var ik_cm := float(_live.get("dist", 0.0)) * 100.0
	_info.text = "%s · 왼손 IK 비중 %.2f · 왼 손바닥 ↔ 표지: IK 뒤 %.1f cm (동작 그대로 %.1f cm) · 손 회전 차 %.0f° · 오른손 = 소켓 고정(0 cm)" % [
		mo, w, ik_cm, float(raw.get("dist", 0.0)) * 100.0, float(_live.get("rot", 0.0))]


## 미리보기에 표시: 왼손 표지(초록) · IK 뒤 왼 손바닥(빨강) · 고른 노드 축(빨 x · 초 y · 파 z) · 소켓(노랑)
func _draw_marks() -> void:
	_imesh.clear_surfaces()
	if _prev == null or _dot_mode:
		return
	var sk := _prev.get_skeleton()
	if sk == null:
		return
	_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var any := false
	if not _live.is_empty():
		var g := sk.global_transform
		_cross(g * (_live["target"] as Vector3), 0.025, Color(0.2, 1.0, 0.3))
		_cross(g * (_live["palm"] as Vector3), 0.015, Color(1.0, 0.25, 0.2))
		any = true
	for s in _prev.get_sockets():
		_cross(s.global_position, 0.02, Color(1.0, 0.9, 0.2))
		any = true
	var pn := _prev_node(_node(_sel)) as Node3D
	if pn != null:
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
	for r in _last_rep:
		by[String((r as Dictionary)["motion"])] = r
	_mt.set_column_title(2, "IK 뒤 cm" + (" (지난 값)" if _rep_stale else ""))
	if _prev != null:
		var names := _prev.motion_names()
		names.sort()
		for n in names:
			var it := _mt.create_item(top)
			it.set_text(0, n)
			if by.has(n):
				var d: Dictionary = by[n]
				it.set_text(1, "%.1f / %.0f" % [float(d["raw_avg"]) * 100.0, float(d["raw_max"]) * 100.0])
				it.set_text(2, "%.1f / %.0f" % [float(d["ik_avg"]) * 100.0, float(d["ik_max"]) * 100.0])
				if _rep_stale:
					for c in [1, 2]:
						it.set_custom_color(c, Color(0.5, 0.52, 0.56))
						it.set_tooltip_text(c, "잰 뒤 무기 · 표지 자리가 바뀜 — [모든 동작 재기]")
				elif float(d["ik_max"]) > 0.05 and float(d["weight"]) > 0.0:
					it.set_custom_color(2, Color(0.95, 0.65, 0.3))
					it.set_tooltip_text(2, "팔이 표지에 안 닿는 시점이 있음(어깨 → 손목 목표 / 팔 길이 최대 %.2f)" % float(d["reach_max"]))
			else:
				it.set_text(1, "-")
				it.set_text(2, "-")
			if mk is DRHandTarget3D:
				it.set_cell_mode(3, TreeItem.CELL_MODE_RANGE)
				it.set_range_config(3, 0.0, 1.0, 0.05)
				it.set_range(3, (mk as DRHandTarget3D).weight_for(n))
				it.set_editable(3, true)
			else:
				it.set_text(3, "표지 없음" if mk == null else "1(고정)")
	_mt_lock = false


func _on_mt_edited() -> void:
	if _mt_lock:
		return
	var it := _mt.get_edited()
	if it == null or _mt.get_edited_column() != 3:
		return
	set_motion_weight(it.get_text(0), it.get_range(3))


## 동작마다 왼 손바닥 ↔ 표지(IK 전 · 뒤) — 미리보기 사본으로 8 시점씩. 돌려주는 값 = DREquipHold.motion_report
func measure_all() -> Array:
	if _prev == null:
		return []
	var keep := current_motion()
	var t := _time_sl.value
	var rep := DREquipHold.motion_report(_prev, _prev.motion_names(), 8)
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
