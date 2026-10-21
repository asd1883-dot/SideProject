extends Resource
class_name StatMod

## 수정자 — 버프 · 디버프 · 좌석 효율 하나.  (보병_추상화.md §2-13, 안건 F)
## 병사마다 목록(BattleSoldier.mods)으로 들고, 최종 수치는 BattleSoldier.stat() 한 곳에서 낸다:
##   최종 = (기본 + 더하기의 합) × 곱하기의 곱      기본 = 부르는 쪽이 병종 · 무기에서 넣는 값
## 예) 좌석 "사수 · 숙련도 0 → 효율 75 %" = 퍼짐 × 1/0.75 · 조준 시간 × 1/0.75 · 선회 × 0.75 (시간 · 퍼짐 ÷ 효율, 속도 × 효율)
## 파일(.tres)로 만들어 두면 같은 버프를 여러 곳에서 붙일 수 있다 — 시간이 있는 것은 붙일 때 복사된다(병사마다 남은 시간이 따로).

# ── 수치 이름 — stat() 에 넣는 이름 ──
const WALK_SPEED := &"walk_speed"
const RUN_SPEED := &"run_speed"
const CRAWL_SPEED := &"crawl_speed"
const SUPPRESS_RESIST := &"suppress_resist"
const RANGE := &"range_m"
const AIM_TIME := &"aim_time"
const FIRE_INTERVAL := &"fire_interval"
const RELOAD_TIME := &"reload_time"
const SPREAD := &"spread_deg"
const DAMAGE := &"damage"
const TRAVERSE := &"traverse_deg_s"
## 클수록 좋은 수치 — 효율을 곱한다. 나머지(시간 · 퍼짐)는 효율로 나눈다
const HIGHER_BETTER: Array[StringName] = [WALK_SPEED, RUN_SPEED, CRAWL_SPEED, SUPPRESS_RESIST, RANGE, DAMAGE, TRAVERSE]
## 확인 글자에 쓰는 이름
const STAT_NAMES := {
	&"walk_speed": "걷기 속도", &"run_speed": "달리기 속도", &"crawl_speed": "포복 속도", &"suppress_resist": "제압 내성",
	&"range_m": "사거리", &"aim_time": "조준 시간", &"fire_interval": "연사 간격", &"reload_time": "장전 시간",
	&"spread_deg": "퍼짐", &"damage": "피해", &"traverse_deg_s": "선회",
}

## 어느 수치를 바꾸나(위 이름)
@export var stat: StringName = &""
@export var add := 0.0
@export var mul := 1.0
## 이어지는 시간(초). 0 보다 작으면 누가 뺄 때까지 계속
@export var duration := -1.0
## 확인용 글자(시험장 상태 글자에 나온다) — 예: "좌석: 사수 · 숙련도 0 → 75 %"
@export var label := ""

## 누가 붙였나 — 같은 꼬리표를 한 번에 뺀다(예: "seat:3" = 장비 3 의 좌석이 붙인 것)
var tag := ""
## 남은 시간(붙일 때 duration 에서)
var time_left := -1.0


static func make(stat_name: StringName, mul_v: float, add_v: float, label_v: String, tag_v: String = "", dur: float = -1.0) -> StatMod:
	var m := StatMod.new()
	m.stat = stat_name
	m.mul = mul_v
	m.add = add_v
	m.label = label_v
	m.tag = tag_v
	m.duration = dur
	return m


## 효율(0 ~ 1)을 그 수치에 거는 곱 — 시간 · 퍼짐은 ÷ 효율, 속도 같은 클수록 좋은 수치는 × 효율
static func efficiency_mul(stat_name: StringName, eff: float) -> float:
	return eff if HIGHER_BETTER.has(stat_name) else 1.0 / maxf(eff, 0.01)


## 확인용 한 줄 — 수치 · 값 · (남은 시간) ← 라벨
func describe() -> String:
	var v := ""
	if not is_equal_approx(mul, 1.0):
		v += "×%.2f" % mul
	if not is_zero_approx(add):
		v += "%+.2f" % add
	var t := "" if time_left < 0.0 else " (%.1f초)" % time_left
	var nm: String = STAT_NAMES.get(stat, String(stat))
	return "%s %s%s%s" % [nm, v, t, ("  ← " + label) if label != "" else ""]
