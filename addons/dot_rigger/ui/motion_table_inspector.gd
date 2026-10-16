@tool
extends EditorInspectorPlugin
class_name DRMotionTableInspector

## 동작 표(DRMotionTable — 게임의 MotionTable 도)를 인스펙터에서 열면 기본 배열 편집기 대신 상태별 편집 화면(DRMotionTableEditor)을 보인다(10-16).
## 줄 배열(clips)의 기본 편집기는 숨기고, default_motion · library_path 는 기본 편집기 그대로 아래에 둔다. 등록 = plugin.gd


func _can_handle(object: Object) -> bool:
	return object is DRMotionTable


func _parse_begin(object: Object) -> void:
	var ed := DRMotionTableEditor.new()
	ed.table = object as DRMotionTable
	add_custom_control(ed)


func _parse_property(_object: Object, _type: Variant.Type, name: String, _hint_type: PropertyHint, _hint_string: String,
		_usage_flags: int, _wide: bool) -> bool:
	return name == "clips"
