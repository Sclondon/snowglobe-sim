// Particles inside the snow globe (drawn by GlobeParticles as a MultiMesh).
//
// Shapes are drawn procedurally on a unit quad. They use alpha scissor (with
// alpha-to-coverage for soft edges under MSAA) rather than blending so they
// render in the opaque pass and get picked up by the glass refraction.
//
// Per-instance data: COLOR = colour, INSTANCE_CUSTOM = (random, random,
// random speed, unused).
shader_type spatial;
render_mode cull_disabled;

/** 0 = flake, 1 = bubble, 2 = glitter, 3 = rain / streak, 4 = mote, 5 = cloud. */
uniform int shape = 0;
uniform float emission_strength = 0.15;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.7;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float tumble_speed = 1.5;
/** Clouds: how solid the puffs are (lower = thinner fog). */
uniform float cloud_density = 1.0;

varying vec4 custom;

mat3 axis_angle(vec3 axis, float a) {
	float s = sin(a);
	float c = cos(a);
	float t = 1.0 - c;
	return mat3(
		vec3(t * axis.x * axis.x + c, t * axis.x * axis.y + s * axis.z, t * axis.x * axis.z - s * axis.y),
		vec3(t * axis.x * axis.y - s * axis.z, t * axis.y * axis.y + c, t * axis.y * axis.z + s * axis.x),
		vec3(t * axis.x * axis.z + s * axis.y, t * axis.y * axis.z - s * axis.x, t * axis.z * axis.z + c));
}

void vertex() {
	custom = INSTANCE_CUSTOM;
	float angle = TIME * tumble_speed * (0.4 + INSTANCE_CUSTOM.z) + INSTANCE_CUSTOM.x * 6.2831;
	if (shape == 2) {
		// Glitter tumbles freely in 3D.
		vec3 axis = normalize(vec3(INSTANCE_CUSTOM.x - 0.5, INSTANCE_CUSTOM.y - 0.5, 0.25 + INSTANCE_CUSTOM.z));
		mat3 r = axis_angle(axis, angle);
		VERTEX = r * VERTEX;
		NORMAL = r * NORMAL;
	} else if (shape == 3) {
		// Rain / streaks: stretched along the instance's Y axis (its velocity, set on
		// the CPU) and turned around that axis to face the camera.
		vec3 axis = MODEL_MATRIX[1].xyz;
		float width = length(MODEL_MATRIX[0].xyz);
		vec3 center = MODEL_MATRIX[3].xyz;
		vec3 to_cam = normalize(CAMERA_POSITION_WORLD - center);
		vec3 side = cross(axis, to_cam);
		if (dot(side, side) < 1e-10) {
			side = cross(axis, vec3(1.0, 0.0, 0.0));
		}
		side = normalize(side) * width;
		vec3 facing = normalize(cross(side, axis));
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side, 0.0), vec4(axis, 0.0), vec4(facing, 0.0), vec4(center, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX) * mat3(normalize(side), normalize(axis), facing);
	} else {
		// Flakes and clouds spin in the screen plane; bubbles don't (keeps the
		// highlight in place). Then billboard, keeping the instance scale.
		if (shape == 0 || shape == 5) {
			float c = cos(angle);
			float s = sin(angle);
			VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
		}
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
		MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	}
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	vec3 col = COLOR.rgb;
	float alpha = 1.0;
	vec3 glow = vec3(0.0);
	// Fake a little sphere so billboards pick up light from above.
	vec3 ball_normal = normalize(vec3(p.x, -p.y, sqrt(max(0.0, 1.0 - r * r))));

	if (shape == 0) {
		float a = atan(p.y, p.x);
		float arms = 0.6 + 0.4 * pow(abs(cos(3.0 * a + custom.y * 6.2831)), 4.0);
		alpha = 1.0 - smoothstep(arms - 0.2, arms, r);
		NORMAL = normalize(mix(NORMAL, ball_normal, 0.6));
	} else if (shape == 1) {
		float ring = smoothstep(0.62, 0.86, r) * (1.0 - smoothstep(0.9, 1.0, r));
		float highlight = 1.0 - smoothstep(0.05, 0.24, length(p - vec2(-0.35, -0.38)));
		alpha = max(ring, highlight);
		NORMAL = ball_normal;
		glow = vec3(highlight);
	} else if (shape == 2) {
		vec2 q = abs(p);
		float hex = max(q.x * 0.866 + q.y * 0.5, q.y);
		alpha = 1.0 - smoothstep(0.82, 0.9, hex);
	} else if (shape == 3) {
		alpha = (1.0 - smoothstep(0.2, 0.9, abs(p.x))) * (1.0 - smoothstep(0.55, 1.0, abs(p.y)));
		glow = col * 0.3;
	} else if (shape == 4) {
		alpha = 1.0 - smoothstep(0.35, 1.0, r);
		NORMAL = ball_normal;
		glow = col * (1.0 - r) * 0.8;
	} else if (shape == 5) {
		// Dithered soft puff: coverage falls off toward the edge and is broken
		// up by noise, then compared against an ordered-dither threshold so it
		// stays in the opaque pass (visible through the glass refraction).
		float n = fract(sin(dot(floor(UV * 6.0) + custom.xy * 17.0, vec2(12.9898, 78.233))) * 43758.5453);
		float coverage = (1.0 - smoothstep(0.45, 1.0, r)) * (0.85 + 0.15 * n) * cloud_density;
		ivec2 px = ivec2(FRAGCOORD.xy) % 4;
		int idx = px.x + px.y * 4;
		float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
		alpha = step((bayer[idx] + 0.5) / 16.0, coverage);
		NORMAL = normalize(mix(NORMAL, ball_normal, 0.5));
	}

	ALBEDO = col;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	EMISSION = col * emission_strength + glow;
	ALPHA = alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
}
