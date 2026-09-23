class_name OrbitCamera
extends Camera3D
## Smoothed orbit camera around a focus point, or a first-person view from
## inside a globe. Driven by main.gd.
##
## Works in any aspect ratio: on narrow screens it backs off so the scene
## isn't cropped at the sides. `view_rect` is the part of the screen not
## covered by UI; the camera frames the focus in the middle of it.

@export var focus := Vector3(0, 1.1, 0)
@export var distance := 6.5
@export var min_distance := 1.5
@export var max_distance := 22.0
@export_range(-89, 89) var pitch_degrees := -14.0
@export var yaw_degrees := 0.0
@export var min_pitch := -80.0
@export var max_pitch := 30.0
@export var smoothing := 12.0
## Width, relative to height, the view must always show (keeps the globe
## from being cropped on narrow portrait screens).
@export var min_width_ratio := 0.7
## Field of view outside and (adjustable) inside a globe.
@export var outside_fov := 45.0
@export var inside_fov := 75.0
## Eye height above the floor inside a globe, as a fraction of its radius.
@export var inside_eye_height := 0.12

## Uncovered part of the screen, in 0..1 screen fractions.
var view_rect := Rect2(0, 0, 1, 1)
## When set, the camera stands on this globe's floor looking around.
var inside: SnowGlobe:
	set(v):
		inside = v
		if v:
			_look_yaw = 180.0
			_look_pitch = 5.0
			_look_yaw_s = _look_yaw
			_look_pitch_s = _look_pitch
			fov = inside_fov

var _yaw: float
var _pitch: float
var _distance: float
var _rect := Rect2(0, 0, 1, 1)
var _look_yaw := 180.0
var _look_pitch := 5.0
var _look_yaw_s := 180.0
var _look_pitch_s := 5.0


func _ready() -> void:
	_yaw = yaw_degrees
	_pitch = pitch_degrees
	_distance = distance
	_apply()


## Drag: orbits outside, looks around inside.
func orbit(delta_yaw: float, delta_pitch: float) -> void:
	if inside:
		_look_yaw -= delta_yaw
		_look_pitch = clampf(_look_pitch - delta_pitch, -80.0, 85.0)
		return
	yaw_degrees -= delta_yaw
	pitch_degrees = clampf(pitch_degrees - delta_pitch, min_pitch, max_pitch)


## Wheel / pinch: distance outside, field of view inside.
func zoom(factor: float) -> void:
	if inside:
		inside_fov = clampf(inside_fov * factor, 30.0, 110.0)
		return
	distance = clampf(distance * factor, min_distance, max_distance)


func _process(delta: float) -> void:
	var t := 1.0 - exp(-smoothing * delta)
	if inside and is_instance_valid(inside):
		_look_yaw_s = lerpf(_look_yaw_s, _look_yaw, t)
		_look_pitch_s = lerpf(_look_pitch_s, _look_pitch, t)
		fov = lerpf(fov, inside_fov, t)
		_apply_inside()
		return
	_yaw = lerpf(_yaw, yaw_degrees, t)
	_pitch = lerpf(_pitch, pitch_degrees, t)
	_distance = lerpf(_distance, distance, t)
	_rect.position = _rect.position.lerp(view_rect.position, t)
	_rect.size = _rect.size.lerp(view_rect.size, t)
	fov = lerpf(fov, outside_fov, t)
	near = 0.05
	_apply()


## Standing on the floor a little way out from the middle, facing inward, and
## moving (and tumbling) with the globe.
func _apply_inside() -> void:
	var g := inside
	var fr := g.get_floor_radius()
	var spot := Vector3(0, 0, fr * 0.45)
	spot.y = g.get_floor_height(spot.x, spot.z) + g.globe_radius * inside_eye_height
	var look := Basis.from_euler(Vector3(deg_to_rad(_look_pitch_s), deg_to_rad(_look_yaw_s), 0.0))
	global_transform = g.global_transform * Transform3D(look, spot)
	h_offset = 0.0
	v_offset = 0.0
	near = 0.005


func _apply() -> void:
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	# `distance` frames the scene for a full landscape screen. Back off so the
	# free part of the screen shows at least that much height, and at least
	# `min_width_ratio` of it across (portrait phones, editor panels).
	var w := maxf(_rect.size.x, 0.2)
	var h := maxf(_rect.size.y, 0.2)
	var d := _distance * maxf(1.0 / h, min_width_ratio / (aspect * w))

	var b := Basis.from_euler(Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw), 0.0))
	position = focus + b * Vector3(0, 0, d)
	look_at(focus)

	# Slide the image so the focus lands in the middle of the free area.
	var half_h := tan(deg_to_rad(fov) * 0.5) * d
	var half_w := half_h * aspect
	var center := _rect.get_center() * 2.0 - Vector2.ONE # -1..1, y down
	h_offset = -center.x * half_w
	v_offset = center.y * half_h
