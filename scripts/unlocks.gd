class_name Unlocks
extends RefCounted
## Which effects a player may use when making globes. Everything can always
## be *viewed* (community globes show it all); locks only apply to making
## things: the editor, the randomizer and which built-in presets are offered.
##
## Each unlockable has an id ("layer:lava", "shell:forcefield", "shape:pyramid",
## "stand:platform", "prop:frog") and a placeholder ticket price for the site's
## shop. Where the unlocked list comes from, in order:
##   1. The host page: window.snowglobe.unlocks = ["layer:lava", ...] before the
##      game starts, or window.snowglobe.setUnlocks([...]) at any time.
##   2. The save: user://unlocks.json ({"unlocked": [...]}), written whenever it
##      changes, so a host can also ship unlocks inside a save.
##   3. Testing: ?unlock=all in the page address, or --unlock-all.

const SAVE_PATH := "user://unlocks.json"

## id -> [display name, ticket price]. Anything not listed here is free.
const CATALOG := {
	"layer:dust": ["Dust", 50],
	"layer:wind": ["Wind", 50],
	"layer:clouds": ["Clouds / fog", 75],
	"layer:cobwebs": ["Cobwebs", 75],
	"layer:ants": ["Ants", 100],
	"layer:sea_monkeys": ["Sea monkeys", 150],
	"layer:butterflies": ["Butterflies", 150],
	"layer:people": ["Tiny people", 150],
	"layer:heat": ["Heat waves", 150],
	"layer:sunrays": ["Sun rays", 150],
	"layer:birds": ["Songbirds", 200],
	"layer:fireflies": ["Fireflies", 200],
	"layer:rainbow": ["Rainbow", 200],
	"layer:noodle": ["Noodle", 200],
	"layer:fireworks": ["Fireworks", 250],
	"layer:dynamite": ["Dynamite", 250],
	"layer:aurora": ["Aurora", 250],
	"layer:snake": ["Snake", 250],
	"layer:plasma": ["Plasma ball", 300],
	"layer:lava": ["Lava lamp", 350],
	"layer:dragon": ["Dragon", 400],
	"shell:water": ["Water shell", 100],
	"shell:none": ["No shell", 100],
	"shell:ice": ["Ice shell", 150],
	"shell:bubble": ["Soap bubble shell", 150],
	"shell:magnetic": ["Magnetic field shell", 250],
	"shell:forcefield": ["Force field shell", 300],
	"shape:box": ["Box glass", 100],
	"shape:diamond": ["Diamond glass", 150],
	"shape:hourglass": ["Hourglass glass", 150],
	"shape:pyramid": ["Pyramid glass", 150],
	"stand:none": ["No stand", 50],
	"stand:legs": ["Legs & ring stand", 100],
	"stand:platform": ["Platform stand", 150],
	"prop:anthill": ["Anthill", 50],
	"prop:coral": ["Coral", 75],
	"prop:seaweed": ["Seaweed", 75],
	"prop:cactus": ["Cactus", 75],
	"prop:ball": ["Bouncy ball", 100],
	"prop:ring": ["Ring", 100],
	"prop:lighthouse": ["Lighthouse", 150],
	"prop:frog": ["Frog", 150],
}

## Ids by enum index (null = always free).
const SHELL_IDS := [null, "shell:ice", "shell:bubble", "shell:water", "shell:none", "shell:forcefield", "shell:magnetic"]
const SHAPE_IDS := [null, null, "shape:diamond", null, "shape:hourglass", "shape:box", "shape:pyramid"]
const STAND_IDS := [null, "stand:legs", "stand:none", "stand:platform"]
const BODY_IDS := ["layer:sea_monkeys", "layer:butterflies", "layer:ants", "layer:people", "layer:fireflies", "layer:birds"]
const SERPENT_IDS := ["layer:snake", "layer:dragon", "layer:noodle"]
## Particle shapes that are their own unlock (Dust mote, Cloud).
const PARTICLE_SHAPE_IDS := {4: "layer:dust", 5: "layer:clouds"}

## Lets UI react when the unlocked set changes.
class Events:
	extends RefCounted
	signal changed

static var events := Events.new()
static var _unlocked := {}
static var _all := false
static var _loaded := false


## Reads saved unlocks, the host page's and the testing switches (once).
static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	if "--unlock-all" in OS.get_cmdline_user_args():
		_all = true
	var saved := GlobePreset.load_file(SAVE_PATH)
	for id in saved.get("unlocked", []):
		_unlocked[String(id)] = true
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("new URLSearchParams(location.search).get('unlock') || ''", true)
		if String(q) == "all":
			_all = true
		var host = JavaScriptBridge.eval("JSON.stringify((window.snowglobe && window.snowglobe.unlocks) || null)", true)
		var parsed = JSON.parse_string(String(host)) if host != null else null
		if parsed is Array:
			set_unlocked(parsed)
		_expose_to_page()


static var _js_callback: JavaScriptObject

## window.snowglobe.setUnlocks([...]) replaces the list from the page.
static func _expose_to_page() -> void:
	_js_callback = JavaScriptBridge.create_callback(func(args: Array) -> void:
		if args.size() > 0 and args[0] is JavaScriptObject:
			var json = JavaScriptBridge.get_interface("JSON").stringify(args[0])
			var parsed = JSON.parse_string(String(json))
			if parsed is Array:
				set_unlocked(parsed))
	JavaScriptBridge.eval("window.snowglobe = window.snowglobe || {};", true)
	var sg: JavaScriptObject = JavaScriptBridge.get_interface("snowglobe")
	if sg:
		sg.setUnlocks = _js_callback


static func is_unlocked(id) -> bool:
	if id == null or String(id).is_empty() or _all:
		return true
	if not CATALOG.has(String(id)):
		return true
	return _unlocked.has(String(id))


static func set_unlocked(ids: Array) -> void:
	_unlocked.clear()
	for id in ids:
		_unlocked[String(id)] = true
	_save()
	events.changed.emit()


static func unlock(id: String) -> void:
	if not _unlocked.has(id):
		_unlocked[id] = true
		_save()
		events.changed.emit()


static func set_all(on: bool) -> void:
	_all = on
	events.changed.emit()


static func unlocked_ids() -> Array:
	return _unlocked.keys()


static func _save() -> void:
	GlobePreset._write(SAVE_PATH, {"unlocked": _unlocked.keys()})


static func display_name(id: String) -> String:
	return CATALOG[id][0] if CATALOG.has(id) else id


static func price(id: String) -> int:
	return CATALOG[id][1] if CATALOG.has(id) else 0


## "🔒 250 tickets" style suffix for a locked option (empty when unlocked).
static func lock_suffix(id) -> String:
	if is_unlocked(id):
		return ""
	return "  (locked · %d tickets)" % price(String(id))


# --- What a globe uses ---------------------------------------------------------

## Unlock id of one layer entry (preset format), or "" when it's free.
static func layer_id(entry: Dictionary) -> String:
	var kind := String(entry.get("kind", ""))
	match kind:
		"particles":
			var style: Dictionary = entry.get("style", {})
			var shape := int(style.get("shape", 0))
			if PARTICLE_SHAPE_IDS.has(shape):
				return PARTICLE_SHAPE_IDS[shape]
			if absf(float(style.get("wind", 0.0))) > 0.3:
				return "layer:wind"
			return ""
		"creatures":
			var body := int((entry.get("species", {}) as Dictionary).get("body", 0))
			return BODY_IDS[body] if body >= 0 and body < BODY_IDS.size() else ""
		"serpent":
			var st := int((entry.get("settings", {}) as Dictionary).get("style", 0))
			return SERPENT_IDS[st] if st >= 0 and st < SERPENT_IDS.size() else ""
		_:
			return "layer:" + kind


## Every unlock id a preset uses.
static func ids_in(data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var g: Dictionary = data.get("globe", {})
	for pair in [[SHELL_IDS, "shell"], [SHAPE_IDS, "glass_shape"], [STAND_IDS, "base_type"]]:
		var ids: Array = pair[0]
		var i := int(g.get(pair[1], 0))
		if i >= 0 and i < ids.size() and ids[i] != null:
			out.append(ids[i])
	for p in data.get("props", []):
		if p is Dictionary:
			out.append("prop:" + String(p.get("type", "")))
	for entry in data.get("layers", []):
		if entry is Dictionary:
			var id := layer_id(entry)
			if id != "":
				out.append(id)
	return out.filter(func(id: String) -> bool: return CATALOG.has(id))


## The locked things a preset uses (display names, no repeats).
static func locked_in(data: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in ids_in(data):
		if not is_unlocked(id) and not display_name(id) in out:
			out.append(display_name(id))
	return out


static func preset_allowed(data: Dictionary) -> bool:
	return locked_in(data).is_empty()


## A copy of a preset with every locked part taken out or swapped for a free
## one (used by the randomizer).
static func strip_locked(data: Dictionary) -> Dictionary:
	var d := data.duplicate(true)
	var g: Dictionary = d.get("globe", {})
	if not is_unlocked(_at(SHELL_IDS, int(g.get("shell", 0)))):
		g["shell"] = SnowGlobe.Shell.GLASS
		g["glass_tint"] = GlobePreset._encode(SnowGlobe.SHELL_TINTS[0])
	if not is_unlocked(_at(SHAPE_IDS, int(g.get("glass_shape", 0)))):
		g["glass_shape"] = GlassShape.Kind.SPHERE
		g["floor_depth"] = GlassShape.DEFAULT_FLOOR_DEPTH[0]
	if not is_unlocked(_at(STAND_IDS, int(g.get("base_type", 0)))):
		g["base_type"] = GlobeBase.Kind.PEDESTAL
	d["props"] = (d.get("props", []) as Array).filter(func(p) -> bool: return p is Dictionary and is_unlocked("prop:" + String(p.get("type", ""))))
	var layers := (d.get("layers", []) as Array).filter(func(e) -> bool: return e is Dictionary and is_unlocked(layer_id(e)))
	if layers.is_empty():
		layers.append({"kind": "particles", "name": "Snow", "amount": 700, "seed": 0, "style": GlobePreset.capture_resource(load("res://particles/snow.tres"))})
	d["layers"] = layers
	return d


static func _at(ids: Array, i: int):
	return ids[i] if i >= 0 and i < ids.size() else null
