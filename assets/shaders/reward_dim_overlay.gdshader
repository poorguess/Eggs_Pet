shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float dim_strength : hint_range(0.0, 1.0) = 0.68;
uniform float grayscale_strength : hint_range(0.0, 1.0) = 0.72;
uniform vec2 focus_center = vec2(0.5, 0.47);
uniform float focus_radius : hint_range(0.0, 1.0) = 0.36;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.28;

void fragment() {
	vec4 scene_color = texture(screen_texture, SCREEN_UV);
	float gray = dot(scene_color.rgb, vec3(0.299, 0.587, 0.114));
	vec3 desaturated = mix(scene_color.rgb, vec3(gray), grayscale_strength);

	vec2 delta = SCREEN_UV - focus_center;
	delta.x *= 0.5625;
	float focus = smoothstep(focus_radius * 0.35, focus_radius, length(delta));
	float vignette = smoothstep(0.28, 0.82, distance(SCREEN_UV, vec2(0.5)));
	float darken = dim_strength + vignette * vignette_strength - (1.0 - focus) * 0.18;

	vec3 result = desaturated * (1.0 - clamp(darken, 0.0, 0.92));
	COLOR = vec4(result, 1.0);
}
