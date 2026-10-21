@tool
extends EditorPlugin

## Dot Rigger — 프로젝트 > 도구 메뉴에 창 하나를 띄운다.
## 창(DRHubWindow) 안에 탭 페이지: ① 유닛 · ② 장비(뼈 소켓) · ③ 복장 — 10-16 셋 다 3D(예전 2D 굽기 페이지는 뺐다).
## (10-06 이전에는 기능마다 창이 따로였다 — 여러 창을 껐다 켜는 게 번거로워 한 창의 탭으로 합쳤다)
## 동작 표(DRMotionTable)를 인스펙터에서 열면 상태별 편집 화면(동작 여러 개 · 비중 % · 상하체 합성 · [3D 동작 내보내기] — ui/motion_table_editor.gd, 10-16).
## (10-15 에 같은 메뉴에 "3D 동작 내보내기" 를 두었으나 10-21 뺐다 — 늘 기본 동작 표만 · 저장 안 한 고침을 안 읽어, 지금 보는 표를 내보내는
##  동작 표 화면의 버튼과 겹치고 헷갈렸다. 사용자 "3D 동작 내보내기는 왜 드롭다운 원소에 추가시켜 놓은 거야?" → "엉"(빼기). 명령줄은 tools/export_motions_cli.gd)

const MENU_ITEM := "Dot Rigger"
const MENU_RESET := "Dot Rigger — 개발 내용 갱신"

var _hub: DRHubWindow
var _motion_inspector: DRMotionTableInspector


func _enter_tree() -> void:
	add_tool_menu_item(MENU_ITEM, _open)
	add_tool_menu_item(MENU_RESET, _reopen)
	_motion_inspector = DRMotionTableInspector.new()
	add_inspector_plugin(_motion_inspector)
	# 추가 동작 파일에 BoneMap 자동 지정(DRBoneMapAuto) — 가져오기가 끝날 때마다 + 켤 때 한 번 전체
	EditorInterface.get_resource_filesystem().resources_reimported.connect(_on_resources_reimported)
	_auto_bone_map.call_deferred(PackedStringArray())


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ITEM)
	remove_tool_menu_item(MENU_RESET)
	if _motion_inspector != null:
		remove_inspector_plugin(_motion_inspector)
		_motion_inspector = null
	var fs := EditorInterface.get_resource_filesystem()
	if fs.resources_reimported.is_connected(_on_resources_reimported):
		fs.resources_reimported.disconnect(_on_resources_reimported)
	_free_window()


func _on_resources_reimported(paths: PackedStringArray) -> void:
	_auto_bone_map.call_deferred(paths)


## 같은 폴더의 다른 파일이 쓰는 BoneMap 을 새 파일에도 넣고 다시 가져온다. 다시 가져오면 이미 지정돼 있어 또 고치지 않는다
func _auto_bone_map(paths: PackedStringArray) -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs.is_scanning():
		get_tree().create_timer(1.0).timeout.connect(_auto_bone_map.bind(paths))
		return
	var redo := PackedStringArray()
	for fix in DRBoneMapAuto.find_fixes(paths):
		if DRBoneMapAuto.apply(fix):
			redo.append(String(fix["path"]))
			print("[Dot Rigger] BoneMap 자동 지정: %s ← %s (뼈 이름 %d%% 맞음, 같은 폴더의 다른 파일과 같은 표 · 텍스처는 안 꺼냄)" % [
				String(fix["path"]).get_file(), String(fix["bonemap"]).get_file(), int(round(float(fix["match"]) * 100.0))])
	if redo.size() > 0:
		fs.reimport_files(redo)


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
