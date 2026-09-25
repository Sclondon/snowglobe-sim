class_name GlobePlasma
extends Node3D
## Plasma-ball filling: a glowing electrode on a stem throwing crackling arcs
## to the glass. Touch (or click and hold) the glass and the arcs gather under
## your finger. Add as a child of a SnowGlobe.
##
## Each arc is a tendril that writhes smoothly (layered noise along its
## length) and every so often crackles into a new shape; arcs fork near the
## glass and splash a bright spot where they touch it. They're drawn as
## camera-facing ribbons with a hot core and a dithered coloured sheath, in
## the opaque pass so the glass refraction picks them up.

const KIND := "plasma"
## Stored in presets.
const SETTINGS: Array[String] = ["arc_count", "arc_color", "core_color", "jitter", "arc_width", "wander_speed", "brightness", "electrode_size", "branching"]
## Shown in the in-game editor.
const EDITOR_ROWS := [
	["arc_count", "Arcs", 1, 16, 1],
	["arc_color", "Arc colour"],
	["core_color", "Core colour"],
	["jitter", "Writhing", 0.0, 2.0, 0.01],
	["branching", "Forks", 0.0, 1.0, 0.01],
	["arc_width", "Arc thickness", 0.002, 0.05, 0.001],
	["wander_speed", "Wander", 0.0, 3.0, 0.01],
	["brightness", "Brightness", 0.0, 4.0, 0.01],
	["electrode_size", "Electrode size", 0.03, 0.3, 0.005],
]
const EDITOR_HINT := "Touch or click-and-hold the glass to pull the arcs."
const SHADER := preload("res://shaders/plasma_arc.gdshader")

@export_range(1, 16, 1) var arc_count := 7
@export var arc_color := Color(0.72, 0.42, 1.0)
@export var core_color := Color(1.0, 0.92, 1.0)
## How much the arcs writhe and bend.
@export_range(0.0, 2.0, 0.01) var jitter := 0.7
## How often arcs fork near the glass.
@export_range(0.0, 1.0, 0.01) var branching := 0.6
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

const SEGMENTS := 28
const BRANCH_SEGMENTS := 10

var _globe: SnowGlobe
var _mesh := ImmediateMesh.new()
var _arcs_mi: MeshInstance3D
var _ball: MeshInstance3D
var _stem: MeshInstance3D
var _light: OmniLight3D
var _arc_mat := ShaderMaterial.new()
var _spot_mat := ShaderMaterial.new()
var _ball_mat := StandardMaterial3D.new()
var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
## Per arc: angle around the axis and height (0..1) of its end on the glass.
var _ends: Array[Vector2] = []
var _end_points: Array[Vector3] = []
## Per arc: noise seed, time jump (a crackle moves it), time to next crackle,
## flicker level, and fork (start along the arc, sideways reach; x < 0 = none).
var _seed: Array[float] = []
var _jump: Array[float] = []
var _crackle_in: Array[float] = []
var _flicker: Array[float] = []
var _fork: Array[Vector3] = []
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
	_rng.randomize()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_noise.seed = _rng.randi()
	_arc_mat.shader = SHADER
	_spot_mat.shader = SHADER
	_spot_mat.set_shader_parameter("spot", true)
	_ball_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_arcs_mi = MeshInstance3D.new()
	_arcs_mi.mesh = _mesh
	_arcs_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arcs_mi)

	_ball = MeshInstance3D.new()
	_ball.mesh = SphereMesh.new()
	_ball.material_override = _ball_mat
	_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	delta = _globe.lod_step(self, delta)
	if delta <= 0.0:
		return
	_light.visible = _globe.detail == SnowGlobe.Detail.FULL
	_time += delta
	for m in [_arc_mat, _spot_mat]:
		m.set_shader_parameter("arc_color", arc_color)
		m.set_shader_parameter("core_color", core_color)
		m.set_shader_parameter("brightness", brightness)
	var hum := 0.5 + 0.5 * sin(_time * 9.0) * sin(_time * 5.3)
	_ball_mat.albedo_color = core_color.lerp(arc_color, 0.15 + 0.2 * hum)
	_light.light_color = arc_color
	_light.light_energy = brightness * (1.1 + 0.5 * _noise.get_noise_1d(_time * 20.0))

	while _ends.size() < arc_count:
		_ends.append(Vector2(_rng.randf() * TAU, _rng.randf_range(0.15, 0.95)))
		_end_points.append(Vector3.ZERO)
		_seed.append(_rng.randf() * 1000.0)
		_jump.append(0.0)
		_crackle_in.append(_rng.randf() * 0.3)
		_flicker.append(1.0)
		_fork.append(_roll_fork())
	for arr in [_ends, _end_points, _seed, _jump, _crackle_in, _flicker, _fork]:
		arr.resize(arc_count)

	var e := _electrode()
	var touch := _globe.touch_active
	# Shaking makes it angrier.
	var agitation := _globe.agitation
	for i in arc_count:
		var end := _ends[i]
		end.x += (_rng.randf() - 0.5) * wander_speed * 3.0 * delta
		end.y = clampf(end.y + (_rng.randf() - 0.5) * wander_speed * delta, 0.1, 0.97)
		_ends[i] = end
		var target := _wall_point(end)
		if touch:
			# Most arcs jump to the finger; spread them a little.
			var spread := Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5) * _globe.globe_radius * 0.06
			target = target.lerp(_globe.touch_point + spread, 0.85 if i % 4 != 3 else 0.0)
		_end_points[i] = _end_points[i].lerp(target, 1.0 - exp(-(20.0 if touch else 6.0) * delta)) if _end_points[i] != Vector3.ZERO else target
		# Crackle: jump to a new shape, flash bright, maybe fork differently.
		_crackle_in[i] -= delta * (1.0 + agitation * 3.0)
		if _crackle_in[i] <= 0.0:
			_crackle_in[i] = _rng.randf_range(0.06, 0.35)
			_jump[i] += _rng.randf_range(0.6, 3.0)
			_flicker[i] = 1.0
			if _rng.randf() < 0.3:
				_fork[i] = _roll_fork()
		_flicker[i] = maxf(0.45, _flicker[i] - delta * 3.0)
	_draw(e)


func _roll_fork() -> Vector3:
	if _rng.randf() > branching:
		return Vector3(-1, 0, 0)
	return Vector3(_rng.randf_range(0.45, 0.8), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-0.5, 0.5))


## Point on the inside of the glass for an (angle, height fraction) pair.
func _wall_point(end: Vector2) -> Vector3:
	var shape := _globe.get_container()
	var gc := _globe.glass_center
	# From just above the floor up to the top of the glass.
	var low := _globe.get_floor_height(0, 0) + _globe.globe_radius * 0.12
	var y := lerpf(low, gc.y + shape.y_max, end.y)
	var r := shape.radius_at(y - gc.y) * shape.radius_factor(sin(end.x), cos(end.x)) * 0.96
	return Vector3(sin(end.x) * r, y, cos(end.x) * r)


## Writhing path from a to b: layered noise sideways, pinned at both ends.
func _tendril(a: Vector3, b: Vector3, seed: float, t_time: float, points: int, amount: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var span := a.distance_to(b)
	var dir := (b - a) / maxf(span, 1e-5)
	var side1 := dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT).normalized()
	var side2 := dir.cross(side1)
	for k in points + 1:
		var t := float(k) / points
		var env := pow(sin(t * PI), 0.7)
		var o1 := _noise.get_noise_2d(seed + t * 1.5, t_time) * 0.6 + _noise.get_noise_2d(seed + 40.0 + t * 5.0, t_time * 2.3) * 0.28 + _noise.get_noise_2d(seed + 80.0 + t * 9.0, t_time * 4.0) * 0.07
		var o2 := _noise.get_noise_2d(seed + 200.0 + t * 1.5, t_time) * 0.6 + _noise.get_noise_2d(seed + 240.0 + t * 5.0, t_time * 2.3) * 0.28 + _noise.get_noise_2d(seed + 280.0 + t * 9.0, t_time * 4.0) * 0.07
		pts.append(a.lerp(b, t) + (side1 * o1 + side2 * o2) * span * 0.4 * amount * env)
	return pts


func _draw(e: Vector3) -> void:
	_mesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null or arc_count == 0:
		return
	var cam_local := global_transform.affine_inverse() * cam.global_position
	var R := _globe.globe_radius
	var w := R * arc_width
	var ball_r := R * electrode_size
	var spots: Array[Vector4] = [] # xyz + size
	var spot_flicker: Array[float] = []

	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _arc_mat)
	for i in arc_count:
		var tt := _time * (0.6 + wander_speed) + _jump[i]
		var end := _end_points[i]
		# Start on the ball's surface, facing the end.
		var start := e + (end - e).normalized() * ball_r * 0.9
		var path := _tendril(start, end, _seed[i], tt, SEGMENTS, jitter)
		# Thin at the electrode, fuller toward the glass.
		_ribbon(path, cam_local, w * 4.5, 0.4, 1.0, _flicker[i])
		spots.append(Vector4(end.x, end.y, end.z, w * 9.0))
		spot_flicker.append(_flicker[i])
		var f := _fork[i]
		if f.x > 0.0:
			var from := path[int(f.x * SEGMENTS)]
			# Fork to a spot on the glass beside the main end.
			var to_end := end - e
			var tangent := to_end.cross(Vector3.UP).normalized()
			if tangent.length_squared() < 0.5:
				tangent = Vector3.RIGHT
			var fork_end := end + (tangent * f.y + Vector3.UP * f.z) * R * 0.35
			fork_end = e + (fork_end - e).normalized() * (end - e).length()
			var branch := _tendril(from, fork_end, _seed[i] + 500.0, tt * 1.3, BRANCH_SEGMENTS, jitter * 0.8)
			_ribbon(branch, cam_local, w * 3.0, 0.6, 0.8, _flicker[i] * 0.85)
			spots.append(Vector4(fork_end.x, fork_end.y, fork_end.z, w * 5.0))
			spot_flicker.append(_flicker[i] * 0.8)
	_mesh.surface_end()

	# Glows: where arcs touch the glass, and a corona round the electrode.
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _spot_mat)
	var corona := 0.75 + 0.25 * _noise.get_noise_1d(_time * 12.0 + 7.0)
	spots.append(Vector4(e.x, e.y, e.z, ball_r * 3.4))
	spot_flicker.append(corona)
	var up := (cam.global_basis.y * global_basis).normalized()
	for k in spots.size():
		var s := spots[k]
		var c := Vector3(s.x, s.y, s.z)
		var to_cam := (cam_local - c).normalized()
		var right := up.cross(to_cam).normalized() * s.w
		var upv := to_cam.cross(right).normalized() * s.w
		# Nudge toward the camera so the glass-side half isn't buried.
		c += to_cam * minf(s.w * 0.3, ball_r * 1.05)
		_quad(c - right - upv, c + right - upv, c + right + upv, c - right + upv, spot_flicker[k])
	_mesh.surface_end()


## One camera-facing strip along the path; width tapers from w_start to w_end
## (fractions of `width`).
func _ribbon(path: PackedVector3Array, cam_local: Vector3, width: float, w_start: float, w_end: float, flicker: float) -> void:
	var n := path.size()
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for k in n:
		var t := float(k) / (n - 1)
		var tangent := path[mini(k + 1, n - 1)] - path[maxi(k - 1, 0)]
		var to_cam := (cam_local - path[k]).normalized()
		var side := tangent.cross(to_cam).normalized() * width * lerpf(w_start, w_end, t)
		left.append(path[k] - side)
		right.append(path[k] + side)
	var col := Color(flicker, 0, 0)
	for k in n - 1:
		var t0 := float(k) / (n - 1)
		var t1 := float(k + 1) / (n - 1)
		for v in [[left[k], Vector2(t0, 0)], [right[k], Vector2(t0, 1)], [right[k + 1], Vector2(t1, 1)], [left[k], Vector2(t0, 0)], [right[k + 1], Vector2(t1, 1)], [left[k + 1], Vector2(t1, 0)]]:
			_mesh.surface_set_color(col)
			_mesh.surface_set_uv(v[1])
			_mesh.surface_add_vertex(v[0])


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, flicker: float) -> void:
	var col := Color(flicker, 0, 0)
	for v in [[a, Vector2(0, 0)], [b, Vector2(1, 0)], [c, Vector2(1, 1)], [a, Vector2(0, 0)], [c, Vector2(1, 1)], [d, Vector2(0, 1)]]:
		_mesh.surface_set_color(col)
		_mesh.surface_set_uv(v[1])
		_mesh.surface_add_vertex(v[0])
