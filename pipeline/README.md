# 자산 공정 (asset pipeline)

자산 하나 = `asset.json` 하나. 생성 → 정규화(Blender) → 굽기(Dot Rigger 장비 굽기) → 검수가 이 파일의 자기 칸을 읽고 결과를 적는다.
지금(1단계)은 **무기**만. 앞단(ComfyUI 이미지 · image-to-3D)은 2단계에서 `source` 칸을 채우는 쪽으로 붙는다.

```
python pipeline/asset_pipeline.py source3d/weapons/kar98k/asset.json            # 전부
python pipeline/asset_pipeline.py <asset.json> --only normalize                  # 정규화만(Godot 에디터가 열려 있어도 됨)
python pipeline/asset_pipeline.py <asset.json> --only bake                       # 굽기만
python pipeline/asset_pipeline.py <asset.json> --project <다른 프로젝트 경로>     # 샌드박스
```
마지막 줄이 `PIPELINE OK` 또는 `PIPELINE FAIL <이유>`. 굽기는 명령줄 Godot 라서 **같은 프로젝트를 에디터가 열고 있으면 멈춘다**
(`--force` 로 무시 — 권하지 않음). 에디터가 열려 있을 때는 정규화만 돌리고, 굽기는 에디터의 장비 굽기 창에서 하면 된다(창에서 구워도 asset.json 의 equip 칸이 갱신된다).

## 생성(Tripo API) — `source.generator.tool` 이 `"tripo"` 일 때
`source.generator.image`(입력 이미지) 한 장으로 Tripo 에서 3D(GLB, 텍스처 포함)를 받아 `generated/<id>_tripo.glb` 에 두고 `source.file` 을 그것으로 바꾼다.
키 = 환경 변수 `TRIPO_API_KEY`(파일에 적지 않는다). 같은 이미지·설정으로 이미 만든 결과가 있으면 다시 만들지 않는다(`--regen` 으로 강제).
잔액만: `python pipeline/generate_tripo.py --balance`. 쓴 크레딧은 `source.generator.credits_before/after` 에 남는다.

## asset.json 칸

| 칸 | 누가 쓰나 | 뜻 |
|---|---|---|
| `id` · `kind` | 사람 | 이름 · 종류(weapon) |
| `source.file` | 사람 / 2단계 생성기 | 원본 3D(OBJ · FBX · GLB, 절대 경로나 res://) |
| `source.generator` | 2단계 생성기 | 만든 도구 · 워크플로 · 프롬프트 · 시드 · 참조 이미지 — 다시 만들 때 같게 |
| `normalize.length_m` | 사람 | 총구 축 길이(m). 0 = 그대로 |
| `normalize.forward` | 사람 | 원본에서 총구 축(`+X` … `-Z`) 또는 `auto`(가장 긴 축 · 양 끝 단면이 작은 쪽이 총구) |
| `normalize.up` | 사람 | 원본에서 위 축(기본 `+Z` — Blender 가 OBJ 를 Z-up 으로 가져온다) |
| `normalize.grip_node` | 사람 | 손이 잡는 자리 노드(원점이 여기로) |
| `normalize.output` | 사람 | 정규화 결과 GLB(res://) |
| `normalize.result` | 정규화 | 찾은 총구 축 · 잰 길이 · 배율 · 파트 · 삼각형 수 |
| `character.preset` · `character.sets` | 사람 | 어느 캐릭터 · 세트에 맞춰 굽나 |
| `equip` | 굽기(CLI · 창) | 장비 설정 전부(equip.json 의 설정 부분과 같다). `grip_base` 가 있으면 다음 굽기는 자동 그립 대신 이 값 그대로 |
| `history` | 모든 단계 | 언제 어느 단계가 성공/실패 |

## 규격(정규화 결과, Godot 축)
총구 = +Z · 위 = +Y · 크기 = `length_m` · 원점 = 잡는 자리 · 파트(하위 오브젝트) 이름 유지.

## 검수(자동)
정규화: 길이 ±2 cm · 삼각형 60,000 이하 · 잡는 자리 노드 있음. 굽기: equip.json · 자세마다 그림 파일.

### 정규화 추가 칸 (AI 생성 무기, 10-01)
- `normalize.max_triangles` — 넘으면 Decimate 로 줄인다(Tripo 에 face_limit 을 안 주면 100만 면 이상. MP40 = 20000).
- `normalize.split` — `{"<파트 이름>": {"min": [x, y, z], "max": [x, y, z]}}`(Godot 축 · 정규화 결과 기준 m: x 옆 · y 위 · z 총구 쪽). 면 가운데가 상자 안이면 그 파트로 떼어 낸다(통짜 AI 모델의 탄알집 등).

## 캐릭터(사람 몸 · 옷) — 10-02
Dot Rigger 의 **복장 굽기 창**(프로젝트 > 도구 > Dot Rigger — 복장 굽기)에서 아래를 버튼으로 할 수 있다. 명령줄은 같은 스크립트.

| 파일 | 하는 일 |
|---|---|
| `blender/render_turnaround.py <모델.glb> <폴더> [1024] [texture]` | 기준 몸 앞 · 왼 · 뒤 · 오 4장 + sheet(T-포즈, 같은 배율). AI 이미지에 넣는 체형 · 포즈 기준. `texture` = 회색 대신 모델 색(옷 입힐 "이 사람") |
| `reference/body_ual1/` · `reference/soldier_base/` | 위 결과. `body_ual1/SPEC.md` = 뼈대 치수와 AI 에 넘길 문장 |
| `blender/bind_to_skeleton.py --base <기준 몸.glb> --src <AI 원본.glb> --out <결과.glb>` | AI 사람 몸 · 옷을 기준 뼈대(UAL1)에 붙인다. `--smooth 12` `--hand_fit 1` `--thumb_fit 1` `--part_fix 1` `--keep_base 0` `--shoulder_cut 0`. 결과 `.import` 에 기준 몸의 뼈 이름표를 복사. 마지막 줄 `BIND_RESULT {json}` |
| `check_character.py <glb> [--anims …] [--rest_time 0.42]` | 샌드박스(`Documents/1941`)에 복사해 동작마다 **실제 굽기** → 마네킹과 나란히 `check/<이름>_sheet.png`. 캐릭터를 바꾸면 이걸 보고 넘긴다 |

AI 생성: 이미지 4장(정면 · 왼 · 뒤 · 오, T-포즈) → ComfyUI `Tripo: Generate model` `multiview_to_model` · `face_limit` 20000 · `file_prefix` = 자산 이름 → `comfy/`(저장소 밖).

## 파일
- `asset_pipeline.py` — 실행기(Python 3). Blender · Godot 경로는 맨 위 상수.
- `blender/normalize_weapon.py` — Blender 헤드리스 정규화.
- `blender/render_turnaround.py` · `blender/bind_to_skeleton.py` · `check_character.py` — 캐릭터(위 표).
- `generate_tripo.py` — Tripo API 직접 호출(무기 1장 생성용).
- 이 폴더는 `.gdignore` 로 Godot 가져오기에서 뺐다. `comfy/*.glb`(AI 원본) · `check/`(검사 그림)는 `.gitignore`.
