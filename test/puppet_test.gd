extends Node2D

## 구운 퍼펫을 게임처럼 돌려 보는 시험장.  이 씬을 열고 F6(현재 씬 실행).
##
##   숫자 1~9   동작 바꾸기 (sets.json 의 모든 세트의 동작이 순서대로. 세트가 달라도 이름만으로 바뀐다)
##   마우스     조준 — 조준하는 동작(이름에 aim·rifle·fir·shoot 가 들어간 것)일 때 몸통이 마우스를 따라간다(위로 올리면 위를 겨눔)
##   A          조준을 동작과 상관없이 강제로 켬/끔/자동
##   F          좌우 자동 반전 켬/끔 (마우스가 등 뒤로 가면 돌아본다)
##   + / −      확대/축소        L  모든 동작 반복 켬/끔        R  sets.json 다시 읽기(다시 구운 뒤)
##   E          장비 바꿔 들기 — res://equip/<이름>/equip.json 으로 구워 둔 무기를 차례로(맨손 → 무기1 → 무기2 … → 맨손)
##   O          상의 바꿔 입기 — res://outfits/<이름>/outfit.json 으로 구워 둔 복장의 몸통 · 팔을 차례로(기본 몸 → 복장1 → … → 기본 몸)
##   P          하의 · 신발 바꿔 입기 — 같은 복장들의 골반 · 다리 · 발을 차례로. 상의와 따로 골라 섞어 입는다(머리 · 손은 늘 기본 몸)
##
## Unity 와의 대응: DRPuppetSet 노드 = Animator 가 붙은 프리팹. play("이름") = animator.Play("이름").
## 구운 세트(폴더)가 여러 개여도 이 노드 하나가 묶어서 다룬다 — 세트는 자세 계열(서기/앉기/포복)마다 파트 그림이 달라서 나뉘는 것.
##
## 병사는 보통 이 스크립트가 코드로 만든다. 이 씬 안에 DRPuppetSet 노드(Node2D + dr_puppet_set.gd)를 직접 놓아 두었으면
## 새로 만들지 않고 **그 노드를 그대로 쓴다** — 놓은 자리·크기·인스펙터 값이 그대로 가고, 키와 마우스가 그 노드를 움직인다.

const SETS_JSON := "res://puppet/sets.json"
const AIM_WORDS := ["aim", "rifle", "fir", "shoot", "pistol"]
const EQUIP_DIR := "res://equip"
const OUTFIT_DIR := "res://outfits"

var soldier: DRPuppetSet
var _label: Label
var _names: PackedStringArray = PackedStringArray()
var _aim_mode := 0          # 0 = 자동(동작 이름으로) · 1 = 늘 켬 · 2 = 늘 끔
var _zoom := 1.5
var _weapons: PackedStringArray = PackedStringArray()   # 구워 둔 장비의 equip.json 경로들
var _weapon_i := -1         # −1 = 맨손
var _placed := false        # 씬에 직접 놓아 둔 DRPuppetSet 을 쓰는 중(자리는 놓은 그대로 둔다)
var _outfits: PackedStringArray = PackedStringArray()   # 구워 둔 복장의 outfit.json 경로들
var _outfit_cache: Dictionary = {}                      # 경로 -> DROutfit (키를 누를 때마다 그림을 다시 읽지 않게)
var _top_i := -1            # 상의(몸통 · 팔)로 입은 복장 번호, −1 = 기본 몸
var _bottom_i := -1         # 하의 · 신발(골반 · 다리 · 발)로 입은 복장 번호, −1 = 기본 몸


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.36, 0.42, 0.36))
	soldier = _find_placed(self)
	if soldier != null:
		_placed = true
		_zoom = maxf(absf(soldier.scale.x), 0.01)
	else:
		soldier = DRPuppetSet.new()
		soldier.name = "Soldier"
		soldier.force_loop = true
		soldier.sets_json = SETS_JSON
		add_child(soldier)
	var ui := CanvasLayer.new()
	add_child(ui)
	_label = Label.new()
	_label.position = Vector2(12, 8)
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	ui.add_child(_label)
	_names = soldier.get_animations()
	_find_weapons()
	_find_outfits()
	_adopt_inspector_outfit()
	_layout()
	get_viewport().size_changed.connect(_layout)


## 구워 둔 장비 찾기(res://equip/*/equip.json)
func _find_weapons() -> void:
	_weapons = PackedStringArray()
	for d in DirAccess.get_directories_at(EQUIP_DIR):
		var p := EQUIP_DIR.path_join(d).path_join("equip.json")
		if FileAccess.file_exists(p):
			_weapons.append(p)


func _next_weapon() -> void:
	_find_weapons()
	_weapon_i += 1
	if _weapon_i >= _weapons.size():
		_weapon_i = -1
	if _weapon_i < 0:
		soldier.unequip("weapon")
		return
	var es := DREquipSet.load_json(_weapons[_weapon_i])
	if es != null:
		soldier.equip(es)


## 구워 둔 복장 찾기(res://outfits/*/outfit.json)
func _find_outfits() -> void:
	_outfits = PackedStringArray()
	if not DirAccess.dir_exists_absolute(OUTFIT_DIR):
		return
	for d in DirAccess.get_directories_at(OUTFIT_DIR):
		var p := OUTFIT_DIR.path_join(d).path_join("outfit.json")
		if FileAccess.file_exists(p):
			_outfits.append(p)


## 인스펙터 복장 칸(outfit_json · outfit_part)에 넣어 둔 복장이 있으면 그 상태에서 시작한다.
## 그 뒤로는 O · P 키가 상의 · 하의를 따로 고르므로, 인스펙터 칸은 비워 둔다(R 로 다시 읽어도 키로 고른 상태가 남게).
func _adopt_inspector_outfit() -> void:
	if soldier.outfit_json == "":
		return
	var i := _outfits.find(soldier.outfit_json)
	if i < 0:
		_outfits.append(soldier.outfit_json)
		i = _outfits.size() - 1
	_top_i = i if soldier.outfit_part != 2 else -1       # 0 전부 · 1 상의만 · 2 하의+신발만
	_bottom_i = i if soldier.outfit_part != 1 else -1
	soldier.outfit_json = ""
	_apply_outfits()


func _outfit_at(i: int) -> DROutfit:
	if i < 0 or i >= _outfits.size():
		return null
	var p := _outfits[i]
	if not _outfit_cache.has(p):
		_outfit_cache[p] = DROutfit.load_json(p)
	return _outfit_cache[p] as DROutfit


## 고른 상의 · 하의대로 다시 입힌다(머리 · 손은 늘 기본 몸)
func _apply_outfits() -> void:
	soldier.take_off()
	var top := _outfit_at(_top_i)
	if top != null:
		soldier.wear(top, top.slot_parts("top"), false)
	var bottom := _outfit_at(_bottom_i)
	if bottom != null:
		soldier.wear(bottom, bottom.slot_parts("bottom") + bottom.slot_parts("shoes"), false)


## 다음 복장(−1 = 기본 몸 → 0 → 1 … → 기본 몸)
func _cycle(i: int) -> int:
	_find_outfits()
	i += 1
	return -1 if i >= _outfits.size() else i


func _outfit_name(i: int) -> String:
	if i < 0 or i >= _outfits.size():
		return "기본 몸"
	return _outfits[i].get_base_dir().get_file()


## 이 씬 안에 직접 놓아 둔 DRPuppetSet(없으면 null)
func _find_placed(n: Node) -> DRPuppetSet:
	for c in n.get_children():
		if c is DRPuppetSet:
			return c as DRPuppetSet
		var deep := _find_placed(c)
		if deep != null:
			return deep
	return null


func _layout() -> void:
	var vs := get_viewport_rect().size
	if not _placed:
		soldier.position = Vector2(vs.x * 0.5, vs.y * 0.82)      # 발이 화면 아래쪽 가운데
	soldier.scale = Vector2(_zoom * float(soldier.get_facing()), _zoom)
	queue_redraw()


func _draw() -> void:
	var vs := get_viewport_rect().size
	var gy: float = to_local(soldier.global_position).y if soldier != null else vs.y * 0.82
	draw_line(Vector2(0, gy), Vector2(vs.x, gy), Color(0.2, 0.25, 0.2), 2.0)   # 바닥 = 병사의 발 높이


func _wants_aim(anim: String) -> bool:
	if _aim_mode == 1:
		return true
	if _aim_mode == 2:
		return false
	var s := anim.to_lower()
	for w in AIM_WORDS:
		if s.contains(w):
			return true
	return false


func _process(_delta: float) -> void:
	soldier.aim_target = get_global_mouse_position()
	soldier.aim_enabled = _wants_aim(String(soldier.current_animation()))
	var lines := PackedStringArray()
	lines.append("세트 [%s]  동작 [%s]   조준 %s  %+.0f°   %s" % [soldier.current_set(), soldier.current_animation(),
		["자동", "늘 켬", "늘 끔"][_aim_mode] + ("(켜짐)" if soldier.aim_enabled else "(꺼짐)"), -soldier.get_aim_degrees(),
		"좌우 자동" if soldier.auto_face else "좌우 고정"])
	for i in _names.size():
		lines.append("  %d  %s%s" % [i + 1, _names[i], "   ◀" if String(soldier.current_animation()) == _names[i] else ""])
	var held := soldier.get_equipped("weapon")
	lines.append("장비 [%s]  (구워 둔 것 %d개)" % [held.id if held != null else "맨손", _weapons.size()])
	lines.append("복장  상의 [%s]  하의·신발 [%s]  (구워 둔 것 %d개)" % [_outfit_name(_top_i), _outfit_name(_bottom_i), _outfits.size()])
	lines.append("A 조준 자동/켬/끔 · F 좌우 반전 · +/− 확대 · L 반복 · R 다시 읽기 · E 장비 바꿔 들기 · O 상의 · P 하의")
	_label.text = "\n".join(lines)


func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not (ev as InputEventKey).pressed or (ev as InputEventKey).echo:
		return
	var k := (ev as InputEventKey).keycode
	if k >= KEY_1 and k <= KEY_9:
		var i := int(k - KEY_1)
		if i < _names.size():
			soldier.play(_names[i], 0.15)
	elif k == KEY_A:
		_aim_mode = (_aim_mode + 1) % 3
	elif k == KEY_F:
		soldier.auto_face = not soldier.auto_face
	elif k == KEY_EQUAL or k == KEY_KP_ADD:
		_zoom = minf(_zoom + 0.25, 4.0)
		_layout()
	elif k == KEY_MINUS or k == KEY_KP_SUBTRACT:
		_zoom = maxf(_zoom - 0.25, 0.5)
		_layout()
	elif k == KEY_L:
		soldier.force_loop = not soldier.force_loop
		soldier.reload()
		_names = soldier.get_animations()
	elif k == KEY_E:
		_next_weapon()
	elif k == KEY_O:
		_top_i = _cycle(_top_i)
		_apply_outfits()
	elif k == KEY_P:
		_bottom_i = _cycle(_bottom_i)
		_apply_outfits()
	elif k == KEY_R:
		soldier.reload()
		_names = soldier.get_animations()
