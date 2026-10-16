@tool
extends VBoxContainer
class_name DRMotionTableEditor

## 동작 표(DRMotionTable) 편집 화면(10-16) — 인스펙터에서 표를 열 때와 Dot Rigger ① 유닛 탭에 같은 화면이 들어간다.
## 사용자 요청: "한 상태에 동작 여러 개를 넣으면 그중 하나를 골라 틀고, 목록 옆에 % 를 넣어 33 · 33 · 33 을 20 · 40 · 40 처럼 조정 ·
## 상하체 합성은 살려서" · "세트는 자세별 묶음(서기 / 앉기 / 엎드림), 나중에 장비가 오면 설치 / 조작 같은 묶음".
##   - 세트(DRMotionSet) → 상태 → 줄(DRMotionClip): 동작 고르기 · 비중 막대 · 비중 % · 지우기. 한 줄의 % 를 바꾸면 나머지가 비율을 지킨 채 합 100
##   - [+ 동작] 새 줄 = 100/n %(기존 줄은 비율대로 줄어듦) · [+ 상하체 합성] 하체 + 상체(길이 맞춤 · 반복 · 상체 방향 유지 · 몸통 각도) · [균등]
##   - 세트: 상태 추가(그 세트의 빈 상태 또는 새 이름) · 이름 바꾸기 · 지우기 · [+ 세트] · 상태를 다른 세트로 옮기기
##   - 위: [3D 동작 내보내기](저장 → 이 표로 DRMotionExporter) · [저장] · [동작 목록 다시 읽기] · 안 내보낸 동작 알림
##   - 고칠 때마다 되돌리기(Ctrl+Z) 한 칸 — 기록은 표(리소스)의 snapshot / restore_snapshot(이 화면은 인스펙터가 다시 만들면 사라지므로)
## 인스펙터 연결 = ui/motion_table_inspector.gd(plugin.gd 가 등록). 에디터 밖(명령줄 검사)에서는 되돌리기 없이 바로 고친다.

const COL_WARN := Color(1.0, 0.5, 0.4)
const COL_DIM := Color(0.68, 0.7, 0.72)
const COL_HEAD := Color(0.62, 0.8, 1.0)
const COL_SET := Color(0.95, 0.82, 0.5)
const PCT_W := 78.0
const BAR_W := 46.0
const NO_SET := "(세트 없음)"

## 동작 목록 캐시 {"model": 모델 자체 동작, "extra": 추가 동작 폴더} — 처음 한 번 읽고 [동작 목록 다시 읽기] 로 비운다
static var _names_cache: Dictionary = {}
## 펼친 세트 · 상태 "표 경로|키" -> bool(인스펙터가 화면을 다시 만들어도 유지)
static var _open: Dictionary = {}

## 고칠 표. 바꾸면 set_table() 로
var table: DRMotionTable

var _list: VBoxContainer
var _status: Label
var _lib_note: Label
var _show_empty: CheckBox
var _new_set: LineEdit
var _rebuild_queued := false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_shell()
	set_table(table)


func _exit_tree() -> void:
	if table != null and table.changed.is_connected(_queue_rebuild):
		table.changed.disconnect(_queue_rebuild)


## 다른 표로 바꾼다(① 유닛 탭이 유닛을 고를 때)
func set_table(t: DRMotionTable) -> void:
	if table != null and table.changed.is_connected(_queue_rebuild):
		table.changed.disconnect(_queue_rebuild)
	table = t
	if table != null and not table.changed.is_connected(_queue_rebuild):
		table.changed.connect(_queue_rebuild)
	if _list != null:
		_rebuild()


# ───────────── 틀 ─────────────

func _build_shell() -> void:
	var title := Label.new()
	title.text = "동작 표 — 세트 · 상태마다 동작 여러 개 · 비중(%)"
	title.add_theme_color_override("font_color", COL_HEAD)
	add_child(title)
	var hint := Label.new()
	hint.text = "그 상태가 되면 비중대로 하나를 골라 튼다(반복 동작은 한 바퀴마다 다시). % 를 바꾸면 나머지가 비율대로 맞춰진다. 세트는 정리용 묶음."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", COL_DIM)
	hint.add_theme_font_size_override("font_size", 12)
	add_child(hint)

	var bar := HFlowContainer.new()
	add_child(bar)
	var exp := Button.new()
	exp.text = "3D 동작 내보내기"
	exp.tooltip_text = "표를 저장하고, 표의 동작(상하체 합성 포함)을 2D 굽기와 같은 처리로 3D 동작 묶음(library_path)에 내보낸다. 몇 초 걸린다."
	exp.pressed.connect(_on_export)
	bar.add_child(exp)
	var save := Button.new()
	save.text = "저장"
	save.tooltip_text = "이 표(.tres)를 저장"
	save.pressed.connect(_on_save)
	bar.add_child(save)
	var reload := Button.new()
	reload.text = "동작 목록 다시 읽기"
	reload.tooltip_text = "고를 수 있는 동작 이름(프리셋 모델의 동작 + 추가 동작 폴더의 파일)을 다시 읽는다 — Mixamo 동작을 새로 넣은 뒤"
	reload.pressed.connect(func() -> void:
		_names_cache = {}
		_rebuild())
	bar.add_child(reload)
	_show_empty = CheckBox.new()
	_show_empty.text = "빈 상태도 보기"
	_show_empty.tooltip_text = "동작이 없는 상태(덜 구체적인 상태로 내려가는 것)까지 다 보이기"
	_show_empty.toggled.connect(func(_on: bool) -> void: _rebuild())
	bar.add_child(_show_empty)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", COL_DIM)
	add_child(_status)
	_lib_note = Label.new()
	_lib_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lib_note.add_theme_font_size_override("font_size", 12)
	add_child(_lib_note)
	add_child(HSeparator.new())
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_list)

	var add_row := HBoxContainer.new()
	add_child(add_row)
	_new_set = LineEdit.new()
	_new_set.placeholder_text = "새 세트 이름(예: 설치 · 조작)"
	_new_set.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_set.text_submitted.connect(func(_t: String) -> void: _on_add_set())
	add_row.add_child(_new_set)
	var add_set := Button.new()
	add_set.text = "+ 세트"
	add_set.tooltip_text = "상태 묶음을 하나 더 만든다(장비가 생기면 설치 · 조작처럼)"
	add_set.pressed.connect(_on_add_set)
	add_row.add_child(add_set)


func _queue_rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


# ───────────── 다시 그리기 ─────────────

func _rebuild() -> void:
	_rebuild_queued = false
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	if table == null:
		_status.text = "표가 없습니다"
		_lib_note.text = ""
		return
	var names := _names()
	var all_names := PackedStringArray(names["extra"]) + PackedStringArray(names["model"])
	var used := 0
	var lines := 0
	var in_sets := {}
	for s in table.effective_sets():
		_list.add_child(_set_block(s.name, s.states, names, all_names))
		for st in s.states:
			in_sets[st] = true
	# 어느 세트에도 없는 상태(줄이 있는 것만)
	var loose := PackedStringArray()
	for c in table.clips:
		if c != null and not in_sets.has(c.state) and not loose.has(c.state):
			loose.append(c.state)
	if not loose.is_empty():
		_list.add_child(_set_block(NO_SET, loose, names, all_names))
	for c in table.clips:
		if c != null:
			lines += 1
	var seen := {}
	for c in table.clips:
		if c != null and not seen.has(c.state):
			seen[c.state] = true
			used += 1
	_status.text = "세트 %d개 · 상태 %d개에 줄 %d개 · 고를 수 있는 동작: 추가 동작 %d · 모델 %d (프리셋 %s)" % [table.effective_sets().size(),
		used, lines, (names["extra"] as PackedStringArray).size(), (names["model"] as PackedStringArray).size(), DRMotionExporter.DEFAULT_PRESET.get_file()]
	_update_lib_note()


## 3D 동작 묶음에 아직 없는 이름(= 다시 내보내야 함) 알림
func _update_lib_note() -> void:
	var path := table.library_path
	if path == "":
		_lib_note.text = "3D 동작 묶음 경로(library_path)가 비어 있음 — 내보내면 %s 에 저장" % DRMotionExporter.DEFAULT_OUT
		_lib_note.add_theme_color_override("font_color", COL_DIM)
		return
	if not ResourceLoader.exists(path):
		_lib_note.text = "⚠ 3D 동작 묶음이 아직 없음: %s — [3D 동작 내보내기]" % path
		_lib_note.add_theme_color_override("font_color", COL_WARN)
		return
	var lib := load(path) as AnimationLibrary
	var have := PackedStringArray()
	if lib != null:
		for n in lib.get_animation_list():
			have.append(String(n))
	var miss := PackedStringArray()
	for n in table.motion_names():
		if not have.has(n):
			miss.append(n)
	if miss.is_empty():
		_lib_note.text = "3D 동작 묶음 %s — 표의 동작이 다 들어 있음(동작 %d개)" % [path.get_file(), have.size()]
		_lib_note.add_theme_color_override("font_color", COL_DIM)
	else:
		_lib_note.text = "⚠ 3D 동작 묶음에 아직 없는 동작 %d개: %s — [3D 동작 내보내기] 를 누르세요" % [miss.size(), ", ".join(miss)]
		_lib_note.add_theme_color_override("font_color", COL_WARN)


func _open_key(k: String) -> String:
	return "%s|%s" % [table.resource_path, k]


func _set_block(set_name: String, states: PackedStringArray, names: Dictionary, all_names: PackedStringArray) -> Control:
	var box := VBoxContainer.new()
	var head := HBoxContainer.new()
	box.add_child(head)
	var key := "set:" + set_name
	var open := bool(_open.get(_open_key(key), true))
	var tog := Button.new()
	tog.flat = true
	tog.alignment = HORIZONTAL_ALIGNMENT_LEFT
	tog.add_theme_color_override("font_color", COL_SET)
	var with_clips := 0
	for st in states:
		if not table.clips_of(st).is_empty():
			with_clips += 1
	tog.text = "%s 세트 · %s   (상태 %d개 채움)" % ["▾" if open else "▸", set_name, with_clips]
	tog.tooltip_text = "세트 펼치기 / 접기"
	tog.pressed.connect(func() -> void:
		_open[_open_key(key)] = not bool(_open.get(_open_key(key), true))
		_rebuild())
	head.add_child(tog)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	if set_name != NO_SET:
		var ren := Button.new()
		ren.text = "이름"
		ren.flat = true
		ren.tooltip_text = "이 세트 이름 바꾸기(아래 새 세트 칸에 적은 이름으로)"
		ren.pressed.connect(func() -> void:
			var nn := _new_set.text.strip_edges()
			if nn == "":
				_status.text = "아래 '새 세트 이름' 칸에 바꿀 이름을 적고 [이름] 을 누르세요"
				return
			_rename_set(set_name, nn)
			_new_set.text = "")
		head.add_child(ren)
		var del := Button.new()
		del.text = "✕"
		del.flat = true
		del.tooltip_text = "세트 지우기 — 안의 상태 · 줄은 그대로(세트 없음으로)"
		del.pressed.connect(_delete_set.bind(set_name))
		head.add_child(del)
	if not open:
		return box
	var rows := VBoxContainer.new()
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 12)
	m.add_child(rows)
	box.add_child(m)
	var empties := PackedStringArray()
	for st in states:
		var cl := table.clips_of(st)
		if cl.is_empty():
			empties.append(st)
			if not _show_empty.button_pressed:
				continue
		rows.add_child(_state_block(st, cl, names, all_names))
	if set_name != NO_SET:
		rows.add_child(_add_state_row(set_name, empties))
	return box


## 세트 안 "상태 추가" 줄 — 그 세트의 빈 상태를 고르거나, 새 이름(장비 상태 등)을 적는다
func _add_state_row(set_name: String, empties: PackedStringArray) -> Control:
	var row := HBoxContainer.new()
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.fit_to_longest_item = false
	ob.clip_text = true
	for st in empties:
		ob.add_item(st)
	if empties.is_empty():
		ob.add_item("(빈 상태 없음)")
		ob.disabled = true
	row.add_child(ob)
	var custom := LineEdit.new()
	custom.placeholder_text = "새 상태 이름"
	custom.custom_minimum_size = Vector2(110, 0)
	custom.tooltip_text = "게임이 아직 모르는 상태(장비의 설치 · 조작 등)를 미리 적어 둘 때. 비우면 왼쪽 목록에서"
	row.add_child(custom)
	var add := Button.new()
	add.text = "+ 상태"
	add.tooltip_text = "이 세트에 상태를 넣고 동작 한 줄을 만든다"
	add.pressed.connect(func() -> void:
		var st := custom.text.strip_edges()
		if st == "" and not empties.is_empty() and ob.selected >= 0:
			st = ob.get_item_text(ob.selected)
		if st == "":
			return
		_open[_open_key("state:" + st)] = true
		_add_clip(st, false, set_name))
	row.add_child(add)
	return row


func _state_block(st: String, cl: Array[DRMotionClip], names: Dictionary, all_names: PackedStringArray) -> Control:
	var box := VBoxContainer.new()
	var head := HBoxContainer.new()
	box.add_child(head)
	var key := "state:" + st
	var open := bool(_open.get(_open_key(key), false))
	var tog := Button.new()
	tog.flat = true
	tog.text = ("▾ " if open else "▸ ") + st
	tog.alignment = HORIZONTAL_ALIGNMENT_LEFT
	tog.tooltip_text = "펼치기 / 접기"
	tog.pressed.connect(func() -> void:
		_open[_open_key(key)] = not bool(_open.get(_open_key(key), false))
		_rebuild())
	head.add_child(tog)
	var sum := Label.new()
	sum.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sum.clip_text = true
	sum.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sum.add_theme_color_override("font_color", COL_DIM)
	var parts := PackedStringArray()
	var bad := false
	for c in cl:
		parts.append("%s %s" % [_clip_label(c), _pct_text(c.weight)])
		bad = bad or not _clip_ok(c, all_names)
	sum.text = " · ".join(parts) if not parts.is_empty() else "(비어 있음 — 덜 구체적인 상태로 내려감)"
	if bad:
		sum.add_theme_color_override("font_color", COL_WARN)
	if not _state_known(st):
		sum.text = "⚠ 게임이 아직 모르는 상태 · " + sum.text
		sum.add_theme_color_override("font_color", COL_WARN)
	head.add_child(sum)
	if not open:
		return box
	var rows := VBoxContainer.new()
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_child(rows)
	box.add_child(m)
	for c in cl:
		rows.add_child(_clip_row(st, c, cl.size(), names, all_names))
	var btns := HFlowContainer.new()
	rows.add_child(btns)
	var b1 := Button.new()
	b1.text = "+ 동작"
	b1.tooltip_text = "이 상태에 동작 한 줄 더(새 줄 = 100/n %, 기존 줄은 비율대로 줄어듦)"
	b1.pressed.connect(_add_clip.bind(st, false, ""))
	btns.add_child(b1)
	var b2 := Button.new()
	b2.text = "+ 상하체 합성"
	b2.tooltip_text = "하체 동작 + 상체 동작을 합친 줄(3D 동작 내보내기 때 2D 굽기와 같은 처리로 한 동작으로 굽는다)"
	b2.pressed.connect(_add_clip.bind(st, true, ""))
	btns.add_child(b2)
	if cl.size() > 1:
		var b3 := Button.new()
		b3.text = "균등"
		b3.tooltip_text = "이 상태의 줄들을 똑같이 나눔"
		b3.pressed.connect(_equalize.bind(st))
		btns.add_child(b3)
	var mv := OptionButton.new()
	mv.tooltip_text = "이 상태를 다른 세트로 옮기기"
	var cur := table.set_of(st)
	mv.add_item("세트: " + (cur if cur != "" else NO_SET))
	mv.set_item_metadata(0, cur)
	for s in table.effective_sets():
		if s.name != cur:
			mv.add_item("→ " + s.name)
			mv.set_item_metadata(mv.item_count - 1, s.name)
	mv.select(0)
	mv.item_selected.connect(func(i: int) -> void:
		if i > 0:
			_move_state(st, String(mv.get_item_metadata(i))))
	btns.add_child(mv)
	return box


## 상태 이름을 게임이 아는지 — 게임의 표가 all_keys() 를 주면 그것으로, 아니면 다 안다고 본다(애드온이 게임 클래스에 묶이지 않게)
func _state_known(st: String) -> bool:
	if table.has_method("all_keys"):
		var keys: PackedStringArray = table.call("all_keys")
		return keys.has(st)
	return true


func _clip_row(st: String, c: DRMotionClip, n: int, names: Dictionary, all_names: PackedStringArray) -> Control:
	var idx := table.clips.find(c)
	var is_comp := c.is_composite() or (c.anim == "" and (c.lower != "" or c.upper != ""))
	var box := VBoxContainer.new()
	var top := HBoxContainer.new()
	box.add_child(top)
	if is_comp:
		var lab := Label.new()
		lab.text = "합성"
		lab.tooltip_text = "상하체 합성 — 하체(골반 · 다리) + 상체(몸통 · 머리 · 팔)"
		lab.add_theme_color_override("font_color", COL_HEAD)
		top.add_child(lab)
		var nm := Label.new()
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		nm.text = ("→ " + c.play_name()) if c.play_name() != "" else "→ (하체 · 상체를 고르세요)"
		nm.add_theme_color_override("font_color", COL_DIM)
		top.add_child(nm)
	else:
		var ob := _anim_picker(c.anim, names, all_names)
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.item_selected.connect(func(i: int) -> void: _set_field(idx, "anim", ob.get_item_metadata(i)))
		top.add_child(ob)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(BAR_W, 0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = c.weight
	bar.tooltip_text = "이 상태 안에서 이 동작이 나올 확률"
	top.add_child(bar)
	var sp := SpinBox.new()
	sp.custom_minimum_size = Vector2(PCT_W, 0)
	sp.min_value = 0.0
	sp.max_value = 100.0
	sp.step = 0.1
	sp.custom_arrow_step = 1.0
	sp.suffix = "%"
	sp.select_all_on_focus = true
	sp.set_value_no_signal(c.weight)
	sp.editable = n > 1
	sp.tooltip_text = "비중(%) — 바꾸면 이 상태의 나머지 줄이 비율을 지킨 채 합 100 이 되게 맞춰진다" if n > 1 else "줄이 하나면 늘 100 %"
	sp.value_changed.connect(func(v: float) -> void: _set_weight(st, idx, v))
	top.add_child(sp)
	var del := Button.new()
	del.text = "✕"
	del.flat = true
	del.tooltip_text = "이 줄 지우기(나머지 줄이 비율대로 늘어남)"
	del.pressed.connect(_remove_clip.bind(idx))
	top.add_child(del)
	if not _clip_ok(c, all_names):
		var w := Label.new()
		w.text = "⚠ 고를 수 있는 동작 목록에 없음(오타 · 아직 가져오기 안 됨) — 내보내기에서 빠진다"
		w.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		w.add_theme_font_size_override("font_size", 12)
		w.add_theme_color_override("font_color", COL_WARN)
		box.add_child(w)
	if is_comp:
		box.add_child(_composite_rows(idx, c, names, all_names))
	return box


func _composite_rows(idx: int, c: DRMotionClip, names: Dictionary, all_names: PackedStringArray) -> Control:
	var g := GridContainer.new()
	g.columns = 2
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var add_pair := func(label: String, tip: String, ctl: Control) -> void:
		var l := Label.new()
		l.text = label
		l.tooltip_text = tip
		l.add_theme_font_size_override("font_size", 12)
		g.add_child(l)
		ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ctl.tooltip_text = tip
		g.add_child(ctl)
	var lo := _anim_picker(c.lower, names, all_names)
	lo.item_selected.connect(func(i: int) -> void: _set_field(idx, "lower", lo.get_item_metadata(i)))
	add_pair.call("하체", "골반 · 다리를 가져올 동작(걷기 · 앉기 등)", lo)
	var up := _anim_picker(c.upper, names, all_names)
	up.item_selected.connect(func(i: int) -> void: _set_field(idx, "upper", up.get_item_metadata(i)))
	add_pair.call("상체", "몸통 · 머리 · 팔을 가져올 동작(사격 · 조준 등)", up)
	var ln := OptionButton.new()
	for i in DRMotionClip.LEN_NAMES.size():
		ln.add_item(DRMotionClip.LEN_NAMES[i], i)
	ln.select(clampi(c.length_mode, 0, DRMotionClip.LEN_NAMES.size() - 1))
	ln.item_selected.connect(func(i: int) -> void: _set_field(idx, "length_mode", i))
	add_pair.call("길이", "길이가 다른 두 동작을 맞추는 법(2D 합성과 같음)", ln)
	var lp := CheckBox.new()
	lp.text = "반복"
	lp.button_pressed = c.loop
	lp.toggled.connect(func(on: bool) -> void: _set_field(idx, "loop", on))
	add_pair.call("반복", "합성 동작을 반복 재생", lp)
	var kp := SpinBox.new()
	kp.min_value = 0.0
	kp.max_value = 1.0
	kp.step = 0.05
	kp.set_value_no_signal(c.upper_keep)
	kp.value_changed.connect(func(v: float) -> void: _set_field(idx, "upper_keep", v))
	add_pair.call("상체 방향 유지", "1 이면 골반이 숙어도 몸통이 상체 동작에서와 같은 쪽을 본다(앉아 쏘기에서 총구가 숙지 않게)", kp)
	var pt := SpinBox.new()
	pt.min_value = -90.0
	pt.max_value = 90.0
	pt.step = 0.5
	pt.suffix = "°"
	pt.set_value_no_signal(c.upper_pitch)
	pt.value_changed.connect(func(v: float) -> void: _set_field(idx, "upper_pitch", v))
	add_pair.call("몸통 각도", "몸통을 더 젖히거나(+) 숙인다(−)", pt)
	var nm := LineEdit.new()
	nm.placeholder_text = "(비우면 하체+상체)"
	nm.text = c.composite_name
	nm.text_submitted.connect(func(t: String) -> void: _set_field(idx, "composite_name", t.strip_edges()))
	nm.focus_exited.connect(func() -> void:
		if nm.text.strip_edges() != c.composite_name:
			_set_field(idx, "composite_name", nm.text.strip_edges()))
	add_pair.call("이름", "합성 동작 이름 — 같은 하체 · 상체를 다른 설정으로 두 번 쓸 때만 바꾼다", nm)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_child(g)
	return m


## 동작 고르기 목록 — 추가 동작(Mixamo) 먼저, 모델 자체 동작(UAL) 다음. 목록에 없는 지금 값은 ⚠ 를 붙여 맨 위에 둔다(값을 잃지 않게)
func _anim_picker(cur: String, names: Dictionary, all_names: PackedStringArray) -> OptionButton:
	var ob := OptionButton.new()
	ob.fit_to_longest_item = false
	ob.clip_text = true
	var sel := -1
	if cur == "":
		ob.add_item("(동작 고르기)")
		ob.set_item_metadata(ob.item_count - 1, "")
		sel = 0
	elif not all_names.has(cur):
		ob.add_item("⚠ " + cur)
		ob.set_item_metadata(ob.item_count - 1, cur)
		sel = 0
	for group in [["extra", "추가 동작(Mixamo 등)"], ["model", "모델 동작(UAL)"]]:
		var list: PackedStringArray = names[group[0]]
		if list.is_empty():
			continue
		ob.add_separator(String(group[1]))
		for n in list:
			ob.add_item(n)
			ob.set_item_metadata(ob.item_count - 1, n)
			if n == cur and sel < 0:
				sel = ob.item_count - 1
	if sel >= 0:
		ob.select(sel)
	return ob


func _clip_label(c: DRMotionClip) -> String:
	if c.is_composite():
		return "[%s]" % c.play_name()
	return c.anim if c.anim != "" else "(빈 줄)"


func _clip_ok(c: DRMotionClip, all_names: PackedStringArray) -> bool:
	if all_names.is_empty():
		return true                  # 목록을 못 읽었으면 판단 안 함
	if c.is_composite():
		return all_names.has(c.lower) and all_names.has(c.upper)
	return c.anim == "" or all_names.has(c.anim)


static func _pct_text(w: float) -> String:
	return ("%d%%" % roundi(w)) if absf(w - roundf(w)) < 0.05 else ("%.1f%%" % w)


# ───────────── 고치기(되돌리기 한 칸씩) — 모두 표의 snapshot 을 고친 값으로 ─────────────

func _set_field(idx: int, field: String, value: Variant) -> void:
	var snap := table.snapshot()
	var cl: Array = snap["clips"]
	if idx < 0 or idx >= cl.size():
		return
	(cl[idx] as Dictionary)[field] = value
	_commit("동작 표: %s 바꾸기" % field, snap)


func _set_weight(st: String, idx: int, value: float) -> void:
	var snap := table.snapshot()
	var cl: Array = snap["clips"]
	var ids := _state_ids(cl, st)
	var at := ids.find(idx)
	if at < 0:
		return
	var ws := PackedFloat32Array()
	for i in ids:
		ws.append(float((cl[i] as Dictionary)["weight"]))
	ws = DRMotionTable.rebalance(ws, at, value)
	for k in ids.size():
		(cl[ids[k]] as Dictionary)["weight"] = ws[k]
	_commit("동작 표: %s 비중" % st, snap)


## 그 상태에 줄 하나(새 줄 = 100/n %). into_set 이 있으면 그 상태를 그 세트에 넣는다(다른 세트에서 빼고)
func _add_clip(st: String, composite: bool, into_set: String = "") -> void:
	var snap := table.snapshot()
	var cl: Array = snap["clips"]
	var ids := _state_ids(cl, st)
	var ws := PackedFloat32Array()
	for i in ids:
		ws.append(float((cl[i] as Dictionary)["weight"]))
	ws = DRMotionTable.with_added(ws)
	for k in ids.size():
		(cl[ids[k]] as Dictionary)["weight"] = ws[k]
	var c := DRMotionClip.new()
	c.state = st
	c.weight = ws[ws.size() - 1]
	var d := c.to_dict()
	if composite:
		d["lower"] = _first_existing(["Crouch_Idle", "Idle"])
		d["upper"] = ""
	var insert_at := (ids[ids.size() - 1] + 1) if not ids.is_empty() else cl.size()
	cl.insert(insert_at, d)
	if into_set != "":
		_put_state(snap["sets"], st, into_set)
	_open[_open_key("state:" + st)] = true
	_commit("동작 표: %s 에 %s 더하기" % [st, "합성" if composite else "동작"], snap)


func _remove_clip(idx: int) -> void:
	var snap := table.snapshot()
	var cl: Array = snap["clips"]
	if idx < 0 or idx >= cl.size():
		return
	var st := String((cl[idx] as Dictionary)["state"])
	var ids := _state_ids(cl, st)
	var at := ids.find(idx)
	var ws := PackedFloat32Array()
	for i in ids:
		ws.append(float((cl[i] as Dictionary)["weight"]))
	ws = DRMotionTable.without(ws, at)
	var k := 0
	for i in ids:
		if i == idx:
			continue
		(cl[i] as Dictionary)["weight"] = ws[k]
		k += 1
	cl.remove_at(idx)
	_commit("동작 표: %s 줄 지우기" % st, snap)


func _equalize(st: String) -> void:
	var snap := table.snapshot()
	var cl: Array = snap["clips"]
	var ids := _state_ids(cl, st)
	var ws := DRMotionTable.equalized(ids.size())
	for k in ids.size():
		(cl[ids[k]] as Dictionary)["weight"] = ws[k]
	_commit("동작 표: %s 균등" % st, snap)


func _move_state(st: String, to_set: String) -> void:
	var snap := table.snapshot()
	_put_state(snap["sets"], st, to_set)
	_commit("동작 표: %s → 세트 %s" % [st, to_set], snap)


func _on_add_set() -> void:
	var nn := _new_set.text.strip_edges()
	if nn == "":
		_status.text = "새 세트 이름을 적으세요"
		return
	var snap := table.snapshot()
	for s in (snap["sets"] as Array):
		if String((s as Dictionary)["name"]) == nn:
			_status.text = "같은 이름의 세트가 있습니다: " + nn
			return
	(snap["sets"] as Array).append({"name": nn, "states": []})
	_new_set.text = ""
	_open[_open_key("set:" + nn)] = true
	_commit("동작 표: 세트 %s 더하기" % nn, snap)


func _rename_set(old: String, nn: String) -> void:
	var snap := table.snapshot()
	for s in (snap["sets"] as Array):
		if String((s as Dictionary)["name"]) == nn:
			_status.text = "같은 이름의 세트가 있습니다: " + nn
			return
	for s in (snap["sets"] as Array):
		if String((s as Dictionary)["name"]) == old:
			(s as Dictionary)["name"] = nn
	_commit("동작 표: 세트 이름 %s → %s" % [old, nn], snap)


func _delete_set(set_name: String) -> void:
	var snap := table.snapshot()
	var ss: Array = snap["sets"]
	for i in range(ss.size() - 1, -1, -1):
		if String((ss[i] as Dictionary)["name"]) == set_name:
			ss.remove_at(i)
	_commit("동작 표: 세트 %s 지우기" % set_name, snap)


## 세트 목록(사전)에서 그 상태를 다른 세트에서 빼고 to_set 에 넣는다
static func _put_state(sets: Array, st: String, to_set: String) -> void:
	for s in sets:
		var arr: Array = (s as Dictionary)["states"]
		arr.erase(st)
		(s as Dictionary)["states"] = arr
	for s in sets:
		if String((s as Dictionary)["name"]) == to_set:
			var arr: Array = (s as Dictionary)["states"]
			arr.append(st)
			(s as Dictionary)["states"] = arr


func _state_ids(cl: Array, st: String) -> Array[int]:
	var out: Array[int] = []
	for i in cl.size():
		if String((cl[i] as Dictionary)["state"]) == st:
			out.append(i)
	return out


func _first_existing(cands: Array) -> String:
	var names := _names()
	var all := PackedStringArray(names["extra"]) + PackedStringArray(names["model"])
	for n in cands:
		if all.has(String(n)):
			return String(n)
	return ""


## 고침 한 칸 — 에디터면 되돌리기 기록(표의 snapshot / restore_snapshot), 아니면 바로
func _commit(action: String, after: Dictionary) -> void:
	var before := table.snapshot()
	if Engine.is_editor_hint() and is_inside_tree():
		var ur := EditorInterface.get_editor_undo_redo()
		ur.create_action(action, UndoRedo.MERGE_DISABLE, table)
		ur.add_do_method(table, "restore_snapshot", after)
		ur.add_undo_method(table, "restore_snapshot", before)
		ur.commit_action()
	else:
		table.restore_snapshot(after)


# ───────────── 버튼 ─────────────

func _on_save() -> void:
	if table.resource_path == "" or table.resource_path.contains("::"):
		_status.text = "이 표는 다른 리소스 안에 들어 있어(내장) — 그 리소스를 저장하세요"
		return
	var err := ResourceSaver.save(table, table.resource_path)
	_status.text = ("저장함: %s" % table.resource_path) if err == OK else ("저장 실패(%s)" % error_string(err))


func _on_export() -> void:
	if table.resource_path != "" and not table.resource_path.contains("::"):
		ResourceSaver.save(table, table.resource_path)
	var ex := DRMotionExporter.new()
	ex.table = table
	ex.table_path = table.resource_path
	var host: Node = EditorInterface.get_base_control() if Engine.is_editor_hint() else get_tree().root
	var t0 := Time.get_ticks_msec()
	var res := ex.run(host)
	var lines := PackedStringArray()
	if bool(res.get("ok", false)):
		lines.append("동작 %d개 → %s  (%.0f KB, %.1f 초)" % [ex.motions.size(), ex.out_path, float(ex.file_size) / 1024.0,
			float(Time.get_ticks_msec() - t0) / 1000.0])
		if table.library_path == "":
			table.library_path = ex.out_path
	else:
		lines.append("내보내기 실패")
	for m in ex.missing:
		lines.append("✗ 없는 동작: " + m)
	for w in ex.warnings:
		lines.append("⚠ " + w)
	ex.cleanup()
	print("[Dot Rigger] 3D 동작 내보내기(동작 표)\n" + "\n".join(lines))
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
		var dlg := AcceptDialog.new()
		dlg.title = "3D 동작 내보내기"
		dlg.dialog_text = "\n".join(lines)
		dlg.confirmed.connect(dlg.queue_free)
		dlg.canceled.connect(dlg.queue_free)
		EditorInterface.popup_dialog_centered(dlg)
	_status.text = lines[0]
	_update_lib_note()
	exported.emit()


## 3D 동작 내보내기가 끝났을 때(① 유닛 탭이 미리보기 동작 묶음을 다시 읽는다)
signal exported


# ───────────── 고를 수 있는 동작 이름 ─────────────

## {"model": 프리셋 모델의 동작, "extra": 추가 동작 폴더의 파일(파일 이름 = 동작 이름 — DRBaker 와 같은 규칙)} — 캐시
static func _names() -> Dictionary:
	if not _names_cache.is_empty():
		return _names_cache
	var model := PackedStringArray()
	var extra := PackedStringArray()
	var preset := load(DRMotionExporter.DEFAULT_PRESET) as DRPreset if ResourceLoader.exists(DRMotionExporter.DEFAULT_PRESET) else null
	if preset != null:
		var ps := load(preset.model_path) as PackedScene if ResourceLoader.exists(preset.model_path) else null
		if ps != null:
			var inst := ps.instantiate()
			var ap := DRBaker._find_node(inst, "AnimationPlayer") as AnimationPlayer
			if ap != null:
				for n in ap.get_animation_list():
					if String(n) != "RESET":
						model.append(String(n))
			inst.free()
		var dir := preset.extra_anim_dir.strip_edges()
		var d := DirAccess.open(dir) if dir != "" else null
		if d != null:
			for f in d.get_files():
				var fn := String(f)
				if DRBaker.EXTRA_ANIM_EXT.has(fn.get_extension().to_lower()):
					var n := DRBaker._clean_anim_name(fn.get_basename())
					if not extra.has(n):
						extra.append(n)
	model.sort()
	extra.sort()
	_names_cache = {"model": model, "extra": extra}
	return _names_cache
