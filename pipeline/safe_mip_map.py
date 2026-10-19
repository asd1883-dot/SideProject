# -*- coding: utf-8 -*-
"""안전 밉 지도 — 텍스처 텍셀마다 "다른 UV 조각(섬) · 틈까지 거리"를 작은 지도로 굽는다. 도트 셰이더(dot_char)가 그 거리보다
긴 발자국으로 읽지 않게 기울기를 줄여, 작게 그릴 때 옆 조각 색이 섞이지 않는다 (10-19).

    python pipeline/safe_mip_map.py source3d/characters/human_base/human_base.glb source3d/characters/uniform_m36/uniform_m36.glb
    python pipeline/safe_mip_map.py <glb> --preview <png>      (지도를 눈으로 — 밝을수록 경계에서 멂)

왜: 사용자 "탈모 형태로 x2 도트화부터 머리 빈 곳이 보임. 살색이 비쳐짐 정수리 부분이나". 원본 텍스처의 정수리(바인드 자세 y > 1.78)는
  전부 진한 머리색(밝기 상위 10 % ≤ 51)인데 도트 화면에서 밝기 70 ~ 120 도트가 찍혔다 — 머리카락 조각 A 의 오른쪽 끝(정수리 앞 · 가운데 이음매)이
  아틀라스에서 피부 조각과 몇 텍셀 사이로 붙어 있어, 밉맵 4 ~ 5 단계(16 ~ 32 텍셀 네모)부터 피부가 섞였다. 도트가 클수록(밉 단계가 높을수록)
  늘어남: 순수 머리 구역의 밝은 도트 도트 1 = 0.16 % · 2 = 0.85 % · 3 = 1.8 % · 4 = 3.85 %(1 m = 40 px 에선 머리 도트 몇 개 중 30 ~ 100 %).
  틈을 다시 칠해도(fill_uv_gaps) 거의 같았다(맞닿은 섬이라).
하는 일: glb UV 삼각형으로 섬 번호를 그리고(같은 UV 를 쓰는 정점끼리 묶음 · 틈 = 0) 섬이 바뀌는 텍셀 = 경계. 텍셀마다 경계까지
  체비쇼프 거리 d(텍셀) → 읽어도 되는 발자국 길이 L = d / 1.5(겹선형이 발자국의 1.5 배까지 읽는 최악) → 값 = log2(L + 1) / 8(0 ~ 1, L 0 ~ 255)
  → 4×4 칸의 최솟값으로 1/4 크기(2048 → 512) 회색 PNG `<텍스처 이름>.safemip.png`(+ .import: 무손실 · 밉맵 없음 · 3D 감지 끔).
  DRCharacter3D.char_material 이 텍스처 옆에 이 파일이 있으면 dot_char 의 safe_tex 로 넣는다. 셰이더: 발자국 긴 축 > L 이면 두 기울기를
  같은 비율로 줄여 textureGrad(비등방 유지 — 경계 근처만 또렷하게, 안쪽은 그대로).
⚠ 모델(glb)을 새로 뽑으면(UV 가 바뀌면) 다시 돌릴 것. 텍스처 그림만 바뀌면 그대로 써도 된다(섬 모양만 본다).
마지막 줄 `SAFEMIP OK` 또는 `SAFEMIP FAIL <이유>`.
"""
import os
import sys

sys.dont_write_bytecode = True
import numpy as np  # noqa: E402
from PIL import Image, ImageDraw  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fill_uv_gaps as fug  # noqa: E402

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
SUFFIX = ".safemip.png"
DOWN = 4                      # 지도 = 텍스처 크기 / DOWN (칸 최솟값 — 보수적)
SUPPORT = 1.5                 # 겹선형 + 밉 칸 정렬로 발자국의 몇 배까지 읽나(등방 최악)
RADII = [0, 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 384]

IMPORT_TEXT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="%s"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=false
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=false
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def island_map(js, bin_, img_index, w, h):
    """그 이미지를 쓰는 프리미티브의 UV 섬 번호 지도(int32, 0 = 틈). 같은 UV 자리 정점끼리 하나로(노멀 이음매로 갈린 정점도 같은 섬)"""
    mat_img = {}
    for mi, m in enumerate(js.get("materials", [])):
        t = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if t is not None:
            mat_img[mi] = js["textures"][t["index"]]["source"]
    tris = []
    for mesh in js.get("meshes", []):
        for p in mesh["primitives"]:
            if p.get("mode", 4) != 4 or "TEXCOORD_0" not in p["attributes"] or mat_img.get(p.get("material")) != img_index:
                continue
            uv = fug.accessor(js, bin_, p["attributes"]["TEXCOORD_0"])
            ix = fug.accessor(js, bin_, p["indices"]).reshape(-1).astype(np.int64) if "indices" in p else np.arange(uv.shape[0])
            tris.append((uv, ix[: ix.size // 3 * 3].reshape(-1, 3)))
    img = Image.new("I", (w, h), 0)
    d = ImageDraw.Draw(img)
    base = 0
    for uv, ix in tris:
        # 같은 UV 자리 = 한 정점
        key = np.round(np.mod(uv, 1.0) * (1 << 20)).astype(np.int64)
        _, vid = np.unique(key[:, 0] * (1 << 21) + key[:, 1], return_inverse=True)
        parent = np.arange(vid.max() + 1)

        def find(a):
            r = a
            while parent[r] != r:
                r = parent[r]
            while parent[a] != r:
                parent[a], a = r, parent[a]
            return r
        for t in vid[ix]:
            ra = find(t[0])
            parent[find(t[1])] = ra
            parent[find(t[2])] = ra
        roots = np.array([find(i) for i in range(len(parent))])
        _, comp = np.unique(roots, return_inverse=True)
        tri_isl = comp[vid[ix[:, 0]]] + base + 1
        base = int(tri_isl.max())
        u = np.mod(uv, 1.0)
        for k, t in enumerate(ix):
            pts = [(float(u[t[j], 0] * w), float(u[t[j], 1] * h)) for j in range(3)]
            d.polygon(pts, fill=int(tri_isl[k]), outline=int(tri_isl[k]))
    return np.asarray(img, np.int32), base


def _boxsum(mask, r):
    c = np.pad(mask.astype(np.int32), ((1, 0), (1, 0))).cumsum(0).cumsum(1)
    h, w = mask.shape
    y0 = np.clip(np.arange(h) - r, 0, h)
    y1 = np.clip(np.arange(h) + r + 1, 0, h)
    x0 = np.clip(np.arange(w) - r, 0, w)
    x1 = np.clip(np.arange(w) + r + 1, 0, w)
    return c[y1][:, x1] - c[y0][:, x1] - c[y1][:, x0] + c[y0][:, x0]


def safe_map(lab):
    """텍셀마다 읽어도 되는 발자국 길이 L(텍셀) — 남의 섬 · 틈까지 체비쇼프 거리 / SUPPORT"""
    b = np.zeros(lab.shape, bool)
    for dy, dx in [(0, 1), (1, 0), (1, 1), (1, -1)]:
        diff = lab != np.roll(np.roll(lab, dy, 0), dx, 1)
        b |= diff
        b |= np.roll(np.roll(diff, -dy, 0), -dx, 1)
    dist = np.zeros(lab.shape, np.float32)          # 경계 텍셀 자신 = 남의 텍셀까지 1
    for r in RADII:
        free = _boxsum(b, r) == 0
        dist[free] = r + 1
    return dist / SUPPORT, b


def encode(L, w, h):
    v = np.clip(np.log2(L + 1.0) / 8.0, 0.0, 1.0)
    q = np.floor(v * 255.0).astype(np.uint8)        # 내림 — 늘 보수적
    hh, ww = h // DOWN, w // DOWN
    return q[: hh * DOWN, : ww * DOWN].reshape(hh, DOWN, ww, DOWN).min(axis=(1, 3))


def project_root(path):
    """path 위로 project.godot 이 있는 폴더(사본에서 돌려도 res:// 길이 맞게). 없으면 이 저장소"""
    d = os.path.dirname(os.path.abspath(path))
    while True:
        if os.path.exists(os.path.join(d, "project.godot")):
            return d
        up = os.path.dirname(d)
        if up == d:
            return PROJECT
        d = up


def process(glb, preview):
    root = project_root(glb)
    js, bin_ = fug.read_glb(glb)
    ok = True
    imgs = sorted({js["textures"][m["pbrMetallicRoughness"]["baseColorTexture"]["index"]]["source"]
                   for m in js.get("materials", []) if m.get("pbrMetallicRoughness", {}).get("baseColorTexture") is not None})
    if not imgs:
        print("  ⚠ baseColor 텍스처가 없음: " + glb)
        return True
    for img_i in imgs:
        tex = fug.texture_path(glb, js, img_i)
        if tex == "":
            print("  ✗ Godot 이 꺼낸 텍스처 파일을 못 찾음(이미지 %d — 에디터에서 glb 를 한 번 가져와야 생김): %s" % (img_i, glb))
            ok = False
            continue
        w, h = Image.open(tex).size
        lab, n = island_map(js, bin_, img_i, w, h)
        L, bnd = safe_map(lab)
        q = encode(L, w, h)
        out = os.path.splitext(tex)[0] + SUFFIX
        Image.fromarray(q, "L").save(out)
        imp = out + ".import"
        if not os.path.exists(imp):
            rel = "res://" + os.path.relpath(out, root).replace("\\", "/")
            with open(imp, "w", encoding="utf-8", newline="\n") as f:
                f.write(IMPORT_TEXT % rel)
        cov = lab > 0
        Lc = L[cov]
        print("  %s  %dx%d · 섬 %d · 덮개 %.1f %% · 경계 텍셀 %.1f %% · 읽어도 되는 발자국(텍셀) 중앙 %.0f · 하위 10 %% %.1f · 25 %% %.1f" % (
            os.path.relpath(tex, root), w, h, n, cov.mean() * 100, (bnd & cov).mean() * 100 / max(cov.mean(), 1e-9),
            np.median(Lc), np.percentile(Lc, 10), np.percentile(Lc, 25)))
        print("    → %s (%dx%d)" % (os.path.relpath(out, root), q.shape[1], q.shape[0]))
        if preview:
            Image.fromarray(q, "L").resize((1024, 1024), Image.NEAREST).save(preview)
            print("    → 그림 " + preview)
    return ok


def main():
    args = sys.argv[1:]
    preview = args[args.index("--preview") + 1] if "--preview" in args else ""
    glbs = [a for i, a in enumerate(args) if not a.startswith("--") and (i == 0 or args[i - 1] != "--preview")]
    if not glbs:
        print(__doc__)
        print("SAFEMIP FAIL glb 를 주세요")
        return 1
    ok = True
    for g in glbs:
        p = os.path.abspath(g) if os.path.exists(g) else os.path.join(PROJECT, g)
        print("[%s]" % os.path.relpath(p, project_root(p)))
        if not os.path.exists(p):
            print("  ✗ 파일 없음")
            ok = False
            continue
        ok = process(p, preview) and ok
    print("SAFEMIP OK" if ok else "SAFEMIP FAIL 위 ✗ 참고")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
