shader_type spatial;
// Additive, unshaded light for the delve beacons. One shader covers both parts
// of a beacon: `shape = 0` is the vertical column (CylinderMesh, VERTEX.y gives
// the height) and `shape = 1` is the soft ring it pools on the floor
// (PlaneMesh, UV runs 0..1 across the square).
//
// Everything moves on TIME - travelling bands up the column, a slow ripple
// around it and a rotating shimmer on the ring - so the node needs no
// _process at all. Additive blending plus depth_draw_never means the light can
// only ever brighten the floor, never paint a dark quad over it.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 beam_color : source_color = vec4(1.0, 0.78, 0.38, 1.0);
uniform float shape = 0.0;
uniform float energy = 1.0;
uniform float beam_height = 7.0;
uniform float ring_inner = 0.21;
uniform float ring_outer = 0.58;
uniform float band_speed = 3.1;
uniform float band_count = 21.0;
uniform float agitation = 0.0;

varying float v_along;

void vertex() {
	v_along = clamp(VERTEX.y / max(beam_height * 0.5, 0.001) * 0.5 + 0.5, 0.0, 1.0);
}

void fragment() {
	vec3 tint = beam_color.rgb;
	float fade = 0.0;

	if (shape < 0.5) {
		// Column: bright core (the longest chord through the cylinder), soft
		// silhouette, bands climbing upward and a hot foot where it meets the floor.
		float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
		float body = smoothstep(0.02, 0.78, facing);
		float lift = smoothstep(0.0, 0.05, v_along) * (1.0 - smoothstep(0.42, 0.86, v_along));
		float foot = mix(1.3, 1.0, smoothstep(0.0, 0.3, v_along));
		float speed = band_speed * (1.0 + agitation * 0.8);
		float bands = 0.58 + 0.42 * sin(v_along * band_count - TIME * speed);
		float ripple = 0.72 + 0.28 * sin(UV.x * 19.0 + TIME * 1.6 * (1.0 + agitation) + v_along * 6.0);
		fade = body * lift * foot * mix(0.6, 1.0, bands) * ripple * energy * 0.74;
		tint *= 0.8 + 0.35 * bands;
	} else {
		// Ground ring: a soft band with a rotating shimmer and a faint pool of
		// light toward the middle so the beacon visibly owns its footprint.
		vec2 p = UV * 2.0 - 1.0;
		float reach = length(p);
		float middle = mix(ring_inner, ring_outer, 0.5);
		float band = smoothstep(ring_inner, middle, reach) * (1.0 - smoothstep(middle, ring_outer, reach));
		float angle = atan(p.y, p.x);
		float shimmer = 0.6 + 0.4 * sin(angle * 3.0 - TIME * 2.2);
		float opening = 1.0 - smoothstep(ring_outer, min(ring_outer + 0.18, 1.0), reach);
		float pool = (1.0 - smoothstep(0.0, ring_outer, reach)) * 0.18;
		fade = (band * shimmer * opening * 0.9 + pool) * energy;
		tint *= 0.85 + 0.3 * shimmer;
	}

	fade = clamp(fade, 0.0, 1.0);
	ALBEDO = tint * fade * 1.35;
	ALPHA = fade;
}
