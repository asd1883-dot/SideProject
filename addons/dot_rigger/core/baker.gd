@tool
extends RefCounted
class_name DRBaker

## A뷰의 엔진. 3D 모델을 고정 시점에서 파트별로 렌더하고,
## 애니메이션을 2D 본 커브로 투영해 내보낸다.

const SHADER_PATH := "res://addons/dot_rigger/shaders/dot_flat.gdshader"

## 동작 평면화용 두 번째 카메라. 렌더하지 않고(current 아님) 뼈 각도만 이 시점에서 잰다.
var pose_camera: Camera3D


class Options:
	var view_size: Vector2i = Vector2i(192, 192)
	var yaw: float = 90.0          # 도(°). 90 = 정측면
	var pitch: float = 0.0
	var ortho_size: float = 0.0    # 0 = 모델 크기에 맞춰 자동
	var supersample: int = 1       # 2 이상이면 크게 렌더 후 축소(부드러운 도트)
	var alpha_threshold: float = 0.5
	var color_levels: int = 0      # 0 = 양자화 끔
	var bleed_rings: int = 1
	var rest_anim: String = ""
	var rest_time: float = 0.0
	var light_bands: int = 3
	var ambient: float = 0.45
	var light_dir: Vector3 = Vector3(-0.4, 0.7, 0.6)
	var trim_parts: bool = true
	## 캐릭터 화면 위치 이동(px). +x = 오른쪽, +y = 위. 도트 크기(Ortho)는 그대로 두고 찍는 틀만 옮긴다.
	## 자동 맞춤이 켜져 있으면 결국 다시 가운데로 맞춰진다.
	var view_offset: Vector2 = Vector2.ZERO
	## 동작 평면화(2D 게임식). 각도는 pose_yaw 시점에서 재고(위치 강체·늘이기 1), 그림은 렌더 시점.
	## pose_yaw 가 ±360 밖(기본 999)이면 자동 = 렌더 yaw 에 가까운 측면(±90).
	var planar: bool = false
	var pose_yaw: float = 999.0


var opts: Options
var profile: DRPartProfile
var rig: DRRigModel
var split: DRMeshSplitter.SplitResult

var viewport: SubViewport
var camera: Camera3D
var model_root: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var part_nodes: Dictionary = {}    # part -> MeshInstance3D

var _host: Node
var _model_aabb: AABB


func setup(host: Node, scene: PackedScene, p_profile: DRPartProfile, p_opts: Options) -> bool:
	_host = host
	profile = p_profile
	opts = p_opts

	model_root = scene.instantiate() as Node3D
	if model_root == null:
		push_error("[DotRigger] 씬 루트가 Node3D 가 아닙니다.")
		return false

	skeleton = _find_node(model_root, "Skeleton3D") as Skeleton3D
	if skeleton == null:
		push_error("[DotRigger] Skeleton3D 를 찾지 못했습니다.")
		return false
	anim_player = _find_node(model_root, "AnimationPlayer") as AnimationPlayer
	if anim_player != null:
		# 시간이 저절로 흐르지 않게 한다. 안 그러면 파트 15장을 한 장씩 찍는 동안
		# 자세가 계속 움직여서 서로 어긋난 스프라이트가 나온다.
		anim_player.speed_scale = 0.0

	var source_mi := _find_skinned_mesh(model_root)
	if source_mi == null:
		push_error("[DotRigger] 스킨드 MeshInstance3D 를 찾지 못했습니다.")
		return false

	split = DRMeshSplitter.split(source_mi, skeleton, profile, opts.bleed_rings)
	if split.meshes.is_empty():
		push_error("[DotRigger] 파트 분리 결과가 비어 있습니다. 프로필 규칙을 확인하세요.")
		return false

	rig = DRRigModel.build(skeleton, split.bone_part, split.part_bones, split.weighted_bones)
	# 파트 -> 레이어(그리기 순서 목록의 한 줄). 발가락은 발 레이어에 묶인다
	for pn in rig.order:
		rig.layer_of[pn] = profile.layer_for_part(pn)
		if not profile.stretch_for_part(pn):
			rig.no_stretch[pn] = true
		var lim := profile.stretch_limit_for_part(pn)
		if lim > 0.0:
			rig.stretch_limit[pn] = lim
		var fade := profile.angle_fade_for_part(pn)
		if fade > 0.0:
			rig.angle_fade[pn] = fade

	# 원본 메쉬를 숨기고 파트 메쉬로 교체
	source_mi.visible = false
	_model_aabb = source_mi.get_aabb()
	var shader := load(SHADER_PATH) as Shader
	for part in split.meshes.keys():
		var mi := MeshInstance3D.new()
		mi.name = "part_%s" % part
		mi.mesh = split.meshes[part]
		mi.skin = source_mi.skin
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		skeleton.add_child(mi)
		mi.skeleton = mi.get_path_to(skeleton)
		_apply_dot_material(mi, shader)
		part_nodes[part] = mi

	_build_viewport()
	host.add_child(viewport)
	return true


func _apply_dot_material(mi: MeshInstance3D, shader: Shader) -> void:
	var am := mi.mesh as ArrayMesh
	for si in am.get_surface_count():
		var sm := ShaderMaterial.new()
		sm.shader = shader
		var src := am.surface_get_material(si)
		var col := Color(0.8, 0.8, 0.8, 1.0)
		if src is BaseMaterial3D:
			col = (src as BaseMaterial3D).albedo_color
			var tex := (src as BaseMaterial3D).albedo_texture
			if tex != null:
				sm.set_shader_parameter("albedo_tex", tex)
				sm.set_shader_parameter("use_tex", true)
		sm.set_shader_parameter("albedo_color", col)
		sm.set_shader_parameter("bands", opts.light_bands)
		sm.set_shader_parameter("ambient", opts.ambient)
		sm.set_shader_parameter("light_dir", opts.light_dir)
		mi.set_surface_override_material(si, sm)


func _build_viewport() -> void:
	var ss: int = maxi(1, opts.supersample)
	viewport = SubViewport.new()
	viewport.name = "DRBakeViewport"
	viewport.size = opts.view_size * ss
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	viewport.use_debanding = false
	viewport.positional_shadow_atlas_size = 0
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var holder := Node3D.new()
	holder.name = "Model"
	viewport.add_child(holder)
	holder.add_child(model_root)

	camera = Camera3D.new()
	camera.name = "BakeCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.01
	camera.far = 100.0
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.sdfgi_enabled = false
	env.ssao_enabled = false
	env.glow_enabled = false
	env.fog_enabled = false
	camera.environment = env
	viewport.add_child(camera)
	pose_camera = Camera3D.new()
	pose_camera.name = "PoseCamera"
	pose_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	pose_camera.near = 0.01
	pose_camera.far = 100.0
	viewport.add_child(pose_camera)
	pose_camera.current = false
	camera.current = true
	apply_camera()


## opts.view_size / opts.supersample 가 바뀌면 SubViewport 도 같이 키워야 한다.
## 이걸 안 하면 렌더는 옛 크기로 나오는데 auto_fit 은 새 크기로 계산해서
## 캐릭터 위치와 배율이 어긋난다.
func apply_view_size() -> void:
	if viewport == null:
		return
	var ss: int = maxi(1, opts.supersample)
	var want := Vector2i(maxi(opts.view_size.x, 2), maxi(opts.view_size.y, 2)) * ss
	if viewport.size != want:
		viewport.size = want


## yaw/pitch(도) -> 카메라 기저. **pitch 양수 = 위에서 내려다봄.**
## Basis.from_euler 의 X 회전은 양수일 때 +Z 쪽 점을 아래로 내리므로 부호를 뒤집는다.
## (09-15 이전에는 뒤집지 않아 "탑다운 60"·"아이소 30" 프리셋이 아래에서 올려다봤다)
static func view_basis(yaw_deg: float, pitch_deg: float) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(-pitch_deg), deg_to_rad(yaw_deg), 0.0))


func _cam_dist() -> float:
	var radius: float = maxf(_model_aabb.size.length() * 0.5, 0.001)
	return radius * 4.0 + 2.0


func apply_camera() -> void:
	if camera == null:
		return
	var size := opts.ortho_size
	if size <= 0.0:
		size = maxf(_model_aabb.size.y, _model_aabb.size.x) * 1.15
	camera.size = maxf(size, 0.01)
	# 캐릭터를 화면에서 옮기려면 카메라를 반대로 옮긴다 (px → 월드 = 화면 세로 높이 / 세로 픽셀 수)
	var wpp := camera.size / float(maxi(opts.view_size.y, 1))
	_place_camera(opts.yaw, opts.pitch, -opts.view_offset * wpp)


## 자동 맞춤으로 잡힌 크기와 화면 안 위치를 유지한 채 각도만 바꾼다(기즈모 드래그용).
## auto_fit 은 카메라를 자기 오른쪽/위 방향으로만 옮기므로, 그 두 성분을 떼어 두었다가
## 새 각도의 오른쪽/위 방향에 다시 얹으면 인물이 화면에서 튀지 않는다.
func orbit_camera(yaw_deg: float, pitch_deg: float) -> void:
	if camera == null:
		return
	var ideal := _model_aabb.get_center() + view_basis(opts.yaw, opts.pitch) * Vector3(0, 0, _cam_dist())
	var off := camera.global_position - ideal
	var b := camera.global_transform.basis
	var shift := Vector2(off.dot(b.x), off.dot(b.y))
	opts.yaw = yaw_deg
	opts.pitch = pitch_deg
	_place_camera(yaw_deg, pitch_deg, shift)


func _place_camera(yaw_deg: float, pitch_deg: float, shift: Vector2) -> void:
	var center := _model_aabb.get_center()
	var dist := _cam_dist()
	var pos := center + view_basis(yaw_deg, pitch_deg) * Vector3(0, 0, dist)
	var xf := Transform3D(Basis(), pos).looking_at(center, Vector3.UP)
	xf.origin += xf.basis.x * shift.x + xf.basis.y * shift.y
	camera.global_transform = xf
	camera.far = dist * 3.0
	_sync_pose_camera()


## 평면화가 켜졌을 때 각도를 잴 시점(yaw). 자동이면 렌더 yaw 에 가까운 쪽 측면.
func effective_pose_yaw() -> float:
	if opts.pose_yaw > 360.0 or opts.pose_yaw < -360.0:
		return 90.0 if opts.yaw >= 0.0 else -90.0
	return opts.pose_yaw


## 평면화가 켜져 있을 때만 포즈 카메라, 아니면 null (rig.project_local / capture_rest 에 그대로 넘긴다)
func pose_cam() -> Camera3D:
	return pose_camera if (opts.planar and pose_camera != null) else null


## 포즈 카메라 = 렌더 카메라와 같은 크기(px 배율이 같아야 루트 이동을 그대로 옮길 수 있다)·같은 거리,
## 각도만 effective_pose_yaw, pitch 0 (평면화는 늘 수평 시점에서 잰다).
func _sync_pose_camera() -> void:
	if pose_camera == null or camera == null:
		return
	pose_camera.size = camera.size
	var center := _model_aabb.get_center()
	var dist := _cam_dist()
	var pos := center + view_basis(effective_pose_yaw(), 0.0) * Vector3(0, 0, dist)
	pose_camera.global_transform = Transform3D(Basis(), pos).looking_at(center, Vector3.UP)
	pose_camera.far = dist * 3.0


## 창·익스포터·검사 도구가 쓰는 한 통로 — 평면화 여부까지 포함해 같은 값을 낸다.
func project_local() -> Dictionary:
	return rig.project_local(skeleton, camera, pose_cam())


func capture_rest() -> void:
	rig.capture_rest(skeleton, camera, pose_cam())


## 현재 카메라 상태를 통째로 직렬화한다. 장비/무기를 나중에 따로 구울 때
## 캐릭터와 픽셀 단위로 정렬되려면 완전히 같은 카메라여야 하므로,
## yaw/pitch 만이 아니라 최종 트랜스폼까지 저장해 둔다.
func serialize_view() -> Dictionary:
	var x := camera.global_transform
	return {
		"yaw": opts.yaw,
		"pitch": opts.pitch,
		"view_offset": [opts.view_offset.x, opts.view_offset.y],   # 캐릭터 화면 위치 이동(px), 참고용(실제 위치는 camera_origin)
		"ortho_size": camera.size,
		"size": [opts.view_size.x, opts.view_size.y],
		"supersample": opts.supersample,
		"rest_anim": opts.rest_anim,
		"rest_time": opts.rest_time,
		"planar": opts.planar,                                   # 동작 평면화(각도를 pose_yaw 시점에서 잼)
		"pose_yaw": effective_pose_yaw() if opts.planar else 0.0,
		"camera_basis": [x.basis.x.x, x.basis.x.y, x.basis.x.z,
						 x.basis.y.x, x.basis.y.y, x.basis.y.z,
						 x.basis.z.x, x.basis.z.y, x.basis.z.z],
		"camera_origin": [x.origin.x, x.origin.y, x.origin.z],
	}


## serialize_view() 결과를 그대로 복원한다.
func apply_view(v: Dictionary) -> void:
	if camera == null:
		return
	if v.has("ortho_size"):
		camera.size = float(v["ortho_size"])
	if v.has("camera_basis") and v.has("camera_origin"):
		var b: Array = v["camera_basis"]
		var o: Array = v["camera_origin"]
		camera.global_transform = Transform3D(
			Basis(Vector3(b[0], b[1], b[2]), Vector3(b[3], b[4], b[5]), Vector3(b[6], b[7], b[8])),
			Vector3(o[0], o[1], o[2]))
	if v.has("rest_anim"):
		opts.rest_anim = String(v["rest_anim"])
	if v.has("rest_time"):
		opts.rest_time = float(v["rest_time"])
	if v.has("planar"):
		opts.planar = bool(v["planar"])
		if opts.planar and v.has("pose_yaw"):
			opts.pose_yaw = float(v["pose_yaw"])
	_sync_pose_camera()


## 레스트 포즈 실루엣이 화면에 꽉 차도록 카메라 크기/중심을 자동 보정한다.
## 모델 AABB 로 잡으면 T포즈 팔 벌린 폭 때문에 여백이 크게 남으므로
## 실제 렌더 결과의 used_rect 를 보고 몇 번 수렴시키는 쪽이 정확하다.
func auto_fit(margin_px: int = 6, iterations: int = 3) -> void:
	var vw := float(opts.view_size.x)
	var vh := float(opts.view_size.y)
	for _i in iterations:
		var img: Image = await render_all_parts_composite()
		var r := img.get_used_rect()
		if r.size.x <= 0 or r.size.y <= 0:
			return
		# 1) 중심 맞추기 (현재 배율 기준)
		var world_per_px := camera.size / vh
		var dx := (float(r.position.x) + float(r.size.x) * 0.5) - vw * 0.5
		var dy := (float(r.position.y) + float(r.size.y) * 0.5) - vh * 0.5
		var b := camera.global_transform.basis
		camera.global_translate(b.x * dx * world_per_px - b.y * dy * world_per_px)
		# 2) 배율 맞추기
		var s := minf((vh - margin_px * 2.0) / float(r.size.y),
					  (vw - margin_px * 2.0) / float(r.size.x))
		if absf(s - 1.0) < 0.01:
			break
		camera.size = maxf(camera.size / s, 0.01)
	_sync_pose_camera()


## glTF 임포터는 "Idle_Loop" 같은 이름에서 _Loop 접미사를 떼고 loop_mode 로 바꾼다.
## 원본 이름으로 불러도 찾아지도록 관대하게 해석한다. 실패하면 "" 반환.
func resolve_anim(name: String) -> String:
	if anim_player == null or name == "":
		return ""
	if anim_player.has_animation(name):
		return name
	var cands := PackedStringArray([name])
	for suf in ["_Loop", "_loop", "-loop", "-Loop"]:
		if name.ends_with(suf):
			cands.append(name.substr(0, name.length() - suf.length()))
	for c in cands:
		if anim_player.has_animation(c):
			return c
	# 대소문자 무시 매칭
	var want := name.to_lower()
	for a in anim_player.get_animation_list():
		var s := String(a)
		if s.to_lower() == want or s.to_lower() + "_loop" == want:
			return s
	return ""


## 애니메이션의 특정 시점으로 포즈를 세팅
func set_pose(anim_name: String, time: float) -> void:
	if anim_player == null or anim_name == "":
		return
	anim_name = resolve_anim(anim_name)
	if anim_name == "":
		return
	# speed_scale 0 으로 세워 둔다(setup 에서 설정).
	# pause() 를 쓰면 믹서가 자세 적용을 멈춰서 바인드 포즈로 돌아가 버리므로,
	# "재생 중이되 시간이 흐르지 않는" 상태로 두는 것이 맞다.
	anim_player.play(anim_name)
	anim_player.seek(time, true)
	anim_player.advance(0.0)
	if skeleton.has_method("force_update_all_bone_transforms"):
		skeleton.call("force_update_all_bone_transforms")


## 프리뷰에서 애니메이션을 실제로 돌려 보고 싶을 때만 켠다.
## 베이크 경로는 항상 set_pose() 를 거치므로 이 값과 무관하게 자세가 고정된다.
## 3D 프리뷰 재생 on/off. speed 는 배속(0 = 멈춘 채 스크럽만).
func set_playback(on: bool, speed: float = 1.0) -> void:
	if anim_player != null:
		anim_player.speed_scale = speed if on else 0.0


func set_rest_pose() -> void:
	if opts.rest_anim != "":
		set_pose(opts.rest_anim, opts.rest_time)
	elif anim_player != null:
		anim_player.stop()


## 파트 하나만 보이게 하고 한 장 렌더. 나머지는 숨기므로
## 가려진 부분까지 온전한 스프라이트가 나온다(= 컷아웃에 필요한 형태).
func render_part(part: String) -> Image:
	return await render_parts(PackedStringArray([part]))


## 지정한 파트들만 보이게 하고 한 장 렌더.
## 3D 렌더라 그 파트들끼리의 가림은 정확하게 나온다 —
## 두세 개만 골라서 어느 쪽이 앞이어야 하는지 판단할 때 쓴다.
func render_parts(names: PackedStringArray) -> Image:
	var want := {}
	for n in names:
		want[n] = true
	for k in part_nodes.keys():
		(part_nodes[k] as MeshInstance3D).visible = want.has(k)
	return await _grab()


func render_all_parts_composite() -> Image:
	for k in part_nodes.keys():
		(part_nodes[k] as MeshInstance3D).visible = true
	return await _grab()


func _grab() -> Image:
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := viewport.get_texture().get_image()
	var ss: int = maxi(1, opts.supersample)
	if ss > 1:
		img.resize(opts.view_size.x, opts.view_size.y, Image.INTERPOLATE_BILINEAR)
	_post(img)
	return img


func _post(img: Image) -> void:
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var th := opts.alpha_threshold
	var levels := opts.color_levels
	if th <= 0.0 and levels <= 0:
		return
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if th > 0.0:
				c.a = 0.0 if c.a < th else 1.0
			if c.a > 0.0 and levels > 1:
				var n := float(levels - 1)
				c.r = roundf(c.r * n) / n
				c.g = roundf(c.g * n) / n
				c.b = roundf(c.b * n) / n
			img.set_pixel(x, y, c)


static func _find_node(root: Node, cls: String) -> Node:
	if root.is_class(cls):
		return root
	for c in root.get_children():
		var r := _find_node(c, cls)
		if r != null:
			return r
	return null


static func _find_skinned_mesh(root: Node) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_v := -1
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh is ArrayMesh and mi.skin != null:
				var v := 0
				for si in (mi.mesh as ArrayMesh).get_surface_count():
					v += (mi.mesh as ArrayMesh).surface_get_array_len(si)
				if v > best_v:
					best_v = v
					best = mi
		for c in n.get_children():
			stack.append(c)
	return best


func cleanup() -> void:
	if viewport != null and is_instance_valid(viewport):
		viewport.queue_free()
	viewport = null
