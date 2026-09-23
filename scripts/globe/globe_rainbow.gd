class_name GlobeRainbow
extends GlobeEffectLayer
## A rainbow arching over the floor, slowly fading in and out and shimmering
## when the globe is shaken.

const KIND := "rainbow"
const SETTINGS: Array[String] = ["arc_size", "band_width", "opacity", "brightness", "turn", "fade_cycle"]
const EDITOR_ROWS := [
	["arc_size", "Size", 0.3, 1.0, 0.01],
	["band_width", "Width", 0.05, 0.4, 0.01],
	["opacity", "Opacity", 0.1, 1.0, 0.01],
	["brightness", "Brightness", 0.2, 3.0, 0.01],
	["turn", "Facing", 0.0, 360.0, 1.0],
	["fade_cycle", "Fades in and out"],
]
const SHADER := preload("res://shaders/rainbow.gdshader")

## Arc radius as a fraction of the room above the floor.
@export_range(0.3, 1.0, 0.01) var arc_size := 0.75:
	set(v): arc_size = v; _queue_build()
## Band width as a fraction of the globe radius.
@export_range(0.05, 0.4, 0.01) var band_width := 0.16:
	set(v): band_width = v; _queue_build()
@export_range(0.1, 1.0, 0.01) var opacity := 0.9:
	set(v): opacity = v; _apply_params()
@export_range(0.2, 3.0, 0.01) var brightness := 1.2:
	set(v): brightness = v; _apply_params()
## Which way the arc faces, in degrees.
@export_range(0.0, 360.0, 1.0) var turn := 0.0:
	set(v): turn = v; _queue_build()
@export var fade_cycle := true:
	set(v): fade_cycle = v; _apply_params()


func _shader() -> Shader:
	return SHADER


func _apply_params() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("opacity", opacity)
	_mat.set_shader_parameter("brightness", brightness)
	_mat.set_shader_parameter("fade_cycle", fade_cycle)


func _build_mesh() -> Mesh:
	var shape := _globe.get_container()
	var gc := _globe.glass_center
	var R := _globe.globe_radius
	var base_y := _globe.floor_y + R * 0.03
	# Fit inside: no wider than the floor, no taller than the room above it.
	var room := gc.y + shape.y_max - base_y
	var r_out := minf(shape.floor_radius * 0.9, room * 0.85) * arc_size
	var r_in := maxf(r_out - R * band_width, r_out * 0.3)
	var rot := Basis(Vector3.UP, deg_to_rad(turn))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 48
	for i in n:
		var quad := []
		for k in [[i, 0], [i + 1, 0], [i + 1, 1], [i, 1]]:
			var t := float(k[0]) / n
			var a := PI * t
			var r := lerpf(r_in, r_out, float(k[1]))
			var p := rot * Vector3(cos(a) * r, sin(a) * r, 0) + Vector3(0, base_y, 0)
			quad.append([p, Vector2(t, float(k[1]))])
		for idx in [0, 1, 2, 0, 2, 3]:
			_v(st, quad[idx][0], quad[idx][1])
	return st.commit()
