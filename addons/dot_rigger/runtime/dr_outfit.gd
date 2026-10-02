@tool
extends Resource
class_name DROutfit

## 복장 — 옷 모델을 퍼펫의 세트마다(같은 카메라 · 같은 레스트 자세) 구운 파트 그림 묶음.
## 퍼펫(기본 몸)의 그 파트 그림만 바꿔 끼운다. 머리 · 손처럼 복장에 없는 파트는 몸 그대로.
##   굽기: tools/outfit_bake_cli.gd → res://outfits/<id>/outfit.json + <세트>/parts/<파트>.png
##   쓰기: DRPuppetSet.wear(DROutfit.load_json("res://outfits/m36/outfit.json")) / take_off()
##
## 상의 · 하의를 따로 섞으려면 only_parts 로 일부 파트만 입힌다(예: 상의 = Torso · 팔).

@export var id: String = ""
## 세트 이름 -> { 파트 이름: {"texture": Texture2D, "crop": Vector2} }
@export var sets: Dictionary = {}
## 파트 -> 슬롯("top" 상의 · "bottom" 하의 · "shoes" 신발). 복장 굽기 창에서 정한 것 — 비면 아래 기본 묶음
@export var slots: Dictionary = {}

## 상의 · 하의 · 신발 기본 묶음(파트 이름) — slots 가 없는 옛 outfit.json 용
const TOP := ["Torso", "L_UpperArm", "L_Forearm", "R_UpperArm", "R_Forearm"]
const BOTTOM := ["Hips", "L_Thigh", "L_Calf", "R_Thigh", "R_Calf"]
const SHOES := ["L_Foot", "R_Foot"]


## 그 슬롯에 든 파트들(slot = "top" · "bottom" · "shoes")
func slot_parts(slot: String) -> Array:
	if slots.is_empty():
		match slot:
			"top":
				return TOP
			"bottom":
				return BOTTOM
			"shoes":
				return SHOES
		return []
	var out: Array = []
	for pn in slots.keys():
		if String(slots[pn]) == slot:
			out.append(pn)
	return out


## 그 세트에서 입힐 파트들(only 가 비면 전부)
func parts_for(set_name: String, only: Array = []) -> Dictionary:
	var all: Dictionary = sets.get(set_name, {})
	if only.is_empty():
		return all
	var out := {}
	for pn in only:
		if all.has(pn):
			out[pn] = all[pn]
	return out


static func load_json(path: String) -> DROutfit:
	if not FileAccess.file_exists(path):
		push_warning("[DROutfit] 파일이 없습니다: %s" % path)
		return null
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (v is Dictionary):
		push_warning("[DROutfit] 읽을 수 없습니다: %s" % path)
		return null
	var d: Dictionary = v
	var o := DROutfit.new()
	o.id = String(d.get("id", path.get_base_dir().get_file()))
	o.slots = (d.get("slots", {}) as Dictionary).duplicate()
	var base := path.get_base_dir()
	var ss: Dictionary = d.get("sets", {})
	for sn in ss.keys():
		var parts: Dictionary = (ss[sn] as Dictionary).get("parts", {})
		var out := {}
		for pn in parts.keys():
			var pd: Dictionary = parts[pn]
			var tex := _load_texture(base.path_join(String(pd.get("image", ""))))
			if tex == null:
				continue
			var c: Array = pd.get("crop", [0, 0, 0, 0])
			out[pn] = {"texture": tex, "crop": Vector2(float(c[0]), float(c[1]))}
		o.sets[String(sn)] = out
	return o


## 가져오기(import)된 그림은 그대로, 아직 안 됐으면(명령줄로 방금 구운 것) PNG 를 직접 읽는다
static func _load_texture(p: String) -> Texture2D:
	if ResourceLoader.exists(p, "Texture2D"):
		return load(p) as Texture2D
	if FileAccess.file_exists(p):
		var img := Image.load_from_file(ProjectSettings.globalize_path(p))
		if img != null:
			return ImageTexture.create_from_image(img)
	return null
