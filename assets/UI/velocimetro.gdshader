shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;

uniform vec2 center_uv = vec2(0.488, 0.585);
uniform float start_angle_deg = -118.0;
uniform float sweep_deg = 236.0;
uniform float dot_min_radius = 0.463;

uniform vec4 color_low : source_color = vec4(0.0, 0.9, 1.0, 1.0);
uniform vec4 color_mid : source_color = vec4(0.8, 0.1, 1.0, 1.0);
uniform vec4 color_high : source_color = vec4(1.0, 0.1, 0.2, 1.0);

uniform float glow_intensity : hint_range(1.0, 20.0) = 6.0;
uniform float halo_strength : hint_range(0.0, 30.0) = 12.0;
uniform float glow_radius : hint_range(1.0, 30.0) = 9.0;
uniform float core_whiteness : hint_range(0.0, 1.0) = 0.6;
uniform float head_boost : hint_range(0.0, 4.0) = 1.5;
uniform float pulse_amount : hint_range(0.0, 0.5) = 0.12;
uniform float pulse_speed : hint_range(0.0, 20.0) = 6.0;
uniform float unlit_brightness : hint_range(0.0, 1.0) = 0.35;

vec3 neon_color(float t) {
	if (t < 0.5) {
		return mix(color_low.rgb, color_mid.rgb, t * 2.0);
	}
	return mix(color_mid.rgb, color_high.rgb, (t - 0.5) * 2.0);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);

	vec2 p = (UV - center_uv) * vec2(1.0, TEXTURE_PIXEL_SIZE.x / TEXTURE_PIXEL_SIZE.y);
	float r = length(p);

	float angle = degrees(atan(p.x, -p.y));
	float t = (angle - start_angle_deg) / sweep_deg;

	bool outer = r > dot_min_radius;
	bool in_arc = t >= 0.0 && t <= 1.0;

	COLOR = tex;

	if (outer) {
		COLOR.rgb = tex.rgb * unlit_brightness;

		if (in_arc && progress > 0.001 && t <= progress) {
			// Halo: 5 anillos x 16 direcciones, con caída suave
			float halo = 0.0;
			float total = 0.0;
			for (int ring = 1; ring <= 5; ring++) {
				float fr = float(ring);
				float dist = glow_radius * fr * 0.5;
				float weight = exp(-fr * 0.5);
				for (int i = 0; i < 16; i++) {
					float a = float(i) * 0.3926991;
					vec2 dir = vec2(cos(a), sin(a));
					halo += texture(TEXTURE, UV + dir * TEXTURE_PIXEL_SIZE * dist).a * weight;
					total += weight;
				}
			}
			halo = halo / total;

			vec3 neon = neon_color(clamp(t, 0.0, 1.0));

			// La punta de la aguja brilla más, y todo pulsa un poco
			float head = smoothstep(progress - 0.08, progress, t);
			float pulse = 1.0 + pulse_amount * sin(TIME * pulse_speed);
			float boost = glow_intensity * (1.0 + head * head_boost) * pulse;

			// Núcleo casi blanco, halo del color neón
			vec3 glow_col = neon * boost;
			vec3 core = mix(neon, vec3(1.0), core_whiteness) * boost;

			// Curva suave: 1 - exp(-x) se satura sin cortes bruscos
			float glow_a = 1.0 - exp(-halo * halo_strength * (1.0 + head * head_boost));
			float out_a = clamp(max(tex.a, glow_a), 0.0, 1.0);

			COLOR.rgb = mix(glow_col, core, tex.a);
			COLOR.a = out_a;
		}
	}
}