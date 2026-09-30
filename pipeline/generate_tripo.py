# -*- coding: utf-8 -*-
"""생성 단계(Tripo API) — 이미지 한 장으로 3D(GLB)를 만들어 asset.json 의 source 에 적는다.

    python pipeline/generate_tripo.py <asset.json>              (asset_pipeline.py 가 부른다)
    python pipeline/generate_tripo.py --balance                  잔액만 확인(크레딧 안 씀)

- API 키 = 환경 변수 TRIPO_API_KEY (파일에 적지 않는다).
- asset.json 의 source.generator:
    { "tool": "tripo", "image": "<입력 이미지 경로>", "texture": true, "pbr": false,
      "model_version": "", "face_limit": 0, "task_id": (결과), "credits_before/after": (결과) }
- 결과 GLB 는 asset.json 옆의 generated/<id>_tripo.glb 에 받고, source.file 을 그 경로로 바꾼다.
- 같은 이미지 · 같은 설정으로 이미 만든 task_id 가 있으면 다시 만들지 않는다(크레딧 절약). --regen 으로 강제.
"""
import json, os, sys, time, mimetypes, urllib.request, urllib.error, uuid, hashlib

API = "https://api.tripo3d.ai/v2/openapi"


def key():
    k = os.environ.get("TRIPO_API_KEY", "")
    if not k and os.name == "nt":
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as h:
                k = winreg.QueryValueEx(h, "TRIPO_API_KEY")[0]
        except OSError:
            k = ""
    if not k:
        raise SystemExit("TRIPO_API_KEY 환경 변수가 없습니다")
    return k


def call(method, path, body=None, headers=None, raw=None):
    h = {"Authorization": "Bearer " + key()}
    if headers:
        h.update(headers)
    data = raw
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(API + path, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        raise SystemExit("Tripo %s %s → HTTP %d %s" % (method, path, e.code, e.read().decode("utf-8", "replace")[:300]))


def balance():
    d = call("GET", "/user/balance")
    return int(d.get("data", {}).get("balance", 0))


def upload(image_path):
    boundary = uuid.uuid4().hex
    name = os.path.basename(image_path)
    ctype = mimetypes.guess_type(name)[0] or "image/png"
    with open(image_path, "rb") as f:
        payload = f.read()
    body = (("--%s\r\nContent-Disposition: form-data; name=\"file\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n" % (boundary, name, ctype)).encode("utf-8")
            + payload + ("\r\n--%s--\r\n" % boundary).encode("utf-8"))
    d = call("POST", "/upload", raw=body, headers={"Content-Type": "multipart/form-data; boundary=" + boundary})
    tok = d.get("data", {}).get("image_token", "")
    if not tok:
        raise SystemExit("업로드 응답에 image_token 이 없습니다: %s" % str(d)[:300])
    return tok, os.path.splitext(name)[1].lstrip(".").lower() or "png"


def wait(task_id, log):
    t0 = time.time()
    while True:
        d = call("GET", "/task/" + task_id).get("data", {})
        st = d.get("status", "")
        if st in ("success", "failed", "cancelled", "banned", "expired", "unknown"):
            return d
        if time.time() - t0 > 900:
            raise SystemExit("Tripo 작업이 15분 안에 안 끝났습니다: " + task_id)
        log("      진행 %s %s%%" % (st, d.get("progress", "?")))
        time.sleep(5)


def download(url, out):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with urllib.request.urlopen(url, timeout=300) as r, open(out, "wb") as f:
        f.write(r.read())


def res_to_abs(p, project):
    return os.path.join(project, p[6:].replace("/", os.sep)) if p.startswith("res://") else p


def fingerprint(image_path, g):
    h = hashlib.sha1()
    with open(image_path, "rb") as f:
        h.update(f.read())
    h.update(json.dumps({k: g.get(k) for k in ("texture", "pbr", "model_version", "face_limit")}, sort_keys=True).encode())
    return h.hexdigest()[:16]


def generate(asset_path, project, log=print, regen=False):
    with open(asset_path, encoding="utf-8") as f:
        asset = json.load(f)
    src = asset.setdefault("source", {})
    g = src.setdefault("generator", {})
    img = res_to_abs(str(g.get("image", "")), project)
    if not img or not os.path.exists(img):
        return False, "source.generator.image 가 없습니다: %s" % img
    fp = fingerprint(img, g)
    out = os.path.join(os.path.dirname(asset_path), "generated", "%s_tripo.glb" % asset.get("id", "asset"))
    if not regen and g.get("fingerprint") == fp and g.get("task_id") and os.path.exists(out):
        log("      같은 이미지 · 설정으로 이미 만든 결과를 씁니다(크레딧 안 씀): " + g["task_id"])
        return True, out
    before = balance()
    tok, ext = upload(img)
    body = {"type": "image_to_model", "file": {"type": "jpg" if ext == "jpeg" else ext, "file_token": tok},
            "texture": bool(g.get("texture", True)), "pbr": bool(g.get("pbr", False))}
    if g.get("model_version"):
        body["model_version"] = g["model_version"]
    if int(g.get("face_limit", 0) or 0) > 0:
        body["face_limit"] = int(g["face_limit"])
    d = call("POST", "/task", body=body)
    task_id = d.get("data", {}).get("task_id", "")
    if not task_id:
        return False, "작업 생성 실패: %s" % str(d)[:300]
    log("      Tripo 작업 %s" % task_id)
    r = wait(task_id, log)
    if r.get("status") != "success":
        return False, "Tripo 작업 %s: %s" % (task_id, r.get("status"))
    o = r.get("output", {})
    url = o.get("pbr_model") or o.get("model") or o.get("base_model") or ""
    if not url:
        return False, "결과에 모델 주소가 없습니다: %s" % str(o)[:300]
    download(url, out)
    after = balance()
    g.update({"tool": "tripo", "task_id": task_id, "fingerprint": fp, "credits_before": before, "credits_after": after,
              "at": time.strftime("%Y-%m-%dT%H:%M:%S")})
    src["file"] = out.replace("\\", "/")
    with open(asset_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(asset, f, ensure_ascii=False, indent="\t")
    log("      받음 %s · 크레딧 %d → %d (%d 씀)" % (os.path.basename(out), before, after, before - after))
    return True, out


if __name__ == "__main__":
    if "--balance" in sys.argv:
        print("Tripo API 잔액:", balance())
        sys.exit(0)
    a = [x for x in sys.argv[1:] if not x.startswith("--")]
    project = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ok, msg = generate(os.path.abspath(a[0]), project, regen="--regen" in sys.argv)
    print(("OK " if ok else "FAIL ") + str(msg))
    sys.exit(0 if ok else 1)
