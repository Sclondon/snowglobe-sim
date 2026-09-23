class_name AmbientAtmosphere
extends Node3D
## Dust drifting through the room (glinting where the spotlight catches it)
## and low fog creeping over the shelf. Shakes and thumps stir them up via
## disturb().

const SHADER := preload("res://shaders/globe_particles.gdshader")
const STRIDE := 20

## Multipliers on how much dust / fog there is (0 = none).
@export_range(0.0, 3.0, 0.05) var dust_amount := 1.0:
	set(v): dust_amount = v; _queue_rebuild()
@export_range(0.0, 3.0, 0.05) var fog_amount := 1.0:
	set(v): fog_amount = v; _queue_rebuild()
## The region the dust fills.
@export var bounds := AABB(Vector3(-10, 0.1, -5), Vector3(20, 5.5, 10))
@export var spot_light: SpotLight3D

const DUST_BASE := 300
const FOG_BASE := 22

var _dust: MultiMeshInstance3D
var _fog: MultiMeshInstance3D
var _d_pos := PackedVector3Array()
var _d_vel := PackedVector3Array()
var _d_size := PackedFloat32Array()
var _d_buf := PackedFloat32Array()
var _f_pos := PackedVector3Array()
var _f_vel := PackedVector3Array()
var _f_buf := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _rebuild_queued := false


func _ready() -> void:
	_rng.randomize()
	_rebuild()


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


## Pushes nearby dust and fog away from `at` (world space).
func disturb(at: Vector3, strength: float) -> void:
	var reach := 1.5 + strength * 1.5
	for i in _d_pos.size():
		var d := _d_pos[i] - at
		var dist := d.length()
		if dist < reach:
			_d_vel[i] += (d / maxf(dist, 0.05) + Vector3.UP * 0.6) * strength * 1.4 * (1.0 - dist / reach)
	for i in _f_pos.size():
		var d := _f_pos[i] - at
		d.y = 0.0
		var dist := d.length()
		if dist < reach * 1.5:
			_f_vel[i] += d / maxf(dist, 0.05) * strength * 0.6 * (1.0 - dist / (reach * 1.5))


func _rebuild() -> void:
	_rebuild_queued = false
	for c in get_children():
		c.queue_free()
	var nd := int(DUST_BASE * dust_amount)
	var nf := int(FOG_BASE * fog_amount)
	_dust = _make_layer(nd, 4, 1.4, 1.0)
	_fog = _make_layer(nf, 5, 0.1, 0.3)
	_d_pos.resize(nd)
	_d_vel.resize(nd)
	_d_size.resize(nd)
	_d_buf.resize(nd * STRIDE)
	_d_buf.fill(0.0)
	for i in nd:
		_d_pos[i] = bounds.position + Vector3(_rng.randf(), _rng.randf(), _rng.randf()) * bounds.size
		_d_vel[i] = Vector3.ZERO
		_d_size[i] = _rng.randf_range(0.012, 0.03)
		var o := i * STRIDE
		_d_buf[o + 16] = _rng.randf()
		_d_buf[o + 17] = _rng.randf()
	_f_pos.resize(nf)
	_f_vel.resize(nf)
	_f_buf.resize(nf * STRIDE)
	_f_buf.fill(0.0)
	for i in nf:
		_f_pos[i] = Vector3(_rng.randf_range(-9.0, 9.0), _rng.randf_range(0.15, 0.5), _rng.randf_range(-3.5, 3.5))
		_f_vel[i] = Vector3.ZERO
		var s := _rng.randf_range(1.6, 2.8)
		var o := i * STRIDE
		_f_buf[o] = s
		_f_buf[o + 5] = s * 0.5
		_f_buf[o + 10] = s
		var c := Color(0.42, 0.44, 0.5)
		_f_buf[o + 12] = c.r
		_f_buf[o + 13] = c.g
		_f_buf[o + 14] = c.b
		_f_buf[o + 15] = 1.0
		_f_buf[o + 16] = _rng.randf()
		_f_buf[o + 17] = _rng.randf()


func _make_layer(count: int, shape: int, emission: float, density: float) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = count
	mmi.multimesh = mm
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("shape", shape)
	m.set_shader_parameter("emission_strength", emission)
	m.set_shader_parameter("roughness_value", 1.0)
	m.set_shader_parameter("tumble_speed", 0.2)
	m.set_shader_parameter("cloud_density", density)
	mmi.material_override = m
	mmi.custom_aabb = bounds.grow(2.0)
	add_child(mmi)
	return mmi


func _process(delta: float) -> void:
	_time += delta
	var t := _time
	var spot_pos := Vector3.ZERO
	var spot_dir := Vector3.DOWN
	var spot_cos := 1.0
	var spot_on := spot_light != null and spot_light.visible
	if spot_on:
		spot_pos = spot_light.global_position
		spot_dir = -spot_light.global_basis.z
		spot_cos = cos(deg_to_rad(spot_light.spot_angle))
	var damp := exp(-1.5 * delta)
	for i in _d_pos.size():
		var p := _d_pos[i]
		var drift := Vector3(sin(p.y * 0.9 + t * 0.21 + i), sin(p.z * 0.7 + t * 0.17) * 0.4 - 0.05, sin(p.x * 0.8 + t * 0.19 + i * 0.5)) * 0.06
		var v := _d_vel[i] * damp
		p += (v + drift) * delta
		# Wrap around the room.
		for k in 3:
			if p[k] < bounds.position[k]:
				p[k] += bounds.size[k]
			elif p[k] > bounds.end[k]:
				p[k] -= bounds.size[k]
		_d_pos[i] = p
		_d_vel[i] = v
		# Glint inside the spotlight's cone.
		var lit := 0.12
		if spot_on:
			var to := (p - spot_pos).normalized()
			lit += smoothstep(spot_cos, spot_cos + 0.05, to.dot(spot_dir)) * 0.9
		var o := i * STRIDE
		var s := _d_size[i]
		_d_buf[o] = s
		_d_buf[o + 5] = s
		_d_buf[o + 10] = s
		_d_buf[o + 3] = p.x
		_d_buf[o + 7] = p.y
		_d_buf[o + 11] = p.z
		_d_buf[o + 12] = 1.0 * lit
		_d_buf[o + 13] = 0.93 * lit
		_d_buf[o + 14] = 0.82 * lit
		_d_buf[o + 15] = 1.0
	if _d_pos.size() > 0:
		_dust.multimesh.buffer = _d_buf
	for i in _f_pos.size():
		var p := _f_pos[i]
		var v := _f_vel[i] * exp(-0.8 * delta)
		p += (v + Vector3(sin(t * 0.05 + i) * 0.05, 0, cos(t * 0.04 + i * 1.7) * 0.04)) * delta
		p.x = wrapf(p.x, -10.0, 10.0)
		p.z = clampf(p.z, -4.0, 4.0)
		_f_pos[i] = p
		_f_vel[i] = v
		var o := i * STRIDE
		_f_buf[o + 3] = p.x
		_f_buf[o + 7] = p.y
		_f_buf[o + 11] = p.z
	if _f_pos.size() > 0:
		_fog.multimesh.buffer = _f_buf
