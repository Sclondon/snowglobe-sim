// Lava-lamp wax (GlobeLava): metaballs ray-marched inside a box that covers
// the globe's interior. Blobs melt into each other and into the pool on the
// floor. Writes depth, so props and particles sit properly among the blobs,
// and stays in the opaque pass so the glass refraction sees it.
shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

const int MAX_BLOBS = 12;
uniform vec4 blobs[12];
uniform int blob_count = 6;
uniform float pool_top = 0.0;
uniform float pool_radius = 0.5;
uniform float floor_y = 0.0;
uniform float top_y = 1.0;
uniform float blend = 0.15;
uniform vec3 box_half = vec3(1.0);
uniform vec4 color_low : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform vec4 color_high : source_color = vec4(0.95, 0.15, 0.4, 1.0);
uniform float glow = 1.0;

varying vec3 model_pos;

void vertex() {
	model_pos = VERTEX;
}

float smin(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

float map(vec3 p) {
	// The pool: a slab over the floor (with a bottom, so it never shows
	// below the floor).
	float d = max(max(p.y - pool_top, floor_y - 0.02 - p.y), length(p.xz) - pool_radius);
	for (int i = 0; i < MAX_BLOBS; i++) {
		if (i >= blob_count) {
			break;
		}
		vec4 b = blobs[i];
		d = smin(d, length(p - b.xyz) - b.w, blend);
	}
	return d;
}

vec3 map_normal(vec3 p) {
	vec2 e = vec2(0.004, -0.004);
	return normalize(e.xyy * map(p + e.xyy) + e.yyx * map(p + e.yyx) + e.yxy * map(p + e.yxy) + e.xxx * map(p + e.xxx));
}

void fragment() {
	mat4 inv_model = inverse(MODEL_MATRIX);
	vec3 cam = (inv_model * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	vec3 dir = normalize(model_pos - cam);
	// Enter the box (or start at the camera if it's already inside).
	vec3 inv_d = 1.0 / dir;
	vec3 t1 = (-box_half - cam) * inv_d;
	vec3 t2 = (box_half - cam) * inv_d;
	vec3 tmin = min(t1, t2);
	float t = max(max(max(tmin.x, tmin.y), tmin.z), 0.0);
	float t_end = length(model_pos - cam);
	bool hit = false;
	vec3 p;
	for (int i = 0; i < 56; i++) {
		p = cam + dir * t;
		float d = map(p);
		if (d < 0.002) {
			hit = true;
			break;
		}
		t += max(d * 0.9, 0.003);
		if (t > t_end) {
			break;
		}
	}
	if (!hit) {
		discard;
	}
	vec3 n = map_normal(p);
	float h = clamp((p.y - floor_y) / max(top_y - floor_y, 1e-3), 0.0, 1.0);
	vec3 col = mix(color_low.rgb, color_high.rgb, smoothstep(0.0, 1.0, h));
	// Waxy: lit from the lamp below, glowing through at the edges.
	float from_below = 0.5 + 0.5 * max(-n.y, 0.0) + 0.25 * max(n.y, 0.0);
	float rim = pow(1.0 - abs(dot(n, -dir)), 2.0);
	float depth_glow = mix(1.15, 0.8, h);
	ALBEDO = col * (from_below * 0.75 + rim * 0.55) * depth_glow * glow;
	vec4 clip = PROJECTION_MATRIX * VIEW_MATRIX * MODEL_MATRIX * vec4(p, 1.0);
	float ndc_z = clip.z / clip.w;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	DEPTH = ndc_z * 0.5 + 0.5;
#else
	DEPTH = ndc_z;
#endif
}
