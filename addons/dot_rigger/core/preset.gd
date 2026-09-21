@tool
extends Resource
class_name DRPreset

## 에디터 창의 설정 한 벌. `.tres` 로 저장되므로 파일시스템 독에 그대로 보이고,
## 툴을 열지 않아도 인스펙터에서 값을 확인/수정할 수 있다.
##
## 캐릭터마다(또는 게임마다) 시점과 그리기 순서가 다르므로,
## 한 번 맞춰 놓은 걸 파일로 남겨 두고 다시 불러 쓰는 용도.

@export var model_path: String = ""
## 추가 동작 폴더(res://). 모델 파일 밖의 동작(Mixamo FBX 등)을 같은 캐릭터에 얹는다. 파일 이름 = 동작 이름. "" = 안 씀
@export_dir var extra_anim_dir: String = ""
## 상하체 합성 동작 정의(창의 `상하체 합성…` 팝업). 각 { name, lower, upper, length_mode(0 하체 속도 · 1 한 번씩 · 2 상체 속도), loop }
@export var composites: Array[Dictionary] = []
## 상체로 칠 파트. 비면 기본(몸통·머리·두 팔)
@export var composite_upper_parts: PackedStringArray = PackedStringArray()
## 사람이 알아보기 위한 메모. 동작에는 영향 없음.
@export_multiline var note: String = ""

@export_group("시점")
@export var yaw: float = 90.0
@export var pitch: float = 0.0
@export var ortho: float = 0.0
## 캐릭터 화면 위치 이동(px). +x = 오른쪽, +y = 위. 자동 맞춤이 켜져 있으면 무시(다시 가운데로 맞춤).
@export var offset_x: int = 0
@export var offset_y: int = 0
@export var auto_fit: bool = true
@export var margin: int = 6

@export_group("도트화")
@export var resolution: int = 192
@export var supersample: int = 1
@export var light_bands: int = 3
@export var ambient: float = 0.45
@export var alpha_threshold: float = 0.5
@export var color_levels: int = 0

@export_group("파트 / 그리기 순서")
@export var bleed_rings: int = 1
## true 면 3D 깊이로 자동 정렬. false 면 아래 z_order 를 그대로 쓴다.
@export var z_auto: bool = true
## 레이어 이름, 뒤 -> 앞 순서. 발가락처럼 다른 줄에 묶인 파트는 따로 적지 않는다.
@export var z_order: PackedStringArray = PackedStringArray()

@export_group("포즈 / 애니메이션")
@export var rest_anim: String = ""
@export var rest_time: float = 0.0
## 레스트 자세 자동(고른 동작에서 찾기). 켜져 있으면 rest_anim/rest_time 은 마지막으로 찾은 값.
@export var rest_auto: bool = true
@export var animations: PackedStringArray = PackedStringArray()
@export var fps: int = 12
@export var apply_stretch: bool = true
## 부드러운 도트 이동 셰이더(2D 프리뷰 + 베이크 씬 스프라이트). 끄면 예전처럼 nearest.
@export var smooth_pixel: bool = true
## 도트 아웃라인(카툰 선) 두께(도트 단위, 0 = 없음)와 색. 창 상단 바.
@export var outline_px: int = 0
@export var outline_color: Color = Color.BLACK
## true = 전체 실루엣에만 선(기본), false = 파트마다 선
@export var outline_whole: bool = true
## 선의 색 방식 — 0 = 카툰(outline_color 한 색) · 1 = 픽셀 퍼펙트(선의 도트마다 바로 옆 몸 도트 색을 어둡게). 둘 중 하나.
@export_enum("카툰 (한 색)", "픽셀 퍼펙트 (옆 도트 색의 톤)") var outline_style: int = 0
## 픽셀 퍼펙트에서 옆 도트 색을 얼마나 어둡게 할지 (0 = 같은 색 · 1 = 검정)
@export_range(0.0, 1.0, 0.05) var outline_tone: float = 0.45
## 도트 격자 고정 — 도트 해상도로 그린 뒤 통째로 확대. 베이크하면 puppet_pixel.tscn 이 같이 나온다(부드러운 도트 이동은 꺼짐)
@export var pixel_grid: bool = false
## 동작 평면화(2D 게임식). 켜면 팔다리 각도를 측면(pose_yaw) 시점에서 재고 위치는 강체·늘이기 없음.
@export var planar: bool = false
@export var pose_auto: bool = true
@export var pose_yaw: float = 90.0

@export_group("리깅 애니메이션 세트")
## 자세 계열별 묶음. 각 항목 { "name", "rest_anim", "rest_time"(0~1), "animations": PackedStringArray }.
## 하나라도 있으면 베이크가 세트 전부를 순서대로 <out_dir>/<name>/ 에 굽고 sets.json 을 남긴다.
@export var sets: Array[Dictionary] = []

@export_group("출력")
@export var out_dir: String = "res://puppet"
## 같은 폴더에 다시 구울 때 예전에 구운 애니를 유지(레스트 포즈·시점이 같을 때만).
@export var keep_anims: bool = true
