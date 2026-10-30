shader_type spatial;
// Grass/flower/fern clumps. UV2 = (wind phase, wind weight). UV2.y rises toward
// the blade tip so the base stays planted. Camera-distance fade starts just
// before the MultiMesh visibility range ends, hiding the chunk cut.
//
// A clump is lit as a soft mound, not as boards: the card normal is bent toward
// the sky (`normal_up`), so every card of a tuft - front face or back - takes
// the same light the ground under it does. The base sits in its own shade
// (`base_shade`, by the wind weight) and light passes through a blade from behind
// (`translucency`), so a torch beyond the verge rims the grass instead of
// blacking it out.
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.35;
uniform float wind_strength = 0.12;
uniform float wind_speed = 1.2;
uniform float wind_scale = 0.45;
uniform float fade_start = 58.0;
uniform float fade_end = 72.0;
uniform float base_shade : hint_range(0.0, 1.0) = 0.78;
uniform float normal_up : hint_range(0.0, 1.0) = 0.6;
uniform float translucency : hint_range(0.0, 1.0) = 0.3;

void vertex() {
	float phase = UV2.x;
	float weight = UV2.y;
	float t = TIME * wind_speed;
	vec2 origin = MODEL_MATRIX[3].xz;
	float gust = sin(t * 1.3 + phase * 6.283185 + dot(origin, vec2(wind_scale, wind_scale * 0.7)));
	float flutter = sin(t * 2.9 + phase * 4.1 + origin.x * wind_scale * 2.0);
	VERTEX.x += (gust + flutter * 0.35) * wind_strength * weight;
	VERTEX.z += (gust * 0.6 - flutter * 0.25) * wind_strength * weight;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec4 colour = tex * COLOR * tint;
	// Fragment VERTEX is view-space, so its length is camera distance.
	float distance_to_camera = length(VERTEX);
	float fade = 1.0 - smoothstep(fade_start, fade_end, distance_to_camera);
	float rise = smoothstep(0.0, 1.0, UV2.y);
	vec3 albedo = colour.rgb * mix(base_shade, 1.0, rise);
	ALBEDO = albedo;
	ALPHA = colour.a * fade;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	ROUGHNESS = 0.9;
	SPECULAR = 0.08;
	AO = mix(0.45, 1.0, rise);
	BACKLIGHT = albedo * translucency;
	vec3 facing = FRONT_FACING ? NORMAL : -NORMAL;
	vec3 sky = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	NORMAL = normalize(mix(facing, sky, normal_up));
}
