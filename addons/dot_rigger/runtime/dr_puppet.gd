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
var _z_follow: Dictionary = {}   # slot -> {art: 기준 파트의 Sprite2D, gap: int} — z_after_part 로 장착한 장비
var _equipped_overlays: Dictionary = {}   # slot -> Array[Sprite2D] — 앞 조각(장비 위에 그리는 파트 조각)
var _hidden_parts: Dictionary = {}       # slot -> PackedStringArray — 장비를 드는 동안 안 그리는 파트
var _raised: Dictionary = {}             # slot -> [{art, orig, rank}] — 장비를 드는 동안 장비 위로 올린 파트(z 를 매 프레임 덮어씀)
var _ov_follow: Array = []               # [{spr, art}] — 총 조각(파트 위에 얹는 장비 부분): 그 파트의 z + 1 을 매 프레임 따라간다
## 본체 파트 스프라이트의 머티리얼(부드러운 도트 이동 셰이더). 장비도 같은 방식으로 그려야 결이 맞는다
var _art_material: Material = null
## 본체 밑깔개의 머티리얼·z (전체 실루엣 아웃라인으로 구운 씬만). null 이면 밑깔개 없음
var _outline_material: Material = null
var _outline_z: int = -1


func _ready() -> void:
	rebuild_index()
	set_process(false)


## z_after_part 로 장착한 장비는 기준 파트의 z 를 따라간다(자동 순서로 구운 씬은 파트 z 가 프레임마다 바뀐다)
func _process(_delta: float) -> void:
	for slot in _raised.keys():
		var ws := _equipped.get(slot, null) as Sprite2D
		if not is_instance_valid(ws):
			continue
		for r in _raised[slot]:
			var ra := (r as Dictionary)["art"] as Sprite2D
			if is_instance_valid(ra):
				ra.z_index = ws.z_index + 1 + int((r as Dictionary)["rank"])
	for f in _ov_follow:
		var fs := (f as Dictionary)["spr"] as Sprite2D
		var fa := (f as Dictionary)["art"] as Sprite2D
		if is_instance_valid(fs) and is_instance_valid(fa):
			fs.z_index = fa.z_index + 1
	for slot in _z_follow.keys():
		var f: Dictionary = _z_follow[slot]
		var art := f["art"] as Sprite2D
		var spr := _equipped.get(slot, null) as Sprite2D
		if is_instance_valid(art) and is_instance_valid(spr):
			spr.z_index = art.z_index + int(f["gap"])
			for o in _equipped_overlays.get(slot, []):
				if is_instance_valid(o) and (o as Sprite2D).get_meta("kind", "part") == "part":
					(o as Sprite2D).z_index = spr.z_index + 1


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
		"art": b.get_node_or_null("stretch/art"),
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


## 파트의 Bone2D (없으면 null). 조준처럼 애니메이션 위에 각도를 더할 때 쓴다.
func get_bone(part: String) -> Bone2D:
	if _parts.is_empty():
		rebuild_index()
	if not _parts.has(part):
		return null
	return _parts[part]["bone"] as Bone2D


## 파트의 레스트 피벗(퍼펫 좌표 = 베이크 캔버스 좌표)
func get_rest_head(part: String) -> Vector2:
	if _parts.is_empty():
		rebuild_index()
	return Vector2(_parts[part]["rest_head"]) if _parts.has(part) else Vector2.ZERO


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
	if item.z_after_part != "":
		var ref := (_parts[item.z_after_part]["art"] as Sprite2D) if _parts.has(item.z_after_part) else null
		if ref == null:
			push_warning("[DRPuppet] z_after_part 파트를 찾을 수 없습니다: %s — z_index %d 를 씁니다" % [item.z_after_part, item.z_index])
		else:
			var gap := _z_gap()
			if gap == 0:
				push_warning("[DRPuppet] 이 씬은 파트 z 간격이 1 이라 장비를 파트 사이에 끼울 수 없습니다(같은 z 로 둠). 다시 구우면 간격 10 으로 나옵니다.")
			spr.z_index = ref.z_index + gap
			_z_follow[item.slot] = {"art": ref, "gap": gap}
			set_process(true)
	spr.modulate = item.modulate
	spr.material = _art_material
	# 본체 파트 스프라이트와 완전히 같은 규격으로 배치한다.
	# 그림은 캔버스(레스트) 방향 그대로다. stretch 는 레스트 각(ra)만큼 돌아 있어 −ra 로 되돌리고,
	# 뼈(레스트 회전 0)에 바로 붙일 때는 돌리지 않는다(09-29: 뼈에 붙이면서도 −ra 를 줘서 총이 레스트 각만큼 틀어졌다)
	var on_stretch: bool = host == info["stretch"]
	spr.rotation = (-ra if on_stretch else 0.0) + item.angle
	spr.set_meta("equip_angle", item.angle)
	spr.position = (item.offset - Vector2(info["rest_head"])).rotated(-ra if on_stretch else 0.0)
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
	# 앞 조각 — 파트의 그 부분을 파트에 붙여 장비 바로 위에
	var ovs: Array = []
	for o in item.overlays:
		var od: Dictionary = o
		var pn := String(od.get("part", ""))
		if not _parts.has(pn) or (od.get("texture") == null and not (String(od.get("kind", "part")) in ["hide", "raise"])):
			continue
		if String(od.get("kind", "part")) == "raise":
			var rart := _parts[pn]["art"] as Sprite2D
			if rart != null:
				var lst: Array = _raised.get(item.slot, [])
				lst.append({"art": rart, "orig": rart.z_index, "rank": int(od.get("rank", 0))})
				_raised[item.slot] = lst
				rart.z_index = spr.z_index + 1 + int(od.get("rank", 0))
				set_process(true)
			continue
		var pinfo: Dictionary = _parts[pn]
		var kind := String(od.get("kind", "part"))
		if kind == "hide":
			_set_part_drawn(pn, false)
			var hp: PackedStringArray = _hidden_parts.get(item.slot, PackedStringArray())
			hp.append(pn)
			_hidden_parts[item.slot] = hp
			continue
		var os := Sprite2D.new()
		os.texture = od["texture"]
		os.centered = false
		os.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		os.z_as_relative = false
		os.modulate = item.modulate
		os.material = _art_material
		os.set_meta("kind", kind)
		if kind == "weapon":
			# 총 조각 — 장비와 같이 움직이고(장비의 호스트에), 그 파트 바로 위에 그린다
			os.name = "equip_%s_over_%s" % [item.slot, pn]
			os.rotation = spr.rotation
			os.position = (Vector2(od.get("offset", Vector2.ZERO)) - Vector2(info["rest_head"])).rotated(spr.rotation)
			var pref := pinfo["art"] as Sprite2D
			os.z_index = (pref.z_index + 1) if pref != null else spr.z_index + 1
			host.add_child(os)
			if pref != null:
				_ov_follow.append({"spr": os, "art": pref})
				set_process(true)
		else:
			# 앞 조각 — 파트의 그 부분을 파트에 붙여 장비 바로 위에
			var phost: Node2D = pinfo["stretch"] if pinfo["stretch"] != null else pinfo["bone"]
			var pra: float = pinfo["rest_angle"]
			os.name = "equip_%s_front_%s" % [item.slot, pn]
			os.z_index = spr.z_index + 1
			os.rotation = -pra
			os.position = (Vector2(od.get("offset", Vector2.ZERO)) - Vector2(pinfo["rest_head"])).rotated(-pra)
			phost.add_child(os)
		ovs.append(os)
	_equipped_overlays[item.slot] = ovs

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
	for o in _equipped_overlays.get(slot, []):
		if is_instance_valid(o):
			(o as Node).queue_free()
	for r in _raised.get(slot, []):
		var ra := (r as Dictionary)["art"] as Sprite2D
		if is_instance_valid(ra):
			ra.z_index = int((r as Dictionary)["orig"])   # 수동 순서 씬은 이 값이 그대로 남는다(자동 순서 씬은 다음 프레임 애니가 덮어씀)
	_raised.erase(slot)
	for hp in _hidden_parts.get(slot, PackedStringArray()):
		_set_part_drawn(String(hp), true)
	_hidden_parts.erase(slot)
	var keep: Array = []
	for f in _ov_follow:
		var fs := (f as Dictionary)["spr"] as Sprite2D
		if is_instance_valid(fs) and not _equipped_overlays.get(slot, []).has(fs):
			keep.append(f)
	_ov_follow = keep
	_equipped_overlays.erase(slot)
	_z_follow.erase(slot)
	if _z_follow.is_empty() and _ov_follow.is_empty() and _raised.is_empty():
		set_process(false)
	if _equipped_outline.has(slot):
		var o: Node = _equipped_outline[slot]
		if is_instance_valid(o):
			o.queue_free()
		_equipped_outline.erase(slot)
	unequipped.emit(slot)


## 파트 사이에 장비가 끼어들 z 여유(파트 z 간격의 절반). 간격이 1 인 옛 씬은 0.
func _z_gap() -> int:
	var zs: Array = []
	for k in _parts.keys():
		var art := _parts[k]["art"] as Sprite2D
		if art != null and not zs.has(art.z_index):
			zs.append(art.z_index)
	zs.sort()
	var step := 0
	for i in range(1, zs.size()):
		var d := int(zs[i]) - int(zs[i - 1])
		if d > 0 and (step == 0 or d < step):
			step = d
	return int(step / 2.0)


func unequip_all() -> void:
	for s in _equipped.keys().duplicate():
		unequip(String(s))


func get_equipped(slot: String) -> Sprite2D:
	return _equipped.get(slot, null)


## 장비의 앞 조각 스프라이트들(없으면 빈 배열)
func get_equipped_overlays(slot: String) -> Array:
	return _equipped_overlays.get(slot, [])


## 장비의 전체 실루엣 밑깔개(없으면 null — 파트별 아웃라인이거나 아웃라인 없이 구운 씬)
func get_equipped_outline(slot: String) -> Sprite2D:
	return _equipped_outline.get(slot, null)


## 파트의 그림(본체 + 밑깔개) 보이기/숨기기 — 장비의 숨김 규칙용. 뼈는 그대로라 애니·조준에는 영향 없다
func _set_part_drawn(part: String, on: bool) -> void:
	var info: Dictionary = _parts[part]
	var b := info["bone"] as Bone2D
	for n in ["stretch/art", "stretch/outline"]:
		var c := b.get_node_or_null(n) as CanvasItem
		if c != null:
			c.visible = on


## 복장 입기 — 파트 그림을 다른 옷으로 구운 그림으로 바꿔 끼운다(머리 · 손처럼 안 준 파트는 그대로).
## parts = { 파트 이름: {"texture": Texture2D, "crop": Vector2(캔버스에서 그림 왼쪽 위)} }
## 같은 뼈대 · 같은 카메라 · 같은 레스트 자세로 구운 그림이어야 맞는다(DROutfit / outfit_bake_cli 가 그렇게 굽는다).
## 배치 공식은 익스포터와 같다: (crop − 레스트 피벗)을 레스트 각만큼 되돌림. 처음 바꿀 때 원래 그림을 기억해 둔다.
var _worn: Dictionary = {}   # part -> {art_tex, art_pos, ol_tex, ol_pos} — 원래 그림(벗을 때 되돌림)

func wear_parts(parts: Dictionary) -> int:
	if _parts.is_empty():
		rebuild_index()
	var n := 0
	for pn in parts.keys():
		if not _parts.has(pn):
			continue
		var d: Dictionary = parts[pn]
		var tex := d.get("texture", null) as Texture2D
		if tex == null:
			continue
		var info: Dictionary = _parts[pn]
		var b := info["bone"] as Bone2D
		var art := b.get_node_or_null("stretch/art") as Sprite2D
		if art == null:
			continue
		var ol := b.get_node_or_null("stretch/outline") as Sprite2D
		if not _worn.has(pn):
			_worn[pn] = {"art_tex": art.texture, "art_pos": art.position,
				"ol_tex": ol.texture if ol != null else null, "ol_pos": ol.position if ol != null else Vector2.ZERO}
		var ra: float = info["rest_angle"]
		var pos := (Vector2(d.get("crop", Vector2.ZERO)) - Vector2(info["rest_head"])).rotated(-ra)
		art.texture = tex
		art.position = pos
		if ol != null:
			ol.texture = tex
			ol.position = pos
		n += 1
	return n


## 복장 벗기 — 바꿔 끼운 파트를 원래(구운 몸) 그림으로 되돌린다
func take_off_outfit() -> void:
	for pn in _worn.keys():
		if not _parts.has(pn):
			continue
		var w: Dictionary = _worn[pn]
		var b := (_parts[pn] as Dictionary)["bone"] as Bone2D
		var art := b.get_node_or_null("stretch/art") as Sprite2D
		if art != null:
			art.texture = w["art_tex"]
			art.position = w["art_pos"]
		var ol := b.get_node_or_null("stretch/outline") as Sprite2D
		if ol != null:
			ol.texture = w["ol_tex"]
			ol.position = w["ol_pos"]
	_worn.clear()


## 파트 본체 스프라이트 색만 바꾸기(팔레트 스왑의 가장 싼 형태).
func tint_part(part: String, color: Color) -> void:
	if not _parts.has(part):
		return
	var info: Dictionary = _parts[part]
	var host: Node2D = info["stretch"] if info["stretch"] != null else info["bone"]
	var art := host.get_node_or_null("art") as Sprite2D
	if art != null:
		art.modulate = color
