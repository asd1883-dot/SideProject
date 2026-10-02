@tool
extends RefCounted
class_name DROutfitBaker

## 복장 굽기 코어 — 옷을 입은 모델(기본 몸과 같은 뼈대)을 기본 몸 세트마다 **같은 카메라 · 같은 레스트 자세**로 놓고
## 옷 파트만 그린다. 결과를 기본 몸 퍼펫(DRPuppetSet)에 바꿔 끼우면 옷만 갈아입는다(DROutfit · wear()).
## 창(DROutfitWindow)과 명령줄(outfit_bake_cli)이 같이 쓴다.
##
##   var ob := DROutfitBaker.new()
##   ob.baker = baker            # 옷 모델로 setup 한 DRBaker (프리셋의 도트화 값 · 추가 동작 폴더는 기본 몸과 같게)
##   ob.setup("res://puppet/sets.json")
##   var res := await ob.run("res://outfits", "m36")

signal progress(i: int, n: int, label: String)

## 파트 → 슬롯. top = 상의 · bottom = 하의 · shoes = 신발 · "" = 안 씀(기본 몸 그대로, 예: 머리 · 손)
const DEFAULT_SLOTS := {
	"Torso": "top", "L_UpperArm": "top", "L_Forearm": "top", "R_UpperArm": "top", "R_Forearm": "top",
	"Hips": "bottom", "L_Thigh": "bottom", "L_Calf": "bottom", "R_Thigh": "bottom", "R_Calf": "bottom",
	"L_Foot": "shoes", "R_Foot": "shoes",
	"Head": "", "L_Hand": "", "R_Hand": "",
}
const SLOT_NAMES := {"top": "상의", "bottom": "하의", "shoes": "신발", "": "안 씀"}

var baker: DRBaker
var eb: DREquipBaker          # 세트 세우기(apply_set · read_sets)는 장비 굽기와 같다
var sets_json := "res://puppet/sets.json"
var sets: Array = []
var slots: Dictionary = DEFAULT_SLOTS.duplicate()
var warnings: PackedStringArray = PackedStringArray()


func setup(p_sets_json: String) -> bool:
	sets_json = p_sets_json
	eb = DREquipBaker.new()
	eb.baker = baker
	eb.sets_json = sets_json
	sets = eb.read_sets()
	warnings = eb.warnings.duplicate()
	return not sets.is_empty()


## 굽는 파트(슬롯이 있는 것)
func wear_parts() -> Array:
	var out: Array = []
	for pn in slots.keys():
		if String(slots[pn]) != "":
			out.append(pn)
	return out


## 세트 하나: 그 세트의 카메라 · 레스트로 세우고 옷 파트를 한 장씩 그린다 → {파트: {image: Image, crop: Rect2i}}
func bake_set(sd: Dictionary) -> Dictionary:
	var out := {}
	if not eb.apply_set(sd):
		warnings.append("%s — 세트를 세울 수 없습니다: %s" % [String(sd.get("name", "")), ", ".join(eb.warnings)])
		return out
	await RenderingServer.frame_post_draw
	var grow := int((sd["rig"] as Dictionary).get("outline_px", 0))
	for pn in wear_parts():
		if not baker.part_nodes.has(pn):
			continue
		var img: Image = await baker.render_part(pn)
		var used := img.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			continue
		if grow > 0:   # 아웃라인은 셰이더가 텍스처 안에만 그리므로 그 두께만큼 여유(익스포터와 같게)
			used = used.grow(grow).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		out[pn] = {"image": img.get_region(used), "crop": used}
	return out


## 모든 세트(only_set 을 주면 그 세트만) → {세트 이름: {파트: {image, crop}}}
func bake_all(only_set: String = "") -> Dictionary:
	var res := {}
	var n := sets.size()
	for i in n:
		var sd: Dictionary = sets[i]
		var sname := String(sd["name"])
		if only_set != "" and sname != only_set:
			continue
		progress.emit(i, n, sname)
		res[sname] = await bake_set(sd)
	return res


## 구운 것을 바로 입힐 수 있는 DROutfit 으로(메모리 — 파일을 안 거침)
func to_outfit(baked: Dictionary, id: String = "") -> DROutfit:
	var o := DROutfit.new()
	o.id = id
	o.slots = slots.duplicate()
	for sname in baked.keys():
		var parts := {}
		for pn in (baked[sname] as Dictionary).keys():
			var d: Dictionary = baked[sname][pn]
			parts[pn] = {"texture": ImageTexture.create_from_image(d["image"]), "crop": Vector2((d["crop"] as Rect2i).position)}
		o.sets[sname] = parts
	return o


## 굽고 파일로 남긴다: <out_root>/<id>/outfit.json + <세트 폴더>/parts/<파트>.png
func run(out_root: String, id: String, model_path: String = "") -> Dictionary:
	warnings = PackedStringArray()
	var root := out_root.path_join(id)
	var baked: Dictionary = await bake_all()
	var doc := {"version": 1, "id": id, "model": model_path, "sets_json": sets_json, "slots": slots.duplicate(), "sets": {}}
	var dirs := {}
	for s in sets:
		dirs[String((s as Dictionary)["name"])] = String((s as Dictionary).get("dir", (s as Dictionary)["name"])).validate_filename()
	for sname in baked.keys():
		var sdir := String(dirs.get(sname, String(sname).validate_filename()))
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root.path_join(sdir).path_join("parts")))
		var parts := {}
		for pn in (baked[sname] as Dictionary).keys():
			var d: Dictionary = baked[sname][pn]
			var rel := sdir.path_join("parts").path_join("%s.png" % pn)
			(d["image"] as Image).save_png(root.path_join(rel))
			var c: Rect2i = d["crop"]
			parts[pn] = {"image": rel, "crop": [c.position.x, c.position.y, c.size.x, c.size.y]}
		doc["sets"][sname] = {"dir": sdir, "parts": parts}
	var jp := root.path_join("outfit.json")
	var f := FileAccess.open(jp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "쓸 수 없습니다: %s" % jp}
	f.store_string(JSON.stringify(doc, "\t"))
	f.close()
	return {"ok": true, "json": jp, "sets": baked.keys(), "warnings": warnings}
