@tool
class_name GlobeParticles
extends MultiMeshInstance3D
## Snow (or bubbles, glitter, ...) floating in a SnowGlobe's liquid.
##
## Add as a child of a SnowGlobe. `amount` sets how many; `style` decides what
## they are and how they move (see GlobeParticleStyle and the presets in
## res://particles/). Several of these can share one globe, e.g. snow + glitter.
##
## Particles are simulated on the CPU in the globe's local space, so turning
## the globe over makes them fall "up", moving it flings them around, and
## twisting it sets the liquid swirling.

const SHADER := preload("res://shaders/globe_particles.gdshader")
## Floats per instance in the MultiMesh buffer: 12 transform, 4 colour, 4 custom.
const STRIDE := 20
## At LITE detail only this share of the particles is simulated and drawn.
const LITE_FRACTION := 0.35

@export_range(0, 5000, 1) var amount := 600:
	set(v): amount = v; _queue_reset()
@export var style: GlobeParticleStyle:
	set(v):
		if style and style.changed.is_connected(_queue_reset):
			style.changed.disconnect(_queue_reset)
		style = v
		if style:
			style.changed.connect(_queue_reset)
		_queue_reset()
## Changes which random scatter / sizes / colours you get.
@export var random_seed := 0:
	set(v): random_seed = v; _queue_reset()
## Run the simulation in the editor too (otherwise it just shows the scatter).
@export var simulate_in_editor := false
## How quickly the liquid spins up to match the glass when the globe is turned.
@export var liquid_spin_up := 1.2

var _globe: SnowGlobe
var _style: GlobeParticleStyle
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _radius := PackedFloat32Array()
var _rest := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _buf := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _fluid_spin := Vector3.ZERO
var _agitation := 0.0
var _time := 0.0
var _reset_queued := false
## Asleep: everything has settled and the globe is still, so the simulation
## is skipped until something moves it.
var _sleeping := false
var _sleep_up := Vector3.UP


func _init() -> void:
	add_to_group(&"globe_layer")


func _ready() -> void:
	var n := get_parent()
	while n and not (n is SnowGlobe):
		n = n.get_parent()
	_globe = n as SnowGlobe
	if _globe == null:
		push_warning("GlobeParticles must be inside a SnowGlobe.")
		return
	_globe.rebuilt.connect(_queue_reset)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	reset()


## The mesh, material and bounds are regenerated from the exported settings,
## so keep them out of saved scenes (the particle buffer alone is huge).
func _validate_property(property: Dictionary) -> void:
	if property.name in ["multimesh", "material_override", "custom_aabb"]:
		property.usage &= ~PROPERTY_USAGE_STORAGE


func _queue_reset() -> void:
	if _reset_queued or not is_inside_tree() or _globe == null:
		return
	_reset_queued = true
	reset.call_deferred()


## Rebuilds the mesh/material and per-particle looks. Existing particles keep
## their positions (so live edits don't make everything jump) unless
## `rescatter` is set; new ones are scattered through the liquid.
func reset(rescatter := false) -> void:
	_reset_queued = false
	if _globe == null:
		return
	_style = style if style else GlobeParticleStyle.new()
	# Looks come from their own seeded generator so they stay the same
	# across resets; positions use the free-running simulation generator.
	var look := RandomNumberGenerator.new()
	look.seed = random_seed
	var kept := 0 if rescatter else mini(_pos.size(), amount)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _make_mesh()
	mm.instance_count = amount
	material_override = _make_material()

	_pos.resize(amount)
	_vel.resize(amount)
	_radius.resize(amount)
	_rest.resize(amount)
	_phase.resize(amount)
	_buf.resize(amount * STRIDE)
	_buf.fill(0.0)
	for i in amount:
		var d := _style.size * maxf(0.05, 1.0 + _style.size_randomness * look.randf_range(-1.0, 1.0))
		_radius[i] = d * 0.5
		if i >= kept:
			_pos[i] = _random_point_in_liquid(_radius[i])
			_vel[i] = Vector3.ZERO
			_rest[i] = 0.0
		_phase[i] = look.randf() * TAU
		var col := _style.color
		var pick := look.randf()
		if _style.color_gradient:
			col = _style.color_gradient.sample(pick)
		var o := i * STRIDE
		_buf[o] = d
		_buf[o + 5] = d
		_buf[o + 10] = d
		_buf[o + 3] = _pos[i].x
		_buf[o + 7] = _pos[i].y
		_buf[o + 11] = _pos[i].z
		_buf[o + 12] = col.r
		_buf[o + 13] = col.g
		_buf[o + 14] = col.b
		_buf[o + 15] = col.a
		_buf[o + 16] = look.randf()
		_buf[o + 17] = look.randf()
		_buf[o + 18] = look.randf()
	if amount > 0:
		mm.buffer = _buf
	multimesh = mm
	custom_aabb = GlobeParticles.glass_aabb(_globe)


func _make_mesh() -> Mesh:
	if _style.shape == GlobeParticleStyle.Shape.CUSTOM and _style.custom_mesh:
		return _style.custom_mesh
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	return quad


func _make_material() -> Material:
	if _style.shape == GlobeParticleStyle.Shape.CUSTOM:
		return _style.custom_material
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("shape", int(_style.shape))
	m.set_shader_parameter("emission_strength", _style.emission)
	m.set_shader_parameter("roughness_value", _style.roughness)
	m.set_shader_parameter("metallic_value", _style.metallic)
	m.set_shader_parameter("tumble_speed", _style.tumble_speed)
	return m


func _random_point_in_liquid(radius: float) -> Vector3:
	var shape := _globe.get_container()
	var gc := _globe.glass_center
	var gap := radius + _globe.globe_radius * 0.02
	for attempt in 30:
		var p := shape.random_point(_rng, gap, _globe.floor_y - gc.y) + gc
		if p.y > _globe.get_floor_height(p.x, p.z) + radius:
			return p
	return gc


func _physics_process(delta: float) -> void:
	if _globe == null or amount == 0 or multimesh == null:
		return
	if Engine.is_editor_hint() and not simulate_in_editor:
		return
	if not Engine.is_editor_hint():
		var shown := -1 if _globe.detail == SnowGlobe.Detail.FULL else _sim_count()
		if multimesh.visible_instance_count != shown:
			multimesh.visible_instance_count = shown
		delta = _globe.lod_step(self, delta)
		if delta <= 0.0:
			return
	if _asleep():
		return
	_simulate(delta)
	multimesh.buffer = _buf


## How many particles are simulated (and drawn) at the current detail.
func _sim_count() -> int:
	if _globe.detail == SnowGlobe.Detail.FULL:
		return _pos.size()
	return mini(_pos.size(), ceili(_pos.size() * LITE_FRACTION))


## True while asleep; any motion, shake, touch or tilt wakes it.
func _asleep() -> bool:
	if not _sleeping:
		return false
	if _globe_stirred() or _globe.global_basis.y.dot(_sleep_up) < 0.999:
		_sleeping = false
	return _sleeping


func _globe_stirred() -> bool:
	return _globe.linear_acceleration.length() > 0.8 or _globe.angular_velocity.length() > 0.05 or _globe.agitation > 0.02 or _globe.touch_active


func _simulate(delta: float) -> void:
	var st := _style
	_time += delta
	var R := _globe.globe_radius
	var shape := _globe.get_container()
	var gc := _globe.glass_center
	var lut := shape.lut_r
	var slopes := shape.lut_slope
	var y_lo := shape.y_min
	var y_hi := shape.y_max
	var inv_step := 1.0 / shape.lut_step
	var lut_last := float(GlassShape.LUT_SIZE) - 0.001
	var flat := shape.flat_shaded
	# Keep particles off the inside of the glass wall.
	var wall_gap := R * 0.02
	var floor_y := _globe.floor_y
	var floor_r := maxf(shape.floor_radius, 1e-4)
	var mound := R * _globe.mound_height
	var obstacles := _globe.get_obstacles()
	var obstacle_top := -INF
	for ob in obstacles:
		obstacle_top = maxf(obstacle_top, ob.w)

	# Forces in the globe's frame: gravity turns with the globe, and when the
	# globe accelerates the particles get left behind.
	var inv := _globe.global_basis.orthonormalized().inverse()
	var acc_world := _globe.linear_acceleration
	var body := (inv * Vector3.DOWN) * st.gravity - (inv * acc_world) * st.shake_response

	# The fill lags behind the glass when it's turned, then catches up.
	var glass_spin := _globe.angular_velocity
	_fluid_spin = _fluid_spin.lerp(glass_spin, 1.0 - exp(-liquid_spin_up * delta))
	var swirl := inv * (_fluid_spin - glass_spin) * st.swirl_response * _globe.get_swirl_scale()

	# Agitation: how stirred up the fill is. A rise in it is a jolt that
	# kicks every particle in a random direction, biased against gravity.
	var kick := minf(acc_world.length() * 0.01 + glass_spin.length() * 0.15, 1.5)
	_agitation *= exp(-1.0 * delta)
	var jolt := maxf(0.0, kick - _agitation) * st.shake_turbulence
	_agitation = maxf(_agitation, kick)
	var up := inv * Vector3.UP * signf(st.gravity)
	var turb := st.turbulence + st.shake_turbulence * _agitation
	var freq := 4.0 / R
	var t := _time

	var damp := exp(-st.drag * _globe.get_drag_scale() * delta)
	# Settled particles stay put, but a good shake knocks them loose.
	var stick := exp(-st.stickiness * delta * (1.0 - minf(_agitation, 1.0)))
	var bounce := 1.0 + st.restitution
	var rain := st.shape == GlobeParticleStyle.Shape.RAIN
	var wind := st.wind
	var lift := st.lift

	var count := _sim_count()
	var settled := 0
	for i in count:
		var p := _pos[i]
		var v := _vel[i]
		var s := _radius[i]

		# Velocity of the fill here: swirl plus a divergence-free wobble,
		# phase-shifted per particle so neighbours don't move in lockstep.
		var u := swirl.cross(p - gc)
		if turb > 0.0:
			var ph := _phase[i]
			u += Vector3(
				sin(p.y * freq + t * 0.9 + ph),
				sin(p.z * freq + t * 1.3 + ph * 2.0),
				sin(p.x * freq + t * 1.1 + ph * 3.0)) * turb
		if wind != 0.0 or lift != 0.0:
			# Circling wind around the axis, gusting per particle, plus lift.
			var gust := 0.7 + 0.3 * sin(t * 0.8 + _phase[i])
			u += Vector3(p.z - gc.z, 0.0, -(p.x - gc.x)).normalized() * wind * R * gust + Vector3.UP * lift * R
		if jolt > 0.001:
			var r3 := Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5) * 2.0
			v += (r3 + up * 1.3) * jolt

		v += body * delta
		v = u + (v - u) * damp
		p += v * delta

		# Glass: look the wall radius up by height (works for any shape).
		var touching := false
		var inset := s + wall_gap
		var ly := p.y - gc.y
		if ly > y_hi - inset:
			ly = y_hi - inset
			if v.y > 0.0:
				v.y = -v.y * st.restitution
			touching = true
		elif ly < y_lo + inset:
			ly = y_lo + inset
			if v.y < 0.0:
				v.y = -v.y * st.restitution
			touching = true
		p.y = gc.y + ly
		var f := clampf((ly - y_lo) * inv_step, 0.0, lut_last)
		var k := int(f)
		var ft := f - k
		var wall_r := lerpf(lut[k], lut[k + 1], ft)
		if flat:
			wall_r *= shape.radius_factor(p.x, p.z)
		wall_r = maxf(wall_r - inset, 0.0)
		var rr := sqrt(p.x * p.x + p.z * p.z)
		if rr > wall_r:
			var slope := lerpf(slopes[k], slopes[k + 1], ft)
			var n2 := Vector2(1.0, -slope).normalized()
			var n := Vector3(p.x / rr * n2.x, n2.y, p.z / rr * n2.x)
			p -= n * (rr - wall_r) * n2.x
			var rr2 := sqrt(p.x * p.x + p.z * p.z)
			if rr2 > wall_r:
				var k2 := wall_r / rr2
				p.x *= k2
				p.z *= k2
			var vn := v.dot(n)
			if vn > 0.0:
				v -= n * vn * bounce
			touching = true

		# Floor.
		var fr := minf(sqrt(p.x * p.x + p.z * p.z) / floor_r, 1.0)
		var fy := floor_y + mound * (1.0 - fr * fr) + s
		if p.y < fy:
			p.y = fy
			if v.y < 0.0:
				v.y = -v.y * st.restitution
			touching = true

		# Props: upright cylinders; particles landing near the top rest on it.
		if p.y < obstacle_top + s:
			for ob in obstacles:
				var dx := p.x - ob.x
				var dz := p.z - ob.y
				var reach := ob.z + s
				var d2 := dx * dx + dz * dz
				if d2 < reach * reach and p.y < ob.w + s:
					if ob.w + s - p.y < R * 0.04:
						p.y = ob.w + s
						v.y = maxf(v.y, 0.0)
					else:
						var d := maxf(sqrt(d2), 1e-5)
						p.x = ob.x + dx / d * reach
						p.z = ob.y + dz / d * reach
						var vr := (v.x * dx + v.z * dz) / d
						if vr < 0.0:
							v.x -= dx / d * vr
							v.z -= dz / d * vr
					touching = true

		if touching:
			v *= stick
			_rest[i] += delta
			if st.pop_at_rest and _rest[i] > st.pop_delay:
				p = _respawn_point(body, s)
				v = Vector3.ZERO
				_rest[i] = 0.0
		else:
			_rest[i] = maxf(0.0, _rest[i] - delta)
		if _rest[i] > 1.0:
			settled += 1

		_pos[i] = p
		_vel[i] = v
		var o := i * STRIDE
		_buf[o + 3] = p.x
		_buf[o + 7] = p.y
		_buf[o + 11] = p.z
		if rain:
			# Streak along the velocity: the shader billboards around this axis.
			var speed := v.length()
			var axis := v / speed if speed > 1e-4 else up * -1.0
			var length := s * 5.0 + speed * st.stretch
			_buf[o + 1] = axis.x * length
			_buf[o + 5] = axis.y * length
			_buf[o + 9] = axis.z * length

	# All settled and nothing stirring: sleep until the globe moves.
	if settled == count and count > 0 and not st.pop_at_rest and not _globe_stirred():
		_sleeping = true
		_sleep_up = _globe.global_basis.y


## Somewhere on the side of the globe the particles drift away from.
func _respawn_point(body: Vector3, radius: float) -> Vector3:
	var gc := _globe.glass_center
	var shape := _globe.get_container()
	var dir := body.normalized() if body.length_squared() > 1e-6 else Vector3.DOWN
	var reach := minf(shape.max_radius, maxf(-shape.y_min, shape.y_max)) * 0.6
	var jitter := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * shape.max_radius * 0.3
	var p := gc - dir * reach + jitter
	p.y = maxf(p.y, _globe.get_floor_height(p.x, p.z) + radius)
	return p


## Bounds of a globe's glass in globe-local space (for culling).
static func glass_aabb(globe: SnowGlobe) -> AABB:
	var shape := globe.get_container()
	var ext := Vector3(shape.max_radius, maxf(-shape.y_min, shape.y_max), shape.max_radius)
	return AABB(globe.glass_center - ext, ext * 2.0)


## An explosion at globe-local `origin`: flings particles outward, harder the
## closer they are, and stirs everything up.
func blast(origin: Vector3, strength: float) -> void:
	var R := _globe.globe_radius
	for i in _pos.size():
		var d := _pos[i] - origin
		var dist := d.length()
		var k := strength * R * 3.0 / (1.0 + dist / R * 3.0)
		var jitter := Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5) * k * 0.5
		_vel[i] += d / maxf(dist, 1e-4) * k + jitter
		_rest[i] = 0.0
	_agitation = maxf(_agitation, minf(strength, 1.5))
