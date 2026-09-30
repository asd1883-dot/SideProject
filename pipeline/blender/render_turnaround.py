# -*- coding: utf-8 -*-
"""기준 몸 네 방향 그림 (Blender 헤드리스) — AI 이미지 생성(Astra 등)에 넣을 체형 · 포즈 기준.

    blender -b --factory-startup -P pipeline/blender/render_turnaround.py -- <모델.glb> <출력 폴더> [한 변 픽셀=1024]

- 뼈대의 기본 자세(바인드 포즈, UAL1 은 T-포즈) 그대로, 직교 카메라로 앞 · 뒤 · 왼쪽 · 오른쪽을 같은 배율로 찍는다.
  (네 장의 키 · 발 위치가 픽셀까지 같아야 image-to-3D 가 한 사람으로 읽는다)
- 흰 배경 · 밝은 회색 무광 — 모양만 전달하고 색은 AI 가 정하게.
- front/back/left/right.png + 네 장을 붙인 sheet.png. left = 인물의 왼쪽 옆면(인물 기준).
"""
import bpy, sys, os, math
from mathutils import Vector

a = sys.argv[sys.argv.index("--") + 1:]
src, out_dir = a[0], a[1]
size = int(a[2]) if len(a) > 2 else 1024
os.makedirs(out_dir, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
sc = bpy.context.scene

# 바인드 포즈로 — 가져올 때 붙은 동작은 무시
for o in sc.objects:
    if o.type == "ARMATURE":
        o.data.pose_position = "REST"
        if o.animation_data:
            o.animation_data.action = None
# 뼈대에 붙은(스킨) 메시만 찍는다 — 보조 오브젝트(Icosphere 등) 제외
meshes = [o for o in sc.objects if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers)]
for o in sc.objects:
    if o.type == "MESH" and o not in meshes:
        o.hide_render = True
bpy.context.view_layer.update()

dg = bpy.context.evaluated_depsgraph_get()
lo = Vector((1e9,) * 3); hi = Vector((-1e9,) * 3)
for o in meshes:
    ev = o.evaluated_get(dg)
    me = ev.to_mesh()
    for v in me.vertices:
        p = ev.matrix_world @ v.co
        for k in range(3):
            lo[k] = min(lo[k], p[k]); hi[k] = max(hi[k], p[k])
    ev.to_mesh_clear()
ctr = (lo + hi) / 2
dims = hi - lo
print("BODY size x %.3f y %.3f z %.3f" % tuple(dims))

sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.display.shading.color_type = "SINGLE"
sc.display.shading.single_color = (0.78, 0.78, 0.78)
sc.display.shading.show_cavity = True
sc.render.resolution_x = sc.render.resolution_y = size
sc.render.film_transparent = False
sc.world = bpy.data.worlds.new("w")
sc.world.color = (1, 1, 1)
sc.view_settings.view_transform = "Standard"

cam = bpy.data.cameras.new("cam"); cam.type = "ORTHO"
cam.ortho_scale = max(dims.x, dims.y, dims.z) * 1.08
co = bpy.data.objects.new("cam", cam); sc.collection.objects.link(co); sc.camera = co

# glTF 인물은 Blender 에서 -Y 를 바라본다(앞 = -Y 쪽에서 본 모습)
dist = 10.0
views = {
    "front": Vector((0, -1, 0)),
    "back": Vector((0, 1, 0)),
    "left": Vector((1, 0, 0)),    # 인물의 왼쪽(+X)에서 본 옆면
    "right": Vector((-1, 0, 0)),
}
files = []
for name, d in views.items():
    co.location = ctr + d * dist
    co.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(out_dir, name + ".png")
    bpy.ops.render.render(write_still=True)
    files.append(sc.render.filepath)

# 네 장을 한 장으로(앞 · 왼 · 뒤 · 오)
imgs = {n: bpy.data.images.load(os.path.join(out_dir, n + ".png")) for n in views}
order = ["front", "left", "back", "right"]
sheet = bpy.data.images.new("sheet", size * 4, size)
px = [1.0] * (size * 4 * size * 4)
for i, n in enumerate(order):
    src_px = list(imgs[n].pixels)
    for y in range(size):
        row = src_px[y * size * 4:(y + 1) * size * 4]
        start = (y * size * 4 + i * size) * 4
        px[start:start + size * 4] = row
sheet.pixels = px
sheet.filepath_raw = os.path.join(out_dir, "sheet.png")
sheet.file_format = "PNG"
sheet.save()
print("TURNAROUND_OK", out_dir)
