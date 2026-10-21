extends Resource
class_name SquadComp

## 분대 구성 — 병종이 섞인 분대 · 운용 장비가 딸린 분대("MG42 팀 = 기관총수 3 + MG42").  (보병_추상화.md §2-13 ④)
## 병종 하나로 된 분대는 그 병종의 `분대 인원`으로 투입하면 된다(Battlefield.deploy_squad). 섞이면 이 리소스로(Battlefield.deploy_comp).
## 분대 두뇌(태세 · 엄폐 · 자리)는 섞여도 같다 — 장비는 장비 두뇌(CrewBrain)가 좌석 · 설치 · 운반을 맡는다.

@export var display_name := "MG42 팀"
## 병사 — 한 줄에 한 명(같은 병종을 여러 줄로)
@export var members: Array[SoldierType] = []
## 분대가 가지고 나가는 운용 장비 — 처음엔 숙련도가 가장 높은 병사가 들고 나온다
@export var equipment: Array[EquipmentType] = []
