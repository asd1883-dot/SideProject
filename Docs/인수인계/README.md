# Dot Rigger 인수인계 — 여기서 시작

> 최종 갱신 **2026-09-14** · 저장소 `Documents\1941` (Godot 4.7.2 프로젝트 "1941")

3D 휴머노이드 모델(.glb)을 **고정 시점 2D 컷아웃 퍼펫**(파트 스프라이트 + Skeleton2D + 애니메이션)으로 바꿔 주는 Godot 에디터 애드온. 옷·무기·장구류를 갈아입는 캐릭터용이다 — 장비 1종 = 이미지 1장.

---

## 문서 지도

| 문서 | 내용 |
|---|---|
| **이 문서** | 다른 PC에서 시작하기 · 검증 · 현재 상태 · 남은 일 |
| [01_설계와_구조.md](01_설계와_구조.md) | 왜 컷아웃인가 · 파이프라인 · 파일 지도 · 설계 결정과 이유 · 데이터 포맷 |
| [02_버그와_교훈.md](02_버그와_교훈.md) | 겪은 버그 전부(증상·원인·해결·검사) · Godot 함정 · 작업 규칙 · 측정값 |
| [addons/dot_rigger/README.md](../../addons/dot_rigger/README.md) | **사용법** — 창 버튼·조작 · CLI · 장비 붙이기 · 알려진 한계 |

---

## 다른 PC에서 시작하기

### 1. 준비물

| 항목 | 내용 |
|---|---|
| Godot | **4.7.2 mono** (`Godot_v4.7.2-stable_mono_win64`). 이 PC 위치 `C:\Users\Dev\Desktop\Godot_v4.7.2-stable_mono_win64\`. `project.godot` 에 `[dotnet]` 섹션이 있어 **mono 판으로만 검증**했다(C# 코드는 없음) |
| 렌더러 | Forward+ / Windows D3D12 (`project.godot`). 이 PC GPU는 RTX 5060 |
| Python + Pillow | 선택. 비교 이미지를 만들 때만 썼다(애드온·검증 도구 자체에는 불필요) |

### 2. 열기

1. clone → Godot 프로젝트 매니저에서 `project.godot` 가져오기
2. 첫 실행 때 `models/UAL1.glb`(21MB) 임포트에 시간이 걸린다
3. 플러그인은 `project.godot` 에 이미 켜져 있다 → 메뉴 **`프로젝트 > 도구 > Dot Rigger (3D → 2D 컷아웃)`**
4. `0. 프리셋 > 불러오기...` → `res://UAL1_preset.tres` 를 고르면 사용자 작업 설정이 그대로 돌아온다

### 3. 저장소에 있는 것 / 없는 것

| 경로 | 저장소 | 비고 |
|---|:---:|---|
| `addons/dot_rigger/` | ✓ | 애드온 전체 (코드·셰이더·검증 도구·사용법 README) |
| `Docs/인수인계/` | ✓ | 이 문서들 |
| `models/UAL1.glb` | ✓ | Quaternius *Universal Animation Library*, **CC0(퍼블릭 도메인)**. 원본 폴더(.blend·FBX·루트모션 `_RM` 판·라이선스 파일)는 저장소에 없음 — 이 PC `Desktop\Universal Animation Library[Source]\` |
| `UAL1_preset.tres` | ✓ | 사용자 작업 설정 |
| `puppet/` | ✓ | 사용자가 09-11 에디터에서 구운 결과 |
| `puppet_test/` | ✗ | 검증 도구 산출물. `.gitignore` 대상이고 도구가 다시 만든다 |
| `.godot/` | ✗ | 임포트 캐시 |

---

## 검증

렌더가 필요한 도구는 **창이 잠깐 떴다 닫힌다.** `--headless` 로는 SubViewport 가 안 그려져서 쓸 수 없다(`bake_cli --diag` 만 예외). 출력을 받으려면 `_console.exe` 를 쓴다.

**Git Bash**
```bash
G="/c/<경로>/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64_console.exe"
P="C:/<경로>/1941"

"$G" --headless --path "$P" --import                                                     # ① 스크립트 등록 (새 class_name 추가 후에도 필수)
"$G" --headless --path "$P" --script res://addons/dot_rigger/tools/bake_cli.gd -- --diag   # ② 본→파트 매핑
"$G" --path "$P" --resolution 1280x860 --script res://addons/dot_rigger/tools/ui_smoke_cli.gd       # ③ 에디터 창 전체
"$G" --path "$P" --resolution 400x300  --script res://addons/dot_rigger/tools/rootbone_check_cli.gd # ④ 파트 피벗
"$G" --path "$P" --resolution 400x300  --script res://addons/dot_rigger/tools/drift_check_cli.gd    # ⑤ 자세 고정
```

**PowerShell**
```powershell
$G = "C:\<경로>\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe"
$P = "C:\<경로>\1941"
& $G --path $P --resolution 1280x860 --script res://addons/dot_rigger/tools/ui_smoke_cli.gd
```

| 도구 | 성공 기준 | 2026-09-14 결과 |
|---|---|---|
| ① `--import` | 출력에 `SCRIPT ERROR` / `Parse Error` 없음 | 0건 |
| ② `bake_cli --diag` | 본 65개 → 15파트, `(미매핑)` 없음 | ✓ |
| ③ `ui_smoke_cli` | 마지막 줄 `스모크 테스트 전부 통과`, 종료 코드 0 | ✓ (`puppet_test/` **없는 상태**에서 실행 = 새 clone 과 같은 조건) |
| ④ `rootbone_check_cli` | `모든 파트의 루트 본 정상` (Hips = pelvis) | ✓ |
| ⑤ `drift_check_cli` | `포즈 고정 OK` | ✓ |
| `bake_cli` → `preview_cli` | `결과: { "ok": true ... }` → 구운 씬이 트랙 60개로 재생 | ✓ |
| `compare_cli` | 3D 렌더 대비 2D 순서 합성 불일치 %. 합격선 없음, **각도 비교용** | 사용자 각도 yaw −55° · 184px → **4.3%** |

주의
- ③은 `--resolution` 이 툴 창(1000×700)보다 커야 한다. 작으면 창 캡처가 잘려 16번 배치 검사가 실패한다.
- ③ 실행 중 `ERROR: Class type: 'EditorFileDialog' is not instantiable` 이 찍히는 건 정상(에디터 밖이라 일반 FileDialog 로 떨어지는 경로를 검사하는 것).
- `preview_cli` · `equip_test_cli` 는 `bake_cli` 를 먼저 돌려 `puppet_test/puppet.tscn` 이 있어야 한다. `equip_test_cli` 는 장비 PNG(`--tex=`)가 필요 — 아무 작은 PNG 면 된다.
- 에디터의 **`베이크` 버튼 경로**는 자동 테스트에 없다. 대신 사용자 `puppet/puppet.tscn` 이 임포트된 `Texture2D` 15개를 참조하고 있어(=`rebuild_scene()` 까지 정상 완료) 동작은 확인됐다.

---

## 현재 상태 (2026-09-14)

### 된 것
- 본 웨이트 기반 파트 분리(UAL1 → 15파트) + 관절 겹침 링
- 고정 각도 렌더 + 도트 셰이더(명암 계단화) · 자동 맞춤 · 해상도/슈퍼샘플/알파 임계/색 양자화
- 3D 애니메이션 → 2D 커브 자동 생성 (각도 펴기 · 루프 닫기 · 단축 보정)
- `puppet.tscn` 생성 + 장비 런타임(`DRPuppet` / `DREquipItem`)
- 에디터 창
  - 프리셋 저장/불러오기(`.tres`)
  - 프리뷰 **3D / 2D 순서** 두 모드, 두 모드 모두 `▶ 재생`
  - 확대/이동(휠·가운데·우클릭 드래그, 정수 배율)
  - 그리기 순서 자동/수동, Shift·Ctrl 다중 선택, **선택한 파트만 프리뷰**
  - 파트 트리 · `◀ 전체 보기` · 실루엣 채움 % 표시
- 검증 도구 7종

### 사용자 작업 설정 (`UAL1_preset.tres`)
yaw **−55°**, pitch 0 · 자동 맞춤 **끔** · 여백 0 · 해상도 **184px** · 레스트 포즈 `Idle` · 그리기 순서 **수동**(뒤→앞: L_Foot, L_Thigh, L_Calf, L_UpperArm, L_Hand, L_Forearm, Head, Torso, Hips, R_Hand, R_Foot, R_Forearm, R_Thigh, R_UpperArm, R_Calf) · 내보낼 애니메이션 없음

### 결과물 유효성
**2026-09-09 17:36 이전에 구운 결과물은 무효**(자세 드리프트·힙 루트 본 버그 — [02 §0](02_버그와_교훈.md)). 사용자 `puppet/`(09-11)은 그 이후라 유효.

---

## 남은 일

1. **장비 3D 베이크 모드** — 지금은 런타임 부착만 된다(검증에 쓴 헬멧 PNG 는 손으로 만든 것). 캐릭터와 같은 카메라(`rig.json` 의 `view` → `DRBaker.apply_view()`)·같은 레스트 포즈로 장비 메쉬를 구워 `DREquipItem`(오프셋 자동 계산 포함)을 만드는 흐름이 필요하다.
2. **각도 확정** — 09-14 재측정 결과 3D 대비 불일치는 각도별 **4.3~5.9%** 로 큰 차이가 없다(정측면 4.6% · −45° 5.9% · 사용자 −55° 4.3% · −65° 5.5%). 이전의 "정측면이 확실히 유리, −65° 는 22%" 는 자세 드리프트 버그가 섞인 틀린 값이었다([02 §7](02_버그와_교훈.md#7-측정값-모음-근거)). 단 이 수치는 **레스트 정지 자세의 그리기 순서**만 본 것이라, 팔 단축률은 각도마다 베이크의 `[단축률 진단]` 으로 따로 확인할 것.
3. **도트화 품질** — 아웃라인 패스, 팔레트 LUT (지금 색 양자화는 단순 계단).
4. **파트 프로필 확장** — 탱크·중장비. `core/part_profile.gd` 규칙 배열만 추가하면 된다.
5. **재생할 애니 따로 고르기** — 프리뷰 재생은 "레스트 포즈로 고른 애니"를 돌린다. 바꾸면 파트 이미지도 그 애니의 해당 시점으로 다시 찍힌다.
6. **보류 중인 제안**(사용자 결정 대기) — 마지막 프리셋 자동 불러오기 / 여백을 해상도에 비례.
7. 원리적 한계(깊이 회전 · 도트+회전 · 스프라이트 단위 정렬)는 애드온 README "알려진 한계".

---

## 새 Claude 세션이라면

- 이 문서 → 01 → 02 순서로 읽는다. Claude 메모리는 PC마다 따로라 **이 문서들이 원본**이다.
- 작업 규칙은 [02 §6](02_버그와_교훈.md#6-이-작업-환경의-규칙) (`sed -i` 금지 등).
- 코드를 고치면 ③ 스모크 테스트를 돌리고, 버그를 잡으면 02 문서에 한 항목 추가한다.
- UI 를 건드렸다면 ③의 16번(창 밖 / 너무 작음 / 목록 스크롤) 결과를 꼭 본다.
