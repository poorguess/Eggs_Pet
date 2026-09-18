shader_type canvas_item;

uniform float time_offset = 0.0;
uniform float wobble_strength : hint_range(0.0, 1.0) = 0.0;
uniform float entrance_squash : hint_range(0.0, 1.0) = 0.0;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.35;
uniform float chromatic_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 sample_uv_min = vec2(0.0, 0.31);
uniform vec2 sample_uv_max = vec2(1.0, 0.64);
uniform vec4 rim_color : source_color = vec4(1.0, 0.42, 0.95, 1.0);

void vertex() {
	float y = UV.y - 0.5;
	float wave = sin((UV.y * 7.5 + time_offset * 4.2) + UV.x * 2.4);
	VERTEX.x += wave * entrance_squash * 20.0 * (1.0 - abs(y) * 0.75);
	VERTEX.y += sin(UV.x * 9.0 + time_offset * 5.0) * entrance_squash * 8.0;
}

void fragment() {
	vec2 uv = mix(sample_uv_min, sample_uv_max, UV);
	float ripple = sin((uv.x * 16.0 + uv.y * 8.0) + time_offset * 5.4);
	float ripple_2 = sin((uv.y * 19.0 - uv.x * 6.0) - time_offset * 4.1);
	float idle_wave = sin(UV.x * 8.0 + time_offset * 1.7) * sin(UV.y * 5.0 - time_offset * 1.15);
	float water = 0.18 + wobble_strength * 0.82;
	uv += (vec2(ripple, ripple_2) * water * 0.0045 + vec2(idle_wave, -idle_wave) * 0.0018) * (sample_uv_max - sample_uv_min);

	vec2 chroma = vec2(0.0045, -0.0028) * chromatic_strength * (sample_uv_max - sample_uv_min);
	vec4 tex = texture(TEXTURE, uv) * COLOR;
	tex.r = texture(TEXTURE, uv + chroma).r * COLOR.r;
	tex.b = texture(TEXTURE, uv - chroma).b * COLOR.b;
	float alpha = tex.a;
	float edge = smoothstep(0.02, 0.42, alpha) * (1.0 - smoothstep(0.42, 0.88, alpha));
	float color_flow = sin(UV.x * 9.0 + UV.y * 4.0 + time_offset * 2.2) * 0.5 + 0.5;

	vec3 lit = tex.rgb + rim_color.rgb * edge * (0.16 + glow_strength * 0.9 + wobble_strength * 0.45);
	lit += rim_color.rgb * color_flow * edge * glow_strength * 0.12;
	COLOR = vec4(lit, alpha);
}
