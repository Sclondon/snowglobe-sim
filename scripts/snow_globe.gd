@tool
class_name SnowGlobe
extends Node3D
## A procedurally built snow globe: glass (any GlassShape), a stand
## (GlobeBase), a floor, and scenery props (PropLibrary).
##
## Local space: the origin is where the globe rests on the table; the floor
## sits at y = floor_y and the glass's centre at `glass_center`. The generated
## parts live under an unsaved "Generated" child and are rebuilt whenever an
## exported property changes (also in the editor). Anything else you add as a
## child — particle / creature / plasma layers — is kept in the scene and
## moves with the globe.
##
## Movement is driven by target_position / target_orientation. The globe
## follows smoothly, rotating about the glass centre, sways from
## acceleration, and exposes linear_acceleration / angular_velocity so the
## contents can react to being shaken and turned.

signal rebuilt

enum Fill { WATER, AIR }
enum FloorType { SNOW, SAND, GRASS, MOSS, ROCK }

const FILL_NAMES := ["Water", "Air"]
const FLOOR_NAMES := ["Snow", "Sand", "Grass", "Moss", "Rock"]
const FLOOR_COLORS := [Color(0.8, 0.83, 0.88), Color(0.76, 0.66, 0.46), Color(0.3, 0.5, 0.22), Color(0.25, 0.36, 0.2), Color(0.42, 0.41, 0.39)]
const FLOOR_ROUGHNESS := [0.85, 1.0, 0.95, 1.0, 0.9]
const GLASS_SHADER := preload("res://shaders/glass.gdshader")
const GLASS_INSIDE_SHADER := preload("res://shaders/glass_inside.gdshader")
const STAND_SHADER := preload("res://shaders/stand.gdshader")
const MAX_PROPS := 16

@export_group("Glass")
@export_range(0.1, 5.0, 0.01) var globe_radius := 1.0:
	set(v): globe_radius = v; _queue_rebuild()
@export var glass_shape := GlassShape.Kind.SPHERE:
	set(v): glass_shape = v; _queue_rebuild()
@export_range(0.5, 1.8, 0.01) var glass_width := 1.0:
	set(v): glass_width = v; _queue_rebuild()
@export_range(0.5, 2.0, 0.01) var glass_height := 1.0:
	set(v): glass_height = v; _queue_rebuild()
## Sides of the Diamond shape.
@export_range(3, 24) var glass_facets := 8:
	set(v): glass_facets = v; _queue_rebuild()
## How far below the glass's centre the floor sits (0 = centre, 1 = bottom).
@export_range(0.0, 0.9, 0.01) var floor_depth := 0.6:
	set(v): floor_depth = v; _queue_rebuild()
## How thick the glass wall looks: edge tint and bending at the rim.
@export_range(0.0, 1.0, 0.01) var glass_thickness := 0.2:
	set(v): glass_thickness = v; _update_materials()
## Barrel distortion toward the rim (negative pinches instead).
@export_range(-0.5, 1.0, 0.01) var glass_distortion := 0.15:
	set(v): glass_distortion = v; _update_materials()
## How much bigger the contents look through water.
@export_range(1.0, 2.0, 0.01) var magnification := 1.2:
	set(v): magnification = v; _update_materials()
@export var glass_tint := Color(0.93, 0.97, 1.0):
	set(v): glass_tint = v; _update_materials()
@export var glass_edge_tint := Color(0.62, 0.78, 0.9):
	set(v): glass_edge_tint = v; _update_materials()
## What the globe is filled with. Air: things fall fast, no water lens.
@export var fill := Fill.WATER:
	set(v): fill = v; _update_materials()

@export_group("Stand")
@export var base_type := GlobeBase.Kind.PEDESTAL:
	set(v): base_type = v; _queue_rebuild()
@export var base_finish := GlobeBase.Finish.WOOD:
	set(v): base_finish = v; _update_materials()
@export var base_color := Color(0.5, 0.3, 0.17):
	set(v): base_color = v; _update_materials()
@export var base_accent := Color(0.24, 0.12, 0.06):
	set(v): base_accent = v; _update_materials()
@export var trim_color := Color(0.95, 0.75, 0.35):
	set(v): trim_color = v; _update_materials()
@export_range(3, 64) var stand_sides := 8:
	set(v): stand_sides = v; _queue_rebuild()
## Pedestal height as a fraction of the globe radius.
@export_range(0.1, 2.0, 0.01) var stand_height := 0.55:
	set(v): stand_height = v; _queue_rebuild()
## Pedestal bottom radius as a fraction of the globe radius.
@export_range(0.5, 2.0, 0.01) var stand_bottom_radius := 1.05:
	set(v): stand_bottom_radius = v; _queue_rebuild()
@export_range(3, 8) var leg_count := 4:
	set(v): leg_count = v; _queue_rebuild()
## Gap under the glass when on legs, as a fraction of the globe radius.
@export_range(0.05, 1.0, 0.01) var leg_clearance := 0.25:
	set(v): leg_clearance = v; _queue_rebuild()
## Optional texture that replaces the procedural stand surface.
@export var stand_texture: Texture2D:
	set(v): stand_texture = v; _update_materials()

@export_group("Floor")
@export var floor_type := FloorType.SNOW:
	set(v): floor_type = v; _update_materials()
@export var floor_color := Color(0.8, 0.83, 0.88):
	set(v): floor_color = v; _update_materials()
## Height of the central mound as a fraction of the globe radius.
@export_range(0.0, 0.5, 0.01) var mound_height := 0.12:
	set(v): mound_height = v; _queue_rebuild()
@export_range(0.0, 0.1, 0.001) var snow_bumpiness := 0.025:
	set(v): snow_bumpiness = v; _queue_rebuild()
@export var snow_seed := 1:
	set(v): snow_seed = v; _queue_rebuild()

@export_group("Props")
## Scenery: [{type, x, z, rot, scale, color}], x/z as fractions of the floor
## radius (so props stay on the floor when the glass changes shape), rot in
## degrees, color as "#rrggbb". Call props_changed() after editing in place.
@export var props: Array = [{"type": "pine", "x": 0.0, "z": 0.0, "rot": 0.0, "scale": 1.0, "color": "#21603a"}]:
	set(v): props = v; _queue_rebuild()

@export_group("Handling")
## How quickly the globe catches up to target_position.
@export var follow_speed := 14.0
## How quickly the globe catches up to target_orientation.
@export var turn_speed := 16.0
## Sway in radians per unit of acceleration.
@export var sway_amount := 0.012
@export var max_sway := 0.45
@export var sway_stiffness := 60.0
@export var sway_damping := 7.0

## Where the globe should rest when upright.
var target_position := Vector3.ZERO
var target_orientation := Quaternion.IDENTITY
var linear_velocity := Vector3.ZERO
var linear_acceleration := Vector3.ZERO
## World-space angular velocity in radians/second.
var angular_velocity := Vector3.ZERO
## Where a finger / mouse is pressing on the glass (globe-local), for layers
## that react to touch (plasma, creatures). Set by main.gd.
var touch_active := false
var touch_point := Vector3.ZERO

## Local-space centre of the glass.
var glass_center := Vector3.ZERO
## Kept for older code: same as glass_center.
var sphere_center: Vector3:
	get: return glass_center
## Local-space Y of the floor's rim.
var floor_y := 0.0

var _shape: GlassShape
var _generated: Node3D
var _props_root: Node3D
var _prop_nodes: Array[Node3D] = []
var _glass_mat: ShaderMaterial
var _glass_inside_mat: ShaderMaterial
var _glass_node: MeshInstance3D
var _inside_view := false
var _stand_mat: ShaderMaterial
var _trim_mat: ShaderMaterial
var _floor_mat: StandardMaterial3D
var _under_mat: StandardMaterial3D
var _rebuild_queued := false
var _center := Vector3.ZERO
var _orientation := Quaternion.IDENTITY
var _sway := Vector2.ZERO # rotation about world X and world Z
var _sway_velocity := Vector2.ZERO
var _shake_time := -1.0
var _shake_strength := 0.0
var _noise: FastNoiseLite


func _ready() -> void:
	_layout()
	_orientation = basis.get_rotation_quaternion()
	target_orientation = _orientation
	_center = global_position + basis * glass_center
	target_position = global_position
	_rebuild()


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


# --- Queries used by layers, props and input ---------------------------------

## The glass's shape (glass-local coordinates: subtract glass_center).
func get_container() -> GlassShape:
	if _shape == null:
		_layout()
	return _shape


## Radius of the ring where the floor meets the glass.
func get_floor_radius() -> float:
	return get_container().floor_radius


## Local-space height of the floor surface at local (x, z).
func get_floor_height(x: float, z: float) -> float:
	return floor_y + _snow_height_at(x, z)


## Drag multiplier for things moving through the fill.
func get_drag_scale() -> float:
	return 1.0 if fill == Fill.WATER else 0.2


## How much the fill swirls along when the globe turns.
func get_swirl_scale() -> float:
	return 1.0 if fill == Fill.WATER else 0.15


## Props as obstacles: Vector4(x, z, radius, top_y) in globe-local space.
func get_obstacles() -> Array[Vector4]:
	var out: Array[Vector4] = []
	var fr := get_floor_radius()
	for p in props:
		var inf := PropLibrary.info(String(p.get("type", "pine")))
		var s := float(p.get("scale", 1.0)) * globe_radius
		var x := float(p.get("x", 0.0)) * fr
		var z := float(p.get("z", 0.0)) * fr
		out.append(Vector4(x, z, float(inf["radius"]) * s, get_floor_height(x, z) + float(inf["height"]) * s))
	return out


## Switches the glass to the version seen from inside (for the inside camera).
func set_inside_view(on: bool) -> void:
	_inside_view = on
	if _glass_node:
		_glass_node.material_override = _glass_inside_mat if on else _glass_mat


## Moves the globe so the glass's centre ends up at a world point.
func set_target_center(world_center: Vector3) -> void:
	target_position = world_center - Vector3.UP * glass_center.y


## Gives the globe a quick back-and-forth jiggle (a real physical shake when
## it sits in a GlobeBody).
func shake(strength := 1.0) -> void:
	if get_parent() is GlobeBody:
		get_parent().shake(strength)
		return
	_shake_time = 0.0
	_shake_strength = strength


## Returns true if a world-space ray hits the glass or the stand.
func intersects_ray(from: Vector3, dir: Vector3) -> bool:
	var inv := global_transform.affine_inverse()
	var o := inv * from
	var d := (inv.basis * dir).normalized()
	var shape := get_container()
	var extent := Vector3(shape.max_radius, maxf(-shape.y_min, shape.y_max), shape.max_radius).length()
	if _ray_hits_sphere(o, d, glass_center, extent * 0.9):
		return true
	var base_top := glass_center.y + shape.floor_y
	return base_type != GlobeBase.Kind.NONE and _ray_hits_sphere(o, d, Vector3(0, base_top * 0.5, 0), maxf(globe_radius * stand_bottom_radius, base_top * 0.6))


## World-space ray to the point where it first enters the glass
## (globe-local), or null.
func raycast_glass(from: Vector3, dir: Vector3) -> Variant:
	var inv := global_transform.affine_inverse()
	var hit = get_container().raycast(inv * from - glass_center, (inv.basis * dir).normalized())
	return null if hit == null else hit + glass_center


static func _ray_hits_sphere(o: Vector3, d: Vector3, c: Vector3, r: float) -> bool:
	var oc := o - c
	var b := oc.dot(d)
	var disc := b * b - (oc.length_squared() - r * r)
	return disc >= 0.0 and (-b + sqrt(disc)) >= 0.0


# --- Props ------------------------------------------------------------------------

## Rebuilds just the props (after editing `props` in place).
func props_changed() -> void:
	if _props_root == null:
		return
	for c in _props_root.get_children():
		c.queue_free()
	_prop_nodes.clear()
	var fr := get_floor_radius()
	for i in mini(props.size(), MAX_PROPS):
		var p: Dictionary = props[i]
		var type := String(p.get("type", "pine"))
		var col := String(p.get("color", PropLibrary.info(type)["color"]))
		var node := PropLibrary.build(type, Color.html(col) if Color.html_is_valid(col) else Color.WHITE)
		_props_root.add_child(node)
		_prop_nodes.append(node)
		_place_prop(i, fr)


## Moves prop `index` to floor-relative (x, z) without rebuilding it.
func move_prop(index: int, x: float, z: float) -> void:
	if index < 0 or index >= props.size():
		return
	var v := Vector2(x, z)
	v = v.limit_length(0.92 * get_container().radius_factor(v.x, v.y))
	props[index]["x"] = v.x
	props[index]["z"] = v.y
	_place_prop(index, get_floor_radius())


func _place_prop(i: int, fr: float) -> void:
	if i >= _prop_nodes.size():
		return
	var p: Dictionary = props[i]
	var x := float(p.get("x", 0.0)) * fr
	var z := float(p.get("z", 0.0)) * fr
	var node := _prop_nodes[i]
	node.position = Vector3(x, get_floor_height(x, z) - 0.005 * globe_radius, z)
	node.rotation.y = deg_to_rad(float(p.get("rot", 0.0)))
	node.scale = Vector3.ONE * float(p.get("scale", 1.0)) * globe_radius


# --- Motion ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Inside a GlobeBody, physics moves the globe and fills in the motion data.
	if Engine.is_editor_hint() or delta <= 0.0 or get_parent() is GlobeBody:
		return
	var goal_center := target_position + Vector3.UP * glass_center.y
	if _shake_time >= 0.0:
		# A decaying side-to-side wobble with a little bounce.
		_shake_time += delta
		var env := exp(-_shake_time * 4.0) * _shake_strength
		goal_center += Vector3(sin(_shake_time * 38.0) * 0.18, absf(sin(_shake_time * 19.0)) * 0.12, sin(_shake_time * 29.0) * 0.06) * env
		if env < 0.01:
			_shake_time = -1.0

	var prev_center := _center
	var prev_vel := linear_velocity
	_center = _center.lerp(goal_center, 1.0 - exp(-follow_speed * delta))
	linear_velocity = (_center - prev_center) / delta
	linear_acceleration = (linear_velocity - prev_vel) / delta

	# Pendulum-ish sway: the bottom lags behind acceleration.
	var goal := Vector2(linear_acceleration.z, -linear_acceleration.x) * sway_amount
	goal = goal.limit_length(max_sway)
	_sway_velocity += ((goal - _sway) * sway_stiffness - _sway_velocity * sway_damping) * delta
	_sway += _sway_velocity * delta

	var prev_rot := basis.get_rotation_quaternion()
	_orientation = _orientation.slerp(target_orientation, 1.0 - exp(-turn_speed * delta))
	var rot := Quaternion.from_euler(Vector3(_sway.x, 0.0, _sway.y)) * _orientation
	var b := Basis(rot)
	transform = Transform3D(b, _center - b * glass_center)

	var dq := rot * prev_rot.inverse()
	if dq.w < 0.0:
		dq = -dq
	var angle := dq.get_angle()
	angular_velocity = dq.get_axis() * (angle / delta) if angle > 1e-6 else Vector3.ZERO


# --- Construction ---------------------------------------------------------------

## Works out the shape and where the glass sits on its stand.
func _layout() -> void:
	_shape = GlassShape.create(glass_shape, globe_radius, glass_width, glass_height, glass_facets, floor_depth)
	var cy: float
	match base_type:
		GlobeBase.Kind.PEDESTAL:
			cy = globe_radius * stand_height - _shape.floor_y
		GlobeBase.Kind.LEGS:
			cy = globe_radius * leg_clearance - _shape.y_min
		_:
			cy = -_shape.y_min
	glass_center = Vector3(0, cy, 0)
	floor_y = cy + _shape.floor_y


func _rebuild() -> void:
	_rebuild_queued = false
	_layout()
	if _generated:
		_generated.queue_free()

	# Built nodes have no owner, so they're regenerated on load rather than
	# saved into the scene.
	_generated = Node3D.new()
	_generated.name = "Generated"
	add_child(_generated)
	move_child(_generated, 0)
	if _glass_mat == null:
		_make_materials()
	_update_materials()

	var fr := _shape.floor_radius
	match base_type:
		GlobeBase.Kind.PEDESTAL:
			var h := globe_radius * stand_height
			# Wide enough to hide any glass that bulges out below the floor.
			var top := maxf(fr, _shape.widest_below(_shape.floor_y))
			_generated.add_child(GlobeBase.build_pedestal(stand_sides, h, globe_radius * stand_bottom_radius, top * 1.06, _stand_mat))
		GlobeBase.Kind.LEGS:
			_generated.add_child(GlobeBase.build_legs(leg_count, floor_y, fr, globe_radius, _stand_mat, _trim_mat))

	var under := MeshInstance3D.new()
	under.name = "UnderFloor"
	under.mesh = _shape.build_lower_fill()
	under.material_override = _under_mat
	under.position = glass_center
	_generated.add_child(under)

	var floor_mi := MeshInstance3D.new()
	floor_mi.name = "Floor"
	floor_mi.mesh = _build_floor_mesh()
	floor_mi.material_override = _floor_mat
	floor_mi.position.y = floor_y
	_generated.add_child(floor_mi)

	_props_root = Node3D.new()
	_props_root.name = "Props"
	_generated.add_child(_props_root)
	props_changed()

	var glass := MeshInstance3D.new()
	glass.name = "Glass"
	glass.mesh = _shape.build_mesh()
	glass.material_override = _glass_inside_mat if _inside_view else _glass_mat
	_glass_node = glass
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.position = glass_center
	_generated.add_child(glass)
	rebuilt.emit()


func _make_materials() -> void:
	_glass_mat = ShaderMaterial.new()
	_glass_mat.shader = GLASS_SHADER
	_glass_inside_mat = ShaderMaterial.new()
	_glass_inside_mat.shader = GLASS_INSIDE_SHADER
	_stand_mat = ShaderMaterial.new()
	_stand_mat.shader = STAND_SHADER
	_trim_mat = ShaderMaterial.new()
	_trim_mat.shader = STAND_SHADER
	_floor_mat = StandardMaterial3D.new()
	_under_mat = StandardMaterial3D.new()
	_under_mat.roughness = 1.0


## Pushes colour/look properties into the existing materials. Cheap, so the
## setters for these call it directly instead of rebuilding the meshes.
func _update_materials() -> void:
	if _glass_mat == null:
		return
	var water := fill == Fill.WATER
	_glass_mat.set_shader_parameter("tint", glass_tint)
	_glass_mat.set_shader_parameter("edge_tint", glass_edge_tint)
	_glass_mat.set_shader_parameter("magnification", magnification if water else lerpf(1.0, magnification, 0.15))
	_glass_mat.set_shader_parameter("rim_bend", glass_distortion)
	_glass_mat.set_shader_parameter("thickness", glass_thickness)
	_glass_mat.set_shader_parameter("glass_size", globe_radius)
	_glass_mat.set_shader_parameter("edge_highlight", 0.6 if get_container().flat_shaded else 0.0)
	# From inside: same glass, but no water lens.
	for p in ["tint", "edge_tint", "thickness", "glass_size", "edge_highlight"]:
		_glass_inside_mat.set_shader_parameter(p, _glass_mat.get_shader_parameter(p))
	_glass_inside_mat.set_shader_parameter("magnification", 1.0)
	_glass_inside_mat.set_shader_parameter("rim_bend", 0.0)

	for m in [_stand_mat, _trim_mat]:
		m.set_shader_parameter("material_mode", int(base_finish))
		m.set_shader_parameter("primary_color", base_color)
		m.set_shader_parameter("secondary_color", base_accent)
		m.set_shader_parameter("trim_color", trim_color)
		m.set_shader_parameter("use_texture", stand_texture != null)
		m.set_shader_parameter("albedo_texture", stand_texture)
	var trim := GlobeBase.trim_range(globe_radius * stand_height)
	_stand_mat.set_shader_parameter("trim_start", trim.x if base_type == GlobeBase.Kind.PEDESTAL else -1.0)
	_stand_mat.set_shader_parameter("trim_end", trim.y if base_type == GlobeBase.Kind.PEDESTAL else -1.0)
	_trim_mat.set_shader_parameter("trim_start", -1000.0)
	_trim_mat.set_shader_parameter("trim_end", 1000.0)

	var ft := clampi(floor_type, 0, FLOOR_NAMES.size() - 1)
	_floor_mat.albedo_color = floor_color
	_floor_mat.roughness = FLOOR_ROUGHNESS[ft]
	_floor_mat.rim_enabled = ft == FloorType.SNOW
	_floor_mat.rim = 0.2
	_floor_mat.rim_tint = 0.3
	_under_mat.albedo_color = floor_color.darkened(0.25)


## Floor height above floor_y: a smooth mound plus noise bumps.
func _snow_height_at(x: float, z: float) -> float:
	var rf := get_floor_radius()
	var t := clampf(Vector2(x, z).length() / maxf(rf, 1e-4), 0.0, 1.0)
	var mound := globe_radius * mound_height * (1.0 - t * t)
	if _noise == null or _noise.seed != snow_seed:
		_noise = FastNoiseLite.new()
		_noise.seed = snow_seed
		_noise.frequency = 1.6
	# Fade bumps out at the rim so the floor meets the glass cleanly.
	var bumps := _noise.get_noise_2d(x / globe_radius, z / globe_radius) * snow_bumpiness * globe_radius
	return mound + bumps * (1.0 - t)


func _build_floor_mesh() -> ArrayMesh:
	var rf := get_floor_radius() * 0.995
	var rings := 24
	var segments := 72
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = [Vector3(0, _snow_height_at(0, 0), 0)]
	for ri in range(1, rings + 1):
		var rr := rf * float(ri) / rings
		for si in segments:
			var a := TAU * si / segments
			# Flat-sided glass: pull the rim in to the walls.
			var k := get_container().radius_factor(sin(a), cos(a))
			var x := sin(a) * rr * k
			var z := cos(a) * rr * k
			pts.append(Vector3(x, _snow_height_at(x, z), z))
	for p in pts:
		st.set_uv(Vector2(p.x, p.z) / maxf(rf * 2.0, 1e-4) + Vector2(0.5, 0.5))
		st.add_vertex(p)
	# Indices: centre fan, then ring strips, wound clockwise seen from above
	# so the surface faces up.
	for si in segments:
		var s1 := (si + 1) % segments
		st.add_index(0); st.add_index(1 + s1); st.add_index(1 + si)
	for ri in range(1, rings):
		var inner := 1 + (ri - 1) * segments
		var outer := 1 + ri * segments
		for si in segments:
			var s1 := (si + 1) % segments
			st.add_index(inner + si); st.add_index(outer + s1); st.add_index(outer + si)
			st.add_index(inner + si); st.add_index(inner + s1); st.add_index(outer + s1)
	st.generate_normals()
	return st.commit()
