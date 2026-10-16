@tool
extends VBoxContainer
class_name DRMotionTableEditor

## 동작 표(DRMotionTable) 인스펙터 화면(10-16) — 사용자 요청: "한 상태에 동작 여러 개를 넣으면 그중 하나를 골라 틀고,
## 목록 옆에 % 를 넣어 33 · 33 · 33 을 20 · 40 · 40 처럼 조정 · 상하체 합성은 살려서".
##   - 상태마다 줄(DRMotionClip): 동작 고르기 · 비중 막대 · 비중 % · 지우기. 한 줄의 % 를 바꾸면 나머지가 비율을 지킨 채 합 100 이 된다
##   - [+ 동작] 새 줄은 100/n %, 기존 줄은 비율대로 줄어듦 · [+ 상하체 합성] 하체 + 상체(길이 맞춤 · 반복 · 상체 방향 유지 · 몸통 각도) · [균등]
##   - 위: 동작 목록(프리셋의 모델 동작 + 추가 동작 폴더) 다시 읽기 · [3D 동작 내보내기](저장 → 이 표로 DRMotionExporter) ·
##         안 내보낸 동작 알림(표에 있는데 3D 동작 묶음에 없는 이름)
##   - 고칠 때마다 되돌리기(Ctrl+Z) 한 칸 — 되돌리기 기록은 표(리소스)의 snapshot / restore_snapshot 을 부른다(이 화면은 인스펙터가 다시 만들면 사라지므로)
## 인스펙터 연결 = ui/motion_table_inspector.gd(plugin.gd 가 등록). 에디터 밖(명령줄 검사)에서는 되돌리기 없이 바로 고친다.

const COL_WARN := Color(1.0, 0.5, 0.4)
const COL_DIM := Color(0.68, 0.7, 0.72)
const COL_HEAD := Color(0.62, 0.8, 1.0)
const PCT_W := 78.0
const BAR_W := 46.0

## 동작 목록 캐시 {"model": 모델 자체 동작, "extra": 추가 동작 폴더} — 처음 한 번 읽고 [동작 목록 다시 읽기] 로 비운다
static var _names_cache: Dictionary = {}
## 펼친 상태 "표 경로|상태" -> true(인스펙터가 화면을 다시 만들어도 유지)
static var _open: Dictionary = {}

var table: DRMotionTable

var _list: VBoxContainer
var _status: Label
var _lib_note: Label
var _show_empty: CheckBox
var _add_state: OptionButton
var _rebuild_queued := false


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_shell()
	if table != null and not table.changed.is_connected(_queue_rebuild):
		table.changed.connect(_queue_rebuild)
	_rebuild()


func _exit_tree() -> void:
	if table != null and table.changed.is_connected(_queue_rebuild):
		table.changed.disconnect(_queue_rebuild)


# ───────────── 틀 ─────────────

func _build_shell() -> void:
	var title := Label.new()
	title.text = "동작 표 — 상태마다 동작 여러 개 · 비중(%)"
	title.add_theme_color_override("font_color", COL_HEAD)
	add_child(title)
	var hint := Label.new()
	hint.text = "그 상태가 되면 비중대로 하나를 골라 튼다(반복 동작은 한 바퀴마다 다시). % 를 바꾸면 나머지가 비율대로 맞춰진다."
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
	var l := Label.new()
	l.text = "상태 추가"
	add_row.add_child(l)
	_add_state = OptionButton.new()
	_add_state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_state.fit_to_longest_item = false
	add_row.add_child(_add_state)
	var add_btn := Button.new()
	add_btn.text = "+ 동작"
	add_btn.tooltip_text = "고른 상태에 동작 한 줄을 넣는다"
	add_btn.pressed.connect(func() -> void:
		if _add_state.selected >= 0:
			var st := _add_state.get_item_text(_add_state.selected)
			_open[_open_key(st)] = true
			_add_clip(st, false))
	add_row.add_child(add_btn)


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
		return
	var names := _names()
	var all_names := PackedStringArray(names["extra"]) + PackedStringArray(names["model"])
	var states := table.state_names()
	var used := 0
	var lines := 0
	_add_state.clear()
	for st in states:
		var cl := table.clips_of(st)
		lines += cl.size()
		if cl.is_empty():
			_add_state.add_item(st)
			if not _show_empty.button_pressed:
				continue
		else:
			used += 1
		_list.add_child(_state_block(st, cl, names, all_names))
	_status.text = "상태 %d개에 줄 %d개 · 고를 수 있는 동작: 추가 동작 %d · 모델 %d (프리셋 %s)" % [used, lines,
		(names["extra"] as PackedStringArray).size(), (names["model"] as PackedStringArray).size(), DRMotionExporter.DEFAULT_PRESET.get_file()]
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


func _open_key(st: String) -> String:
	return "%s|%s" % [table.resource_path, st]


func _state_block(st: String, cl: Array[DRMotionClip], names: Dictionary, all_names: PackedStringArray) -> Control:
	var box := VBoxContainer.new()
	var head := HBoxContainer.new()
	box.add_child(head)
	var open := bool(_open.get(_open_key(st), false))
	var tog := Button.new()
	tog.flat = true
	tog.text = ("▾ " if open else "▸ ") + st
	tog.alignment = HORIZONTAL_ALIGNMENT_LEFT
	tog.tooltip_text = "펼치기 / 접기"
	tog.pressed.connect(func() -> void:
		_open[_open_key(st)] = not bool(_open.get(_open_key(st), false))
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
		sum.text = "⚠ 게임이 모르는 상태 이름 · " + sum.text
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
	var btns := HBoxContainer.new()
	rows.add_child(btns)
	var b1 := Button.new()
	b1.text = "+ 동작"
	b1.tooltip_text = "이 상태에 동작 한 줄 더(새 줄 = 100/n %, 기존 줄은 비율대로 줄어듦)"
	b1.pressed.connect(_add_clip.bind(st, false))
	btns.add_child(b1)
	var b2 := Button.new()
	b2.text = "+ 상하체 합성"
	b2.tooltip_text = "하체 동작 + 상체 동작을 합친 줄(3D 동작 내보내기 때 2D 굽기와 같은 처리로 한 동작으로 굽는다)"
	b2.pressed.connect(_add_clip.bind(st, true))
	btns.add_child(b2)
	if cl.size() > 1:
		var b3 := Button.new()
		b3.text = "균등"
		b3.tooltip_text = "이 상태의 줄들을 똑같이 나눔"
		b3.pressed.connect(_equalize.bind(st))
		btns.add_child(b3)
	return box


## 상태 이름을 게임이 아는지 — 게임의 표가 all_keys() 를 주면 그것으로, 아니면 다 안다고 본다(애드온이 게임 클래스에 묶이지 않게)
func _state_known(st: String) -> bool:
	if table.has_method("all_keys"):
		var keys: PackedStringArray = table.call("all_keys")
		return keys.has(st)
	return true


func _clip_row(st: String, c: DRMotionClip, n: int, names: Dictionary, all_names: PackedStringArray) -> Control:
	var idx := table.clips.find(c)
	var box := VBoxContainer.new()
	var top := HBoxContainer.new()
	box.add_child(top)
	if c.is_composite() or (c.anim == "" and (c.lower != "" or c.upper != "")):
		var lab := Label.new()
		lab.text = "합성"
		lab.tooltip_text = "상하체 합성 — 하체(골반 · 다리) + 상체(몸통 · 머리 · 팔)"
		lab.add_theme_color_override("font_color", COL_HEAD)
		top.add_child(lab)
		var nm := Label.new()
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		nm.text = "→ " + c.play_name() if c.play_name() != "" else "→ (하체 · 상체를 고르세요)"
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
	if c.is_composite() or (c.anim == "" and (c.lower != "" or c.upper != "")):
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
	add_pair.call("길이", "길이가 다른 두 동작을 맞추는 법(2D 합성 창과 같음)", ln)
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


# ───────────── 고치기(되돌리기 한 칸씩) ─────────────

func _set_field(idx: int, field: String, value: Variant) -> void:
	if idx < 0 or idx >= table.clips.size():
		return
	var snap := table.snapshot()
	(snap[idx] as Dictionary)[field] = value
	_commit("동작 표: %s 바꾸기" % field, snap)


func _set_weight(st: String, idx: int, value: float) -> void:
	var snap := table.snapshot()
	var ids := _state_ids(snap, st)
	var ws := PackedFloat32Array()
	for i in ids:
		ws.append(float((snap[i] as Dictionary)["weight"]))
	var at := ids.find(idx)
	if at < 0:
		return
	ws = DRMotionTable.rebalance(ws, at, value)
	for k in ids.size():
		(snap[ids[k]] as Dictionary)["weight"] = ws[k]
	_commit("동작 표: %s 비중" % st, snap)


func _add_clip(st: String, composite: bool) -> void:
	var snap := table.snapshot()
	var ids := _state_ids(snap, st)
	var ws := PackedFloat32Array()
	for i in ids:
		ws.append(float((snap[i] as Dictionary)["weight"]))
	ws = DRMotionTable.with_added(ws)
	for k in ids.size():
		(snap[ids[k]] as Dictionary)["weight"] = ws[k]
	var c := DRMotionClip.new()
	c.state = st
	c.weight = ws[ws.size() - 1]
	var d := c.to_dict()
	if composite:
		d["lower"] = _first_existing(["Crouch_Idle", "Idle"])
		d["upper"] = ""
	var insert_at := (ids[ids.size() - 1] + 1) if not ids.is_empty() else snap.size()
	snap.insert(insert_at, d)
	_open[_open_key(st)] = true
	_commit("동작 표: %s 에 %s 더하기" % [st, "합성" if composite else "동작"], snap)


func _remove_clip(idx: int) -> void:
	var snap := table.snapshot()
	if idx < 0 or idx >= snap.size():
		return
	var st := String((snap[idx] as Dictionary)["state"])
	var ids := _state_ids(snap, st)
	var at := ids.find(idx)
	var ws := PackedFloat32Array()
	for i in ids:
		ws.append(float((snap[i] as Dictionary)["weight"]))
	ws = DRMotionTable.without(ws, at)
	var k := 0
	for i in ids:
		if i == idx:
			continue
		(snap[i] as Dictionary)["weight"] = ws[k]
		k += 1
	snap.remove_at(idx)
	_commit("동작 표: %s 줄 지우기" % st, snap)


func _equalize(st: String) -> void:
	var snap := table.snapshot()
	var ids := _state_ids(snap, st)
	var ws := DRMotionTable.equalized(ids.size())
	for k in ids.size():
		(snap[ids[k]] as Dictionary)["weight"] = ws[k]
	_commit("동작 표: %s 균등" % st, snap)


func _state_ids(snap: Array, st: String) -> Array[int]:
	var out: Array[int] = []
	for i in snap.size():
		if String((snap[i] as Dictionary)["state"]) == st:
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
func _commit(action: String, after: Array) -> void:
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
	print("[Dot Rigger] 3D 동작 내보내기(동작 표 인스펙터)\n" + "\n".join(lines))
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
