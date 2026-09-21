@tool
extends Node2D
class_name DRPixelPuppet

## 도트 격자 고정 래퍼 — 베이크가 `puppet_pixel.tscn` 의 루트에 붙인다.
##
## 컷아웃 퍼펫을 게임에서 그대로 확대하면(scale 3 등) 파트가 돌 때 도트가 **기울어진 큰 사각형**으로 보인다.
## 이 래퍼는 퍼펫을 도트 해상도(배율 1)의 작은 SubViewport 에 그린 뒤 그 그림을 정수 배로 키워 보여 준다.
## → 돌아간 파트도 도트 격자에 다시 찍혀서 모든 도트가 같은 크기·같은 격자에 놓인다.
##
##   PuppetPixel (이 스크립트)
##   ├ View    SubViewport — 투명 배경 · nearest · snap_2d_transforms_to_pixel
##   │  └ Puppet   puppet.tscn 인스턴스(DRPuppet). 자리는 view_origin
##   └ Screen  Sprite2D — View 의 그림. 배율 pixel_scale, nearest
##
## 이 노드의 원점 = 퍼펫의 원점(베이크 캔버스 왼쪽 위)이라 puppet.tscn 과 바꿔 끼워도 자리가 같다.
## 게임 전체를 저해상도 뷰포트로 그리는 프로젝트(스트레치 모드 viewport)라면 이 래퍼 없이 puppet.tscn 을 배율 1 로 쓰면 된다.

## 도트 1개를 화면 몇 픽셀로 보일지. 정수만 — 정수가 아니면 도트 크기가 들쭉날쭉해진다.
@export_range(1, 16, 1) var pixel_scale: int = 1:
	set(v):
		pixel_scale = maxi(1, v)
		_layout()

## 뷰포트 크기와, 그 안에서 퍼펫 원점이 놓이는 자리(베이크가 모든 애니의 움직임 범위를 재서 넣는다)
@export var view_size: Vector2i = Vector2i(64, 64):
	set(v):
		view_size = v
		_layout()
@export var view_origin: Vector2i = Vector2i.ZERO:
	set(v):
		view_origin = v
		_layout()

## 사방으로 더 둘 여유(도트). 장비(헬멧·총)가 몸 밖으로 많이 나가 잘리면 키운다.
@export_range(0, 256, 1) var extra_margin: int = 0:
	set(v):
		extra_margin = maxi(0, v)
		_layout()


func _ready() -> void:
	_layout()


func _layout() -> void:
	if not is_inside_tree():
		return
	var view := get_node_or_null("View") as SubViewport
	var screen := get_node_or_null("Screen") as Sprite2D
	if view == null or screen == null:
		return
	var m := Vector2i(extra_margin, extra_margin)
	view.size = view_size + m * 2
	var inner := view.get_node_or_null("Puppet") as Node2D
	if inner != null:
		inner.position = Vector2(view_origin + m)
	screen.texture = view.get_texture()
	screen.centered = false
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	screen.scale = Vector2(pixel_scale, pixel_scale)
	screen.position = -Vector2(view_origin + m) * float(pixel_scale)


## 안쪽 퍼펫(장비 장착 등은 여기에: get_puppet().equip(item))
func get_puppet() -> DRPuppet:
	return get_node_or_null("View/Puppet") as DRPuppet


func get_animation_player() -> AnimationPlayer:
	return get_node_or_null("View/Puppet/AnimationPlayer") as AnimationPlayer


func play(anim: StringName, custom_blend: float = -1.0) -> void:
	var ap := get_animation_player()
	if ap != null:
		ap.play(anim, custom_blend)
