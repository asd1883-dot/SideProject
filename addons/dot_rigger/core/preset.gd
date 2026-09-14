@tool
extends Resource
class_name DRPreset

## 에디터 창의 설정 한 벌. `.tres` 로 저장되므로 파일시스템 독에 그대로 보이고,
## 툴을 열지 않아도 인스펙터에서 값을 확인/수정할 수 있다.
##
## 캐릭터마다(또는 게임마다) 시점과 그리기 순서가 다르므로,
## 한 번 맞춰 놓은 걸 파일로 남겨 두고 다시 불러 쓰는 용도.

@export var model_path: String = ""
## 사람이 알아보기 위한 메모. 동작에는 영향 없음.
@export_multiline var note: String = ""

@export_group("시점")
@export var yaw: float = 90.0
@export var pitch: float = 0.0
@export var ortho: float = 0.0
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
## 뒤 -> 앞 순서
@export var z_order: PackedStringArray = PackedStringArray()

@export_group("포즈 / 애니메이션")
@export var rest_anim: String = ""
@export var rest_time: float = 0.0
@export var animations: PackedStringArray = PackedStringArray()
@export var fps: int = 12
@export var apply_stretch: bool = true

@export_group("출력")
@export var out_dir: String = "res://puppet"
