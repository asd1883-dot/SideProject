extends RefCounted

## 운용 장비 자리 표시 — 모델이 아직 없어서(10-21: MG42 는 안 구움) 선 · 점 · 글자로 장비 · 좌석을 그린다.  (보병_추상화.md §2-13 ⑤)
## BattleView(2D)와 BattleView3D 가 같이 쓴다: 땅 층(_bg — 병사 뒤)에 장비 몸 · 좌석 자리, 글자 층(_fg — 병사 위)에 이름 · 상태.
##   총몸 · 총열 = 굵은 선(총구 쪽으로) · 라페테 다리 = 두 갈래 선 · 좌석 = 땅 위 동그라미(앉은 병사가 있으면 채움, 사수 = 큰 것)
##   색 = 운용하는 편, 버려진 장비 = 회색. 들고 가는 중이면 운반병 어깨 위에 짧은 막대
## 장비 종류에 모습 프리팹(EquipmentType.prefab)이 생기면 그것으로 바꾼다(좌석 자리 = 프리팹의 Marker3D).

const ABANDONED := Color(0.7, 0.7, 0.7, 0.9)
const LEG_SPREAD_M := 0.45
const CARRY_LEN_M := 1.0


static func _color(eq: BattleEquipment) -> Color:
	if eq.squad == null:
		return ABANDONED
	return BattleView.TEAM_LINE[clampi(eq.team, 0, 1)]


## 땅 층 — 장비 몸 · 좌석 자리(놓인 · 설치된 장비만. 들고 가는 장비는 글자 층에서 운반병 위에)
static func draw_ground(v: BattleView, ci: Node2D, bf: Battlefield) -> void:
	for eq in bf.equipments:
		if eq.state == BattleEquipment.State.CARRIED:
			continue
		var col := _color(eq)
		var f := float(eq.facing)
		var d := eq.depth
		var g := v.vis_ground(eq.x, d)                  # 참호 버전 도랑 안이면 내려 그린다(병사와 같이)
		var mh := eq.type.muzzle_height
		var up := eq.state == BattleEquipment.State.READY or eq.state == BattleEquipment.State.TEARDOWN
		if eq.state == BattleEquipment.State.DROPPED:
			mh = 0.15                                   # 놓인 채(접힌 장비) — 땅에 눕힌다
		var hub := v.to_canvas(eq.x, g + mh - 0.1, d)
		if up or eq.state == BattleEquipment.State.SETUP:
			var leg := col.darkened(0.25)
			ci.draw_line(hub, v.to_canvas(eq.x + f * LEG_SPREAD_M, g, d), leg, 2.0)
			ci.draw_line(hub, v.to_canvas(eq.x - f * LEG_SPREAD_M * 1.2, g, d), leg, 2.0)
		var breech := v.to_canvas(eq.x - f * 0.4, g + mh - 0.04, d)
		var muzzle := v.to_canvas(eq.x + f * eq.type.muzzle_ahead_m, g + mh, d)
		ci.draw_line(breech, muzzle, col, 4.0 if up else 3.0)
		if eq.state == BattleEquipment.State.SETUP:
			# 설치가 얼마나 됐나 — 총몸 아래 가는 막대
			var t := 1.0 - clampf(eq.timer / maxf(eq.type.setup_time, 0.01), 0.0, 1.0)
			ci.draw_line(breech + Vector2(0, 5), breech.lerp(muzzle, t) + Vector2(0, 5), Color(1.0, 0.9, 0.3, 0.9), 2.0)
		for i in eq.seats.size():
			var p := v.to_canvas(eq.seat_x(i), v.vis_ground(eq.seat_x(i), eq.seat_depth(i)), eq.seat_depth(i))
			var r := 5.0 if i == 0 else 4.0
			if eq.seats[i] != null:
				ci.draw_circle(p, r, Color(col, 0.55))
			else:
				ci.draw_arc(p, r, 0.0, TAU, 16, Color(col, 0.6), 1.0)


## 글자 층 — 이름 · 상태 · 탄. 들고 가는 장비는 운반병 어깨 위 막대 + 이름
static func draw_overlay(v: BattleView, ci: Node2D, bf: Battlefield, font: Font) -> void:
	for eq in bf.equipments:
		var col := _color(eq)
		var text := "%s · %s" % [eq.type.display_name, BattleEquipment.STATE_NAMES[eq.state]]
		var top := v.to_canvas(eq.x, eq.type.muzzle_height + 0.45, eq.depth)
		if eq.state == BattleEquipment.State.CARRIED and eq.carrier != null:
			var c := eq.carrier
			var sh := c.type.box(c.stance).y * 0.82
			var f := float(c.facing if c.facing != 0 else 1)
			ci.draw_line(v.to_canvas(c.x - f * CARRY_LEN_M * 0.35, sh, c.depth), v.to_canvas(c.x + f * CARRY_LEN_M * 0.65, sh + 0.05, c.depth), col, 4.0)
			top = v.to_canvas(c.x, c.type.box(c.stance).y + 0.55, c.depth)
		elif eq.state == BattleEquipment.State.READY:
			text += " · 탄 %d/%d" % [eq.ammo, eq.mag_size()]
			if eq.reloader != null:
				text += " · 장전 중"
		elif eq.state == BattleEquipment.State.SETUP or eq.state == BattleEquipment.State.TEARDOWN:
			text += " %.1f초" % maxf(eq.timer, 0.0)
		if eq.squad == null:
			text += " · 버려짐"
		if font == null:
			continue
		var w := 220.0
		var pos := top - Vector2(w * 0.5, 0.0)
		ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, 11, 3, Color(0.0, 0.0, 0.0, 0.85))
		ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, w, 11, col.lightened(0.35))
