# -*- coding: utf-8 -*-
"""자산 공정 — asset.json 하나로 정규화(Blender) → 굽기(Godot 장비 굽기 CLI) → 검수를 한 번에.

    python pipeline/asset_pipeline.py source3d/weapons/kar98k/asset.json
    python pipeline/asset_pipeline.py <asset.json> --only generate       (생성만 — source.generator.tool 이 "tripo" 일 때)
    python pipeline/asset_pipeline.py <asset.json> --only normalize      (정규화만)
    python pipeline/asset_pipeline.py <asset.json> --only bake           (굽기만)
    python pipeline/asset_pipeline.py <asset.json> --project <다른 프로젝트>   (샌드박스 등)

- 각 단계는 asset.json 의 자기 칸을 읽고 결과를 적는다(normalize.result · equip · history).
- 굽기는 Godot 를 명령줄로 띄운다. 같은 프로젝트를 에디터가 열고 있으면 멈추고 알린다(--force 로 무시).
  (에디터가 열린 프로젝트에 명령줄 Godot 를 같이 돌리면 가져오기 캐시가 꼬일 수 있다 — 인수인계 규칙)
- 마지막 줄 = "PIPELINE OK" 또는 "PIPELINE FAIL <이유>". 토큰을 아끼려고 출력은 요약만.
"""
import json, os, subprocess, sys, datetime

BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
GODOT = r"C:\Users\Dev\Desktop\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PROJECT = os.path.dirname(HERE)

# 검수 기준(무기)
CHECK = {"length_tol": 0.02, "max_triangles": 60000}


if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(errors="replace")   # 한글 Windows 콘솔(cp949)에서 — 같은 글자로 멈추지 않게


def log(msg):
    print(msg, flush=True)


def load(p):
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def save(p, d):
    with open(p, "w", encoding="utf-8", newline="\n") as f:
        json.dump(d, f, ensure_ascii=False, indent="\t")


def history(asset_path, step, ok, note=""):
    d = load(asset_path)
    d.setdefault("history", []).append({"step": step, "at": datetime.datetime.now().isoformat(timespec="seconds"), "ok": ok, "note": note})
    save(asset_path, d)


def editor_open_on(project):
    """이 프로젝트를 연 Godot 에디터가 떠 있나(명령줄에 --path <프로젝트> 가 있는 것)"""
    try:
        out = subprocess.run(["powershell", "-NoProfile", "-Command",
            "Get-CimInstance Win32_Process -Filter \"Name like 'Godot%'\" | ForEach-Object { $_.CommandLine }"],
            capture_output=True, text=True, timeout=30).stdout
    except Exception:
        return False
    key = project.replace("\\", "/").lower().rstrip("/")
    for line in out.splitlines():
        l = line.replace("\\", "/").lower()
        if "--editor" in l and key in l:
            return True
    return False


def res_path(project, p):
    return os.path.join(project, p[6:].replace("/", os.sep)) if p.startswith("res://") else p


def to_res(project, abs_path):
    rel = os.path.relpath(abs_path, project).replace("\\", "/")
    return "res://" + rel


def step_normalize(asset_path, project):
    log("[1/3] 정규화 (Blender)")
    r = subprocess.run([BLENDER, "-b", "--factory-startup", "-P", os.path.join(HERE, "blender", "normalize_weapon.py"), "--",
                        "--asset", asset_path, "--project", project], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=900)
    line = next((l for l in r.stdout.splitlines() if l.startswith("NORMALIZE_RESULT ")), "")
    if not line:
        tail = "\n".join((r.stdout + r.stderr).splitlines()[-8:])
        history(asset_path, "normalize", False, tail[-400:])
        return False, "정규화 결과가 없습니다:\n" + tail
    res = json.loads(line[len("NORMALIZE_RESULT "):])
    log("      총구 %s · 길이 %.3f m(배율 %.3f) · 파트 %d · 삼각형 %d · 잡는 자리 %s"
        % (res["forward_found"], res["length_m"], res["scale"], len(res["parts"]), res["triangles"], "찾음" if res["grip_found"] else "없음(경계 상자 가운데)"))
    history(asset_path, "normalize", bool(res["ok"]), "")
    return bool(res["ok"]), res


def check_normalize(asset):
    nz = asset.get("normalize", {})
    res = nz.get("result", {})
    probs = []
    want = float(nz.get("length_m", 0) or 0)
    if want > 0 and abs(res.get("length_m", 0) - want) > CHECK["length_tol"]:
        probs.append("길이 %.3f ≠ %.3f" % (res.get("length_m", 0), want))
    if res.get("triangles", 0) > CHECK["max_triangles"]:
        probs.append("삼각형 %d > %d" % (res["triangles"], CHECK["max_triangles"]))
    if nz.get("grip_node") and not res.get("grip_found"):
        probs.append("잡는 자리 노드 '%s' 없음" % nz["grip_node"])
    return probs


def step_bake(asset_path, project, force):
    log("[2/3] 굽기 (Godot 장비 굽기)")
    if editor_open_on(project) and not force:
        return False, "이 프로젝트를 Godot 에디터가 열고 있습니다 — 에디터를 닫고 다시 돌리거나, 에디터의 장비 굽기 창에서 `구운 장비 열기…` → `굽기`"
    asset_res = to_res(project, asset_path)
    r = subprocess.run([GODOT, "--path", project, "--resolution", "900x700", "--script", "res://addons/dot_rigger/tools/equip_bake_cli.gd", "--",
                        "--asset=" + asset_res], capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=900)
    out = r.stdout + r.stderr
    lines = [l for l in out.splitlines() if l.startswith("[장비]") or "SCRIPT ERROR" in l]
    for l in lines:
        if l.startswith("[장비] 결과"):
            continue
        log("      " + l[:200])
    ok = any(l.startswith("[장비] 자산 기록 갱신: true") for l in lines)
    if not ok:
        return False, "\n".join(lines[-6:]) or out[-600:]
    return True, ""


def check_bake(asset, project):
    eq = asset.get("equip", {})
    out_dir = res_path(project, eq.get("out_dir", "res://equip"))
    ej = os.path.join(out_dir, eq.get("id", asset.get("id", "")), "equip.json")
    probs = []
    if not os.path.exists(ej):
        return ["equip.json 없음: " + ej]
    d = load(ej)
    sets = d.get("sets", {})
    if not sets:
        probs.append("구운 자세 0개")
    for name, s in sets.items():
        if not os.path.exists(os.path.join(os.path.dirname(ej), s.get("image", ""))):
            probs.append("%s 그림 없음" % name)
    return probs


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return 2
    asset_path = os.path.abspath(a[0])
    only = a[a.index("--only") + 1] if "--only" in a else ""
    project = os.path.abspath(a[a.index("--project") + 1]) if "--project" in a else DEFAULT_PROJECT
    force = "--force" in a
    asset = load(asset_path)
    log("자산 %s (%s) · 프로젝트 %s" % (asset.get("id"), asset.get("kind"), project))
    tool = str(asset.get("source", {}).get("generator", {}).get("tool", "manual"))
    if only in ("", "generate") and tool == "tripo":
        log("[0/3] 생성 (Tripo API)")
        sys.path.insert(0, HERE)
        import generate_tripo
        ok, msg = generate_tripo.generate(asset_path, project, log=log, regen="--regen" in a)
        history(asset_path, "generate", ok, str(msg)[-300:])
        if not ok:
            log("PIPELINE FAIL 생성 — " + str(msg))
            return 1
        if only == "generate":
            log("PIPELINE OK")
            return 0
    if only in ("", "normalize"):
        ok, res = step_normalize(asset_path, project)
        if not ok:
            log("PIPELINE FAIL 정규화 — " + str(res))
            return 1
        probs = check_normalize(load(asset_path))
        if probs:
            log("PIPELINE FAIL 정규화 검수 — " + " · ".join(probs))
            return 1
    if only in ("", "bake"):
        ok, why = step_bake(asset_path, project, force)
        if not ok:
            log("PIPELINE FAIL 굽기 — " + why)
            return 1
        log("[3/3] 검수")
        probs = check_bake(load(asset_path), project)
        if probs:
            log("PIPELINE FAIL 굽기 검수 — " + " · ".join(probs))
            return 1
        log("      자세 %d개 · equip.json 확인" % len(load(os.path.join(res_path(project, load(asset_path)["equip"].get("out_dir", "res://equip")), load(asset_path)["equip"].get("id", asset.get("id")), "equip.json")).get("sets", {})))
    log("PIPELINE OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
