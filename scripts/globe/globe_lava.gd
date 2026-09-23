class_name GlobeLava
extends MeshInstance3D
## Lava-lamp wax: blobs warm up in the pool on the floor, swell and rise,
## cool near the top and sink back, merging and splitting as they pass (the
## metaballs are ray-marched in lava.gdshader). Shaking stirs them about.

const KIND := "lava"
const SETTINGS: Array[String] = ["blob_count", "blob_size", "color_low", "color_high", "speed", "pool", "glow", "lamp_light"]
const EDITOR_ROWS := [
	["blob_count", "Blobs", 2, 12, 1],
	["blob_size", "Blob size", 0.06, 0.25, 0.005],
	["color_low", "Colour (bottom)"],
	["color_high", "Colour (top)"],
	["speed", "Speed", 0.2, 3.0, 0.01],
	["pool", "Pool on the floor", 0.0, 2.0, 0.01],
	["glow", "Glow", 0.3, 2.0, 0.01],
	["lamp_light", "Lamp light"],
]
const SHADER := preload("res://shaders/lava.gdshader")
const MAX_BLOBS := 12

@export_range(2, MAX_BLOBS, 1) var blob_count := 7:
	set(v): blob_count = v; _queue_build()
## Blob radius, in globe radii.
@export_range(0.06, 0.25, 0.005) var blob_size := 0.13:
	set(v): blob_size = v; _queue_build()
@export var color_low := Color(1.0, 0.45, 0.1):
	set(v): color_low = v; _apply_params()
@export var color_high := Color(0.95, 0.15, 0.4):
	set(v): color_high = v; _apply_params()
@export_range(0.2, 3.0, 0.01) var speed := 1.0
## Depth of the wax pool on the floor.
@export_range(0.0, 2.0, 0.01) var pool := 1.0:
	set(v): pool = v; _queue_build()
@export_range(0.3, 2.0, 0.01) var glow := 1.0:
	set(v): glow = v; _apply_params()
## A warm light from the lamp's bulb under the wax.
@export var lamp_light := true:
	set(v):
		lamp_light = v
		if _light:
			_light.visible = v

var _globe: SnowGlobe
var _mat: ShaderMaterial
var _light: OmniLight3D
var _rng := RandomNumberGenerator.new()
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _temp := PackedFloat32Array()
var _base_r := PackedFloat32Array()
var _time := 0.0
var _build_queued := false
var _center := Vector3.ZERO
var _uniform := PackedVector4Array()


func _init() -> void:
	add_to_group(&"globe_layer")


func _ready() -> void:
	var n := get_parent()
	while n and not (n is SnowGlobe):
		n = n.get_parent()
	_globe = n as SnowGlobe
	if _globe == null:
		push_warning("GlobeLava must be inside a SnowGlobe.")
		return
	_rng.randomize()
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light = OmniLight3D.new()
	_light.shadow_enabled = false
	_light.visible = lamp_light
	add_child(_light)
	_globe.rebuilt.connect(_queue_build)
	_build()


func _queue_build() -> void:
	if _build_queued or not is_inside_tree() or _globe == null:
		return
	_build_queued = true
	_build.call_deferred()


func _build() -> void:
	_build_queued = false
	if _globe == null:
		return
	var R := _globe.globe_radius
	var aabb := GlobeParticles.glass_aabb(_globe)
	_center = aabb.get_center()
	position = _center
	var box := BoxMesh.new()
	box.size = aabb.size
	mesh = box
	var shape := _globe.get_container()
	var floor_y := _globe.floor_y
	_pos.resize(blob_count)
	_vel.resize(blob_count)
	_temp.resize(blob_count)
	_base_r.resize(blob_count)
	for i in blob_count:
		var a := _rng.randf() * TAU
		var rr := _rng.randf() * shape.floor_radius * 0.5
		_base_r[i] = blob_size * R * _rng.randf_range(0.7, 1.3)
		_pos[i] = Vector3(sin(a) * rr, floor_y + _base_r[i] * 0.3 + _rng.randf() * R * 0.8, cos(a) * rr)
		_vel[i] = Vector3.ZERO
		_temp[i] = _rng.randf()
	_uniform.resize(blob_count)
	_mat.set_shader_parameter("box_half", aabb.size * 0.5)
	_mat.set_shader_parameter("blob_count", blob_count)
	# Deep enough to cover the floor's mound in the middle.
	var floor_top := maxf(_globe.get_floor_height(0, 0), floor_y)
	_mat.set_shader_parameter("pool_top", floor_top + R * 0.06 * pool - _center.y if pool > 0.0 else -1000.0)
	_mat.set_shader_parameter("pool_radius", shape.floor_radius * 0.98)
	_mat.set_shader_parameter("floor_y", floor_y - _center.y)
	_mat.set_shader_parameter("top_y", _globe.glass_center.y + shape.y_max - _center.y)
	_mat.set_shader_parameter("blend", R * 0.12)
	_light.position = Vector3(0, floor_y + R * 0.1, 0) - _center
	_light.omni_range = R * 2.0
	_apply_params()
	_upload()


func _apply_params() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("color_low", color_low)
	_mat.set_shader_parameter("color_high", color_high)
	_mat.set_shader_parameter("glow", glow)
	if _light:
		_light.light_color = color_low.lerp(Color(1, 0.8, 0.5), 0.4)
		_light.light_energy = 0.9 * glow


func _physics_process(delta: float) -> void:
	if _globe == null or _pos.is_empty() or delta <= 0.0:
		return
	_time += delta
	var R := _globe.globe_radius
	var shape := _globe.get_container()
	var gc := _globe.glass_center
	var floor_y := _globe.floor_y
	var top := gc.y + shape.y_max
	var inv := _globe.global_basis.orthonormalized().inverse()
	var up := inv * Vector3.UP
	var fling := -(inv * _globe.linear_acceleration)
	var stir := _globe.agitation
	for i in _pos.size():
		var p := _pos[i]
		var v := _vel[i]
		var r := _base_r[i]
		var h := clampf((p.y - floor_y) / maxf(top - floor_y, 1e-3), 0.0, 1.0)
		# Warmed by the bulb near the bottom, cooling as it rises.
		var t := _temp[i] + delta * speed * (0.45 * (1.0 - smoothstep(0.0, 0.25, h)) - 0.22 * h - 0.02)
		t = clampf(t, 0.0, 1.0)
		_temp[i] = t
		var buoy := (t - 0.5) * R * 0.9 * speed
		v += up * buoy * delta
		# A lazy drift, and shaking sloshes them around.
		v += Vector3(sin(_time * 0.3 + i * 2.1), 0, cos(_time * 0.27 + i * 1.3)) * R * 0.05 * speed * delta
		v += fling * 0.08 * delta
		v *= exp(-(1.8 - minf(stir, 1.0)) * delta)
		p += v * delta
		# Stay inside the glass (blobs can sink into the pool).
		var ly := clampf(p.y - gc.y, shape.y_min + r * 0.8, shape.y_max - r * 0.8)
		p.y = gc.y + ly
		var wall := maxf(shape.radius_at(ly) * shape.radius_factor(p.x, p.z) - r * 0.9, 0.0)
		var rr := Vector2(p.x, p.z).length()
		if rr > wall:
			p.x *= wall / maxf(rr, 1e-5)
			p.z *= wall / maxf(rr, 1e-5)
			var nrm := Vector3(p.x, 0, p.z).normalized()
			v -= nrm * maxf(v.dot(nrm), 0.0)
		var fh := _globe.get_floor_height(p.x, p.z) - r * 0.2
		if p.y < fh:
			p.y = fh
			v.y = maxf(v.y, 0.0)
		_pos[i] = p
		_vel[i] = v
	_upload()


func _upload() -> void:
	for i in _pos.size():
		# Blobs swell a little as they warm, and wobble.
		var r := _base_r[i] * (0.85 + 0.3 * _temp[i]) * (1.0 + 0.05 * sin(_time * 1.7 + i * 3.0))
		var p := _pos[i] - _center
		_uniform[i] = Vector4(p.x, p.y, p.z, r)
	_mat.set_shader_parameter("blobs", _uniform)
