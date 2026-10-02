# -*- coding: utf-8 -*-
"""캐릭터 검수 — 붙인 몸(bind_to_skeleton.py 결과)을 실제 Godot 굽기로 돌려 기준 몸과 나란히 비교한 그림을 만든다.

    python pipeline/check_character.py source3d/characters/human_base/human_base.glb
    python pipeline/check_character.py <glb> --anims Idle_Loop,Sprint_Loop,Rifle_Aiming_Idle --yaw -55
    python pipeline/check_character.py <glb> --anims Sprint_Loop --rest_time 0.42      (레스트 = 0.42초 프레임)

⚠ 레스트 시점이 다르면 결과가 뒤집힐 수 있다(10-02: 첫 프레임 레스트에선 좋아 보인 뚜껑이 사용자의 Sprint 63% 레스트에선 얼룩).
  사용자 창의 "레스트 자동" 값(예: Sprint 63% = 0.67초 x 0.63)을 --rest_time 으로 맞춰 확인할 것.

왜: Blender 3D 렌더로는 통과해도 Godot 컷아웃 굽기에서 문제가 나왔다(10-01 엄지 · 10-02 라이플 T-포즈 · 다리 살).
    사용자 화면에 가기 전에 같은 조건(동작마다 그 동작 프레임을 레스트로 · 동작 평면화)으로 굽고 눈으로 본다.

- 실제 프로젝트가 아니라 샌드박스(Documents/1941)에 복사해서 굽는다 — 에디터가 열려 있어도 안전(인수인계 규칙).
- 결과: pipeline/check/<이름>_sheet.png (동작마다 한 줄: 위 = 기준 몸, 아래 = 검사할 몸)
  + 추가 동작(Mixamo) 뼈 매칭 경고를 출력. 마지막 줄 CHECK OK / CHECK FAIL <이유>.
"""
import os, sys, shutil, subprocess, time

GODOT = r"C:\Users\Dev\Desktop\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
SANDBOX = r"C:\Users\Dev\Documents\1941"
HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
BASE_RES = "res://source3d/UAL1_humanoid.glb"
DEFAULT_ANIMS = ["Idle_Loop", "Sprint_Loop", "Crouch_Idle_Loop", "Rifle_Aiming_Idle", "Firing_Rifle"]
EXTRA = "res://source3d/mixamo"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(errors="replace")


def arg(name, default):
    a = sys.argv
    return a[a.index("--" + name) + 1] if "--" + name in a else default


def godot(args, timeout=600):
    r = subprocess.run([GODOT, "--path", SANDBOX] + args, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=timeout)
    return r.stdout + r.stderr


def main():
    if len(sys.argv) < 2 or sys.argv[1].startswith("--"):
        print(__doc__)
        return 2
    src = os.path.abspath(sys.argv[1])
    name = os.path.splitext(os.path.basename(src))[0]
    anims = arg("anims", ",".join(DEFAULT_ANIMS)).split(",")
    yaw = arg("yaw", "-55")
    rest_time = arg("rest_time", "0")
    out_dir = os.path.join(HERE, "check")
    os.makedirs(out_dir, exist_ok=True)

    # 1) 샌드박스로 복사(glb · .import(뼈 이름표) · 텍스처)
    rel = os.path.relpath(os.path.dirname(src), PROJECT)
    dst_dir = os.path.join(SANDBOX, rel)
    os.makedirs(dst_dir, exist_ok=True)
    for f in os.listdir(os.path.dirname(src)):
        if f.startswith(name) and not f.endswith(".import") or f == name + ".glb.import":
            shutil.copy2(os.path.join(os.path.dirname(src), f), os.path.join(dst_dir, f))
    if not os.path.exists(src + ".import") or "retarget/bone_map" not in open(src + ".import", encoding="utf-8").read():
        print("경고: %s.import 에 뼈 이름표(BoneMap)가 없습니다 — 추가 동작(라이플 등)이 T-포즈로 멈춥니다" % name)
    model_res = "res://" + rel.replace("\\", "/") + "/" + name + ".glb"
    print("검사: %s (샌드박스 %s)" % (model_res, SANDBOX))
    godot(["--headless", "--import"], timeout=900)

    # 2) 동작마다 그 동작 첫 프레임을 레스트로 굽고 엔진으로 재생해 캡처 — 기준 몸 · 검사할 몸
    rows = []
    problems = []
    # 매번 새 폴더 — 같은 폴더에 다시 구우면 Godot 가 조각 그림을 예전 가져오기 캐시로 읽어
    # 엉뚱한 몸 · 흩어진 팔다리가 찍힌다(10-02). 샌드박스 res://_check/ 아래는 지워도 된다.
    run_id = time.strftime("%m%d_%H%M%S")
    for an in anims:
        for tag, model in (("base", BASE_RES), ("test", model_res)):
            out = "res://_check/%s/%s_%s" % (run_id, tag, an)
            log = godot(["--resolution", "900x700", "--script", "res://addons/dot_rigger/tools/bake_cli.gd", "--",
                         "--model=" + model, "--extra_anims=" + EXTRA, "--anims=" + an, "--rest=" + an, "--rest_time=" + rest_time,
                         "--planar", "--out=" + out, "--fresh", "--yaw=" + yaw])
            if '"ok": true' not in log:
                problems.append("%s/%s 굽기 실패" % (tag, an))
                continue
            if tag == "test":
                for line in log.splitlines():
                    if "추가 동작" in line and ("안 맞아" in line or "없는 뼈" in line) and an.split("_Loop")[0] in line:
                        problems.append("%s: %s" % (an, line.strip()[:160]))
            baked = an[:-5] if an.endswith("_Loop") else an      # 굽기 도구가 _Loop 를 뗀다
            log2 = godot(["--resolution", "900x700", "--script", "res://addons/dot_rigger/tools/preview_cli.gd", "--",
                          "--scene=%s/puppet.tscn" % out, "--anim=" + baked, "--frames=4", "--scale=2"])
            png = os.path.join(SANDBOX, out[6:], "_engine_%s_strip.png" % baked)
            if not os.path.exists(png):
                problems.append("%s/%s 캡처 실패" % (tag, an))
                continue
            rows.append((an, tag, png))
            print("  %-18s %-4s 완료" % (an, tag))

    # 3) 한 장으로
    try:
        from PIL import Image, ImageDraw
        ims = [(an, tag, Image.open(p).convert("RGB")) for an, tag, p in rows]
        if ims:
            w = max(i.width for _, _, i in ims) + 150
            h = sum(i.height for _, _, i in ims)
            sheet = Image.new("RGB", (w, h), (30, 30, 36))
            d = ImageDraw.Draw(sheet)
            y = 0
            for an, tag, im in ims:
                sheet.paste(im, (150, y))
                d.text((6, y + 6), an, fill=(230, 230, 230))
                # 글꼴 없이 그리므로 영문으로(한글은 네모로 깨짐)
                d.text((6, y + 22), "BASE" if tag == "base" else "TEST", fill=(255, 200, 80) if tag == "test" else (150, 150, 150))
                y += im.height
            path = os.path.join(out_dir, name + "_sheet.png")
            sheet.save(path)
            print("비교 그림: " + path)
    except ImportError:
        print("Pillow 가 없어 비교 그림을 못 만듦 — 줄별 그림은 샌드박스 _check_* 폴더")

    if problems:
        print("CHECK FAIL " + " · ".join(problems))
        return 1
    print("CHECK OK (그림은 눈으로 확인)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
