shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_disabled;

// 3D 캐릭터(DRCharacter3D — 몸 · 옷 · 무기)용 도트 플랫 셰이딩(10-15). dot_flat.gdshader 를 바탕으로:
//  - instance uniform tint(색 곱, 기본 흰색) · fade(1 보임 → 0 사라짐) — 병사마다 다른 값인데 재질은 병사끼리 공유한다
//    (재질을 병사마다 복제하면 100 명이면 재질 400 개 · 그리기 묶음도 깨짐). 죽은 병사는 tint 로 어둡게, 시체는 fade 로 지운다.
//  - fade 는 반투명 대신 4x4 바이어 디더로 픽셀을 버린다(discard) — 반투명이면 깊이를 안 써서 앞뒤가 꼬이고(09-15 dot_flat 주석),
//    도트 화면에서는 픽셀 단위로 듬성듬성 사라지는 편이 도트 게임답다. 저해상도로 그리면(C 갈래) 그 픽셀 격자에 맞는다.
//  - 양면(cull_disabled) + 안쪽 면 어둡게(inside_shade): 옷을 입히면 그 슬롯의 몸을 빼므로 소매 · 깃 · 옷자락 안쪽이 비어 있다.
//    한쪽 면만 그리면 그 구멍으로 옷의 뒷면이 안 그려져 배경이 비친다 → 안쪽 면도 그리되 어둡게(옷 속 그림자처럼).
//    구멍 둘을 잇는 시선(소매 → 몸통 → 반대 소매)은 슬롯 경계 뚜껑(정점 색 COLOR, DRSlotMesh._add_caps)이 막는다.
//  - 텍스처는 밉맵(filter_linear_mipmap) — 2048 텍스처를 캐릭터 키 수십 픽셀로 그리면 nearest 는 움직일 때마다 색이 반짝인다.
// 공통 값(bands · ambient · light_wrap · light_dir · rim · inside_shade)은 DRCharacter3D.set_shading() 이 모든 재질에 한꺼번에 준다.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable, hint_default_white;
uniform bool use_tex = false;
uniform vec4 albedo_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform int bands : hint_range(2, 8) = 3;
uniform float ambient : hint_range(0.0, 1.0) = 0.45;
uniform float light_wrap : hint_range(0.0, 1.0) = 0.25;
uniform vec3 light_dir = vec3(-0.4, 0.7, 0.6);
uniform float rim : hint_range(0.0, 1.0) = 0.0;
// 안쪽 면(뒷면이 보이는 곳 — 소매 · 깃 · 옷자락 속)의 밝기 배율
uniform float inside_shade : hint_range(0.0, 1.0) = 0.35;

// 병사마다 — MeshInstance3D.set_instance_shader_parameter("tint" / "fade", 값)
instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float fade : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_n;
varying vec3 v_v;

// 4x4 바이어 행렬(0 ~ 15). fade 가 칸의 문턱 (값 + 0.5) / 16 보다 작으면 그 픽셀을 버린다 → fade 1 = 다 보임, 0 = 다 버림
const float BAYER[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

void vertex() {
	v_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_v = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD;
}

void fragment() {
	ivec2 p = ivec2(FRAGCOORD.xy) % 4;
	if (fade < (BAYER[p.y * 4 + p.x] + 0.5) / 16.0) {
		discard;
	}
	vec4 base = albedo_color;
	if (use_tex) {
		base *= texture(albedo_tex, UV);
	}
	// 정점 색 — 슬롯 경계 뚜껑(DRSlotMesh._add_caps)만 어둡고 나머지는 흰색. 정점 색이 없는 메시(무기)는 Godot 이 흰색을 준다
	base.rgb *= COLOR.rgb;
	// 투명 텍스처는 0.5 기준으로 오려낸다(ALPHA 를 쓰면 반투명 물체로 분류돼 깊이를 안 쓴다 — dot_flat 09-15)
	if (base.a < 0.5) {
		discard;
	}
	vec3 n = normalize(v_n);
	// 안쪽(옷 속) = 감김이 뒷면이고 노멀도 카메라 반대쪽. AI 메시에는 감김만 뒤집힌 삼각형이 섞여 있어(군복 옷자락 — 10-15 확인)
	// 감김(FRONT_FACING)만 보면 겉면이 안쪽처럼 검게 칠해진다 → 노멀이 카메라를 보면 겉면으로 친다. VIEW = 조각 → 카메라(직교에서도 맞다)
	vec3 to_cam = (INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz;
	bool inside = !FRONT_FACING && dot(n, to_cam) < 0.0;
	if (inside) {
		n = -n;
	}
	float nl = dot(n, normalize(light_dir));
	nl = clamp(nl * (1.0 - light_wrap) + light_wrap, 0.0, 1.0);
	float b = float(bands);
	nl = clamp(floor(nl * b) / max(b - 1.0, 1.0), 0.0, 1.0);
	float shade = ambient + (1.0 - ambient) * nl;
	vec3 col = base.rgb * shade;
	if (rim > 0.0) {
		float f = pow(1.0 - clamp(dot(n, normalize(-v_v)), 0.0, 1.0), 3.0);
		col = mix(col, vec3(1.0), step(0.6, f) * rim);
	}
	if (inside) {
		col *= inside_shade;
	}
	ALBEDO = col * tint.rgb;
}
