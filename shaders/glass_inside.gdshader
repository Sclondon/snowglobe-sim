// The glass seen from inside the globe (back faces). See glass_common.gdshaderinc.
shader_type spatial;
render_mode blend_mix, cull_front, depth_draw_opaque, specular_schlick_ggx;

#define GLASS_INSIDE
#include "res://shaders/glass_common.gdshaderinc"
