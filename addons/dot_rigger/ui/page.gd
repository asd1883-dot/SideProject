@tool
extends Control
class_name DRPage

## Dot Rigger 창(DRHubWindow)의 페이지 하나 — 캐릭터 굽기 · 장비 굽기 · 복장 굽기가 이것을 상속한다.
## 예전에는 기능마다 창(Window)이 따로였다. 창을 여러 개 껐다 켜는 게 번거로워(10-06 사용자) 한 창의 탭 페이지로 바꿨다.
## 페이지는 그냥 Control 이라 어디에든 넣을 수 있다 — 검사 도구는 창 없이 root 에 바로 넣어 돌린다(test_layout).

## 공통 설정(프리셋 · 세트 목록)을 이 페이지가 바꿨을 때 — 창이 받아 다른 페이지에 돌린다.
## ctx 에는 바뀐 것만: {"preset": 경로} · {"sets": 경로} · {"rebaked": true}(세트를 다시 구움)
signal context_changed(ctx: Dictionary)

## 탭에 보이는 이름
var page_title := ""
## 탭 창(DRHubWindow) 안에 있나 — 그러면 프리셋 · 세트 목록 칸은 창 위의 `공통 설정` 줄이 대신한다
var hosted := false
var _paused_viewports: Dictionary = {}   # SubViewport -> 멈추기 전 갱신 방식


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 에디터는 Control 의 글자를 자기 번역 사전으로 자동 번역한다(동작 이름 "Idle" → "대기"). 문구가 전부 하드코딩이라 끈다.
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED


## 이 페이지가 든 창의 화면 위치 — 팝업 메뉴를 단추 아래에 띄울 때 더한다
func window_origin() -> Vector2i:
	var w := get_window()
	return w.position if w != null else Vector2i.ZERO


## 탭이 바뀔 때 창이 부른다. 안 보이는 페이지의 미리보기 뷰포트(매 프레임 그리는 것)를 멈춰 두고, 다시 보이면 되돌린다.
## 굽는 중에 탭을 바꿔도 괜찮다 — 굽기는 찍을 때마다 자기 뷰포트를 다시 켠다(DRBaker._grab).
func set_page_active(on: bool) -> void:
	if on:
		for vp in _paused_viewports.keys():
			if is_instance_valid(vp):
				(vp as SubViewport).render_target_update_mode = _paused_viewports[vp]
		_paused_viewports.clear()
		return
	for c in get_children():
		var vp := c as SubViewport
		if vp != null and not _paused_viewports.has(vp) and vp.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			_paused_viewports[vp] = vp.render_target_update_mode
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


## 공통 설정이 정해지거나 바뀌면 창이 부른다(페이지를 만든 직후에도 한 번). ctx = {preset, sets} 전부,
## changed = 이번에 바뀐 키("preset" · "sets" · "rebaked"). 페이지마다 자기 칸을 맞추고 필요하면 다시 불러온다.
func apply_context(_ctx: Dictionary, _changed: PackedStringArray) -> void:
	pass


## 미리보기 배경색(창 위 공통 설정 줄에서 고름, 10-08). c.a == 0 = 기본(페이지마다 원래 색). 페이지가 자기 미리보기에 적용한다.
## 자홍 같은 튀는 색이면 조각 사이 구멍 · 비침이 잘 보인다.
func set_preview_bg(_c: Color) -> void:
	pass


## 검사 도구용 — 창 없이 root 에 넣었을 때 왼쪽 위에 이 크기로 놓는다(화면 캡처 · 배치 검사가 이 틀 기준)
func test_layout(sz: Vector2i) -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = Vector2(sz)
