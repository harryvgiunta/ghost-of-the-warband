shader_type spatial;
// Authored flame cards for the village firepit and the forest camp.
//
// The 2x2 atlas holds four hand-drawn tongues. Every card cross-fades between
// two neighbouring cells so the fire morphs continuously instead of stepping
// through four stills, and a rising noise field leans the body and flutters the
// tip, so one card reads as a live tongue rather than a painted sprite. Cards
// are gathered into the merged fire mesh, so each one carries its own phase in
// its vertex colour and is sampled at a different rate.
//
// Where a card enters the ash bed, the charred logs or the cauldron, the scene
// depth fades it out: a flame column intersecting the ground keeps a soft edge
// instead of drawing a hard cut line.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D albedo_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
// Tongues per second: how fast the fire walks through the atlas.
uniform float frame_rate = 6.5;
// Multiplier on the authored tongue colour; the filmic tonemap turns the core
// white and leaves the tips orange.
uniform float glow = 1.32;
// How far the rising noise field leans a tongue, in card widths.
uniform float waver = 0.22;
uniform float warp_scale = 2.1;
uniform float rise_speed = 0.85;
// Global breathing of the whole fire, on top of the per-card motion.
uniform float flicker = 0.16;
// Metres over which a card fades out against the geometry behind it.
uniform float soft_distance = 0.34;
uniform vec3 hot_color : source_color = vec3(1.0, 0.88, 0.62);
uniform vec3 cool_color : source_color = vec3(1.0, 0.40, 0.10);

// Baked per card into the merged mesh's vertex colour.
varying float card_seed;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.55;
	for (int octave = 0; octave < 3; octave++) {
		total += value_noise(p) * amplitude;
		p *= 2.13;
		amplitude *= 0.5;
	}
	return total / 0.9625;
}

// The 512 px atlas pastes four 232 px cells with a 16 px gutter on each side, so
// a cell is 0.453 of the atlas, not half: sampling a 0.5 span reaches into the
// neighbouring tongue and the gutter, which is what draws rectangle edges across
// a flame.
const float CELL_SPAN = 0.453125;
vec2 cell_uv(float frame, vec2 uv) {
	vec2 origin = vec2(16.0 + mod(frame, 2.0) * 248.0, 16.0 + floor(frame / 2.0) * 248.0) / 512.0;
	return origin + uv * CELL_SPAN;
}

void vertex() {
	card_seed = COLOR.r;
}

void fragment() {
	float t = TIME;
	float seed = card_seed * 6.2831853;

	// Two neighbouring tongues, cross-faded over the step they used to snap on.
	float tick = t * frame_rate + card_seed * 4.0;
	float frame_a = mod(floor(tick), 4.0);
	float frame_b = mod(frame_a + 1.0, 4.0);
	float morph = smoothstep(0.28, 1.0, fract(tick));

	vec2 uv = clamp(UV, vec2(0.002), vec2(0.998));
	float lift = uv.y;
	// The field scrolls upward and displaces more toward the tip: that gradient
	// is what makes a flame lean and lick instead of drifting as a whole sheet.
	vec2 flow = vec2(uv.x * warp_scale + card_seed * 19.0,
		uv.y * warp_scale * 1.15 - t * rise_speed);
	float lean = fbm(flow) - 0.5;
	float flutter = fbm(flow * 2.2 + vec2(3.1, -t * rise_speed * 0.7)) - 0.5;
	vec2 warped = uv;
	warped.x += (lean * 1.6 + flutter * 0.55) * waver * lift;
	warped.y += flutter * 0.06 * lift;
	warped = clamp(warped, vec2(0.002), vec2(0.998));

	vec4 tex = mix(texture(albedo_texture, cell_uv(frame_a, warped)),
		texture(albedo_texture, cell_uv(frame_b, warped)), morph);

	// Heat down the tongue: white-hot where the fuel sits, deep orange at the tip.
	vec3 ramp = mix(cool_color, hot_color, smoothstep(1.0, 0.12, lift));
	float breathe = 1.0 + flicker * (sin(t * 8.3 + seed) * 0.6 + sin(t * 13.9 + seed * 1.7) * 0.4);
	vec3 color = tex.rgb * mix(vec3(1.0), ramp, 0.35) * glow * breathe;

	// Soft contact with whatever the card is cutting through.
	vec3 ndc = vec3(SCREEN_UV, texture(depth_texture, SCREEN_UV).r) * 2.0 - 1.0;
	vec4 scene = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	scene.xyz /= scene.w;
	float scene_distance = -scene.z;
	float fragment_distance = -VERTEX.z;
	float contact = smoothstep(0.0, soft_distance, scene_distance - fragment_distance);

	ALBEDO = color;
	ALPHA = tex.a * contact;
}
