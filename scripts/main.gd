extends Node3D
## Scene input and the shelf of globes. Works with mouse, keyboard and touch.
##
## Shelf mode
##   Tap / click a globe        select it (the editor, spotlight and buttons follow)
##   Drag a globe               swing it from where you grabbed it; let go to toss
##   Wheel while holding        spin it
##   Drag elsewhere             orbit the camera (right-drag works everywhere)
##   Wheel / pinch              zoom
##   Double-click / double-tap  inspect
## Inspect mode (I / Tab; Esc puts it back)
##   Drag                       twist the globe freely
##   Right-drag / two fingers   orbit the camera
##   Wheel / pinch              bring the globe closer or further
## Inside mode (V; Esc steps out)
##   Drag                       look around; wheel / pinch zooms
## Anywhere
##   Space / Shake button       shake the selected globe
##   Shaking the phone          shakes every globe on the shelf
##   R                          put every globe back on its spot
## (E opens the editor, F11 toggles fullscreen — see app_ui.gd.)

enum Mode { SHELF, INSPECT, INSIDE }

## The most globes the shelf holds. Change freely.
@export var max_globes := 8
@export var camera: OrbitCamera
@export var ui: AppUI
## Room settings (lighting, tablecloth, dust, fog), saved with the session.
@export var scene_settings: SceneSettings
## Room dust and fog, stirred by shakes and thumps.
@export var atmosphere: AmbientAtmosphere
## Spot light that follows the selected globe (optional).
@export var spot_light: SpotLight3D
## Soft light near the camera that fades in while inspecting, so the contents
## stay visible when the stand is turned between them and the spot (optional).
@export var inspect_fill: Light3D
@export var inspect_fill_energy := 0.8
## Half the shelf's width (x) and depth (y), for placing globes.
@export var shelf_half_size := Vector2(7.6, 2.7)
## Preset used when there's no saved session.
@export_file("*.json") var starting_preset := "res://presets/01_classic_snow.json"
## Lowest / highest a carried globe's grab point can go.
@export var carry_height := Vector2(0.2, 3.5)
## How far a globe lifts off the shelf when you pick it up (globe radii), so
## it's carried rather than dragged along the cloth.
@export var pickup_lift := 0.3
@export var orbit_sensitivity := 0.3
## Degrees of globe rotation per pixel of mouse movement in inspect mode.
@export var twist_sensitivity := 0.4
## Inspect position as a fraction of the way from the camera's focus to the camera.
@export_range(0.0, 0.9) var inspect_pull := 0.3

var globes: Array[GlobeBody] = []
var selected: GlobeBody

var _mode := Mode.SHELF
var _holding: GlobeBody
var _grab_plane := Plane()
var _twisting := false
var _orbiting := false
var _touched: SnowGlobe
var _view_rect := Rect2(0, 0, 1, 1)
var _globes_root: Node3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _ring_alpha := 0.0
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
	_globes_root = Node3D.new()
	_globes_root.name = "Globes"
	add_child(_globes_root)
	_ring = _make_ring()
	add_child(_ring)

	if ui:
		ui.shake_pressed.connect(func() -> void:
			if selected:
				shake_globe(selected))
		ui.set_scene_settings(scene_settings)
		ui.inspect_pressed.connect(func() -> void: _set_mode(Mode.SHELF if _mode == Mode.INSPECT else Mode.INSPECT))
		ui.inside_pressed.connect(func() -> void: _set_mode(Mode.SHELF if _mode == Mode.INSIDE else Mode.INSIDE))
		ui.add_globe_pressed.connect(_on_add_pressed)
		ui.remove_globe_requested.connect(remove_selected)
		ui.save_requested.connect(save_session)
		ui.view_rect_changed.connect(func(r: Rect2) -> void:
			_view_rect = r
			camera.view_rect = r)
	var motion := DeviceShake.new()
	motion.shaken.connect(func(strength: float) -> void:
		for g in globes:
			shake_globe(g, strength))
	add_child(motion)

	var fresh := "--fresh" in OS.get_cmdline_user_args()
	if scene_settings:
		if not fresh:
			scene_settings.restore(GlobePreset.load_session_scene())
		scene_settings.apply_all()
	var session: Array = [] if fresh else GlobePreset.load_session()
	if session.is_empty():
		session = [GlobePreset.load_file(starting_preset)]
	for data in session.slice(0, max_globes):
		add_globe(data)
	select(globes[0])

	var shot_path := _screenshot_arg()
	if shot_path != "":
		_take_screenshot_and_quit(shot_path)


func _process(delta: float) -> void:
	if selected == null:
		return
	var sel_pos := selected.global_position
	if _mode == Mode.INSPECT:
		# Float the globe in front of the camera, centred in the part of the
		# screen the UI leaves free.
		var vp := get_viewport().get_visible_rect().size
		var depth := camera.global_position.distance_to(camera.focus) * (1.0 - inspect_pull)
		selected.set_target_center(camera.project_position(_view_rect.get_center() * vp, depth))
	elif _mode == Mode.SHELF:
		# Keep the selected globe framed as it moves along the shelf.
		var want := Vector3(clampf(sel_pos.x, -shelf_half_size.x, shelf_half_size.x), 1.1, clampf(sel_pos.z, -shelf_half_size.y, shelf_half_size.y) * 0.6)
		camera.focus = camera.focus.lerp(want, 1.0 - exp(-2.5 * delta))
	if spot_light:
		var aim := selected.globe.global_transform * selected.globe.glass_center
		var basis_want := spot_light.global_transform.looking_at(aim, Vector3.FORWARD).basis
		spot_light.global_basis = spot_light.global_basis.slerp(basis_want, 1.0 - exp(-4.0 * delta))
		spot_light.global_position = spot_light.global_position.lerp(Vector3(clampf(sel_pos.x, -shelf_half_size.x, shelf_half_size.x) * 0.8, 5.5, 0.6), 1.0 - exp(-2.0 * delta))
	if inspect_fill:
		var goal := inspect_fill_energy if _mode == Mode.INSPECT else 0.0
		inspect_fill.light_energy = move_toward(inspect_fill.light_energy, goal, delta * 1.5)
		inspect_fill.visible = inspect_fill.light_energy > 0.001
	# Selection ring under the selected globe: flashes on select, then fades.
	_ring_alpha = move_toward(_ring_alpha, 0.0, delta * 1.2)
	_ring_mat.albedo_color.a = _ring_alpha
	_ring.visible = _ring_alpha > 0.01 and _mode == Mode.SHELF and sel_pos.y > -0.5
	_ring.global_position = Vector3(sel_pos.x, 0.012, sel_pos.z)


# --- Globes on the shelf ----------------------------------------------------------

## Puts a new globe on the shelf from preset data. Returns null when full.
func add_globe(data: Dictionary) -> GlobeBody:
	if globes.size() >= max_globes:
		return null
	var body := GlobeBody.new()
	body.name = "Globe%d" % (globes.size() + 1)
	var g := SnowGlobe.new()
	g.name = "SnowGlobe"
	body.add_child(g)
	body.home = _free_spot()
	body.position = body.home + Vector3.UP * 0.02
	_globes_root.add_child(body, true)
	GlobePreset.apply(g, data)
	body.fell_off.connect(_on_fell_off.bind(body))
	body.thumped.connect(func(at: Vector3, strength: float) -> void:
		if atmosphere:
			atmosphere.disturb(at, strength))
	globes.append(body)
	_update_can_add()
	return body


func remove_selected() -> void:
	if globes.size() <= 1 or selected == null:
		return
	_set_mode(Mode.SHELF)
	var gone := selected
	globes.erase(gone)
	gone.queue_free()
	select(globes[0])
	_update_can_add()
	save_session()


func select(body: GlobeBody) -> void:
	if body == selected or body == null:
		return
	if _mode != Mode.SHELF:
		_set_mode(Mode.SHELF)
	selected = body
	if ui:
		ui.set_globe(body.globe)
	var r := body.globe.globe_radius * maxf(body.globe.stand_bottom_radius, 1.0) * 1.08
	(_ring.mesh as TorusMesh).inner_radius = r
	(_ring.mesh as TorusMesh).outer_radius = r + 0.06
	_ring_alpha = 0.85


func save_session() -> void:
	var list: Array[SnowGlobe] = []
	for b in globes:
		list.append(b.globe)
	GlobePreset.save_session(list, scene_settings.capture() if scene_settings else {})


## Shakes a globe and stirs the room's dust around it.
func shake_globe(body: GlobeBody, strength := 1.0) -> void:
	body.shake(strength)
	if atmosphere:
		atmosphere.disturb(body.global_position + Vector3.UP * body.globe.glass_center.y, 1.2 * strength)


## A globe fell off the shelf: if something now sits on its spot, give it a
## free one before it drops back in.
func _on_fell_off(body: GlobeBody) -> void:
	for other in globes:
		if other != body and Vector2(other.global_position.x - body.home.x, other.global_position.z - body.home.z).length() < 1.6:
			body.home = _free_spot(body)
			return


func _on_add_pressed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var body := add_globe(GlobeRandomizer.roll(rng))
	if body:
		select(body)
		save_session()


func _update_can_add() -> void:
	if ui:
		ui.set_can_add(globes.size() < max_globes)


## The spot on the shelf furthest from the other globes (ignoring `skip`).
func _free_spot(skip: GlobeBody = null) -> Vector3:
	var others := globes.filter(func(g) -> bool: return g != skip)
	if others.is_empty():
		return Vector3.ZERO
	var best := Vector3.ZERO
	var best_d := -INF
	var span := shelf_half_size - Vector2(1.3, 1.1)
	for i in 21:
		for j in 7:
			var p := Vector3(lerpf(-span.x, span.x, i / 20.0), 0, lerpf(-span.y, span.y, j / 6.0))
			var d := INF
			for g in others:
				d = minf(d, Vector2(g.global_position.x - p.x, g.global_position.z - p.z).length())
			# Prefer the front-middle when there's room.
			d -= Vector2(p.x * 0.06, (p.z + span.y) * 0.1).length()
			if d > best_d:
				best_d = d
				best = p
	return best


func _make_ring() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.rings = 48
	torus.ring_segments = 8
	mi.mesh = torus
	mi.scale = Vector3(1, 0.15, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.55, 0.75, 1.0, 0.0)
	mi.material_override = m
	_ring_mat = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## The globe under a screen point (nearest to the camera), or null.
func _globe_at(screen_pos: Vector2) -> GlobeBody:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var best: GlobeBody = null
	var best_d := INF
	for b in globes:
		if b.globe.intersects_ray(from, dir):
			var d := from.distance_to(b.global_position)
			if d < best_d:
				best = b
				best_d = d
	return best


# --- Input --------------------------------------------------------------------------

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
			_carry_to(event.position)
		elif _twisting:
			_twist(event.relative)
		elif _orbiting:
			camera.orbit(event.relative.x * orbit_sensitivity, event.relative.y * orbit_sensitivity)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				if selected:
					shake_globe(selected)
			KEY_I, KEY_TAB:
				_set_mode(Mode.SHELF if _mode == Mode.INSPECT else Mode.INSPECT)
			KEY_V:
				_set_mode(Mode.SHELF if _mode == Mode.INSIDE else Mode.INSIDE)
			KEY_ESCAPE:
				_set_mode(Mode.SHELF)
			KEY_R:
				_set_mode(Mode.SHELF)
				for g in globes:
					g.respawn(g.home)


## Mouse, and single-finger touch (which Godot turns into mouse events).
func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_update_touch_point(event.position)
			elif _touched:
				_touched.touch_active = false
				_touched = null
			if not event.pressed and _prop_drag >= 0:
				_prop_drag = -1
				ui.prop_moved()
				return
			if event.pressed and ui and ui.props_editing and _try_prop_press(event.position):
				return
			if event.double_click and _mode == Mode.SHELF:
				var hit := _globe_at(event.position)
				if hit:
					_release()
					select(hit)
					_set_mode(Mode.INSPECT)
					return
			match _mode:
				Mode.INSPECT:
					_twisting = event.pressed
					return
				Mode.INSIDE:
					_orbiting = event.pressed
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
				_holding.apply_torque_impulse(Vector3.UP * dir * 0.8)
			else:
				camera.zoom(0.9 if dir > 0.0 else 1.0 / 0.9)


func _on_touch(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			if event.double_tap and _mode == Mode.SHELF:
				var hit := _globe_at(event.position)
				if hit:
					_release()
					select(hit)
					_set_mode(Mode.INSPECT)
		else:
			_touches.erase(event.index)
		if _touches.size() >= 2:
			# A second finger turns whatever the first was doing into a gesture.
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
	if mode == _mode or selected == null:
		return
	# Leave the current mode.
	match _mode:
		Mode.INSPECT:
			selected.end_inspect()
		Mode.INSIDE:
			camera.inside = null
			selected.globe.set_inside_view(false)
	_release()
	_twisting = false
	_orbiting = false
	_mode = mode
	match mode:
		Mode.INSPECT:
			selected.begin_inspect()
		Mode.INSIDE:
			camera.inside = selected.globe
			selected.globe.set_inside_view(true)
	if ui:
		ui.set_mode(int(mode))


# --- Carrying and tossing ------------------------------------------------------------

func _try_grab(screen_pos: Vector2) -> bool:
	var body := _globe_at(screen_pos)
	if body == null:
		return false
	select(body)
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var hit = body.globe.raycast_glass(from, dir)
	var point: Vector3
	if hit != null:
		point = body.globe.global_transform * (hit as Vector3)
	else:
		# Grabbed the stand: take the nearest point on the ray to its centre.
		var c := body.global_position + Vector3.UP * body.globe.floor_y * 0.5
		point = from + dir * maxf((c - from).dot(dir), 0.0)
	# Carry in one plane through the grab point: upright and facing the camera
	# when it looks across the shelf (moving up the screen lifts the globe),
	# tipping toward flat the more it looks down (so the pointer slides the
	# globe around the shelf instead of shoving it into the table).
	var back := camera.global_basis.z
	var flat_back := Vector3(back.x, 0.0, back.z).normalized()
	var down := clampf((back.y - 0.35) / 0.5, 0.0, 1.0)
	_grab_plane = Plane(flat_back.slerp(Vector3.UP, down).normalized(), point)
	body.grab(point)
	body.drag_target = point + Vector3.UP * _lift(body)
	_holding = body
	return true


func _lift(body: GlobeBody) -> float:
	return pickup_lift * body.globe.globe_radius


func _carry_to(screen_pos: Vector2) -> void:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var hit = _grab_plane.intersects_ray(from, dir)
	if hit == null:
		return
	var p: Vector3 = hit
	# Held a little off the shelf (never pulled down into it, which just makes
	# the two fight).
	var lift := _lift(_holding)
	p.y += lift
	p.y = clampf(p.y, maxf(carry_height.x, _holding.grab_local.y + lift), maxf(carry_height.y, _holding.grab_local.y + 1.0 + lift))
	p.x = clampf(p.x, -shelf_half_size.x - 3.0, shelf_half_size.x + 3.0)
	p.z = clampf(p.z, -shelf_half_size.y - 3.0, shelf_half_size.y + 3.0)
	_holding.drag_target = p


func _release() -> void:
	if _holding:
		_holding.release()
	_holding = null


# --- Touching the glass / moving props -----------------------------------------

## Tells the globe under the pointer where it's being pressed (plasma arcs and
## creatures react to it).
func _update_touch_point(screen_pos: Vector2) -> void:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var body := _holding if _holding else _globe_at(screen_pos)
	if _touched and (body == null or _touched != body.globe):
		_touched.touch_active = false
		_touched = null
	if body == null:
		return
	var g := body.globe
	var hit = g.raycast_glass(from, dir)
	g.touch_active = hit != null
	if hit != null:
		# Just inside the glass, where things can actually reach.
		var p: Vector3 = hit
		g.touch_point = p + (g.glass_center - p).normalized() * g.globe_radius * 0.06
		_touched = g


## Where a screen point lands on the selected globe's floor, as floor-relative
## (x, z) (1 = floor rim), or null.
func _floor_hit(screen_pos: Vector2):
	var g := selected.globe
	var inv := g.global_transform.affine_inverse()
	var o := inv * camera.project_ray_origin(screen_pos)
	var d := (inv.basis * camera.project_ray_normal(screen_pos)).normalized()
	if absf(d.y) < 1e-4:
		return null
	var plane_y := g.floor_y + g.globe_radius * g.mound_height * 0.5
	var t := (plane_y - o.y) / d.y
	if t < 0.0:
		return null
	var p := o + d * t
	var rel := Vector2(p.x, p.z) / maxf(g.get_floor_radius(), 1e-4)
	return rel if rel.length() < 1.1 else null


## In the editor's Props tab: grab the prop under the pointer, or move the
## selected prop to where the floor was tapped.
func _try_prop_press(screen_pos: Vector2) -> bool:
	var hit = _floor_hit(screen_pos)
	if hit == null:
		return false
	var g := selected.globe
	var fr := g.get_floor_radius()
	var best := -1
	var best_d := INF
	for i in g.props.size():
		var p: Dictionary = g.props[i]
		var at := Vector2(float(p.get("x", 0.0)), float(p.get("z", 0.0)))
		var d: float = at.distance_to(hit) * fr
		var reach := float(PropLibrary.info(String(p.get("type", "")))["radius"]) * float(p.get("scale", 1.0)) * g.globe_radius * 1.3 + g.globe_radius * 0.05
		if d < reach and d < best_d:
			best = i
			best_d = d
	if best >= 0:
		var p: Dictionary = g.props[best]
		_prop_grab = Vector2(float(p.get("x", 0.0)), float(p.get("z", 0.0))) - hit
	else:
		best = ui.get_selected_prop()
		if best < 0:
			return false
		_prop_grab = Vector2.ZERO
		g.move_prop(best, hit.x, hit.y)
	_prop_drag = best
	ui.select_prop(best)
	return true


func _drag_prop(screen_pos: Vector2) -> void:
	var hit = _floor_hit(screen_pos)
	if hit == null:
		return
	var at: Vector2 = hit + _prop_grab
	selected.globe.move_prop(_prop_drag, at.x, at.y)


# --- Inspect mode -------------------------------------------------------------

## Trackball-style: dragging turns the globe about the camera's axes.
func _twist(relative: Vector2) -> void:
	var cam := camera.global_basis
	var k := deg_to_rad(twist_sensitivity)
	var q := Quaternion(cam.y, relative.x * k) * Quaternion(cam.x, relative.y * k)
	selected.target_orientation = (q * selected.target_orientation).normalized()


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
