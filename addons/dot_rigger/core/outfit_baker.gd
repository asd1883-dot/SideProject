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

## 파트 → 슬롯. top = 상의 · bottom = 하의(발 · 신발 포함) · "" = 안 씀(기본 몸 그대로, 예: 머리 · 손)
## 옷은 상의 · 하의 두 가지뿐(10-06 사용자). 옛 outfit.json 의 "shoes" 는 하의로 친다(DROutfit.slot_parts).
const DEFAULT_SLOTS := {
	"Torso": "top", "L_UpperArm": "top", "L_Forearm": "top", "R_UpperArm": "top", "R_Forearm": "top",
	"Hips": "bottom", "L_Thigh": "bottom", "L_Calf": "bottom", "R_Thigh": "bottom", "R_Calf": "bottom",
	"L_Foot": "bottom", "R_Foot": "bottom",
	"Head": "", "L_Hand": "", "R_Hand": "",
}
const SLOT_NAMES := {"top": "상의", "bottom": "하의", "": "안 씀"}
const ALL_PARTS := ["Head", "Torso", "Hips", "L_UpperArm", "L_Forearm", "L_Hand", "R_UpperArm", "R_Forearm", "R_Hand",
	"L_Thigh", "L_Calf", "L_Foot", "R_Thigh", "R_Calf", "R_Foot"]

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


## 기본 몸 세트에 다시 자른 파트 그림을 그대로 넣는다(복장 창에서 기본 몸을 칠한 뒤 — 메인 창에서 다시 굽지 않아도 되게).
## baked = bake_all() 결과(기본 몸 모델로, 파트 전부). 세트마다 puppet.tscn 의 파트 그림 · 위치와 parts/*.png · rig.json 의 crop 만 바꾼다.
## 같은 카메라 · 같은 레스트로 그렸으니 뼈 · 동작은 그대로 맞는다. 고친 세트 이름 목록을 돌려준다.
func write_base_sets(baked: Dictionary) -> PackedStringArray:
	var done := PackedStringArray()
	var doc := DREquipBaker._read_json(sets_json)
	var base := sets_json.get_base_dir()
	for e in doc.get("sets", []):
		var sd: Dictionary = e
		var sname := String(sd.get("name", ""))
		if not baked.has(sname) or String(sd.get("scene", "")) == "":
			continue
		var scene_path := base.path_join(String(sd["scene"]))
		var ps := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if ps == null:
			warnings.append("%s — 씬을 열 수 없습니다: %s" % [sname, scene_path])
			continue
		var root := ps.instantiate()
		if not root.has_method("rebuild_index"):
			root.free()
			warnings.append("%s — 퍼펫 씬이 아닙니다: %s" % [sname, scene_path])
			continue
		root.call("rebuild_index")
		var info_all: Dictionary = root.get("_parts")
		var set_dir := scene_path.get_base_dir()
		var rig_path := base.path_join(String(sd.get("rig", "")))
		var rig := DREquipBaker._read_json(rig_path)
		for pn in (baked[sname] as Dictionary).keys():
			if not info_all.has(pn):
				continue
			var d: Dictionary = baked[sname][pn]
			var img: Image = d["image"]
			var c: Rect2i = d["crop"]
			var info: Dictionary = info_all[pn]
			var b := info["bone"] as Bone2D
			var pos := (Vector2(c.position) - Vector2(info["rest_head"])).rotated(-float(info["rest_angle"]))
			var tex := ImageTexture.create_from_image(img)
			for n in ["stretch/art", "stretch/outline"]:
				var s := b.get_node_or_null(n) as Sprite2D
				if s != null:
					s.texture = tex
					s.position = pos
			img.save_png(set_dir.path_join("parts").path_join("%s.png" % pn))
			for rp in rig.get("parts", []):
				if String((rp as Dictionary).get("name", "")) == pn:
					(rp as Dictionary)["crop"] = [c.position.x, c.position.y, c.size.x, c.size.y]
		var out := PackedScene.new()
		out.pack(root)
		root.free()
		out.take_over_path(scene_path)      # 에디터 · 퍼펫 세트가 캐시된 옛 씬을 쓰지 않게
		if ResourceSaver.save(out, scene_path) != OK:
			warnings.append("%s — 씬을 저장할 수 없습니다: %s" % [sname, scene_path])
			continue
		if not rig.is_empty():
			var f := FileAccess.open(rig_path, FileAccess.WRITE)
			if f != null:
				f.store_string(JSON.stringify(rig, "\t"))
				f.close()
		done.append(sname)
	return done


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
