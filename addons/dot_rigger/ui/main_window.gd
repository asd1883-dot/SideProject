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
var _smooth: CheckBox
## 도트 아웃라인(카툰 선) — 창 상단 바. 파트 셰이더 uniform 이라 2D 순서 프리뷰·베이크 결과에 같이 적용
var _outline_px: SpinBox
var _outline_color: ColorPickerButton
var _outline_whole: CheckBox   # 켬 = 전체 실루엣(기본) · 끔 = 파트별
## 동작 평면화(2D 게임식) — 팔다리 각도를 측면 시점에서 재서 화면 안에서만 돌게 한다
var _planar: CheckBox
var _pose_auto: CheckBox
var _pose_yaw: SpinBox
var _off_x: SpinBox
var _off_y: SpinBox
## ▶ 재생으로 돌릴 애니(5번에서 고른 것 중). 레스트 포즈(파트 그림 기준)와 따로 고른다.
var _play_anim: OptionButton
## 리깅 애니메이션 세트 — 자세 계열별(서기/엎드리기/수영…) 레스트 + 동작 묶음. 순서대로 따로 굽는다.
var _sets: Array[Dictionary] = []
var _sets_list: ItemList
var _set_name: LineEdit
## 재생 속도(배속, 0 = 멈춤)와 재생 위치 스크럽. 동작을 천천히·프레임 단위로 뜯어보는 용도.
var _speed: OptionButton
var _scrub: HSlider
var _scrub_lbl: Label
var _isolate: OptionButton
var _rest_anim: OptionButton
var _rest_time: HSlider
var _rest_time_lbl: Label
## 레스트 자동: 고른 동작(+시점)이 바뀌면 다시 찾는다. 찾은 값은 레스트 칸에 들어가므로 이후 흐름은 수동과 같다
var _rest_auto: CheckBox
var _rest_info: Label
var _rest_btns: Array = []
var _auto_rest_key := ""
## 왼쪽 열 접히는 섹션 { 제목 -> FoldableContainer }
var _sections: Dictionary = {}
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
## 5번 목록에서 고른 동작 이름 { name: true }. 검색으로 목록을 다시 채워도 선택이 남도록
## 목록(ItemList)과 따로 들고 있는다. (예전엔 검색을 바꾸면 선택이 풀려 마지막 검색 것만 구워졌음)
var _picked_anims: Dictionary = {}
var _anim_count: Label
var _keep_anims: CheckBox
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
## 2D 퍼펫 뷰포트가 파트 캔버스보다 몇 배 크게 그리는지 (부드러운 도트 이동이면 화면 배율)
var _puppet_scale := 1.0
var _smooth_mat: ShaderMaterial
var _outline_mat: ShaderMaterial   # 전체 실루엣 밑깔개(같은 셰이더, outline_only)
## 프리뷰 확대 계산에 쓰는 원래 크기. 2D 퍼펫 텍스처는 화면 배율로 커지므로 텍스처 크기를 쓰면 안 된다
var _pv_logical := Vector2.ZERO
const PUPPET_SCALE_MAX := 8.0
## 2D 순서 프리뷰의 여유 폭(캔버스 비율, 각 변). 구운 퍼펫에는 캔버스 틀이 없으므로 엎드리기·쭈그리기처럼
## 레스트 틀 밖으로 나가는 동작도 프리뷰에서 잘리지 않게 캔버스보다 넓게 그린다. 틀은 얇은 선으로 표시.
const PUPPET_PAD := 0.25
var _canvas_box: Control
var _puppet_sig := ""
var _play_t := 0.0

## 3D 회전 기즈모. 값의 기준은 2. 시점의 Yaw·Pitch 칸 하나뿐이고 기즈모는 그 칸을 바꾸는 손잡이다.
const GIZMO_SIZE := 92.0
const GIZMO_DEG_PER_PX := 0.5
var _gizmo: Control
var _giz_drag := false
var _giz_moved := false
var _giz_press_pos := Vector2.ZERO
## 칸은 1도 단위라 드래그 누적값을 따로 들고 있다가 정수로 넣는다(칸 = 카메라 = 베이크 각도).
var _giz_yaw := 0.0
var _giz_pitch := 0.0


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
	# 왼쪽 열 = 접히는 섹션들이 든 스크롤 + 스크롤 밖의 바닥(출력 폴더·베이크 버튼·진행바).
	# 섹션이 8개까지 늘어 스크롤이 길어졌고, 베이크 버튼이 맨 아래라 작업할 때마다 내려야 했다(09-16 사용자 지적).
	# 자주 안 만지는 섹션(도트화·파트 분리)은 접어 두고, 베이크는 늘 보이게 바닥에 둔다.
	var left_col := VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(330, 0)
	split.add_child(left_col)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_col.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	scroll.add_child(col)
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	left_col.add_child(footer)
	# 아래 코드는 "left" 에 위젯을 붙인다. _section() 이 접히는 섹션을 만들고 그 내용 상자를 left 로 바꿔 준다.
	var left: VBoxContainer = col

	# 프리셋
	# 섹션 제목·체크박스 글자는 잘리지 않아 왼쪽 열 최소 너비가 된다 — 짧게 쓰고 설명은 툴팁·안내문에(스모크 16번)
	left = _section(col, "0. 프리셋", false)
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
	_tip(load_p, ".tres 프리셋을 골라 모델·각도·도트화·그리기 순서·애니 선택을 한 번에 되돌립니다.\n프리셋의 모델이 지금과 다르면 그 모델을 먼저 불러옵니다.")
	left.add_child(prow)
	_preset_label = Label.new()
	_preset_label.text = "(저장된 프리셋 없음)"
	_preset_label.clip_text = true
	_preset_label.custom_minimum_size = Vector2(80, 20)
	_preset_label.add_theme_font_size_override("font_size", 11)
	left.add_child(_preset_label)

	# 모델
	left = _section(col, "1. 모델", false)
	var mrow := HBoxContainer.new()
	_model_edit = LineEdit.new()
	_model_edit.placeholder_text = "res://models/....glb"
	_model_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mrow.add_child(_model_edit)
	_tip(_model_edit, "불러올 3D 모델 경로(res://). 스킨(뼈대)과 애니메이션이 들어 있는 .glb 권장.")
	var browse := Button.new()
	browse.text = "..."
	browse.pressed.connect(_on_browse)
	mrow.add_child(browse)
	_tip(browse, "파일 탐색기로 모델 고르기")
	left.add_child(mrow)
	var load_btn := Button.new()
	load_btn.text = "모델 불러오기 / 파트 분리"
	load_btn.pressed.connect(_on_load)
	left.add_child(load_btn)
	_tip(load_btn, "모델을 읽고 뼈 가중치로 몸을 파트(머리·몸통·팔다리…)로 나눕니다.\n파트 목록·애니메이션 목록·그리기 순서가 여기서 채워집니다.")

	# 시점
	left = _section(col, "2. 시점 (게임의 유일한 각도)", false)
	_yaw = _spin(left, "Yaw (좌우 회전)", -180, 180, 1, 90)
	_pitch = _spin(left, "Pitch (상하 회전)", -89, 89, 1, 0)
	_ortho = _spin(left, "Ortho 크기 (0=자동)", 0, 100, 0.01, 0)
	_off_x = _spin(left, "캐릭터 이동 X (px)", -1024, 1024, 1, 0)
	_off_y = _spin(left, "캐릭터 이동 Y (px)", -1024, 1024, 1, 0)   # 라벨 폭 150 을 넘어 잘림 — +위 는 툴팁에
	_tip(_yaw, "0 = 정면(+Z 쪽에서 봄), 90 = 오른쪽(+X), -90 = 왼쪽, 180 = 뒤.\n" \
		+ "3D 프리뷰 오른쪽 위 기즈모를 드래그해도 이 값이 바뀝니다.\n" \
		+ "고르는 요령: 동작이 주로 '화면 안에서' 일어나는 각도가 2D 로 잘 나옵니다(걷기·공중제비는 측면 90).\n" \
		+ "몸이 카메라 쪽으로 넘어오는 각도에서는 파트가 줄어들며 종이가 접히듯 보입니다.")
	_tip(_pitch, "양수 = 위에서 내려다봄, 음수 = 아래에서 올려다봄 (±89 까지).\n" \
		+ "3D 프리뷰 오른쪽 위 기즈모와 연동됩니다.")
	_tip(_ortho, "직교 카메라(원근 없음)가 화면 세로로 담는 실제 높이. 모델 단위(UAL1 키는 약 1.8).\n" \
		+ "작게 하면 인물이 크게 찍히고 잘릴 수 있고, 크게 하면 작게 찍힙니다.\n" \
		+ "0 = 자동(모델 크기 × 1.15).\n" \
		+ "'자동 맞춤'이 켜져 있으면 이 값은 시작값일 뿐, 화면에 꽉 차게 다시 맞춥니다.\n" \
		+ "휠 확대와 달리 베이크 결과 자체가 바뀝니다.")
	_tip(_off_x, "도트 크기(Ortho)는 그대로 두고 캐릭터가 찍히는 위치만 옮깁니다(캔버스 픽셀 단위, + = 오른쪽).\n" \
		+ "수영·눕기처럼 몸이 틀 밖으로 나가 잘릴 때 씁니다.\n" \
		+ "'자동 맞춤'이 켜져 있으면 다시 가운데로 맞춰져 무시됩니다. 베이크 결과(파트 그림·카메라)가 바뀝니다.")
	_tip(_off_y, "캐릭터를 위(+)·아래(−)로 옮깁니다(캔버스 픽셀 단위). 아래가 잘리면 + 로 올리세요.\n" \
		+ "'자동 맞춤'이 켜져 있으면 무시됩니다. 베이크 결과가 바뀝니다.")
	var vrow := HBoxContainer.new()
	_autofit = CheckBox.new()
	_autofit.text = "자동 맞춤"
	_autofit.button_pressed = true
	vrow.add_child(_autofit)
	left.add_child(vrow)
	_margin = _spin(left, "여백 (px)", 0, 64, 1, 6)
	_tip(_autofit, "켜면 캐릭터가 캔버스에 꽉 차도록 카메라 위치와 Ortho 크기를 자동으로 맞춥니다(아래 여백만큼 남김).\n" \
		+ "끄면 Ortho 크기 값을 그대로 쓰고 캐릭터를 가운데에 둡니다.")
	_tip(_margin, "자동 맞춤 때 캔버스 가장자리에 남길 픽셀 수. 자동 맞춤이 꺼져 있으면 쓰이지 않습니다.\n" \
		+ "픽셀 고정이라 해상도가 낮을수록 차지하는 비중이 커집니다(64px 이면 2 정도 권장).")
	var preset := HBoxContainer.new()
	for d in [["정측면", 90.0, 0.0], ["3/4 앞", 45.0, 0.0], ["정면", 0.0, 0.0],
			["아이소", 45.0, 30.0], ["탑다운", 0.0, 60.0]]:
		var b := Button.new()
		b.text = String(d[0])
		b.clip_text = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "Yaw %d° · Pitch %d° 로 맞춥니다." % [int(d[1]), int(d[2])]
		b.pressed.connect(func():
			_yaw.value = float(d[1])
			_pitch.value = float(d[2])
			_refresh_preview())
		preset.add_child(b)
	left.add_child(preset)

	# 도트화
	left = _section(col, "3. 도트화", true)
	_res = _spin(left, "해상도 (px, 정사각)", 32, 1024, 8, 192)
	_ss = _spin(left, "슈퍼샘플 (1=직접)", 1, 4, 1, 1)
	_bands = _spin(left, "명암 단계", 2, 8, 1, 3)
	_ambient = _spin(left, "앰비언트", 0, 1, 0.05, 0.45)
	_alpha = _spin(left, "알파 임계값", 0, 1, 0.05, 0.5)
	_levels = _spin(left, "색 양자화 (0=끔)", 0, 32, 1, 0)
	_tip(_res, "캐릭터 한 마리가 들어갈 정사각 캔버스 크기(px). 작을수록 도트가 굵어집니다.\n" \
		+ "파트 이미지와 퍼펫 좌표가 모두 이 크기 기준이라, 바꾸면 다시 구워야 합니다.")
	_tip(_ss, "2 이상이면 그 배수만큼 크게 찍은 뒤 해상도로 줄입니다(가는 부분이 덜 끊기지만 느림).\n" \
		+ "1 = 해상도 그대로 바로 찍음(가장 도트다움).")
	_tip(_bands, "빛 받는 정도를 몇 단계 색으로 나눌지(2~8).\n적을수록 단순한 만화식 명암, 많을수록 부드러운 명암.")
	_tip(_ambient, "빛을 안 받는 쪽의 밝기(0~1). 낮추면 그림자 쪽이 어두워져 입체감이 강해집니다.")
	_tip(_alpha, "가장자리의 반투명 픽셀을 이 값보다 옅으면 투명, 진하면 완전 불투명으로 자릅니다.\n" \
		+ "도트에 흐린 테두리가 안 생기게 합니다(0 = 자르지 않음).")
	_tip(_levels, "색을 빨강·초록·파랑 각각 N단계로 반올림해 줄입니다(0 또는 1 = 끔).\n" \
		+ "작을수록 쓰이는 색 수가 줄어 팔레트 느낌이 납니다.")

	# 파트
	left = _section(col, "4. 파트 분리", true)
	_bleed = _spin(left, "관절 겹침 링 수", 0, 4, 1, 1)
	_tip(_bleed, "파트 경계에서 이웃 파트 쪽 삼각형을 몇 겹 더 가져올지 (모든 관절 공통).\n" \
		+ "2D 에서 관절을 굽혔을 때 이음새가 벌어지는 틈을 메웁니다. 바깥 실루엣은 안 커지고 관절에서만 자랍니다.\n" \
		+ "크게 하면 이웃 살점까지 들고 다녀서, 그리기 순서가 어긋난 곳에 턱이 보일 수 있습니다.")
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
	_tip(_isolate, "파트 하나만 골라 프리뷰에 띄웁니다. 맨 위 항목 = 전체 합성.")

	# 레스트 포즈
	# 리깅 애니메이션 — 내보낼 동작 + 그 동작들을 찍을 레스트 자세.
	# 예전엔 5(레스트)·6(동작)이 따로였는데, 레스트는 결국 "고른 동작들이 화면과 가장 나란한 프레임"이라(02 P8)
	# 동작을 고르면 레스트가 자동으로 정해지게 합쳤다(09-16). 수동이 필요하면 자동을 끈다.
	left = _section(col, "5. 리깅 애니메이션 (동작 + 레스트)", false)
	_anim_filter = LineEdit.new()
	_anim_filter.placeholder_text = "검색 (예: idle, jog, throw)"
	_anim_filter.text_changed.connect(func(_t):
		_sync_picked_from_list()
		_fill_anim_list())
	left.add_child(_anim_filter)
	_tip(_anim_filter, "이름에 이 글자가 들어간 애니메이션만 아래 목록에 보여 줍니다. 선택은 유지됩니다.")
	_anim_list = ItemList.new()
	_anim_list.select_mode = ItemList.SELECT_MULTI
	_anim_list.custom_minimum_size = Vector2(0, 160)
	left.add_child(_anim_list)
	_tip(_anim_list, "베이크할 동작. Ctrl + 클릭 = 하나씩 추가, Shift + 클릭 = 범위 선택.\n" \
		+ "검색어를 바꿔 가며 골라도 선택이 쌓입니다(아래 '선택 N개' 확인). 고른 동작에서 레스트 자세가 자동으로 정해집니다.")
	# 선택이 바뀌면 목록 상태를 기억해 둔다. 여러 칸이 한꺼번에 바뀌는 클릭도 있어 한 프레임 뒤에 읽는다
	_anim_list.multi_selected.connect(func(_i, _on): _sync_picked_from_list.call_deferred())
	_anim_list.item_selected.connect(func(_i): _sync_picked_from_list.call_deferred())
	_anim_list.empty_clicked.connect(func(_p, _b): _sync_picked_from_list.call_deferred())
	var acrow := HBoxContainer.new()
	_anim_count = Label.new()
	_anim_count.text = "선택 0개"
	_anim_count.clip_text = true
	_anim_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_anim_count.custom_minimum_size = Vector2(80, 20)
	_anim_count.add_theme_font_size_override("font_size", 11)
	acrow.add_child(_anim_count)
	var aclear := Button.new()
	aclear.text = "선택 비우기"
	aclear.pressed.connect(func():
		_picked_anims.clear()
		_fill_anim_list())
	acrow.add_child(aclear)
	left.add_child(acrow)
	_tip(aclear, "고른 동작을 전부 해제합니다(검색으로 목록에 안 보이는 것까지).")

	# --- 레스트 자세: 파트 그림을 찍을 자세 하나. 자동이면 고른 동작에서 찾아 아래 칸에 넣는다 ---
	_rest_auto = CheckBox.new()
	_rest_auto.text = "레스트 자동 (고른 동작에서 찾기)"
	_rest_auto.button_pressed = true
	_rest_auto.toggled.connect(func(on):
		_set_rest_manual_enabled(not on)
		_auto_rest_key = ""
		_refresh_preview())
	left.add_child(_rest_auto)
	_tip(_rest_auto, "파트 그림은 레스트 자세 한 장에서 찍히므로, 고른 동작들이 화면과 가장 나란한 프레임이 가장 좋습니다.\n" \
		+ "켜면 위에서 고른 동작(과 시점)이 바뀔 때마다 그런 프레임을 찾아 아래 칸에 넣습니다.\n" \
		+ "끄면 아래 칸을 직접 고릅니다 — 예: 내보내지 않는 Crawl_Enter 를 엎드리기 세트의 레스트로 쓸 때.")
	_rest_info = Label.new()
	_rest_info.text = "레스트: 동작을 고르면 자동으로 찾습니다"
	_rest_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rest_info.add_theme_font_size_override("font_size", 11)
	left.add_child(_rest_info)
	_rest_anim = OptionButton.new()
	_rest_anim.item_selected.connect(func(_i): _refresh_preview())
	left.add_child(_rest_anim)
	_tip(_rest_anim, "파트 이미지를 찍을 자세(애니). 2D 퍼펫은 이 자세에서 찍은 그림 그대로 돌리고 늘여서 움직입니다.\n" \
		+ "팔다리가 카메라 쪽을 향하지 않는 자세가 좋습니다(T포즈는 측면에서 팔이 뭉개짐). 자동이 켜져 있으면 잠깁니다.")
	_rest_time = HSlider.new()
	_rest_time.min_value = 0.0
	_rest_time.max_value = 1.0
	_rest_time.step = 0.01
	_rest_time.value_changed.connect(func(_v): _refresh_preview())
	left.add_child(_rest_time)
	_tip(_rest_time, "위 애니메이션의 몇 % 시점을 레스트 자세로 쓸지 (0% = 첫 프레임). 자동이 켜져 있으면 잠깁니다.")
	_rest_time_lbl = Label.new()
	_rest_time_lbl.text = "t = 0%"
	left.add_child(_rest_time_lbl)
	# 수동 찾기 버튼 두 범위 — "위 애니 안에서 몇 %" / "고른 동작들 중 어느 애니의 몇 %"(자동이 하는 일과 같음)
	var frow := HBoxContainer.new()
	var find_here := Button.new()
	find_here.text = "이 애니에서 자세 찾기"
	find_here.clip_text = true
	find_here.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	find_here.pressed.connect(_find_rest_pose.bind("rest"))
	frow.add_child(find_here)
	var find_picked := Button.new()
	find_picked.text = "고른 동작에서 찾기"
	find_picked.clip_text = true
	find_picked.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	find_picked.pressed.connect(_find_rest_pose.bind("picked"))
	frow.add_child(find_picked)
	_rest_btns = [find_here, find_picked]
	left.add_child(frow)
	var find_tip := "지금 시점에서 팔다리가 카메라를 향하지 않고 화면과 가장 나란한 자세를 찾아 레스트에 넣습니다.\n" \
		+ "카메라를 향해 짧게 찍힌 파트(예: −55° 의 Idle 오른발)는 그 파트가 화면과 나란해지는 동작에서 3D 와 크게 어긋납니다.\n"
	_tip(find_here, "위에서 고른 애니메이션 **안에서** 가장 좋은 시점(%)만 찾습니다. 애니는 바뀌지 않습니다.\n" + find_tip \
		+ "엎드리기·수영 계열을 따로 구울 때: 그 계열 애니를 위에 고르고 이 버튼.")
	_tip(find_picked, "고른 동작들(없으면 전체)을 훑어 **어느 애니의 몇 %** 가 가장 좋은지 찾습니다. 애니가 바뀔 수 있습니다.\n" + find_tip)
	_set_rest_manual_enabled(false)

	# --- 베이크 옵션 ---
	_fps = _spin(left, "샘플 FPS", 4, 60, 1, 12)
	_tip(_fps, "애니메이션에서 1초에 몇 번 자세를 뽑아 키로 넣을지.\n" \
		+ "키 사이는 Godot 이 이어 주므로 12 로도 부드럽게 움직입니다.\n" \
		+ "공중제비·구르기처럼 빠르게 도는 동작은 올려야 모양이 정확합니다(파일은 커짐).")
	_stretch = CheckBox.new()
	_stretch.text = "단축 보정 (팔 권장)"
	_stretch.button_pressed = true
	left.add_child(_stretch)
	_tip(_stretch, "팔다리가 카메라 쪽으로 향하면 화면에서 짧아지는데, 이걸 흉내 내려고 파트 그림을 뼈 방향으로 줄이거나 늘립니다\n" \
		+ "(0.63 ~ 1.6배로 제한). 끄면 도트 결은 깨끗하지만 관절이 벌어져 보일 수 있습니다.\n" \
		+ "몸이 카메라 쪽으로 크게 넘어가는 동작에서는 종이가 접히는 것처럼 보이는 원인이기도 합니다.")
	_smooth = CheckBox.new()
	_smooth.text = "부드러운 도트 이동"
	_smooth.button_pressed = true
	_smooth.tooltip_text = "2D 순서 프리뷰와 베이크 씬의 파트 스프라이트에 셰이더를 붙입니다.\n" \
		+ "도트 칸 안쪽은 또렷하게 두고 칸 경계만 화면 1픽셀 폭으로 섞어서,\n" \
		+ "1픽셀 미만으로 움직일 때 도트가 깜빡이지(TV 노이즈) 않고 매끄럽게 움직입니다.\n" \
		+ "게임에서 캐릭터를 확대해서 그릴 때 효과가 있고, 1:1 로 그리면 끈 것과 거의 같습니다."
	_smooth.toggled.connect(func(_on):
		_apply_puppet_scale()
		_layout_preview()
		_refresh_preview())
	left.add_child(_smooth)
	# 동작 평면화 — 3D 를 그대로 투영하면 팔이 카메라 쪽으로 오갈 때 짧아졌다 길어져 종이 접히듯(페이퍼맨) 보인다.
	# 2D 게임의 컷아웃처럼 팔다리가 화면 안에서만 돌게 하려면 각도를 측면 시점에서 재야 한다.
	_planar = CheckBox.new()
	# 체크박스는 글자를 안 자르므로 라벨이 길면 왼쪽 열 최소 너비가 커져 오른쪽 열이 창 밖으로 밀린다(스모크 16번)
	_planar.text = "동작 평면화 (2D 게임식)"
	_planar.button_pressed = false
	_planar.toggled.connect(func(_on): _refresh_preview())
	left.add_child(_planar)
	_tip(_planar, "켜면 각 파트의 회전을 게임 시점이 아니라 '동작 시점'(보통 측면)에서 재서, 팔다리가 화면 앞뒤로 오가지 않고\n" \
		+ "화면 안에서만 돕니다. 위치는 관절에 고정(강체 2D 리그), 늘이기 없음, 힙의 위아래 들썩임만 유지.\n" \
		+ "3D 와 똑같지는 않지만 2D 게임 캐릭터가 움직이는 방식이 됩니다. 끄면 3D 를 그대로 투영(깊이로 짧아짐).\n" \
		+ "그리기 순서는 그대로 게임 시점의 깊이로 정합니다. 프리뷰·베이크 모두 적용.")
	_pose_auto = CheckBox.new()
	_pose_auto.text = "동작 시점 자동 (측면)"
	_pose_auto.button_pressed = true
	_pose_auto.toggled.connect(func(on):
		_pose_yaw.editable = not on
		_refresh_preview())
	left.add_child(_pose_auto)
	_tip(_pose_auto, "평면화에서 각도를 잴 시점. 자동 = 게임 Yaw 에 가까운 쪽 측면(±90°) — 걷기·달리기처럼 앞뒤로 흔드는 동작에 맞습니다.\n" \
		+ "옆으로 벌리는 동작(점핑잭 등)이 많으면 끄고 아래에 0(정면)을 넣어 보세요.")
	_pose_yaw = _spin(left, "동작 시점 Yaw", -180, 180, 1, 90)
	_pose_yaw.editable = false
	_tip(_pose_yaw, "평면화 각도를 잴 시점(도). 자동이 꺼졌을 때만 씁니다. 90/−90 = 측면, 0 = 정면.")


	# 리깅 애니메이션 세트 — 5번(동작 + 레스트) 한 벌을 이름 붙여 담아 두고, 베이크 때 순서대로 전부 굽는다.
	# 서기·엎드리기·수영은 파트 그림이 달라야 하므로 세트마다 자기 폴더에 따로 구워진다.
	left = _section(col, "6. 애니메이션 세트 (자세 계열별)", false)
	var shint := Label.new()
	shint.text = "5번의 동작 + 레스트 자세 한 벌을 세트로 담습니다. 세트가 있으면 베이크가 전부를 순서대로 <출력 폴더>/<세트 이름>/ 에 굽고 sets.json 을 만듭니다."
	shint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	shint.add_theme_font_size_override("font_size", 11)
	left.add_child(shint)
	var nrow := HBoxContainer.new()
	_set_name = LineEdit.new()
	_set_name.placeholder_text = "세트 이름 (비우면 레스트 애니 이름)"
	_set_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nrow.add_child(_set_name)
	var add_set := Button.new()
	add_set.text = "세트로 추가"
	add_set.clip_text = true
	add_set.pressed.connect(_add_set)
	nrow.add_child(add_set)
	left.add_child(nrow)
	_tip(_set_name, "세트 이름 = 출력 폴더 이름. 예: stand, crawl, swim")
	_tip(add_set, "지금 5번의 동작과 레스트 자세(자동이면 찾은 값)를 세트 하나로 목록에 담습니다.\n이름 = 출력 폴더 이름.")
	_sets_list = ItemList.new()
	_sets_list.custom_minimum_size = Vector2(0, 110)
	_sets_list.select_mode = ItemList.SELECT_SINGLE
	left.add_child(_sets_list)
	_tip(_sets_list, "베이크할 세트 목록(위부터 순서대로). 줄을 고르고 아래 버튼으로 편집합니다.")
	var srow := HBoxContainer.new()
	for spec in [["세트 불러오기", "load", "고른 세트의 동작·레스트를 5번에 다시 펼칩니다(수정하려면 이걸로 꺼내 고친 뒤 '덮어쓰기')."],
			["덮어쓰기", "save", "고른 세트를 지금의 5번 설정으로 바꿉니다."],
			["삭제", "del", "고른 세트를 목록에서 뺍니다(구운 폴더는 지우지 않음)."],
			["▲", "up", "고른 세트를 한 칸 위로(먼저 굽고 sets.json 에서 앞 번호)."],
			["▼", "down", "고른 세트를 한 칸 아래로."]]:
		var sb := Button.new()
		sb.text = String(spec[0])
		sb.clip_text = true
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.pressed.connect(_on_set_button.bind(String(spec[1])))
		sb.tooltip_text = String(spec[2])
		srow.add_child(sb)
	left.add_child(srow)

	# 출력
	# 7. 출력 — 스크롤 밖 바닥. 뭘 하든 베이크 버튼이 보인다
	left = footer
	left.add_child(HSeparator.new())
	var out_lbl := Label.new()
	out_lbl.text = "7. 출력"
	out_lbl.add_theme_font_size_override("font_size", 14)
	left.add_child(out_lbl)
	_out_edit = LineEdit.new()
	_out_edit.text = DEF_OUT
	left.add_child(_out_edit)
	_tip(_out_edit, "베이크 결과(parts/*.png, rig.json, puppet.tscn)를 저장할 res:// 폴더.\n" \
		+ "같은 폴더에 다시 구우면 파트 그림과 씬을 새로 만듭니다(애니메이션은 아래 칸 참고).")
	_keep_anims = CheckBox.new()
	_keep_anims.text = "기존 애니 유지"
	_keep_anims.button_pressed = true
	left.add_child(_keep_anims)
	_tip(_keep_anims, "켜면 같은 폴더에 다시 구울 때 예전에 구운 애니를 남기고 이번 애니를 추가합니다(같은 이름은 새로 구운 것으로 교체).\n" \
		+ "애니는 레스트 포즈·시점 기준 값이라, 레스트 포즈·시점·해상도·파트 구성이 예전과 다르면 섞지 않고 상태줄에 이유를 알려 줍니다.\n" \
		+ "끄면 이번에 고른 애니만 남습니다.")
	_bake_btn = Button.new()
	_bake_btn.text = "베이크"
	_bake_btn.custom_minimum_size = Vector2(0, 36)
	_bake_btn.pressed.connect(_on_bake)
	left.add_child(_bake_btn)
	_tip(_bake_btn, "고른 애니메이션을 지금 설정(시점·도트화·그리기 순서)으로 굽습니다.\n" \
		+ "6번 세트가 하나라도 있으면 세트 전부를 순서대로 <출력 폴더>/<세트 이름>/ 에 굽고 sets.json 을 만듭니다.\n" \
		+ "굽는 동안 창을 닫지 마세요(닫혀 있으면 화면이 안 그려집니다).")
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

	# 상단 바 — 도트 스타일. 왼쪽(설정)·오른쪽(그리기 순서)·아래(파트 트리)에 이어 위쪽 빈 자리를 쓴다(09-16 사용자 요청).
	var topbar := HBoxContainer.new()
	var tl := Label.new()
	tl.text = "도트 스타일"
	tl.add_theme_font_size_override("font_size", 13)
	topbar.add_child(tl)
	var ol := Label.new()
	ol.text = "  아웃라인"   # 짧게 — 상단 바 최소 너비가 커지면 오른쪽 열이 창 밖으로 밀린다(스모크 16)
	topbar.add_child(ol)
	_outline_px = SpinBox.new()
	_outline_px.min_value = 0
	_outline_px.max_value = 3
	_outline_px.step = 1
	_outline_px.value = 0
	_outline_px.tooltip_text = "카툰 렌더링처럼 캐릭터 바깥에 선을 그립니다. 값 = 선 두께(도트 수, 카메라로 확대해도 도트 단위), 0 = 없음.\n" \
		+ "선을 어디에 그릴지는 옆의 `전체 실루엣` 체크가 정합니다.\n" \
		+ "2D 순서 프리뷰와 베이크 결과(장비 포함)에 적용되고, 3D 모드에는 안 보입니다."
	_outline_px.value_changed.connect(_on_style_changed)
	topbar.add_child(_outline_px)
	ol.tooltip_text = _outline_px.tooltip_text
	ol.mouse_filter = Control.MOUSE_FILTER_PASS
	_outline_color = ColorPickerButton.new()
	_outline_color.color = Color.BLACK
	_outline_color.edit_alpha = false
	_outline_color.custom_minimum_size = Vector2(44, 0)
	_outline_color.tooltip_text = "아웃라인 색 (기본 검정)"
	_outline_color.color_changed.connect(_on_style_changed)
	topbar.add_child(_outline_color)
	_outline_whole = CheckBox.new()
	_outline_whole.text = "전체 실루엣"
	_outline_whole.button_pressed = true
	_outline_whole.tooltip_text = "켬(기본) = 캐릭터 전체 실루엣 바깥에만 선 — 파트마다 선 색 밑깔개를 모든 파트 뒤에 깔아서, 관절 겹침은 파트가 덮고 바깥 테두리만 남습니다.\n" \
		+ "끔 = 파트마다 선 — 관절이 겹치는 곳에도 선이 생깁니다(종이 인형 느낌)."
	_outline_whole.toggled.connect(_on_style_changed)
	topbar.add_child(_outline_whole)
	var oh := Label.new()
	oh.text = "2D 순서 프리뷰 · 베이크 결과에 적용 (3D 모드에는 안 보임)"
	oh.add_theme_font_size_override("font_size", 11)
	oh.clip_text = true
	oh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topbar.add_child(oh)
	right.add_child(topbar)

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
	# 베이크 캔버스 틀(2D 순서 모드에서만). 프리뷰는 캔버스보다 넓게 그리므로 어디까지가 구워지는 틀인지 표시
	_canvas_box = Control.new()
	_canvas_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas_box.visible = false
	_canvas_box.draw.connect(func():
		_canvas_box.draw_rect(Rect2(Vector2.ZERO, _canvas_box.size), Color(1, 1, 1, 0.35), false, 1.0))
	_pv_area.add_child(_canvas_box)
	# 3D 회전 기즈모 (프리뷰 오른쪽 위, 3D 모드에서만). 드래그하면 2. 시점의 Yaw·Pitch 칸이 같이 바뀐다
	_gizmo = Control.new()
	_gizmo.custom_minimum_size = Vector2(GIZMO_SIZE, GIZMO_SIZE)
	_gizmo.size = Vector2(GIZMO_SIZE, GIZMO_SIZE)
	_gizmo.mouse_filter = Control.MOUSE_FILTER_STOP
	_gizmo.mouse_default_cursor_shape = Control.CURSOR_MOVE
	_gizmo.tooltip_text = "드래그: 좌우·상하 회전 (2. 시점의 Yaw·Pitch 칸과 연동)\n축 끝 동그라미 클릭: 그 방향에서 보기"
	_gizmo.draw.connect(_draw_gizmo)
	_gizmo.gui_input.connect(_on_gizmo_input)
	_gizmo.visible = false
	_pv_area.add_child(_gizmo)

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
		_update_gizmo()
		_refresh_preview())
	toolbar.add_child(_mode_2d)

	# 프리뷰에서 애니메이션을 돌려 보는 기능. 베이크에는 영향이 없다
	# (베이크는 항상 프레임마다 자세를 세워 놓고 찍는다).
	_play = CheckBox.new()
	_play.text = "▶ 재생"
	_play.tooltip_text = "오른쪽 드롭다운에서 고른 애니메이션을 프리뷰에서 돌립니다.\n" \
		+ "2D 순서 모드에서도 돌아가며, 그때는 지정한 그리기 순서가 적용된 채로 재생됩니다\n" \
		+ "(= 베이크 결과를 그대로 미리 보는 것). 베이크 자체에는 영향이 없습니다."
	_play.toggled.connect(func(on):
		_play_t = 0.0
		_refresh_preview())
	toolbar.add_child(_play)
	_play_anim = OptionButton.new()
	_play_anim.custom_minimum_size = Vector2(120, 0)
	_play_anim.clip_text = true
	_play_anim.fit_to_longest_item = false
	_play_anim.tooltip_text = "▶ 재생으로 돌릴 애니메이션. 5번에서 고른 동작 중에서 고릅니다.\n" \
		+ "레스트 자세는 파트 그림 기준으로 그대로 두고 동작만 미리 봅니다.\n" \
		+ "5번에서 아무것도 안 골랐으면 레스트 애니를 돌립니다."
	_play_anim.item_selected.connect(func(_i):
		_play_t = 0.0
		if _play.button_pressed:
			_refresh_preview())
	toolbar.add_child(_play_anim)

	# 재생 줄 — 속도(느리게 보기) + 위치 스크럽. 3D 는 AnimationPlayer 의 speed_scale,
	# 2D 는 _process 의 delta 에 배속을 곱한다. 속도 0 이면 멈춘 채 슬라이더로 프레임을 옮겨 본다.
	var playbar := HBoxContainer.new()
	_speed = OptionButton.new()
	for sp in [["×1", 1.0], ["×1/2", 0.5], ["×1/4", 0.25], ["×1/10", 0.1], ["멈춤(스크럽)", 0.0]]:
		var si := _speed.item_count
		_speed.add_item(String(sp[0]))
		_speed.set_item_metadata(si, float(sp[1]))
	_speed.select(0)
	_speed.tooltip_text = "▶ 재생 속도. 느리게 하면 도트가 어떻게 움직이는지 자세히 볼 수 있습니다.\n" \
		+ "멈춤을 고르면 오른쪽 슬라이더로 원하는 시점을 잡아 놓고 봅니다."
	_speed.item_selected.connect(func(_i):
		if baker != null and _play != null and _play.button_pressed and not _mode_2d.button_pressed:
			baker.set_playback(true, _speed_value()))
	playbar.add_child(_speed)
	_scrub = HSlider.new()
	_scrub.min_value = 0.0
	_scrub.max_value = 1.0
	_scrub.step = 0.001
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.tooltip_text = "재생 위치. 재생 중에 끌면 그 시점으로 건너뛰고, 멈춤 속도면 그 시점에 멈춰 있습니다."
	_scrub.value_changed.connect(_on_scrub)
	playbar.add_child(_scrub)
	_scrub_lbl = Label.new()
	_scrub_lbl.text = "0.00 / 0.00s"
	_scrub_lbl.custom_minimum_size = Vector2(96, 0)
	_scrub_lbl.add_theme_font_size_override("font_size", 11)
	playbar.add_child(_scrub_lbl)
	right.add_child(playbar)
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
	_tip(_parts_tree, "나뉜 파트 목록(계층 순). 줄을 누르면 그 파트만 프리뷰에 뜹니다.\n" \
		+ "루트 본 = 파트가 붙어 도는 뼈, 삼각형 = 그 파트에 들어간 면 수(관절 겹침 포함).")

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
	_tip(_z_auto, "켜면 3D 깊이로 매 프레임 순서를 자동으로 정합니다(팔이 몸 앞뒤로 교차하는 동작에 맞춰 바뀜).\n" \
		+ "끄면 아래 목록 순서를 모든 프레임에 고정합니다. ▲▼ 로 순서를 바꾸면 자동으로 꺼집니다.")
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
		b.tooltip_text = "선택한 줄을 한 칸 뒤로(목록 위쪽) 옮깁니다." if int(spec[1]) < 0 \
			else "선택한 줄을 한 칸 앞으로(목록 아래쪽) 옮깁니다."
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


## 접히는 섹션을 col 에 붙이고, 위젯을 담을 내용 상자를 돌려준다. 제목으로 _sections 에 기억(_fold 용).
func _section(col: Control, t: String, folded: bool = false) -> VBoxContainer:
	var f := FoldableContainer.new()
	f.title = t
	f.folded = folded
	col.add_child(f)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	f.add_child(v)
	_sections[t] = f
	return v


## 제목이 prefix 로 시작하는 섹션을 접거나 편다(예: 모델을 불러온 뒤 "1. 모델" 접기)
func _fold(prefix: String, folded: bool) -> void:
	for t in _sections.keys():
		if String(t).begins_with(prefix):
			(_sections[t] as FoldableContainer).folded = folded


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


## 툴팁을 컨트롤과, 같은 줄의 이름표(Label)에 같이 붙인다.
## Label 은 기본값이 "마우스 무시"라 그대로 두면 글자 위에 올려도 툴팁이 안 뜬다.
func _tip(c: Control, text: String) -> void:
	c.tooltip_text = text
	var row := c.get_parent()
	if row is HBoxContainer:
		for s in row.get_children():
			if s is Label:
				(s as Label).tooltip_text = text
				(s as Label).mouse_filter = Control.MOUSE_FILTER_PASS


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
	p.offset_x = int(_off_x.value)
	p.offset_y = int(_off_y.value)
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
	p.rest_auto = _rest_auto.button_pressed
	_sync_picked_from_list()
	p.animations = _picked_anim_names()
	p.keep_anims = _keep_anims.button_pressed
	p.fps = int(_fps.value)
	p.apply_stretch = _stretch.button_pressed
	p.smooth_pixel = _smooth.button_pressed
	p.outline_px = int(_outline_px.value)
	p.outline_color = _outline_color.color
	p.outline_whole = _outline_whole.button_pressed
	p.planar = _planar.button_pressed
	p.pose_auto = _pose_auto.button_pressed
	p.pose_yaw = _pose_yaw.value
	p.out_dir = _out_edit.text.strip_edges()
	var sets_copy: Array[Dictionary] = []
	for s in _sets:
		sets_copy.append((s as Dictionary).duplicate(true))
	p.sets = sets_copy
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
	_off_x.value = p.offset_x
	_off_y.value = p.offset_y
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
	_smooth.button_pressed = p.smooth_pixel
	_outline_px.value = p.outline_px
	_outline_color.color = p.outline_color
	_outline_whole.button_pressed = p.outline_whole
	_planar.button_pressed = p.planar
	_pose_auto.button_pressed = p.pose_auto
	_pose_yaw.value = p.pose_yaw
	_pose_yaw.editable = not p.pose_auto
	if p.out_dir != "":
		_out_edit.text = p.out_dir

	# 레스트 포즈는 인덱스가 아니라 이름으로 찾는다(모델이 바뀌면 인덱스가 달라짐)
	_rest_anim.select(0)
	for i in _rest_anim.item_count:
		if _rest_anim.get_item_text(i) == p.rest_anim:
			_rest_anim.select(i)
			break
	_rest_time.value = p.rest_time
	_rest_auto.button_pressed = p.rest_auto

	# 내보낼 애니메이션도 이름으로 복원. 필터를 지워야 전부 보인다.
	_picked_anims.clear()
	for a in p.animations:
		_picked_anims[String(a)] = true
	_anim_filter.text = ""
	_fill_anim_list()
	_keep_anims.button_pressed = p.keep_anims
	_sets.clear()
	for s in p.sets:
		_sets.append((s as Dictionary).duplicate(true))
	_refresh_sets_list()

	# 그리기 순서 — 레이어 단위. 옛 프리셋의 파트 이름(L_Toe 등)도 소속 레이어로 바꿔 받는다
	_z_auto.set_pressed_no_signal(p.z_auto)
	if not p.z_auto and p.z_order.size() > 0 and baker != null:
		_z_list.clear()
		for l in baker.rig.normalize_layer_order(p.z_order):
			_z_list.add_item(String(l))

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
	o.view_offset = Vector2(_off_x.value, _off_y.value)
	o.planar = _planar.button_pressed
	o.pose_yaw = 999.0 if _pose_auto.button_pressed else _pose_yaw.value
	o.supersample = int(_ss.value)
	o.bleed_rings = int(_bleed.value)
	o.light_bands = int(_bands.value)
	o.ambient = _ambient.value
	o.alpha_threshold = _alpha.value
	o.color_levels = int(_levels.value)
	if _rest_anim.selected >= 0:
		o.rest_anim = _rest_anim.get_item_text(_rest_anim.selected)
		# 슬라이더는 0~1 비율, 베이커는 초 단위. 이걸 안 넘기면 프리뷰는 슬라이더 시점으로 찍고
		# 베이크는 항상 0% 로 찍어 파트 그림과 애니 기준이 어긋난다(02 C10).
		if baker != null and baker.anim_player != null:
			var rn := baker.resolve_anim(o.rest_anim)
			if rn != "":
				o.rest_time = baker.anim_player.get_animation(rn).length * _rest_time.value
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
	_picked_anims.clear()
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
	for l in baker.rig.layer_names():     # 그리기 순서 목록은 레이어 단위
		_z_list.add_item(String(l))
	_iso_parts = PackedStringArray()
	_fit_sig = ""

	var un := baker.split.unmapped_bones.size()
	_status.text = "파트 %d개(순서 목록 %d줄) / 본 %d개 / 애니 %d개%s" % [
		baker.rig.order.size(), baker.rig.layer_names().size(),
		baker.skeleton.get_bone_count(), _all_anims.size(),
		("  ⚠ 미매핑 본 %d개" % un) if un > 0 else ""]
	_fold("1.", true)   # 불러왔으면 모델 칸은 접어 스크롤을 줄인다
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
	return _zoom_for(_pv_logical)


## 원래 크기 ts 인 그림을 지금 확대 상태로 보일 때의 배율
func _zoom_for(ts: Vector2) -> float:
	if _zoom > 0.0:
		return _zoom
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
	var ts := _pv_logical
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
	if _gizmo != null:
		_gizmo.position = Vector2(_pv_area.size.x - GIZMO_SIZE - 8.0, 8.0)
		_gizmo.size = Vector2(GIZMO_SIZE, GIZMO_SIZE)
	if _preview.texture == null:
		_zoom_label.text = "맞춤"
		return
	var ts := _pv_logical
	var z := _current_zoom()
	_preview.size = ts * z
	if _puppet_vp != null and _preview.texture == _puppet_vp.get_texture():
		_apply_puppet_scale()
		# 화면 배율 그대로 그렸으면 1:1 로 붙인다. 조금이라도 늘이면 섞어 둔 경계가 다시 nearest 로 뭉개진다
		if is_equal_approx(_puppet_scale, z):
			_preview.size = Vector2(_puppet_vp.size)
	var base := (_pv_area.size - _preview.size) * 0.5
	if _zoom <= 0.0:
		_pan = Vector2.ZERO
	# 정수 좌표로 스냅해야 도트가 반 픽셀에 걸려 흐려지지 않는다
	_preview.position = (base + _pan).round()
	_zoom_label.text = "맞춤" if _zoom <= 0.0 else "%d%%" % int(round(z * 100.0))
	# 2D 순서 모드에서는 캔버스보다 넓게 그리므로, 실제 베이크 캔버스 틀을 얇은 선으로 보여 준다
	if _canvas_box != null:
		var in_2d := baker != null and _puppet_vp != null and _preview.texture == _puppet_vp.get_texture()
		_canvas_box.visible = in_2d
		if in_2d:
			_canvas_box.position = _preview.position + Vector2(_puppet_pad()) * z
			_canvas_box.size = Vector2(baker.opts.view_size) * z
			_canvas_box.queue_redraw()


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


## 목록에 보이는 순서 그대로(위 = 뒤쪽) 돌려준다. 항목은 레이어 이름.
func _order_from_list() -> PackedStringArray:
	var out := PackedStringArray()
	for i in _z_list.item_count:
		out.append(_z_list.get_item_text(i))
	return out


## 목록(레이어) 순서를 파트 순서로 펼친다. 같은 레이어의 파트(발 + 발가락)는 붙어서 나온다.
func _part_order_from_list() -> PackedStringArray:
	if baker == null:
		return _order_from_list()
	return baker.rig.expand_layers(_order_from_list())


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
		# 전체 실루엣 밑깔개(베이크와 같은 구조). 켜고 끄는 건 _apply_part_material
		var ol := art.duplicate() as Sprite2D
		ol.name = DRExporter.OUTLINE_NODE
		ol.z_index = DRExporter.OUTLINE_Z
		ol.visible = false
		stretch.add_child(ol)
		stretch.add_child(art)

		_puppet_bones[pname] = {"bone": bone, "stretch": stretch, "art": art, "outline": ol}
	_puppet_sig = sig
	_pose_puppet(true)
	_apply_puppet_scale()


func _smooth_material() -> ShaderMaterial:
	if _smooth_mat == null:
		_smooth_mat = ShaderMaterial.new()
		_smooth_mat.shader = load(DRExporter.SMOOTH_SHADER) as Shader
	return _smooth_mat


## 파트 스프라이트 머티리얼 — 부드러운 이동이나 파트별 아웃라인 중 하나라도 켜면 셰이더를 붙이고 uniform 을 맞춘다.
## 전체 실루엣이면 밑깔개(outline)를 켜고 같은 셰이더의 outline_only 머티리얼을 붙인다.
## 베이크(DRExporter._build_and_save_scene)와 같은 규칙.
func _apply_part_material() -> void:
	if _puppet_vp == null:
		return
	var smooth := _smooth != null and _smooth.button_pressed
	var opx := int(_outline_px.value) if _outline_px != null else 0
	var whole := _outline_whole == null or _outline_whole.button_pressed
	var ocol: Color = _outline_color.color if _outline_color != null else Color.BLACK
	var part_opx := opx if not whole else 0
	var mat: Material = null
	if smooth or part_opx > 0:
		var sm := _smooth_material()
		sm.set_shader_parameter("smooth_edges", smooth)
		sm.set_shader_parameter("outline_px", part_opx)
		sm.set_shader_parameter("outline_color", ocol)
		mat = sm
	var ol_mat: Material = null
	if opx > 0 and whole:
		if _outline_mat == null:
			_outline_mat = ShaderMaterial.new()
			_outline_mat.shader = load(DRExporter.SMOOTH_SHADER) as Shader
			_outline_mat.set_shader_parameter("outline_only", true)
		_outline_mat.set_shader_parameter("smooth_edges", smooth)
		_outline_mat.set_shader_parameter("outline_px", opx)
		_outline_mat.set_shader_parameter("outline_color", ocol)
		ol_mat = _outline_mat
	for pname in _puppet_bones.keys():
		var nodes: Dictionary = _puppet_bones[pname]
		var art: Sprite2D = nodes["art"]
		if art.material != mat:
			art.material = mat
		var ol: Sprite2D = nodes["outline"]
		if ol.material != ol_mat:
			ol.material = ol_mat
		ol.visible = ol_mat != null and art.visible


## 상단 바(아웃라인)가 바뀌면 — 셰이더 값만 바꾸면 되므로 파트 캐시는 그대로
func _on_style_changed(_v) -> void:
	_apply_part_material()
	_refresh_preview()


## 부드러운 도트 이동이 켜져 있으면 2D 퍼펫을 화면에 보이는 배율 그대로 그린다.
## 파트 캔버스(예: 184px)에 그린 뒤 확대하면 셰이더가 섞을 화면 픽셀이 없어 nearest 와 같아진다
## (2026-09-15 실측: 캔버스에 그린 뒤 확대 = 지금 방식과 차이 없음, 화면 배율 + 셰이더 = Idle 노이즈 81% 감소).
## 여기서 바뀌는 건 프리뷰 뷰포트 크기뿐이고 파트 이미지·베이크에는 영향이 없다.
func _apply_puppet_scale() -> void:
	if _puppet_vp == null or baker == null:
		return
	var on := _smooth != null and _smooth.button_pressed
	var vs := Vector2(baker.opts.view_size)
	var pad := Vector2(_puppet_pad())
	var r := 1.0
	if on:
		r = clampf(_zoom_for(vs + pad * 2.0), 1.0, PUPPET_SCALE_MAX)
	var want := Vector2i(((vs + pad * 2.0) * r).round())
	if _puppet_vp.size != want:
		_puppet_vp.size = want
	_puppet_scale = r
	for c in _puppet_vp.get_children():
		if c is Node2D and not c.is_queued_for_deletion():
			(c as Node2D).scale = Vector2(r, r)
			(c as Node2D).position = pad * r   # 캔버스 원점을 여유 폭만큼 안쪽으로
	_apply_part_material()


## 2D 순서 프리뷰의 여유 폭(px, 각 변). 3D 프리뷰(= 베이크 캔버스)에는 없다.
func _puppet_pad() -> Vector2i:
	if baker == null:
		return Vector2i.ZERO
	return Vector2i((Vector2(baker.opts.view_size) * PUPPET_PAD).round())


## 현재 3D 자세를 투영해 2D 퍼펫에 적용한다. rest_only 면 레스트 상태로 되돌린다.
func _pose_puppet(rest_only: bool = false) -> void:
	if _puppet_bones.is_empty():
		return
	var zpos := {}
	var ord := _part_order_from_list()   # 레이어를 파트로 펼친 순서
	for i in ord.size():
		zpos[ord[i]] = i
	var want := {}
	for n in _iso_parts:
		want[n] = true

	var loc := {}
	if not rest_only:
		loc = baker.project_local()   # 평면화 여부까지 베이커가 정함(베이크와 같은 값)

	for pname in _puppet_bones.keys():
		var nodes: Dictionary = _puppet_bones[pname]
		var bone: Node2D = nodes["bone"]
		var stretch: Node2D = nodes["stretch"]
		var art: Sprite2D = nodes["art"]
		art.visible = want.is_empty() or want.has(pname)
		var ol: Sprite2D = nodes["outline"]
		ol.visible = art.visible and ol.material != null   # 밑깔개는 전체 실루엣일 때만(머티리얼이 붙어 있음)
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
	for n in _part_order_from_list():     # 뒤 -> 앞 (레이어를 파트로 펼친 순서)
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
	return "%.3f|%.3f|%.4f|%d|%d|%d|%d|%d|%.4f|%d|%d|%d|%d" % [
		_yaw.value, _pitch.value, _ortho.value,
		int(_res.value), int(_ss.value), int(_margin.value),
		1 if _autofit.button_pressed else 0,
		_rest_anim.selected, _rest_time.value,
		int(_off_x.value), int(_off_y.value),
		1 if _planar.button_pressed else 0, 999 if _pose_auto.button_pressed else int(_pose_yaw.value)]


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
		var lay := baker.rig.layer(pname)
		it.set_text(0, pname if lay == pname else "%s   (%s 줄에 묶임)" % [pname, lay])
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
	var names := baker.rig.rest_layer_order()   # 레이어 단위 — 발가락은 발 줄에 포함

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
		var lay := _z_list.get_item_text(i)
		if baker != null:
			picked.append_array(baker.rig.layer_parts(lay))   # 발 줄을 고르면 발가락도 같이
		else:
			picked.append(lay)
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
			# 목록 줄은 레이어 단위이므로 파트(L_Toe)는 소속 레이어(L_Foot) 줄을 고른다
			want[baker.rig.layer(String(n)) if baker != null else String(n)] = true
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
			var idx := _anim_list.add_item(a)
			if _picked_anims.has(a):
				_anim_list.select(idx, false)
	_update_anim_count()


## 목록에 지금 보이는 항목의 선택 상태를 _picked_anims 에 옮긴다.
## 검색으로 숨은 항목의 선택은 건드리지 않는다.
func _sync_picked_from_list() -> void:
	var before := _picked_anim_names()
	for i in _anim_list.item_count:
		var n := _anim_list.get_item_text(i)
		if _anim_list.is_selected(i):
			_picked_anims[n] = true
		else:
			_picked_anims.erase(n)
	_update_anim_count()
	# 고른 동작이 바뀌면 레스트 자동이 다시 찾아야 한다(갱신 중이면 _dirty 로 한 번만)
	if _rest_auto != null and _rest_auto.button_pressed and _picked_anim_names() != before:
		_refresh_preview()


## 고른 애니 이름(원래 목록 순서)
func _picked_anim_names() -> PackedStringArray:
	var out := PackedStringArray()
	for a in _all_anims:
		if _picked_anims.has(a):
			out.append(a)
	return out


func _update_anim_count() -> void:
	if _anim_count == null:
		return
	var names := _picked_anim_names()
	_anim_count.text = "선택 %d개%s" % [names.size(), (": " + ", ".join(names)) if names.size() > 0 else ""]
	_anim_count.tooltip_text = _anim_count.text
	_refill_play_anims()


## ▶ 재생 드롭다운을 5번에서 고른 동작으로 채운다. 고른 게 없으면 "(레스트 포즈 애니)" 하나.
## 고르던 항목이 목록에 남아 있으면 그대로 둔다.
func _refill_play_anims() -> void:
	if _play_anim == null:
		return
	var prev := ""
	if _play_anim.item_count > 0 and _play_anim.selected >= 0:
		prev = String(_play_anim.get_item_metadata(_play_anim.selected))
	_play_anim.clear()
	var names := _picked_anim_names()
	if names.is_empty():
		_play_anim.add_item("(레스트 포즈 애니)")
		_play_anim.set_item_metadata(0, "")
	else:
		for n in names:
			var i := _play_anim.item_count
			_play_anim.add_item(n)
			_play_anim.set_item_metadata(i, n)
	var pick := 0
	for i in _play_anim.item_count:
		if String(_play_anim.get_item_metadata(i)) == prev:
			pick = i
	_play_anim.select(pick)
	if String(_play_anim.get_item_metadata(pick)) != prev and _play != null and _play.button_pressed:
		_play_t = 0.0
		_refresh_preview()


## ▶ 재생으로 돌릴 애니메이션의 실제 이름. 드롭다운이 레스트 항목이면 레스트 포즈 애니.
func _current_play_anim() -> String:
	if baker != null and _play_anim != null and _play_anim.item_count > 0 and _play_anim.selected >= 0:
		var n := String(_play_anim.get_item_metadata(_play_anim.selected))
		if n != "":
			return baker.resolve_anim(n)
	return _current_rest_anim()


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
	await _ensure_auto_rest()   # 자동이면 고른 동작에서 레스트를 먼저 정한다(레스트 칸에 들어감)
	baker.opts = _current_opts()
	if _rest_time != null:
		_rest_time_lbl.text = "t = %d%%" % int(_rest_time.value * 100.0)
	# 레스트 포즈
	if _rest_anim.selected > 0:
		var an := _rest_anim.get_item_text(_rest_anim.selected)
		var res := baker.resolve_anim(an)
		if res != "" and baker.anim_player.has_animation(res):
			baker.set_pose(res, baker.opts.rest_time)   # _current_opts 가 초 단위로 환산해 둠 — 베이크와 같은 시점
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
	baker.capture_rest()
	_fill_z_list()

	var img: Image
	var what := ""
	var use_2d := _mode_2d != null and _mode_2d.button_pressed
	var playing := _play != null and _play.button_pressed
	# 3D 는 엔진이 직접 돌린다(뷰포트 텍스처가 그대로 갱신됨).
	# 2D 는 _process 에서 자세를 투영해 퍼펫을 움직인다.
	# 3D 재생: 파트 기준(레스트 포즈)은 위에서 이미 잡았으니, 재생할 애니로 바꿔 엔진이 돌리게 한다.
	# (2D 재생은 _process 가 재생할 애니로 자세를 세운다. 파트 그림 캐시는 레스트 포즈로 찍힌 그대로)
	if playing and not use_2d:
		var pa := _current_play_anim()
		if pa != "":
			baker.set_pose(pa, _play_t)
	baker.set_playback(playing and not use_2d, _speed_value())
	# 재생 중엔 두 모드 모두 _process 를 돈다 — 2D 는 자세를 세우고, 3D 는 스크럽 표시만 따라간다
	set_process(playing)
	_update_scrub()
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
	# 2D 퍼펫은 화면 배율로 크게 그렸을 수 있으므로 파트 캔버스 픽셀로 되돌려 센다
	var px := _puppet_scale if use_2d else 1.0
	var used_w := roundi(used.size.x / px)
	var used_h := roundi(used.size.y / px)
	if used_h > 0:
		var fill := 100.0 * float(used_h) / float(maxi(baker.opts.view_size.y, 1))
		_iso_label.text = "%s · %d×%d · 채움 %.0f%%" % [
			what, used_w, used_h, fill]
	else:
		_iso_label.text = what
	if playing:
		_iso_label.text = "▶ 재생 중 · " + what      # 수치는 재생 중엔 옛 값이라 안 붙인다
	_iso_label.tooltip_text = _iso_label.text

	if use_2d:
		_preview.texture = _puppet_vp.get_texture()
		_pv_logical = Vector2(baker.opts.view_size + _puppet_pad() * 2)   # 여유 폭 포함
	else:
		_preview.texture = baker.viewport.get_texture()
		_pv_logical = Vector2(_preview.texture.get_size())
	# 해상도가 바뀌면 확대 상태를 유지해봐야 엉뚱한 곳을 보게 되므로 맞춤으로 되돌린다
	# (2D 퍼펫 텍스처는 확대할 때마다 크기가 바뀌므로 텍스처가 아니라 원래 크기로 비교한다)
	var tsz := Vector2i(_pv_logical)
	if tsz != _last_tex_size:
		_last_tex_size = tsz
		_zoom = 0.0
		_pan = Vector2.ZERO
	_layout_preview()
	_update_gizmo()


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

	_sync_picked_from_list()
	baker.opts = _current_opts()
	var cfg := _bake_cfg()
	var exporters: Array = []
	var res: Dictionary
	if _sets.is_empty():
		# 세트 없음 — 지금 5번 설정 한 벌을 출력 폴더에
		var ex := DRExporter.new()
		ex.baker = baker
		ex.out_dir = out
		ex.anim_names = _picked_anim_names()   # 검색으로 목록에 안 보이는 것까지
		ex.apply_cfg(cfg)
		ex.progress.connect(func(stage, cur, total):
			_progress.max_value = total
			_progress.value = cur
			_status.text = "%s %d/%d" % [stage, cur, total])
		res = await ex.run()
		exporters.append(ex)
	else:
		# 세트 있음 — 순서대로 전부, <출력 폴더>/<세트 이름>/ + sets.json
		var sb := DRSetBaker.new()
		sb.baker = baker
		sb.progress.connect(func(si, sn, sname, stage, cur, total):
			_progress.max_value = total
			_progress.value = cur
			_status.text = "세트 %d/%d %s — %s %d/%d" % [si + 1, sn, sname, stage, cur, total])
		# 자동 레스트 세트는 지금 시점으로 다시 찾는다(담을 때와 시점이 달라졌을 수 있음)
		for s in _sets:
			if bool(s.get("rest_auto", false)):
				var best: Dictionary = await _scan_best_rest(PackedStringArray(s.get("animations", PackedStringArray())))
				if String(best["anim"]) != "":
					s["rest_anim"] = best["anim"]
					s["rest_time"] = best["t"]
		_refresh_sets_list()
		res = await sb.run(_sets, out, cfg)
		exporters = sb.exporters

	# PNG 를 임포트시킨 뒤 씬을 다시 저장해서, 임베드 이미지가 아니라
	# 임포트된 텍스처 파일을 참조하게 만든다.
	var fs := EditorInterface.get_resource_filesystem()
	fs.scan()
	while fs.is_scanning():
		await get_tree().process_frame
	await get_tree().process_frame
	for ex in exporters:
		(ex as DRExporter).rebuild_scene()
	fs.scan()

	_busy = false
	_bake_btn.disabled = false
	_progress.value = 0
	if bool(res.get("ok", false)):
		var msg := ""
		if res.has("sets"):
			var lines := PackedStringArray()
			for e in res["sets"]:
				var ln := "%s → %s (애니 %d개)" % [e["name"], e["dir"], (e["animations"] as Array).size()]
				if String(e.get("dropped_reason", "")) != "":
					ln += " ⚠ " + String(e["dropped_reason"])
				lines.append(ln)
			msg = "완료 — 세트 %d개 → %s/sets.json\n%s" % [lines.size(), out, "\n".join(lines)]
		else:
			msg = "완료 — 파트 %d개, 애니 %d개 → %s" % [
				res["parts"].size(), res["animations"].size(), res["scene"]]
			var kept: PackedStringArray = res.get("kept", PackedStringArray())
			if kept.size() > 0:
				msg += "  (예전 애니 %d개 유지: %s)" % [kept.size(), ", ".join(kept)]
			if String(res.get("dropped_reason", "")) != "":
				msg += "\n⚠ " + String(res["dropped_reason"])
		_status.text = msg
		EditorInterface.get_file_system_dock().navigate_to_path(String(res["scene"]))
	else:
		_status.text = "베이크 실패: %s" % String(res.get("error", "알 수 없음"))


## 세트 공통 베이크 설정(5번 아래 베이크 옵션 + 그리기 순서). 익스포터가 apply_cfg 로 받는다.
func _bake_cfg() -> Dictionary:
	return {
		"fps": int(_fps.value),
		"auto_fit": _autofit.button_pressed,
		"margin": int(_margin.value),
		"stretch": _stretch.button_pressed,
		"smooth": _smooth.button_pressed,
		"outline_px": int(_outline_px.value),
		"outline_color": _outline_color.color,
		"outline_whole": _outline_whole.button_pressed,
		"keep_previous": _keep_anims.button_pressed,
		"z_override": _current_z_override(),
	}


# ---------------------------------------------------------------- 리깅 애니메이션 세트

## 지금 5번(동작 + 레스트) 한 벌을 세트 사전으로.
func _set_from_current() -> Dictionary:
	_sync_picked_from_list()
	var rest := ""
	if _rest_anim.selected > 0:
		rest = _rest_anim.get_item_text(_rest_anim.selected)
	var name := _set_name.text.strip_edges()
	if name == "":
		name = rest if rest != "" else "set%d" % (_sets.size() + 1)
	return {
		"name": name,
		"rest_anim": rest,
		"rest_time": _rest_time.value,
		"rest_auto": _rest_auto.button_pressed,
		"animations": _picked_anim_names(),
		# 그리기 순서도 세트마다 — 달리기는 오른팔을 허벅지 뒤로, 걷기는 앞으로 두고 싶을 수 있다
		"z_auto": _z_auto.button_pressed,
		"z_order": _order_from_list(),
	}


## 세트를 5번에 펼친다(프리뷰는 한 번만 갱신).
func _apply_set(s: Dictionary) -> void:
	_loading = true
	_rest_anim.select(0)
	for i in _rest_anim.item_count:
		if _rest_anim.get_item_text(i) == String(s.get("rest_anim", "")):
			_rest_anim.select(i)
	_rest_time.value = float(s.get("rest_time", 0.0))
	_rest_auto.button_pressed = bool(s.get("rest_auto", false))
	# 그리기 순서 복원(세트에 있을 때만 — 옛 세트는 목록을 건드리지 않는다)
	if s.has("z_auto"):
		_z_auto.set_pressed_no_signal(bool(s["z_auto"]))
		var zo := PackedStringArray(s.get("z_order", PackedStringArray()))
		if not bool(s["z_auto"]) and not zo.is_empty() and baker != null:
			_z_list.clear()
			for l in baker.rig.normalize_layer_order(zo):
				_z_list.add_item(String(l))
	_picked_anims.clear()
	for a in s.get("animations", PackedStringArray()):
		_picked_anims[String(a)] = true
	_anim_filter.text = ""
	_fill_anim_list()
	_set_name.text = String(s.get("name", ""))
	_loading = false
	_refresh_preview()


func _add_set() -> void:
	if baker == null:
		_status.text = "먼저 모델을 불러오세요."
		return
	var s := _set_from_current()
	if (s["animations"] as PackedStringArray).is_empty():
		_status.text = "5번에서 동작을 하나 이상 고른 뒤 세트로 담으세요."
		return
	_sets.append(s)
	_refresh_sets_list()
	_sets_list.select(_sets.size() - 1)
	_status.text = "세트 추가: %s (레스트 %s %d%% · 동작 %d개)" % [
		s["name"], s["rest_anim"], int(round(float(s["rest_time"]) * 100.0)), (s["animations"] as PackedStringArray).size()]


func _selected_set() -> int:
	var sel := _sets_list.get_selected_items()
	return sel[0] if sel.size() > 0 else -1


func _on_set_button(what: String) -> void:
	var i := _selected_set()
	if i < 0:
		_status.text = "목록에서 세트를 먼저 고르세요."
		return
	match what:
		"load":
			_apply_set(_sets[i])
			_status.text = "세트 불러옴: %s" % String(_sets[i]["name"])
		"save":
			var s := _set_from_current()
			if _set_name.text.strip_edges() == "":
				s["name"] = _sets[i]["name"]
			_sets[i] = s
			_refresh_sets_list()
			_sets_list.select(i)
			_status.text = "세트 덮어씀: %s" % String(s["name"])
		"del":
			var nm := String(_sets[i]["name"])
			_sets.remove_at(i)
			_refresh_sets_list()
			if _sets.size() > 0:
				_sets_list.select(mini(i, _sets.size() - 1))
			_status.text = "세트 삭제: %s" % nm
		"up", "down":
			var j := i - 1 if what == "up" else i + 1
			if j < 0 or j >= _sets.size():
				return
			var tmp: Dictionary = _sets[i]
			_sets[i] = _sets[j]
			_sets[j] = tmp
			_refresh_sets_list()
			_sets_list.select(j)


func _refresh_sets_list() -> void:
	if _sets_list == null:
		return
	_sets_list.clear()
	for i in _sets.size():
		var s: Dictionary = _sets[i]
		var anims: PackedStringArray = PackedStringArray(s.get("animations", PackedStringArray()))
		var zt := ""
		if s.has("z_auto"):
			zt = " · 순서 자동" if bool(s["z_auto"]) else " · 순서 수동"
		_sets_list.add_item("%d. %s — 레스트 %s %d%% · 동작 %d개%s" % [
			i + 1, s.get("name", ""), s.get("rest_anim", ""), int(round(float(s.get("rest_time", 0.0)) * 100.0)), anims.size(), zt])
		_sets_list.set_item_tooltip(i, "동작: " + ", ".join(anims))


## 지금 선택된 레스트 포즈 애니메이션의 실제 이름("" = 없음)
func _current_rest_anim() -> String:
	if baker == null or baker.anim_player == null or _rest_anim.selected <= 0:
		return ""
	return baker.resolve_anim(_rest_anim.get_item_text(_rest_anim.selected))


## 레스트 자세 점수에서 빼는 파트 — 짧거나 작아서(힙 tail 16px, 머리 19px, 손) 단축률이 뜻이 없다.
const REST_SCAN_SKIP := ["Hips", "Head", "L_Hand", "R_Hand"]


## 한 자세의 점수 = 파트 중 가장 낮은 단축률(1 = 화면과 나란함, 0 = 카메라를 향함) 과 그 파트.
func _rest_score() -> Array:
	var f: Dictionary = baker.rig.foreshortening(baker.skeleton, baker.camera, float(baker.opts.view_size.y))
	var mn := INF
	var mp := ""
	for pn in f.keys():
		if String(pn) in REST_SCAN_SKIP:
			continue
		if float(f[pn]) < mn:
			mn = float(f[pn])
			mp = String(pn)
	return [mn if mn != INF else 0.0, mp]


## 후보 애니들을 1초당 12프레임씩 훑어 파트 최소 단축률(힙·머리·손 제외)이 가장 큰 프레임을 돌려준다.
## { anim, t(0~1), score, part }. 스캔 중 자세를 바꾸므로 끝난 뒤 호출자가 레스트를 다시 세운다.
func _scan_best_rest(cands: PackedStringArray) -> Dictionary:
	var best := {"anim": "", "t": 0.0, "score": -1.0, "part": ""}
	if baker == null or baker.anim_player == null:
		return best
	var n := 0
	for an0 in cands:
		var an := baker.resolve_anim(String(an0))
		if an == "":
			continue
		var anim := baker.anim_player.get_animation(an)
		var steps := clampi(roundi(anim.length * 12.0), 4, 36)
		for k in steps:
			var frac := float(k) / float(steps)
			baker.set_pose(an, anim.length * frac)
			var sc := _rest_score()
			if float(sc[0]) > float(best["score"]):
				best = {"anim": String(an0), "t": frac, "score": float(sc[0]), "part": String(sc[1])}
			n += 1
			if n % 24 == 0:
				await get_tree().process_frame
	return best


## 레스트 칸을 잠그거나 푼다(자동일 때 잠금)
func _set_rest_manual_enabled(on: bool) -> void:
	_rest_anim.disabled = not on
	_rest_time.editable = on
	for b in _rest_btns:
		(b as Button).disabled = not on


## 레스트 자동: 5번에서 고른 동작(+ 시점)이 바뀌었을 때만 다시 찾아 레스트 칸에 넣는다.
## 단축률은 카메라 각도만 보므로 열쇠는 동작 목록 + yaw/pitch. 프리뷰 갱신 첫머리에서 부른다.
func _ensure_auto_rest() -> void:
	if baker == null or _rest_auto == null or not _rest_auto.button_pressed:
		return
	var picked := _picked_anim_names()
	if picked.is_empty():
		_rest_info.text = "레스트: 동작을 고르면 자동으로 찾습니다 (지금은 아래 칸 값 그대로)"
		return
	var key := "%s|%.1f|%.1f" % [",".join(picked), _yaw.value, _pitch.value]
	if key == _auto_rest_key:
		return
	if _view_sig() != _fit_sig:   # 각도가 바뀐 직후면 카메라부터 그 각도로
		baker.opts = _current_opts()
		baker.apply_view_size()
		baker.apply_camera()
	var best: Dictionary = await _scan_best_rest(picked)
	_auto_rest_key = key
	if String(best["anim"]) == "":
		return
	_loading = true
	for i in _rest_anim.item_count:
		if _rest_anim.get_item_text(i) == String(best["anim"]):
			_rest_anim.select(i)
	_rest_time.value = snappedf(float(best["t"]), 0.01)
	_loading = false
	_rest_info.text = "레스트 자동: %s %d%% (가장 눌린 파트 %s %.2f)" % [
		best["anim"], int(round(float(best["t"]) * 100.0)), best["part"], float(best["score"])]


## 수동 찾기 버튼. scope "rest" = 레스트 칸의 애니 안에서 시점만 · "picked" = 5번에서 고른 동작들(없으면 전체) 중에서.
func _find_rest_pose(scope: String = "picked") -> void:
	if baker == null or baker.anim_player == null or _busy:
		return
	var cands := PackedStringArray()
	var scanned := ""
	if scope == "rest":
		if _rest_anim.selected <= 0:
			_status.text = "먼저 레스트 애니메이션을 고르세요."
			return
		cands.append(_rest_anim.get_item_text(_rest_anim.selected))
		scanned = "%s 안에서" % cands[0]
	else:
		cands = _picked_anim_names()
		scanned = "고른 동작 %d개 중" % cands.size()
		if cands.is_empty():
			cands = _all_anims
			scanned = "전체 %d개 중" % cands.size()
	_busy = true
	baker.set_playback(false)
	var before := _rest_score()
	var best: Dictionary = await _scan_best_rest(cands)
	_busy = false
	if String(best["anim"]) == "":
		_status.text = "레스트 자세를 찾지 못했습니다(애니메이션 없음)."
		return
	_loading = true
	for i in _rest_anim.item_count:
		if _rest_anim.get_item_text(i) == String(best["anim"]):
			_rest_anim.select(i)
	_rest_time.value = snappedf(float(best["t"]), 0.01)
	_loading = false
	_status.text = "레스트 자세 → %s %d%% (%s · 가장 눌린 파트 %s %.2f · 이전 %s %.2f)" % [
		best["anim"], int(round(float(best["t"]) * 100.0)), scanned, best["part"], float(best["score"]), String(before[1]), float(before[0])]
	_refresh_preview()


## 2D 순서 모드에서의 재생. 3D 를 다시 렌더하지 않고
## 본 투영값만 계산해서 캐시된 파트 스프라이트를 움직인다.
func _process(delta: float) -> void:
	if baker == null or not visible or _play == null or not _play.button_pressed:
		return
	# 프리뷰 갱신 중에는 절대 자세를 건드리면 안 된다.
	# 파트 캐시를 한 장씩 렌더하는 도중에 자세가 바뀌면
	# 파트마다 다른 순간이 찍혀서 팔다리가 몸에서 떨어져 나간다.
	if _busy:
		return
	var an := _current_play_anim()
	if an == "":
		return
	var anim := baker.anim_player.get_animation(an)
	if anim == null:
		return
	if _mode_2d.button_pressed:
		if _puppet_bones.is_empty():
			return
		_play_t = fmod(_play_t + delta * _speed_value(), maxf(anim.length, 0.001))
		baker.set_pose(an, _play_t)
		_pose_puppet(false)
	elif baker.anim_player.current_animation == an:
		_play_t = baker.anim_player.current_animation_position   # 3D 는 엔진이 돌리므로 읽기만
	_update_scrub()


func _speed_value() -> float:
	if _speed == null or _speed.selected < 0:
		return 1.0
	return float(_speed.get_item_metadata(_speed.selected))


## 스크럽 슬라이더와 시간 표시를 지금 재생 위치에 맞춘다(신호 없이).
func _update_scrub() -> void:
	if _scrub == null or baker == null:
		return
	var an := _current_play_anim()
	var len := 0.0
	if an != "" and baker.anim_player != null and baker.anim_player.has_animation(an):
		len = baker.anim_player.get_animation(an).length
	_scrub.set_value_no_signal(_play_t / len if len > 0.0 else 0.0)
	_scrub_lbl.text = "%.2f / %.2fs" % [_play_t, len]


## 사용자가 슬라이더를 끌었을 때 — 재생 중이면 그 시점으로 건너뛴다.
func _on_scrub(v: float) -> void:
	if baker == null or _busy or _play == null or not _play.button_pressed:
		return
	var an := _current_play_anim()
	if an == "":
		return
	var len := baker.anim_player.get_animation(an).length
	_play_t = clampf(v, 0.0, 1.0) * len
	baker.set_pose(an, _play_t)
	if _mode_2d.button_pressed:
		_pose_puppet(false)
	_scrub_lbl.text = "%.2f / %.2fs" % [_play_t, len]


# ---------------------------------------------------------------- 3D 회전 기즈모

func _update_gizmo() -> void:
	if _gizmo == null:
		return
	_gizmo.visible = baker != null and not (_mode_2d != null and _mode_2d.button_pressed)
	_gizmo.queue_redraw()


## 축 끝 좌표(기즈모 안 좌표)와 깊이. 카메라 기저를 그대로 투영하므로
## 부호 규칙과 무관하게 화면에 보이는 모델 방향과 일치한다.
func _gizmo_axes() -> Array:
	var out: Array = []
	if baker == null or baker.camera == null:
		return out
	var b := baker.camera.global_transform.basis
	var c := Vector2(GIZMO_SIZE, GIZMO_SIZE) * 0.5
	var rad := GIZMO_SIZE * 0.5 - 12.0
	var defs := [
		["X", Vector3.RIGHT, Color(0.93, 0.33, 0.33)],
		["Y", Vector3.UP, Color(0.55, 0.85, 0.30)],
		["Z", Vector3.BACK, Color(0.32, 0.56, 0.98)],
	]
	for d in defs:
		for sgn in [1.0, -1.0]:
			var v: Vector3 = Vector3(d[1]) * float(sgn)
			out.append({
				"name": ("" if float(sgn) > 0.0 else "-") + String(d[0]),
				"axis": v,
				"pos": c + Vector2(v.dot(b.x), -v.dot(b.y)) * rad,
				"depth": v.dot(b.z),
				"color": d[2],
				"positive": float(sgn) > 0.0,
			})
	# 먼 축부터 그려서 가까운 축이 위에 오게
	out.sort_custom(func(p, q): return float(p["depth"]) < float(q["depth"]))
	return out


func _draw_gizmo() -> void:
	var c := Vector2(GIZMO_SIZE, GIZMO_SIZE) * 0.5
	_gizmo.draw_circle(c, GIZMO_SIZE * 0.5 - 1.0, Color(0, 0, 0, 0.45 if _giz_drag else 0.28))
	var font := _gizmo.get_theme_default_font()
	for a in _gizmo_axes():
		var col: Color = a["color"]
		var p: Vector2 = a["pos"]
		if bool(a["positive"]):
			_gizmo.draw_line(c, p, col, 2.0, true)
			_gizmo.draw_circle(p, 8.0, col)
			_gizmo.draw_string(font, p + Vector2(-4, 4), String(a["name"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.08, 0.08, 0.1))
		else:
			_gizmo.draw_circle(p, 6.0, Color(col, 0.3))
			_gizmo.draw_arc(p, 6.0, 0.0, TAU, 16, col, 1.5, true)


## 드래그 = 좌우·상하 회전. 거의 안 움직이고 떼면 축 클릭.
func _on_gizmo_input(ev: InputEvent) -> void:
	if baker == null:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_giz_drag = true
			_giz_moved = false
			_giz_press_pos = mb.position
			_giz_yaw = _yaw.value
			_giz_pitch = _pitch.value
		else:
			var was_drag := _giz_drag and _giz_moved
			_giz_drag = false
			if was_drag:
				_refresh_preview()     # 손을 뗄 때 한 번: 자동 맞춤·그리기 순서까지 제대로 다시
			else:
				_gizmo_click(mb.position)
		_gizmo.queue_redraw()
		_gizmo.accept_event()
	elif ev is InputEventMouseMotion and _giz_drag:
		var mm := ev as InputEventMouseMotion
		if not _giz_moved and (mm.position - _giz_press_pos).length() > 3.0:
			_giz_moved = true
		if _giz_moved and not _busy:
			_giz_yaw -= mm.relative.x * GIZMO_DEG_PER_PX
			_giz_pitch = clampf(_giz_pitch + mm.relative.y * GIZMO_DEG_PER_PX, -89.0, 89.0)
			_set_view_live(wrapf(roundf(_giz_yaw), -180.0, 180.0), roundf(_giz_pitch))
		_gizmo.accept_event()


## 드래그 중: 칸 숫자와 카메라만 즉시 바꾼다. 자동 맞춤·순서 재계산 같은 전체 갱신은
## 손을 뗄 때 한 번 — 매 픽셀마다 돌리면 렌더가 쌓여 끊긴다.
func _set_view_live(yaw: float, pitch: float) -> void:
	_yaw.set_value_no_signal(yaw)
	_pitch.set_value_no_signal(pitch)
	baker.orbit_camera(_yaw.value, _pitch.value)
	_gizmo.queue_redraw()


## 축 끝을 누르면 그 방향에서 본다. 정면 +Z = Yaw 0, 오른쪽 +X = Yaw 90, 위 +Y = Pitch 89.
func _gizmo_click(pos: Vector2) -> void:
	var best: Dictionary = {}
	var best_d := 12.0
	for a in _gizmo_axes():
		var dd := (Vector2(a["pos"]) - pos).length()
		if dd <= best_d:
			best_d = dd
			best = a
	if best.is_empty():
		return
	var v: Vector3 = best["axis"]
	var yaw := _yaw.value
	var pitch := 0.0
	if absf(v.y) > 0.5:
		pitch = 89.0 if v.y > 0.0 else -89.0
	else:
		yaw = rad_to_deg(atan2(v.x, v.z))
	_yaw.set_value_no_signal(wrapf(roundf(yaw), -180.0, 180.0))
	_pitch.set_value_no_signal(pitch)
	_refresh_preview()


func _teardown() -> void:
	if baker != null:
		baker.cleanup()
		baker = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_teardown()
