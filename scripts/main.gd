extends Node3D
## Scene input: carry the globe along the shelf, inspect it up close, shake it.
## Works with mouse, keyboard and touch.
##
## Shelf mode
##   Drag the globe            pick it up and move it along the shelf
##   Wheel while holding       spin it
##   Drag elsewhere            orbit the camera (right-drag works everywhere)
##   Wheel / pinch             zoom
##   Double-click / double-tap inspect
## Inspect mode (I / Tab also toggle; Esc puts it back)
##   Drag                      twist the globe freely
##   Right-drag / two fingers  orbit the camera
##   Wheel / pinch             bring the globe closer or further
## Anywhere
##   Space / Shake button / shaking the phone   shake
##   R                         reset
## (E opens the editor, F11 toggles fullscreen — see app_ui.gd.)

enum Mode { SHELF, INSPECT }

@export var globe: SnowGlobe
@export var camera: OrbitCamera
@export var ui: AppUI
## Spot light that keeps itself aimed at the globe (optional).
@export var spot_light: SpotLight3D
@export var spot_follows_globe := true
## Soft light near the camera that fades in while inspecting, so the contents
## stay visible when the stand is turned between them and the spot (optional).
@export var inspect_fill: Light3D
@export var inspect_fill_energy := 0.8
## Height the globe is lifted to while carried.
@export var lift_height := 0.4
## Half the shelf's width (x) and depth (y) the globe's base must stay within.
@export var shelf_half_size := Vector2(3.1, 1.3)
@export var orbit_sensitivity := 0.3
## Degrees of globe rotation per pixel of mouse movement in inspect mode.
@export var twist_sensitivity := 0.4
## Inspect position as a fraction of the way from the camera's focus to the camera.
@export_range(0.0, 0.9) var inspect_pull := 0.3

var _mode := Mode.SHELF
var _holding := false
var _twisting := false
var _orbiting := false
var _grab_offset := Vector3.ZERO
var _shelf_position := Vector3.ZERO
var _shelf_orientation := Quaternion.IDENTITY
var _view_rect := Rect2(0, 0, 1, 1)
## Active touch points by finger index; two or more means a gesture, and the
## mouse events Godot emulates from the first finger are ignored.
var _touches := {}
var _pinch_distance := 0.0
var _pinch_center := Vector2.ZERO
## Prop being dragged in the editor's Props tab (-1 = none), and where on it
## it was grabbed (floor-relative).
var _prop_drag := -1
var _prop_grab := Vector2.ZERO


func _ready() -> void:
	if ui:
		ui.shake_pressed.connect(func() -> void: globe.shake())
		ui.inspect_pressed.connect(func() -> void: _set_mode(Mode.SHELF if _mode == Mode.INSPECT else Mode.INSPECT))
		ui.view_rect_changed.connect(func(r: Rect2) -> void:
			_view_rect = r
			camera.view_rect = r)
	var motion := DeviceShake.new()
	motion.shaken.connect(func(strength: float) -> void: globe.shake(strength))
	add_child(motion)

	var shot_path := _screenshot_arg()
	if shot_path != "":
		_take_screenshot_and_quit(shot_path)


func _process(delta: float) -> void:
	if _mode == Mode.INSPECT:
		# Float the globe in front of the camera, centred in the part of the
		# screen the UI leaves free.
		var vp := get_viewport().get_visible_rect().size
		var depth := camera.global_position.distance_to(camera.focus) * (1.0 - inspect_pull)
		globe.set_target_center(camera.project_position(_view_rect.get_center() * vp, depth))
	if spot_light and spot_follows_globe:
		var aim := globe.global_transform * globe.sphere_center
		var want := spot_light.global_transform.looking_at(aim, Vector3.FORWARD).basis
		spot_light.global_basis = spot_light.global_basis.slerp(want, 1.0 - exp(-4.0 * delta))
	if inspect_fill:
		var goal := inspect_fill_energy if _mode == Mode.INSPECT else 0.0
		inspect_fill.light_energy = move_toward(inspect_fill.light_energy, goal, delta * 1.5)
		inspect_fill.visible = inspect_fill.light_energy > 0.001


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_on_touch(event)
	elif event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion:
		if _touches.size() >= 2:
			return
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_update_touch_point(event.position)
		if _prop_drag >= 0:
			_drag_prop(event.position)
		elif _holding:
			_drag_to(event.position)
		elif _twisting:
			_twist(event.relative)
		elif _orbiting:
			camera.orbit(event.relative.x * orbit_sensitivity, event.relative.y * orbit_sensitivity)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				globe.shake()
			KEY_I, KEY_TAB:
				_set_mode(Mode.SHELF if _mode == Mode.INSPECT else Mode.INSPECT)
			KEY_ESCAPE:
				_set_mode(Mode.SHELF)
			KEY_R:
				_shelf_position = Vector3.ZERO
				_shelf_orientation = Quaternion.IDENTITY
				_set_mode(Mode.SHELF)


# --- Mouse (and single-finger touch, which Godot turns into mouse events) ---

func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_update_touch_point(event.position)
			else:
				globe.touch_active = false
			if not event.pressed and _prop_drag >= 0:
				_prop_drag = -1
				ui.prop_moved()
				return
			if event.pressed and ui and ui.props_editing and _try_prop_press(event.position):
				return
			if event.double_click and _mode == Mode.SHELF and _hits_globe(event.position):
				_holding = false
				_set_mode(Mode.INSPECT)
				return
			if _mode == Mode.INSPECT:
				_twisting = event.pressed
				return
			if event.pressed and _try_grab(event.position):
				return
			if not event.pressed and _holding:
				_release()
				return
			_orbiting = event.pressed
		MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if not event.pressed:
				return
			var dir := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
			if _mode == Mode.INSPECT:
				inspect_pull = clampf(inspect_pull + dir * 0.05, 0.0, 0.75)
			elif _holding:
				globe.target_orientation = Quaternion(Vector3.UP, dir * deg_to_rad(15.0)) * globe.target_orientation
			else:
				camera.zoom(0.9 if dir > 0.0 else 1.0 / 0.9)


# --- Multi-touch gestures ----------------------------------------------------

func _on_touch(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if event.double_tap and _mode == Mode.SHELF and _hits_globe(event.position):
				_holding = false
				_set_mode(Mode.INSPECT)
		else:
			_touches.erase(event.index)
		if _touches.size() >= 2:
			# A second finger turns whatever the first was doing into a gesture.
			if _holding:
				_release()
			_twisting = false
			_orbiting = false
			_pinch_distance = _touch_spread()
			_pinch_center = _touch_center()
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() < 2:
			return
		var spread := _touch_spread()
		var center := _touch_center()
		if _pinch_distance > 1.0 and spread > 1.0:
			var ratio := spread / _pinch_distance
			if _mode == Mode.INSPECT:
				inspect_pull = clampf(inspect_pull + (ratio - 1.0) * 0.6, 0.0, 0.75)
			else:
				camera.zoom(1.0 / ratio)
		var moved := center - _pinch_center
		camera.orbit(moved.x * orbit_sensitivity, moved.y * orbit_sensitivity)
		_pinch_distance = spread
		_pinch_center = center


func _touch_spread() -> float:
	var pts := _touches.values()
	return (pts[0] as Vector2).distance_to(pts[1]) if pts.size() >= 2 else 0.0


func _touch_center() -> Vector2:
	var pts := _touches.values()
	return ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5 if pts.size() >= 2 else Vector2.ZERO


# --- Modes ----------------------------------------------------------------------

func _set_mode(mode: Mode) -> void:
	if mode == Mode.INSPECT and _mode == Mode.SHELF:
		_shelf_position = Vector3(globe.target_position.x, 0.0, globe.target_position.z)
		_shelf_orientation = globe.target_orientation
	elif mode == Mode.SHELF:
		globe.target_position = _shelf_position
		globe.target_orientation = _shelf_orientation
	_mode = mode
	_holding = false
	_twisting = false
	if ui:
		ui.set_inspecting(mode == Mode.INSPECT)


# --- Shelf mode ---------------------------------------------------------------

func _hits_globe(screen_pos: Vector2) -> bool:
	return globe.intersects_ray(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))


func _try_grab(screen_pos: Vector2) -> bool:
	if not _hits_globe(screen_pos):
		return false
	var hit = _plane_hit(screen_pos)
	if hit == null:
		return false
	_holding = true
	var lifted := globe.target_position
	lifted.y = lift_height
	_grab_offset = lifted - hit
	globe.target_position = lifted
	return true


func _release() -> void:
	_holding = false
	globe.target_position.y = 0.0


func _drag_to(screen_pos: Vector2) -> void:
	var hit = _plane_hit(screen_pos)
	if hit == null:
		return
	var p: Vector3 = hit + _grab_offset
	var margin := globe.globe_radius * globe.stand_bottom_radius
	p.x = clampf(p.x, -shelf_half_size.x + margin, shelf_half_size.x - margin)
	p.z = clampf(p.z, -shelf_half_size.y + margin, shelf_half_size.y - margin)
	globe.target_position = Vector3(p.x, lift_height, p.z)


## Where the mouse ray meets the horizontal carry plane, or null.
func _plane_hit(screen_pos: Vector2):
	var plane := Plane(Vector3.UP, lift_height)
	return plane.intersects_ray(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))


# --- Touching the glass / moving props -----------------------------------------

## Tells the globe where a finger / the mouse presses on the glass (plasma
## arcs and creatures react to it).
func _update_touch_point(screen_pos: Vector2) -> void:
	var hit = globe.raycast_glass(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	globe.touch_active = hit != null
	if hit != null:
		# Just inside the glass, where things can actually reach.
		var p: Vector3 = hit
		globe.touch_point = p + (globe.glass_center - p).normalized() * globe.globe_radius * 0.06


## Where a screen point lands on the globe's floor, as floor-relative (x, z)
## (1 = floor rim), or null.
func _floor_hit(screen_pos: Vector2):
	var inv := globe.global_transform.affine_inverse()
	var o := inv * camera.project_ray_origin(screen_pos)
	var d := (inv.basis * camera.project_ray_normal(screen_pos)).normalized()
	if absf(d.y) < 1e-4:
		return null
	var plane_y := globe.floor_y + globe.globe_radius * globe.mound_height * 0.5
	var t := (plane_y - o.y) / d.y
	if t < 0.0:
		return null
	var p := o + d * t
	var rel := Vector2(p.x, p.z) / maxf(globe.get_floor_radius(), 1e-4)
	return rel if rel.length() < 1.1 else null


## In the editor's Props tab: grab the prop under the pointer, or move the
## selected prop to where the floor was tapped.
func _try_prop_press(screen_pos: Vector2) -> bool:
	var hit = _floor_hit(screen_pos)
	if hit == null:
		return false
	var fr := globe.get_floor_radius()
	var best := -1
	var best_d := INF
	for i in globe.props.size():
		var p: Dictionary = globe.props[i]
		var at := Vector2(float(p.get("x", 0.0)), float(p.get("z", 0.0)))
		var d: float = at.distance_to(hit) * fr
		var reach := float(PropLibrary.info(String(p.get("type", "")))["radius"]) * float(p.get("scale", 1.0)) * globe.globe_radius * 1.3 + globe.globe_radius * 0.05
		if d < reach and d < best_d:
			best = i
			best_d = d
	if best >= 0:
		var p: Dictionary = globe.props[best]
		_prop_grab = Vector2(float(p.get("x", 0.0)), float(p.get("z", 0.0))) - hit
	else:
		best = ui.get_selected_prop()
		if best < 0:
			return false
		_prop_grab = Vector2.ZERO
		globe.move_prop(best, hit.x, hit.y)
	_prop_drag = best
	ui.select_prop(best)
	return true


func _drag_prop(screen_pos: Vector2) -> void:
	var hit = _floor_hit(screen_pos)
	if hit == null:
		return
	var at: Vector2 = hit + _prop_grab
	globe.move_prop(_prop_drag, at.x, at.y)


# --- Inspect mode -------------------------------------------------------------

## Trackball-style: dragging turns the globe about the camera's axes.
func _twist(relative: Vector2) -> void:
	var cam := camera.global_basis
	var k := deg_to_rad(twist_sensitivity)
	var q := Quaternion(cam.y, relative.x * k) * Quaternion(cam.x, relative.y * k)
	globe.target_orientation = (q * globe.target_orientation).normalized()


# --- Dev helper: `godot -- --screenshot=path.png` renders a frame and quits.

func _screenshot_arg() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			return arg.trim_prefix("--screenshot=")
	return ""


func _take_screenshot_and_quit(path: String) -> void:
	for i in 90:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	get_tree().quit()
