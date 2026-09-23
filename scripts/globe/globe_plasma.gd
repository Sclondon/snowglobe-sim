class_name GlobePlasma
extends Node3D
## Plasma-ball filling: a glowing electrode on a stem throwing crackling arcs
## to the glass. Touch (or click and hold) the glass and the arcs gather under
## your finger. Add as a child of a SnowGlobe.
##
## Arcs are drawn as opaque, camera-facing ribbons (ImmediateMesh) so the
## glass refraction picks them up like everything else inside.

@export_range(1, 16, 1) var arc_count := 7
@export var arc_color := Color(0.72, 0.42, 1.0)
@export var core_color := Color(1.0, 0.92, 1.0)
## How jagged the arcs are.
@export_range(0.0, 2.0, 0.01) var jitter := 0.7
## Arc thickness as a fraction of the globe radius.
@export_range(0.002, 0.05, 0.001) var arc_width := 0.012
## How quickly arc ends wander over the glass.
@export_range(0.0, 3.0, 0.01) var wander_speed := 0.5
@export_range(0.0, 4.0, 0.01) var brightness := 1.0
## Electrode ball radius as a fraction of the globe radius.
@export_range(0.03, 0.3, 0.005) var electrode_size := 0.11:
	set(v):
		electrode_size = v
		if _globe:
			_place_electrode()

const SEGMENTS := 14
const REFRESH := 0.05

var _globe: SnowGlobe
var _mesh := ImmediateMesh.new()
var _arcs_mi: MeshInstance3D
var _ball: MeshInstance3D
var _stem: MeshInstance3D
var _light: OmniLight3D
var _outer_mat := StandardMaterial3D.new()
var _core_mat := StandardMaterial3D.new()
var _ball_mat := StandardMaterial3D.new()
var _rng := RandomNumberGenerator.new()
## Per arc: angle around the axis and height (0..1) of its end on the glass.
var _ends: Array[Vector2] = []
var _end_points: Array[Vector3] = []
var _paths: Array[PackedVector3Array] = []
var _refresh_in := 0.0
var _time := 0.0


func _init() -> void:
	add_to_group(&"globe_layer")


func _ready() -> void:
	var n := get_parent()
	while n and not (n is SnowGlobe):
		n = n.get_parent()
	_globe = n as SnowGlobe
	if _globe == null:
		push_warning("GlobePlasma must be inside a SnowGlobe.")
		return
	for m in [_outer_mat, _core_mat, _ball_mat]:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_arcs_mi = MeshInstance3D.new()
	_arcs_mi.mesh = _mesh
	_arcs_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arcs_mi)

	_ball = MeshInstance3D.new()
	_ball.mesh = SphereMesh.new()
	_ball.material_override = _ball_mat
	add_child(_ball)
	_stem = MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.radial_segments = 16
	_stem.mesh = stem_mesh
	var stem_mat := StandardMaterial3D.new()
	stem_mat.albedo_color = Color(0.12, 0.1, 0.14)
	stem_mat.metallic = 0.6
	stem_mat.roughness = 0.3
	_stem.material_override = stem_mat
	add_child(_stem)
	_light = OmniLight3D.new()
	_light.shadow_enabled = false
	add_child(_light)
	_globe.rebuilt.connect(_place_electrode)
	_place_electrode()


func _electrode() -> Vector3:
	var R := _globe.globe_radius
	var floor_h := _globe.get_floor_height(0, 0)
	var shape := _globe.get_container()
	var top := _globe.glass_center.y + shape.y_max
	# Sit the ball near the middle of the space above the floor.
	return Vector3(0, lerpf(floor_h, top, 0.42) if top > floor_h else floor_h + R * 0.4, 0)


func _place_electrode() -> void:
	var R := _globe.globe_radius
	var e := _electrode()
	var floor_h := _globe.get_floor_height(0, 0)
	var r := R * electrode_size
	var ball_mesh := _ball.mesh as SphereMesh
	ball_mesh.radius = r
	ball_mesh.height = r * 2.0
	_ball.position = e
	var stem_mesh := _stem.mesh as CylinderMesh
	stem_mesh.top_radius = r * 0.25
	stem_mesh.bottom_radius = r * 0.45
	stem_mesh.height = maxf(e.y - floor_h, 0.001)
	_stem.position = Vector3(0, (e.y + floor_h) * 0.5, 0)
	_light.position = e
	_light.omni_range = R * 3.0


func _process(delta: float) -> void:
	if _globe == null:
		return
	_time += delta
	_outer_mat.albedo_color = arc_color * clampf(brightness, 0.0, 1.0)
	_core_mat.albedo_color = core_color
	_ball_mat.albedo_color = core_color.lerp(arc_color, 0.35 + 0.15 * sin(_time * 9.0))
	_light.light_color = arc_color
	_light.light_energy = brightness * (1.2 + 0.4 * sin(_time * 37.0) * sin(_time * 13.0))

	while _ends.size() < arc_count:
		_ends.append(Vector2(_rng.randf() * TAU, _rng.randf_range(0.15, 0.95)))
		_end_points.append(Vector3.ZERO)
	_ends.resize(arc_count)
	_end_points.resize(arc_count)

	var e := _electrode()
	var touch := _globe.touch_active
	for i in arc_count:
		var end := _ends[i]
		end.x += (_rng.randf() - 0.5) * wander_speed * 3.0 * delta
		end.y = clampf(end.y + (_rng.randf() - 0.5) * wander_speed * delta, 0.1, 0.97)
		_ends[i] = end
		var target := _wall_point(end, e)
		if touch:
			# Most arcs jump to the finger; spread them a little.
			var spread := Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5) * _globe.globe_radius * 0.06
			target = target.lerp(_globe.touch_point + spread, 0.85 if i % 4 != 3 else 0.0)
		_end_points[i] = _end_points[i].lerp(target, 1.0 - exp(-(20.0 if touch else 6.0) * delta)) if _end_points[i] != Vector3.ZERO else target

	_refresh_in -= delta
	if _refresh_in <= 0.0 or _paths.size() != arc_count:
		_refresh_in = REFRESH
		_paths.clear()
		for i in arc_count:
			_paths.append(_jagged(e, _end_points[i]))
	_draw_arcs()


## Point on the inside of the glass for an (angle, height fraction) pair.
func _wall_point(end: Vector2, _e: Vector3) -> Vector3:
	var shape := _globe.get_container()
	var gc := _globe.glass_center
	# From just above the floor up to the top of the glass.
	var low := _globe.get_floor_height(0, 0) + _globe.globe_radius * 0.12
	var y := lerpf(low, gc.y + shape.y_max, end.y)
	var r := shape.radius_at(y - gc.y) * 0.96
	return Vector3(sin(end.x) * r, y, cos(end.x) * r)


func _jagged(a: Vector3, b: Vector3) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var span := a.distance_to(b)
	var dir := (b - a) / maxf(span, 1e-5)
	var side1 := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	var side2 := dir.cross(side1)
	for k in SEGMENTS + 1:
		var t := float(k) / SEGMENTS
		var taper := sin(t * PI)
		var off := (side1 * _rng.randf_range(-1, 1) + side2 * _rng.randf_range(-1, 1)) * span * 0.07 * jitter * taper
		pts.append(a.lerp(b, t) + off)
	return pts


func _draw_arcs() -> void:
	_mesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null or _paths.is_empty():
		return
	var cam_local := global_transform.affine_inverse() * cam.global_position
	var w := _globe.globe_radius * arc_width
	for pass_i in 2:
		_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _outer_mat if pass_i == 0 else _core_mat)
		var width := w * (1.8 if pass_i == 0 else 0.6)
		for path in _paths:
			# One continuous strip per arc: each point gets a side vector from
			# its neighbours, so bends don't leave gaps.
			var left := PackedVector3Array()
			var right := PackedVector3Array()
			var n := path.size()
			for k in n:
				var tangent := path[mini(k + 1, n - 1)] - path[maxi(k - 1, 0)]
				var to_cam := (cam_local - path[k]).normalized()
				var taper := 0.35 + 0.65 * sin(PI * (0.15 + 0.85 * float(k) / (n - 1)))
				var side := tangent.cross(to_cam).normalized() * width * taper
				# Core sits a hair in front of the glow.
				var lift := to_cam * (w * 0.6 if pass_i == 1 else 0.0)
				left.append(path[k] - side + lift)
				right.append(path[k] + side + lift)
			for k in n - 1:
				for v in [left[k], right[k], right[k + 1], left[k], right[k + 1], left[k + 1]]:
					_mesh.surface_add_vertex(v)
		_mesh.surface_end()
