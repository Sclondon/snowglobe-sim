// Creatures drawn by GlobeCreatures (MultiMesh). Parts are tagged in UV2.x
// (0 = body / per-creature colour, 1 = accent, 2 = detail) and animated here.
// INSTANCE_CUSTOM = (animation phase, state, random, animation amount);
// state: 0 moving, 1 resting, 2 tumbling.
shader_type spatial;

/** 0 = sea monkey, 1 = butterfly, 2 = ant, 3 = person, 4 = firefly, 5 = bird. */
uniform int body = 0;
uniform vec4 accent_color : source_color = vec4(1.0, 0.55, 0.45, 1.0);
uniform vec4 detail_color : source_color = vec4(0.08, 0.06, 0.06, 1.0);
uniform float emission_strength = 0.1;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.6;

varying float part;
varying float blink;

// Rotates p about the X axis around height `pivot_y`.
vec3 swing_x(vec3 p, float pivot_y, float a) {
	float dy = p.y - pivot_y;
	return vec3(p.x, pivot_y + dy * cos(a) - p.z * sin(a), dy * sin(a) + p.z * cos(a));
}

void vertex() {
	part = UV2.x;
	blink = 0.55 + 0.45 * sin(TIME * (1.5 + INSTANCE_CUSTOM.z * 2.0) + INSTANCE_CUSTOM.z * 40.0);
	float ph = INSTANCE_CUSTOM.x;
	float state = INSTANCE_CUSTOM.y;
	float amount = INSTANCE_CUSTOM.w;
	if (body == 0) {
		// Tail waggle, growing toward the back.
		float w = clamp(0.25 - VERTEX.z * 1.6, 0.0, 1.0);
		VERTEX.x += sin(ph - VERTEX.z * 5.0) * 0.14 * w * amount;
	} else if (body == 1 || body == 4) {
		// Wings flap upward (butterflies: body + accent parts; fireflies:
		// just the accent wings, fast and small).
		bool wing = body == 1 ? (part < 1.5 && abs(VERTEX.x) > 0.03) : (part > 0.5 && part < 1.5);
		if (body == 4) {
			ph *= 3.0;
			amount *= 0.6;
		}
		if (wing) {
			float a = state > 0.5 && state < 1.5
				? 1.25 + 0.15 * sin(ph)
				: (0.15 + 0.95 * (0.5 + 0.5 * sin(ph))) * amount;
			float s = sign(VERTEX.x);
			float x = abs(VERTEX.x);
			VERTEX = vec3(s * (x * cos(a) - VERTEX.y * sin(a)), x * sin(a) + VERTEX.y * cos(a), VERTEX.z);
			NORMAL = vec3(s * (NORMAL.x * cos(a) - NORMAL.y * sin(a)), abs(NORMAL.x) * sin(a) + NORMAL.y * cos(a), NORMAL.z);
		}
	} else if (body == 5) {
		if (part > 2.5) {
			// Wings hinge at the shoulders (x = ±0.1, y = 0.36).
			float s = sign(VERTEX.x);
			vec3 q = VERTEX - vec3(s * 0.1, 0.36, 0.0);
			vec3 qn = NORMAL;
			bool perched = state > 0.5 && state < 1.5;
			if (perched) {
				// Folded: swept back along the body and drooping a little.
				float t = s * 1.45;
				q = vec3(q.x * cos(t) + q.z * sin(t), q.y, -q.x * sin(t) + q.z * cos(t));
				qn = vec3(qn.x * cos(t) + qn.z * sin(t), qn.y, -qn.x * sin(t) + qn.z * cos(t));
				q.y -= abs(q.z) * 0.25;
				q.x += s * 0.07;
			} else {
				// Flapping (with the odd glide), up and down about the body axis.
				float a = (sin(ph) * 0.85 + 0.15) * amount;
				q = vec3(q.x * cos(a) - s * q.y * sin(a), s * q.x * sin(a) + q.y * cos(a), q.z);
				qn = vec3(qn.x * cos(a) - s * qn.y * sin(a), s * qn.x * sin(a) + qn.y * cos(a), qn.z);
			}
			VERTEX = q + vec3(s * 0.1, 0.36, 0.0);
			NORMAL = qn;
		} else if (state > 0.5 && state < 1.5 && VERTEX.y > 0.34 && VERTEX.z > 0.1) {
			// Perched: the head pecks and glances about now and then.
			float peck = max(0.0, sin(ph * 0.7 + INSTANCE_CUSTOM.z * 20.0) - 0.6) * 2.5;
			VERTEX.y -= peck * 0.12 * (VERTEX.z - 0.1);
			VERTEX.x += sin(ph * 0.3 + INSTANCE_CUSTOM.z * 7.0) * 0.08 * (VERTEX.z - 0.1);
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
	vec3 col = part < 0.5 ? COLOR.rgb : (part < 1.5 ? accent_color.rgb : (part < 2.5 ? detail_color.rgb : COLOR.rgb * 0.7));
	ALBEDO = col;
	ROUGHNESS = roughness_value;
	if (body == 4) {
		// Only the tail glows, blinking gently out of step with the others.
		EMISSION = part < 0.5 ? col * emission_strength * blink : vec3(0.0);
	} else {
		EMISSION = col * emission_strength;
	}
}
