class_name GlobePreset
extends RefCounted
## Saves and loads whole snow-globe setups — glass, stand, floor, props and
## every content layer (particles, creatures, plasma) — as plain JSON, so
## presets are easy to read, share and sanity-check when loading.
##
## Built-in presets live in res://presets/ (read-only); the player's own go
## to user://presets/, which on the web is kept in the browser's storage.
## Version 1 files (particles only, wood/snow colours) still load.

const VERSION := 2
const BUILTIN_DIR := "res://presets/"
const USER_DIR := "user://presets/"
const LAST_SESSION_PATH := "user://last_session.json"
const MAX_PARTICLES_PER_LAYER := 5000
const MAX_LAYERS := 8

## SnowGlobe properties that make up its look.
const GLOBE_PROPERTIES: Array[String] = [
	"globe_radius", "glass_shape", "glass_width", "glass_height", "glass_facets", "floor_depth",
	"glass_thickness", "glass_distortion", "magnification", "glass_tint", "glass_edge_tint", "fill", "shell", "field_color",
	"base_type", "base_finish", "base_color", "base_accent", "trim_color",
	"stand_sides", "stand_height", "stand_bottom_radius", "leg_count", "leg_clearance",
	"floor_type", "floor_color", "mound_height", "snow_bumpiness", "snow_seed",
]
## Version 1 names for globe properties.
const LEGACY_NAMES := {"wood_light": "base_color", "wood_dark": "base_accent", "snow_color": "floor_color"}
## Settings newer than some saved presets: when a preset leaves them out they
## go back to their defaults rather than keeping whatever the globe had.
const LATER_PROPERTIES: Array[String] = ["shell", "field_color"]


# --- Capture / apply ----------------------------------------------------------

static func capture(globe: SnowGlobe, preset_name: String) -> Dictionary:
	var g := {}
	for prop in GLOBE_PROPERTIES:
		g[prop] = _encode(globe.get(prop))
	var layers := []
	for layer in get_layers(globe):
		var entry := {"kind": layer_kind(layer), "name": String(layer.name)}
		if layer is GlobeParticles:
			entry["amount"] = layer.amount
			entry["seed"] = layer.random_seed
			entry["style"] = capture_resource(layer.style if layer.style else GlobeParticleStyle.new())
		elif layer is GlobeCreatures:
			entry["amount"] = layer.amount
			entry["seed"] = layer.random_seed
			entry["species"] = capture_resource(layer.species if layer.species else CreatureSpecies.new())
		else:
			var settings := {}
			for prop in layer_settings(layer):
				settings[prop] = _encode(layer.get(prop))
			entry["settings"] = settings
		layers.append(entry)
	return {"version": VERSION, "name": preset_name, "globe": g, "props": _clean_props(globe.props), "layers": layers}


## Every stored script property of a style / species resource.
static func capture_resource(res: Resource) -> Dictionary:
	var d := {}
	for prop in _stored_properties(res):
		var v = _encode(res.get(prop))
		if v != null or res.get(prop) == null:
			d[prop] = v
	return d


## Applies a preset to a globe, replacing its content layers. Unknown keys
## are ignored and values are type-checked and clamped, so hand-edited or
## shared files can't break the scene.
static func apply(globe: SnowGlobe, data: Dictionary) -> void:
	var g: Dictionary = data.get("globe", {}).duplicate()
	for old in LEGACY_NAMES:
		if g.has(old) and not g.has(LEGACY_NAMES[old]):
			g[LEGACY_NAMES[old]] = g[old]
	for prop in LATER_PROPERTIES:
		if not g.has(prop):
			globe.set(prop, globe.get_script().get_property_default_value(prop))
	for prop in GLOBE_PROPERTIES:
		if g.has(prop):
			var v = _decode(g[prop], globe.get(prop))
			if v != null:
				globe.set(prop, v)
	if data.has("props"):
		globe.props = _clean_props(data["props"])
	elif g.has("show_placeholder_tree"):
		globe.props = [_default_prop("pine")] if bool(g["show_placeholder_tree"]) else []

	for layer in get_layers(globe):
		globe.remove_child(layer)
		layer.queue_free()
	var layers: Array = data.get("layers", [])
	if data.has("particles"):
		for entry in data["particles"]:
			if entry is Dictionary:
				var e: Dictionary = entry.duplicate()
				e["kind"] = "particles"
				layers.append(e)
	for i in mini(layers.size(), MAX_LAYERS):
		var entry = layers[i]
		if entry is Dictionary:
			var node := make_layer(entry)
			if node:
				globe.add_child(node, true)


## Builds one content layer node from a preset entry.
static func make_layer(entry: Dictionary) -> Node3D:
	var node: Node3D
	match String(entry.get("kind", "particles")):
		"particles":
			var p := GlobeParticles.new()
			p.amount = clampi(int(entry.get("amount", 500)), 0, MAX_PARTICLES_PER_LAYER)
			p.random_seed = int(entry.get("seed", 0))
			var style: GlobeParticleStyle = resource_from_dict(GlobeParticleStyle.new(), entry.get("style", {}))
			if style.shape == GlobeParticleStyle.Shape.CUSTOM:
				style.shape = GlobeParticleStyle.Shape.FLAKE
			p.style = style
			node = p
		"creatures":
			var c := GlobeCreatures.new()
			c.amount = clampi(int(entry.get("amount", 40)), 0, GlobeCreatures.MAX_AMOUNT)
			c.random_seed = int(entry.get("seed", 0))
			c.species = resource_from_dict(CreatureSpecies.new(), entry.get("species", {}))
			node = c
		var kind:
			node = new_settings_layer(kind)
			if node == null:
				return null
			var s = entry.get("settings", {})
			if s is Dictionary:
				for prop in layer_settings(node):
					if s.has(prop):
						var v = _decode(s[prop], node.get(prop))
						if v != null:
							node.set(prop, v)
	node.name = String(entry.get("name", "Layer")).validate_node_name()
	return node


static func resource_from_dict(res: Resource, d) -> Resource:
	if not (d is Dictionary):
		return res
	for prop in _stored_properties(res):
		if not d.has(prop):
			continue
		var is_gradient := res.get(prop) is Gradient or prop.ends_with("gradient")
		var v = _decode(d[prop], res.get(prop), is_gradient)
		if v != null or is_gradient:
			res.set(prop, v)
	return res


static func get_layers(globe: SnowGlobe) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in globe.get_children():
		if child.is_in_group(&"globe_layer") and not child.is_queued_for_deletion():
			out.append(child)
	return out


static func layer_kind(layer: Node) -> String:
	if layer is GlobeCreatures:
		return "creatures"
	if layer is GlobeParticles:
		return "particles"
	return String(_script_const(layer, "KIND", "particles"))


## New layer of a kind described by a flat list of settings (each class lists
## them in its SETTINGS constant and names its kind in KIND), or null.
static func new_settings_layer(kind: String) -> Node3D:
	match kind:
		"plasma": return GlobePlasma.new()
		"fireworks": return GlobeFireworks.new()
		"dynamite": return GlobeDynamite.new()
		"cobwebs": return GlobeCobwebs.new()
		"aurora": return GlobeAurora.new()
		"heat": return GlobeHeat.new()
		"sunrays": return GlobeSunrays.new()
		"rainbow": return GlobeRainbow.new()
		"serpent": return GlobeSerpent.new()
		"lava": return GlobeLava.new()
		"snake": return GlobeSerpent.with_style(GlobeSerpent.Style.SNAKE)
		"dragon": return GlobeSerpent.with_style(GlobeSerpent.Style.DRAGON)
		"noodle": return GlobeSerpent.with_style(GlobeSerpent.Style.NOODLE)
	return null


## The settings a settings-kind layer stores (its SETTINGS constant).
static func layer_settings(layer: Object) -> Array:
	return _script_const(layer, "SETTINGS", [])


static func _script_const(obj: Object, name: String, fallback):
	var script: Script = obj.get_script()
	if script == null:
		return fallback
	return script.get_script_constant_map().get(name, fallback)


static func _stored_properties(res: Object) -> Array[String]:
	var out: Array[String] = []
	for p in res.get_property_list():
		var usage: int = p["usage"]
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_STORAGE):
			continue
		var v = res.get(p["name"])
		# Meshes / materials can't go in JSON; gradients can.
		if v is Object and not (v is Gradient):
			continue
		if p["type"] == TYPE_OBJECT and p["hint_string"] != "Gradient":
			continue
		out.append(p["name"])
	return out


# --- Props ------------------------------------------------------------------------

static func _default_prop(type: String) -> Dictionary:
	return {"type": type, "x": 0.0, "z": 0.0, "rot": 0.0, "scale": 1.0, "color": String(PropLibrary.info(type)["color"])}


## Validated copy of a props list.
static func _clean_props(list) -> Array:
	var out := []
	if not (list is Array):
		return out
	for p in list:
		if not (p is Dictionary) or out.size() >= SnowGlobe.MAX_PROPS:
			continue
		var type := String(p.get("type", ""))
		if not PropLibrary.TYPES.has(type):
			continue
		var pos := Vector2(_num(p.get("x", 0.0)), _num(p.get("z", 0.0))).limit_length(0.95)
		var col := String(p.get("color", PropLibrary.info(type)["color"]))
		out.append({
			"type": type,
			"x": snappedf(pos.x, 0.0001),
			"z": snappedf(pos.y, 0.0001),
			"rot": snappedf(fposmod(_num(p.get("rot", 0.0)), 360.0), 0.01),
			"scale": snappedf(clampf(_num(p.get("scale", 1.0)), 0.1, 4.0), 0.0001),
			"color": col if Color.html_is_valid(col) else String(PropLibrary.info(type)["color"]),
		})
	return out


static func _num(v) -> float:
	return float(v) if (v is float or v is int) else 0.0


# --- JSON encoding --------------------------------------------------------------

static func _encode(v):
	if v is Color:
		return _round([v.r, v.g, v.b, v.a])
	if v is Gradient:
		var colors := []
		for c in v.colors:
			colors.append(_round([c.r, c.g, c.b, c.a]))
		return {"offsets": _round(Array(v.offsets)), "colors": colors}
	if v is float:
		return snappedf(v, 0.0001)
	if v is Object:
		return null
	return v


## Keeps saved files readable (0.62 rather than 0.620000004768372).
static func _round(values: Array) -> Array:
	return values.map(func(x: float) -> float: return snappedf(x, 0.0001))


## Converts a JSON value back to the type of `like`. Returns null if it
## doesn't fit.
static func _decode(v, like, is_gradient := false):
	if is_gradient:
		if not (v is Dictionary) or not v.has("offsets") or not v.has("colors"):
			return null
		var grad := Gradient.new()
		var offsets := PackedFloat32Array()
		var colors := PackedColorArray()
		var n := mini(v["offsets"].size(), v["colors"].size())
		for i in n:
			var c = _decode(v["colors"][i], Color())
			if c == null:
				return null
			offsets.append(clampf(float(v["offsets"][i]), 0.0, 1.0))
			colors.append(c)
		grad.offsets = offsets
		grad.colors = colors
		return grad
	match typeof(like):
		TYPE_COLOR:
			if v is Array and v.size() >= 3:
				return Color(float(v[0]), float(v[1]), float(v[2]), float(v[3]) if v.size() > 3 else 1.0)
			if v is String and Color.html_is_valid(v):
				return Color.html(v)
			return null
		TYPE_BOOL:
			return bool(v) if (v is bool or v is float or v is int) else null
		TYPE_INT:
			return int(v) if (v is float or v is int) else null
		TYPE_FLOAT:
			return clampf(float(v), -1000.0, 1000.0) if (v is float or v is int) else null
	return null


# --- Storage --------------------------------------------------------------------

## Every preset on offer: [{name, path, builtin}], built-ins first.
static func list_presets() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dir in [BUILTIN_DIR, USER_DIR]:
		for file in _json_files(dir):
			var data := load_file(dir + file)
			if data.is_empty():
				continue
			out.append({"name": String(data.get("name", file.get_basename())), "path": dir + file, "builtin": dir == BUILTIN_DIR})
	return out


static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func save_user(preset_name: String, data: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var path := USER_DIR + _file_name_for(preset_name)
	return path if _write(path, data) else ""


static func delete_user(path: String) -> void:
	if path.begins_with(USER_DIR):
		DirAccess.remove_absolute(path)


## Saves every globe on the shelf plus the room settings (session format 3).
static func save_session(globes: Array[SnowGlobe], scene := {}) -> void:
	var list := []
	for g in globes:
		list.append(capture(g, "Globe"))
	_write(LAST_SESSION_PATH, {"version": 3, "globes": list, "scene": scene})


## The room settings saved with the last session ({} if none).
static func load_session_scene() -> Dictionary:
	var s = load_file(LAST_SESSION_PATH).get("scene", {})
	return s if s is Dictionary else {}


## The globes of the last session as preset dictionaries (older sessions,
## which held a single globe, come back as a list of one).
static func load_session() -> Array:
	var data := load_file(LAST_SESSION_PATH)
	if data.is_empty():
		return []
	if data.has("globes") and data["globes"] is Array:
		return (data["globes"] as Array).filter(func(g) -> bool: return g is Dictionary)
	return [data]


static func _write(path: String, data: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Couldn't save %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return true


static func _file_name_for(preset_name: String) -> String:
	var base := preset_name.strip_edges().to_lower().validate_filename().replace(" ", "_")
	return (base if base != "" else "preset") + ".json"


static func _json_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.get_extension() == "json":
			out.append(f)
	out.sort()
	return out
