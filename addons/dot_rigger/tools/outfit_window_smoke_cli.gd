extends SceneTree

## 복장 굽기 창(DROutfitWindow) 스모크 — 창을 띄워
##  [2] 불러오기(옷 모델 칸에 기본 몸이면 거절) → [3] 2D 입힘 → [4] 면 단위 표시 · 붓 칠하기 → 다시 자르기 → [5] 되돌리기
##  [6] 직선 나누기(머리 아래를 Torso 로) → [7] 칠할 대상 = 기본 몸 → 직선 나누기 → 2D 에 바로 보임
##  [8] 슬롯(상의 · 하의 두 가지) · 미리보기 상의만 → [9] 굽기 = 기본 몸 세트에 넣기 + 복장 → 다시 읽기
##
##   godot --path . --resolution 1400x860 --script res://addons/dot_rigger/tools/outfit_window_smoke_cli.gd -- \
##       --preset=res://human.tres --sets=res://puppet/sets.json --model=res://source3d/characters/uniform_m36/uniform_m36.glb
##
## ⚠ [9] 는 sets.json 의 기본 몸 세트(puppet.tscn · rig.json · parts)를 실제로 고친다 — 끝나고 원래대로 되돌리지만 샌드박스에서 돌릴 것.
##   (칠하기 파일 <모델>.parts.json 도 끝나고 되돌린다)

const OUT := "res://puppet_test/outfit_win"

var _fail := 0
var win_src_mesh: ArrayMesh      # 옷 모델 원본 메시(자르기로 늘어난 정점 수 비교용)
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


func _check(ok: bool, msg: String) -> void:
	print("  %s  %s" % ["OK  " if ok else "FAIL", msg])
	if not ok:
		_fail += 1


func _wait_idle(win, cap: int = 4000) -> void:
	var n := 0
	await process_frame
	while n < cap:
		var dirty: bool = win._busy or win._pv_dirty
		for t in [win._t_outfit, win._t_base]:
			if t != null and t.resplit_dirty:
				dirty = true
		if not dirty:
			break
		await process_frame
		n += 1


func _keep(path: String) -> Variant:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else null


func _put_back(path: String, v: Variant) -> void:
	if v == null:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(String(v))
	f.close()


## 화면에서 부위 p 의 정점들을 위아래로 가르는 가로선(뷰포트 좌표) — 정점 화면 y 의 frac 지점
## 조각(part) 메시의 정점이 자르기 경계를 얼마나 넘는가 — 곧은 경계 확인용.
## part 가 남는 쪽(from)이면 영역 쪽으로, into = true(받는 쪽)이면 영역 밖으로 넘은 최대 거리(m). 선 끝(옆 평면) 근처는 뺀다
func _piece_vs_cut(split, part: String, cut: Dictionary, into: bool = false) -> Dictionary:
	var planes: Array = cut["planes"]
	var main: Array = planes[0]
	var am: ArrayMesh = split.meshes.get(part)
	var out := {"max_over": 0.0, "new_verts": 0}
	if am == null:
		return out
	for si in am.get_surface_count():
		var arr := am.surface_get_arrays(si)
		var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var used := {}
		for k in idx:
			used[k] = true
		var src_n := 0
		var src_mesh: ArrayMesh = win_src_mesh
		if src_mesh != null and si < src_mesh.get_surface_count():
			src_n = src_mesh.surface_get_array_len(si)
		out["new_verts"] = int(out["new_verts"]) + maxi(vs.size() - src_n, 0)
		for k in used.keys():
			var p: Vector3 = vs[k]
			var in_slab := true
			for j in range(1, planes.size()):
				if DRMeshCutter.plane_dist(planes[j], p) < 0.02:
					in_slab = false
			if not in_slab:
				continue
			var d := DRMeshCutter.plane_dist(main, p)
			var over := -d if into else d
			out["max_over"] = maxf(float(out["max_over"]), over)
	return out


## 화면에서 그 부위 정점들이 차지하는 사각형
func _part_rect(win, part: String) -> Rect2:
	var t = win._target
	var r := Rect2()
	var first := true
	for i in t.pos.size():
		if t.part_of(i) != part:
			continue
		var s: Vector2 = win._cam3.unproject_position(t.pos[i])
		if first:
			r = Rect2(s, Vector2.ZERO)
			first = false
		else:
			r = r.expand(s)
	return r


func _cut_line(win, part: String, frac: float) -> Array:
	var t = win._target
	var ys: Array = []
	var xs: Array = []
	for i in t.pos.size():
		if t.part_of(i) == part:
			var s: Vector2 = win._cam3.unproject_position(t.pos[i])
			ys.append(s.y)
			xs.append(s.x)
	ys.sort()
	xs.sort()
	var y: float = ys[int((ys.size() - 1) * frac)]
	return [Vector2(xs[0] - 30.0, y), Vector2(xs[-1] + 30.0, y)]


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://puppet_test"))
	var model := _arg("model", "res://source3d/characters/uniform_m36/uniform_m36.glb")
	var preset := _arg("preset", "res://human.tres")
	var base_model := (load(preset) as DRPreset).model_path
	var keep_outfit_paint = _keep(DRPartOverrides.path_for(model))
	var keep_base_paint = _keep(DRPartOverrides.path_for(base_model))
	# 칠하기 · 경계 없는 상태에서 시작(사용자 파일을 복사해 온 샌드박스여도 같은 결과) — 끝나면 위에서 든 원래 내용으로 되돌린다
	for mp in [model, base_model]:
		_put_back(DRPartOverrides.path_for(mp), JSON.stringify({"version": 2, "model": mp, "points": [], "cuts": []}))
	var win := DROutfitWindow.new()
	root.add_child(win)
	win.test_layout(Vector2i(1340, 800))
	await process_frame

	print("[1] 창 구성")
	_check(win._bake_btn.disabled, "불러오기 전엔 굽기 잠김")
	_check(win._slot_opts.size() == 15 and (win._slot_opts["L_Foot"] as OptionButton).item_count == 3 and win._wear_cb.size() == 2, "슬롯 칸 15 · 고를 것 3(상의 · 하의 · 안 씀) · 미리보기 체크 2")
	_check(win._part_btns.size() == 16 and win._tool_btns.size() == 3 and win._tool == "line" and win._tgt_btns.size() == 3, "부위 단추 16 · 도구 3(직선 자르기 기본 · 사각형 · 붓) · 대상 3(둘 다 · 옷 모델만 · 기본 몸만)")

	print("[2] 불러오기")
	win._preset_edit.text = preset
	win._sets_edit.text = _arg("sets", "res://puppet/sets.json")
	win._model_edit.text = base_model
	win._on_load()
	await _wait_idle(win)
	_check(not win._loaded and win._load_status.text.contains("기본 몸"), "옷 모델 칸에 기본 몸 → 거절: %s" % win._load_status.text.left(60))
	win._model_edit.text = model
	win._id_edit.text = "outfit_smoke"
	win._out_edit.text = OUT
	win._on_load()
	await _wait_idle(win)
	_check(win._loaded and not win._bake_btn.disabled, "불러옴: %s" % win._load_status.text.split("\n")[0])
	if not win._loaded:
		printerr("불러오기 실패 — 중단"); quit(1); return
	var t = win._t_outfit
	win_src_mesh = win.baker.source_mesh_instance.mesh as ArrayMesh
	_check(t.pos.size() > 1000 and t.tri.size() % 3 == 0 and win._pm_mi.mesh.get_surface_count() == 1, "옷 모델 정점 %d · 삼각형 %d" % [t.pos.size(), t.tri.size() / 3])
	var shown: int = (win._pm_mi.mesh as ArrayMesh).surface_get_array_len(0)
	_check(shown == t.tri.size(), "면마다 한 색: 표시 정점 %d = 삼각형 × 3" % shown)

	print("[3] 2D 미리보기 — 기본 몸 퍼펫에 입힘")
	var sname := String((win.ob.sets[0] as Dictionary)["name"])
	_check(win._baked.has(sname) and (win._baked[sname] as Dictionary).size() == 12, "세트 %s 옷 그림 12장" % sname)
	var pup: DRPuppet = win._soldier.get_puppet()
	_check(pup._worn.has("Torso") and pup._worn.has("L_Foot") and not (win._outfit.sets[sname] as Dictionary).has("Head"), "몸통 · 발 = 옷 · 머리는 옷에 없음(기본 몸 것)")
	_check(win._target_kind == "both" and win._paint_both and win._t_base != null and win._target == win._t_outfit, "칠할 대상 기본 = 둘 다(3D 에는 옷 모델, 기본 몸도 불러 둠)")

	print("[4] 붓 칠하기(옷 모델만) → 저장 → 다시 자르기")
	await win._switch_target("outfit")
	var hips_i: int = t.auto.find("Hips")
	var target: Vector3 = t.pos[hips_i]
	var tris_before := int(win.baker.split.tri_counts.get("Torso", 0))
	var painted_before: int = t.ov.size()
	var h: Dictionary = win.pick(win._cam3.unproject_position(target))
	_check(bool(h.get("hit", false)), "광선으로 모델 표면을 맞힘")
	win._painting = true
	win._stroke = {}
	var n: int = win.paint_at(target, "Torso", 0.06)
	win.end_stroke()
	_check(n > 0 and t.ov.size() == painted_before + n and FileAccess.file_exists(DRPartOverrides.path_for(model)), "골반 쪽 %d곳 Torso 로 · 저장됨" % n)
	await _wait_idle(win)
	var tris_after := int(win.baker.split.tri_counts.get("Torso", 0))
	_check(tris_after > tris_before, "다시 자른 몸통 조각 삼각형 %d → %d" % [tris_before, tris_after])

	print("[5] 되돌리기")
	win._on_undo()
	await _wait_idle(win)
	_check(t.ov.size() == painted_before and int(win.baker.split.tri_counts.get("Torso", 0)) == tris_before, "되돌림 — 칠한 곳 %d(원래 %d) · 몸통 삼각형 %d" % [t.ov.size(), painted_before, int(win.baker.split.tri_counts.get("Torso", 0))])

	print("[6] 직선 자르기 — 옷 모델: 머리 조각 아래쪽 20% 를 Torso 로(삼각형을 쪼개 곧게)")
	var head_before := 0
	for i in t.pos.size():
		if t.part_of(i) == "Head":
			head_before += 1
	var ln := _cut_line(win, "Head", 0.8)
	win._stroke = {}
	var r: Dictionary = win.split_line(ln[0], ln[1], "Torso")
	win.end_stroke()
	var head_after := 0
	var below_wrong := 0
	for i in t.pos.size():
		if t.part_of(i) == "Head":
			head_after += 1
			if win._cam3.unproject_position(t.pos[i]).y > ln[0].y + 1.0:
				below_wrong += 1
	_check(String(r.get("source", "")) == "Head" and int(r.get("changed", 0)) > 0, "자를 부위 = Head 를 알아서 잡음 · %d곳 → Torso" % int(r.get("changed", 0)))
	_check(head_after < head_before and below_wrong == 0, "머리 정점 %d → %d · 선 아래에 남은 머리 정점 %d(앞뒤 함께 잘림)" % [head_before, head_after, below_wrong])
	_check(t.ov.cuts.size() == 1 and t.ov.size() == painted_before, "자르기 1개로 저장(붓 칠한 자리 %d 그대로)" % t.ov.size())
	await _wait_idle(win)
	var cut: Dictionary = t.ov.cuts[0]
	var st := _piece_vs_cut(win.baker.split, "Head", cut)
	_check(st["new_verts"] > 0, "삼각형을 평면에서 쪼갬 — 새 정점 %d개" % st["new_verts"])
	_check(st["max_over"] <= DRMeshCutter.MARGIN + 0.0005, "곧은 경계: 머리 조각이 선 너머로 %.1f mm 까지만(겹침 %.0f mm 이내 — 예전 정점 방식은 삼각형 한 줄만큼 들쭉날쭉)" % [st["max_over"] * 1000.0, DRMeshCutter.MARGIN * 1000.0])
	var st2 := _piece_vs_cut(win.baker.split, "Torso", cut, true)
	_check(st2["max_over"] <= DRMeshCutter.MARGIN + 0.0005, "몸통 조각도 선 너머(머리 쪽)로 %.1f mm 까지만 — 새로 받은 목 부분이 곧게 끝남" % (st2["max_over"] * 1000.0))
	win._on_undo()
	await _wait_idle(win)
	_check(t.ov.cuts.is_empty(), "되돌리기 → 자르기 없음")

	print("[6-2] 사각형 — 사각형 안(앞뒤 함께)이 고른 부위로")
	var hr := _part_rect(win, "Head")
	var rr := Rect2(Vector2(hr.position.x - 20.0, hr.end.y - hr.size.y * 0.25), Vector2(hr.size.x + 40.0, hr.size.y * 0.25 + 30.0))
	win._stroke = {}
	var r6: Dictionary = win.rect_cut(rr.position, rr.end, "Torso")
	win.end_stroke()
	var head_in_rect := 0
	for i in t.pos.size():
		if t.part_of(i) == "Head" and rr.has_point(win._cam3.unproject_position(t.pos[i])):
			head_in_rect += 1
	_check(int(r6.get("changed", 0)) > 0 and head_in_rect == 0 and t.ov.cuts.size() == 1 and String(t.ov.cuts[0]["from"]) == "*", "사각형 안 %d곳 → Torso · 사각형 안에 남은 머리 정점 %d" % [int(r6.get("changed", 0)), head_in_rect])
	win._on_undo()
	await _wait_idle(win)

	print("[6-1] 둘 다 — 선 하나로 옷 모델과 기본 몸의 같은 자리를 같이 자른다")
	await win._switch_target("both")
	var o_before: int = win._t_outfit.ov.cuts.size()
	var b_before: int = win._t_base.ov.cuts.size()
	var ln_b := _cut_line(win, "Head", 0.8)
	win._stroke = {}
	var rb: Dictionary = win.split_line(ln_b[0], ln_b[1], "Torso")
	win.end_stroke()
	var per: Dictionary = rb.get("per", {})
	_check(int(per.get("outfit", 0)) > 0 and int(per.get("base", 0)) > 0, "선 하나 → 옷 모델 %d곳 · 기본 몸 %d곳" % [int(per.get("outfit", 0)), int(per.get("base", 0))])
	_check(win._base_dirty and win._t_base.ov.cuts.size() > b_before and win._t_outfit.ov.cuts.size() > o_before, "둘 다 저장 · 기본 몸은 굽기 때 세트에 들어감 표시")
	var base_head_low := 0
	for i in win._t_base.pos.size():
		if win._t_base.part_of(i) == "Head" and win._cam3.unproject_position(win._t_base.pos[i]).y > ln_b[0].y + 1.0:
			base_head_low += 1
	_check(base_head_low == 0, "기본 몸도 같은 선 아래에 머리 정점이 안 남음(%d)" % base_head_low)
	await _wait_idle(win)
	_check(win._base_outfit != null, "2D 미리보기에 기본 몸 새 조각이 바로 반영")
	win._on_undo()
	await _wait_idle(win)
	_check(win._t_outfit.ov.cuts.size() == o_before and win._t_base.ov.cuts.size() == b_before, "되돌리기 한 번에 둘 다 원래대로")

	print("[6-3] 관절 경계 — 왼 손목: 그 두 부위만 · 두 모델 같이 · 곧게")
	await win._switch_target("both")
	_check(win._joints.has("L_Hand") and win._joints.has("Head") and String(win._joints["L_Hand"]["from"]) == "L_Forearm" and String(win._joints["Head"]["from"]) == "Torso",
		"관절 목록 %d개 · 왼 손목 = L_Forearm | L_Hand · 목 = Torso | Head" % win._joints.size())
	var ot = win._t_outfit
	var pb := PackedStringArray()
	for i in ot.pos.size():
		pb.append(ot.part_of(i))
	for i in win._joint_opt.item_count:
		if String(win._joint_opt.get_item_metadata(i)) == "L_Hand":
			win._joint_opt.select(i)
	win._on_joint_selected()
	win._joint_off.value = 2.0          # 손 쪽으로 2 cm — 움직이면 저절로 켜짐
	win._joint_commit()
	await _wait_idle(win)
	var wrist_changed := 0
	var other_changed := 0
	for i in ot.pos.size():
		var now: String = ot.part_of(i)
		if now == pb[i]:
			continue
		if (pb[i] == "L_Hand" or pb[i] == "L_Forearm") and (now == "L_Hand" or now == "L_Forearm"):
			wrist_changed += 1
		else:
			other_changed += 1
	_check(win._joint_on.button_pressed and wrist_changed > 0 and other_changed == 0, "손목 두 부위만 바뀜 %d곳 · 다른 부위 %d곳(관통 없음)" % [wrist_changed, other_changed])
	var jc: Dictionary = win._joint_cut(win._t_base, "L_Hand")
	_check(not jc.is_empty() and jc == win._joint_cut(win._t_outfit, "L_Hand"), "옷 모델 · 기본 몸에 같은 경계(위치 %+.1f cm)" % (float(jc.get("offset", 0.0)) * 100.0))
	var sj := _piece_vs_cut(win._t_base.baker.split, "L_Hand", jc, true)      # 손 = 받는 쪽(평면 앞)
	var sj2 := _piece_vs_cut(win._t_base.baker.split, "L_Forearm", jc)
	_check(sj["max_over"] <= DRMeshCutter.MARGIN + 0.0005 and sj2["max_over"] <= DRMeshCutter.MARGIN + 0.0005,
		"곧은 경계(기본 몸): 손 조각 %.1f mm · 팔 조각 %.1f mm 만 넘음" % [sj["max_over"] * 1000.0, sj2["max_over"] * 1000.0])
	_check(win._joint_mi.visible, "3D 에 노란 판(경계) 표시")
	win._t_outfit.ov.cuts = []
	var nsync: int = win._sync_joints_from_base()
	_check(nsync > 0 and win._joint_cut(win._t_outfit, "L_Hand") == jc, "기본 몸 경계 → 옷 모델로 자동(다른 옷을 불러와도 따라감)")
	await _wait_idle(win)
	win._on_undo()
	await _wait_idle(win)
	_check(win._joint_cut(win._t_base, "L_Hand").is_empty() and win._joint_cut(win._t_outfit, "L_Hand").is_empty() and not win._joint_on.button_pressed,
		"되돌리기 → 두 모델 다 경계 없음 · [곧게] 꺼짐")
	win._enable_joints(["Head", "L_Hand", "R_Hand"])
	await _wait_idle(win)
	_check(not win._joint_cut(win._t_base, "Head").is_empty() and not win._joint_cut(win._t_outfit, "R_Hand").is_empty() and win._undo.size() > 0, "[목 · 손목 곧게] 한 번에 3개")
	win._on_undo()
	await _wait_idle(win)

	print("[7] 칠할 대상 = 기본 몸만 → 직선 자르기 → 2D 에 바로")
	await win._switch_target("base")
	await _wait_idle(win)
	_check(win._t_base != null and win._target == win._t_base and win._t_base.scene_path == base_model, "기본 몸 불러옴(옷 모델 칸은 그대로 %s)" % win._model_edit.text.get_file())
	var bt = win._t_base
	var ln2 := _cut_line(win, "Head", 0.85)
	win._stroke = {}
	var r2: Dictionary = win.split_line(ln2[0], ln2[1], "Torso")
	win.end_stroke()
	_check(String(r2.get("source", "")) == "Head" and int(r2.get("changed", 0)) > 0 and win._base_dirty, "기본 몸 머리 아래 %d곳 → Torso · 굽기 때 세트에 들어감 표시" % int(r2.get("changed", 0)))
	await _wait_idle(win)
	_check(win._base_outfit != null and (win._base_outfit.sets.get(sname, {}) as Dictionary).size() == 15, "기본 몸 다시 자른 그림 15장이 미리보기 바탕으로")
	pup = win._soldier.get_puppet()
	var base_head_tex: Texture2D = (win._base_outfit.sets[sname]["Head"] as Dictionary)["texture"]
	var head_art: Sprite2D = pup.get_bone("Head").get_node("stretch/art")
	_check(head_art.texture == base_head_tex, "2D 의 머리 = 새로 자른 기본 몸 머리")

	print("[8] 슬롯 · 미리보기 상의만")
	var hips_opt: OptionButton = win._slot_opts["Hips"]
	hips_opt.select(0)
	hips_opt.item_selected.emit(0)    # Hips → 상의
	await _wait_idle(win)
	_check(win._outfit.slot_parts("top").has("Hips") and win._outfit.slot_parts("bottom").has("L_Foot"), "Hips = 상의 · 발 = 하의")
	(win._wear_cb["bottom"] as CheckBox).button_pressed = false
	await process_frame
	pup = win._soldier.get_puppet()
	var thigh_art: Sprite2D = pup.get_bone("L_Thigh").get_node("stretch/art")
	var base_thigh: Texture2D = (win._base_outfit.sets[sname]["L_Thigh"] as Dictionary)["texture"]
	_check(thigh_art.texture == base_thigh, "하의 끔 → 다리는 기본 몸 그림")
	(win._wear_cb["bottom"] as CheckBox).button_pressed = true

	print("[9] 굽기 = 기본 몸 세트에 넣기 + 복장")
	var sets_doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(win._sets_edit.text))
	var scene_path: String = win._sets_edit.text.get_base_dir().path_join(String(sets_doc["sets"][0]["scene"]))
	var head_png: String = scene_path.get_base_dir().path_join("parts/Head.png")
	var old_head := Image.load_from_file(ProjectSettings.globalize_path(head_png))
	# 이 검사는 기본 몸 세트 파일을 실제로 고친다 — 끝나고 되돌리려고 원래 내용을 들어 둔다(다시 돌려도 같은 결과가 나오게)
	var set_dir := scene_path.get_base_dir()
	var keep_files := {}
	for f in [scene_path, set_dir.path_join("rig.json")]:
		keep_files[f] = FileAccess.get_file_as_bytes(f)
	for f in DirAccess.get_files_at(set_dir.path_join("parts")):
		if String(f).ends_with(".png"):
			keep_files[set_dir.path_join("parts").path_join(f)] = FileAccess.get_file_as_bytes(set_dir.path_join("parts").path_join(f))
	win._on_bake()
	await _wait_idle(win)
	var new_head := Image.load_from_file(ProjectSettings.globalize_path(head_png))
	_check(not win._base_dirty and win._status.text.contains("기본 몸 세트 1개"), "기본 몸 세트에 넣음: %s" % win._status.text.split("\n")[0])
	_check(new_head.get_size() != old_head.get_size() or new_head.get_data() != old_head.get_data(), "세트의 머리 그림이 바뀜 %s → %s" % [str(old_head.get_size()), str(new_head.get_size())])
	var ps := ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var inst := ps.instantiate()
	inst.call("rebuild_index")
	var saved_head: Sprite2D = (inst.get("_parts")["Head"]["bone"] as Bone2D).get_node("stretch/art")
	_check(saved_head.texture.get_size() == Vector2(new_head.get_size()), "puppet.tscn 의 머리 그림도 새 것(%s)" % str(saved_head.texture.get_size()))
	inst.free()
	var jp := OUT.path_join("outfit_smoke").path_join("outfit.json")
	var o := DROutfit.load_json(jp)
	_check(o != null and (o.sets.get(sname, {}) as Dictionary).size() == 12 and String(o.slots.get("Hips", "")) == "top", "복장 다시 읽음: 파트 %d · Hips = %s" % [(o.sets.get(sname, {}) as Dictionary).size() if o != null else -1, String(o.slots.get("Hips", "")) if o != null else "?"])
	root.get_texture().get_image().save_png("res://puppet_test/_outfitwin_layout.png")
	await process_frame
	await RenderingServer.frame_post_draw
	win._vp3.get_texture().get_image().save_png("res://puppet_test/_outfitwin_3d.png")
	win._vp2.get_texture().get_image().save_png("res://puppet_test/_outfitwin_2d.png")

	for f in keep_files.keys():
		var fa := FileAccess.open(f, FileAccess.WRITE)
		fa.store_buffer(keep_files[f])
		fa.close()
	_put_back(DRPartOverrides.path_for(model), keep_outfit_paint)
	_put_back(DRPartOverrides.path_for(base_model), keep_base_paint)
	win.queue_free()
	await process_frame
	print("복장 굽기 창 검사 %s (실패 %d)" % ["전부 통과" if _fail == 0 else "실패 있음", _fail])
	quit(1 if _fail > 0 else 0)
