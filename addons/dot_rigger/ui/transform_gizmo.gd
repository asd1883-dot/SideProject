@tool
extends Control

## 유니티식 변환 기즈모(10-16) — 3D 미리보기(SubViewportContainer, stretch) 위에 겹친 2D 층. ② 장비 탭이 쓴다(class_name 없이 preload —
## 에디터를 다시 켜지 않고 "개발 내용 갱신"만으로 바뀐다).
## 사용자(10-16): "2탭 장비에 기즈모 조작으로 인한 적용 기능도 부탁해. 단축키는 유니티 기즈모와 동일."
##   이동(W): 축 화살표 · 평면 네모(카메라 쪽 사분면으로 뒤집힘) · 가운데 네모 = 화면 평면
##   회전(E): 축 고리(앞쪽 반만 진하게) · 바깥 고리 = 화면 축 · 안쪽 = 자유(트랙볼)
##   크기(R): 축 끝 네모(늘 로컬 축) · 가운데 = 전체(오른쪽 · 위로 끌면 커짐)
##   변환(Y): 이동 + 회전 고리 + 가운데 = 전체 크기. 보기(Q): 손잡이 없음(왼쪽 끌기는 카메라)
##   Ctrl 누르고 끌기 = 눈금(snap_*) · 끄는 중 오른쪽 누름 = 취소. 손잡이 크기는 화면 기준(멀어져도 같은 크기 — 유니티와 같음).
##   단축키(Q W E R Y · X 로컬/글로벌 · Z 피벗/중심 · F)는 페이지가 받아 이 칸들을 바꾼다.
## target(미리보기 사본의 노드)을 끄는 동안 바로 옮기고 transform_changed, 놓으면 transform_end(끌기 전 로컬 변환) —
## 페이지가 그 값을 진짜 노드(유닛 씬)에 되돌리기 한 칸으로 넣는다. 그리기 · 고르기는 화면 좌표, 끌기 계산은 3D(광선 ↔ 평면).
## 기즈모가 아닌 곳의 입력은 view_input(카메라)으로, 끌지 않고 누른 뒤 뗀 것은 clicked(노드 고르기)로 넘긴다.

signal transform_begin(node: Node3D)
signal transform_changed(node: Node3D)
signal transform_end(node: Node3D, before: Transform3D)
signal clicked(pos: Vector2)
signal view_input(ev: InputEvent)

enum Tool { VIEW, MOVE, ROTATE, SCALE, TRANSFORM }
## 손잡이 — 축 · 평면 · 고리는 x · y · z 차례로 붙어 있다(H.AX + k)
enum H { NONE, AX, AY, AZ, PYZ, PXZ, PXY, FREE, RX, RY, RZ, RVIEW, RFREE, SX, SY, SZ, SALL }

const TOOL_NAMES := ["보기", "이동", "회전", "크기", "변환"]
const COL := [Color(0.93, 0.27, 0.22), Color(0.53, 0.84, 0.24), Color(0.27, 0.56, 0.98)]
const COL_HOT := Color(1.0, 0.89, 0.18)
const COL_VIEW := Color(0.86, 0.87, 0.9)
const SIZE_PX := 84.0          # 축 길이 · 회전 고리 반지름(화면 픽셀)
const AXIS_MIN_PX := 25.0      # 화면에서 이보다 짧은 축(카메라를 거의 보는 축)은 숨기고 못 잡는다
const AXIS_STEEP := 0.85       # 축 · 시선 cos 가 이보다 크면 축 이동을 화면 거리로(광선 ↔ 평면 교점이 튀지 않게)
const VIEW_RING := 1.12        # 바깥 고리 = SIZE_PX ×
const PICK_PX := 7.0
const CLICK_PX := 4.0          # 이만큼 안 움직이고 떼면 누름(고르기)
const RING_N := 64

var camera: Camera3D
var target: Node3D = null
var tool_mode: int = Tool.MOVE
var local_space := true        # X — 손잡이 방향: 로컬(노드 축) ↔ 글로벌(세상 축)
var pivot_mode := true         # Z — 기즈모 자리: 피벗(노드 원점) ↔ 중심(보이는 메시 경계 상자 가운데)
var allow_scale := true        # 왼손 표지처럼 크기가 뜻이 없는 노드는 끈다
var snap_move := 0.01          # m
var snap_rotate := 15.0        # °
var snap_scale := 0.1          # 배율

var _hot: int = H.NONE
var _drag: int = H.NONE
var _drag_node: Node3D = null
var _press := Vector2.ZERO
var _moved := false
var _view_drag := false
# 끌기를 시작할 때 잡아 두는 것(끄는 동안 기준)
var _start_local := Transform3D.IDENTITY
var _start := Transform3D.IDENTITY
var _parent := Transform3D.IDENTITY
var _o := Vector3.ZERO
var _axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
var _plane := Plane()
var _hit0 := Vector3.ZERO
var _tan := Vector2.RIGHT
var _raxis := Vector3.UP
var _rot := Basis.IDENTITY
var _ang := 0.0
var _last := Vector2.ZERO
var _c2 := Vector2.ZERO
var _sdir: Array[Vector2] = [Vector2.RIGHT, Vector2.RIGHT, Vector2.RIGHT]
var _slen: Array[float] = [1.0, 1.0, 1.0]
var _axis_screen := false      # 축 이동을 화면 거리로(축이 카메라 쪽으로 기움)
var _axis_dir := Vector2.RIGHT
var _axis_ppm := 1.0           # 그 축의 화면 픽셀 / m


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK
	set_anchors_preset(Control.PRESET_FULL_RECT)


func is_dragging() -> bool:
	return _drag != H.NONE


func _ok() -> bool:
	return camera != null and is_instance_valid(camera) and target != null and is_instance_valid(target) \
		and target.is_inside_tree() and tool_mode != Tool.VIEW


# ---------------------------------------------------------------- 자리 · 축

## 기즈모 자리(세상) — 피벗 = 노드 원점, 중심 = 보이는 메시 경계 상자 가운데(메시가 없으면 원점)
func pivot_point() -> Vector3:
	if pivot_mode:
		return target.global_position
	var bb := world_aabb(target)
	return bb.get_center() if bb.size != Vector3.ZERO else target.global_position


## 노드와 그 아래의 보이는 메시를 모두 덮는 세상 경계 상자(없으면 크기 0)
static func world_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is Node3D and not (c as Node3D).visible:
			continue
		stack.append_array(c.get_children())
		var mi := c as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var bb := mi.global_transform * mi.get_aabb()
		out = bb if first else out.merge(bb)
		first = false
	return out


## 손잡이 축(세상, 단위) — 크기는 늘 로컬(유니티와 같음)
func _axes_now(scale_axes: bool) -> Array[Vector3]:
	if local_space or scale_axes:
		var b := target.global_transform.basis
		return [b.x.normalized(), b.y.normalized(), b.z.normalized()]
	return [Vector3.RIGHT, Vector3.UP, Vector3.BACK]


## 그 깊이에서 화면 1 픽셀 = 세상 몇 m
func _wpp(p: Vector3) -> float:
	var h := maxf(float(camera.get_viewport().get_visible_rect().size.y), 1.0)
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL:
		return camera.size / h
	var depth := (p - camera.global_position).dot(-camera.global_basis.z)
	return 2.0 * maxf(depth, 0.01) * tan(deg_to_rad(camera.fov) * 0.5) / h


func _p(w: Vector3) -> Vector2:
	return camera.unproject_position(w)


## 평면 손잡이 네모 — 축 i · j 사이, 카메라 쪽 사분면
func _plane_quad(o: Vector3, ax: Array[Vector3], i: int, j: int, l: float) -> PackedVector2Array:
	var to_cam := camera.global_position - o
	var si := 1.0 if ax[i].dot(to_cam) >= 0.0 else -1.0
	var sj := 1.0 if ax[j].dot(to_cam) >= 0.0 else -1.0
	var pts := PackedVector2Array()
	for uv: Vector2 in [Vector2(0.12, 0.12), Vector2(0.34, 0.12), Vector2(0.34, 0.34), Vector2(0.12, 0.34)]:
		pts.append(_p(o + ax[i] * (si * uv.x * l) + ax[j] * (sj * uv.y * l)))
	return pts


## 축 k 둘레 고리의 점들 — [화면 점, 앞쪽인가, θ]. θ 가 늘면 축 둘레 오른손 방향(u → v)
func _ring(o: Vector3, ax: Array[Vector3], k: int, r: float) -> Array:
	var u := ax[(k + 1) % 3]
	var v := ax[(k + 2) % 3]
	var to_cam := (camera.global_position - o).normalized()
	var out := []
	for s in RING_N + 1:
		var th := TAU * float(s) / RING_N
		var d := u * cos(th) + v * sin(th)
		out.append([_p(o + d * r), d.dot(to_cam) >= -0.02, th])
	return out


func _plane_ok(ax: Array[Vector3], k: int, o: Vector3) -> bool:
	return absf(ax[k].dot((camera.global_position - o).normalized())) >= 0.15     # 평면이 거의 옆으로 누우면 안 그림


# ---------------------------------------------------------------- 그리기

func _draw() -> void:
	if not _ok():
		return
	var o := pivot_point()
	if camera.is_position_behind(o):
		return
	var o2 := _p(o)
	var l := SIZE_PX * _wpp(o)
	var hot := _drag if _drag != H.NONE else _hot
	match tool_mode:
		Tool.MOVE:
			_draw_move(o, o2, l, hot, true)
		Tool.ROTATE:
			_draw_rotate(o, o2, l, hot, true)
		Tool.SCALE:
			if allow_scale:
				_draw_scale(o, o2, l, hot)
		Tool.TRANSFORM:
			_draw_rotate(o, o2, l, hot, false)
			_draw_move(o, o2, l, hot, false)
			if allow_scale:
				draw_rect(Rect2(o2 - Vector2(6, 6), Vector2(12, 12)), COL_HOT if hot == H.SALL else Color(COL_VIEW, 0.9))


func _draw_move(o: Vector3, o2: Vector2, l: float, hot: int, center: bool) -> void:
	var ax := _axes_now(false)
	for k in 3:
		if not _plane_ok(ax, k, o):
			continue
		var q := _plane_quad(o, ax, (k + 1) % 3, (k + 2) % 3, l)
		var on := hot == H.PYZ + k
		var c: Color = COL_HOT if on else COL[k]
		draw_colored_polygon(q, Color(c, 0.6 if on else 0.3))
		draw_polyline(q + PackedVector2Array([q[0]]), Color(c, 0.9), 1.0, true)
	for k in 3:
		var tip := _p(o + ax[k] * l)
		var v := tip - o2
		if v.length() < AXIS_MIN_PX:
			continue                            # 축이 카메라를 거의 똑바로 봄(유니티도 숨김 — 끌면 조금만 움직여도 멀리 튄다)
		var on := hot == H.AX + k
		var c: Color = COL_HOT if on else COL[k]
		draw_line(o2, tip, c, 2.5 if on else 2.0, true)
		var d := v.normalized()
		var n := d.orthogonal() * 5.5
		draw_colored_polygon(PackedVector2Array([tip + d * 12.0, tip + n, tip - n]), c)
	if center:
		draw_rect(Rect2(o2 - Vector2(6, 6), Vector2(12, 12)), COL_HOT if hot == H.FREE else Color(COL_VIEW, 0.95), false, 1.5)


func _draw_rotate(o: Vector3, o2: Vector2, l: float, hot: int, outer: bool) -> void:
	var ax := _axes_now(false)
	if outer and hot == H.RFREE:
		draw_circle(o2, SIZE_PX, Color(1, 1, 1, 0.08))
	for k in 3:
		var on := hot == H.RX + k
		var c: Color = COL_HOT if on else COL[k]
		var pts := _ring(o, ax, k, l)
		for s in RING_N:
			var a: Array = pts[s]
			var b: Array = pts[s + 1]
			var front: bool = a[1] and b[1]
			draw_line(a[0], b[0], Color(c, 1.0 if front else 0.16), (2.5 if on else 2.0) if front else 1.0, true)
	if outer:
		var on := hot == H.RVIEW
		draw_arc(o2, SIZE_PX * VIEW_RING, 0.0, TAU, 72, COL_HOT if on else Color(COL_VIEW, 0.7), 2.0 if on else 1.5, true)


func _draw_scale(o: Vector3, o2: Vector2, l: float, hot: int) -> void:
	var ax := _axes_now(true)
	for k in 3:
		var tip := _p(o + ax[k] * l)
		if (tip - o2).length() < AXIS_MIN_PX:
			continue
		var on := hot == H.SX + k
		var c: Color = COL_HOT if on else COL[k]
		draw_line(o2, tip, c, 2.5 if on else 2.0, true)
		draw_rect(Rect2(tip - Vector2(5, 5), Vector2(10, 10)), c)
	draw_rect(Rect2(o2 - Vector2(6, 6), Vector2(12, 12)), COL_HOT if hot == H.SALL else Color(COL_VIEW, 0.9))


# ---------------------------------------------------------------- 고르기

## 화면 점 아래의 손잡이(없으면 H.NONE)
func pick(pos: Vector2) -> int:
	if not _ok():
		return H.NONE
	var o := pivot_point()
	if camera.is_position_behind(o):
		return H.NONE
	var o2 := _p(o)
	var l := SIZE_PX * _wpp(o)
	match tool_mode:
		Tool.MOVE:
			return _pick_move(pos, o, o2, l, true)
		Tool.ROTATE:
			return _pick_rotate(pos, o, o2, l, true)
		Tool.SCALE:
			return _pick_scale(pos, o, o2, l) if allow_scale else H.NONE
		Tool.TRANSFORM:
			if allow_scale and _in_box(pos, o2):
				return H.SALL
			var h := _pick_move(pos, o, o2, l, false)
			return h if h != H.NONE else _pick_rotate(pos, o, o2, l, false)
	return H.NONE


static func _in_box(pos: Vector2, c: Vector2) -> bool:
	return absf(pos.x - c.x) <= 7.0 and absf(pos.y - c.y) <= 7.0


func _pick_move(pos: Vector2, o: Vector3, o2: Vector2, l: float, center: bool) -> int:
	if center and _in_box(pos, o2):
		return H.FREE
	var ax := _axes_now(false)
	var best: int = H.NONE
	var bd := PICK_PX
	for k in 3:
		var tip := _p(o + ax[k] * l)
		var v := tip - o2
		if v.length() < AXIS_MIN_PX:
			continue
		var d := pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, o2, tip + v.normalized() * 12.0))
		if d < bd:
			bd = d
			best = H.AX + k
	if best != H.NONE:
		return best
	for k in 3:
		if _plane_ok(ax, k, o) and Geometry2D.is_point_in_polygon(pos, _plane_quad(o, ax, (k + 1) % 3, (k + 2) % 3, l)):
			return H.PYZ + k
	return H.NONE


func _pick_rotate(pos: Vector2, o: Vector3, o2: Vector2, l: float, outer: bool) -> int:
	var ax := _axes_now(false)
	var best: int = H.NONE
	var bd := PICK_PX
	for k in 3:
		var pts := _ring(o, ax, k, l)
		for s in RING_N:
			var a: Array = pts[s]
			var b: Array = pts[s + 1]
			if not (a[1] and b[1]):
				continue                        # 뒤쪽 반은 안 잡는다(유니티와 같음)
			var d := pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, a[0], b[0]))
			if d < bd:
				bd = d
				best = H.RX + k
	if best != H.NONE or not outer:
		return best
	var r := pos.distance_to(o2)
	if absf(r - SIZE_PX * VIEW_RING) < PICK_PX:
		return H.RVIEW
	return H.RFREE if r < SIZE_PX * 0.92 else H.NONE


func _pick_scale(pos: Vector2, o: Vector3, o2: Vector2, l: float) -> int:
	if _in_box(pos, o2):
		return H.SALL
	var ax := _axes_now(true)
	var best: int = H.NONE
	var bd := PICK_PX
	for k in 3:
		var tip := _p(o + ax[k] * l)
		if (tip - o2).length() < AXIS_MIN_PX:
			continue
		var d := pos.distance_to(Geometry2D.get_closest_point_to_segment(pos, o2, tip))
		if d < bd:
			bd = d
			best = H.SX + k
	return best


## 검사용 — 손잡이 위의 화면 점(화살표 70 % · 평면 네모 가운데 · 고리에서 카메라를 가장 보는 점 · 가운데 · 바깥 고리 오른쪽)
func handle_point(h: int) -> Vector2:
	var o := pivot_point()
	var o2 := _p(o)
	var l := SIZE_PX * _wpp(o)
	if h >= H.AX and h <= H.AZ:
		return o2.lerp(_p(o + _axes_now(false)[h - H.AX] * l), 0.7)
	if h >= H.SX and h <= H.SZ:
		return o2.lerp(_p(o + _axes_now(true)[h - H.SX] * l), 0.97)
	if h >= H.PYZ and h <= H.PXY:
		var k := h - H.PYZ
		var q := _plane_quad(o, _axes_now(false), (k + 1) % 3, (k + 2) % 3, l)
		return (q[0] + q[1] + q[2] + q[3]) * 0.25
	if h >= H.RX and h <= H.RZ:
		var ax := _axes_now(false)
		var k := h - H.RX
		var u := ax[(k + 1) % 3]
		var v := ax[(k + 2) % 3]
		var to_cam := (camera.global_position - o).normalized()
		var best := o2
		var bf := -INF
		for s in RING_N:
			var th := TAU * float(s) / RING_N
			var d := u * cos(th) + v * sin(th)
			var f := d.dot(to_cam)
			if f > bf:
				bf = f
				best = _p(o + d * l)
		return best
	if h == H.RVIEW:
		return o2 + Vector2(SIZE_PX * VIEW_RING, 0.0)
	return o2


# ---------------------------------------------------------------- 끌기

func _begin(h: int, pos: Vector2) -> void:
	_drag = h
	_drag_node = target
	_start_local = target.transform
	_start = target.global_transform
	var par := target.get_parent() as Node3D
	_parent = par.global_transform if par != null else Transform3D.IDENTITY
	_o = pivot_point()
	_axes = _axes_now(h >= H.SX)
	_press = pos
	_last = pos
	_c2 = _p(_o)
	_rot = Basis.IDENTITY
	_ang = 0.0
	var l := SIZE_PX * _wpp(_o)
	if h >= H.AX and h <= H.AZ:
		var a := _axes[h - H.AX]
		_plane = _axis_plane(a)
		_axis_screen = absf(a.dot((_o - camera.global_position).normalized())) > AXIS_STEEP
		var v := _p(_o + a * l) - _c2
		_axis_ppm = maxf(v.length(), 1.0) / maxf(l, 0.000001)
		_axis_dir = v.normalized() if v.length() > 0.0001 else Vector2.RIGHT
	elif h >= H.PYZ and h <= H.PXY:
		_plane = Plane(_axes[h - H.PYZ], _o)
	elif h == H.FREE:
		_plane = Plane(camera.global_basis.z, _o)
	elif h >= H.RX and h <= H.RZ:
		_raxis = _axes[h - H.RX]
		_tan = _ring_tangent(pos, h - H.RX, l)
	elif h >= H.SX and h <= H.SZ:
		for k in 3:
			var v := _p(_o + _axes[k] * l) - _c2
			_slen[k] = maxf(v.length(), 1.0)
			_sdir[k] = v / _slen[k]
	_hit0 = _o
	if h <= H.FREE:
		var hit: Variant = _ray(pos)
		if hit != null:
			_hit0 = hit
	queue_redraw()
	transform_begin.emit(target)


## 축 a 를 품고 카메라를 가장 마주 보는 평면(축 이동 — 마우스 광선이 맞히는 점의 축 방향 성분만 쓴다)
func _axis_plane(a: Vector3) -> Plane:
	var view := (_o - camera.global_position).normalized()
	var n := a.cross(view).cross(a)
	if n.length() < 0.0001:
		n = camera.global_basis.z
	return Plane(n.normalized(), _o)


func _ray(pos: Vector2) -> Variant:
	return _plane.intersects_ray(camera.project_ray_origin(pos), camera.project_ray_normal(pos))


## 누른 자리에서 가장 가까운 고리 점의 화면 접선(θ 가 느는 쪽) — 회전 = 그 방향으로 끈 거리 ÷ 고리 반지름(유니티처럼 고리를 따라 끈다)
func _ring_tangent(pos: Vector2, k: int, r: float) -> Vector2:
	var u := _axes[(k + 1) % 3]
	var v := _axes[(k + 2) % 3]
	var best := 0.0
	var bd := INF
	for s in RING_N:
		var th := TAU * float(s) / RING_N
		var d := pos.distance_to(_p(_o + (u * cos(th) + v * sin(th)) * r))
		if d < bd:
			bd = d
			best = th
	var p := _o + (u * cos(best) + v * sin(best)) * r
	var t2 := _p(p + (u * -sin(best) + v * cos(best)) * (r * 0.05)) - _p(p)
	return t2.normalized() if t2.length() > 0.0001 else Vector2.RIGHT


func _turn(t: Transform3D, r: Basis) -> Transform3D:
	return Transform3D(r * t.basis, _o + r * (t.origin - _o))


## 로컬 축 방향으로 sv 배 — 기즈모 자리(_o)는 그대로
func _scaled(t: Transform3D, sv: Vector3) -> Transform3D:
	var b := t.basis * Basis.from_scale(sv)
	return Transform3D(b, _o + (b * t.basis.inverse()) * (t.origin - _o))


func _update_drag(pos: Vector2, snap: bool) -> void:
	if _drag_node == null or not is_instance_valid(_drag_node):
		_drag = H.NONE
		return
	var g := _start
	if _drag >= H.AX and _drag <= H.AZ:
		var a := _axes[_drag - H.AX]
		var d := 0.0
		if _axis_screen:
			d = (pos - _press).dot(_axis_dir) / _axis_ppm          # 화면에서 축 방향으로 끈 거리 ÷ 그 축의 픽셀/m
		else:
			var hit: Variant = _ray(pos)
			if hit == null:
				return
			d = ((hit as Vector3) - _hit0).dot(a)                 # 마우스 광선이 축을 품은 평면을 맞힌 점의 축 성분(그대로 따라옴)
		if snap:
			d = snappedf(d, snap_move)
		g.origin = _start.origin + a * d
	elif _drag >= H.PYZ and _drag <= H.PXY:
		var hit: Variant = _ray(pos)
		if hit == null:
			return
		var k := _drag - H.PYZ
		var dv := (hit as Vector3) - _hit0
		var di := dv.dot(_axes[(k + 1) % 3])
		var dj := dv.dot(_axes[(k + 2) % 3])
		if snap:
			di = snappedf(di, snap_move)
			dj = snappedf(dj, snap_move)
		g.origin = _start.origin + _axes[(k + 1) % 3] * di + _axes[(k + 2) % 3] * dj
	elif _drag == H.FREE:
		var hit: Variant = _ray(pos)
		if hit == null:
			return
		var dv := (hit as Vector3) - _hit0
		if snap:
			dv = dv.snapped(Vector3.ONE * snap_move)
		g.origin = _start.origin + dv
	elif _drag >= H.RX and _drag <= H.RZ:
		var a := (pos - _press).dot(_tan) / SIZE_PX
		if snap:
			a = deg_to_rad(snappedf(rad_to_deg(a), snap_rotate))
		_ang = a
		g = _turn(_start, Basis(_raxis, a))
	elif _drag == H.RVIEW:
		_ang += wrapf((pos - _c2).angle() - (_last - _c2).angle(), -PI, PI)     # 화면에서 시계 방향 = 카메라 앞쪽 축 둘레 +
		var a := _ang
		if snap:
			a = deg_to_rad(snappedf(rad_to_deg(a), snap_rotate))
		g = _turn(_start, Basis(-camera.global_basis.z, a))
	elif _drag == H.RFREE:
		var rel := pos - _last
		_rot = Basis(camera.global_basis.x, rel.y / SIZE_PX) * Basis(camera.global_basis.y, rel.x / SIZE_PX) * _rot
		g = _turn(_start, _rot.orthonormalized())
	elif _drag >= H.SX and _drag <= H.SZ:
		var k := _drag - H.SX
		var f := 1.0 + (pos - _press).dot(_sdir[k]) / _slen[k]     # 축 끝까지 끌면 2배
		if snap:
			f = snappedf(f, snap_scale)
		var sv := Vector3.ONE
		sv[k] = maxf(f, 0.01)
		g = _scaled(_start, sv)
	elif _drag == H.SALL:
		var f := 1.0 + ((pos.x - _press.x) - (pos.y - _press.y)) / 100.0
		if snap:
			f = snappedf(f, snap_scale)
		g = _scaled(_start, Vector3.ONE * maxf(f, 0.01))
	_last = pos
	_drag_node.transform = _parent.affine_inverse() * g
	transform_changed.emit(_drag_node)
	queue_redraw()


func _finish() -> void:
	var n := _drag_node
	_drag = H.NONE
	_drag_node = null
	queue_redraw()
	if n != null and is_instance_valid(n):
		transform_end.emit(n, _start_local)


## 끄는 중 취소 — 끌기 전 자리로(오른쪽 누름 · Esc · 고른 노드가 바뀜)
func cancel_drag() -> void:
	if _drag == H.NONE:
		return
	var n := _drag_node
	_drag = H.NONE
	_drag_node = null
	if n != null and is_instance_valid(n):
		n.transform = _start_local
		transform_changed.emit(n)
	queue_redraw()


# ---------------------------------------------------------------- 입력

func _gui_input(ev: InputEvent) -> void:
	var mb := ev as InputEventMouseButton
	if mb != null:
		if mb.pressed:
			grab_focus()                        # 단축키가 칸(숫자 입력)이 아니라 미리보기로 오게
		if _drag != H.NONE:
			if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
				_finish()
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				cancel_drag()
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.alt_pressed and not mb.shift_pressed and tool_mode != Tool.VIEW:
			if mb.pressed:
				var h := pick(mb.position)
				if h != H.NONE:
					_begin(h, mb.position)
					accept_event()
					return
				_view_drag = true                # 기즈모 밖 — 끌면 카메라, 그냥 떼면 고르기
				_moved = false
				_press = mb.position
			elif _view_drag:
				_view_drag = false
				if not _moved:
					view_input.emit(ev)
					clicked.emit(mb.position)
					accept_event()
					return
		view_input.emit(ev)
		accept_event()
		return
	var mm := ev as InputEventMouseMotion
	if mm != null:
		if _drag != H.NONE:
			_update_drag(mm.position, mm.ctrl_pressed or mm.meta_pressed)
			accept_event()
			return
		if _view_drag and mm.position.distance_to(_press) > CLICK_PX:
			_moved = true
		var h := pick(mm.position) if mm.button_mask == 0 else _hot
		if h != _hot:
			_hot = h
			queue_redraw()
		view_input.emit(ev)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hot != H.NONE:
		_hot = H.NONE
		queue_redraw()
