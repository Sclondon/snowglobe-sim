class_name GlobeHeat
extends Node3D
## Heat waves: the view through the shell shimmers as if the air inside were
## baking (more when shaken), with an optional warm glow from the floor.

const KIND := "heat"
const SETTINGS: Array[String] = ["strength", "warm_glow", "glow_color"]
const EDITOR_ROWS := [
	["strength", "Shimmer", 0.1, 3.0, 0.01],
	["warm_glow", "Warm glow from below"],
	["glow_color", "Glow colour"],
]

@export_range(0.1, 3.0, 0.01) var strength := 1.0
@export var warm_glow := true:
	set(v):
		warm_glow = v
		if _light:
			_light.visible = v
@export var glow_color := Color(1.0, 0.55, 0.25):
	set(v):
		glow_color = v
		if _light:
			_light.light_color = v

var _globe: SnowGlobe
var _light: OmniLight3D
var _time := 0.0


func _init() -> void:
	add_to_group(&"globe_layer")


func _ready() -> void:
	var n := get_parent()
	while n and not (n is SnowGlobe):
		n = n.get_parent()
	_globe = n as SnowGlobe
	if _globe == null:
		push_warning("GlobeHeat must be inside a SnowGlobe.")
		return
	_light = OmniLight3D.new()
	_light.light_color = glow_color
	_light.visible = warm_glow
	_light.shadow_enabled = false
	add_child(_light)


func _exit_tree() -> void:
	if _globe:
		_globe.set_heat(0.0)


func _process(delta: float) -> void:
	if _globe == null:
		return
	_time += delta
	_globe.set_heat(strength * (1.0 + _globe.agitation * 1.5))
	if _light.visible:
		var R := _globe.globe_radius
		_light.position = Vector3(0, _globe.floor_y + R * 0.15, 0)
		_light.omni_range = R * 1.6
		_light.light_energy = 1.2 + 0.25 * sin(_time * 3.1) * sin(_time * 1.7)
