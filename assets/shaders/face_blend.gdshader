shader_type canvas_item;
// 换脸混合：把 warp 后的五官贴图按羽化遮罩叠到手绘底图上。
// gain 做肤色增益匹配（底图肤色均值 / 照片肤色均值），缓解照片与手绘的色差。

uniform sampler2D warp_tex : filter_linear, repeat_disable;
uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform vec3 gain = vec3(1.0, 1.0, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float feather_px = 6.0;
uniform vec2 mask_size = vec2(320.0, 395.0);

float feathered_mask(vec2 uv) {
	vec2 r = feather_px / mask_size;
	float m = texture(mask_tex, uv).r * 4.0;
	m += texture(mask_tex, uv + vec2(r.x, 0.0)).r;
	m += texture(mask_tex, uv - vec2(r.x, 0.0)).r;
	m += texture(mask_tex, uv + vec2(0.0, r.y)).r;
	m += texture(mask_tex, uv - vec2(0.0, r.y)).r;
	m += texture(mask_tex, uv + r).r;
	m += texture(mask_tex, uv - r).r;
	m += texture(mask_tex, uv + vec2(r.x, -r.y)).r;
	m += texture(mask_tex, uv + vec2(-r.x, r.y)).r;
	return m / 12.0;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec4 warp = texture(warp_tex, UV);
	float m = smoothstep(0.2, 0.8, feathered_mask(UV)) * warp.a * strength;
	vec3 rgb = mix(base.rgb, warp.rgb * gain, m);
	COLOR = vec4(rgb, max(base.a, warp.a * m));
}
