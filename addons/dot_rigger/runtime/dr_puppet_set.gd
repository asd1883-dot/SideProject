@tool
extends Node2D
class_name DRPuppetSet

## 구운 세트 여러 벌(<출력>/<세트>/puppet.tscn + sets.json)을 **캐릭터 하나**처럼 다루는 런타임.
##
## Unity 로 치면: 세트 1개 = 프리팹 1개 = Animator 1개(그 안의 동작 = 클립). 자세 계열(서기/앉기/포복)은 파트 그림이 달라서
## 세트가 나뉘고 씬도 폴더별로 나뉘는데, 게임 코드가 그걸 일일이 갈아 끼우면 번거롭다. 이 노드가 sets.json 을 읽어
## 세트의 퍼펫을 전부 자식으로 들고 있다가, `play("동작 이름")` 하면 그 동작이 든 세트를 보이게 하고 재생한다.
##   $Soldier.play("Rifle_Aiming_Idle")     # 어느 폴더에 있든 이름만
##   $Soldier.aim_enabled = true ; $Soldier.aim_target = get_global_mouse_position()
##
## - 세트를 바꿔도 **발 자리가 같게** 놓는다: 이 노드의 원점 = 두 발 사이의 바닥(rig.json 의 발 피벗 · 파트 그림 아래끝에서 계산).
## - 조준: 애니메이션이 자세를 정한 **뒤에** aim_part(기본 몸통) 본에 각도를 더한다. 머리·팔·총이 몸통의 자식이라 한 덩어리로 돈다.
##   AnimationPlayer 를 수동(MANUAL)으로 돌려 "지난 프레임에 더한 각도를 빼고 → 애니 진행 → 새 각도를 더함" 순서를 지킨다
##   (그냥 더하면 애니가 끝났거나 멈춘 동안 각도가 매 프레임 쌓인다).
## - 좌우 반전: auto_face 면 조준 목표가 등 뒤로 가면 돌아본다(scale.x = −1).

signal animation_changed(anim: StringName, set_name: String)

## sets.json 경로. 세트 베이크가 <출력 폴더>/sets.json 으로 남긴다.
@export_file("*.json") var sets_json: String = "res://puppet/sets.json":
	set(v):
		sets_json = v
		if is_inside_tree():
			reload()
## 모든 동작을 반복으로(가져온 애니에 반복 표시가 없어도 계속 돌려 볼 때 — Mixamo 동작은 기본이 반복 아님)
@export var force_loop: bool = false
## 구운 캐릭터가 화면 오른쪽을 보고 있는가(왼쪽을 보게 구웠으면 끈다)
@export var baked_facing_right: bool = true

@export_group("조준")
@export var aim_enabled: bool = false
## 조준할 곳(전역 좌표). 보통 매 프레임 get_global_mouse_position()
@export var aim_target: Vector2 = Vector2.ZERO
## 위아래로 돌릴 수 있는 한계(도)
@export_range(0.0, 90.0, 1.0) var aim_limit_deg: float = 35.0
## 각도를 더할 파트. 몸통이면 머리·팔·총이 같이 돈다
@export var aim_part: String = "Torso"
## 목표를 따라가는 빠르기(클수록 즉시)
@export_range(1.0, 60.0, 1.0) var aim_speed: float = 14.0
## 목표가 등 뒤로 가면 돌아본다
@export var auto_face: bool = true

var _entries: Array = []            # [{name, dir, puppet: DRPuppet, player: AnimationPlayer, anims: PackedStringArray, origin: Vector2}]
var _anim_to_set: Dictionary = {}   # 동작 이름 -> _entries 번호
var _active := -1
var _current: StringName = &""
var _aim_applied := 0.0             # 지난 프레임에 본에 더해 둔 각도(라디안)
var _aim_cur := 0.0
var _facing := 1                    # 1 = 구운 방향 그대로, −1 = 반전
var _equip_sets: Dictionary = {}    # slot -> DREquipSet (다시 읽어도 다시 장착한다)


func _ready() -> void:
	reload()


## sets.json 을 다시 읽어 퍼펫들을 다시 만든다.
func reload() -> void:
	for e in _entries:
		var old: Node = (e as Dictionary)["holder"]
		if is_instance_valid(old):
			old.queue_free()
	_entries.clear()
	_anim_to_set.clear()
	_active = -1
	_current = &""
	_aim_applied = 0.0
	if sets_json == "" or not FileAccess.file_exists(sets_json):
		push_warning("[DRPuppetSet] sets.json 을 찾을 수 없습니다: %s" % sets_json)
		return
	var doc = JSON.parse_string(FileAccess.get_file_as_string(sets_json))
	if not (doc is Dictionary):
		push_warning("[DRPuppetSet] sets.json 을 읽을 수 없습니다: %s" % sets_json)
		return
	var base := sets_json.get_base_dir()
	for s in (doc as Dictionary).get("sets", []):
		var sd: Dictionary = s
		if not bool(sd.get("ok", true)):
			continue
		var scene_path := base.path_join(String(sd.get("scene", "")))
		var ps := load(scene_path) as PackedScene
		if ps == null:
			push_warning("[DRPuppetSet] 씬을 열 수 없습니다: %s" % scene_path)
			continue
		var puppet := ps.instantiate() as Node2D
		var player := puppet.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if player == null:
			puppet.free()
			continue
		# 발 자리를 원점에 맞추려고 한 겹 감싼다(퍼펫의 원점은 베이크 캔버스의 왼쪽 위)
		var holder := Node2D.new()
		holder.name = String(sd.get("dir", sd.get("name", "set")))
		add_child(holder)
		holder.add_child(puppet)
		var origin := _feet_origin(base.path_join(String(sd.get("rig", ""))))
		puppet.position = -origin
		holder.visible = false
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var names := PackedStringArray()
		for an in player.get_animation_list():
			if String(an) == "RESET":
				continue
			names.append(String(an))
			if force_loop:
				player.get_animation(an).loop_mode = Animation.LOOP_LINEAR
			if not _anim_to_set.has(String(an)):
				_anim_to_set[String(an)] = _entries.size()
		_entries.append({"name": String(sd.get("name", "")), "holder": holder, "puppet": puppet, "player": player, "anims": names, "origin": origin})
	for slot in _equip_sets.keys():
		_apply_equip(_equip_sets[slot])
	if _entries.size() > 0:
		var first: PackedStringArray = _entries[0]["anims"]
		if first.size() > 0:
			play(first[0])


## 장비를 **모든 세트에** 장착한다. 세트마다 그 세트용 그림(DREquipSet.items[세트 이름])이 붙으므로
## 동작이 바뀌어 세트가 넘어가도 그대로 들려 있다. 같은 슬롯에 이미 있으면 바꿔 든다(무기 교체).
## 돌려주는 값 = 장착된 세트 수. 그 세트용 그림이 없는 세트는 그 슬롯을 비운다.
func equip(equip_set: DREquipSet) -> int:
	if equip_set == null or equip_set.slot == "":
		return 0
	_equip_sets[equip_set.slot] = equip_set
	return _apply_equip(equip_set)


func unequip(slot: String) -> void:
	_equip_sets.erase(slot)
	for e in _entries:
		var pup := (e as Dictionary)["puppet"] as DRPuppet
		if pup != null:
			pup.unequip(slot)


## 지금 그 슬롯에 든 장비(없으면 null)
func get_equipped(slot: String) -> DREquipSet:
	return _equip_sets.get(slot, null) as DREquipSet


func _apply_equip(equip_set: DREquipSet) -> int:
	var n := 0
	for e in _entries:
		var ed: Dictionary = e
		var pup := ed["puppet"] as DRPuppet
		if pup == null:
			continue
		var item := equip_set.item_for(String(ed["name"]))
		if item == null:
			pup.unequip(equip_set.slot)
			continue
		if item.slot != equip_set.slot:
			item = item.duplicate() as DREquipItem
			item.slot = equip_set.slot
		if pup.equip(item):
			n += 1
	return n


## 두 발 사이의 바닥(퍼펫 좌표). x = 두 발 피벗의 가운데, y = 파트 그림 가운데 가장 아래 끝
func _feet_origin(rig_path: String) -> Vector2:
	var doc = JSON.parse_string(FileAccess.get_file_as_string(rig_path)) if FileAccess.file_exists(rig_path) else null
	if not (doc is Dictionary):
		return Vector2.ZERO
	var xs: Array = []
	var bottom := 0.0
	var pad := float((doc as Dictionary).get("outline_px", 0))
	for p in (doc as Dictionary).get("parts", []):
		var pd: Dictionary = p
		var crop: Array = pd.get("crop", [0, 0, 0, 0])
		bottom = maxf(bottom, float(crop[1]) + float(crop[3]) - pad)
		if String(pd.get("name", "")).ends_with("Foot"):
			xs.append(float(pd["rest"]["head"][0]))
	var x := 0.0
	for v in xs:
		x += float(v)
	return Vector2(x / float(maxi(xs.size(), 1)), bottom)


## 모든 세트의 동작 이름(세트 순서대로)
func get_animations() -> PackedStringArray:
	var out := PackedStringArray()
	for e in _entries:
		out.append_array((e as Dictionary)["anims"])
	return out


func has_animation(anim: StringName) -> bool:
	return _anim_to_set.has(String(anim))


## 동작을 재생한다. 그 동작이 다른 세트에 있으면 세트(퍼펫)를 바꾼다. 없는 이름이면 false.
func play(anim: StringName, custom_blend: float = -1.0) -> bool:
	if not _anim_to_set.has(String(anim)):
		push_warning("[DRPuppetSet] 그런 동작이 없습니다: %s (있는 것: %s)" % [anim, ", ".join(get_animations())])
		return false
	var idx := int(_anim_to_set[String(anim)])
	if idx != _active:
		_remove_aim()                      # 예전 퍼펫의 본에 더해 둔 각도를 빼 놓는다
		if _active >= 0:
			(_entries[_active]["holder"] as Node2D).visible = false
		_active = idx
		(_entries[_active]["holder"] as Node2D).visible = true
	var player: AnimationPlayer = _entries[_active]["player"]
	if _current != anim or not player.is_playing():
		player.play(anim, custom_blend)
	_current = anim
	animation_changed.emit(anim, String(_entries[_active]["name"]))
	return true


func current_animation() -> StringName:
	return _current


func current_set() -> String:
	return String(_entries[_active]["name"]) if _active >= 0 else ""


## 지금 보이는 퍼펫(장비 장착 등은 여기에). 세트마다 따로이므로 세트가 바뀌면 다시 장착해야 한다
func get_puppet() -> DRPuppet:
	return (_entries[_active]["puppet"] as DRPuppet) if _active >= 0 else null


func get_animation_player() -> AnimationPlayer:
	return (_entries[_active]["player"] as AnimationPlayer) if _active >= 0 else null


## 지금 조준으로 더해져 있는 각도(도, + = 아래 · − = 위. 화면 기준)
func get_aim_degrees() -> float:
	return rad_to_deg(_aim_cur)


## 1 = 구운 방향, −1 = 반전
func get_facing() -> int:
	return _facing


func _aim_bone() -> Bone2D:
	var p := get_puppet()
	return p.get_bone(aim_part) if p != null else null


func _remove_aim() -> void:
	if _aim_applied != 0.0:
		var b := _aim_bone()
		if b != null:
			b.rotation -= _aim_applied
	_aim_applied = 0.0


func _process(delta: float) -> void:
	if _active < 0:
		return
	if Engine.is_editor_hint():
		return                       # 에디터에 놓았을 때는 첫 동작의 첫 자세만 보인다
	# 1) 지난 프레임에 더한 조준 각도를 뺀다 — 애니가 멈춰 있어도 각도가 쌓이지 않게
	_remove_aim()
	# 2) 애니메이션 진행(수동)
	(_entries[_active]["player"] as AnimationPlayer).advance(delta)
	# 3) 바라보는 쪽 + 조준 각도
	var want := 0.0
	var bone := _aim_bone()
	if aim_enabled and bone != null:
		var base_dir := 1.0 if baked_facing_right else -1.0
		if auto_face:
			# 목표가 몸의 반대쪽으로 충분히 넘어가면 돌아본다(경계에서 떨지 않게 여유 12px). 화면(전역) 좌표로 잰다
			var dx := aim_target.x - bone.global_position.x
			if absf(dx) > 12.0:
				var want_right := dx > 0.0
				_facing = 1 if want_right == baked_facing_right else -1
		scale.x = absf(scale.x) * float(_facing)
		# 반전까지 적용된 퍼펫 좌표에서 잰다 → 늘 "구운 방향" 기준의 각도가 나온다
		var holder: Node2D = _entries[_active]["holder"]
		var t := holder.to_local(aim_target)
		var pv := holder.to_local(bone.global_position)
		var dir := t - pv
		if dir.length() > 1.0:
			var ang := atan2(dir.y, dir.x * base_dir)             # 정면 수평 = 0, 위 = −, 아래 = +
			want = clampf(ang, -deg_to_rad(aim_limit_deg), deg_to_rad(aim_limit_deg)) * base_dir
	_aim_cur = lerp_angle(_aim_cur, want, 1.0 - exp(-delta * aim_speed))
	if bone != null and absf(_aim_cur) > 0.00001:
		bone.rotation += _aim_cur
		_aim_applied = _aim_cur
