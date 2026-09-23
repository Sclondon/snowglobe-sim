// Stands (and the shelf): procedural wood, brushed metal, glazed ceramic or
// marble, with an optional metallic trim band. Set use_texture to swap the
// procedural surface for any albedo texture (sampled with the mesh UVs).
shader_type spatial;

/** 0 = wood, 1 = metal, 2 = ceramic, 3 = stone. */
uniform int material_mode = 0;
/** Wood: light grain; metal/ceramic/stone: main colour. */
uniform vec4 primary_color : source_color = vec4(0.5, 0.3, 0.17, 1.0);
/** Wood: dark grain; ceramic: speckle; stone: veins; metal: tarnish. */
uniform vec4 secondary_color : source_color = vec4(0.24, 0.12, 0.06, 1.0);

group_uniforms wood;
/** Growth rings per unit of distance from the log's core. */
uniform float ring_frequency = 22.0;
/** How much the rings wobble. */
uniform float grain_warp = 0.9;
uniform float wood_roughness : hint_range(0.0, 1.0) = 0.45;

group_uniforms texture_override;
uniform bool use_texture = false;
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec2 texture_scale = vec2(1.0, 1.0);

group_uniforms trim;
/** Local-space Y range of the trim band (set by snow_globe.gd). */
uniform float trim_start = -1.0;
uniform float trim_end = -1.0;
uniform vec4 trim_color : source_color = vec4(0.95, 0.75, 0.35, 1.0);
uniform float trim_roughness : hint_range(0.0, 1.0) = 0.35;

varying vec3 local_pos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float value_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec3 p = local_pos;
	vec3 color;
	float rough;
	float metal = 0.0;
	float spec = 0.5;
	if (use_texture) {
		color = texture(albedo_texture, UV * texture_scale).rgb;
		rough = wood_roughness;
	} else if (material_mode == 1) {
		// Brushed metal: fine streaks running around the stand.
		float streak = fbm(vec3(p.y * 140.0, length(p.xz) * 6.0, 0.0));
		float tarnish = fbm(p * 5.0);
		color = mix(primary_color.rgb, secondary_color.rgb, smoothstep(0.55, 0.8, tarnish) * 0.5) * (0.82 + 0.3 * streak);
		metal = 1.0;
		rough = 0.28 + 0.18 * streak;
	} else if (material_mode == 2) {
		// Glazed ceramic: glossy with speckles and a soft glaze pooling.
		float speck = step(0.97, hash(floor(p * 240.0)));
		float pool = fbm(p * 4.0);
		color = mix(primary_color.rgb * (0.92 + 0.12 * pool), secondary_color.rgb, speck * 0.85);
		rough = 0.08 + 0.06 * pool;
		spec = 0.7;
	} else if (material_mode == 3) {
		// Marble: warped veins.
		float n = fbm(p * 3.0);
		float v = abs(sin((p.x * 1.2 + p.y * 0.8 + p.z * 0.5 + n * 2.6) * 7.0));
		float vein = 1.0 - smoothstep(0.0, 0.14, v);
		color = mix(primary_color.rgb * (0.94 + 0.08 * n), secondary_color.rgb, vein * 0.8);
		rough = 0.22;
		spec = 0.6;
	} else {
		// Wood: rings around an axis running along X, offset so the core is
		// outside the piece, like a stand turned from a plank.
		float warp = fbm(p * vec3(1.5, 6.0, 6.0)) * grain_warp;
		float d = length(p.yz + vec2(0.35, 0.8)) + warp * 0.08;
		float rings = fract(d * ring_frequency);
		rings = smoothstep(0.0, 0.25, rings) * (1.0 - smoothstep(0.6, 1.0, rings));
		float streaks = fbm(p * vec3(2.0, 40.0, 40.0));
		color = mix(secondary_color.rgb, primary_color.rgb, rings * 0.7 + streaks * 0.3);
		rough = wood_roughness;
	}
	float trim = step(trim_start, p.y) * step(p.y, trim_end);
	ALBEDO = mix(color, trim_color.rgb, trim);
	METALLIC = mix(metal, 0.55, trim);
	ROUGHNESS = mix(rough, trim_roughness, trim);
	SPECULAR = spec;
}
