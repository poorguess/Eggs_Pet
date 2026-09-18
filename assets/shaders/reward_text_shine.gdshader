shader_type canvas_item;

uniform float shine_progress : hint_range(0.0, 1.0) = 0.0;
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.0;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.35;

void vertex() {
	float wave = sin(UV.x * 18.0 + TIME * 5.5) * pulse_strength * 3.0;
	VERTEX.y += wave * smoothstep(0.0, 0.28, UV.y) * (1.0 - smoothstep(0.78, 1.0, UV.y));
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV) * COLOR;
	float diagonal = UV.x + UV.y * 0.22;
	float shine = 1.0 - smoothstep(0.025, 0.13, abs(diagonal - mix(-0.18, 1.22, shine_progress)));
	shine *= smoothstep(0.04, 0.32, tex.a);
	float rim = smoothstep(0.02, 0.35, tex.a) * (1.0 - smoothstep(0.35, 0.78, tex.a));
	vec3 result = tex.rgb + vec3(1.0, 0.95, 0.55) * shine * 0.42 + vec3(1.0, 0.38, 0.12) * rim * glow_strength * 0.28;
	COLOR = vec4(result, tex.a);
}
