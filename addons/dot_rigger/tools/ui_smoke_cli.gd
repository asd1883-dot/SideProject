extends SceneTree

## 에디터 창 UI 코드 경로 스모크 테스트.
## 창을 실제로 띄우진 않고, 위젯 구성 -> 모델 로드 -> 프리뷰 갱신까지
## 크래시 없이 도는지 확인한다. (EditorInterface 를 쓰는 베이크 버튼은 제외)

func _initialize() -> void:
	_run.call_deferred()


## 거의 검은 불투명 픽셀 수
func _count_dark(img: Image) -> int:
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5 and c.r < 0.1 and c.g < 0.1 and c.b < 0.1:
				n += 1
	return n


## base 에서 완전히 불투명한(캐릭터 안쪽) 픽셀 중 img 에서 색이 바뀐 수 — 전체 실루엣 선은 0 이어야 한다
func _inner_changed(base: Image, img: Image) -> int:
	var n := 0
	for y in mini(base.get_height(), img.get_height()):
		for x in mini(base.get_width(), img.get_width()):
			var a := base.get_pixel(x, y)
			if a.a < 0.99:
				continue
			var b := img.get_pixel(x, y)
			if (Vector3(a.r, a.g, a.b) - Vector3(b.r, b.g, b.b)).length() > 0.1 or b.a < 0.99:
				n += 1
	return n


## 프리뷰 밑깔개(outline) 중 보이는 것의 수
func _visible_underlays(win) -> int:
	var n := 0
	for p in win._puppet_bones.keys():
		var ol: Sprite2D = win._puppet_bones[p]["outline"]
		if ol.visible:
			n += 1
	return n


func _run() -> void:
	# 산출물 폴더. 저장소에는 없으므로(.gitignore) 새로 clone 한 PC 에서는 여기서 만든다.
	# 없으면 19번 프리셋 저장 검사가 실패한다.
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://puppet_test"))
	var win := DRMainWindow.new()
	root.add_child(win)
	# 숨긴 채로 두면 SubViewport 가 렌더되지 않아 프리뷰가 검게 나온다.
	# 실사용(창을 열어 놓은 상태)과 같은 조건으로 테스트한다.
	win.popup_centered(Vector2i(1000, 700))
	await process_frame
	print("1) UI 구성 OK")
	# 이름 글자(Label)에 올려도 툴팁이 떠야 한다 (Label 기본값은 마우스 무시라 그냥 두면 안 뜸)
	var tip_lbl: Label = null
	for tip_c in win._yaw.get_parent().get_children():
		if tip_c is Label:
			tip_lbl = tip_c
	if tip_lbl == null or tip_lbl.tooltip_text == "" or tip_lbl.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		printerr("Yaw 이름표에 툴팁이 안 붙음"); quit(1); return
	var tip_names := ["_yaw", "_pitch", "_ortho", "_autofit", "_margin", "_res", "_ss", "_bands",
		"_ambient", "_alpha", "_levels", "_bleed", "_rest_anim", "_anim_list", "_fps", "_stretch",
		"_smooth", "_out_edit", "_keep_anims", "_bake_btn", "_z_auto", "_parts_tree",
		"_off_x", "_off_y", "_play_anim", "_speed", "_scrub", "_sets_list", "_set_name",
		"_planar", "_pose_auto", "_pose_yaw", "_rest_auto", "_outline_px", "_outline_color", "_outline_whole", "_extra_edit"]
	var tip_missing := []
	for tip_n in tip_names:
		if (win.get(tip_n) as Control).tooltip_text == "":
			tip_missing.append(tip_n)
	if tip_missing.size() > 0:
		printerr("툴팁 없음: %s" % str(tip_missing)); quit(1); return
	print("1-1) 툴팁 OK — 이름 글자에도 뜸(Yaw), 설정 %d개 모두 툴팁 있음" % tip_names.size())
	# 왼쪽 열: 접히는 섹션 7개(0~6), 도트화·파트 분리는 접힌 채 시작, 베이크 버튼은 스크롤 밖(항상 보임)
	var sec_titles: Array = win._sections.keys()
	sec_titles.sort()
	var fold_bad := []
	for t in sec_titles:
		var f: FoldableContainer = win._sections[t]
		var want_fold: bool = String(t).begins_with("3.") or String(t).begins_with("4.")
		if f.folded != want_fold:
			fold_bad.append("%s=%s" % [t, f.folded])
	if win._sections.size() != 7 or fold_bad.size() > 0:
		printerr("섹션 구성 이상: %d개 %s, 접힘 불일치 %s" % [win._sections.size(), str(sec_titles), str(fold_bad)]); quit(1); return
	var bake_in_scroll := false
	var pnode: Node = win._bake_btn
	while pnode != null:
		if pnode is ScrollContainer:
			bake_in_scroll = true
		pnode = pnode.get_parent()
	if bake_in_scroll or not win._bake_btn.is_visible_in_tree():
		printerr("베이크 버튼이 스크롤 안에 있거나 안 보임"); quit(1); return
	print("1-2) 왼쪽 열 OK — 접히는 섹션 %d개(3·4 접힘), 베이크 버튼은 스크롤 밖" % win._sections.size())

	win._model_edit.text = "res://models/UAL1.glb"
	win._on_load()
	if win.baker == null:
		printerr("모델 로드 실패"); quit(1); return
	print("2) 모델 로드 OK — %s" % win._status.text)
	var model_sec: FoldableContainer = null
	for t in win._sections.keys():
		if String(t).begins_with("1."):
			model_sec = win._sections[t]
	if model_sec == null or not model_sec.folded:
		printerr("모델을 불러온 뒤 1. 모델 섹션이 안 접힘"); quit(1); return
	# 아래 검사들은 레스트를 직접 고르므로 자동은 끈다(자동은 28번에서 따로 검사)
	win._rest_auto.button_pressed = false
	print("   파트 드롭다운 %d개, 레스트 드롭다운 %d개, 애니 목록 %d개" % [
		win._isolate.item_count, win._rest_anim.item_count, win._anim_list.item_count])
	print("   레스트 기본 선택: %s" % win._rest_anim.get_item_text(win._rest_anim.selected))

	# 파트 트리
	var t := win._parts_tree.get_root()
	var n := 0
	var stack: Array = [t]
	while stack.size() > 0:
		var it: TreeItem = stack.pop_back()
		for c in it.get_children():
			n += 1
			stack.append(c)
	print("3) 파트 트리 항목 %d개" % n)

	# 프리뷰 (합성) — _on_load 가 이미 시작해 뒀을 수 있으므로 끝날 때까지 대기
	while win._busy:
		await process_frame
	await win._refresh_preview()
	if win._preview.texture == null:
		printerr("프리뷰 텍스처 없음"); quit(1); return
	print("4) 합성 프리뷰 OK — %s" % str(win._preview.texture.get_size()))

	# 파트 격리 프리뷰
	win._isolate.select(5)
	await win._refresh_preview()
	print("5) 파트 격리 프리뷰 OK — %s" % win._isolate.get_item_text(5))

	# 각도 변경. 뷰포트를 직접 다시 읽으면 프레임 대기를 안 해 검은 이미지가 나오므로
	# 베이커가 프레임을 기다린 뒤 돌려주는 Image 를 그대로 쓴다.
	win._isolate.select(0)
	win._yaw.value = 45.0
	win._pitch.value = 20.0
	await win._refresh_preview()
	while win._busy:
		await process_frame
	var img: Image = await win.baker.render_all_parts_composite()
	img.save_png("res://puppet_test/_ui_smoke_45deg.png")
	print("6) 각도 변경(yaw45/pitch20) OK -> _ui_smoke_45deg.png")

	# 애니 필터
	win._anim_filter.text = "jog"
	win._fill_anim_list()
	print("7) 애니 필터 'jog' -> %d개" % win._anim_list.item_count)
	# 검색을 바꿔 가며 골라도 선택이 쌓여야 한다(예전엔 목록을 다시 채우며 선택이 풀렸음)
	win._anim_list.select(0, false)
	var pick_a := win._anim_list.get_item_text(0)
	win._anim_filter.text = "idle"
	win._anim_filter.text_changed.emit("idle")
	win._anim_list.select(0, false)
	var pick_b := win._anim_list.get_item_text(0)
	win._anim_filter.text = ""
	win._anim_filter.text_changed.emit("")
	var pick_got := win._picked_anim_names()
	var pick_sel := 0
	for i in win._anim_list.item_count:
		if win._anim_list.is_selected(i):
			pick_sel += 1
	if pick_got.size() != 2 or not pick_got.has(pick_a) or not pick_got.has(pick_b) or pick_sel != 2:
		printerr("검색을 바꾸자 선택이 풀림: 고른 것 %s / 목록 선택 %d개 (기대 %s, %s)" % [str(pick_got), pick_sel, pick_a, pick_b])
		quit(1); return
	print("7-1) 검색을 바꿔도 선택 유지 — %s · 표시 \"%s\"" % [str(pick_got), win._anim_count.text])
	win._picked_anims.clear()
	win._fill_anim_list()

	# 그리기 순서 목록 (자동)
	if win._z_list.item_count != 15:
		printerr("z 목록 항목 수 이상: %d" % win._z_list.item_count); quit(1); return
	var auto_order := []
	for i in win._z_list.item_count:
		auto_order.append(win._z_list.get_item_text(i))
	print("8) 그리기 순서 자동 %d개 — 맨뒤=%s 맨앞=%s" % [
		auto_order.size(), auto_order[0], auto_order[-1]])
	# 기본 프로필은 발가락을 발에 합친다(발은 한 장, 발목 회전만). 늘이기를 끈 파트는 없어야 한다
	var lrig := win.baker.rig
	if lrig.order.size() != 15 or lrig.parts.has("L_Toe") or lrig.parts.has("R_Toe") or not lrig.no_stretch.is_empty():
		printerr("파트 구성 이상: 파트 %d개, 발가락 파트 %s, 늘이기 끔 %s" % [
			lrig.order.size(), lrig.parts.has("L_Toe"), str(lrig.no_stretch.keys())])
		quit(1); return
	print("8-1) 파트 %d개 · 순서 목록 %d줄 — 발가락은 발에 합침, 늘이기는 전 파트 켬" % [
		lrig.order.size(), win._z_list.item_count])

	# 수동 재정렬 -> 자동 해제 확인
	win._z_list.select(0)
	win._move_z(1)
	if win._z_auto.button_pressed:
		printerr("재정렬했는데 자동이 안 꺼짐"); quit(1); return
	if win._z_list.get_item_text(1) != auto_order[0]:
		printerr("재정렬이 반영되지 않음"); quit(1); return
	var ov := win._current_z_override()
	print("9) 수동 재정렬 OK — 자동 해제됨, override %d개 (맨뒤=%s)" % [ov.size(), ov[0]])

	# 다중 선택 이동 검증
	var before := []
	for i in win._z_list.item_count:
		before.append(win._z_list.get_item_text(i))
	# 인접 3개(4,5,6)를 위로 한 칸
	win._z_list.deselect_all()
	for i in [4, 5, 6]:
		win._z_list.select(i, false)
	win._move_z(-1)
	var after := []
	for i in win._z_list.item_count:
		after.append(win._z_list.get_item_text(i))
	var expect := before.duplicate()
	var moved_up := expect.pop_at(3)
	expect.insert(6, moved_up)          # 4,5,6 이 위로 = 3번이 6번 자리로
	if after != expect:
		printerr("인접 다중 이동 결과 불일치\n 기대: %s\n 실제: %s" % [expect, after])
		quit(1); return
	if Array(win._z_list.get_selected_items()) != [3, 4, 5]:
		printerr("이동 후 선택 유지 실패: %s" % str(win._z_list.get_selected_items()))
		quit(1); return
	print("11) 인접 3개 위로 이동 OK, 선택도 따라감 %s" % str(win._z_list.get_selected_items()))

	# 떨어진 항목 2개를 아래로
	win._z_list.deselect_all()
	win._z_list.select(1, false)
	win._z_list.select(8, false)
	var b1 := win._z_list.get_item_text(1)
	var b8 := win._z_list.get_item_text(8)
	win._move_z(1)
	if win._z_list.get_item_text(2) != b1 or win._z_list.get_item_text(9) != b8:
		printerr("비인접 다중 이동 실패"); quit(1); return
	print("12) 떨어진 2개 아래로 이동 OK")

	# 경계에서 막히는지
	win._z_list.deselect_all()
	win._z_list.select(0, false)
	win._z_list.select(1, false)
	var top := win._z_list.get_item_text(0)
	win._move_z(-1)
	if win._z_list.get_item_text(0) != top:
		printerr("맨 위에서 위로 이동이 막히지 않음"); quit(1); return
	print("13) 경계 차단 OK")

	# 파트로 들어갔다가 전체로 복귀
	win._isolate.select(3)
	win._isolate.item_selected.emit(3)      # 실제 클릭과 같은 경로로
	while win._busy:
		await process_frame
	if win._iso_parts.size() != 1:
		printerr("드롭다운 격리가 반영 안 됨: %s" % str(win._iso_parts)); quit(1); return
	var iso_txt := String(win._iso_parts[0])
	win._show_composite()
	while win._busy:
		await process_frame
	if win._isolate.selected != 0 or not win._iso_parts.is_empty():
		printerr("전체 복귀 실패"); quit(1); return
	print("10) 드롭다운 격리(%s) -> 전체 복귀 OK" % iso_txt)

	# 다중 선택이 프리뷰 갱신 후에도 살아남는지 + 고른 것만 보이는지
	win._z_auto.button_pressed = true
	win._show_composite()
	while win._busy:
		await process_frame
	win._z_list.deselect_all()
	for i in [2, 3, 4]:
		win._z_list.select(i, false)
	win._on_z_selection_changed()               # Shift 클릭이 만드는 상태와 동일
	while win._busy:
		await process_frame
	if Array(win._z_list.get_selected_items()) != [2, 3, 4]:
		printerr("갱신 후 다중 선택이 날아감: %s" % str(win._z_list.get_selected_items()))
		quit(1); return
	var expect_parts := 0
	for i in [2, 3, 4]:
		expect_parts += win.baker.rig.layer_parts(win._z_list.get_item_text(i)).size()
	if win._iso_parts.size() != expect_parts:
		printerr("프리뷰 대상 수 불일치: %s (기대 %d — 발 줄이면 발가락 포함)" % [str(win._iso_parts), expect_parts]); quit(1); return
	# 고른 3개만 렌더되는지: 전체 합성보다 픽셀이 확실히 적어야 한다
	var only3: Image = await win.baker.render_parts(win._iso_parts)
	var allimg: Image = await win.baker.render_all_parts_composite()
	var n3 := 0
	var na := 0
	for y in only3.get_height():
		for x in only3.get_width():
			if only3.get_pixel(x, y).a > 0.0:
				n3 += 1
			if allimg.get_pixel(x, y).a > 0.0:
				na += 1
	if n3 == 0 or n3 >= na:
		printerr("선택한 것만 렌더되지 않음 (선택 %d px / 전체 %d px)" % [n3, na])
		quit(1); return
	print("15) 다중 선택 유지 %s → 프리뷰 %s (%d px / 전체 %d px)"
		% [str(win._z_list.get_selected_items()), str(win._iso_parts), n3, na])
	# 겹치는 조합으로 한 장 저장(눈으로 확인용)
	win._yaw.value = -45.0
	await win._refresh_preview()
	while win._busy:
		await process_frame
	var pair := PackedStringArray(["Torso", "R_UpperArm"])
	(await win.baker.render_parts(pair)).save_png("res://puppet_test/_ui_pair.png")
	(await win.baker.render_all_parts_composite()).save_png("res://puppet_test/_ui_all.png")
	win._yaw.value = 90.0
	win._show_composite()
	while win._busy:
		await process_frame

	# 해상도 변경이 뷰포트에 실제로 반영되고, 캐릭터가 계속 중앙에 오는지
	win._isolate.select(0)
	win._yaw.value = 90.0
	win._pitch.value = 0.0
	for r in [192, 96, 64, 256]:
		win._res.value = r
		await win._refresh_preview()
		while win._busy:
			await process_frame
		var vs := win.baker.viewport.size
		var im: Image = await win.baker.render_all_parts_composite()
		var used := im.get_used_rect()
		if vs != Vector2i(r, r) or im.get_width() != r:
			printerr("해상도 %d 반영 실패: viewport=%s image=%d" % [r, vs, im.get_width()])
			quit(1); return
		# 중심 오차: 실루엣 중심이 화면 중심에서 얼마나 벗어났나
		var cx := float(used.position.x) + float(used.size.x) * 0.5 - float(r) * 0.5
		var cy := float(used.position.y) + float(used.size.y) * 0.5 - float(r) * 0.5
		var fill := float(used.size.y) / float(r)
		print("15) %3dpx → viewport %s, 실루엣 %dx%d, 중심오차 (%.1f, %.1f), 세로채움 %.0f%%"
			% [r, vs, used.size.x, used.size.y, cx, cy, fill * 100.0])
		if absf(cx) > 2.0 or absf(cy) > 2.0:
			printerr("  ↑ 중심이 틀어짐"); quit(1); return
		if fill < 0.8:
			printerr("  ↑ 화면을 제대로 못 채움"); quit(1); return

	# 파일 다이얼로그가 툴 창의 자식으로 붙는지 (에디터 본체 뒤로 안 밀리게)
	win._on_browse()
	await process_frame
	var fd: Node = null
	for c in win.get_children():
		if c is FileDialog or c.get_class() == "EditorFileDialog":
			fd = c
	if fd == null:
		printerr("파일 다이얼로그가 창의 자식으로 안 붙음"); quit(1); return
	print("14) 파일 다이얼로그(%s) 부모 = %s — 툴 창 자식 OK"
		% [fd.get_class(), fd.get_parent().name])
	fd.queue_free()
	await process_frame

	# ---- 2D 순서 합성이 실제로 순서를 반영하는지 ----
	# 아래 픽셀 비교는 3D 렌더와 같은 캔버스 크기여야 하므로 부드러운 도트 이동은 끄고 한다(21 에서 따로 검사)
	win._smooth.button_pressed = false
	win._yaw.value = -45.0
	win._show_composite()
	while win._busy:
		await process_frame
	win._mode_2d.button_pressed = true
	await win._refresh_preview()
	while win._busy:
		await process_frame
	var a := win._composite_by_order(PackedStringArray())
	# Torso 를 맨 앞으로 보내면 그림이 달라져야 한다
	var ti := -1
	for i in win._z_list.item_count:
		if win._z_list.get_item_text(i) == "Torso":
			ti = i
	if ti < 0:
		printerr("Torso 없음"); quit(1); return
	win._z_list.deselect_all()
	win._z_list.select(ti, false)
	while ti < win._z_list.item_count - 1:
		win._move_z(1)
		ti += 1
	while win._busy:
		await process_frame
	if win._z_list.get_item_text(win._z_list.item_count - 1) != "Torso":
		printerr("Torso 를 맨 앞으로 못 보냄"); quit(1); return
	var b := win._composite_by_order(PackedStringArray())
	var diff := 0
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				diff += 1
	if diff == 0:
		printerr("순서를 바꿨는데 2D 합성 결과가 동일 — 순서가 반영 안 됨")
		quit(1); return
	if not win._mode_2d.button_pressed:
		printerr("순서 변경 시 2D 모드로 자동 전환 안 됨"); quit(1); return
	# 실제 퍼펫 뷰포트(스프라이트 z_index)도 CPU 합성과 같은 순서로 그려야 한다(밑깔개 z −1 이 끼어도 마찬가지)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var vp_img: Image = win._puppet_vp.get_texture().get_image()
	vp_img = vp_img.get_region(Rect2i(win._puppet_pad(), win.baker.opts.view_size))
	var zg_area := 0
	var zg_diff := 0
	for y in b.get_height():
		for x in b.get_width():
			var pb := b.get_pixel(x, y)
			var pv := vp_img.get_pixel(x, y)
			if pb.a > 0.0 or pv.a > 0.0:
				zg_area += 1
				if (pb.a > 0.0) != (pv.a > 0.0) or (pb.a > 0.0 and (Vector3(pb.r, pb.g, pb.b) - Vector3(pv.r, pv.g, pv.b)).length() > 0.15):
					zg_diff += 1
	var zg_pct := 100.0 * float(zg_diff) / float(maxi(zg_area, 1))
	if zg_pct > 3.0:
		printerr("퍼펫 뷰포트가 그리기 순서를 안 지킴: CPU 합성과 %.1f%% 다름" % zg_pct); quit(1); return
	# 3D 렌더와는 달라야 정상(3D 는 지정 순서를 무시하므로)
	var d3: Image = await win.baker.render_all_parts_composite()
	var diff3 := 0
	for y in b.get_height():
		for x in b.get_width():
			if b.get_pixel(x, y) != d3.get_pixel(x, y):
				diff3 += 1
	print("18) 2D 순서 반영 OK — Torso 맨앞 전후 %d px 변화, 3D 렌더와 %d px 차이, 퍼펫 뷰포트 vs CPU 합성 %.1f%% 다름"
		% [diff, diff3, zg_pct])
	a.save_png("res://puppet_test/_order_before.png")
	b.save_png("res://puppet_test/_order_after.png")
	d3.save_png("res://puppet_test/_order_3d.png")

	# 2D 순서 모드에서도 재생이 되는지 (3D 재렌더 없이 자세만 바뀌어야 한다)
	win._rest_anim.select(0)
	for i in win._rest_anim.item_count:
		if win._rest_anim.get_item_text(i) == "Jog_Fwd":
			win._rest_anim.select(i)
	win._play.button_pressed = true
	await win._refresh_preview()
	while win._busy:
		await process_frame
	if not win.is_processing():
		printerr("2D 모드에서 재생이 켜지지 않음"); quit(1); return
	var f0: Image = win._puppet_vp.get_texture().get_image()
	var t0 := win._play_t
	for _k in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var f1: Image = win._puppet_vp.get_texture().get_image()
	var moved := 0
	for y in f0.get_height():
		for x in f0.get_width():
			if f0.get_pixel(x, y) != f1.get_pixel(x, y):
				moved += 1
	if win._play_t <= t0 or moved == 0:
		printerr("2D 모드 재생이 안 움직임 (t %.3f→%.3f, 픽셀차 %d)"
			% [t0, win._play_t, moved]); quit(1); return
	print("    2D 순서 모드 재생 OK — t %.2f→%.2f, 프레임 간 %d px 변화"
		% [t0, win._play_t, moved])
	f1.save_png("res://puppet_test/_order_playing.png")
	win._play.button_pressed = false
	await win._refresh_preview()
	while win._busy:
		await process_frame

	# 파트 캐시가 한 자세에서 일관되게 찍혔는지 검사한다.
	# 렌더 도중 자세가 흘렀다면 팔다리가 떨어져 나가므로 3D 렌더와 크게 벌어진다.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var rest2d: Image = win._puppet_vp.get_texture().get_image()
	# 2D 순서 뷰포트는 캔버스보다 여유 폭만큼 넓다 — 캔버스 부분만 잘라 3D 와 비교
	rest2d = rest2d.get_region(Rect2i(win._puppet_pad(), win.baker.opts.view_size))
	var rest3d: Image = await win.baker.render_all_parts_composite()
	var area := 0
	var gap := 0
	for y in rest2d.get_height():
		for x in rest2d.get_width():
			var a2 := rest2d.get_pixel(x, y).a > 0.0
			var a3 := rest3d.get_pixel(x, y).a > 0.0
			if a2 or a3:
				area += 1
			if a2 != a3:
				gap += 1
	var pct := 100.0 * float(gap) / float(maxi(area, 1))
	print("    레스트에서 2D 퍼펫 vs 3D 실루엣 차이 %.1f%%" % pct)
	if pct > 25.0:
		printerr("파트 캐시가 한 자세로 안 찍혔습니다(팔다리 분리 의심)")
		quit(1); return

	# ---- 부드러운 도트 이동: 2D 퍼펫을 화면 배율로 그리고 셰이더를 붙이는지 ----
	win._smooth.button_pressed = true
	await win._refresh_preview()
	while win._busy:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var sm_vs := win.baker.opts.view_size
	var sm_pad := win._puppet_pad()
	var sm_full := Vector2(sm_vs + sm_pad * 2)   # 뷰포트 = 캔버스 + 여유 폭
	var sm_z := win._current_zoom()
	var sm_want := Vector2i((sm_full * clampf(sm_z, 1.0, DRMainWindow.PUPPET_SCALE_MAX)).round())
	if win._puppet_vp.size != sm_want:
		printerr("부드러운 도트: 퍼펫 뷰포트 %s (기대 %s, 화면 배율 %.2f)" % [win._puppet_vp.size, sm_want, sm_z]); quit(1); return
	var sm_mats := 0
	for sm_p in win._puppet_bones.keys():
		var sm_art: Sprite2D = win._puppet_bones[sm_p]["art"]
		if sm_art.material is ShaderMaterial:
			sm_mats += 1
	if sm_mats != win._puppet_bones.size():
		printerr("부드러운 도트: 셰이더가 %d/%d 파트에만 붙음" % [sm_mats, win._puppet_bones.size()]); quit(1); return
	if win._zoom_label.text != "맞춤":
		printerr("부드러운 도트: 뷰포트 크기가 바뀌면서 확대 상태가 풀림/바뀜 (%s)" % win._zoom_label.text); quit(1); return
	if is_equal_approx(win._puppet_scale, sm_z) and win._preview.size != Vector2(win._puppet_vp.size):
		printerr("부드러운 도트: 화면 배율로 그렸는데 1:1 로 안 붙음 (%s vs %s)" % [win._preview.size, win._puppet_vp.size]); quit(1); return
	# 크게 그린 결과를 캔버스 크기로 줄였을 때 끈 상태(rest2d)와 실루엣이 거의 같아야 한다
	var sm_img: Image = win._puppet_vp.get_texture().get_image()
	sm_img = sm_img.get_region(Rect2i(Vector2i((Vector2(sm_pad) * win._puppet_scale).round()),
		Vector2i((Vector2(sm_vs) * win._puppet_scale).round())))
	sm_img.resize(sm_vs.x, sm_vs.y, Image.INTERPOLATE_NEAREST)
	var sm_area := 0
	var sm_gap := 0
	for y in rest2d.get_height():
		for x in rest2d.get_width():
			var sm_a1 := rest2d.get_pixel(x, y).a > 0.0
			var sm_a2 := sm_img.get_pixel(x, y).a > 0.0
			if sm_a1 or sm_a2:
				sm_area += 1
			if sm_a1 != sm_a2:
				sm_gap += 1
	var sm_pct := 100.0 * float(sm_gap) / float(maxi(sm_area, 1))
	if sm_pct > 15.0:
		printerr("부드러운 도트: 끈 상태와 실루엣 차이 %.1f%%" % sm_pct); quit(1); return
	# 확대하면 뷰포트도 따라 커지고, 프리뷰 크기는 원래 크기 × 배율이어야 한다
	win._step_zoom(1, win._pv_area.size * 0.5)
	var sm_z2 := win._current_zoom()
	var sm_want2 := Vector2i((sm_full * clampf(sm_z2, 1.0, DRMainWindow.PUPPET_SCALE_MAX)).round())
	if win._puppet_vp.size != sm_want2 or (win._preview.size - sm_full * sm_z2).length() > 2.0:
		printerr("부드러운 도트: 확대 %.2f 에서 뷰포트 %s (기대 %s), 프리뷰 %s" % [sm_z2, win._puppet_vp.size, sm_want2, win._preview.size]); quit(1); return
	win._fit_preview()
	# 캔버스 틀 표시: 2D 모드에서 보이고, 위치 = 프리뷰 + 여유 폭 × 배율, 크기 = 캔버스 × 배율
	if not win._canvas_box.visible or (win._canvas_box.size - Vector2(sm_vs) * win._current_zoom()).length() > 1.5 \
			or (win._canvas_box.position - (win._preview.position + Vector2(sm_pad) * win._current_zoom())).length() > 1.5:
		printerr("캔버스 틀 이상: 보임 %s 위치 %s 크기 %s" % [win._canvas_box.visible, win._canvas_box.position, win._canvas_box.size]); quit(1); return
	print("21) 부드러운 도트 이동 OK — 맞춤 %.2f배 → 뷰포트 %s(캔버스 %s + 여유 %s×2), 셰이더 %d개, 캔버스로 줄이면 실루엣 차이 %.1f%%, 확대 %.0f%% → 뷰포트 %s, 캔버스 틀 표시 OK"
		% [sm_z, sm_want, sm_vs, sm_pad, sm_mats, sm_pct, sm_z2 * 100.0, sm_want2])
	win._rest_anim.select(0)
	for i in win._rest_anim.item_count:
		if win._rest_anim.get_item_text(i) == "Idle":
			win._rest_anim.select(i)
	win._mode_2d.button_pressed = false
	win._z_auto.button_pressed = true
	win._yaw.value = 90.0
	win._show_composite()
	while win._busy:
		await process_frame

	# ---- 프리뷰 확대/이동 ----
	win._fit_preview()
	await process_frame
	var fit_z := win._current_zoom()
	var anchor := win._pv_area.size * 0.5
	# 앵커(커서 위치)의 이미지 좌표가 확대 전후로 같아야 한다
	var before_pt := (anchor - win._preview.position) / win._current_zoom()
	win._step_zoom(1, anchor)
	var z1 := win._current_zoom()
	var after_pt := (anchor - win._preview.position) / z1
	if z1 <= fit_z:
		printerr("확대가 안 됨: %.2f -> %.2f" % [fit_z, z1]); quit(1); return
	if (before_pt - after_pt).length() > 1.5:
		printerr("앵커가 밀림: %s -> %s" % [before_pt, after_pt]); quit(1); return
	# 몇 번 더 확대해도 이미지 크기가 배율과 일치하는지
	for _k in 3:
		win._step_zoom(1, anchor)
	var zn := win._current_zoom()
	var ts := Vector2(win._preview.texture.get_size())
	if (win._preview.size - ts * zn).length() > 1.0:
		printerr("확대 크기 불일치: %s vs %s" % [win._preview.size, ts * zn]); quit(1); return
	# 이동
	var p0 := win._preview.position
	win._pan += Vector2(40, -25)
	win._layout_preview()
	if (win._preview.position - p0 - Vector2(40, -25)).length() > 1.5:
		printerr("이동 반영 안 됨"); quit(1); return
	# 정수 스냅(도트가 흐려지지 않게)
	win._pan += Vector2(0.37, 0.62)
	win._layout_preview()
	if win._preview.position != win._preview.position.round():
		printerr("정수 스냅 안 됨: %s" % win._preview.position); quit(1); return
	print("17) 확대 %.0f%% → %.0f%%, 앵커 고정 OK, 이동/정수스냅 OK"
		% [fit_z * 100.0, zn * 100.0])
	# 확대된 상태를 캡처(도트가 또렷하게 커지는지 눈으로 확인용)
	win._fit_preview()
	win._step_zoom(1, anchor)
	win._step_zoom(1, anchor)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	win.get_texture().get_image().save_png("res://puppet_test/_ui_zoomed.png")
	print("    확대 상태 캡처 (%s) -> _ui_zoomed.png" % win._zoom_label.text)

	win._fit_preview()
	if win._zoom_label.text != "맞춤":
		printerr("맞춤 복귀 실패: %s" % win._zoom_label.text); quit(1); return

	# ---- 프리셋 저장 / 불러오기 왕복 ----
	win._yaw.value = -33.0
	win._pitch.value = 12.0
	win._res.value = 96
	win._bands.value = 5
	win._margin.value = 3
	win._fps.value = 20
	win._stretch.button_pressed = false
	win._smooth.button_pressed = false
	win._keep_anims.button_pressed = false
	win._off_y.value = 7
	win._planar.button_pressed = true
	win._pose_auto.button_pressed = false
	win._pose_yaw.value = 45
	win._outline_px.value = 2
	win._outline_color.color = Color(0.2, 0.1, 0.0)
	win._outline_whole.button_pressed = false
	win._out_edit.text = "res://preset_out"
	win._anim_filter.text = ""
	win._fill_anim_list()
	win._anim_list.deselect_all()
	for i in [0, 4, 9]:
		win._anim_list.select(i, false)
	var want_anims := []
	for i in [0, 4, 9]:
		want_anims.append(win._anim_list.get_item_text(i))
	# 수동 그리기 순서를 만들어 둔다
	win._z_auto.button_pressed = false
	win._z_list.deselect_all()
	win._z_list.select(0, false)
	win._move_z(1)
	win._move_z(1)
	var want_order := []
	for i in win._z_list.item_count:
		want_order.append(win._z_list.get_item_text(i))
	while win._busy:
		await process_frame

	var pset := win._collect_preset()
	var ppath := "res://puppet_test/_test_preset.tres"
	if ResourceSaver.save(pset, ppath) != OK:
		printerr("프리셋 저장 실패"); quit(1); return

	# 값을 전부 흐트러뜨린 뒤 불러와서 복원되는지 본다
	win._yaw.value = 90.0
	win._pitch.value = 0.0
	win._res.value = 256
	win._bands.value = 2
	win._margin.value = 10
	win._fps.value = 12
	win._stretch.button_pressed = true
	win._smooth.button_pressed = true
	win._keep_anims.button_pressed = true
	win._rest_auto.button_pressed = true
	win._off_y.value = 0
	win._planar.button_pressed = false
	win._pose_auto.button_pressed = true
	win._pose_yaw.value = 90
	win._outline_px.value = 0
	win._outline_color.color = Color.BLACK
	win._outline_whole.button_pressed = true
	win._out_edit.text = "res://elsewhere"
	win._z_auto.button_pressed = true
	win._anim_list.deselect_all()
	while win._busy:
		await process_frame

	var loaded = ResourceLoader.load(ppath, "", ResourceLoader.CACHE_MODE_IGNORE)
	if not (loaded is DRPreset):
		printerr("프리셋 로드 실패"); quit(1); return
	win._apply_preset(loaded as DRPreset)
	while win._busy:
		await process_frame

	var bad_fields: Array = []
	if absf(win._yaw.value - (-33.0)) > 0.01: bad_fields.append("yaw=%s" % win._yaw.value)
	if absf(win._pitch.value - 12.0) > 0.01: bad_fields.append("pitch=%s" % win._pitch.value)
	if int(win._res.value) != 96: bad_fields.append("res=%s" % win._res.value)
	if int(win._bands.value) != 5: bad_fields.append("bands=%s" % win._bands.value)
	if int(win._margin.value) != 3: bad_fields.append("margin=%s" % win._margin.value)
	if int(win._fps.value) != 20: bad_fields.append("fps=%s" % win._fps.value)
	if win._stretch.button_pressed: bad_fields.append("stretch")
	if win._smooth.button_pressed: bad_fields.append("smooth")
	if win._rest_auto.button_pressed: bad_fields.append("rest_auto")
	if win._keep_anims.button_pressed: bad_fields.append("keep_anims")
	if int(win._off_y.value) != 7: bad_fields.append("offset_y=%s" % win._off_y.value)
	if not win._planar.button_pressed or win._pose_auto.button_pressed or int(win._pose_yaw.value) != 45 or not win._pose_yaw.editable:
		bad_fields.append("planar/pose_yaw")
	if int(win._outline_px.value) != 2 or not win._outline_color.color.is_equal_approx(Color(0.2, 0.1, 0.0)) or win._outline_whole.button_pressed:
		bad_fields.append("outline")
	if win._out_edit.text != "res://preset_out": bad_fields.append("out=%s" % win._out_edit.text)
	if win._z_auto.button_pressed: bad_fields.append("z_auto 가 다시 켜짐")
	var got_order := []
	for i in win._z_list.item_count:
		got_order.append(win._z_list.get_item_text(i))
	if got_order != want_order: bad_fields.append("그리기 순서 불일치")
	var got_anims := []
	for i in win._anim_list.item_count:
		if win._anim_list.is_selected(i):
			got_anims.append(win._anim_list.get_item_text(i))
	if got_anims != want_anims:
		bad_fields.append("애니 선택 불일치 %s vs %s" % [got_anims, want_anims])
	if bad_fields.size() > 0:
		printerr("프리셋 복원 실패: %s" % String(", ").join(PackedStringArray(bad_fields)))
		quit(1); return
	print("19) 프리셋 왕복 OK — 시점/도트/순서(%d개)/애니(%d개)/출력 전부 복원"
		% [got_order.size(), got_anims.size()])
	win._z_auto.button_pressed = true
	win._off_y.value = 0
	win._planar.button_pressed = false
	win._pose_auto.button_pressed = true
	win._outline_px.value = 0
	win._outline_color.color = Color.BLACK
	win._outline_whole.button_pressed = true
	win._res.value = 256
	win._yaw.value = 90.0
	win._pitch.value = 0.0
	win._show_composite()
	while win._busy:
		await process_frame

	# ---- 3D 회전 기즈모 (2. 시점 칸과 연동) ----
	win._mode_2d.button_pressed = false
	win._yaw.value = 90.0
	win._pitch.value = 0.0
	await win._refresh_preview()
	while win._busy:
		await process_frame
	if not win._gizmo.visible:
		printerr("3D 모드인데 기즈모가 안 보임"); quit(1); return
	# pitch 부호: 양수 = 위에서 내려다봄
	win._pitch.value = 60.0
	await win._refresh_preview()
	while win._busy:
		await process_frame
	var g_cy := win.baker.camera.global_position.y - win.baker._model_aabb.get_center().y
	if g_cy <= 0.0:
		printerr("pitch +60 인데 카메라가 모델 아래 (%.2f)" % g_cy); quit(1); return
	win._pitch.value = 0.0
	await win._refresh_preview()
	while win._busy:
		await process_frame
	# 드래그 흉내: 누르고 → 오른쪽 아래로 20px 씩 두 번 → 뗌 (기대: yaw 90→70, pitch 0→20)
	var g_pos := Vector2(46, 46)
	var g_down := InputEventMouseButton.new()
	g_down.button_index = MOUSE_BUTTON_LEFT
	g_down.pressed = true
	g_down.position = g_pos
	win._on_gizmo_input(g_down)
	for g_k in 2:
		var g_mv := InputEventMouseMotion.new()
		g_mv.relative = Vector2(20, 20)
		g_mv.position = g_pos + Vector2(20, 20) * float(g_k + 1)
		win._on_gizmo_input(g_mv)
	var g_yaw := win._yaw.value
	var g_pitch := win._pitch.value
	var g_camyaw := win.baker.opts.yaw
	var g_camdir := -win.baker.camera.global_transform.basis.z
	var g_up := InputEventMouseButton.new()
	g_up.button_index = MOUSE_BUTTON_LEFT
	g_up.pressed = false
	g_up.position = g_pos + Vector2(40, 40)
	win._on_gizmo_input(g_up)
	while win._busy:
		await process_frame
	if absf(g_yaw - 70.0) > 0.01 or absf(g_pitch - 20.0) > 0.01:
		printerr("드래그가 시점 칸에 반영 안 됨: yaw %.2f pitch %.2f (기대 70 / 20)" % [g_yaw, g_pitch]); quit(1); return
	if absf(g_camyaw - g_yaw) > 0.01 or g_camdir.y >= 0.0:
		printerr("드래그 중 카메라가 칸 값과 어긋남 (카메라 yaw %.2f, 시선 y %.2f)" % [g_camyaw, g_camdir.y]); quit(1); return
	var g_pset := win._collect_preset()
	if absf(g_pset.yaw - 70.0) > 0.01 or absf(g_pset.pitch - 20.0) > 0.01:
		printerr("기즈모 각도가 프리셋(출력)에 안 들어감"); quit(1); return
	if absf(win.baker.opts.yaw - 70.0) > 0.01 or absf(win.baker.opts.pitch - 20.0) > 0.01:
		printerr("손을 뗀 뒤 베이커 옵션이 칸 값과 다름"); quit(1); return
	# 축 클릭: +X 끝을 눌렀다 떼면 오른쪽(+X)에서 보기
	var g_xpos := Vector2(-999, -999)
	for g_ax in win._gizmo_axes():
		if String(g_ax["name"]) == "X":
			g_xpos = g_ax["pos"]
	var g_cdown := InputEventMouseButton.new()
	g_cdown.button_index = MOUSE_BUTTON_LEFT
	g_cdown.pressed = true
	g_cdown.position = g_xpos
	win._on_gizmo_input(g_cdown)
	var g_cup := InputEventMouseButton.new()
	g_cup.button_index = MOUSE_BUTTON_LEFT
	g_cup.pressed = false
	g_cup.position = g_xpos
	win._on_gizmo_input(g_cup)
	while win._busy:
		await process_frame
	if absf(win._yaw.value - 90.0) > 0.5 or absf(win._pitch.value) > 0.5:
		printerr("X 축 클릭 → yaw %.1f pitch %.1f (기대 90 / 0)" % [win._yaw.value, win._pitch.value]); quit(1); return
	# 2D 순서 모드에서는 숨김
	win._mode_2d.button_pressed = true
	while win._busy:
		await process_frame
	if win._gizmo.visible:
		printerr("2D 모드인데 기즈모가 보임"); quit(1); return
	win._mode_2d.button_pressed = false
	while win._busy:
		await process_frame
	print("20) 기즈모 OK — pitch +60 은 위에서(+%.2f), 드래그 → 칸 yaw 70·pitch 20 = 카메라 = 프리셋, X축 클릭 → yaw 90, 2D 에서 숨김" % g_cy)

	# ---- 캐릭터 화면 위치 이동 (자동 맞춤 끔일 때) ----
	win._mode_2d.button_pressed = false
	win._autofit.button_pressed = false
	win._off_x.value = 0
	win._off_y.value = 0
	await win._refresh_preview()
	while win._busy:
		await process_frame
	var off0: Image = await win.baker.render_all_parts_composite()
	win._off_x.value = -10
	win._off_y.value = 12
	await win._refresh_preview()
	while win._busy:
		await process_frame
	var off1: Image = await win.baker.render_all_parts_composite()
	var off_d := off1.get_used_rect().position - off0.get_used_rect().position
	if absi(off_d.x + 10) > 1 or absi(off_d.y + 12) > 1:
		printerr("캐릭터 이동이 안 맞음: X -10 · Y +12(위) 인데 찍힌 위치 이동 %s (기대 약 (-10, -12))" % str(off_d)); quit(1); return
	print("22) 캐릭터 이동 OK — X -10 · Y +12(위) → 찍힌 위치 %s 이동 (Ortho %.3f 그대로)" % [str(off_d), win.baker.camera.size])
	win._off_x.value = 0
	win._off_y.value = 0
	win._autofit.button_pressed = true
	await win._refresh_preview()
	while win._busy:
		await process_frame

	# ---- ▶ 재생 애니 분리: 레스트 포즈는 그대로, 6번에서 고른 애니를 돌림 ----
	for i in win._rest_anim.item_count:
		if win._rest_anim.get_item_text(i) == "Idle":
			win._rest_anim.select(i)
	win._picked_anims.clear()
	win._picked_anims["Idle"] = true
	win._picked_anims["Jog_Fwd"] = true
	win._anim_filter.text = ""
	win._fill_anim_list()
	var pl_found := false
	for i in win._play_anim.item_count:
		if String(win._play_anim.get_item_metadata(i)) == "Jog_Fwd":
			win._play_anim.select(i)
			pl_found = true
	if not pl_found or win._play_anim.item_count != 2:
		printerr("재생 드롭다운이 6번 선택으로 안 채워짐 (%d개)" % win._play_anim.item_count); quit(1); return
	if win._current_play_anim() != "Jog_Fwd" or win._current_rest_anim() != "Idle":
		printerr("재생 애니 %s / 레스트 %s (기대 Jog_Fwd / Idle)" % [win._current_play_anim(), win._current_rest_anim()]); quit(1); return
	win._mode_2d.button_pressed = false
	win._play.button_pressed = true
	await win._refresh_preview()
	while win._busy:
		await process_frame
	var pl_3d := String(win.baker.anim_player.current_animation)
	if pl_3d != "Jog_Fwd" or win.baker.anim_player.speed_scale != 1.0:
		printerr("3D 재생이 Jog_Fwd 가 아님: %s (속도 %.1f)" % [pl_3d, win.baker.anim_player.speed_scale]); quit(1); return
	win._mode_2d.button_pressed = true
	await win._refresh_preview()
	while win._busy:
		await process_frame
	var pl_sig := win._part_sig
	var pl_t0 := win._play_t
	for _k in 20:
		await process_frame
	var pl_2d := String(win.baker.anim_player.current_animation)
	if pl_2d != "Jog_Fwd" or win._play_t <= pl_t0 or win._part_sig != pl_sig:
		printerr("2D 재생 이상: 애니 %s · t %.2f→%.2f · 파트 캐시 바뀜 %s" % [pl_2d, pl_t0, win._play_t, win._part_sig != pl_sig]); quit(1); return
	win._play.button_pressed = false
	await win._refresh_preview()
	while win._busy:
		await process_frame
	win._picked_anims.clear()
	win._fill_anim_list()
	if win._play_anim.item_count != 1 or win._current_play_anim() != "Idle":
		printerr("6번 선택이 없는데 재생 애니가 레스트가 아님: %s" % win._current_play_anim()); quit(1); return
	win._mode_2d.button_pressed = false
	await win._refresh_preview()
	while win._busy:
		await process_frame
	print("23) ▶ 재생 애니 분리 OK — 레스트 Idle 그대로, 3D·2D 모두 Jog_Fwd 재생(파트 캐시 유지), 6번 선택 없으면 레스트 애니")

	# ---- 재생 속도 + 스크럽 ----
	win._picked_anims.clear()
	win._picked_anims["Jog_Fwd"] = true
	win._fill_anim_list()
	for i in win._play_anim.item_count:
		if String(win._play_anim.get_item_metadata(i)) == "Jog_Fwd":
			win._play_anim.select(i)
	var sp_len: float = win.baker.anim_player.get_animation("Jog_Fwd").length
	# 2D · ×1/4: 20프레임 동안 흐른 시간이 실시간의 약 1/4
	win._mode_2d.button_pressed = true
	win._speed.select(2)
	win._speed.item_selected.emit(2)
	win._play.button_pressed = true
	await win._refresh_preview()
	while win._busy:
		await process_frame
	var sp_t0: float = win._play_t
	var sp_wall := Time.get_ticks_msec()
	for _k in 20:
		await process_frame
	var sp_real := float(Time.get_ticks_msec() - sp_wall) / 1000.0
	var sp_adv := win._play_t - sp_t0
	if sp_adv <= 0.0 or sp_adv > sp_real * 0.5:
		printerr("2D ×1/4 재생 이상: 실시간 %.2f초에 %.3f초 흐름 (기대 약 1/4)" % [sp_real, sp_adv]); quit(1); return
	# 멈춤 + 스크럽: 시간이 안 흐르고, 슬라이더로 옮기면 그 시점
	win._speed.select(4)
	win._speed.item_selected.emit(4)
	var sp_hold: float = win._play_t
	for _k in 10:
		await process_frame
	if absf(win._play_t - sp_hold) > 0.0001:
		printerr("멈춤인데 시간이 흐름: %.3f → %.3f" % [sp_hold, win._play_t]); quit(1); return
	win._scrub.value = 0.5
	win._scrub.value_changed.emit(0.5)
	if absf(win._play_t - sp_len * 0.5) > 0.001:
		printerr("스크럽 반영 안 됨: %.3f (기대 %.3f)" % [win._play_t, sp_len * 0.5]); quit(1); return
	# 3D · 멈춤 + 스크럽: 엔진 재생 위치가 슬라이더를 따라야 한다
	win._mode_2d.button_pressed = false
	await win._refresh_preview()
	while win._busy:
		await process_frame
	if win.baker.anim_player.speed_scale != 0.0:
		printerr("3D 멈춤인데 speed_scale %.2f" % win.baker.anim_player.speed_scale); quit(1); return
	win._scrub.value = 0.25
	win._scrub.value_changed.emit(0.25)
	await process_frame
	var sp_pos: float = win.baker.anim_player.current_animation_position
	if absf(sp_pos - sp_len * 0.25) > 0.02:
		printerr("3D 스크럽 반영 안 됨: 엔진 위치 %.3f (기대 %.3f)" % [sp_pos, sp_len * 0.25]); quit(1); return
	# ×1 로 돌리면 다시 흐른다
	win._speed.select(0)
	win._speed.item_selected.emit(0)
	if win.baker.anim_player.speed_scale != 1.0:
		printerr("3D ×1 인데 speed_scale %.2f" % win.baker.anim_player.speed_scale); quit(1); return
	print("25) 재생 속도·스크럽 OK — 2D ×1/4: 실시간 %.2f초에 %.3f초 · 멈춤 유지 · 스크럽 50%%→%.2fs · 3D 스크럽 25%%→엔진 %.2fs" % [sp_real, sp_adv, sp_len * 0.5, sp_pos])
	win._play.button_pressed = false
	await win._refresh_preview()
	while win._busy:
		await process_frame
	win._picked_anims.clear()
	win._fill_anim_list()

	# ---- 리깅 애니메이션 세트: 추가 → 두 번째 추가 → 위로 → 불러오기 → 덮어쓰기 → 프리셋 왕복 → 삭제 ----
	win._sets.clear()
	win._refresh_sets_list()
	win._add_set()                                   # 6번이 비어 있으면 안 담겨야 한다
	if win._sets.size() != 0:
		printerr("동작 없이 세트가 담김"); quit(1); return
	for i in win._rest_anim.item_count:
		if win._rest_anim.get_item_text(i) == "Idle":
			win._rest_anim.select(i)
	win._rest_time.value = 0.0
	win._picked_anims["Idle"] = true
	win._picked_anims["Jog_Fwd"] = true
	win._fill_anim_list()
	win._z_auto.button_pressed = true            # stand 세트는 자동 순서로
	win._set_name.text = "stand"
	win._add_set()
	# 두 번째 세트는 수동 순서(첫 줄을 한 칸 뒤로) — 세트마다 순서가 따로 저장돼야 한다
	win._z_list.deselect_all()
	win._z_list.select(0, false)
	win._move_z(1)
	var st_manual_first := win._z_list.get_item_text(0)
	for i in win._rest_anim.item_count:
		if win._rest_anim.get_item_text(i) == "Crawl_Enter":
			win._rest_anim.select(i)
	win._rest_time.value = 0.16
	win._picked_anims.clear()
	win._picked_anims["Crawl_Fwd"] = true
	win._fill_anim_list()
	win._set_name.text = ""                          # 비우면 레스트 애니 이름
	win._add_set()
	while win._busy:
		await process_frame
	if win._sets.size() != 2 or String(win._sets[1]["name"]) != "Crawl_Enter" or win._sets_list.item_count != 2:
		printerr("세트 추가 이상: %d개 %s" % [win._sets.size(), str(win._sets)]); quit(1); return
	win._sets_list.select(1)
	win._on_set_button("up")
	if String(win._sets[0]["name"]) != "Crawl_Enter" or win._selected_set() != 0:
		printerr("세트 ▲ 이상: %s 선택 %d" % [str(win._sets[0]["name"]), win._selected_set()]); quit(1); return
	# 세트별 그리기 순서: Crawl_Enter(0번) 수동 · stand(1번) 자동, 불러오면 목록·자동 체크가 따라와야 한다
	if bool(win._sets[0]["z_auto"]) or not bool(win._sets[1]["z_auto"]) \
			or (win._sets[0]["z_order"] as PackedStringArray).size() != 15 or String(win._sets[0]["z_order"][0]) != st_manual_first:
		printerr("세트에 그리기 순서가 안 담김: %s / %s" % [str(win._sets[0].get("z_auto")), str(win._sets[1].get("z_auto"))]); quit(1); return
	win._sets_list.select(1)
	win._on_set_button("load")                    # stand → 자동
	while win._busy:
		await process_frame
	if not win._z_auto.button_pressed:
		printerr("자동 순서 세트를 불러왔는데 자동이 안 켜짐"); quit(1); return
	win._sets_list.select(0)
	win._on_set_button("load")                    # Crawl_Enter → 수동, 첫 줄 = 저장된 순서
	while win._busy:
		await process_frame
	if win._z_auto.button_pressed or win._z_list.get_item_text(0) != st_manual_first:
		printerr("수동 순서 세트 복원 실패: 자동 %s, 첫 줄 %s (기대 %s)" % [win._z_auto.button_pressed, win._z_list.get_item_text(0), st_manual_first]); quit(1); return
	# stand(이제 2번) 불러오기 → 5번·6번 복원
	win._sets_list.select(1)
	win._on_set_button("load")
	while win._busy:
		await process_frame
	if win._rest_anim.get_item_text(win._rest_anim.selected) != "Idle" or win._picked_anim_names().size() != 2 or win._set_name.text != "stand":
		printerr("세트 불러오기 이상: 레스트 %s · 동작 %s · 이름 %s" % [win._rest_anim.get_item_text(win._rest_anim.selected), str(win._picked_anim_names()), win._set_name.text]); quit(1); return
	# 동작 하나 빼고 덮어쓰기
	win._picked_anims.erase("Jog_Fwd")
	win._fill_anim_list()
	win._on_set_button("save")
	if (win._sets[1]["animations"] as PackedStringArray).size() != 1 or String(win._sets[1]["name"]) != "stand":
		printerr("세트 덮어쓰기 이상: %s" % str(win._sets[1])); quit(1); return
	# 프리셋 왕복
	var st_pset := win._collect_preset()
	if st_pset.sets.size() != 2 or String(st_pset.sets[0]["name"]) != "Crawl_Enter":
		printerr("프리셋에 세트가 안 담김: %s" % str(st_pset.sets)); quit(1); return
	var st_path := "res://puppet_test/_test_sets_preset.tres"
	if ResourceSaver.save(st_pset, st_path) != OK:
		printerr("세트 프리셋 저장 실패"); quit(1); return
	win._sets.clear()
	win._refresh_sets_list()
	var st_loaded = ResourceLoader.load(st_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	win._apply_preset(st_loaded as DRPreset)
	while win._busy:
		await process_frame
	if win._sets.size() != 2 or String(win._sets[0]["name"]) != "Crawl_Enter" or absf(float(win._sets[0]["rest_time"]) - 0.16) > 0.001 \
			or Array(win._sets[1]["animations"]) != ["Idle"]:
		printerr("프리셋에서 세트 복원 이상: %s" % str(win._sets)); quit(1); return
	win._sets_list.select(0)
	win._on_set_button("del")
	if win._sets.size() != 1 or String(win._sets[0]["name"]) != "stand":
		printerr("세트 삭제 이상: %s" % str(win._sets)); quit(1); return
	var st_cfg: Dictionary = win._bake_cfg()
	if int(st_cfg["fps"]) != int(win._fps.value) or not st_cfg.has("z_override"):
		printerr("베이크 설정 묶음 이상: %s" % str(st_cfg)); quit(1); return
	print("26) 리깅 애니메이션 세트 OK — 추가 2 · ▲ · 세트별 그리기 순서(수동/자동) 저장·복원 · 불러오기 · 덮어쓰기 · 프리셋 왕복 · 삭제 → %d개 남음, 베이크 설정 묶음 %d키" % [win._sets.size(), st_cfg.size()])
	win._z_auto.button_pressed = true

	# ---- 동작 평면화: 2D 순서 프리뷰에서 늘이기 1 · 자식 위치 = 레스트 오프셋 · 각도는 측면 시점 ----
	win._sets.clear()
	win._refresh_sets_list()
	win._yaw.value = -55.0
	for i in win._rest_anim.item_count:
		if win._rest_anim.get_item_text(i) == "Idle":
			win._rest_anim.select(i)
	win._rest_time.value = 0.0
	win._mode_2d.button_pressed = true
	win._planar.button_pressed = true
	await win._refresh_preview()
	while win._busy:
		await process_frame
	if win.baker.pose_cam() == null or absf(win.baker.effective_pose_yaw() - (-90.0)) > 0.01:
		printerr("평면화 포즈 카메라 이상: %s / yaw %.0f (기대 -90)" % [win.baker.pose_cam(), win.baker.effective_pose_yaw()]); quit(1); return
	var pl_an: String = win.baker.resolve_anim("Jog_Fwd")
	var pl_len: float = win.baker.anim_player.get_animation(pl_an).length
	var pl_rig = win.baker.rig
	var pl_bad := ""
	var pl_rmin := INF
	var pl_rmax := -INF
	for k in 8:
		win.baker.set_pose(pl_an, pl_len * float(k) / 8.0)
		var loc: Dictionary = win.baker.project_local()
		for pn in loc.keys():
			var e: Dictionary = loc[pn]
			if absf(float(e["s"]) - 1.0) > 0.000001:
				pl_bad = "%s s=%.2f" % [pn, e["s"]]
			var part = pl_rig.parts[pn]
			if part.parent != "":
				var want_p: Vector2 = part.rest_head2d - pl_rig.parts[part.parent].rest_head2d
				if (Vector2(e["p"]) - want_p).length() > 0.001:
					pl_bad = "%s p=%s (기대 %s)" % [pn, e["p"], want_p]
		pl_rmin = minf(pl_rmin, float(loc["L_Forearm"]["r"]))
		pl_rmax = maxf(pl_rmax, float(loc["L_Forearm"]["r"]))
	if pl_bad != "":
		printerr("평면화 값 이상: %s" % pl_bad); quit(1); return
	var pl_swing := rad_to_deg(pl_rmax - pl_rmin)
	if pl_swing < 15.0:
		printerr("평면화에서 팔이 안 움직임: L_Forearm 회전 폭 %.1f°" % pl_swing); quit(1); return
	# 끄면 다시 3D 투영(늘이기가 1이 아닌 파트가 생긴다)
	win._planar.button_pressed = false
	await win._refresh_preview()
	while win._busy:
		await process_frame
	win.baker.set_pose(pl_an, pl_len * 0.25)
	var loc_off: Dictionary = win.baker.project_local()
	var pl_stretched := 0
	for pn in loc_off.keys():
		if absf(float(loc_off[pn]["s"]) - 1.0) > 0.02:
			pl_stretched += 1
	if win.baker.pose_cam() != null or pl_stretched == 0:
		printerr("평면화를 껐는데 3D 투영으로 안 돌아옴 (늘이기≠1 파트 %d개)" % pl_stretched); quit(1); return
	print("27) 동작 평면화 OK — 포즈 시점 −90°, Jog_Fwd 8프레임 늘이기 전부 1 · 자식 위치 = 레스트 오프셋 · L_Forearm 회전 폭 %.0f° · 끄면 늘이기≠1 파트 %d개" % [pl_swing, pl_stretched])
	win._mode_2d.button_pressed = false
	win._yaw.value = 90.0
	await win._refresh_preview()
	while win._busy:
		await process_frame
	win._sets.clear()
	win._refresh_sets_list()
	win._set_name.text = ""
	win._picked_anims.clear()
	win._fill_anim_list()
	for i in win._rest_anim.item_count:
		if win._rest_anim.get_item_text(i) == "Idle":
			win._rest_anim.select(i)
	win._rest_time.value = 0.0
	await win._refresh_preview()
	while win._busy:
		await process_frame

	# ---- 레스트 자동: 고른 동작에서 알아서 찾고, 고른 동작이 바뀌면 다시 찾는다 ----
	win._yaw.value = -55.0
	for i in win._rest_anim.item_count:
		if win._rest_anim.get_item_text(i) == "Idle":
			win._rest_anim.select(i)
	win._rest_time.value = 0.0
	win._picked_anims.clear()
	win._picked_anims["Idle"] = true
	win._picked_anims["Walk"] = true
	win._fill_anim_list()
	win._rest_auto.button_pressed = true
	await win._refresh_preview()
	while win._busy:
		await process_frame
	var ar_anim := win._rest_anim.get_item_text(win._rest_anim.selected)
	if ar_anim != "Walk" or win._rest_time.value <= 0.0 or not win._rest_info.text.contains("Walk"):
		printerr("레스트 자동 실패: %s %.2f / %s" % [ar_anim, win._rest_time.value, win._rest_info.text]); quit(1); return
	var ar_t: float = win._rest_time.value
	if not win._rest_anim.disabled or win._rest_time.editable:
		printerr("자동인데 레스트 칸이 안 잠김"); quit(1); return
	if absf(win.baker.opts.rest_time - win.baker.anim_player.get_animation("Walk").length * win._rest_time.value) > 0.001:
		printerr("자동 레스트가 베이커 옵션에 안 감"); quit(1); return
	# 고른 동작을 Jog_Fwd 하나로 바꾸면(목록 클릭 경로) 레스트도 Jog_Fwd 로
	win._anim_list.deselect_all()
	for i in win._anim_list.item_count:
		if win._anim_list.get_item_text(i) == "Jog_Fwd":
			win._anim_list.select(i, false)
	win._sync_picked_from_list()
	while win._busy:
		await process_frame
	await win._refresh_preview()
	while win._busy:
		await process_frame
	if win._rest_anim.get_item_text(win._rest_anim.selected) != "Jog_Fwd":
		printerr("고른 동작을 바꿨는데 레스트가 안 따라옴: %s" % win._rest_anim.get_item_text(win._rest_anim.selected)); quit(1); return
	# 아무것도 안 고르면 마지막 값 유지, 자동을 끄면 칸이 풀린다
	win._picked_anims.clear()
	win._fill_anim_list()
	await win._refresh_preview()
	while win._busy:
		await process_frame
	if win._rest_anim.get_item_text(win._rest_anim.selected) != "Jog_Fwd":
		printerr("동작이 비었는데 레스트가 바뀜"); quit(1); return
	var ar_set: Dictionary = win._set_from_current()
	if not bool(ar_set.get("rest_auto", false)):
		printerr("세트에 rest_auto 가 안 담김"); quit(1); return
	win._rest_auto.button_pressed = false
	while win._busy:
		await process_frame
	if win._rest_anim.disabled or not win._rest_time.editable:
		printerr("자동을 껐는데 레스트 칸이 안 풀림"); quit(1); return
	print("28) 레스트 자동 OK — Idle+Walk → Walk %.0f%% (칸 잠김, 베이커 반영) · Jog_Fwd 만 고르면 Jog_Fwd %.0f%% · 비우면 유지 · 끄면 풀림" % [ar_t * 100.0, win._rest_time.value * 100.0])
	for i in win._rest_anim.item_count:
		if win._rest_anim.get_item_text(i) == "Idle":
			win._rest_anim.select(i)
	win._rest_time.value = 0.0
	win._yaw.value = 90.0
	await win._refresh_preview()
	while win._busy:
		await process_frame

	# ---- 도트 아웃라인(상단 바): 2D 순서 프리뷰에 검은 선이 생기고, 셰이더 uniform 이 맞는지 ----
	win._mode_2d.button_pressed = true
	win._smooth.button_pressed = true
	win._outline_px.value = 0
	await win._refresh_preview()
	while win._busy:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var ol_img0: Image = win._puppet_vp.get_texture().get_image()
	var ol_n0 := _count_dark(ol_img0)
	if _visible_underlays(win) != 0:
		printerr("아웃라인 0 인데 밑깔개가 보임"); quit(1); return
	# 전체 실루엣(기본): 밑깔개가 전부 켜지고 outline_only 머티리얼, 파트 셰이더의 outline 은 0
	if not win._outline_whole.button_pressed:
		printerr("전체 실루엣이 기본이 아님"); quit(1); return
	win._outline_px.value = 1
	await win._refresh_preview()
	while win._busy:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var ol_img1: Image = win._puppet_vp.get_texture().get_image()
	var ol_n1 := _count_dark(ol_img1)
	var ol_in1 := _inner_changed(ol_img0, ol_img1)
	var ol_under: Sprite2D = win._puppet_bones["Torso"]["outline"]
	var ol_um := ol_under.material as ShaderMaterial
	var ol_pm := (win._puppet_bones["Torso"]["art"] as Sprite2D).material as ShaderMaterial
	var ol_vis1 := _visible_underlays(win)
	if ol_um == null or not bool(ol_um.get_shader_parameter("outline_only")) or int(ol_um.get_shader_parameter("outline_px")) != 1 \
			or ol_under.z_index != DRExporter.OUTLINE_Z or ol_vis1 != win._puppet_bones.size() \
			or ol_pm == null or int(ol_pm.get_shader_parameter("outline_px")) != 0 or ol_n1 < ol_n0 + 200:
		printerr("전체 실루엣 아웃라인 이상: 검은 픽셀 %d → %d, 밑깔개 보임 %d/%d, 밑깔개 머티리얼 %s, 파트 outline %s"
			% [ol_n0, ol_n1, ol_vis1, win._puppet_bones.size(), ol_um, ol_pm.get_shader_parameter("outline_px") if ol_pm else "-"]); quit(1); return
	# 핵심: 전체 실루엣 선은 캐릭터 안쪽(관절 겹침)을 건드리지 않는다
	if ol_in1 > 0:
		printerr("전체 실루엣인데 캐릭터 안쪽 픽셀 %d개가 바뀜(관절에 선이 생김)" % ol_in1); quit(1); return
	win._puppet_vp.get_texture().get_image().save_png("res://puppet_test/_outline_whole.png")
	# 파트별: 파트 셰이더에 outline 1, 밑깔개 꺼짐, 관절에도 선이 생겨 안쪽 픽셀이 바뀐다
	win._outline_whole.button_pressed = false
	await win._refresh_preview()
	while win._busy:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var ol_img2: Image = win._puppet_vp.get_texture().get_image()
	var ol_n2 := _count_dark(ol_img2)
	var ol_in2 := _inner_changed(ol_img0, ol_img2)
	var ol_mat := (win._puppet_bones["Torso"]["art"] as Sprite2D).material as ShaderMaterial
	if ol_mat == null or int(ol_mat.get_shader_parameter("outline_px")) != 1 or _visible_underlays(win) != 0 or ol_in2 < 50:
		printerr("파트별 아웃라인 이상: 안쪽 바뀐 픽셀 %d, 머티리얼 %s, 밑깔개 보임 %d" % [ol_in2, ol_mat, _visible_underlays(win)]); quit(1); return
	ol_img2.save_png("res://puppet_test/_outline_parts.png")
	# 다시 전체로 → 밑깔개가 다시 켜진다
	win._outline_whole.button_pressed = true
	while win._busy:
		await process_frame
	if _visible_underlays(win) != win._puppet_bones.size():
		printerr("전체 실루엣으로 되돌렸는데 밑깔개가 안 켜짐"); quit(1); return
	win._outline_whole.button_pressed = false
	while win._busy:
		await process_frame
	# 부드러운 이동을 꺼도 아웃라인만으로 셰이더가 붙어야 하고, 둘 다 끄면 떨어져야 한다
	win._smooth.button_pressed = false
	while win._busy:
		await process_frame
	var ol_mat2 := (win._puppet_bones["Torso"]["art"] as Sprite2D).material as ShaderMaterial
	if ol_mat2 == null or bool(ol_mat2.get_shader_parameter("smooth_edges")):
		printerr("부드러운 이동 끔 + 아웃라인 켬인데 셰이더/uniform 이상"); quit(1); return
	win._outline_px.value = 0
	while win._busy:
		await process_frame
	if (win._puppet_bones["Torso"]["art"] as Sprite2D).material != null or _visible_underlays(win) != 0:
		printerr("둘 다 껐는데 머티리얼/밑깔개가 남음"); quit(1); return
	if int(win._bake_cfg()["outline_px"]) != 0 or not win._bake_cfg().has("outline_color") or not win._bake_cfg().has("outline_whole"):
		printerr("베이크 설정에 아웃라인이 없음"); quit(1); return
	print("29) 도트 아웃라인 OK — 검은 픽셀 %d → 전체 실루엣 %d(안쪽 바뀐 픽셀 %d, 밑깔개 %d장) · 파트별 %d(안쪽 %d = 관절 선), 부드러운 이동 없이도 셰이더 유지, 둘 다 끄면 해제"
		% [ol_n0, ol_n1, ol_in1, ol_vis1, ol_n2, ol_in2])
	win._outline_whole.button_pressed = true
	win._smooth.button_pressed = true
	win._mode_2d.button_pressed = false
	await win._refresh_preview()
	while win._busy:
		await process_frame

	# ---- 레스트 자세 찾기 + 레스트 시점(슬라이더)이 베이커 옵션까지 가는지 ----
	win._yaw.value = -55.0
	win._pitch.value = 0.0
	for i in win._rest_anim.item_count:
		if win._rest_anim.get_item_text(i) == "Idle":
			win._rest_anim.select(i)
	win._rest_time.value = 0.0
	win._picked_anims.clear()
	win._picked_anims["Idle"] = true
	win._picked_anims["Walk"] = true
	win._fill_anim_list()
	await win._refresh_preview()
	while win._busy:
		await process_frame
	var rs_before: Array = win._rest_score()
	# "이 애니에서" — 5번 애니(Idle)는 그대로 두고 시점만 찾아야 한다
	await win._find_rest_pose("rest")
	while win._busy:
		await process_frame
	if win._rest_anim.get_item_text(win._rest_anim.selected) != "Idle":
		printerr("'이 애니에서 찾기'가 애니를 바꿈: %s" % win._rest_anim.get_item_text(win._rest_anim.selected)); quit(1); return
	# "6번 동작에서" — Idle·Walk 중 Walk 가 골라져야 한다
	await win._find_rest_pose("picked")
	while win._busy:
		await process_frame
	var rs_anim := win._rest_anim.get_item_text(win._rest_anim.selected)
	var rs_after: Array = win._rest_score()
	if rs_anim != "Walk" or float(rs_after[0]) <= float(rs_before[0]) + 0.2:
		printerr("레스트 자세 찾기 실패: %s %.0f%% 점수 %.2f (이전 Idle %.2f, 기대: Walk 로 바뀌고 점수 크게 상승)" % [
			rs_anim, win._rest_time.value * 100.0, rs_after[0], rs_before[0]]); quit(1); return
	# "이 애니에서" 를 Walk 에 다시 — 애니는 Walk 그대로, 점수는 6번 결과와 같아야(같은 애니라 같은 최적 시점)
	var rs_t := win._rest_time.value
	await win._find_rest_pose("rest")
	while win._busy:
		await process_frame
	if win._rest_anim.get_item_text(win._rest_anim.selected) != "Walk" or absf(win._rest_time.value - rs_t) > 0.011:
		printerr("'이 애니에서 찾기'(Walk) 결과가 다름: %s %.2f (기대 Walk %.2f)" % [
			win._rest_anim.get_item_text(win._rest_anim.selected), win._rest_time.value, rs_t]); quit(1); return
	var rs_len: float = win.baker.anim_player.get_animation("Walk").length
	if absf(win.baker.opts.rest_time - rs_len * win._rest_time.value) > 0.001 or win._rest_time.value <= 0.0:
		printerr("레스트 시점이 베이커 옵션에 안 감: 슬라이더 %.2f → opts.rest_time %.3f (기대 %.3f)" % [
			win._rest_time.value, win.baker.opts.rest_time, rs_len * win._rest_time.value]); quit(1); return
	print("24) 레스트 자세 찾기 OK — '이 애니에서'는 애니 유지 · '6번 동작에서' Idle(%s %.2f) → Walk %.0f%% (%s %.2f), opts.rest_time %.3f초 = 길이 × 슬라이더" % [
		rs_before[1], rs_before[0], win._rest_time.value * 100.0, rs_after[1], rs_after[0], win.baker.opts.rest_time])
	win._rest_time.value = 0.0
	for i in win._rest_anim.item_count:
		if win._rest_anim.get_item_text(i) == "Idle":
			win._rest_anim.select(i)
	win._picked_anims.clear()
	win._fill_anim_list()
	win._yaw.value = 90.0
	await win._refresh_preview()
	while win._busy:
		await process_frame

	# ---- "(바인드 포즈)" 는 진짜 바인드 포즈여야 한다 + `지금 프레임을 레스트로` ----
	# 09-18 사용자 "바인드 포즈로 해 놓으면 다 맞네? 버그임?" — 예전엔 마지막에 보던 프레임이 그대로 레스트로 찍혔다(02 C12)
	win._rest_auto.button_pressed = false
	win._mode_2d.button_pressed = false
	await win._refresh_preview()
	while win._busy:
		await process_frame
	win.baker.set_pose("Jog_Fwd", 0.2)          # 뭔가를 보고 있던 상황
	win._rest_anim.select(0)                      # (바인드 포즈)
	await win._refresh_preview()
	while win._busy:
		await process_frame
	if win._current_opts().rest_anim != "":
		printerr("(바인드 포즈)인데 rest_anim 이 '%s'" % win._current_opts().rest_anim); quit(1); return
	win.baker.set_pose("Jog_Fwd", 0.2)
	win.baker.set_rest_pose()
	var bp_sk: Skeleton3D = win.baker.skeleton
	var bp_off := 0
	for bi in bp_sk.get_bone_count():
		if not bp_sk.get_bone_pose(bi).is_equal_approx(bp_sk.get_bone_rest(bi)):
			bp_off += 1
	if bp_off > 0:
		printerr("(바인드 포즈)로 세웠는데 본 %d개가 레스트와 다름 — 보던 프레임이 남음" % bp_off); quit(1); return
	# 지금 프레임을 레스트로: 재생 애니 Walk 의 40% 지점
	win._picked_anims.clear()
	win._picked_anims["Walk"] = true
	win._fill_anim_list()
	await win._refresh_preview()
	while win._busy:
		await process_frame
	var rn_an: String = win._current_play_anim()
	var rn_len: float = win.baker.anim_player.get_animation(rn_an).length
	win._play_t = rn_len * 0.4
	win._rest_auto.button_pressed = true          # 자동이 켜져 있어도 눌리면 꺼져야 한다
	while win._busy:
		await process_frame
	win._on_rest_from_current()
	while win._busy:
		await process_frame
	await win._refresh_preview()
	while win._busy:
		await process_frame
	if rn_an != "Walk" or win._rest_auto.button_pressed or win._rest_anim.disabled \
			or win._rest_anim.get_item_text(win._rest_anim.selected) != "Walk" or absf(win._rest_time.value - 0.4) > 0.006 \
			or absf(win.baker.opts.rest_time - rn_len * win._rest_time.value) > 0.001:
		printerr("지금 프레임을 레스트로 이상: 재생 애니 %s, 자동 %s, 레스트 %s %.2f, opts %.3f" % [rn_an, win._rest_auto.button_pressed,
			win._rest_anim.get_item_text(win._rest_anim.selected), win._rest_time.value, win.baker.opts.rest_time]); quit(1); return
	print("31) 바인드 포즈 · 지금 프레임 OK — (바인드 포즈) = 본 %d개 전부 레스트(보던 Jog_Fwd 프레임 안 남음) · `지금 프레임을 레스트로` → 자동 꺼짐, Walk 40%%, opts %.3f초" % [bp_sk.get_bone_count(), win.baker.opts.rest_time])
	win._picked_anims.clear()
	win._fill_anim_list()
	for i in win._rest_anim.item_count:
		if win._rest_anim.get_item_text(i) == "Idle":
			win._rest_anim.select(i)
	win._rest_time.value = 0.0
	await win._refresh_preview()
	while win._busy:
		await process_frame

	# ---- 추가 동작 폴더: 모델 파일 밖의 동작을 같은 캐릭터에 얹는다(Mixamo 접목의 통로) ----
	# Mixamo 파일에 기대지 않으려고 Walk 사본으로 시험 폴더를 만든다: 노드 경로를 엉뚱하게 바꾼 것(경로 고쳐 쓰기 검사) +
	# 없는 뼈 트랙 하나(경고 검사) / 뼈 이름이 전부 틀린 것(빼고 경고)
	var xa_dir := "res://puppet_test/_extra_anims"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(xa_dir))
	var xa_walk: Animation = win.baker.anim_player.get_animation(win.baker.resolve_anim("Walk"))
	var xa_good := xa_walk.duplicate(true) as Animation
	var xa_bad := xa_walk.duplicate(true) as Animation
	for xa_ti in xa_good.get_track_count():
		var xa_sub := xa_good.track_get_path(xa_ti).get_concatenated_subnames()
		xa_good.track_set_path(xa_ti, NodePath("Some/Other/Rig:%s" % xa_sub))
		xa_bad.track_set_path(xa_ti, NodePath("Some/Other/Rig:nobone_%d" % xa_ti))
	var xa_extra_ti := xa_good.add_track(Animation.TYPE_ROTATION_3D)
	xa_good.track_set_path(xa_extra_ti, NodePath("Some/Other/Rig:bone_not_in_model"))
	xa_good.rotation_track_insert_key(xa_extra_ti, 0.0, Quaternion.IDENTITY)
	ResourceSaver.save(xa_good, xa_dir.path_join("Test Extra.res"))   # 공백은 _ 로 바뀌어야 한다
	ResourceSaver.save(xa_bad, xa_dir.path_join("Bad_Bones.res"))
	var xa_before: int = win._all_anims.size()
	# 다시 불러와도 작업 상태(수동 그리기 순서 · 고른 동작 · 레스트)가 남아야 한다 — 09-18 사용자 "그리기 순서가 초기화되네"
	win._rest_auto.button_pressed = false
	win._z_auto.button_pressed = false
	win._z_list.move_item(0, win._z_list.item_count - 1)   # 맨 뒤 줄을 맨 앞으로 — 기본 순서와 달라진다
	var xa_order: PackedStringArray = win._order_from_list()
	win._picked_anims.clear()
	win._picked_anims["Walk"] = true
	win._picked_anims["Jog_Fwd"] = true
	win._fill_anim_list()
	for i in win._rest_anim.item_count:
		if win._rest_anim.get_item_text(i) == "Walk":
			win._rest_anim.select(i)
	win._rest_time.value = 0.25
	# 위에서 값을 바꾸며 프리뷰 갱신이 걸렸다 — 바쁜 동안의 _on_load() 는 무시되므로 끝나길 기다린다
	await win._refresh_preview()
	while win._busy:
		await process_frame
	win._extra_edit.text = xa_dir
	win._on_load()
	while win._busy:
		await process_frame
	await win._refresh_preview()
	while win._busy:
		await process_frame
	if win._z_auto.button_pressed or win._order_from_list() != xa_order:
		printerr("다시 불러오니 그리기 순서가 초기화됨: 자동 %s, %s → %s" % [win._z_auto.button_pressed, str(xa_order.slice(0, 3)), str(win._order_from_list().slice(0, 3))]); quit(1); return
	var xa_picked: PackedStringArray = win._picked_anim_names()
	if xa_picked.size() != 2 or not xa_picked.has("Walk") or not xa_picked.has("Jog_Fwd") \
			or win._rest_anim.get_item_text(win._rest_anim.selected) != "Walk" or absf(win._rest_time.value - 0.25) > 0.001:
		printerr("다시 불러오니 고른 동작/레스트가 초기화됨: %s · 레스트 %s %.2f" % [str(xa_picked), win._rest_anim.get_item_text(win._rest_anim.selected), win._rest_time.value]); quit(1); return
	if not win._status.text.contains("유지: 그리기 순서"):
		printerr("상태줄에 유지 안내가 없음: %s" % win._status.text); quit(1); return
	if not win._all_anims.has("Test_Extra") or win._all_anims.has("Bad_Bones") or win._all_anims.size() != xa_before + 1 \
			or Array(win.baker.extra_anims) != ["Test_Extra"]:
		printerr("추가 동작이 목록에 안 들어옴: 애니 %d → %d, extra %s" % [xa_before, win._all_anims.size(), str(win.baker.extra_anims)]); quit(1); return
	if win.baker.extra_anim_warnings.size() != 2 or not win._status.text.contains("추가 동작 1개"):
		printerr("추가 동작 경고/상태줄 이상: %s / %s" % [str(win.baker.extra_anim_warnings), win._status.text]); quit(1); return
	# 경로를 고쳐 썼다면 Walk 와 똑같은 자세가 나온다(안 고쳤으면 트랙이 허공을 가리켜 레스트 자세 그대로)
	var xa_bone: int = win.baker.skeleton.find_bone(win.baker.skeleton.get_bone_name((win.baker.rig.parts["L_Calf"] as DRRigModel.Part).root_bone))
	win.baker.set_pose("Walk", 0.3)
	var xa_p0: Transform3D = win.baker.skeleton.get_bone_global_pose(xa_bone)
	win.baker.set_rest_pose()
	win.baker.set_pose("Test_Extra", 0.3)
	var xa_p1: Transform3D = win.baker.skeleton.get_bone_global_pose(xa_bone)
	if not xa_p0.is_equal_approx(xa_p1):
		printerr("추가 동작의 자세가 원본(Walk)과 다름 — 트랙 경로를 못 고쳐 씀"); quit(1); return
	# 가져온 모델의 라이브러리는 그대로여야 한다(메모리에서 사본에만 얹음)
	var xa_fresh := (load("res://models/UAL1.glb") as PackedScene).instantiate()
	var xa_fresh_ap := xa_fresh.get_node("AnimationPlayer") as AnimationPlayer
	var xa_leaked := xa_fresh_ap.has_animation("Test_Extra")
	xa_fresh.free()
	if xa_leaked:
		printerr("추가 동작이 가져온 모델의 라이브러리에 새어 들어감"); quit(1); return
	# 프리셋 왕복: 폴더가 저장되고, 빈 프리셋을 적용하면 칸이 비고 모델을 다시 불러 목록에서 빠진다
	var xa_preset: DRPreset = win._collect_preset()
	if xa_preset.extra_anim_dir != xa_dir or win._current_opts().extra_anim_dir != xa_dir:
		printerr("추가 동작 폴더가 프리셋/옵션에 안 담김"); quit(1); return
	xa_preset.extra_anim_dir = ""
	win._apply_preset(xa_preset)
	while win._busy:
		await process_frame
	await win._refresh_preview()
	while win._busy:
		await process_frame
	if win._extra_edit.text != "" or win._all_anims.has("Test_Extra") or win._all_anims.size() != xa_before:
		printerr("추가 동작 폴더를 비운 프리셋을 적용했는데 안 빠짐"); quit(1); return
	print("30) 추가 동작 폴더 OK — 애니 %d → %d(Test_Extra, 공백→_), 경고 2건(없는 뼈 트랙 · 뼈 이름 전부 틀린 파일은 뺌), 자세 = 원본 Walk, 가져온 라이브러리 안 건드림, 프리셋 왕복 · 다시 불러와도 수동 그리기 순서·고른 동작 2개·레스트 Walk 25%% 유지" % [xa_before, xa_before + 1])

	# ---- 창 자체를 캡처해서 배치 검사 ----
	win._show_composite()
	while win._busy:
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var shot := win.get_texture().get_image()
	shot.save_png("res://puppet_test/_ui_layout.png")
	print("16) 창 캡처 %dx%d (창 크기 %s) -> _ui_layout.png"
		% [shot.get_width(), shot.get_height(), win.size])
	if shot.get_width() < win.size.x:
		printerr("  ↑ 캡처가 잘렸습니다. 메인 창(--resolution)이 툴 창보다 작습니다.")
		quit(1); return

	# 주요 위젯이 창 밖으로 나가거나 찌그러지지 않았는지 수치로 확인.
	# 왼쪽 설정 열은 ScrollContainer 안이라 창 밖으로 나가는 게 정상 → 제외.
	var wrect := Rect2(Vector2.ZERO, Vector2(win.size))
	var checks := {
		"프리뷰": win._preview,
		"파트 트리": win._parts_tree,
		"그리기 순서 목록": win._z_list,
		"상태줄": win._iso_label,
		"기즈모": win._gizmo,
		"베이크 버튼": win._bake_btn,
	}
	var bad := 0
	for name in checks.keys():
		var c: Control = checks[name]
		var r := c.get_global_rect()
		var inside := wrect.encloses(r)
		var ok := inside and r.size.x >= 40.0 and r.size.y >= 16.0
		if not ok:
			bad += 1
		print("    %-16s pos(%4d,%4d) size(%4d x %4d) %s" % [
			name, int(r.position.x), int(r.position.y),
			int(r.size.x), int(r.size.y),
			"OK" if ok else ("← 창 밖" if not inside else "← 너무 작음")])
	if bad > 0:
		printerr("배치 문제 %d건" % bad)
		quit(1); return
	# 그리기 순서 목록이 15개를 스크롤 없이 담는지
	var per_item := 0.0
	if win._z_list.item_count > 0:
		per_item = win._z_list.get_item_rect(0).size.y
	var need := per_item * float(win._z_list.item_count)
	print("    목록 높이 %d px / 15개에 필요 %d px → %s" % [
		int(win._z_list.size.y), int(need),
		"스크롤 불필요" if win._z_list.size.y >= need else "스크롤 필요"])

	print("\n스모크 테스트 전부 통과")
	quit(0)
