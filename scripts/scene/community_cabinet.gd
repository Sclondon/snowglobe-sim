class_name CommunityCabinet
extends Node3D
## The community shelf: a tall antique display cabinet holding everyone's
## globes, three tiers high and as many columns wide as it needs. Swipe to
## browse, pinch / wheel to zoom, tap a globe to bring it forward (turn it,
## shake it, read its plaque), tap outside or press back to return it.
##
## Globes here are view-only and have no physics. To keep dozens of them
## smooth, only the one being viewed runs at full detail; the rest on screen
## run LITE and those off screen sleep (see SnowGlobe.Detail).

signal viewing_changed(globe: SnowGlobe)

@export var tiers := 3
@export var slot_width := 2.5
@export var tier_height := 3.0
@export var depth := 2.3
## Globes are shown at most this big in the cabinet (they keep their true
## size in their own data).
@export var display_max_radius := 0.85
## Globes built per frame while filling the cabinet (spreads the work out).
@export var spawn_per_frame := 2

const PLINTH := 0.45
const BOARD := 0.12
const TAP_SLOP := 14.0

var camera: OrbitCamera
var globes: Array[SnowGlobe] = []
var viewing: SnowGlobe

var _columns := 0
var _width := 0.0
var _pending: Array = []
var _slots: Array[Vector3] = []
var _frame: Node3D
var _press_pos := Vector2.ZERO
var _pressed := false
var _dragging := false
var _wood: ShaderMaterial
var _velvet: ShaderMaterial


func _ready() -> void:
	_wood = ShaderMaterial.new()
	_wood.shader = preload("res://shaders/stand.gdshader")
	_wood.set_shader_parameter("primary_color", Color(0.3, 0.17, 0.09))
	_wood.set_shader_parameter("secondary_color", Color(0.12, 0.06, 0.03))
	_wood.set_shader_parameter("ring_frequency", 9.0)
	_wood.set_shader_parameter("grain_warp", 1.2)
	_wood.set_shader_parameter("wood_roughness", 0.5)
	_wood.set_shader_parameter("use_texture", false)
	_velvet = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = Tablecloth.SHADER_CODE
	_velvet.shader = sh
	_velvet.set_shader_parameter("pattern", int(Tablecloth.Pattern.DAMASK))
	_velvet.set_shader_parameter("color_a", Color(0.17, 0.08, 0.2))
	_velvet.set_shader_parameter("color_b", Color(0.29, 0.16, 0.3))
	_velvet.set_shader_parameter("trim_color", Color(0.85, 0.66, 0.3))
	_velvet.set_shader_parameter("pattern_scale", 1.2)


## Fills the cabinet with these globes (preset dictionaries).
func show_list(list: Array) -> void:
	for g in globes:
		g.queue_free()
	globes.clear()
	viewing = null
	_slots.clear()
	_columns = maxi(4, ceili(float(list.size()) / tiers))
	_width = _columns * slot_width + 0.6
	_build_frame()
	# Column by column, middle tier first, so a short list fills eye level.
	var order := [1, 0, 2] if tiers == 3 else range(tiers)
	for i in list.size():
		var col := i / tiers
		var tier: int = order[i % tiers]
		_slots.append(Vector3(-_width * 0.5 + 0.3 + (col + 0.5) * slot_width, _tier_top(tier), 0.1))
	_pending = list.duplicate()


## Where the camera should look when the cabinet opens.
func home_focus() -> Vector3:
	# The first columns (they fill first), middle tier.
	return Vector3(-_width * 0.5 + 0.3 + slot_width * 1.5, _tier_top(1) + tier_height * 0.4, 0.0)


func _tier_top(tier: int) -> float:
	return PLINTH + BOARD + tier * tier_height


func _box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	_frame.add_child(mi)


func _build_frame() -> void:
	if _frame:
		_frame.queue_free()
	_frame = Node3D.new()
	add_child(_frame)
	var h := PLINTH + tiers * tier_height + BOARD
	var back_z := -depth * 0.5
	# Plinth, boards (one per tier plus the roof), back, sides and crown.
	_box(Vector3(_width + 0.3, PLINTH, depth + 0.2), Vector3(0, PLINTH * 0.5, 0), _wood)
	for k in tiers + 1:
		var y := PLINTH + k * tier_height + BOARD * 0.5
		_box(Vector3(_width, BOARD, depth), Vector3(0, y, 0), _wood)
		if k < tiers:
			_runner(y + BOARD * 0.5)
	_box(Vector3(_width, h, 0.1), Vector3(0, h * 0.5, back_z - 0.05), _wood)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.18, h, depth + 0.1), Vector3(side * (_width * 0.5 + 0.09), h * 0.5, 0), _wood)
	_box(Vector3(_width + 0.5, 0.25, depth + 0.35), Vector3(0, h + 0.125, 0.05), _wood)
	# Slim uprights between every four columns.
	for c in range(4, _columns, 4):
		var x := -_width * 0.5 + 0.3 + c * slot_width
		_box(Vector3(0.1, h - PLINTH, 0.12), Vector3(x, PLINTH + (h - PLINTH) * 0.5, depth * 0.5 - 0.06), _wood)


## A velvet runner along a tier, gold-trimmed at the front edge.
func _runner(y: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := _width * 0.5 - 0.05
	var z0 := -depth * 0.5 + 0.1
	var z1 := depth * 0.5 + 0.02
	var corners := [Vector3(-hx, y + 0.004, z0), Vector3(hx, y + 0.004, z0), Vector3(hx, y + 0.004, z1), Vector3(-hx, y + 0.004, z1)]
	for i in [0, 1, 2, 0, 2, 3]:
		var c: Vector3 = corners[i]
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(c.x, c.z))
		# Distance from the front edge drives the trim and fringe.
		st.set_uv2(Vector2(z1 - c.z, c.x))
		st.add_vertex(c)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _velvet
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_frame.add_child(mi)


func _process(delta: float) -> void:
	if not visible:
		return
	# Build a few waiting globes per frame.
	for k in spawn_per_frame:
		if _pending.is_empty():
			break
		_spawn(_pending.pop_front())
	if camera == null:
		return
	# Detail: the viewed globe gets everything, visible ones LITE, the rest sleep.
	for g in globes:
		if g == viewing:
			g.detail = SnowGlobe.Detail.FULL
		elif camera.is_position_in_frustum(g.global_transform * g.glass_center):
			g.detail = SnowGlobe.Detail.LITE
		else:
			g.detail = SnowGlobe.Detail.ASLEEP
	if viewing:
		var vp := get_viewport().get_visible_rect().size
		var rect := camera.view_rect
		# Close enough that the globe (with its stand) fills about half the view.
		var extent := viewing.globe_radius * 1.8
		var d := clampf(extent / (tan(deg_to_rad(camera.fov * 0.5)) * 0.5), 1.0, camera.global_position.distance_to(camera.focus) * 0.8)
		viewing.set_target_center(camera.project_position(rect.get_center() * vp, d))


func _spawn(data: Dictionary) -> void:
	var i := globes.size()
	var d := data.duplicate(true)
	var g: Dictionary = d.get("globe", {})
	g["globe_radius"] = minf(float(g.get("globe_radius", 1.0)), display_max_radius)
	d["globe"] = g
	var globe := SnowGlobe.new()
	globe.name = "Community%d" % i
	# The cabinet sits at the origin, so local = world; place it before it
	# enters the tree (it starts gliding from wherever it is then).
	globe.position = _slots[i]
	add_child(globe)
	globe.target_position = _slots[i]
	GlobePreset.apply(globe, d)
	globe.detail = SnowGlobe.Detail.LITE
	globes.append(globe)


# --- Input (called by main.gd while the community view is open) --------------------

func pointer_down(pos: Vector2) -> void:
	_pressed = true
	_dragging = false
	_press_pos = pos


func pointer_move(pos: Vector2, relative: Vector2) -> void:
	if not _pressed:
		return
	if not _dragging and pos.distance_to(_press_pos) > TAP_SLOP:
		_dragging = true
	if not _dragging:
		return
	if viewing:
		# Turn the viewed globe.
		var q := Quaternion(Vector3.UP, relative.x * 0.01) * Quaternion(camera.global_basis.x, relative.y * 0.01)
		viewing.target_orientation = (q * viewing.target_orientation).normalized()
	else:
		pan(relative)


func pointer_up(pos: Vector2) -> void:
	if _pressed and not _dragging:
		_tap(pos)
	_pressed = false
	_dragging = false


## Slides the view along the cabinet (screen pixels).
func pan(relative: Vector2) -> void:
	var vp := get_viewport().get_visible_rect().size
	var world_per_px := 2.0 * camera.global_position.distance_to(camera.focus) * tan(deg_to_rad(camera.fov * 0.5)) / maxf(vp.y, 1.0)
	var f := camera.focus + Vector3(-relative.x, relative.y, 0) * world_per_px
	f.x = clampf(f.x, -_width * 0.5 + 1.0, _width * 0.5 - 1.0)
	f.y = clampf(f.y, _tier_top(0) + 0.8, _tier_top(tiers - 1) + tier_height * 0.6)
	camera.focus = f


func _tap(pos: Vector2) -> void:
	var hit := _globe_at(pos)
	if hit and hit == viewing:
		viewing.shake()
	elif hit:
		view(hit)
	elif viewing:
		view(null)


func _globe_at(pos: Vector2) -> SnowGlobe:
	var from := camera.project_ray_origin(pos)
	var dir := camera.project_ray_normal(pos)
	var best: SnowGlobe = null
	var best_d := INF
	for g in globes:
		if g.intersects_ray(from, dir):
			var d := from.distance_to(g.global_position)
			if d < best_d:
				best = g
				best_d = d
	return best


## Brings a globe forward to look at (null puts the current one back).
func view(g: SnowGlobe) -> void:
	if viewing and viewing != g:
		var i := globes.find(viewing)
		viewing.target_position = _slots[i]
		viewing.target_orientation = Quaternion.IDENTITY
	viewing = g
	if g:
		# Face it toward the camera to start with.
		g.target_orientation = Quaternion(Vector3.UP, camera.global_rotation.y)
	viewing_changed.emit(g)


## Shakes the viewed globe, or every globe in sight.
func shake() -> void:
	if viewing:
		viewing.shake()
		return
	for g in globes:
		if g.detail != SnowGlobe.Detail.ASLEEP:
			g.shake(0.8)
