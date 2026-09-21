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
	## 추가 동작 폴더(res://). 모델 파일 밖의 동작(예: Mixamo FBX)을 같은 캐릭터에 얹는다. "" = 안 씀.
	## 폴더 안의 .fbx/.glb/.gltf/.tscn/.scn/.res/.tres 를 읽고, 동작이 하나뿐인 파일은 **파일 이름 = 동작 이름**.
	## 뼈 이름이 모델과 같아야 한다 — 뼈대가 다른 출처(Mixamo 등)는 양쪽 임포트 설정에 BoneMap(리타깃)을 지정할 것.
	var extra_anim_dir: String = ""
	## 상하체 합성 동작 정의. 각 { name, lower, upper, length_mode(0~3), loop, upper_keep(0~1 상체 방향 유지), upper_pitch(도, 몸통 각도 보정) } — 하체는 lower 애니, 상체는 upper 애니에서
	## 뼈 트랙을 가져와 새 동작을 만든다(메모리에서만). 만든 동작은 다른 애니와 똑같이 고르고·레스트로 쓰고·굽는다.
	var composites: Array = []
	## 상체로 칠 파트(이 파트들의 뼈는 upper 애니에서). 비면 DEFAULT_UPPER_PARTS.
	var composite_upper_parts: PackedStringArray = PackedStringArray()


const EXTRA_ANIM_EXT := ["fbx", "glb", "gltf", "tscn", "scn", "res", "tres"]
## 상하체 합성의 기본 상체 — 몸통·머리·두 팔. 힙과 다리(와 파트에 안 속한 root 등)는 하체.
const DEFAULT_UPPER_PARTS := ["Torso", "Head", "L_UpperArm", "L_Forearm", "L_Hand", "R_UpperArm", "R_Forearm", "R_Hand"]
## 합성 동작의 길이 맞춤
const LEN_LOWER_SPEED := 0   # 하체 시간에 상체를 맞춤 (하체 반복): 길이 = 하체 주기 × n(상체 길이에 가장 가까운 정수배), 상체를 거기에 맞춰 늘이거나 줄임
const LEN_ONCE := 1          # 하체 시간에 상체를 맞춤 (하체 1번): 길이 = 하체 길이, 상체를 거기에 맞춤
const LEN_UPPER_SPEED := 2   # 상체 시간에 하체를 맞춤 (하체 반복): 길이 = 상체 길이, 하체 주기를 정수 번 넣음
const LEN_ONCE_UPPER := 3    # 상체 시간에 하체를 맞춤 (하체 1번): 길이 = 상체 길이, 하체 한 주기를 거기에 맞춤
## 팝업 미리보기용 숨은 동작 이름. `__` 로 시작하는 이름은 창의 동작 목록에 나오지 않는다
const PREVIEW_ANIM := "__composite_preview__"
const COMPOSITE_FPS := 30.0

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
## 추가 동작 폴더에서 얹은 동작 이름 / 그 과정의 경고(창 상태줄·CLI 가 보여 준다)
var extra_anims: PackedStringArray = PackedStringArray()
var extra_anim_warnings: PackedStringArray = PackedStringArray()
## 상하체 합성으로 만든 동작 이름 / 경고 / 실제로 쓴 정의(길이·주기 수 포함 — rig.json 에 남긴다)
var composite_anims: PackedStringArray = PackedStringArray()
var composite_warnings: PackedStringArray = PackedStringArray()
var composite_info: Array = []
var _owns_library := false

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
	extra_anims = PackedStringArray()
	extra_anim_warnings = PackedStringArray()
	if opts.extra_anim_dir.strip_edges() != "":
		_load_extra_anims(opts.extra_anim_dir.strip_edges())
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
	# 상하체 합성 동작 — 파트(뼈 → 파트)가 정해진 뒤에 만든다
	composite_anims = PackedStringArray()
	if opts.composites.size() > 0:
		build_composites(opts.composites, opts.composite_upper_parts)
		if anim_player != null:
			anim_player.speed_scale = 0.0
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


## 추가 동작 폴더의 동작을 모델의 AnimationPlayer 기본 라이브러리에 얹는다(메모리에서만 — 파일은 안 바뀐다).
## - 가져온(캐시된) 라이브러리를 직접 고치면 에디터 세션 내내 남으므로 얕은 사본에 담는다.
## - 트랙의 노드 경로는 출처마다 다르므로(Skeleton3D / Armature/Skeleton3D / %GeneralSkeleton) 이 모델의 뼈대 경로로 고쳐 쓴다.
## - 뼈 이름은 고쳐 주지 않는다. 뼈대가 다른 출처는 양쪽 임포트 설정의 BoneMap(리타깃)으로 이름을 맞춰 와야 한다.
func _load_extra_anims(dir_path: String) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		extra_anim_warnings.append("추가 동작 폴더를 열 수 없습니다: %s" % dir_path)
		return
	var lib := _own_library()

	var ap_root := anim_player.get_node_or_null(anim_player.root_node)
	var skel_path := _rel_path(ap_root, skeleton)

	var files := Array(d.get_files())
	files.sort()
	for f in files:
		var fname := String(f)
		if not EXTRA_ANIM_EXT.has(fname.get_extension().to_lower()):
			continue
		var path := dir_path.path_join(fname)
		if not ResourceLoader.exists(path):
			extra_anim_warnings.append("%s — 아직 가져오기(임포트)가 안 됨" % fname)
			continue
		var res := ResourceLoader.load(path)
		var found := {}   # 원래 이름 -> Animation
		if res is PackedScene:
			var inst := (res as PackedScene).instantiate()
			var ap := _find_node(inst, "AnimationPlayer") as AnimationPlayer
			if ap != null:
				for an in ap.get_animation_list():
					if String(an) != "RESET":
						found[String(an)] = ap.get_animation(an).duplicate(true)
			inst.free()
		elif res is AnimationLibrary:
			for an in (res as AnimationLibrary).get_animation_list():
				if String(an) != "RESET":
					found[String(an)] = (res as AnimationLibrary).get_animation(an).duplicate(true)
		elif res is Animation:
			found[fname.get_basename()] = (res as Animation).duplicate(true)
		if found.is_empty():
			extra_anim_warnings.append("%s — 동작이 없음" % fname)
			continue
		for src_name in found.keys():
			var anim: Animation = found[src_name]
			# 동작이 하나뿐인 파일(Mixamo 는 전부 "mixamo.com")은 파일 이름이 곧 동작 이름
			var new_name := _clean_anim_name(fname.get_basename() if found.size() == 1 else String(src_name))
			var bone_tracks := 0
			var missing := 0
			for ti in anim.get_track_count():
				var sub := anim.track_get_path(ti).get_concatenated_subnames()
				if sub == "":
					continue
				bone_tracks += 1
				if skeleton.find_bone(sub) < 0:
					missing += 1
					continue
				anim.track_set_path(ti, NodePath("%s:%s" % [skel_path, sub]))
			if bone_tracks == 0 or missing == bone_tracks:
				extra_anim_warnings.append("%s — 뼈 이름이 모델과 하나도 안 맞아 뺌. 모델과 이 파일 양쪽 임포트 설정에 BoneMap(리타깃)을 지정했는지 확인" % fname)
				continue
			if missing > 0:
				extra_anim_warnings.append("%s — 모델에 없는 뼈 트랙 %d/%d개(그 트랙은 무시됨)" % [new_name, missing, bone_tracks])
			if lib.has_animation(new_name):
				extra_anim_warnings.append("%s — 모델에 같은 이름의 동작이 있어 추가 동작으로 바꿈" % new_name)
				lib.remove_animation(new_name)
			lib.add_animation(new_name, anim)
			extra_anims.append(new_name)
	for w in extra_anim_warnings:
		push_warning("[DotRigger] 추가 동작: " + w)


## 이 베이커만의 기본 라이브러리를 돌려준다(처음 부를 때 만든다).
## 가져온(캐시된) 라이브러리를 직접 고치면 에디터 세션 내내 남으므로 얕은 사본으로 바꿔 끼운다.
## 동작이 없는 모델(스킨만 받은 캐릭터)이면 AnimationPlayer 도 만들어 준다.
func _own_library() -> AnimationLibrary:
	if anim_player == null:
		anim_player = AnimationPlayer.new()
		anim_player.name = "AnimationPlayer"
		model_root.add_child(anim_player)
	if _owns_library and anim_player.has_animation_library(""):
		return anim_player.get_animation_library("")
	var lib: AnimationLibrary
	if anim_player.has_animation_library(""):
		lib = anim_player.get_animation_library("").duplicate(false) as AnimationLibrary
		anim_player.remove_animation_library("")
	else:
		lib = AnimationLibrary.new()
	anim_player.add_animation_library("", lib)
	_owns_library = true
	return lib


## 상하체 합성 동작을 (다시) 만든다. 모델을 다시 불러오지 않고도 정의만 바꿔 부를 수 있다.
## 합성은 **3D 뼈 트랙 단계**에서 한다: 상체 파트의 뼈는 upper 애니에서, 나머지(힙·다리·root)는 lower 애니에서.
## 몸통은 힙의 자식 뼈라 하체의 들썩임·기울기를 그대로 따라가고, 그 위에 상체 애니의 허리·팔 자세가 얹힌다.
## 2D 로 합치지 않는 이유: 단축률·늘이기·깊이(z)가 실제 3D 자세에서 계산돼야 팔이 몸통에 제대로 붙는다.
func build_composites(defs: Array, upper_parts: PackedStringArray = PackedStringArray()) -> void:
	var lib := _own_library()
	for old in composite_anims:
		if lib.has_animation(old):
			lib.remove_animation(old)
	composite_anims = PackedStringArray()
	composite_warnings = PackedStringArray()
	composite_info = []
	if defs.is_empty() or split == null:
		return
	for d in defs:
		var def: Dictionary = d
		var cname := composite_name(def)
		if composite_anims.has(cname):
			composite_warnings.append("%s — 같은 이름의 합성이 이미 있어 건너뜀" % cname)
			continue
		if lib.has_animation(cname):
			composite_warnings.append("%s — 모델에 같은 이름의 동작이 있어 건너뜀(합성 이름을 바꾸세요)" % cname)
			continue
		var made := _make_composite(def, upper_parts)
		if String(made["warning"]) != "":
			composite_warnings.append("%s — %s" % [cname, made["warning"]])
			continue
		lib.add_animation(cname, made["anim"])
		composite_anims.append(cname)
		var info: Dictionary = made["info"]
		info["name"] = cname
		composite_info.append(info)
	for w in composite_warnings:
		push_warning("[DotRigger] 상하체 합성: " + w)


## 합성 정의의 동작 이름(비면 `하체+상체` — 팝업의 auto_name 과 같은 규칙)
static func composite_name(def: Dictionary) -> String:
	var cname := _clean_anim_name(String(def.get("name", "")))
	if cname == "":
		cname = _clean_anim_name("%s+%s" % [def.get("lower", ""), def.get("upper", "")])
	return cname


## 팝업의 미리보기용: 정의 하나를 합성해 PREVIEW_ANIM 이라는 숨은 이름으로 넣는다(목록·세트·베이크에는 안 나온다).
## 돌려주는 값 { ok, length, lower_cycles, warning }. 팝업을 닫을 때 clear_composite_preview() 로 치운다.
func make_composite_preview(def: Dictionary, upper_parts: PackedStringArray = PackedStringArray()) -> Dictionary:
	var lib := _own_library()
	if lib.has_animation(PREVIEW_ANIM):
		lib.remove_animation(PREVIEW_ANIM)
	if split == null:
		return {"ok": false, "length": 0.0, "lower_cycles": 1, "warning": "모델이 없음"}
	var made := _make_composite(def, upper_parts)
	if String(made["warning"]) != "":
		return {"ok": false, "length": 0.0, "lower_cycles": 1, "warning": made["warning"]}
	lib.add_animation(PREVIEW_ANIM, made["anim"])
	var info: Dictionary = made["info"]
	return {"ok": true, "length": float(info["length"]), "lower_cycles": int(info["lower_cycles"]), "warning": ""}


func clear_composite_preview() -> void:
	if anim_player == null or not _owns_library:
		return
	var lib := anim_player.get_animation_library("")
	if lib != null and lib.has_animation(PREVIEW_ANIM):
		if anim_player.current_animation == PREVIEW_ANIM:
			anim_player.stop()
		lib.remove_animation(PREVIEW_ANIM)


## 모든 파트가 보이게(팝업 프리뷰는 전체 몸을 보여 준다 — 창의 파트 격리 상태와 무관하게)
func show_all_parts() -> void:
	for k in part_nodes.keys():
		(part_nodes[k] as MeshInstance3D).visible = true


## 정의 하나를 합성한다(라이브러리에는 넣지 않는다). { anim, info, warning } — warning 이 "" 가 아니면 실패.
func _make_composite(def: Dictionary, upper_parts: PackedStringArray) -> Dictionary:
	var lib := _own_library()
	var lower_name := resolve_anim(String(def.get("lower", "")))
	var upper_name := resolve_anim(String(def.get("upper", "")))
	if lower_name == "" or upper_name == "" or lower_name == PREVIEW_ANIM or upper_name == PREVIEW_ANIM:
		return {"anim": null, "info": {}, "warning": "동작을 찾을 수 없음 (하체 '%s' · 상체 '%s')" % [def.get("lower", ""), def.get("upper", "")]}
	var uppers := upper_parts if upper_parts.size() > 0 else PackedStringArray(DEFAULT_UPPER_PARTS)
	var upper_bone := {}   # 뼈 이름 -> true
	for bi in split.bone_part.keys():
		if uppers.has(String(split.bone_part[bi])):
			upper_bone[skeleton.get_bone_name(int(bi))] = true
	var lo := lib.get_animation(lower_name)
	var up := lib.get_animation(upper_name)
	var lo_len := maxf(lo.length, 0.0001)
	var up_len := maxf(up.length, 0.0001)
	var mode := int(def.get("length_mode", LEN_LOWER_SPEED))
	var lo_cycles := 1
	var total := lo_len                       # LEN_ONCE: 하체 길이에 한 번씩
	if mode == LEN_LOWER_SPEED:
		lo_cycles = maxi(1, int(round(up_len / lo_len)))
		total = lo_len * float(lo_cycles)
	elif mode == LEN_UPPER_SPEED:
		lo_cycles = maxi(1, int(round(up_len / lo_len)))
		total = up_len
	elif mode == LEN_ONCE_UPPER:
		total = up_len                        # 상체 길이에 한 번씩(하체를 늘이거나 줄임)
	var out := Animation.new()
	out.length = total
	out.loop_mode = Animation.LOOP_LINEAR if bool(def.get("loop", true)) else Animation.LOOP_NONE
	out.step = 1.0 / COMPOSITE_FPS
	var n_lo := _copy_tracks(out, lo, total, lo_cycles, upper_bone, false)
	var n_up := _copy_tracks(out, up, total, 1, upper_bone, true)
	if n_lo == 0 or n_up == 0:
		return {"anim": null, "info": {}, "warning": "가져올 트랙이 없음 (하체 %d · 상체 %d). 상체 파트 선택을 확인" % [n_lo, n_up]}
	var keep := clampf(float(def.get("upper_keep", 0.0)), 0.0, 1.0)
	var pitch := clampf(float(def.get("upper_pitch", 0.0)), -90.0, 90.0)
	_fix_upper_roots(out, lo, up, total, lo_cycles, upper_bone, keep, pitch)
	return {"anim": out, "warning": "", "info": {"name": "", "lower": lower_name, "upper": upper_name, "length_mode": mode,
		"loop": out.loop_mode != Animation.LOOP_NONE, "length": total, "lower_cycles": lo_cycles, "upper_parts": Array(uppers),
		"upper_keep": keep, "upper_pitch": pitch}}


## 합성의 시각 t 가 출처 애니(src)의 몇 초에 해당하는가. src 는 total 동안 cycles 번 돈다. last = 마지막 샘플(반복 지점)
static func _src_time(t: float, total: float, cycles: int, src: Animation, last: bool) -> float:
	var src_len := maxf(src.length, 0.0001)
	if last:
		return src_len if src.loop_mode == Animation.LOOP_NONE and cycles == 1 else 0.0
	var phase := (t / total) * float(cycles)
	return (phase - floorf(phase)) * src_len


## 뼈 이름 -> 회전 트랙 번호
static func _rot_tracks(anim: Animation) -> Dictionary:
	var m := {}
	for ti in anim.get_track_count():
		if anim.track_get_type(ti) == Animation.TYPE_ROTATION_3D and anim.track_get_key_count(ti) > 0:
			m[anim.track_get_path(ti).get_concatenated_subnames()] = ti
	return m


## 그 애니의 time 시점에서 뼈 bi 의 부모 기준 회전(트랙이 없으면 뼈대의 레스트)
func _local_rot(anim: Animation, tracks: Dictionary, bi: int, time: float) -> Quaternion:
	var bn := skeleton.get_bone_name(bi)
	if tracks.has(bn):
		return anim.rotation_track_interpolate(int(tracks[bn]), time)
	return skeleton.get_bone_rest(bi).basis.get_rotation_quaternion()


## 그 애니의 time 시점에서 뼈 bi 의 **뼈대 기준** 회전 = 뿌리부터 bi 까지 부모 기준 회전을 차례로 곱한 것
func _chain_rot(anim: Animation, tracks: Dictionary, bi: int, time: float) -> Quaternion:
	var chain: Array[int] = []
	var w := bi
	while w >= 0:
		chain.push_front(w)
		w = skeleton.get_bone_parent(w)
	var q := Quaternion.IDENTITY
	for b in chain:
		q = q * _local_rot(anim, tracks, b, time)
	return q.normalized()


## 뼈대 공간에서 본 캐릭터의 좌우 축(모델은 +Z 를 본다 → 세상의 X 가 좌우). setup 중에는 트리에 없으므로 부모를 직접 거슬러 곱한다
func _side_axis_in_skeleton() -> Vector3:
	var b := Basis.IDENTITY
	var n: Node = skeleton
	while n != null:
		if n is Node3D:
			b = (n as Node3D).transform.basis.orthonormalized() * b
		if n == model_root:
			break
		n = n.get_parent()
	return (b.inverse() * Vector3.RIGHT).normalized()


## 상체의 "뿌리" 뼈(= 부모가 하체인 상체 뼈. 기본 구성이면 허리 첫 마디 하나)의 회전을 고쳐 쓴다.
##
## 왜 필요한가(02 M5): 뼈의 회전은 부모 기준이다. 하체 애니가 골반을 앞으로 숙이면(UAL Crouch_Idle 은 Idle 대비 27°)
## 상체 애니의 허리 각도를 그대로 얹어도 몸통 전체가 그만큼 같이 숙는다 — Crouch_Idle + Idle 에서 몸통 숙임이 8° → 33°.
##   keep  (상체 방향 유지 0~1): 1 이면 몸통이 **세상 기준으로** 상체 애니에서와 똑같은 쪽을 본다(골반이 숙든 말든). 0 이면 예전처럼 골반을 따라간다.
##                               언리얼의 Mesh Space Rotation Blend 와 같은 생각. 팔만 상체로 뒀을 때는 팔(총구) 방향이 유지된다.
##   pitch (몸통 각도 보정, 도): 그 위에 좌우 축으로 더 돌린다. + = 뒤로 젖힘(세움), − = 앞으로 숙임.
func _fix_upper_roots(out: Animation, lo: Animation, up: Animation, total: float, lo_cycles: int,
		upper_bone: Dictionary, keep: float, pitch_deg: float) -> void:
	if keep <= 0.0 and absf(pitch_deg) < 0.01:
		return
	var lo_tr := _rot_tracks(lo)
	var up_tr := _rot_tracks(up)
	var out_tr := _rot_tracks(out)
	var ap_root := anim_player.get_node_or_null(anim_player.root_node)
	var skel_path := _rel_path(ap_root, skeleton)
	var steps := maxi(1, int(ceil(total * COMPOSITE_FPS)))
	var pitch_q := Quaternion(_side_axis_in_skeleton(), -deg_to_rad(pitch_deg))
	for bi in skeleton.get_bone_count():
		var bn := skeleton.get_bone_name(bi)
		if not upper_bone.has(bn):
			continue
		var par := skeleton.get_bone_parent(bi)
		if par < 0 or upper_bone.has(skeleton.get_bone_name(par)):
			continue                       # 부모도 상체면 뿌리가 아니다(부모를 따라 같이 돈다)
		var ot := -1
		if out_tr.has(bn):
			ot = int(out_tr[bn])
			while out.track_get_key_count(ot) > 0:
				out.track_remove_key(ot, 0)
		else:                              # 상체 애니에 이 뼈의 회전 트랙이 없었다(레스트) — 새로 만든다
			ot = out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(ot, NodePath("%s:%s" % [skel_path, bn]))
			out.track_set_interpolation_type(ot, Animation.INTERPOLATION_LINEAR)
		for k in steps + 1:
			var t := minf(total, float(k) / COMPOSITE_FPS)
			var st_lo := _src_time(t, total, lo_cycles, lo, k == steps)
			var st_up := _src_time(t, total, 1, up, k == steps)
			var g_par := _chain_rot(lo, lo_tr, par, st_lo)          # 합성에서 부모(하체 쪽)의 뼈대 기준 회전
			var l := _local_rot(up, up_tr, bi, st_up)               # 예전 방식: 상체 애니의 부모 기준 회전 그대로
			if keep > 0.0:
				var g_up := _chain_rot(up, up_tr, bi, st_up)        # 상체 애니에서 이 뼈가 뼈대 기준으로 향하던 쪽
				l = l.slerp((g_par.inverse() * g_up).normalized(), keep)
			if absf(pitch_deg) >= 0.01:
				l = g_par.inverse() * pitch_q * g_par * l
			out.rotation_track_insert_key(ot, t, l.normalized())


## src 의 뼈 트랙 중 상체(want_upper) 또는 하체에 속한 것을 out 에 다시 찍어 넣는다. 돌려주는 값 = 넣은 트랙 수.
## 길이가 다른 두 애니를 한 시간축에 놓아야 하므로 키를 그대로 복사하지 않고 COMPOSITE_FPS 로 다시 샘플한다.
## src 는 total 동안 cycles 번 돈다(늘이거나 줄여서 정확히 맞춤 → 반복 지점이 이어진다).
func _copy_tracks(out: Animation, src: Animation, total: float, cycles: int, upper_bone: Dictionary, want_upper: bool) -> int:
	var count := 0
	var steps := maxi(1, int(ceil(total * COMPOSITE_FPS)))
	for ti in src.get_track_count():
		var tt := src.track_get_type(ti)
		if tt != Animation.TYPE_POSITION_3D and tt != Animation.TYPE_ROTATION_3D and tt != Animation.TYPE_SCALE_3D:
			continue
		var path := src.track_get_path(ti)
		var bone := path.get_concatenated_subnames()
		if bone == "" or upper_bone.has(bone) != want_upper:
			continue
		if src.track_get_key_count(ti) == 0:
			continue
		var ot := out.add_track(tt)
		out.track_set_path(ot, path)
		out.track_set_interpolation_type(ot, Animation.INTERPOLATION_LINEAR)
		for k in steps + 1:
			var t := minf(total, float(k) / COMPOSITE_FPS)
			var st := _src_time(t, total, cycles, src, k == steps)   # 끝 샘플 = 반복 지점
			if tt == Animation.TYPE_POSITION_3D:
				out.position_track_insert_key(ot, t, src.position_track_interpolate(ti, st))
			elif tt == Animation.TYPE_ROTATION_3D:
				out.rotation_track_insert_key(ot, t, src.rotation_track_interpolate(ti, st))
			else:
				out.scale_track_insert_key(ot, t, src.scale_track_interpolate(ti, st))
		count += 1
	return count


## AnimationLibrary 가 받지 않는 글자( / : , [ )와 공백을 _ 로
static func _clean_anim_name(s: String) -> String:
	var out := s.strip_edges().replace(" ", "_")
	for ch in ["/", ":", ",", "["]:
		out = out.replace(ch, "_")
	return out


## from_root 에서 node 까지의 상대 경로(트리에 안 붙어 있어도 되게 부모를 직접 거슬러 오른다)
static func _rel_path(from_root: Node, node: Node) -> String:
	if from_root == null or node == null or from_root == node:
		return "."
	var names := PackedStringArray()
	var n := node
	while n != null and n != from_root:
		names.insert(0, String(n.name))
		n = n.get_parent()
	if n == null:
		return "%" + String(node.name)   # 조상이 아님 — 고유 이름에 기댄다
	return "/".join(names)


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
	# 먼저 모든 뼈를 레스트로 되돌린다(02 C13). 임포터는 레스트와 값이 같은 트랙을 지우므로(remove_immutable_tracks)
	# 애니마다 트랙이 있는 뼈가 다르고, AnimationPlayer 는 **트랙이 없는 뼈를 건드리지 않는다** → 앞서 본 애니의 자세가 그 뼈에 남는다.
	# 예: Idle 에는 허리 첫 마디(spine_01)의 회전 트랙이 없다 — 상하체 합성의 각도 보정은 바로 그 뼈에 쓰므로,
	#     합성을 본 뒤의 Idle 이 57° 틀어진 채로 나왔다. 되돌려 놓으면 "트랙 없음 = 레스트" 라는 원래 뜻대로 된다.
	skeleton.reset_bone_poses()
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


## 레스트 자세로 세운다. rest_anim 이 비었거나 모델에 없는 이름이면 **진짜 바인드 포즈**(뼈대의 레스트)로 되돌린다.
## (02 C12: 예전엔 stop() 만 해서 마지막에 보던 프레임이 그대로 남았고, 그게 레스트로 찍혔다.)
func set_rest_pose() -> void:
	if opts.rest_anim != "" and resolve_anim(opts.rest_anim) != "":
		set_pose(opts.rest_anim, opts.rest_time)
		return
	if anim_player != null:
		anim_player.stop()
	if skeleton != null:
		skeleton.reset_bone_poses()
		if skeleton.has_method("force_update_all_bone_transforms"):
			skeleton.call("force_update_all_bone_transforms")


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
