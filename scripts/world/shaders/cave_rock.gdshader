shader_type spatial;
// The Weeping Hollow's stone: walls, roofs, floors and the rock skins over them.
//
// * The rock is one of the cave sets (`assets/world/cave/textures/cave_<set>_*`,
//   processed in Blender from CC0 scans), read world-triplanar so a skin of any
//   shape - and the collider boxes behind it - share one continuous surface. The
//   three reads' tangent normals are laid on the mesh normal per plane.
// * Sediment is the floor set, read top-down: it settles on whatever faces up
//   and fills the rock's low texels first (a height blend on the rock's own
//   height in ORH.b), so a ledge collects silt in its hollows and a floor is silt
//   with bedrock breaking through it.
// * Water runs down the walls in streaks (darker, mineral-stained, glossy), the
//   wet areas are darker and glossier overall, and their floors pool.
// * Growth - biofilm, moss - takes damp up-facing stone near the floor.
// * A broad mottle keeps a long wall from printing one tone.
//
// ORH is linear data: R occlusion, G roughness, B height.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D rock_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_orh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D floor_orh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Linear data, not colour: R broad, G medium, B fine/clumpy, A broad.
uniform sampler2D noise_texture : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec3 rock_tint : source_color = vec3(1.0);
uniform vec3 floor_tint : source_color = vec3(1.0);
// What the water leaves on the stone it runs down (a multiplier).
uniform vec3 stain_tint : source_color = vec3(0.62, 0.5, 0.38);
uniform vec3 growth_tint : source_color = vec3(0.24, 0.32, 0.18);
// Repeats per metre.
uniform float rock_tile = 0.3;
uniform float floor_tile = 0.33;
uniform float normal_strength = 1.0;
// How readily up-facing rock takes the floor layer.
uniform float sediment : hint_range(0.0, 1.0) = 0.6;
// 1 on the floor itself: the floor layer is the ground and the rock shows through.
uniform float floor_mode : hint_range(0.0, 1.0) = 0.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.0;
uniform float streaks : hint_range(0.0, 1.0) = 0.5;
uniform float growth : hint_range(0.0, 1.0) = 0.0;
uniform float pools : hint_range(0.0, 1.0) = 0.0;
uniform float mottle : hint_range(0.0, 1.0) = 0.3;
// The cave floor's height in the world: the dirty, damp foot of every wall.
uniform float floor_y = 0.0;
uniform float sharpness = 6.0;
// How far (in tiles) the rock's coordinates wander, breaking the scan's repeat.
uniform float warp = 0.55;

varying vec3 v_world;
varying vec3 v_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 unpack_normal(vec3 t) {
	vec2 xy = t.xy * 2.0 - 1.0;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

void fragment() {
	vec3 p = v_world;
	vec3 n = normalize(v_normal);

	// --- the rock, triplanar. Each plane's image-up is world +y on the walls and
	// world -z on floors and roofs; its image-right is chosen so the tangent frame
	// is right-handed about the face it projects onto. A plane with next to no
	// weight is skipped; the reads take their gradients from outside the branch so
	// the mips stay right where neighbouring pixels take different branches.
	vec3 w = pow(abs(n), vec3(sharpness));
	w /= max(w.x + w.y + w.z, 0.0001);
	vec3 sg = vec3(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0, n.z >= 0.0 ? 1.0 : -1.0);
	vec2 uv_x = vec2(-p.z * sg.x, -p.y) * rock_tile;
	vec2 uv_y = vec2(p.x * sg.y, p.z) * rock_tile + vec2(0.37, 0.61);
	vec2 uv_z = vec2(p.x * sg.z, -p.y) * rock_tile + vec2(0.71, 0.13);
	// A slow warp of each plane's own coordinates, so a scan's bedding never lines
	// up into courses across a long wall the way a tiled photograph does. Floors
	// and roofs see the bedding end-on, where a warp turns it into wood grain, so
	// the top-down plane only drifts a little.
	uv_x += (texture(noise_texture, uv_x * 0.19 + vec2(0.13, 0.71)).rg - 0.5) * warp;
	uv_y += (texture(noise_texture, uv_y * 0.19 + vec2(0.57, 0.29)).rg - 0.5) * warp * 0.25;
	uv_z += (texture(noise_texture, uv_z * 0.19 + vec2(0.83, 0.41)).rg - 0.5) * warp;
	vec2 dx_x = dFdx(uv_x);
	vec2 dy_x = dFdy(uv_x);
	vec2 dx_y = dFdx(uv_y);
	vec2 dy_y = dFdy(uv_y);
	vec2 dx_z = dFdx(uv_z);
	vec2 dy_z = dFdy(uv_z);
	vec3 albedo = vec3(0.0);
	vec3 orh = vec3(0.0);
	vec3 lean = vec3(0.0);
	if (w.x > 0.004) {
		albedo += textureGrad(rock_albedo, uv_x, dx_x, dy_x).rgb * w.x;
		orh += textureGrad(rock_orh, uv_x, dx_x, dy_x).rgb * w.x;
		vec3 t = unpack_normal(textureGrad(rock_normal, uv_x, dx_x, dy_x).rgb);
		lean += (vec3(0.0, 0.0, -sg.x) * t.x + vec3(0.0, 1.0, 0.0) * t.y) * w.x;
	}
	if (w.y > 0.004) {
		albedo += textureGrad(rock_albedo, uv_y, dx_y, dy_y).rgb * w.y;
		orh += textureGrad(rock_orh, uv_y, dx_y, dy_y).rgb * w.y;
		vec3 t = unpack_normal(textureGrad(rock_normal, uv_y, dx_y, dy_y).rgb);
		lean += (vec3(sg.y, 0.0, 0.0) * t.x + vec3(0.0, 0.0, -1.0) * t.y) * w.y;
	}
	if (w.z > 0.004) {
		albedo += textureGrad(rock_albedo, uv_z, dx_z, dy_z).rgb * w.z;
		orh += textureGrad(rock_orh, uv_z, dx_z, dy_z).rgb * w.z;
		vec3 t = unpack_normal(textureGrad(rock_normal, uv_z, dx_z, dy_z).rgb);
		lean += (vec3(sg.z, 0.0, 0.0) * t.x + vec3(0.0, 1.0, 0.0) * t.y) * w.z;
	}
	float kept = max(w.x * step(0.004, w.x) + w.y * step(0.004, w.y) + w.z * step(0.004, w.z), 0.0001);
	albedo /= kept;
	orh /= kept;
	vec3 rock_n = normalize(n + lean / kept * normal_strength);
	albedo *= rock_tint;
	float rock_h = orh.b;

	// --- broad noise, in metres
	vec4 broad = texture(noise_texture, p.xz / 23.0 + vec2(p.y / 31.0, 0.0));
	vec4 fine = texture(noise_texture, (p.xz + p.yy * 0.7) / 5.3 + vec2(0.43, 0.17));

	// --- sediment: the floor set, top-down, on whatever faces up
	vec2 uv_f = p.xz * floor_tile;
	vec2 dx_f = dFdx(uv_f);
	vec2 dy_f = dFdy(uv_f);
	float up = smoothstep(0.42, 0.9, n.y);
	vec3 f_albedo = albedo;
	vec3 f_orh = orh;
	vec3 f_n = rock_n;
	if (up > 0.0 || floor_mode > 0.0) {
		f_albedo = textureGrad(floor_albedo, uv_f, dx_f, dy_f).rgb * floor_tint;
		f_orh = textureGrad(floor_orh, uv_f, dx_f, dy_f).rgb;
		vec3 fn = unpack_normal(textureGrad(floor_normal, uv_f, dx_f, dy_f).rgb);
		f_n = normalize(vec3(fn.x * normal_strength, fn.z, -fn.y * normal_strength));
	}
	float cover = mix(sediment * up * (0.55 + 0.8 * broad.g), 0.62 + 0.5 * (broad.r - 0.5), floor_mode);
	// The silt fills the rock's hollows first.
	float h_rock = rock_h + (1.0 - cover) * 1.6;
	float h_silt = f_orh.b * 0.35 + cover * 1.6;
	float silt = smoothstep(-0.07, 0.07, h_silt - h_rock) * step(0.001, cover);
	albedo = mix(albedo, f_albedo, silt);
	float roughness = mix(orh.g, f_orh.g, silt);
	float occlusion = mix(orh.r, f_orh.r, silt);
	float height = mix(rock_h, f_orh.b, silt);
	vec3 world_n = normalize(mix(rock_n, f_n, silt * up));

	// --- water down the walls: streaks hang from the roof and run to the floor
	float side = 1.0 - abs(n.y);
	float along = dot(p.xz, normalize(vec2(abs(n.z) + 0.001, abs(n.x) + 0.001)));
	float runnel = texture(noise_texture, vec2(along / 3.1, p.y / 41.0 + 0.3)).g;
	float streak = smoothstep(0.56, 0.74, runnel + (fine.b - 0.5) * 0.18) * side * streaks;
	albedo *= mix(vec3(1.0), stain_tint, streak * 0.75);
	// --- the foot of the wall: grimier, damper
	float foot = 1.0 - smoothstep(0.0, 1.1, p.y - floor_y);
	albedo *= mix(1.0, 0.78, foot * side);
	// --- growth on damp stone near the floor and on ledges
	float grow = growth * smoothstep(0.5, 0.72, broad.a + (fine.g - 0.5) * 0.3)
		* clamp(up * 0.8 + foot * 0.9, 0.0, 1.0) * (1.0 - silt * 0.6);
	float luma = dot(albedo, vec3(0.2126, 0.7152, 0.0722));
	albedo = mix(albedo, growth_tint * (0.55 + luma * 1.4), grow);
	// --- broad mottle
	albedo *= mix(1.0, 0.68 + 0.64 * broad.b, mottle);
	// --- wet: darker, glossier; floors pool in their low texels
	float pool = pools * floor_mode * smoothstep(0.58, 0.66, broad.r + (0.5 - height) * 0.25 + (fine.r - 0.5) * 0.1);
	float wet = clamp(wetness * (0.55 + 0.45 * (1.0 - height)) + streak * 0.85 + foot * wetness * 0.4, 0.0, 1.0);
	wet = max(wet, pool);
	albedo *= mix(1.0, 0.55, wet);
	albedo = mix(albedo, albedo * 0.45, pool);
	roughness = mix(roughness, 0.2, wet);
	roughness = mix(roughness, 0.05, pool);
	world_n = normalize(mix(world_n, vec3(0.0, 1.0, 0.0), pool));
	// Crevices carry their own shade under any light.
	albedo *= mix(1.0, occlusion, 0.35);

	ALBEDO = albedo;
	ROUGHNESS = roughness;
	SPECULAR = mix(0.35, 0.6, wet);
	AO = occlusion;
	AO_LIGHT_AFFECT = 0.15;
	NORMAL = normalize((VIEW_MATRIX * vec4(world_n, 0.0)).xyz);
}
