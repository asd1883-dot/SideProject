extends RefCounted
class_name BattleSoldier

## 병사 기록 — 노드가 아니다. 전장 관리자(Battlefield)가 배열로 들고 돈다.  (보병_추상화.md §2-6)
## 상태 논리는 BattleBody(몸) · SoldierBrain(두뇌)가 모든 병사에 같이 쓰고, 병사는 "지금 상태 번호 + 타이머 + 수치"만 가진다.
## 화면에 그리는 일은 BattleView 가 이 기록을 읽어서 한다(여기엔 그림 정보가 없다).

var id := 0
## 0 = 왼쪽 끝에서 나오는 편(앞 = +x) · 1 = 오른쪽 끝에서 나오는 편(앞 = −x)
var team := 0
var type: SoldierType
var squad: BattleSquad = null
## 빙의 중 — 분대의 인원 · 자리 · 평균에서 빠진다(§2-7 "나만 빠짐")
var detached := false

# ── 자리 ──
var x := 0.0                    # 전선 방향(m)
var depth := 0.5                # 0(화면 안쪽) ~ 1(화면 앞쪽)
var facing := 1                 # +1 = 오른쪽을 봄 · −1 = 왼쪽

# ── 몸(§2-4): 두 영역 + 덮어쓰기. 값은 BattleBody 의 enum ──
var move_state := 0             # BattleBody.Move
var act_state := 0              # BattleBody.Act
var override := 0               # BattleBody.Ovr
var stance := 0                 # BattleBody.Stance (상태가 아니라 속성)
var ability: Ability = null     # 행동 영역이 지금 하는 능력(§2-13) — 없으면 null
var phase := 0                  # 그 능력의 단계(Ability.Phase — 준비 · 실행 · 마무리)
var act_timer := 0.0
var ovr_timer := 0.0
var fire_cooldown := 0.0

# ── 수치 ──
var hp := 100.0
var ammo := 0
var suppression := 0.0          # 1 을 넘으면 제압(몸 덮어쓰기)
var bloom_deg := 0.0            # 연사로 넓어진 퍼짐(도)

# ── 수정자(§2-13): 버프 · 디버프 · 좌석 효율. 최종 수치는 stat() 한 곳 ──
var mods: Array[StatMod] = []
var _mod_sum: Dictionary = {}       # 수치 이름 -> [더하기의 합, 곱하기의 곱] — mods 가 바뀔 때만 다시 만든다
var _mods_dirty := false
var _timed_mods := 0                # 시간이 있는 수정자 수(0 이면 매 걸음 훑지 않는다)

# ── 엄폐(§2-9) ──
var cover: BattleCover = null   # 분대가 배정해 준 엄폐물
var slot := -1                  # 그 엄폐물의 칸 번호
var in_cover := false           # 자리에 도착해 엄폐를 받는 중

# ── 의도(§2-3): 조종자(AI 두뇌 또는 플레이어)가 채우고, 몸이 읽는다. 누가 채우든 모양이 같다 ──
var controller := 0             # 0 = AI 두뇌 · 1 = 플레이어(빙의)
var use_goal := true            # true = goal_x 까지 간다(AI) · false = move_dir 방향으로 간다(플레이어)
var goal_x := 0.0
var goal_depth := 0.5
var move_dir := 0               # −1 · 0 · +1
var want_run := false
var want_stance := 0
var want_fire := false
var want_reload := false
var aim_x := 0.0                # 조준점(m) — 표적(target)이 없을 때 · 플레이어가 쏠 때
var aim_h := 1.0
var aim_depth := 0.5
var target: BattleSoldier = null

# ── 두뇌가 쓰는 것 ──
var brain_timer := 0.0
var can_engage := false         # 지금 표적을 쏠 수 있는 사선이 있나(분대 두뇌가 "교전 중"을 이걸로 센다)
var intent_name := ""           # 디버그: 두뇌가 고른 의도
var intent_scores: Dictionary = {}

var alive: bool:
	get:
		return override != BattleBody.Ovr.DEAD


## 지금 쓸 수 있는 능력 목록 — 병종의 것(배열을 새로 만들지 않고 그대로 돌려준다)
func abilities() -> Array[Ability]:
	return type.abilities


# ───────────── 수정자 · 최종 수치 ─────────────

## 최종 수치 = (기본 + 더하기의 합) × 곱하기의 곱. 기본 = 부르는 쪽이 병종 · 무기에서 넣는 값(StatMod 의 수치 이름)
func stat(name: StringName, base: float) -> float:
	if mods.is_empty():
		return base
	if _mods_dirty:
		_rebuild_mods()
	var v: Variant = _mod_sum.get(name)
	if v == null:
		return base
	var p: Array = v
	return (base + float(p[0])) * float(p[1])


## 수정자를 붙인다. 시간이 있는 것은 복사해서 붙인다(같은 .tres 를 여러 병사가 쓰면 남은 시간이 따로여야 하므로) — 붙은 것을 돌려준다
func add_mod(m: StatMod) -> StatMod:
	var mm := m
	if m.duration >= 0.0:
		mm = m.duplicate() as StatMod
		mm.tag = m.tag
		mm.time_left = m.duration
		_timed_mods += 1
	mods.append(mm)
	_mods_dirty = true
	return mm


## 그 꼬리표의 수정자를 모두 뺀다. 뺀 수
func remove_mods(tag: String) -> int:
	var n := 0
	var i := mods.size() - 1
	while i >= 0:
		if mods[i].tag == tag:
			if mods[i].time_left >= 0.0:
				_timed_mods -= 1
			mods.remove_at(i)
			n += 1
		i -= 1
	if n > 0:
		_mods_dirty = true
	return n


## 시간이 있는 수정자의 시간을 줄이고 다 된 것을 뺀다(몸이 매 걸음 부른다 — 시간 있는 것이 없으면 바로 나간다)
func tick_mods(dt: float) -> void:
	if _timed_mods == 0:
		return
	var i := mods.size() - 1
	while i >= 0:
		var m := mods[i]
		if m.time_left >= 0.0:
			m.time_left -= dt
			if m.time_left <= 0.0:
				mods.remove_at(i)
				_timed_mods -= 1
				_mods_dirty = true
		i -= 1


func _rebuild_mods() -> void:
	_mods_dirty = false
	_mod_sum.clear()
	for m in mods:
		var p: Array = _mod_sum.get(m.stat, [0.0, 1.0])
		p[0] = float(p[0]) + m.add
		p[1] = float(p[1]) * m.mul
		_mod_sum[m.stat] = p


## 싸울 수 있나(죽지도 패닉도 아님)
func can_fight() -> bool:
	return override != BattleBody.Ovr.DEAD and override != BattleBody.Ovr.PANIC


## 지금 엄폐 뒤에 완전히 숨었나(숨는 자세)
func is_hidden() -> bool:
	return in_cover and cover != null and stance == cover.hide_stance()
