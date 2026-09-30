# 기준 몸 사양 (UAL1 뼈대) — AI 이미지 생성에 넘기는 정보

이 폴더의 `front/left/back/right.png` 는 **겉모습이 아니라 치수 · 포즈 기준**이다.
생성할 인물은 사람(군인)이어야 하고, 마네킹 모양을 따라 하면 안 된다. 이 체형 · 관절 위치 · 자세만 맞춘다.
(맞춰야 하는 이유: 생성한 3D 를 이 뼈대에 그대로 붙여 기존 동작 · 조준 · 무기 그립을 재사용한다)

## 치수 (뼈대 실측, 발바닥 = 0)
| 항목 | 값 |
|---|---|
| 키 | 1.83 m |
| 어깨 관절 높이 | 1.44 m |
| 골반(고관절) 높이 | 0.93 m |
| 무릎 높이 | 0.53 m |
| 발목 높이 | 0.10 m |
| 팔 벌린 폭(손끝~손끝) | 1.94 m |
| 윗팔 · 아래팔 길이 | 0.27 m · 0.27 m |
| 넓적다리 · 종아리 길이 | 0.40 m · 0.43 m |
| 두 다리 간격(고관절 사이) | 0.18 m — 다리는 곧게 아래로, 발은 어깨너비보다 좁게 |

## 자세
- **T-포즈**: 두 팔을 어깨 높이에서 **수평(0°)** 으로 곧게 편다. 손바닥은 아래, 손가락은 펴서 모은다.
- 다리는 곧게 서서 발끝은 정면. 고개는 정면, 무표정.

## 촬영
- 직교(원근 없음) 전신, 흰 배경, 그림자 없는 고른 조명. 네 장 모두 같은 배율 · 같은 발 위치.
- left = 인물의 왼쪽 옆면(인물이 그림 왼쪽을 바라봄), right = 그 반대.

## 넘길 문장 (영어가 잘 먹힘)
> Generate a character turnaround sheet (front, left side, back, right side) of a **realistic adult male soldier**.
> Use the attached grey figure **only as a proportion and pose guide — do not copy its mannequin look**.
> Height 1.83 m, shoulder joints at 1.44 m, hip joints at 0.93 m, knees at 0.53 m, arm span 1.94 m.
> Strict **T-pose**: arms straight and exactly horizontal at shoulder height, palms down, fingers together;
> legs straight, feet 18 cm apart, toes forward, head forward, neutral face.
> Wearing: plain grey sleeveless undershirt and grey shorts, barefoot, short hair.
> Orthographic full body, same scale and foot position in all four views, plain white background, flat even lighting, no shadows.

- 군복 차례에는 `Wearing:` 줄만 바꾼다. 예) `M36 German field-grey wool tunic and trousers, leather belt, marching boots` / `1944 duck-hunter camouflage jacket and trousers`.
- 헬멧 · 무기 · 배낭은 **넣지 않는다**(장비 굽기로 따로 붙인다). 옷도 몸에 붙는 것만(펄럭이는 코트 자락은 파트 분리가 어려움).
