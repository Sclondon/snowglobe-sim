class_name SceneSettings
extends Node
## Room-level options (lighting, tablecloth, ambient dust and fog), edited in
## the editor's Scene tab and remembered with the session.

## Stored in the session.
const SETTINGS: Array[String] = ["lighting", "tablecloth", "cloth_pattern", "cloth_color", "cloth_color_2", "cloth_trim", "dust", "fog", "spot_breathing"]
## Bumped when defaults change enough that older saved values should be
## dropped (version 2: the antique cloth, and gentler spotlight breathing).
const VERSION := 2
const DROPPED_BEFORE_V2: Array[String] = ["cloth_pattern", "cloth_color", "cloth_color_2", "spot_breathing"]
## Sliders / colours / toggles for the editor (dropdowns are added separately).
const EDITOR_ROWS := [
	["spot_breathing", "Spotlight breathing", 0.0, 0.1, 0.005],
	["tablecloth", "Tablecloth"],
	["cloth_color", "Cloth colour"],
	["cloth_color_2", "Cloth pattern colour"],
	["cloth_trim", "Cloth trim"],
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
@export var cloth_pattern := Tablecloth.Pattern.DAMASK:
	set(v):
		cloth_pattern = v
		if tablecloth_node:
			tablecloth_node.pattern = v
@export var cloth_color := Color(0.17, 0.08, 0.2):
	set(v):
		cloth_color = v
		if tablecloth_node:
			tablecloth_node.color_a = v
@export var cloth_color_2 := Color(0.29, 0.16, 0.3):
	set(v):
		cloth_color_2 = v
		if tablecloth_node:
			tablecloth_node.color_b = v
@export var cloth_trim := Color(0.85, 0.66, 0.3):
	set(v):
		cloth_trim = v
		if tablecloth_node:
			tablecloth_node.trim_color = v
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
@export var spot_breathing := 0.02:
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
	d["version"] = VERSION
	return d


func restore(d) -> void:
	if not (d is Dictionary):
		return
	var old: bool = int(d.get("version", 1)) < VERSION
	for prop in SETTINGS:
		if old and prop in DROPPED_BEFORE_V2:
			continue
		if d.has(prop):
			var v = GlobePreset._decode(d[prop], get(prop))
			if v != null:
				set(prop, v)
