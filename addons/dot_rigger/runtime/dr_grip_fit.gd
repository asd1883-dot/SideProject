@tool
extends RefCounted
class_name DRGripFit

## 무기 그립을 지금 몸 · 지금 동작의 두 손에 다시 맞춘다(10-15) — 3D 쪽 보정. asset.json 은 고치지 않는다.
## ※ 10-16 부터 옛 방식: 무기는 유닛 프리팹의 소켓 노드(BoneAttachment3D, ② 장비 탭)에 고정하고 왼손은 표지에 IK 로 붙인다
##   (DRCharacter3D "소켓 · 장비" 절). 이 파일은 소켓 무기가 없는 유닛의 weapon_asset 칸(옛 asset.json 그립)과 pose() 도우미로만 쓴다.
##
## asset.json 의 그립(grip_base · grip_frame · grip_pivot)은 장비 굽기 창이 DREquipBaker.auto_grip 으로 **그때의 그립 세트 레스트 자세**에서
## 잡은 값(손 뼈 로컬)이다. 10-15 확인: kar98k 의 그립은 10-12 굽기 때 세트가 Sprint 하나뿐이라 **달리기 자세(Sprint 62.5 %)** 의 두 손바닥으로
## 총열 방향을 잡은 것이었다(10-07 몸 · 그 자세에서 오른손 · 왼손 · 각 어긋남 0.00) — 소총을 든 자세가 아니라, 3D 소총 동작에서는
## 왼손이 총열에서 28~39 cm 떨어진다(2D 는 총 그림을 세트마다 화면 총열 방향으로 돌려 붙여 덜 드러났다). 손 뼈 변화(10-14 손가락 · 10-15
## 손 크기 · 팔 다시 리깅) 몫은 손 뼈 위치 1.8 cm · 손바닥 점 2.0 cm · 방향 0° 뿐.
## → 불러올 때 auto_grip 과 같은 계산을 **지금 몸 · 지금 동작의 소총 자세**로 다시 한다:
##   총열 = 붙일 손(R_Hand) 손바닥 → 받치는 손(L_Hand) 손바닥, 위 = 모델 위(+Y), 무기의 잡는 점 = 붙일 손 손바닥.
## 사용자가 창에서 손으로 준 조정(adj_pos · adj_rot · 세트 조정)은 그 위에 그대로 얹는다(DREquipBaker.compose_grip).
## Mixamo 소총 동작은 동작마다 두 손 사이가 달라(Rifle_Idle 에 맞추면 Firing_Rifle 왼손 19 cm · Walk_With_Rifle 11 cm) 하나로는 다 못 맞춘다 →
## 동작마다 맞춘 그립(fit_anim · apply_anim)을 동작을 바꿀 때 바꿔 끼운다(2D 의 세트별 조정 set_adjust 와 같은 뜻).
## 결과는 (asset · 몸 · 동작 라이브러리 · 자세) 별로 캐시 — 병사마다 다시 계산하지 않는다.
##
## 쓰는 예:  ch.attach_weapon(asset) ; DRGripFit.apply(ch)                  # 한 그립(기본 = Rifle_Idle 11.1 %)
##          ch.get_animation_player().play("Firing_Rifle") ; DRGripFit.apply_anim(ch, "Firing_Rifle")   # 동작별 그립
## set_motions 로 소총 동작이 든 라이브러리를 먼저 넣을 것. 처음 한 번은 자세를 잡아 재므로 불러오기 때 미리 불러 두면 좋다(그 뒤는 캐시).

## 그립을 잡을 자세 [동작 이름, 길이 비율] — 2D 장비 굽기의 그립 세트(sets.json 의 첫 소총 세트 stand = Rifle_Idle, 레스트 11.1 %)
const DEFAULT_POSES := [["Rifle_Idle", 0.111111]]

static var _cache := {}


## 그립을 다시 맞춰 캐릭터의 무기에 준다. 못 맞추면(무기 · 동작 없음) false — 그때는 asset.json 그립 그대로
static func apply(ch: DRCharacter3D, poses: Array = DEFAULT_POSES, set_name: String = "") -> bool:
	var r := fit(ch, poses, set_name)
	if r.is_empty():
		return false
	ch.set_weapon_grip(r["grip"])
	return true


## 동작 하나에 맞춘 그립(그 동작을 samples 등분한 시점들의 평균). 그 동작이 라이브러리에 없으면 {}
static func fit_anim(ch: DRCharacter3D, anim: String, samples: int = 6, set_name: String = "") -> Dictionary:
	var poses: Array = []
	for i in maxi(samples, 1):
		poses.append([anim, i / float(maxi(samples, 1))])
	return fit(ch, poses, set_name)


## 동작에 맞춘 그립을 캐릭터의 무기에 준다(동작을 바꿀 때 부른다). 못 맞추면 false — 그립은 그대로
static func apply_anim(ch: DRCharacter3D, anim: String, samples: int = 6, set_name: String = "") -> bool:
	var r := fit_anim(ch, anim, samples, set_name)
	if r.is_empty():
		return false
	ch.set_weapon_grip(r["grip"])
	return true


## 다시 맞춘 그립 {grip(손 뼈 로컬, 배율 전), base · frame · pivot(조정 전 자동 그립), poses(쓴 자세)}. 못 맞추면 {}
## poses 가 여럿이면 자세마다 잡은 자동 그립의 평균(회전 = 쿼터니언 평균)
static func fit(ch: DRCharacter3D, poses: Array = DEFAULT_POSES, set_name: String = "") -> Dictionary:
	var w := ch.get_weapon_entry()
	var body := ch.get_body_entry()
	var ap := ch.get_animation_player()
	var skel := ch.get_skeleton()
	if w.is_empty() or body.is_empty() or ap == null or skel == null:
		return {}
	var lib_id := ap.get_animation_library("").get_instance_id() if ap.has_animation_library("") else 0
	var key := "%s|%s|%d|%s|%s" % [String(w["asset"]), String(body["key"]), lib_id, str(poses), set_name]
	if _cache.has(key):
		return _cache[key]
	var rig: DRRigModel = body["rig"]
	var pa: DRRigModel.Part = rig.parts.get(String(w["part"]), null)
	var ps: DRRigModel.Part = rig.parts.get(String(w["support"]), null)
	if pa == null or ps == null or pa.root_bone < 0 or ps.root_bone < 0:
		push_warning("[DRGripFit] 손 파트가 없습니다: %s / %s" % [String(w["part"]), String(w["support"])])
		return {}
	# 지금 재생 상태를 기억했다가 되돌린다
	var keep_anim := ap.current_animation
	var keep_pos := ap.current_animation_position if keep_anim != "" else 0.0
	var keep_playing := ap.is_playing()
	var bases: Array = []
	var frames: Array = []
	var pivot := Vector3.ZERO
	var used: Array = []
	for pz in poses:
		var an := String((pz as Array)[0])
		if not ap.has_animation(an):
			continue
		pose(ch, an, float((pz as Array)[1]))
		var r := auto_grip_now(ch, pa, ps, w)
		if r.is_empty():
			continue
		bases.append(r["base"])
		frames.append(r["frame"])
		pivot = r["pivot"]
		used.append(pz)
	skel.reset_bone_poses()
	if keep_anim != "":
		ap.play(keep_anim)
		ap.seek(keep_pos, true)
		if not keep_playing:
			ap.pause()
	else:
		ap.stop()
	if bases.is_empty():
		push_warning("[DRGripFit] 그립을 잡을 동작이 라이브러리에 없습니다: %s" % str(poses))
		return {}
	var src: DREquipBaker = w["equip"]
	var eb := DREquipBaker.new()        # 조정 계산(compose_grip · _apply_adjust)만 빌린다 — 캐시된 것은 안 건드린다
	eb.adj_pos = src.adj_pos
	eb.adj_rot = src.adj_rot
	eb.set_adjust = src.set_adjust.duplicate(true)
	eb.grip_base = _avg_xform(bases)
	eb.grip_frame = _avg_xform(frames.map(func(b): return Transform3D(b, Vector3.ZERO))).basis
	eb.grip_pivot = pivot
	var out := {"grip": eb.compose_grip(set_name), "base": eb.grip_base, "frame": eb.grip_frame, "pivot": pivot, "poses": used}
	_cache[key] = out
	return out


## 동작 an 의 길이 × frac 시점 자세로 세운다(DRBaker.set_pose 와 같은 순서 — 먼저 레스트로 되돌려 트랙 없는 뼈에 앞 자세가 안 남게)
static func pose(ch: DRCharacter3D, an: String, frac: float) -> void:
	var ap := ch.get_animation_player()
	var skel := ch.get_skeleton()
	skel.reset_bone_poses()
	ap.play(an)
	ap.seek(clampf(frac, 0.0, 1.0) * ap.get_animation(an).length, true)
	ap.advance(0.0)
	skel.force_update_all_bone_transforms()


## 지금 자세에서 DREquipBaker.auto_grip 과 같은 계산(뼈대 공간 — 캐릭터가 돌거나 커져도 같은 값). {base, frame, pivot} 또는 {}
static func auto_grip_now(ch: DRCharacter3D, pa: DRRigModel.Part, ps: DRRigModel.Part, w: Dictionary) -> Dictionary:
	var skel := ch.get_skeleton()
	var hr := skel.get_bone_global_pose(pa.root_bone)
	var pr := hr * (pa.tail_local * 0.5)
	var pl := skel.get_bone_global_pose(ps.root_bone) * (ps.tail_local * 0.5)
	var d := pl - pr
	if d.length() < 0.0001:
		return {}
	d = d.normalized()
	var up := Vector3.UP
	if absf(d.dot(up)) > 0.98:
		up = Vector3.FORWARD
	var side := up.cross(d).normalized()
	var up2 := d.cross(side).normalized()
	var world_basis := Basis(side, up2, d)
	var f: Vector3 = w["forward"]
	var fix := Basis.IDENTITY
	if f.distance_to(Vector3(0, 0, 1)) > 0.001:
		if f.distance_to(Vector3(0, 0, -1)) < 0.001:
			fix = Basis(Vector3.UP, PI)
		else:
			fix = Basis(Quaternion(f, Vector3(0, 0, 1)))
	var b := world_basis * fix
	var gp: Vector3 = (w["grip_point"] as Vector3) * float(w["scale"])
	var hand_inv := hr.affine_inverse()
	return {"base": hand_inv * Transform3D(b, pr - b * gp), "frame": hand_inv.basis * world_basis, "pivot": hand_inv * pr}


## 지금 자세에서 두 손이 무기를 얼마나 쥐었나(m · 도). 잡을 자리 = 무기의 잡는 점 어림 − 조정 이동(손이 무기에 대해 있어야 할 곳 — 그립을 잡은 자세에서는 두 손바닥이 이 점을 지나는 총열 방향 직선 위에 온다)
##   r = 붙일 손 손바닥 ↔ 잡을 자리, l = 받치는 손 손바닥 ↔ 그 직선, l_along = 받치는 손이 직선을 따라 잡을 자리에서 앞으로 간 거리, angle = 총열 ↔ 두 손바닥 방향 각
static func measure(ch: DRCharacter3D) -> Dictionary:
	var w := ch.get_weapon_entry()
	var body := ch.get_body_entry()
	if w.is_empty() or body.is_empty():
		return {}
	var skel := ch.get_skeleton()
	var rig: DRRigModel = body["rig"]
	var pa: DRRigModel.Part = rig.parts.get(String(w["part"]), null)
	var ps: DRRigModel.Part = rig.parts.get(String(w["support"]), null)
	if pa == null or ps == null:
		return {}
	var hr := skel.get_bone_global_pose(pa.root_bone)
	var pr := hr * (pa.tail_local * 0.5)
	var pl := skel.get_bone_global_pose(ps.root_bone) * (ps.tail_local * 0.5)
	var s := float(w["scale"])
	var g := ch.get_weapon_grip()
	var wx := hr * Transform3D(g.basis * Basis.from_scale(Vector3.ONE * s), g.origin)
	var src: DREquipBaker = w["equip"]
	var hold_m: Vector3 = (w["grip_point"] as Vector3) - src.adj_pos / s        # 무기 모델 공간
	var f: Vector3 = w["forward"]
	var hold := wx * hold_m
	var axis := (wx.basis * f).normalized()
	var v := pl - hold
	var along := v.dot(axis)
	var d := pl - pr
	return {
		"r": pr.distance_to(hold),
		"l": (v - axis * along).length(),
		"l_along": along,
		"angle": rad_to_deg(axis.angle_to(d.normalized())) if d.length() > 1e-5 else 0.0,
		"palm_r": pr, "palm_l": pl, "weapon": wx,
	}


## 변환 평균(위치 = 산술 평균, 회전 = 부호 맞춘 쿼터니언 평균, 배율 = 첫 것)
static func _avg_xform(xs: Array) -> Transform3D:
	if xs.size() == 1:
		return xs[0]
	var b0: Basis = (xs[0] as Transform3D).basis
	var scl := b0.get_scale()
	var q0 := b0.get_rotation_quaternion()
	var acc := Vector4.ZERO
	var o := Vector3.ZERO
	for x in xs:
		var t: Transform3D = x
		var q := t.basis.get_rotation_quaternion()
		if q.dot(q0) < 0.0:
			q = -q
		acc += Vector4(q.x, q.y, q.z, q.w)
		o += t.origin
	var qa := Quaternion(acc.x, acc.y, acc.z, acc.w).normalized()
	return Transform3D(Basis(qa) * Basis.from_scale(scl), o / float(xs.size()))


static func clear_cache() -> void:
	_cache.clear()
