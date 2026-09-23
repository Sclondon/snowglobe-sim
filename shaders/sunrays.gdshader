// Light shafts (GlobeSunrays). UV.y runs top (0) to bottom (1).
shader_type spatial;
render_mode cull_disabled, unshaded;
#include "res://shaders/dither.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float intensity = 0.55;
uniform float brightness = 1.3;
uniform float agitation = 0.0;
uniform float size = 1.0;

void vertex() {
	VERTEX.x += sin(TIME * 0.3 + VERTEX.z * 3.0) * 0.04 * size * UV.y;
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float flicker = 0.8 + 0.2 * sin(TIME * 0.9 + UV.y * 4.0 + VERTEX.x * 2.0) + agitation * 0.4;
	float coverage = intensity * (1.0 - UV.y * 0.55) * pow(across, 1.5) * flicker;
	if (dither_discard(coverage, FRAGCOORD.xy)) {
		discard;
	}
	vec3 c = color.rgb * brightness * (1.2 - UV.y * 0.4);
	ALBEDO = c / max(1.0, max(c.r, max(c.g, c.b)));
}
