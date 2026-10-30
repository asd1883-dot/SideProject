// 깃발 흔들기(아스트라 리소스 10-30) — 잘게 나눈 Polygon2D(가로 28 × 세로 4 칸)에 깃발 문양을 입히고 wind_time 을 매 프레임 넘긴다
shader_type canvas_item;
render_mode unshaded;

uniform vec2 cloth_size = vec2(122.0, 64.0);
uniform float wind_time = 0.0;
uniform float phase_offset = 0.0;
uniform float amplitude : hint_range(0.0, 16.0) = 6.0;
uniform float speed : hint_range(0.0, 8.0) = 2.8;
varying vec2 local_uv;

void vertex() {
    local_uv = VERTEX / cloth_size;
    float u = clamp(local_uv.x, 0.0, 1.0);
    float envelope = pow(u, 1.35);
    float phase = u * 9.0 - wind_time * speed + phase_offset;
    VERTEX.y += envelope * amplitude * (sin(phase) + 0.28 * sin(phase * 2.0 + local_uv.y * 1.4));
    VERTEX.x += envelope * amplitude * 0.22 * sin(phase + 1.2);
}

void fragment() {
    vec4 cloth = texture(TEXTURE, UV);
    float shade = 0.91 + 0.10 * cos(local_uv.x * 9.0 - wind_time * speed + phase_offset);
    COLOR = vec4(cloth.rgb * shade, cloth.a);
}
