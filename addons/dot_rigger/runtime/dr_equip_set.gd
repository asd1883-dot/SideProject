@tool
extends Resource
class_name DREquipSet

## 장비 한 점의 "세트별 묶음". 무기 하나 = 이 리소스 하나.
##
## 세트(서기/앉기/엎드리기)마다 레스트 자세의 손 방향이 달라서 장비 그림도 세트마다 한 장씩 필요하다.
## 그 그림들(DREquipItem)을 세트 이름으로 묶어 두면 DRPuppetSet.equip() 한 번에 모든 세트에 장착된다 —
## 동작이 바뀌어 세트가 넘어가도 무기가 그대로 들려 있다.

## 장비 이름(예: "kar98k")
@export var id: String = ""
## 슬롯. 한 슬롯에는 하나만 장착된다(예: "weapon"). items 의 각 DREquipItem.slot 과 같아야 한다
@export var slot: String = "weapon"
## 세트 이름(sets.json 의 name) -> DREquipItem
@export var items: Dictionary = {}


## 이 세트용 장착 정보(없으면 null)
func item_for(set_name: String) -> DREquipItem:
	return items.get(set_name, null) as DREquipItem


## 장비 굽기가 남긴 equip.json 을 읽어 만든다(못 읽으면 null).
##   var rifle := DREquipSet.load_json("res://equip/kar98k/equip.json")
##   soldier.equip(rifle)
static func load_json(path: String) -> DREquipSet:
	if not FileAccess.file_exists(path):
		push_warning("[DREquipSet] 파일이 없습니다: %s" % path)
		return null
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (doc is Dictionary):
		push_warning("[DREquipSet] 읽을 수 없습니다: %s" % path)
		return null
	var d: Dictionary = doc
	var es := DREquipSet.new()
	es.id = String(d.get("id", ""))
	es.slot = String(d.get("slot", "weapon"))
	var base := path.get_base_dir()
	var sets: Dictionary = d.get("sets", {})
	for set_name in sets.keys():
		var sd: Dictionary = sets[set_name]
		var tex := _load_texture(base.path_join(String(sd.get("image", ""))))
		if tex == null:
			continue
		var it := DREquipItem.new()
		it.slot = es.slot
		it.part = String(d.get("part", ""))
		it.texture = tex
		var off: Array = sd.get("offset", [0, 0])
		it.offset = Vector2(float(off[0]), float(off[1]))
		it.z_index = int(d.get("z_index", 1000))
		it.z_after_part = String(d.get("z_after_part", ""))
		it.follow_stretch = bool(d.get("follow_stretch", false))
		es.items[String(set_name)] = it
	return es


## 임포트된 텍스처가 있으면 그것, 없으면(방금 구워 아직 임포트 전) PNG 파일을 바로 읽는다
static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		if img != null:
			return ImageTexture.create_from_image(img)
	push_warning("[DREquipSet] 그림을 찾을 수 없습니다: %s" % path)
	return null
