shader_type spatial;
// Energy Shield ward shell: a warm yellow rim that pulses like a held breath.
// Presentation only, additive so it reads over armour in every light.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.84, 0.28, 1.0);
uniform float energy = 1.15;
uniform float rim_power = 2.7;
uniform float band_density = 26.0;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - clamp(facing, 0.0, 1.0), rim_power);
	float bands = 0.88 + 0.12 * sin(TIME * 2.4 - UV.y * band_density);
	float breath = 0.94 + 0.06 * sin(TIME * 1.7);
	ALBEDO = tint.rgb * energy * bands * breath;
	// The shell is drawn with both faces so the far rim survives; keep the
	// centre thin or the doubled fill hides the body inside it.
	ALPHA = clamp(rim * 0.95 + 0.02, 0.0, 1.0) * tint.a;
}
