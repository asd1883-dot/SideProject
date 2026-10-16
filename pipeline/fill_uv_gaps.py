# -*- coding: utf-8 -*-
"""AI 모델 텍스처의 UV 틈을 각 조각(섬) 자기 색으로 다시 채운다 — **시험용, 기본 공정에 안 들어감** (10-16).

    python pipeline/fill_uv_gaps.py <glb> --check            (고치지 않고 덮개 · 틈 비율 · 밉맵 번짐만 잰다 — 새 AI 모델을 받으면 먼저)
    python pipeline/fill_uv_gaps.py <glb> [<glb> …]          (채워서 그 텍스처 파일에 덮어씀)
    python pipeline/fill_uv_gaps.py <glb> --force            (이미 채운 파일도 다시 — 보통은 건너뜀)
    python pipeline/fill_uv_gaps.py <glb> --preview <png>    (덮개 · 채운 결과를 나란히 그려 본다)

왜 만들었나: 도트 화면은 캐릭터를 작게 그려 밉맵 3 ~ 7 단계를 읽는데, 밉맵은 UV 섬 · 틈을 가리지 않고 평균을 내므로 섬 가장자리에
  틈 색이 섞인다. Tripo 텍스처는 섬이 잘게 쪼개져 있고 틈이 아틀라스의 31 ~ 34 % 다.
결과(10-16, human_base · uniform_m36): Tripo 는 틈을 이미 이웃 섬 색으로 대강 번져 둬서 효과가 작았다(밉맵 3 단계 번짐 상위 1 % 1.8 → 1.1,
  5 단계 22.9 → 22.4 · 도트 그림도 거의 같음) → 적용 안 함. "머리 꼭대기가 비어 보임"의 진짜 원인은 셰이더 쪽이었다(dot_char.gdshader —
  반복 읽기로 아틀라스 반대쪽 가장자리 색이 감겨 듦 · 비스듬한 면의 밉맵이 256 텍셀 네모로 뽑힘 → 반복 끔 · 비등방).
  틈이 검정 · 단색으로 비어 있는 텍스처(다른 생성기 · 직접 푼 UV)라면 크게 듣는다 — `--check` 의 번짐 숫자가 크면 돌릴 것.
하는 일: glb 의 UV 삼각형으로 실제로 쓰는 텍셀(덮개)을 그리고, 덮개 밖 텍셀만 가까운 섬 가장자리 색으로 바깥으로 번져 채운다(DILATE 텍셀),
  더 먼 틈은 밉맵식 평균(pull-push)으로. 덮개 안 텍셀은 원래 색 그대로(JPEG 는 다시 저장하며 생기는 오차만).
  그러면 Godot 이 만드는 밉맵이 어느 단계에서도 섬 둘레에 그 섬 색만 섞는다.
대상 파일: Godot 이 glb 에서 꺼낸 텍스처(`<glb 이름>_<이미지 이름>.jpg|png`, 같은 폴더). glb 는 안 바꾼다.
  Godot 은 glb 안 그림이 바뀔 때만(.import 의 generator_parameters md5) 이 파일을 다시 꺼내므로 고친 파일이 유지된다.
  ⚠ 모델(glb)을 새로 뽑으면 Godot 이 원래 그림을 다시 꺼내니 이 단계를 다시 돌릴 것.
이미 채운 파일은 JPEG 주석 · PNG 글 칸의 표시(MARK)로 알아보고 건너뛴다(다시 저장할 때마다 JPEG 가 조금씩 뭉개지지 않게).
마지막 줄 `FILL OK` 또는 `FILL FAIL <이유>`.
"""
import json
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw, PngImagePlugin

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
MARK = "dr_fill_uv_gaps v1"
DILATE = 48          # 섬 가장자리 색을 그대로 번지는 텍셀 수(그 밖은 pull-push) — 2048 텍스처의 밉맵 5 단계(32 텍셀)보다 넉넉히
JPEG_QUALITY = 95

COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    data = open(path, "rb").read()
    magic, _ver, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise ValueError("glb 가 아닙니다: " + path)
    off = 12
    js = None
    bin_ = b""
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:
            bin_ = chunk
        off += 8 + clen
    return js, bin_


def accessor(js, bin_, i):
    a = js["accessors"][i]
    bv = js["bufferViews"][a["bufferView"]]
    dt = np.dtype(COMP[a["componentType"]])
    n = NCOMP[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    item = dt.itemsize * n
    stride = bv.get("byteStride", 0) or item
    raw = np.frombuffer(bin_, dtype=np.uint8, count=stride * (a["count"] - 1) + item, offset=start)
    rows = np.lib.stride_tricks.as_strided(raw, shape=(a["count"], item), strides=(stride, 1))
    arr = np.frombuffer(np.ascontiguousarray(rows).tobytes(), dtype=dt).reshape(a["count"], n)
    if a.get("normalized") and dt.kind in "iu":
        arr = arr.astype(np.float64) / np.iinfo(dt).max
    return arr.astype(np.float64)


def uv_triangles(js, bin_):
    """이미지 번호 -> UV 삼각형 배열(N, 3, 2) — 그 이미지를 baseColor 로 쓰는 프리미티브만"""
    mat_img = {}
    for mi, m in enumerate(js.get("materials", [])):
        t = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if t is not None:
            mat_img[mi] = js["textures"][t["index"]]["source"]
    out = {}
    for mesh in js.get("meshes", []):
        for p in mesh["primitives"]:
            if p.get("mode", 4) != 4 or "TEXCOORD_0" not in p["attributes"] or p.get("material") not in mat_img:
                continue
            uv = accessor(js, bin_, p["attributes"]["TEXCOORD_0"])
            ix = accessor(js, bin_, p["indices"]).reshape(-1).astype(np.int64) if "indices" in p else np.arange(uv.shape[0])
            out.setdefault(mat_img[p["material"]], []).append(uv[ix[: ix.size // 3 * 3].reshape(-1, 3)])
    return {k: np.concatenate(v, axis=0) for k, v in out.items()}


def coverage(tris, w, h):
    """UV 삼각형이 덮는 텍셀(가장자리 텍셀 포함). glTF UV 원점 = 그림 왼쪽 위"""
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    uv = np.mod(tris, 1.0) if (tris.min() < 0.0 or tris.max() > 1.0) else tris
    for t in uv:
        d.polygon([(float(t[0, 0] * w), float(t[0, 1] * h)), (float(t[1, 0] * w), float(t[1, 1] * h)),
                   (float(t[2, 0] * w), float(t[2, 1] * h))], fill=255, outline=255)
    return np.asarray(img) > 0


def _shift(a, dy, dx):
    """a 를 (dy, dx) 만큼 민 것(빈 곳 0)"""
    out = np.zeros_like(a)
    h, w = a.shape[:2]
    ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
    xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
    out[yd, xd] = a[ys, xs]
    return out


def fill(rgb, known):
    """known 밖 텍셀을 채운다: DILATE 번 바깥으로 번지기(이웃 평균 — 가장자리 색이 그대로 뻗음) → 남은 곳은 pull-push"""
    col = rgb.astype(np.float32) * known[..., None]
    have = known.astype(np.float32)
    nb = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]
    for _ in range(DILATE):
        acc = np.zeros_like(col)
        cnt = np.zeros_like(have)
        for dy, dx in nb:
            acc += _shift(col, dy, dx)
            cnt += _shift(have, dy, dx)
        grow = (have == 0) & (cnt > 0)
        if not grow.any():
            break
        col[grow] = acc[grow] / cnt[grow][:, None]
        have[grow] = 1.0
    if (have == 0).any():
        col = _pull_push(col, have)
    return col


def _pull_push(col, have):
    """빈 텍셀(have 0)을 덮개 가중 평균 피라미드로 채운다(가까운 칠한 텍셀이 많이 들어감)"""
    levels = [(col * have[..., None], have)]
    c, w = levels[0]
    while min(c.shape[:2]) > 1:
        h2, w2 = (c.shape[0] + 1) // 2, (c.shape[1] + 1) // 2
        cp = np.zeros((h2 * 2, w2 * 2, 3), np.float32)
        wp = np.zeros((h2 * 2, w2 * 2), np.float32)
        cp[: c.shape[0], : c.shape[1]] = c
        wp[: w.shape[0], : w.shape[1]] = w
        c = cp[0::2, 0::2] + cp[1::2, 0::2] + cp[0::2, 1::2] + cp[1::2, 1::2]
        w = wp[0::2, 0::2] + wp[1::2, 0::2] + wp[0::2, 1::2] + wp[1::2, 1::2]
        levels.append((c, w))
    c, w = levels[-1]
    filled = c / np.maximum(w, 1e-6)[..., None]
    for c, w in reversed(levels[:-1]):
        up = np.repeat(np.repeat(filled, 2, axis=0), 2, axis=1)[: c.shape[0], : c.shape[1]]
        filled = np.where((w > 0)[..., None], c / np.maximum(w, 1e-6)[..., None], up)
    return np.where((have > 0)[..., None], col, filled)


def mip_bleed(rgb, known, levels=(3, 4, 5)):
    """밉맵 단계마다 덮개 안 텍셀이 원래 색(그 단계 크기로 덮개만 평균)에서 얼마나 벗어나나 — 평균 · 상위 1 % (0 ~ 255)"""
    out = []
    a = rgb.astype(np.float32)
    k = known.astype(np.float32)
    for lv in levels:
        s = 2 ** lv
        h, w = a.shape[0] // s * s, a.shape[1] // s * s
        blk = a[:h, :w].reshape(h // s, s, w // s, s, 3)
        kb = k[:h, :w].reshape(h // s, s, w // s, s)
        plain = blk.mean(axis=(1, 3))                                   # 밉맵(섬 · 틈 가리지 않음)
        ksum = kb.sum(axis=(1, 3))
        own = (blk * kb[..., None]).sum(axis=(1, 3)) / np.maximum(ksum, 1e-6)[..., None]   # 덮개만
        m = ksum > 0
        d = np.abs(plain - own).max(axis=-1)[m]
        out.append((lv, float(d.mean()), float(np.percentile(d, 99))))
    return out


def texture_path(glb, js, img_index):
    """Godot 이 꺼낸 텍스처 파일 — <glb 이름>_<이미지 이름>.<확장자>"""
    im = js["images"][img_index]
    name = im.get("name") or ("image_%d" % img_index)
    ext = {"image/jpeg": "jpg", "image/png": "png"}.get(im.get("mimeType", ""), "")
    stem = os.path.splitext(os.path.basename(glb))[0]
    for e in ([ext] if ext else []) + ["jpg", "jpeg", "png"]:
        p = os.path.join(os.path.dirname(glb), "%s_%s.%s" % (stem, name, e))
        if os.path.exists(p):
            return p
    return ""


def is_marked(path):
    try:
        im = Image.open(path)
        return MARK in str(im.info.get("comment", b"")) or im.info.get("dr_fill") == MARK
    except OSError:
        return False


def save(path, arr):
    img = Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), "RGB")
    if path.lower().endswith((".jpg", ".jpeg")):
        img.save(path, quality=JPEG_QUALITY, subsampling=0, comment=MARK.encode("utf-8"))
    else:
        meta = PngImagePlugin.PngInfo()
        meta.add_text("dr_fill", MARK)
        img.save(path, pnginfo=meta)


def process(glb, check, force, preview):
    js, bin_ = read_glb(glb)
    tris = uv_triangles(js, bin_)
    if not tris:
        print("  ⚠ baseColor 텍스처를 쓰는 UV 가 없음: " + glb)
        return True
    ok = True
    for img_i, t in tris.items():
        tex = texture_path(glb, js, img_i)
        if tex == "":
            print("  ✗ Godot 이 꺼낸 텍스처 파일을 못 찾음(이미지 %d, 에디터에서 glb 를 한 번 가져와야 생김): %s" % (img_i, glb))
            ok = False
            continue
        rel = os.path.relpath(tex, PROJECT)
        if is_marked(tex) and not force and not check:
            print("  - 이미 채움(건너뜀, --force 로 다시): " + rel)
            continue
        src = Image.open(tex).convert("RGB")
        rgb = np.asarray(src).astype(np.float32)
        h, w = rgb.shape[:2]
        known = coverage(t, w, h)
        before = mip_bleed(rgb, known)
        print("  %s  %dx%d · 삼각형 %d · 덮개 %.1f %% (틈 %.1f %%)" % (rel, w, h, len(t), known.mean() * 100, (1 - known.mean()) * 100))
        print("    번짐(밉맵 단계: 평균 / 상위 1 %%, 0~255) 지금 %s" % " · ".join("%d: %.1f / %.1f" % b for b in before))
        if check:
            continue
        out = fill(rgb, known)
        out[known] = rgb[known]
        after = mip_bleed(out, known)
        print("    번짐 채운 뒤          %s" % " · ".join("%d: %.1f / %.1f" % b for b in after))
        save(tex, out)
        print("    → 저장(덮개 안은 원래 색 · JPEG 품질 %d · 표시 %s)" % (JPEG_QUALITY, MARK))
        if preview:
            vis = rgb.copy()
            vis[~known] = vis[~known] * 0.25 + np.array([255, 0, 255], np.float32) * 0.75
            sheet = Image.new("RGB", (w * 2, h))
            sheet.paste(Image.fromarray(vis.astype(np.uint8)), (0, 0))
            sheet.paste(Image.fromarray(np.clip(out, 0, 255).astype(np.uint8)), (w, 0))
            sheet.resize((1024, 512), Image.BOX).save(preview)
            print("    → 그림 " + preview)
    return ok


def main():
    args = sys.argv[1:]
    check = "--check" in args
    force = "--force" in args
    preview = args[args.index("--preview") + 1] if "--preview" in args else ""
    glbs = [a for i, a in enumerate(args) if not a.startswith("--") and (i == 0 or args[i - 1] != "--preview")]
    if not glbs:
        print(__doc__)
        print("FILL FAIL glb 를 주세요")
        return 1
    ok = True
    for g in glbs:
        p = g if os.path.isabs(g) else os.path.join(PROJECT, g) if not os.path.exists(g) else os.path.abspath(g)
        print("[%s]" % os.path.relpath(p, PROJECT))
        if not os.path.exists(p):
            print("  ✗ 파일 없음")
            ok = False
            continue
        ok = process(p, check, force, preview) and ok
    print("FILL OK" if ok else "FILL FAIL 위 ✗ 참고")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
