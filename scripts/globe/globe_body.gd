class_name GlobeBody
extends RigidBody3D
## Physics body for one snow globe on the shelf (the SnowGlobe is its child,
## sharing its origin). Grab it and it swings from where you hold it; let go
## mid-swing and it flies. It's bottom-heavy (it wobbles back from a nudge but
## can be knocked over), drops back in from above if tossed off the shelf, and
## is steered kinematically while being inspected. Feeds its motion to the
## globe so the contents react.

signal fell_off
## Landed or hit something hard (world position, strength 0..~3).
signal thumped(at: Vector3, strength: float)

## How hard the grabbed point is pulled toward the pointer.
@export var grab_stiffness := 260.0
## Damping on the grabbed point (higher = less wobble while carrying).
@export var grab_damping := 22.0
## Strongest pull (N per kg), so fast drags don't teleport the globe.
@export var max_grab_accel := 450.0
## Height above its spot a fallen-off globe drops back in from.
@export var respawn_height := 6.0
## How long the Shake routine lasts (seconds).
@export var shake_duration := 0.9
## Below this height the globe counts as fallen off and respawns.
@export var fall_limit := -6.0
## Strength of a Shake-button shake.
@export var shake_strength := 1.0

var globe: SnowGlobe
## Where this globe rests on the shelf (world position of its base).
var home := Vector3.ZERO
var held := false
## Grab point in body-local space, and where the pointer wants it (world).
var grab_local := Vector3.ZERO
var drag_target := Vector3.ZERO

## Inspect / return: kinematic steering toward these.
var target_center := Vector3.ZERO
var target_orientation := Quaternion.IDENTITY
var _steer := 0 # 0 = physics, 1 = inspect, 2 = returning to the shelf
var _return_spot := Vector3.ZERO
var _steer_time := 0.0

var _shake_time := -1.0
var _shake_power := 0.0
var _shake_dir := Vector3.RIGHT
var _shake_anchor := Vector3.ZERO
var _shake_grab := Vector3.ZERO
var _prev_speed := 0.0
var _prev_center_vel := Vector3.ZERO
var _last_center := Vector3.ZERO
var _kin_angular := Vector3.ZERO
var _accel := Vector3.ZERO
var _hull_points := PackedVector3Array()
var _shape_node: CollisionShape3D
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	mass = 1.0
	continuous_cd = true
	can_sleep = false
	linear_damp = 0.05
	angular_damp = 0.8
	var mat := PhysicsMaterial.new()
	mat.friction = 0.7
	mat.bounce = 0.15
	physics_material_override = mat
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# Needed to notice hard landings.
	contact_monitor = true
	max_contacts_reported = 4
	_rng.randomize()


func _ready() -> void:
	for c in get_children():
		if c is SnowGlobe:
			globe = c
	_shape_node = CollisionShape3D.new()
	add_child(_shape_node)
	if globe:
		globe.rebuilt.connect(_rebuild_shape)
		_rebuild_shape()


## Collision hull from the glass and stand, plus a low centre of mass so a
## nudged globe rocks back upright (a hard knock still tips it over).
func _rebuild_shape() -> void:
	var pts := PackedVector3Array()
	var shape := globe.get_container()
	var gc := globe.glass_center
	var sides := 16
	var glass_sides := shape.sides if shape.flat_shaded else sides
	for p in shape.profile:
		for i in glass_sides:
			pts.append(gc + MeshUtil.ring_dir(i, glass_sides) * p.x + Vector3(0, p.y, 0))
	# The stand: a ring at the bottom and one at the floor.
	if globe.base_type == GlobeBase.Kind.PLATFORM:
		for i in sides:
			var d := MeshUtil.ring_dir(i, sides)
			pts.append(d * globe.platform_radius())
			pts.append(d * globe.platform_radius() + Vector3(0, globe.platform_top(), 0))
	elif globe.base_type != GlobeBase.Kind.NONE:
		var r_base := globe.globe_radius * (globe.stand_bottom_radius if globe.base_type == GlobeBase.Kind.PEDESTAL else 1.25)
		for i in sides:
			var d := MeshUtil.ring_dir(i, sides)
			pts.append(d * r_base)
			pts.append(d * shape.floor_radius * 1.06 + Vector3(0, globe.floor_y, 0))
	var hull := ConvexPolygonShape3D.new()
	hull.points = pts
	_shape_node.shape = hull
	# High enough that a hard knock can leave it lying on its side, low enough
	# that small nudges still wobble back upright.
	center_of_mass = Vector3(0, lerpf(globe.floor_y, globe.glass_center.y, 0.45), 0)
	# Bigger globes are heavier (forces below scale with mass, so they still
	# follow the pointer, just with more swing).
	mass = clampf(globe.globe_radius * globe.globe_radius, 0.12, 5.0)


## Starts carrying the globe from a world-space point on it.
func grab(world_point: Vector3) -> void:
	held = true
	grab_local = global_transform.affine_inverse() * world_point
	drag_target = world_point


func release() -> void:
	held = false


## A good hard shake, like a hand picking it up and shaking it: lift, then
## swing side to side a few times. strength 1 = the Shake button.
func shake(strength := 1.0) -> void:
	if freeze:
		# Inspecting: wobble the steered target instead.
		_shake_time = 0.0
		_shake_power = strength * shake_strength
		return
	_shake_time = 0.0
	_shake_power = clampf(strength * shake_strength, 0.3, 2.0)
	var cam_right := Vector3.RIGHT
	var vp := get_viewport()
	if vp and vp.get_camera_3d():
		cam_right = vp.get_camera_3d().global_basis.x
	_shake_dir = (cam_right + Vector3(0, 0, _rng.randf_range(-0.3, 0.3))).normalized()
	# Hold it by the top of the glass.
	var top := globe.glass_center + Vector3.UP * globe.get_container().y_max * 0.8
	_shake_grab = top
	_shake_anchor = global_transform * top


## Switches to kinematic steering (inspect mode).
func begin_inspect() -> void:
	held = false
	_steer = 1
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	target_orientation = global_basis.get_rotation_quaternion()
	_return_spot = Vector3(global_position.x, 0.0, global_position.z)


## Glides back to where it was on the shelf, then hands over to physics.
func end_inspect() -> void:
	_steer = 2
	_steer_time = 0.0
	target_orientation = Quaternion(Vector3.UP, global_basis.get_euler().y)


## Moves the globe (while inspecting) so its glass centre ends up here.
func set_target_center(world_center: Vector3) -> void:
	target_center = world_center


## Drops the globe back in from above "at", turning slowly.
func respawn(at: Vector3) -> void:
	_steer = 0
	freeze = false
	held = false
	_shake_time = -1.0
	global_transform = Transform3D(Basis(), at + Vector3(0, respawn_height, 0))
	linear_velocity = Vector3.ZERO
	# A lazy turn about its own axis only: landing tilted from this height would
	# catch the stand's edge and roll it over.
	angular_velocity = Vector3(0, _rng.randf_range(-1.5, 1.5), 0)


## Stands it back up where it is (used by "put back" / reset).
func stand_up() -> void:
	global_transform = Transform3D(Basis(Vector3.UP, global_basis.get_euler().y), Vector3(global_position.x, maxf(global_position.y, 0.0) + 0.05, global_position.z))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var target := drag_target
	var grab_point := grab_local
	var pulling := held
	if _shake_time >= 0.0 and not freeze:
		# The "hand" shake: lift, then swing side to side, then let go.
		_shake_time += state.step
		var t := _shake_time / shake_duration
		var R := globe.globe_radius
		var lift := sin(minf(t * 3.0, 1.0) * PI * 0.5) * (1.0 - smoothstep(0.8, 1.0, t))
		var swing := sin(_shake_time * TAU * 4.0) * smoothstep(0.1, 0.25, t) * (1.0 - smoothstep(0.75, 1.0, t))
		var bob := sin(_shake_time * TAU * 8.0) * 0.3
		var offset := Vector3.UP * (0.35 + bob * 0.2) * R * lift * _shake_power + _shake_dir * swing * 0.45 * R * _shake_power
		if held:
			target += offset
		else:
			grab_point = _shake_grab
			target = _shake_anchor + offset
			pulling = true
		if t >= 1.0:
			_shake_time = -1.0
	if pulling:
		var grab_world := state.transform * grab_point
		var r := grab_world - state.transform.origin
		var point_vel := state.linear_velocity + state.angular_velocity.cross(r)
		var accel := (target - grab_world) * grab_stiffness - point_vel * grab_damping
		accel = accel.limit_length(max_grab_accel)
		# Hold against gravity too, so it hangs rather than sags.
		state.apply_force((accel + Vector3.UP * 9.8) * mass, r)
		state.angular_velocity *= exp(-1.2 * state.step)

	# Hard landings / knocks (for the room's dust and fog).
	var speed := state.linear_velocity.length()
	if _prev_speed - speed > 2.5 and state.get_contact_count() > 0:
		thumped.emit(state.transform.origin, (_prev_speed - speed) * 0.3)
	_prev_speed = speed


func _physics_process(delta: float) -> void:
	if globe == null or delta <= 0.0:
		return
	if _steer != 0:
		_steer_kinematic(delta)
	elif global_position.y < fall_limit:
		fell_off.emit()
		respawn(home)

	# Motion of the glass centre, for the contents (smoothed a little so
	# contact jitter on the shelf doesn't stir them).
	var c := global_transform * globe.glass_center
	var v := linear_velocity + angular_velocity.cross(c - global_position)
	if freeze:
		v = (c - _last_center) / delta
		globe.angular_velocity = _kin_angular
	else:
		globe.angular_velocity = angular_velocity
	_last_center = c
	var a := (v - _prev_center_vel) / delta
	_prev_center_vel = v
	_accel = _accel.lerp(a, 0.6)
	globe.linear_acceleration = _accel
	globe.linear_velocity = v


func _steer_kinematic(delta: float) -> void:
	var t := 1.0 - exp(-14.0 * delta)
	var cur := global_basis.get_rotation_quaternion()
	var rot := cur.slerp(target_orientation, 1.0 - exp(-16.0 * delta))
	var dq := rot * cur.inverse()
	if dq.w < 0.0:
		dq = -dq
	var ang := dq.get_angle()
	_kin_angular = dq.get_axis() * (ang / delta) if ang > 1e-6 else Vector3.ZERO
	var b := Basis(rot)
	var goal_center := target_center
	if _shake_time >= 0.0:
		# Shaking while inspecting: wobble in front of the camera.
		_shake_time += delta
		var fade := 1.0 - clampf(_shake_time / shake_duration, 0.0, 1.0)
		goal_center += (Vector3.RIGHT * sin(_shake_time * TAU * 4.0) + Vector3.UP * sin(_shake_time * TAU * 6.0) * 0.5) * globe.globe_radius * 0.35 * fade * _shake_power
		t = 1.0 - exp(-30.0 * delta)
		if fade <= 0.0:
			_shake_time = -1.0
	if _steer == 2:
		goal_center = _return_spot + Vector3.UP * (globe.glass_center.y + 0.25)
	var center := (global_transform * globe.glass_center).lerp(goal_center, t)
	global_transform = Transform3D(b, center - b * globe.glass_center)
	_steer_time += delta
	# Hand back to physics once home (or after a moment regardless).
	if _steer == 2 and ((center.distance_to(goal_center) < 0.05 and ang < 0.02) or _steer_time > 1.5):
		_steer = 0
		freeze = false
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
