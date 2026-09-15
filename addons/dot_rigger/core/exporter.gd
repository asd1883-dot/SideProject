@tool
extends RefCounted
class_name DRExporter

## 베이크 실행 + 결과물 저장(파트 PNG / rig.json / puppet.tscn).

signal progress(stage: String, cur: int, total: int)

var baker: DRBaker
var out_dir: String = "res://puppet"
var anim_fps: int = 12
var anim_names: PackedStringArray = PackedStringArray()
var auto_fit: bool = true
var fit_margin: int = 6
## 본 축 단축 보정. 끄면 강체 스프라이트가 되어 팔 관절이 벌어질 수 있고,
## 켜면 픽셀이 축 방향으로 늘어나므로 도트 결이 약간 흐트러진다.
var apply_stretch: bool = true
var stretch_limit: float = 1.6

## 부드러운 도트 이동 셰이더를 파트 스프라이트에 붙인다.
## 게임에서 캐릭터를 확대해서 그릴 때 1픽셀 미만 움직임이 깜빡임(TV 노이즈) 대신 매끄럽게 보인다.
var smooth_pixel: bool = true
const SMOOTH_SHADER := "res://addons/dot_rigger/runtime/smooth_pixel.gdshader"

## 그리기 순서 수동 지정 — 레이어 이름, 뒤 -> 앞. 비어 있으면 3D 깊이로 자동 계산한다.
## 값이 있으면 그 순서를 모든 프레임에 고정하고, 프레임별 z 트랙을 만들지 않는다.
## (한 각도로 고정된 게임에서는 고정 표가 예측 가능해서 더 안전한 경우가 많다)
var z_override: PackedStringArray = PackedStringArray()

## 같은 출력 폴더에 예전에 구운 애니메이션을 이어서 담을지.
## 애니 값은 "레스트 포즈·카메라 기준 상대값"이라 둘이 같을 때만 섞는다.
## 다르면 예전 애니는 버리고 dropped_reason 에 이유를 남긴다. 이름이 같은 애니는 이번 것으로 교체.
var keep_previous: bool = true
## 실행 결과: 예전 rig.json 에서 이어 담은 애니 이름 / 이어 담지 못한 이유("" = 없음)
var kept_anims: PackedStringArray = PackedStringArray()
var dropped_reason: String = ""

var _part_crop: Dictionary = {}   # part -> Rect2i
var _part_img: Dictionary = {}    # part -> Image
var _anim_data: Dictionary = {}


func run() -> Dictionary:
	if baker == null or baker.rig == null:
		return {"ok": false, "error": "baker 미설정"}

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir.path_join("parts")))

	# 1) 레스트 포즈 확정 + 기준 투영값 캡처
	# (UI 에서 해상도를 바꿨을 수 있으므로 뷰포트 크기를 먼저 맞춘다)
	baker.apply_view_size()
	baker.set_rest_pose()
	await RenderingServer.frame_post_draw
	if auto_fit:
		await baker.auto_fit(fit_margin)
	baker.rig.capture_rest(baker.skeleton, baker.camera)

	# 2) 파트별 스프라이트 렌더
	var names := baker.rig.order
	var total := names.size()
	var i := 0
	for part in names:
		i += 1
		progress.emit("파트 렌더", i, total)
		if not baker.part_nodes.has(part):
			continue
		var img: Image = await baker.render_part(part)
		var used := img.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			push_warning("[DotRigger] 파트 %s 가 비어 있어 건너뜁니다." % part)
			continue
		var final_img := img
		if baker.opts.trim_parts:
			final_img = img.get_region(used)
		else:
			used = Rect2i(Vector2i.ZERO, Vector2i(img.get_width(), img.get_height()))
		_part_crop[part] = used
		_part_img[part] = final_img
		final_img.save_png(out_dir.path_join("parts/%s.png" % part))

	# 3) 애니메이션 투영
	var ai := 0
	for aname in anim_names:
		ai += 1
		progress.emit("애니메이션 투영", ai, anim_names.size())
		var key := baker.resolve_anim(aname)
		if key == "":
			key = aname
		_anim_data[key] = await _project_anim(aname)

	# 4) 같은 폴더에 예전에 구운 애니가 있으면 이어 담는다(같은 레스트 포즈·시점일 때만)
	#    rig.json 을 덮어쓰기 전에 읽어야 한다.
	_merge_previous()

	# 5) 저장
	_write_json()
	var scene_path := out_dir.path_join("puppet.tscn")
	var err := _build_and_save_scene(scene_path)

	return {
		"ok": err == OK,
		"parts": _part_crop.keys(),
		"animations": _anim_data.keys(),
		"scene": scene_path,
		"json": out_dir.path_join("rig.json"),
		"kept": kept_anims,
		"dropped_reason": dropped_reason,
	}


## 출력 폴더의 예전 rig.json 에서 애니메이션을 가져와 이번 결과에 합친다.
func _merge_previous() -> void:
	kept_anims = PackedStringArray()
	dropped_reason = ""
	if not keep_previous:
		return
	var path := out_dir.path_join("rig.json")
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var doc = JSON.parse_string(f.get_as_text())
	f.close()
	if not (doc is Dictionary) or not (doc.get("animations") is Dictionary):
		return
	var old: Dictionary = doc["animations"]
	var old_names := PackedStringArray()
	for an in old.keys():
		if not _anim_data.has(an):
			old_names.append(String(an))
	if old_names.is_empty():
		return
	var why := _incompatible_reason(doc)
	if why != "":
		dropped_reason = "%s — 예전 애니 %s 는 섞을 수 없어 뺐습니다" % [why, ", ".join(old_names)]
		push_warning("[DotRigger] " + dropped_reason)
		return
	for an in old_names:
		_anim_data[an] = old[an]
		kept_anims.append(an)


## 예전 결과와 이번 결과의 애니를 섞으면 안 되는 이유. 같으면 "".
## 애니 값(위치·회전)은 레스트 포즈를 이 카메라로 찍은 기준에서 잰 상대값이다.
func _incompatible_reason(doc: Dictionary) -> String:
	var v: Dictionary = doc.get("view", {})
	var now := baker.serialize_view()
	if String(v.get("rest_anim", "")) != String(now["rest_anim"]) \
			or absf(float(v.get("rest_time", 0.0)) - float(now["rest_time"])) > 0.0001:
		return "레스트 포즈가 다름 (예전 %s %d%% → 지금 %s %d%%)" % [
			v.get("rest_anim", ""), int(float(v.get("rest_time", 0.0)) * 100.0),
			now["rest_anim"], int(float(now["rest_time"]) * 100.0)]
	var sz: Array = v.get("size", [])
	if sz.size() != 2 or int(sz[0]) != int(now["size"][0]) or int(sz[1]) != int(now["size"][1]):
		return "해상도가 다름 (예전 %s → 지금 %s)" % [str(sz), str(now["size"])]
	if absf(float(v.get("ortho_size", 0.0)) - float(now["ortho_size"])) > 0.001:
		return "카메라 크기(Ortho)가 다름 (예전 %.3f → 지금 %.3f)" % [float(v.get("ortho_size", 0.0)), float(now["ortho_size"])]
	for key in ["camera_basis", "camera_origin"]:
		var a: Array = v.get(key, [])
		var b: Array = now[key]
		if a.size() != b.size():
			return "시점(카메라 위치·각도)이 다름"
		for i in a.size():
			if absf(float(a[i]) - float(b[i])) > 0.001:
				return "시점(카메라 위치·각도)이 다름"
	var old_parts := {}
	for p in doc.get("parts", []):
		old_parts[String(p.get("name", ""))] = true
	if old_parts.size() != _part_crop.size():
		return "파트 구성이 다름 (예전 %d개 → 지금 %d개)" % [old_parts.size(), _part_crop.size()]
	for pn in _part_crop.keys():
		if not old_parts.has(String(pn)):
			return "파트 구성이 다름 (%s)" % pn
	return ""


## 그리기 순서를 레이어 단위(뒤 -> 앞)로 확정한다.
## z_override 는 레이어 이름 목록(옛 프리셋처럼 파트 이름이 섞여도 소속 레이어로 바뀜).
## 비어 있으면 레스트 포즈의 카메라 깊이로 자동 정렬한다.
func resolve_layer_order() -> PackedStringArray:
	if z_override.size() > 0:
		return baker.rig.normalize_layer_order(z_override)
	return baker.rig.rest_layer_order()


## 파트 단위 그리기 순서(뒤 -> 앞). 레이어 순서를 펼친 것이라
## 한 레이어의 파트(발 + 발가락)는 항상 붙어서 연속된 z 를 받는다.
func resolve_z_order() -> PackedStringArray:
	var out := PackedStringArray()
	for pname in baker.rig.expand_layers(resolve_layer_order()):
		if _part_crop.has(pname):
			out.append(pname)
	return out


## 에디터에서 PNG 임포트가 끝난 뒤 다시 호출하면, 씬이 임베드된 이미지 대신
## 임포트된 텍스처 파일을 참조하도록 다시 저장한다.
func rebuild_scene() -> int:
	return _build_and_save_scene(out_dir.path_join("puppet.tscn"))


func _project_anim(aname: String) -> Dictionary:
	var ap := baker.anim_player
	if ap == null:
		return {}
	var resolved := baker.resolve_anim(aname)
	if resolved == "":
		push_warning("[DotRigger] 애니메이션을 찾을 수 없습니다: %s" % aname)
		return {}
	aname = resolved
	var anim := ap.get_animation(aname)
	var length: float = maxf(anim.length, 0.0001)
	var looping := anim.loop_mode != Animation.LOOP_NONE
	var count: int = maxi(1, int(round(length * float(anim_fps))))
	var frames: Array = []
	for f in count:
		var t: float = 0.0
		if looping:
			# 루프는 마지막 프레임이 0프레임과 겹치므로 [0, length) 로 샘플
			t = (float(f) / float(count)) * length
		else:
			t = (float(f) / float(maxi(count - 1, 1))) * length
		baker.set_pose(aname, t)
		await RenderingServer.frame_post_draw
		frames.append({"t": t, "parts": _to_json(
			baker.rig.project_local(baker.skeleton, baker.camera))})

	_unwrap_rotations(frames)
	if looping and frames.size() > 1:
		frames.append(_closing_frame(frames, length))
	return {"fps": anim_fps, "length": length, "loop": looping, "frames": frames}


## atan2 는 [-PI, PI] 로 감기므로 경계에 걸친 파트는 프레임 사이에서 각도가 360도 튄다.
## 그대로 두면 Godot 이 키 사이를 보간할 때 한 바퀴를 헛돈다. 프레임 순서대로 펴 준다.
func _unwrap_rotations(frames: Array) -> void:
	if frames.size() < 2:
		return
	var prev := {}
	for fr in frames:
		var pd: Dictionary = fr["parts"]
		for pname in pd.keys():
			var r: float = float(pd[pname]["r"])
			if prev.has(pname):
				var p: float = float(prev[pname])
				while r - p > PI:
					r -= TAU
				while r - p < -PI:
					r += TAU
			pd[pname]["r"] = r
			prev[pname] = r


## 루프 애니메이션은 [0, length) 로 샘플하므로 끝에 0프레임 사본을 붙여
## 마지막 키 -> 루프 지점 구간도 매끄럽게 이어지게 한다.
func _closing_frame(frames: Array, length: float) -> Dictionary:
	var first: Dictionary = frames[0]["parts"]
	var last: Dictionary = frames[frames.size() - 1]["parts"]
	var out := {}
	for pname in first.keys():
		var e: Dictionary = (first[pname] as Dictionary).duplicate(true)
		if last.has(pname):
			var r: float = float(e["r"])
			var p: float = float(last[pname]["r"])
			while r - p > PI:
				r -= TAU
			while r - p < -PI:
				r += TAU
			e["r"] = r
		out[pname] = e
	return {"t": length, "parts": out}


## project_local() 결과를 JSON 에 담을 수 있는 형태로 바꾼다(Vector2 -> [x, y]).
func _to_json(loc: Dictionary) -> Dictionary:
	var out := {}
	for pname in loc.keys():
		var e: Dictionary = loc[pname]
		var lp: Vector2 = e["p"]
		out[pname] = {
			"p": [lp.x, lp.y],
			"r": float(e["r"]),
			"s": float(e["s"]),
			"d": float(e["d"]),
			"z": int(e.get("z", 0)),
		}
	return out


func _write_json() -> void:
	var parts_arr: Array = []
	for pname in baker.rig.order:
		if not _part_crop.has(pname):
			continue
		var p: DRRigModel.Part = baker.rig.parts[pname]
		var c: Rect2i = _part_crop[pname]
		parts_arr.append({
			"name": pname,
			"parent": p.parent,
			"layer": baker.rig.layer(pname),
			"stretch": not baker.rig.no_stretch.has(pname),   # false = 늘이기 없이 회전만(예: 발)
			"root_bone": baker.skeleton.get_bone_name(p.root_bone),
			"bones": p.bones.size(),
			"image": "parts/%s.png" % pname,
			"crop": [c.position.x, c.position.y, c.size.x, c.size.y],
			"rest": {
				"head": [p.rest_head2d.x, p.rest_head2d.y],
				"angle": p.rest_angle,
				"len": p.rest_len2d,
				"depth": p.rest_depth,
			},
		})
	var doc := {
		"version": 1,
		"view": baker.serialize_view(),
		"parts": parts_arr,
		"z_order": resolve_z_order(),        # 뒤 -> 앞
		"layer_order": resolve_layer_order(),   # 그리기 순서 목록(레이어) 뒤 -> 앞
		"z_order_manual": z_override.size() > 0,
		"smooth_pixel": smooth_pixel,   # 파트 스프라이트에 runtime/smooth_pixel.gdshader 를 붙였는지
		"animations": _anim_data,
		"unmapped_bones": baker.split.unmapped_bones,
	}
	var f := FileAccess.open(out_dir.path_join("rig.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(doc, "\t"))
		f.close()


func _build_and_save_scene(path: String) -> int:
	var root := Node2D.new()
	root.name = "Puppet"
	var puppet_script := load("res://addons/dot_rigger/runtime/dr_puppet.gd")
	if puppet_script != null:
		root.set_script(puppet_script)
	var skel2d := Skeleton2D.new()
	skel2d.name = "Skeleton2D"
	root.add_child(skel2d)

	# 정지 상태(애니메이션을 재생하지 않을 때)의 그리기 순서.
	# 이걸 안 넣으면 전부 z_index=0 이 되어 씬 트리 순서가 그리기 순서가 되고,
	# 어깨가 몸통 위로 올라오는 식으로 어긋난다.
	var zorder := resolve_z_order()
	var z_of := {}
	for i in zorder.size():
		z_of[zorder[i]] = i

	# 모든 파트가 머티리얼 하나를 같이 쓴다(씬에 한 번만 저장됨)
	var smooth_mat: ShaderMaterial = null
	if smooth_pixel:
		var sh := load(SMOOTH_SHADER) as Shader
		if sh != null:
			smooth_mat = ShaderMaterial.new()
			smooth_mat.shader = sh
		else:
			push_warning("[DotRigger] 부드러운 도트 셰이더를 찾을 수 없습니다: %s" % SMOOTH_SHADER)

	var bones := {}   # part -> Bone2D
	for pname in baker.rig.order:
		if not _part_crop.has(pname):
			continue
		var p: DRRigModel.Part = baker.rig.parts[pname]
		var b := Bone2D.new()
		b.name = pname
		var parent_node: Node2D = skel2d
		var parent_head := Vector2.ZERO
		if p.parent != "" and bones.has(p.parent):
			parent_node = bones[p.parent]
			parent_head = (baker.rig.parts[p.parent] as DRRigModel.Part).rest_head2d
		parent_node.add_child(b)
		b.position = p.rest_head2d - parent_head
		b.rotation = 0.0
		b.rest = Transform2D(0.0, b.position)
		# 말단 본은 자식이 없어 Godot 이 길이/각도를 못 구하고 경고를 낸다.
		# 3D 에서 이미 알고 있으므로 직접 넣어 준다(에디터 기즈모 표시에도 쓰임).
		b.set_autocalculate_length_and_angle(false)
		b.set_length(p.rest_len2d)
		b.set_bone_angle(p.rest_angle)

		# 본 축 방향 늘이기 노드.
		# 3D 에서 팔다리가 카메라 쪽으로 돌면 화면상 길이가 짧아지는데(단축),
		# 강체 스프라이트는 그걸 표현하지 못해 관절이 떨어져 보인다.
		# 본 축을 x축에 맞춘 뒤 x 만 스케일하고 되돌리는 구조.
		# scale=(1,1) 이면 아무 영향 없으므로 stretch 를 꺼도 계층은 그대로다.
		var stretch := Node2D.new()
		stretch.name = "stretch"
		stretch.rotation = p.rest_angle
		b.add_child(stretch)

		var spr := Sprite2D.new()
		spr.name = "art"
		spr.centered = false
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.z_as_relative = false
		spr.z_index = int(z_of.get(pname, 0))
		spr.material = smooth_mat
		spr.rotation = -p.rest_angle
		# 에디터에서 실행하면 임포트된 텍스처를 쓰고, CLI 등 임포트 전이면
		# 방금 렌더한 Image 를 그대로 씬에 심는다.
		var tex_path := out_dir.path_join("parts/%s.png" % pname)
		var tex: Texture2D = null
		if ResourceLoader.exists(tex_path, "Texture2D"):
			tex = ResourceLoader.load(tex_path, "Texture2D") as Texture2D
		if tex == null and _part_img.has(pname):
			tex = ImageTexture.create_from_image(_part_img[pname])
		if tex != null:
			spr.texture = tex
		var crop: Rect2i = _part_crop[pname]
		spr.position = (Vector2(crop.position) - p.rest_head2d).rotated(-p.rest_angle)
		stretch.add_child(spr)
		bones[pname] = b

	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	var lib := AnimationLibrary.new()
	for aname in _anim_data.keys():
		var a := _make_animation(_anim_data[aname], bones, root)
		if a != null:
			lib.add_animation(StringName(aname), a)
	ap.add_animation_library("", lib)

	_set_owner(root, root)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	if err != OK:
		root.free()
		return err
	err = ResourceSaver.save(ps, path)
	root.free()
	return err


func _make_animation(data: Dictionary, bones: Dictionary, root: Node2D) -> Animation:
	var frames: Array = data.get("frames", [])
	if frames.is_empty():
		return null
	var a := Animation.new()
	a.length = float(data.get("length", 1.0))
	if bool(data.get("loop", false)):
		a.loop_mode = Animation.LOOP_LINEAR
	else:
		a.loop_mode = Animation.LOOP_NONE
	a.step = 1.0 / float(maxi(int(data.get("fps", 12)), 1))

	for pname in bones.keys():
		var node: Node2D = bones[pname]
		var base := String(root.get_path_to(node))
		var t_pos := a.add_track(Animation.TYPE_VALUE)
		a.track_set_path(t_pos, NodePath(base + ":position"))
		var t_rot := a.add_track(Animation.TYPE_VALUE)
		a.track_set_path(t_rot, NodePath(base + ":rotation"))
		# 수동 순서를 지정했으면 프레임별 z 를 만들지 않는다.
		# (씬에 박아 둔 고정 z_index 가 모든 프레임에 그대로 유지된다)
		var t_z := -1
		if z_override.is_empty():
			t_z = a.add_track(Animation.TYPE_VALUE)
			a.track_set_path(t_z, NodePath(base + "/stretch/art:z_index"))
			a.value_track_set_update_mode(t_z, Animation.UPDATE_DISCRETE)
			a.track_set_interpolation_type(t_z, Animation.INTERPOLATION_NEAREST)
		var t_s := -1
		if apply_stretch and not baker.rig.no_stretch.has(pname):
			t_s = a.add_track(Animation.TYPE_VALUE)
			a.track_set_path(t_s, NodePath(base + "/stretch:scale"))

		for fr in frames:
			var t := float(fr["t"])
			var pd: Dictionary = fr["parts"]
			if not pd.has(pname):
				continue
			var e: Dictionary = pd[pname]
			var pa: Array = e["p"]
			a.track_insert_key(t_pos, t, Vector2(float(pa[0]), float(pa[1])))
			a.track_insert_key(t_rot, t, float(e["r"]))
			if t_z >= 0:
				a.track_insert_key(t_z, t, int(e.get("z", 0)))
			if t_s >= 0:
				var s := clampf(float(e.get("s", 1.0)), 1.0 / stretch_limit, stretch_limit)
				a.track_insert_key(t_s, t, Vector2(s, 1.0))
	return a


static func _set_owner(n: Node, owner: Node) -> void:
	for c in n.get_children():
		c.owner = owner
		_set_owner(c, owner)
