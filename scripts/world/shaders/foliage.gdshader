shader_type spatial;
// Alpha-scissored foliage cards. UV2 = (wind phase, wind weight) baked by TreeKit,
// COLOR carries baked crown shading and the MultiMesh instance tint.
render_mode cull_disabled, depth_prepass_alpha;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float alpha_scissor : hint_range(0.0, 1.0) = 0.38;
uniform float wind_strength = 0.3;
uniform float wind_speed = 1.0;
uniform float wind_scale = 0.3;

void vertex() {
	float phase = UV2.x;
	float weight = UV2.y;
	float t = TIME * wind_speed;
	// Two frequencies keep big crowns from moving as one rigid sheet. The instance
	// origin offsets the phase so neighbouring trees never sway in lockstep.
	vec2 origin = MODEL_MATRIX[3].xz;
	float wave = sin(t * 1.7 + phase * 6.283185 + dot(origin, vec2(wind_scale, wind_scale * 1.3)));
	float wave2 = sin(t * 0.9 + phase * 3.7 + origin.y * wind_scale * 1.7);
	VERTEX.x += wave * wind_strength * weight;
	VERTEX.z += wave2 * wind_strength * weight * 0.65;
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec4 colour = tex * COLOR * tint;
	ALBEDO = colour.rgb;
	ALPHA = colour.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	ROUGHNESS = 0.9;
	SPECULAR = 0.08;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
