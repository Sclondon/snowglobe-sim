class_name SceneSettings
extends Node
## Room-level options (lighting, tablecloth, ambient dust and fog), edited in
## the editor's Scene tab and remembered with the session.

## Stored in the session.
const SETTINGS: Array[String] = ["lighting", "tablecloth", "cloth_pattern", "cloth_color", "cloth_color_2", "dust", "fog", "spot_breathing"]
## Sliders / colours / toggles for the editor (dropdowns are added separately).
const EDITOR_ROWS := [
	["spot_breathing", "Spotlight breathing", 0.0, 0.3, 0.01],
	["tablecloth", "Tablecloth"],
	["cloth_color", "Cloth colour"],
	["cloth_color_2", "Cloth second colour"],
	["dust", "Dust in the air", 0.0, 3.0, 0.05],
	["fog", "Fog over the shelf", 0.0, 3.0, 0.05],
]

@export var tablecloth_node: Tablecloth
@export var lighting_node: SceneLighting
@export var atmosphere_node: AmbientAtmosphere

@export var lighting := SceneLighting.Mode.SPOTLIGHT:
	set(v):
		lighting = v
		if lighting_node:
			lighting_node.mode = v
@export var tablecloth := true:
	set(v):
		tablecloth = v
		if tablecloth_node:
			tablecloth_node.visible = v
@export var cloth_pattern := Tablecloth.Pattern.GINGHAM:
	set(v):
		cloth_pattern = v
		if tablecloth_node:
			tablecloth_node.pattern = v
@export var cloth_color := Color(0.72, 0.12, 0.12):
	set(v):
		cloth_color = v
		if tablecloth_node:
			tablecloth_node.color_a = v
@export var cloth_color_2 := Color(0.95, 0.93, 0.88):
	set(v):
		cloth_color_2 = v
		if tablecloth_node:
			tablecloth_node.color_b = v
@export var dust := 1.0:
	set(v):
		dust = v
		if atmosphere_node:
			atmosphere_node.dust_amount = v
@export var fog := 1.0:
	set(v):
		fog = v
		if atmosphere_node:
			atmosphere_node.fog_amount = v
@export var spot_breathing := 0.08:
	set(v):
		spot_breathing = v
		if lighting_node:
			lighting_node.spot_breathing = v


## Pushes every setting to the scene nodes.
func apply_all() -> void:
	for prop in SETTINGS:
		set(prop, get(prop))


func capture() -> Dictionary:
	var d := {}
	for prop in SETTINGS:
		d[prop] = GlobePreset._encode(get(prop))
	return d


func restore(d) -> void:
	if not (d is Dictionary):
		return
	for prop in SETTINGS:
		if d.has(prop):
			var v = GlobePreset._decode(d[prop], get(prop))
			if v != null:
				set(prop, v)
