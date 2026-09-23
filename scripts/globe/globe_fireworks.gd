class_name GlobeFireworks
extends MultiMeshInstance3D
## Fireworks inside a globe: rockets launch from the floor and burst into
## sparks that arc down and fade (they shrink away, since the glass refraction
## only shows opaque things). Shaking sets off a volley. Add as a child of a
## SnowGlobe.

const KIND := "fireworks"
## Stored in presets.
const SETTINGS: Array[String] = ["auto_launch", "shake_volley", "launch_interval", "burst_size", "rocket_speed", "spark_speed", "spark_life", "spark_size", "gravity", "multicolour", "color", "glow"]
## Shown in the in-game editor.
const EDITOR_ROWS := [
	["auto_launch", "Launch on their own too"],
	["shake_volley", "Rockets per shake", 1, 12, 1],
	["launch_interval", "Seconds between rockets", 0.2, 5.0, 0.05],
	["burst_size", "Sparks per burst", 10, 150, 1],
	["rocket_speed", "Rocket speed", 0.5, 3.0, 0.01],
	["spark_speed", "Burst size", 0.1, 1.5, 0.01],
	["spark_life", "Spark life (s)", 0.3, 4.0, 0.05],
	["spark_size", "Spark size", 0.005, 0.08, 0.001],
	["gravity", "Gravity", 0.0, 3.0, 0.01],
	["multicolour", "Random colours"],
	["color", "Colour"],
	["glow", "Glow", 0.0, 4.0, 0.01],
]
const EDITOR_HINT := "Shake the globe to set off a volley."
const SHADER := preload("res://shaders/globe_particles.gdshader")
const STRIDE := 20
const MAX_SPARKS := 600

## Also launch rockets every so often without shaking.
@export var auto_launch := true
## Rockets fired each time the globe is shaken.
@export_range(1, 12, 1) var shake_volley := 5
@export_range(0.2, 5.0, 0.05) var launch_interval := 1.3
@export_range(10, 150, 1) var burst_size := 60
## Rocket launch speed in globe radii per second.
@export_range(0.5, 3.0, 0.01) var rocket_speed := 1.5
@export_range(0.1, 1.5, 0.01) var spark_speed := 0.55
@export_range(0.3, 4.0, 0.05) var spark_life := 1.5
@export_range(0.005, 0.08, 0.001) var spark_size := 0.022
@export_range(0.0, 3.0, 0.01) var gravity := 0.9
@export var multicolour := true
@export var color := Color(1.0, 0.75, 0.3)
@export_range(0.0, 4.0, 0.01) var glow := 2.2:
	set(v):
		glow = v
		if material_override:
			(material_override as ShaderMaterial).set_shader_parameter("emission_strength", v)

var _globe: SnowGlobe
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _life := PackedFloat32Array()
var _max_life := PackedFloat32Array()
var _size := PackedFloat32Array()
var _rocket := PackedByteArray()
var _buf := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _next_launch := 0.5
var _prev_agitation := 0.0
var _volley_cooldown := 0.0


func _init() -> void:
	add_to_group(&"globe_layer")


func _ready() -> void:
	var n := get_parent()
	while n and not (n is SnowGlobe):
		n = n.get_parent()
	_globe = n as SnowGlobe
	if _globe == null:
		push_warning("GlobeFireworks must be inside a SnowGlobe.")
		return
	_rng.randomize()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = MAX_SPARKS
	multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("shape", 4)
	m.set_shader_parameter("emission_strength", glow)
	m.set_shader_parameter("roughness_value", 1.0)
	m.set_shader_parameter("tumble_speed", 0.0)
	material_override = m
	for arr in [_pos, _vel]:
		arr.resize(MAX_SPARKS)
	for arr in [_life, _max_life, _size]:
		arr.resize(MAX_SPARKS)
	_rocket.resize(MAX_SPARKS)
	_buf.resize(MAX_SPARKS * STRIDE)
	_buf.fill(0.0)
	_globe.rebuilt.connect(func() -> void: custom_aabb = GlobeParticles.glass_aabb(_globe))
	custom_aabb = GlobeParticles.glass_aabb(_globe)


func _validate_property(property: Dictionary) -> void:
	if property.name in ["multimesh", "material_override", "custom_aabb"]:
		property.usage &= ~PROPERTY_USAGE_STORAGE


func _physics_process(delta: float) -> void:
	if _globe == null or Engine.is_editor_hint():
		return
	var R := _globe.globe_radius
	var inv := _globe.global_basis.orthonormalized().inverse()
	var up := inv * Vector3.UP
	# A shake (the globe's agitation jumping up) sets off a volley.
	_volley_cooldown -= delta
	var ag := _globe.agitation
	if ag > 0.35 and ag > _prev_agitation + 0.1 and _volley_cooldown <= 0.0:
		_volley_cooldown = 0.6
		for k in shake_volley:
			_launch(up)
	_prev_agitation = ag

	if auto_launch:
		_next_launch -= delta
		if _next_launch <= 0.0:
			_next_launch = launch_interval * _rng.randf_range(0.6, 1.4)
			_launch(up)

	var shape := _globe.get_container()
	var gc := _globe.glass_center
	var drag := exp(-(1.5 if _globe.fill == SnowGlobe.Fill.WATER else 0.4) * delta)
	var g := -up * gravity * R
	for i in MAX_SPARKS:
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		var p := _pos[i]
		var v := _vel[i]
		if _rocket[i] == 1:
			v += g * 0.35 * delta
			if _life[i] <= 0.0 or not shape.contains(p - gc, R * 0.08):
				_burst(i)
				continue
		else:
			v = (v + g * delta) * drag
		p += v * delta
		if not shape.contains(p - gc, R * 0.01) or p.y < _globe.get_floor_height(p.x, p.z):
			_life[i] = 0.0
		_pos[i] = p
		_vel[i] = v
	_write()


func _launch(up: Vector3) -> void:
	var i := _free_slot()
	if i < 0:
		return
	var R := _globe.globe_radius
	var shape := _globe.get_container()
	var a := _rng.randf() * TAU
	var r := sqrt(_rng.randf()) * shape.floor_radius * 0.5
	var p := Vector3(sin(a) * r, 0, cos(a) * r)
	p.y = _globe.get_floor_height(p.x, p.z) + R * 0.02
	_pos[i] = p
	var side := Vector3(_rng.randf() - 0.5, 0, _rng.randf() - 0.5) * 0.3
	_vel[i] = (up + side).normalized() * rocket_speed * R * _rng.randf_range(0.8, 1.1)
	_life[i] = _rng.randf_range(0.45, 0.75) * rocket_speed / maxf(gravity, 0.5)
	_max_life[i] = _life[i]
	_size[i] = spark_size * 1.4
	_rocket[i] = 1
	_set_color(i, Color(1.0, 0.9, 0.7))


func _burst(rocket: int) -> void:
	_life[rocket] = 0.0
	var origin := _pos[rocket]
	var col := Color.from_hsv(_rng.randf(), 0.75, 1.0) if multicolour else color
	var col2 := Color.from_hsv(fposmod(col.h + 0.15, 1.0), 0.6, 1.0) if multicolour else color.lightened(0.3)
	var R := _globe.globe_radius
	for k in burst_size:
		var i := _free_slot()
		if i < 0:
			return
		var dir := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1))
		dir = dir.normalized() if dir.length_squared() > 1e-4 else Vector3.UP
		_pos[i] = origin
		_vel[i] = dir * spark_speed * R * _rng.randf_range(0.7, 1.0)
		_life[i] = spark_life * _rng.randf_range(0.7, 1.2)
		_max_life[i] = _life[i]
		_size[i] = spark_size * _rng.randf_range(0.7, 1.2)
		_rocket[i] = 0
		_set_color(i, col if k % 3 != 0 else col2)


func _free_slot() -> int:
	for i in MAX_SPARKS:
		if _life[i] <= 0.0:
			return i
	return -1


func _set_color(i: int, c: Color) -> void:
	var o := i * STRIDE
	_buf[o + 12] = c.r
	_buf[o + 13] = c.g
	_buf[o + 14] = c.b
	_buf[o + 15] = 1.0


func _write() -> void:
	for i in MAX_SPARKS:
		var o := i * STRIDE
		var s := 0.0
		if _life[i] > 0.0:
			# Sparks shrink away as they die (rockets keep their size).
			s = _size[i] * (1.0 if _rocket[i] == 1 else sqrt(clampf(_life[i] / _max_life[i], 0.0, 1.0)))
		_buf[o] = s
		_buf[o + 5] = s
		_buf[o + 10] = s
		var p := _pos[i]
		_buf[o + 3] = p.x
		_buf[o + 7] = p.y
		_buf[o + 11] = p.z
	multimesh.buffer = _buf


## An explosion nearby: throws the sparks around and launches a volley.
func blast(origin: Vector3, strength: float) -> void:
	var R := _globe.globe_radius
	for i in MAX_SPARKS:
		if _life[i] > 0.0:
			var d := _pos[i] - origin
			_vel[i] += d.normalized() * strength * R * 2.0 / (1.0 + d.length() / R * 3.0)
	for k in 4:
		_launch(_globe.global_basis.orthonormalized().inverse() * Vector3.UP)
