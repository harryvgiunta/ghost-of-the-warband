shader_type spatial;
// Authored flame cards for the village firepit.
//
// The 2x2 atlas holds four hand-drawn tongues; each card cycles through them so a
// ring of cards reads as a live fire without any particle system. Every card gets
// its own phase and horizontal waver from its baked world position, because the
// whole fire is one merged mesh with one material.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform float frame_rate = 11.0;
uniform float glow = 1.35;
uniform float waver = 0.016;

varying float seed;

void vertex() {
	seed = dot(VERTEX, vec3(0.37, 0.11, 0.53));
}

void fragment() {
	float tick = TIME * frame_rate + seed * 2.7;
	float frame = mod(floor(tick), 4.0);
	vec2 cell = vec2(mod(frame, 2.0), floor(frame / 2.0)) * 0.5;
	// a slow sideways breath, stronger towards the tip
	float sway = sin(TIME * 3.1 + seed * 5.3 + UV.y * 5.0) * waver * UV.y;
	vec2 uv = cell + clamp(UV + vec2(sway, 0.0), vec2(0.002), vec2(0.998)) * 0.5;
	vec4 tex = texture(albedo_texture, uv);
	ALBEDO = tex.rgb * glow;
	ALPHA = tex.a;
	EMISSION = tex.rgb * 0.7 * tex.a;
}
