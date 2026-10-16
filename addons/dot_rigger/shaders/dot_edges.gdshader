shader_type spatial;
// 3D 도트 창(DRDotView3D)의 선 그리기 — 카메라 앞을 덮는 화면 쿼드.  (10-15)
//
// 저해상도 3D 렌더(텍셀 하나 = 화면 도트 하나) 위에서 한 번만 돈다. 규칙은 하나:
//   "이 도트보다 확실히 앞에 있는 이웃 도트(상하좌우)가 있으면 이 도트는 선이다."
//   - 배경 도트(알파 0) 옆에 몸 도트가 있으면 → 실루엣 바깥 1 도트 외곽선
//   - 몸 도트인데 이웃이 inner_gap(m) 넘게 앞에 있으면 → 겹친 캐릭터 사이 선(뒤 캐릭터 쪽에 그려진다)
//   선은 언제나 앞 물체의 바깥(뒤쪽 도트)에 생기므로 2D 퍼펫의 "실루엣 밖 밑깔개" 선과 같은 자리 · 같은 두께다.
//
// 왜 2D(canvas) 단계가 아니라 여기서: 겹친 병사 사이 선은 깊이가 있어야 정확히 가릴 수 있는데, 깊이는 3D 렌더 안에만 있다.
//   바깥 외곽선도 같은 패스에서 같은 규칙으로 그려야 픽셀 퍼펙트 톤 · 두께가 실루엣과 겹친 곳에서 똑같이 나온다.
//   값도 싸다: 텍셀 수(화면 픽셀 / dot_px²)만큼만 돈다(2D 에서 하면 실제 화면 픽셀마다 돈다).
//
// 투명 배경 지키기: 선이 아닌 도트는 ALPHA 0 으로 내보낸다 — blend_mix 라 색 · 알파 모두 그대로 남는다(배경 알파 0 유지).
//   선 도트만 알파 1 로 덮어쓴다. 그래서 2D 땅이 3D 뒤에서 그대로 보인다.
//
// 선의 색(2D 퍼펫 · core/exporter.gd 와 같은 두 방식)
//   style 0 카툰: line_color 한 색
//   style 1 픽셀 퍼펙트: 선 도트마다 바로 옆(앞 물체) 도트 색을 tone 만큼 어둡게 — 그 자리 색을 따라가는 가장자리(selout)
//   3D 버퍼는 선형 색이라, 2D 셰이더(sRGB 값에 곱함)와 같은 밝기가 되게 (1 − tone)^2.2 를 곱한다.

render_mode unshaded, blend_mix, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform int style : hint_range(0, 1) = 1;
uniform vec4 line_color : source_color = vec4(0.07, 0.06, 0.06, 1.0);
uniform float tone : hint_range(0.0, 1.0) = 0.45;
uniform bool inner = true;
// 이웃이 이만큼(m, 카메라가 보는 방향 거리) 넘게 앞에 있어야 안쪽 선. 몸 두께 · 팔다리 겹침(0.2 ~ 0.4 m)에는 안 생기게
uniform float inner_gap = 0.5;

void vertex() {
	// 화면 전체를 덮는 쿼드(QuadMesh 2×2). 4.3 부터 역방향 Z 라 z = 1 이 가까운 면
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

// 텍셀의 카메라 방향 거리(m). 직교 카메라라 깊이 값이 거리와 선형이다
float view_depth(ivec2 p, mat4 inv_proj) {
	float z = texelFetch(depth_tex, p, 0).r;
	vec4 v = inv_proj * vec4(0.0, 0.0, z, 1.0);
	return -v.z / v.w;
}

void fragment() {
	ivec2 hi = ivec2(VIEWPORT_SIZE) - ivec2(1);
	ivec2 c = ivec2(FRAGCOORD.xy);
	bool bg = texelFetch(screen_tex, c, 0).a < 0.5;
	float dc = bg ? 0.0 : view_depth(c, INV_PROJECTION_MATRIX);
	vec3 sum = vec3(0.0);
	float cnt = 0.0;
	for (int i = 0; i < 4; i++) {
		ivec2 o = i == 0 ? ivec2(1, 0) : (i == 1 ? ivec2(-1, 0) : (i == 2 ? ivec2(0, 1) : ivec2(0, -1)));
		ivec2 q = c + o;
		if (q.x < 0 || q.y < 0 || q.x > hi.x || q.y > hi.y) {
			continue;
		}
		vec4 qc = texelFetch(screen_tex, q, 0);
		if (qc.a < 0.5) {
			continue;                       // 이웃이 배경이면 앞에 있을 수 없다
		}
		if (!bg) {
			if (!inner || dc - view_depth(q, INV_PROJECTION_MATRIX) < inner_gap) {
				continue;                   // 같은 몸이거나 거의 같은 깊이 — 선 없음
			}
		}
		sum += qc.rgb;
		cnt += 1.0;
	}
	if (cnt < 0.5) {
		ALBEDO = vec3(0.0);
		ALPHA = 0.0;                        // 선이 아니다 — 그 자리 색 · 알파를 그대로 둔다
	} else if (style == 0) {
		ALBEDO = line_color.rgb;
		ALPHA = line_color.a;
	} else {
		ALBEDO = sum / cnt * pow(1.0 - tone, 2.2);
		ALPHA = 1.0;
	}
}
