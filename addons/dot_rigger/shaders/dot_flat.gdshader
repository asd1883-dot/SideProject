shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_opaque, cull_back;

// 도트화용 플랫 셰이딩. 조명을 N단으로 계단화해서
// 다운샘플/양자화 후에도 색이 뭉개지지 않게 한다.

uniform sampler2D albedo_tex : source_color, filter_nearest, hint_default_white;
uniform bool use_tex = false;
uniform vec4 albedo_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform int bands : hint_range(2, 8) = 3;
uniform float ambient : hint_range(0.0, 1.0) = 0.45;
uniform float light_wrap : hint_range(0.0, 1.0) = 0.25;
uniform vec3 light_dir = vec3(-0.4, 0.7, 0.6);
uniform float rim : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_n;
varying vec3 v_v;

void vertex() {
	v_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_v = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD;
}

void fragment() {
	vec4 base = albedo_color;
	if (use_tex) {
		base *= texture(albedo_tex, UV);
	}
	vec3 n = normalize(v_n);
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
	ALBEDO = col;
	// ALPHA 만 쓰면 Godot 이 반투명 물체로 분류해 깊이를 기록하지 않는다 → 나중에 그린 면이 무조건 위에 올라가
	// 뒤쪽 어깨·관절 안쪽이 앞으로 비쳐 보였다(2026-09-15 실측: 합성의 6~8% 픽셀, 오른손 파트 93px 중 18px).
	// 알파 가위(ALPHA_SCISSOR_THRESHOLD)를 주면 불투명 파이프라인으로 그려져 픽셀마다 앞뒤를 가린다.
	// 투명 텍스처는 0.5 기준으로 오려낸다. (알파를 아예 뺀 결과와 픽셀 단위로 같음을 확인)
	ALPHA = base.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
