@tool
extends EditorPlugin

## Dot Rigger — 프로젝트 > 도구 메뉴에 창 하나를 띄운다.
## 창(DRHubWindow) 안에 탭 페이지: ① 캐릭터 굽기 · ② 장비 굽기 · ③ 복장 굽기.
## (10-06 이전에는 기능마다 창이 따로였다 — 여러 창을 껐다 켜는 게 번거로워 한 창의 탭으로 합쳤다)
## 3D 노선(10-15): 같은 메뉴의 "3D 동작 내보내기" = 게임 동작 표의 동작을 3D 캐릭터용 AnimationLibrary 로 저장(DRMotionExporter).
## 동작 표(DRMotionTable)를 인스펙터에서 열면 상태별 편집 화면(동작 여러 개 · 비중 % · 상하체 합성 — ui/motion_table_editor.gd, 10-16).

const MENU_ITEM := "Dot Rigger"
const MENU_RESET := "Dot Rigger — 개발 내용 갱신"
const MENU_MOTIONS := "Dot Rigger — 3D 동작 내보내기"

var _hub: DRHubWindow
var _motion_inspector: DRMotionTableInspector


func _enter_tree() -> void:
	add_tool_menu_item(MENU_ITEM, _open)
	add_tool_menu_item(MENU_RESET, _reopen)
	add_tool_menu_item(MENU_MOTIONS, _export_motions)
	_motion_inspector = DRMotionTableInspector.new()
	add_inspector_plugin(_motion_inspector)
	# 추가 동작 파일에 BoneMap 자동 지정(DRBoneMapAuto) — 가져오기가 끝날 때마다 + 켤 때 한 번 전체
	EditorInterface.get_resource_filesystem().resources_reimported.connect(_on_resources_reimported)
	_auto_bone_map.call_deferred(PackedStringArray())


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ITEM)
	remove_tool_menu_item(MENU_RESET)
	remove_tool_menu_item(MENU_MOTIONS)
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


## 3D 동작 내보내기(10-15) — 명령줄 도구(tools/export_motions_cli.gd)와 같은 일을 기본값으로:
## 프리셋 UAL1_preset.tres 의 처리(추가 동작 · 손 맞춤 · 비틀림 · 제자리 · 합성)를 거친 동작 중 게임 동작 표(game/units/rifleman_motions.tres)에
## 적힌 것을 game/motions/rifleman_anims.res 로 저장한다. 동작 표를 고치거나 Mixamo 동작을 새로 받은 뒤 누른다. 몇 초 걸린다(그동안 에디터가 멈춘다)
func _export_motions() -> void:
	var ex := DRMotionExporter.new()
	var t0 := Time.get_ticks_msec()
	var res := ex.run(EditorInterface.get_base_control())
	var lines := PackedStringArray()
	if bool(res.get("ok", false)):
		lines.append("동작 %d개 → %s  (%.0f KB, %.1f 초)" % [ex.motions.size(), ex.out_path, float(ex.file_size) / 1024.0,
			float(Time.get_ticks_msec() - t0) / 1000.0])
		lines.append("제자리로 만든 동작: %s" % (", ".join(ex.in_place_names) if not ex.in_place_names.is_empty() else "없음"))
	else:
		lines.append("내보내기 실패")
	if ex.missing.size() > 0:
		lines.append("")
		lines.append("동작 표에 있는데 없는 동작 %d개(가져오기 안 됨 · 이름 틀림):" % ex.missing.size())
		for m in ex.missing:
			lines.append("  ✗ " + m)
	if ex.warnings.size() > 0:
		lines.append("")
		lines.append("알림 %d개:" % ex.warnings.size())
		for w in ex.warnings:
			lines.append("  ⚠ " + w)
	ex.cleanup()
	print("[Dot Rigger] 3D 동작 내보내기\n" + "\n".join(lines))
	EditorInterface.get_resource_filesystem().scan()      # 새로 쓴 파일이 파일 시스템 창 · 열려 있는 리소스에 반영되게
	var dlg := AcceptDialog.new()
	dlg.title = "3D 동작 내보내기"
	dlg.dialog_text = "\n".join(lines)
	dlg.confirmed.connect(dlg.queue_free)
	dlg.canceled.connect(dlg.queue_free)
	EditorInterface.popup_dialog_centered(dlg)            # 에디터 창 가운데에(10-06: 직접 띄운 창이 다른 모니터 구석에 뜬 적이 있다)
