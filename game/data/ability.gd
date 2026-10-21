extends Resource
class_name Ability

## 능력 — 병사가 할 수 있는 기능 하나(사격 · 장전 · 투척 …). 기능 하나 = 파일 하나(.tres).  (보병_추상화.md §2-13, 안건 F)
## 병종(SoldierType)의 `능력` 목록에 끌어다 넣고 빼면 그 병종이 그 기능을 얻고 잃는다 — 상태 코드 안의 공격 로직을 찾아 고칠 일이 없다.
##
## 상태 없는 전략(Strategy): 모든 병사가 같은 파일을 같이 쓰고, 병사마다 다른 값(지금 능력 · 단계 · 타이머)은 병사 기록에 있다.
##   두뇌(SoldierBrain): 가진 능력마다 score() 로 점수만 묻는다 → 이 능력이 뽑히면 apply() 가 의도 칸(want_*)을 채운다
##   몸(BattleBody):     wants() 인 능력 중 priority 가 큰 것을 begin() → 매 걸음 step()(준비 → 실행 → 마무리) → false 면 끝
## 동작 표에는 행동 이름(BattleBody.Act — 조준 · 사격 · 장전 …)만 낸다: 단계마다 s.act_state 를 바꾼다.
## 앉은 좌석(운용 장비)이 있으면 그 좌석의 능력 목록이 병종의 것을 대신한다(BattleSoldier.abilities()).

## 단계 — 몸 상태머신이 아는 것은 "지금 어떤 능력을 어느 단계" 뿐이다
enum Phase { PREP, EXEC, END }
const PHASE_NAMES := ["준비", "실행", "마무리"]

@export var display_name := ""
## 두뇌 점수표에 쓰는 의도 이름 — "사격" · "장전". 같은 이름의 능력이 둘이면 앞의 것만 묻는다
@export var intent := ""
## 몸이 고를 때 우선순위 — 같은 걸음에 둘 이상이 하고 싶으면 큰 것부터(장전 1 > 사격 0: 빙의 중 R 과 클릭을 같이 누르면 장전)
@export var priority := 0


## 두뇌 — 이 능력의 점수(0 = 안 함). ctx(BrainCtx)에 계획(쏠 자세 등)을 적어도 된다
func score(_s: BattleSoldier, _bf: Battlefield, _ctx: BrainCtx) -> float:
	return 0.0


## 두뇌가 이 능력을 골랐다 — 의도 칸을 채운다
func apply(_s: BattleSoldier, _ctx: BrainCtx) -> void:
	pass


## 두뇌가 "대기"를 골랐을 때 이 능력이 덧붙일 것(예: 장전 — 덜 찬 탄창을 채운다)
func idle(_s: BattleSoldier, _ctx: BrainCtx) -> void:
	pass


## 몸 — 의도 칸을 보고 지금 시작하고 싶나
func wants(_s: BattleSoldier) -> bool:
	return false


## 몸 — 시작(단계 · 타이머 · 행동 이름)
func begin(_s: BattleSoldier, _bf: Battlefield) -> void:
	pass


## 몸 — 한 걸음. false 를 돌려주면 끝(몸이 s.ability 를 비운다)
func step(_s: BattleSoldier, _bf: Battlefield, _dt: float) -> bool:
	return false


## 끝나거나 끊겼을 때(피격 · 제압 · 사망 · 좌석 바뀜) — 붙들고 있던 것(장비의 장전 담당 등)을 놓는다
func stop(_s: BattleSoldier) -> void:
	pass
