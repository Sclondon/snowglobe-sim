// Creatures drawn by GlobeCreatures (MultiMesh). Parts are tagged in UV2.x
// (0 = body / per-creature colour, 1 = accent, 2 = detail) and animated here.
// INSTANCE_CUSTOM = (animation phase, state, random, animation amount);
// state: 0 moving, 1 resting, 2 tumbling.
shader_type spatial;

/** 0 = sea monkey, 1 = butterfly, 2 = ant, 3 = person. */
uniform int body = 0;
uniform vec4 accent_color : source_color = vec4(1.0, 0.55, 0.45, 1.0);
uniform vec4 detail_color : source_color = vec4(0.08, 0.06, 0.06, 1.0);
uniform float emission_strength = 0.1;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.6;

varying float part;

// Rotates p about the X axis around height `pivot_y`.
vec3 swing_x(vec3 p, float pivot_y, float a) {
	float dy = p.y - pivot_y;
	return vec3(p.x, pivot_y + dy * cos(a) - p.z * sin(a), dy * sin(a) + p.z * cos(a));
}

void vertex() {
	part = UV2.x;
	float ph = INSTANCE_CUSTOM.x;
	float state = INSTANCE_CUSTOM.y;
	float amount = INSTANCE_CUSTOM.w;
	if (body == 0) {
		// Tail waggle, growing toward the back.
		float w = clamp(0.25 - VERTEX.z * 1.6, 0.0, 1.0);
		VERTEX.x += sin(ph - VERTEX.z * 5.0) * 0.14 * w * amount;
	} else if (body == 1) {
		// Wings (body / accent parts away from the centre) flap upward.
		if (part < 1.5 && abs(VERTEX.x) > 0.03) {
			float a = state > 0.5 && state < 1.5
				? 1.25 + 0.15 * sin(ph)
				: (0.15 + 0.95 * (0.5 + 0.5 * sin(ph))) * amount;
			float s = sign(VERTEX.x);
			float x = abs(VERTEX.x);
			VERTEX = vec3(s * (x * cos(a) - VERTEX.y * sin(a)), x * sin(a) + VERTEX.y * cos(a), VERTEX.z);
			NORMAL = vec3(s * (NORMAL.x * cos(a) - NORMAL.y * sin(a)), abs(NORMAL.x) * sin(a) + NORMAL.y * cos(a), NORMAL.z);
		}
	} else if (body == 2) {
		// Legs scuttle back and forth, alternating sides.
		if (part > 1.5 && VERTEX.y < 0.16) {
			VERTEX.z += sin(ph + sign(VERTEX.x) * 1.57 + VERTEX.z * 12.0) * 0.07 * amount;
		}
	} else if (body == 3) {
		// Legs swing from the hips, arms from the shoulders, opposite phase.
		float swing = sin(ph) * 0.55 * amount;
		if (VERTEX.y < 0.44 && abs(VERTEX.x) < 0.14) {
			VERTEX = swing_x(VERTEX, 0.42, swing * sign(VERTEX.x));
		} else if (abs(VERTEX.x) > 0.15 && VERTEX.y > 0.38) {
			VERTEX = swing_x(VERTEX, 0.78, -swing * sign(VERTEX.x) * (state > 1.5 ? 2.5 : 1.0));
		}
	}
}

void fragment() {
	vec3 col = part < 0.5 ? COLOR.rgb : (part < 1.5 ? accent_color.rgb : detail_color.rgb);
	ALBEDO = col;
	ROUGHNESS = roughness_value;
	EMISSION = col * emission_strength;
}
