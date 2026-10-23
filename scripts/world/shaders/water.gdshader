shader_type spatial;
// Pond water. Two scrolling normal-map layers (or a procedural fallback when
// water_normal.png is absent) perturb a world-space normal; fresnel pulls the
// colour toward the sky tint at grazing angles. No screen texture, no compute:
// Compatibility-safe.
render_mode cull_disabled, blend_mix;

uniform sampler2D ripple_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float ripple_on : hint_range(0.0, 1.0) = 1.0;
uniform vec4 shallow_color : source_color = vec4(0.32, 0.47, 0.42, 1.0);
uniform vec4 deep_color : source_color = vec4(0.11, 0.24, 0.25, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.72, 0.82, 0.84, 1.0);
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.32;
uniform float ripple_scale = 0.18;
uniform float ripple_speed = 0.05;
uniform float fresnel_power = 3.5;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.84;
uniform float wave_height = 0.025;

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ripple = sin(v_world.x * 0.65 + TIME * 0.8) + sin(v_world.z * 0.83 - TIME * 0.65);
	VERTEX.y += ripple * wave_height * 0.5;
}

void fragment() {
	vec2 flow = TIME * ripple_speed * vec2(0.7, 0.35);
	vec2 uv_a = v_world.xz * ripple_scale + flow;
	vec2 uv_b = v_world.xz * ripple_scale * 1.9 - flow.yx * 1.4;
	vec2 slope = vec2(0.0);
	if (ripple_on > 0.5) {
		vec3 normal_a = texture(ripple_texture, uv_a).xyz * 2.0 - 1.0;
		vec3 normal_b = texture(ripple_texture, uv_b).xyz * 2.0 - 1.0;
		slope = (normal_a.xy + normal_b.xy) * 0.5;
	} else {
		// Missing normal map: cheap analytic ripples so the water still moves.
		slope = vec2(
			sin(uv_a.x * 9.0 + TIME * 1.1) + sin(uv_b.x * 13.0),
			cos(uv_a.y * 11.0 - TIME * 0.8) + cos(uv_b.y * 15.0)
		) * 0.06;
	}
	vec3 world_normal = normalize(vec3(slope.x * ripple_strength, 1.0, slope.y * ripple_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);

	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world);
	float fresnel = pow(1.0 - clamp(dot(world_normal, view_dir), 0.0, 1.0), fresnel_power);
	vec3 body = mix(deep_color.rgb, shallow_color.rgb, clamp(0.55 + world_normal.x * 0.35, 0.0, 1.0));
	ALBEDO = mix(body, sky_tint.rgb, fresnel * 0.7);
	EMISSION = sky_tint.rgb * fresnel * 0.08;
	ALPHA = clamp(base_alpha + fresnel * 0.12, 0.0, 1.0);
	ROUGHNESS = 0.08;
	SPECULAR = 0.55;
	METALLIC = 0.0;
}
