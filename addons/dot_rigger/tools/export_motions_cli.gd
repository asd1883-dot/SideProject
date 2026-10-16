extends SceneTree

## 3D 동작 내보내기 명령줄 도구(10-15) — DRMotionExporter 로 게임 동작 표의 동작을 AnimationLibrary(.res) 하나로 저장한다.
## 2D 굽기와 같은 DRBaker.setup(프리셋 값)을 거친 동작이라 손 · 팔 처리 결과가 2D 퍼펫과 같다. 게임 쪽 계약은 core/motion_exporter.gd 머리말.
##
## 사용:
##   Godot.exe --headless --path <프로젝트> --script res://addons/dot_rigger/tools/export_motions_cli.gd -- \
##       --preset=res://UAL1_preset.tres --table=res://game/units/rifleman_motions.tres --out=res://game/motions/rifleman_anims.res
##   (세 값 모두 위가 기본값 — 인자 없이 돌려도 된다)
##
## --all          표와 상관없이 라이브러리의 동작 전부(모델 · 추가 동작 폴더 · 합성). 표의 A+B 합성 · 이동 동작 제자리는 그대로 반영
## --compress / --nocompress   Animation.compress()(손실) 켬 / 끔. 기본 끔 — 1/3 크기지만 몇 동작에서 손 · 발이 수백 mm 튐(motion_exporter.gd 의 compress)
##                             파일은 늘 무손실 압축(ResourceSaver.FLAG_COMPRESS)으로 저장한다
## --loop=source|keys  반복 여부. source(기본) = 2D 퍼펫과 같은 규칙(처리된 동작의 loop_mode — UAL 이름의 _Loop · Mixamo .import 의
##                     loop_mode · 합성 정의의 loop), keys = 표 키로(사망 · 피격 · 장전 · 투척 · 근접 = 한 번, 나머지 = 반복)
## --noreset      RESET(레스트 자세) 동작을 넣지 않음
## --check        저장한 파일을 다시 읽어 새 모델 인스턴스에서 재생 → DRBaker 메모리 동작과 손목 · 발목 · 머리 위치 차이(mm),
##                제자리 동작의 힙 수평 이동(처음 → 끝)

var _args := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--"):
			s = s.substr(2)
		var eq := s.find("=")
		if eq >= 0:
			_args[s.substr(0, eq)] = s.substr(eq + 1)
		else:
			_args[s] = "1"
	_run.call_deferred()


func _arg(key: String, def: String = "") -> String:
	return String(_args.get(key, def))


func _run() -> void:
	var ex := DRMotionExporter.new()
	ex.preset_path = _arg("preset", DRMotionExporter.DEFAULT_PRESET)
	ex.table_path = _arg("table", DRMotionExporter.DEFAULT_TABLE)
	ex.out_path = _arg("out", DRMotionExporter.DEFAULT_OUT)
	ex.export_all = _args.has("all")
	if _args.has("compress"):
		ex.compress = true
	if _args.has("nocompress"):
		ex.compress = false
	ex.loop_rule = DRMotionExporter.LOOP_KEYS if _arg("loop", "source") == "keys" else DRMotionExporter.LOOP_SOURCE
	ex.add_reset = not _args.has("noreset")
	print("[동작 내보내기] 프리셋 %s · 표 %s%s → %s" % [ex.preset_path, ex.table_path, " (--all 전부)" if ex.export_all else "", ex.out_path])
	var t0 := Time.get_ticks_msec()
	var res := ex.run(root)
	if not bool(res.get("ok", false)):
		for w in ex.warnings:
			printerr("  ⚠ ", w)
		printerr("[동작 내보내기] 실패")
		ex.cleanup()
		quit(1)
		return
	print("모델 %s · 트랙 경로 %s:<뼈> · 반복 규칙 %s · Animation 압축 %s · 파일 압축 %s · RESET %s" % [ex.model_path, ex.skeleton_path,
		"keys(표 키)" if ex.loop_rule == DRMotionExporter.LOOP_KEYS else "source(2D 와 같음)",
		"켬" if ex.compress else "끔", "켬" if ex.save_compressed else "끔", "넣음" if ex.add_reset else "안 넣음"])
	print("  %-32s %6s  %-4s %-6s %7s %6s  %s" % ["동작", "길이s", "반복", "제자리", "이동m", "트랙", "상태 키"])
	for e in ex.motions:
		var d: Dictionary = e
		print("  %-32s %6.3f  %-4s %-6s %7.3f %3d+%-2d  %s" % [d["name"], float(d["length"]), _loop_name(int(d["loop"])),
			"제자리" if bool(d["in_place"]) else "-", float(d["travel"]), int(d["tracks"]) - int(d["filled"]), int(d["filled"]),
			", ".join(d["keys"]) + (" [합성]" if bool(d["composite"]) else "")])
	print("  (트랙 a+b = 원래 a + 레스트로 채운 b · 이동m = 제자리로 만들기 전 뿌리 수평 이동)")
	var dis := ex.loop_disagreements()
	if dis.size() > 0:
		print("[반복 규칙 차이] 2D(처리된 동작) 값과 표 키 규칙이 다른 동작 — 지금 쓴 값: %s" % ("표 키" if ex.loop_rule == DRMotionExporter.LOOP_KEYS else "2D"))
		for e in dis:
			var d: Dictionary = e
			print("  %-32s 2D=%s · 표 키=%s  (%s)" % [d["name"], _loop_name(int(d["loop_src"])), _loop_name(int(d["loop_keys"])), ", ".join(d["keys"])])
	if ex.missing.size() > 0:
		print("[없는 동작] %d개" % ex.missing.size())
		for m in ex.missing:
			print("  ✗ ", m)
	if ex.warnings.size() > 0:
		print("[경고] %d개" % ex.warnings.size())
		for w in ex.warnings:
			print("  ⚠ ", w)
	print("[동작 내보내기] %d개 (+RESET %s) → %s  %.1f KB  (%.1f 초)" % [ex.motions.size(), "있음" if ex.add_reset else "없음", ex.out_path,
		float(ex.file_size) / 1024.0, float(Time.get_ticks_msec() - t0) / 1000.0])

	if _args.has("check"):
		var v := ex.verify(root)
		if not bool(v.get("ok", false)):
			printerr("[검사] 실패: ", v.get("error", ""))
		else:
			print("[검사] 저장 파일을 새 모델 인스턴스에서 재생(뼈를 되돌리지 않고 차례로) vs DRBaker 메모리 동작 — 손목 · 발목 · 머리 최대 위치 차이")
			var mm: Dictionary = v["motions"]
			for n in mm.keys():
				var r: Dictionary = mm[n]
				print("  %-32s %8.3f mm  (%s, t=%.3f, 표본 %d)" % [n, float(r["mm"]), r["bone"], float(r["t"]), int(r["samples"])])
			print("  최대 %.3f mm" % float(v["worst_mm"]))
			var hips: Dictionary = v["hips"]
			if not hips.is_empty():
				print("[검사] 제자리 동작의 힙 수평 자리 — 처음 → 끝 / 한 주기 안 가장 멀리")
				for n in hips.keys():
					var h: Dictionary = hips[n]
					print("  %-32s 처음→끝 %7.2f mm · 흔들림 최대 %6.1f mm  (원래 이동 %.3f m)" % [n, float(h["start_end_mm"]), float(h["sway_mm"]), float(h["orig_travel_m"])])
	ex.cleanup()
	quit(0)


static func _loop_name(m: int) -> String:
	match m:
		Animation.LOOP_NONE:
			return "한 번"
		Animation.LOOP_LINEAR:
			return "반복"
		Animation.LOOP_PINGPONG:
			return "왕복"
	return "-"
