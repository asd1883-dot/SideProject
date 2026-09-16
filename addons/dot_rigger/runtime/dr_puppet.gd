@tool
extends Node2D
class_name DRPuppet

## 베이크된 2D 컷아웃 퍼펫의 런타임. 장비 장착/해제를 담당한다.
##
## 전체 실루엣 아웃라인으로 구운 씬은 파트마다 stretch/outline(밑깔개, z −1)이 있다.
## 장비도 같은 밑깔개를 하나 더 받아야 헬멧 같은 돌출부 바깥에도 선이 이어진다.
##
## 필요한 정보(파트별 레스트 피벗/각도)는 씬 안에 이미 들어 있으므로
## rig.json 을 런타임에 읽지 않는다:
##   - 레스트 각도  = Bone2D.get_bone_angle()   (베이크 때 넣어 둠)
##   - 레스트 피벗  = 조상들의 Bone2D.rest.origin 누적합 (레스트에서 회전은 전부 0)

signal equipped(slot: String, item: DREquipItem)
signal unequipped(slot: String)

var _parts: Dictionary = {}      # part 이름 -> {bone, stretch, rest_head, rest_angle}
var _equipped: Dictionary = {}   # slot -> Sprite2D
var _equipped_outline: Dictionary = {}   # slot -> Sprite2D (전체 실루엣 밑깔개, 없으면 키 없음)
## 본체 파트 스프라이트의 머티리얼(부드러운 도트 이동 셰이더). 장비도 같은 방식으로 그려야 결이 맞는다
var _art_material: Material = null
## 본체 밑깔개의 머티리얼·z (전체 실루엣 아웃라인으로 구운 씬만). null 이면 밑깔개 없음
var _outline_material: Material = null
var _outline_z: int = -1


func _ready() -> void:
	rebuild_index()


## 씬 구조가 바뀌었을 때 다시 훑는다.
func rebuild_index() -> void:
	_parts.clear()
	_art_material = null
	_outline_material = null
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
	if _art_material == null:
		var art := b.get_node_or_null("stretch/art") as Sprite2D
		if art != null:
			_art_material = art.material
	if _outline_material == null:
		var ol := b.get_node_or_null("stretch/outline") as Sprite2D
		if ol != null:
			_outline_material = ol.material
			_outline_z = ol.z_index
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
	spr.material = _art_material
	# 본체 파트 스프라이트와 완전히 같은 규격으로 배치한다.
	spr.rotation = -ra
	spr.position = (item.offset - Vector2(info["rest_head"])).rotated(-ra)
	if _outline_material != null:
		# 전체 실루엣 밑깔개 — 본체와 같은 자리·같은 z(모든 파트 뒤)
		var ol := spr.duplicate() as Sprite2D
		ol.name = "equip_%s_outline" % item.slot
		ol.z_index = _outline_z
		ol.modulate = Color.WHITE
		ol.material = _outline_material
		host.add_child(ol)
		_equipped_outline[item.slot] = ol
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
	if _equipped_outline.has(slot):
		var o: Node = _equipped_outline[slot]
		if is_instance_valid(o):
			o.queue_free()
		_equipped_outline.erase(slot)
	unequipped.emit(slot)


func unequip_all() -> void:
	for s in _equipped.keys().duplicate():
		unequip(String(s))


func get_equipped(slot: String) -> Sprite2D:
	return _equipped.get(slot, null)


## 장비의 전체 실루엣 밑깔개(없으면 null — 파트별 아웃라인이거나 아웃라인 없이 구운 씬)
func get_equipped_outline(slot: String) -> Sprite2D:
	return _equipped_outline.get(slot, null)


## 파트 본체 스프라이트 색만 바꾸기(팔레트 스왑의 가장 싼 형태).
func tint_part(part: String, color: Color) -> void:
	if not _parts.has(part):
		return
	var info: Dictionary = _parts[part]
	var host: Node2D = info["stretch"] if info["stretch"] != null else info["bone"]
	var art := host.get_node_or_null("art") as Sprite2D
	if art != null:
		art.modulate = color
