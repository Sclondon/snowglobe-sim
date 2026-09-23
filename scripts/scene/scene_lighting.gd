class_name SceneLighting
extends Node3D
## Room lighting: the overhead spotlight (gently breathing in size) and/or a
## warm, flickering glow from an off-screen fireplace to one side.

enum Mode { SPOTLIGHT, FIREPLACE, BOTH }
const MODE_NAMES := ["Spotlight", "Fireplace", "Both"]

@export var mode := Mode.SPOTLIGHT:
	set(v): mode = v; _apply_mode()
@export var spot_light: SpotLight3D
@export var environment: WorldEnvironment
## How much the spotlight's cone swells and shrinks (fraction).
@export_range(0.0, 0.1, 0.005) var spot_breathing := 0.02
@export var breathing_period := 10.0
@export var fire_color := Color(1.0, 0.55, 0.22)
@export var fire_energy := 3.2
@export var fire_position := Vector3(-11.0, 1.0, 3.0)

var _fire: OmniLight3D
var _fire_fill: OmniLight3D
var _spot_angle := 30.0
var _spot_energy := 14.0
var _time := 0.0
var _noise := FastNoiseLite.new()
var _ambient_base := Color.BLACK


func _ready() -> void:
	if spot_light:
		_spot_angle = spot_light.spot_angle
		_spot_energy = spot_light.light_energy
	if environment and environment.environment:
		_ambient_base = environment.environment.ambient_light_color
	_noise.frequency = 3.0
	_fire = OmniLight3D.new()
	_fire.name = "Fireplace"
	_fire.light_color = fire_color
	_fire.omni_range = 22.0
	_fire.omni_attenuation = 1.2
	_fire.shadow_enabled = true
	_fire.shadow_bias = 0.1
	add_child(_fire)
	# A weaker, wider bounce so the far side isn't pitch black.
	_fire_fill = OmniLight3D.new()
	_fire_fill.light_color = fire_color.lerp(Color.WHITE, 0.3)
	_fire_fill.omni_range = 30.0
	_fire_fill.shadow_enabled = false
	add_child(_fire_fill)
	_apply_mode()


func _apply_mode() -> void:
	if _fire == null:
		return
	var fire := mode != Mode.SPOTLIGHT
	_fire.visible = fire
	_fire_fill.visible = fire
	if spot_light:
		spot_light.visible = mode != Mode.FIREPLACE
	if environment and environment.environment:
		var env := environment.environment
		env.ambient_light_color = _ambient_base.lerp(Color(0.5, 0.32, 0.2), 0.5 if fire else 0.0)


func _process(delta: float) -> void:
	_time += delta
	if spot_light and spot_light.visible:
		var breathe := sin(_time * TAU / breathing_period)
		spot_light.spot_angle = _spot_angle * (1.0 + spot_breathing * breathe)
		spot_light.light_energy = _spot_energy * (1.0 + spot_breathing * 0.6 * breathe)
	if _fire.visible:
		# Layered noise: slow swells plus quick flicker, and a slight wander.
		var slow := _noise.get_noise_1d(_time * 0.6)
		var fast := _noise.get_noise_1d(_time * 7.0 + 100.0)
		var e := fire_energy * (1.0 + slow * 0.25 + fast * 0.18)
		_fire.light_energy = maxf(e, 0.2)
		_fire.position = fire_position + Vector3(_noise.get_noise_1d(_time * 2.0 + 50.0), _noise.get_noise_1d(_time * 2.5 + 70.0), 0.0) * 0.15
		_fire_fill.light_energy = maxf(e * 0.2, 0.05)
		_fire_fill.position = fire_position + Vector3(2.0, 3.0, 2.0)
