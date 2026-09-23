class_name GlobeRandomizer
extends RefCounted
## Rolls a random snow globe as preset data (see GlobePreset), so it loads,
## saves and shares like any other preset.
##
## A theme is picked first so the pieces make sense together (sea monkeys in
## water on sand with coral, butterflies in air over grass...); the glass,
## stand and colours are then rolled independently.

const THEMES := {
	"winter": {
		"weight": 3, "fill": SnowGlobe.Fill.WATER, "floors": [SnowGlobe.FloorType.SNOW],
		"props": ["pine", "pine", "round_tree", "snowman", "cabin", "rocks"],
		"layers": [["snow", 0.7], ["snowfall", 0.4], ["glitter", 0.3], ["birds", 0.25], ["people", 0.3]],
	},
	"underwater": {
		"weight": 2, "fill": SnowGlobe.Fill.WATER, "floors": [SnowGlobe.FloorType.SAND],
		"props": ["coral", "coral", "seaweed", "seaweed", "rocks", "lighthouse"],
		"layers": [["sea_monkeys", 1.0], ["bubbles", 0.7]],
		"tint": Color(0.8, 0.95, 0.95),
	},
	"garden": {
		"weight": 2, "fill": SnowGlobe.Fill.AIR, "floors": [SnowGlobe.FloorType.GRASS, SnowGlobe.FloorType.MOSS],
		"props": ["round_tree", "round_tree", "pine", "rocks", "cabin"],
		"layers": [["butterflies", 1.0], ["birds", 0.4], ["people", 0.25]],
	},
	"desert": {
		"weight": 1, "fill": SnowGlobe.Fill.AIR, "floors": [SnowGlobe.FloorType.SAND],
		"props": ["cactus", "cactus", "rocks", "anthill"],
		"layers": [["ants", 1.0], ["snake", 0.35], ["people", 0.2]],
	},
	"storm": {
		"weight": 1, "fill": SnowGlobe.Fill.AIR, "floors": [SnowGlobe.FloorType.GRASS, SnowGlobe.FloorType.ROCK],
		"props": ["lighthouse", "rocks", "cabin", "round_tree"],
		"layers": [["rain", 1.0], ["people", 0.2]],
	},
	"plasma": {
		"weight": 1, "fill": SnowGlobe.Fill.AIR, "floors": [SnowGlobe.FloorType.ROCK],
		"props": [], "layers": [["plasma", 1.0]],
		"tint": Color(0.62, 0.55, 0.78),
	},
	"party": {
		"weight": 1, "fill": SnowGlobe.Fill.WATER, "floors": [SnowGlobe.FloorType.SNOW, SnowGlobe.FloorType.MOSS],
		"props": ["pine", "snowman", "round_tree", "cabin"],
		"layers": [["glitter", 1.0], ["bubbles", 0.5], ["snow", 0.4]],
	},
	"attic": {
		"weight": 1, "fill": SnowGlobe.Fill.AIR, "floors": [SnowGlobe.FloorType.ROCK, SnowGlobe.FloorType.MOSS],
		"props": ["rocks", "cabin", "round_tree", "rocks"],
		"layers": [["cobwebs", 1.0], ["dust", 1.0], ["people", 0.2]],
		"tint": Color(0.85, 0.82, 0.72),
	},
	"celebration": {
		"weight": 1, "fill": SnowGlobe.Fill.WATER, "floors": [SnowGlobe.FloorType.SNOW, SnowGlobe.FloorType.GRASS],
		"props": ["cabin", "pine", "snowman", "lighthouse"],
		"layers": [["fireworks", 1.0], ["glitter", 0.4], ["snow", 0.3]],
	},
	"sky": {
		"weight": 1, "fill": SnowGlobe.Fill.AIR, "floors": [SnowGlobe.FloorType.GRASS, SnowGlobe.FloorType.MOSS],
		"props": ["lighthouse", "round_tree", "rocks"],
		"layers": [["clouds", 1.0], ["wind", 0.7], ["rain", 0.3]],
		"tint": Color(0.82, 0.9, 1.0),
	},
	"meadow_night": {
		"weight": 2, "fill": SnowGlobe.Fill.AIR, "floors": [SnowGlobe.FloorType.GRASS, SnowGlobe.FloorType.MOSS],
		"props": ["round_tree", "pine", "frog", "rocks", "frog"],
		"layers": [["fireflies", 1.0], ["aurora", 0.6]],
		"tint": Color(0.8, 0.85, 1.0),
	},
	"desert_heat": {
		"weight": 1, "fill": SnowGlobe.Fill.AIR, "floors": [SnowGlobe.FloorType.SAND],
		"props": ["cactus", "cactus", "rocks", "anthill"],
		"layers": [["heat", 1.0], ["sunrays", 0.7], ["ants", 0.4]],
		"tint": Color(1.0, 0.95, 0.85),
	},
	"rainbow_garden": {
		"weight": 1, "fill": SnowGlobe.Fill.AIR, "floors": [SnowGlobe.FloorType.GRASS],
		"props": ["round_tree", "ball", "frog", "ring"],
		"layers": [["rainbow", 1.0], ["butterflies", 0.7], ["rain", 0.3]],
	},
	"pond": {
		"weight": 1, "fill": SnowGlobe.Fill.WATER, "floors": [SnowGlobe.FloorType.MOSS, SnowGlobe.FloorType.SAND],
		"props": ["frog", "frog", "seaweed", "rocks", "ball"],
		"layers": [["bubbles", 1.0], ["sea_monkeys", 0.3]],
		"tint": Color(0.82, 0.95, 0.9),
	},
	"dragon_lair": {
		"weight": 1, "fill": SnowGlobe.Fill.AIR, "floors": [SnowGlobe.FloorType.ROCK, SnowGlobe.FloorType.MOSS],
		"props": ["rocks", "pine", "rocks", "lighthouse"],
		"layers": [["dragon", 1.0], ["clouds", 0.5], ["glitter", 0.3]],
	},
	"ramen": {
		"weight": 1, "fill": SnowGlobe.Fill.WATER, "floors": [SnowGlobe.FloorType.SAND],
		"props": ["seaweed", "ball", "rocks"],
		"layers": [["noodle", 1.0], ["bubbles", 0.5]],
		"tint": Color(1.0, 0.94, 0.82),
	},
	"lava_lamp": {
		"weight": 2, "fill": SnowGlobe.Fill.WATER, "floors": [SnowGlobe.FloorType.ROCK, SnowGlobe.FloorType.SAND],
		"props": ["rocks"],
		"layers": [["lava", 1.0], ["glitter", 0.3], ["bubbles", 0.25]],
		"tint": Color(0.95, 0.9, 1.0),
	},
	"mine": {
		"weight": 1, "fill": SnowGlobe.Fill.AIR, "floors": [SnowGlobe.FloorType.ROCK, SnowGlobe.FloorType.SAND],
		"props": ["rocks", "rocks", "cactus", "anthill"],
		"layers": [["dynamite", 1.0], ["dust", 0.7], ["people", 0.4]],
	},
}

## Layer recipes: kind, preset resource, amount range.
const LAYERS := {
	"snow": ["particles", "res://particles/snow.tres", Vector2i(500, 1200)],
	"rain": ["particles", "res://particles/rain.tres", Vector2i(350, 600)],
	"snowfall": ["particles", "res://particles/snowfall.tres", Vector2i(350, 700)],
	"bubbles": ["particles", "res://particles/bubbles.tres", Vector2i(40, 160)],
	"glitter": ["particles", "res://particles/glitter.tres", Vector2i(300, 700)],
	"sea_monkeys": ["creatures", "res://creatures/sea_monkeys.tres", Vector2i(25, 60)],
	"butterflies": ["creatures", "res://creatures/butterflies.tres", Vector2i(12, 28)],
	"birds": ["creatures", "res://creatures/birds.tres", Vector2i(4, 10)],
	"ants": ["creatures", "res://creatures/ants.tres", Vector2i(25, 50)],
	"people": ["creatures", "res://creatures/people.tres", Vector2i(5, 12)],
	"dust": ["particles", "res://particles/dust.tres", Vector2i(250, 500)],
	"wind": ["particles", "res://particles/wind.tres", Vector2i(180, 320)],
	"clouds": ["particles", "res://particles/clouds.tres", Vector2i(30, 60)],
	"plasma": ["plasma", "", Vector2i.ZERO],
	"snake": ["snake", "", Vector2i.ZERO],
	"dragon": ["dragon", "", Vector2i.ZERO],
	"noodle": ["noodle", "", Vector2i.ZERO],
	"lava": ["lava", "", Vector2i.ZERO],
	"fireworks": ["fireworks", "", Vector2i.ZERO],
	"dynamite": ["dynamite", "", Vector2i.ZERO],
	"cobwebs": ["cobwebs", "", Vector2i.ZERO],
	"fireflies": ["creatures", "res://creatures/fireflies.tres", Vector2i(18, 40)],
	"aurora": ["aurora", "", Vector2i.ZERO],
	"heat": ["heat", "", Vector2i.ZERO],
	"sunrays": ["sunrays", "", Vector2i.ZERO],
	"rainbow": ["rainbow", "", Vector2i.ZERO],
}
## Shells the themed roll sometimes picks instead of glass.
const FANCY_SHELLS := [SnowGlobe.Shell.ICE, SnowGlobe.Shell.BUBBLE, SnowGlobe.Shell.WATER, SnowGlobe.Shell.FORCEFIELD, SnowGlobe.Shell.MAGNETIC]


static func roll(rng: RandomNumberGenerator) -> Dictionary:
	var theme_name := _pick_theme(rng)
	var theme: Dictionary = THEMES[theme_name]
	var g := {}

	# Glass: mostly middling sizes, now and then a tiny or a big one.
	var size_roll := rng.randf()
	if size_roll < 0.15:
		g["globe_radius"] = rng.randf_range(0.4, 0.65)
	elif size_roll > 0.87:
		g["globe_radius"] = rng.randf_range(1.4, 1.9)
	else:
		g["globe_radius"] = rng.randf_range(0.8, 1.2)
	g["shell"] = SnowGlobe.Shell.GLASS if rng.randf() < 0.7 else FANCY_SHELLS[rng.randi() % FANCY_SHELLS.size()]
	if theme_name == "plasma" and rng.randf() < 0.5:
		g["shell"] = [SnowGlobe.Shell.FORCEFIELD, SnowGlobe.Shell.MAGNETIC][rng.randi() % 2]
	g["field_color"] = Color.from_hsv(rng.randf_range(0.45, 0.8), 0.6, 1.0)
	var shapes := [0, 0, 0, 1, 1, 2, 3, 4, 5, 6]
	var shape: int = shapes[rng.randi() % shapes.size()]
	g["glass_shape"] = shape
	g["glass_width"] = rng.randf_range(0.85, 1.15)
	g["glass_height"] = rng.randf_range(0.9, 1.25) if shape != GlassShape.Kind.TUBE else rng.randf_range(1.0, 1.35)
	g["glass_facets"] = rng.randi_range(6, 12)
	g["floor_depth"] = clampf(GlassShape.DEFAULT_FLOOR_DEPTH[shape] + rng.randf_range(-0.08, 0.08), 0.25, 0.85)
	g["glass_thickness"] = rng.randf_range(0.1, 0.4)
	g["glass_distortion"] = rng.randf_range(0.0, 0.3)
	g["magnification"] = rng.randf_range(1.1, 1.3)
	g["fill"] = theme["fill"]
	var tint: Color = theme.get("tint", SnowGlobe.SHELL_TINTS[g["shell"]])
	g["glass_tint"] = tint.lerp(Color.from_hsv(rng.randf(), 0.12, 1.0), 0.3)
	g["glass_edge_tint"] = Color(g["glass_tint"]).darkened(0.3)

	# Stand.
	var r := rng.randf()
	g["base_type"] = GlobeBase.Kind.PEDESTAL if r < 0.5 else (GlobeBase.Kind.LEGS if r < 0.68 else (GlobeBase.Kind.PLATFORM if r < 0.86 else GlobeBase.Kind.NONE))
	var finish := rng.randi() % GlobeBase.FINISH_NAMES.size()
	g["base_finish"] = finish
	var colors: Array = GlobeBase.FINISH_COLORS[finish]
	match finish:
		GlobeBase.Finish.CERAMIC:
			var hue := rng.randf()
			g["base_color"] = Color.from_hsv(hue, rng.randf_range(0.1, 0.5), rng.randf_range(0.55, 0.95))
			g["base_accent"] = Color.from_hsv(fposmod(hue + 0.5, 1.0), 0.5, 0.6)
		GlobeBase.Finish.METAL:
			g["base_color"] = [Color(0.72, 0.73, 0.76), Color(0.85, 0.7, 0.35), Color(0.72, 0.45, 0.3), Color(0.12, 0.12, 0.14)][rng.randi() % 4]
			g["base_accent"] = colors[1]
		_:
			g["base_color"] = Color(colors[0]).lerp(Color.from_hsv(rng.randf(), 0.4, 0.5), rng.randf_range(0.0, 0.25))
			g["base_accent"] = colors[1]
	g["trim_color"] = [Color(0.95, 0.75, 0.35), Color(0.85, 0.87, 0.92), Color(0.72, 0.45, 0.3), Color.from_hsv(rng.randf(), 0.5, 0.8)][rng.randi() % 4]
	g["stand_sides"] = [5, 6, 8, 8, 10, 12, 16, 32][rng.randi() % 8]
	g["stand_height"] = rng.randf_range(0.4, 0.7)
	g["stand_bottom_radius"] = rng.randf_range(0.95, 1.2)
	g["leg_count"] = rng.randi_range(3, 5)
	g["leg_clearance"] = rng.randf_range(0.15, 0.35)

	# Floor.
	var floors: Array = theme["floors"]
	var floor_type: int = floors[rng.randi() % floors.size()]
	g["floor_type"] = floor_type
	g["floor_color"] = Color(SnowGlobe.FLOOR_COLORS[floor_type]).lerp(Color.from_hsv(rng.randf(), 0.3, 0.7), rng.randf_range(0.0, 0.12))
	g["mound_height"] = rng.randf_range(0.0, 0.15) if theme_name != "plasma" else 0.0
	g["snow_bumpiness"] = rng.randf_range(0.0, 0.05)
	g["snow_seed"] = rng.randi_range(0, 99)

	for k in g:
		g[k] = GlobePreset._encode(g[k])
	return {
		"version": GlobePreset.VERSION,
		"name": "Random %s" % theme_name.capitalize(),
		"globe": g,
		"props": _roll_props(rng, theme["props"]),
		"layers": _roll_layers(rng, theme["layers"]),
	}


## No theme: every part is picked on its own, from everything available.
static func roll_chaos(rng: RandomNumberGenerator) -> Dictionary:
	var data := roll(rng)
	var g: Dictionary = data["globe"]
	g["glass_shape"] = rng.randi() % GlassShape.KIND_NAMES.size()
	g["shell"] = rng.randi() % SnowGlobe.SHELL_NAMES.size()
	g["globe_radius"] = rng.randf_range(0.4, 1.9)
	g["base_type"] = rng.randi() % GlobeBase.KIND_NAMES.size()
	g["glass_width"] = rng.randf_range(0.7, 1.4)
	g["glass_height"] = rng.randf_range(0.7, 1.6)
	g["floor_depth"] = clampf(GlassShape.DEFAULT_FLOOR_DEPTH[g["glass_shape"]] + rng.randf_range(-0.15, 0.1), 0.25, 0.85)
	g["glass_thickness"] = rng.randf_range(0.0, 0.7)
	g["glass_distortion"] = rng.randf_range(-0.3, 0.6)
	g["fill"] = rng.randi() % SnowGlobe.FILL_NAMES.size()
	g["glass_tint"] = GlobePreset._encode(Color.from_hsv(rng.randf(), rng.randf_range(0.0, 0.35), 1.0))
	g["glass_edge_tint"] = GlobePreset._encode(Color.from_hsv(rng.randf(), 0.4, 0.8))
	var floor_type := rng.randi() % SnowGlobe.FLOOR_NAMES.size()
	g["floor_type"] = floor_type
	g["floor_color"] = GlobePreset._encode(Color.from_hsv(rng.randf(), rng.randf_range(0.0, 0.7), rng.randf_range(0.3, 0.95)))
	g["base_color"] = GlobePreset._encode(Color.from_hsv(rng.randf(), rng.randf_range(0.0, 0.8), rng.randf_range(0.2, 0.95)))
	g["base_accent"] = GlobePreset._encode(Color.from_hsv(rng.randf(), rng.randf_range(0.0, 0.8), rng.randf_range(0.2, 0.9)))
	g["mound_height"] = rng.randf_range(0.0, 0.3)

	var types := PropLibrary.type_ids()
	var pool := []
	for i in 6:
		pool.append(types[rng.randi() % types.size()])
	data["props"] = _roll_props(rng, pool)
	if rng.randf() < 0.15:
		data["props"] = []

	var kinds := LAYERS.keys()
	kinds.shuffle()
	var options := []
	for i in rng.randi_range(1, 3):
		options.append([kinds[(i + rng.randi()) % kinds.size()], 1.0])
	data["layers"] = _roll_layers(rng, options)
	for entry in data["layers"]:
		# Push the looks further than the themed roll does.
		if entry.has("style"):
			entry["style"]["color"] = GlobePreset._encode(Color.from_hsv(rng.randf(), rng.randf_range(0.2, 1.0), 1.0))
			entry["style"]["size"] = float(entry["style"]["size"]) * rng.randf_range(0.6, 2.0)
			entry["style"]["gravity"] = float(entry["style"]["gravity"]) * rng.randf_range(-0.5, 1.8)
		if entry.has("species"):
			entry["species"]["color"] = GlobePreset._encode(Color.from_hsv(rng.randf(), rng.randf_range(0.3, 1.0), rng.randf_range(0.5, 1.0)))
			entry["species"]["size"] = float(entry["species"]["size"]) * rng.randf_range(0.7, 1.6)
	data["name"] = "Random Chaos"
	return data


static func _pick_theme(rng: RandomNumberGenerator) -> String:
	var total := 0
	for t in THEMES:
		total += int(THEMES[t]["weight"])
	var pick := rng.randi() % total
	for t in THEMES:
		pick -= int(THEMES[t]["weight"])
		if pick < 0:
			return t
	return "winter"


static func _roll_props(rng: RandomNumberGenerator, pool: Array) -> Array:
	var out := []
	if pool.is_empty():
		return out
	var count := rng.randi_range(1, 4)
	var spots: Array[Vector2] = []
	for i in count:
		# Keep props apart so they don't overlap.
		var at := Vector2.ZERO
		for attempt in 20:
			var a := rng.randf() * TAU
			var d := 0.0 if (i == 0 and rng.randf() < 0.5) else sqrt(rng.randf()) * 0.65
			at = Vector2(sin(a), cos(a)) * d
			var ok := true
			for s in spots:
				if s.distance_to(at) < 0.4:
					ok = false
			if ok:
				break
		spots.append(at)
		var type: String = pool[rng.randi() % pool.size()]
		var base := Color.html(String(PropLibrary.info(type)["color"]))
		out.append({
			"type": type, "x": at.x, "z": at.y, "rot": rng.randf_range(0.0, 360.0),
			"scale": rng.randf_range(0.7, 1.15),
			"color": "#" + base.lerp(Color.from_hsv(rng.randf(), 0.5, 0.7), rng.randf_range(0.0, 0.25)).to_html(false),
		})
	return out


static func _roll_layers(rng: RandomNumberGenerator, options: Array) -> Array:
	var out := []
	for opt in options:
		# The first option is the theme's signature layer and always appears.
		if out.size() > 0 and rng.randf() > float(opt[1]):
			continue
		var recipe: Array = LAYERS[opt[0]]
		var entry := {"kind": recipe[0], "name": String(opt[0]).capitalize(), "seed": rng.randi_range(0, 999)}
		var span: Vector2i = recipe[2]
		entry["amount"] = rng.randi_range(span.x, span.y)
		match recipe[0]:
			"particles":
				var style: GlobeParticleStyle = (load(recipe[1]) as GlobeParticleStyle).duplicate(true)
				if opt[0] != "rain":
					style.color = style.color.lerp(Color.from_hsv(rng.randf(), 0.6, 1.0), rng.randf_range(0.0, 0.35))
				if opt[0] == "glitter" or (opt[0] == "snow" and rng.randf() < 0.15):
					var grad := Gradient.new()
					grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
					grad.colors = PackedColorArray([Color.from_hsv(rng.randf(), 0.6, 1.0), Color.from_hsv(rng.randf(), 0.4, 1.0), Color.from_hsv(rng.randf(), 0.6, 1.0)])
					style.color_gradient = grad
				entry["style"] = GlobePreset.capture_resource(style)
			"creatures":
				var sp: CreatureSpecies = (load(recipe[1]) as CreatureSpecies).duplicate(true)
				sp.color = sp.color.lerp(Color.from_hsv(rng.randf(), 0.7, 0.9), rng.randf_range(0.0, 0.5))
				sp.size *= rng.randf_range(0.85, 1.2)
				entry["species"] = GlobePreset.capture_resource(sp)
			"fireworks":
				entry["settings"] = {
					"launch_interval": rng.randf_range(0.6, 2.0),
					"burst_size": rng.randi_range(35, 90),
					"multicolour": rng.randf() < 0.75,
					"color": GlobePreset._encode(Color.from_hsv(rng.randf(), 0.7, 1.0)),
				}
			"dynamite":
				entry["settings"] = {"count": rng.randi_range(1, 3), "stick_color": GlobePreset._encode(Color.from_hsv(rng.randf_range(-0.03, 0.05), 0.85, 0.8))}
			"cobwebs":
				entry["settings"] = {"count": rng.randi_range(2, 5), "web_size": rng.randf_range(0.28, 0.45), "spokes": rng.randi_range(7, 11), "web_seed": rng.randi_range(0, 99)}
			"plasma":
				var hue := rng.randf_range(0.6, 1.1)
				entry["settings"] = {
					"arc_count": rng.randi_range(5, 10),
					"arc_color": GlobePreset._encode(Color.from_hsv(fposmod(hue, 1.0), 0.6, 1.0)),
					"jitter": rng.randf_range(0.5, 1.0),
				}
			"lava":
				var hue := rng.randf()
				entry["settings"] = {
					"blob_count": rng.randi_range(5, 9),
					"color_low": GlobePreset._encode(Color.from_hsv(hue, 0.85, 1.0)),
					"color_high": GlobePreset._encode(Color.from_hsv(fposmod(hue + rng.randf_range(-0.15, 0.15), 1.0), 0.9, 0.95)),
					"speed": rng.randf_range(0.7, 1.4),
				}
			"snake", "dragon", "noodle":
				var st: int = ["snake", "dragon", "noodle"].find(recipe[0])
				var d: Dictionary = GlobeSerpent.DEFAULTS[st]
				entry["settings"] = {
					"style": st,
					"count": 1 if rng.randf() < 0.7 else 2,
					"body_length": d["body_length"] * rng.randf_range(0.8, 1.2),
					"color": GlobePreset._encode((d["color"] as Color).lerp(Color.from_hsv(rng.randf(), 0.7, 0.8), rng.randf_range(0.0, 0.4))),
					"color2": GlobePreset._encode(d["color2"]),
				}
		out.append(entry)
	return out
