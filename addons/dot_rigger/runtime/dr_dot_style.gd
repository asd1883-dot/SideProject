@tool
extends Resource
class_name DRDotStyle

## 도트 느낌 설정(10-16) — 예전 ① 탭(2D 굽기)의 도트화 · 외곽선 칸(외곽선 두께 · 카툰 / 픽셀 퍼펙트 · 톤 · 명암 단계)을 3D 로 옮긴 것.
## 사용자: "예전에 픽셀 퍼펙트 기능 같은 게 사라져 있네?" → 게임 화면(BattleView3D)과 ① 유닛 탭 미리보기가 **같은 파일**(DEFAULT_PATH)을
## 읽어 같은 모습이 된다. ① 탭의 "도트 느낌" 칸에서 바꾸면 미리보기에 바로, [저장] 하면 게임도 그 값으로.
## 외곽선 · 도트 = DRDotView3D(창 하나 · 렌더 한 번), 명암 = 캐릭터 재질 공통 값(DRCharacter3D.set_shading — 병사끼리 공유하는 재질 전부).

const DEFAULT_PATH := "res://game/dot_style.tres"

@export_group("도트")
## 도트 하나 = 화면 몇 픽셀(1 = 도트화 끔). 화면 기준이라 확대하면 캐릭터가 더 촘촘해진다
@export_range(1, 8) var dot_px := 2
## 카메라가 내려다보는 각(도)
@export_range(1.0, 45.0, 0.5) var pitch_deg := 15.0
## 동작을 초당 몇 번 새로 그리나 — 12 = 예전 2D 퍼펫(초당 12장)과 같은 끊는 맛(0 = 매 프레임)
@export_range(0.0, 60.0, 1.0) var step_hz := 12.0

@export_group("외곽선")
## 외곽선 두께(도트, 0 = 없음)
@export_range(0, 1) var outline_px := 1
## 선의 색 방식 — 카툰 = 한 색 · 픽셀 퍼펙트 = 선 도트마다 바로 옆 몸 도트 색을 톤만큼 어둡게(예전 2D 와 같은 두 방식)
@export_enum("카툰 (한 색)", "픽셀 퍼펙트 (옆 도트 색의 톤)") var outline_style := 1
@export var outline_color := Color(0.07, 0.06, 0.06, 1.0)
## 픽셀 퍼펙트일 때 어둡게 하는 정도(0 = 같은 색 · 1 = 검정)
@export_range(0.0, 1.0, 0.05) var outline_tone := 0.45
## 겹친 캐릭터 사이에도 선
@export var inner_outline := true
## 사이 선이 생기는 깊이 차(m)
@export_range(0.05, 5.0, 0.05) var inner_gap_m := 0.5

@export_group("명암")
## 명암 단계 수
@export_range(2, 8) var light_bands := 3
## 가장 어두운 면의 밝기
@export_range(0.0, 1.0, 0.05) var ambient := 0.45
@export_range(0.0, 1.0, 0.05) var light_wrap := 0.25
## 빛이 오는 쪽(세상 좌표, +Z = 화면 앞쪽)
@export var light_dir := Vector3(-0.4, 0.7, 0.6)
## 가장자리 빛(0 = 끔)
@export_range(0.0, 1.0, 0.05) var rim := 0.0
## 옷 안쪽 면(소매 · 깃 속)의 밝기
@export_range(0.0, 1.0, 0.05) var inside_shade := 0.35
## 명암 매끈함(cm) — 메시를 나눌 때 면 방향(노멀)을 이 반경만큼 고르게 편다. AI 메시의 주름 · 울퉁불퉁마다 명암 단계가 잘게 끊겨
## 도트가 얼룩지고 움직이면 반짝이던 것(10-16). 크면 큰 덩어리 명암(얼굴 입체감도 준다) · 0 = 모델 그대로. 바꾸면 병사를 다시 조립해야 보인다
@export_range(0.0, 20.0, 0.5, "suffix:cm") var normal_smooth_cm := 6.0


## 기본 설정 파일(없으면 기본값 새것)
static func load_default() -> DRDotStyle:
	if ResourceLoader.exists(DEFAULT_PATH):
		var s := load(DEFAULT_PATH) as DRDotStyle
		if s != null:
			return s
	return DRDotStyle.new()


## 도트 창에 도트 · 외곽선을 넣는다
func apply_to(dots: DRDotView3D) -> void:
	if dots == null:
		return
	dots.dot_px = dot_px
	dots.pitch_deg = pitch_deg
	dots.outline_px = outline_px
	dots.outline_style = outline_style
	dots.outline_color = outline_color
	dots.outline_tone = outline_tone
	dots.inner_outline = inner_outline
	dots.inner_gap_m = inner_gap_m


## 캐릭터 재질 공통 명암(모든 병사 · 미리보기의 공유 재질에 한꺼번에) + 명암 매끈함(메시 — 이 뒤에 조립하는 병사부터).
## 매끈함이 바뀌었으면 true(미리보기는 캐릭터를 다시 만들어야 보인다)
func apply_shading() -> bool:
	DRCharacter3D.set_shading({"bands": light_bands, "ambient": ambient, "light_wrap": light_wrap, "light_dir": light_dir,
		"rim": rim, "inside_shade": inside_shade})
	return DRCharacter3D.set_normal_smooth(normal_smooth_cm / 100.0)
