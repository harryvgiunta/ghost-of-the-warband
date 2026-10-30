shader_type spatial;
// Armour flair: one body's livery on the armour it wears.
//
// Every dyed, painted or finished armour surface of a warband body is drawn by
// this one shader (`scripts/armor_flair.gd` builds the materials). The authored
// StandardMaterial3D is mirrored exactly - albedo map and colour, roughness and
// metallic maps on their channels, the normal map and its depth - and the flair
// is laid over it in the skeleton's *rest* space, which the rig bakes into
// CUSTOM0. Rest space does not move when the body does, so a stripe drawn across
// the chest stays on the chest through a swing, a roll and a ragdoll.
//
// Rest space: metres, +Y up, the body faces +Z, its left hand is +X, arms out in
// a T at y 1.456, the legs at x +-0.09.
render_mode cull_disabled;

// ---- the authored material, mirrored ----
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float roughness = 1.0;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float metallic = 0.0;
uniform sampler2D metallic_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 metallic_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform bool normal_enabled = false;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float normal_scale = 1.0;

// ---- what this surface is (ArmorFlair.ROLES) ----
uniform int role = 0;
// A darker cut of the same role (the `*_Dark` materials).
uniform float shade = 1.0;
// Mean linear luminance of the texels this role re-colours: the authored map
// divided by it is the weave, the grain and the grime with the colour taken out.
uniform float veil = 0.2;
// The outfit atlas's second class (its leather), measured the same way.
uniform float veil_alt = 0.2;
// 0 head, 1 chest, 2 hands, 3 legs, 4 feet.
uniform int piece = 0;
// The piece's open edges in rest space: x lowest hem, y highest top, z outer
// cuff |x|, w inner cuff |x|; -10 where the piece has no such edge.
uniform vec4 edges = vec4(-10.0);
// A cloth surcoat drawn over a mail or plate chest.
uniform bool surcoat = false;

// ---- whose colours (WarbandFlair) ----
uniform vec4 field_color : source_color = vec4(0.49, 0.16, 0.13, 1.0);
uniform vec4 charge_color : source_color = vec4(0.85, 0.81, 0.72, 1.0);
uniform vec4 thread_color : source_color = vec4(0.84, 0.68, 0.32, 1.0);
uniform float thread_metal = 0.0;
uniform vec4 paint_color : source_color = vec4(0.85, 0.81, 0.72, 1.0);
uniform vec4 stain_color : source_color = vec4(0.21, 0.11, 0.07, 1.0);
uniform vec4 fittings_color : source_color = vec4(0.82, 0.71, 0.46, 1.0);
uniform vec4 bone_color : source_color = vec4(0.85, 0.80, 0.69, 1.0);
uniform vec4 finish_tint : source_color = vec4(1.0);
uniform float finish_rough = 0.0;
uniform float finish_metal = 1.0;
uniform int design = 0;
uniform int motif = 0;
uniform int hem = 0;
uniform float seed = 0.0;

const int ROLE_CLOTH = 1;
const int ROLE_LINING = 2;
const int ROLE_OUTFIT = 3;
const int ROLE_LEATHER = 4;
const int ROLE_HIDE = 5;
const int ROLE_PLATE = 6;
const int ROLE_MAIL = 7;
const int ROLE_STEEL = 8;
const int ROLE_FITTINGS = 9;
const int ROLE_BONE = 10;

// Body landmarks in rest space.
const float CHEST_Y = 1.27;
const float BACK_Y = 1.25;
const float FRONT_SIZE = 0.072;
const float BACK_SIZE = 0.105;
const float WAIST_Y = 1.10;
const float TORSO_HALF = 0.30;
const float ARM_Y = 1.456;
const float ARM_Z = -0.07;
const float LEG_X = 0.09;
const float LEG_Z = -0.036;
const float BAND = 0.032;

varying vec3 rest;

void vertex() {
	rest = CUSTOM0.xyz;
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1.0e-10)), d / (q.x + 1.0e-10), q.x);
}

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Coverage of a signed distance (negative inside), soft over `aa`.
float cover(float d, float aa) {
	return 1.0 - smoothstep(-aa, aa, d);
}

// A square wave along `coord`: the first half of every period is covered.
float stripes(float coord, float period, float px) {
	float t = fract(coord / period);
	return cover((abs(t - 0.5) - 0.25) * period, px);
}

float xor_cover(float a, float b) {
	return a + b - 2.0 * a * b;
}

// The share of the charge colour at `p` under the body's heraldic design
// (WarbandFlair.DESIGNS, same order). Partitions and stripes run over the whole
// body - mi-parti hose, a barred hood - while the ordinaries sit on the trunk.
float design_cover(vec3 p, float px) {
	float x = p.x;
	float y = p.y;
	float trunk = float(piece == 1) * step(abs(x), TORSO_HALF) * step(0.78, y) * step(y, 1.66);
	if (design == 1) {
		return cover(-x, px);
	}
	if (design == 2) {
		return cover(y - WAIST_Y, px);
	}
	if (design == 3) {
		return xor_cover(cover(-x, px), cover(y - WAIST_Y, px));
	}
	if (design == 4) {
		return cover(-(x + (y - 1.18)) * 0.7071, px);
	}
	if (design == 5) {
		return trunk * cover(abs(x) - 0.065, px);
	}
	if (design == 6) {
		return trunk * cover(abs(y - 1.22) - 0.06, px);
	}
	if (design == 7) {
		return trunk * cover(abs(y - (1.36 - 0.8 * abs(x))) * 0.78 - 0.045, px);
	}
	if (design == 8) {
		float a = abs((y - 1.20) - x * 1.1) * 0.673;
		float b = abs((y - 1.20) + x * 1.1) * 0.673;
		return trunk * cover(min(a, b) - 0.042, px);
	}
	if (design == 9) {
		return trunk * cover(min(abs(x) - 0.048, abs(y - 1.30) - 0.048), px);
	}
	if (design == 10) {
		return trunk * cover(abs((y - 1.20) - x * 1.1) * 0.673 - 0.06, px);
	}
	if (design == 11) {
		return stripes(x + 0.0325, 0.13, px);
	}
	if (design == 12) {
		return stripes(y, 0.11, px);
	}
	if (design == 13) {
		return xor_cover(stripes(x + 0.025, 0.10, px), stripes(y, 0.10, px));
	}
	if (design == 14) {
		float a = x / 0.10 + y / 0.15;
		float b = x / 0.10 - y / 0.15;
		float scale = px * 12.0;
		return xor_cover(stripes(a, 1.0, scale), stripes(b, 1.0, scale));
	}
	return 0.0;
}

float sd_circle(vec2 p, float r) {
	return length(p) - r;
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float sd_segment(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}

// Inigo Quilez's five-pointed star.
float sd_star5(vec2 p, float r, float rf) {
	vec2 k1 = vec2(0.809016994375, -0.587785252292);
	vec2 k2 = vec2(-k1.x, k1.y);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

// The body's emblem (WarbandFlair.MOTIFS, same order) as a signed distance in
// units of its own half-size, +Y up.
float motif_sd(vec2 q) {
	vec2 s = vec2(abs(q.x), q.y);
	if (motif == 0) {
		// a skull: cranium, jaw, two sockets, the nose and the teeth
		float d = min(sd_circle(q - vec2(0.0, 0.16), 0.62), sd_box(q - vec2(0.0, -0.40), vec2(0.30, 0.24)) - 0.05);
		float holes = min(sd_circle(s - vec2(0.24, 0.06), 0.165), sd_box(q - vec2(0.0, -0.19), vec2(0.055, 0.085)));
		float teeth = sd_box(vec2(mod(q.x + 0.1, 0.2) - 0.1, q.y + 0.52), vec2(0.022, 0.12));
		holes = min(holes, max(teeth, abs(q.x) - 0.26));
		return max(d, -holes);
	}
	if (motif == 1) {
		// crossed bones, a knuckle at every end
		float d = min(sd_segment(q, vec2(-0.62, -0.62), vec2(0.62, 0.62), 0.10),
			sd_segment(q, vec2(-0.62, 0.62), vec2(0.62, -0.62), 0.10));
		vec2 r = abs(q);
		return min(d, min(sd_circle(r - vec2(0.58, 0.76), 0.14), sd_circle(r - vec2(0.76, 0.58), 0.14)));
	}
	if (motif == 2) {
		// a sun: a disc and ten tapering rays
		float r = length(q);
		float sector = 6.2831853 / 10.0;
		float off = abs(mod(atan(q.y, q.x) + sector * 0.5, sector) - sector * 0.5);
		float ray = max(off * r - 0.15 * (0.98 - r), r - 0.98);
		ray = max(ray, 0.40 - r);
		return min(sd_circle(q, 0.40), ray);
	}
	if (motif == 3) {
		// a crescent moon
		return max(sd_circle(q, 0.80), -sd_circle(q - vec2(0.34, 0.16), 0.66));
	}
	if (motif == 4) {
		// a five-pointed star
		return sd_star5(q, 0.92, 0.45);
	}
	if (motif == 5) {
		// an open eye
		float almond = max(sd_circle(q - vec2(0.0, -0.60), 0.98), sd_circle(q - vec2(0.0, 0.60), 0.98));
		return min(max(almond, -sd_circle(q, 0.31)), sd_circle(q, 0.17));
	}
	if (motif == 6) {
		// a stag's antlers over a skull boss
		float d = sd_segment(s, vec2(0.10, -0.58), vec2(0.34, -0.05), 0.075);
		d = min(d, sd_segment(s, vec2(0.34, -0.05), vec2(0.50, 0.80), 0.065));
		d = min(d, sd_segment(s, vec2(0.30, -0.14), vec2(0.06, 0.24), 0.055));
		d = min(d, sd_segment(s, vec2(0.42, 0.34), vec2(0.20, 0.64), 0.05));
		d = min(d, sd_segment(s, vec2(0.47, 0.60), vec2(0.78, 0.78), 0.045));
		return min(d, sd_circle(q - vec2(0.0, -0.70), 0.21));
	}
	// the elk rune
	float d = sd_segment(q, vec2(0.0, -0.88), vec2(0.0, 0.88), 0.085);
	return min(d, sd_segment(s, vec2(0.0, 0.08), vec2(0.56, 0.80), 0.085));
}

// The emblem on the chest piece: small on the breast, large between the
// shoulder blades, read the right way round from both sides. x = fill, y = the
// stitched outline round it.
vec2 motif_cover(vec3 p, float px) {
	if (piece != 1 || motif < 0) {
		return vec2(0.0);
	}
	bool front = p.z >= 0.0;
	float size = front ? FRONT_SIZE : BACK_SIZE;
	vec2 centre = vec2(0.0, front ? CHEST_Y : BACK_Y);
	vec2 q = (vec2(front ? p.x : -p.x, p.y) - centre) / size;
	if (abs(q.x) > 1.25 || abs(q.y) > 1.25) {
		return vec2(0.0);
	}
	float d = motif_sd(q);
	float aa = px / size;
	return vec2(cover(d, aa), cover(abs(d) - 0.07, aa));
}

// Distance inward from this piece's nearest open edge, and a coordinate along
// that edge (arc length round the limb or the trunk it circles).
vec2 band_coords(vec3 p) {
	float d = 1000.0;
	float u = 0.0;
	if (piece == 1) {
		if (edges.x > -5.0 && abs(p.x) < 0.30) {
			d = p.y - edges.x;
			u = atan(p.x, p.z) * 0.16;
		}
		if (edges.z > 0.30 && abs(p.x) > 0.32 && edges.z - abs(p.x) < d) {
			d = edges.z - abs(p.x);
			u = atan(p.y - ARM_Y, p.z - ARM_Z) * 0.06;
		}
	} else if (piece == 3) {
		d = p.y - edges.x;
		u = atan(abs(p.x) - LEG_X, p.z - LEG_Z) * 0.07;
	} else if (piece == 2) {
		d = abs(p.x) - edges.w;
		u = atan(p.y - ARM_Y, p.z - ARM_Z) * 0.05;
	} else if (piece == 4) {
		d = edges.y - p.y;
		u = atan(abs(p.x) - LEG_X, p.z - LEG_Z) * 0.07;
	} else {
		d = p.y - edges.x;
		u = atan(p.x, p.z) * 0.11;
	}
	return vec2(d, u);
}

// The border along an edge, in the body's border style (WarbandFlair.HEMS).
float band_cover(vec2 band, float px) {
	float d = band.x;
	if (d < -0.004 || d > BAND + 0.004) {
		return 0.0;
	}
	float u = band.y;
	float v = clamp(d / BAND, 0.0, 1.0);
	float aa = px / BAND;
	float c;
	if (hem == 0) {
		c = cover(abs(v - 0.5) - 0.40, aa);
	} else if (hem == 1) {
		c = max(cover(abs(v - 0.22) - 0.13, aa), cover(abs(v - 0.78) - 0.13, aa));
	} else if (hem == 2) {
		float t = abs(fract(u / 0.05) - 0.5) * 2.0;
		c = cover(abs(v - (0.16 + 0.68 * t)) - 0.15, aa);
	} else if (hem == 3) {
		vec2 cell = vec2((fract(u / 0.03) - 0.5) * 0.03 / BAND, v - 0.5);
		c = cover(length(cell) - 0.30, aa);
	} else if (hem == 4) {
		c = cover(abs(v - 0.5) - 0.16, aa) * cover(abs(fract(u / 0.024) - 0.5) - 0.28, px / 0.024);
	} else {
		float high = step(0.5, fract(u / 0.05));
		c = cover(abs(v - mix(0.30, 0.70, high)) - 0.20, aa);
	}
	// every border but the plain band keeps a fine rule along the edge itself
	if (hem != 0) {
		c = max(c, cover(abs(v - 0.05) - 0.05, aa));
	}
	return c;
}

// The shape of a sleeveless surcoat over a mail or plate trunk, as a signed
// distance in metres (negative on the cloth).
float surcoat_sd(vec3 p) {
	if (!surcoat || piece != 1) {
		return 1.0;
	}
	float bottom = max(edges.x + 0.05, 0.86);
	float half_width = 0.205 - max(p.y - 1.38, 0.0) * 1.1;
	return max(max(abs(p.x) - half_width, bottom - p.y), p.y - 1.56);
}

// Satin stitches: a fine twill of light across the thread that fades out
// before it can alias.
float stitch(vec3 p, float px) {
	float phase = dot(p, vec3(1.0, 1.4, 0.6)) * 1400.0;
	float amp = 0.20 * clamp(1.0 - px * 1400.0 * 0.4, 0.0, 1.0);
	return 1.0 - amp + amp * sin(phase);
}

// Chipped paint: where the pigment survived.
float paint_wear(vec3 p) {
	vec2 w = vec2(p.x + p.z * 0.7, p.y);
	float n = value_noise(w * 42.0 + seed * 17.0) * 0.65 + value_noise(w * 120.0 + seed * 5.0) * 0.35;
	return smoothstep(0.30, 0.42, n);
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 base = albedo.rgb * tex.rgb;
	float rough = roughness * dot(texture(roughness_texture, UV), roughness_channel);
	float metal = metallic * dot(texture(metallic_texture, UV), metallic_channel);
	vec3 nmap = normal_enabled ? texture(normal_texture, UV).rgb : vec3(0.5, 0.5, 1.0);
	float depth = normal_enabled ? normal_scale : 0.0;
	// One screen pixel, measured in rest-space metres: what every edge is soft over.
	float px = max(length(fwidth(rest)), 1.0e-5);
	float lum = luma(base);
	vec3 color = base;

	// How much of this texel is the body's own cloth, and how much is leather.
	float cloth = 0.0;
	float leather = 0.0;
	vec3 cloth_base = vec3(0.0);
	if (role == ROLE_CLOTH) {
		cloth = 1.0;
		cloth_base = mix(field_color.rgb, charge_color.rgb, design_cover(rest, px))
			* clamp(lum / max(veil, 1.0e-4), 0.25, 2.5) * shade;
	} else if (role == ROLE_LINING) {
		// A lining is the garment's own dye worked darker, not a second colour.
		cloth = 1.0;
		cloth_base = mix(field_color.rgb, charge_color.rgb, 0.18) * 0.5
			* clamp(lum / max(veil, 1.0e-4), 0.25, 2.5) * shade;
	} else if (role == ROLE_OUTFIT) {
		vec3 hsv = rgb_to_hsv(base);
		float bare_metal = 1.0 - smoothstep(0.3, 0.6, metal);
		cloth = smoothstep(0.16, 0.21, hsv.x) * (1.0 - smoothstep(0.46, 0.52, hsv.x))
			* smoothstep(0.15, 0.30, hsv.y) * bare_metal;
		leather = max(1.0 - smoothstep(0.10, 0.14, hsv.x), smoothstep(0.93, 0.97, hsv.x))
			* smoothstep(0.25, 0.40, hsv.y) * bare_metal * (1.0 - cloth);
		cloth_base = mix(field_color.rgb, charge_color.rgb, design_cover(rest, px))
			* clamp(lum / max(veil, 1.0e-4), 0.25, 2.5);
		color = mix(color, stain_color.rgb * clamp(lum / max(veil_alt, 1.0e-4), 0.40, 1.60), leather);
	} else if (role == ROLE_LEATHER) {
		color = stain_color.rgb * clamp(lum / max(veil, 1.0e-4), 0.40, 1.60) * shade;
	} else if (role == ROLE_HIDE) {
		color = stain_color.rgb * clamp(lum / max(veil, 1.0e-4), 0.40, 1.60);
	} else if (role == ROLE_FITTINGS) {
		color = fittings_color.rgb * clamp(lum / max(veil, 1.0e-4), 0.55, 1.30);
	} else if (role == ROLE_BONE) {
		color = bone_color.rgb * clamp(lum / max(veil, 1.0e-4), 0.50, 1.25);
	} else if (role == ROLE_PLATE || role == ROLE_MAIL || role == ROLE_STEEL) {
		color = base * finish_tint.rgb;
		rough = clamp(rough + finish_rough, 0.05, 1.0);
		metal *= finish_metal;
	}

	// A surcoat turns the trunk of a mail or plate chest into livery cloth, with a
	// thread border round its own edge.
	float coat_sd = surcoat_sd(rest);
	float coat = 0.0;
	if (coat_sd < px && (role == ROLE_PLATE || role == ROLE_MAIL || role == ROLE_STEEL
			|| role == ROLE_FITTINGS)) {
		coat = cover(coat_sd, px);
		vec3 weave = vec3(0.92 + 0.08 * value_noise(vec2(rest.x * 900.0, rest.y * 60.0)));
		vec3 coat_color = mix(field_color.rgb, charge_color.rgb, design_cover(rest, px)) * weave;
		color = mix(color, coat_color, coat);
		rough = mix(rough, 0.9, coat);
		metal = mix(metal, 0.0, coat);
		depth = mix(depth, 0.0, coat);
		cloth = max(cloth, coat);
		cloth_base = coat_color;
	}

	if (cloth > 0.0) {
		color = mix(color, cloth_base, cloth);
		rough = mix(rough, max(rough, 0.80), cloth);
		metal = mix(metal, 0.0, cloth);
		// Embroidery: the border along the open edges and the emblem.
		float thread = 0.0;
		if (coat > 0.0) {
			thread = cover(abs(coat_sd + BAND * 0.32) - BAND * 0.22, px) * coat;
		} else {
			thread = band_cover(band_coords(rest), px);
		}
		vec2 emblem = motif_cover(rest, px);
		vec3 stitched = thread_color.rgb * stitch(rest, px);
		float sewn = max(thread, emblem.x) * cloth;
		color = mix(color, stitched, sewn);
		color = mix(color, thread_color.rgb * 0.22, emblem.y * (1.0 - emblem.x) * cloth * 0.85);
		rough = mix(rough, mix(0.62, 0.36, thread_metal), sewn);
		metal = mix(metal, thread_metal * 0.8, sewn);
	}

	if (role == ROLE_HIDE) {
		// War paint: the device daubed on the breast and the back, and a trunk
		// ordinary (pale, fess, chevron, saltire, cross, bend) slashed across the
		// harness - never a whole-body partition, which on bare hide reads as a
		// costume, not paint. Worn through to the hide where it was rubbed.
		float daub = motif_cover(rest, px).x;
		if (design >= 5 && design <= 10) {
			daub = max(daub, design_cover(rest, px) * 0.9);
		}
		// A painted helm reads as a costume; the paint is on what a man carries
		// and wears, not over his own face.
		daub *= paint_wear(rest) * float(piece != 0) * 0.9;
		color = mix(color, paint_color.rgb * clamp(lum / max(veil, 1.0e-4), 0.7, 1.3), daub);
		rough = mix(rough, 0.86, daub);
		depth = mix(depth, depth * 0.4, daub);
	} else if ((role == ROLE_PLATE || role == ROLE_MAIL || role == ROLE_STEEL) && coat < 0.5) {
		// Bare steel: gilt (plate) or latten rings (mail) along every open edge,
		// and on plate the emblem painted on the breast and the back.
		float trim = band_cover(band_coords(rest), px) * (1.0 - coat);
		color = mix(color, fittings_color.rgb * (role == ROLE_MAIL ? 0.85 : 1.0), trim);
		metal = mix(metal, 0.85, trim);
		rough = mix(rough, 0.30, trim);
		if (role != ROLE_MAIL) {
			float painted = motif_cover(rest, px).x * paint_wear(rest) * (1.0 - coat);
			color = mix(color, paint_color.rgb, painted);
			metal = mix(metal, 0.05, painted);
			rough = mix(rough, 0.72, painted);
		}
	}

	ALBEDO = color;
	ROUGHNESS = clamp(rough, 0.04, 1.0);
	METALLIC = clamp(metal, 0.0, 1.0);
	if (normal_enabled) {
		NORMAL_MAP = nmap;
		NORMAL_MAP_DEPTH = depth;
	}
}
