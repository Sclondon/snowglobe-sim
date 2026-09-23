// Aurora curtains (GlobeAurora). UV.x runs along a curtain, UV.y bottom to top.
shader_type spatial;
render_mode cull_disabled, unshaded;
#include "res://shaders/dither.gdshaderinc"

uniform vec4 color_low : source_color = vec4(0.2, 1.0, 0.55, 1.0);
uniform vec4 color_high : source_color = vec4(0.65, 0.3, 1.0, 1.0);
uniform float brightness = 1.6;
uniform float density = 0.75;
uniform float agitation = 0.0;
uniform float size = 1.0;

void vertex() {
	float sway = size * 0.05 * (0.4 + UV.y) * (1.0 + agitation * 2.5);
	VERTEX.x += sin(TIME * 0.6 + UV.x * 9.0 + UV.y * 2.0) * sway;
	VERTEX.z += cos(TIME * 0.5 + UV.x * 7.0) * sway;
}

void fragment() {
	float bands = 0.5 + 0.5 * sin(UV.x * 60.0 + TIME * 1.2 + sin(UV.x * 9.0 + TIME * 0.7) * 3.0);
	float fade = smoothstep(0.0, 0.15, UV.y) * (1.0 - smoothstep(0.45, 1.0, UV.y)) * smoothstep(0.0, 0.1, UV.x) * (1.0 - smoothstep(0.9, 1.0, UV.x));
	float coverage = fade * (0.35 + 0.65 * bands) * density * (1.0 + agitation * 0.5);
	if (dither_discard(coverage, FRAGCOORD.xy)) {
		discard;
	}
	vec3 c = mix(color_low.rgb, color_high.rgb, UV.y) * brightness * (0.6 + 0.6 * bands) * (1.0 + agitation);
	// Scale back (not clip) anything over 1 so bright curtains keep their hue
	// instead of washing out to white.
	ALBEDO = c / max(1.0, max(c.r, max(c.g, c.b)));
}
