class_name OrbitCamera
extends Camera3D
## Smoothed orbit camera around a focus point. Driven by main.gd.
##
## Works in any aspect ratio: on narrow screens it backs off so the scene
## isn't cropped at the sides. `view_rect` is the part of the screen not
## covered by UI; the camera frames the focus in the middle of it.

@export var focus := Vector3(0, 1.1, 0)
@export var distance := 5.2
@export var min_distance := 1.5
@export var max_distance := 12.0
@export_range(-89, 89) var pitch_degrees := -14.0
@export var yaw_degrees := 0.0
@export var min_pitch := -80.0
@export var max_pitch := 30.0
@export var smoothing := 12.0
## Width, relative to height, the view must always show (keeps the globe
## from being cropped on narrow portrait screens).
@export var min_width_ratio := 0.7

## Uncovered part of the screen, in 0..1 screen fractions.
var view_rect := Rect2(0, 0, 1, 1)

var _yaw: float
var _pitch: float
var _distance: float
var _rect := Rect2(0, 0, 1, 1)


func _ready() -> void:
	_yaw = yaw_degrees
	_pitch = pitch_degrees
	_distance = distance
	_apply()


func orbit(delta_yaw: float, delta_pitch: float) -> void:
	yaw_degrees -= delta_yaw
	pitch_degrees = clampf(pitch_degrees - delta_pitch, min_pitch, max_pitch)


func zoom(factor: float) -> void:
	distance = clampf(distance * factor, min_distance, max_distance)


func _process(delta: float) -> void:
	var t := 1.0 - exp(-smoothing * delta)
	_yaw = lerpf(_yaw, yaw_degrees, t)
	_pitch = lerpf(_pitch, pitch_degrees, t)
	_distance = lerpf(_distance, distance, t)
	_rect.position = _rect.position.lerp(view_rect.position, t)
	_rect.size = _rect.size.lerp(view_rect.size, t)
	_apply()


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
