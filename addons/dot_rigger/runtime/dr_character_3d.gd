@tool
extends Node3D
class_name DRCharacter3D

## 게임 병사 한 명의 3D 모습(10-15) — 2D 컷아웃 굽기의 리소스 관리가 너무 힘들어(세트 · 파트 그림 · 복장 그림 · 장비 그림을
## 자세마다 굽고 맞춰야 했다) 3D 캐릭터를 게임에 바로 쓰는 노선으로 바꿨다. 도트 느낌은 셰이더(dot_char)와 저해상도 화면이 낸다.
##
## 노드 구조(setup 뒤):
##   DRCharacter3D                        ← 게임이 위치 · 방향(rotation.y) · 크기(scale)를 준다. 모델은 +Z 를 본다
##     ├ <몸 glb 인스턴스>(human_base)       — 구조 그대로: AnimationPlayer(root_node "..") 의 트랙 `%GeneralSkeleton:<뼈>` 가 그대로 풀린다
##     │   ├ Armature/GeneralSkeleton
##     │   │    ├ SlotTop · SlotBottom · SlotBase (MeshInstance3D — 슬롯 메시. 원래 통메시 Body 는 뺐다)
##     │   │    └ DR_SocketRef · DR_LeftElbow · DR_LeftArmIK · DR_LeftHandRot (왼손 표지가 있을 때만 — 왼팔 IK 수정자)
##     │   └ AnimationPlayer
##     └ 오른손 (BoneAttachment3D = 소켓, 씬에 든 노드 — 10-16)  └ kar98k (장비 = 모델 씬 인스턴스)  └ 왼손 (DRHandTarget3D 표지)
##
## 슬롯: top(몸통 · 윗팔 · 아래팔) · bottom(골반 · 허벅지 · 종아리 · 발) · base(머리 · 손 — 늘 기본 몸).
## 기본 몸 = 세 덩어리(내복 차림). 복장을 입으면 그 슬롯 노드의 메시를 복장 것으로 바꿔 끼운다 — "기본 몸 메시를 숨기고 복장 메시를 보인다"
## 와 같은 결과인데 노드가 늘지 않는다(병사 100 명 이상). 복장의 머리 · 손은 안 쓴다.
## 나누기(DRSlotMesh) · 재질은 정적 캐시로 병사끼리 공유한다 — 같은 (glb · 슬롯 표 · parts.json) 이면 같은 ArrayMesh · Skin · ShaderMaterial.
## 병사마다 다른 값(tint · fade)은 instance uniform 이라 재질을 복제하지 않는다.
##
## 쓰는 예:
##   var ch := DRCharacter3D.new()
##   add_child(ch)                          # 트리에 먼저 넣어도 되고 setup 뒤에 넣어도 된다
##   ch.setup()                             # 기본 = 사람 몸(human_base)
##   ch.set_motions(lib)                    # A 갈래의 AnimationLibrary(트랙 %GeneralSkeleton:<뼈>)
##   ch.wear("res://outfits/uniform_m36/outfit.json")            # 군복 전체 · ["top"] 이면 상의만
##   ch.play_motion("Rifle_Idle")           # 무기 = 유닛 프리팹의 소켓 노드(② 장비 탭) — 조립 때 저절로 붙고 왼손은 표지에 IK
##   (옛 방식: ch.attach_weapon(asset.json) + DRGripFit — 소켓 무기가 없을 때만, weapon_asset 칸)
##   ch.rotation.y = atan2(dir.x, dir.z)    # dir 쪽을 보게(+X = PI/2)
##   ch.scale = Vector3.ONE * (1.75 / ch.model_height())
##   ch.set_tint(Color(0.45, 0.45, 0.45)) ; ch.set_fade(0.3)    # 죽은 병사 어둡게 · 도트식으로 사라지기

const BODY_DEFAULT := "res://source3d/characters/human_base/human_base.glb"
const SHADER_PATH := "res://addons/dot_rigger/shaders/dot_char.gdshader"
const SLOTS := ["top", "bottom", "base"]
## 복장으로 바꿔 끼울 수 있는 슬롯(base = 머리 · 손은 늘 기본 몸)
const WEAR_SLOTS := ["top", "bottom"]
const SLOT_NODE := {"top": "SlotTop", "bottom": "SlotBottom", "base": "SlotBase"}

## 셰이더 공통 값 — 모든 병사의 재질(_mats)에 같이 들어간다. 바꿀 때는 set_shading()
static var _shading := {"bands": 3, "ambient": 0.45, "light_wrap": 0.25, "light_dir": Vector3(-0.4, 0.7, 0.6),
	"rim": 0.0, "inside_shade": 0.35}
static var _shader: Shader = null
## 나눈 모델 캐시: 키(glb|슬롯 표|parts.json md5) -> {model, meshes{슬롯: ArrayMesh}, skin, split(DRSlotMesh.Result), rig(DRRigModel), aabb, height}
static var _entries := {}
## 원래 재질(Material, 없으면 null) -> 공유 ShaderMaterial(dot_char)
static var _mats := {}
## 무기 캐시: asset.json 경로 -> {asset, equip(DREquipBaker — 그립 계산만), mesh(ArrayMesh, 숨김 노드 뺀 합본), part, support, scale, grip_point}
static var _weapons := {}
## Skin 두 개의 바인드가 같은지(인스턴스 id 쌍 -> bool) — 같으면 복장 슬롯도 몸의 Skin 을 써서 뼈대 연결(SkinReference)이 하나로 준다
static var _skin_same := {}
## 파일 읽기 캐시(10-16) — 병사마다 · 옷을 입힐 때마다 outfit.json 을 다시 읽고 parts.json 의 md5 를 다시 재지 않게. clear_cache() 로 비운다
static var _json_cache := {}         # 경로 -> Dictionary
static var _md5_cache := {}          # parts.json 경로 -> md5("" = 없음)

# ---------------------------------------------------------------- 유닛 프리팹(10-16)
## 이 노드를 씬의 루트로 두면 그 씬이 유닛 프리팹이 된다(game/units/soldier_base.tscn — 기본형 군인).
## 다른 유닛 = 그 씬을 상속한 자식 씬(Dot Rigger ① 유닛 탭의 [새 자식 유닛] 또는 씬 > 새 상속 씬)에서 바꿀 칸만 바꾼다 —
## 안 바꾼 칸은 부모를 따라간다(유니티 프리팹 변형과 같다). 칸을 바꾸면 에디터 3D 화면의 모습도 바로 다시 만든다.

@export_group("유닛 모습")
## 기본 몸(사람 몸 glb). 옷을 안 입힌 슬롯은 이 몸(내복)이 보인다
@export_file("*.glb", "*.gltf") var body_model := BODY_DEFAULT:
	set(v):
		body_model = v
		_changed()
## 상의 복장(outfit.json — ③ 복장 탭이 만든 것). 비우면 내복
@export_file("*.json") var outfit_top := "":
	set(v):
		outfit_top = v
		_changed()
## 하의 복장(outfit.json). 비우면 내복
@export_file("*.json") var outfit_bottom := "":
	set(v):
		outfit_bottom = v
		_changed()
## 옛 방식 무기(asset.json 그립 + DRGripFit). 소켓(오른손 BoneAttachment3D)에 무기가 있으면 쓰지 않는다 — 무기는 ② 장비 탭에서 소켓에 넣는다(10-16)
@export_file("*.json") var weapon_asset := "":
	set(v):
		weapon_asset = v
		_changed()
## 동작 표(세트 → 상태 → 동작 · 비중 % · 상하체 합성). 3D 동작 묶음은 표의 library_path 에서 읽는다
@export var motions: DRMotionTable:
	set(v):
		motions = v
		_changed()
## 키(m) — 모델을 이 키로 맞춘다(0 = 모델 그대로)
@export_range(0.0, 2.5, 0.01, "suffix:m") var height_m := 1.75:
	set(v):
		height_m = v
		_apply_height()
## 씬에 들어가면(_ready) 위 칸대로 저절로 조립한다. 끄면 setup() · wear() 를 직접 부를 때만
@export var auto_build := true

@export_group("미리보기 (에디터)")
## 에디터 3D 화면에서 이 동작 자세로 보여 준다(동작 표의 동작 · 내보낸 3D 동작 묶음에 있어야 함)
@export var preview_motion := "":
	set(v):
		preview_motion = v
		_apply_preview()
## 미리보기 동작을 에디터에서 계속 재생(끄면 그 동작의 한 장면에서 멈춤)
@export var preview_playing := false:
	set(v):
		preview_playing = v
		_apply_preview()

## 조립이 끝났을 때(build) — 유닛 탭 미리보기 등이 받는다
signal built

var _built := false
var _rebuild_queued := false
var _motion := ""                    # 지금 튼 동작(play_motion)
var _grip_from := Transform3D.IDENTITY
var _grip_to := Transform3D.IDENTITY
var _grip_t := -1.0                  # 동작이 바뀔 때 무기 그립을 섞은 시간(−1 = 안 섞는 중)
var _grip_blend := 0.1

var _body_path := ""
var _body: Dictionary = {}
var _model: Node3D = null
var _skel: Skeleton3D = null
var _ap: AnimationPlayer = null
var _slot_mi := {}            # 슬롯 -> MeshInstance3D
var _worn := {}               # 슬롯 -> outfit.json 경로
var _tint := Color.WHITE
var _fade := 1.0
var _cast_shadow := false
var _mount: BoneAttachment3D = null
var _weapon_mi: MeshInstance3D = null
var _weapon: Dictionary = {}
var _grip := Transform3D.IDENTITY   # 손 뼈 로컬 무기 변환(배율 전) — DREquipBaker.compose_grip 과 같은 뜻
# 소켓 · 장비(10-16) — 아래 "소켓 · 장비" 절
var _sockets: Array[BoneAttachment3D] = []
var _equip_mis: Array[MeshInstance3D] = []     # 소켓 장비 메시 중 도트 재질을 입힌 것(tint · fade · 그림자를 같이)
var _sock_weapon: Node3D = null                # 오른손 소켓의 보이는 장비
var _support: Node3D = null                    # 왼손 표지(DRHandTarget3D 또는 이름 "왼손")
var _support_sock: BoneAttachment3D = null     # 표지가 든 소켓
var _ik_ref: ModifierBoneTarget3D = null       # 뼈대 아래(주인 없음): 수정자 차례 안에서 소켓 뼈를 따라감
var _ik_wrist: Node3D = null                   # _ik_ref 아래: 왼 손목 목표(원점) · 손 회전(기저)
var _ik_pole: ModifierBoneTarget3D = null      # 극 = 동작의 왼 팔꿈치(IK 보다 앞 차례라 동작 자세) — 팔꿈치가 동작 쪽으로 굽게
var _ik: TwoBoneIK3D = null
var _ik_rot: CopyTransformModifier3D = null
var _ik_bones := PackedInt32Array()            # [위팔, 아래팔, 손, 소켓 뼈]
var _ik_rel := Transform3D.IDENTITY            # 소켓 → 표지(배율 뺌)
var _palm_l := Vector3.ZERO                    # 왼손 뼈 로컬 손바닥 점(뼈 머리 · 꼬리 가운데 — DRGripFit 과 같은 뜻)
var _ik_w := 0.0
var _ik_from := 0.0
var _ik_to := 0.0
var _equip_sig := ""                           # 편집 중인 씬에서 소켓 구조가 바뀌었나(에디터만)
var _saved_skel_paths := {}                    # 저장하는 동안 비운 소켓의 뼈대 길(소켓 -> 길)
var _equip_poll := 0.0


# ---------------------------------------------------------------- 만들기

func _ready() -> void:
	if auto_build and _model == null:
		build()
	_update_processing()


## 에디터 미리보기 재생(preview_playing) — 게임에서는 화면(BattleView3D)이 step_motion 으로 직접 돌린다.
## 편집 중인 씬이면 소켓 장비 · 왼손 표지를 기즈모로 옮길 때 왼손 IK 가 바로 따라가게 한다(10-16)
func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	if preview_playing and _ap != null:
		step_motion(delta)
	if is_part_of_edited_scene():
		_editor_follow(delta)


## 에디터에서 씬을 저장할 때 — 소켓이 가리키는 뼈대는 안에서 조립한(저장 안 되는) 노드라 그 길을 비웠다가 저장 뒤 그대로 되돌린다
## (안 그러면 씬 파일에 external_skeleton = "../human_base/…" 같은 줄이 저장할 때마다 남는다. 불러오면 조립 뒤 어차피 다시 잇는다).
## 되돌릴 때는 길만 — 묶음(뼈대 신호 연결)은 그대로라 다시 묶으면 "이미 연결됨" 오류(10-16)
func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_saved_skel_paths.clear()
		for s in find_sockets(self, _model):          # 지금 씬에 든 소켓(_sockets 는 다음 다시 잇기 전까지 방금 더하거나 뺀 것이 안 맞을 수 있다)
			if not s.external_skeleton.is_empty():
				_saved_skel_paths[s] = s.external_skeleton
				s.external_skeleton = NodePath()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		for s in _saved_skel_paths.keys():
			if is_instance_valid(s):
				(s as BoneAttachment3D).external_skeleton = _saved_skel_paths[s]
		_saved_skel_paths.clear()


## _process 를 켤지 — 에디터에서 미리보기를 재생하거나 편집 중인 씬일 때만(게임 · 미리보기 사본은 끈다)
func _update_processing() -> void:
	set_process(Engine.is_editor_hint() and (preview_playing or (is_inside_tree() and is_part_of_edited_scene())))


## 위 "유닛 모습" 칸대로 조립한다 — 몸 → 키 → 상의 · 하의 → 동작 묶음 → 무기. 다시 부르면 처음부터(칸을 바꿨을 때)
func build() -> bool:
	_rebuild_queued = false
	_motion = ""
	_grip_t = -1.0
	if not setup(body_model):
		return false
	_apply_height()
	if outfit_top != "":
		wear(outfit_top, PackedStringArray(["top"]))
	if outfit_bottom != "":
		wear(outfit_bottom, PackedStringArray(["bottom"]))
	if motions != null and motions.library_path != "" and ResourceLoader.exists(motions.library_path):
		set_motions(load(motions.library_path) as AnimationLibrary)
	if Engine.is_editor_hint() and _ap != null:
		_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL   # 에디터에서는 _process 가 직접 돌린다
	refresh_equipment()
	if weapon_asset != "" and _sock_weapon == null:
		attach_weapon(weapon_asset)        # 옛 방식(asset.json 그립 + DRGripFit) — 소켓 무기가 없을 때만
	_built = true
	_apply_preview()
	built.emit()
	return true


## 칸이 바뀌었다 — 이미 조립했으면(씬 안) 다음 프레임에 한 번 다시 조립. 씬을 불러오는 중(트리 밖)에는 _ready 가 조립한다
func _changed() -> void:
	if not _built or not is_inside_tree() or not auto_build or _rebuild_queued:
		return
	_rebuild_queued = true
	build.call_deferred()


func _apply_height() -> void:
	if _model == null:
		return
	var h := model_height()
	_model.scale = Vector3.ONE * (height_m / h if height_m > 0.0 and h > 0.0 else 1.0)


## 에디터 미리보기 자세(preview_motion) — 그 동작의 30 % 자세(재생 켜면 이어서 돈다)
func _apply_preview() -> void:
	if not Engine.is_editor_hint() or _ap == null or not _built:
		_update_processing()
		return
	_update_processing()
	if preview_motion == "" or not _ap.has_animation(preview_motion):
		return
	DRGripFit.fit_anim(self, preview_motion)       # 캐시를 먼저(처음 계산이 재생 상태를 건드리므로)
	play_motion(preview_motion, 0.0)
	_ap.seek(_ap.get_animation(preview_motion).length * 0.3, true)


## 인스펙터의 미리보기 동작 칸 = 지금 동작 묶음의 동작 목록에서 고르기
func _validate_property(property: Dictionary) -> void:
	if String(property["name"]) == "preview_motion":
		property["hint"] = PROPERTY_HINT_ENUM_SUGGESTION
		property["hint_string"] = ",".join(motion_names())


## 복장 보기(시험장 F4) — 이 유닛의 상의 · 하의를 입히거나 벗긴다(없는 쪽은 내복)
func dress(top_on: bool, bottom_on: bool) -> void:
	take_off()
	if top_on and outfit_top != "":
		wear(outfit_top, PackedStringArray(["top"]))
	if bottom_on and outfit_bottom != "":
		wear(outfit_bottom, PackedStringArray(["bottom"]))


# ---------------------------------------------------------------- 동작 재생(무기 그립 포함)

## 동작을 튼다(섞는 시간 blend 초).
## 소켓 무기(정석, 10-16): 무기 자리는 소켓 기준으로 고정이고, 그 동작의 왼손 IK 비중(표지의 동작별 비중)으로 같은 시간 동안 옮긴다 —
##   `_grip_t` 가 섞기 시간, `_grip_from` · `_grip_to` 는 무기의 소켓 기준 자리(동작과 상관없이 같다).
## 옛 무기(weapon_asset): 그 동작에 맞춘 그립(DRGripFit — 동작마다 두 손에 다시 맞춘 것, 캐시)으로 같은 시간 동안 옮긴다.
func play_motion(motion: String, blend: float = 0.1) -> void:
	if _ap == null or not _ap.has_animation(motion):
		return
	var first := _motion == "" or not _ap.is_playing()
	_ap.play(motion, 0.0 if first else blend)
	if first:
		_ap.advance(0.0)                   # 처음 자세를 바로 — 안 그러면 다음 갱신까지 레스트(T자) 자세로 보인다
	_motion = motion
	if _sock_weapon != null:
		var w := _support_weight(motion)
		if first or blend <= 0.0:
			_set_ik_weight(w)
			_grip_t = -1.0
		else:
			_ik_from = _ik_w
			_ik_to = w
			_grip_from = _sock_weapon.transform
			_grip_to = _sock_weapon.transform
			_grip_blend = blend
			_grip_t = 0.0
		return
	if _weapon_mi == null:
		return
	var g := DRGripFit.fit_anim(self, motion)
	if g.is_empty():
		return
	if first or blend <= 0.0:
		set_weapon_grip(g["grip"])
		_grip_t = -1.0
	else:
		_grip_from = _grip
		_grip_to = g["grip"]
		_grip_blend = blend
		_grip_t = 0.0


## 동작을 dt 초 진행한다(AnimationPlayer 를 손으로 돌릴 때 — 게임은 초당 12번 모아서). 돌려주는 값 = 반복 동작이 한 바퀴 돌았나
func step_motion(dt: float) -> bool:
	if _ap == null:
		return false
	var before := _ap.current_animation_position
	_ap.advance(dt)
	var wrapped := _ap.current_animation_position < before
	if _grip_t >= 0.0:
		_grip_t += dt
		var k := clampf(_grip_t / maxf(_grip_blend, 0.001), 0.0, 1.0)
		if _weapon_mi != null:
			set_weapon_grip(_grip_from.interpolate_with(_grip_to, k))
		if _ik != null:
			_set_ik_weight(lerpf(_ik_from, _ik_to, k))
		if k >= 1.0:
			_grip_t = -1.0
	return wrapped


## 동작마다 무기 그립을 미리 계산(로딩 때) — 옛 무기(weapon_asset)만. DRGripFit 캐시라 같은 몸 · 무기 · 동작 묶음이면 병사 수와 상관없이 한 번.
## 소켓 무기는 미리 계산할 것이 없다(자리 고정 + 왼손은 IK 가 갱신 때마다 — 뼈대 수정자). 처음 계산은 자세를 잠깐 바꿨다 되돌리므로 재생 중이 아닐 때 부른다
func precompute_grips() -> void:
	if _weapon_mi == null or _ap == null:
		return
	for n in _ap.get_animation_list():
		if String(n) != "RESET":
			DRGripFit.fit_anim(self, String(n))


## 동작 묶음의 동작 이름(RESET 뺌)
func motion_names() -> PackedStringArray:
	var out := PackedStringArray()
	if _ap != null:
		for n in _ap.get_animation_list():
			if String(n) != "RESET":
				out.append(String(n))
	return out


func current_motion() -> String:
	return _motion


# ---------------------------------------------------------------- 만들기

## 몸 glb 를 인스턴스해 구조를 그대로 두고, 원래 통메시를 빼고 슬롯 메시 셋(기본 몸 = 내복)을 붙인다. 다시 부르면 처음부터.
## 프리팹으로 쓸 때는 build() 가 칸(body_model …)대로 부른다
func setup(model_path: String = BODY_DEFAULT) -> bool:
	_clear()
	var e := load_entry(model_path)
	if e.is_empty():
		return false
	var ps := load(model_path) as PackedScene
	_model = ps.instantiate() as Node3D if ps != null else null
	if _model == null:
		push_error("[DRCharacter3D] 몸 모델의 루트가 Node3D 가 아닙니다: %s" % model_path)
		return false
	add_child(_model)
	_skel = DRBaker._find_node(_model, "Skeleton3D") as Skeleton3D
	_ap = DRBaker._find_node(_model, "AnimationPlayer") as AnimationPlayer
	if _skel == null:
		push_error("[DRCharacter3D] Skeleton3D 가 없습니다: %s" % model_path)
		_clear()
		return false
	if _ap == null:                        # 스킨만 받은 몸 — 동작은 set_motions 로 넣는다
		_ap = AnimationPlayer.new()
		_ap.name = "AnimationPlayer"
		_model.add_child(_ap)              # root_node 기본값 ".." = 모델 루트
	# 원래 통메시는 뺀다 — 슬롯 메시가 대신한다(숨기기만 하면 노드 · 스킨 연결이 병사마다 남는다)
	var stack: Array[Node] = [_model]
	var olds: Array[MeshInstance3D] = []
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).skin != null:
			olds.append(n as MeshInstance3D)
		stack.append_array(n.get_children())
	for mi in olds:
		mi.get_parent().remove_child(mi)
		mi.free()
	for s in SLOTS:
		var mi := MeshInstance3D.new()
		mi.name = String(SLOT_NODE[s])
		_skel.add_child(mi)
		mi.skeleton = NodePath("..")
		_slot_mi[s] = mi
	_body = e
	_body_path = model_path
	for s in SLOTS:
		_put(String(s), e)
	_apply_shadow()
	return true


func _clear() -> void:
	detach_weapon()
	if _model != null and is_instance_valid(_model):
		if _model.get_parent() != null:
			_model.get_parent().remove_child(_model)
		_model.free()
	_model = null
	_skel = null
	_ap = null
	_slot_mi.clear()
	_worn.clear()
	_body = {}
	_body_path = ""


# ---------------------------------------------------------------- 복장

## 복장을 입힌다. only_slots 가 비면 그 복장이 가진 top · bottom 다. 예: wear(A, ["top"]); wear(B, ["bottom"]) = 상의 A + 하의 B
## 돌려주는 값 = 하나라도 입혔나
func wear(outfit_json: String, only_slots: PackedStringArray = PackedStringArray()) -> bool:
	if _model == null:
		push_error("[DRCharacter3D] setup() 을 먼저 부르세요")
		return false
	var d := _read_json(outfit_json)
	var glb := String(d.get("model", ""))
	if glb == "":
		push_warning("[DRCharacter3D] 복장 파일을 읽을 수 없거나 model 이 없습니다: %s" % outfit_json)
		return false
	var table: Dictionary = d.get("slots", {})
	var e := load_entry(glb, table)
	if e.is_empty():
		return false
	var want: Array = Array(only_slots) if not only_slots.is_empty() else WEAR_SLOTS
	var done := false
	for s in want:
		var ss := String(s)
		if not WEAR_SLOTS.has(ss):
			push_warning("[DRCharacter3D] '%s' 슬롯은 입힐 수 없습니다(머리 · 손 = 늘 기본 몸)" % ss)
			continue
		if not (e["meshes"] as Dictionary).has(ss):
			continue                       # 그 복장에 그 슬롯이 없다(예: 상의만 있는 복장)
		_put(ss, e)
		_worn[ss] = outfit_json
		done = true
	return done


## 벗긴다. "" = 전부(내복)
func take_off(slot: String = "") -> void:
	if _model == null:
		return
	for s in (WEAR_SLOTS if slot == "" else [slot]):
		var ss := String(s)
		if not WEAR_SLOTS.has(ss):
			continue
		_put(ss, _body)
		_worn.erase(ss)


## 그 슬롯에 입은 복장(outfit.json 경로). 기본 몸이면 ""
func worn(slot: String) -> String:
	return String(_worn.get(slot, ""))


## 슬롯 노드에 그 모델의 슬롯 메시를 끼운다
func _put(slot: String, e: Dictionary) -> void:
	var mi: MeshInstance3D = _slot_mi.get(slot, null)
	if mi == null:
		return
	mi.mesh = (e["meshes"] as Dictionary).get(slot, null)
	mi.skin = _skin_for(e)
	_apply_params(mi)


## 복장 Skin 의 바인드(뼈 이름 · 바인드 자세)가 몸 것과 같으면 몸 Skin 을 같이 쓴다 — 뼈대 연결(SkinReference)이 병사마다 하나
func _skin_for(e: Dictionary) -> Skin:
	var mine: Skin = _body.get("skin", null)
	var theirs: Skin = e.get("skin", null)
	if String(e.get("key", "")) == String(_body.get("key", "")) or mine == null or theirs == null or mine == theirs:
		return theirs if theirs != null else mine
	var key := "%d|%d" % [mine.get_instance_id(), theirs.get_instance_id()]
	if not _skin_same.has(key):
		_skin_same[key] = _skins_equal(mine, theirs)
	return mine if bool(_skin_same[key]) else theirs


static func _skins_equal(a: Skin, b: Skin) -> bool:
	if a.get_bind_count() != b.get_bind_count():
		return false
	for i in a.get_bind_count():
		if a.get_bind_bone(i) != b.get_bind_bone(i) or a.get_bind_name(i) != b.get_bind_name(i):
			return false
		var pa := a.get_bind_pose(i)
		var pb := b.get_bind_pose(i)
		if pa.origin.distance_to(pb.origin) > 1e-4:
			return false
		for k in 3:
			if pa.basis[k].distance_to(pb.basis[k]) > 1e-4:
				return false
	return true


# ---------------------------------------------------------------- 동작 · 노드

## AnimationPlayer 의 기본("") 라이브러리를 바꿔 끼운다(A 갈래가 내보낸 동작 묶음 — 트랙 %GeneralSkeleton:<뼈>). 여러 병사가 같은 라이브러리를 같이 써도 된다
func set_motions(lib: AnimationLibrary) -> void:
	if _ap == null or lib == null:
		return
	if _ap.has_animation_library(""):
		_ap.remove_animation_library("")
	_ap.add_animation_library("", lib)


func get_animation_player() -> AnimationPlayer:
	return _ap


func get_skeleton() -> Skeleton3D:
	return _skel


## 슬롯 노드(MeshInstance3D) — 시험 · 효과용
func get_slot_node(slot: String) -> MeshInstance3D:
	return _slot_mi.get(slot, null)


## 몸 모델의 키(m) — 바인드(T-포즈) 자세의 높이. 게임 크기 맞추기: scale = 원하는 키 / model_height()
func model_height() -> float:
	return float(_body.get("height", 0.0))


## 몸 모델의 바인드 자세 경계 상자(이 노드 공간, 배율 전)
func model_aabb() -> AABB:
	return _body.get("aabb", AABB())


## 지금 조립한 몸 모델 경로(setup 에 준 것)
func body_path() -> String:
	return _body_path


## 몸 캐시 항목(DRGripFit · 시험용) — {model, meshes, skin, split, rig, aabb, height}
func get_body_entry() -> Dictionary:
	return _body


# ---------------------------------------------------------------- 색 · 사라지기

## 색 곱(기본 흰색). 죽은 병사 어둡게 등 — 재질은 그대로(공유), 이 병사의 instance uniform 만
func set_tint(c: Color) -> void:
	_tint = c
	for mi in _geometry():
		mi.set_instance_shader_parameter("tint", c)


func get_tint() -> Color:
	return _tint


## 1 = 보임 → 0 = 사라짐(4x4 바이어 디더로 픽셀을 버린다). 0 이면 모델을 아예 안 그린다(visible = false)
func set_fade(f: float) -> void:
	_fade = clampf(f, 0.0, 1.0)
	for mi in _geometry():
		mi.set_instance_shader_parameter("fade", _fade)
	if _model != null:
		_model.visible = _fade > 0.0
	for s in _sockets:                     # 소켓 장비(무기 · 헬멧)도 같이 — 몸 모델 밖에 있다
		if is_instance_valid(s):
			s.visible = _fade > 0.0


func get_fade() -> float:
	return _fade


## 그림자 드리우기(기본 끔 — 조명 없는 도트 셰이더라 받지는 않는다. 바닥에 그림자가 필요하면 켠다)
func set_cast_shadow(on: bool) -> void:
	_cast_shadow = on
	_apply_shadow()


func _apply_shadow() -> void:
	var m := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for mi in _geometry():
		mi.cast_shadow = m


func _apply_params(mi: MeshInstance3D) -> void:
	mi.set_instance_shader_parameter("tint", _tint)
	mi.set_instance_shader_parameter("fade", _fade)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _geometry() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for s in SLOTS:
		var mi: MeshInstance3D = _slot_mi.get(s, null)
		if mi != null:
			out.append(mi)
	if _weapon_mi != null and is_instance_valid(_weapon_mi):
		out.append(_weapon_mi)
	for mi in _equip_mis:                  # 소켓 장비 중 도트 재질을 입힌 메시
		if is_instance_valid(mi):
			out.append(mi)
	return out


## 셰이더 공통 값(bands · ambient · light_wrap · light_dir · rim · inside_shade)을 모든 병사의 재질에 한꺼번에. 준 키만 바뀐다
static func set_shading(values: Dictionary) -> void:
	for k in values.keys():
		_shading[String(k)] = values[k]
	for sm in _mats.values():
		_apply_shading(sm as ShaderMaterial)


static func get_shading() -> Dictionary:
	return _shading.duplicate()


static func _apply_shading(sm: ShaderMaterial) -> void:
	for k in _shading.keys():
		sm.set_shader_parameter(String(k), _shading[k])


## 원래 재질 → 공유 dot_char 재질(albedo 색 · 텍스처를 옮긴다). 같은 원래 재질이면 같은 객체
static func char_material(src: Material) -> ShaderMaterial:
	if _mats.has(src):
		return _mats[src]
	if _shader == null:
		_shader = load(SHADER_PATH) as Shader
	var sm := ShaderMaterial.new()
	sm.shader = _shader
	var col := Color(0.8, 0.8, 0.8, 1.0)
	if src is BaseMaterial3D:
		var bm := src as BaseMaterial3D
		col = bm.albedo_color
		if bm.albedo_texture != null:
			sm.set_shader_parameter("albedo_tex", bm.albedo_texture)
			sm.set_shader_parameter("use_tex", true)
	sm.set_shader_parameter("albedo_color", col)
	_apply_shading(sm)
	_mats[src] = sm
	return sm


# ---------------------------------------------------------------- 나누기 캐시

## 그 모델을 그 슬롯 표로 나눈 것(처음 한 번만 나누고 이후는 캐시). table 이 비면 기본 표(DRSlotMesh.DEFAULT_SLOTS)
static func load_entry(glb: String, table: Dictionary = {}) -> Dictionary:
	var tbl: Dictionary = table if not table.is_empty() else DRSlotMesh.DEFAULT_SLOTS
	var key := _entry_key(glb, tbl)
	if _entries.has(key):
		return _entries[key]
	var ps := load(glb) as PackedScene
	if ps == null:
		push_error("[DRCharacter3D] 모델을 열 수 없습니다: %s" % glb)
		return {}
	var inst := ps.instantiate()
	var skel := DRBaker._find_node(inst, "Skeleton3D") as Skeleton3D
	var mi := DRBaker._find_skinned_mesh(inst)
	if skel == null or mi == null:
		push_error("[DRCharacter3D] 스킨드 메시 · 뼈대가 없습니다: %s" % glb)
		inst.free()
		return {}
	var res := DRSlotMesh.split(mi, skel, DRPartProfile.humanoid(), tbl, DRPartOverrides.load_for(glb))
	if res.meshes.is_empty():
		push_error("[DRCharacter3D] 슬롯 나누기 결과가 비었습니다: %s" % glb)
		inst.free()
		return {}
	for s in res.meshes.keys():
		var am: ArrayMesh = res.meshes[s]
		for si in am.get_surface_count():
			am.surface_set_material(si, char_material(am.surface_get_material(si)))
	var aabb: AABB = DRBaker._xform_to(inst, mi) * mi.get_aabb()
	var e := {
		"key": key, "model": glb, "meshes": res.meshes, "skin": mi.skin, "split": res,
		"rig": DRRigModel.build(skel, res.bone_part, res.part_bones, res.weighted_bones),
		"aabb": aabb, "height": aabb.size.y,
	}
	inst.free()
	if tbl != DRSlotMesh.DEFAULT_SLOTS and _table_sig(tbl) != _table_sig(DRSlotMesh.DEFAULT_SLOTS):
		push_warning("[DRCharacter3D] %s 의 슬롯 표가 기본 몸과 다릅니다 — 경계가 기본 몸과 안 맞아 틈 · 겹침이 생길 수 있음" % glb)
	_entries[key] = e
	return e


static func _entry_key(glb: String, tbl: Dictionary) -> String:
	var pj := DRPartOverrides.path_for(glb)
	if not _md5_cache.has(pj):
		_md5_cache[pj] = FileAccess.get_md5(pj) if FileAccess.file_exists(pj) else ""
	return "%s|%s|%s" % [glb, _table_sig(tbl), _md5_cache[pj]]


static func _table_sig(tbl: Dictionary) -> String:
	var keys := tbl.keys()
	keys.sort()
	var out := PackedStringArray()
	for k in keys:
		out.append("%s=%s" % [k, DRSlotMesh.slot_of(String(k), tbl)])
	return ",".join(out)


## 캐시를 비운다(모델 · parts.json 을 고친 뒤 다시 나누게). 이미 만든 병사는 옛 메시를 계속 쓴다
static func clear_cache() -> void:
	_entries.clear()
	_weapons.clear()
	_skin_same.clear()
	_json_cache.clear()
	_md5_cache.clear()


## JSON 파일(outfit.json · asset.json)을 읽는다 — 경로마다 한 번(캐시). 고친 파일을 다시 읽으려면 clear_cache()
static func _read_json(path: String) -> Dictionary:
	if _json_cache.has(path):
		return _json_cache[path]
	var out := {}
	if path != "" and FileAccess.file_exists(path):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if v is Dictionary:
			out = v
	_json_cache[path] = out
	return out


# ---------------------------------------------------------------- 무기(옛 방식 — weapon_asset)

## (옛 방식 — 10-16 부터 무기는 소켓 노드. 소켓 무기가 없을 때 weapon_asset 칸으로만 쓴다)
## 무기를 든다 — asset.json 의 "equip"(장비 굽기 창이 저장한 그립)대로 2D 장비 굽기와 **같은 자리**:
## 붙일 파트(R_Hand)의 맨 위 뼈에 BoneAttachment3D, 그 아래 무기 = compose_grip(set_name) × weapon_scale(DREquipBaker.place_weapon 과 같은 식).
## set_name = 2D 세트 이름(그 세트의 조정 set_adjust 까지 더함, "" = 공통 조정만). hidden 노드(탄 클립 등)는 뺀다.
## ⚠ kar98k 의 저장 그립은 달리기 자세(Sprint)에서 잡힌 것이라(10-15 확인) 소총 동작에서 왼손이 총에 안 닿는다 —
##   DRGripFit.apply(ch) / apply_anim(ch, 동작) 으로 지금 몸 · 지금 동작에 다시 맞출 것.
func attach_weapon(asset_json: String, set_name: String = "") -> bool:
	detach_weapon()
	if _model == null:
		push_error("[DRCharacter3D] setup() 을 먼저 부르세요")
		return false
	var w := load_weapon_entry(asset_json)
	if w.is_empty():
		return false
	var rig: DRRigModel = _body.get("rig", null)
	var p: DRRigModel.Part = rig.parts.get(String(w["part"]), null) if rig != null else null
	if p == null or p.root_bone < 0:
		push_warning("[DRCharacter3D] 무기를 붙일 파트가 몸에 없습니다: %s" % String(w["part"]))
		return false
	_mount = BoneAttachment3D.new()
	_mount.name = "WeaponMount"
	_skel.add_child(_mount)
	_mount.bone_name = _skel.get_bone_name(p.root_bone)
	_weapon_mi = MeshInstance3D.new()
	_weapon_mi.name = "Weapon"
	_weapon_mi.mesh = w["mesh"]
	_mount.add_child(_weapon_mi)
	_weapon = w
	set_weapon_grip((w["equip"] as DREquipBaker).compose_grip(set_name))
	_apply_params(_weapon_mi)
	return true


func detach_weapon() -> void:
	if _mount != null and is_instance_valid(_mount):
		if _mount.get_parent() != null:
			_mount.get_parent().remove_child(_mount)
		_mount.free()
	_mount = null
	_weapon_mi = null
	_weapon = {}


## 손 뼈 로컬 무기 변환(배율 전 — DREquipBaker.compose_grip 과 같은 뜻)을 바꾼다. DRGripFit 이 다시 맞춘 그립을 줄 때
func set_weapon_grip(g: Transform3D) -> void:
	_grip = g
	if _weapon_mi != null and is_instance_valid(_weapon_mi):
		var xf := g
		xf.basis = xf.basis * Basis.from_scale(Vector3.ONE * float(_weapon.get("scale", 1.0)))
		_weapon_mi.transform = xf


func get_weapon_grip() -> Transform3D:
	return _grip


## 든 무기 — 오른손 소켓의 장비(정석, 10-16). 없으면 옛 방식(weapon_asset)의 메시. 안 들었으면 null
func get_weapon_node() -> Node3D:
	if _sock_weapon != null and is_instance_valid(_sock_weapon):
		return _sock_weapon
	return _weapon_mi


## 무기가 붙은 BoneAttachment3D — 소켓(정석) 또는 옛 방식의 WeaponMount
func get_weapon_mount() -> BoneAttachment3D:
	if _sock_weapon != null and is_instance_valid(_sock_weapon):
		return _sock_weapon.get_parent() as BoneAttachment3D
	return _mount


## 든 무기의 캐시 항목(DRGripFit · 시험용). 안 들었으면 {}
func get_weapon_entry() -> Dictionary:
	return _weapon


## 무기 캐시 항목 — 숨김 노드를 뺀 무기 메시를 재질별로 합친 ArrayMesh 하나(병사마다 MeshInstance3D 하나 · 그리기 = 재질 수)
static func load_weapon_entry(asset_json: String) -> Dictionary:
	if _weapons.has(asset_json):
		return _weapons[asset_json]
	var eq: Dictionary = _read_json(asset_json).get("equip", {})
	if eq.is_empty():
		push_warning("[DRCharacter3D] asset.json 에 equip 칸이 없습니다(장비 굽기 창에서 그립을 먼저 저장): %s" % asset_json)
		return {}
	var eb := DREquipBaker.new()
	eb.from_dict(eq)                       # 그립 · 조정 · 숨김 · 무기 리소스(source) — 그립 계산은 이 객체의 compose_grip 을 그대로 쓴다
	if eb.weapon_res == null:
		push_warning("[DRCharacter3D] 무기 모델을 열 수 없습니다: %s" % String(eq.get("source", "")))
		return {}
	var root: Node3D = null
	if eb.weapon_res is PackedScene:
		root = (eb.weapon_res as PackedScene).instantiate() as Node3D
	elif eb.weapon_res is Mesh:
		root = Node3D.new()
		var one := MeshInstance3D.new()
		one.name = String(eq.get("source", "mesh")).get_file().get_basename()
		one.mesh = eb.weapon_res as Mesh
		root.add_child(one)
	if root == null:
		return {}
	# 재질별로 합친다(SurfaceTool.append_from 이 노드 변환까지 굽는다). 경계 상자 · 그립 점 어림은 DREquipBaker.grip_point_guess 와 같은 식
	var groups := {}        # 재질 -> SurfaceTool
	var order: Array = []
	var box := AABB()
	var first := true
	var node_boxes := {}
	for mi in DREquipBaker._meshes(root):
		if mi.mesh == null:
			continue
		var xf := DRBaker._xform_to(root, mi)
		var b: AABB = xf * mi.get_aabb()
		node_boxes[String(mi.name)] = b
		if eb.hidden_nodes.has(String(mi.name)):
			continue
		box = b if first else box.merge(b)
		first = false
		for si in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat := mi.get_active_material(si)
			if not groups.has(mat):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[mat] = st
				order.append(mat)
			(groups[mat] as SurfaceTool).append_from(mi.mesh, si, xf)
	root.free()
	var am := ArrayMesh.new()
	am.resource_name = "weapon_%s" % String(eq.get("id", "weapon"))
	for mat in order:
		var st: SurfaceTool = groups[mat]
		st.set_material(char_material(mat))
		st.commit(am)
	if am.get_surface_count() == 0:
		push_warning("[DRCharacter3D] 무기에 그릴 메시가 없습니다: %s" % asset_json)
		return {}
	var f := eb.forward.normalized()
	var gp := Vector3.ZERO
	if eb.grip_node != "" and node_boxes.has(eb.grip_node):
		gp = (node_boxes[eb.grip_node] as AABB).get_center()
	else:
		var half := box.size * 0.5
		gp = box.get_center() - f * (absf(f.dot(half)) * 0.3) - Vector3.UP * (half.y * 0.33)
	var w := {
		"asset": asset_json, "equip": eb, "eq": eq, "mesh": am, "aabb": box,
		"part": eb.attach_part, "support": eb.support_part, "scale": eb.weapon_scale,
		"forward": f, "grip_point": gp + eb.grip_offset,
	}
	_weapons[asset_json] = w
	return w


# ---------------------------------------------------------------- 소켓 · 장비(10-16, 3D 게임 정석)
## 사용자(10-16): "2번 탭은 장비 3D 모델 하이어라키에 접근해 맞추는 방식, 즉 3D 게임 방식의 정석으로. 나중에 헬멧도 모델링 head 에 꽂으면 되고."
## 소켓 = 이 노드 아래(몸 모델 밖)의 BoneAttachment3D — 씬에 실제로 든 노드라 씬 독 · 인스펙터에 보이고, 자식 프리팹(상속 씬)이
##   소켓을 더하거나 장비를 바꿀 수 있다(상속 노드는 지울 수 없어 부모 장비는 숨기고 새 장비를 넣는다 — 게임에서는 숨긴 장비를 지운다).
## 몸은 안에서(주인 없는 노드로) 조립하므로 조립할 때마다 소켓을 지금 뼈대에 다시 잇는다(use_external_skeleton + external_skeleton).
## 장비 = 소켓의 보이는 자식(모델 씬 인스턴스 — 무기 · 헬멧). 자리 · 회전은 소켓 기준으로 고정(에디터 기즈모 · ② 장비 탭 숫자).
## 왼손 = 장비 아래 표지(DRHandTarget3D 또는 이름 "왼손")에 왼팔 두 마디 IK. 내장 수정자만 쓴다(병사가 많아도 가볍게 — 10-16 실측
## 갱신 한 번에 잴 수 없을 만큼 작음):
##   DR_SocketRef(ModifierBoneTarget3D — 소켓 뼈를 수정자 차례 안에서 따라감. 소켓 노드는 갱신 끝에 옮겨져 목표로 쓰면 한 박자 늦다)
##     └ DR_LeftWrist(손목 목표 = 표지 − 손바닥 거리, 기저 = 표지 회전)
##   DR_LeftElbow(ModifierBoneTarget3D — 동작의 왼 팔꿈치 = 극. TwoBoneIK3D 는 극이 없으면 풀지 않는다 — 10-16 실측)
##   DR_LeftArmIK(TwoBoneIK3D 위팔 → 아래팔 → 손) · DR_LeftHandRot(CopyTransformModifier3D — 손 회전 = 표지 회전)
## 뼈대 수정자는 게임 · 미리보기 사본에서 "자세가 바뀔 때만"(MANUAL — step_motion 초당 12번) 돈다. 기본(IDLE)이면 멈춘 병사도
## 매 프레임 돈다(10-16 실측). 편집 중인 씬만 IDLE(기즈모로 표지를 끌 때 팔이 바로 따라오게).

const SUPPORT_NAME := "왼손"
const WEAPON_BONE := "RightHand"
const LEFT_ARM := ["LeftUpperArm", "LeftLowerArm", "LeftHand"]


## 소켓 · 장비 · 왼손 표지를 다시 찾아 지금 몸에 잇는다 — 조립 때 저절로, ② 장비 탭이 노드를 바꾼 뒤, 편집 중인 씬에서 구조가 바뀌면.
## 몸이 없으면(조립 전) 아무것도 안 한다
func refresh_equipment() -> void:
	_free_ik()
	_sockets.clear()
	_equip_mis.clear()
	_sock_weapon = null
	_support = null
	_support_sock = null
	if _skel == null or not is_instance_valid(_skel):
		return
	var edited := is_inside_tree() and is_part_of_edited_scene()
	for s in find_sockets(self, _model):
		if not _bind_socket(s):
			continue
		_sockets.append(s)
		for c in s.get_children():
			var e := c as Node3D
			if e == null:
				continue
			if not e.visible:
				if not Engine.is_editor_hint():
					e.queue_free()             # 게임: 자식 프리팹이 숨긴 부모 장비 — 병사마다 남기지 않는다
				continue
			_paint_equipment(e, edited)
			if _sock_weapon == null and s.bone_name == WEAPON_BONE:
				_sock_weapon = e
			if _support == null:
				_support = find_support(e)
				_support_sock = s if _support != null else null
	if _support != null:
		_make_ik(edited)
	_set_ik_weight(_support_weight(_motion))
	_equip_sig = _socket_sig()


## 이 노드 아래(skip — 몸 모델 — 빼고)의 소켓(BoneAttachment3D)을 씬 순서대로. 소켓 안으로는 더 내려가지 않는다
static func find_sockets(root: Node, skip: Node = null) -> Array[BoneAttachment3D]:
	var out: Array[BoneAttachment3D] = []
	_collect_sockets(root, skip, out)
	return out


static func _collect_sockets(n: Node, skip: Node, out: Array[BoneAttachment3D]) -> void:
	for c in n.get_children():
		if c == skip:
			continue
		if c is BoneAttachment3D:
			out.append(c as BoneAttachment3D)
		else:
			_collect_sockets(c, skip, out)


## 장비 아래 왼손 표지 — DRHandTarget3D 가 먼저, 없으면 이름이 "왼손" 인 Node3D(모델 씬 속에 들어 있어도 된다)
static func find_support(e: Node) -> Node3D:
	var by_name: Node3D = null
	var stack: Array[Node] = [e]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is DRHandTarget3D:
			return n as Node3D
		if by_name == null and n is Node3D and String(n.name) == SUPPORT_NAME:
			by_name = n as Node3D
		stack.append_array(n.get_children())
	return by_name


## 소켓을 지금 뼈대에 잇는다. 몸을 다시 조립했으면 옛 뼈대는 지워졌으므로 길을 비웠다가(옛 연결 표시를 풀고) 새 뼈대로 묶는다 —
## 길만 바꾸면 BoneAttachment3D 가 새 뼈대에서 옛 연결을 끊으려다 오류를 낸다
func _bind_socket(s: BoneAttachment3D) -> bool:
	var bi := _skel.find_bone(s.bone_name) if s.bone_name != "" else -1
	if bi < 0:
		push_warning("[DRCharacter3D] 소켓 %s 의 뼈 '%s' 가 몸에 없습니다" % [s.name, s.bone_name])
		return false
	if s.use_external_skeleton and s.get_skeleton() == _skel:
		# 길이 벌써 이 뼈대 — 묶인 채(다시 잇기)일 수도, 길만 맞고 안 묶였을 수도 있다: 조립된 씬을 pack 한 사본(① ② 미리보기) ·
		# 그 길이 저장된 씬은 몸을 조립하기 전에 트리에 들어가 못 묶인다(10-16 — 그대로 두면 소켓이 뼈를 안 따라가 3 cm 어긋남).
		# 뼈 이름을 다시 넣으면 묶였으면 풀고 다시 묶는다
		s.bone_name = s.bone_name
		return true
	s.external_skeleton = NodePath()
	s.use_external_skeleton = true
	s.external_skeleton = s.get_path_to(_skel)
	s.bone_name = s.bone_name                # 새 뼈대에서 뼈 번호를 다시 찾고 묶는다(몸 모델이 바뀌어도)
	return true


## 장비 메시에 도트 재질(char_material — 병사끼리 공유) · tint · fade · 그림자. 숨긴 부품(탄 클립 등)은 건너뛴다.
## 편집 중인 씬이 직접 가진 메시(owner = 이 노드)는 건드리지 않는다 — 씬에 저장되므로. 모델 씬 인스턴스 속 메시는 저장되지 않는다(10-16 확인)
func _paint_equipment(e: Node3D, edited: bool) -> void:
	var stack: Array[Node] = [e]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and not (n as Node3D).visible:
			continue
		stack.append_array(n.get_children())
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null or (edited and mi.owner == self):
			continue
		for si in mi.mesh.get_surface_count():
			var cur := mi.get_surface_override_material(si)
			if cur is ShaderMaterial and _shader != null and (cur as ShaderMaterial).shader == _shader:
				continue                        # 이미 입힘(다시 잇기)
			var src: Material = mi.mesh.surface_get_material(si)
			if src == null:
				src = cur
			mi.set_surface_override_material(si, char_material(src))
		_apply_params(mi)
		_equip_mis.append(mi)


## 왼팔 IK 수정자를 뼈대 아래에 만든다(주인 없는 노드 — 저장 안 됨, 몸을 다시 조립하면 같이 사라진다)
func _make_ik(edited: bool) -> void:
	var ids := PackedInt32Array()
	for b in LEFT_ARM:
		ids.append(_skel.find_bone(String(b)))
	ids.append(_skel.find_bone(_support_sock.bone_name))
	if ids.has(-1):
		push_warning("[DRCharacter3D] 왼팔 IK 뼈(%s)가 몸에 없습니다 — 왼손 표지를 쓰지 않음" % ", ".join(PackedStringArray(LEFT_ARM)))
		return
	_ik_bones = ids
	var rig: DRRigModel = _body.get("rig", null)
	var part: DRRigModel.Part = rig.parts.get("L_Hand", null) if rig != null else null
	_palm_l = part.tail_local * 0.5 if part != null else Vector3.ZERO
	_ik_ref = ModifierBoneTarget3D.new()
	_ik_ref.name = "DR_SocketRef"
	_skel.add_child(_ik_ref)
	_ik_ref.bone_name = _support_sock.bone_name
	_ik_wrist = Node3D.new()
	_ik_wrist.name = "DR_LeftWrist"
	_ik_ref.add_child(_ik_wrist)
	_ik_pole = ModifierBoneTarget3D.new()
	_ik_pole.name = "DR_LeftElbow"
	_skel.add_child(_ik_pole)
	_ik_pole.bone_name = String(LEFT_ARM[1])
	_ik = TwoBoneIK3D.new()
	_ik.name = "DR_LeftArmIK"
	_skel.add_child(_ik)
	_ik.setting_count = 1
	_ik.set_root_bone_name(0, String(LEFT_ARM[0]))
	_ik.set_middle_bone_name(0, String(LEFT_ARM[1]))
	_ik.set_end_bone_name(0, String(LEFT_ARM[2]))
	_ik.set_target_node(0, _ik.get_path_to(_ik_wrist))
	_ik.set_pole_node(0, _ik.get_path_to(_ik_pole))
	_ik_rot = CopyTransformModifier3D.new()
	_ik_rot.name = "DR_LeftHandRot"
	_skel.add_child(_ik_rot)
	_ik_rot.setting_count = 1
	_ik_rot.set_apply_bone_name(0, String(LEFT_ARM[2]))
	_ik_rot.set_reference_type(0, BoneConstraint3D.REFERENCE_TYPE_NODE)
	_ik_rot.set_reference_node(0, _ik_rot.get_path_to(_ik_wrist))
	_ik_rot.set_copy_flags(0, CopyTransformModifier3D.TRANSFORM_FLAG_ROTATION)
	_skel.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE if edited else Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	sync_support()


func _free_ik() -> void:
	for n in [_ik_rot, _ik, _ik_pole, _ik_ref]:
		if n != null and is_instance_valid(n):
			var nn := n as Node
			if nn.get_parent() != null:
				nn.get_parent().remove_child(nn)
			nn.free()                          # 바로 — 같은 이름으로 다시 만들 때 겹치지 않게
	_ik_ref = null
	_ik_wrist = null
	_ik_pole = null
	_ik = null
	_ik_rot = null
	_ik_bones = PackedInt32Array()
	_ik_w = 0.0


## 소켓 → 왼손 표지 변환을 IK 목표에 옮긴다 — 표지 · 장비를 옮긴 뒤(② 장비 탭이 부른다 · 편집 중인 씬은 매 프레임). 게임은 조립 때 한 번
func sync_support() -> void:
	if _support == null or _ik_wrist == null or not is_instance_valid(_support) or not is_instance_valid(_ik_wrist):
		return
	var rel := Transform3D.IDENTITY
	var n: Node = _support
	while n != null and n != _support_sock:
		if n is Node3D:
			rel = (n as Node3D).transform * rel
		n = n.get_parent()
	rel.basis = rel.basis.orthonormalized()     # 장비 배율은 뺀다(손 회전 · 손바닥 거리는 뼈대 단위)
	_ik_rel = rel
	var t := rel * Transform3D(Basis.IDENTITY, -_palm_l)
	if not t.is_equal_approx(_ik_wrist.transform):
		_ik_wrist.transform = t


## 그 동작의 왼손 IK 비중 — 표지(DRHandTarget3D)의 동작별 비중. 동작이 없으면(레스트 자세) 0
func _support_weight(motion: String) -> float:
	if _support == null or _ik == null or motion == "":
		return 0.0
	if _support is DRHandTarget3D:
		return (_support as DRHandTarget3D).weight_for(motion)
	return 1.0


func _set_ik_weight(w: float) -> void:
	_ik_w = w
	if _ik == null or not is_instance_valid(_ik):
		return
	var on := w > 0.001
	_ik.active = on
	_ik_rot.active = on
	if on:
		_ik.influence = w
		_ik_rot.influence = w


## 편집 중인 씬(에디터): 기즈모로 장비 · 표지를 옮기면 IK 목표를 바로 맞추고, 소켓 · 장비를 더하거나 빼면(되돌리기 포함) 다시 잇는다
func _editor_follow(delta: float) -> void:
	if not _built:
		return
	sync_support()
	_equip_poll -= delta
	if _equip_poll <= 0.0:
		_equip_poll = 0.25
		if _socket_sig() != _equip_sig:
			refresh_equipment()


## 소켓 구조(소켓 · 뼈 · 보이는 장비 · 표지) — 바뀌면 다시 잇는다
func _socket_sig() -> String:
	var parts := PackedStringArray()
	for s in find_sockets(self, _model):
		parts.append("%s>%s" % [s.name, s.bone_name])
		for c in s.get_children():
			if c is Node3D:
				var m := find_support(c)
				parts.append("%d|%s|%s" % [c.get_instance_id(), str((c as Node3D).visible), str(m.get_instance_id()) if m != null else "-"])
	return ";".join(parts)


## 지금 묶인 소켓들
func get_sockets() -> Array[BoneAttachment3D]:
	return _sockets.duplicate()


## 왼손 표지(없으면 null)
func get_support_marker() -> Node3D:
	return _support


## 왼팔 IK(TwoBoneIK3D, 표지가 없으면 null) · 지금 비중
func get_left_arm_ik() -> TwoBoneIK3D:
	return _ik


func get_ik_weight() -> float:
	return _ik_w


## 소켓 장비 중 도트 재질을 입힌 메시(검사용)
func get_equipment_meshes() -> Array[MeshInstance3D]:
	return _equip_mis.duplicate()


## 지금 뼈 자세 그대로 왼 손바닥 ↔ 표지를 잰다(뼈대 공간) — skeleton_updated 신호 안에서 부르면 IK 뒤, 밖에서 부르면 동작 자세(수정자 전 —
## 갱신이 끝나면 뼈대가 동작 자세로 되돌아가 있다). {dist(m), rot(도), palm, target, hand(왼손 뼈 변환)} · 표지가 없으면 {}
func support_now() -> Dictionary:
	if _ik == null or _skel == null or _ik_bones.size() < 4:
		return {}
	var hand := _skel.get_bone_global_pose(_ik_bones[2])
	var tgt := _skel.get_bone_global_pose(_ik_bones[3]) * _ik_rel     # 손바닥이 올 자리(원점) · 손 회전(기저)
	var palm := hand * _palm_l
	return {
		"dist": palm.distance_to(tgt.origin), "palm": palm, "target": tgt.origin, "hand": hand,
		"rot": rad_to_deg(hand.basis.orthonormalized().get_rotation_quaternion().angle_to(tgt.basis.get_rotation_quaternion())),
	}


## 지금 자세에서 왼손이 표지에 얼마나 붙었나(② 장비 탭 · 검사) — 뼈대를 바로 한 번 갱신해 IK 뒤 손을 읽는다(자세는 그대로).
## {ik: IK 뒤 손바닥 ↔ 표지(m), raw: 동작 그대로의 손바닥 ↔ 표지(m), rot: IK 뒤 손 회전 ↔ 표지 회전(도),
##  reach: 어깨 → 손목 목표 / 팔 길이(1 넘으면 안 닿음), weight: 지금 IK 비중, palm · target(뼈대 공간)}. 표지가 없으면 {}
func support_report() -> Dictionary:
	if _ik == null or _skel == null or _ik_bones.size() < 4:
		return {}
	sync_support()
	var hb := _ik_bones[2]
	var raw := support_now()                                          # 수정자 전 = 동작 자세
	var rec := {}
	var cb := func() -> void: rec["ik"] = support_now()
	_skel.skeleton_updated.connect(cb)
	_skel.set_bone_pose_rotation(hb, _skel.get_bone_pose_rotation(hb))   # 갱신할 거리를 만든다(값은 그대로)
	_skel.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	_skel.skeleton_updated.disconnect(cb)
	var ik: Dictionary = rec.get("ik", raw)
	var sh := _skel.get_bone_global_pose(_ik_bones[0]).origin
	var el := _skel.get_bone_global_pose(_ik_bones[1]).origin
	var arm := sh.distance_to(el) + el.distance_to((raw["hand"] as Transform3D).origin)
	var wrist_t := (_skel.get_bone_global_pose(_ik_bones[3]) * _ik_rel) * -_palm_l     # 손목 목표 = 표지 − 손바닥 거리(표지 회전으로)
	return {
		"ik": float(ik["dist"]), "raw": float(raw["dist"]), "rot": float(ik["rot"]),
		"reach": sh.distance_to(wrist_t) / maxf(arm, 1e-5),
		"weight": _ik_w, "palm": ik["palm"], "target": ik["target"],
	}
