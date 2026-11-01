shader_type spatial;
// The Hollow's small life, animated in the vertex stage so a room's worth of bats
// or rats is one MultiMesh and one draw. Every mesh faces -Z with its wings or
// legs spread along X (`assets/world/cave/cave_fauna.glb`).
//
// INSTANCE_CUSTOM: r = how much it is moving (a bat or moth on the wing 1, folded
// at roost 0; a rat's run 0..1), g = its phase, b = its shade.
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// 0 bat, 1 rat, 2 spider, 3 moth.
uniform int kind = 0;

varying float v_shade;

// A wing vertex turned about the body's long axis at the shoulder.
vec3 wing(vec3 v, float root, float reach, float angle, float spread) {
	float span = abs(v.x);
	float side = v.x >= 0.0 ? 1.0 : -1.0;
	float r = max(span - root, 0.0);
	float bend = smoothstep(0.0, reach - root, r);
	float a = angle * bend;
	return vec3(side * (min(span, root) + r * cos(a) * mix(1.0, spread, bend)), v.y + r * sin(a), v.z);
}

void vertex() {
	float motion = INSTANCE_CUSTOM.r;
	float t = TIME + INSTANCE_CUSTOM.g * 31.0;
	v_shade = 0.8 + 0.4 * INSTANCE_CUSTOM.b;
	if (kind == 0) {
		// Flying: a deep stroke with the tips lagging; roosting: wings folded down
		// and in round the body.
		float flap = sin(t * 13.0 - abs(VERTEX.x) * 9.0) * 0.95;
		float angle = mix(-1.3, flap, motion);
		VERTEX = wing(VERTEX, 0.014, 0.17, angle, mix(0.3, 1.0, motion));
		VERTEX.y -= sin(t * 13.0) * 0.006 * motion;
	} else if (kind == 3) {
		float flap = sin(t * 41.0) * 1.15;
		VERTEX = wing(VERTEX, 0.002, 0.026, mix(0.6, flap, motion), 1.0);
	} else if (kind == 1) {
		// Gait bob while running, the tail swinging behind (+Z), and a sniffing
		// head (-Z) while still.
		VERTEX.y += abs(sin(t * 24.0)) * 0.006 * motion;
		float tail = smoothstep(0.07, 0.25, VERTEX.z);
		VERTEX.x += sin(t * (4.0 + 9.0 * motion) - VERTEX.z * 18.0) * tail * (0.02 + 0.03 * motion);
		float head = smoothstep(-0.06, -0.12, VERTEX.z);
		VERTEX.y += sin(t * 15.0) * 0.004 * head * (1.0 - motion);
		VERTEX.x += sin(t * 3.1) * 0.006 * head * (1.0 - motion);
	} else {
		// A spider is still until it is not.
		float leg = smoothstep(0.015, 0.05, length(VERTEX.xz));
		float twitch = step(0.94, sin(t * 0.9)) * sin(t * 31.0);
		VERTEX.y += leg * twitch * 0.003;
	}
}

void fragment() {
	ALBEDO = COLOR.rgb * v_shade;
	ROUGHNESS = 0.78;
	SPECULAR = 0.3;
}
