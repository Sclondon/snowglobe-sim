// Shared body of the globe shell shaders (glass.gdshader: seen from outside;
// glass_inside.gdshader: seen from inside, with GLASS_INSIDE defined).
//
// The view through the shell is drawn through EMISSION (sampled from the
// screen texture through a simple lens model), so ALBEDO stays black and the
// engine's own specular lighting supplies reflections and highlights.
// The mesh's origin must be the shell's centre (works for any convex shape).
//
// shell_mode: 0 glass, 1 ice, 2 soap bubble, 3 water, 5 force field,
// 6 magnetic field (4 = none: the mesh is hidden instead).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;

group_uniforms tint;
/** Colour of the water/glass seen straight on. */
uniform vec4 tint : source_color = vec4(0.93, 0.97, 1.0, 1.0);
/** Colour the glass takes on at grazing angles. */
uniform vec4 edge_tint : source_color = vec4(0.62, 0.78, 0.9, 1.0);

group_uniforms refraction;
/** How much bigger the contents look through the water (1 = no lens). */
uniform float magnification : hint_range(1.0, 2.0) = 1.2;
/** Barrel distortion toward the rim (negative pinches). */
uniform float rim_bend : hint_range(-0.5, 1.0) = 0.15;
/** How thick the glass wall looks (edge band + inward bending). */
uniform float thickness : hint_range(0.0, 1.0) = 0.2;
/** Rough size of the glass in world units (scales the thickness effect). */
uniform float glass_size = 1.0;
/** Per-channel difference in magnification; 0 disables colour fringing. */
uniform float dispersion : hint_range(0.0, 0.05) = 0.0;

group_uniforms surface;
uniform float roughness : hint_range(0.0, 1.0) = 0.04;
uniform float specular : hint_range(0.0, 1.0) = 0.7;
uniform float fresnel_power : hint_range(0.5, 10.0) = 3.5;
/** Extra emissive rim so the silhouette reads against dark backgrounds. */
uniform vec4 rim_color : source_color = vec4(0.85, 0.93, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;
/** Glow along facet edges (flat-sided glass reads as glass even face-on). */
uniform float edge_highlight : hint_range(0.0, 2.0) = 0.0;

group_uniforms shell;
uniform int shell_mode = 0;
/** How stirred up the globe is right now (set every frame). */
uniform float agitation = 0.0;
/** Where a finger touches the shell (mesh space) and whether it does. */
uniform vec3 touch_local = vec3(0.0);
uniform float touch_on = 0.0;
/** Heat shimmer from a Heat waves layer (0 = none). */
uniform float heat = 0.0;
/** Colour of force-field / magnetic-field glow. */
uniform vec4 field_color : source_color = vec4(0.35, 0.8, 1.0, 1.0);

varying vec3 center_view;
varying vec3 obj_pos;

void vertex() {
	center_view = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	obj_pos = VERTEX;
	// Bubbles and water wobble, more when shaken.
	if (shell_mode == 2 || shell_mode == 3) {
		float amp = glass_size * (shell_mode == 2 ? 0.012 : 0.02) * (0.3 + agitation * 2.0);
		float w = sin(VERTEX.y / glass_size * 6.0 + TIME * 3.0) * sin(VERTEX.x / glass_size * 5.0 + TIME * 2.3) + 0.5 * sin(VERTEX.z / glass_size * 7.0 - TIME * 2.7);
		VERTEX += NORMAL * w * amp;
	}
}

// Screen UV of the view-space point found by shrinking this surface point
// toward the glass's centre by `scale`, then pushing it in along the surface
// normal by `inset` (thick glass: flat facets shift the view in steps).
vec2 lens_uv(vec3 surface, vec3 normal, float scale, float inset, vec2 screen_uv, mat4 proj, vec2 surface_ndc) {
	vec3 p = center_view + (surface - center_view) * scale - normal * inset;
	vec4 clip = proj * vec4(p, 1.0);
	return screen_uv + (clip.xy / clip.w - surface_ndc) * 0.5;
}

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

// Distance to the nearest edge of a Voronoi cell (ice cracks).
float crack_lines(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 o = vec3(hash3(i + g), hash3(i + g + 17.0), hash3(i + g + 31.0));
				float d = length(g + o - f);
				if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
			}
		}
	}
	return d2 - d1;
}

// Hexagon grid: x,y = offset inside the cell.
vec2 hex_cell(vec2 uv) {
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(uv, r) - h;
	vec2 b = mod(uv - h, r) - h;
	return dot(a, a) < dot(b, b) ? a : b;
}

float hex_edge(vec2 gv) {
	vec2 p = abs(gv);
	float d = max(dot(p, normalize(vec2(1.0, 1.7320508))), p.x);
	return smoothstep(0.42, 0.5, d);
}

void fragment() {
#ifdef GLASS_INSIDE
	// Seen from inside we draw back faces: make sure the normal faces the
	// viewer (whether or not the engine already flipped it).
	if (dot(NORMAL, VIEW) < 0.0) {
		NORMAL = -NORMAL;
	}
#endif
	float n_dot_v = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// Thicker glass shows a wider tinted band toward the edge.
	float fresnel = pow(1.0 - n_dot_v, fresnel_power / (1.0 + thickness * 2.5));
	vec3 op = obj_pos / glass_size;

	// Magnify uniformly about the centre in view space, so it's the same in
	// both screen axes at any zoom and aspect ratio. The rim term is a
	// polynomial in the normal, which keeps the mapping smooth up to the edge.
	float rim = dot(NORMAL.xy, NORMAL.xy);
	float scale = (1.0 + rim_bend * rim) / magnification;
	float inset = thickness * glass_size * 0.15 * (1.0 - n_dot_v * 0.5);
	vec4 surface_clip = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
	vec2 surface_ndc = surface_clip.xy / surface_clip.w;

	// Extra wobble of the view: heat shimmer, rippling water.
	vec2 wobble = vec2(sin(op.y * 25.0 - TIME * 6.0 + op.x * 10.0), sin(op.y * 21.0 - TIME * 5.0 + op.z * 12.0)) * heat * 0.006;
	if (shell_mode == 3) {
		wobble += vec2(sin(op.y * 9.0 + TIME * 2.2), cos(op.x * 8.0 + TIME * 1.9)) * 0.004 * (1.0 + agitation * 3.0);
	}

	vec2 uv = lens_uv(VERTEX, NORMAL, scale, inset, SCREEN_UV, PROJECTION_MATRIX, surface_ndc) + wobble;
	vec3 refracted;
	if (shell_mode == 1) {
		// Ice: frosted, so blur the view with a few jittered taps.
		refracted = vec3(0.0);
		for (int k = 0; k < 5; k++) {
			float a = float(k) * 2.39996 + hash3(op * 40.0) * 6.28;
			refracted += texture(screen_tex, uv + vec2(cos(a), sin(a)) * 0.006 * (0.4 + float(k) * 0.3)).rgb;
		}
		refracted /= 5.0;
	} else if (dispersion > 0.0) {
		refracted = vec3(
			texture(screen_tex, lens_uv(VERTEX, NORMAL, scale * (1.0 + dispersion), inset, SCREEN_UV, PROJECTION_MATRIX, surface_ndc) + wobble).r,
			texture(screen_tex, uv).g,
			texture(screen_tex, lens_uv(VERTEX, NORMAL, scale * (1.0 - dispersion), inset, SCREEN_UV, PROJECTION_MATRIX, surface_ndc) + wobble).b);
	} else {
		refracted = texture(screen_tex, uv).rgb;
	}

	vec3 body_tint = mix(tint.rgb, edge_tint.rgb, fresnel);
	float rim_amt = rim_strength;
	vec3 glow = vec3(0.0);
	float rough = roughness;

	if (shell_mode == 1) {
		// Pale, frosty, with bright crack lines.
		body_tint *= vec3(0.86, 0.96, 1.0);
		float cracks = 1.0 - smoothstep(0.0, 0.06, crack_lines(op * 3.0));
		glow += vec3(0.85, 0.95, 1.0) * (cracks * 0.5 + fresnel * 0.4 + 0.06);
		rough = 0.35;
	} else if (shell_mode == 2) {
		// Soap film: nearly clear, with swirling rainbow colours.
		body_tint = vec3(1.0);
		float swirl = sin(op.x * 4.0 + TIME * 0.4) * sin(op.y * 3.0 - TIME * 0.3) + sin(op.z * 5.0 + TIME * 0.5) * 0.5;
		float hue = fresnel * 1.4 + swirl * 0.35 + TIME * 0.03;
		vec3 iris = 0.5 + 0.5 * cos(6.2831 * (hue + vec3(0.0, 0.33, 0.67)));
		glow += iris * (0.08 + 0.55 * fresnel) * (1.0 + agitation * 0.5);
		rim_amt *= 0.5;
		rough = 0.02;
	} else if (shell_mode == 3) {
		// Water: green-blue body, soft edge, caustic shimmer.
		body_tint *= vec3(0.8, 0.95, 0.97);
		float caustic = pow(abs(sin(op.x * 13.0 + TIME * 1.7) * sin(op.y * 11.0 - TIME * 1.3) * sin(op.z * 12.0 + TIME)), 3.0);
		glow += vec3(0.6, 0.9, 1.0) * caustic * 0.35;
		rim_amt *= 0.4;
	} else if (shell_mode == 5) {
		// Force field: glowing hex grid, pulsing, flaring on shakes and touch.
		body_tint = mix(vec3(1.0), field_color.rgb, 0.15);
		float lon = atan(op.z, op.x);
		vec2 grid = vec2(lon * 3.0, op.y * 5.0);
		float edges = hex_edge(hex_cell(grid));
		float pulse = 0.35 + 0.35 * sin(TIME * 2.0 + op.y * 4.0);
		float touch = touch_on * exp(-length(obj_pos - touch_local) / glass_size * 4.0) * 2.5;
		glow += field_color.rgb * edges * (pulse + agitation * 2.0 + touch) + field_color.rgb * touch * 0.3;
		rim_amt *= 1.5;
	} else if (shell_mode == 6) {
		// Magnetic field: field lines flowing from pole to pole.
		body_tint = vec3(0.98, 0.98, 1.0);
		float lon = atan(op.z, op.x);
		float lat = op.y;
		float lines = 1.0 - smoothstep(0.0, 0.08, abs(fract(lon * 12.0 / 6.2831 + sin(lat * 3.0) * 0.08) - 0.5) * 2.0);
		float flow = smoothstep(0.6, 1.0, fract(lat * 2.5 - TIME * (0.5 + agitation * 2.0) + lon * 0.2));
		glow += field_color.rgb * lines * (0.15 + flow * 0.9) * (1.0 + agitation);
		rim_amt *= 0.6;
	}

	float edge = 0.0;
	if (edge_highlight > 0.0 && UV2.x >= 0.0) {
		vec2 e = min(UV2, 1.0 - UV2);
		edge = 1.0 - smoothstep(0.0, 0.025, min(e.x, e.y));
	}
	ALBEDO = vec3(0.0);
	EMISSION = refracted * body_tint * (1.0 - (0.6 + 0.25 * thickness) * fresnel) + rim_color.rgb * (fresnel * rim_amt + edge * edge_highlight) + glow;
	ROUGHNESS = rough;
	SPECULAR = specular;
	METALLIC = 0.0;
	ALPHA = 1.0;
}
