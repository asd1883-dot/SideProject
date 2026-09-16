shader_type canvas_item;

// Dot Rigger 파트 스프라이트 셰이더 — 부드러운 도트 이동 + 도트 아웃라인
//
// [부드러운 도트 이동] smooth_edges
// 도트 텍스처를 확대해 그릴 때: 텍셀 안쪽은 또렷하게, 텍셀 경계만 화면 1픽셀 폭으로 섞는다.
// nearest 로 그리면 1픽셀 미만으로 움직일 때마다 텍셀이 통째로 켜졌다 꺼졌다 해서
// 몸통 안쪽이 옛날 TV 노이즈처럼 깜빡인다. 경계만 섞으면 같은 움직임이
// 경계의 옅은 색 변화로 나타나서 도트 느낌은 유지한 채 매끄럽게 움직인다.
// (2026-09-15 실측: Idle 에서 흐리게 본 튐 25.5 → 4.9, 움직임 양은 그대로)
// 텍셀 4개를 직접 읽어 알파를 미리 곱한 뒤 섞는다. 필터로 섞으면 투명 텍셀의 RGB(검정)가
// 섞여 파트 테두리에 어두운 선이 생긴다. texelFetch 라 텍스처 필터 설정과 무관하다.
//
// [도트 아웃라인] outline_px / outline_color / outline_only (2026-09-16)
// 두께 단위는 텍셀(= 도트)이라 카메라 줌·노드 배율과 상관없이 도트 두께가 유지된다.
// 텍스처 밖에는 못 그리므로 베이크는 파트 그림을 outline_px 만큼 여유 있게 잘라 둔다.
// - 파트별 (outline_only = false): 투명 텍셀 중 맨해튼 거리 outline_px 안에 불투명 텍셀이 있으면 outline_color.
//   파트마다 자기 z 에서 그려지므로 관절이 겹치는 곳에도 선이 생긴다(종이 인형 느낌).
// - 전체 실루엣 (outline_only = true): 이 머티리얼을 쓰는 스프라이트는 "밑깔개" — 파트와 같은 텍스처·위치로
//   모든 파트보다 뒤(z −1)에 깔리고, 실루엣을 outline_px 만큼 부풀린 모양을 outline_color 한 색으로 그린다.
//   파트 본체가 그 위를 덮으므로 관절 겹침은 가려지고 캐릭터 전체 바깥 테두리만 남는다.
//   (CanvasGroup 으로 모아 그리는 방식은 z_index 가 다른 자식을 그룹에서 빼 버려 못 씀 — 02 M2)

uniform bool smooth_edges = true;
uniform int outline_px : hint_range(0, 3) = 0;
uniform vec4 outline_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform bool outline_only = false;

// 텍셀 q 를 outline_px 만큼 부풀린 알파(주변 맨해튼 거리 안 최대 알파)
float dilated_alpha(sampler2D tex, ivec2 q, ivec2 hi, int r) {
	float a = 0.0;
	for (int dy = -3; dy <= 3; dy++) {
		for (int dx = -3; dx <= 3; dx++) {
			if (abs(dx) + abs(dy) > r) {
				continue;
			}
			ivec2 p = q + ivec2(dx, dy);
			if (p.x < 0 || p.y < 0 || p.x > hi.x || p.y > hi.y) {
				continue;
			}
			a = max(a, texelFetch(tex, p, 0).a);
		}
	}
	return a;
}

void fragment() {
	ivec2 n = textureSize(TEXTURE, 0);
	ivec2 hi = n - ivec2(1);
	vec2 uv = UV * vec2(n);
	ivec2 c = clamp(ivec2(floor(uv)), ivec2(0), hi);

	if (outline_only) {
		// 밑깔개: 부풀린 실루엣을 한 색으로. 경계 섞기는 본체와 같은 방식(알파만 섞음)
		float a = 0.0;
		if (!smooth_edges) {
			a = dilated_alpha(TEXTURE, c, hi, outline_px);
		} else {
			vec2 seam = floor(uv + 0.5);
			vec2 w = max(fwidth(uv), vec2(0.00001));
			vec2 t = clamp((uv - seam) / w + 0.5, 0.0, 1.0);
			ivec2 i = ivec2(seam) - ivec2(1);
			float a00 = dilated_alpha(TEXTURE, i, hi, outline_px);
			float a10 = dilated_alpha(TEXTURE, i + ivec2(1, 0), hi, outline_px);
			float a01 = dilated_alpha(TEXTURE, i + ivec2(0, 1), hi, outline_px);
			float a11 = dilated_alpha(TEXTURE, i + ivec2(1, 1), hi, outline_px);
			a = mix(mix(a00, a10, t.x), mix(a01, a11, t.x), t.y);
		}
		COLOR = vec4(outline_color.rgb, outline_color.a * a);
	} else {
		vec4 center = texelFetch(TEXTURE, c, 0);

		bool edge = false;
		if (outline_px > 0 && center.a < 0.5) {
			edge = dilated_alpha(TEXTURE, c, hi, outline_px) >= 0.5;
		}

		if (edge) {
			COLOR = outline_color;
		} else if (!smooth_edges) {
			COLOR = center;
		} else {
			vec2 seam = floor(uv + 0.5);
			vec2 w = max(fwidth(uv), vec2(0.00001));
			vec2 t = clamp((uv - seam) / w + 0.5, 0.0, 1.0);
			ivec2 i = ivec2(seam) - ivec2(1);
			vec4 c00 = texelFetch(TEXTURE, clamp(i, ivec2(0), hi), 0);
			vec4 c10 = texelFetch(TEXTURE, clamp(i + ivec2(1, 0), ivec2(0), hi), 0);
			vec4 c01 = texelFetch(TEXTURE, clamp(i + ivec2(0, 1), ivec2(0), hi), 0);
			vec4 c11 = texelFetch(TEXTURE, clamp(i + ivec2(1, 1), ivec2(0), hi), 0);
			c00.rgb *= c00.a;
			c10.rgb *= c10.a;
			c01.rgb *= c01.a;
			c11.rgb *= c11.a;
			vec4 m = mix(mix(c00, c10, t.x), mix(c01, c11, t.x), t.y);
			COLOR = m.a > 0.0001 ? vec4(m.rgb / m.a, m.a) : vec4(0.0);
		}
	}
}
