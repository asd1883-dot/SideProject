extends SceneTree

## 3D 캐릭터(DRCharacter3D) 시험 도구(10-15) — 사람 몸(human_base) + 군복(uniform_m36) + kar98k 만 쓴다(UAL 마네킹은 레거시).
## 그림을 찍으므로 창 모드로 돌린다(--headless 는 렌더가 안 된다). 사용자 주 모니터를 가리지 않게 왼쪽 보조 모니터(--screen 0)에:
##   Godot.exe --path <프로젝트> --screen 0 --resolution 1280x720 \
##       --script res://addons/dot_rigger/tools/character3d_check_cli.gd -- --out=res://_out
##   (--position 에 음수 좌표를 주면 Godot 이 주 모니터 (0,y) 로 끌어온다 — 10-16 C 갈래 실측)
##   --only=stats,wear,seam,inside,weapon,tint (기본 전부) · --cell=256 (칸 크기 px)
## 결과: <out>/wear_*.png(차림 4 가지 × 자세 × 앞 · 3/4 · 뒤) · seam_*.png(목 · 손목 · 허리 확대)
##       · inside_*.png(옷 속 — 지금(양면 + 뚜껑) · 뚜껑 없음 · 한면 비교) · weapon_*.png(소총 — 저장 그립 · 한 그립 · 동작별 그립)
##       · tint_fade.png · character3d_report.txt(숫자)
## 배경은 자홍 — "닫힌 자홍"(가장자리와 안 이어진 배경 픽셀) 중 굵은 곳이 없는 덩어리 = 가는 틈(이음매 틈 후보)으로 따로 센다.
## 소총 동작(Mixamo — Rifle_Idle 등)은 모델 파일에 없어 DRBaker 를 프리셋(UAL1_preset.tres) 값으로 setup 해 처리된 라이브러리를 빌린다.

const HUMAN := "res://source3d/characters/human_base/human_base.glb"
const OUTFIT := "res://outfits/uniform_m36/outfit.json"
const ASSET := "res://source3d/weapons/kar98k/asset.json"
const PRESET := "res://UAL1_preset.tres"
const BG := Color(1.0, 0.0, 1.0)          # 배경(자홍) — 틈으로 비치면 바로 보인다
const LABEL_BAND := 18                     # 칸 위쪽 글씨 띠(구멍 세기에서 뺀다)

const POSES := [["A_TPose", 0.0], ["Idle", 0.3], ["Crouch_Idle", 0.3], ["Sprint", 0.35], ["Crawl_Idle", 0.3]]
const VIEWS := [["앞", 0.0, 8.0], ["3/4", -45.0, 8.0], ["뒤", 180.0, 8.0]]
const SEAM_VIEWS := [["앞", 0.0, 10.0], ["3/4", -45.0, 10.0], ["옆", -90.0, 10.0], ["뒤", 180.0, 10.0]]
const SEAM_POSES := [["A_TPose", 0.0], ["Idle", 0.3], ["Sprint", 0.35]]
const WEAPON_ANIMS := ["Rifle_Idle", "Firing_Rifle", "Walk_With_Rifle"]
const WEAPON_FRAMES := [0.0, 0.25, 0.5, 0.75]
const WEAPON_VIEWS := [["오른 옆", -90.0, 5.0], ["3/4", -45.0, 10.0]]
const GRIP_MODES := ["저장", "한 그립", "동작별"]

var _args := {}
var _out := "res://_out"
var _cell := 256
var _vp: SubViewport
var _cam: Camera3D
var _label: Label
var _report := PackedStringArray()
var _lib: AnimationLibrary
var _baker: DRBaker
var _uniform_glb := ""
var _uniform_slots := {}
var _nocap := {}          # glb -> {슬롯: 뚜껑 없는 ArrayMesh}(옷 속 비교용)


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
	_out = String(_args.get("out", _out))
	_cell = int(_args.get("cell", str(_cell)))
	_run.call_deferred()


func _want(section: String) -> bool:
	if not _args.has("only"):
		return true
	return String(_args["only"]).split(",").has(section)


func _log(s: String) -> void:
	print(s)
	_report.append(s)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var od := DRCharacter3D._read_json(OUTFIT)
	_uniform_glb = String(od.get("model", ""))
	_uniform_slots = od.get("slots", {})
	_build_viewport()
	await _load_motions()
	if _lib == null:
		quit(1)
		return
	if _want("stats"):
		await _stats()
	if _want("wear"):
		await _wear_sheets()
	if _want("seam"):
		await _seam_sheets()
	if _want("inside"):
		await _inside_sheets()
	if _want("weapon"):
		await _weapon_sheets()
	if _want("tint"):
		await _tint_fade()
	var f := FileAccess.open(ProjectSettings.globalize_path(_out.path_join("character3d_report.txt")), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_report) + "\n")
		f.close()
	print("[완료] ", _out)
	quit(0)


# ---------------------------------------------------------------- 준비

func _build_viewport() -> void:
	_vp = SubViewport.new()
	_vp.name = "CheckView"
	_vp.size = Vector2i(_cell, _cell)
	_vp.own_world_3d = true
	_vp.world_3d = World3D.new()
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.near = 0.05
	_cam.far = 40.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_cam.environment = env
	_vp.add_child(_cam)
	_cam.current = true
	_label = Label.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Arial"])
	_label.add_theme_font_override("font", font)
	_label.add_theme_font_size_override("font_size", 12)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.position = Vector2(3, 0)
	_vp.add_child(_label)


## 프리셋 값으로 DRBaker 를 세워 처리된 동작 라이브러리(UAL + Mixamo 추가 동작 · 합성 · 손 맞춤)를 빌린다.
## 베이커는 끝까지 살려 두고 뷰포트만 멈춘다(queue_free 하면 재질 덮어쓰기가 먼저 풀려 렌더러가 "material is null" 을 찍는다 — 09-22 장비 창과 같은 일)
func _load_motions() -> void:
	var t0 := Time.get_ticks_msec()
	var pr := load(PRESET) as DRPreset
	if pr == null:
		printerr("프리셋을 열 수 없습니다: ", PRESET)
		return
	var opts := DRBaker.Options.new()
	opts.view_size = Vector2i(32, 32)
	opts.extra_anim_dir = pr.extra_anim_dir
	opts.composites = Array(pr.composites)
	opts.composite_upper_parts = pr.composite_upper_parts
	opts.in_place = pr.in_place
	_baker = DRBaker.new()
	var scene := load(pr.model_path) as PackedScene
	if scene == null or not _baker.setup(root, scene, DRPartProfile.humanoid(), opts):
		printerr("DRBaker setup 실패 — 동작을 빌릴 수 없습니다")
		return
	_baker.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_lib = _baker.anim_player.get_animation_library("")
	_log("[동작] 라이브러리 %d 개(추가 %d 개 · 합성 %s · 손 IK %d · 손 레스트 %d · 비틀림 %d) — %.1f s" % [_lib.get_animation_list().size(),
		_baker.extra_anims.size(), ", ".join(_baker.composite_anims), _baker.ik_anims, _baker.rest_fix_anims, _baker.twist_anims,
		(Time.get_ticks_msec() - t0) / 1000.0])
	for w in _baker.extra_anim_warnings:
		_log("   ⚠ " + w)
	for n in WEAPON_ANIMS + ["A_TPose", "Idle", "Crouch_Idle", "Sprint", "Crawl_Idle"]:
		if not _lib.has_animation(n):
			_log("   ⚠ 라이브러리에 없음: " + n)
	await process_frame


## 병사 하나(시험용 — 재생 시간은 멈춰 두고 seek 로 자세를 잡는다)
func _soldier(outfit: String = "", slots: PackedStringArray = PackedStringArray(), weapon: bool = false) -> DRCharacter3D:
	var ch := DRCharacter3D.new()
	_vp.add_child(ch)
	ch.setup(HUMAN)
	ch.set_motions(_lib)
	ch.get_animation_player().speed_scale = 0.0
	if outfit != "":
		ch.wear(outfit, slots)
	if weapon:
		ch.attach_weapon(ASSET)
	return ch


func _pose(ch: DRCharacter3D, an: String, frac: float) -> void:
	DRGripFit.pose(ch, an, frac)


func _bone_pos(ch: DRCharacter3D, bone: String) -> Vector3:
	var sk := ch.get_skeleton()
	var bi := sk.find_bone(bone)
	if bi < 0:
		return ch.global_position
	return sk.global_transform * sk.get_bone_global_pose(bi).origin


## 전신 틀의 가운데: 서 있으면 키 절반쯤, 엎드리면(골반이 낮으면) 내려서
func _body_center(ch: DRCharacter3D) -> Vector3:
	var hips := _bone_pos(ch, "Hips")
	return Vector3(hips.x, clampf(hips.y + 0.05, 0.5, 0.92), hips.z)


## 카메라: center 를 yaw(도, 0 = 앞에서 — 모델이 +Z 를 본다) · pitch(도, + = 내려다봄)에서 직교 크기 size(m)로
func _frame(center: Vector3, yaw: float, pitch: float, size: float) -> void:
	var b := DRBaker.view_basis(yaw, pitch)
	_cam.size = size
	_cam.global_transform = Transform3D(b, center + b * Vector3(0, 0, 8.0))


func _grab(caption: String) -> Image:
	_label.text = caption
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


func _sheet(cells: Array, cols: int) -> Image:
	var cw: int = (cells[0] as Image).get_width()
	var chh: int = (cells[0] as Image).get_height()
	var rows := int(ceil(cells.size() / float(cols)))
	var img := Image.create(cw * cols, chh * rows, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.15, 0.15, 0.15))
	for i in cells.size():
		var c: Image = cells[i]
		img.blit_rect(c, Rect2i(0, 0, c.get_width(), c.get_height()), Vector2i((i % cols) * cw, int(i / cols) * chh))
	return img


func _save(img: Image, name: String) -> void:
	img.save_png(ProjectSettings.globalize_path(_out.path_join(name)))
	_log("   → %s" % _out.path_join(name))


## 배경색 픽셀 중 바깥(가장자리 · 글씨 띠)과 이어지지 않은 것 = 몸 안으로 배경이 비치는 곳.
## Vector2i(닫힌 자홍 전부, 그중 가는 틈) — 가는 틈 = 사방 8 칸이 다 배경인 픽셀이 하나도 없는 덩어리(폭 2 px 이하).
## 팔과 몸통 사이 · 손가락 고리처럼 몸 부위가 둘러싼 빈 곳은 보통 굵어서 "닫힌 자홍" 에만 든다
func _holes(img: Image) -> Vector2i:
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var bg := PackedByteArray()
	bg.resize(w * h)
	for i in w * h:
		if data[i * 4] > 235 and data[i * 4 + 1] < 20 and data[i * 4 + 2] > 235:
			bg[i] = 1
	var seen := PackedByteArray()
	seen.resize(w * h)
	var q := PackedInt32Array()
	for y in h:
		for x in w:
			if (y < LABEL_BAND or x == 0 or y == h - 1 or x == w - 1) and bg[y * w + x] == 1:
				seen[y * w + x] = 1
				q.append(y * w + x)
	_flood(q, 0, bg, seen, w, h, 1)
	var total := 0
	var thin := 0
	for i in w * h:
		if bg[i] != 1 or seen[i] != 0:
			continue
		var comp := PackedInt32Array([i])
		seen[i] = 2
		_flood(comp, 0, bg, seen, w, h, 2)
		var deep := false
		for j in comp:
			var x := j % w
			var y := int(j / w)
			if x <= 0 or y <= 0 or x >= w - 1 or y >= h - 1:
				continue
			if bg[j - 1] == 1 and bg[j + 1] == 1 and bg[j - w] == 1 and bg[j + w] == 1 and bg[j - w - 1] == 1 and bg[j - w + 1] == 1 and bg[j + w - 1] == 1 and bg[j + w + 1] == 1:
				deep = true
				break
		total += comp.size()
		if not deep:
			thin += comp.size()
	return Vector2i(total, thin)


## q 의 픽셀에서 시작해 배경(bg = 1) · 아직 안 본(seen = 0) 이웃 4 칸을 mark 로 칠하며 q 에 더한다
func _flood(q: PackedInt32Array, head: int, bg: PackedByteArray, seen: PackedByteArray, w: int, h: int, mark: int) -> void:
	while head < q.size():
		var i := q[head]
		head += 1
		var x := i % w
		var y := int(i / w)
		if x > 0 and bg[i - 1] == 1 and seen[i - 1] == 0:
			seen[i - 1] = mark
			q.append(i - 1)
		if x < w - 1 and bg[i + 1] == 1 and seen[i + 1] == 0:
			seen[i + 1] = mark
			q.append(i + 1)
		if y > 0 and bg[i - w] == 1 and seen[i - w] == 0:
			seen[i - w] = mark
			q.append(i - w)
		if y < h - 1 and bg[i + w] == 1 and seen[i + w] == 0:
			seen[i + w] = mark
			q.append(i + w)


# ---------------------------------------------------------------- 숫자 · 공유

func _stats() -> void:
	_log("\n[나누기 · 공유]")
	DRCharacter3D.clear_cache()
	var t0 := Time.get_ticks_usec()
	var a := DRCharacter3D.new()
	_vp.add_child(a)
	a.setup(HUMAN)
	var t_a := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var b := DRCharacter3D.new()
	_vp.add_child(b)
	b.setup(HUMAN)
	var t_b := (Time.get_ticks_usec() - t0) / 1000.0
	var sp: DRSlotMesh.Result = a.get_body_entry()["split"]
	_log_split("기본 몸 human_base", sp)
	_log("setup 시간: 첫 병사 %.1f ms(나누기 포함) · 둘째 병사 %.1f ms(캐시)" % [t_a, t_b])
	_log("키 model_height() = %.3f m · 경계 상자 %s" % [a.model_height(), str(a.model_aabb())])
	t0 = Time.get_ticks_usec()
	a.wear(OUTFIT)
	var t_w1 := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	b.wear(OUTFIT)
	var t_w2 := (Time.get_ticks_usec() - t0) / 1000.0
	var so: DRSlotMesh.Result = DRCharacter3D.load_entry(_uniform_glb, _uniform_slots)["split"]
	_log_split("군복 uniform_m36", so)
	_log("wear 시간: 첫 병사 %.1f ms(나누기 포함) · 둘째 %.1f ms(캐시)" % [t_w1, t_w2])
	# 자르기 고르기(needed_cuts)가 슬롯 나뉨을 안 바꾸는지 — 전부 자른 것과 슬롯별 넓이 · 경계 상자 비교(뚜껑 빼고)
	for pair in [[HUMAN, {}], [_uniform_glb, _uniform_slots]]:
		var glb := String(pair[0])
		var inst := (load(glb) as PackedScene).instantiate()
		var mi := DRBaker._find_skinned_mesh(inst)
		var skl := DRBaker._find_node(inst, "Skeleton3D") as Skeleton3D
		var ov := DRPartOverrides.load_for(glb)
		var r1 := DRSlotMesh.split(mi, skl, DRPartProfile.humanoid(), pair[1], ov, true, false)
		var r2 := DRSlotMesh.split(mi, skl, DRPartProfile.humanoid(), pair[1], ov, false, false)
		var line := PackedStringArray()
		for s in ["top", "bottom", "base"]:
			var a1 := _area(r1.meshes[s])
			var a2 := _area(r2.meshes[s])
			var b1: AABB = (r1.meshes[s] as ArrayMesh).get_aabb()
			var b2: AABB = (r2.meshes[s] as ArrayMesh).get_aabb()
			line.append("%s 넓이 %.6f / %.6f m² (차 %.8f) · 상자 차 %.8f m" % [s, a1, a2, absf(a1 - a2), b1.position.distance_to(b2.position) + b1.end.distance_to(b2.end)])
		_log("자르기 고르기 검증 %s(뚜껑 빼고): 자르기 %d/%d 개 씀 · 정점 %d (전부 자르면 %d) · 삼각형 %d (%d)\n      %s" % [glb.get_file(),
			r1.cuts_used, r1.cuts_total, _sum(r1.vert_counts), _sum(r2.vert_counts), _sum(r1.tri_counts), _sum(r2.tri_counts), "\n      ".join(line)])
		inst.free()
	var pk := sp.part_tri_counts.keys()
	pk.sort()
	var pt := PackedStringArray()
	for k in pk:
		pt.append("%s %d" % [k, int(sp.part_tri_counts[k])])
	_log("   기본 몸 파트별 삼각형(뚜껑 빼고): " + ", ".join(pt))
	# 공유
	var ma := (a.get_slot_node("top").mesh as ArrayMesh).surface_get_material(0)
	var mb := (b.get_slot_node("top").mesh as ArrayMesh).surface_get_material(0)
	var mbody_a := (a.get_slot_node("base").mesh as ArrayMesh).surface_get_material(0)
	var mbody_b := (b.get_slot_node("base").mesh as ArrayMesh).surface_get_material(0)
	_log("공유: 두 병사 군복 상의 메시 같은 객체=%s · 기본 몸 머리손 메시 같은 객체=%s · 군복 재질 같은 객체=%s · 몸 재질 같은 객체=%s" % [
		str(a.get_slot_node("top").mesh == b.get_slot_node("top").mesh), str(a.get_slot_node("base").mesh == b.get_slot_node("base").mesh),
		str(ma == mb), str(mbody_a == mbody_b)])
	_log("     Skin: 몸 슬롯 · 군복 슬롯이 같은 Skin=%s(복장 바인드가 몸과 같아 몸 Skin 을 같이 씀) · 두 병사 같은 Skin=%s · 공유 재질 수(전체 캐시) %d" % [
		str(a.get_slot_node("top").skin == a.get_slot_node("base").skin), str(a.get_slot_node("top").skin == b.get_slot_node("top").skin), DRCharacter3D._mats.size()])
	_log("     재질은 메시 서피스에 직접 — 병사 노드의 재질 덮어쓰기 없음(override=%s), 병사마다 다른 값은 instance uniform(tint · fade)" % str(a.get_slot_node("top").get_surface_override_material(0)))
	a.attach_weapon(ASSET)
	b.attach_weapon(ASSET)
	_log("무기: 두 병사 무기 메시 같은 객체=%s · 서피스(=그리기) %d 개 · 붙인 뼈 %s" % [str(a.get_weapon_node().mesh == b.get_weapon_node().mesh),
		a.get_weapon_node().mesh.get_surface_count(), a.get_weapon_mount().bone_name])
	_log("병사 한 명 노드: MeshInstance3D %d 개(슬롯 3 + 무기 1) · 전체 노드 %d 개 · 그리기 묶음(서피스) %d 개" % [_count(a, "MeshInstance3D"), _count(a, "Node"), _draws(a)])
	_log("구조: %s" % _tree_line(a))
	# 동작 트랙 %GeneralSkeleton:<뼈> 가 풀리는지 — Idle 을 걸고 뼈가 레스트에서 움직였나
	var ap := a.get_animation_player()
	var sk := a.get_skeleton()
	var bi := sk.find_bone("LeftUpperArm")
	sk.reset_bone_poses()
	var rest_q := sk.get_bone_pose_rotation(bi)
	ap.speed_scale = 0.0
	ap.play("Idle")
	ap.seek(0.3, true)
	var idle_q := sk.get_bone_pose_rotation(bi)
	_log("동작 풀림: Idle 트랙 경로 예 %s → LeftUpperArm 회전이 레스트에서 %.1f° 움직임 · Rifle_Idle 트랙 경로 예 %s" % [
		str(_lib.get_animation("Idle").track_get_path(0)), rad_to_deg(rest_q.angle_to(idle_q)),
		str(_lib.get_animation("Rifle_Idle").track_get_path(0)) if _lib.has_animation("Rifle_Idle") else "-"])
	a.queue_free()
	b.queue_free()
	await process_frame


func _log_split(name: String, r: DRSlotMesh.Result) -> void:
	_log("%s: 원본 정점 %d · 삼각형 %d → 나누기 %.1f ms (관절 자르기 %d/%d 개 · 새 정점 %d · 넓이 0 뺌 %d · 파트 못 정함 %d · 뚜껑 고리 %s · 부채꼴 %d · 못 닫은 사슬 %d)" % [
		name, r.source_verts, r.source_tris, r.ms, r.cuts_used, r.cuts_total, r.cut_new_verts, r.degenerate_tris, r.unassigned_tris,
		str(r.cap_loops), r.cap_fan, r.cap_open])
	var tv := 0
	var tt := 0
	for s in ["top", "bottom", "base"]:
		_log("   %-6s 정점 %5d · 삼각형 %5d (그중 뚜껑 %d)" % [s, int(r.vert_counts.get(s, 0)), int(r.tri_counts.get(s, 0)), int(r.cap_tris.get(s, 0))])
		tv += int(r.vert_counts.get(s, 0))
		tt += int(r.tri_counts.get(s, 0))
	_log("   합     정점 %5d · 삼각형 %5d (원본 정점 %d — 늘어난 것 = 자르기 새 정점 · 두 슬롯이 같이 쓰는 경계 정점 · 뚜껑 정점)" % [tv, tt, r.source_verts])


func _area(m: ArrayMesh) -> float:
	var a := 0.0
	for si in m.get_surface_count():
		var arr := m.surface_get_arrays(si)
		var p: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for k in int(ix.size() / 3):
			a += (p[ix[k * 3 + 1]] - p[ix[k * 3]]).cross(p[ix[k * 3 + 2]] - p[ix[k * 3]]).length() * 0.5
	return a


func _sum(d: Dictionary) -> int:
	var n := 0
	for v in d.values():
		n += int(v)
	return n


func _count(n: Node, cls: String) -> int:
	var c := 1 if n.is_class(cls) else 0
	for k in n.get_children():
		c += _count(k, cls)
	return c


func _draws(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		c += (n as MeshInstance3D).mesh.get_surface_count()
	for k in n.get_children():
		c += _draws(k)
	return c


func _tree_line(n: Node, depth: int = 0) -> String:
	var s := "%s%s(%s)" % ["\n        " + "  ".repeat(depth) if depth > 0 else "", n.name, n.get_class()]
	for k in n.get_children():
		s += _tree_line(k, depth + 1)
	return s


# ---------------------------------------------------------------- 차림 4 가지

func _wear_sheets() -> void:
	_log("\n[차림] 행 = 자세(%s) · 열 = 앞 · 3/4 · 뒤" % ", ".join(PackedStringArray(POSES.map(func(p): return String(p[0])))))
	var looks := [["naked", "내복", ""], ["top", "상의만", "top"], ["bottom", "하의만", "bottom"], ["full", "군복 전체", "all"]]
	for lk in looks:
		var slots := PackedStringArray() if String(lk[2]) in ["", "all"] else PackedStringArray([String(lk[2])])
		var ch := _soldier(OUTFIT if String(lk[2]) != "" else "", slots)
		var cells: Array = []
		var holes := Vector2i.ZERO
		for p in POSES:
			_pose(ch, String(p[0]), float(p[1]))
			await process_frame
			var c := _body_center(ch)
			for v in VIEWS:
				_frame(c, float(v[1]), float(v[2]), 2.15)
				var img: Image = await _grab("%s · %s · %s" % [lk[1], p[0], v[0]])
				holes += _holes(img)
				cells.append(img)
		_save(_sheet(cells, VIEWS.size()), "wear_%s.png" % lk[0])
		_log("   %s: 닫힌 자홍 %d px · 그중 가는 틈 %d px (15 칸 합)" % [lk[1], holes.x, holes.y])
		ch.queue_free()
		await process_frame


# ---------------------------------------------------------------- 이음매 확대

func _seam_center(ch: DRCharacter3D, joint: String) -> Vector3:
	match joint:
		"neck":
			return (_bone_pos(ch, "Neck") + _bone_pos(ch, "Head")) * 0.5
		"waist":
			return _bone_pos(ch, "Spine")
		"LeftHand", "RightHand":
			var h := _bone_pos(ch, joint)
			var f := _bone_pos(ch, "LeftLowerArm" if joint == "LeftHand" else "RightLowerArm")
			return h + (f - h).normalized() * 0.03
	return ch.global_position


func _seam_sheets() -> void:
	var looks := [["top", "상의만", ["top"], [["목", "neck", 0.36], ["왼 손목", "LeftHand", 0.26], ["오른 손목", "RightHand", 0.26], ["허리", "waist", 0.5]]],
		["bottom", "하의만", ["bottom"], [["허리", "waist", 0.5]]],
		["full", "군복 전체", [], [["목", "neck", 0.36], ["왼 손목", "LeftHand", 0.26], ["오른 손목", "RightHand", 0.26]]]]
	for lk in looks:
		_log("\n[이음매 %s] 행 = 관절 × 자세(%s) · 열 = 앞 · 3/4 · 옆 · 뒤" % [lk[1], ", ".join(PackedStringArray(SEAM_POSES.map(func(p): return String(p[0]))))])
		var ch := _soldier(OUTFIT, PackedStringArray(lk[2]))
		var cells: Array = []
		for j in lk[3]:
			var holes := Vector2i.ZERO
			for p in SEAM_POSES:
				_pose(ch, String(p[0]), float(p[1]))
				await process_frame
				for v in SEAM_VIEWS:
					_frame(_seam_center(ch, String(j[1])), float(v[1]), float(v[2]), float(j[2]))
					var img: Image = await _grab("%s · %s · %s · %s" % [lk[1], j[0], p[0], v[0]])
					holes += _holes(img)
					cells.append(img)
			_log("   %s: 닫힌 자홍 %d px · 그중 가는 틈 %d px (자세 %d × 보기 %d 칸)" % [j[0], holes.x, holes.y, SEAM_POSES.size(), SEAM_VIEWS.size()])
		_save(_sheet(cells, SEAM_VIEWS.size()), "seam_%s.png" % lk[0])
		ch.queue_free()
		await process_frame


# ---------------------------------------------------------------- 옷 속(빈 안쪽 면) — 지금(양면 + 뚜껑) vs 뚜껑 없음 vs 한면

## 뚜껑 없는 슬롯 메시(비교용 — 재질은 공유 재질)
func _nocap_meshes(glb: String, table: Dictionary) -> Dictionary:
	if _nocap.has(glb):
		return _nocap[glb]
	var inst := (load(glb) as PackedScene).instantiate()
	var mi := DRBaker._find_skinned_mesh(inst)
	var skl := DRBaker._find_node(inst, "Skeleton3D") as Skeleton3D
	var r := DRSlotMesh.split(mi, skl, DRPartProfile.humanoid(), table, DRPartOverrides.load_for(glb), true, false)
	for s in r.meshes.keys():
		var am: ArrayMesh = r.meshes[s]
		for si in am.get_surface_count():
			am.surface_set_material(si, DRCharacter3D.char_material(am.surface_get_material(si)))
	inst.free()
	_nocap[glb] = r.meshes
	return r.meshes


## mode: 0 = 지금(양면 + 뚜껑) · 1 = 뚜껑 없음(양면) · 2 = 뚜껑 없음 + 한면(cull_back). 그 병사의 슬롯 노드만 바꾼다(공유 메시 · 재질은 그대로)
func _look_mode(ch: DRCharacter3D, mode: int) -> void:
	var sh := Shader.new()
	sh.code = (load(DRCharacter3D.SHADER_PATH) as Shader).code.replace("cull_disabled", "cull_back")
	for s in DRCharacter3D.SLOTS:
		var ss := String(s)
		var mi := ch.get_slot_node(ss)
		var worn := ch.worn(ss) != ""
		var e := DRCharacter3D.load_entry(_uniform_glb, _uniform_slots) if worn else ch.get_body_entry()
		if mode == 0:
			mi.mesh = (e["meshes"] as Dictionary)[ss]
		else:
			mi.mesh = _nocap_meshes(_uniform_glb if worn else HUMAN, _uniform_slots if worn else {})[ss]
		var am := mi.mesh as ArrayMesh
		for si in am.get_surface_count():
			if mode != 2:
				mi.set_surface_override_material(si, null)
				continue
			var src := am.surface_get_material(si) as ShaderMaterial
			var sm := ShaderMaterial.new()
			sm.shader = sh
			for pn in ["albedo_tex", "use_tex", "albedo_color", "bands", "ambient", "light_wrap", "light_dir", "rim", "inside_shade"]:
				sm.set_shader_parameter(pn, src.get_shader_parameter(pn))
			mi.set_surface_override_material(si, sm)


func _inside_sheets() -> void:
	# [보기 이름, 관절, 자세, yaw, pitch, 크기]
	var looks := [["top", "상의만", ["top"], [["깃 위에서", "neck", "Idle", 0.0, 70.0, 0.4], ["오른 소매 끝(팔 축)", "RightHand", "A_TPose", -90.0, 0.0, 0.3],
			["왼 소매 끝(팔 축)", "LeftHand", "A_TPose", 90.0, 0.0, 0.3], ["윗옷 자락 아래에서", "waist", "Idle", 0.0, -55.0, 0.6], ["윗옷 자락 뒤 아래", "waist", "Sprint", 180.0, -40.0, 0.6]]],
		["bottom", "하의만", ["bottom"], [["바지 허리 위에서", "waist", "Idle", 0.0, 65.0, 0.6], ["바지 허리 뒤 위", "waist", "Crouch_Idle", 180.0, 55.0, 0.6],
			["옷자락 오른 엉덩이(3/4)", "waist", "Idle", -45.0, 10.0, 0.5]]],
		["full", "군복 전체", [], [["깃 위에서", "neck", "Idle", 0.0, 70.0, 0.4], ["깃 뒤 위", "neck", "Crouch_Idle", 180.0, 60.0, 0.4],
			["오른 소매 끝(팔 축)", "RightHand", "A_TPose", -90.0, 0.0, 0.3], ["왼 소매 끝(팔 축)", "LeftHand", "A_TPose", 90.0, 0.0, 0.3]]]]
	var names := ["지금(양면+뚜껑)", "뚜껑 없음", "한면·뚜껑 없음"]
	for lk in looks:
		_log("\n[옷 속 %s] 열 = %s — 닫힌 자홍 px" % [lk[1], " · ".join(PackedStringArray(names))])
		var ch := _soldier(OUTFIT, PackedStringArray(lk[2]))
		var cells: Array = []
		for v in lk[3]:
			_pose(ch, String(v[2]), 0.3 if String(v[2]) != "A_TPose" else 0.0)
			await process_frame
			_frame(_seam_center(ch, String(v[1])), float(v[3]), float(v[4]), float(v[5]))
			var hs := PackedStringArray()
			for mode in 3:
				_look_mode(ch, mode)
				var img: Image = await _grab("%s · %s · %s" % [lk[1], v[0], names[mode]])
				hs.append(str(_holes(img).x))
				cells.append(img)
			_look_mode(ch, 0)
			_log("   %s: %s" % [v[0], " · ".join(hs)])
		_save(_sheet(cells, 3), "inside_%s.png" % lk[0])
		ch.queue_free()
		await process_frame


# ---------------------------------------------------------------- 무기

func _grip_for(mode: String, an: String, stored: Transform3D, one: Transform3D, ch: DRCharacter3D) -> Transform3D:
	match mode:
		"한 그립":
			return one
		"동작별":
			var r := DRGripFit.fit_anim(ch, an)
			return r["grip"] if not r.is_empty() else one
	return stored


func _weapon_sheets() -> void:
	_log("\n[무기] kar98k — 저장(asset.json 그립 = 2D 장비 굽기와 같은 자리) · 한 그립(DRGripFit.apply = Rifle_Idle 11.1 %) · 동작별(DRGripFit.apply_anim)")
	var ch := _soldier(OUTFIT, PackedStringArray(), true)
	if ch.get_weapon_node() == null:
		_log("   ⚠ 무기를 붙이지 못함")
		ch.queue_free()
		return
	var w := ch.get_weapon_entry()
	var eb: DREquipBaker = w["equip"]
	var stored := ch.get_weapon_grip()
	var t0 := Time.get_ticks_usec()
	var fit := DRGripFit.fit(ch)
	var t_fit := (Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	DRGripFit.fit(ch)
	var t_fit2 := (Time.get_ticks_usec() - t0) / 1000.0
	if fit.is_empty():
		_log("   ⚠ 그립 다시 맞추기 실패")
		ch.queue_free()
		return
	var one: Transform3D = fit["grip"]
	_log("무기 메시: 서피스 %d · 정점 %d · 숨김 %s · 붙인 뼈 %s · 잡는 점 어림(무기 공간) %s · 다시 맞추기 첫 %.1f ms · 캐시 %.2f ms" % [
		(w["mesh"] as ArrayMesh).get_surface_count(), _mesh_verts(w["mesh"]), str(eb.hidden_nodes), ch.get_weapon_mount().bone_name, _v(w["grip_point"]), t_fit, t_fit2])
	var rig: DRRigModel = ch.get_body_entry()["rig"]
	var pa: DRRigModel.Part = rig.parts[String(w["part"])]
	var palm_now := pa.tail_local * 0.5
	_log("손바닥 점(오른손 뼈 로컬): 저장 grip_pivot %s · 지금 몸 %s → %.1f cm 차이" % [_v(eb.grip_pivot), _v(palm_now), eb.grip_pivot.distance_to(palm_now) * 100.0])
	var db := eb.grip_base.affine_inverse() * (fit["base"] as Transform3D)
	_log("자동 그립(조정 전, 손 뼈 로컬): 저장 grip_base vs 지금 Rifle_Idle 11.1 %% 에서 다시 잡은 것 — 위치 %.1f cm · 회전 %.1f°" % [
		eb.grip_base.origin.distance_to((fit["base"] as Transform3D).origin) * 100.0, rad_to_deg(db.basis.orthonormalized().get_rotation_quaternion().get_angle())])
	# 그립 자세에서 무기가 놓이는 자리 차이(저장 → 한 그립)
	_pose(ch, "Rifle_Idle", 0.111111)
	var sk := ch.get_skeleton()
	var hr := sk.get_bone_global_pose(pa.root_bone)
	var s := float(w["scale"])
	var hold_m: Vector3 = (w["grip_point"] as Vector3) - eb.adj_pos / s
	var box: AABB = w["aabb"]
	var fw: Vector3 = w["forward"]
	var muzzle_m := box.get_center() + fw * (box.size.dot(fw.abs()) * 0.5)
	var butt_m := box.get_center() - fw * (box.size.dot(fw.abs()) * 0.5)
	var ws := hr * Transform3D(stored.basis * Basis.from_scale(Vector3.ONE * s), stored.origin)
	var wf := hr * Transform3D(one.basis * Basis.from_scale(Vector3.ONE * s), one.origin)
	var drot := ws.basis.orthonormalized().inverse() * wf.basis.orthonormalized()
	_log("Rifle_Idle 11.1 %% 에서 무기 자리 차이(저장 → 한 그립): 잡는 자리 %.1f cm · 총구 %.1f cm · 개머리판 끝 %.1f cm · 회전 %.1f°" % [
		(ws * hold_m).distance_to(wf * hold_m) * 100.0, (ws * muzzle_m).distance_to(wf * muzzle_m) * 100.0,
		(ws * butt_m).distance_to(wf * butt_m) * 100.0, rad_to_deg(drot.get_rotation_quaternion().get_angle())])
	# 동작마다 프레임을 훑어 손 어긋남(평균 / 최대) — 세 방식
	_log("손 어긋남(24 시점): 오른손 = 손바닥 ↔ 잡을 자리, 왼손 = 손바닥 ↔ 총열 방향 직선, 각 = 총열 ↔ 두 손바닥 방향")
	for an in WEAPON_ANIMS:
		if not _lib.has_animation(an):
			continue
		var grips := {}
		for mode in GRIP_MODES:
			grips[mode] = _grip_for(String(mode), an, stored, one, ch)
		var acc := {}
		for mode in GRIP_MODES:
			acc[mode] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		var n := 24
		for i in n:
			_pose(ch, an, i / float(n))
			for mode in GRIP_MODES:
				ch.set_weapon_grip(grips[mode])
				var m := DRGripFit.measure(ch)
				var a: Array = acc[mode]
				a[0] += float(m["r"])
				a[1] = maxf(a[1], float(m["r"]))
				a[2] += float(m["l"])
				a[3] = maxf(a[3], float(m["l"]))
				a[4] += float(m["angle"])
				a[5] = maxf(a[5], float(m["angle"]))
		for mode in GRIP_MODES:
			var a: Array = acc[mode]
			_log("   %-16s %-6s: 오른손 평균 %4.1f / 최대 %4.1f cm · 왼손 평균 %4.1f / 최대 %4.1f cm · 각 평균 %4.1f / 최대 %4.1f°" % [an, mode,
				a[0] / n * 100.0, a[1] * 100.0, a[2] / n * 100.0, a[3] * 100.0, a[4] / n, a[5]])
	ch.set_weapon_grip(stored)
	# 그림: 동작마다 행 = 시점, 열 = 방식(저장 · 한 그립 · 동작별) × 보기(오른 옆 · 3/4)
	for an in WEAPON_ANIMS:
		if not _lib.has_animation(an):
			continue
		var cells: Array = []
		for fr in WEAPON_FRAMES:
			_pose(ch, an, float(fr))
			await process_frame
			var c := (_bone_pos(ch, "RightHand") + _bone_pos(ch, "LeftHand")) * 0.5
			var hips := _bone_pos(ch, "Hips")
			for mode in GRIP_MODES:
				ch.set_weapon_grip(_grip_for(String(mode), an, stored, one, ch))
				for v in WEAPON_VIEWS:
					_frame(Vector3(hips.x, (c.y + 0.95) * 0.5, hips.z), float(v[1]), float(v[2]), 2.0)
					cells.append(await _grab("%s %d%% · %s · %s" % [an, int(float(fr) * 100), mode, v[0]]))
		ch.set_weapon_grip(stored)
		_save(_sheet(cells, GRIP_MODES.size() * WEAPON_VIEWS.size()), "weapon_%s.png" % an)
	# 손 확대: 그립 자세(Rifle_Idle 11.1 %)에서 행 = 저장 / 한 그립, 열 = 오른 옆 · 3/4 · 앞 · 위
	var cells2: Array = []
	_pose(ch, "Rifle_Idle", 0.111111)
	await process_frame
	var hc := (_bone_pos(ch, "RightHand") + _bone_pos(ch, "LeftHand")) * 0.5
	for mode in ["저장", "한 그립"]:
		ch.set_weapon_grip(stored if mode == "저장" else one)
		for v in [["오른 옆", -90.0, 5.0], ["3/4", -45.0, 15.0], ["앞", 0.0, 10.0], ["위", -60.0, 75.0]]:
			_frame(hc, float(v[1]), float(v[2]), 0.75)
			cells2.append(await _grab("Rifle_Idle 11%% · %s · %s" % [mode, v[0]]))
	ch.set_weapon_grip(stored)
	_save(_sheet(cells2, 4), "weapon_grip_closeup.png")
	ch.queue_free()
	await process_frame


func _mesh_verts(m: Mesh) -> int:
	var n := 0
	for si in m.get_surface_count():
		n += (m as ArrayMesh).surface_get_array_len(si)
	return n


func _v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


# ---------------------------------------------------------------- tint · fade

func _tint_fade() -> void:
	_log("\n[tint · fade] 왼쪽부터: 보통 · tint 어둡게(0.45) · fade 0.6 · fade 0.3 · fade 0 — 재질은 다섯 다 같은 객체")
	var specs := [[Color.WHITE, 1.0], [Color(0.45, 0.45, 0.45), 1.0], [Color.WHITE, 0.6], [Color.WHITE, 0.3], [Color.WHITE, 0.0]]
	var chs: Array = []
	for i in specs.size():
		var ch := _soldier(OUTFIT, PackedStringArray(), true)
		ch.position = Vector3((i - 2) * 0.9, 0, 0)
		ch.set_tint(specs[i][0])
		ch.set_fade(specs[i][1])
		_pose(ch, "Rifle_Idle", 0.111111)
		DRGripFit.apply_anim(ch, "Rifle_Idle")
		chs.append(ch)
	_vp.size = Vector2i(_cell * 3, _cell)
	_frame(Vector3(0, 0.92, 0), -20.0, 8.0, 2.1)
	await process_frame
	var img: Image = await _grab("보통 · tint 0.45 · fade 0.6 · fade 0.3 · fade 0")
	_save(img, "tint_fade.png")
	var same := true
	for ch in chs:
		same = same and (ch as DRCharacter3D).get_slot_node("top").mesh.surface_get_material(0) == (chs[0] as DRCharacter3D).get_slot_node("top").mesh.surface_get_material(0)
	_log("   다섯 병사 상의 재질 같은 객체=%s" % str(same))
	for ch in chs:
		(ch as Node).queue_free()
	_vp.size = Vector2i(_cell, _cell)
	await process_frame
