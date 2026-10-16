@tool
extends Resource
class_name DRMotionTable

## 동작 표(10-16) — 상태 이름마다 동작 여러 개를 비중(%)과 함께 둔다. 그 상태가 되면 비중대로 하나를 골라 튼다.
##   피격: hit_1 20 % · hit_2 40 % · hit_3 40 %   → 맞을 때마다 셋 중 하나
##   서기: Rifle_Idle 50 % · Idle_LookAround 50 %  → 반복 동작은 한 바퀴 돌 때마다 다시 고른다(BattleView3D)
## 줄 하나 = DRMotionClip(단일 동작 또는 상하체 합성). 인스펙터 화면 = ui/motion_table_editor.gd.
## 상태 이름의 뜻(어느 상태가 어느 상태로 내려가는지)은 게임 쪽이 정한다 — 게임의 MotionTable 이 이것을 물려받아 state_names() 를 준다.
##
## 연산: 고르기는 상태가 바뀔 때만 부른다. 상태 → (이름 · 누적 비중) 목록은 처음 쓸 때 한 번 만들고(인덱스), 표를 고치면(changed) 다시 만든다.

## 줄들(같은 상태의 줄끼리 비중을 나눈다)
@export var clips: Array[DRMotionClip] = []
## 어디에도 안 걸릴 때 재생할 동작(비우면 지금 동작을 그대로 둔다)
@export var default_motion := ""
## 3D 동작 내보내기가 이 표의 동작을 저장할 곳(AnimationLibrary .res). 병종의 motion_library 가 비면 게임이 이것을 읽는다
@export_file("*.res", "*.tres") var library_path := ""

var _index: Dictionary = {}          # 상태 -> [[동작 이름, 비중] …](비중 0 인 줄은 뺌)
var _indexed := false


func _init() -> void:
	changed.connect(_invalidate)


func _invalidate() -> void:
	_indexed = false


## 인스펙터가 보여 줄 상태 이름(순서대로). 기본 = 줄에 나온 순서. 게임의 표가 "쓸 수 있는 상태 전부"로 덮어 쓴다
func state_names() -> PackedStringArray:
	var out := PackedStringArray()
	for c in clips:
		if c != null and not out.has(c.state):
			out.append(c.state)
	return out


## 그 상태의 줄들(표 순서)
func clips_of(state: String) -> Array[DRMotionClip]:
	var out: Array[DRMotionClip] = []
	for c in clips:
		if c != null and c.state == state:
			out.append(c)
	return out


## 후보 상태(구체적인 것부터) 가운데 동작이 하나라도 available 에 있는 첫 상태에서 비중대로 하나를 고른다.
## 어디에도 없으면 default_motion(available 에 있으면), 그것도 없으면 "". available = 캐릭터 · 퍼펫이 가진 동작 이름들
func pick(candidates: PackedStringArray, available: PackedStringArray, rng: RandomNumberGenerator = null) -> String:
	for st in candidates:
		var m := pick_state(st, available, rng)
		if m != "":
			return m
	if default_motion != "" and available.has(default_motion):
		return default_motion
	return ""


## 그 상태 안에서만 고른다(사망처럼 덜 구체적인 상태로 내려가면 안 될 때). 없으면 ""
func pick_state(state: String, available: PackedStringArray, rng: RandomNumberGenerator = null) -> String:
	var list: Array = _entries(state)
	if list.is_empty():
		return ""
	var total := 0.0
	var only := ""
	var n := 0
	for it in list:
		if available.has(String(it[0])):
			total += float(it[1])
			only = String(it[0])
			n += 1
	if n <= 1:
		return only
	var r := (rng.randf() if rng != null else randf()) * total
	for it in list:
		if not available.has(String(it[0])):
			continue
		r -= float(it[1])
		if r < 0.0:
			return String(it[0])
	return only


## pick 이 고를 상태(후보 중 동작이 있는 첫 상태). 없으면 ""
func state_of(candidates: PackedStringArray, available: PackedStringArray) -> String:
	for st in candidates:
		if variant_count(st, available) > 0:
			return st
	return ""


## 그 상태에서 고를 수 있는 동작 수(available 에 있는 것만) — 2 이상이면 반복할 때마다 다시 고를 만하다
func variant_count(state: String, available: PackedStringArray) -> int:
	var n := 0
	for it in _entries(state):
		if available.has(String(it[0])):
			n += 1
	return n


## 그 상태에 그 동작이 있나(예: 걷기에 "달리기" 동작을 빌려 쓰는 중인지)
func has_motion(state: String, motion: String) -> bool:
	for it in _entries(state):
		if String(it[0]) == motion:
			return true
	return false


## 표에 나온 동작 이름 전부(중복 없이, 처음 나온 순서) + 기본 동작
func motion_names() -> PackedStringArray:
	var out := PackedStringArray()
	for c in clips:
		if c == null:
			continue
		var n := c.play_name()
		if n != "" and not out.has(n):
			out.append(n)
	if default_motion != "" and not out.has(default_motion):
		out.append(default_motion)
	return out


## 표에 적혀 있는데 available 에 없는 동작(= 아직 안 내보냈거나 안 구운 것) {상태: [동작 이름 …]}
func missing(available: PackedStringArray) -> Dictionary:
	var out := {}
	for c in clips:
		if c == null:
			continue
		var n := c.play_name()
		if n != "" and not available.has(n):
			if not out.has(c.state):
				out[c.state] = []
			(out[c.state] as Array).append(n)
	return out


## 상하체 합성 줄들의 합성 정의(이름이 같으면 처음 것) — 3D 동작 내보내기가 굽는다
func composite_defs() -> Array:
	var out: Array = []
	var seen := {}
	for c in clips:
		if c == null or not c.is_composite():
			continue
		var n := c.play_name()
		if seen.has(n):
			continue
		seen[n] = true
		out.append(c.composite_def())
	return out


## 줄 전부를 값으로(인스펙터의 되돌리기 기록용 — 화면 노드는 인스펙터가 다시 만들면 사라지므로 기록은 표가 들고 있는다)
func snapshot() -> Array:
	var out: Array = []
	for c in clips:
		if c != null:
			out.append(c.to_dict())
	return out


## snapshot() 으로 만든 값으로 줄 전부를 바꾼다(되돌리기 · 다시 하기가 부른다)
func restore_snapshot(snap: Array) -> void:
	var out: Array[DRMotionClip] = []
	for d in snap:
		out.append(DRMotionClip.from_dict(d as Dictionary))
	clips = out
	emit_changed()


# ───────────── 비중 맞추기(인스펙터 · 정적) ─────────────

## index 줄의 비중을 value(%)로 바꾸고, 나머지는 서로의 비율을 지킨 채 합이 100 이 되게 줄이거나 늘린다.
## (33 · 33 · 33 에서 첫 줄을 20 → 20 · 40 · 40). 나머지가 다 0 이면 똑같이 나눈다
static func rebalance(weights: PackedFloat32Array, index: int, value: float) -> PackedFloat32Array:
	var out := weights.duplicate()
	var n := out.size()
	if n == 0 or index < 0 or index >= n:
		return out
	if n == 1:
		out[0] = 100.0
		return out
	var v := clampf(value, 0.0, 100.0)
	var rest := 100.0 - v
	var others := 0.0
	for i in n:
		if i != index:
			others += out[i]
	for i in n:
		if i == index:
			out[i] = v
		elif others > 0.0001:
			out[i] = out[i] * rest / others
		else:
			out[i] = rest / float(n - 1)
	return out


## 새 줄을 하나 더할 때: 새 줄 = 100 / n, 기존 줄은 비율을 지킨 채 (n − 1) / n 배(33 · 33 · 33 → 25 · 25 · 25 · 25)
static func with_added(weights: PackedFloat32Array) -> PackedFloat32Array:
	var n := weights.size() + 1
	var out := PackedFloat32Array()
	var sum := 0.0
	for w in weights:
		sum += w
	for w in weights:
		out.append(w / sum * 100.0 * float(n - 1) / float(n) if sum > 0.0001 else 100.0 / float(n))
	out.append(100.0 / float(n))
	return out


## 줄 하나를 뺄 때: 나머지를 비율을 지킨 채 합 100 으로
static func without(weights: PackedFloat32Array, index: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var sum := 0.0
	for i in weights.size():
		if i != index:
			out.append(weights[i])
			sum += weights[i]
	for i in out.size():
		out[i] = out[i] / sum * 100.0 if sum > 0.0001 else 100.0 / float(out.size())
	return out


static func equalized(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in n:
		out.append(100.0 / float(maxi(n, 1)))
	return out


# ───────────── 안쪽 ─────────────

func _entries(state: String) -> Array:
	if not _indexed:
		_build_index()
	return _index.get(state, [])


func _build_index() -> void:
	_index = {}
	for c in clips:
		if c == null or c.weight <= 0.0:
			continue
		var n := c.play_name()
		if n == "":
			continue
		if not _index.has(c.state):
			_index[c.state] = []
		(_index[c.state] as Array).append([n, c.weight])
	_indexed = true
