extends RefCounted
class_name BattleCover

## 엄폐물 기록 — x 구간 + 높이 + 벽이 있는 쪽 + 칸.  (보병_추상화.md §2-1 · §2-9)
##
## 가림은 숫자 표가 아니라 기하로 정해진다(§2-12): 총알이 벽의 x 를 지날 때 높이가 벽보다 낮으면 벽에 박힌다.
## 벽은 깊이 전체를 덮는다. 병사는 x0 ~ x1 사이 칸에 선다.
##   낮음(모래주머니 · 낮은 담): 앉아서 쏘고 · 엎드려 숨는다
##   높음(참호 · 벽):           서서 쏘고 · 앉아서 숨는다

enum Kind { LOW, HIGH }
const KIND_NAMES := ["낮음", "높음"]
const WALL_HEIGHTS := [1.0, 1.5]        # m

var id := 0
var x0 := 0.0
var x1 := 0.0
var kind := Kind.LOW
## 벽이 있는 쪽: +1 = +x 쪽 끝 · −1 = −x 쪽 끝 · 0 = 양쪽(참호)
var wall_side := 0

var slot_x := PackedFloat32Array()
var slot_depth := PackedFloat32Array()
var slot_owner: Array[BattleSoldier] = []


## 칸을 만든다. count = 칸 수(0 이면 길이로 정한다 — 1 m 에 2칸)
func build_slots(count: int = 0) -> void:
	var length := maxf(x1 - x0, 0.5)
	if count <= 0:
		count = maxi(2, int(round(length * 2.0)))
	var rows := maxi(1, int(floor(length / 0.9)))
	var cols := int(ceil(float(count) / float(rows)))
	slot_x.resize(count)
	slot_depth.resize(count)
	slot_owner.resize(count)
	for i in count:
		var r := i % rows
		var c := i / rows
		slot_x[i] = x0 + (float(r) + 0.5) * length / float(rows)
		slot_depth[i] = clampf((float(c) + 0.5 + (0.25 if r % 2 == 1 else 0.0)) / float(cols), 0.05, 0.95)
		slot_owner[i] = null


func center_x() -> float:
	return (x0 + x1) * 0.5


func wall_height() -> float:
	return WALL_HEIGHTS[kind]


## 벽의 x 자리들(총알 경로 판정용)
func wall_xs() -> PackedFloat32Array:
	if wall_side > 0:
		return PackedFloat32Array([x1])
	if wall_side < 0:
		return PackedFloat32Array([x0])
	return PackedFloat32Array([x0, x1])


## dir(+1/−1) 쪽에서 오는 총알을 막아 주는가(그쪽에 벽이 있나)
func protects_from(dir: int) -> bool:
	return wall_side == 0 or wall_side == dir


## 쏘는 자세 · 숨는 자세 (BattleBody.Stance)
func fire_stance() -> int:
	return BattleBody.Stance.CROUCH if kind == Kind.LOW else BattleBody.Stance.STAND


func hide_stance() -> int:
	return BattleBody.Stance.PRONE if kind == Kind.LOW else BattleBody.Stance.CROUCH


func free_count() -> int:
	var k := 0
	for o in slot_owner:
		if o == null:
			k += 1
	return k


## 병사에게 가장 가까운 빈 칸을 준다. 없으면 −1.
func take_slot(s: BattleSoldier) -> int:
	var best := -1
	var best_d := INF
	for i in slot_owner.size():
		if slot_owner[i] != null:
			continue
		var d := absf(slot_x[i] - s.x) + absf(slot_depth[i] - s.depth) * 3.0
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		slot_owner[best] = s
	return best


func release(s: BattleSoldier) -> void:
	for i in slot_owner.size():
		if slot_owner[i] == s:
			slot_owner[i] = null
