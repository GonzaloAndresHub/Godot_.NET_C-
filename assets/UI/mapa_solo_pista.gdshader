shader_type spatial;
render_mode unshaded, depth_draw_always;

uniform sampler2D mapa : source_color, filter_linear_mipmap;
uniform float umbral : hint_range(0.0, 1.0) = 0.55;
uniform float suavidad : hint_range(0.0, 0.3) = 0.08;
uniform vec3 color_pista : source_color = vec3(0.12, 0.13, 0.15);

void fragment() {
	vec3 c = texture(mapa, UV).rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	// La carretera es oscura: 1 donde es oscuro, 0 donde es claro
	float es_pista = 1.0 - smoothstep(umbral - suavidad, umbral + suavidad, lum);
	ALBEDO = mix(c, color_pista, 0.0) * 1.0;
	ALPHA = es_pista;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}