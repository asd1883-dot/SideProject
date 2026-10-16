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
	## 아래팔 비틀림 뼈(이름에 twist 가 든 아래팔의 자식 뼈 — bind_to_skeleton.py --forearm_twist)가 있으면, 동작마다 손이 아래팔 축으로
	## 비튼 각도 × 그 뼈의 자리 비율(팔꿈치 0 → 손목 1)만큼 돌리는 트랙을 넣는다. Mixamo 동작은 손목에서 100 ~ 130° 를 비틀어
	## 손목 살이 꼬였다(10-14). 비틀림 뼈가 없는 모델은 아무 일도 안 한다.
	var forearm_twist: bool = true
	## 손 자리 맞춤(10-15) — 추가 동작(Mixamo 등)의 뼈대가 이 모델과 팔 · 몸통 비율이 다르면(Mixamo 아래팔 = 윗팔의 0.78, 이 몸 0.99 ·
	## 몸통 10 % 큼) 같은 관절 각도로도 손이 다른 자리에 간다 — Rifle Idle 에서 두 손이 원본보다 10 cm 앞이라 옆에서 보면 앞손이
	## 뒷팔을 붙잡은 것처럼 겹쳤다. 출처 뼈대에서 손목이 가슴(UpperChest) 기준 어디 있었는지(몸통 비율만큼 키워)를 이 모델에 옮기고
	## 윗팔 · 아래팔을 두 마디 IK 로 다시 돌린다(손의 방향은 원래 동작 그대로). 출처 팔이 거의 펴진 자세는 원래 관절 각도 쪽으로 섞는다.
	var hand_ik: bool = true
	## 손 레스트 방향 맞춤(10-15) — 리타깃은 뼈의 틀(축)을 맞춰 회전을 옮기지만, T-포즈에서 손이 팔에 대해 기운 정도(레스트 모양)는
	## 뼈대마다 다르다(Mixamo 손: 손바닥 쪽 4.5° · 엄지 쪽 7.9°, 이 몸: 손바닥 쪽 8.1° → 10.6° 차이). 같은 회전을 얹으면 손이 늘 그만큼
	## 다른 쪽을 봐서 Rifle_Idle 오른손 손목이 원본 30.8° 대신 38.9° 로 꺾였다. 추가 동작마다 출처 손(손목 → 중지 뿌리 · 엄지 쪽)과
	## 이 모델 손의 레스트 차이를 고정 회전으로 손 회전 뒤에 곱해 손이 원본과 같은 쪽을 보게 한다(손가락은 손을 따라감).
	var hand_rest_fix: bool = true
	## 제자리로 만들 동작 이름 — 뿌리 뼈(힙)가 처음 → 끝 사이에 수평으로 간 거리를 지운다(Mixamo `In Place` 와 같은 효과).
	## 걸음마다 들썩임 · 좌우 흔들림은 남는다. 원본 파일은 안 바뀐다(메모리에서만).
	var in_place: PackedStringArray = PackedStringArray()


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
## 관절 받침 짝 {아래 조각: [위 조각 …]}(10-08, DRMeshSplitter.tuck_pairs) — render_part(아래)가 위 조각의 관절 둘레(관절점 중심 원)를
## 아래 조각 그림의 빈 곳에 채운다. 관절이 돌아 위 조각이 비켜난 틈을 아래 조각이 메운다(평소엔 위 조각에 가려 안 보임).
## 굽는 쪽(익스포터 · 복장 굽기 · 메인 창 2D 순서)이 그 세트의 그리기 순서로 정해 두고 다 그리면 비운다. 비면 꺼짐(평소 3D 보기 · 부위만 보기)
var tuck_pairs: Dictionary = {}:
	set(v):
		tuck_pairs = v
		_tuck_body = null      # 세트(카메라 · 레스트)가 바뀌었을 수 있다 — 몸 실루엣을 다시 잰다
## 관절 받침 원 반지름 = 레스트 몸 전체 실루엣 안에 드는 가장 큰 원(관절점 중심) × tuck_fit + tuck_pad 픽셀, 관절 둘레(3D)를 넘지 않게.
## 실루엣 안의 원이라 위 조각이 어느 쪽으로 돌아도 원 밖으로 안 튀어나온다(둥근 관절) — 크게 잡으면 레스트 모양 토막이 남아 보였다(10-08 어깨).
## 두 조각만의 실루엣으로 재면 다른 조각이 덮던 작은 틈에 걸려 원이 2~3px 로 쪼그라들었다(10-08 뒷다리 고관절 → 사타구니 틈 그대로).
static var tuck_fit := 1.0
static var tuck_pad := 1.0
static var tuck_max := 1.0      # 관절 둘레(3D) 상한에 곱하는 값
var _tuck_body: Image = null    # 레스트 몸 전체(모든 파트) — 관절 받침 원의 크기를 재는 실루엣
## 파트로 자르기 전의 원본 스킨드 메시(숨겨 둠) — 복장 창의 부위 칠하기가 정점을 읽는다
var source_mesh_instance: MeshInstance3D
## 이 모델의 부위 칠하기(<모델>.parts.json, 없으면 빈 것)
var part_overrides: DRPartOverrides
## 추가 동작 폴더에서 얹은 동작 이름 / 그 과정의 경고(창 상태줄·CLI 가 보여 준다)
var extra_anims: PackedStringArray = PackedStringArray()
var extra_anim_warnings: PackedStringArray = PackedStringArray()
## 상하체 합성으로 만든 동작 이름 / 경고 / 실제로 쓴 정의(길이·주기 수 포함 — rig.json 에 남긴다)
var composite_anims: PackedStringArray = PackedStringArray()
var composite_warnings: PackedStringArray = PackedStringArray()
var composite_info: Array = []
## 제자리로 바꿔 끼운 동작의 원래 것 {이름: Animation} — 끄면 되돌린다
var _in_place_orig: Dictionary = {}
## 아래팔 비틀림 트랙을 넣은 동작 수(0 = 비틀림 뼈가 없거나 비튼 동작이 없음)
var twist_anims: int = 0
## 손 자리 맞춤(IK)을 건 추가 동작 수 / 마지막으로 쓴 몸통 비율(이 모델 ÷ 출처)
var ik_anims: int = 0
var ik_scale: float = 1.0
## 손 레스트 방향 맞춤을 건 추가 동작 수 / 마지막으로 쓴 보정 각(도, [왼손, 오른손])
var rest_fix_anims: int = 0
var rest_fix_deg: Vector2 = Vector2.ZERO
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
	ik_anims = 0
	rest_fix_anims = 0
	if opts.extra_anim_dir.strip_edges() != "":
		_load_extra_anims(opts.extra_anim_dir.strip_edges())
	twist_anims = 0
	if anim_player != null and opts.forearm_twist:
		twist_anims = _add_forearm_twist()   # 제자리 · 합성보다 먼저 — 그 둘은 이 트랙을 그대로 옮긴다
	_in_place_orig = {}
	if anim_player != null and opts.in_place.size() > 0:
		apply_in_place(opts.in_place)     # 합성보다 먼저 — 합성의 하체가 제자리가 된 동작을 쓰게
	if anim_player != null:
		# 시간이 저절로 흐르지 않게 한다. 안 그러면 파트 15장을 한 장씩 찍는 동안
		# 자세가 계속 움직여서 서로 어긋난 스프라이트가 나온다.
		anim_player.speed_scale = 0.0

	var source_mi := _find_skinned_mesh(model_root)
	if source_mi == null:
		push_error("[DotRigger] 스킨드 MeshInstance3D 를 찾지 못했습니다.")
		return false

	# 부위 칠하기(모델 옆 <이름>.parts.json) — 있으면 칠한 정점은 칠한 파트로 자른다
	source_mesh_instance = source_mi
	part_overrides = DRPartOverrides.load_for(scene.resource_path)
	split = DRMeshSplitter.split(source_mi, skeleton, profile, opts.bleed_rings, part_overrides)
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
		var src_inst: Node = null          # 출처 씬(뼈대가 있으면 손 자리 맞춤이 그 뼈대로 원래 손 자리를 잰다) — 이 파일을 다 처리한 뒤 푼다
		var src_skel: Skeleton3D = null
		if res is PackedScene:
			var inst := (res as PackedScene).instantiate()
			var ap := _find_node(inst, "AnimationPlayer") as AnimationPlayer
			if ap != null:
				for an in ap.get_animation_list():
					if String(an) != "RESET":
						found[String(an)] = ap.get_animation(an).duplicate(true)
			src_skel = _find_node(inst, "Skeleton3D") as Skeleton3D
			if src_skel != null and (opts.hand_ik or opts.hand_rest_fix):
				src_inst = inst
			else:
				src_skel = null
				inst.free()
		elif res is AnimationLibrary:
			for an in (res as AnimationLibrary).get_animation_list():
				if String(an) != "RESET":
					found[String(an)] = (res as AnimationLibrary).get_animation(an).duplicate(true)
		elif res is Animation:
			found[fname.get_basename()] = (res as Animation).duplicate(true)
		if found.is_empty():
			extra_anim_warnings.append("%s — 동작이 없음" % fname)
			if src_inst != null:
				src_inst.free()
			continue
		# Mixamo 를 With Skin 으로 받으면 진짜 동작(mixamo.com) 옆에 키가 하나뿐인 멈춘 자세(Take 001)가 같이 온다.
		# 그대로 두면 동작이 둘이라 파일 이름 대신 "mixamo_com" · "Take_001" 로 들어간다(10-14 Rifle Idle) → 멈춘 것은 뺀다
		if found.size() > 1:
			var moving := {}
			for src_name in found.keys():
				if not _is_static_anim(found[src_name]):
					moving[src_name] = found[src_name]
			if moving.size() > 0:
				found = moving
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
				extra_anim_warnings.append("%s — 뼈 이름이 모델과 하나도 안 맞아 뺌. 모델과 이 파일 양쪽 임포트 설정에 BoneMap(리타깃)을 지정했는지 확인" % fname
					+ " (에디터에서는 같은 폴더 파일이 쓰는 BoneMap 을 자동으로 넣고 다시 가져온다 — 잠시 뒤 `모델 불러오기` 를 다시 누를 것)")
				continue
			if missing > 0:
				extra_anim_warnings.append("%s — 모델에 없는 뼈 트랙 %d/%d개(그 트랙은 무시됨)" % [new_name, missing, bone_tracks])
			if src_skel != null and opts.hand_rest_fix and _hand_rest_fix(anim, src_skel, src_inst):
				rest_fix_anims += 1               # 손 레스트 맞춤이 먼저 — IK 는 맞춘 손 방향을 지킨다
			if src_skel != null and opts.hand_ik and _hand_ik(anim, src_skel, src_inst, skel_path):
				ik_anims += 1
			if lib.has_animation(new_name):
				extra_anim_warnings.append("%s — 모델에 같은 이름의 동작이 있어 추가 동작으로 바꿈" % new_name)
				lib.remove_animation(new_name)
			lib.add_animation(new_name, anim)
			extra_anims.append(new_name)
		if src_inst != null:
			src_inst.free()
	for w in extra_anim_warnings:
		push_warning("[DotRigger] 추가 동작: " + w)


## 모든 트랙의 키가 하나 이하 = 움직이지 않는 자세 하나(바인드 포즈 테이크 등)
static func _is_static_anim(a: Animation) -> bool:
	for ti in a.get_track_count():
		if a.track_get_key_count(ti) > 1:
			return false
	return true


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
		_in_place_orig.erase(old)          # 합성의 제자리는 _make_composite 가 만들 때 건다
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


## 제자리 동작을 정한다. names 에 든 동작은 뿌리 뼈의 수평 이동을 지운 사본으로 바꿔 끼우고, 빠진 동작은 원래 것으로 되돌린다.
## 합성은 여기서 바꾸지 않는다 — build_composites 가 만들 때 반영하므로, 합성이 있으면 이것을 부른 뒤 합성을 다시 만든다(창이 그렇게 한다).
## 돌려주는 값 = 실제로 바꾼(지우거나 되돌린) 동작 이름
func apply_in_place(names: PackedStringArray) -> PackedStringArray:
	opts.in_place = names
	var changed := PackedStringArray()
	if anim_player == null:
		return changed
	var lib := _own_library()
	for n in _in_place_orig.keys():
		if names.has(n):
			continue
		if lib.has_animation(n):
			lib.remove_animation(n)
			lib.add_animation(n, _in_place_orig[n])
			changed.append(n)
		_in_place_orig.erase(n)
	for n in names:
		if _in_place_orig.has(n) or not lib.has_animation(n) or composite_anims.has(n):
			continue
		var orig := lib.get_animation(n)
		var a := orig.duplicate(true) as Animation   # 모델 자신의 동작은 가져온(캐시된) 것과 같은 객체라 사본을 고친다
		if not _strip_root_travel(a):
			continue                                  # 뿌리 뼈가 움직이지 않는다 — 이미 제자리
		lib.remove_animation(n)
		lib.add_animation(n, a)
		_in_place_orig[n] = orig
		changed.append(n)
	return changed


## 아래팔 비틀림 뼈를 손의 비틀림에 맞춰 돌리는 트랙을 모든 동작에 넣는다. 돌려주는 값 = 트랙을 넣은 동작 수.
## 손의 회전(아래팔 기준)을 쉬는 자세와 비교해 아래팔 축(손 쉬는 자리 방향) 둘레 비틀림 θ 를 구하고,
## 비틀림 뼈 = θ × 자리 비율 f(아래팔 시작 0 → 손목 1)만큼 그 축으로 돌린다. 손 자신은 그대로(손 방향은 원래 동작과 같다).
## 살은 bind_to_skeleton.py 가 자리에 따라 아래팔 · 비틀림1 · 비틀림2 · 손으로 나눠 두었다 → 한 구간이 떠안는 비틀림이 θ 의 40 % 남짓.
func _add_forearm_twist() -> int:
	var arms: Array = []    # [아래팔, 손, [[비틀림 뼈, 비율] …]]
	for pr in [["LeftLowerArm", "LeftHand"], ["RightLowerArm", "RightHand"], ["lowerarm_l", "hand_l"], ["lowerarm_r", "hand_r"]]:
		var la := skeleton.find_bone(pr[0])
		var hd := skeleton.find_bone(pr[1])
		if la < 0 or hd < 0 or skeleton.get_bone_parent(hd) != la:
			continue
		var a_l := skeleton.get_bone_rest(hd).origin
		var L := a_l.length()
		if L < 1e-4:
			continue
		a_l /= L
		var tws: Array = []
		for c in skeleton.get_bone_children(la):
			if skeleton.get_bone_name(c).to_lower().contains("twist"):
				tws.append([c, clampf(skeleton.get_bone_rest(c).origin.dot(a_l) / L, 0.0, 1.0)])
		if not tws.is_empty():
			arms.append([la, hd, tws, a_l])
	if arms.is_empty():
		return 0
	var lib := _own_library()
	var count := 0
	for an in lib.get_animation_list():
		var n := String(an)
		if n == PREVIEW_ANIM or n == "RESET":
			continue
		var src := lib.get_animation(n)
		var plan: Array = []   # [[경로 앞부분, 손 트랙, 팔 정보] …]
		for arm in arms:
			var hd_name := skeleton.get_bone_name(int(arm[1]))
			for ti in src.get_track_count():
				if src.track_get_type(ti) == Animation.TYPE_ROTATION_3D and src.track_get_key_count(ti) > 0 \
						and src.track_get_path(ti).get_concatenated_subnames() == hd_name:
					plan.append([String(src.track_get_path(ti)).get_slice(":", 0), ti, arm])
					break
		if plan.is_empty():
			continue
		# 비튼 동작만 바꾼다(UAL 동작은 손 비틀림이 거의 0 — 그대로 둔다)
		var biggest := 0.0
		for p in plan:
			var arm: Array = p[2]
			var rq := skeleton.get_bone_rest(int(arm[1])).basis.get_rotation_quaternion()
			var a_h: Vector3 = rq.inverse() * (arm[3] as Vector3)
			for k in src.track_get_key_count(int(p[1])):
				biggest = maxf(biggest, absf(_twist_about(rq.inverse() * (src.track_get_key_value(int(p[1]), k) as Quaternion), a_h)))
		if biggest < deg_to_rad(2.0):
			continue
		var a := src.duplicate(true) as Animation   # 모델 자신의 동작은 가져온(캐시된) 것과 같은 객체 — 사본을 고친다
		for p in plan:
			var arm: Array = p[2]
			var ti_h: int = p[1]
			var rq := skeleton.get_bone_rest(int(arm[1])).basis.get_rotation_quaternion()
			var a_l: Vector3 = arm[3]
			var a_h := rq.inverse() * a_l
			for tw in arm[2]:
				var bi: int = tw[0]
				var f: float = tw[1]
				var path := NodePath("%s:%s" % [p[0], skeleton.get_bone_name(bi)])
				var old := a.find_track(path, Animation.TYPE_ROTATION_3D)
				if old >= 0:
					a.remove_track(old)
				var nt := a.add_track(Animation.TYPE_ROTATION_3D)
				a.track_set_path(nt, path)
				a.track_set_interpolation_type(nt, Animation.INTERPOLATION_LINEAR)
				var rt := skeleton.get_bone_rest(bi).basis.get_rotation_quaternion()
				var th_prev := 0.0
				for k in a.track_get_key_count(ti_h):
					var th := _twist_about(rq.inverse() * (a.track_get_key_value(ti_h, k) as Quaternion), a_h)
					# θ 는 ±180° 에서 감긴다 — 이웃 키와 가까운 쪽으로 편다(10-15). 안 펴면 손이 180° 근처를 지날 때 비틀림 뼈가 한 프레임에
					# θ × 비율만큼 뒤집혔다(Crouch_Rifle_Kneel_Hit_To_Back 왼손 −176° → +180° → −167°: 비틀림1 이 174° 튐 — 3D 로 쓰면 아래팔 살이 꼬여 보임)
					if k > 0:
						th = th_prev + wrapf(th - th_prev, -PI, PI)
					th_prev = th
					a.rotation_track_insert_key(nt, a.track_get_key_time(ti_h, k), (Quaternion(a_l, th * f) * rt).normalized())
		lib.remove_animation(n)
		lib.add_animation(n, a)
		count += 1
	return count


## q 의 축 ax(단위) 둘레 비틀림 각도(라디안, 부호 포함) — 스윙-트위스트 분해의 트위스트
static func _twist_about(q: Quaternion, ax: Vector3) -> float:
	var p := Vector3(q.x, q.y, q.z).dot(ax)
	var tw := Quaternion(ax.x * p, ax.y * p, ax.z * p, q.w).normalized()
	var ang := 2.0 * acos(clampf(absf(tw.w), 0.0, 1.0))
	return ang if (p * tw.w) >= 0.0 else -ang


## 손 자리 맞춤에 쓰는 뼈(BoneMap 리타깃 이름) — [어깨, 윗팔, 아래팔, 손, 바깥쪽 부호(모델 +X = 캐릭터 왼쪽)]
const IK_ARMS := [["LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand", 1.0],
	["RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand", -1.0]]
const IK_CHEST := ["UpperChest", "Chest", "Spine"]
const IK_FPS := 30.0
## 출처 팔 펴짐(어깨 → 손목 거리 ÷ 팔 길이)이 이 사이면 가슴 기준 자리 → 원래 관절 각도로 서서히 넘긴다(팔을 쭉 편 자세는 그대로 편 채로)
const IK_STRAIGHT := Vector2(0.88, 0.98)
## IK 가 손목 각(아래팔 기준 손 회전)을 원래보다 바꿔도 되는 한도(라디안, 10°). 넘으면 손의 세상 방향을 그만큼 양보한다
const IK_WRIST_MAX := 0.1745329


## 손 레스트 방향 맞춤(Options.hand_rest_fix) — 출처 뼈대와 이 모델의 레스트 손 틀(손목 → 중지 뿌리, 엄지 쪽 = 검지 뿌리 − 새끼 뿌리,
## 그 법선)을 맞추는 고정 회전 Q 를 손 회전 키마다 뒤에 곱한다. 리타깃 뒤 두 뼈대의 손 뼈 틀은 같은 쪽을 보지만, 손 살(손가락 뿌리)이
## 그 틀에 대해 기운 정도가 뼈대마다 달라 손이 늘 그만큼 다른 쪽을 봤다. Q = 출처 레스트⁻¹ · 출처 손 틀 · 이 모델 손 틀⁻¹ · 이 모델 레스트
## (모두 모델 공간). 손가락은 손의 자식이라 같이 따라간다. 바꿨으면 true
func _hand_rest_fix(anim: Animation, src_sk: Skeleton3D, src_root: Node) -> bool:
	var m_o := _xform_to(model_root, skeleton).basis.orthonormalized()
	var m_s := _xform_to(src_root, src_sk).basis.orthonormalized()
	var rot_tr := _bone_tracks(anim, Animation.TYPE_ROTATION_3D)
	var changed := false
	for d in IK_ARMS:
		var hn := String(d[3])
		var side := hn.trim_suffix("Hand")
		var hb_o := skeleton.find_bone(hn)
		var hb_s := src_sk.find_bone(hn)
		if hb_o < 0 or hb_s < 0 or not rot_tr.has(hn):
			continue
		var fo := _hand_frame(skeleton, side, m_o)
		var fs := _hand_frame(src_sk, side, m_s)
		if absf(fo.determinant()) < 0.5 or absf(fs.determinant()) < 0.5:
			continue                                       # 손가락 뼈가 없는 뼈대
		var ro := (m_o * skeleton.get_bone_global_rest(hb_o).basis).orthonormalized()
		var rs := (m_s * src_sk.get_bone_global_rest(hb_s).basis).orthonormalized()
		var q := (rs.inverse() * fs * fo.inverse() * ro).get_rotation_quaternion().normalized()
		if q.get_angle() < deg_to_rad(0.5):
			continue
		var ti := int(rot_tr[hn])
		for k in anim.track_get_key_count(ti):
			anim.track_set_key_value(ti, k, ((anim.track_get_key_value(ti, k) as Quaternion) * q).normalized())
		changed = true
		if float(d[4]) > 0.0:
			rest_fix_deg.x = rad_to_deg(q.get_angle())
		else:
			rest_fix_deg.y = rad_to_deg(q.get_angle())
	return changed


## 레스트 손 해부 틀(모델 공간 방향): 열 = 손 방향(손목 → 중지 뿌리), 엄지 쪽(검지 뿌리 − 새끼 뿌리, 손 방향에 수직), 그 둘의 법선.
## 손가락 뼈가 없으면 0 행렬
static func _hand_frame(sk: Skeleton3D, side: String, m: Basis) -> Basis:
	var ids := [sk.find_bone(side + "Hand"), sk.find_bone(side + "MiddleProximal"), sk.find_bone(side + "IndexProximal"), sk.find_bone(side + "LittleProximal")]
	if ids.has(-1):
		return Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	var p: Array[Vector3] = []
	for i in ids:
		p.append(sk.get_bone_global_rest(int(i)).origin)
	var h := (m * (p[1] - p[0])).normalized()
	var l := m * (p[2] - p[3])
	l = (l - h * l.dot(h)).normalized()
	return Basis(h, l, h.cross(l))


## 추가 동작 하나에 손 자리 맞춤을 건다(트랙 경로는 이미 이 모델 뼈대로 고쳐 쓴 뒤). src_sk = 그 파일의 뼈대(출처 비율). 바꿨으면 true.
## 손목 목표 = 이 모델 가슴 + (출처 손목 − 출처 가슴) × 몸통 비율(골반 → 목, 이 모델 ÷ 출처) — 모델 공간(두 뼈대 모두 +Z 를 본다).
## 두 마디 IK: 어깨는 그대로, 팔꿈치는 원래 아래팔 방향을 가장 잘 지키는 자리(원래 굽은 쪽 반원 안). 윗팔 · 아래팔은 가장 짧은 회전으로
## 돌려 비틀림을 지키고, 손은 원래 세상 방향 그대로 — 단 손목 각이 IK_WRIST_MAX 넘게 바뀌면 그만큼만(손목이 꺾여 매달린 듯 안 보이게).
func _hand_ik(anim: Animation, src_sk: Skeleton3D, src_root: Node, skel_path: String) -> bool:
	var chest := ""
	for n in IK_CHEST:
		if skeleton.find_bone(n) >= 0 and src_sk.find_bone(n) >= 0:
			chest = n
			break
	var hips_o := skeleton.find_bone("Hips")
	var hips_s := src_sk.find_bone("Hips")
	var neck_o := skeleton.find_bone("Neck")
	var neck_s := src_sk.find_bone("Neck")
	if chest == "" or hips_o < 0 or hips_s < 0 or neck_o < 0 or neck_s < 0 or anim.length <= 0.0:
		return false
	var m_o := _xform_to(model_root, skeleton)
	var m_s := _xform_to(src_root, src_sk)
	var torso_o := (m_o * skeleton.get_bone_global_rest(neck_o).origin).distance_to(m_o * skeleton.get_bone_global_rest(hips_o).origin)
	var torso_s := (m_s * src_sk.get_bone_global_rest(neck_s).origin).distance_to(m_s * src_sk.get_bone_global_rest(hips_s).origin)
	if torso_o < 1e-5 or torso_s < 1e-5:
		return false
	var k := clampf(torso_o / torso_s, 0.5, 2.0)
	var rot_tr := _bone_tracks(anim, Animation.TYPE_ROTATION_3D)
	var pos_tr := _bone_tracks(anim, Animation.TYPE_POSITION_3D)
	var scl_tr := _bone_tracks(anim, Animation.TYPE_SCALE_3D)
	var arms: Array = []
	for d in IK_ARMS:
		var o: Array = []
		var s: Array = []
		for i in 4:
			o.append(skeleton.find_bone(String(d[i])))
			s.append(src_sk.find_bone(String(d[i])))
		if o.has(-1) or s.has(-1):
			continue
		if skeleton.get_bone_parent(o[1]) != o[0] or skeleton.get_bone_parent(o[2]) != o[1] or skeleton.get_bone_parent(o[3]) != o[2]:
			continue
		if not rot_tr.has(String(d[1])) and not rot_tr.has(String(d[2])):
			continue                                       # 이 동작은 그 팔을 안 움직인다
		var ua_s := m_s * src_sk.get_bone_global_rest(s[1]).origin
		var la_s := m_s * src_sk.get_bone_global_rest(s[2]).origin
		var hd_s := m_s * src_sk.get_bone_global_rest(s[3]).origin
		arms.append({"d": d, "o": o, "s": s, "len_s": ua_s.distance_to(la_s) + la_s.distance_to(hd_s)})
	if arms.is_empty():
		return false
	var ch_o := skeleton.find_bone(chest)
	var ch_s := src_sk.find_bone(chest)
	var mi := m_o.affine_inverse()
	var down := (mi.basis * Vector3.DOWN).normalized()
	var back := (mi.basis * Vector3(0, 0, -1)).normalized()     # 캐릭터는 +Z 를 본다 → 등 = −Z
	var side := (mi.basis * Vector3.RIGHT).normalized()          # 캐릭터 왼쪽 = +X
	var steps := maxi(1, int(ceil(anim.length * IK_FPS)))
	var times := PackedFloat32Array()
	for i in steps + 1:
		times.append(minf(anim.length, float(i) / IK_FPS))
	var out := {}            # 뼈 번호 -> Array[Quaternion]
	for arm in arms:
		var d: Array = arm["d"]
		var o: Array = arm["o"]
		var s: Array = arm["s"]
		for i in 3:
			out[o[i + 1]] = []
		for t in times:
			var g_sh := _anim_global(skeleton, anim, rot_tr, pos_tr, scl_tr, o[0], t)
			var g_ua := g_sh * _anim_local(skeleton, anim, rot_tr, pos_tr, scl_tr, o[1], t)
			var g_la := g_ua * _anim_local(skeleton, anim, rot_tr, pos_tr, scl_tr, o[2], t)
			var g_hd := g_la * _anim_local(skeleton, anim, rot_tr, pos_tr, scl_tr, o[3], t)
			var g_ch := _anim_global(skeleton, anim, rot_tr, pos_tr, scl_tr, ch_o, t)
			var sg_ch := m_s * _anim_global(src_sk, anim, rot_tr, pos_tr, scl_tr, ch_s, t)
			var sg_ua := m_s * _anim_global(src_sk, anim, rot_tr, pos_tr, scl_tr, s[1], t)
			var sg_hd := m_s * _anim_global(src_sk, anim, rot_tr, pos_tr, scl_tr, s[3], t)
			var sh := g_ua.origin
			var el := g_la.origin
			var wr := g_hd.origin
			var a := sh.distance_to(el)
			var b := el.distance_to(wr)
			if a < 1e-5 or b < 1e-5:
				for i in 3:
					(out[o[i + 1]] as Array).append(_anim_local(skeleton, anim, rot_tr, pos_tr, scl_tr, o[i + 1], t).basis.get_rotation_quaternion())
				continue
			var tgt := mi * ((m_o * g_ch).origin + (sg_hd.origin - sg_ch.origin) * k)
			var ext := sg_hd.origin.distance_to(sg_ua.origin) / maxf(float(arm["len_s"]), 1e-5)
			var al := smoothstep(IK_STRAIGHT.x, IK_STRAIGHT.y, ext)
			if al > 0.0:
				tgt = tgt.lerp(sh + (wr - sh).normalized() * minf(ext, 1.0) * (a + b), al)
			var st := tgt - sh
			var dist := clampf(st.length(), absf(a - b) + 1e-4, a + b - 1e-4)
			var u := st.normalized() if st.length() > 1e-6 else (wr - sh).normalized()
			var pole := (el - sh) + (down * 0.1 + back * 0.07 + side * float(d[4]) * 0.07) * a
			pole -= u * pole.dot(u)
			if pole.length() < 1e-6:
				pole = down - u * down.dot(u)
			var v := pole.normalized()
			var ca := clampf((a * a + dist * dist - b * b) / (2.0 * a * dist), -1.0, 1.0)
			var wr2 := sh + u * dist
			# 팔꿈치 = 어깨 · 손목 목표를 잇는 축 둘레 원 위의 한 점. 원래 아래팔 방향을 가장 잘 지키는 점을 고른다(그만큼 손목이 덜 꺾임 —
			# 처음엔 원래 팔꿈치 쪽을 골랐더니 Walk · Shoot 손목이 원본보다 16 ~ 20° 펴짐, 진단 10-15). 원래 굽은 쪽에서 90° 넘게 돌면 원래 쪽.
			var cc := sh + u * (a * ca)
			var rr := a * sqrt(maxf(0.0, 1.0 - ca * ca))
			var el2 := cc + v * rr
			var want := (wr2 - (wr - el).normalized() * b) - cc
			want -= u * want.dot(u)
			if want.length() > 1e-6 and want.normalized().dot(v) > 0.0:
				el2 = cc + want.normalized() * rr
			var b_sh := g_sh.basis.orthonormalized()
			var b_ua := g_ua.basis.orthonormalized()
			var b_la := g_la.basis.orthonormalized()
			var b_hd := g_hd.basis.orthonormalized()
			var q1 := Quaternion((el - sh).normalized(), (el2 - sh).normalized())
			var b_ua2 := Basis(q1) * b_ua
			var b_la1 := Basis(q1) * b_la
			var q2 := Quaternion((q1 * (wr - el)).normalized(), (wr2 - el2).normalized())
			var b_la2 := Basis(q2) * b_la1
			# 손: 세상 방향(총 방향)을 지키되, 손목 각이 원래(아래팔 기준)보다 IK_WRIST_MAX 넘게 바뀌면 그만큼만 — 손목이 부러진 듯 꺾이지 않게
			var l_fk := (b_la.inverse() * b_hd).get_rotation_quaternion().normalized()
			var l_hd := (b_la2.inverse() * b_hd).get_rotation_quaternion().normalized()
			var dev := l_fk.angle_to(l_hd)
			if dev > IK_WRIST_MAX:
				l_hd = l_fk.slerp(l_hd, IK_WRIST_MAX / dev).normalized()
			(out[o[1]] as Array).append((b_sh.inverse() * b_ua2).get_rotation_quaternion().normalized())
			(out[o[2]] as Array).append((b_ua2.inverse() * b_la2).get_rotation_quaternion().normalized())
			(out[o[3]] as Array).append(l_hd)
	for bi in out.keys():
		var path := NodePath("%s:%s" % [skel_path, skeleton.get_bone_name(int(bi))])
		var ti := anim.find_track(path, Animation.TYPE_ROTATION_3D)
		if ti < 0:
			ti = anim.add_track(Animation.TYPE_ROTATION_3D)
			anim.track_set_path(ti, path)
		while anim.track_get_key_count(ti) > 0:
			anim.track_remove_key(ti, 0)
		anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_LINEAR)
		var qs: Array = out[bi]
		for i in times.size():
			anim.rotation_track_insert_key(ti, times[i], qs[i])
	ik_scale = k
	return true


## 노드 root 에서 node 까지의 Node3D 변환을 곱한 것(root 포함 · 트리 밖이어도 된다) — 뼈대 공간 → 모델 공간
static func _xform_to(root: Node, node: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != null:
		if n is Node3D:
			t = (n as Node3D).transform * t
		if n == root:
			break
		n = n.get_parent()
	return t


## 뼈 이름 -> 그 종류(회전 · 위치 · 크기) 트랙 번호
static func _bone_tracks(anim: Animation, type: int) -> Dictionary:
	var m := {}
	for ti in anim.get_track_count():
		if anim.track_get_type(ti) == type and anim.track_get_key_count(ti) > 0:
			m[anim.track_get_path(ti).get_concatenated_subnames()] = ti
	return m


## 동작의 시각 t 에서 뼈 bi 의 부모 기준 자세(트랙이 없으면 레스트 · 위치 트랙은 motion_scale 을 곱한다 — AnimationPlayer 와 같게)
static func _anim_local(sk: Skeleton3D, anim: Animation, rot_tr: Dictionary, pos_tr: Dictionary, scl_tr: Dictionary, bi: int, t: float) -> Transform3D:
	var rest := sk.get_bone_rest(bi)
	var nm := sk.get_bone_name(bi)
	var o := rest.origin
	if pos_tr.has(nm):
		o = anim.position_track_interpolate(int(pos_tr[nm]), t) * sk.motion_scale
	var q := rest.basis.get_rotation_quaternion()
	if rot_tr.has(nm):
		q = anim.rotation_track_interpolate(int(rot_tr[nm]), t)
	var sc := rest.basis.get_scale()
	if scl_tr.has(nm):
		sc = anim.scale_track_interpolate(int(scl_tr[nm]), t)
	return Transform3D(Basis(q) * Basis.from_scale(sc), o)


## 동작의 시각 t 에서 뼈 bi 의 뼈대 기준 자세(뿌리부터 부모 기준 자세를 차례로 곱한 것)
static func _anim_global(sk: Skeleton3D, anim: Animation, rot_tr: Dictionary, pos_tr: Dictionary, scl_tr: Dictionary, bi: int, t: float) -> Transform3D:
	var chain: Array[int] = []
	var w := bi
	while w >= 0:
		chain.push_front(w)
		w = sk.get_bone_parent(w)
	var g := Transform3D.IDENTITY
	for b in chain:
		g = g * _anim_local(sk, anim, rot_tr, pos_tr, scl_tr, b, t)
	return g


## 그 동작이 처음 → 끝 사이에 수평으로 간 거리(m, 제자리로 바꾸기 전 기준). 뿌리 뼈가 안 움직이면 0
## 합성은 끝 프레임이 반복 지점이라 직접 못 잰다 → 하체 동작 한 주기의 이동(하체를 이미 제자리로 했으면 0).
## 하체를 여러 번 돌리는 합성도 주기마다 힙이 처음 자리로 돌아오므로 한 주기 거리가 화면에서 걸어 나가는 거리다
func root_travel(anim_name: String) -> float:
	for info in composite_info:
		var ci: Dictionary = info
		if String(ci.get("name", "")) == anim_name:
			var lower := String(ci.get("lower", ""))
			if _in_place_orig.has(lower):
				return 0.0
			return root_travel(lower)
	var a: Animation = _in_place_orig.get(anim_name, null)
	if a == null:
		if anim_player == null or not anim_player.has_animation(anim_name):
			return 0.0
		a = anim_player.get_animation(anim_name)
	var info := _root_travel_info(a)
	if info.is_empty():
		return 0.0
	return (info["d"] as Vector3).length() * skeleton.motion_scale   # 리타깃이 위치 트랙을 힙 높이로 나눠 두었으면 되돌려 m 로


## 뿌리 뼈 = 수평으로 움직이는 위치 트랙이 있는 뼈 중 가장 위(보통 힙). { track, d(처음 → 끝 수평 이동, 트랙 공간), t0, t1 } — 없으면 {}
func _root_travel_info(a: Animation) -> Dictionary:
	var best := {}
	var best_depth := 1 << 30
	for ti in a.get_track_count():
		if a.track_get_type(ti) != Animation.TYPE_POSITION_3D or a.track_get_key_count(ti) < 2:
			continue
		var bi := skeleton.find_bone(a.track_get_path(ti).get_concatenated_subnames())
		if bi < 0:
			continue
		var depth := 0
		var w := skeleton.get_bone_parent(bi)
		while w >= 0:
			depth += 1
			w = skeleton.get_bone_parent(w)
		if depth >= best_depth:
			continue
		var up := _up_axis_in_bone_parent(bi)
		var last := a.track_get_key_count(ti) - 1
		var d: Vector3 = (a.track_get_key_value(ti, last) as Vector3) - (a.track_get_key_value(ti, 0) as Vector3)
		d -= up * d.dot(up)
		if d.length() < 0.0001:
			continue                       # 이 뼈는 수평으로 안 간다(위아래만 들썩임) — 더 아래 뼈를 본다
		best_depth = depth
		best = {"track": ti, "d": d, "t0": a.track_get_key_time(ti, 0), "t1": a.track_get_key_time(ti, last)}
	return best


## 수평 이동을 지운다 — 처음 → 끝 이동을 시간에 비례해 빼므로 끝 = 처음(반복 지점이 이어진다), 걸음 사이의 들썩임 · 흔들림은 남는다
func _strip_root_travel(a: Animation) -> bool:
	var info := _root_travel_info(a)
	if info.is_empty():
		return false
	var ti: int = info["track"]
	var d: Vector3 = info["d"]
	var t0: float = info["t0"]
	var span := maxf(float(info["t1"]) - t0, 0.0001)
	for k in a.track_get_key_count(ti):
		var f := clampf((a.track_get_key_time(ti, k) - t0) / span, 0.0, 1.0)
		a.track_set_key_value(ti, k, (a.track_get_key_value(ti, k) as Vector3) - d * f)
	return true


## 화면의 위쪽(세상 +Y)이 뼈 bi 의 부모 공간에서 어느 쪽인가 — 위치 트랙 값은 부모 뼈 기준이다
func _up_axis_in_bone_parent(bi: int) -> Vector3:
	var b := Basis.IDENTITY
	var n: Node = skeleton
	while n != null:
		if n is Node3D:
			b = (n as Node3D).transform.basis.orthonormalized() * b
		if n == model_root:
			break
		n = n.get_parent()
	var up := (b.inverse() * Vector3.UP).normalized()
	var par := skeleton.get_bone_parent(bi)
	if par >= 0:
		up = (skeleton.get_bone_global_rest(par).basis.orthonormalized().inverse() * up).normalized()
	return up


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
	# 합성 자체를 제자리로 골랐으면 하체의 이동을 지운 사본으로 합친다. 합성은 끝 프레임을 반복 지점(처음 자세)으로 다시 찍으므로
	# 다 만든 뒤에는 처음 = 끝이라 이동을 잴 수 없다 — 그래서 만들기 전에 지운다
	if opts != null and opts.in_place.has(composite_name(def)):
		lo = lo.duplicate(true) as Animation
		_strip_root_travel(lo)
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


## 부위 칠하기가 바뀌었을 때 모델을 다시 불러오지 않고 파트 메시만 다시 자른다(뼈 → 파트 · 리그는 그대로).
## ov 가 null 이면 지금 칠하기(part_overrides) 그대로 다시 자른다.
func resplit(ov: DRPartOverrides = null) -> void:
	if source_mesh_instance == null or skeleton == null:
		return
	if ov != null:
		part_overrides = ov
	var ns := DRMeshSplitter.split(source_mesh_instance, skeleton, profile, opts.bleed_rings, part_overrides)
	var shader := load(SHADER_PATH) as Shader
	for part in part_nodes.keys():
		var mi := part_nodes[part] as MeshInstance3D
		if ns.meshes.has(part):
			mi.mesh = ns.meshes[part]
			_apply_dot_material(mi, shader)
		else:
			mi.mesh = null      # 칠해서 정점이 하나도 안 남은 파트 — 그림이 비어 굽기에서 빠진다
	split.meshes = ns.meshes
	split.tri_counts = ns.tri_counts
	split.joints = ns.joints


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
## tuck_pairs 에 이 파트가 있으면 위 조각들의 관절 둘레를 빈 곳에 채운다(관절 받침).
func render_part(part: String) -> Image:
	var img: Image = await render_parts(PackedStringArray([part]))
	if tuck_pairs.has(part):
		for up in (tuck_pairs[part] as PackedStringArray):
			await _tuck_joint(img, part, String(up))
	return img


## 관절 받침 하나: 위 조각(up)을 따로 그려, 관절점 중심 원 안에서 아래 조각(img) 이 빈 픽셀을 위 조각 픽셀로 채운다.
## 원 = 레스트 몸 전체 실루엣 안에 드는 가장 큰 원(× tuck_fit + tuck_pad), 관절 둘레(3D)를 넘지 않게.
func _tuck_joint(img: Image, lo: String, up: String) -> void:
	var jd := {}
	for j in split.joints:
		var pc := [String((j as Dictionary)["parent"]), String((j as Dictionary)["child"])]
		if pc.has(lo) and pc.has(up):
			jd = j
			break
	if jd.is_empty() or float(jd["radius"]) <= 0.0 or not rig.parts.has(String(jd["child"])):
		return
	var cp: DRRigModel.Part = rig.parts[String(jd["child"])]
	if cp.root_bone < 0:
		return
	var ss: float = float(maxi(1, opts.supersample))
	var head3d := (skeleton.global_transform * skeleton.get_bone_global_pose(cp.root_bone)).origin
	var c := camera.unproject_position(head3d) / ss
	var r_max := float(jd["radius"]) * float(opts.view_size.y) / maxf(camera.size, 0.0001) * tuck_max
	if _tuck_body == null:
		_tuck_body = await render_all_parts_composite()
	var up_img: Image = await render_parts(PackedStringArray([up]))
	var w := img.get_width()
	var h := img.get_height()
	# 레스트 몸 실루엣 안에 드는 가장 큰 원: 관절점에서 가장 가까운 빈(바탕) 픽셀까지
	var r_in := r_max
	var n := int(ceil(r_max)) + 1
	for y in range(maxi(int(c.y) - n, 0), mini(int(c.y) + n + 1, h)):
		for x in range(maxi(int(c.x) - n, 0), mini(int(c.x) + n + 1, w)):
			if _tuck_body.get_pixel(x, y).a >= 0.5:
				continue
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d < r_in:
				r_in = d
	var r := minf(r_in * tuck_fit + tuck_pad, r_max)
	if r < 1.0:
		return
	var m := int(ceil(r))
	for y in range(maxi(int(c.y) - m, 0), mini(int(c.y) + m + 1, h)):
		for x in range(maxi(int(c.x) - m, 0), mini(int(c.x) + m + 1, w)):
			if Vector2(x + 0.5, y + 0.5).distance_to(c) > r:
				continue
			if img.get_pixel(x, y).a >= 0.5:
				continue
			var u := up_img.get_pixel(x, y)
			if u.a >= 0.5:
				img.set_pixel(x, y, u)


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
