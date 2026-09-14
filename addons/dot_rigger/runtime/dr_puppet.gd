@tool
extends Node2D
class_name DRPuppet

## 베이크된 2D 컷아웃 퍼펫의 런타임. 장비 장착/해제를 담당한다.
##
## 필요한 정보(파트별 레스트 피벗/각도)는 씬 안에 이미 들어 있으므로
## rig.json 을 런타임에 읽지 않는다:
##   - 레스트 각도  = Bone2D.get_bone_angle()   (베이크 때 넣어 둠)
##   - 레스트 피벗  = 조상들의 Bone2D.rest.origin 누적합 (레스트에서 회전은 전부 0)

signal equipped(slot: String, item: DREquipItem)
signal unequipped(slot: String)

var _parts: Dictionary = {}      # part 이름 -> {bone, stretch, rest_head, rest_angle}
var _equipped: Dictionary = {}   # slot -> Sprite2D


func _ready() -> void:
	rebuild_index()


## 씬 구조가 바뀌었을 때 다시 훑는다.
func rebuild_index() -> void:
	_parts.clear()
	var skel := get_node_or_null("Skeleton2D")
	if skel == null:
		push_warning("[DRPuppet] Skeleton2D 를 찾지 못했습니다.")
		return
	for c in skel.get_children():
		_walk(c, Vector2.ZERO)


func _walk(n: Node, parent_head: Vector2) -> void:
	if not (n is Bone2D):
		return
	var b := n as Bone2D
	var head := parent_head + b.rest.origin
	_parts[b.name] = {
		"bone": b,
		"stretch": b.get_node_or_null("stretch"),
		"rest_head": head,
		"rest_angle": b.get_bone_angle(),
	}
	for c in b.get_children():
		_walk(c, head)


func part_names() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _parts.keys():
		out.append(String(k))
	return out


func has_part(part: String) -> bool:
	return _parts.has(part)


## 장비 장착. 같은 슬롯에 이미 있으면 교체한다.
func equip(item: DREquipItem) -> bool:
	if item == null or item.slot == "":
		return false
	if _parts.is_empty():
		rebuild_index()
	if not _parts.has(item.part):
		push_warning("[DRPuppet] 파트를 찾을 수 없습니다: %s (사용 가능: %s)"
			% [item.part, String(", ").join(part_names())])
		return false
	unequip(item.slot)

	var info: Dictionary = _parts[item.part]
	var host: Node2D = info["stretch"] if (item.follow_stretch and info["stretch"] != null) \
		else info["bone"]
	var ra: float = info["rest_angle"]

	var spr := Sprite2D.new()
	spr.name = "equip_%s" % item.slot
	spr.texture = item.texture
	spr.centered = false
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	spr.z_as_relative = false
	spr.z_index = item.z_index
	spr.modulate = item.modulate
	# 본체 파트 스프라이트와 완전히 같은 규격으로 배치한다.
	spr.rotation = -ra
	spr.position = (item.offset - Vector2(info["rest_head"])).rotated(-ra)
	host.add_child(spr)

	_equipped[item.slot] = spr
	equipped.emit(item.slot, item)
	return true


func unequip(slot: String) -> void:
	if not _equipped.has(slot):
		return
	var n: Node = _equipped[slot]
	if is_instance_valid(n):
		n.queue_free()
	_equipped.erase(slot)
	unequipped.emit(slot)


func unequip_all() -> void:
	for s in _equipped.keys().duplicate():
		unequip(String(s))


func get_equipped(slot: String) -> Sprite2D:
	return _equipped.get(slot, null)


## 파트 본체 스프라이트 색만 바꾸기(팔레트 스왑의 가장 싼 형태).
func tint_part(part: String, color: Color) -> void:
	if not _parts.has(part):
		return
	var info: Dictionary = _parts[part]
	var host: Node2D = info["stretch"] if info["stretch"] != null else info["bone"]
	var art := host.get_node_or_null("art") as Sprite2D
	if art != null:
		art.modulate = color
