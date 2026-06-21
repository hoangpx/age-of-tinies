shader_type canvas_item;
render_mode unshaded;
// Viền quanh silhouette: pixel TRONG SUỐT mà cạnh nó (8 hướng) có pixel đặc → tô màu viền.
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float width : hint_range(0.0, 4.0) = 1.6;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (c.a > 0.3) {
		COLOR = c;
	} else {
		vec2 s = TEXTURE_PIXEL_SIZE * width;
		float a = 0.0;
		a = max(a, texture(TEXTURE, UV + vec2( s.x, 0.0)).a);
		a = max(a, texture(TEXTURE, UV + vec2(-s.x, 0.0)).a);
		a = max(a, texture(TEXTURE, UV + vec2(0.0,  s.y)).a);
		a = max(a, texture(TEXTURE, UV + vec2(0.0, -s.y)).a);
		a = max(a, texture(TEXTURE, UV + vec2( s.x,  s.y)).a);
		a = max(a, texture(TEXTURE, UV + vec2(-s.x,  s.y)).a);
		a = max(a, texture(TEXTURE, UV + vec2( s.x, -s.y)).a);
		a = max(a, texture(TEXTURE, UV + vec2(-s.x, -s.y)).a);
		COLOR = (a > 0.3) ? line_color : vec4(0.0);
	}
}
