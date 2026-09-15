shader_type canvas_item;

// 부드러운 도트 이동 (Dot Rigger)
//
// 도트 파트 이미지를 확대·회전해서 그릴 때, 텍셀 안쪽은 또렷하게 두고
// 텍셀과 텍셀의 경계만 화면 1픽셀 폭으로 섞는다.
//
// nearest 로 그리면 1픽셀 미만으로 움직일 때마다 텍셀이 통째로 켜졌다 꺼졌다 해서
// 몸통 안쪽이 옛날 TV 노이즈처럼 깜빡인다. 경계만 섞으면 같은 움직임이
// 경계의 옅은 색 변화로 나타나서 도트 느낌은 유지한 채 매끄럽게 움직인다.
// (2026-09-15 실측: Idle 에서 흐리게 본 튐 25.5 → 4.9, 움직임 양은 그대로)
//
// 텍셀 4개를 직접 읽어 알파를 미리 곱한 뒤 섞는다. 필터로 섞으면 투명 텍셀의 RGB(검정)가
// 섞여 파트 테두리에 어두운 선이 생긴다. texelFetch 라 텍스처 필터 설정과 무관하다.
// 확대하지 않고(1:1) 그리면 nearest 와 거의 같게 보인다.

void fragment() {
	ivec2 n = textureSize(TEXTURE, 0);
	vec2 uv = UV * vec2(n);
	vec2 seam = floor(uv + 0.5);
	vec2 w = max(fwidth(uv), vec2(0.00001));
	vec2 t = clamp((uv - seam) / w + 0.5, 0.0, 1.0);
	ivec2 i = ivec2(seam) - ivec2(1);
	ivec2 hi = n - ivec2(1);
	vec4 c00 = texelFetch(TEXTURE, clamp(i, ivec2(0), hi), 0);
	vec4 c10 = texelFetch(TEXTURE, clamp(i + ivec2(1, 0), ivec2(0), hi), 0);
	vec4 c01 = texelFetch(TEXTURE, clamp(i + ivec2(0, 1), ivec2(0), hi), 0);
	vec4 c11 = texelFetch(TEXTURE, clamp(i + ivec2(1, 1), ivec2(0), hi), 0);
	c00.rgb *= c00.a;
	c10.rgb *= c10.a;
	c01.rgb *= c01.a;
	c11.rgb *= c11.a;
	vec4 c = mix(mix(c00, c10, t.x), mix(c01, c11, t.x), t.y);
	COLOR = c.a > 0.0001 ? vec4(c.rgb / c.a, c.a) : vec4(0.0);
}
