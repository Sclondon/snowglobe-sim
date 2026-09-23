class_name GlobeDynamite
extends Node3D
## Sticks of dynamite lying on the floor. They roll about with the globe, and
## if it's shaken too violently the fuse fizzes and — boom: a flash, a burst
## of sparks and smoke, a jolt to the whole globe, and a shockwave through
## everything else inside. The sticks fade back in a few seconds later.
## Add as a child of a SnowGlobe.

const KIND := "dynamite"
const SETTINGS: Array[String] = ["count", "threshold", "fuse_time", "respawn_time", "blast_strength", "stick_color"]
const EDITOR_ROWS := [
	["count", "Sticks", 1, 5, 1],
	["threshold", "Explodes at (shake strength)", 0.3, 3.0, 0.01],
	["fuse_time", "Fuse (s)", 0.0, 3.0, 0.05],
	["respawn_time", "Comes back after (s)", 1.0, 20.0, 0.5],
	["blast_strength", "Blast strength", 0.2, 3.0, 0.01],
	["stick_color", "Colour"],
]
const EDITOR_HINT := "Shake hard (or toss the globe) to set it off."
const SPARK_SHADER := preload("res://shaders/globe_particles.gdshader")
const MAX_DEBRIS := 160
const STRIDE := 20

@export_range(1, 5, 1) var count := 2:
	set(v):
		count = v
		if _globe:
			_rebuild_sticks()
## How violent a shake has to be (roughly: 1 = a Shake-button shake).
@export_range(0.3, 3.0, 0.01) var threshold := 1.3
@export_range(0.0, 3.0, 0.05) var fuse_time := 0.6
@export_range(1.0, 20.0, 0.5) var respawn_time := 4.0
@export_range(0.2, 3.0, 0.01) var blast_strength := 1.2
@export var stick_color := Color(0.8, 0.12, 0.1):
	set(v):
		stick_color = v
		if _stick_mat:
			_stick_mat.albedo_color = v

enum State { READY, FUSING, GONE }

var _globe: SnowGlobe
var _state := State.READY
var _timer := 0.0
var _sticks: Array[Node3D] = []
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _rot: Array[Quaternion] = []
var _spin := PackedVector3Array()
var _stick_mat := StandardMaterial3D.new()
var _spark_mat := StandardMaterial3D.new()
var _fuse_sparks: Array[MeshInstance3D] = []
var _flash: OmniLight3D
var _debris: MultiMeshInstance3D
var _d_pos := PackedVector3Array()
var _d_vel := PackedVector3Array()
var _d_life := PackedFloat32Array()
var _d_size := PackedFloat32Array()
var _d_buf := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _agitation := 0.0


func _init() -> void:
	add_to_group(&"globe_layer")


func _ready() -> void:
	var n := get_parent()
	while n and not (n is SnowGlobe):
		n = n.get_parent()
	_globe = n as SnowGlobe
	if _globe == null:
		push_warning("GlobeDynamite must be inside a SnowGlobe.")
		return
	_rng.randomize()
	_stick_mat.albedo_color = stick_color
	_stick_mat.roughness = 0.7
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.albedo_color = Color(1.0, 0.85, 0.4)
	_flash = OmniLight3D.new()
	_flash.light_color = Color(1.0, 0.7, 0.35)
	_flash.light_energy = 0.0
	_flash.visible = false
	add_child(_flash)
	_make_debris()
	_globe.rebuilt.connect(_rebuild_sticks)
	_rebuild_sticks()


## Lays the sticks out on the floor.
func _rebuild_sticks() -> void:
	for s in _sticks:
		s.queue_free()
	_sticks.clear()
	_fuse_sparks.clear()
	_pos.resize(count)
	_vel.resize(count)
	_spin.resize(count)
	_rot.resize(count)
	var fr := _globe.get_floor_radius()
	for i in count:
		var stick := _make_stick()
		add_child(stick)
		_sticks.append(stick)
		var a := TAU * (i + _rng.randf() * 0.5) / count
		var r := fr * _rng.randf_range(0.25, 0.55)
		var p := Vector3(sin(a) * r, 0, cos(a) * r)
		_pos[i] = p
		_vel[i] = Vector3.ZERO
		_spin[i] = Vector3.ZERO
		# Lying on its side, pointing some random way.
		_rot[i] = Quaternion(Vector3.UP, _rng.randf() * TAU) * Quaternion(Vector3.RIGHT, PI * 0.5)
	_state = State.READY
	_place_all(1.0)


func _make_stick() -> Node3D:
	var R := _globe.globe_radius
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = R * 0.032
	cyl.bottom_radius = R * 0.032
	cyl.height = R * 0.2
	cyl.radial_segments = 12
	body.mesh = cyl
	body.material_override = _stick_mat
	root.add_child(body)
	var band := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = R * 0.034
	band_mesh.bottom_radius = R * 0.034
	band_mesh.height = R * 0.05
	band_mesh.radial_segments = 12
	band.mesh = band_mesh
	var paper := StandardMaterial3D.new()
	paper.albedo_color = Color(0.9, 0.85, 0.7)
	band.material_override = paper
	root.add_child(band)
	var fuse := MeshInstance3D.new()
	var fuse_mesh := CylinderMesh.new()
	fuse_mesh.top_radius = R * 0.004
	fuse_mesh.bottom_radius = R * 0.006
	fuse_mesh.height = R * 0.07
	fuse_mesh.radial_segments = 5
	fuse.mesh = fuse_mesh
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.1, 0.08)
	fuse.material_override = dark
	fuse.position = Vector3(0, R * 0.13, 0)
	fuse.rotation.z = 0.4
	root.add_child(fuse)
	var spark := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = R * 0.014
	sphere.height = R * 0.028
	spark.mesh = sphere
	spark.material_override = _spark_mat
	spark.position = Vector3(-R * 0.014, R * 0.165, 0)
	spark.visible = false
	root.add_child(spark)
	_fuse_sparks.append(spark)
	return root


func _physics_process(delta: float) -> void:
	if _globe == null or Engine.is_editor_hint():
		return
	var R := _globe.globe_radius
	var inv := _globe.global_basis.orthonormalized().inverse()
	var up := inv * Vector3.UP
	var fling := -(inv * _globe.linear_acceleration)
	var kick := _globe.linear_acceleration.length() * 0.01 + _globe.angular_velocity.length() * 0.15
	_agitation = maxf(_agitation * exp(-3.0 * delta), kick)

	match _state:
		State.READY:
			if _agitation >= threshold:
				_state = State.FUSING
				_timer = fuse_time
		State.FUSING:
			_timer -= delta
			if _timer <= 0.0:
				_explode()
		State.GONE:
			_timer -= delta
			if _timer <= 0.0:
				_rebuild_sticks()
				_place_all(0.001)
				_state = State.READY
	if _state != State.GONE:
		_roll(delta, up, fling)
		var grow := 1.0
		if _sticks.size() > 0 and _sticks[0].scale.x < 1.0:
			grow = minf(1.0, _sticks[0].scale.x + delta * 2.0)
		_place_all(grow)
	for s in _fuse_sparks:
		s.visible = _state == State.FUSING and fmod(_timer * 30.0, 2.0) < 1.4
	_update_flash(delta)
	_update_debris(delta, up)


## Loose-body tumbling, like knocked-over walkers.
func _roll(delta: float, up: Vector3, fling: Vector3) -> void:
	var R := _globe.globe_radius
	var shape := _globe.get_container()
	var gc := _globe.glass_center
	var r := R * 0.035
	var water := _globe.fill == SnowGlobe.Fill.WATER
	for i in _pos.size():
		var p := _pos[i]
		var v := _vel[i]
		v += (-up * R * 3.0 + fling * 0.12) * delta
		v *= exp(-(2.0 if water else 0.3) * delta)
		p += v * delta
		var touching := false
		var ly := clampf(p.y - gc.y, shape.y_min + r, shape.y_max - r)
		if ly != p.y - gc.y:
			v.y *= -0.2
			touching = true
		p.y = gc.y + ly
		var wall := maxf(shape.radius_at(ly) * shape.radius_factor(p.x, p.z) - r - R * 0.02, 0.0)
		var rr := Vector2(p.x, p.z).length()
		if rr > wall:
			p.x *= wall / rr
			p.z *= wall / rr
			var n := Vector3(p.x, 0, p.z).normalized()
			v -= n * maxf(v.dot(n), 0.0) * 1.3
			touching = true
		var fh := _globe.get_floor_height(p.x, p.z) + r
		if p.y < fh:
			p.y = fh
			v.y = maxf(v.y, -v.y * 0.25)
			touching = true
		if touching:
			v *= exp(-5.0 * delta)
			_spin[i] *= exp(-4.0 * delta)
			# Rolling: spin about the horizontal axis across the motion.
			var roll_axis := up.cross(v)
			if roll_axis.length_squared() > 1e-8:
				_spin[i] = _spin[i].lerp(roll_axis.normalized() * v.length() / r, 0.2)
		var s := _spin[i]
		if s.length_squared() > 1e-8:
			_rot[i] = (Quaternion(s.normalized(), s.length() * delta) * _rot[i]).normalized()
		_pos[i] = p
		_vel[i] = v


func _place_all(grow: float) -> void:
	for i in _sticks.size():
		_sticks[i].transform = Transform3D(Basis(_rot[i]).scaled(Vector3.ONE * grow), _pos[i])


func _explode() -> void:
	var R := _globe.globe_radius
	var origin := Vector3.ZERO
	for p in _pos:
		origin += p
	origin /= maxf(_pos.size(), 1)
	for s in _sticks:
		s.visible = false
	_state = State.GONE
	_timer = respawn_time
	_flash.position = origin + Vector3.UP * R * 0.1
	_flash.omni_range = R * 4.0
	_flash.light_energy = 10.0 * blast_strength
	_flash.visible = true
	# Sparks and smoke.
	for k in MAX_DEBRIS:
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.2, 1.2), _rng.randf_range(-1, 1)).normalized()
		_d_pos[k] = origin
		var smoke := k % 4 == 0
		_d_vel[k] = dir * R * _rng.randf_range(0.8, 2.6) * blast_strength * (0.4 if smoke else 1.0)
		_d_life[k] = _rng.randf_range(0.4, 1.0) * (2.0 if smoke else 1.0)
		_d_size[k] = R * (_rng.randf_range(0.06, 0.12) if smoke else _rng.randf_range(0.012, 0.03))
		var c := Color(0.35, 0.33, 0.32) if smoke else Color.from_hsv(_rng.randf_range(0.02, 0.13), 0.8, 1.0)
		var o := k * STRIDE
		_d_buf[o + 12] = c.r
		_d_buf[o + 13] = c.g
		_d_buf[o + 14] = c.b
		_d_buf[o + 15] = 1.0
	# Kick the whole globe, and everything else inside it.
	var body := _globe.get_parent()
	if body is GlobeBody:
		var jolt := Vector3(_rng.randf_range(-1, 1), 2.5, _rng.randf_range(-1, 1)) * blast_strength
		body.apply_central_impulse(_globe.global_basis * jolt * body.mass)
		body.apply_torque_impulse(Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * 0.6 * blast_strength)
	for layer in GlobePreset.get_layers(_globe):
		if layer != self and layer.has_method("blast"):
			layer.blast(origin, blast_strength * 2.0)


func _update_flash(delta: float) -> void:
	if not _flash.visible:
		return
	_flash.light_energy = move_toward(_flash.light_energy, 0.0, delta * 25.0)
	if _flash.light_energy <= 0.0:
		_flash.visible = false


func _make_debris() -> void:
	_debris = MultiMeshInstance3D.new()
	_debris.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = MAX_DEBRIS
	_debris.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = SPARK_SHADER
	m.set_shader_parameter("shape", 4)
	m.set_shader_parameter("emission_strength", 2.0)
	_debris.material_override = m
	_debris.custom_aabb = AABB(Vector3.ONE * -4.0, Vector3.ONE * 8.0)
	add_child(_debris)
	_d_pos.resize(MAX_DEBRIS)
	_d_vel.resize(MAX_DEBRIS)
	_d_life.resize(MAX_DEBRIS)
	_d_size.resize(MAX_DEBRIS)
	_d_buf.resize(MAX_DEBRIS * STRIDE)
	_d_buf.fill(0.0)
	mm.buffer = _d_buf


func _update_debris(delta: float, up: Vector3) -> void:
	var any := false
	var shape := _globe.get_container()
	var gc := _globe.glass_center
	var R := _globe.globe_radius
	for k in MAX_DEBRIS:
		var o := k * STRIDE
		if _d_life[k] <= 0.0:
			if _d_buf[o] != 0.0:
				_d_buf[o] = 0.0
				_d_buf[o + 5] = 0.0
				_d_buf[o + 10] = 0.0
				any = true
			continue
		any = true
		_d_life[k] -= delta
		var smoke := k % 4 == 0
		var v := _d_vel[k] * exp(-(2.5 if smoke else 1.0) * delta) + (up * R * 0.3 if smoke else -up * R * 1.5) * delta
		var p := _d_pos[k] + v * delta
		if not shape.contains(p - gc, R * 0.02):
			v = -v * 0.3
			p = _d_pos[k]
		_d_pos[k] = p
		_d_vel[k] = v
		var s := _d_size[k] * clampf(_d_life[k] * 2.0, 0.0, 1.0) * (1.0 + (0.6 if smoke else 0.0) * (1.0 - _d_life[k]))
		_d_buf[o] = s
		_d_buf[o + 5] = s
		_d_buf[o + 10] = s
		_d_buf[o + 3] = p.x
		_d_buf[o + 7] = p.y
		_d_buf[o + 11] = p.z
	if any:
		_debris.multimesh.buffer = _d_buf
