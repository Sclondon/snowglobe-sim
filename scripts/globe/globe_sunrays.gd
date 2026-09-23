class_name GlobeSunrays
extends GlobeEffectLayer
## Shafts of light slanting down from the top of the globe to the floor.

const KIND := "sunrays"
const SETTINGS: Array[String] = ["rays", "color", "intensity", "brightness", "slant", "ray_seed"]
const EDITOR_ROWS := [
	["rays", "Rays", 1, 10, 1],
	["color", "Colour"],
	["intensity", "Strength", 0.1, 1.0, 0.01],
	["brightness", "Brightness", 0.2, 3.0, 0.01],
	["slant", "Slant", 0.0, 1.0, 0.01],
	["ray_seed", "Arrangement", 0, 99, 1],
]
const SHADER := preload("res://shaders/sunrays.gdshader")

@export_range(1, 10, 1) var rays := 5:
	set(v): rays = v; _queue_build()
@export var color := Color(1.0, 0.9, 0.6):
	set(v): color = v; _apply_params()
@export_range(0.1, 1.0, 0.01) var intensity := 0.55:
	set(v): intensity = v; _apply_params()
@export_range(0.2, 3.0, 0.01) var brightness := 1.3:
	set(v): brightness = v; _apply_params()
@export_range(0.0, 1.0, 0.01) var slant := 0.35:
	set(v): slant = v; _queue_build()
@export var ray_seed := 2:
	set(v): ray_seed = v; _queue_build()


func _shader() -> Shader:
	return SHADER


func _apply_params() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("color", color)
	_mat.set_shader_parameter("intensity", intensity)
	_mat.set_shader_parameter("brightness", brightness)


func _build_mesh() -> Mesh:
	var shape := _globe.get_container()
	var gc := _globe.glass_center
	var R := _globe.globe_radius
	var rng := RandomNumberGenerator.new()
	rng.seed = ray_seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y_top := gc.y + shape.y_max * 0.85
	var lean := Vector3(1, 0, 0.3).normalized() * slant
	for k in rays:
		var a := rng.randf() * TAU
		var top_r := shape.radius_at(y_top - gc.y) * 0.5 * sqrt(rng.randf())
		var top := Vector3(sin(a) * top_r, y_top, cos(a) * top_r)
		var drop := y_top - _globe.floor_y
		var bottom := top + lean * drop + Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1)) * R
		# Keep the foot inside the glass.
		var fr := shape.floor_radius * 0.85 * shape.radius_factor(bottom.x, bottom.z)
		var flat := Vector2(bottom.x, bottom.z).limit_length(fr)
		bottom = Vector3(flat.x, _globe.get_floor_height(flat.x, flat.y), flat.y)
		var w0 := R * rng.randf_range(0.03, 0.05)
		var w1 := R * rng.randf_range(0.1, 0.18)
		# Two crossed quads so it looks like a shaft from any side.
		for side in [Vector3.RIGHT, Vector3.BACK]:
			var s: Vector3 = side
			var q := [top - s * w0, top + s * w0, bottom + s * w1, bottom - s * w1]
			var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			for idx in [0, 1, 2, 0, 2, 3]:
				_v(st, q[idx], uv[idx])
	return st.commit()
