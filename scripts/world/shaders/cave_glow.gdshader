shader_type spatial;
// Glowworms on a damp roof: a cold point of light where each larva clings and a
// thread of beaded silk hanging below it. Drawn additively, unlit and unfogged -
// it is the light - and turned to face the eye in the vertex stage.
//
// The mesh is one strip: UV.y runs 0 at the roof to 1 at the thread's end, UV.x
// is -0.5/0.5 across. INSTANCE_CUSTOM: r = thread length (m), g = phase,
// b = brightness.
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec3 glow : source_color = vec3(0.45, 0.95, 1.0);
uniform float energy = 1.0;
// The first `head` of the strip is the light itself, `bulb` metres across.
const float head = 0.12;
const float bulb = 0.05;

varying float v_t;
varying float v_side;
varying float v_bright;

void vertex() {
	float t = UV.y;
	float length_m = INSTANCE_CUSTOM.r;
	float phase = INSTANCE_CUSTOM.g * 40.0;
	float y = t < head ? -t / head * bulb : -(bulb + (t - head) / (1.0 - head) * length_m);
	float sway = sin(TIME * 0.6 + phase) * 0.025 * (-y);
	vec4 view = MODELVIEW_MATRIX * vec4(sway, y, 0.0, 1.0);
	float width = t < head ? bulb : 0.0024;
	view.x += UV.x * width * 2.0;
	POSITION = PROJECTION_MATRIX * view;
	v_t = t;
	v_side = UV.x * 2.0;
	v_bright = INSTANCE_CUSTOM.b;
}

void fragment() {
	float light = 0.0;
	if (v_t < head) {
		float d = length(vec2(v_side, v_t / head * 2.0 - 1.0));
		light = pow(1.0 - smoothstep(0.0, 1.0, d), 2.2) * 1.6;
	} else {
		float along = (v_t - head) / (1.0 - head);
		float bead = pow(0.5 + 0.5 * sin(along * 46.0), 18.0);
		light = (0.08 + 0.55 * bead) * (1.0 - along * 0.6) * (1.0 - abs(v_side));
	}
	ALBEDO = glow * energy * (0.6 + 0.6 * v_bright);
	ALPHA = clamp(light, 0.0, 1.0);
}
