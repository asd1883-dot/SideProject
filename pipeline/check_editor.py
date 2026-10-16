# -*- coding: utf-8 -*-
"""에디터 안 검사 — Dot Rigger 창을 **실제 Godot 에디터**에서 메뉴를 누른 것처럼 띄워 본다.

    python pipeline/check_editor.py            (애드온 · 테스트 씬을 샌드박스에 복사한 뒤 돌림)
    python pipeline/check_editor.py --no-sync  (샌드박스에 이미 있는 코드로)
    python pipeline/check_editor.py --headless (에디터를 창 없이 — 화면에 아무것도 안 뜬다. 창 자리 검사만 건너뜀, 10-16)
    python pipeline/check_editor.py --sandbox=<폴더>  (다른 샌드박스 — 저장소 통째 사본 등. 그 project.godot 의 플러그인 줄을 잠깐 바꿨다 되돌린다)

왜: 명령줄 검사(--script …_smoke_cli.gd)는 에디터 밖이라 Engine.is_editor_hint() 가 거짓 — 에디터 설정 읽기 · 창 띄우기 같은
    에디터 전용 길을 안 탄다. 10-06 에 그 길에서 ③ 탭 오류와 "창이 다른 모니터 구석에 떠서 못 끌고 못 닫음" 이 나왔다.
어떻게: 샌드박스(Documents/1941)에 탐침 플러그인(pipeline/editor_probe)을 잠깐 넣고 에디터를 띄운다 → 끝나면 빼고 설정을 되돌린다.
        에디터 창이 30초쯤 떴다 닫힌다. 실제 프로젝트는 건드리지 않는다.
결과: PROBE 줄들 + 마지막 줄 `EDITOR CHECK OK` / `EDITOR CHECK FAIL <이유>`.
"""
import os, shutil, subprocess, sys

GODOT = r"C:\Users\Dev\Desktop\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
SANDBOX = r"C:\Users\Dev\Documents\1941"
HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
PLUGIN_LINE = 'enabled=PackedStringArray("res://addons/dot_rigger/plugin.cfg")'
PLUGIN_LINE_PROBE = 'enabled=PackedStringArray("res://addons/dot_rigger/plugin.cfg", "res://addons/_dr_probe/plugin.cfg")'

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(errors="replace")


def sync():
    """애드온 코드(.gd · 셰이더)와 시험장 스크립트를 샌드박스로. game/ 은 ① 유닛 탭(10-16)이 유닛 프리팹 · 동작 표 · 3D 동작 묶음을 읽어서 씬 · 리소스까지,
    source3d/weapons 의 장비 씬 · asset.json 은 유닛 프리팹의 소켓 장비(② 장비 탭, 10-16)가 불러서"""
    n = 0
    for sub, exts in (("addons/dot_rigger", (".gd", ".gdshader", ".cfg")), ("test", (".gd", ".gdshader", ".cfg")),
                      ("game", (".gd", ".tscn", ".tres", ".res")), ("source3d/weapons", (".tscn", ".json"))):
        for root, _dirs, files in os.walk(os.path.join(PROJECT, sub)):
            for f in files:
                if not f.endswith(exts):
                    continue
                src = os.path.join(root, f)
                dst = os.path.join(SANDBOX, os.path.relpath(src, PROJECT))
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                if not os.path.exists(dst) or open(src, "rb").read() != open(dst, "rb").read():
                    shutil.copy2(src, dst)
                    n += 1
    print("샌드박스로 복사: %d개" % n)


def main():
    global SANDBOX
    for a in sys.argv[1:]:
        if a.startswith("--sandbox="):
            SANDBOX = os.path.abspath(a.split("=", 1)[1])
    if os.path.normcase(SANDBOX) == os.path.normcase(PROJECT):
        print("EDITOR CHECK FAIL 실제 프로젝트를 샌드박스로 쓸 수 없습니다(사용자 에디터가 열고 있음)")
        return 1
    headless = "--headless" in sys.argv
    if "--no-sync" not in sys.argv:
        sync()
    probe_dst = os.path.join(SANDBOX, "addons", "_dr_probe")
    pg = os.path.join(SANDBOX, "project.godot")
    original = open(pg, encoding="utf-8").read()
    if PLUGIN_LINE not in original:
        print("EDITOR CHECK FAIL 샌드박스 project.godot 의 플러그인 줄이 예상과 다릅니다")
        return 1
    out = ""
    try:
        shutil.copytree(os.path.join(HERE, "editor_probe"), probe_dst, dirs_exist_ok=True)
        open(pg, "w", encoding="utf-8", newline="\n").write(original.replace(PLUGIN_LINE, PLUGIN_LINE_PROBE))
        subprocess.run([GODOT, "--headless", "--path", SANDBOX, "--import"], capture_output=True, timeout=900)
        try:
            r = subprocess.run([GODOT] + (["--headless"] if headless else []) + ["--editor", "--path", SANDBOX], capture_output=True, text=True,
                               encoding="utf-8", errors="replace", timeout=420)
            out = r.stdout + r.stderr
        except subprocess.TimeoutExpired as e:
            for part in (e.stdout, e.stderr):      # stderr 도 — 멈춘 까닭(SCRIPT ERROR)이 거기 찍힌다(10-16: 버려서 못 봤다)
                out += (part or b"").decode("utf-8", "replace") if isinstance(part, bytes) else (part or "")
            out += "\nPROBE TIMEOUT"
    finally:
        open(pg, "w", encoding="utf-8", newline="\n").write(original)
        shutil.rmtree(probe_dst, ignore_errors=True)

    lines = out.splitlines()
    start = next((i for i, l in enumerate(lines) if l.startswith("PROBE start")), None)
    if start is None:
        print("\n".join(lines[-15:]))
        print("EDITOR CHECK FAIL 탐침이 시작하지 못했습니다(스크립트 오류?)")
        return 1
    problems = []
    i = start
    while i < len(lines):
        l = lines[i]
        if l.startswith("PROBE"):
            print(l)
            if l.startswith("PROBE FAIL") or "TIMEOUT" in l:
                problems.append(l[6:].strip())
        elif l.startswith(("SCRIPT ERROR", "ERROR")):
            block = [l] + [x for x in lines[i + 1:i + 6] if x.startswith("   ")]
            print("\n".join(block))
            problems.append(l[:120])
        i += 1
    if not any(l.startswith("PROBE done") for l in lines):
        problems.append("끝까지 못 감(멈춤 또는 꺼짐)")
    if problems:
        print("EDITOR CHECK FAIL " + " · ".join(problems[:5]))
        return 1
    print("EDITOR CHECK OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
