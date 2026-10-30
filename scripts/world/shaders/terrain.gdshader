shader_type spatial;
// The ground: four tiled layers - grass, forest-floor litter, trodden dirt and
// rock - blended by weights that come from the world, and by their own heights.
//
// * Dirt is the worn ground: the ground map's red channel (the warband's
//   half-metre bake of its lanes, yards and ruts) or the mesh's vertex alpha (the
//   frontier's per-vertex paths), whichever is larger. The map's green channel is
//   wet: darker albedo, a glossier surface.
// * Rock is the slope, litter is a broad noise patchwork over the rest, and grass
//   is what is left.
// * Every layer's albedo alpha is its height. Where two layers share a texel the
//   taller one wins, so a dirt edge is grass blades standing in soil and stones
//   breaking through it, never a linear cross-fade - and never the shape of the
//   mesh's triangles.
// * Each tiled layer is read twice, once turned and scaled, and the two reads are
//   height-blended by a broad noise, so a 4 m tile never prints the same patch
//   in a row across a clearing.
//
// Normals are the layers' own tangent maps, blended with the same weights and
// laid on the mesh normal in world space (UVs are world x/z, so the frame is
// world-aligned); they and the height contrast fade with distance so far
// hillsides stay calm.
render_mode cull_back;

uniform sampler2D grass_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D litter_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// Linear data, not colour: R broad patches, G medium, B fine/clumpy, A broad.
uniform sampler2D noise_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
// R wear, G wet. Unset (black) where a scene carries its paths in vertex alpha.
uniform sampler2D ground_map : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec2 ground_map_origin = vec2(0.0);
uniform vec2 ground_map_size = vec2(1.0);

uniform vec4 grass_tint : source_color = vec4(1.0);
uniform vec4 grass_dry_tint : source_color = vec4(1.0);
uniform vec4 litter_tint : source_color = vec4(1.0);
uniform vec4 dirt_tint : source_color = vec4(1.0);
uniform vec4 rock_tint : source_color = vec4(1.0);
uniform float tile = 4.0;
uniform float litter_tile = 3.2;
uniform float dirt_tile = 5.0;
uniform float rock_tile = 4.0;
// Share of the open ground that is fallen leaves rather than grass, and share of
// the grass that is dry.
uniform float litter_cover : hint_range(0.0, 1.0) = 0.3;
uniform float dry_cover : hint_range(0.0, 1.0) = 0.3;
// How far a layer's height can override its weight, and how wide the hand-over
// between two layers is.
uniform float blend_contrast = 0.55;
uniform float blend_softness = 0.1;
// Centres each layer's height on 0.5 (grass, litter, dirt, rock; the authored
// means are about 0.45/0.52/0.27/0.61), so the weights decide how much of each
// layer shows and the heights only decide where. Without it the low-lying dirt
// lost every hand-over and a worn line read as leaves.
uniform vec4 height_offset = vec4(0.05, -0.02, 0.23, -0.11);
uniform float normal_strength = 1.0;
// Broad value mottling over everything.
uniform float detail_strength = 1.0;
uniform vec2 detail_fade = vec2(70.0, 140.0);

varying vec3 v_world;
varying vec3 v_world_normal;

// The second read of a layer: turned by 0.62 rad and 1.31x larger.
const float TURN_S = 0.58104;
const float TURN_C = 0.81388;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 unpack_normal(vec3 t) {
	vec2 xy = t.xy * 2.0 - 1.0;
	return vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0)));
}

// One tiled layer: albedo + height, and its normal as a world-flat vector
// (x, up, z). The two reads are height-blended by `pick`.
vec4 layer(sampler2D albedo_tex, sampler2D normal_tex, vec2 p, float scale, float pick,
		out vec3 flat_normal) {
	vec2 uv_a = p / scale;
	vec2 uv_b = vec2(TURN_C * p.x - TURN_S * p.y, TURN_S * p.x + TURN_C * p.y)
		/ (scale * 1.31) + vec2(0.37, 0.71);
	vec4 a = texture(albedo_tex, uv_a);
	vec4 b = texture(albedo_tex, uv_b);
	vec3 na = unpack_normal(texture(normal_tex, uv_a).rgb);
	vec3 nb = unpack_normal(texture(normal_tex, uv_b).rgb);
	float ha = a.a + 1.0 - pick;
	float hb = b.a + pick;
	float top = max(ha, hb) - 0.2;
	float wa = max(ha - top, 0.0);
	float wb = max(hb - top, 0.0);
	float inv = 1.0 / max(wa + wb, 0.0001);
	// Image up (green) is world -z for the straight read; the turned read's axes
	// are turned back so both normals lean the same way in the world.
	vec3 flat_a = vec3(na.x, na.z, -na.y);
	vec3 flat_b = vec3(TURN_C * nb.x - TURN_S * nb.y, nb.z, -TURN_S * nb.x - TURN_C * nb.y);
	flat_normal = (flat_a * wa + flat_b * wb) * inv;
	return (a * wa + b * wb) * inv;
}

void fragment() {
	vec2 p = v_world.xz;
	float distance_to_camera = length(VERTEX);
	float detail = 1.0 - smoothstep(detail_fade.x, detail_fade.y, distance_to_camera);
	vec4 broad = texture(noise_texture, p / 61.0);
	vec4 fine = texture(noise_texture, p / 13.7 + vec2(0.43, 0.17));

	// --- weights from the world
	vec2 worn = texture(ground_map, (p - ground_map_origin) / ground_map_size).rg;
	float wear = max(clamp(COLOR.a, 0.0, 1.0), worn.r);
	float wet = worn.g;
	vec3 geometric = normalize(v_world_normal);
	float slope = 1.0 - clamp(geometric.y, 0.0, 1.0);
	float rock = smoothstep(0.16, 0.52, slope + (fine.b - 0.5) * 0.16);
	// A worn edge is ragged: the fine noise pushes it in and out, but only inside
	// its own transition, so untouched ground stays untouched and bare earth bare.
	float edge = wear * (1.0 - wear) * 4.0;
	float dirt = clamp(wear + (fine.b - 0.5) * 0.75 * edge, 0.0, 1.0);
	float litter = smoothstep(0.4, 0.62, broad.r + litter_cover - 0.5);
	float dry = smoothstep(0.42, 0.72, fine.g + dry_cover - 0.5);
	vec4 weight;
	weight.w = rock;
	weight.z = (1.0 - rock) * dirt;
	float rest = (1.0 - rock) * (1.0 - dirt);
	weight.y = rest * litter;
	weight.x = rest * (1.0 - litter);

	// --- the layers
	float pick = smoothstep(0.38, 0.62, broad.a);
	vec3 n_grass;
	vec3 n_litter;
	vec3 n_dirt;
	vec4 grass = layer(grass_texture, grass_normal, p, tile, pick, n_grass);
	vec4 leaves = layer(litter_texture, litter_normal, p, litter_tile, 1.0 - pick, n_litter);
	vec4 soil = layer(dirt_texture, dirt_normal, p, dirt_tile, pick, n_dirt);
	vec2 rock_uv = p / rock_tile;
	vec4 stone = texture(rock_texture, rock_uv);
	vec3 rn = unpack_normal(texture(rock_normal, rock_uv).rgb);
	vec3 n_rock = vec3(rn.x, rn.z, -rn.y);

	// --- height blend: the taller texel wins where two layers share the ground
	vec4 heights = clamp(vec4(grass.a, leaves.a, soil.a, stone.a) + height_offset, 0.0, 1.0);
	vec4 reach = clamp(weight * 4.0, 0.0, 1.0);
	vec4 x = weight + heights * (blend_contrast * mix(0.35, 1.0, detail)) * reach;
	float top = max(max(x.x, x.y), max(x.z, x.w)) - blend_softness;
	vec4 share = max(x - top, vec4(0.0));
	share /= max(dot(share, vec4(1.0)), 0.0001);

	vec3 grass_colour = grass.rgb * mix(grass_tint.rgb, grass_dry_tint.rgb, dry);
	vec3 albedo = grass_colour * share.x + leaves.rgb * litter_tint.rgb * share.y
		+ soil.rgb * dirt_tint.rgb * share.z + stone.rgb * rock_tint.rgb * share.w;
	float height = dot(heights, share);
	// Broad value mottling, so a hillside is never one flat tone.
	albedo *= mix(1.0, 0.7 + 0.6 * broad.b, 0.5 * detail_strength);

	// --- wet ground: darker and glossier, the low texels first
	float damp = clamp(wet * (1.25 - 0.5 * height), 0.0, 1.0);
	albedo *= mix(1.0, 0.42, damp);
	ALBEDO = albedo * COLOR.rgb;
	float roughness = dot(vec4(0.86, 0.9, 0.95, 0.84), share);
	ROUGHNESS = mix(roughness, 0.3, damp);
	SPECULAR = mix(0.3, 0.5, damp);
	AO = mix(0.62, 1.0, height);

	// --- normals: the blended layer normal laid on the mesh's own
	vec3 flat_normal = n_grass * share.x + n_litter * share.y + n_dirt * share.z + n_rock * share.w;
	flat_normal.xz *= normal_strength * detail * (1.0 - 0.6 * damp);
	vec3 tangent = normalize(vec3(geometric.y, -geometric.x, 0.0));
	vec3 bitangent = cross(tangent, geometric);
	vec3 world_normal = normalize(tangent * flat_normal.x + geometric * max(flat_normal.y, 0.05)
		+ bitangent * flat_normal.z);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
}
