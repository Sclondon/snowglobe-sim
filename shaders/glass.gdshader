// Glass shell of a water-filled snow globe.
//
// The refracted interior is drawn through EMISSION (sampled from the screen
// texture through a simple lens model), so ALBEDO stays black and the engine's
// own specular lighting supplies the reflections and light highlights.
//
// The mesh's origin must be the glass's centre (works for any convex shape).
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, specular_schlick_ggx;

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
uniform float dispersion : hint_range(0.0, 0.05) = 0.0015;

group_uniforms surface;
uniform float roughness : hint_range(0.0, 1.0) = 0.04;
uniform float specular : hint_range(0.0, 1.0) = 0.7;
uniform float fresnel_power : hint_range(0.5, 10.0) = 3.5;
/** Extra emissive rim so the silhouette reads against dark backgrounds. */
uniform vec4 rim_color : source_color = vec4(0.85, 0.93, 1.0, 1.0);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.35;

varying vec3 center_view;

void vertex() {
	center_view = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

// Screen UV of the view-space point found by shrinking this surface point
// toward the glass's centre by `scale`, then pushing it in along the surface
// normal by `inset` (thick glass: flat facets shift the view in steps).
vec2 lens_uv(vec3 surface, vec3 normal, float scale, float inset, vec2 screen_uv, mat4 proj, vec2 surface_ndc) {
	vec3 p = center_view + (surface - center_view) * scale - normal * inset;
	vec4 clip = proj * vec4(p, 1.0);
	return screen_uv + (clip.xy / clip.w - surface_ndc) * 0.5;
}

void fragment() {
	float n_dot_v = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	// Thicker glass shows a wider tinted band toward the edge.
	float fresnel = pow(1.0 - n_dot_v, fresnel_power / (1.0 + thickness * 2.5));

	// Magnify uniformly about the centre in view space, so it's the same in
	// both screen axes at any zoom and aspect ratio. The rim term is a
	// polynomial in the normal, which keeps the mapping smooth up to the edge.
	float rim = dot(NORMAL.xy, NORMAL.xy);
	float scale = (1.0 + rim_bend * rim) / magnification;
	float inset = thickness * glass_size * 0.15 * (1.0 - n_dot_v * 0.5);
	vec4 surface_clip = PROJECTION_MATRIX * vec4(VERTEX, 1.0);
	vec2 surface_ndc = surface_clip.xy / surface_clip.w;
	vec3 refracted = vec3(
		texture(screen_tex, lens_uv(VERTEX, NORMAL, scale * (1.0 + dispersion), inset, SCREEN_UV, PROJECTION_MATRIX, surface_ndc)).r,
		texture(screen_tex, lens_uv(VERTEX, NORMAL, scale, inset, SCREEN_UV, PROJECTION_MATRIX, surface_ndc)).g,
		texture(screen_tex, lens_uv(VERTEX, NORMAL, scale * (1.0 - dispersion), inset, SCREEN_UV, PROJECTION_MATRIX, surface_ndc)).b
	);

	vec3 body_tint = mix(tint.rgb, edge_tint.rgb, fresnel);
	ALBEDO = vec3(0.0);
	EMISSION = refracted * body_tint * (1.0 - (0.6 + 0.25 * thickness) * fresnel) + rim_color.rgb * fresnel * rim_strength;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	METALLIC = 0.0;
	ALPHA = 1.0;
}
