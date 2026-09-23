// Plasma-ball arcs and glows (GlobePlasma). Ribbons have UV.y across their
// width; with `spot` on, a quad is a round glow instead. Kept in the opaque
// pass (dithered halo) so the glass refraction sees it.
// COLOR.r = flicker of this arc (0..1).
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://shaders/dither.gdshaderinc"

uniform vec4 arc_color : source_color = vec4(0.72, 0.42, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.92, 1.0, 1.0);
uniform float brightness = 1.0;
uniform bool spot = false;

void fragment() {
	float d = spot ? length(UV * 2.0 - 1.0) : abs(UV.y * 2.0 - 1.0);
	float flick = COLOR.r;
	// A thin white-hot core inside a soft coloured sheath.
	float core = 1.0 - smoothstep(spot ? 0.08 : 0.1, spot ? 0.3 : 0.28, d);
	float halo = exp(-d * d * (spot ? 3.0 : 3.5)) * (1.0 - smoothstep(0.85, 1.0, d));
	float coverage = max(core * (0.55 + 0.45 * flick), halo * (0.5 + 0.4 * flick));
	if (dither_discard(coverage, FRAGCOORD.xy)) {
		discard;
	}
	vec3 sheath = arc_color.rgb * (0.5 + 0.9 * halo);
	vec3 c = mix(sheath, core_color.rgb * 1.6, core);
	ALBEDO = c * brightness * (0.55 + 0.45 * flick);
}
