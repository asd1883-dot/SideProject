@tool
extends Window
class_name DRMainWindow

## A뷰 — 3D 모델을 고정 시점에서 보고, 파트 분리를 확인하고, 베이크한다.
## UI 는 .tscn 없이 코드로 구성한다(에디터 없이도 수정/리뷰가 되도록).

const DEF_OUT := "res://puppet"

var profile: DRPartProfile = DRPartProfile.humanoid()
var baker: DRBaker
var scene_res: PackedScene
var model_path: String = ""

# --- 위젯 ---
var _model_edit: LineEdit
var _preview: TextureRect
var _pv_area: Control
var _zoom_label: Button
var _mode_2d: CheckBox
var _play: CheckBox
var _yaw: SpinBox
var _pitch: SpinBox
var _ortho: SpinBox
var _res: SpinBox
var _ss: SpinBox
var _bands: SpinBox
var _ambient: SpinBox
var _alpha: SpinBox
var _levels: SpinBox
var _bleed: SpinBox
var _fps: SpinBox
var _margin: SpinBox
var _autofit: CheckBox
var _stretch: CheckBox
var _isolate: OptionButton
var _rest_anim: OptionButton
var _rest_time: HSlider
var _rest_time_lbl: Label
var _anim_filter: LineEdit
var _anim_list: ItemList
var _out_edit: LineEdit
var _parts_tree: Tree
var _iso_label: Label
var _z_auto: CheckBox
var _z_list: ItemList
var _status: Label
var _progress: ProgressBar
var _bake_btn: Button
var _preset_label: Label

## 프리셋을 적용하는 동안에는 위젯을 하나씩 바꿀 때마다 프리뷰를 다시 그리지 않는다.
var _loading := false
var _preset_path := ""

var _all_anims: PackedStringArray = PackedStringArray()
var _busy := false
var _dirty := false
## 프리뷰에 보여줄 파트 집합. 비어 있으면 전체 합성.
## 드롭다운 / 파트 트리 / 그리기 순서 목록이 모두 여기에 쓴다.
var _iso_parts: PackedStringArray = PackedStringArray()
## 카메라 자동 맞춤 캐시. 시점 관련 값이 안 바뀌었으면 다시 맞추지 않는다
## (auto_fit 은 렌더를 3번 돌리므로 클릭할 때마다 하면 느리다).
var _fit_sig := ""

# --- 프리뷰 확대/이동 (화면 표시만, 베이크 결과와 무관) ---
## 도트는 정수 배율에서만 깨끗하게 보이므로 단계를 정해 둔다.
const ZOOM_STEPS := [0.25, 0.5, 1.0, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0, 24.0, 32.0]
var _zoom := 0.0                     # 0 = 화면에 맞춤
var _pan := Vector2.ZERO
var _panning := false
var _last_tex_size := Vector2i.ZERO

## 2D 순서 합성용 파트 이미지 캐시. 시점/도트 설정이 그대로면 재렌더하지 않으므로
## 순서만 바꿀 때는 3D 렌더 없이 즉시 다시 겹쳐 그린다.
var _part_imgs: Dictionary = {}
var _part_sig := ""

## 2D 퍼펫 프리뷰. 캐시한 파트 이미지를 Sprite2D 로 붙이고
## 3D 본을 투영한 값으로 움직인다 — 베이크된 씬과 완전히 같은 구조라
## "구우면 이렇게 나온다"를 그대로 보여주고, 3D 재렌더 없이 재생도 된다.
var _puppet_vp: SubViewport
var _puppet_bones: Dictionary = {}     # part -> {bone, stretch, art}
var _puppet_sig := ""
var _play_t := 0.0


func _init() -> void:
	title = "Dot Rigger — 3D → 2D 컷아웃 리그"
	# 에디터는 Control 의 텍스트를 자기 번역 사전으로 자동 번역한다.
	# 그래서 애니메이션 이름 "Idle" 이 목록에 "대기" 로 표시되는 등
	# 데이터가 원본과 다르게 보인다. 이 창의 문구는 전부 하드코딩이므로 끈다.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	size = Vector2i(1180, 780)
	min_size = Vector2i(900, 600)
	exclusive = false
	close_requested.connect(func(): hide())
	_build_ui()


# ---------------------------------------------------------------- UI 구성

func _build_ui() -> void:
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.split_offset = 340
	add_child(split)

	# ===== 왼쪽: 설정 =====
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 6)
	scroll.add_child(left)

	# 프리셋
	left.add_child(_section("0. 프리셋 (설정 한 벌 저장/불러오기)"))
	var prow := HBoxContainer.new()
	var save_btn := Button.new()
	save_btn.text = "저장..."
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.tooltip_text = "지금 설정(각도·그리기 순서·애니 선택 등)을 .tres 파일로 저장합니다."
	save_btn.pressed.connect(_on_save_preset)
	prow.add_child(save_btn)
	var load_p := Button.new()
	load_p.text = "불러오기..."
	load_p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_p.pressed.connect(_on_load_preset)
	prow.add_child(load_p)
	left.add_child(prow)
	_preset_label = Label.new()
	_preset_label.text = "(저장된 프리셋 없음)"
	_preset_label.clip_text = true
	_preset_label.custom_minimum_size = Vector2(80, 20)
	_preset_label.add_theme_font_size_override("font_size", 11)
	left.add_child(_preset_label)

	# 모델
	left.add_child(_section("1. 모델"))
	var mrow := HBoxContainer.new()
	_model_edit = LineEdit.new()
	_model_edit.placeholder_text = "res://models/....glb"
	_model_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(_model_edit)
	var browse := Button.new()
	browse.text = "..."
	browse.pressed.connect(_on_browse)
	mrow.add_child(browse)
	left.add_child(mrow)
	var load_btn := Button.new()
	load_btn.text = "모델 불러오기 / 파트 분리"
	load_btn.pressed.connect(_on_load)
	left.add_child(load_btn)

	# 시점
	left.add_child(_section("2. 시점 (이 게임의 유일한 각도)"))
	_yaw = _spin(left, "Yaw (좌우 회전)", -180, 180, 1, 90)
	_pitch = _spin(left, "Pitch (상하 회전)", -89, 89, 1, 0)
	_ortho = _spin(left, "Ortho 크기 (0=자동)", 0, 100, 0.01, 0)
	var vrow := HBoxContainer.new()
	_autofit = CheckBox.new()
	_autofit.text = "자동 맞춤"
	_autofit.button_pressed = true
	vrow.add_child(_autofit)
	left.add_child(vrow)
	_margin = _spin(left, "여백 (px)", 0, 64, 1, 6)
	var preset := HBoxContainer.new()
	for d in [["정측면", 90.0, 0.0], ["3/4 앞", 45.0, 0.0], ["정면", 0.0, 0.0],
			["아이소", 45.0, 30.0], ["탑다운", 0.0, 60.0]]:
		var b := Button.new()
		b.text = String(d[0])
		b.pressed.connect(func():
			_yaw.value = float(d[1])
			_pitch.value = float(d[2])
			_refresh_preview())
		preset.add_child(b)
	left.add_child(preset)

	# 도트화
	left.add_child(_section("3. 도트화"))
	_res = _spin(left, "해상도 (px, 정사각)", 32, 1024, 8, 192)
	_ss = _spin(left, "슈퍼샘플 (1=직접)", 1, 4, 1, 1)
	_bands = _spin(left, "명암 단계", 2, 8, 1, 3)
	_ambient = _spin(left, "앰비언트", 0, 1, 0.05, 0.45)
	_alpha = _spin(left, "알파 임계값", 0, 1, 0.05, 0.5)
	_levels = _spin(left, "색 양자화 (0=끔)", 0, 32, 1, 0)

	# 파트
	left.add_child(_section("4. 파트 분리"))
	_bleed = _spin(left, "관절 겹침 링 수", 0, 4, 1, 1)
	var irow := HBoxContainer.new()
	var ilbl := Label.new()
	ilbl.text = "미리보기"
	ilbl.custom_minimum_size = Vector2(120, 0)
	irow.add_child(ilbl)
	_isolate = OptionButton.new()
	_isolate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_isolate.item_selected.connect(func(i):
		if i <= 0:
			_set_isolation(PackedStringArray(), true)
		else:
			_set_isolation(PackedStringArray([_isolate.get_item_text(i)]), true))
	irow.add_child(_isolate)
	left.add_child(irow)

	# 레스트 포즈
	left.add_child(_section("5. 레스트 포즈 (파트 스프라이트를 뽑는 자세)"))
	var hint := Label.new()
	hint.text = "T포즈는 측면에서 팔이 뭉개집니다. Idle 계열 권장."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	left.add_child(hint)
	_rest_anim = OptionButton.new()
	_rest_anim.item_selected.connect(func(_i): _refresh_preview())
	left.add_child(_rest_anim)
	_rest_time = HSlider.new()
	_rest_time.min_value = 0.0
	_rest_time.max_value = 1.0
	_rest_time.step = 0.01
	_rest_time.value_changed.connect(func(_v): _refresh_preview())
	left.add_child(_rest_time)
	_rest_time_lbl = Label.new()
	_rest_time_lbl.text = "t = 0%"
	left.add_child(_rest_time_lbl)

	# 애니메이션
	left.add_child(_section("6. 내보낼 애니메이션"))
	_anim_filter = LineEdit.new()
	_anim_filter.placeholder_text = "검색 (예: idle, jog, throw)"
	_anim_filter.text_changed.connect(func(_t): _fill_anim_list())
	left.add_child(_anim_filter)
	_anim_list = ItemList.new()
	_anim_list.select_mode = ItemList.SELECT_MULTI
	_anim_list.custom_minimum_size = Vector2(0, 160)
	left.add_child(_anim_list)
	_fps = _spin(left, "샘플 FPS", 4, 60, 1, 12)
	_stretch = CheckBox.new()
	_stretch.text = "단축 보정 (팔 권장, 도트 결은 약간 흐트러짐)"
	_stretch.button_pressed = true
	left.add_child(_stretch)

	# 출력
	left.add_child(_section("7. 출력"))
	_out_edit = LineEdit.new()
	_out_edit.text = DEF_OUT
	left.add_child(_out_edit)
	_bake_btn = Button.new()
	_bake_btn.text = "베이크"
	_bake_btn.custom_minimum_size = Vector2(0, 36)
	_bake_btn.pressed.connect(_on_bake)
	left.add_child(_bake_btn)
	_progress = ProgressBar.new()
	_progress.value = 0
	left.add_child(_progress)

	# ===== 오른쪽 =====
	# 가운데(프리뷰 + 파트 트리) | 맨 오른쪽(그리기 순서, 세로 전체)
	# 그리기 순서를 아래에 두면 15개가 다 안 보여 계속 스크롤해야 해서
	# 프리뷰 옆 빈 공간을 세로로 쓰는 편이 낫다.
	var rsplit := HSplitContainer.new()
	rsplit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rsplit.split_offset = 520
	split.add_child(rsplit)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rsplit.add_child(right)

	var pv_panel := PanelContainer.new()
	pv_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(pv_panel)
	# 컨테이너가 아니라 맨 Control 이어야 자식 위치를 직접 잡을 수 있다.
	# (확대/이동을 직접 계산해서 그린다)
	_pv_area = Control.new()
	_pv_area.clip_contents = true
	_pv_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_pv_area.gui_input.connect(_on_preview_input)
	_pv_area.resized.connect(_layout_preview)
	pv_panel.add_child(_pv_area)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_SCALE
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pv_area.add_child(_preview)

	_status = Label.new()
	_status.text = "모델을 불러오세요."
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_status)

	# 프리뷰 도구 줄. 한 줄에 다 넣으면 가로 최소 너비가 커져서
	# 오른쪽 그리기 순서 열이 창 밖으로 밀린다. 두 줄로 나눈다.
	var toolbar := HBoxContainer.new()
	right.add_child(toolbar)

	var zout := Button.new()
	zout.text = "−"
	zout.tooltip_text = "축소 (프리뷰 위에서 휠 아래로)"
	zout.pressed.connect(func(): _step_zoom(-1, _pv_area.size * 0.5))
	toolbar.add_child(zout)
	_zoom_label = Button.new()
	_zoom_label.text = "맞춤"
	_zoom_label.tooltip_text = "눌러서 화면에 맞추기 (휠=확대/축소, 가운데·우클릭 드래그=이동)"
	_zoom_label.custom_minimum_size = Vector2(64, 0)
	_zoom_label.pressed.connect(_fit_preview)
	toolbar.add_child(_zoom_label)
	var zin := Button.new()
	zin.text = "+"
	zin.tooltip_text = "확대 (프리뷰 위에서 휠 위로)"
	zin.pressed.connect(func(): _step_zoom(1, _pv_area.size * 0.5))
	toolbar.add_child(zin)

	# 3D 렌더는 GPU 깊이 버퍼가 가림을 정하므로 오른쪽에서 지정한 그리기 순서를
	# 무시한다. 지정한 순서가 실제로 어떻게 보이는지는 이 모드로 확인한다.
	_mode_2d = CheckBox.new()
	_mode_2d.text = "2D 순서"
	_mode_2d.tooltip_text = "켜면 오른쪽 그리기 순서대로 파트를 겹쳐 그립니다(베이크 결과와 동일).\n" \
		+ "끄면 3D 렌더라 가림이 항상 정확하지만, 지정한 순서는 반영되지 않습니다."
	_mode_2d.toggled.connect(func(on):
		if baker != null:
			baker.set_playback(false)
		_refresh_preview())
	toolbar.add_child(_mode_2d)

	# 프리뷰에서 애니메이션을 돌려 보는 기능. 베이크에는 영향이 없다
	# (베이크는 항상 프레임마다 자세를 세워 놓고 찍는다).
	_play = CheckBox.new()
	_play.text = "▶ 재생"
	_play.tooltip_text = "선택한 레스트 포즈 애니메이션을 프리뷰에서 돌립니다.\n" \
		+ "2D 순서 모드에서도 돌아가며, 그때는 지정한 그리기 순서가 적용된 채로 재생됩니다\n" \
		+ "(= 베이크 결과를 그대로 미리 보는 것). 베이크 자체에는 영향이 없습니다."
	_play.toggled.connect(func(on):
		_play_t = 0.0
		_refresh_preview())
	toolbar.add_child(_play)
	_iso_label = Label.new()
	_iso_label.text = "현재: 전체 합성"
	_iso_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 줄바꿈 없는 Label 은 텍스트 전체 너비를 최소 너비로 요구해서
	# 가운데 열을 밀어내고 오른쪽 그리기 순서 열을 창 밖으로 쫓아낸다.
	# clip_text 로 최소 너비를 없애되, 높이는 직접 잡아 줘야 0 으로 찌부러지지 않는다.
	_iso_label.clip_text = true
	_iso_label.custom_minimum_size = Vector2(80, 22)
	_iso_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var navbar := HBoxContainer.new()
	var back := Button.new()
	back.text = "◀ 전체 보기"
	back.tooltip_text = "파트 격리를 풀고 전체 합성으로 돌아갑니다."
	back.pressed.connect(_show_composite)
	navbar.add_child(back)
	navbar.add_child(_iso_label)
	right.add_child(navbar)

	_parts_tree = Tree.new()
	_parts_tree.columns = 4
	_parts_tree.set_column_title(0, "파트")
	_parts_tree.set_column_title(1, "루트 본")
	_parts_tree.set_column_title(2, "본 수")
	_parts_tree.set_column_title(3, "삼각형")
	_parts_tree.column_titles_visible = true
	_parts_tree.custom_minimum_size = Vector2(0, 190)
	_parts_tree.item_selected.connect(_on_tree_select)
	right.add_child(_parts_tree)

	# ---- 그리기 순서 (B뷰 역할) — 세로 전체를 쓰는 우측 컬럼 ----
	var zbox := VBoxContainer.new()
	zbox.custom_minimum_size = Vector2(210, 0)
	rsplit.add_child(zbox)
	var zl := Label.new()
	zl.text = "그리기 순서  (위 = 뒤쪽)"
	zl.add_theme_font_size_override("font_size", 14)
	zbox.add_child(zl)
	_z_auto = CheckBox.new()
	_z_auto.text = "자동 (3D 깊이 기준)"
	_z_auto.button_pressed = true
	_z_auto.toggled.connect(func(on):
		_z_list.tooltip_text = "자동 모드에서는 편집할 수 없습니다." if on else ""
		if on:
			_fill_z_list())
	zbox.add_child(_z_auto)
	_z_list = ItemList.new()
	_z_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Shift = 범위 선택, Ctrl = 하나씩 추가. 여러 개를 한 번에 올리고 내릴 수 있다.
	_z_list.select_mode = ItemList.SELECT_MULTI
	_z_list.multi_selected.connect(func(_i, _on): _on_z_selection_changed())
	zbox.add_child(_z_list)
	var zbtn := HBoxContainer.new()
	for spec in [["▲ 뒤로", -1], ["▼ 앞으로", 1]]:
		var b := Button.new()
		b.text = String(spec[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_move_z.bind(int(spec[1])))
		zbtn.add_child(b)
	zbox.add_child(zbtn)
	var zhint := Label.new()
	zhint.text = "Shift = 범위, Ctrl = 개별 선택\n고른 파트만 프리뷰에 뜹니다."
	zhint.tooltip_text = "여러 개를 고르면 그것들만 3D 로 렌더되어 서로의 가림을 " \
		+ "바로 확인할 수 있습니다.\n▲▼ 는 고른 것 전부를 한 칸씩 옮깁니다.\n" \
		+ "순서를 바꾸면 자동이 꺼지고 그 순서가 모든 프레임에 고정됩니다."
	zhint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	zhint.add_theme_font_size_override("font_size", 11)
	zbox.add_child(zhint)


func _section(t: String) -> Control:
	var v := VBoxContainer.new()
	var sep := HSeparator.new()
	v.add_child(sep)
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 14)
	v.add_child(l)
	return v


func _spin(parent: Control, label: String, lo: float, hi: float, step: float, val: float) -> SpinBox:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(150, 0)
	l.clip_text = true
	row.add_child(l)
	var sb := SpinBox.new()
	sb.min_value = lo
	sb.max_value = hi
	sb.step = step
	sb.value = val
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sb.value_changed.connect(func(_v): _refresh_preview())
	row.add_child(sb)
	parent.add_child(row)
	return sb


# ---------------------------------------------------------------- 동작

const MODEL_FILTER := "*.glb,*.gltf,*.fbx,*.blend,*.tscn,*.scn ; 3D 모델"
const PRESET_FILTER := "*.tres ; Dot Rigger 프리셋"

## 파일 대화상자를 띄운다.
## EditorFileDialog 는 에디터 밖에서 null 을 돌려주므로 일반 FileDialog 로 떨어진다.
## 에디터 본체(get_base_control)에 붙이면 메인 에디터 창에 떠서 이 툴 창이 뒤로
## 밀리므로, 반드시 이 창의 자식으로 붙인다.
func _file_dialog(save: bool, filter: String, title: String,
		default_name: String, on_selected: Callable) -> void:
	var efd := EditorFileDialog.new()
	var dlg: Window = efd
	if efd != null:
		efd.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE if save \
			else EditorFileDialog.FILE_MODE_OPEN_FILE
		efd.access = EditorFileDialog.ACCESS_RESOURCES
		efd.filters = PackedStringArray([filter])
		if default_name != "":
			efd.current_file = default_name
	else:
		var f := FileDialog.new()
		f.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save \
			else FileDialog.FILE_MODE_OPEN_FILE
		f.access = FileDialog.ACCESS_RESOURCES
		f.filters = PackedStringArray([filter])
		f.use_native_dialog = false
		if default_name != "":
			f.current_file = default_name
		dlg = f
	dlg.title = title
	dlg.connect("file_selected", func(p):
		var picked := String(p)
		dlg.queue_free()
		on_selected.call(picked))
	dlg.connect("canceled", func(): dlg.queue_free())
	add_child(dlg)
	if efd != null:
		efd.popup_file_dialog()
	else:
		dlg.popup_centered_ratio(0.6)


func _on_browse() -> void:
	_file_dialog(false, MODEL_FILTER, "모델 선택 — Dot Rigger", "", func(p):
		_model_edit.text = p
		_on_load())


# ---------------------------------------------------------------- 프리셋

func _collect_preset() -> DRPreset:
	var p := DRPreset.new()
	p.model_path = _model_edit.text.strip_edges()
	p.yaw = _yaw.value
	p.pitch = _pitch.value
	p.ortho = _ortho.value
	p.auto_fit = _autofit.button_pressed
	p.margin = int(_margin.value)
	p.resolution = int(_res.value)
	p.supersample = int(_ss.value)
	p.light_bands = int(_bands.value)
	p.ambient = _ambient.value
	p.alpha_threshold = _alpha.value
	p.color_levels = int(_levels.value)
	p.bleed_rings = int(_bleed.value)
	p.z_auto = _z_auto.button_pressed
	p.z_order = _order_from_list()
	if _rest_anim.selected > 0:
		p.rest_anim = _rest_anim.get_item_text(_rest_anim.selected)
	p.rest_time = _rest_time.value
	var picked := PackedStringArray()
	for i in _anim_list.item_count:
		if _anim_list.is_selected(i):
			picked.append(_anim_list.get_item_text(i))
	p.animations = picked
	p.fps = int(_fps.value)
	p.apply_stretch = _stretch.button_pressed
	p.out_dir = _out_edit.text.strip_edges()
	return p


func _apply_preset(p: DRPreset) -> void:
	_loading = true
	# 모델이 다르면 먼저 새로 불러온다(파트 목록/애니 목록이 여기서 채워진다)
	if p.model_path != "" and p.model_path != _model_edit.text.strip_edges():
		_model_edit.text = p.model_path
		_on_load()
	elif baker == null and p.model_path != "":
		_model_edit.text = p.model_path
		_on_load()

	_yaw.value = p.yaw
	_pitch.value = p.pitch
	_ortho.value = p.ortho
	_autofit.button_pressed = p.auto_fit
	_margin.value = p.margin
	_res.value = p.resolution
	_ss.value = p.supersample
	_bands.value = p.light_bands
	_ambient.value = p.ambient
	_alpha.value = p.alpha_threshold
	_levels.value = p.color_levels
	_bleed.value = p.bleed_rings
	_fps.value = p.fps
	_stretch.button_pressed = p.apply_stretch
	if p.out_dir != "":
		_out_edit.text = p.out_dir

	# 레스트 포즈는 인덱스가 아니라 이름으로 찾는다(모델이 바뀌면 인덱스가 달라짐)
	_rest_anim.select(0)
	for i in _rest_anim.item_count:
		if _rest_anim.get_item_text(i) == p.rest_anim:
			_rest_anim.select(i)
			break
	_rest_time.value = p.rest_time

	# 내보낼 애니메이션도 이름으로 복원. 필터를 지워야 전부 보인다.
	_anim_filter.text = ""
	_fill_anim_list()
	var want := {}
	for a in p.animations:
		want[a] = true
	for i in _anim_list.item_count:
		if want.has(_anim_list.get_item_text(i)):
			_anim_list.select(i, false)

	# 그리기 순서
	_z_auto.set_pressed_no_signal(p.z_auto)
	if not p.z_auto and p.z_order.size() > 0 and baker != null:
		var known := {}
		for n in baker.rig.order:
			known[n] = true
		_z_list.clear()
		var seen := {}
		for n in p.z_order:
			if known.has(n) and not seen.has(n):
				_z_list.add_item(String(n))
				seen[n] = true
		for n in baker.rig.order:          # 프리셋에 없던 파트는 뒤에 붙인다
			if not seen.has(n):
				_z_list.add_item(String(n))

	_loading = false
	_fit_sig = ""
	_part_sig = ""
	_iso_parts = PackedStringArray()
	_refresh_preview()


func _on_save_preset() -> void:
	var default_name := "dotrig_preset.tres"
	if _preset_path != "":
		default_name = _preset_path.get_file()
	elif _model_edit.text.strip_edges() != "":
		default_name = _model_edit.text.get_file().get_basename() + "_preset.tres"
	_file_dialog(true, PRESET_FILTER, "프리셋 저장 — Dot Rigger", default_name, func(p):
		var path: String = String(p)
		if path.get_extension().to_lower() != "tres":
			path += ".tres"
		var err := ResourceSaver.save(_collect_preset(), path)
		if err == OK:
			_preset_path = path
			_preset_label.text = "프리셋: %s" % path.get_file()
			_status.text = "프리셋 저장 완료 — %s" % path
			if Engine.is_editor_hint():
				EditorInterface.get_resource_filesystem().scan()
		else:
			_status.text = "프리셋 저장 실패 (%d) — %s" % [err, path])


func _on_load_preset() -> void:
	_file_dialog(false, PRESET_FILTER, "프리셋 불러오기 — Dot Rigger", "", func(p):
		var path: String = String(p)
		var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res is DRPreset:
			_preset_path = path
			_preset_label.text = "프리셋: %s" % path.get_file()
			_apply_preset(res as DRPreset)
			_status.text = "프리셋 적용 — %s" % path
		else:
			_status.text = "Dot Rigger 프리셋이 아닙니다: %s" % path)


func _current_opts() -> DRBaker.Options:
	var o := DRBaker.Options.new()
	var r := int(_res.value)
	o.view_size = Vector2i(r, r)
	o.yaw = _yaw.value
	o.pitch = _pitch.value
	o.ortho_size = _ortho.value
	o.supersample = int(_ss.value)
	o.bleed_rings = int(_bleed.value)
	o.light_bands = int(_bands.value)
	o.ambient = _ambient.value
	o.alpha_threshold = _alpha.value
	o.color_levels = int(_levels.value)
	if _rest_anim.selected >= 0:
		o.rest_anim = _rest_anim.get_item_text(_rest_anim.selected)
	return o


func _on_load() -> void:
	if _busy:
		return
	model_path = _model_edit.text.strip_edges()
	if model_path == "":
		_status.text = "모델 경로가 비어 있습니다."
		return
	scene_res = load(model_path) as PackedScene
	if scene_res == null:
		_status.text = "모델을 로드하지 못했습니다: %s" % model_path
		return
	_teardown()
	baker = DRBaker.new()
	if not baker.setup(self, scene_res, profile, _current_opts()):
		_status.text = "파트 분리 실패. 출력 로그를 확인하세요."
		baker = null
		return

	# 애니메이션 목록
	_all_anims = PackedStringArray()
	if baker.anim_player != null:
		for a in baker.anim_player.get_animation_list():
			_all_anims.append(String(a))
	_rest_anim.clear()
	_rest_anim.add_item("(바인드 포즈)")
	for a in _all_anims:
		_rest_anim.add_item(a)
	# Idle 계열을 기본 선택
	for i in _rest_anim.item_count:
		if _rest_anim.get_item_text(i).to_lower().begins_with("idle"):
			_rest_anim.select(i)
			break
	_fill_anim_list()

	# 파트 목록
	_isolate.clear()
	_isolate.add_item("전체 합성")
	for p in baker.rig.order:
		_isolate.add_item(p)
	_fill_parts_tree()
	_z_auto.button_pressed = true
	_z_list.clear()
	for p in baker.rig.order:
		_z_list.add_item(String(p))
	_iso_parts = PackedStringArray()
	_fit_sig = ""

	var un := baker.split.unmapped_bones.size()
	_status.text = "파트 %d개 / 본 %d개 / 애니 %d개%s" % [
		baker.rig.order.size(), baker.skeleton.get_bone_count(), _all_anims.size(),
		("  ⚠ 미매핑 본 %d개" % un) if un > 0 else ""]
	_refresh_preview()


# ---------------------------------------------------------------- 프리뷰 확대/이동
#
# 여기서 하는 확대는 "찍힌 결과를 크게 보는 것"일 뿐이고 베이크에는 영향이 없다.
# 실제로 카메라를 당기려면 시점 항목의 Ortho 크기를 줄여야 한다.

func _on_preview_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_step_zoom(1, mb.position)
					_pv_area.accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_step_zoom(-1, mb.position)
					_pv_area.accept_event()
			MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
				_panning = mb.pressed
				_pv_area.accept_event()
	elif ev is InputEventMouseMotion and _panning:
		_pan += (ev as InputEventMouseMotion).relative
		_layout_preview()


## 현재 실제 배율. _zoom 이 0 이면 화면에 맞춘 배율을 계산해서 돌려준다.
func _current_zoom() -> float:
	if _zoom > 0.0:
		return _zoom
	if _preview.texture == null:
		return 1.0
	var ts := Vector2(_preview.texture.get_size())
	var area := _pv_area.size
	if ts.x <= 0.0 or ts.y <= 0.0 or area.x <= 0.0 or area.y <= 0.0:
		return 1.0
	return maxf(minf(area.x / ts.x, area.y / ts.y), 0.05)


## 커서 아래 지점이 제자리에 있도록 확대/축소한다.
func _step_zoom(dir: int, anchor: Vector2) -> void:
	if _preview.texture == null:
		return
	var old := _current_zoom()
	# 지금 배율에서 가장 가까운 단계를 찾아 한 칸 이동
	var idx := 0
	var best := INF
	for i in ZOOM_STEPS.size():
		var d: float = absf(float(ZOOM_STEPS[i]) - old)
		if d < best:
			best = d
			idx = i
	# 맞춤 상태에서 확대하면 현재 배율보다 확실히 큰 단계로 가야 자연스럽다
	if _zoom <= 0.0 and dir > 0 and float(ZOOM_STEPS[idx]) <= old:
		idx += 1
	elif _zoom <= 0.0 and dir < 0 and float(ZOOM_STEPS[idx]) >= old:
		idx -= 1
	else:
		idx += dir
	idx = clampi(idx, 0, ZOOM_STEPS.size() - 1)
	var new_z := float(ZOOM_STEPS[idx])

	# 앵커 고정: 커서 위치의 이미지 좌표가 그대로 유지되도록 pan 을 다시 잡는다
	var img_pt := (anchor - _preview.position) / old
	var ts := Vector2(_preview.texture.get_size())
	var base := (_pv_area.size - ts * new_z) * 0.5
	_pan = anchor - img_pt * new_z - base
	_zoom = new_z
	_layout_preview()


func _fit_preview() -> void:
	_zoom = 0.0
	_pan = Vector2.ZERO
	_layout_preview()


func _layout_preview() -> void:
	if _preview == null or _pv_area == null:
		return
	if _preview.texture == null:
		_zoom_label.text = "맞춤"
		return
	var ts := Vector2(_preview.texture.get_size())
	var z := _current_zoom()
	_preview.size = ts * z
	var base := (_pv_area.size - ts * z) * 0.5
	if _zoom <= 0.0:
		_pan = Vector2.ZERO
	# 정수 좌표로 스냅해야 도트가 반 픽셀에 걸려 흐려지지 않는다
	_preview.position = (base + _pan).round()
	_zoom_label.text = "맞춤" if _zoom <= 0.0 else "%d%%" % int(round(z * 100.0))


# ---------------------------------------------------------------- 2D 순서 합성
#
# 3D 렌더는 GPU 깊이 버퍼가 픽셀마다 가림을 정하므로 "그리기 순서" 설정이 아예
# 반영되지 않는다. 베이크된 2D 씬은 반대로 파트 한 장씩 순서대로 겹쳐 그린다.
# 지정한 순서를 확인하려면 여기서 같은 방식으로 다시 그려 봐야 한다.

## 파트 이미지에 영향을 주는 모든 값. 이게 그대로면 캐시를 재사용한다.
func _render_sig() -> String:
	return "%s|%d|%d|%.2f|%.2f|%d" % [
		_view_sig(), int(_bleed.value), int(_bands.value),
		_ambient.value, _alpha.value, int(_levels.value)]


func _ensure_part_cache() -> void:
	var sig := _render_sig()
	if sig == _part_sig and not _part_imgs.is_empty():
		return
	_part_imgs.clear()
	for p in baker.rig.order:
		_part_imgs[p] = await baker.render_part(String(p))
	_part_sig = sig


## 목록에 보이는 순서 그대로(위 = 뒤쪽) 돌려준다.
func _order_from_list() -> PackedStringArray:
	var out := PackedStringArray()
	for i in _z_list.item_count:
		out.append(_z_list.get_item_text(i))
	return out


## 캐시한 파트 이미지로 2D 퍼펫을 만든다. 베이크된 씬과 같은 노드 구조.
## 파트 이미지가 캔버스 전체 크기라 레스트에서는 그냥 (0,0) 에 놓으면 맞고,
## 움직일 때만 파트별 피벗 기준으로 회전/이동시키면 된다.
func _build_puppet(sig: String) -> void:
	if _puppet_vp == null:
		_puppet_vp = SubViewport.new()
		_puppet_vp.transparent_bg = true
		_puppet_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_puppet_vp.canvas_item_default_texture_filter = \
			Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		add_child(_puppet_vp)
	_puppet_vp.size = baker.opts.view_size
	for c in _puppet_vp.get_children():
		c.queue_free()
	_puppet_bones.clear()

	var root2d := Node2D.new()
	root2d.name = "Puppet"
	_puppet_vp.add_child(root2d)

	for pname in baker.rig.order:
		if not _part_imgs.has(pname):
			continue
		var p: DRRigModel.Part = baker.rig.parts[pname]
		var bone := Node2D.new()
		bone.name = String(pname)
		var parent_node: Node2D = root2d
		var parent_head := Vector2.ZERO
		if p.parent != "" and _puppet_bones.has(p.parent):
			parent_node = _puppet_bones[p.parent]["bone"]
			parent_head = (baker.rig.parts[p.parent] as DRRigModel.Part).rest_head2d
		parent_node.add_child(bone)
		bone.position = p.rest_head2d - parent_head

		var stretch := Node2D.new()
		stretch.name = "stretch"
		stretch.rotation = p.rest_angle
		bone.add_child(stretch)

		var art := Sprite2D.new()
		art.name = "art"
		art.centered = false
		art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		art.z_as_relative = false
		art.rotation = -p.rest_angle
		art.position = (-p.rest_head2d).rotated(-p.rest_angle)
		art.texture = ImageTexture.create_from_image(_part_imgs[pname])
		stretch.add_child(art)

		_puppet_bones[pname] = {"bone": bone, "stretch": stretch, "art": art}
	_puppet_sig = sig
	_pose_puppet(true)


## 현재 3D 자세를 투영해 2D 퍼펫에 적용한다. rest_only 면 레스트 상태로 되돌린다.
func _pose_puppet(rest_only: bool = false) -> void:
	if _puppet_bones.is_empty():
		return
	var zpos := {}
	var ord := _order_from_list()
	for i in ord.size():
		zpos[ord[i]] = i
	var want := {}
	for n in _iso_parts:
		want[n] = true

	var loc := {}
	if not rest_only:
		loc = baker.rig.project_local(baker.skeleton, baker.camera)

	for pname in _puppet_bones.keys():
		var nodes: Dictionary = _puppet_bones[pname]
		var bone: Node2D = nodes["bone"]
		var stretch: Node2D = nodes["stretch"]
		var art: Sprite2D = nodes["art"]
		art.visible = want.is_empty() or want.has(pname)
		# 그리기 순서는 목록이 정한다(3D 깊이가 아니라) — 이게 이 모드의 존재 이유
		art.z_index = int(zpos.get(pname, 0))
		if rest_only or not loc.has(pname):
			var p: DRRigModel.Part = baker.rig.parts[pname]
			var parent_head := Vector2.ZERO
			if p.parent != "" and baker.rig.parts.has(p.parent):
				parent_head = (baker.rig.parts[p.parent] as DRRigModel.Part).rest_head2d
			bone.position = p.rest_head2d - parent_head
			bone.rotation = 0.0
			stretch.scale = Vector2.ONE
			continue
		var e: Dictionary = loc[pname]
		bone.position = e["p"]
		bone.rotation = float(e["r"])
		if _stretch.button_pressed:
			stretch.scale = Vector2(clampf(float(e["s"]), 1.0 / 1.6, 1.6), 1.0)
		else:
			stretch.scale = Vector2.ONE


## only 가 비어 있지 않으면 그 파트들만 그린다.
func _composite_by_order(only: PackedStringArray) -> Image:
	var vs := baker.opts.view_size
	var out := Image.create(vs.x, vs.y, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var want := {}
	for n in only:
		want[n] = true
	for n in _order_from_list():          # 뒤 -> 앞
		if not want.is_empty() and not want.has(n):
			continue
		var im: Image = _part_imgs.get(n)
		if im == null:
			continue
		if im.get_size() != Vector2i(vs.x, vs.y):
			continue
		out.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i.ZERO)
	return out


## 시점에 영향을 주는 값들의 지문. 이게 그대로면 카메라를 다시 맞추지 않는다.
func _view_sig() -> String:
	return "%.3f|%.3f|%.4f|%d|%d|%d|%d|%d|%.4f" % [
		_yaw.value, _pitch.value, _ortho.value,
		int(_res.value), int(_ss.value), int(_margin.value),
		1 if _autofit.button_pressed else 0,
		_rest_anim.selected, _rest_time.value]


## 파트 격리를 풀고 전체 합성으로 돌아간다.
func _show_composite() -> void:
	_parts_tree.deselect_all()
	var r := _parts_tree.get_root()
	if r != null:
		r.select(0)
	# _set_isolation 은 대상이 이미 같으면 조기 반환하므로,
	# "무조건 전체로" 를 보장하려면 위젯 상태는 여기서 직접 맞춘다.
	_isolate.select(0)
	if _z_list != null:
		_z_list.deselect_all()
	_set_isolation(PackedStringArray(), false)


func _fill_parts_tree() -> void:
	_parts_tree.clear()
	if baker == null:
		return
	var root := _parts_tree.create_item()
	# 루트 행 자체가 "전체로 돌아가기" 역할을 한다.
	# (파트를 눌러 들어간 뒤 되돌아올 곳이 필요하다)
	root.set_text(0, "＊ 전체 합성")
	root.set_metadata(0, "")
	root.set_selectable(0, true)
	var items := {}
	for pname in baker.rig.order:
		var p: DRRigModel.Part = baker.rig.parts[pname]
		var parent_item: TreeItem = items.get(p.parent, root)
		var it := _parts_tree.create_item(parent_item)
		it.set_text(0, pname)
		it.set_text(1, baker.skeleton.get_bone_name(p.root_bone))
		it.set_text(2, str(p.bones.size()))
		it.set_text(3, str(int(baker.split.tri_counts.get(pname, 0))))
		it.set_metadata(0, pname)
		items[pname] = it
	_parts_tree.get_root().set_collapsed(false)


func _on_tree_select() -> void:
	var it := _parts_tree.get_selected()
	if it == null:
		return
	var pname := String(it.get_metadata(0))
	if pname == "":            # 루트 행 = 전체로 복귀
		_set_isolation(PackedStringArray(), true)
	else:
		_set_isolation(PackedStringArray([pname]), true)


## 그리기 순서 목록을 현재 상태로 채운다. 자동 모드면 3D 깊이 기준으로 정렬한다.
func _fill_z_list() -> void:
	if baker == null:
		return
	if not _z_auto.button_pressed:
		return          # 수동 모드에서는 사용자가 만든 순서를 건드리지 않는다
	var names: Array = []
	for p in baker.rig.order:
		names.append(p)
	names.sort_custom(func(a, b):
		return (baker.rig.parts[a] as DRRigModel.Part).rest_depth \
			> (baker.rig.parts[b] as DRRigModel.Part).rest_depth)

	# 내용이 그대로면 손대지 않는다.
	# clear() 하는 순간 다중 선택이 통째로 날아가므로, 각도가 바뀌지 않은
	# 단순 프리뷰 갱신에서는 목록을 건드리면 안 된다.
	if _z_list.item_count == names.size():
		var same := true
		for i in names.size():
			if _z_list.get_item_text(i) != String(names[i]):
				same = false
				break
		if same:
			return

	# 순서가 실제로 바뀐 경우: 선택을 인덱스가 아니라 "이름"으로 복원한다
	var keep := {}
	for i in _z_list.get_selected_items():
		keep[_z_list.get_item_text(i)] = true
	_z_list.clear()
	for n in names:
		_z_list.add_item(String(n))
	for i in _z_list.item_count:
		if keep.has(_z_list.get_item_text(i)):
			_z_list.select(i, false)


## 목록에서 고른 파트들만 프리뷰에 띄운다.
## Shift 로 두세 개를 잡으면 그것들끼리의 가림을 3D 로 바로 확인할 수 있어서
## 어느 쪽이 앞이어야 하는지 판단하기 쉽다.
func _on_z_selection_changed() -> void:
	var picked := PackedStringArray()
	for i in _z_list.get_selected_items():
		picked.append(_z_list.get_item_text(i))
	_set_isolation(picked)


## 프리뷰 대상 집합을 바꾸고 갱신한다. 비어 있으면 전체 합성.
func _set_isolation(names: PackedStringArray, sync_list: bool = false) -> void:
	if _iso_parts == names:
		return
	_iso_parts = names
	# 드롭다운은 단일 선택만 표현할 수 있으므로 그때만 맞춰 준다
	if names.size() == 1:
		for k in _isolate.item_count:
			if _isolate.get_item_text(k) == names[0]:
				_isolate.select(k)
				break
	elif names.is_empty():
		_isolate.select(0)
	if sync_list and _z_list != null:
		var want := {}
		for n in names:
			want[n] = true
		_z_list.deselect_all()
		for i in _z_list.item_count:
			if want.has(_z_list.get_item_text(i)):
				_z_list.select(i, false)
	_refresh_preview()


## 선택한 항목들을 한 칸 위/아래로 옮긴다. 여러 개를 동시에 옮길 수 있고,
## 떨어져 있어도 각각 한 칸씩 이동한다.
func _move_z(dir: int) -> void:
	var sel := _z_list.get_selected_items()
	if sel.is_empty():
		return
	var idx: Array = Array(sel)
	idx.sort()
	if dir > 0:
		idx.reverse()          # 아래로 밀 때는 끝에서부터 처리해야 서로 안 덮어씀
	# 하나라도 범위를 벗어나면 통째로 중단(부분 이동은 순서가 뒤엉킨다)
	for i in idx:
		if i + dir < 0 or i + dir >= _z_list.item_count:
			return
	_z_auto.button_pressed = false          # 손을 대면 자동 해제
	# 순서를 손대는 순간부터는 그 순서가 보여야 의미가 있다.
	# 3D 프리뷰는 지정한 순서를 무시하므로 2D 합성으로 전환한다.
	if _mode_2d != null and not _mode_2d.button_pressed:
		_mode_2d.set_pressed_no_signal(true)
	var moved: Array = []
	for i in idx:
		var j: int = i + dir
		var a := _z_list.get_item_text(i)
		var b := _z_list.get_item_text(j)
		_z_list.set_item_text(i, b)
		_z_list.set_item_text(j, a)
		moved.append(j)
	_z_list.deselect_all()
	for j in moved:
		_z_list.select(j, false)            # false = 기존 선택에 추가
	_refresh_preview()                      # 바뀐 순서를 바로 보여준다


func _current_z_override() -> PackedStringArray:
	if _z_auto.button_pressed:
		return PackedStringArray()
	var out := PackedStringArray()
	for i in _z_list.item_count:
		out.append(_z_list.get_item_text(i))
	return out


func _fill_anim_list() -> void:
	var f := _anim_filter.text.to_lower()
	_anim_list.clear()
	for a in _all_anims:
		if f == "" or a.to_lower().contains(f):
			_anim_list.add_item(a)


## 렌더 중에 또 요청이 오면(슬라이더를 계속 돌리는 경우) 버리지 않고
## 마지막 상태로 한 번 더 돌린다. 그냥 return 하면 프리뷰가 낡은 채 남는다.
func _refresh_preview() -> void:
	if baker == null or _loading:
		return
	if _busy:
		_dirty = true
		return
	_busy = true
	_dirty = true
	while _dirty:
		_dirty = false
		await _render_preview_once()
	_busy = false


func _render_preview_once() -> void:
	baker.opts = _current_opts()
	if _rest_time != null:
		_rest_time_lbl.text = "t = %d%%" % int(_rest_time.value * 100.0)
	# 레스트 포즈
	if _rest_anim.selected > 0:
		var an := _rest_anim.get_item_text(_rest_anim.selected)
		var res := baker.resolve_anim(an)
		if res != "" and baker.anim_player.has_animation(res):
			baker.set_pose(res, baker.anim_player.get_animation(res).length * _rest_time.value)
	else:
		baker.set_rest_pose()
	# 시점 관련 값이 바뀐 경우에만 카메라를 다시 잡는다.
	# 파트 선택만 바뀐 갱신에서 apply_camera 를 다시 부르면
	# auto_fit 결과가 리셋되고 렌더가 3번씩 더 돈다.
	var sig := _view_sig()
	if sig != _fit_sig:
		baker.apply_view_size()
		baker.apply_camera()
		if _autofit.button_pressed:
			await baker.auto_fit(int(_margin.value))
		_fit_sig = sig
	# 카메라/포즈가 확정된 뒤 기준값을 다시 잡는다. 그리기 순서 자동 정렬이
	# 이 깊이값을 쓰므로 각도를 바꾸면 순서도 따라 바뀌어야 한다.
	baker.rig.capture_rest(baker.skeleton, baker.camera)
	_fill_z_list()

	var img: Image
	var what := ""
	var use_2d := _mode_2d != null and _mode_2d.button_pressed
	var playing := _play != null and _play.button_pressed
	# 3D 는 엔진이 직접 돌린다(뷰포트 텍스처가 그대로 갱신됨).
	# 2D 는 _process 에서 자세를 투영해 퍼펫을 움직인다.
	baker.set_playback(playing and not use_2d)
	set_process(playing and use_2d)
	if use_2d:
		await _ensure_part_cache()
		var rsig := _render_sig()
		if rsig != _puppet_sig or _puppet_bones.is_empty():
			_build_puppet(rsig)
		_pose_puppet(not playing)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		img = _puppet_vp.get_texture().get_image()
		if _iso_parts.is_empty():
			what = "2D 순서 · 전체"
		else:
			what = "2D 순서 · %d개: %s" % [_iso_parts.size(), String(", ").join(_iso_parts)]
	elif _iso_parts.is_empty():
		img = await baker.render_all_parts_composite()
		what = "전체 합성"
	elif _iso_parts.size() == 1:
		img = await baker.render_part(_iso_parts[0])
		what = "%s 만" % _iso_parts[0]
	else:
		img = await baker.render_parts(_iso_parts)
		what = "%d개: %s" % [_iso_parts.size(), String(", ").join(_iso_parts)]
	# 실루엣이 화면을 얼마나 쓰는지 보여준다. 여백은 픽셀 고정이라
	# 저해상도로 갈수록 손해가 커지는데, 숫자로 봐야 알아챌 수 있다.
	# 라벨은 clip_text 라 길어지면 잘리므로 짧은 형식으로 쓴다.
	var used := img.get_used_rect() if img != null else Rect2i()
	if used.size.y > 0:
		var fill := 100.0 * float(used.size.y) / float(maxi(baker.opts.view_size.y, 1))
		_iso_label.text = "%s · %d×%d · 채움 %.0f%%" % [
			what, used.size.x, used.size.y, fill]
	else:
		_iso_label.text = what
	if playing:
		_iso_label.text = "▶ 재생 중 · " + what      # 수치는 재생 중엔 옛 값이라 안 붙인다
	_iso_label.tooltip_text = _iso_label.text

	if use_2d:
		_preview.texture = _puppet_vp.get_texture()
	else:
		_preview.texture = baker.viewport.get_texture()
	# 해상도가 바뀌면 확대 상태를 유지해봐야 엉뚱한 곳을 보게 되므로 맞춤으로 되돌린다
	var tsz := Vector2i(_preview.texture.get_size())
	if tsz != _last_tex_size:
		_last_tex_size = tsz
		_zoom = 0.0
		_pan = Vector2.ZERO
	_layout_preview()


func _on_bake() -> void:
	if baker == null:
		return
	var out := _out_edit.text.strip_edges()
	if not out.begins_with("res://"):
		_status.text = "출력 경로는 res:// 로 시작해야 합니다."
		return
	# 프리뷰 렌더가 돌고 있으면 끝날 때까지 기다린다(무시하고 리턴하면
	# 버튼이 아무 반응 없는 것처럼 보임).
	while _busy:
		await get_tree().process_frame
	_busy = true
	_bake_btn.disabled = true

	var picked := PackedStringArray()
	for i in _anim_list.item_count:
		if _anim_list.is_selected(i):
			picked.append(_anim_list.get_item_text(i))

	var ex := DRExporter.new()
	ex.baker = baker
	ex.out_dir = out
	ex.anim_fps = int(_fps.value)
	ex.anim_names = picked
	ex.auto_fit = _autofit.button_pressed
	ex.fit_margin = int(_margin.value)
	ex.apply_stretch = _stretch.button_pressed
	ex.z_override = _current_z_override()
	ex.progress.connect(func(stage, cur, total):
		_progress.max_value = total
		_progress.value = cur
		_status.text = "%s %d/%d" % [stage, cur, total])

	baker.opts = _current_opts()
	var res: Dictionary = await ex.run()

	# PNG 를 임포트시킨 뒤 씬을 다시 저장해서, 임베드 이미지가 아니라
	# 임포트된 텍스처 파일을 참조하게 만든다.
	var fs := EditorInterface.get_resource_filesystem()
	fs.scan()
	while fs.is_scanning():
		await get_tree().process_frame
	await get_tree().process_frame
	ex.rebuild_scene()
	fs.scan()

	_busy = false
	_bake_btn.disabled = false
	_progress.value = 0
	if bool(res.get("ok", false)):
		_status.text = "완료 — 파트 %d개, 애니 %d개 → %s" % [
			res["parts"].size(), res["animations"].size(), res["scene"]]
		EditorInterface.get_file_system_dock().navigate_to_path(String(res["scene"]))
	else:
		_status.text = "베이크 실패: %s" % String(res.get("error", "알 수 없음"))


## 지금 선택된 레스트 포즈 애니메이션의 실제 이름("" = 없음)
func _current_rest_anim() -> String:
	if baker == null or baker.anim_player == null or _rest_anim.selected <= 0:
		return ""
	return baker.resolve_anim(_rest_anim.get_item_text(_rest_anim.selected))


## 2D 순서 모드에서의 재생. 3D 를 다시 렌더하지 않고
## 본 투영값만 계산해서 캐시된 파트 스프라이트를 움직인다.
func _process(delta: float) -> void:
	if baker == null or not visible or _puppet_bones.is_empty():
		return
	# 프리뷰 갱신 중에는 절대 자세를 건드리면 안 된다.
	# 파트 캐시를 한 장씩 렌더하는 도중에 자세가 바뀌면
	# 파트마다 다른 순간이 찍혀서 팔다리가 몸에서 떨어져 나간다.
	if _busy:
		return
	var an := _current_rest_anim()
	if an == "":
		return
	var anim := baker.anim_player.get_animation(an)
	if anim == null:
		return
	_play_t = fmod(_play_t + delta, maxf(anim.length, 0.001))
	baker.set_pose(an, _play_t)
	_pose_puppet(false)


func _teardown() -> void:
	if baker != null:
		baker.cleanup()
		baker = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_teardown()
