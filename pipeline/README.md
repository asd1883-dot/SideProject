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

## 파일
- `asset_pipeline.py` — 실행기(Python 3). Blender · Godot 경로는 맨 위 상수.
- `blender/normalize_weapon.py` — Blender 헤드리스 정규화.
- 이 폴더는 `.gdignore` 로 Godot 가져오기에서 뺐다.
