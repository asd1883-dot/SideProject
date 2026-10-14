@tool
extends RefCounted
class_name DRBoneMapAuto

## 추가 동작 파일(Mixamo FBX 등)에 BoneMap(리타깃)을 자동으로 넣는다.
## 10-14 사용자: "이거 자동화 안 돼? 매번 너한테 물어봐야 해?" — 폴더에 FBX 를 넣을 때마다 고급 임포트 설정에서 손으로 넣어야 했다.
##
## 규칙: **같은 폴더의 다른 파일이 이미 BoneMap 을 쓰고 있고**, 새 파일의 뼈 이름이 그 표와 MIN_MATCH 이상 맞으면 같은 표를 넣는다.
##       BoneMap 을 쓰는 파일이 없는 폴더(예: models/ 의 원본 모델)는 건드리지 않는다.
## 같이: 이 파일들은 동작만 쓰므로 FBX · glTF 안의 텍스처는 꺼내지 않는다(Mixamo 를 With Skin 으로 받으면 그림이 수십 MB 쏟아진다).
## 에디터에서는 plugin.gd 가 가져오기가 끝날 때마다 부르고, 고친 파일을 다시 가져온다. 이 파일은 판정 · .import 쓰기만 한다.

const SCENE_EXT := ["fbx", "glb", "gltf"]
const MIN_MATCH := 0.8
const SKIP_DIRS := [".godot", ".git", "addons"]


## 고칠 것 [{ path, bonemap, skeleton_path, match }]. paths 가 비면 res:// 전체를 훑는다
static func find_fixes(paths: PackedStringArray = PackedStringArray()) -> Array:
	var files := paths if paths.size() > 0 else _all_scene_files("res://")
	var out := []
	var folder_maps := {}
	for p in files:
		var fix := check(String(p), folder_maps)
		if not fix.is_empty():
			out.append(fix)
	return out


## 파일 하나 — 고쳐야 하면 { path, bonemap, skeleton_path, match }, 아니면 {}
## folder_maps = 폴더 → 그 폴더 파일들이 쓰는 BoneMap 경로들(여러 파일을 볼 때 다시 읽지 않게)
static func check(path: String, folder_maps: Dictionary = {}) -> Dictionary:
	if not SCENE_EXT.has(path.get_extension().to_lower()):
		return {}
	var cfg := ConfigFile.new()
	if cfg.load(path + ".import") != OK or String(cfg.get_value("remap", "importer", "")) != "scene":
		return {}
	if not bone_maps_in(cfg).is_empty():
		return {}                                      # 이미 지정됨
	var dir := path.get_base_dir()
	if not folder_maps.has(dir):
		folder_maps[dir] = _folder_bone_maps(dir)
	var cands: PackedStringArray = folder_maps[dir]
	if cands.is_empty():
		return {}
	if not ResourceLoader.exists(path):
		return {}                                      # 아직 안 가져옴 — 가져오기가 끝나면 다시 불린다
	var scene := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene == null:
		return {}
	var root := scene.instantiate()
	var out := {}
	var sk := _find_skeleton(root)
	if sk != null:
		var best := ""
		var best_m := 0.0
		for bm_path in cands:
			var m := match_ratio(sk, load(bm_path) as BoneMap)
			if m > best_m:
				best_m = m
				best = bm_path
		if best != "" and best_m >= MIN_MATCH:
			out = {"path": path, "bonemap": best, "skeleton_path": "PATH:" + String(root.get_path_to(sk)), "match": best_m}
	root.free()
	return out


## 표가 가리키는 뼈 이름 중 뼈대에 있는 비율(0~1)
static func match_ratio(sk: Skeleton3D, bm: BoneMap) -> float:
	if sk == null or bm == null or bm.profile == null:
		return 0.0
	var total := 0
	var hit := 0
	for i in bm.profile.bone_size:
		var want := String(bm.get_skeleton_bone_name(bm.profile.get_bone_name(i)))
		if want == "":
			continue
		total += 1
		if sk.find_bone(want) >= 0:
			hit += 1
	return float(hit) / float(total) if total > 0 else 0.0


## .import 에 BoneMap 을 넣고 텍스처는 꺼내지 않게 한다. 다시 가져오기는 부른 쪽이(에디터: reimport_files)
static func apply(fix: Dictionary) -> bool:
	var path: String = fix["path"]
	var cfg := ConfigFile.new()
	if cfg.load(path + ".import") != OK:
		return false
	var sub = cfg.get_value("params", "_subresources", {})
	if not (sub is Dictionary):
		sub = {}
	var nodes = (sub as Dictionary).get("nodes", {})
	if not (nodes is Dictionary):
		nodes = {}
	var nd = (nodes as Dictionary).get(fix["skeleton_path"], {})
	if not (nd is Dictionary):
		nd = {}
	nd["retarget/bone_map"] = load(String(fix["bonemap"]))
	nodes[fix["skeleton_path"]] = nd
	sub["nodes"] = nodes
	cfg.set_value("params", "_subresources", sub)
	for key in ["fbx/embedded_image_handling", "gltf/embedded_image_handling"]:
		if cfg.has_section_key("params", key):
			cfg.set_value("params", key, 0)            # 0 = 텍스처 버림(동작만 쓴다)
	return cfg.save(path + ".import") == OK


## .import 안에서 쓰는 BoneMap 경로들
static func bone_maps_in(cfg: ConfigFile) -> PackedStringArray:
	var out := PackedStringArray()
	var sub = cfg.get_value("params", "_subresources", {})
	if not (sub is Dictionary):
		return out
	var nodes = (sub as Dictionary).get("nodes", {})
	if not (nodes is Dictionary):
		return out
	for k in (nodes as Dictionary).keys():
		var nd = nodes[k]
		if nd is Dictionary and (nd as Dictionary).has("retarget/bone_map"):
			var r = nd["retarget/bone_map"]
			if r is Resource and (r as Resource).resource_path != "":
				out.append((r as Resource).resource_path)
	return out


static func _folder_bone_maps(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if not SCENE_EXT.has(String(f).get_extension().to_lower()):
			continue
		var cfg := ConfigFile.new()
		if cfg.load(dir.path_join(f) + ".import") != OK:
			continue
		for bm in bone_maps_in(cfg):
			if not out.has(bm):
				out.append(bm)
	return out


static func _all_scene_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if SCENE_EXT.has(String(f).get_extension().to_lower()):
			out.append(dir.path_join(f))
	for sd in d.get_directories():
		if SKIP_DIRS.has(String(sd)):
			continue
		out.append_array(_all_scene_files(dir.path_join(sd)))
	return out


static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null
