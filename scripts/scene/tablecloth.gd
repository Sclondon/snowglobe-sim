class_name Tablecloth
extends MeshInstance3D
## A cloth laid over the shelf: a flat top plus a skirt hanging over every
## edge in soft folds, with a woven plain / gingham / striped pattern.

enum Pattern { PLAIN, GINGHAM, STRIPES }
const PATTERN_NAMES := ["Plain", "Gingham", "Stripes"]

## Size of the shelf top the cloth covers (x, z).
@export var shelf_size := Vector2(16, 6):
	set(v): shelf_size = v; _build()
## How far the cloth hangs down over the edges.
@export var drop := 0.9:
	set(v): drop = v; _build()
@export var pattern := Pattern.GINGHAM:
	set(v): pattern = v; _update_material()
@export var color_a := Color(0.72, 0.12, 0.12):
	set(v): color_a = v; _update_material()
@export var color_b := Color(0.95, 0.93, 0.88):
	set(v): color_b = v; _update_material()
## Pattern repeats per unit.
@export var pattern_scale := 3.0:
	set(v): pattern_scale = v; _update_material()

var _mat: ShaderMaterial

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled;
uniform int pattern = 1;
uniform vec4 color_a : source_color;
uniform vec4 color_b : source_color;
uniform float pattern_scale = 3.0;
void fragment() {
	vec2 uv = UV * pattern_scale;
	vec3 col = color_b.rgb;
	if (pattern == 1) {
		// Gingham: two sets of bands, darker where they cross.
		float a = step(0.5, fract(uv.x));
		float b = step(0.5, fract(uv.y));
		col = mix(color_b.rgb, color_a.rgb, (a + b) * 0.5);
	} else if (pattern == 2) {
		col = mix(color_b.rgb, color_a.rgb, step(0.5, fract(uv.x)));
	} else {
		col = color_a.rgb;
	}
	// Fine weave.
	float weave = sin(UV.x * 900.0) * sin(UV.y * 900.0);
	col *= 0.93 + 0.07 * weave;
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
	// Soft sheen at grazing angles, like fabric.
	float sheen = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = col * sheen * 0.08;
}
"""


func _ready() -> void:
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER_CODE
	_mat.shader = sh
	material_override = _mat
	_update_material()
	_build()


func _update_material() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("pattern", int(pattern))
	_mat.set_shader_parameter("color_a", color_a)
	_mat.set_shader_parameter("color_b", color_b)
	_mat.set_shader_parameter("pattern_scale", pattern_scale)


func _build() -> void:
	if not is_inside_tree():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := shelf_size.x * 0.5 + 0.02
	var hz := shelf_size.y * 0.5 + 0.02
	var y := 0.002
	# Top: UVs in world units so the pattern lines up with the skirt.
	var corners := [Vector3(-hx, y, -hz), Vector3(hx, y, -hz), Vector3(hx, y, hz), Vector3(-hx, y, hz)]
	for idx in [0, 1, 2, 0, 2, 3]:
		var c: Vector3 = corners[idx]
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(c.x, c.z))
		st.add_vertex(c)

	# Skirt around a rounded rectangle, hanging in folds.
	var path := _perimeter(hx, hz, 0.12, 220)
	var rows := 10
	var total := 0.0
	var arc := PackedFloat32Array([0.0])
	for i in range(1, path.size()):
		total += Vector2(path[i].x, path[i].z).distance_to(Vector2(path[i - 1].x, path[i - 1].z))
		arc.append(total)
	var grid: Array[PackedVector3Array] = []
	for r in rows + 1:
		var t := float(r) / rows
		var ring := PackedVector3Array()
		for i in path.size():
			var p: Vector3 = path[i]
			# Push out along the edge normal (not radially) for straight sides.
			var out := _edge_normal(p, hx, hz)
			var fold := sin(arc[i] * 5.0) * 0.05 + sin(arc[i] * 11.7 + 1.3) * 0.02
			var hang := t * t * 0.1
			ring.append(Vector3(p.x, y - t * drop, p.z) + out * (0.01 + hang + fold * t))
		grid.append(ring)
	for r in rows:
		for i in path.size() - 1:
			var a := grid[r][i]
			var b := grid[r][i + 1]
			var c := grid[r + 1][i + 1]
			var d := grid[r + 1][i]
			var uv_a := Vector2(arc[i], hz + float(r) / rows * drop)
			var uv_b := Vector2(arc[i + 1], hz + float(r) / rows * drop)
			var uv_c := Vector2(arc[i + 1], hz + float(r + 1) / rows * drop)
			var uv_d := Vector2(arc[i], hz + float(r + 1) / rows * drop)
			for pair in [[a, uv_a], [b, uv_b], [c, uv_c], [a, uv_a], [c, uv_c], [d, uv_d]]:
				st.set_uv(pair[1])
				st.add_vertex(pair[0])
	st.generate_normals()
	mesh = st.commit()


## Points around a rounded rectangle at y = 0 (closed: last == first).
func _perimeter(hx: float, hz: float, radius: float, count: int) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var cx := hx - radius
	var cz := hz - radius
	var centers := [Vector2(cx, cz), Vector2(-cx, cz), Vector2(-cx, -cz), Vector2(cx, -cz)]
	var per_corner := count / 4
	for k in 4:
		for i in per_corner + 1:
			var a := (float(k) + float(i) / per_corner) * PI * 0.5
			var c: Vector2 = centers[k]
			pts.append(Vector3(c.x + cos(a) * radius, 0, c.y + sin(a) * radius))
	pts.append(pts[0])
	return pts


func _edge_normal(p: Vector3, hx: float, hz: float) -> Vector3:
	var dx := absf(p.x) - (hx - 0.12)
	var dz := absf(p.z) - (hz - 0.12)
	var n := Vector3(signf(p.x) * maxf(dx, 0.0), 0, signf(p.z) * maxf(dz, 0.0))
	return n.normalized() if n.length_squared() > 1e-8 else Vector3(p.x, 0, p.z).normalized()
