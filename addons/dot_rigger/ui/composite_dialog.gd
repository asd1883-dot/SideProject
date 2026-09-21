@tool
extends AcceptDialog
class_name DRCompositeDialog

## 상하체 합성 설정 팝업. "하체 동작 + 상체 동작 = 새 동작" 을 여러 개 정의한다.
## 실제 합성은 DRBaker.build_composites() 가 3D 뼈 트랙 단계에서 하고, 만든 동작은 창의 5번 목록에
## 다른 애니와 똑같이 나타난다(고르고 · 레스트로 쓰고 · 세트에 담고 · 굽는다).
## 이 팝업은 정의만 편집하고 `적용` 을 누르면 applied 신호로 넘긴다.
##
## 오른쪽 **프리뷰**: 지금 고른 합성을 그 자리에서 만들어(DRBaker.make_composite_preview — 숨은 이름이라 목록에는 안 나온다)
## 베이커의 3D 도트 렌더로 보여 주고 재생한다. 칸을 바꾸면 바로 다시 만든다. `적용` 전에도 결과를 볼 수 있다.
## 팝업이 닫히면 미리보기 동작을 치우고 closed 신호로 창에 알린다(창이 자기 프리뷰 자세를 되돌린다).

signal applied(defs: Array, upper_parts: PackedStringArray, auto_pick: bool)
signal closed()

## 길이 맞춤 — [DRBaker 의 LEN_* 값, 표시 글자]. 질문 둘의 조합: 누구의 시간에 맞추나(하체/상체) × 하체를 몇 번 돌리나(반복/1번).
## 글자는 09-21 사용자와 같이 정한 것 — 처음의 "하체 기준 / 한 번씩" 은 무슨 뜻인지 읽히지 않았다.
const LEN_ITEMS := [
	[0, "하체 시간에 상체를 맞춤 (하체 반복)"],
	[1, "하체 시간에 상체를 맞춤 (하체 1번)"],
	[2, "상체 시간에 하체를 맞춤 (하체 반복)"],
	[3, "상체 시간에 하체를 맞춤 (하체 1번)"],
]

var _baker: DRBaker
var _anims: PackedStringArray = PackedStringArray()
var _lengths: Dictionary = {}          # 애니 이름 -> 길이(초)
var _parts: PackedStringArray = PackedStringArray()
var _defs: Array = []                   # Array[Dictionary]
var _sel := -1
var _filling := false

var _part_box: VBoxContainer
var _part_checks: Dictionary = {}       # 파트 이름 -> CheckBox
var _list: ItemList
var _name_edit: LineEdit
var _lower_filter: LineEdit
var _lower: OptionButton
var _upper_filter: LineEdit
var _upper: OptionButton
var _len_mode: OptionButton
var _loop: CheckBox
var _keep: HSlider          # 상체 방향 유지 0~100 %
var _keep_lbl: Label
var _pitch: SpinBox         # 몸통 각도 보정(도, + = 뒤로 젖힘)
var _info: Label
var _auto_pick: CheckBox
var _editor_box: VBoxContainer

# 프리뷰
var _pv_tex: TextureRect
var _pv_play: CheckBox
var _pv_speed: OptionButton
var _pv_scrub: HSlider
var _pv_time: Label
var _pv_msg: Label
var _pv_t := 0.0
var _pv_len := 0.0
var _pv_ok := false
var _pv_dirty := false      # 슬라이더·각도 칸이 바뀜 → 다음 프레임에 프리뷰를 다시 만든다


func _init() -> void:
	title = "상하체 합성 — Dot Rigger"
	ok_button_text = "적용"
	add_cancel_button("닫기")
	min_size = Vector2i(1060, 600)
	dialog_hide_on_ok = true
	_build()
	confirmed.connect(_on_confirmed)
	visibility_changed.connect(_on_visibility_changed)
	set_process(false)


func _build() -> void:
	var rootv := VBoxContainer.new()
	add_child(rootv)
	var intro := Label.new()
	intro.text = "하체는 한 동작에서, 상체는 다른 동작에서 가져와 새 동작을 만듭니다 (예: 앉아 걷기 + 소총 조준 = 앉아 걸으며 조준).\n" \
		+ "합성은 3D 뼈대에서 하므로 몸통은 하체의 들썩임을 그대로 따라가고, 만든 동작은 5번 목록에 다른 애니와 똑같이 나타납니다."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# 줄바꿈 라벨은 너비가 안 정해지면 "가장 좁을 때의 높이"를 최소 높이로 내놓아 팝업이 수천 px 로 늘어난다 → 최소 너비를 준다
	intro.custom_minimum_size = Vector2(700, 0)
	intro.add_theme_font_size_override("font_size", 12)
	rootv.add_child(intro)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rootv.add_child(body)

	# ---- 왼쪽: 상체로 칠 파트 ----
	var leftv := VBoxContainer.new()
	leftv.custom_minimum_size = Vector2(170, 0)
	body.add_child(leftv)
	var pl := Label.new()
	pl.text = "상체로 칠 파트"
	leftv.add_child(pl)
	pl.tooltip_text = "체크한 파트의 뼈는 상체 동작에서, 나머지(힙·다리)는 하체 동작에서 가져옵니다.\n기본 = 몸통·머리·두 팔. 모든 합성에 같이 적용됩니다."
	pl.mouse_filter = Control.MOUSE_FILTER_PASS
	var pscroll := ScrollContainer.new()
	pscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	leftv.add_child(pscroll)
	_part_box = VBoxContainer.new()
	_part_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pscroll.add_child(_part_box)
	var pdef := Button.new()
	pdef.text = "기본값 (몸통·머리·팔)"
	pdef.pressed.connect(func():
		_set_upper_parts(PackedStringArray(DRBaker.DEFAULT_UPPER_PARTS))
		_rebuild_preview())
	leftv.add_child(pdef)

	body.add_child(VSeparator.new())

	# ---- 가운데: 합성 목록 + 편집 ----
	var rightv := VBoxContainer.new()
	rightv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(rightv)
	var ll := Label.new()
	ll.text = "합성 동작"
	rightv.add_child(ll)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 130)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_list.item_selected.connect(_on_select)
	rightv.add_child(_list)
	var brow := HBoxContainer.new()
	rightv.add_child(brow)
	for spec in [["추가", "add"], ["복제", "dup"], ["삭제", "del"], ["▲", "up"], ["▼", "down"]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(_on_list_button.bind(spec[1]))
		brow.add_child(b)

	_editor_box = VBoxContainer.new()
	rightv.add_child(_editor_box)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "새 동작 이름 (게임에서 이 이름으로 재생)"
	_name_edit.text_changed.connect(func(_t): _store_fields(false))
	_row("이름", _name_edit, "구운 퍼펫의 AnimationPlayer 에 들어갈 이름. 비우면 `하체+상체` 로 붙습니다.\n모델에 이미 있는 애니 이름과 같으면 만들어지지 않습니다.")
	_lower_filter = LineEdit.new()
	_lower_filter.placeholder_text = "검색"
	_lower_filter.custom_minimum_size = Vector2(90, 0)
	_lower_filter.text_changed.connect(func(_t): _fill_anim_options())
	_lower = OptionButton.new()
	_lower.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_lower.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lower.item_selected.connect(func(_i): _store_fields(true))
	_row2("하체 동작", _lower_filter, _lower, "힙·다리(와 몸 전체의 들썩임)를 가져올 애니. 보통 이동 동작 — Walk, Crouch_Fwd …")
	_upper_filter = LineEdit.new()
	_upper_filter.placeholder_text = "검색"
	_upper_filter.custom_minimum_size = Vector2(90, 0)
	_upper_filter.text_changed.connect(func(_t): _fill_anim_options())
	_upper = OptionButton.new()
	_upper.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_upper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_upper.item_selected.connect(func(_i): _store_fields(true))
	_row2("상체 동작", _upper_filter, _upper, "몸통·머리·팔을 가져올 애니. 보통 무기 동작 — Rifle_Aiming_Idle, Firing_Rifle …")
	_len_mode = OptionButton.new()
	for it in LEN_ITEMS:
		_len_mode.add_item(String(it[1]), int(it[0]))
	_len_mode.item_selected.connect(func(_i): _store_fields(true))
	_row("길이 맞춤", _len_mode, "두 애니의 길이(초)가 다를 때 — **누구의 시간에 맞추나** × **하체를 몇 번 돌리나**.\n" \
		+ "· 하체 시간에 상체를 맞춤 (하체 반복) — 기본. 걸음 속도 그대로. 걸음을 여러 번 넣어 상체 길이와 비슷하게 만들고, 상체를 거기에 조금 맞춥니다.\n" \
		+ "· 하체 시간에 상체를 맞춤 (하체 1번) — 걸음 한 번의 초가 곧 전체 길이. 상체 전체가 그 안에 들어가도록 빨라지거나 느려집니다.\n" \
		+ "· 상체 시간에 하체를 맞춤 (하체 반복) — 사격·장전 속도 그대로. 상체 길이 안에 걸음을 여러 번 넣고, 걸음을 조금 맞춥니다.\n" \
		+ "· 상체 시간에 하체를 맞춤 (하체 1번) — 상체의 초가 곧 전체 길이. 걸음 한 번이 그 길이로 늘어나거나 줄어듭니다.\n" \
		+ "`하체 1번` 은 둘 다 한 번 하고 끝나는 동작(앉기 + 장전 등)을 같이 시작해 같이 끝내고 싶을 때 씁니다.\n" \
		+ "결과는 아래 설명 줄(몇 초 · 속도 몇 배)과 오른쪽 프리뷰에서 바로 확인할 수 있습니다.")
	_loop = CheckBox.new()
	_loop.text = "반복"
	_loop.button_pressed = true
	_loop.toggled.connect(func(_on): _store_fields(true))
	_row("", _loop, "켜면 구운 애니가 반복(loop)됩니다. 한 번 쏘고 끝나는 동작이면 끕니다.")
	# 상체 방향 유지 — 하체가 골반을 숙이는 동작(앉기)일 때 상체가 같이 숙는 것을 막는다
	var keep_tip := "하체 동작이 골반을 앞으로 숙이면(앉기 등) 상체 동작을 그대로 얹어도 몸통이 그만큼 같이 숙습니다 — 뼈의 각도가 부모(골반) 기준이라서.\n" \
		+ "100% = 몸통이 **상체 동작에서 보던 방향 그대로**(바르게 선 Idle 이면 앉아서도 바르게). 0% = 골반이 숙은 만큼 같이 숙음.\n" \
		+ "그 사이 값으로 자연스러운 지점을 고르세요. 걷기처럼 골반이 거의 안 기우는 하체에서는 차이가 작습니다.\n" \
		+ "상체 파트를 팔만 골랐을 때는 팔(총구)의 방향이 유지됩니다."
	var keep_row := HBoxContainer.new()
	_keep = HSlider.new()
	_keep.min_value = 0
	_keep.max_value = 100
	_keep.step = 5
	_keep.value = 100
	_keep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_keep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_keep.tooltip_text = keep_tip
	_keep.value_changed.connect(func(v):
		_keep_lbl.text = "%d%%" % int(v)
		_store_fields(false)
		_pv_dirty = true)             # 슬라이더를 끄는 동안 값이 연달아 바뀐다 — 프리뷰는 프레임당 한 번만 다시 만든다(_process)
	keep_row.add_child(_keep)
	_keep_lbl = Label.new()
	_keep_lbl.text = "100%"
	_keep_lbl.custom_minimum_size = Vector2(44, 0)
	_keep_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keep_row.add_child(_keep_lbl)
	_row("방향 유지", keep_row, keep_tip)
	_pitch = SpinBox.new()
	_pitch.min_value = -60
	_pitch.max_value = 60
	_pitch.step = 1
	_pitch.value = 0
	_pitch.suffix = "°"
	_pitch.value_changed.connect(func(_v):
		_store_fields(false)
		_pv_dirty = true)
	_row("각도 보정", _pitch, "몸통(상체)을 좌우 축으로 더 돌립니다. **+ = 뒤로 젖힘(세움), − = 앞으로 숙임.** 위 `방향 유지` 를 적용한 뒤에 더해집니다.\n" \
		+ "예: 앉아서 조준할 때 살짝 앞으로 −5°, 너무 숙어 보이면 +10°. 동작 내내 같은 각도가 더해집니다.")
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(480, 32)     # 위와 같은 이유 + 두 줄 자리를 미리 잡아 글자 수에 따라 팝업이 들썩이지 않게
	_info.add_theme_font_size_override("font_size", 11)
	_editor_box.add_child(_info)

	body.add_child(VSeparator.new())

	# ---- 오른쪽: 프리뷰(합성 결과를 그 자리에서 재생) ----
	var pvv := VBoxContainer.new()
	pvv.custom_minimum_size = Vector2(300, 0)
	body.add_child(pvv)
	var pvl := Label.new()
	pvl.text = "프리뷰 (고른 합성)"
	pvv.add_child(pvl)
	var pv_panel := PanelContainer.new()
	pv_panel.custom_minimum_size = Vector2(300, 300)
	pv_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pvv.add_child(pv_panel)
	_pv_tex = TextureRect.new()
	_pv_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pv_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pv_tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_pv_tex.tooltip_text = "지금 고른 합성의 결과(3D 도트 렌더, 창의 2번 시점 그대로). 아직 `적용` 하지 않아도 보입니다.\n" \
		+ "하체·상체 동작, 길이 맞춤, 왼쪽의 상체 파트를 바꾸면 바로 다시 만들어집니다."
	pv_panel.add_child(_pv_tex)
	var pvrow := HBoxContainer.new()
	pvv.add_child(pvrow)
	_pv_play = CheckBox.new()
	_pv_play.text = "▶ 재생"
	_pv_play.button_pressed = true
	_pv_play.tooltip_text = "합성 결과를 재생합니다. 끄고 아래 슬라이더로 한 프레임씩 볼 수도 있습니다."
	pvrow.add_child(_pv_play)
	_pv_speed = OptionButton.new()
	for sp in [["×1", 1.0], ["×1/2", 0.5], ["×1/4", 0.25]]:
		_pv_speed.add_item(String(sp[0]))
		_pv_speed.set_item_metadata(_pv_speed.item_count - 1, float(sp[1]))
	_pv_speed.tooltip_text = "재생 속도"
	pvrow.add_child(_pv_speed)
	_pv_time = Label.new()
	_pv_time.text = "0.00 / 0.00s"
	_pv_time.add_theme_font_size_override("font_size", 11)
	pvrow.add_child(_pv_time)
	_pv_scrub = HSlider.new()
	_pv_scrub.min_value = 0.0
	_pv_scrub.max_value = 1.0
	_pv_scrub.step = 0.001
	_pv_scrub.tooltip_text = "재생 위치. 끌면 그 시점의 자세를 봅니다(재생 중이면 거기서부터 이어서)."
	_pv_scrub.value_changed.connect(_on_pv_scrub)
	pvv.add_child(_pv_scrub)
	_pv_msg = Label.new()
	_pv_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pv_msg.custom_minimum_size = Vector2(290, 30)
	_pv_msg.add_theme_font_size_override("font_size", 11)
	pvv.add_child(_pv_msg)

	_auto_pick = CheckBox.new()
	_auto_pick.text = "적용하면 5번 동작 목록에서 합성 동작을 자동으로 고르기"
	_auto_pick.button_pressed = true
	rootv.add_child(_auto_pick)
	_set_editor_enabled(false)


func _row(label_text: String, ctrl: Control, tip: String) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(80, 0)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl.tooltip_text = tip
	h.add_child(ctrl)
	_editor_box.add_child(h)


func _row2(label_text: String, a: Control, b: Control, tip: String) -> void:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(80, 0)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(l)
	a.tooltip_text = "이름 일부를 넣으면 오른쪽 목록이 줄어듭니다"
	h.add_child(a)
	b.tooltip_text = tip
	h.add_child(b)
	_editor_box.add_child(h)


## 창이 팝업을 열 때 부른다. baker = 프리뷰를 그릴 베이커, anims = 합성 재료로 쓸 수 있는 애니(합성으로 만든 것은 빼고), lengths = 이름 -> 초.
func open_with(baker: DRBaker, anims: PackedStringArray, lengths: Dictionary, parts: PackedStringArray, defs: Array, upper_parts: PackedStringArray) -> void:
	_baker = baker
	_anims = anims
	_lengths = lengths
	_parts = parts
	_defs = []
	for d in defs:
		_defs.append((d as Dictionary).duplicate(true))
	_filling = true
	for c in _part_box.get_children():
		c.queue_free()
	_part_checks.clear()
	for p in _parts:
		var cb := CheckBox.new()
		cb.text = String(p)
		cb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cb.toggled.connect(func(_on):
			if not _filling:
				_rebuild_preview())
		_part_box.add_child(cb)
		_part_checks[String(p)] = cb
	_set_upper_parts(upper_parts if upper_parts.size() > 0 else PackedStringArray(DRBaker.DEFAULT_UPPER_PARTS))
	_filling = false
	_lower_filter.text = ""
	_upper_filter.text = ""
	_sel = -1
	_pv_t = 0.0
	if _baker != null and _baker.viewport != null:
		_pv_tex.texture = _baker.viewport.get_texture()
		_baker.show_all_parts()
	_refresh_list()
	if _defs.size() > 0:
		_list.select(0)
		_on_select(0)
	else:
		_set_editor_enabled(false)
		_info.text = "`추가` 를 눌러 첫 합성을 만드세요."
		_rebuild_preview()


func get_defs() -> Array:
	var out: Array = []
	for d in _defs:
		out.append((d as Dictionary).duplicate(true))
	return out


func get_upper_parts() -> PackedStringArray:
	var out := PackedStringArray()
	for p in _parts:
		var cb: CheckBox = _part_checks.get(String(p))
		if cb != null and cb.button_pressed:
			out.append(String(p))
	return out


func _set_upper_parts(parts: PackedStringArray) -> void:
	var was := _filling
	_filling = true
	for p in _part_checks.keys():
		(_part_checks[p] as CheckBox).button_pressed = parts.has(String(p))
	_filling = was


static func auto_name(lower: String, upper: String) -> String:
	return "%s+%s" % [lower, upper]


func _item_text(d: Dictionary) -> String:
	var nm := String(d.get("name", ""))
	if nm == "":
		nm = auto_name(String(d.get("lower", "")), String(d.get("upper", "")))
	return "%s   ←  하체 %s  +  상체 %s" % [nm, d.get("lower", "?"), d.get("upper", "?")]


func _refresh_list() -> void:
	_list.clear()
	for d in _defs:
		_list.add_item(_item_text(d))
	if _sel >= 0 and _sel < _list.item_count:
		_list.select(_sel)


func _set_editor_enabled(on: bool) -> void:
	for c in [_name_edit, _lower_filter, _upper_filter]:
		(c as LineEdit).editable = on
	for c in [_lower, _upper, _len_mode]:
		(c as OptionButton).disabled = not on
	_loop.disabled = not on
	_keep.editable = on
	_pitch.editable = on


func _fill_anim_options() -> void:
	if _sel < 0 or _sel >= _defs.size():
		return
	_filling = true
	var d: Dictionary = _defs[_sel]
	for pair in [[_lower, _lower_filter, String(d.get("lower", ""))], [_upper, _upper_filter, String(d.get("upper", ""))]]:
		var ob: OptionButton = pair[0]
		var f := String((pair[1] as LineEdit).text).to_lower()
		var cur: String = pair[2]
		ob.clear()
		for a in _anims:
			var s := String(a)
			if f == "" or s.to_lower().contains(f) or s == cur:    # 지금 고른 것은 검색에 안 걸려도 남긴다
				ob.add_item(s)
				if s == cur:
					ob.select(ob.item_count - 1)
		if cur != "" and not _anims.has(cur):                      # 모델이 바뀌어 없어진 동작 — 보이게는 한다
			ob.add_item(cur + "  (없음)")
			ob.select(ob.item_count - 1)
	_filling = false


func _on_select(i: int) -> void:
	_sel = i
	if i < 0 or i >= _defs.size():
		_set_editor_enabled(false)
		_rebuild_preview()
		return
	_filling = true
	var d: Dictionary = _defs[i]
	_name_edit.text = String(d.get("name", ""))
	var li := _len_mode.get_item_index(int(d.get("length_mode", 0)))
	_len_mode.select(li if li >= 0 else 0)
	_loop.button_pressed = bool(d.get("loop", true))
	_keep.value = roundf(clampf(float(d.get("upper_keep", 0.0)), 0.0, 1.0) * 100.0)   # 예전 정의(칸이 없던 때)는 0% = 그때 동작 그대로
	_keep_lbl.text = "%d%%" % int(_keep.value)
	_pitch.value = float(d.get("upper_pitch", 0.0))
	_filling = false
	_set_editor_enabled(true)
	_fill_anim_options()
	_update_info()
	_pv_t = 0.0
	_rebuild_preview()


## 편집 칸의 값을 고른 정의에 넣는다. affects_motion = 동작이 달라지는 칸(이름만 바꿨으면 프리뷰를 다시 만들 필요가 없다)
func _store_fields(affects_motion: bool) -> void:
	if _filling or _sel < 0 or _sel >= _defs.size():
		return
	var d: Dictionary = _defs[_sel]
	d["name"] = _name_edit.text.strip_edges()
	if _lower.selected >= 0:
		d["lower"] = _lower.get_item_text(_lower.selected).replace("  (없음)", "")
	if _upper.selected >= 0:
		d["upper"] = _upper.get_item_text(_upper.selected).replace("  (없음)", "")
	d["length_mode"] = _len_mode.get_selected_id()
	d["loop"] = _loop.button_pressed
	d["upper_keep"] = _keep.value / 100.0
	d["upper_pitch"] = _pitch.value
	_defs[_sel] = d
	_list.set_item_text(_sel, _item_text(d))
	_update_info()
	if affects_motion:
		_rebuild_preview()


## 고른 합성이 몇 초짜리가 되는지 미리 보여 준다(DRBaker._make_composite 와 같은 계산)
func _update_info() -> void:
	if _sel < 0 or _sel >= _defs.size():
		_info.text = ""
		return
	var d: Dictionary = _defs[_sel]
	var lo := String(d.get("lower", ""))
	var up := String(d.get("upper", ""))
	if not _lengths.has(lo) or not _lengths.has(up):
		_info.text = "⚠ 하체·상체 동작을 골라 주세요."
		return
	var lo_len := maxf(float(_lengths[lo]), 0.0001)
	var up_len := maxf(float(_lengths[up]), 0.0001)
	var mode := int(d.get("length_mode", 0))
	var n := maxi(1, int(round(up_len / lo_len)))
	var txt := ""
	if mode == DRBaker.LEN_LOWER_SPEED:
		txt = "길이 %.2f초 = 하체 %s %.2f초 × %d번 · 상체 %s %.2f초 → %.2f초로 맞춤(속도 ×%.2f)" % [
			lo_len * n, lo, lo_len, n, up, up_len, lo_len * n, up_len / (lo_len * n)]
	elif mode == DRBaker.LEN_ONCE:
		txt = "길이 %.2f초 = 하체 %s 길이 · 상체 %s %.2f초 → %.2f초로 맞춤(속도 ×%.2f)" % [lo_len, lo, up, up_len, lo_len, up_len / lo_len]
	elif mode == DRBaker.LEN_ONCE_UPPER:
		txt = "길이 %.2f초 = 상체 %s 길이 · 하체 %s %.2f초 → %.2f초로 맞춤(속도 ×%.2f)" % [up_len, up, lo, lo_len, up_len, lo_len / up_len]
	else:
		txt = "길이 %.2f초 = 상체 %s 길이 · 하체 %s %.2f초 × %d번을 그 안에(속도 ×%.2f)" % [up_len, up, lo, lo_len, n, (lo_len * n) / up_len]
	_info.text = txt


func _on_list_button(what: String) -> void:
	match what:
		"add":
			var lo := ""
			var up := ""
			for a in _anims:          # 그럴듯한 첫 값 — 걷기 + 조준
				var s := String(a).to_lower()
				if lo == "" and s.begins_with("walk"):
					lo = String(a)
				if up == "" and (s.contains("aim") or s.contains("rifle") or s.contains("pistol")):
					up = String(a)
			if lo == "" and _anims.size() > 0:
				lo = String(_anims[0])
			if up == "" and _anims.size() > 0:
				up = String(_anims[0])
			# 새 합성은 상체 방향 유지 100% 로 시작한다 — 앉기처럼 골반이 숙는 하체에서도 상체가 바르게 선다
			_defs.append({"name": "", "lower": lo, "upper": up, "length_mode": DRBaker.LEN_LOWER_SPEED, "loop": true,
				"upper_keep": 1.0, "upper_pitch": 0.0})
			_sel = _defs.size() - 1
		"dup":
			if _sel >= 0 and _sel < _defs.size():
				var c: Dictionary = (_defs[_sel] as Dictionary).duplicate(true)
				if String(c.get("name", "")) != "":
					c["name"] = String(c["name"]) + "_2"
				_defs.insert(_sel + 1, c)
				_sel += 1
		"del":
			if _sel >= 0 and _sel < _defs.size():
				_defs.remove_at(_sel)
				_sel = mini(_sel, _defs.size() - 1)
		"up":
			if _sel > 0:
				var t = _defs[_sel - 1]
				_defs[_sel - 1] = _defs[_sel]
				_defs[_sel] = t
				_sel -= 1
		"down":
			if _sel >= 0 and _sel < _defs.size() - 1:
				var t2 = _defs[_sel + 1]
				_defs[_sel + 1] = _defs[_sel]
				_defs[_sel] = t2
				_sel += 1
	_refresh_list()
	_on_select(_sel)
	if _defs.is_empty():
		_info.text = "`추가` 를 눌러 첫 합성을 만드세요."


# ---------------------------------------------------------------- 프리뷰

## 고른 정의로 미리보기 동작을 다시 만든다(숨은 이름 — 목록·세트·베이크와 무관)
func _rebuild_preview() -> void:
	_pv_ok = false
	_pv_len = 0.0
	if _baker == null:
		_pv_msg.text = ""
		return
	if _sel < 0 or _sel >= _defs.size():
		_baker.clear_composite_preview()
		_baker.set_rest_pose()
		_pv_msg.text = "합성을 고르거나 `추가` 하면 여기서 결과가 재생됩니다."
		_update_pv_time()
		return
	var r: Dictionary = _baker.make_composite_preview(_defs[_sel], get_upper_parts())
	if not bool(r.get("ok", false)):
		_baker.set_rest_pose()
		_pv_msg.text = "⚠ " + String(r.get("warning", "만들 수 없음"))
		_update_pv_time()
		return
	_pv_ok = true
	_pv_len = maxf(float(r["length"]), 0.0001)
	_pv_t = fposmod(_pv_t, _pv_len)
	_pv_msg.text = "하체 %d번 · %.2f초 — 아직 `적용` 전입니다(이 팝업 안에서만 보임)." % [int(r["lower_cycles"]), _pv_len]
	_baker.show_all_parts()
	_apply_pv_pose()


func _apply_pv_pose() -> void:
	if not _pv_ok or _baker == null:
		return
	_baker.set_pose(DRBaker.PREVIEW_ANIM, _pv_t)
	_update_pv_time()


func _update_pv_time() -> void:
	_pv_time.text = "%.2f / %.2fs" % [_pv_t if _pv_ok else 0.0, _pv_len]
	_pv_scrub.set_value_no_signal((_pv_t / _pv_len) if (_pv_ok and _pv_len > 0.0) else 0.0)


func _on_pv_scrub(v: float) -> void:
	if not _pv_ok:
		return
	_pv_t = clampf(v, 0.0, 1.0) * _pv_len
	_apply_pv_pose()


func _process(delta: float) -> void:
	if not visible or _baker == null:
		return
	if _pv_dirty:
		_pv_dirty = false
		_rebuild_preview()
	if not _pv_ok or not _pv_play.button_pressed:
		return
	var sp := 1.0
	if _pv_speed.selected >= 0:
		sp = float(_pv_speed.get_item_metadata(_pv_speed.selected))
	_pv_t = fposmod(_pv_t + delta * sp, _pv_len)
	_apply_pv_pose()


func _on_visibility_changed() -> void:
	if visible:
		set_process(true)
		return
	set_process(false)
	_pv_ok = false
	if _baker != null:
		_baker.clear_composite_preview()
	closed.emit()


func _on_confirmed() -> void:
	applied.emit(get_defs(), get_upper_parts(), _auto_pick.button_pressed)
