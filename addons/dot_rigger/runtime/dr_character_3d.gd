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
##     │   │    └ DR_AimSolver(무기를 들었을 때 · 맨 앞 — 조준 IK, 10-21) · DR_Aim<손>Elbow · ArmIK · HandRot(조준 팔) · DR_HitSolver(IK 피격, 10-21) · DR_GripSolver(받침대가 있을 때) · DR_<손>Ref · DR_<손>Elbow · DR_<손>ArmIK · DR_<손>HandRot (손 표지마다 — 팔 IK 수정자) · DR_HitArmSolver(손 IK 로 잡은 팔의 피격, 맨 뒤)
##     │   └ AnimationPlayer
##     ├ 오른손 (BoneAttachment3D = 소켓, 씬에 든 노드 — 10-16)  └ kar98k (장비 = 모델 씬 인스턴스)  └ 왼손 (DRHandTarget3D 표지)
##     └ 양손 (DRGripMount3D = 받침대 — 두 손 사이 보간 · 땅 고정, 10-16)  └ mg42  └ 오른손 · 왼손 (표지 — 두 손 다 IK)
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
##   ch.set_aim_target(적_가슴_세상좌표)       # 사격 · 조준 동작에서 팔(견착) · 허리로 총구 높낮이를 그리로(조준 IK, 10-21) · clear_aim_target()
##   ch.hit_react(맞은_점, 총알_방향)          # IK 피격 — 맞은 부위가 젖혀졌다 돌아옴(10-21). 자세별 피격 동작은 게임 화면이 hit_anim_chance 로

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
## 명암 매끈함 기본값(m) — DRDotStyle.normal_smooth_cm 의 기본과 같다(스타일을 안 넣은 곳 — ③ 탭 · 시험 도구 — 도 같은 모습)
const DEFAULT_SMOOTH_M := 0.06
## 메시를 나눌 때 노멀을 고르게 펴는 반경(m, DRSlotMesh.smooth_normals). 바꿀 때는 set_normal_smooth() — 그 뒤에 조립하는 병사부터
static var _smooth_m := DEFAULT_SMOOTH_M
## 나눈 모델 캐시: 키(glb|슬롯 표|parts.json md5|명암 매끈함) -> {model, meshes{슬롯: ArrayMesh}, skin, split(DRSlotMesh.Result), rig(DRRigModel), aabb, height}
static var _entries := {}
## 원래 재질(Material, 없으면 null) -> 공유 ShaderMaterial(dot_char)
static var _mats := {}
## 무기 캐시: asset.json 경로 -> {asset, equip(DREquipBaker — 그립 계산만), mesh(ArrayMesh, 숨김 노드 뺀 합본), part, support, scale, grip_point}
static var _weapons := {}
## Skin 두 개의 바인드가 같은지(인스턴스 id 쌍 -> bool) — 같으면 복장 슬롯도 몸의 Skin 을 써서 뼈대 연결(SkinReference)이 하나로 준다
static var _skin_same := {}
## 파일 읽기 캐시(10-16) — 병사마다 · 옷을 입힐 때마다 outfit.json 을 다시 읽고 parts.json 의 md5 를 다시 재지 않게. clear_cache() 로 비운다
static var _json_cache := {}         # 경로 -> Dictionary
## 무기 메시에서 잰 총구 · 견착점(조준 IK, 10-21): 메시 묶음 열쇠 -> [총구, 견착점](무기 로컬) — 병사마다 다시 재지 않게
static var _muzzle_geo := {}
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

@export_group("조준")
## 조준 IK(10-21) — 사격 · 조준 동작에서 표적 높이에 맞춰 총구를 위아래로 든다(팔 · 허리). 표적은 게임이 준다(set_aim_target).
## 좌우는 안 돈다(횡스크롤 — 사용자 10-21 "옆은 필요 없는 것 같아"). 각도는 모두 "그 동작이 원래 겨눈 높이"에서 더 드는 각.
@export var aim_enabled := true
## 위로 최대 각(°) — 동작이 원래 겨눈 높이에서 총구를 더 들 수 있는 각. 표적이 더 높으면 여기서 멈춘다(40° 면 몸이 뒤로 크게 젖혀져 기본 30°)
@export_range(0.0, 80.0, 1.0, "suffix:°") var aim_up_deg := 30.0
## 아래로 최대 각(°) — 동작이 원래 겨눈 높이에서 총구를 더 내릴 수 있는 각
@export_range(0.0, 80.0, 1.0, "suffix:°") var aim_down_deg := 30.0
## 빠르기(초당 °) — 표적 높이가 바뀔 때 총구가 따라가는 속도
@export_range(30.0, 1440.0, 10.0, "suffix:°/s") var aim_speed_deg := 240.0
## 팔 몫(0 ~ 1) — 드는 각 중 팔이 맡는 비율: 개머리판을 어깨에 댄 채(견착점 축) 두 팔이 총을 들고 내린다. 나머지는 허리 · 가슴이 숙이고 젖힌다.
## 사용자(10-21): "허리가 들리는 것도 있지만 진짜 조준을 할 때 팔 부분이 영향이 제일 많이 가잖아 — 양팔로 인한 견착 위치에 따라"
@export_range(0.0, 1.0, 0.05) var aim_arm_share := 0.7
## 동작마다 조준 비중(0 = 동작 그대로 · 1 = 총구가 표적으로). 없는 동작 = 동작 표에서 "사격" · "조준" 상태에 든 동작이면 1, 아니면 0
## (상하체 합성 "A+B" 는 제 것이 없으면 상체 B 것) — ② 장비 탭 동작 표의 "조준" 칸
@export var aim_motion_weights: Dictionary[String, float] = {}

@export_group("피격")
## 피격 반응(10-21). 사용자: "idle 히트 · 앉기 히트 · 누워서 히트 애니메이션을 쓰되, IK 히트 토글을 누르면 부위별 맞는 레이 히트 기준으로
## 맞는 IK 애니메이션이 보간되는 것도 · 이 애니메이션이 출력될 확률을 정하는 인풋 필드"
## 피격 동작 확률(0 ~ 1) — 맞을 때 자세별 피격 동작(동작 표의 피격 · 피격+앉기 · 피격+엎드림)을 틀 확률. 안 틀면 하던 동작 그대로(IK 피격만). 게임 화면이 굴린다
@export_range(0.0, 1.0, 0.05) var hit_anim_chance := 0.5
## 피격 동작 최대 초 — 피격 동작(Idle_Hit 2.3 초 등)을 틀면 이만큼까지 보여 주고 다음 동작으로 넘긴다(그 전이라도 쓰러짐 · 패닉 · 걷기 · 사격이 오면 바로).
## 시뮬의 피격 경직(0.25 초)과 따로 — 화면만
@export_range(0.25, 3.0, 0.05, "suffix:s") var hit_anim_max_sec := 1.0
## IK 피격 — 총알이 맞은 점에서 가장 가까운 부위(머리 · 가슴 · 배 · 팔 · 다리)가 총알 방향으로 젖혀졌다 돌아온다. 동작 위에 덧씌움(피격 동작을 틀어도 같이)
@export var hit_ik_enabled := true
## IK 세기 — 맞은 부위가 젖혀지는 최대 각(°)
@export_range(0.0, 60.0, 1.0, "suffix:°") var hit_ik_deg := 15.0
## IK 길이 — 젖혀졌다 돌아오는 시간(초)
@export_range(0.1, 1.5, 0.05, "suffix:s") var hit_ik_sec := 0.4

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
var _mounts: Array[DRGripMount3D] = []         # 받침대(두 손 사이 · 고정 — 10-16 양손)
var _equip_mis: Array[MeshInstance3D] = []     # 장비 메시 중 도트 재질을 입힌 것(tint · fade · 그림자를 같이)
var _sock_weapon: Node3D = null                # 든 무기(손 표지가 있는 장비 → 없으면 오른손 소켓의 장비)
var _hands: Array = [null, null]               # 손마다(0 = 왼손 · 1 = 오른손) HandIK — 그 손 표지가 있고 그 손이 받침이 아닐 때만
var _solver: SkeletonModifier3D = null         # 받침대 풀이(뼈대 수정자 차례 맨 앞 — 받침대가 있을 때만)
var _pose_equips: Array[PoseEquip] = []        # 동작별 무기 자리를 얹는 장비(게임 · 미리보기 사본 — 편집 중인 씬은 기본 자리 그대로)
var _equip_sig := ""                           # 편집 중인 씬에서 받침 구조가 바뀌었나(에디터만)
var _saved_skel_paths := {}                    # 저장하는 동안 비운 소켓의 뼈대 길(소켓 -> 길)
var _saved_mount_xf := {}                      # 저장하는 동안 원점에 둔 두 손 사이 받침대의 자리(받침대 -> 변환)
var _equip_poll := 0.0
# 조준 IK(10-21) — 아래 "조준 IK" 절
var _aim_solver: SkeletonModifier3D = null
var _aim_bones := PackedInt32Array()           # 돌릴 뼈(허리 → 가슴, 아래부터)
var _aim_shares := PackedFloat32Array()        # 뼈마다 몫(합 1)
var _muzzle := []                              # 무기 로컬 총구 [자리, 방향] — 무기가 없으면 []
var _aim_has := false                          # 표적이 있나
var _aim_point := Vector3.ZERO                 # 표적(세상 좌표)
var _aim_by_angle := false                     # 표적 대신 각으로(② 탭 미리보기 — set_aim_elevation)
var _aim_elev := 0.0                           # 그 각(라디안) = 총구 높낮이(수평 = 0, 위 +)
var _aim_on := 0.0                             # 표적이 있는 정도(나타나고 사라질 때 섞음)
var _aim_w := 0.0                              # 지금 동작의 조준 비중(동작이 바뀔 때 _grip_t 로 섞음)
var _aim_w_from := 0.0
var _aim_w_to := 0.0
var _aim_cur := 0.0                            # 지금 든 각(라디안, 비중 곱하기 전 — 위 +)
var _aim_valid := false                        # _aim_cur 가 이어 가는 값인가(아니면 다음 풀이에서 바로 그 값으로)
var _aim_dt := 0.0                             # 지난 풀이 뒤 흐른 시간(step_motion 이 모은다)
var _aim_refs := {}                            # 동작 -> [총구 자리, 방향](캐릭터 공간, 동작 그대로 시점 평균) 또는 [](조준 못 함)
var _aim_defaults := {}                        # 동작 -> 동작 표로 정한 기본 비중
var _anim_tracks := {}                         # Animation -> {뼈 번호: [위치, 회전, 크기 트랙](없으면 −1)}
var _aim_last := {}                            # 마지막 풀이(검사 · ② 탭) — aim_report
var _aim_arm_q := Quaternion.IDENTITY          # 이번 풀이의 팔 몫 돌림(뼈대 공간, 견착점 축) — 받침대 풀이가 두 손 사이 받침대에 얹는다
var _aim_arm_on := false
var _aim_hand: Node3D = null                   # 손 소켓 무기: 든 손의 목표(뼈대 공간) — 조준 팔 IK 가 따라감
var _aim_arm_pole: ModifierBoneTarget3D = null
var _aim_arm_ik: TwoBoneIK3D = null
var _aim_arm_rot: CopyTransformModifier3D = null
var _aim_arm_hand := -1                        # 그 손 뼈
var _aim_head := -1                            # 머리 뼈(팔이 든 각을 일부 따라감 — 뺨을 개머리판에)
# IK 피격(10-21) — 아래 "피격 반응" 절
var _hit_solver: SkeletonModifier3D = null
var _hits: Array[HitReaction] = []             # 지금 도는 반응(최대 HIT_MAX — 넘치면 오래된 것부터 뺌)
var _hit_dt := 0.0                             # 지난 풀이 뒤 흐른 시간(step_motion 이 모은다)
var _hit_post: SkeletonModifier3D = null        # 손 IK 로 잡은 팔의 피격 — 수정자 차례 맨 뒤


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
## 되돌릴 때는 길만 — 묶음(뼈대 신호 연결)은 그대로라 다시 묶으면 "이미 연결됨" 오류(10-16).
## 두 손 사이 받침대(DRGripMount3D HANDS)의 자리도 동작마다 계산되는 값이라 원점으로 저장한다(저장할 때마다 씬 파일이 바뀌지 않게)
func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_saved_skel_paths.clear()
		_saved_mount_xf.clear()
		for a in find_anchors(self, _model):          # 지금 씬에 든 받침(_sockets 는 다음 다시 잇기 전까지 방금 더하거나 뺀 것이 안 맞을 수 있다)
			if a is BoneAttachment3D and not (a as BoneAttachment3D).external_skeleton.is_empty():
				_saved_skel_paths[a] = (a as BoneAttachment3D).external_skeleton
				(a as BoneAttachment3D).external_skeleton = NodePath()
			elif a is DRGripMount3D and (a as DRGripMount3D).mode == DRGripMount3D.Mode.HANDS:
				_saved_mount_xf[a] = a.transform
				a.transform = Transform3D.IDENTITY
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		for s in _saved_skel_paths.keys():
			if is_instance_valid(s):
				(s as BoneAttachment3D).external_skeleton = _saved_skel_paths[s]
		for m in _saved_mount_xf.keys():
			if is_instance_valid(m):
				(m as Node3D).transform = _saved_mount_xf[m]
		_saved_skel_paths.clear()
		_saved_mount_xf.clear()


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
## 소켓 · 받침대 무기(정석, 10-16): 무기 자리는 받침 기준 기본 자리 × 그 동작의 동작별 자리(10-19, 장비 메타 — 없으면 기본 자리 그대로)이고,
##   그 동작의 손 IK 비중(손 표지마다 동작별 비중)과 함께 같은 시간 동안 옮긴다 — `_grip_t` 가 섞기 시간. 두 손 사이 받침대는 그 비중으로 잡은 손만 따른다(풀이 수정자).
## 옛 무기(weapon_asset): 그 동작에 맞춘 그립(DRGripFit — 동작마다 두 손에 다시 맞춘 것, 캐시)으로 같은 시간 동안 옮긴다.
func play_motion(motion: String, blend: float = 0.1) -> void:
	if _ap == null or not _ap.has_animation(motion):
		return
	var first := _motion == "" or not _ap.is_playing()
	_ap.play(motion, 0.0 if first else blend)
	if first:
		_ap.advance(0.0)                   # 처음 자세를 바로 — 안 그러면 다음 갱신까지 레스트(T자) 자세로 보인다
	_motion = motion
	var moving := _aim_offsets(motion, first or blend <= 0.0)
	if _sock_weapon != null or _has_hand_ik() or moving:
		if first or blend <= 0.0:
			for side in 2:
				_set_hand_weight(side, _hand_weight(side, motion))
			_aim_w = aim_weight_for(motion)
			_grip_t = -1.0
		else:
			for side in 2:
				var h: HandIK = _hands[side]
				if h != null:
					h.w_from = h.w
					h.w_to = _hand_weight(side, motion)
			_aim_w_from = _aim_w                   # 조준 비중도 손 IK 와 같은 시간 동안
			_aim_w_to = aim_weight_for(motion)
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
	_aim_dt += dt                              # 조준 수정자가 이번 갱신에 쓴다(빠르기 · 표적 섞기)
	_hit_dt += dt                              # IK 피격 수정자도
	_ap.advance(dt)
	if not _hits.is_empty() and _skel != null:  # 자세가 멈춰 있어도(끝난 동작 · 멈춤) 피격 반응은 흘러야 — 뼈대를 다시 풀게
		_skel.set_bone_pose_rotation(0, _skel.get_bone_pose_rotation(0))
	var wrapped := _ap.current_animation_position < before
	if _grip_t >= 0.0:
		_grip_t += dt
		var k := clampf(_grip_t / maxf(_grip_blend, 0.001), 0.0, 1.0)
		if _weapon_mi != null:
			set_weapon_grip(_grip_from.interpolate_with(_grip_to, k))
		for side in 2:
			var h: HandIK = _hands[side]
			if h != null:
				_set_hand_weight(side, lerpf(h.w_from, h.w_to, k))
		_aim_w = lerpf(_aim_w_from, _aim_w_to, k)
		var moved := false
		for pq in _pose_equips:
			if is_instance_valid(pq.e) and not pq.from.is_equal_approx(pq.to):
				pq.cur = pq.from.interpolate_with(pq.to, k)
				pq.e.transform = pq.base * pq.cur
				if k >= 1.0:
					pq.from = pq.to
				moved = true
		if moved:
			sync_support()                     # 장비가 움직였으니 손 IK 목표도(표지는 장비 아래)
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
	_aim_refs.clear()                          # 동작이 바뀌었으니 총구 기준도 다시
	_anim_tracks.clear()


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
	for s in _sockets:                     # 받침의 장비(무기 · 헬멧)도 같이 — 몸 모델 밖에 있다
		if is_instance_valid(s):
			s.visible = _fade > 0.0
	for m in _mounts:
		if is_instance_valid(m):
			m.visible = _fade > 0.0


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


## 명암 매끈함(m) — 메시를 나눌 때 노멀을 이 반경만큼 고르게 편다(10-16 저녁). 재질 값이 아니라 메시라서 **이 뒤에 조립하는 병사부터**
## 바뀐다(이미 있는 병사는 다시 조립해야 — ① 탭은 미리보기를 다시 만든다). 값이 바뀌었으면 true
static func set_normal_smooth(m: float) -> bool:
	m = maxf(m, 0.0)
	if is_equal_approx(m, _smooth_m):
		return false
	_smooth_m = m
	return true


static func normal_smooth() -> float:
	return _smooth_m


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
			# 안전 밉 지도(pipeline/safe_mip_map.py — 텍스처 옆 <이름>.safemip.png): 있으면 UV 조각 경계 근처에서 옆 조각 색이 안 섞이게(10-19)
			var sp := safe_mip_path(bm.albedo_texture.resource_path)
			if sp != "" and ResourceLoader.exists(sp):
				sm.set_shader_parameter("safe_tex", load(sp))
				sm.set_shader_parameter("use_safe", true)
	sm.set_shader_parameter("albedo_color", col)
	_apply_shading(sm)
	_mats[src] = sm
	return sm


## 그 텍스처의 안전 밉 지도 경로(없으면 ""). 같은 폴더 · 같은 이름 + .safemip.png
static func safe_mip_path(tex_path: String) -> String:
	if tex_path == "" or not tex_path.begins_with("res://") or tex_path.contains("::"):
		return ""
	return tex_path.get_basename() + ".safemip.png"


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
	var res := DRSlotMesh.split(mi, skel, DRPartProfile.humanoid(), tbl, DRPartOverrides.load_for(glb), true, true, _smooth_m)
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
	# 같은 모델 · 표의 다른 명암 매끈함 것은 뺀다(① 탭에서 값을 돌릴 때마다 캐시가 쌓이지 않게 — 쓰던 병사는 메시를 계속 쥐고 있다)
	var stem := key.substr(0, key.rfind("|") + 1)
	for k in _entries.keys():
		if String(k).begins_with(stem):
			_entries.erase(k)
	_entries[key] = e
	return e


static func _entry_key(glb: String, tbl: Dictionary) -> String:
	var pj := DRPartOverrides.path_for(glb)
	if not _md5_cache.has(pj):
		_md5_cache[pj] = FileAccess.get_md5(pj) if FileAccess.file_exists(pj) else ""
	return "%s|%s|%s|n%d" % [glb, _table_sig(tbl), _md5_cache[pj], roundi(_smooth_m * 1000.0)]


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
	_muzzle_geo.clear()


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


## 든 무기 — 손 표지가 있는 장비(없으면 오른손 소켓의 장비 — 정석, 10-16). 없으면 옛 방식(weapon_asset)의 메시. 안 들었으면 null
func get_weapon_node() -> Node3D:
	if _sock_weapon != null and is_instance_valid(_sock_weapon):
		return _sock_weapon
	return _weapon_mi


## 무기의 받침 — 소켓(BoneAttachment3D) · 받침대(DRGripMount3D) 또는 옛 방식의 WeaponMount
func get_weapon_mount() -> Node3D:
	if _sock_weapon != null and is_instance_valid(_sock_weapon):
		return _sock_weapon.get_parent() as Node3D
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
## 받침(장비를 고정하는 곳) = 이 노드 아래(몸 모델 밖)의
##   · 소켓(BoneAttachment3D) — 뼈 하나를 따라감(오른손 · 왼손 · 머리 · 가슴 …). 씬에 든 노드라 씬 독 · 인스펙터에 보이고, 자식 프리팹(상속 씬)이
##     소켓을 더하거나 장비를 바꿀 수 있다(상속 노드는 지울 수 없어 부모 장비는 숨기고 새 장비를 넣는다 — 게임에서는 숨긴 장비를 지운다).
##     몸은 안에서(주인 없는 노드로) 조립하므로 조립할 때마다 소켓을 지금 뼈대에 다시 잇는다(use_external_skeleton + external_skeleton).
##   · 받침대(DRGripMount3D, 10-16 양손) — 두 손 사이(보간) 또는 유닛(땅)에 고정. 자리는 수정자 차례 맨 앞의 풀이 수정자가 동작 자세로 계산한다.
## 장비 = 받침의 보이는 자식(모델 씬 인스턴스 — 무기 · 헬멧). 자리 · 회전은 받침 기준으로 고정(기즈모 · ② 장비 탭 숫자).
## 손 = 장비 아래 손 표지(DRHandTarget3D 왼손 · 오른손, 또는 이름 "왼손")에 그 팔 두 마디 IK — 받침이 그 손이면(오른손 소켓 무기의 오른손) 안 건다.
## 사용자(10-16): "오른손 · 왼손 · 양손 — 어느 부분(소켓)을 고정할지 … 무기를 움직이면 오른손도 따라가거나 양손이거나" →
##   오른손 소켓 = 왼손이 따라감 · 왼손 소켓 = 오른손이 따라감 · 받침대(두 손 사이 · 땅) = 두 손이 따라감.
## 내장 수정자만 쓴다(병사가 많아도 가볍게 — 10-16 실측 갱신 한 번에 잴 수 없을 만큼 작음). 손마다:
##   DR_<손>Ref(ModifierBoneTarget3D — 소켓 뼈를 수정자 차례 안에서 따라감. 소켓 노드는 갱신 끝에 옮겨져 목표로 쓰면 한 박자 늦다 · 받침대면 없음)
##     └ DR_<손>Wrist(손목 목표 = 표지 − 손바닥 거리, 기저 = 표지 회전 — 받침대면 뼈대 바로 아래, 풀이 수정자가 옮김)
##   DR_<손>Elbow(ModifierBoneTarget3D — 동작의 팔꿈치 = 극. TwoBoneIK3D 는 극이 없으면 풀지 않는다 — 10-16 실측)
##   DR_<손>ArmIK(TwoBoneIK3D 위팔 → 아래팔 → 손) · DR_<손>HandRot(CopyTransformModifier3D — 손 회전 = 표지 회전)
## 뼈대 수정자는 게임 · 미리보기 사본에서 "자세가 바뀔 때만"(MANUAL — step_motion 초당 12번) 돈다. 기본(IDLE)이면 멈춘 병사도
## 매 프레임 돈다(10-16 실측). 편집 중인 씬만 IDLE(기즈모로 표지를 끌 때 팔이 바로 따라오게).

const SUPPORT_NAME := "왼손"
const WEAPON_BONE := "RightHand"
const LEFT_ARM := ["LeftUpperArm", "LeftLowerArm", "LeftHand"]
## 손마다(0 = 왼손 · 1 = 오른손)
const HAND_BONES := ["LeftHand", "RightHand"]
const ARMS := [["LeftUpperArm", "LeftLowerArm", "LeftHand"], ["RightUpperArm", "RightLowerArm", "RightHand"]]
const PALM_PARTS := ["L_Hand", "R_Hand"]
const SIDE_NAMES := ["왼손", "오른손"]
const SIDE_TAGS := ["Left", "Right"]
const SOLVER_SCRIPT := preload("res://addons/dot_rigger/runtime/dr_grip_solver_3d.gd")
const AIM_SOLVER_SCRIPT := preload("res://addons/dot_rigger/runtime/dr_aim_solver_3d.gd")
const HIT_SOLVER_SCRIPT := preload("res://addons/dot_rigger/runtime/dr_hit_solver_3d.gd")
## 동작별 무기 자리(10-19) — 장비 노드의 메타 칸 이름. 값 = {동작 이름: Transform3D}, 그 동작에서 장비 자리 = 기본 자리(transform) × 이 값
## (장비 자신의 축 기준 위치 · 회전 차이 — 받침을 바꿔도(잡기 오른손 → 양손) 뜻이 같다). 동작 표의 상하체 합성 "A+B" 는 제 것이 없으면 상체 B 것을 쓴다.
## 사용자(10-16): "2번 탭은 애니메이션별로 양손이든 왼손이든 오른손이든 총기 위치 회전 오프셋을 지정해 둘 수 있는 리소스 툴인 거지?" → 10-19 "2번 작업도 시행"
const MOTION_OFFSETS_META := &"dr_motion_offsets"


## 손 하나의 IK(10-16 — 왼손만이던 것을 두 손으로)
class HandIK:
	var side := 0
	var marker: Node3D = null            # 손 표지
	var anchor: Node3D = null            # 그 장비의 받침(소켓 BoneAttachment3D 또는 DRGripMount3D)
	var ref: ModifierBoneTarget3D = null # 소켓 받침 = 받침 뼈를 수정자 차례 안에서 따라감 · 받침대 = null
	var wrist: Node3D = null             # 손목 목표(원점) · 손 회전(기저)
	var pole: ModifierBoneTarget3D = null
	var ik: TwoBoneIK3D = null
	var rot: CopyTransformModifier3D = null
	var bones := PackedInt32Array()      # [위팔, 아래팔, 손, 받침 뼈(소켓) 또는 -1(받침대)]
	var rel := Transform3D.IDENTITY      # 받침 → 표지(배율 뺌)
	var palm := Vector3.ZERO             # 손 뼈 로컬 손바닥 점(뼈 머리 · 꼬리 가운데 — DRGripFit 과 같은 뜻)
	var w := 0.0
	var w_from := 0.0
	var w_to := 0.0


## IK 피격 반응 하나(10-21) — 뼈 사슬(아래부터) · 몫 · 돌림 축(뼈대 공간) · 흐른 시간 · 최대 각(라디안)
class HitReaction:
	var part := ""
	var side := -1                          # 팔이면 그 손(0 = 왼손 · 1 = 오른손) — 그 손이 IK 로 잡고 있으면 손 IK 뒤에 돌려 총에서 튕겼다 돌아오게
	var bones := PackedInt32Array()
	var shares := PackedFloat32Array()
	var bone := -1                          # 맞은 뼈 마디의 뼈 · 그 뼈 기준 맞은 점 · 총알 방향(뼈대 공간) — 축은 처음 돌릴 때 그때 자세로(_hit_axis)
	var local := Vector3.ZERO
	var dir := Vector3.ZERO
	var ready := false
	var axis := Vector3.RIGHT
	var t := 0.0
	var amp := 0.0


## 동작별 자리를 얹는 장비 하나(10-19) — base = 기본 자리(씬에 저장된 transform), cur = 지금 얹은 차이, from → to = 섞는 중
class PoseEquip:
	var e: Node3D = null
	var base := Transform3D.IDENTITY
	var cur := Transform3D.IDENTITY
	var from := Transform3D.IDENTITY
	var to := Transform3D.IDENTITY


## 받침 · 장비 · 손 표지를 다시 찾아 지금 몸에 잇는다 — 조립 때 저절로, ② 장비 탭이 노드를 바꾼 뒤, 편집 중인 씬에서 구조가 바뀌면.
## 몸이 없으면(조립 전) 아무것도 안 한다
func refresh_equipment() -> void:
	_free_ik()
	_sockets.clear()
	_mounts.clear()
	_equip_mis.clear()
	_sock_weapon = null
	if _skel == null or not is_instance_valid(_skel):
		return
	var edited := is_inside_tree() and is_part_of_edited_scene()
	var found := [null, null]            # 손마다 [표지, 받침] — 먼저 찾은 것
	var hand_equip: Node3D = null        # 오른손 소켓의 첫 장비(표지 있는 장비가 없을 때의 "무기")
	var old := {}                        # 장비 → PoseEquip(다시 잇기 — 이미 동작별 자리를 얹은 장비의 기본 자리를 지금 transform 으로 착각하지 않게)
	for pq in _pose_equips:
		old[pq.e] = pq
	_pose_equips.clear()
	for a in find_anchors(self, _model):
		var abone := ""
		if a is BoneAttachment3D:
			if not _bind_socket(a as BoneAttachment3D):
				continue
			_sockets.append(a as BoneAttachment3D)
			abone = (a as BoneAttachment3D).bone_name
		else:
			_mounts.append(a as DRGripMount3D)
		for c in a.get_children():
			var e := c as Node3D
			if e == null:
				continue
			if not e.visible:
				if not Engine.is_editor_hint():
					e.queue_free()             # 게임: 자식 프리팹이 숨긴 부모 장비 — 병사마다 남기지 않는다
				continue
			_paint_equipment(e, edited)
			if not edited:                     # 편집 중인 씬은 기본 자리 그대로(얹으면 그 값이 저장된다)
				var pq: PoseEquip = old.get(e, null)
				if pq == null:
					pq = PoseEquip.new()
					pq.e = e
					pq.base = e.transform
				_pose_equips.append(pq)
			var marked := false
			for side in 2:
				var mk := find_hand_marker(e, side)
				if mk == null:
					continue
				marked = true
				if not edited:                 # 손 표지도 동작별 자리를 얹는다(10-27 사용자 "오른손 왼손도 기즈모로 움직여서 살짝 조정") — 무기와 같은 장치
					var mq: PoseEquip = old.get(mk, null)
					if mq == null:
						mq = PoseEquip.new()
						mq.e = mk
						mq.base = mk.transform
					_pose_equips.append(mq)
				if anchor_can_grip(a, side) and found[side] == null:
					found[side] = [mk, a]      # 받침이 그 손 소켓이면(무기가 그 손을 따라감) IK 안 함 — 한 손 받침대의 다른 손은 비중 0 으로 만들어 둠
			if _sock_weapon == null and marked:
				_sock_weapon = e
			if hand_equip == null and abone == WEAPON_BONE:
				hand_equip = e
	if _sock_weapon == null:
		_sock_weapon = hand_equip
	if not _mounts.is_empty():
		_solver = SOLVER_SCRIPT.new()
		_solver.name = "DR_GripSolver"
		_solver.set("character", self)
		_skel.add_child(_solver)
		_skel.move_child(_solver, 0)       # 수정자 차례 맨 앞(손 IK 보다 먼저 — 동작 자세로)
	_make_aim()                            # 그보다 더 앞(허리를 돌린 자세로 받침대 · 손 IK 가 푼다)
	_make_hit()                            # 조준 바로 뒤(젖혀진 자세로 받침대 · 손 IK 가 푼다)
	for side in 2:
		if found[side] != null:
			_make_ik(side, found[side][0], found[side][1])
	_make_hit_post()                       # 맨 뒤(손 IK 로 잡은 팔의 피격 — 잡은 자세 위에)
	if _hit_solver != null or _aim_solver != null or _solver != null or _hands[0] != null or _hands[1] != null:
		_skel.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE if edited else Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	_aim_offsets(_motion, true)                # 지금 동작의 동작별 자리를 바로(안 움직였으면 아래 sync_support 가 손 IK 목표를)
	sync_support()
	for side in 2:
		_set_hand_weight(side, _hand_weight(side, _motion))
	_aim_w = aim_weight_for(_motion)
	_equip_sig = _socket_sig()


# ---------------------------------------------------------------- 동작별 무기 자리(10-19)

## 장비 e 의 동작별 자리 — {동작: Transform3D}. 없으면 {}
static func motion_offsets(e: Node) -> Dictionary:
	if e == null or not e.has_meta(MOTION_OFFSETS_META):
		return {}
	var v: Variant = e.get_meta(MOTION_OFFSETS_META)
	return v if v is Dictionary else {}


## 그 동작에 쓰는 동작별 자리의 이름 — 그 동작 것 → 없으면 상하체 합성(A+B)의 상체 B 것 → 없으면 ""(기본 자리)
static func offset_key(e: Node, motion: String) -> String:
	var d := motion_offsets(e)
	if d.is_empty() or motion == "":
		return ""
	if d.get(motion) is Transform3D:
		return motion
	var plus := motion.rfind("+")
	if plus > 0 and d.get(motion.substr(plus + 1)) is Transform3D:
		return motion.substr(plus + 1)
	return ""


## 그 동작의 동작별 자리(장비 축 기준 차이 — 장비 자리 = 기본 자리 × 이 값). 없으면 IDENTITY
static func offset_for(e: Node, motion: String) -> Transform3D:
	var k := offset_key(e, motion)
	if k == "":
		return Transform3D.IDENTITY
	return motion_offsets(e)[k]


## 동작별 자리 차이의 크기 — [옮긴 거리 m(받침 기준 장비 원점), 돌린 각 °]. base = 기본 자리
static func offset_size(base: Transform3D, off: Transform3D) -> Vector2:
	return Vector2((base * off).origin.distance_to(base.origin), rad_to_deg(off.basis.orthonormalized().get_rotation_quaternion().get_angle()))


## 동작별 자리를 그 동작 것으로 — instant 면 바로, 아니면 섞기 시작(step_motion 이 옮긴다). 섞어 옮길 것이 있으면 true
func _aim_offsets(motion: String, instant: bool) -> bool:
	var moving := false
	var moved := false
	for pq in _pose_equips:
		if not is_instance_valid(pq.e):
			continue
		var t := offset_for(pq.e, motion)
		if instant:
			if not t.is_equal_approx(pq.cur) or not pq.e.transform.is_equal_approx(pq.base * t):
				pq.cur = t
				pq.e.transform = pq.base * t
				moved = true
			pq.from = t
			pq.to = t
		else:
			pq.from = pq.cur
			pq.to = t
			moving = moving or not t.is_equal_approx(pq.cur)
	if moved:
		sync_support()
	return moving


func _pose_of(e: Node) -> PoseEquip:
	for pq in _pose_equips:
		if pq.e == e:
			return pq
	return null


## 장비 e 의 기본 자리를 바꾼다(① ② 탭이 유닛 씬 값을 미리보기 사본에 옮길 때) — 지금 얹은 동작별 자리는 그대로 얹어 놓는다
func set_equip_base(e: Node3D, base: Transform3D) -> void:
	_aim_refs.clear()                          # 무기 자리가 바뀌면 총구 기준도 다시
	var pq := _pose_of(e)
	if pq == null:
		e.transform = base
		return
	pq.base = base
	e.transform = base * pq.cur


## 장비 e 의 기본 자리(동작별 자리를 얹기 전 — 씬에 저장된 값). 동작별 자리를 안 쓰는 노드(편집 중인 씬)면 지금 transform
func get_equip_base(e: Node3D) -> Transform3D:
	var pq := _pose_of(e)
	return pq.base if pq != null else e.transform


## 장비 e 에 지금 얹은 동작별 자리(섞는 중이면 그 사이 값). 없으면 IDENTITY
func get_equip_offset(e: Node3D) -> Transform3D:
	var pq := _pose_of(e)
	return pq.cur if pq != null else Transform3D.IDENTITY


## 미리보기 사본 = src(같은 구조의 유닛 — 편집 중인 씬)의 받침 · 장비 · 표지 값으로(다시 조립하지 않고). ① ② 탭이 자리 · 비중 · 보간 ·
## 동작별 자리만 바뀌었을 때 부른다. 소켓은 뼈가, 두 손 사이 받침대는 두 손이 자리를 정하므로 안 덮는다(덮으면 그 프레임에 원점으로 튐, 10-16).
## 끝나면 지금 동작의 동작별 자리 · 손 비중을 새 값으로 바로(동작 · 시점은 그대로)
func sync_from(src: DRCharacter3D) -> void:
	if src == null:
		return
	for s in find_anchors(src, src._model):
		var stack: Array[Node] = [s]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			if n.owner != src:
				continue
			var pn := get_node_or_null(src.get_path_to(n))
			if pn == null:
				continue
			var driven := n is BoneAttachment3D or (n is DRGripMount3D and (n as DRGripMount3D).mode == DRGripMount3D.Mode.HANDS)
			if pn is Node3D and n is Node3D and not driven:
				if n.get_parent() is BoneAttachment3D or n.get_parent() is DRGripMount3D or _pose_of(pn) != null:   # 장비 · 손 표지 — 기본 자리 + 동작별 자리
					if n.has_meta(MOTION_OFFSETS_META):
						pn.set_meta(MOTION_OFFSETS_META, (n.get_meta(MOTION_OFFSETS_META) as Dictionary).duplicate())
					elif pn.has_meta(MOTION_OFFSETS_META):
						pn.remove_meta(MOTION_OFFSETS_META)
					set_equip_base(pn as Node3D, (n as Node3D).transform)
				else:
					(pn as Node3D).transform = (n as Node3D).transform
			if pn is DRHandTarget3D and n is DRHandTarget3D:
				(pn as DRHandTarget3D).motion_weights = (n as DRHandTarget3D).motion_weights.duplicate()
				(pn as DRHandTarget3D).weight = (n as DRHandTarget3D).weight
			if pn is DRGripMount3D and n is DRGripMount3D:
				for k in ["blend", "hold", "right_offset", "left_offset"]:
					pn.set(k, n.get(k))
	for k in AIM_PROPS + HIT_PROPS:            # 조준 · 피격 칸(유닛 루트)
		set(k, src.get(k))
	aim_motion_weights = src.aim_motion_weights.duplicate()
	refresh_muzzle()                           # 총구 · 견착 표지를 기즈모로 옮겼을 수 있다
	_aim_valid = false
	_grip_t = -1.0                             # 섞던 것은 끊고 지금 동작 값으로
	_aim_offsets(_motion, true)
	sync_support()
	for side in 2:
		_set_hand_weight(side, _hand_weight(side, _motion))
	_aim_w = aim_weight_for(_motion)


# ---------------------------------------------------------------- 조준 IK(10-21)
## 사용자(10-21): "사격을 할 때 적의 위치 · 적을 바라보는 벡터 기준으로 허리가 살짝 굽거나 해야 될 것 같아 — 총구가 적을 바라봐야 되니까. IK 기술의 파생인가?"
## = 조준 IK(에임 오프셋). 동작 위에 덧씌운다 — 그 동작의 **총구 기준**(동작 그대로 여러 시점 평균 방향)을 표적 쪽으로 한계 안에서
## 돌리고, 그 돌림을 허리 · 가슴 뼈에 나눠 준다. 기준이 평균이라 동작의 반동 · 흔들림은 그대로 남는다(매 장면 총구를 표적에 붙이면 반동이 지워진다).
## 손 · 무기는 몸을 따라오고 뒤의 받침대 풀이 · 손 IK 가 돌린 자세로 다시 잡는다.
##   위아래만: 총구 높낮이 = 총구에서 표적을 보는 높낮이(정확히). 좌우는 안 돈다 — 횡스크롤이라 동작이 원래 겨눈 좌우 방향 그대로
##   (10-21 사용자 "옆은 필요 없는 것 같아 — 결국 횡스크롤 게임에 리소스를 3D 만 쓰는 거라". 처음엔 앞뒤 줄 표적으로 몸을 옆으로도 돌렸다).
## 무기 총구 = 장비 아래 "총구" 노드(자리 · +Z 방향)가 있으면 그것, 없으면 무기 +Z(normalize_weapon 규칙: 원점 = 잡는 자리 · +Z = 총구 쪽) 앞 끝의
## 총열 축(메시에서 잼 — kar98k 는 원점보다 4.5 cm 위. 처음엔 원점 높이로 잡아 총구 선이 총열 아래에서 나갔다, 10-21 사용자 "조준선과 총구가 안 맞네").
## 고정 받침대(땅 — MG42 라페테)에 든 무기는 몸을 돌려 겨누지 않는다(장비를 돌리는 것은 나중).
## 팔 · 견착(10-21 저녁, 사용자: "진짜 조준을 할 때 팔 부분이 영향이 제일 많이 가잖아 — 양팔로 인한 견착 위치에 따라"):
##   높낮이의 aim_arm_share(기본 70 %)는 **견착점(개머리판 끝 — 장비 아래 "견착" 노드, 없으면 −Z 쪽 메시 끝의 가운데) 축으로 총을 돌려** 팔이 맡는다 —
##   손 소켓 무기 = 든 손을 그 팔 두 마디 IK(DR_AimArmIK)로 돌린 자리에(다른 손은 원래 표지 IK), 두 손 사이 받침대 = 받침대를 돌림(두 손이 표지 IK).
##   나머지 높낮이는 허리 · 가슴. 머리는 팔 몫의 AIM_HEAD_SHARE 만큼 따라 숙이고 든다(뺨을 개머리판에).

## 돌릴 뼈와 몫(아래부터 — 합 1). 몸에 없는 뼈는 빼고 나머지 몫을 다시 나눈다
const AIM_BONES := [["Spine", 0.3], ["Chest", 0.35], ["UpperChest", 0.35]]
## 총구 기준을 재는 시점 수(동작 길이를 고르게)
const AIM_SAMPLES := 8
## 표적이 나타나거나 사라질 때 섞는 시간(초)
const AIM_FADE_SEC := 0.15
## 동작 표 상태 이름에 이 말이 들어 있으면 그 상태의 동작은 기본 조준 비중 1
const AIM_STATE_WORDS := ["사격", "조준"]
## 조준 칸(sync_from 이 옮긴다 — aim_motion_weights 는 따로 복제)
const AIM_PROPS := ["aim_enabled", "aim_up_deg", "aim_down_deg", "aim_speed_deg", "aim_arm_share"]
const NO_TRACKS := [-1, -1, -1]
## 팔 몫 돌림을 머리가 따라가는 정도
const AIM_HEAD_SHARE := 0.6
## 조준 표지 이름(10-21) — 무기 아래 이 이름의 Node3D(② 탭이 Marker3D 로 만든다 · 기즈모로 옮김):
## 총구 = 레이(총구 선)가 나가는 자리, +Z = 방향 · 견착 = 팔 몫 조준의 축(개머리판 끝). 없으면 메시에서 잰다(_measure_weapon)
## 사용자(10-21): "조준선과 총구 위치(즉 레이 기능) — 그 위치를 조정할 수 있는 기즈모 기능 연동도 필요해"
const MUZZLE_NAME := "총구"
const SHOULDER_NAME := "견착"


## 표적(세상 좌표)을 준다 — 조준 비중이 있는 동작(사격 · 조준)에서 허리 · 가슴을 돌려 총구가 이리로. 표적을 바꾸면 aim_speed_deg 로 따라간다.
## instant = 섞지 않고 바로(② 탭 미리보기 · 시험). 자세는 다음 뼈대 갱신(step_motion)에 바뀐다
func set_aim_target(p: Vector3, instant := false) -> void:
	_aim_point = p
	_aim_by_angle = false
	_aim_has = true
	if instant:
		_aim_on = 1.0
		_aim_valid = false


## 표적 대신 높낮이로 겨눈다(② 장비 탭 미리보기) — 총구 높낮이(수평 = 0, 위 +, 도)
func set_aim_elevation(height_deg: float, instant := false) -> void:
	_aim_elev = deg_to_rad(height_deg)
	_aim_by_angle = true
	_aim_has = true
	if instant:
		_aim_on = 1.0
		_aim_valid = false


## 표적을 거둔다 — 허리가 AIM_FADE_SEC 동안 동작 그대로 돌아온다(instant = 바로)
func clear_aim_target(instant := false) -> void:
	_aim_has = false
	if instant:
		_aim_on = 0.0
		_aim_valid = false


func has_aim_target() -> bool:
	return _aim_has


func get_aim_target() -> Vector3:
	return _aim_point


## 그 동작의 조준 비중(0 ~ 1) — aim_motion_weights → 상하체 합성(A+B)이면 상체 B 것 → 동작 표 기본(aim_default_weight)
func aim_weight_for(motion: String) -> float:
	if not aim_enabled or motion == "":
		return 0.0
	if aim_motion_weights.has(motion):
		return clampf(aim_motion_weights[motion], 0.0, 1.0)
	var plus := motion.rfind("+")
	if plus > 0 and aim_motion_weights.has(motion.substr(plus + 1)):
		return clampf(aim_motion_weights[motion.substr(plus + 1)], 0.0, 1.0)
	return aim_default_weight(motion)


## 동작 표로 정한 기본 조준 비중 — 그 동작이 "사격" · "조준" 이 든 상태(서기+사격 · 앉기+조준 · 엎드림+사격 …)에 있으면 1, 아니면 0. 표가 없으면 0
func aim_default_weight(motion: String) -> float:
	var v: Variant = _aim_defaults.get(motion)
	if v != null:
		return v
	var w := 0.0
	if motions != null:
		for st in motions.state_names():
			var hit := false
			for word in AIM_STATE_WORDS:
				hit = hit or st.contains(String(word))
			if hit and motions.has_motion(st, motion):
				w = 1.0
				break
	_aim_defaults[motion] = w
	return w


## 마지막 조준 풀이 — {weight(비중 × 표적), pitch(지금 든 각 °) = arm_pitch(팔) + body_pitch(허리 · 가슴), want_pitch(한계 전 필요한 각 °),
## base_pitch(동작이 원래 겨눈 높낮이 °), err(돌린 총구 기준 ↔ 겨눌 방향 °, 반동 빼고 — 따라가는 중 · 비중을 섞는 중이면 그만큼 남음),
## lag(표적이 바뀌어 아직 덜 돈 각 °, aim_speed_deg 로 따라감), clamped(한계에 걸림),
## muzzle · dir(돌린 총구 기준 — 캐릭터 공간) · aim_dir(겨눌 방향 — 캐릭터 공간, 한계 전)}. 조준 안 하면 {}
func aim_report() -> Dictionary:
	return _aim_last.duplicate()


## 지금 무기 총구(세상 좌표) [자리, 방향] — 뼈대 갱신 뒤 무기 노드 그대로(동작의 반동 포함). 무기가 없으면 []
func muzzle_world() -> Array:
	if _sock_weapon == null or not is_instance_valid(_sock_weapon) or _muzzle.is_empty() or not _sock_weapon.is_inside_tree():
		return []
	var g := _sock_weapon.global_transform
	return [g * (_muzzle[0] as Vector3), (g.basis * (_muzzle[1] as Vector3)).normalized()]


## 총구 · 견착점을 다시 찾는다(조준 표지를 옮기거나 더하고 뺀 뒤 — ② 탭 기즈모 · sync_from). 총구 기준(동작별 평균)도 다시
func refresh_muzzle() -> void:
	if _sock_weapon == null or not is_instance_valid(_sock_weapon) or _muzzle.is_empty():
		return
	var mz := find_muzzle(_sock_weapon)
	if not mz.is_empty():
		_muzzle = mz
	_aim_refs.clear()


## 지금 견착점(세상 좌표 — 개머리판 끝, 팔 몫 조준의 축). 무기가 없으면 Vector3.INF
func shoulder_world() -> Vector3:
	if _sock_weapon == null or not is_instance_valid(_sock_weapon) or _muzzle.is_empty() or not _sock_weapon.is_inside_tree():
		return Vector3.INF
	return _sock_weapon.global_transform * (_muzzle[2] as Vector3)


## 무기 e 의 로컬 [총구 자리, 총구 방향, 견착점] — 아래 "총구" 노드가 있으면 그 자리 · +Z, 없으면 +Z 쪽 앞 끝의 총열 축(보이는 메시만 — 숨긴 탄 클립 빼고).
## 견착점 = 아래 "견착" 노드 자리, 없으면 −Z 쪽 끝(개머리판 끝 — normalize_weapon 규칙에서 총구 반대쪽)의 가운데. 메시에서 잰 값은 무기마다 한 번(_muzzle_geo)
static func find_muzzle(e: Node3D) -> Array:
	if e == null:
		return []
	var muzzle: Array = []
	var butt := Vector3.INF
	var meshes: Array = []                     # [Mesh, rel]
	var key := PackedStringArray()
	var stack: Array = [[e, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var n: Node = it[0]
		var rel: Transform3D = it[1]
		if n != e and n is Node3D:
			if not (n as Node3D).visible:
				continue                           # 숨긴 표지(자식 유닛이 부모 것을 숨김) · 숨긴 부품은 안 씀
			if String(n.name) == MUZZLE_NAME:
				muzzle = [rel.origin, rel.basis.z.normalized()]
			elif String(n.name) == SHOULDER_NAME:
				butt = rel.origin
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			meshes.append([(n as MeshInstance3D).mesh, rel])
			key.append("%d@%s" % [(n as MeshInstance3D).mesh.get_instance_id(), str(rel)])
		for c in n.get_children():
			stack.append([c, rel * (c as Node3D).transform if c is Node3D else rel])
	if muzzle.is_empty() or butt == Vector3.INF:
		var k := ";".join(key)
		var geo: Array = _muzzle_geo.get(k, [])
		if geo.is_empty():
			geo = _measure_weapon(meshes)
			_muzzle_geo[k] = geo
		if geo.is_empty():
			return []
		if muzzle.is_empty():
			muzzle = [geo[0], Vector3.BACK]
		if butt == Vector3.INF:
			butt = geo[1]
	return [muzzle[0], muzzle[1], butt]


## 무기 e 아래 그 이름의 조준 표지(MUZZLE_NAME · SHOULDER_NAME — 보이는 것 중 처음). 없으면 null
static func find_aim_marker(e: Node, marker_name: String) -> Node3D:
	if e == null:
		return null
	var stack: Array[Node] = []
	stack.append_array(e.get_children())
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Node3D and not (n as Node3D).visible:
			continue
		if n is Node3D and String(n.name) == marker_name and not (n is BoneAttachment3D):
			return n as Node3D
		stack.append_array(n.get_children())
	return null


## n 의 자리를 조상 anc 기준으로(트리 밖이어도 — 부모를 따라 곱함). anc 가 조상이 아니면 n 의 지금 transform
static func rel_xform(anc: Node, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != anc:
		if c is Node3D:
			t = (c as Node3D).transform * t
		c = c.get_parent()
	return t if c == anc else n.transform


## 무기 메시에서 [총구(앞 끝의 총열 축), 견착점(뒤 끝 가운데)] — 무기 로컬. 앞 끝 바로 뒤 토막(길이의 2 ~ 9 %)의 정점 가운데가 총열 축
## (맨 끝 토막은 가늠쇠가 올라와 있어 위로 쏠림), 뒤 끝 토막(2 %)의 가운데가 개머리판 끝
static func _measure_weapon(meshes: Array) -> Array:
	var pts := PackedVector3Array()
	for m in meshes:
		var mesh: Mesh = m[0]
		var rel: Transform3D = m[1]
		for si in mesh.get_surface_count():
			var vs: PackedVector3Array = mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
			for v in vs:
				pts.append(rel * v)
	if pts.is_empty():
		return []
	var z0 := INF
	var z1 := -INF
	for p in pts:
		z0 = minf(z0, p.z)
		z1 = maxf(z1, p.z)
	var ln := maxf(z1 - z0, 0.001)
	var tip := Vector3.ZERO
	var nt := 0
	var bt := Vector3.ZERO
	var nb := 0
	for p in pts:
		if p.z <= z1 - ln * 0.02 and p.z >= z1 - ln * 0.09:
			tip += p
			nt += 1
		elif p.z <= z0 + ln * 0.02:
			bt += p
			nb += 1
	tip = tip / nt if nt > 0 else Vector3.ZERO
	bt = bt / nb if nb > 0 else Vector3.ZERO
	return [Vector3(tip.x, tip.y, z1), Vector3(bt.x, bt.y, z0)]


## 조준 수정자를 만든다(무기를 들었을 때 — refresh_equipment). 맨 앞 차례
func _make_aim() -> void:
	_aim_refs.clear()
	_aim_defaults.clear()
	_aim_valid = false
	_aim_last = {}
	_muzzle = find_muzzle(_sock_weapon)
	_aim_bones = PackedInt32Array()
	_aim_shares = PackedFloat32Array()
	if _muzzle.is_empty() or _skel == null:
		return
	var total := 0.0
	for b in AIM_BONES:
		var bi := _skel.find_bone(String(b[0]))
		if bi >= 0:
			_aim_bones.append(bi)
			_aim_shares.append(float(b[1]))
			total += float(b[1])
	if _aim_bones.is_empty():
		return
	for i in _aim_shares.size():
		_aim_shares[i] /= total
	_aim_solver = AIM_SOLVER_SCRIPT.new()
	_aim_solver.name = "DR_AimSolver"
	_aim_solver.set("character", self)
	_skel.add_child(_aim_solver)
	_skel.move_child(_aim_solver, 0)
	_aim_head = _skel.find_bone("Head")
	# 손 소켓 무기 — 팔 몫 조준은 든 손을 견착점 축으로 돌린 자리에 그 팔 두 마디 IK 로(조준 수정자 바로 뒤 — 다른 손 IK 가 돌린 손을 따라가게)
	var sock := _sock_weapon.get_parent() as BoneAttachment3D
	var side := HAND_BONES.find(String(sock.bone_name)) if sock != null else -1
	if side < 0:
		return
	var ids := PackedInt32Array()
	for b in ARMS[side]:
		ids.append(_skel.find_bone(String(b)))
	if ids.has(-1):
		return
	_aim_arm_hand = ids[2]
	var tag := String(SIDE_TAGS[side])
	_aim_hand = Node3D.new()
	_aim_hand.name = "DR_Aim%sHand" % tag
	_skel.add_child(_aim_hand)
	_aim_arm_pole = ModifierBoneTarget3D.new()
	_aim_arm_pole.name = "DR_Aim%sElbow" % tag
	_skel.add_child(_aim_arm_pole)
	_aim_arm_pole.bone_name = String(ARMS[side][1])
	_aim_arm_ik = TwoBoneIK3D.new()
	_aim_arm_ik.name = "DR_Aim%sArmIK" % tag
	_skel.add_child(_aim_arm_ik)
	_aim_arm_ik.setting_count = 1
	_aim_arm_ik.set_root_bone_name(0, String(ARMS[side][0]))
	_aim_arm_ik.set_middle_bone_name(0, String(ARMS[side][1]))
	_aim_arm_ik.set_end_bone_name(0, String(ARMS[side][2]))
	_aim_arm_ik.set_target_node(0, _aim_arm_ik.get_path_to(_aim_hand))
	_aim_arm_ik.set_pole_node(0, _aim_arm_ik.get_path_to(_aim_arm_pole))
	_aim_arm_rot = CopyTransformModifier3D.new()
	_aim_arm_rot.name = "DR_Aim%sHandRot" % tag
	_skel.add_child(_aim_arm_rot)
	_aim_arm_rot.setting_count = 1
	_aim_arm_rot.set_apply_bone_name(0, String(ARMS[side][2]))
	_aim_arm_rot.set_reference_type(0, BoneConstraint3D.REFERENCE_TYPE_NODE)
	_aim_arm_rot.set_reference_node(0, _aim_arm_rot.get_path_to(_aim_hand))
	_aim_arm_rot.set_copy_flags(0, CopyTransformModifier3D.TRANSFORM_FLAG_ROTATION)
	_skel.move_child(_aim_arm_pole, 1)
	_skel.move_child(_aim_arm_ik, 2)
	_skel.move_child(_aim_arm_rot, 3)
	_set_aim_arm(false)


## 손 소켓 무기의 조준 팔 IK 켜고 끄기(팔 몫 돌림이 없으면 끈다 — 동작 그대로)
func _set_aim_arm(on: bool) -> void:
	if _aim_arm_ik == null or _aim_arm_ik.active == on:
		return
	_aim_arm_ik.active = on
	_aim_arm_rot.active = on


## 조준 풀이 — 조준 수정자(뼈대 수정자 차례 맨 앞)가 부른다. 뼈 자세 = 동작 그대로
func _solve_aim(sk: Skeleton3D) -> void:
	var dt := _aim_dt
	_aim_dt = 0.0
	var on_to := 1.0 if _aim_has else 0.0
	if _aim_on != on_to:
		_aim_on = move_toward(_aim_on, on_to, dt / AIM_FADE_SEC)
	var w := _aim_w * _aim_on
	var ref: Array = _aim_ref(_motion) if w > 0.001 and sk != null else []
	_aim_arm_on = false
	if ref.is_empty():
		_aim_valid = false
		_aim_last = {}
		_set_aim_arm(false)
		return
	var to_c := _skel_to_char()
	var piv := to_c * sk.get_bone_global_pose(_aim_bones[0]).origin
	var pos0: Vector3 = ref[0]
	var dir0: Vector3 = ref[1]
	var butt0: Vector3 = ref[2]
	# 높낮이를 몸(허리 · 가슴)과 팔(견착점 축)이 나눔 — 팔이 못 맡는 받침(머리 소켓 등)이면 몸이 다
	var arm := clampf(aim_arm_share, 0.0, 1.0) if _aim_arm_hand >= 0 or _sock_weapon.get_parent() is DRGripMount3D else 0.0
	var el0 := asin(clampf(dir0.y, -1.0, 1.0))
	var lo := -deg_to_rad(aim_down_deg)
	var hi := deg_to_rad(aim_up_deg)
	var raw := _aim_elev - el0
	var want := clampf(raw, lo, hi)
	if not _aim_by_angle:
		var tgt := (global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY) * _aim_point
		for it in 3:                           # 총구가 몸 축에서 떨어져 있어 돌리면 총구 자리도 바뀐다 — 그 자리에서 표적 높낮이를 다시
			var d := tgt - aim_muzzle_at(want, arm, piv, pos0, dir0, butt0)
			if d.length_squared() < 0.0001:
				break
			raw = asin(clampf(d.normalized().y, -1.0, 1.0)) - el0
			want = clampf(raw, lo, hi)
	if not _aim_valid:
		_aim_cur = want
		_aim_valid = true
	else:
		_aim_cur = move_toward(_aim_cur, want, deg_to_rad(aim_speed_deg) * dt)
	var cur := _aim_cur * w
	var b := aim_basis(cur * (1.0 - arm), dir0)     # 몸 돌림(캐릭터 공간)
	var cb := to_c.basis.orthonormalized()
	var q := (cb.inverse() * b * cb).get_rotation_quaternion()   # 뼈대 공간으로(배율은 서로 지운다)
	for i in _aim_bones.size():
		var bi := _aim_bones[i]
		var g := sk.get_bone_global_pose(bi)
		g.basis = Basis(Quaternion.IDENTITY.slerp(q, _aim_shares[i])) * g.basis    # 그 뼈 자리를 축으로 몫만큼
		sk.set_bone_global_pose(bi, g)
	var db := b * dir0                         # 몸을 돌린 뒤 총구 방향
	var ba := Basis.IDENTITY
	var pa := cur * arm
	if absf(pa) > 1e-4:
		ba = aim_basis(pa, db)                 # 팔 몫(같은 수직면 안에서 위아래 — 축은 몸 돌림과 같다)
		var qa := (cb.inverse() * ba * cb).get_rotation_quaternion()
		_aim_arm_q = qa
		_aim_arm_on = true
		if _aim_head >= 0:                     # 머리도 일부 따라감(뺨을 개머리판에)
			var gh := sk.get_bone_global_pose(_aim_head)
			gh.basis = Basis(Quaternion.IDENTITY.slerp(qa, AIM_HEAD_SHARE)) * gh.basis
			sk.set_bone_global_pose(_aim_head, gh)
		if _aim_arm_hand >= 0:                 # 손 소켓 무기 — 든 손을 견착점 축으로 돌린 자리 = 조준 팔 IK 목표
			var hand := sk.get_bone_global_pose(_aim_arm_hand)
			var butt := hand * (_sock_weapon.transform * (_muzzle[2] as Vector3))
			_aim_hand.transform = Transform3D(Basis(qa) * hand.basis.orthonormalized(), butt + qa * (hand.origin - butt))
	_set_aim_arm(_aim_arm_on and _aim_arm_hand >= 0)
	var md := ba * db
	_aim_last = {"weight": w, "pitch": rad_to_deg(cur), "body_pitch": rad_to_deg(cur * (1.0 - arm)), "arm_pitch": rad_to_deg(pa),
		"want_pitch": rad_to_deg(raw), "base_pitch": rad_to_deg(el0), "err": rad_to_deg(md.angle_to(aim_basis(raw, dir0) * dir0)),
		"lag": rad_to_deg(absf(want - _aim_cur)), "clamped": not is_equal_approx(want, raw),
		"muzzle": aim_muzzle_at(cur, arm, piv, pos0, dir0, butt0), "dir": md, "aim_dir": aim_basis(raw, dir0) * dir0}


## 조준 돌림(캐릭터 공간 — 위 = +Y) — 총구 방향 d 를 그 수직면 안에서 위아래로 a(라디안, + = 위). 좌우 방향은 그대로
static func aim_basis(a: float, d: Vector3) -> Basis:
	var h := Vector3(d.x, 0.0, d.z)
	return Basis((h.normalized() if h.length_squared() > 1e-6 else Vector3.BACK).cross(Vector3.UP).normalized(), a)


## 높낮이 a 를 몸 · 팔(arm 몫)로 나눴을 때 총구 기준 자리(캐릭터 공간) — 몸은 허리(piv) 축, 팔은 몸을 돌린 뒤의 견착점 축
static func aim_muzzle_at(a: float, arm: float, piv: Vector3, pos0: Vector3, dir0: Vector3, butt0: Vector3) -> Vector3:
	var b := aim_basis(a * (1.0 - arm), dir0)
	var p := piv + b * (pos0 - piv)
	if arm <= 0.0 or absf(a) < 1e-6:
		return p
	var bt := piv + b * (butt0 - piv)
	return bt + aim_basis(a * arm, dir0) * (p - bt)


## 뼈대 공간 → 캐릭터 공간(이 노드 로컬) — 트리 밖이어도 되게 부모를 따라 곱한다
func _skel_to_char() -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = _skel
	while n != null and n != self:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


## 그 동작의 총구 기준 [자리, 방향, 견착점](캐릭터 공간) — 동작 그대로(수정자 전) AIM_SAMPLES 시점 평균. 동작 파일에서 바로 계산해 지금 자세를
## 건드리지 않는다(캐시 — 장비 · 동작 묶음이 바뀌면 비운다). 조준 못 하는 동작 · 받침(고정 받침대)이면 []
func _aim_ref(motion: String) -> Array:
	var r: Variant = _aim_refs.get(motion)
	if r != null:
		return r
	var out: Array = []
	var e := _sock_weapon
	var anim: Animation = _ap.get_animation(motion) if _ap != null and motion != "" and _ap.has_animation(motion) else null
	if anim != null and e != null and is_instance_valid(e) and not _muzzle.is_empty() and anim.length > 0.0:
		var pq := _pose_of(e)
		var exf := pq.base * offset_for(e, motion) if pq != null else e.transform    # 받침 기준 무기 자리(그 동작의 동작별 자리까지)
		var to_c := _skel_to_char()
		var tracks := _tracks_of(anim)
		var sp := Vector3.ZERO
		var sd := Vector3.ZERO
		var sb := Vector3.ZERO
		var ok := true
		for k in AIM_SAMPLES:
			var wx: Variant = _anchor_at(anim, tracks, anim.length * (float(k) + 0.5) / float(AIM_SAMPLES), e.get_parent(), motion)
			if wx == null:
				ok = false
				break
			var w := to_c * (wx as Transform3D) * exf
			sp += w * (_muzzle[0] as Vector3)
			sd += (w.basis * (_muzzle[1] as Vector3)).normalized()
			sb += w * (_muzzle[2] as Vector3)
		if ok and sd.length_squared() > 1e-6:
			out = [sp / float(AIM_SAMPLES), sd.normalized(), sb / float(AIM_SAMPLES)]
	_aim_refs[motion] = out
	return out


## 동작 파일의 시점 t 에서 받침의 자리(뼈대 공간) — 소켓 = 그 뼈, 두 손 사이 받침대 = _solve_mounts 와 같은 보간(그 동작의 손 IK 비중으로). 고정 받침대 · 모르는 받침 = null
func _anchor_at(anim: Animation, tracks: Dictionary, t: float, anchor: Node, motion: String) -> Variant:
	var memo := {}
	if anchor is BoneAttachment3D:
		var bi := _skel.find_bone((anchor as BoneAttachment3D).bone_name)
		return _fk(anim, tracks, bi, t, memo) if bi >= 0 else null
	var m := anchor as DRGripMount3D
	if m == null or m.mode != DRGripMount3D.Mode.HANDS:
		return null
	var bl := _skel.find_bone(String(HAND_BONES[0]))
	var br := _skel.find_bone(String(HAND_BONES[1]))
	if bl < 0 or br < 0:
		return null
	var r := _fk(anim, tracks, br, t, memo) * m.right_offset
	var l := _fk(anim, tracks, bl, t, memo) * m.left_offset
	var hl: HandIK = _hands[0]
	var hr: HandIK = _hands[1]
	return r.interpolate_with(l, mount_t(m, _hand_weight(0, motion) if hl != null and hl.anchor == m else 0.0,
		_hand_weight(1, motion) if hr != null and hr.anchor == m else 0.0))


## 동작 파일에서 바로 그 시점의 뼈 자세(뼈대 공간). 트랙이 없는 뼈 · 성분은 레스트 — memo = 이번 시점에 계산한 뼈
func _fk(anim: Animation, tracks: Dictionary, bone: int, t: float, memo: Dictionary) -> Transform3D:
	var v: Variant = memo.get(bone)
	if v != null:
		return v
	var rest := _skel.get_bone_rest(bone)
	var tr: Array = tracks.get(bone, NO_TRACKS)
	var p: Vector3 = rest.origin if int(tr[0]) < 0 else anim.position_track_interpolate(int(tr[0]), t)
	var q: Quaternion = rest.basis.get_rotation_quaternion() if int(tr[1]) < 0 else anim.rotation_track_interpolate(int(tr[1]), t)
	var s: Vector3 = rest.basis.get_scale() if int(tr[2]) < 0 else anim.scale_track_interpolate(int(tr[2]), t)
	var g := Transform3D(Basis(q) * Basis.from_scale(s), p)
	var par := _skel.get_bone_parent(bone)
	if par >= 0:
		g = _fk(anim, tracks, par, t, memo) * g
	memo[bone] = g
	return g


## 동작의 뼈 트랙 — {뼈 번호: [위치, 회전, 크기 트랙 번호(없으면 −1)]} (트랙 길 "%GeneralSkeleton:<뼈>" 의 뼈 이름으로)
func _tracks_of(anim: Animation) -> Dictionary:
	var d: Variant = _anim_tracks.get(anim)
	if d != null:
		return d
	var out := {}
	for i in anim.get_track_count():
		var ty := anim.track_get_type(i)
		var slot := 0 if ty == Animation.TYPE_POSITION_3D else (1 if ty == Animation.TYPE_ROTATION_3D else (2 if ty == Animation.TYPE_SCALE_3D else -1))
		var path := anim.track_get_path(i)
		if slot < 0 or path.get_subname_count() == 0:
			continue
		var bi := _skel.find_bone(String(path.get_subname(0)))
		if bi < 0:
			continue
		if not out.has(bi):
			out[bi] = NO_TRACKS.duplicate()
		(out[bi] as Array)[slot] = i
	_anim_tracks[anim] = out
	return out


# ---------------------------------------------------------------- 피격 반응(10-21)
## 사용자(10-21): "idle 히트 · 앉기 히트 · 누워서 히트 애니메이션을 쓰되, IK 히트 토글을 누르면 자세별 히트 애니메이션도 쓰지만 부위별 맞는 레이 히트
## 기준으로 맞는 IK 애니메이션이 보간되는 것도 · 이 애니메이션이 출력될 확률을 정하는 인풋 필드 — 잘 생각해야 해. UI/UX 적 배치도"
##   자세별 피격 동작 = 동작 표의 피격 · 피격+앉기 · 피격+엎드림(게임 화면이 hit_anim_chance 로 굴려 틀지 정한다 — BattleView3D._on_hit).
##   IK 피격 = hit_react(맞은 점, 총알 방향): 맞은 점에서 가장 가까운 뼈 마디(몸통 · 팔 · 다리는 굵기를 빼고 잰 거리)의 부위를 고르고, 그 부위의 뼈 사슬을
##   "맞은 점이 총알 방향으로 밀리게" 도는 축(사슬 뿌리 → 맞은 점 × 총알 방향)으로 젖혔다 돌아오게 한다. 세기 곡선 = (t/τ)·e^(1 − t/τ)(τ = 길이의 1/4 — 첫 장에서
##   거의 끝까지 젖혀지고 서서히 돌아옴). 여러 발이면 더한다(최대 HIT_MAX). 동작 위에 덧씌우므로 피격 동작을 틀어도 · 안 틀어도 같이.

## 부위 → 돌릴 뼈와 몫(아래부터). 몸에 없는 뼈는 빼고 나머지 몫을 다시 나눈다
const HIT_PARTS := {
	"머리": [["Neck", 0.4], ["Head", 0.6]],
	"가슴": [["Spine", 0.2], ["Chest", 0.35], ["UpperChest", 0.45]],
	"배": [["Spine", 0.55], ["Chest", 0.45]],
	"왼팔": [["LeftShoulder", 0.35], ["LeftUpperArm", 0.65]],
	"오른팔": [["RightShoulder", 0.35], ["RightUpperArm", 0.65]],
	"왼다리": [["LeftUpperLeg", 0.7], ["LeftLowerLeg", 0.3]],
	"오른다리": [["RightUpperLeg", 0.7], ["RightLowerLeg", 0.3]],
}
## 맞은 부위를 고르는 뼈 마디 [뼈, 끝 뼈("" = 그 뼈 위로 HIT_HEAD_LEN), 굵기 m, 부위]
const HIT_SEGS := [
	["Hips", "Spine", 0.15, "배"], ["Spine", "Chest", 0.15, "배"], ["Chest", "UpperChest", 0.15, "가슴"], ["UpperChest", "Neck", 0.15, "가슴"],
	["Neck", "Head", 0.06, "머리"], ["Head", "", 0.1, "머리"],
	["LeftUpperArm", "LeftLowerArm", 0.05, "왼팔"], ["LeftLowerArm", "LeftHand", 0.045, "왼팔"],
	["RightUpperArm", "RightLowerArm", 0.05, "오른팔"], ["RightLowerArm", "RightHand", 0.045, "오른팔"],
	["LeftUpperLeg", "LeftLowerLeg", 0.08, "왼다리"], ["LeftLowerLeg", "LeftFoot", 0.06, "왼다리"],
	["RightUpperLeg", "RightLowerLeg", 0.08, "오른다리"], ["RightLowerLeg", "RightFoot", 0.06, "오른다리"],
]
const HIT_HEAD_LEN := 0.2
## 동시에 도는 반응 수(기관총에 여러 발 — 넘치면 오래된 것부터 뺌)
const HIT_MAX := 4
## 총알 방향과 (사슬 뿌리 → 맞은 점)이 이루는 각의 사인이 이보다 작으면(30° 미만 — 앞으로 뻗은 팔을 앞에서) 아래로 쳐지게 섞는다.
## 안 섞으면 양손 잡기 씬에서 왼팔이 맞아도 팔꿈치가 거꾸로 1.2 cm(10-21 사용자 씬 실측)
const HIT_PUSH_MIN_SIN := 0.5
## 피격 칸(sync_from 이 옮긴다 — ① 탭 미리보기 사본)
const HIT_PROPS := ["hit_anim_chance", "hit_anim_max_sec", "hit_ik_enabled", "hit_ik_deg", "hit_ik_sec"]


## IK 피격 수정자를 만든다(refresh_equipment — 무기가 없어도). 조준 수정자 · 조준 팔 IK 바로 뒤, 받침대 풀이 · 손 IK 보다 앞
func _make_hit() -> void:
	_hits.clear()
	if _skel == null:
		return
	_hit_solver = HIT_SOLVER_SCRIPT.new()
	_hit_solver.name = "DR_HitSolver"
	_hit_solver.set("character", self)
	_skel.add_child(_hit_solver)
	var idx := 0
	for n in [_aim_solver, _aim_arm_pole, _aim_arm_ik, _aim_arm_rot]:
		if n != null:
			idx = maxi(idx, (n as Node).get_index() + 1)
	_skel.move_child(_hit_solver, idx)


## 손 IK 로 무기를 잡은 팔의 피격 수정자 — 손 IK 를 다 만든 뒤 맨 뒤에(손 IK 가 없으면 안 만듦)
func _make_hit_post() -> void:
	if _hit_solver == null or (_hands[0] == null and _hands[1] == null):
		return
	_hit_post = HIT_SOLVER_SCRIPT.new()
	_hit_post.name = "DR_HitArmSolver"
	_hit_post.set("character", self)
	_hit_post.set("after_hands", true)
	_skel.add_child(_hit_post)


## 총알이 맞은 점(세상 좌표) · 총알 방향(세상)으로 IK 피격을 건다 — 돌려주는 값 = 맞은 부위(머리 · 가슴 · 배 · 왼팔 · 오른팔 · 왼다리 · 오른다리, 몸에서 멀면 "").
## 반응은 다음 뼈대 갱신(step_motion)부터 보인다. hit_ik_enabled 가 꺼져 있으면 부위만 돌려준다. power = 세기 배율
func hit_react(point: Vector3, dir: Vector3, power := 1.0) -> String:
	if _skel == null:
		return ""
	var to_s := _skel.global_transform.affine_inverse() if _skel.is_inside_tree() else _skel_to_char().affine_inverse()
	var p := to_s * point
	var seg := _hit_seg_at(p)
	var part := String(seg[0])
	if part == "" or not hit_ik_enabled or _hit_solver == null or hit_ik_deg <= 0.0:
		return part
	var h := HitReaction.new()
	h.part = part
	h.side = 0 if part == "왼팔" else (1 if part == "오른팔" else -1)   # 그 손이 IK 로 잡고 있으면 손 IK 뒤에 돌린다(_hit_after_hand)
	var total := 0.0
	for b in HIT_PARTS[part]:
		var bi := _skel.find_bone(String(b[0]))
		if bi >= 0:
			h.bones.append(bi)
			h.shares.append(float(b[1]))
			total += float(b[1])
	if h.bones.is_empty():
		return part
	for i in h.shares.size():
		h.shares[i] /= total
	h.dir = (to_s.basis * dir).normalized()
	if h.dir.length_squared() < 0.5:
		return part
	h.bone = int(seg[1])
	h.local = _skel.get_bone_global_pose(h.bone).affine_inverse() * p
	h.amp = deg_to_rad(hit_ik_deg) * power
	_hits.append(h)
	if _hits.size() > HIT_MAX:
		_hits.remove_at(0)
	return part


## 뼈대 공간 점 p 에서 가장 가까운 부위(뼈 마디까지 거리 − 굵기). 몸에서 0.35 m 넘게 떨어지면 ""
func hit_part_at(p: Vector3) -> String:
	return String(_hit_seg_at(p)[0])


## [부위, 그 뼈 마디의 뼈] — hit_part_at
func _hit_seg_at(p: Vector3) -> Array:
	var best := ""
	var bb := -1
	var bd := 0.35
	for sg in HIT_SEGS:
		var a := _skel.find_bone(String(sg[0]))
		if a < 0:
			continue
		var ga := _skel.get_bone_global_pose(a)
		var bpos := ga.origin + ga.basis.y.normalized() * HIT_HEAD_LEN
		if String(sg[1]) != "":
			var b := _skel.find_bone(String(sg[1]))
			if b < 0:
				continue
			bpos = _skel.get_bone_global_pose(b).origin
		var d := p.distance_to(Geometry3D.get_closest_point_to_segment(p, ga.origin, bpos)) - float(sg[2])
		if d < bd:
			bd = d
			best = String(sg[3])
			bb = a
	return [best, bb]


## 지금 도는 IK 피격 반응 수(검사 · ① 탭)
func hit_count() -> int:
	return _hits.size()


## 지금 도는 반응들 [{part, t(초), angle(°)}] — 검사 · ① 탭
func hit_report() -> Array:
	var out: Array = []
	var tau := maxf(hit_ik_sec, 0.05) * 0.25
	for h in _hits:
		out.append({"part": h.part, "t": h.t, "angle": rad_to_deg(h.amp * (h.t / tau) * exp(1.0 - h.t / tau))})
	return out


## IK 피격 풀이 — 피격 수정자(조준 뒤 · 손 IK 앞)가 부른다. 시간을 흘려 끝난 반응을 빼고, 몸통 · 머리 · 다리 · 손 IK 없는 팔을 돌린다
func _solve_hits(sk: Skeleton3D) -> void:
	var dt := _hit_dt
	_hit_dt = 0.0
	if _hits.is_empty() or sk == null:
		return
	var dur := maxf(hit_ik_sec, 0.05)
	var i := _hits.size() - 1
	while i >= 0:
		var h := _hits[i]
		h.t += dt
		if h.t >= dur * 1.5:
			_hits.remove_at(i)
		i -= 1
	_solve_hit_pass(sk, false)


## 손 IK 로 무기를 잡은 팔 — 맨 뒤 피격 수정자가 부른다(손 IK 가 잡은 자세 위에 덧씌움 → 손이 총에서 튕겼다 돌아온다).
## 손 IK 앞에서 돌리면 IK 가 도로 잡아 팔꿈치만 0.8 cm, IK 를 풀면 팔이 동작 원래 자세로 튐(양손 잡기 씬 26 cm — 10-21)
func _solve_hits_after_hands(sk: Skeleton3D) -> void:
	if not _hits.is_empty() and sk != null:
		_solve_hit_pass(sk, true)


## 반응의 돌림 축 — 처음 돌릴 때 한 번, 그 수정자 차례의 자세로(손 IK 로 잡은 팔은 잡은 자세 — 동작 원래 자세와 6 cm 넘게 다를 수 있다).
## 사슬 뿌리를 축으로 맞은 점이 총알 방향으로 밀리게
func _hit_axis(sk: Skeleton3D, h: HitReaction) -> void:
	h.ready = true
	var r := sk.get_bone_global_pose(h.bone) * h.local - sk.get_bone_global_pose(h.bones[0]).origin
	var d := h.dir
	var s := r.cross(d).length() / maxf(r.length(), 1e-4)
	if s < HIT_PUSH_MIN_SIN:
		# 총알이 사슬을 따라 들어옴(겨눈 팔을 앞에서) — 돌림으로는 맞은 점이 총알 방향으로 거의 안 밀린다 → 아래로 쳐지는 몫을 섞는다
		d = (d + Vector3.DOWN * (1.0 - s / HIT_PUSH_MIN_SIN)).normalized()
	var axis := r.cross(d)
	if axis.length_squared() < 1e-8:
		axis = Vector3.UP.cross(d)
	if axis.length_squared() < 1e-8:
		h.amp = 0.0
		return
	h.axis = axis.normalized()


## 그 손이 IK 로 무엇을 잡고 있어 팔 피격을 손 IK 뒤에 넣는가
func _hit_after_hand(side: int) -> bool:
	var h: HandIK = _hands[side] if side >= 0 else null
	return h != null and h.w > 0.001 and _hit_post != null


## 반응들을 사슬에 몫만큼 돌린다 — after = 손 IK 뒤 몫(손 IK 로 잡은 팔)만 / 그 밖의 것만
func _solve_hit_pass(sk: Skeleton3D, after: bool) -> void:
	var tau := maxf(hit_ik_sec, 0.05) * 0.25
	for h in _hits:
		if _hit_after_hand(h.side) != after:
			continue
		if not h.ready:
			_hit_axis(sk, h)
		var a := h.amp * (h.t / tau) * exp(1.0 - h.t / tau)
		if absf(a) <= 1e-5:
			continue
		for k in h.bones.size():
			var bi := h.bones[k]
			var g := sk.get_bone_global_pose(bi)
			g.basis = Basis(h.axis, a * h.shares[k]) * g.basis
			sk.set_bone_global_pose(bi, g)


## 이 노드 아래(skip — 몸 모델 — 빼고)의 소켓(BoneAttachment3D)을 씬 순서대로. 소켓 안으로는 더 내려가지 않는다
static func find_sockets(root: Node, skip: Node = null) -> Array[BoneAttachment3D]:
	var out: Array[BoneAttachment3D] = []
	for a in find_anchors(root, skip):
		if a is BoneAttachment3D:
			out.append(a as BoneAttachment3D)
	return out


## 받침 전부 — 소켓(BoneAttachment3D) · 받침대(DRGripMount3D), 씬 순서. 받침 안으로는 더 내려가지 않는다
static func find_anchors(root: Node, skip: Node = null) -> Array[Node3D]:
	var out: Array[Node3D] = []
	_collect_anchors(root, skip, out)
	return out


static func _collect_anchors(n: Node, skip: Node, out: Array[Node3D]) -> void:
	for c in n.get_children():
		if c == skip:
			continue
		if c is BoneAttachment3D or c is DRGripMount3D:
			out.append(c as Node3D)
		else:
			_collect_anchors(c, skip, out)


## 장비 아래 그 손의 표지 — DRHandTarget3D(side 가 같은 것)가 먼저, 없으면 이름이 그 손("왼손" · "오른손")인 Node3D(모델 씬 속에 있어도 된다)
static func find_hand_marker(e: Node, side: int) -> Node3D:
	var by_name: Node3D = null
	var stack: Array[Node] = [e]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is DRHandTarget3D:
			if (n as DRHandTarget3D).side == side:
				return n as Node3D
		elif by_name == null and n is Node3D and String(n.name) == String(SIDE_NAMES[side]) and not (n is BoneAttachment3D):
			by_name = n as Node3D
		stack.append_array(n.get_children())
	return by_name


## 받침 a 아래 장비를 그 손(0 = 왼손 · 1 = 오른손)이 **기본으로**(동작별 비중이 없는 동작에서) 표지(IK)로 잡나 — 손 뼈 소켓이면 그 손은 장비를 들고
## (장비가 그 손을 따라가므로 IK 안 함), 한 손 받침대(10-27)는 그 손만, 두 손 사이 · 고정 받침대 · 손이 아닌 뼈 소켓은 두 손
static func anchor_grips(a: Node, side: int) -> bool:
	if a is BoneAttachment3D:
		return (a as BoneAttachment3D).bone_name != String(HAND_BONES[side])
	if a is DRGripMount3D:
		return (a as DRGripMount3D).grips(side)
	return true


## 그 손이 받침 a 아래 장비에 **붙을 수 있나**(IK 를 만드나) — 손 뼈 소켓의 그 손만 못 붙는다(장비가 그 손을 따라가므로 순환).
## 한 손 받침대의 다른 손도 IK 는 만든다(기본 비중 0 — 동작마다 잡기를 따로 주면 붙는다, 10-27)
static func anchor_can_grip(a: Node, side: int) -> bool:
	return not (a is BoneAttachment3D and (a as BoneAttachment3D).bone_name == String(HAND_BONES[side]))


## 표지 mk(받침 anchor 아래 장비의 그 손 표지)의 그 동작 비중 — 동작별 비중이 있으면 그것(= 그 동작의 잡기), 없으면 기본(표지 비중 × 받침의 기본 잡기)
static func marker_weight(mk: Node, anchor: Node, side: int, motion: String) -> float:
	if mk == null or anchor == null or not anchor_can_grip(anchor, side):
		return 0.0
	var base := 1.0 if anchor_grips(anchor, side) else 0.0
	if mk is DRHandTarget3D:
		var t := mk as DRHandTarget3D
		if motion != "" and t.motion_weights.has(motion):
			return clampf(float(t.motion_weights[motion]), 0.0, 1.0)
		return clampf(t.weight, 0.0, 1.0) * base
	return base


## 그 동작에서 장비 e 에 그 손이 붙는 정도(0 ~ 1) — 표지 없음 · 손 뼈 소켓의 그 손 = 0
static func hand_weight_for(e: Node, side: int, motion: String) -> float:
	if e == null or e.get_parent() == null:
		return 0.0
	return marker_weight(find_hand_marker(e, side), e.get_parent(), side, motion)


## 왼손 표지(예전 이름 — find_hand_marker(e, 0))
static func find_support(e: Node) -> Node3D:
	return find_hand_marker(e, 0)


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


## 그 손 팔 IK 수정자를 뼈대 아래에 만든다(주인 없는 노드 — 저장 안 됨, 몸을 다시 조립하면 같이 사라진다)
func _make_ik(side: int, marker: Node3D, anchor: Node3D) -> void:
	var ids := PackedInt32Array()
	for b in ARMS[side]:
		ids.append(_skel.find_bone(String(b)))
	var abone := _skel.find_bone((anchor as BoneAttachment3D).bone_name) if anchor is BoneAttachment3D else -1
	if ids.has(-1) or (anchor is BoneAttachment3D and abone < 0):
		push_warning("[DRCharacter3D] %s 팔 IK 뼈(%s)가 몸에 없습니다 — 그 손 표지를 쓰지 않음" % [SIDE_NAMES[side], ", ".join(PackedStringArray(ARMS[side]))])
		return
	ids.append(abone)
	var h := HandIK.new()
	h.side = side
	h.marker = marker
	h.anchor = anchor
	h.bones = ids
	var rig: DRRigModel = _body.get("rig", null)
	var part: DRRigModel.Part = rig.parts.get(String(PALM_PARTS[side]), null) if rig != null else null
	h.palm = part.tail_local * 0.5 if part != null else Vector3.ZERO
	var tag := String(SIDE_TAGS[side])
	h.wrist = Node3D.new()
	h.wrist.name = "DR_%sWrist" % tag
	if anchor is BoneAttachment3D:
		h.ref = ModifierBoneTarget3D.new()
		h.ref.name = "DR_%sRef" % tag
		_skel.add_child(h.ref)
		h.ref.bone_name = (anchor as BoneAttachment3D).bone_name
		h.ref.add_child(h.wrist)
	else:
		_skel.add_child(h.wrist)             # 받침대 — 목표를 뼈대 공간에 바로 두고 풀이 수정자(_solve_mounts)가 옮긴다
	h.pole = ModifierBoneTarget3D.new()
	h.pole.name = "DR_%sElbow" % tag
	_skel.add_child(h.pole)
	h.pole.bone_name = String(ARMS[side][1])
	h.ik = TwoBoneIK3D.new()
	h.ik.name = "DR_%sArmIK" % tag
	_skel.add_child(h.ik)
	h.ik.setting_count = 1
	h.ik.set_root_bone_name(0, String(ARMS[side][0]))
	h.ik.set_middle_bone_name(0, String(ARMS[side][1]))
	h.ik.set_end_bone_name(0, String(ARMS[side][2]))
	h.ik.set_target_node(0, h.ik.get_path_to(h.wrist))
	h.ik.set_pole_node(0, h.ik.get_path_to(h.pole))
	h.rot = CopyTransformModifier3D.new()
	h.rot.name = "DR_%sHandRot" % tag
	_skel.add_child(h.rot)
	h.rot.setting_count = 1
	h.rot.set_apply_bone_name(0, String(ARMS[side][2]))
	h.rot.set_reference_type(0, BoneConstraint3D.REFERENCE_TYPE_NODE)
	h.rot.set_reference_node(0, h.rot.get_path_to(h.wrist))
	h.rot.set_copy_flags(0, CopyTransformModifier3D.TRANSFORM_FLAG_ROTATION)
	_hands[side] = h


func _free_ik() -> void:
	var nodes: Array = [_solver, _aim_solver, _aim_arm_rot, _aim_arm_ik, _aim_arm_pole, _aim_hand, _hit_solver, _hit_post]
	for h in _hands:
		if h != null:
			nodes.append_array([(h as HandIK).rot, (h as HandIK).ik, (h as HandIK).pole, (h as HandIK).ref, (h as HandIK).wrist])
	for n in nodes:
		if n != null and is_instance_valid(n):
			var nn := n as Node
			if nn.get_parent() != null:
				nn.get_parent().remove_child(nn)
			nn.free()                          # 바로 — 같은 이름으로 다시 만들 때 겹치지 않게
	_solver = null
	_aim_solver = null
	_hit_solver = null
	_hit_post = null
	_hits.clear()
	_aim_arm_rot = null
	_aim_arm_ik = null
	_aim_arm_pole = null
	_aim_hand = null
	_aim_arm_hand = -1
	_aim_arm_on = false
	_hands = [null, null]


## 받침대 자리 · 받침대 쪽 손 IK 목표 — 풀이 수정자(뼈대 수정자 차례 맨 앞)가 부른다. 뼈 자세 = 동작 그대로(손 IK 전).
## 두 손 사이 받침대: 오른손 쪽 자리 ↔ 왼손 쪽 자리를 blend 로 보간 — 지금 그 받침대를 잡은(IK 비중이 있는) 손만 따른다(총을 놓는 동작에서 안 끌려가게)
func _solve_mounts(sk: Skeleton3D) -> void:
	if sk == null:
		return
	var sg := sk.global_transform
	var bl := -2
	var br := -2
	for m in _mounts:
		# 트리 밖(되돌리기로 방금 빠진 받침대 — 에디터가 다음에 다시 잇기 전까지 목록에 남는다)은 건너뜀
		if not is_instance_valid(m) or not m.is_inside_tree() or m.mode != DRGripMount3D.Mode.HANDS:
			continue
		if bl == -2:
			bl = sk.find_bone(String(HAND_BONES[0]))
			br = sk.find_bone(String(HAND_BONES[1]))
		if bl < 0 or br < 0:
			continue
		var r := sg * sk.get_bone_global_pose(br) * m.right_offset
		var l := sg * sk.get_bone_global_pose(bl) * m.left_offset
		var mt := r.interpolate_with(l, mount_t(m, _holding(0, m), _holding(1, m)))
		if _aim_arm_on and _sock_weapon != null and _sock_weapon.get_parent() == m and _muzzle.size() > 2:
			# 조준 팔 몫(10-21) — 견착점 축으로 받침대를 돌린다(두 손은 무기 표지 IK 로 따라감)
			var sb := sg.basis.orthonormalized()
			var qg := sb * Basis(_aim_arm_q) * sb.inverse()
			var butt := mt * (_sock_weapon.transform * (_muzzle[2] as Vector3))
			mt = Transform3D(qg * mt.basis, butt + qg * (mt.origin - butt))
		m.global_transform = mt
	for h in _hands:
		if h == null or (h as HandIK).ref != null or not is_instance_valid((h as HandIK).anchor) or not (h as HandIK).anchor.is_inside_tree():
			continue
		var hh := h as HandIK
		var mt := sg.affine_inverse() * hh.anchor.global_transform * hh.rel
		mt.basis = mt.basis.orthonormalized()
		hh.wrist.transform = mt * Transform3D(Basis.IDENTITY, -hh.palm)


## 손 기준 받침대가 오른손 쪽(0) ~ 왼손 쪽(1) 어디를 따라가나 — 잡은 손(비중 wl · wr)만 따른다: 왼손만 = 1 · 오른손만 = 0 · 두 손 · 아무도 안 잡음 = 보간
## (한 손 받침대는 그 손 쪽). 비중 사이는 겹선형(동작이 바뀌며 비중이 섞일 때 튀지 않게 — 기본 손이 놓고 다른 손만 잡는 동작, 10-27 동작마다 잡기)
static func mount_t(m: DRGripMount3D, wl: float, wr: float) -> float:
	var b := m.eff_blend()
	var l := clampf(wl, 0.0, 1.0)
	var r := clampf(wr, 0.0, 1.0)
	return l * (1.0 - r) + b * (l * r + (1.0 - l) * (1.0 - r))


## 그 손이 받침대 m 을 잡고 있는 정도(그 손 IK 가 m 의 장비 표지로 가면 IK 비중, 아니면 0)
func _holding(side: int, m: Node3D) -> float:
	var h: HandIK = _hands[side]
	return h.w if h != null and h.anchor == m else 0.0


## 받침 → 손 표지 변환을 IK 목표에 옮긴다 — 표지 · 장비를 옮긴 뒤(② 장비 탭이 부른다 · 편집 중인 씬은 매 프레임). 게임은 조립 때 한 번
func sync_support() -> void:
	for h in _hands:
		if h == null:
			continue
		var hh := h as HandIK
		if not is_instance_valid(hh.marker) or not is_instance_valid(hh.wrist):
			continue
		var rel := Transform3D.IDENTITY
		var n: Node = hh.marker
		while n != null and n != hh.anchor:
			if n is Node3D:
				rel = (n as Node3D).transform * rel
			n = n.get_parent()
		rel.basis = rel.basis.orthonormalized()     # 장비 배율은 뺀다(손 회전 · 손바닥 거리는 뼈대 단위)
		hh.rel = rel
		if hh.ref != null:
			var t := rel * Transform3D(Basis.IDENTITY, -hh.palm)
			if not t.is_equal_approx(hh.wrist.transform):
				hh.wrist.transform = t
	if _solver != null and _skel != null:
		_solve_mounts(_skel)                  # 받침대 쪽 목표도 바로(다음 갱신을 기다리지 않게)


## 그 손의 IK 비중 — 표지(DRHandTarget3D)의 동작별 비중. 동작이 없으면(레스트 자세) 0
func _hand_weight(side: int, motion: String) -> float:
	var h: HandIK = _hands[side]
	if h == null or h.ik == null or motion == "":
		return 0.0
	return marker_weight(h.marker, h.anchor, side, motion)


## 왼손 IK 비중(예전 이름)
func _support_weight(motion: String) -> float:
	return _hand_weight(0, motion)


func _set_hand_weight(side: int, w: float) -> void:
	var h: HandIK = _hands[side]
	if h == null or h.ik == null or not is_instance_valid(h.ik):
		return
	h.w = w
	var on := w > 0.001
	h.ik.active = on
	h.rot.active = on
	if on:
		h.ik.influence = w
		h.rot.influence = w


func _has_hand_ik() -> bool:
	return _hands[0] != null or _hands[1] != null


## 편집 중인 씬(에디터): 기즈모로 장비 · 표지를 옮기면 IK 목표를 바로 맞추고, 받침 · 장비를 더하거나 빼면(되돌리기 포함) 다시 잇는다
func _editor_follow(delta: float) -> void:
	if not _built:
		return
	sync_support()
	_equip_poll -= delta
	if _equip_poll <= 0.0:
		_equip_poll = 0.25
		if _socket_sig() != _equip_sig:
			refresh_equipment()


## 받침 구조(받침 · 뼈 · 방식 · 보이는 장비 · 표지) — 바뀌면 다시 잇는다
func _socket_sig() -> String:
	var parts := PackedStringArray()
	for a in find_anchors(self, _model):
		parts.append("%s>%s" % [a.name, (a as BoneAttachment3D).bone_name if a is BoneAttachment3D else
			"mount%d.%d" % [int((a as DRGripMount3D).mode), int((a as DRGripMount3D).hold)]])
		for c in a.get_children():
			if c is Node3D:
				var ml := find_hand_marker(c, 0)
				var mr := find_hand_marker(c, 1)
				parts.append("%d|%s|%s|%s" % [c.get_instance_id(), str((c as Node3D).visible), str(ml.get_instance_id()) if ml != null else "-",
					str(mr.get_instance_id()) if mr != null else "-"])
	return ";".join(parts)


## 지금 묶인 소켓들
func get_sockets() -> Array[BoneAttachment3D]:
	return _sockets.duplicate()


## 받침 전부(소켓 · 받침대)
func get_anchors() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for s in _sockets:
		out.append(s)
	for m in _mounts:
		out.append(m)
	return out


## 그 손 표지(IK 가 걸린 것 — 받침이 그 손이면 null)
func get_hand_marker(side: int) -> Node3D:
	var h: HandIK = _hands[side]
	return h.marker if h != null else null


## 왼손 표지(예전 이름)
func get_support_marker() -> Node3D:
	return get_hand_marker(0)


## 그 팔 IK(TwoBoneIK3D, 표지가 없으면 null) · 지금 비중 · 섞는 중이면 향하는 비중
func get_arm_ik(side: int) -> TwoBoneIK3D:
	var h: HandIK = _hands[side]
	return h.ik if h != null else null


func get_left_arm_ik() -> TwoBoneIK3D:
	return get_arm_ik(0)


func get_ik_weight(side: int = 0) -> float:
	var h: HandIK = _hands[side]
	return h.w if h != null else 0.0


func ik_target_weight(side: int = 0) -> float:
	var h: HandIK = _hands[side]
	if h == null:
		return 0.0
	return h.w_to if _grip_t >= 0.0 else h.w


## 소켓 장비 중 도트 재질을 입힌 메시(검사용)
func get_equipment_meshes() -> Array[MeshInstance3D]:
	return _equip_mis.duplicate()


## 그 손 IK 목표(표지 자리 · 회전)를 뼈대 공간으로 — 소켓 받침 = 받침 뼈의 지금 자세 기준, 받침대 = 받침대 노드의 지금 자리
func _target_skel(h: HandIK) -> Transform3D:
	if h.ref != null:
		return _skel.get_bone_global_pose(h.bones[3]) * h.rel
	if not is_instance_valid(h.anchor) or not h.anchor.is_inside_tree():
		return h.wrist.transform * Transform3D(Basis.IDENTITY, h.palm) if is_instance_valid(h.wrist) else Transform3D.IDENTITY
	var t := _skel.global_transform.affine_inverse() * h.anchor.global_transform * h.rel
	t.basis = t.basis.orthonormalized()
	return t


## 지금 뼈 자세 그대로 그 손바닥 ↔ 표지를 잰다(뼈대 공간) — skeleton_updated 신호 안에서 부르면 IK 뒤, 밖에서 부르면 동작 자세(수정자 전 —
## 갱신이 끝나면 뼈대가 동작 자세로 되돌아가 있다). {dist(m), rot(도), palm, target, hand(손 뼈 변환)} · 표지가 없으면 {}
func support_now(side: int = 0) -> Dictionary:
	var h: HandIK = _hands[side]
	if h == null or h.ik == null or _skel == null or h.bones.size() < 4:
		return {}
	var hand := _skel.get_bone_global_pose(h.bones[2])
	var tgt := _target_skel(h)                                     # 손바닥이 올 자리(원점) · 손 회전(기저)
	var palm := hand * h.palm
	return {
		"dist": palm.distance_to(tgt.origin), "palm": palm, "target": tgt.origin, "hand": hand,
		"rot": rad_to_deg(hand.basis.orthonormalized().get_rotation_quaternion().angle_to(tgt.basis.get_rotation_quaternion())),
	}


## 지금 자세에서 그 손이 표지에 얼마나 붙었나(② 장비 탭 · 검사) — 뼈대를 바로 한 번 갱신해 IK 뒤 손을 읽는다(자세는 그대로).
## {ik: IK 뒤 손바닥 ↔ 표지(m), raw: 동작 그대로의 손바닥 ↔ 표지(m), rot: IK 뒤 손 회전 ↔ 표지 회전(도),
##  reach: 어깨 → 손목 목표 / 팔 길이(1 넘으면 안 닿음), weight: 지금 IK 비중, palm · target(뼈대 공간)}. 표지가 없으면 {}
func support_report(side: int = 0) -> Dictionary:
	var h: HandIK = _hands[side]
	if h == null or h.ik == null or _skel == null or h.bones.size() < 4:
		return {}
	sync_support()
	var hb := h.bones[2]
	var rec := {}
	var cb := func() -> void: rec["ik"] = support_now(side)
	_skel.skeleton_updated.connect(cb)
	_skel.set_bone_pose_rotation(hb, _skel.get_bone_pose_rotation(hb))   # 갱신할 거리를 만든다(값은 그대로)
	_skel.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
	_skel.skeleton_updated.disconnect(cb)
	var raw := support_now(side)                                      # 수정자 전 = 동작 자세(받침대 자리는 방금 갱신에서 푼 값)
	var ik: Dictionary = rec.get("ik", raw)
	var sh := _skel.get_bone_global_pose(h.bones[0]).origin
	var el := _skel.get_bone_global_pose(h.bones[1]).origin
	var arm := sh.distance_to(el) + el.distance_to((raw["hand"] as Transform3D).origin)
	var wrist_t := _target_skel(h) * -h.palm                           # 손목 목표 = 표지 − 손바닥 거리(표지 회전으로)
	return {
		"ik": float(ik["dist"]), "raw": float(raw["dist"]), "rot": float(ik["rot"]),
		"reach": sh.distance_to(wrist_t) / maxf(arm, 1e-5),
		"weight": h.w, "palm": ik["palm"], "target": ik["target"],
	}
