extends SceneTree

## 소켓 장비(3D) 그림 · 수치 도구(10-16) — 유닛 프리팹이 무기를 든 모습을 동작마다 찍고, 왼손 ↔ 표지 거리를 잰다.
## 그림을 찍으므로 창 모드(사용자 주 모니터를 가리지 않게 왼쪽 보조 모니터):
##   Godot.exe --path <프로젝트> --screen 0 --resolution 1280x720 \
##       --script res://addons/dot_rigger/tools/equip3d_shots_cli.gd -- [옵션]
## 옵션:
##   --unit=res://game/units/soldier_base.tscn   찍을 유닛 프리팹
##   --model=<무기 씬/glb>                       오른손 소켓 장비를 이 모델로 바꿔 넣기(시험 — 유닛 파일은 안 바뀜)
##   --hold=1                                    모델 옆 asset.json 의 무기 기본 자리(socket_hold)를 쓴다
##   --fit=Rifle_Aiming_Idle@0.3                 그 동작 · 시점의 두 손바닥으로 무기 자리 · 왼손 표지를 다시 잡는다(DREquipHold.fit)
##   --grip=x,y,z                                맞추기의 쥐는 점(장비 기준 m — 없으면 어림)
##   --support=x,y,z                             맞추기의 받치는 점(장비 기준 m — 주면 왼손 표지를 여기에, 짧은 무기용)
##   --weights=Sprint=0,Toss_Grenade=0           왼손 표지의 동작별 IK 비중
##   --save-unit=1                               위 결과를 유닛 씬에 저장(소켓 · 장비 · 표지)
##   --save-hold=1                               위 결과를 모델 옆 asset.json 의 socket_hold 에 저장
##   --old=1                                     옛 방식(weapon_asset + DRGripFit)도 같은 동작으로 재서 나란히 적는다
##   --compare=1                                 옛 방식 ↔ 새 방식 그림을 같은 동작 · 시점 · 카메라로 나란히(equip3d_<tag>_compare.png)
##   --shots=0                                   그림 없이 수치만(이때는 --headless 로 돌려도 된다)
##   --tag=kar98k  --out=res://_out  --cell=256
## 결과: <out>/equip3d_<tag>_<n>.png(행 = 동작, 열 = 손 확대 3/4 · 손 확대 옆 · 전신 3/4 · IK 끔 3/4) · equip3d_<tag>.txt

const MOTIONS := ["Rifle_Aiming_Idle", "Firing_Rifle", "Rifle_Idle", "Walk_With_Rifle", "Stand_Reloading",
	"Crouch_Idle+Firing_Rifle", "Crouch_Idle+Rifle_Aiming_Idle", "Crouch_Reload", "Prone_Firing_Rifle", "Sprint",
	"Crouch_Idle", "Crouch_Fwd", "Idle_Hit", "Toss_Grenade"]
const BG := Color(0.42, 0.47, 0.42)
const OLD_ASSET := "res://source3d/weapons/kar98k/asset.json"

var _args := {}
var _out := "res://_out"
var _cell := 256
var _tag := "unit"
var _vp: SubViewport
var _cam: Camera3D
var _label: Label
var _report := PackedStringArray()


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a).trim_prefix("--")
		var eq := s.find("=")
		_args[s if eq < 0 else s.substr(0, eq)] = "1" if eq < 0 else s.substr(eq + 1)
	_out = String(_args.get("out", _out))
	_cell = int(_args.get("cell", str(_cell)))
	_tag = String(_args.get("tag", _tag))
	_run.call_deferred()


func _log(s: String) -> void:
	print(s)
	_report.append(s)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	var unit := String(_args.get("unit", "res://game/units/soldier_base.tscn"))
	_build_viewport()
	var ch := (load(unit) as PackedScene).instantiate() as DRCharacter3D
	var model := String(_args.get("model", ""))
	if model != "":
		_swap_model(ch, model)
	_vp.add_child(ch)
	await process_frame
	var ap := ch.get_animation_player()
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var w := ch.get_weapon_node()
	if w == null:
		_log("⚠ 오른손 소켓에 무기가 없습니다: " + unit)
		quit(1)
		return
	var sock := w.get_parent() as BoneAttachment3D
	_log("[유닛] %s · 소켓 %s(%s) · 장비 %s(%s)" % [unit.get_file(), sock.name, sock.bone_name, w.name, w.scene_file_path.get_file()])
	if _args.has("hold"):
		var h := DREquipHold.read_hold(DREquipHold.asset_for_model(w.scene_file_path))
		if h.is_empty():
			_log("⚠ 무기 기본 자리(socket_hold)가 없습니다")
		else:
			w.transform = h["weapon"]
			if h.has("support"):
				_ensure_marker(w).transform = h["support"]
			_set_weights(_ensure_marker(w), h["motion_weights"])
			_log("무기 기본 자리 씀(asset.json socket_hold)")
	if _args.has("fit"):
		var fs := String(_args["fit"]).split("@")
		var gp := DREquipHold.grip_point_guess(w)
		if _args.has("grip"):
			var g := String(_args["grip"]).split(",")
			gp = Vector3(float(g[0]), float(g[1]), float(g[2]))
		var sp: Variant = null
		if _args.has("support"):
			var s := String(_args["support"]).split(",")
			sp = Vector3(float(s[0]), float(s[1]), float(s[2]))
		var r := DREquipHold.fit(ch, sock.bone_name, fs[0], float(fs[1]) if fs.size() > 1 else 0.3, gp, w.scale, sp)
		if r.is_empty():
			_log("⚠ 맞추기 실패: " + String(_args["fit"]))
		else:
			w.transform = r["weapon"]
			_ensure_marker(w).transform = r["support"]
			_log("맞추기 %s · 쥐는 점(장비 기준) %s · 두 손바닥 거리 %.1f cm" % [_args["fit"], _v(gp), float(r["gap"]) * 100.0])
	if _args.has("weights"):
		var mw := {}
		for kv in String(_args["weights"]).split(","):
			var p := String(kv).split("=")
			if p.size() == 2:
				mw[p[0]] = float(p[1])
		_set_weights(_ensure_marker(w), mw)
	ch.refresh_equipment()
	var mk := ch.get_support_marker()
	_log("무기 자리(소켓 기준) %s" % _xs(w.transform))
	if mk != null:
		_log("왼손 표지(무기 기준) %s · 동작별 비중 %s" % [_xs(mk.transform), str((mk as DRHandTarget3D).motion_weights) if mk is DRHandTarget3D else "-"])
	# 수치
	var names := PackedStringArray()
	for m in ch.motion_names():
		names.append(m)
	var rep := DREquipHold.motion_report(ch, names, 12)
	_log("\n[왼손] 동작마다 12 시점 — 동작 그대로(IK 전) 손바닥 ↔ 표지 · IK 뒤 · 손 회전 ↔ 표지 · 어깨→손목 목표 / 팔 길이(1 넘으면 안 닿음)")
	for r in rep:
		var d: Dictionary = r
		_log("   %-30s 비중 %.2f · IK 전 평균 %5.1f / 최대 %5.1f cm · IK 뒤 평균 %4.1f / 최대 %4.1f cm · 회전 최대 %4.1f° · 닿음 최대 %.2f" % [
			d["motion"], d["weight"], float(d["raw_avg"]) * 100.0, float(d["raw_max"]) * 100.0, float(d["ik_avg"]) * 100.0,
			float(d["ik_max"]) * 100.0, d["rot_max"], d["reach_max"]])
	if _args.has("old"):
		await _old_numbers(names)
	if String(_args.get("shots", "1")) != "0":
		await _shots(ch)
	if _args.has("compare"):
		await _compare(ch)
	if _args.has("save-unit"):
		_save_unit(unit, ch)
	if _args.has("save-hold"):
		var asset := DREquipHold.asset_for_model(w.scene_file_path)
		var ok := DREquipHold.write_hold(asset, sock.bone_name, w.scene_file_path, w.transform,
			mk.transform if mk != null else null, (mk as DRHandTarget3D).motion_weights if mk is DRHandTarget3D else {})
		_log("무기 기본 자리 저장 %s → %s" % [str(ok), asset])
	var f := FileAccess.open(ProjectSettings.globalize_path(_out.path_join("equip3d_%s.txt" % _tag)), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_report) + "\n")
		f.close()
	print("[완료] ", _out)
	quit(0)


# ---------------------------------------------------------------- 준비

func _build_viewport() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(_cell, _cell)
	_vp.own_world_3d = true
	_vp.world_3d = World3D.new()
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_DISABLED
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
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	_label.position = Vector2(3, 0)
	_vp.add_child(_label)


## 오른손 소켓의 장비를 다른 모델로(시험) — 기존 장비는 지우고 새 인스턴스
func _swap_model(ch: DRCharacter3D, model: String) -> void:
	for s in DRCharacter3D.find_sockets(ch):
		if s.bone_name != DRCharacter3D.WEAPON_BONE:
			continue
		for c in s.get_children():
			s.remove_child(c)
			c.free()
		var n := DREquipHold.instantiate_model(model)
		s.add_child(n)
		n.owner = ch
		return


func _ensure_marker(w: Node3D) -> Node3D:
	var m := DRCharacter3D.find_support(w)
	if m != null:
		return m
	var t := DRHandTarget3D.new()
	t.name = DRCharacter3D.SUPPORT_NAME
	w.add_child(t)
	t.owner = w.owner
	return t


func _set_weights(m: Node3D, mw: Dictionary) -> void:
	if m is DRHandTarget3D:
		var d: Dictionary[String, float] = {}
		for k in mw.keys():
			d[String(k)] = float(mw[k])
		(m as DRHandTarget3D).motion_weights = d


# ---------------------------------------------------------------- 옛 방식 수치(weapon_asset + DRGripFit)

func _old_numbers(names: PackedStringArray) -> void:
	var ch := DRCharacter3D.new()
	ch.auto_build = false
	ch.weapon_asset = OLD_ASSET
	ch.motions = load("res://game/units/rifleman_motions.tres") as DRMotionTable
	_vp.add_child(ch)
	if not ch.build():
		_log("⚠ 옛 방식 조립 실패")
		return
	ch.get_animation_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	ch.visible = false
	_log("\n[옛 방식] weapon_asset(kar98k asset.json 그립) + DRGripFit 동작별 다시 맞춤 — 12 시점: 오른손 = 손바닥 ↔ 잡을 자리, 왼손 = 손바닥 ↔ 총열 직선(수직) · 직선을 따라 앞뒤")
	var ap := ch.get_animation_player()
	for mo in names:
		if not ap.has_animation(mo):
			continue
		ch.play_motion(mo, 0.0)
		var acc := [0.0, 0.0, 0.0, 0.0, 0.0]
		for i in 12:
			DRGripFit.pose(ch, mo, i / 12.0)
			var m := DRGripFit.measure(ch)
			acc[0] += float(m["r"]) / 12.0
			acc[1] = maxf(acc[1], float(m["r"]))
			acc[2] += float(m["l"]) / 12.0
			acc[3] = maxf(acc[3], float(m["l"]))
			acc[4] = maxf(acc[4], absf(float(m["l_along"])))
		_log("   %-30s 오른손 평균 %4.1f / 최대 %4.1f cm · 왼손(직선까지) 평균 %4.1f / 최대 %4.1f cm · 앞뒤 최대 %4.1f cm" % [mo,
			acc[0] * 100.0, acc[1] * 100.0, acc[2] * 100.0, acc[3] * 100.0, acc[4] * 100.0])
	ch.queue_free()
	await process_frame


# ---------------------------------------------------------------- 그림

func _frame(center: Vector3, yaw: float, pitch: float, size: float) -> void:
	var b := DRBaker.view_basis(yaw, pitch)
	_cam.size = size
	_cam.global_transform = Transform3D(b, center + b * Vector3(0, 0, 8.0))


func _grab(caption: String) -> Image:
	_label.text = caption
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


## 동작 자세로 세우고(IK 포함 — 뼈대 갱신을 바로) 그 시점의 손 확대 가운데(오른손 소켓 · 왼손 표지 사이)
func _pose(ch: DRCharacter3D, mo: String, frac: float) -> Vector3:
	var ap := ch.get_animation_player()
	ap.seek(ap.get_animation(mo).length * frac, true)
	ch.support_report()                        # 뼈대를 바로 갱신(IK 포함) — 소켓도 따라온다
	var a := ch.get_weapon_mount().global_position
	var mk := ch.get_support_marker()
	var b := mk.global_position if mk != null else a
	return (a + b) * 0.5


func _shots(ch: DRCharacter3D) -> void:
	var ap := ch.get_animation_player()
	var cells: Array = []
	var sheet := 0
	var rows := 0
	var list: Array = MOTIONS
	if _args.has("motions"):
		list = Array(String(_args["motions"]).split(","))
	for mo in list:
		if not ap.has_animation(String(mo)):
			continue
		ch.play_motion(String(mo), 0.0)
		var w := ch.get_ik_weight()
		var c1 := _pose(ch, mo, 0.25)
		await process_frame
		_frame(c1, -45.0, 12.0, 0.85)
		cells.append(await _grab("%s 25%% · 손 3/4 · IK %.1f" % [mo, w]))
		_frame(c1, -90.0, 4.0, 0.85)
		cells.append(await _grab("%s 25%% · 손 옆" % mo))
		var hips := ch.get_skeleton().global_transform * ch.get_skeleton().get_bone_global_pose(ch.get_skeleton().find_bone("Hips"))
		_frame(Vector3(hips.origin.x, clampf(hips.origin.y + 0.05, 0.45, 0.95), hips.origin.z), -35.0, 8.0, 2.1)
		cells.append(await _grab("%s 25%% · 전신 3/4" % mo))
		# 같은 시점 IK 끔(동작 그대로 왼손)
		var ik := ch.get_left_arm_ik()
		if ik != null:
			ch._set_ik_weight(0.0)
			ch.support_report()
			await process_frame
			_frame(c1, -45.0, 12.0, 0.85)
			cells.append(await _grab("%s 25%% · IK 끔(동작 그대로)" % mo))
			ch._set_ik_weight(w)
		rows += 1
		if rows == 5:
			_save(_sheet(cells, 4), "equip3d_%s_%d.png" % [_tag, sheet])
			cells = []
			rows = 0
			sheet += 1
	if not cells.is_empty():
		_save(_sheet(cells, 4), "equip3d_%s_%d.png" % [_tag, sheet])


## 옛 방식(같은 몸 · 옷 + weapon_asset kar98k + DRGripFit 동작별 그립) ↔ 새 방식(소켓 + 왼손 IK) — 행마다 동작 둘(옛 · 새 · 옛 · 새)
func _compare(ch: DRCharacter3D) -> void:
	var old := DRCharacter3D.new()
	old.auto_build = false
	old.body_model = ch.body_model
	old.outfit_top = ch.outfit_top
	old.outfit_bottom = ch.outfit_bottom
	old.weapon_asset = OLD_ASSET
	old.motions = ch.motions
	old.height_m = ch.height_m
	_vp.add_child(old)
	if not old.build():
		_log("⚠ 옛 방식 조립 실패")
		return
	old.get_animation_player().callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	old.precompute_grips()
	var list: Array = ["Rifle_Aiming_Idle", "Firing_Rifle", "Rifle_Idle", "Walk_With_Rifle", "Crouch_Idle+Firing_Rifle", "Prone_Firing_Rifle", "Stand_Reloading", "Idle_Hit"]
	if _args.has("motions"):
		list = Array(String(_args["motions"]).split(","))
	var cells: Array = []
	for mo in list:
		var m := String(mo)
		if not ch.get_animation_player().has_animation(m):
			continue
		ch.visible = true
		ch.play_motion(m, 0.0)
		var c := _pose(ch, m, 0.25)
		old.play_motion(m, 0.0)
		var oap := old.get_animation_player()
		oap.seek(oap.get_animation(m).length * 0.25, true)
		var osk := old.get_skeleton()
		osk.set_bone_pose_rotation(0, osk.get_bone_pose_rotation(0))
		osk.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		ch.visible = false
		old.visible = true
		await process_frame
		_frame(c, -45.0, 12.0, 0.9)
		cells.append(await _grab("%s 25%% · 옛 방식(asset.json 그립 + DRGripFit)" % m))
		old.visible = false
		ch.visible = true
		await process_frame
		_frame(c, -45.0, 12.0, 0.9)
		cells.append(await _grab("%s 25%% · 새 방식(소켓 + 왼손 IK %.1f)" % [m, ch.get_ik_weight()]))
	_save(_sheet(cells, 4), "equip3d_%s_compare.png" % _tag)
	old.queue_free()
	await process_frame


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


# ---------------------------------------------------------------- 저장

## 유닛 씬에 저장 — 씬을 편집 상태로 새로 열어(몸 조립 없이) 같은 자리의 노드에 결과를 옮기고 pack · save(② 탭의 에디터 밖 저장과 같은 길)
func _save_unit(unit: String, ch: DRCharacter3D) -> void:
	var ed := (load(unit) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_MAIN) as DRCharacter3D
	var w := ch.get_weapon_node()
	var path := ch.get_path_to(w)
	var tw := ed.get_node_or_null(path) as Node3D
	if tw == null or tw.scene_file_path != w.scene_file_path:
		_log("⚠ 유닛 씬에 같은 장비 노드가 없어 저장하지 않음(--model 로 바꾼 것은 --save-hold 로)")
		ed.free()
		return
	tw.transform = w.transform
	var mk := ch.get_support_marker()
	if mk != null:
		var tm := DRCharacter3D.find_support(tw)
		if tm == null:
			tm = DRHandTarget3D.new()
			tm.name = DRCharacter3D.SUPPORT_NAME
			tw.add_child(tm)
			tm.owner = ed
		tm.transform = mk.transform
		if mk is DRHandTarget3D and tm is DRHandTarget3D:
			(tm as DRHandTarget3D).motion_weights = (mk as DRHandTarget3D).motion_weights.duplicate()
	var ps := PackedScene.new()
	var ok := ps.pack(ed) == OK and ResourceSaver.save(ps, unit) == OK
	_log("유닛 씬 저장 %s → %s" % [str(ok), unit])
	ed.free()


func _v(v: Vector3) -> String:
	return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]


func _xs(t: Transform3D) -> String:
	var e := t.basis.get_euler() * (180.0 / PI)
	return "위치 %s m · 회전 (%.1f°, %.1f°, %.1f°)" % [_v(t.origin), e.x, e.y, e.z]
