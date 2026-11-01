shader_type spatial;
// The night falling down a shaft: an additive cone, brightest where the eye looks
// through the most of it and at the hole it comes in by, with slow dust drifting
// through it. The mesh is a cylinder centred on its own origin, `height` tall.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec3 colour : source_color = vec3(0.6, 0.72, 0.95);
uniform float strength = 0.16;
uniform float height = 6.0;
uniform sampler2D noise_texture : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 v_local;
varying vec3 v_world;

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 1.8);
	float up = clamp(v_local.y / height + 0.5, 0.0, 1.0);
	float fade = smoothstep(0.0, 0.3, up) * (0.3 + 0.7 * up * up);
	float dust = texture(noise_texture, v_world.xz * 0.45 + vec2(TIME * 0.011, v_world.y * 0.08 - TIME * 0.006)).b;
	ALBEDO = colour;
	ALPHA = clamp(strength * core * fade * (0.7 + 0.6 * dust), 0.0, 1.0);
}
