class_name GlobeCobwebs
extends MeshInstance3D
## Cobwebs strung between the glass and the floor: radial spokes with a
## sagging spiral, built from thin ribbons. They tremble when the globe is
## shaken. Add as a child of a SnowGlobe.

const KIND := "cobwebs"
const SETTINGS: Array[String] = ["count", "web_size", "spokes", "turns", "thread_width", "color", "web_seed"]
const EDITOR_ROWS := [
	["count", "Webs", 1, 8, 1],
	["web_size", "Size", 0.1, 0.7, 0.01],
	["spokes", "Spokes", 4, 16, 1],
	["turns", "Spiral turns", 2, 14, 1],
	["thread_width", "Thread thickness", 0.001, 0.012, 0.0005],
	["color", "Colour"],
	["web_seed", "Arrangement", 0, 99, 1],
]

@export_range(1, 8, 1) var count := 3:
	set(v): count = v; _queue_build()
## Web radius as a fraction of the globe radius.
@export_range(0.1, 0.7, 0.01) var web_size := 0.38:
	set(v): web_size = v; _queue_build()
@export_range(4, 16, 1) var spokes := 9:
	set(v): spokes = v; _queue_build()
@export_range(2, 14, 1) var turns := 7:
	set(v): turns = v; _queue_build()
@export_range(0.001, 0.012, 0.0005) var thread_width := 0.0035:
	set(v): thread_width = v; _queue_build()
@export var color := Color(0.86, 0.87, 0.9):
	set(v):
		color = v
		if _mat:
			_mat.set_shader_parameter("color", v)
@export var web_seed := 3:
	set(v): web_seed = v; _queue_build()

var _globe: SnowGlobe
var _mat: ShaderMaterial
var _wobble := 0.0
var _build_queued := false

static var _shader: Shader


func _init() -> void:
	add_to_group(&"globe_layer")


func _ready() -> void:
	var n := get_parent()
	while n and not (n is SnowGlobe):
		n = n.get_parent()
	_globe = n as SnowGlobe
	if _globe == null:
		push_warning("GlobeCobwebs must be inside a SnowGlobe.")
		return
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 color : source_color;
uniform float wobble = 0.0;
void vertex() {
	// UV.x: 0 at the web's anchors, 1 in the middle (sways most);
	// NORMAL is the web plane's normal.
	float w = UV.x * wobble;
	VERTEX += NORMAL * sin(TIME * 17.0 + UV.y * 6.0) * w;
}
void fragment() {
	ALBEDO = color.rgb;
	ROUGHNESS = 0.6;
	EMISSION = color.rgb * 0.25;
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("color", color)
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_globe.rebuilt.connect(_queue_build)
	_build()


func _queue_build() -> void:
	if _build_queued or _globe == null or not is_inside_tree():
		return
	_build_queued = true
	_build.call_deferred()


func _physics_process(delta: float) -> void:
	if _globe == null or _mat == null:
		return
	var kick := _globe.linear_acceleration.length() * 0.01 + _globe.angular_velocity.length() * 0.15
	_wobble = maxf(_wobble * exp(-3.0 * delta), minf(kick, 2.0))
	_mat.set_shader_parameter("wobble", _wobble * _globe.globe_radius * 0.03)


## A shockwave nearby makes the webs shudder.
func blast(_origin: Vector3, strength: float) -> void:
	_wobble = maxf(_wobble, strength * 2.0)


func _build() -> void:
	_build_queued = false
	var R := _globe.globe_radius
	var shape := _globe.get_container()
	var gc := _globe.glass_center
	var rng := RandomNumberGenerator.new()
	rng.seed = web_seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := R * thread_width
	for web in count:
		# Tuck each web against the glass, a little above the floor.
		var a := TAU * (web + rng.randf_range(0.0, 0.6)) / count
		var out := Vector3(sin(a), 0, cos(a))
		var size := R * web_size * rng.randf_range(0.8, 1.15)
		var y := _globe.floor_y + size * rng.randf_range(0.5, 1.4)
		var wall := shape.radius_at(y - gc.y) * shape.radius_factor(out.x, out.z)
		var center := out * maxf(wall - size * 0.7, 0.0) + Vector3(0, y, 0)
		# The web faces inward and leans a bit.
		var normal := (-out + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.2, 0.3), rng.randf_range(-0.3, 0.3))).normalized()
		var side := normal.cross(Vector3.UP).normalized()
		var up := side.cross(normal).normalized()
		var ends: Array[Vector3] = []
		for s in spokes:
			var ang := TAU * (s + rng.randf_range(-0.2, 0.2)) / spokes
			var dir := side * cos(ang) + up * sin(ang)
			var reach := size * rng.randf_range(0.75, 1.15)
			# Shorten spokes that would poke through the glass or floor.
			var end := center + dir * reach
			for k in 12:
				if shape.contains(end - gc, R * 0.01) and end.y > _globe.get_floor_height(end.x, end.z):
					break
				reach *= 0.85
				end = center + dir * reach
			ends.append(end)
			_thread(st, center, end, normal, w, 0.5, 0.0)
		# Spiral: connect points on neighbouring spokes, sagging between.
		var steps := spokes * turns
		var prev := Vector3.ZERO
		for k in steps + 1:
			var s := k % spokes
			var frac := 0.15 + 0.8 * float(k) / steps
			var p := center.lerp(ends[s], frac)
			if k > 0:
				var mid := (prev + p) * 0.5 + (center - (prev + p) * 0.5) * 0.08
				_thread(st, prev, mid, normal, w * 0.7, 1.0 - frac, frac)
				_thread(st, mid, p, normal, w * 0.7, 1.0 - frac, frac)
			prev = p
	mesh = st.commit()
	custom_aabb = GlobeParticles.glass_aabb(_globe)


## One thin ribbon lying in the web's plane. `sway` goes in UV.x (how much
## this part moves), `phase` in UV.y.
func _thread(st: SurfaceTool, a: Vector3, b: Vector3, normal: Vector3, width: float, sway: float, phase: float) -> void:
	var along := (b - a)
	if along.length_squared() < 1e-10:
		return
	var side := along.cross(normal).normalized() * width
	var quad := [a - side, a + side, b + side, b - side]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_normal(normal)
		st.set_uv(Vector2(sway, phase))
		st.add_vertex(quad[idx])
