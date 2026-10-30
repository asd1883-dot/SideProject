// 땅 띠 겹쳐 잇기(아스트라 리소스 10-30) — 1536 px 땅 조각을 1408 px 간격으로 놓고, 두 번째부터 왼쪽 128 px 를 서서히 투명하게
shader_type canvas_item;
render_mode unshaded;
uniform float texture_width = 1536.0;
uniform float overlap_pixels = 128.0;
uniform bool fade_left = true;
uniform float top_fade_pixels = 0.0;
void fragment() {
    vec4 tex = COLOR;
    if (fade_left) {
        tex.a *= smoothstep(0.0, overlap_pixels, UV.x * texture_width);
    }
    if (top_fade_pixels > 0.0) {
        tex.a *= smoothstep(0.0, top_fade_pixels, UV.y / TEXTURE_PIXEL_SIZE.y);
    }
    COLOR = tex;
}
