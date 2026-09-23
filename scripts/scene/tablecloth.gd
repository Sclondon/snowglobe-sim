class_name Tablecloth
extends MeshInstance3D
## Square cloths laid corner-on (diamond-wise) along the shelf, antique-shop
## style: each corner that reaches past an edge drapes down over it with a
## gold tassel at the tip, and the wood shows between them. Velvet with a
## damask pattern and gold border by default; plain, gingham and stripes too.

enum Pattern { DAMASK, PLAIN, GINGHAM, STRIPES }
const PATTERN_NAMES := ["Damask", "Plain velvet", "Gingham", "Stripes"]

## Size of the shelf top the cloths lie on (x, z).
@export var shelf_size := Vector2(16, 6):
	set(v): shelf_size = v; _queue_build()
## How many cloths along the shelf.
@export_range(1, 6) var cloth_count := 3:
	set(v): cloth_count = v; _queue_build()
## Half the diagonal of each (square) cloth: how far its corners reach.
@export var half_diagonal := 4.1:
	set(v): half_diagonal = v; _queue_build()
@export var pattern := Pattern.DAMASK:
	set(v): pattern = v; _update_material()
@export var color_a := Color(0.17, 0.08, 0.2):
	set(v): color_a = v; _update_material()
@export var color_b := Color(0.29, 0.16, 0.3):
	set(v): color_b = v; _update_material()
@export var trim_color := Color(0.85, 0.66, 0.3):
	set(v): trim_color = v; _update_material(); _update_tassels()
## Pattern repeats per unit.
@export var pattern_scale := 1.2:
	set(v): pattern_scale = v; _update_material()

const RES := 72
const EDGE_ROUND := 0.05

var _mat: ShaderMaterial
var _tassel_mat: StandardMaterial3D
var _tassels: Array[MeshInstance3D] = []
var _build_queued := false

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled;
uniform int pattern = 0;
uniform vec4 color_a : source_color;
uniform vec4 color_b : source_color;
uniform vec4 trim_color : source_color;
uniform float pattern_scale = 1.4;

// Damask: an ogee lattice (two families of wavy lines crossing into onion
// shapes) with a rosette in every cell, the whole thing mirrored left-right.
float band(float d, float w, float aa) {
	return 1.0 - smoothstep(w - aa, w + aa, abs(d));
}

float damask(vec2 uv, float aa) {
	float wave = 0.22 * sin(uv.y * TAU);
	float l1 = fract(uv.x - wave + 0.5) - 0.5;
	float l2 = fract(uv.x + wave + 0.5) - 0.5;
	float lattice = max(band(l1, 0.018, aa), band(l2, 0.018, aa));
	// Rosettes in the onion cells.
	vec2 c = vec2(fract(uv.x) - 0.5, fract(uv.y + 0.25) - 0.5);
	float r = length(c);
	float a = atan(c.y, c.x);
	float petals = step(r, 0.1 + 0.05 * cos(a * 6.0)) * step(0.03, r);
	float ring = band(r - 0.17, 0.012, aa);
	// Little leaves flanking each crossing of the lattice.
	vec2 k = vec2(abs(fract(uv.x + 0.5) - 0.5), fract(uv.y + 0.5) - 0.5);
	float leaf = step(length((k - vec2(0.09, 0.0)) * vec2(1.0, 0.45)), 0.045);
	return clamp(lattice + petals + ring + leaf, 0.0, 1.0);
}

void fragment() {
	vec2 uv = UV * pattern_scale;
	float edge = UV2.x; // distance from the cloth's edge
	// Fringe: loose strands at the very edge.
	if (edge < 0.07 && fract(UV2.y * 40.0) > 0.55) {
		discard;
	}
	vec3 col;
	float sheen_amount = 0.35;
	if (pattern == 0) {
		float aa = max(fwidth(uv.x) + fwidth(uv.y), 0.004);
		col = mix(color_a.rgb, color_b.rgb, damask(uv, aa));
	} else if (pattern == 2) {
		float a = step(0.5, fract(uv.x * 2.0));
		float b = step(0.5, fract(uv.y * 2.0));
		col = mix(color_b.rgb, color_a.rgb, (a + b) * 0.5);
		sheen_amount = 0.08;
	} else if (pattern == 3) {
		col = mix(color_b.rgb, color_a.rgb, step(0.5, fract(uv.x * 2.0)));
		sheen_amount = 0.08;
	} else {
		col = color_a.rgb;
	}
	// Gold border band and fringe.
	float band = step(0.1, edge) * (1.0 - step(0.2, edge));
	float fringe = 1.0 - step(0.07, edge);
	float trim = max(band, fringe);
	// Fine weave, faded out where it would shimmer (moiré) at a distance.
	float wf = 1.0 - smoothstep(0.2, 0.5, (fwidth(UV.x) + fwidth(UV.y)) * 110.0);
	float weave = sin(UV.x * 110.0 * TAU) * sin(UV.y * 110.0 * TAU) * wf;
	col *= 0.93 + 0.07 * weave;
	col = mix(col, trim_color.rgb * (0.85 + 0.15 * weave), trim);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.45, trim);
	METALLIC = trim * 0.6;
	SPECULAR = 0.2;
	// Velvet: brighter at grazing angles, darker face-on.
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float sheen = pow(1.0 - facing, 2.5) * (1.0 - trim);
	ALBEDO *= mix(1.0, 0.8 + sheen * 1.2, sheen_amount / 0.35);
	EMISSION = col * sheen * 0.12 * sheen_amount / 0.35;
}
"""


func _ready() -> void:
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat.shader = sh
	material_override = _mat
	# Lying a hair above the shelf, the two would shadow each other in stripes.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tassel_mat = StandardMaterial3D.new()
	_tassel_mat.metallic = 0.5
	_tassel_mat.roughness = 0.5
	_update_material()
	_build()


func _queue_build() -> void:
	if _build_queued or not is_inside_tree():
		return
	_build_queued = true
	_build.call_deferred()


func _update_material() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("pattern", int(pattern))
	_mat.set_shader_parameter("color_a", color_a)
	_mat.set_shader_parameter("color_b", color_b)
	_mat.set_shader_parameter("trim_color", trim_color)
	_mat.set_shader_parameter("pattern_scale", pattern_scale)


func _update_tassels() -> void:
	if _tassel_mat:
		_tassel_mat.albedo_color = trim_color


## Where a point of the cloth (flat position p on the table plane, x/z) ends
## up once draped: flat on the top, rolled over the rounded edge, then
## hanging straight down (with folds that grow toward the tip).
func _drape(p: Vector2, layer: float) -> Vector3:
	var hx := shelf_size.x * 0.5
	var hz := shelf_size.y * 0.5
	var y0 := 0.003 + layer * 0.003
	var q := Vector2(clampf(p.x, -hx, hx), clampf(p.y, -hz, hz))
	var d := p - q
	var beyond := d.length()
	if beyond < 1e-5:
		return Vector3(p.x, y0, p.y)
	var dir := d / beyond
	var r := EDGE_ROUND + layer * 0.004
	var wrap := r * PI * 0.5
	var out: Vector2
	var y: float
	if beyond < wrap:
		var a := beyond / r
		out = q + dir * r * sin(a)
		y = y0 - r * (1.0 - cos(a))
	else:
		var hang := beyond - wrap
		# Folds: the hanging cloth ripples in and out along the edge.
		var along := q.x * absf(dir.y) + q.y * absf(dir.x)
		var fold := (sin(along * 7.0) * 0.05 + sin(along * 17.0 + 1.1) * 0.015) * minf(hang, 1.0)
		out = q + dir * (r + 0.01 + hang * 0.06 + fold)
		y = y0 - r - hang
	return Vector3(out.x, y, out.y)


func _build() -> void:
	_build_queued = false
	if not is_inside_tree():
		return
	for t in _tassels:
		t.queue_free()
	_tassels.clear()
	_update_tassels()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := shelf_size.x * 0.5
	var hz := shelf_size.y * 0.5
	var side := half_diagonal * sqrt(2.0)
	var spacing := 0.0
	if cloth_count > 1:
		# The end cloths hang over the ends as far as the others hang over the
		# front and back.
		spacing = 2.0 * (hx - hz) / (cloth_count - 1)
	var base := 0
	for n in cloth_count:
		var cx := (n - (cloth_count - 1) * 0.5) * spacing
		# The middle cloth on top, then outward.
		var layer := float(cloth_count - absi(2 * n - (cloth_count - 1)))
		# Cloth-local (a, b) in [-side/2, side/2], turned 45° onto the table.
		var rot := Transform2D(PI * 0.25, Vector2(cx, 0))
		for j in RES + 1:
			for i in RES + 1:
				var a := (float(i) / RES - 0.5) * side
				var b := (float(j) / RES - 0.5) * side
				var flat := rot * Vector2(a, b)
				var edge := side * 0.5 - maxf(absf(a), absf(b))
				var along := a if absf(b) > absf(a) else b
				st.set_uv(Vector2(a, b))
				st.set_uv2(Vector2(edge, along))
				st.add_vertex(_drape(flat, layer))
		for j in RES:
			for i in RES:
				var i0 := base + j * (RES + 1) + i
				for k in [i0, i0 + 1, i0 + RES + 2, i0, i0 + RES + 2, i0 + RES + 1]:
					st.add_index(k)
		base += (RES + 1) * (RES + 1)
		# Tassels on the corners that hang over an edge.
		for corner: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
			var tip := rot * (corner * side * 0.5)
			var pos := _drape(tip, layer)
			if pos.y < -0.1:
				_add_tassel(pos)
	st.generate_normals()
	mesh = st.commit()


func _add_tassel(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var parts := []
	var knob := SphereMesh.new()
	knob.radius = 0.045
	knob.height = 0.09
	knob.radial_segments = 10
	knob.rings = 6
	parts.append([knob, Transform3D(Basis(), Vector3(0, -0.04, 0)), 0])
	var skirt := CylinderMesh.new()
	skirt.top_radius = 0.025
	skirt.bottom_radius = 0.06
	skirt.height = 0.16
	skirt.radial_segments = 12
	parts.append([skirt, Transform3D(Basis(), Vector3(0, -0.15, 0)), 0])
	mi.mesh = MeshUtil.merge_parts(parts)
	mi.material_override = _tassel_mat
	mi.position = at
	add_child(mi)
	_tassels.append(mi)
