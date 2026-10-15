# -*- coding: utf-8 -*-
"""맨몸 human_base.glb 를 원본에서 한 번에 다시 만든다 — 붙이기(bind_to_skeleton.py) → 팔 · 손 몸 맞춤 리깅(rerig_arms.py) (10-15).

    python pipeline/make_human_base.py                       (결과 = source3d/characters/human_base/human_base.glb, .import 는 uid 그대로)
    python pipeline/make_human_base.py --out <다른 glb>       (시험용 — 샌드박스 등에)

1) bind_to_skeleton.py 기본값                      → 임시 bind.glb  (손 크기 · 엄지 · 손가락 맞춤 · 비틀림 뼈까지)
2) bind_to_skeleton.py 손 단계 끔(정점 순서 같음)  → 임시 raw.glb   (rerig 가 손목 띠의 손 단계 변위를 펴는 기준)
3) rerig_arms.py --src bind.glb --raw raw.glb --out <결과>  — 팔꿈치 · 손목 · 손가락 관절을 살 중심으로, 팔 사슬 웨이트를 몸에서 새로
원본 = pipeline/comfy/human_8581eb8d.glb(저장소 밖, 이 PC), 기준 뼈대 = source3d/UAL1_humanoid.glb. 마지막 줄 RERIG_RESULT {json}.
⚠ 에디터가 이 프로젝트를 열고 있어도 파일만 바꾸므로 괜찮다 — 에디터를 껐다 켜고 ① `모델 불러오기`.
"""
import os, sys, subprocess, tempfile, shutil

BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.2\blender.exe"
HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(errors="replace")


def arg(name, default):
    a = sys.argv
    return a[a.index("--" + name) + 1] if "--" + name in a else default


def blender(script, args):
    r = subprocess.run([BLENDER, "-b", "--factory-startup", "-P", script, "--"] + args,
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    return r.stdout + r.stderr


def main():
    out = os.path.abspath(arg("out", os.path.join(PROJECT, "source3d", "characters", "human_base", "human_base.glb")))
    base = os.path.join(PROJECT, "source3d", "UAL1_humanoid.glb")
    src = os.path.join(PROJECT, "pipeline", "comfy", "human_8581eb8d.glb")
    if not os.path.exists(src):
        print("MAKE FAIL 원본이 없습니다: " + src)
        return 1
    bind = os.path.join(HERE, "blender", "bind_to_skeleton.py")
    tmp = tempfile.mkdtemp(prefix="human_base_")
    try:
        b1 = os.path.join(tmp, "bind.glb")
        log = blender(bind, ["--base", base, "--src", src, "--out", b1])
        if not os.path.exists(b1):
            print("MAKE FAIL bind\n" + log[-3000:])
            return 1
        raw = os.path.join(tmp, "raw.glb")
        log = blender(bind, ["--base", base, "--src", src, "--out", raw, "--hand_fit", "0", "--thumb_fit", "0", "--finger_fit", "0",
                             "--forearm_twist", "0", "--hand_scale", "1", "--thumb_len", "1"])
        if not os.path.exists(raw):
            print("MAKE FAIL raw bind\n" + log[-3000:])
            return 1
        log = blender(os.path.join(HERE, "blender", "rerig_arms.py"), ["--src", b1, "--raw", raw, "--out", out])
        line = [l for l in log.splitlines() if l.startswith("RERIG_RESULT")]
        if not line:
            print("MAKE FAIL rerig\n" + log[-3000:])
            return 1
        print(line[-1])
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
