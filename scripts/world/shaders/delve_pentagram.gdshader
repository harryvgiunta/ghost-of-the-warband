shader_type spatial;
// The delve pentagram. scripts/delve_pentagram.gd builds the star outline and
// both rings as flat ribbon meshes; UV.x is the distance travelled along the
// ribbon in metres and UV.y runs across it, so one shader keeps every stroke the
// same thickness and sends a pulse travelling around the figure.
//
// `energy` is the master fade (0 hides the sigil completely) and `ritual` pushes
// the demonic overdrive: faster travelling sparks and a hotter colour. All
// motion comes from TIME. Additive blending with depth_draw_never guarantees the
// sigil can only brighten the floor slab.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 sigil_color : source_color = vec4(1.0, 0.46, 0.12, 1.0);
uniform float energy = 0.0;
uniform float ritual = 0.0;
uniform float edge_softness = 0.34;
uniform float pulse_speed = 2.0;
uniform float pulse_length = 3.6;

varying float v_along;
varying float v_across;

void vertex() {
	v_along = UV.x;
	v_across = clamp(UV.y, 0.0, 1.0);
}

void fragment() {
	float edge = smoothstep(0.0, edge_softness, v_across) * smoothstep(0.0, edge_softness, 1.0 - v_across);
	float travel = sin((v_along / max(pulse_length, 0.05)) * TAU - TIME * pulse_speed);
	float glow = 0.62 + 0.38 * travel;
	float sparks = pow(0.5 + 0.5 * sin((v_along / max(pulse_length, 0.05)) * TAU * 5.0 - TIME * (pulse_speed * 2.6 + 3.2)), 4.0);
	float fade = edge * (glow + sparks * ritual * 1.7) * energy;
	fade = clamp(fade, 0.0, 1.0);
	ALBEDO = sigil_color.rgb * fade * (1.35 + ritual * 0.9);
	ALPHA = fade;
}
