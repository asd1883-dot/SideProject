@tool
extends EditorPlugin

## Dot Rigger — 프로젝트 > 도구 메뉴에 창을 띄운다.
## (Unity 의 EditorWindow 와 같은 사용감: 독이 아니라 독립 창)

const MENU_ITEM := "Dot Rigger (3D → 2D 컷아웃)"
const MENU_RESET := "Dot Rigger — 창 새로 만들기 (초기화)"

var _window: DRMainWindow


func _enter_tree() -> void:
	add_tool_menu_item(MENU_ITEM, _open)
	add_tool_menu_item(MENU_RESET, _reopen)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ITEM)
	remove_tool_menu_item(MENU_RESET)
	_free_window()


func _free_window() -> void:
	if is_instance_valid(_window):
		_window.queue_free()
	_window = null


## 창을 닫아도 hide() 만 되므로 인스턴스는 살아 있다.
## 하던 작업(불러온 모델/각도/선택)을 유지하려는 의도지만,
## 애드온 코드를 고친 뒤에는 옛 인스턴스가 그대로 다시 떠서
## 새 UI 가 안 보이고 에러가 난다. 그럴 때 _reopen 을 쓴다.
func _open() -> void:
	if not is_instance_valid(_window):
		_window = DRMainWindow.new()
		EditorInterface.get_base_control().add_child(_window)
	_window.popup_centered(Vector2i(1180, 780))


func _reopen() -> void:
	_free_window()
	_open()
