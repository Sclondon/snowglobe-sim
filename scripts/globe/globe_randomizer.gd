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
		"layers": [["snow", 1.0], ["glitter", 0.3], ["people", 0.3]],
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
		"layers": [["butterflies", 1.0], ["people", 0.25]],
	},
	"desert": {
		"weight": 1, "fill": SnowGlobe.Fill.AIR, "floors": [SnowGlobe.FloorType.SAND],
		"props": ["cactus", "cactus", "rocks", "anthill"],
		"layers": [["ants", 1.0], ["people", 0.2]],
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
}

## Layer recipes: kind, preset resource, amount range.
const LAYERS := {
	"snow": ["particles", "res://particles/snow.tres", Vector2i(500, 1200)],
	"rain": ["particles", "res://particles/rain.tres", Vector2i(350, 600)],
	"bubbles": ["particles", "res://particles/bubbles.tres", Vector2i(40, 160)],
	"glitter": ["particles", "res://particles/glitter.tres", Vector2i(300, 700)],
	"sea_monkeys": ["creatures", "res://creatures/sea_monkeys.tres", Vector2i(25, 60)],
	"butterflies": ["creatures", "res://creatures/butterflies.tres", Vector2i(12, 28)],
	"ants": ["creatures", "res://creatures/ants.tres", Vector2i(25, 50)],
	"people": ["creatures", "res://creatures/people.tres", Vector2i(5, 12)],
	"plasma": ["plasma", "", Vector2i.ZERO],
}


static func roll(rng: RandomNumberGenerator) -> Dictionary:
	var theme_name := _pick_theme(rng)
	var theme: Dictionary = THEMES[theme_name]
	var g := {}

	# Glass.
	var shape: int = [0, 0, 0, 1, 1, 2, 3][rng.randi() % 7]
	g["glass_shape"] = shape
	g["glass_width"] = rng.randf_range(0.85, 1.15)
	g["glass_height"] = rng.randf_range(0.9, 1.25) if shape != GlassShape.Kind.TUBE else rng.randf_range(1.0, 1.35)
	g["glass_facets"] = rng.randi_range(6, 12)
	match shape:
		GlassShape.Kind.TUBE: g["floor_depth"] = rng.randf_range(0.6, 0.8)
		GlassShape.Kind.DIAMOND: g["floor_depth"] = rng.randf_range(0.3, 0.42)
		_: g["floor_depth"] = rng.randf_range(0.45, 0.68)
	g["glass_thickness"] = rng.randf_range(0.1, 0.4)
	g["glass_distortion"] = rng.randf_range(0.0, 0.3)
	g["magnification"] = rng.randf_range(1.1, 1.3)
	g["fill"] = theme["fill"]
	var tint: Color = theme.get("tint", Color(0.93, 0.97, 1.0))
	g["glass_tint"] = tint.lerp(Color.from_hsv(rng.randf(), 0.12, 1.0), 0.3)
	g["glass_edge_tint"] = Color(g["glass_tint"]).darkened(0.3)

	# Stand.
	var r := rng.randf()
	g["base_type"] = GlobeBase.Kind.PEDESTAL if r < 0.6 else (GlobeBase.Kind.LEGS if r < 0.85 else GlobeBase.Kind.NONE)
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
			"plasma":
				var hue := rng.randf_range(0.6, 1.1)
				entry["settings"] = {
					"arc_count": rng.randi_range(5, 10),
					"arc_color": GlobePreset._encode(Color.from_hsv(fposmod(hue, 1.0), 0.6, 1.0)),
					"jitter": rng.randf_range(0.5, 1.0),
				}
		out.append(entry)
	return out
