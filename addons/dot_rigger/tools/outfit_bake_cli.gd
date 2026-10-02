extends SceneTree

## 복장 굽기 CLI — 옷을 입은 모델(같은 뼈대)을 퍼펫의 세트마다 같은 카메라 · 같은 레스트 자세로 놓고
## 옷 파트(몸통 · 팔 · 골반 · 다리 · 발)만 그린다. 결과를 기본 몸 퍼펫에 바꿔 끼우면 옷만 갈아입는다.
## 창(프로젝트 > 도구 > Dot Rigger — 복장 굽기)과 같은 코어(DROutfitBaker)를 쓴다.
##
##   godot --path . --resolution 900x700 --script res://addons/dot_rigger/tools/outfit_bake_cli.gd -- \
##       --preset=res://human.tres --sets=res://puppet/sets.json \
##       --model=res://source3d/characters/uniform_m36/uniform_m36.glb --id=m36
##
##   --preset   기본 몸을 구운 프리셋(도트화 값 · 추가 동작 폴더를 같게). 모델만 --model 로 바꾼다
##   --sets     기본 몸으로 구운 sets.json — 세트마다 rig.json 의 카메라(view) · 레스트 자세를 그대로 쓴다
##   --parts    입힐 파트(기본: 머리 · 손 빼고 전부)   --out=res://outfits
## 모델 옆 <이름>.parts.json(부위 칠하기)이 있으면 그대로 따른다.
## 결과: <out>/<id>/outfit.json + <out>/<id>/<세트 폴더>/parts/<파트>.png
## 렌더가 필요하므로 --headless 로는 못 돌린다.

var _args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			s = s.substr(2)
		var eq := s.find("=")
		if eq >= 0:
			_args[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			_args[s] = "1"
	_run.call_deferred()


func _arg(key: String, def: String = "") -> String:
	return String(_args.get(key, def))


func _run() -> void:
	var opts := DRBaker.Options.new()
	var preset_path := _arg("preset", "")
	if preset_path != "":
		var p := load(preset_path) as DRPreset
		if p == null:
			printerr("프리셋을 열 수 없습니다: ", preset_path); quit(1); return
		opts.extra_anim_dir = p.extra_anim_dir
		opts.light_bands = p.light_bands
		opts.ambient = p.ambient
		opts.alpha_threshold = p.alpha_threshold
		opts.color_levels = p.color_levels
		opts.bleed_rings = p.bleed_rings
		opts.composites = p.composites.duplicate(true)
		opts.composite_upper_parts = p.composite_upper_parts
	if _args.has("extra_anims"):
		opts.extra_anim_dir = _arg("extra_anims")
	var model_path := _arg("model", "")
	var scene := load(model_path) as PackedScene
	if scene == null:
		printerr("옷 모델을 열 수 없습니다: ", model_path); quit(1); return
	var baker := DRBaker.new()
	if not baker.setup(root, scene, DRPartProfile.humanoid(), opts):
		printerr("setup 실패"); quit(1); return
	await process_frame
	if not baker.part_overrides.is_empty():
		print("[복장] 부위 칠하기 %d곳 따름: %s" % [baker.part_overrides.size(), DRPartOverrides.path_for(model_path)])

	var ob := DROutfitBaker.new()
	ob.baker = baker
	if not ob.setup(_arg("sets", "res://puppet/sets.json")):
		printerr("세트를 읽지 못했습니다: ", ob.sets_json); quit(1); return
	if _args.has("parts"):
		var want := Array(_arg("parts").split(",", false))
		for pn in ob.slots.keys():
			if not want.has(pn):
				ob.slots[pn] = ""
	var id := _arg("id", model_path.get_file().get_basename())
	var res: Dictionary = await ob.run(_arg("out", "res://outfits"), id, model_path)
	for w in ob.warnings:
		print("[복장] ⚠ ", w)
	for sname in res.get("sets", []):
		print("[복장] %s 세트 구움" % sname)
	print("[복장] 결과: ", res.get("json", res.get("error", "?")))
	baker.cleanup()
	quit(0 if bool(res.get("ok", false)) else 1)
