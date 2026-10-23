shader_type spatial;
// Flat arena floor. World-space UVs keep the turf continuous across the slab
// regardless of its box UVs; macro mottling breaks the tile and vertex colour
// (when present) lets the scene tint sections of the field.
render_mode cull_back;

uniform sampler2D grass_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 grass_tint : source_color = vec4(1.0);
uniform float tile = 6.0;
uniform float macro_tile = 22.0;
uniform float detail_strength = 0.9;
uniform vec2 detail_fade = vec2(70.0, 120.0);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 sample = texture(grass_texture, v_world.xz / max(tile, 0.001)).rgb;
	vec3 macro_sample = texture(macro_texture, v_world.xz / max(macro_tile, 0.001)).rgb;
	vec3 detailed = sample * grass_tint.rgb * mix(vec3(1.0), macro_sample * 1.3, 0.25 * detail_strength);
	vec3 macro_colour = macro_sample * grass_tint.rgb * 0.9;
	float distance_to_camera = length(VERTEX);
	float detail = 1.0 - smoothstep(detail_fade.x, detail_fade.y, distance_to_camera);
	ALBEDO = mix(macro_colour, detailed, detail) * COLOR.rgb;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
