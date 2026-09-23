class_name GlobeAurora
extends GlobeEffectLayer
## Northern lights: glowing curtains rippling across the top of the globe,
## brightening and swirling when it's shaken.

const KIND := "aurora"
const SETTINGS: Array[String] = ["curtains", "color_low", "color_high", "brightness", "density", "aurora_seed"]
const EDITOR_ROWS := [
	["curtains", "Curtains", 1, 4, 1],
	["color_low", "Lower colour"],
	["color_high", "Upper colour"],
	["brightness", "Brightness", 0.2, 4.0, 0.01],
	["density", "Thickness", 0.1, 1.0, 0.01],
	["aurora_seed", "Arrangement", 0, 99, 1],
]
const SHADER := preload("res://shaders/aurora.gdshader")

@export_range(1, 4, 1) var curtains := 2:
	set(v): curtains = v; _queue_build()
@export var color_low := Color(0.2, 1.0, 0.55):
	set(v): color_low = v; _apply_params()
@export var color_high := Color(0.65, 0.3, 1.0):
	set(v): color_high = v; _apply_params()
@export_range(0.2, 4.0, 0.01) var brightness := 1.6:
	set(v): brightness = v; _apply_params()
@export_range(0.1, 1.0, 0.01) var density := 0.75:
	set(v): density = v; _apply_params()
@export var aurora_seed := 5:
	set(v): aurora_seed = v; _queue_build()


func _shader() -> Shader:
	return SHADER


func _apply_params() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("color_low", color_low)
	_mat.set_shader_parameter("color_high", color_high)
	_mat.set_shader_parameter("brightness", brightness)
	_mat.set_shader_parameter("density", density)


func _build_mesh() -> Mesh:
	var shape := _globe.get_container()
	var gc := _globe.glass_center
	var rng := RandomNumberGenerator.new()
	rng.seed = aurora_seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var floor_top := _globe.floor_y - gc.y
	var y_bot := lerpf(floor_top, shape.y_max, 0.35)
	var y_top := lerpf(floor_top, shape.y_max, 0.92)
	var cols := 40
	var rows := 6
	for c in curtains:
		var a0 := rng.randf() * TAU
		var span := rng.randf_range(1.4, 2.4)
		var wav := rng.randf_range(3.0, 6.0)
		for i in cols:
			for j in rows:
				var quad := []
				for k in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
					var t := float(k[0]) / cols
					var h := float(k[1]) / rows
					var y := lerpf(y_bot, y_top, h)
					var a := a0 + span * t
					var r := shape.radius_at(y) * shape.radius_factor(sin(a), cos(a)) * (0.5 + 0.15 * sin(t * wav + c))
					quad.append([Vector3(sin(a) * r, y, cos(a) * r) + gc, Vector2(t, h)])
				for idx in [0, 1, 2, 0, 2, 3]:
					_v(st, quad[idx][0], quad[idx][1])
	return st.commit()
