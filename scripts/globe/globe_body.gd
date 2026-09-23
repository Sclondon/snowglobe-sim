class_name GlobeBody
extends RigidBody3D
## Physics body for one snow globe on the shelf (the SnowGlobe is its child,
## sharing its origin). Grab it and it swings from where you hold it; let go
## mid-swing and it flies. It's bottom-heavy and gently rights itself, falls
## back onto the shelf if tossed off, and is steered kinematically while being
## inspected. Feeds its motion to the globe so the contents react.

signal fell_off

## How hard the grabbed point is pulled toward the pointer.
@export var grab_stiffness := 90.0
## Damping on the grabbed point (higher = less wobble while carrying).
@export var grab_damping := 11.0
## Strongest pull (N per kg), so fast drags don't teleport the globe.
@export var max_grab_accel := 120.0
## Torque that stands the globe back up.
@export var upright_strength := 6.0
@export var upright_damping := 1.5
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


## Collision hull from the glass and stand, plus a low centre of mass so the
## globe settles upright like a weeble.
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
	if globe.base_type != GlobeBase.Kind.NONE:
		var r_base := globe.globe_radius * (globe.stand_bottom_radius if globe.base_type == GlobeBase.Kind.PEDESTAL else 1.25)
		for i in sides:
			var d := MeshUtil.ring_dir(i, sides)
			pts.append(d * r_base)
			pts.append(d * shape.floor_radius * 1.06 + Vector3(0, globe.floor_y, 0))
	var hull := ConvexPolygonShape3D.new()
	hull.points = pts
	_shape_node.shape = hull
	center_of_mass = Vector3(0, globe.floor_y * 0.6, 0)


## Starts carrying the globe from a world-space point on it.
func grab(world_point: Vector3) -> void:
	held = true
	grab_local = global_transform.affine_inverse() * world_point
	drag_target = world_point


func release() -> void:
	held = false


## A burst of jolts; strength 1 = the Shake button.
func shake(strength := 1.0) -> void:
	_shake_time = 0.0
	_shake_power = strength * shake_strength
	_shake_dir = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-0.4, 0.4)).normalized()


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


func respawn(at: Vector3) -> void:
	_steer = 0
	freeze = false
	held = false
	global_transform = Transform3D(Basis(), at + Vector3(0, 1.2, 0))
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var com := state.transform * state.center_of_mass_local
	if held:
		var grab_world := state.transform * grab_local
		var r := grab_world - state.transform.origin
		var point_vel := state.linear_velocity + state.angular_velocity.cross(r)
		var accel := (drag_target - grab_world) * grab_stiffness - point_vel * grab_damping
		accel = accel.limit_length(max_grab_accel)
		# Hold against gravity too, so it hangs rather than sags.
		state.apply_force((accel + Vector3.UP * 9.8) * mass, r)
		state.angular_velocity *= exp(-2.5 * state.step)

	# Gentle self-righting (always on, stronger while carried).
	var up := state.transform.basis.y
	var tilt := up.cross(Vector3.UP)
	var w := state.angular_velocity
	var tilt_w := w - Vector3.UP * w.dot(Vector3.UP)
	var k := upright_strength * (2.5 if held else 1.0)
	state.apply_torque((tilt * k - tilt_w * upright_damping) * mass)

	if _shake_time >= 0.0:
		_shake_time += state.step
		var period := 0.07
		var prev := int((_shake_time - state.step) / period)
		var now := int(_shake_time / period)
		if now != prev:
			# Alternate side to side with a little hop, fading out.
			var fade := maxf(0.0, 1.0 - _shake_time / 0.7)
			var side := 1.0 if now % 2 == 0 else -1.0
			var jolt := _shake_dir.rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5)) * side * 2.4 + Vector3.UP * _rng.randf_range(0.3, 1.2)
			state.apply_impulse(jolt * _shake_power * fade * mass, com - state.transform.origin + Vector3.UP * 0.3)
		if _shake_time > 0.7:
			_shake_time = -1.0


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
