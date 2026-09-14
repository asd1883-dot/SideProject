extends SceneTree

## 에디터 창 UI 코드 경로 스모크 테스트.
## 창을 실제로 띄우진 않고, 위젯 구성 -> 모델 로드 -> 프리뷰 갱신까지
## 크래시 없이 도는지 확인한다. (EditorInterface 를 쓰는 베이크 버튼은 제외)

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var win := DRMainWindow.new()
	root.add_child(win)
	# 숨긴 채로 두면 SubViewport 가 렌더되지 않아 프리뷰가 검게 나온다.
	# 실사용(창을 열어 놓은 상태)과 같은 조건으로 테스트한다.
	win.popup_centered(Vector2i(1000, 700))
	await process_frame
	print("1) UI 구성 OK")

	win._model_edit.text = "res://models/UAL1.glb"
	win._on_load()
	if win.baker == null:
		printerr("모델 로드 실패"); quit(1); return
	print("2) 모델 로드 OK — %s" % win._status.text)
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

	# 그리기 순서 목록 (자동)
	if win._z_list.item_count != 15:
		printerr("z 목록 항목 수 이상: %d" % win._z_list.item_count); quit(1); return
	var auto_order := []
	for i in win._z_list.item_count:
		auto_order.append(win._z_list.get_item_text(i))
	print("8) 그리기 순서 자동 %d개 — 맨뒤=%s 맨앞=%s" % [
		auto_order.size(), auto_order[0], auto_order[-1]])

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
	if win._iso_parts.size() != 3:
		printerr("프리뷰 대상이 3개가 아님: %s" % str(win._iso_parts)); quit(1); return
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
	# 3D 렌더와는 달라야 정상(3D 는 지정 순서를 무시하므로)
	var d3: Image = await win.baker.render_all_parts_composite()
	var diff3 := 0
	for y in b.get_height():
		for x in b.get_width():
			if b.get_pixel(x, y) != d3.get_pixel(x, y):
				diff3 += 1
	print("18) 2D 순서 반영 OK — Torso 맨앞 전후 %d px 변화, 3D 렌더와 %d px 차이"
		% [diff, diff3])
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
	win._res.value = 256
	win._yaw.value = 90.0
	win._pitch.value = 0.0
	win._show_composite()
	while win._busy:
		await process_frame

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
