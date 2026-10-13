extends RefCounted

## 시험용 전장 — 논리 검사(sim_smoke.gd)와 전투 시험장(battle_test.tscn)이 같이 쓴다.
## 양쪽이 대칭: 가운데에 참호(양쪽 벽 · 높음), 그 앞뒤로 모래주머니(적 쪽에만 벽 · 낮음).
## 나중에 엄폐물을 씬에 직접 놓는 방식(노드 + 인스펙터)으로 바뀌면 이 파일은 시험 전용으로만 남는다.


static func build(bf: Battlefield) -> void:
	bf.length_m = 120.0
	var low := BattleCover.Kind.LOW
	var high := BattleCover.Kind.HIGH
	bf.add_cover(18.0, 20.5, low, 1)        # 왼쪽편용 — 벽이 +x 쪽(적 쪽)
	bf.add_cover(34.0, 36.5, low, 1)
	bf.add_cover(48.0, 50.5, low, 1)
	bf.add_cover(57.5, 62.5, high, 0, 8)    # 가운데 참호 — 먼저 차지한 편이 쓴다
	bf.add_cover(69.5, 72.0, low, -1)       # 오른쪽편용 — 벽이 −x 쪽
	bf.add_cover(83.5, 86.0, low, -1)
	bf.add_cover(99.5, 102.0, low, -1)
