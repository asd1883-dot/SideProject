@tool
extends EditorPlugin

## Dot Rigger — 프로젝트 > 도구 메뉴에 창 하나를 띄운다.
## 창(DRHubWindow) 안에 탭 페이지: ① 캐릭터 굽기 · ② 장비 굽기 · ③ 복장 굽기.
## (10-06 이전에는 기능마다 창이 따로였다 — 여러 창을 껐다 켜는 게 번거로워 한 창의 탭으로 합쳤다)

const MENU_ITEM := "Dot Rigger"
const MENU_RESET := "Dot Rigger — 개발 내용 갱신"

var _hub: DRHubWindow


func _enter_tree() -> void:
	add_tool_menu_item(MENU_ITEM, _open)
	add_tool_menu_item(MENU_RESET, _reopen)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ITEM)
	remove_tool_menu_item(MENU_RESET)
	_free_window()


func _free_window() -> void:
	if is_instance_valid(_hub):
		_hub.queue_free()
	_hub = null


## 창을 닫아도 hide() 만 되므로 인스턴스는 살아 있다 — 탭마다 하던 작업(불러온 모델 · 각도 · 조정 · 칠하기)이 유지된다.
## 마지막에 보던 탭으로 열린다. 애드온 코드를 고친 뒤에는 옛 인스턴스가 그대로 떠서 새 UI 가 안 보이므로 _reopen 을 쓴다.
func _open() -> void:
	if not is_instance_valid(_hub):
		_hub = DRHubWindow.new()
		EditorInterface.get_base_control().add_child(_hub)
	_hub.open()


## 개발 내용 갱신 — 열려 있던 Dot Rigger 창을 버린다. 다음에 메뉴로 열면 고친 코드로 새로 만들어진다.
## 창은 띄우지 않는다(09-29 사용자 요청: 갱신만 하고 창이 뜨지 않게).
func _reopen() -> void:
	_free_window()
	print("[Dot Rigger] 개발 내용 갱신 — 창을 다시 열면 새 코드로 뜹니다.")
