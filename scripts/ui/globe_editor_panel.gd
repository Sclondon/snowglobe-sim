class_name GlobeEditorPanel
extends PanelContainer
## In-game editor: tweak the globe (glass, stand, floor), its content layers
## (particles, creatures, plasma) and props live, and save / load presets.
## Built entirely in code from the property tables below, so exposing another
## property is usually a one-line change.

signal close_requested
## Something was edited or loaded (used to autosave the session).
signal edited
## The Props tab was opened / left (main.gd lets you drag props then).
signal props_tab_toggled(active: bool)
## "Remove this globe" was pressed.
signal remove_globe_requested

enum Tab { GLOBE, CONTENTS, PROPS, PRESETS }

const PARTICLE_LOOK := [
	["size", "Size", 0.005, 0.15, 0.001],
	["size_randomness", "Size variation", 0.0, 1.0, 0.01],
	["color", "Colour"],
	["emission", "Glow", 0.0, 2.0, 0.01],
	["roughness", "Roughness", 0.0, 1.0, 0.01],
	["metallic", "Metallic", 0.0, 1.0, 0.01],
	["tumble_speed", "Spin", 0.0, 15.0, 0.1],
]
const PARTICLE_MOTION := [
	["gravity", "Gravity (− floats up)", -4.0, 4.0, 0.01],
	["drag", "Drag", 0.2, 10.0, 0.05],
	["shake_response", "Shake response", 0.0, 0.5, 0.005],
	["swirl_response", "Swirl response", 0.0, 2.0, 0.01],
	["turbulence", "Drift", 0.0, 0.5, 0.005],
	["shake_turbulence", "Stir-up on shake", 0.0, 3.0, 0.01],
	["wind", "Wind (circles the globe)", -3.0, 3.0, 0.01],
	["lift", "Updraught", -2.0, 2.0, 0.01],
	["restitution", "Bounciness", 0.0, 1.0, 0.01],
	["stickiness", "Settles", 0.0, 30.0, 0.1],
	["pop_at_rest", "Pop & respawn when settled"],
	["pop_delay", "Pop delay (s)", 0.0, 10.0, 0.1],
]
const CREATURE_LOOK := [
	["size", "Size", 0.02, 0.3, 0.001],
	["size_randomness", "Size variation", 0.0, 1.0, 0.01],
	["color", "Colour"],
	["color_variation", "Colour variation", 0.0, 1.0, 0.01],
	["accent_color", "Accent"],
	["detail_color", "Detail"],
	["emission", "Glow", 0.0, 2.0, 0.01],
	["anim_speed", "Animation speed", 0.1, 4.0, 0.01],
]
const CREATURE_BEHAVIOUR := [
	["speed", "Speed", 0.0, 1.5, 0.01],
	["agility", "Agility", 0.1, 10.0, 0.1],
	["wander", "Wander", 0.0, 3.0, 0.01],
	["separation", "Personal space", 0.0, 3.0, 0.01],
	["alignment", "Follow the group's heading", 0.0, 3.0, 0.01],
	["cohesion", "Stick together", 0.0, 3.0, 0.01],
	["panic", "Scared by shaking", 0.0, 3.0, 0.01],
	["panic_speed", "Panic speed", 1.0, 6.0, 0.1],
	["touch_response", "Touch (− flee, + come)", -2.0, 2.0, 0.01],
	["rest_chance", "Stops to rest", 0.0, 1.0, 0.01],
	["rest_time", "Rest time (s)", 0.2, 20.0, 0.1],
]
const WALKER_BEHAVIOUR := [
	["grip", "Grip (hard to knock over)", 0.1, 5.0, 0.01],
	["follow_leader", "Follow the leader", 0.0, 1.0, 0.01],
]
const SHAPE_NAMES := ["Snowflake", "Bubble", "Glitter", "Rain / streak", "Dust mote", "Cloud"]
const BODY_NAMES := ["Sea monkey", "Butterfly", "Ant", "Person"]
const MOVEMENT_NAMES := ["Swim", "Fly", "Walk"]
## "+ Add" menu: label → [kind, preset path, amount].
const NEW_LAYERS := {
	"Snow": ["particles", "res://particles/snow.tres", 600],
	"Rain": ["particles", "res://particles/rain.tres", 500],
	"Bubbles": ["particles", "res://particles/bubbles.tres", 150],
	"Glitter": ["particles", "res://particles/glitter.tres", 500],
	"Dust": ["particles", "res://particles/dust.tres", 400],
	"Wind": ["particles", "res://particles/wind.tres", 250],
	"Clouds / fog": ["particles", "res://particles/clouds.tres", 45],
	"Sea monkeys": ["creatures", "res://creatures/sea_monkeys.tres", 50],
	"Butterflies": ["creatures", "res://creatures/butterflies.tres", 20],
	"Ants": ["creatures", "res://creatures/ants.tres", 40],
	"People": ["creatures", "res://creatures/people.tres", 12],
	"Plasma": ["plasma", "", 0],
	"Fireworks": ["fireworks", "", 0],
	"Dynamite": ["dynamite", "", 0],
	"Cobwebs": ["cobwebs", "", 0],
}

var globe: SnowGlobe
## Index into globe.props of the prop being edited (-1 = none).
var selected_prop := -1

var _tabs: TabContainer
var _globe_box: VBoxContainer
var _contents_box: VBoxContainer
var _props_box: VBoxContainer
var _presets_box: VBoxContainer
var _layer_index := 0
var _preset_name: LineEdit
var _status: Label


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "Edit globe"
	title.theme_type_variation = &"HeaderLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_icon_button(preload("res://ui/icons/randomize.svg"), "Random themed globe", randomize_globe))
	header.add_child(_icon_button(preload("res://ui/icons/chaos.svg"), "Totally random globe", randomize_globe.bind(true)))
	header.add_child(_icon_button(preload("res://ui/icons/close.svg"), "Close editor", close_requested.emit))

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)
	_globe_box = _add_tab("Globe")
	_contents_box = _add_tab("Contents")
	_props_box = _add_tab("Props")
	_presets_box = _add_tab("Presets")
	_tabs.tab_changed.connect(func(t: int) -> void: props_tab_toggled.emit(t == Tab.PROPS and is_visible_in_tree()))
	visibility_changed.connect(func() -> void: props_tab_toggled.emit(_tabs.current_tab == Tab.PROPS and is_visible_in_tree()))

	_status = Label.new()
	_status.theme_type_variation = &"HintLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)


## Rebuilds every tab from the globe's current state.
func refresh() -> void:
	if globe == null or _tabs == null:
		return
	_build_globe_tab()
	_build_contents_tab()
	_build_props_tab()
	_build_presets_tab()


## Replaces the globe with a randomly rolled one (see GlobeRandomizer).
## chaos: ignore themes and pick every part independently.
func randomize_globe(chaos := false) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var data := GlobeRandomizer.roll_chaos(rng) if chaos else GlobeRandomizer.roll(rng)
	GlobePreset.apply(globe, data)
	_layer_index = 0
	selected_prop = -1
	if chaos:
		_set_status("Rolled a totally random globe — save it in Presets if you like it.")
	else:
		var theme := String(data["name"]).trim_prefix("Random ").to_lower()
		_set_status("Rolled %s %s globe — save it in Presets if you like it." % ["an" if theme[0] in "aeiou" else "a", theme])
	_changed()
	refresh.call_deferred()


## Called by main.gd when a prop is tapped / dragged inside the globe.
func select_prop(index: int) -> void:
	selected_prop = index
	_build_props_tab.call_deferred()


func _add_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	# Right margin keeps values clear of the scrollbar.
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 14)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	return box


static func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


# --- Globe tab ----------------------------------------------------------------

func _build_globe_tab() -> void:
	var box := _globe_box
	_clear(box)
	var rebuild := func() -> void: _build_globe_tab.call_deferred()

	_heading(box, "Glass")
	_option(box, "Shape", GlassShape.KIND_NAMES, globe.glass_shape, func(i: int) -> void:
		globe.glass_shape = i as GlassShape.Kind
		globe.floor_depth = GlassShape.DEFAULT_FLOOR_DEPTH[i]
		rebuild.call())
	_rows(box, [
		["globe_radius", "Size", 0.6, 1.6, 0.01],
		["glass_width", "Width", 0.6, 1.6, 0.01],
		["glass_height", "Height", 0.6, 1.8, 0.01],
	], globe)
	if globe.glass_shape == GlassShape.Kind.DIAMOND:
		_rows(box, [["glass_facets", "Facets", 4, 16, 1]], globe)
	_rows(box, [
		["floor_depth", "Floor level", 0.1, 0.85, 0.01],
		["glass_thickness", "Glass thickness", 0.0, 1.0, 0.01],
		["glass_distortion", "Distortion", -0.5, 1.0, 0.01],
	], globe)
	_option(box, "Fill", SnowGlobe.FILL_NAMES, globe.fill, func(i: int) -> void:
		globe.fill = i as SnowGlobe.Fill
		rebuild.call())
	if globe.fill == SnowGlobe.Fill.WATER:
		_rows(box, [["magnification", "Water magnification", 1.0, 1.6, 0.01]], globe)
	_rows(box, [["glass_tint", "Glass tint"], ["glass_edge_tint", "Glass edge tint"]], globe)

	_heading(box, "Stand")
	_option(box, "Type", GlobeBase.KIND_NAMES, globe.base_type, func(i: int) -> void:
		globe.base_type = i as GlobeBase.Kind
		rebuild.call())
	if globe.base_type != GlobeBase.Kind.NONE:
		_option(box, "Material", GlobeBase.FINISH_NAMES, globe.base_finish, func(i: int) -> void:
			globe.base_finish = i as GlobeBase.Finish
			globe.base_color = GlobeBase.FINISH_COLORS[i][0]
			globe.base_accent = GlobeBase.FINISH_COLORS[i][1]
			rebuild.call())
		if globe.base_type == GlobeBase.Kind.PEDESTAL:
			_rows(box, [
				["stand_sides", "Sides", 3, 24, 1],
				["stand_height", "Height", 0.2, 1.2, 0.01],
				["stand_bottom_radius", "Base width", 0.7, 1.6, 0.01],
			], globe)
		else:
			_rows(box, [
				["leg_count", "Legs", 3, 8, 1],
				["leg_clearance", "Leg height", 0.05, 0.8, 0.01],
			], globe)
		_rows(box, [["base_color", "Colour"], ["base_accent", "Accent"], ["trim_color", "Trim"]], globe)

	_heading(box, "Floor")
	_option(box, "Ground", SnowGlobe.FLOOR_NAMES, globe.floor_type, func(i: int) -> void:
		globe.floor_type = i as SnowGlobe.FloorType
		globe.floor_color = SnowGlobe.FLOOR_COLORS[i]
		rebuild.call())
	_rows(box, [
		["floor_color", "Ground colour"],
		["mound_height", "Mound height", 0.0, 0.4, 0.01],
		["snow_bumpiness", "Bumpiness", 0.0, 0.08, 0.001],
		["snow_seed", "Bump pattern", 0, 99, 1],
	], globe)


# --- Contents tab -------------------------------------------------------------

func _build_contents_tab() -> void:
	var box := _contents_box
	_clear(box)
	var layers := GlobePreset.get_layers(globe)

	var picker_row := HBoxContainer.new()
	box.add_child(picker_row)
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.focus_mode = Control.FOCUS_NONE
	picker.clip_text = true
	for layer in layers:
		picker.add_item(String(layer.name))
	picker_row.add_child(picker)

	var add := MenuButton.new()
	add.text = "+ Add"
	add.flat = false
	for key in NEW_LAYERS:
		add.get_popup().add_item(key)
	add.get_popup().add_item("Copy of this layer")
	add.get_popup().index_pressed.connect(_on_add_layer)
	picker_row.add_child(add)

	if layers.is_empty():
		_hint(box, "The globe is empty — add something.")
		return
	_layer_index = clampi(_layer_index, 0, layers.size() - 1)
	picker.select(_layer_index)
	picker.item_selected.connect(func(i: int) -> void:
		_layer_index = i
		_build_contents_tab.call_deferred())
	var layer := layers[_layer_index]

	var actions := HBoxContainer.new()
	box.add_child(actions)
	if layer.has_method("reset"):
		_button(actions, "Scatter", func() -> void: layer.reset(true))
	_button(actions, "Remove", func() -> void:
		globe.remove_child(layer)
		layer.queue_free()
		_changed()
		_build_contents_tab.call_deferred())

	if layer is GlobeParticles:
		_particles_editor(box, layer)
	elif layer is GlobeCreatures:
		_creatures_editor(box, layer)
	else:
		# Plasma, fireworks, dynamite, cobwebs: rows come from the layer class.
		var consts: Dictionary = layer.get_script().get_script_constant_map()
		_rows(box, consts.get("EDITOR_ROWS", []), layer)
		if consts.has("EDITOR_HINT"):
			_hint(box, consts["EDITOR_HINT"])


func _particles_editor(box: Control, layer: GlobeParticles) -> void:
	# Edit a private copy so shared preset files aren't modified.
	if layer.style == null or not layer.style.resource_path.is_empty():
		layer.style = layer.style.duplicate(true) if layer.style else GlobeParticleStyle.new()
	var style := layer.style
	_slider(box, "Amount", 0, 3000, 1, layer.amount, func(v: float) -> void:
		layer.amount = int(v)
		_changed())
	_option(box, "Shape", SHAPE_NAMES, mini(style.shape, SHAPE_NAMES.size() - 1), func(i: int) -> void:
		style.shape = i as GlobeParticleStyle.Shape
		_build_contents_tab.call_deferred())
	_heading(box, "Look")
	_rows(box, PARTICLE_LOOK, style)
	if style.shape == GlobeParticleStyle.Shape.RAIN:
		_rows(box, [["stretch", "Streak length", 0.0, 0.5, 0.005]], style)
	_multicolour(box, style)
	_heading(box, "Motion")
	_rows(box, PARTICLE_MOTION, style)


func _creatures_editor(box: Control, layer: GlobeCreatures) -> void:
	if layer.species == null or not layer.species.resource_path.is_empty():
		layer.species = layer.species.duplicate(true) if layer.species else CreatureSpecies.new()
	var sp := layer.species
	_slider(box, "Amount", 0, GlobeCreatures.MAX_AMOUNT, 1, layer.amount, func(v: float) -> void:
		layer.amount = int(v)
		_changed())
	_option(box, "Body", BODY_NAMES, sp.body, func(i: int) -> void:
		sp.body = i as CreatureSpecies.Body)
	_option(box, "Moves by", MOVEMENT_NAMES, sp.movement, func(i: int) -> void:
		sp.movement = i as CreatureSpecies.Movement
		layer.reset(true)
		_build_contents_tab.call_deferred())
	_heading(box, "Look")
	_rows(box, CREATURE_LOOK, sp)
	_heading(box, "Behaviour")
	_rows(box, CREATURE_BEHAVIOUR, sp)
	if sp.movement == CreatureSpecies.Movement.WALK:
		_rows(box, WALKER_BEHAVIOUR, sp)


func _on_add_layer(index: int) -> void:
	var layers := GlobePreset.get_layers(globe)
	if layers.size() >= GlobePreset.MAX_LAYERS:
		_set_status("That's the most layers a globe can have.")
		return
	var keys := NEW_LAYERS.keys()
	var node: Node3D
	if index < keys.size():
		var info: Array = NEW_LAYERS[keys[index]]
		match info[0]:
			"particles":
				var p := GlobeParticles.new()
				p.style = (load(info[1]) as GlobeParticleStyle).duplicate(true)
				p.amount = info[2]
				node = p
			"creatures":
				var c := GlobeCreatures.new()
				c.species = (load(info[1]) as CreatureSpecies).duplicate(true)
				c.amount = info[2]
				node = c
			var kind:
				node = GlobePreset.new_settings_layer(kind)
		node.name = keys[index]
	elif not layers.is_empty():
		var entry: Dictionary = GlobePreset.capture(globe, "")["layers"][_layer_index]
		entry["seed"] = int(entry.get("seed", 0)) + 1
		node = GlobePreset.make_layer(entry)
	if node == null:
		return
	globe.add_child(node, true)
	_layer_index = GlobePreset.get_layers(globe).size() - 1
	_changed()
	_build_contents_tab.call_deferred()


## "Multicolour": particles pick from a three-colour gradient.
func _multicolour(parent: Control, style: GlobeParticleStyle) -> void:
	var box := VBoxContainer.new()
	parent.add_child(box)
	_fill_multicolour(box, style)


func _fill_multicolour(box: Control, style: GlobeParticleStyle) -> void:
	_clear(box)
	var on := style.color_gradient != null
	_check(box, "Multicolour", on, func(v: bool) -> void:
		if v:
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
			g.colors = PackedColorArray([style.color, style.color.lightened(0.4), style.color.darkened(0.3)])
			style.color_gradient = g
		else:
			style.color_gradient = null
		_changed()
		_fill_multicolour.call_deferred(box, style))
	if on:
		var g := style.color_gradient
		for i in g.get_point_count():
			_color(box, "Colour %d" % (i + 1), g.get_color(i), func(c: Color) -> void:
				g.set_color(i, c)
				style.emit_changed()
				_changed())


# --- Props tab ----------------------------------------------------------------

func _build_props_tab() -> void:
	var box := _props_box
	_clear(box)
	_hint(box, "Drag props inside the globe to move them. Tap one to select it; with one selected, tap the floor to move it there.")

	var add := MenuButton.new()
	add.text = "+ Add prop"
	add.flat = false
	var ids := PropLibrary.type_ids()
	for id in ids:
		add.get_popup().add_item(PropLibrary.info(id)["name"])
	add.get_popup().index_pressed.connect(func(i: int) -> void:
		if globe.props.size() >= SnowGlobe.MAX_PROPS:
			_set_status("That's as many props as fit.")
			return
		var type: String = ids[i]
		# Drop new props in a free-ish spot on a ring around the middle.
		var a := globe.props.size() * 2.4
		var r := 0.0 if globe.props.is_empty() else 0.5
		globe.props.append({"type": type, "x": sin(a) * r, "z": cos(a) * r, "rot": 0.0, "scale": 1.0, "color": PropLibrary.info(type)["color"]})
		globe.props_changed()
		selected_prop = globe.props.size() - 1
		_changed()
		_build_props_tab.call_deferred())
	box.add_child(add)

	for i in globe.props.size():
		var p: Dictionary = globe.props[i]
		var b := Button.new()
		b.text = PropLibrary.info(String(p.get("type", "")))["name"]
		b.toggle_mode = true
		b.button_pressed = i == selected_prop
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			selected_prop = i
			_build_props_tab.call_deferred())
		box.add_child(b)

	if selected_prop < 0 or selected_prop >= globe.props.size():
		selected_prop = -1
		return
	var prop: Dictionary = globe.props[selected_prop]
	var idx := selected_prop
	_heading(box, "Selected prop")
	_option(box, "Type", ids.map(func(id: String) -> String: return PropLibrary.info(id)["name"]), maxi(ids.find(prop.get("type", "")), 0), func(i: int) -> void:
		prop["type"] = ids[i]
		prop["color"] = PropLibrary.info(ids[i])["color"]
		globe.props_changed()
		_changed()
		_build_props_tab.call_deferred())
	_slider(box, "Size", 0.3, 2.5, 0.01, float(prop.get("scale", 1.0)), func(v: float) -> void:
		prop["scale"] = v
		globe.move_prop(idx, float(prop["x"]), float(prop["z"]))
		_changed())
	_slider(box, "Turn", 0.0, 360.0, 1.0, float(prop.get("rot", 0.0)), func(v: float) -> void:
		prop["rot"] = v
		globe.move_prop(idx, float(prop["x"]), float(prop["z"]))
		_changed())
	var col := String(prop.get("color", "#ffffff"))
	_color(box, "Colour", Color.html(col) if Color.html_is_valid(col) else Color.WHITE, func(c: Color) -> void:
		prop["color"] = "#" + c.to_html(false)
		globe.props_changed()
		_changed())
	var row := HBoxContainer.new()
	box.add_child(row)
	_button(row, "Centre", func() -> void:
		globe.move_prop(idx, 0.0, 0.0)
		_changed())
	_button(row, "Remove", func() -> void:
		globe.props.remove_at(idx)
		globe.props_changed()
		selected_prop = -1
		_changed()
		_build_props_tab.call_deferred())


# --- Presets tab --------------------------------------------------------------

func _build_presets_tab() -> void:
	_clear(_presets_box)
	_heading(_presets_box, "Save current globe")
	var save_row := HBoxContainer.new()
	_presets_box.add_child(save_row)
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "Preset name"
	_preset_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preset_name.max_length = 40
	_preset_name.text_submitted.connect(func(_t: String) -> void: _save_preset())
	save_row.add_child(_preset_name)
	var save := Button.new()
	save.text = "Save"
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(_save_preset)
	save_row.add_child(save)

	var remove := Button.new()
	remove.text = "Remove this globe from the shelf"
	remove.focus_mode = Control.FOCUS_NONE
	remove.pressed.connect(remove_globe_requested.emit)
	_presets_box.add_child(remove)

	_heading(_presets_box, "Load")
	for entry in GlobePreset.list_presets():
		var row := HBoxContainer.new()
		_presets_box.add_child(row)
		var load_button := Button.new()
		load_button.text = entry["name"] + ("" if not entry["builtin"] else "  ·  built-in")
		load_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		load_button.focus_mode = Control.FOCUS_NONE
		load_button.clip_text = true
		var path: String = entry["path"]
		load_button.pressed.connect(func() -> void: load_preset(path))
		row.add_child(load_button)
		if not entry["builtin"]:
			var del := Button.new()
			del.text = "Delete"
			del.focus_mode = Control.FOCUS_NONE
			del.pressed.connect(func() -> void:
				GlobePreset.delete_user(path)
				_set_status("Deleted \"%s\"." % entry["name"])
				_build_presets_tab.call_deferred())
			row.add_child(del)


func load_preset(path: String) -> void:
	var data := GlobePreset.load_file(path)
	if data.is_empty():
		_set_status("Couldn't read that preset.")
		return
	GlobePreset.apply(globe, data)
	_layer_index = 0
	selected_prop = -1
	_set_status("Loaded \"%s\"." % data.get("name", path.get_file().get_basename()))
	_changed()
	# Layers are swapped in this frame; rebuild once they're in the tree.
	refresh.call_deferred()


func _save_preset() -> void:
	var n := _preset_name.text.strip_edges()
	if n.is_empty():
		_set_status("Give the preset a name first.")
		return
	var path := GlobePreset.save_user(n, GlobePreset.capture(globe, n))
	_set_status(("Saved \"%s\"." % n) if path != "" else "Couldn't save — storage may be unavailable.")
	_build_presets_tab.call_deferred()


# --- Control builders ---------------------------------------------------------

## One control per [property, label, (min, max, step)] entry, bound to
## `target`'s property of that name.
func _rows(parent: Control, rows: Array, target: Object) -> void:
	for row in rows:
		var prop: String = row[0]
		var label: String = row[1]
		var value = target.get(prop)
		var setter := func(v) -> void:
			target.set(prop, v)
			_changed()
		match typeof(value):
			TYPE_COLOR:
				_color(parent, label, value, setter)
			TYPE_BOOL:
				_check(parent, label, value, setter)
			TYPE_INT:
				_slider(parent, label, row[2], row[3], row[4], value, func(v: float) -> void: setter.call(int(v)))
			TYPE_FLOAT:
				_slider(parent, label, row[2], row[3], row[4], value, setter)


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"SectionLabel"
	parent.add_child(l)


func _hint(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"HintLabel"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)


func _icon_button(icon: Texture2D, tip: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.icon = icon
	b.tooltip_text = tip
	b.expand_icon = true
	b.custom_minimum_size = Vector2(48, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	return b


func _button(parent: Control, text: String, on_press: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	parent.add_child(b)


func _slider(parent: Control, label: String, lo: float, hi: float, step: float, value: float, on_change: Callable) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	parent.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var name_label := Label.new()
	name_label.text = label
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)
	var value_label := Label.new()
	value_label.theme_type_variation = &"HintLabel"
	top.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	# Let values loaded from presets sit outside the slider's usual range.
	slider.allow_greater = true
	slider.allow_lesser = true
	slider.value = value
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(slider)
	var fmt := "%d" if step >= 1.0 else ("%.3f" if step < 0.01 else "%.2f")
	value_label.text = fmt % value
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = fmt % v
		on_change.call(v))


func _color(parent: Control, label: String, value: Color, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var button := ColorPickerButton.new()
	button.color = value
	button.edit_alpha = false
	button.custom_minimum_size = Vector2(72, 34)
	button.focus_mode = Control.FOCUS_NONE
	var picker := button.get_picker()
	picker.presets_visible = false
	picker.can_add_swatches = false
	picker.sampler_visible = false
	picker.color_modes_visible = false
	button.color_changed.connect(on_change)
	row.add_child(button)


func _check(parent: Control, label: String, value: bool, on_change: Callable) -> void:
	var c := CheckButton.new()
	c.text = label
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(on_change)
	parent.add_child(c)


func _option(parent: Control, label: String, items: Array, selected: int, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	for item in items:
		o.add_item(item)
	o.select(selected)
	o.item_selected.connect(func(i: int) -> void:
		on_change.call(i)
		_changed())
	row.add_child(o)


func _changed() -> void:
	edited.emit()


func _set_status(text: String) -> void:
	_status.text = text
