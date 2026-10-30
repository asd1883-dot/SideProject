# 출처 (Credits)

이 저장소에 들어 있는 남이 만든 자산과 그 이용 조건. 게임을 낼 때는 **크레딧 화면에도 CC BY 자산의 출처를 적는다**.

## 3D 모델

| 자산 | 만든 사람 · 출처 | 이용 조건 | 저장소 위치 | 바꾼 것 |
|---|---|---|---|---|
| **Kar98k** | [Ecler](https://sketchfab.com/ecler) — [Sketchfab "Kar98k"](https://sketchfab.com/3d-models/kar98k-96b7387fe49b4dd491cc8277f765527a) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) (출처 표기) | `source3d/weapons/kar98k/` · `equip/kar98k/` · `equip/kar98_obj/` | 빠진 MTL 새로 만듦 · 길이 · 원점(잡는 자리) · 축 정규화 후 GLB 로 바꿈 · 무기 씬(왼손 표지) · 도트 그림으로 굽기 |
| Universal Animation Library (UAL1) | [Quaternius](https://quaternius.com) | CC0 (퍼블릭 도메인) | `models/UAL1.glb` · `source3d/UAL1_humanoid.glb` | 임포트 설정(BoneMap) |

"Kar98k" (https://sketchfab.com/3d-models/kar98k-96b7387fe49b4dd491cc8277f765527a) by Ecler is licensed under Creative Commons Attribution 4.0 (http://creativecommons.org/licenses/by/4.0/). Modified: material file recreated, normalized and converted to glTF, rendered to pixel sprites.

## 동작

| 자산 | 출처 | 이용 조건 | 저장소 위치 |
|---|---|---|---|
| 소총 동작 FBX | [Adobe Mixamo](https://www.mixamo.com) | Adobe 이용 약관 — 게임 · 영상에 넣어 쓰는 것은 무료. ⚠ 원본 동작 파일을 공개 저장소에 그대로 두는 것이 재배포 제한에 걸리는지는 **확인 안 됨** | `source3d/mixamo/*.fbx` |

## 직접 만든 것 (남의 자산 아님)

| 자산 | 만든 방법 | 저장소 위치 |
|---|---|---|
| 사람 몸 · M36 군복 | ComfyUI + Tripo(사용자 구독) 로 만든 3D · 기준 뼈대에 붙임 | `source3d/characters/human_base/` · `source3d/characters/uniform_m36/` |
| MP40 | ComfyUI 로 만든 3D | `source3d/weapons/mp40/` |
| 맵 그림 · 깃발 문양 | 아스트라(Codex 내장 image_gen) 로 생성(10-30, 이미지 입력 없이 글로만 · 프롬프트 `Docs/게임설계/아스트라_프롬프트.txt`) | `game/map/` |
