// Body of a GlobeSerpent (snake / dragon / noodle): one static tube mesh,
// bent along the simulated spine here. The mesh stores each ring's unit
// circle in VERTEX.xy and how far along the body it is in UV.x (0 = nose).
shader_type spatial;
render_mode cull_back;

const int N = 40;
uniform vec3 spine[40];
uniform vec3 spine_up[40];
uniform float body_length = 2.0;
uniform float radius = 0.05;
/** 0 = snake, 1 = dragon, 2 = noodle. */
uniform int style = 0;
uniform vec4 color : source_color = vec4(0.25, 0.55, 0.2, 1.0);
uniform vec4 color2 : source_color = vec4(0.85, 0.75, 0.3, 1.0);

varying vec2 ring;
varying float arc;

float head_radius() {
	return radius * (style == 2 ? 1.0 : 1.3);
}

// Body radius at distance s from the nose.
float profile(float s) {
	float hr = head_radius();
	float r;
	if (s < hr) {
		// Rounded snout.
		float x = (s - hr) / hr;
		r = hr * sqrt(max(0.0, 1.0 - x * x));
	} else {
		// Head, a slight neck, then the body.
		r = mix(hr, radius, smoothstep(hr, hr * 2.6, s));
		if (style == 0) {
			r *= 1.0 - 0.12 * exp(-pow((s - hr * 2.4) / (hr * 0.6), 2.0));
		}
	}
	float tail = body_length - s;
	if (style == 2) {
		// Noodles are round at both ends.
		if (tail < radius) {
			float x = (radius - tail) / radius;
			r = min(r, radius * sqrt(max(0.0, 1.0 - x * x)));
		}
	} else {
		// Taper to a point over the last third.
		r *= pow(clamp(tail / (body_length * 0.38), 0.0, 1.0), 0.75);
	}
	return r;
}

void vertex() {
	arc = UV.x * body_length;
	float f = UV.x * float(N - 1);
	int i = min(int(f), N - 2);
	float fr = f - float(i);
	vec3 p = mix(spine[i], spine[i + 1], fr);
	vec3 t = spine[i] - spine[i + 1];
	t = length(t) > 1e-6 ? normalize(t) : vec3(0.0, 0.0, 1.0);
	vec3 u = mix(spine_up[i], spine_up[i + 1], fr);
	u = normalize(u - t * dot(u, t) + vec3(0.0, 1e-5, 0.0));
	vec3 side = normalize(cross(u, t));
	vec2 c = VERTEX.xy;
	ring = c;
	float r = profile(arc);
	float flat_belly = style == 0 ? 0.85 : 1.0;
	vec3 off = side * c.x * r + u * c.y * r * (c.y < 0.0 ? flat_belly : 1.0);
	if (style == 1 && arc > head_radius() * 2.5) {
		// Dragon: a crest of saw-tooth spikes along the back.
		float saw = 1.0 - fract(arc / (radius * 1.3));
		float along_tail = clamp((body_length - arc) / (radius * 4.0), 0.0, 1.0);
		off += u * r * 1.1 * saw * smoothstep(0.75, 1.0, c.y) * along_tail;
	}
	VERTEX = p + off;
	NORMAL = normalize(side * c.x + u * c.y);
}

void fragment() {
	vec3 col = color.rgb;
	float belly = smoothstep(-0.25, -0.65, ring.y);
	float rough = 0.5;
	float metal = 0.0;
	if (style == 0) {
		// Diamond chain down the back, pale belly scales.
		float d = abs(fract(arc / (radius * 3.0)) - 0.5) * 2.0 + abs(ring.x) * 1.4;
		float diamond = 1.0 - smoothstep(0.55, 0.65, d);
		float back = smoothstep(0.2, 0.6, ring.y);
		col = mix(col, color2.rgb, diamond * back);
		col = mix(col, mix(color2.rgb, vec3(0.95, 0.92, 0.8), 0.6), belly);
		col *= 0.9 + 0.1 * step(0.5, fract(arc / (radius * 0.45) + ring.x * 2.0));
		rough = 0.3;
	} else if (style == 1) {
		// Scales (offset rows) and a golden plated belly.
		vec2 g = vec2(arc / (radius * 0.55), atan(ring.x, ring.y) * 2.2);
		g.y += step(1.0, mod(g.x, 2.0)) * 0.5;
		vec2 q = fract(g) - 0.5;
		float scale = smoothstep(0.35, 0.5, length(q * vec2(1.0, 1.2)));
		col *= 1.0 - 0.3 * scale;
		float plates = step(0.18, fract(arc / (radius * 0.8)));
		col = mix(col, color2.rgb * (0.75 + 0.25 * plates), belly);
		rough = 0.35;
		metal = 0.25 + 0.3 * belly;
		// The gold catches some light even underneath.
		EMISSION = color2.rgb * belly * 0.12;
	} else {
		// Noodle: soft, faintly ridged, a little translucent-looking.
		col *= 0.93 + 0.07 * sin(atan(ring.x, ring.y) * 10.0);
		col = mix(col, color2.rgb, 0.25 * belly);
		rough = 0.55;
		EMISSION = col * 0.06;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
}
