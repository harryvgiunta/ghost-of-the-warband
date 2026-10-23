shader_type spatial;
// Frontier terrain: world-space UVs blend grass/dirt/rock. Vertex alpha is the
// dirt weight (laid by the world generator along trails), world-normal slope is
// the rock weight, vertex RGB tints the result and a low-frequency macro map
// breaks up repetition. High-frequency detail fades to macro colour with
// distance so far hillsides stay calm.
render_mode cull_back;

uniform sampler2D grass_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 grass_tint : source_color = vec4(1.0);
uniform vec4 dirt_tint : source_color = vec4(1.0);
uniform vec4 rock_tint : source_color = vec4(1.0);
uniform float tile = 7.0;
uniform float dirt_tile = 6.0;
uniform float rock_tile = 5.0;
uniform float macro_tile = 27.0;
uniform float detail_strength = 1.0;
uniform vec2 detail_fade = vec2(95.0, 150.0);

varying vec3 v_world;
varying vec3 v_world_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float dirt_weight = clamp(COLOR.a, 0.0, 1.0);
	float slope = 1.0 - clamp(v_world_normal.y, 0.0, 1.0);
	float rock_weight = smoothstep(0.16, 0.52, slope);

	vec3 grass_sample = texture(grass_texture, v_world.xz / max(tile, 0.001)).rgb;
	vec3 dirt_sample = texture(dirt_texture, v_world.xz / max(dirt_tile, 0.001)).rgb;
	vec3 rock_sample = texture(rock_texture, v_world.xz / max(rock_tile, 0.001)).rgb;
	vec3 macro_sample = texture(macro_texture, v_world.xz / max(macro_tile, 0.001)).rgb;

	// Tints are pale multipliers so the authored textures keep their value range.
	vec3 albedo = mix(grass_sample * grass_tint.rgb, dirt_sample * dirt_tint.rgb, dirt_weight);
	albedo = mix(albedo, rock_sample * rock_tint.rgb, rock_weight);
	albedo *= mix(vec3(1.0), macro_sample * 1.35, 0.3 * detail_strength);

	// Distance detail fade: keep the macro colour/variation, drop the busy tiling.
	vec3 macro_colour = macro_sample * mix(grass_tint.rgb, dirt_tint.rgb, dirt_weight);
	macro_colour = mix(macro_colour, macro_sample * rock_tint.rgb, rock_weight);
	float distance_to_camera = length(VERTEX);
	float detail = 1.0 - smoothstep(detail_fade.x, detail_fade.y, distance_to_camera);
	ALBEDO = mix(macro_colour, albedo, detail) * COLOR.rgb;

	ROUGHNESS = 0.94;
	SPECULAR = 0.12;
}
