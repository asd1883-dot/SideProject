extends Node2D
class_name DRDotView3D

## 2D 캔버스 안에 놓이는 "3D 창" — 3D 캐릭터를 저해상도(도트)로 그려, 2D 로 그린 땅 · 판정 상자 · 글자와 같은 좌표에 끼워 넣는다.  (10-15)
##
## 왜: 2D 컷아웃 굽기는 동작 · 옷 · 무기 조합마다 그림을 구워야 해서 리소스 관리가 감당이 안 됐다. 그래서 3D 캐릭터를 게임에
##     바로 쓰고, 도트 느낌(굵은 도트 · 계단 명암 · 1 도트 외곽선)은 이 창이 화면 단계에서 만든다.
##
## 구조(창 하나 = 3D 렌더 한 번 — 병사가 100 명이어도 렌더 1 번 + 선 패스 1 번 + 2D 사각형 1 장):
##   DRDotView3D (이 노드, _draw 에서 결과 텍스처를 nearest 로 화면 크기만큼 늘려 그린다)
##   └ SubViewport  자기 World3D · 투명 배경 · 해상도 = 보이는 화면 픽셀 / dot_px (+ 여유)
##      ├ World     ← world. 게임이 캐릭터를 여기에 add_child 한다
##      └ Camera3D  직교. −Z 를 보며 pitch_deg 만큼 내려다본다
##         └ Edges  화면 쿼드(shaders/dot_edges.gdshader) — 바깥 외곽선 + 겹친 캐릭터 사이 선
##
## 좌표 계약: 3D 점 P 는 이 노드의 로컬 캔버스 좌표
##     origin + Vector2(P.x · s, −(P.y · cos θ − P.z · sin θ) · s),   θ = pitch_deg,  s = px_per_m / cos θ
##   에 그려진다. +X = 오른쪽, +Y = 위(높이 1 m = px_per_m px), +Z = 화면 앞쪽(아래로 1 m 당 tan θ · px_per_m px).
##   병사 자리 = ground_to_world(전장의 캔버스 자리) — 깊이가 3D Z 가 되어 앞 병사가 뒤 병사를 깊이 버퍼로 가린다(z 띠 정렬이 필요 없다).
##   가로 1 m 는 s 라 세로(px_per_m)보다 1/cos θ 배 넓게 보인다(15° 에서 3.5 %). 2D 쪽 x 1 m 는 3D 로 cos θ m 다.
##
## 도트 떨림 막기: 카메라 중심을 캔버스의 도트 격자(도트 = dot_px / 화면 배율)에 스냅하고, 그리는 사각형은 실제 화면 픽셀에 스냅한다.
##   화면이 한 도트보다 덜 움직이면 3D 렌더가 그대로이고, 한 도트를 넘으면 그림 전체가 정확히 한 도트 밀린다(평행 이동만).
##   카메라 스냅은 그림 자리도 같은 격자로 옮기므로 어긋남을 만들지 않는다. 남는 어긋남은 화면 픽셀 스냅(≤ 0.5 px)과
##   도트로 찍히는 양자화(물체 경계 ≤ 반 도트)뿐 — 실측 최대 0.63 도트(시험: test/dot_view_3d_demo.gd, 10-15).
##
## 그리기 순서는 이 노드의 z_index 를 따른다(땅 · 엄폐물보다 앞, 상자 · 글자보다 뒤에 둔다).
## 화면을 움직이는 코드(Camera2D)보다 늦게 돌아야 보이는 범위를 정확히 덮어서 process_priority 를 크게 잡아 둔다(1000).

## 내려다보는 각(도). 0 이면 깊이가 화면에 안 나타나 땅 자리 → 3D 를 풀 수 없어 1 ~ 89 로 묶는다
@export_range(1.0, 89.0, 0.5) var pitch_deg := 15.0:
	set(v):
		pitch_deg = clampf(v, 1.0, 89.0)
## 높이 1 m 가 캔버스 몇 px 인가 — 게임의 ppm 과 같게
@export var px_per_m := 40.0
## 3D 원점(0, 0, 0)이 그려지는 캔버스 자리. 전투 화면은 Vector2(0, ground_y) 를 주면 깊이 0.5 가 Z 0 이 된다
@export var origin := Vector2.ZERO
## 도트 하나 = 실제 화면 몇 픽셀. 정수라 도트 크기가 들쭉날쭉하지 않다. 화면 기준이라 확대해도 도트 크기는 같고
## 대신 캐릭터가 더 촘촘해진다. 1 = 도트화 끔
@export_range(1, 8) var dot_px := 2
## 외곽선 두께(도트). 0 = 선 없음(바깥 · 안쪽 모두) · 1 = 1 도트
@export_range(0, 1) var outline_px := 1:
	set(v):
		outline_px = clampi(v, 0, 1)
		_apply_lines()
## 선의 색 방식 — 0 = 카툰(outline_color 한 색) · 1 = 픽셀 퍼펙트(선 도트마다 바로 옆 몸 도트 색을 outline_tone 만큼 어둡게)
@export_enum("카툰 (한 색)", "픽셀 퍼펙트 (옆 도트 색의 톤)") var outline_style := 1:
	set(v):
		outline_style = clampi(v, 0, 1)
		_apply_lines()
@export var outline_color := Color(0.07, 0.06, 0.06, 1.0):
	set(v):
		outline_color = v
		_apply_lines()
## 픽셀 퍼펙트일 때 어둡게 하는 정도(0 = 같은 색 · 1 = 검정). 2D 퍼펫과 같은 기본 0.45
@export_range(0.0, 1.0, 0.05) var outline_tone := 0.45:
	set(v):
		outline_tone = v
		_apply_lines()
## 겹친 캐릭터 사이에도 선을 긋는다(앞 캐릭터 실루엣을 따라 뒤 캐릭터 쪽에 1 도트)
@export var inner_outline := true:
	set(v):
		inner_outline = v
		_apply_lines()
## 안쪽 선이 생기는 깊이 차(m, 카메라가 보는 방향). 한 몸의 팔다리 겹침(0.2 ~ 0.4 m)보다 크게 — 너무 작으면 몸 안에 선이 생긴다
@export_range(0.05, 5.0, 0.05) var inner_gap_m := 0.5:
	set(v):
		inner_gap_m = v
		_apply_lines()
## 도트 격자 스냅(끄면 화면이 움직일 때 도트가 떨린다 — 비교 시험용)
@export var snap_to_dots := true

@export_group("명암 (dot_flat)")
## apply_dot_material() 로 입힌 재질 전부에 같이 들어간다(바꾸면 이미 입힌 캐릭터도 바로 바뀐다). 값의 뜻은 shaders/dot_flat.gdshader
@export var light_dir := Vector3(-0.4, 0.7, 0.6):
	set(v):
		light_dir = v
		_apply_light_all()
@export_range(2, 8) var light_bands := 3:
	set(v):
		light_bands = v
		_apply_light_all()
@export_range(0.0, 1.0, 0.05) var light_ambient := 0.45:
	set(v):
		light_ambient = v
		_apply_light_all()
@export_range(0.0, 1.0, 0.05) var light_wrap := 0.25:
	set(v):
		light_wrap = v
		_apply_light_all()

const EDGES_SHADER := preload("res://addons/dot_rigger/shaders/dot_edges.gdshader")
const DOT_FLAT_SHADER := preload("res://addons/dot_rigger/shaders/dot_flat.gdshader")
## 카메라를 화면 평면(원점을 지나는)에서 이만큼 뒤로 뺀다(m). 그 앞뒤 ±이만큼 안의 물체가 그려진다
const CAM_BACK_M := 250.0
## 보이는 사각형 밖으로 더 그리는 도트 — 스냅으로 밀리는 0.5 도트 + 외곽선 1 도트(가장자리 선이 잘리지 않게) + 여유
const MARGIN_DOTS := 4
## 뷰포트 크기를 이 배수로 올린다 — 창 크기가 조금씩 바뀔 때 렌더 타깃을 매번 새로 만들지 않게(짝수라 가운데가 도트 경계)
const SIZE_STEP := 8

## 3D 내용을 넣는 곳 — 게임이 캐릭터를 여기에 add_child 한다(읽기 전용)
var world: Node3D:
	get:
		return _world
	set(_v):
		push_warning("DRDotView3D.world 는 읽기 전용입니다 — world.add_child() 로 넣으세요")

var _vp: SubViewport
var _world: Node3D
var _cam: Camera3D
var _edges: MeshInstance3D
var _edges_mat: ShaderMaterial
var _rect := Rect2()                 # 결과 텍스처를 그리는 자리(로컬)
var _dot := 1.0                      # 지금 도트 하나 = 캔버스 몇 단위
var _mats: Dictionary = {}           # 원래 재질 instance id -> dot_flat ShaderMaterial(같은 재질은 하나를 같이 쓴다)


func _init() -> void:
	process_priority = 1000
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_vp = SubViewport.new()
	_vp.name = "DotViewport"
	_vp.own_world_3d = true
	_vp.world_3d = World3D.new()
	_vp.transparent_bg = true
	# 도트가 섞이지 않게: 안티에일리어싱 · 디더 · 그림자 없음
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_vp.use_taa = false
	_vp.use_debanding = false
	_vp.positional_shadow_atlas_size = 0
	_vp.gui_disable_input = true
	_vp.handle_input_locally = false
	_vp.size = Vector2i(SIZE_STEP, SIZE_STEP)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp, false, Node.INTERNAL_MODE_FRONT)

	_world = Node3D.new()
	_world.name = "World"
	_vp.add_child(_world)

	_cam = Camera3D.new()
	_cam.name = "Camera"
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.near = 0.05
	_cam.far = CAM_BACK_M * 2.0
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR     # unshaded 색이 그대로 나오게(baker 와 같다)
	_cam.environment = env
	_vp.add_child(_cam)
	_cam.current = true

	# 선 패스: 카메라에 붙은 화면 쿼드. 정점 셰이더가 화면 전체로 펴므로 컬링에 걸리지 않게 여유를 크게 준다
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_edges_mat = ShaderMaterial.new()
	_edges_mat.shader = EDGES_SHADER
	_edges_mat.render_priority = Material.RENDER_PRIORITY_MAX
	_edges = MeshInstance3D.new()
	_edges.name = "Edges"
	_edges.mesh = quad
	_edges.material_override = _edges_mat
	_edges.extra_cull_margin = 16384.0
	_edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_edges.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_edges.position = Vector3(0.0, 0.0, -1.0)
	_cam.add_child(_edges)
	_apply_lines()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE or what == NOTIFICATION_VISIBILITY_CHANGED:
		# 숨기면 3D 렌더도 멈춘다(캐릭터 애니는 계속 돈다 — 멈추려면 world.process_mode 를 바꾼다)
		if _vp != null and is_inside_tree():
			_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		_sync()


func _draw() -> void:
	if _rect.size.x > 0.0 and _rect.size.y > 0.0:
		draw_texture_rect(_vp.get_texture(), _rect, false)


# ───────────── 바깥에서 부르는 것 ─────────────

## 3D 점 → 이 노드의 로컬 캔버스 좌표(좌표 계약 그대로)
func world_to_canvas(p: Vector3) -> Vector2:
	var th := deg_to_rad(pitch_deg)
	return origin + Vector2(p.x / cos(th), p.z * tan(th) - p.y) * px_per_m


## 높이 height(m)인 수평면 위에서, 캔버스 점 canvas 에 그려지는 3D 점. 병사 자리 = ground_to_world(to_canvas(x, 0, 깊이))
func ground_to_world(canvas: Vector2, height: float = 0.0) -> Vector3:
	var th := deg_to_rad(pitch_deg)
	var d := canvas - origin
	return Vector3(d.x * cos(th) / px_per_m, height, (d.y / px_per_m + height) / tan(th))


## 지금 도트 하나가 캔버스(이 노드 로컬) 몇 단위인가 — 화면 확대율에 따라 바뀐다
func get_dot_size() -> float:
	return _dot


## 지금 결과 텍스처를 그리는 사각형(로컬) — 확인용
func get_draw_rect() -> Rect2:
	return _rect


## 안의 SubViewport(렌더 결과 확인 · 설정용)
func get_subviewport() -> SubViewport:
	return _vp


## root 아래 모든 MeshInstance3D 에 도트 명암 재질(shaders/dot_flat.gdshader)을 입힌다. 명암 값은 이 창의 light_* 를 따른다.
## 원래 재질이 같으면 재질 하나를 같이 쓴다(같은 모델 병사 100 명 = 재질 1 개 — 그리기 상태 전환이 적다).
func apply_dot_material(root: Node) -> void:
	var list: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D:
		list.append(root)
	for n in list:
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for si in mi.mesh.get_surface_count():
			mi.set_surface_override_material(si, _dot_material_for(mi.get_active_material(si)))


# ───────────── 안쪽 ─────────────

## 보이는 범위 · 화면 배율에 맞춰 뷰포트 크기 · 카메라 · 그리는 자리를 맞춘다(매 프레임)
func _sync() -> void:
	var cxf := get_global_transform_with_canvas()                 # 로컬 → 뷰포트 2D 좌표
	var fxf := get_viewport().get_final_transform() * cxf          # 로컬 → 실제 화면 픽셀(창 스트레치까지)
	var k := fxf.x.length()                                        # 실제 화면 픽셀 / 로컬 단위
	if k < 0.000001 or px_per_m <= 0.0:
		return
	var d := float(maxi(dot_px, 1)) / k                            # 도트 하나 = 로컬 몇 단위
	var vis := cxf.affine_inverse() * get_viewport_rect()          # 지금 보이는 범위(로컬)
	var c := vis.get_center()
	var q := c
	if snap_to_dots:
		q = Vector2(roundf(c.x / d) * d, roundf(c.y / d) * d)       # 카메라 중심을 도트 격자에
	var w := _round_up(ceili(vis.size.x / d) + MARGIN_DOTS * 2)
	var h := _round_up(ceili(vis.size.y / d) + MARGIN_DOTS * 2)
	var want := Vector2i(w, h)
	if _vp.size != want:
		_vp.size = want
	var rect := Rect2(q - Vector2(w, h) * d * 0.5, Vector2(w, h) * d)
	if snap_to_dots:
		# 그림의 도트 경계를 실제 화면 픽셀 경계에 — 픽셀 가운데가 도트 경계에 걸려 도트 폭이 1 · 3 px 로 갈라지지 않게(≤ 0.5 px 이동)
		rect.position = fxf.affine_inverse() * (fxf * rect.position).round()
	_dot = d
	var th := deg_to_rad(pitch_deg)
	var ct := cos(th)
	var st := sin(th)
	var s := px_per_m / ct
	_cam.size = float(h) * d / s
	# q 에 그려지는 점 중 Z = 0 인 것 + 카메라 뒤쪽(0, sin θ, cos θ)으로 CAM_BACK_M — 이 축으로 옮겨도 화면 자리는 같다
	var p0 := Vector3((q.x - origin.x) / s, -(q.y - origin.y) / (s * ct), 0.0)
	_cam.transform = Transform3D(Basis(Vector3.RIGHT, -th), p0 + Vector3(0.0, st, ct) * CAM_BACK_M)
	if rect != _rect:
		_rect = rect
		queue_redraw()


func _round_up(n: int) -> int:
	return ceili(float(n) / float(SIZE_STEP)) * SIZE_STEP


func _apply_lines() -> void:
	if _edges_mat == null or _edges == null:
		return
	_edges.visible = outline_px > 0
	_edges_mat.set_shader_parameter("style", outline_style)
	_edges_mat.set_shader_parameter("line_color", outline_color)
	_edges_mat.set_shader_parameter("tone", outline_tone)
	_edges_mat.set_shader_parameter("inner", inner_outline)
	_edges_mat.set_shader_parameter("inner_gap", inner_gap_m)


func _dot_material_for(src: Material) -> ShaderMaterial:
	if src is ShaderMaterial and (src as ShaderMaterial).shader == DOT_FLAT_SHADER:
		return src as ShaderMaterial          # 이미 입힌 것
	var key := src.get_instance_id() if src != null else 0
	if _mats.has(key):
		return _mats[key] as ShaderMaterial
	var sm := ShaderMaterial.new()
	sm.shader = DOT_FLAT_SHADER
	var col := Color(0.8, 0.8, 0.8, 1.0)
	if src is BaseMaterial3D:
		var bm := src as BaseMaterial3D
		col = bm.albedo_color
		if bm.albedo_texture != null:
			sm.set_shader_parameter("albedo_tex", bm.albedo_texture)
			sm.set_shader_parameter("use_tex", true)
	sm.set_shader_parameter("albedo_color", col)
	_apply_light(sm)
	_mats[key] = sm
	return sm


func _apply_light(sm: ShaderMaterial) -> void:
	sm.set_shader_parameter("light_dir", light_dir)
	sm.set_shader_parameter("bands", light_bands)
	sm.set_shader_parameter("ambient", light_ambient)
	sm.set_shader_parameter("light_wrap", light_wrap)


func _apply_light_all() -> void:
	for m in _mats.values():
		_apply_light(m as ShaderMaterial)
