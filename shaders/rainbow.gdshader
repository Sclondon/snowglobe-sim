// Rainbow arc (GlobeRainbow). UV.x along the arc, UV.y across the bands
// (0 inner / violet, 1 outer / red).
shader_type spatial;
render_mode cull_disabled, unshaded;
#include "res://shaders/dither.gdshaderinc"

uniform float opacity = 0.9;
uniform float brightness = 1.2;
uniform float agitation = 0.0;
uniform bool fade_cycle = true;

vec3 hue(float h) {
	return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}

void fragment() {
	float cycle = fade_cycle ? 0.45 + 0.55 * (0.5 + 0.5 * sin(TIME * 0.25)) : 1.0;
	float ends = 1.0 - smoothstep(0.75, 1.0, abs(UV.x * 2.0 - 1.0));
	float edge = smoothstep(0.0, 0.08, UV.y) * (1.0 - smoothstep(0.92, 1.0, UV.y));
	float shimmer = 1.0 + agitation * 0.6 * sin(TIME * 20.0 + UV.x * 40.0);
	float coverage = opacity * cycle * ends * edge * shimmer;
	if (dither_discard(coverage, FRAGCOORD.xy)) {
		discard;
	}
	vec3 c = hue(0.78 * (1.0 - UV.y)) * brightness;
	ALBEDO = c / max(1.0, max(c.r, max(c.g, c.b)));
}
