@tool
class_name GlobeCreatures
extends MultiMeshInstance3D
## Little creatures living in a SnowGlobe: swimmers and fliers flock as
## boids, walkers wander the floor. All of them panic when the globe is shaken,
## react to a finger on the glass, and respect the globe's fill (fish out of
## water flop about; fliers are sluggish under water). Walkers get knocked
## over by hard shakes or tilting and climb back to their feet.
##
## Simulated on the CPU in the globe's local space, like GlobeParticles, with
## a spatial hash so flocking stays cheap.

const SHADER := preload("res://shaders/creature.gdshader")
const STRIDE := 20
const MAX_AMOUNT := 300

enum State { ACTIVE, RESTING, TUMBLING, GETTING_UP }

@export_range(0, MAX_AMOUNT, 1) var amount := 40:
	set(v): amount = v; _queue_reset()
@export var species: CreatureSpecies:
	set(v):
		if species and species.changed.is_connected(_queue_reset):
			species.changed.disconnect(_queue_reset)
		species = v
		if species:
			species.changed.connect(_queue_reset)
		_queue_reset()
@export var random_seed := 0:
	set(v): random_seed = v; _queue_reset()

var _globe: SnowGlobe
var _sp: CreatureSpecies
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _fwd := PackedVector3Array()
var _wander := PackedVector3Array()
var _state := PackedInt32Array()
var _timer := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _size := PackedFloat32Array()
var _panic := PackedFloat32Array()
var _spin: Array[Quaternion] = []
var _spin_axis := PackedVector3Array()
var _buf := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _agitation := 0.0
var _glow := 0.0
var _reset_queued := false


func _init() -> void:
	add_to_group(&"globe_layer")


func _ready() -> void:
	var n := get_parent()
	while n and not (n is SnowGlobe):
		n = n.get_parent()
	_globe = n as SnowGlobe
	if _globe == null:
		push_warning("GlobeCreatures must be inside a SnowGlobe.")
		return
	_globe.rebuilt.connect(_queue_reset)
	reset()


func _validate_property(property: Dictionary) -> void:
	if property.name in ["multimesh", "material_override", "custom_aabb"]:
		property.usage &= ~PROPERTY_USAGE_STORAGE


func _queue_reset() -> void:
	if _reset_queued or not is_inside_tree() or _globe == null:
		return
	_reset_queued = true
	reset.call_deferred()


## Rebuilds the mesh/material and looks; existing creatures keep their place
## unless `rescatter` is set.
func reset(rescatter := false) -> void:
	_reset_queued = false
	if _globe == null:
		return
	_sp = species if species else CreatureSpecies.new()
	var look := RandomNumberGenerator.new()
	look.seed = random_seed
	var n := clampi(amount, 0, MAX_AMOUNT)
	var kept := 0 if rescatter else mini(_pos.size(), n)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = CreatureMeshes.get_mesh(_sp.body)
	mm.instance_count = n
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("body", int(_sp.body))
	mat.set_shader_parameter("accent_color", _sp.accent_color)
	mat.set_shader_parameter("detail_color", _sp.detail_color)
	mat.set_shader_parameter("emission_strength", _sp.emission)
	material_override = mat
	# Walkers need contact shadows; small floating swimmers / fliers skip them (GPU cost on phones).
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _sp.movement == CreatureSpecies.Movement.WALK else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	for arr in [_pos, _vel, _fwd, _wander, _spin_axis]:
		arr.resize(n)
	for arr in [_timer, _phase, _size, _panic]:
		arr.resize(n)
	_state.resize(n)
	_spin.resize(n)
	_buf.resize(n * STRIDE)
	for i in n:
		_size[i] = _sp.size * maxf(0.2, 1.0 + _sp.size_randomness * look.randf_range(-1.0, 1.0))
		var col := _sp.color
		var h := col.h + look.randf_range(-0.5, 0.5) * _sp.color_variation * 0.3
		var col_v := Color.from_hsv(fposmod(h, 1.0), col.s, clampf(col.v * (1.0 + look.randf_range(-0.5, 0.5) * _sp.color_variation), 0.0, 1.0))
		var rnd := look.randf()
		if i >= kept:
			_spawn(i)
		var o := i * STRIDE
		_buf[o + 12] = col_v.r
		_buf[o + 13] = col_v.g
		_buf[o + 14] = col_v.b
		_buf[o + 15] = 1.0
		_buf[o + 18] = rnd
	_write_all()
	if n > 0:
		mm.buffer = _buf
	multimesh = mm
	custom_aabb = GlobeParticles.glass_aabb(_globe)


func _spawn(i: int) -> void:
	var shape := _globe.get_container()
	var gc := _globe.glass_center
	var s := _size[i]
	var p: Vector3
	if _sp.movement == CreatureSpecies.Movement.WALK:
		var a := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * shape.floor_radius * 0.8 * shape.radius_factor(sin(a), cos(a))
		p = Vector3(sin(a) * r, 0, cos(a) * r)
		p.y = _globe.get_floor_height(p.x, p.z)
	else:
		p = shape.random_point(_rng, s * 2.0 + _globe.globe_radius * 0.03, _globe.floor_y - gc.y + s * 2.0) + gc
	_pos[i] = p
	var dir := Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
	if dir == Vector3.ZERO:
		dir = Vector3.FORWARD
	_vel[i] = dir * _sp.speed * _globe.globe_radius * 0.5
	_fwd[i] = dir
	_wander[i] = dir
	_state[i] = State.ACTIVE
	_timer[i] = 0.0
	_phase[i] = _rng.randf() * TAU
	_panic[i] = 0.0
	_spin[i] = Quaternion.IDENTITY
	_spin_axis[i] = Vector3.UP


func _physics_process(delta: float) -> void:
	if _globe == null or _pos.is_empty() or multimesh == null or Engine.is_editor_hint():
		return
	_simulate(delta)
	_write_all()
	multimesh.buffer = _buf
	if _sp.shake_glow > 0.0 and material_override:
		# Glow up when shaken, then calm back down.
		_glow = maxf(_glow * exp(-0.7 * delta), minf(_globe.agitation, 1.0))
		(material_override as ShaderMaterial).set_shader_parameter("emission_strength", lerpf(_sp.emission, _sp.shake_glow, _glow))


# --- Simulation ---------------------------------------------------------------

func _simulate(delta: float) -> void:
	var R := _globe.globe_radius
	var inv := _globe.global_basis.orthonormalized().inverse()
	var up := inv * Vector3.UP
	var acc_world := _globe.linear_acceleration
	var fling := -(inv * acc_world)
	var kick := minf(acc_world.length() * 0.01 + _globe.angular_velocity.length() * 0.15, 1.5)
	_agitation *= exp(-1.2 * delta)
	var jolt := maxf(0.0, kick - _agitation)
	_agitation = maxf(_agitation, kick)
	var water := _globe.fill == SnowGlobe.Fill.WATER

	var walking := _sp.movement == CreatureSpecies.Movement.WALK
	var stranded := _sp.movement == CreatureSpecies.Movement.SWIM and not water
	var cell := maxf(_sp.size * _sp.neighbor_radius, R * 0.05)
	var grid := _build_grid(cell, walking)
	var obstacles := _globe.get_obstacles()

	for i in _pos.size():
		# Shaking scares everyone; hard jolts or tilting topple walkers.
		if jolt * _sp.panic > 0.15:
			_panic[i] = maxf(_panic[i], 1.0 + _rng.randf() * jolt * _sp.panic)
			if _state[i] == State.RESTING:
				_state[i] = State.ACTIVE
		_panic[i] = maxf(0.0, _panic[i] - delta)

		match _state[i]:
			State.TUMBLING:
				_tumble(i, delta, up, fling, water, stranded)
				continue
			State.GETTING_UP:
				_get_up(i, delta, up)
				continue
		if stranded:
			_start_tumble(i, Vector3.ZERO)
			continue
		if walking:
			if up.y < 0.6 or jolt * _sp.panic / _sp.grip > 0.5:
				_start_tumble(i, (Vector3(_rng.randf() - 0.5, 0.6, _rng.randf() - 0.5)) * jolt * R * 1.5)
				continue
			_walk(i, delta, grid, cell, obstacles)
		else:
			_fly(i, delta, grid, cell, obstacles, up, water)


## Flocking for swimmers and fliers.
func _fly(i: int, delta: float, grid: Dictionary, cell: float, obstacles: Array[Vector4], up: Vector3, water: bool) -> void:
	var R := _globe.globe_radius
	var p := _pos[i]
	var v := _vel[i]
	var s := _size[i]
	var speed := _sp.speed * R * (0.35 if (_sp.movement == CreatureSpecies.Movement.FLY and water) else 1.0)

	if _state[i] == State.RESTING:
		_timer[i] -= delta
		_vel[i] = Vector3.ZERO
		_phase[i] += delta * _sp.anim_speed * 2.0
		if _timer[i] <= 0.0:
			_state[i] = State.ACTIVE
			_vel[i] = (up + _fwd[i] * 0.5).normalized() * speed
		return

	# Wander: a slowly turning preferred direction.
	var w := _wander[i] + Vector3(_rng.randf() - 0.5, (_rng.randf() - 0.5) * 0.6, _rng.randf() - 0.5) * delta * 4.0
	w = w.normalized()
	_wander[i] = w
	var steer := w * _sp.wander

	# Neighbours.
	var sep := Vector3.ZERO
	var ali := Vector3.ZERO
	var coh := Vector3.ZERO
	var count := 0
	var reach := cell
	for j in _neighbours(grid, p, cell, false):
		if j == i:
			continue
		var d := p - _pos[j]
		var dist := d.length()
		if dist < reach and dist > 1e-5:
			sep += d / (dist * dist) * s
			ali += _vel[j]
			coh += _pos[j]
			count += 1
	if count > 0:
		steer += sep * _sp.separation * 2.0
		steer += (ali / count).normalized() * _sp.alignment
		steer += ((coh / count) - p).normalized() * _sp.cohesion

	steer += _avoid_bounds(p, s * 3.0 + R * 0.08)
	steer += _avoid_props(p, obstacles, s * 2.0)

	if _globe.touch_active:
		var to := _globe.touch_point - p
		steer += to.normalized() * _sp.touch_response * 1.5

	var mult := 1.0
	if _panic[i] > 0.0:
		steer += _wander[i] * 2.0 + Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5) * 4.0
		mult = lerpf(1.0, _sp.panic_speed, minf(_panic[i], 1.0))
	if _sp.movement == CreatureSpecies.Movement.FLY:
		# Fluttering bob.
		steer += up * sin(_phase[i] * 0.5) * 0.8

	var desired := steer.normalized() * speed * mult if steer.length_squared() > 1e-8 else v
	v = v.move_toward(desired, speed * _sp.agility * mult * delta)
	if _sp.movement == CreatureSpecies.Movement.FLY and water:
		v -= up * R * 0.05 * delta
	p += v * delta
	var hit := _contain(p, v, s)
	p = hit[0]
	v = hit[1]

	# Landing (butterflies) when close to the floor or a prop top.
	if _sp.rest_chance > 0.0 and _panic[i] <= 0.0 and _rng.randf() < _sp.rest_chance * delta:
		var fh := _globe.get_floor_height(p.x, p.z)
		if p.y - fh < R * 0.25:
			p.y = fh + s * 0.1
			_state[i] = State.RESTING
			_timer[i] = _sp.rest_time * _rng.randf_range(0.5, 1.5)
			v = Vector3.ZERO

	_pos[i] = p
	_vel[i] = v
	var spd := v.length()
	if spd > 1e-4:
		_fwd[i] = v / spd
	_phase[i] += delta * TAU * _sp.anim_speed * (1.0 + 1.5 * spd / maxf(speed, 1e-4)) * (2.0 if _sp.movement == CreatureSpecies.Movement.FLY else 1.0)


## Wandering over the floor for walkers.
func _walk(i: int, delta: float, grid: Dictionary, cell: float, obstacles: Array[Vector4]) -> void:
	var R := _globe.globe_radius
	var p := _pos[i]
	var s := _size[i]
	var fr := _globe.get_floor_radius()
	var speed := _sp.speed * R * 0.4

	if _state[i] == State.RESTING:
		_timer[i] -= delta
		if _timer[i] <= 0.0:
			_state[i] = State.ACTIVE
		_vel[i] = Vector3.ZERO
		return
	if _sp.rest_chance > 0.0 and _panic[i] <= 0.0 and _rng.randf() < _sp.rest_chance * delta:
		_state[i] = State.RESTING
		_timer[i] = _sp.rest_time * _rng.randf_range(0.5, 1.5)
		return

	var heading := Vector3(_fwd[i].x, 0, _fwd[i].z)
	if heading.length_squared() < 1e-6:
		heading = Vector3.FORWARD
	heading = heading.normalized().rotated(Vector3.UP, (_rng.randf() - 0.5) * _sp.wander * 6.0 * delta)
	var steer := heading * 2.0

	for j in _neighbours(grid, p, cell, true):
		if j == i:
			continue
		var d := Vector3(p.x - _pos[j].x, 0, p.z - _pos[j].z)
		var dist := d.length()
		if dist < s * 2.5 and dist > 1e-5:
			steer += d / dist * _sp.separation * (1.0 - dist / (s * 2.5)) * 3.0
	if _sp.follow_leader > 0.0 and i % 12 != 0:
		var lead := _pos[i - 1] - p
		lead.y = 0.0
		if lead.length() > s * 1.4:
			steer += lead.normalized() * _sp.follow_leader * 3.0
	var rr := Vector2(p.x, p.z).length()
	var edge := fr * 0.88 * _globe.get_container().radius_factor(p.x, p.z) - s
	if rr > edge:
		steer += -Vector3(p.x, 0, p.z).normalized() * (rr - edge) / maxf(s, 1e-3) * 2.0
	steer += _avoid_props(p, obstacles, s)
	if _globe.touch_active:
		var to := _globe.touch_point - p
		to.y = 0.0
		steer += to.normalized() * _sp.touch_response
	var mult := 1.0
	if _panic[i] > 0.0:
		mult = lerpf(1.0, _sp.panic_speed, minf(_panic[i], 1.0))

	var dir := steer.normalized()
	# Turn toward the steering direction at a limited rate.
	var fwd := heading.slerp(dir, minf(1.0, _sp.agility * delta)) if dir != Vector3.ZERO else heading
	p += fwd * speed * mult * delta
	var flat := Vector2(p.x, p.z).limit_length(fr * 0.95 * _globe.get_container().radius_factor(p.x, p.z) - s)
	p.x = flat.x
	p.z = flat.y
	p = _push_out_of_props(p, obstacles, s)
	p.y = _globe.get_floor_height(p.x, p.z)
	_vel[i] = fwd * speed * mult
	_fwd[i] = fwd
	_phase[i] += delta * TAU * _sp.anim_speed * 1.6 * mult
	_pos[i] = p


func _start_tumble(i: int, impulse: Vector3) -> void:
	_state[i] = State.TUMBLING
	_timer[i] = 0.0
	_vel[i] += impulse
	var b := _basis_for(i, Vector3.UP)
	_spin[i] = b.get_rotation_quaternion()
	_spin_axis[i] = Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5).normalized() * _rng.randf_range(2.0, 8.0)


## Loose-body physics: falling, bouncing, spinning; then getting back up.
func _tumble(i: int, delta: float, up: Vector3, fling: Vector3, water: bool, stranded: bool) -> void:
	var R := _globe.globe_radius
	var p := _pos[i]
	var v := _vel[i]
	var s := _size[i] * 0.4
	v += (-up * R * 2.5 + fling * 0.15) * delta
	v *= exp(-(2.5 if water else 0.3) * delta)
	p += v * delta
	var hit := _contain(p, v, s, 0.25)
	p = hit[0]
	v = hit[1]
	var touching: bool = hit[2]
	var axis := _spin_axis[i]
	if touching:
		v *= exp(-6.0 * delta)
		axis *= exp(-5.0 * delta)
	_spin_axis[i] = axis
	if axis.length_squared() > 1e-6:
		_spin[i] = (Quaternion(axis.normalized(), axis.length() * delta) * _spin[i]).normalized()
	_pos[i] = p
	_vel[i] = v
	_phase[i] += delta * TAU * _sp.anim_speed * (3.0 if stranded else 1.0)

	if stranded:
		return
	if touching and v.length() < R * 0.1 and up.y > 0.8:
		_timer[i] += delta
		if _timer[i] > 0.7:
			_state[i] = State.GETTING_UP if _sp.movement == CreatureSpecies.Movement.WALK else State.ACTIVE
			_timer[i] = 0.0
			if _sp.movement != CreatureSpecies.Movement.WALK:
				_vel[i] = up * _sp.speed * R
	else:
		_timer[i] = 0.0


func _get_up(i: int, delta: float, up: Vector3) -> void:
	_timer[i] += delta
	var p := _pos[i]
	p.y = lerpf(p.y, _globe.get_floor_height(p.x, p.z), minf(1.0, delta * 8.0))
	_pos[i] = p
	var upright := _basis_for(i, up).get_rotation_quaternion()
	_spin[i] = _spin[i].slerp(upright, minf(1.0, delta * 6.0))
	if _timer[i] > 0.6:
		_state[i] = State.ACTIVE
		_panic[i] = 0.0


# --- Helpers --------------------------------------------------------------------

## Keeps a point inside the glass and above the floor. Returns [p, v, hit].
func _contain(p: Vector3, v: Vector3, s: float, bounce := 0.0) -> Array:
	var shape := _globe.get_container()
	var gc := _globe.glass_center
	var inset := s + _globe.globe_radius * 0.02
	var hit := false
	var ly := clampf(p.y - gc.y, shape.y_min + inset, shape.y_max - inset)
	if ly != p.y - gc.y:
		hit = true
		v.y = -v.y * bounce
	p.y = gc.y + ly
	var wall := maxf(shape.radius_at(ly) * shape.radius_factor(p.x, p.z) - inset, 0.0)
	var rr := Vector2(p.x, p.z).length()
	if rr > wall:
		var n := Vector3(p.x, 0, p.z) / maxf(rr, 1e-5)
		p.x *= wall / maxf(rr, 1e-5)
		p.z *= wall / maxf(rr, 1e-5)
		var vn := v.dot(n)
		if vn > 0.0:
			v -= n * vn * (1.0 + bounce)
		hit = true
	var fh := _globe.get_floor_height(p.x, p.z) + s
	if p.y < fh:
		p.y = fh
		if v.y < 0.0:
			v.y = -v.y * bounce
		hit = true
	return [p, v, hit]


## Steering away from the glass, its top and the floor.
func _avoid_bounds(p: Vector3, margin: float) -> Vector3:
	var shape := _globe.get_container()
	var gc := _globe.glass_center
	var ly := p.y - gc.y
	var steer := Vector3.ZERO
	var wall := shape.radius_at(clampf(ly, shape.y_min + 1e-3, shape.y_max - 1e-3)) * shape.radius_factor(p.x, p.z)
	var rr := Vector2(p.x, p.z).length()
	if rr > wall - margin and rr > 1e-5:
		steer -= Vector3(p.x, 0, p.z) / rr * (rr - (wall - margin)) / margin * 4.0
	if ly > shape.y_max - margin * 1.5:
		steer.y -= 3.0
	var fh := _globe.get_floor_height(p.x, p.z)
	if p.y < fh + margin:
		steer.y += (fh + margin - p.y) / margin * 4.0
	return steer


func _avoid_props(p: Vector3, obstacles: Array[Vector4], margin: float) -> Vector3:
	var steer := Vector3.ZERO
	for ob in obstacles:
		if p.y > ob.w + margin:
			continue
		var d := Vector3(p.x - ob.x, 0, p.z - ob.y)
		var dist := d.length()
		var reach := ob.z + margin * 2.0
		if dist < reach and dist > 1e-5:
			steer += d / dist * (1.0 - dist / reach) * 4.0
	return steer


func _push_out_of_props(p: Vector3, obstacles: Array[Vector4], s: float) -> Vector3:
	for ob in obstacles:
		var d := Vector2(p.x - ob.x, p.z - ob.y)
		var reach := ob.z + s * 0.5
		if d.length() < reach:
			d = d.normalized() * reach if d.length() > 1e-5 else Vector2(reach, 0)
			p.x = ob.x + d.x
			p.z = ob.y + d.y
	return p


func _build_grid(cell: float, flat: bool) -> Dictionary:
	var grid := {}
	for i in _pos.size():
		var k := _cell_key(_pos[i], cell, flat)
		if grid.has(k):
			grid[k].append(i)
		else:
			grid[k] = PackedInt32Array([i])
	return grid


func _cell_key(p: Vector3, cell: float, flat: bool) -> Vector3i:
	return Vector3i(floori(p.x / cell), 0 if flat else floori(p.y / cell), floori(p.z / cell))


func _neighbours(grid: Dictionary, p: Vector3, cell: float, flat: bool) -> PackedInt32Array:
	var out := PackedInt32Array()
	var c := _cell_key(p, cell, flat)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for dy in ([0] if flat else [-1, 0, 1]):
				var k := c + Vector3i(dx, dy, dz)
				if grid.has(k):
					out.append_array(grid[k])
					if out.size() > 24:
						return out
	return out


## Upright orientation facing the creature's heading.
func _basis_for(i: int, up: Vector3) -> Basis:
	var fwd := _fwd[i]
	if _sp.movement == CreatureSpecies.Movement.WALK:
		fwd = (fwd - up * fwd.dot(up))
	if fwd.length_squared() < 1e-6:
		fwd = up.cross(Vector3.RIGHT)
	fwd = fwd.normalized()
	var right := up.cross(fwd)
	if right.length_squared() < 1e-6:
		right = Vector3.RIGHT
	right = right.normalized()
	return Basis(right, fwd.cross(right), fwd)


func _floor_normal(p: Vector3) -> Vector3:
	var e := _globe.globe_radius * 0.03
	var hx := _globe.get_floor_height(p.x + e, p.z) - _globe.get_floor_height(p.x - e, p.z)
	var hz := _globe.get_floor_height(p.x, p.z + e) - _globe.get_floor_height(p.x, p.z - e)
	return Vector3(-hx, 2.0 * e, -hz).normalized()


func _write_all() -> void:
	if _globe == null:
		return
	var up := _globe.global_basis.orthonormalized().inverse() * Vector3.UP if is_inside_tree() else Vector3.UP
	var walking := _sp.movement == CreatureSpecies.Movement.WALK
	for i in _pos.size():
		var b: Basis
		var st := _state[i]
		if st == State.TUMBLING or st == State.GETTING_UP:
			b = Basis(_spin[i])
		elif walking:
			b = _basis_for(i, _floor_normal(_pos[i]))
		else:
			# Swimmers and fliers bank a little but stay mostly level.
			var fwd := _fwd[i]
			fwd.y *= 0.6 if _sp.movement == CreatureSpecies.Movement.FLY else 1.0
			_fwd[i] = fwd.normalized() if fwd.length_squared() > 1e-6 else _fwd[i]
			b = _basis_for(i, up)
		b = b.scaled(Vector3.ONE * _size[i])
		var o := i * STRIDE
		var p := _pos[i]
		_buf[o] = b.x.x
		_buf[o + 1] = b.y.x
		_buf[o + 2] = b.z.x
		_buf[o + 3] = p.x
		_buf[o + 4] = b.x.y
		_buf[o + 5] = b.y.y
		_buf[o + 6] = b.z.y
		_buf[o + 7] = p.y
		_buf[o + 8] = b.x.z
		_buf[o + 9] = b.y.z
		_buf[o + 10] = b.z.z
		_buf[o + 11] = p.z
		var moving := st == State.ACTIVE and (_vel[i].length_squared() > 1e-8 or not walking)
		_buf[o + 16] = fposmod(_phase[i], TAU * 64.0)
		_buf[o + 17] = float(st)
		_buf[o + 19] = 1.0 if moving or st == State.TUMBLING else 0.0


## An explosion at globe-local `origin`: everyone panics; walkers (and anyone
## close) get knocked flying.
func blast(origin: Vector3, strength: float) -> void:
	var R := _globe.globe_radius
	for i in _pos.size():
		var d := _pos[i] - origin
		var dist := d.length()
		var k := strength * R * 2.5 / (1.0 + dist / R * 3.0)
		_panic[i] = maxf(_panic[i], 2.0 + strength)
		if _sp.movement == CreatureSpecies.Movement.WALK or dist < R * 0.4:
			if _state[i] != State.TUMBLING:
				_start_tumble(i, (d / maxf(dist, 1e-4) + Vector3.UP * 0.8) * k)
			else:
				_vel[i] += d / maxf(dist, 1e-4) * k
		else:
			_vel[i] += d / maxf(dist, 1e-4) * k
	_agitation = maxf(_agitation, minf(strength, 1.5))
