@tool
extends RefCounted
class_name DRMotionExporter

## 3D 동작 내보내기(10-15) — 3D 캐릭터를 게임에 바로 쓰는 노선용.
## DRBaker 가 모델을 불러올 때(setup) 메모리에서만 손보는 동작(추가 동작 폴더 얹기 · 손 레스트 방향 맞춤 · 손 자리 IK · 아래팔 비틀림 ·
## 제자리 · 상하체 합성)을 **그 setup 을 프리셋 값으로 그대로 불러** 꺼낸 뒤 AnimationLibrary(.res) 하나로 저장한다.
## 손 · 팔 처리를 여기서 따로 다시 짜면 2D 퍼펫과 3D 가 어긋나므로 같은 함수를 거친다.
## 저장해 두면 깨끗한 클론(54 MB 짜리 Mixamo FBX 를 git 에 안 올림)에서도 같은 동작을 쓴다.
##
## 계약(게임 쪽): 모델(프리셋 model_path, 지금 human_base.glb)을 그대로 인스턴스하고 그 AnimationPlayer 의 "" 라이브러리를 이것으로 바꿔 끼운다.
##   ap.remove_animation_library("")
##   ap.add_animation_library("", load("res://game/motions/rifleman_anims.res"))
##   ap.play("Rifle_Idle")
## - 트랙 경로는 전부 모델 자신의 트랙과 같은 꼴(`%GeneralSkeleton:<뼈>`) — 그 앞부분을 라이브러리 메타 `skeleton_path` 에 적는다.
##   (추가 동작 · 합성은 DRBaker 가 `Armature/GeneralSkeleton:<뼈>` 로 고쳐 써서 한 동작 안에도 두 꼴이 섞여 있었다)
## - 모든 동작이 같은 트랙 묶음을 갖는다 — 없는 뼈는 레스트 값 키 하나로 채운다. AnimationPlayer 는 기본(deterministic 꺼짐)이면
##   트랙이 없는 뼈를 건드리지 않아 앞 동작 자세가 남는다(10-15 실측: Firing_Rifle → Idle 에서 아래팔 비틀림 뼈가 46° 그대로).
##   2D 굽기는 자세마다 뼈를 레스트로 되돌린 뒤 재생하므로(DRBaker.set_pose · 02 C13) "트랙 없음 = 레스트" — 채워서 같은 뜻으로 만든다.

const DEFAULT_PRESET := "res://UAL1_preset.tres"
const DEFAULT_TABLE := "res://game/units/rifleman_motions.tres"
const DEFAULT_OUT := "res://game/motions/rifleman_anims.res"

## 반복 규칙. LOOP_SOURCE = 2D 퍼펫과 같은 규칙 — DRExporter 는 처리된 동작의 loop_mode 를 rig.json "loop" · 퍼펫 애니에 그대로 옮긴다
## (UAL 은 glTF 이름의 _Loop, Mixamo 는 .import 의 settings/loop_mode, 합성은 정의의 loop). LOOP_KEYS = 동작 표의 키로 정한다.
const LOOP_SOURCE := 0
const LOOP_KEYS := 1

## 동작 표(game/data/motion_table.gd · 보병_추상화 §2-5)의 상태 이름 조각. 애드온이 게임 클래스에 묶이지 않게 표는 이름으로만 읽는다
const MOVE_BASES := ["걷기", "달리기", "앉아걷기", "포복"]       # 이 바탕(+행동)에 쓰인 동작은 제자리로
const ONCE_OVERRIDES := ["사망", "피격"]                         # LOOP_KEYS: 이 덮어쓰기(+자세)는 한 번
const ONCE_ACTIONS := ["장전", "투척", "근접"]                   # LOOP_KEYS: 이 행동은 한 번
const DEATH_OVERRIDE := "사망"                                   # 사망 동작은 뿌리 이동을 그대로 둔다(뒤로 쓰러지며 밀려나는 것이 동작)
## 제자리로 안 만든 동작의 뿌리 수평 이동이 이보다 크면 경고(m)
const TRAVEL_WARN := 0.15
## 프리셋에 합성이 하나도 없을 때 새 합성의 설정(합성 창의 새 합성과 같은 값)
const COMPOSITE_DEFAULT := {"length_mode": 0, "loop": true, "upper_keep": 1.0, "upper_pitch": 0.0}
## 검사(verify)가 위치를 재는 뼈 — 손목 · 발목 · 머리
const CHECK_BONES := ["LeftHand", "RightHand", "LeftFoot", "RightFoot", "Head"]
const RESET_NAME := "RESET"

var preset_path := DEFAULT_PRESET
## "" 이면 표 없이(export_all 일 때만 의미가 있다)
var table_path := DEFAULT_TABLE
## 표 객체를 바로 줄 때(인스펙터 — 저장 안 한 고침까지). 주면 table_path 대신 이것
var table: Resource = null
## "" 이면 표의 library_path(DRMotionTable), 그것도 비면 DEFAULT_OUT
var out_path := ""
## true = 표와 상관없이 라이브러리의 동작 전부(표의 A+B 합성 · 제자리는 그대로 반영)
var export_all := false
## Animation.compress()(손실) — 기본 끔. 10-15 실측(표 23동작): 1022 KB → 312 KB 로 줄지만 동작 몇 개에서 손 · 발이 튄다
## (Stand_Rifle_Hit_To_Back 541 mm · Crawl_Fwd 355 mm · Crouch_Idle+Toss_Grenade 286 mm, 나머지는 0.1 ~ 0.2 mm).
## 표본 fps 를 30 · 60 으로 바꿔도 튀는 동작만 달라진다(최대 79 · 541 mm). 회전 키 부호를 이웃 키와 이어 붙여도 그대로였다 —
## 원인은 압축 형식의 회전 부호화(축-각)로 추정, 확인은 안 함. 켜려면 --check 로 튀는 동작이 없는지 꼭 볼 것.
## (참고: Animation.optimize() 도 860 KB 로 16 % 만 줄고 3 ~ 20 mm 어긋나 쓰지 않는다)
var compress := false
## ResourceSaver.FLAG_COMPRESS(무손실 zstd) — 1589 KB → 1022 KB, 오차 0
var save_compressed := true
var loop_rule := LOOP_SOURCE
## RESET(레스트 자세 · 모든 트랙 키 하나) 동작을 넣는다 — 블렌드 기준(AnimationTree · deterministic) · 에디터 저장 시 되돌림 · 풀에서 꺼낼 때 초기화용
var add_reset := true

# ---- 결과 ----
var baker: DRBaker
var library: AnimationLibrary
var model_path := ""
## 트랙 경로 앞부분(모델의 첫 트랙에서) — 예: "%GeneralSkeleton"
var skeleton_path := ""
## 내보낸 동작마다 { name, keys, length, loop, loop_src, loop_keys, in_place, travel, tracks, filled, composite }
var motions: Array = []
var warnings := PackedStringArray()
## 표에 있는데 라이브러리에 없는 동작(임포트 안 됨 · 합성 실패 등) — "이름 (상태 키들)"
var missing := PackedStringArray()
## 제자리로 만든 동작(내보낸 것만)
var in_place_names := PackedStringArray()
var file_size := 0

var _uses: Dictionary = {}       # 동작 이름 -> PackedStringArray(그 동작을 쓰는 상태 키)
var _order: PackedStringArray    # 표에 처음 나온 순서
var _defs: Array = []            # setup 에 넘긴 합성 정의(새로 만든 것 포함)
var _table_defs: Array = []      # 표(DRMotionTable)의 상하체 합성 줄이 준 합성 정의 — 같은 이름이면 프리셋 것보다 먼저


## 내보내기 한 번. host = DRBaker 의 뷰포트를 붙일 노드(CLI 는 SceneTree.root). 결과 요약을 돌려준다.
func run(host: Node) -> Dictionary:
	if not build(host):
		return {"ok": false, "warnings": warnings}
	var err := save()
	if err != OK:
		warnings.append("저장 실패(%s): %s" % [error_string(err), out_path])
		return {"ok": false, "warnings": warnings}
	return {"ok": true, "path": out_path, "size": file_size, "count": motions.size(), "missing": missing, "warnings": warnings}


## 프리셋 · 표를 읽어 DRBaker 를 세우고 library 를 만든다(저장은 save()).
func build(host: Node) -> bool:
	warnings = PackedStringArray()
	missing = PackedStringArray()
	motions = []
	in_place_names = PackedStringArray()
	_uses = {}
	_order = PackedStringArray()
	_table_defs = []
	var preset := load(preset_path) as DRPreset if ResourceLoader.exists(preset_path) else null
	if preset == null:
		warnings.append("프리셋을 열 수 없습니다: %s" % preset_path)
		return false
	model_path = preset.model_path
	var scene := load(model_path) as PackedScene if ResourceLoader.exists(model_path) else null
	if scene == null:
		warnings.append("모델을 열 수 없습니다: %s" % model_path)
		return false
	if not _read_table():
		if not export_all:
			warnings.append("동작 표를 열 수 없습니다: %s" % table_path)
			return false
	if out_path == "":
		out_path = DEFAULT_OUT
	_report_mixed_uses()

	# 합성 — 표의 상하체 합성 줄(10-16, 인스펙터에서 정한 설정이 이긴다) + 프리셋 것 + 표에 A+B 꼴로 적혔는데 어디에도 없는 것(첫 합성의 설정을 본뜸)
	_defs = []
	var have := {}
	for d in _table_defs:
		_defs.append((d as Dictionary).duplicate(true))
		have[DRBaker.composite_name(d)] = true
	for d in preset.composites:
		if have.has(DRBaker.composite_name(d)):
			continue
		_defs.append((d as Dictionary).duplicate(true))
		have[DRBaker.composite_name(d)] = true
	var tpl: Dictionary = (preset.composites[0] as Dictionary) if preset.composites.size() > 0 else COMPOSITE_DEFAULT
	for m in _order:
		var plus := m.find("+")
		if plus <= 0 or plus >= m.length() - 1 or have.has(m):
			continue
		var nd := {"name": "", "lower": m.substr(0, plus), "upper": m.substr(plus + 1),
			"length_mode": int(tpl.get("length_mode", 0)), "loop": bool(tpl.get("loop", true)),
			"upper_keep": float(tpl.get("upper_keep", 1.0)), "upper_pitch": float(tpl.get("upper_pitch", 0.0))}
		_defs.append(nd)
		have[m] = true
		warnings.append("%s — 프리셋 합성에 없어 만듦(첫 합성 설정을 본뜸: 길이 맞춤 %d · 반복 %s · 상체 방향 유지 %.2f · 몸통 각도 %.1f°)" % [
			m, int(nd["length_mode"]), "켬" if bool(nd["loop"]) else "끔", float(nd["upper_keep"]), float(nd["upper_pitch"])])

	# 제자리 — 프리셋 in_place + 이동 키(걷기 · 달리기 · 앉아걷기 · 포복 [+행동])에 쓰인 동작
	var ip := PackedStringArray(preset.in_place)
	for m in _order:
		if _any_key(m, "move") and not ip.has(m):
			ip.append(m)
	for m in ip:
		if _any_key(m, "death"):
			warnings.append("%s — 사망 키에도 쓰이는데 제자리로 만듦(이동 키 · 프리셋 in_place)" % m)

	var opts := DRBaker.Options.new()      # 창의 _opts_from_preset 과 같은 값(동작에 닿는 것만 의미 있음)
	opts.extra_anim_dir = preset.extra_anim_dir
	opts.bleed_rings = preset.bleed_rings
	opts.composites = _defs
	opts.composite_upper_parts = preset.composite_upper_parts
	opts.in_place = ip
	baker = DRBaker.new()
	if not baker.setup(host, scene, DRPartProfile.humanoid(), opts):
		warnings.append("DRBaker setup 실패: %s" % model_path)
		return false
	if baker.viewport != null:
		baker.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED    # 동작만 꺼낸다 — 렌더 안 함
	for w in baker.extra_anim_warnings:
		warnings.append("추가 동작: " + w)
	for w in baker.composite_warnings:
		warnings.append("합성: " + w)
	if baker.anim_player == null:
		warnings.append("모델에 AnimationPlayer 가 없습니다")
		return false
	skeleton_path = _detect_skeleton_path()

	# 내보낼 이름
	var names := PackedStringArray()
	if export_all:
		for an in baker.anim_player.get_animation_list():
			var s := String(an)
			if s != RESET_NAME and s != DRBaker.PREVIEW_ANIM:
				names.append(s)
	for m in _order:
		if baker.anim_player.has_animation(m):
			if not names.has(m):
				names.append(m)
		else:
			var near := baker.resolve_anim(m)
			missing.append("%s (%s)%s" % [m, ", ".join(_uses[m]), (" — 비슷한 이름 %s 은 있음(표는 정확한 이름이어야 함)" % near) if near != "" else ""])
	names.sort()

	# 사본 → 경로 한 꼴 → 트랙 묶음 맞춤
	var out := {}
	for n in names:
		var a := baker.anim_player.get_animation(n).duplicate(true) as Animation   # 모델 자신의 동작은 가져온(캐시된) 것 — 사본을 고친다
		_unify_paths(a, n)
		_continuous_quats(a)
		out[n] = a
	var union := _track_union(out)
	library = AnimationLibrary.new()
	var idx := 0
	if add_reset and not union.is_empty():
		var r := Animation.new()
		r.length = 0.001                               # 에디터가 만드는 RESET 과 같은 길이
		_fill_missing(r, union)
		r.resource_name = RESET_NAME
		r.resource_scene_unique_id = "anim_reset"      # 저장할 때마다 무작위 id 가 붙지 않게(두 번 돌려도 같은 파일)
		library.add_animation(RESET_NAME, r)
	for n in names:
		var a: Animation = out[n]
		var filled := _fill_missing(a, union)
		var src_loop := a.loop_mode
		var key_loop := _loop_by_keys(n)
		if loop_rule == LOOP_KEYS and key_loop >= 0:
			a.loop_mode = key_loop as Animation.LoopMode
		var is_ip := baker.opts.in_place.has(n)        # 원래 제자리였던 동작(UAL Sprint 등)도 포함
		var travel := baker.root_travel(n)             # 제자리로 만든 동작은 만들기 전 거리
		if is_ip:
			in_place_names.append(n)
		elif travel > TRAVEL_WARN and not _any_key(n, "death"):
			warnings.append("%s — 뿌리가 %.2f m 수평 이동(제자리 아님 · %s)" % [n, travel, ", ".join(_uses.get(n, PackedStringArray(["표에 없음"])))])
		if compress:
			a.compress()
		a.resource_name = n
		a.resource_scene_unique_id = "anim_%03d" % idx
		idx += 1
		library.add_animation(n, a)
		motions.append({"name": n, "keys": _uses.get(n, PackedStringArray()), "length": a.length, "loop": a.loop_mode,
			"loop_src": src_loop, "loop_keys": key_loop, "in_place": is_ip, "travel": travel, "tracks": a.get_track_count(),
			"filled": filled, "composite": baker.composite_anims.has(n)})
	library.set_meta("skeleton_path", skeleton_path)
	library.set_meta("model_path", model_path)
	library.set_meta("in_place", in_place_names)
	return true


func save() -> int:
	if library == null:
		return ERR_UNCONFIGURED
	var dir := out_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var e := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		if e != OK:
			return e
	var err := ResourceSaver.save(library, out_path, ResourceSaver.FLAG_COMPRESS if save_compressed else 0)
	if err == OK:
		var f := FileAccess.open(out_path, FileAccess.READ)
		file_size = f.get_length() if f != null else 0
	return err


func cleanup() -> void:
	if baker != null:
		baker.cleanup()


## 반복 규칙의 차이 — 표 키로 정한 값이 2D(처리된 동작) 값과 다른 동작들 [{name, keys, src, keys_loop}]
func loop_disagreements() -> Array:
	var out: Array = []
	for e in motions:
		var d: Dictionary = e
		var kl := int(d["loop_keys"])
		if kl >= 0 and (kl != Animation.LOOP_NONE) != (int(d["loop_src"]) != Animation.LOOP_NONE):
			out.append(d)
	return out


# ───────────── 검사 ─────────────

## 저장한 파일을 다시 읽어 새 모델 인스턴스(AnimationPlayer "" 라이브러리 교체)에서 재생한 뼈 자세를
## DRBaker 메모리 라이브러리로 재생한 자세(set_pose — 뼈를 레스트로 되돌린 뒤 재생)와 비교한다.
## 새 인스턴스 쪽은 뼈를 되돌리지 않고 동작을 차례로 바꿔 재생한다(게임과 같게 — 앞 동작 자세가 남으면 여기서 드러난다).
## 돌려주는 값 { ok, worst_mm, motions: {이름: {mm, bone, t, samples}}, hips: {제자리 동작: {start_end_mm, sway_mm}} }
func verify(host: Node, path: String = "") -> Dictionary:
	if path == "":
		path = out_path
	var lib := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as AnimationLibrary
	if lib == null or baker == null:
		return {"ok": false, "error": "라이브러리를 읽을 수 없음: %s" % path}
	var scene := load(String(lib.get_meta("model_path", model_path))) as PackedScene
	var inst := scene.instantiate() as Node3D
	host.add_child(inst)
	var ap := DRBaker._find_node(inst, "AnimationPlayer") as AnimationPlayer
	var sk := DRBaker._find_node(inst, "Skeleton3D") as Skeleton3D
	if ap == null or sk == null:
		inst.queue_free()
		return {"ok": false, "error": "모델에 AnimationPlayer / Skeleton3D 없음"}
	if ap.has_animation_library(""):
		ap.remove_animation_library("")
	ap.add_animation_library("", lib)
	ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var m_new := DRBaker._xform_to(inst, sk)
	var m_ref := DRBaker._xform_to(baker.model_root, baker.skeleton)
	var bones: Array = []      # [[이름, 새 번호, 기준 번호]]
	for bn in CHECK_BONES:
		var a := sk.find_bone(bn)
		var b := baker.skeleton.find_bone(bn)
		if a >= 0 and b >= 0:
			bones.append([bn, a, b])
	var res := {}
	var worst := 0.0
	for an in lib.get_animation_list():
		var n := String(an)
		if n == RESET_NAME or not baker.anim_player.has_animation(n):
			continue
		var anim := lib.get_animation(n)
		var len_s := maxf(anim.length, 0.0001)
		var steps := maxi(8, int(ceil(len_s * 15.0)))
		var times := PackedFloat32Array()
		for i in steps:
			times.append(len_s * float(i) / float(steps))              # 키 자리(30 fps 의 배수 근처)
			times.append(len_s * (float(i) + 0.37) / float(steps))     # 키 사이(보간)
		if anim.loop_mode == Animation.LOOP_NONE and baker.anim_player.get_animation(n).loop_mode == Animation.LOOP_NONE:
			times.append(len_s)
		var mx := -1.0
		var mx_bone := ""
		var mx_t := 0.0
		for t in times:
			baker.set_pose(n, t)
			ap.play(n)
			ap.seek(t, true)
			sk.force_update_all_bone_transforms()
			for b in bones:
				var p_new := m_new * sk.get_bone_global_pose(int(b[1])).origin
				var p_ref := m_ref * baker.skeleton.get_bone_global_pose(int(b[2])).origin
				var d := p_new.distance_to(p_ref) * 1000.0
				if d > mx:
					mx = d
					mx_bone = String(b[0])
					mx_t = t
		res[n] = {"mm": mx, "bone": mx_bone, "t": mx_t, "samples": times.size()}
		worst = maxf(worst, mx)
	# 제자리 동작: 힙의 수평 자리 처음 → 끝(반복 지점 바로 앞) · 가장 멀리 간 거리
	var hips := {}
	var hb := sk.find_bone("Hips")
	var meta_ip: PackedStringArray = lib.get_meta("in_place", PackedStringArray())
	for n in meta_ip:
		if hb < 0 or not lib.has_animation(n):
			continue
		var anim := lib.get_animation(n)
		var p0 := Vector3.ZERO
		var sway := 0.0
		var se := 0.0
		var steps := maxi(8, int(ceil(anim.length * 30.0)))
		for i in steps + 1:
			var t := minf(anim.length * float(i) / float(steps), anim.length - 0.001)
			ap.play(n)
			ap.seek(t, true)
			sk.force_update_all_bone_transforms()
			var p := m_new * sk.get_bone_global_pose(hb).origin
			p.y = 0.0
			if i == 0:
				p0 = p
			sway = maxf(sway, p.distance_to(p0) * 1000.0)
			se = p.distance_to(p0) * 1000.0
		hips[n] = {"start_end_mm": se, "sway_mm": sway, "orig_travel_m": baker.root_travel(n)}
	inst.queue_free()
	return {"ok": true, "worst_mm": worst, "motions": res, "hips": hips}


# ───────────── 안쪽 ─────────────

## 표를 읽는다. DRMotionTable(10-16 — 상태마다 동작 여러 개 · 상하체 합성 줄)이면 줄마다, 예전 표면 이름으로만
## (motions: Dictionary[String, String], default_motion: String). out_path 가 비면 표의 library_path. 실패면 false
func _read_table() -> bool:
	var res: Resource = table
	if res == null:
		if table_path == "" or not ResourceLoader.exists(table_path):
			return false
		res = load(table_path)
	if res == null:
		return false
	if res is DRMotionTable:
		var t := res as DRMotionTable
		if out_path == "":
			out_path = t.library_path
		for c in t.clips:
			if c != null:
				_use(c.play_name(), c.state)
		if t.default_motion != "":
			_use(t.default_motion, "(기본 동작)")
		_table_defs = t.composite_defs()
		if out_path == "":
			out_path = DEFAULT_OUT
		return true
	if out_path == "":
		out_path = DEFAULT_OUT
	var m: Variant = res.get("motions")
	if not (m is Dictionary):
		return false
	for k in (m as Dictionary).keys():
		_use(String((m as Dictionary)[k]), String(k))
	var dm: Variant = res.get("default_motion")
	if dm != null and String(dm) != "":
		_use(String(dm), "(기본 동작)")
	return true


func _use(motion: String, key: String) -> void:
	if motion == "":
		return
	if not _uses.has(motion):
		_order.append(motion)
	var keys: PackedStringArray = _uses.get(motion, PackedStringArray())
	keys.append(key)
	_uses[motion] = keys       # Packed 배열은 값으로 복사된다 — 꺼내서 고친 뒤 다시 넣는다


## 키 종류: "move"(이동 바탕) · "death" · "once"(LOOP_KEYS 에서 한 번) · "loop"
static func key_kind(key: String) -> PackedStringArray:
	var parts := key.split("+")
	var out := PackedStringArray()
	if MOVE_BASES.has(parts[0]):
		out.append("move")
	if parts[0] == DEATH_OVERRIDE:
		out.append("death")
	var once := ONCE_OVERRIDES.has(parts[0])
	for i in range(1, parts.size()):
		if ONCE_ACTIONS.has(parts[i]):
			once = true
	if key != "(기본 동작)":
		out.append("once" if once else "loop")
	return out


func _any_key(motion: String, kind: String) -> bool:
	for k in _uses.get(motion, PackedStringArray()):
		if key_kind(String(k)).has(kind):
			return true
	return false


## 표 키로 정한 반복(LOOP_NONE · LOOP_LINEAR). 표에 없거나 한 번 · 반복 키에 같이 쓰이면 -1
func _loop_by_keys(motion: String) -> int:
	var once := _any_key(motion, "once")
	var loop := _any_key(motion, "loop")
	if once == loop:
		return -1
	return Animation.LOOP_NONE if once else Animation.LOOP_LINEAR


## 한 동작이 서로 다른 종류의 키(한 번 ↔ 반복, 이동 ↔ 사망)에 같이 쓰이면 경고
func _report_mixed_uses() -> void:
	for m in _order:
		if _any_key(m, "once") and _any_key(m, "loop"):
			warnings.append("%s — 한 번 키와 반복 키에 같이 쓰임(%s)" % [m, ", ".join(_uses[m])])
		if _any_key(m, "move") and _any_key(m, "death"):
			warnings.append("%s — 이동 키와 사망 키에 같이 쓰임(%s)" % [m, ", ".join(_uses[m])])


## 모델 자신의 동작(추가 동작 · 합성이 아닌 것)의 첫 뼈 트랙에서 뼈대 경로 앞부분을 읽는다. 없으면 AnimationPlayer 기준 상대 경로
func _detect_skeleton_path() -> String:
	var ap_root := baker.anim_player.get_node_or_null(baker.anim_player.root_node)
	for an in baker.anim_player.get_animation_list():
		var n := String(an)
		if baker.extra_anims.has(n) or baker.composite_anims.has(n) or n == DRBaker.PREVIEW_ANIM:
			continue
		var a := baker.anim_player.get_animation(n)
		for ti in a.get_track_count():
			var p := a.track_get_path(ti)
			if p.get_concatenated_subnames() == "":
				continue
			var head := String(p.get_concatenated_names())
			if ap_root != null and ap_root.get_node_or_null(NodePath(head)) == baker.skeleton:
				return head
			break
	var fb := DRBaker._rel_path(ap_root, baker.skeleton)
	warnings.append("모델 동작에서 뼈대 경로를 못 읽어 AnimationPlayer 기준 경로(%s)를 씀" % fb)
	return fb


## 모든 뼈 트랙을 skeleton_path:<뼈> 한 꼴로. 뼈대가 아닌 노드 · 없는 뼈 · 같은 뼈 같은 종류가 겹친 트랙은 뺀다(경고)
func _unify_paths(a: Animation, n: String) -> void:
	var ap_root := baker.anim_player.get_node_or_null(baker.anim_player.root_node)
	var seen := {}
	var drop: Array[int] = []
	var dup := 0
	for ti in a.get_track_count():
		var p := a.track_get_path(ti)
		var bone := String(p.get_concatenated_subnames())
		var node: Node = ap_root.get_node_or_null(NodePath(String(p.get_concatenated_names()))) if ap_root != null else null
		var tt := a.track_get_type(ti)
		if node != baker.skeleton or bone == "" or baker.skeleton.find_bone(bone) < 0 \
				or (tt != Animation.TYPE_POSITION_3D and tt != Animation.TYPE_ROTATION_3D and tt != Animation.TYPE_SCALE_3D):
			drop.append(ti)
			continue
		var key := "%s|%d" % [bone, tt]
		if seen.has(key):
			drop.append(ti)
			dup += 1
			continue
		seen[key] = true
		var np := NodePath("%s:%s" % [skeleton_path, bone])
		if np != p:
			a.track_set_path(ti, np)
	drop.reverse()
	for ti in drop:
		a.remove_track(ti)
	if drop.size() > dup:
		warnings.append("%s — 뼈대 뼈가 아닌 트랙 %d개 뺌" % [n, drop.size() - dup])
	if dup > 0:
		warnings.append("%s — 같은 뼈 · 같은 종류 트랙이 겹쳐 %d개 뺌(앞 것을 남김)" % [n, dup])


## 회전 키의 부호를 이웃 키와 같은 쪽(dot ≥ 0)으로 — q 와 −q 는 같은 회전이고 보통 재생(slerp)은 늘 짧은 쪽으로 돌아 결과가 같다.
## 손 IK 는 프레임마다 회전을 따로 구해(get_rotation_quaternion) 부호가 뒤집힌 키가 섞인다(Toss_Grenade 10곳 · Crouch_Reload 12곳, 10-15).
## 게임 쪽이 키 값을 직접 섞거나(lerp) 다른 도구로 옮길 때 긴 쪽으로 도는 일을 막는다(재생 결과는 그대로 — 검사 0 mm).
static func _continuous_quats(a: Animation) -> int:
	var flips := 0
	for ti in a.get_track_count():
		if a.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var prev := Quaternion.IDENTITY
		for k in a.track_get_key_count(ti):
			var q: Quaternion = a.track_get_key_value(ti, k)
			if k > 0 and prev.dot(q) < 0.0:
				q = -q
				a.track_set_key_value(ti, k, q)
				flips += 1
			prev = q
	return flips


## 내보낼 동작들의 뼈 트랙 합집합 [[뼈 번호, 종류] …](뼈 번호 · 종류 순 — 매번 같은 순서)
func _track_union(out: Dictionary) -> Array:
	var u := {}
	for n in out.keys():
		var a: Animation = out[n]
		for ti in a.get_track_count():
			var bi := baker.skeleton.find_bone(String(a.track_get_path(ti).get_concatenated_subnames()))
			u[bi * 8 + a.track_get_type(ti)] = [bi, a.track_get_type(ti)]
	var ks := u.keys()
	ks.sort()
	var arr: Array = []
	for k in ks:
		arr.append(u[k])
	return arr


## 없는 트랙을 레스트 값 키 하나로 채운다. 돌려주는 값 = 채운 트랙 수.
## 위치 트랙 값은 재생할 때 Skeleton3D.motion_scale 이 곱해지므로(리타깃이 힙 높이로 나눠 둔 값) 레스트 ÷ motion_scale 로 넣는다
func _fill_missing(a: Animation, union: Array) -> int:
	var sk := baker.skeleton
	var count := 0
	for e in union:
		var bi: int = e[0]
		var tt: int = e[1]
		var path := NodePath("%s:%s" % [skeleton_path, sk.get_bone_name(bi)])
		if a.find_track(path, tt as Animation.TrackType) >= 0:
			continue
		var rest := sk.get_bone_rest(bi)
		var ti := a.add_track(tt as Animation.TrackType)
		a.track_set_path(ti, path)
		a.track_set_interpolation_type(ti, Animation.INTERPOLATION_LINEAR)
		if tt == Animation.TYPE_POSITION_3D:
			a.position_track_insert_key(ti, 0.0, rest.origin / maxf(sk.motion_scale, 0.0001))
		elif tt == Animation.TYPE_ROTATION_3D:
			a.rotation_track_insert_key(ti, 0.0, rest.basis.get_rotation_quaternion())
		else:
			a.scale_track_insert_key(ti, 0.0, rest.basis.get_scale())
		count += 1
	return count
