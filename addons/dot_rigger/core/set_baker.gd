@tool
extends RefCounted
class_name DRSetBaker

## "리깅 애니메이션 세트" 여러 벌을 순서대로 굽는다.
##
## 세트 = { name, rest_anim, rest_time(0~1 비율), animations: PackedStringArray }
## 서기·엎드리기·수영처럼 몸 방향이 다른 계열은 파트 그림 자체가 달라야 하므로
## 세트마다 자기 레스트 자세로 따로 구워 <base_dir>/<세트 이름>/ 에 넣고,
## <base_dir>/sets.json 에 세트 목록(순서·레스트·동작·씬 경로)을 남긴다.
## 시점·도트화·그리기 순서 등 나머지 설정은 세트 공통(cfg / baker.opts).
##
## 세트를 빼거나 이름을 바꾸면 옛 폴더가 남는다 — 전부 성공한 굽기 끝에 **지난번 sets.json 에 있었고
## 이번 목록에는 없는 폴더**만 치운다(_clean_stale). 지난번 sets.json 에 없던 폴더는 건드리지 않는다.

signal progress(set_index: int, set_count: int, set_name: String, stage: String, cur: int, total: int)

var baker: DRBaker
## 세트마다 만든 익스포터(에디터에서 PNG 임포트 뒤 rebuild_scene() 을 부르기 위해 남겨 둔다)
var exporters: Array = []


## 세트 이름 → 폴더 이름. 파일명에 못 쓰는 글자(: / \ ? * " | % < >)는 _ 로 바꾸고, 비면 번호.
static func dir_name(set_name: String, index: int) -> String:
	var n := set_name.strip_edges().validate_filename()
	return n if n != "" else "set%d" % (index + 1)


func run(sets: Array, base_dir: String, cfg: Dictionary) -> Dictionary:
	exporters.clear()
	if baker == null or baker.rig == null:
		return {"ok": false, "error": "baker 미설정"}
	if sets.is_empty():
		return {"ok": false, "error": "세트가 없습니다"}
	var orig_anim: String = baker.opts.rest_anim
	var orig_time: float = baker.opts.rest_time
	var entries: Array = []
	var all_ok := true
	var first_scene := ""
	var errors := PackedStringArray()
	for i in sets.size():
		var s: Dictionary = sets[i]
		var name := String(s.get("name", ""))
		var dn := dir_name(name, i)
		var rest := String(s.get("rest_anim", ""))
		var frac := clampf(float(s.get("rest_time", 0.0)), 0.0, 1.0)
		var ran := baker.resolve_anim(rest)
		var sec := 0.0
		if ran != "":
			sec = baker.anim_player.get_animation(ran).length * frac
		baker.opts.rest_anim = rest
		baker.opts.rest_time = sec

		_match_dir_case(base_dir, dn)
		var ex := DRExporter.new()
		ex.baker = baker
		ex.out_dir = base_dir.path_join(dn)
		ex.anim_names = PackedStringArray(s.get("animations", PackedStringArray()))
		# 그리기 순서는 세트에 있으면 세트 것(자동이면 빈 값 = 프레임별 깊이), 없으면 공통 cfg
		var set_cfg := cfg.duplicate()
		if s.has("z_auto"):
			set_cfg["z_override"] = PackedStringArray() if bool(s["z_auto"]) \
				else PackedStringArray(s.get("z_order", PackedStringArray()))
		ex.apply_cfg(set_cfg)
		var idx := i
		ex.progress.connect(func(stage: String, cur: int, total: int):
			progress.emit(idx, sets.size(), name, stage, cur, total))
		var r: Dictionary = await ex.run()
		exporters.append(ex)
		var ok := bool(r.get("ok", false))
		all_ok = all_ok and ok
		if not ok:
			errors.append("%s: %s" % [name, String(r.get("error", "?"))])
		if first_scene == "" and ok:
			first_scene = String(r.get("scene", ""))
		entries.append({
			"index": i,
			"name": name,
			"dir": dn,
			"scene": dn + "/puppet.tscn",
			"pixel_scene": (dn + "/" + DRExporter.PIXEL_SCENE) if ex.pixel_grid else "",   # 도트 격자 고정 래퍼(있으면 게임에는 이걸)
			"rig": dn + "/rig.json",
			"rest_anim": rest,
			"rest_time": frac,
			"rest_time_sec": sec,
			"animations": Array(r.get("animations", [])),
			"z_order_manual": ex.z_override.size() > 0,
			"layer_order": Array(ex.resolve_layer_order()) if ok else [],   # 뒤 -> 앞, 이 세트에 실제로 쓴 순서
			"kept": Array(r.get("kept", PackedStringArray())),
			"dropped_reason": String(r.get("dropped_reason", "")),
			"ok": ok,
		})
	baker.opts.rest_anim = orig_anim
	baker.opts.rest_time = orig_time

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_dir))
	var old_dirs := _listed_dirs(base_dir.path_join("sets.json"))   # 덮어쓰기 전에 읽는다
	var doc := {"version": 1, "base": base_dir, "sets": entries}
	var f := FileAccess.open(base_dir.path_join("sets.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(doc, "\t"))
		f.close()
	# 하나라도 실패했으면 옛 것을 남겨 둔다
	var cleaned := {"removed": PackedStringArray(), "left": PackedStringArray()}
	if all_ok:
		var now_dirs := PackedStringArray()
		for e in entries:
			now_dirs.append(String(e["dir"]))
		cleaned = _clean_stale(base_dir, old_dirs, now_dirs)
	return {
		"ok": all_ok,
		"error": ", ".join(errors),
		"sets": entries,
		"scene": first_scene,
		"json": base_dir.path_join("sets.json"),
		"removed_dirs": cleaned["removed"],   # 치운 옛 세트 폴더
		"left_dirs": cleaned["left"],         # 툴이 만들지 않은 파일이 있어 남긴 옛 세트 폴더
	}


## 세트 이름의 대소문자만 바꿨을 때(stand → Stand) 디스크의 폴더 이름도 따라 바꾼다.
## Windows 는 둘을 같은 폴더로 열어 주지만 sets.json 의 경로와 글자가 달라, 대소문자를 가리는 플랫폼으로 내보내면 못 연다.
static func _match_dir_case(base_dir: String, dn: String) -> void:
	var abs_base := ProjectSettings.globalize_path(base_dir)
	if not DirAccess.dir_exists_absolute(abs_base):
		return
	for d in DirAccess.get_directories_at(abs_base):
		if d != dn and d.to_lower() == dn.to_lower():
			DirAccess.rename_absolute(abs_base.path_join(d), abs_base.path_join(dn))
			return


## sets.json 에 적힌 세트 폴더 이름들(없거나 못 읽으면 빈 목록)
static func _listed_dirs(json_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not FileAccess.file_exists(json_path):
		return out
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not (parsed is Dictionary):
		return out
	var sets: Variant = (parsed as Dictionary).get("sets", [])
	if not (sets is Array):
		return out
	for e in sets:
		if e is Dictionary:
			out.append(String((e as Dictionary).get("dir", "")))
	return out


## 지난번 목록(old_dirs)에 있었고 이번 목록(now_dirs)에 없는 세트 폴더를 치운다.
## 툴이 만든 파일(puppet.tscn · puppet_pixel.tscn · rig.json · parts/ 의 PNG 와 .import)만 지우고,
## 다른 파일이 들어 있으면 그 파일과 폴더는 남긴다(left).
## 폴더 이름은 대소문자를 가리지 않고 견준다 — Windows 에서 "idle" 과 "Idle" 은 같은 폴더라, 가려 견주면 방금 구운 걸 지운다.
static func _clean_stale(base_dir: String, old_dirs: PackedStringArray, now_dirs: PackedStringArray) -> Dictionary:
	var removed := PackedStringArray()
	var left := PackedStringArray()
	var now := {}
	for d in now_dirs:
		now[d.to_lower()] = true
	var seen := {}
	for dn in old_dirs:
		var key := dn.to_lower()
		if now.has(key) or seen.has(key):
			continue
		seen[key] = true
		# 폴더 이름 하나여야 한다(sets.json 을 손으로 고쳐 "..", "a/b" 같은 게 들어와도 밖을 지우지 않게)
		if dn == "" or dn != dn.validate_filename() or dn.begins_with("."):
			continue
		var abs_dir := ProjectSettings.globalize_path(base_dir.path_join(dn))
		if not DirAccess.dir_exists_absolute(abs_dir):
			continue
		for fn in ["puppet.tscn", DRExporter.PIXEL_SCENE, "rig.json"]:
			_rm_file(abs_dir.path_join(fn))
		var parts_dir := abs_dir.path_join("parts")
		if DirAccess.dir_exists_absolute(parts_dir):
			for fn in DirAccess.get_files_at(parts_dir):
				if fn.ends_with(".png") or fn.ends_with(".png.import"):
					_rm_file(parts_dir.path_join(fn))
			if _is_empty_dir(parts_dir):
				DirAccess.remove_absolute(parts_dir)
		if _is_empty_dir(abs_dir):
			DirAccess.remove_absolute(abs_dir)
			removed.append(dn)
		else:
			left.append(dn)
	return {"removed": removed, "left": left}


static func _rm_file(abs_path: String) -> void:
	if FileAccess.file_exists(abs_path):
		DirAccess.remove_absolute(abs_path)


static func _is_empty_dir(abs_path: String) -> bool:
	return DirAccess.get_files_at(abs_path).is_empty() and DirAccess.get_directories_at(abs_path).is_empty()
