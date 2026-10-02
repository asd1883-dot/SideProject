@tool
extends RefCounted
class_name DRPartOverrides

## 부위 칠하기 — 정점을 어느 파트(조각)로 자를지 사람이 정해 둔 것. 모델 옆 `<모델 이름>.parts.json`.
##
## 굽기 도구는 정점마다 웨이트가 가장 센 뼈의 파트로 조각을 자른다(DRMeshSplitter). 옷이 입혀진 한 덩어리 몸은
## 그 경계가 사람이 원하는 자리와 다를 수 있다(상의 자락이 골반 조각으로, 깃이 머리 조각으로 …).
## 여기 적힌 정점은 웨이트 대신 적힌 파트로 간다 — 메인 창 세트 굽기 · 복장 굽기 모두 같은 파일을 따른다.
## 3D 변형(웨이트)은 바꾸지 않는다. 어느 조각 그림에 들어가는지만 바꾼다.
##
## 키 = 정점의 바인드 자세 위치(메시 공간)를 0.1 mm 로 반올림한 값 — 텍스처 이음매로 나뉜 같은 자리 정점은 같이 바뀐다.
## 같은 원본 · 같은 붙이기 설정으로 다시 붙이면 위치가 같아 칠한 것이 그대로 맞는다.

const SCALE := 10000.0

var model_path := ""
var map: Dictionary = {}   # Vector3i -> 파트 이름


static func key_of(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x * SCALE), roundi(p.y * SCALE), roundi(p.z * SCALE))


## 모델 경로 → 칠하기 파일 경로 (res://a/b/uniform_m36.glb → res://a/b/uniform_m36.parts.json)
static func path_for(p_model_path: String) -> String:
	return p_model_path.get_basename() + ".parts.json"


## 모델 옆 칠하기 파일을 읽는다. 없으면 빈 것(아무것도 안 바꿈)
static func load_for(p_model_path: String) -> DRPartOverrides:
	var o := DRPartOverrides.new()
	o.model_path = p_model_path
	if p_model_path == "":
		return o
	var jp := path_for(p_model_path)
	if not FileAccess.file_exists(jp):
		return o
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(jp))
	if not (v is Dictionary):
		push_warning("[DotRigger] 부위 칠하기 파일을 읽을 수 없습니다: %s" % jp)
		return o
	for e in (v as Dictionary).get("points", []):
		var a: Array = e
		if a.size() >= 4:
			o.map[Vector3i(int(a[0]), int(a[1]), int(a[2]))] = String(a[3])
	return o


func save() -> bool:
	if model_path == "":
		return false
	var pts: Array = []
	for k in map.keys():
		var kk: Vector3i = k
		pts.append([kk.x, kk.y, kk.z, String(map[k])])
	var d := {"version": 1, "model": model_path, "note": "Dot Rigger 부위 칠하기 — 정점(바인드 자세 위치 × %d, 정수) → 파트" % int(SCALE), "points": pts}
	var f := FileAccess.open(path_for(model_path), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	return true


func part_at(p: Vector3) -> String:
	return String(map.get(key_of(p), ""))


## part 가 "" 면 칠한 것을 지운다(웨이트대로)
func set_part(p: Vector3, part: String) -> void:
	var k := key_of(p)
	if part == "":
		map.erase(k)
	else:
		map[k] = part


func size() -> int:
	return map.size()


func is_empty() -> bool:
	return map.is_empty()
