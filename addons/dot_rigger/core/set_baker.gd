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
	var doc := {"version": 1, "base": base_dir, "sets": entries}
	var f := FileAccess.open(base_dir.path_join("sets.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(doc, "\t"))
		f.close()
	return {
		"ok": all_ok,
		"error": ", ".join(errors),
		"sets": entries,
		"scene": first_scene,
		"json": base_dir.path_join("sets.json"),
	}
