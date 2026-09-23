class_name AppUI
extends CanvasLayer
## On-screen UI: icon buttons, hints and the live editor panel (F11 still
## toggles fullscreen on desktop).
##
## Built for phones as much as desktop. UI size follows the device pixel ratio
## (so it isn't tiny on high-DPI phones), the editor is a side panel in
## landscape and a bottom sheet in portrait, and `view_rect_changed` tells the
## camera which part of the screen is still free so it can keep the globe there.

signal shake_pressed
signal inspect_pressed
signal inside_pressed
signal add_globe_pressed
## The editor asked to take the selected globe off the shelf.
signal remove_globe_requested
## Something the session should remember changed (main.gd saves it).
signal save_requested
## The part of the screen not covered by UI, in 0..1 screen fractions.
signal view_rect_changed(rect: Rect2)

## Extra multiplier on the automatic UI scale.
@export_range(0.5, 2.0, 0.05) var ui_scale_multiplier := 1.0
## Fraction of a portrait screen the editor sheet takes up.
@export_range(0.3, 0.8) var portrait_sheet_height := 0.5
## Keep the 3D view at or below about this many pixels (helps phones with
## very high-resolution screens).
@export var max_3d_pixels := 2_400_000
## Seconds the control hints stay up before fading.
@export var hint_duration := 7.0

const MARGIN := 10.0
const ICON_EDIT := preload("res://ui/icons/edit.svg")
const ICON_SHAKE := preload("res://ui/icons/shake.svg")
const ICON_INSPECT := preload("res://ui/icons/inspect.svg")
const ICON_PUT_BACK := preload("res://ui/icons/put_back.svg")
const ICON_ADD := preload("res://ui/icons/add.svg")
const ICON_INSIDE := preload("res://ui/icons/inside.svg")
const ACCENT := Color(0.62, 0.78, 1.0)

## The globe the editor works on (the selected one); set via set_globe().
var globe: SnowGlobe
var editor_open := false
## True while the editor's Props tab is open: dragging inside the globe moves props.
var props_editing := false

var _root: Control
var _panel: GlobeEditorPanel
var _edit_button: Button
var _shake_button: Button
var _inspect_button: Button
var _add_button: Button
var _inside_button: Button
var _top_buttons: Array[Button] = []
var _hint: Label
var _hint_tween: Tween
var _mode := 0
var _autosave_in := -1.0
var _touch := false
var _fps: Label


func _ready() -> void:
	_touch = DisplayServer.is_touchscreen_available()
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = _make_theme()
	add_child(_root)

	_hint = Label.new()
	_hint.theme_type_variation = &"OverlayHint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hint)

	_inside_button = _tool_button(ICON_INSIDE, "Look from inside (V)", inside_pressed.emit)
	_add_button = _tool_button(ICON_ADD, "Add a globe", add_globe_pressed.emit)
	_edit_button = _tool_button(ICON_EDIT, "Edit globe (E)", toggle_editor)
	# Laid out right-to-left from the top-right corner.
	_top_buttons = [_edit_button, _add_button, _inside_button]
	_shake_button = _tool_button(ICON_SHAKE, "Shake (Space)", shake_pressed.emit, &"BigButton")
	_inspect_button = _tool_button(ICON_INSPECT, "Inspect (I)", inspect_pressed.emit, &"BigButton")

	_panel = GlobeEditorPanel.new()
	_panel.visible = false
	_panel.remove_globe_requested.connect(remove_globe_requested.emit)
	_panel.close_requested.connect(toggle_editor)
	_panel.edited.connect(func() -> void: _autosave_in = 1.0)
	_panel.props_tab_toggled.connect(func(active: bool) -> void: props_editing = active)
	_root.add_child(_panel)

	# Frame-rate readout for testing on phones: add ?fps to the page URL.
	if _wants_fps():
		_fps = Label.new()
		_fps.theme_type_variation = &"OverlayHint"
		_fps.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_root.add_child(_fps)

	get_window().size_changed.connect(_layout)
	_layout.call_deferred()
	set_mode(0)


func _process(delta: float) -> void:
	if _fps:
		_fps.text = "%d fps" % Engine.get_frames_per_second()
	if _autosave_in > 0.0:
		_autosave_in -= delta
		if _autosave_in <= 0.0:
			_save_session()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				toggle_editor()
			KEY_F11:
				toggle_fullscreen()


# --- Public -------------------------------------------------------------------

func toggle_editor() -> void:
	editor_open = not editor_open
	_panel.visible = editor_open
	if editor_open:
		_panel.refresh()
	else:
		_save_session()
	_layout()


func toggle_fullscreen() -> void:
	var mode := DisplayServer.window_get_mode()
	var full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


## Points the editor at a globe (the selected one).
func set_globe(g: SnowGlobe) -> void:
	globe = g
	_panel.globe = g
	if editor_open:
		_panel.refresh()


## Whether another globe fits on the shelf.
func set_can_add(can_add: bool) -> void:
	_add_button.disabled = not can_add


## Called by main when the view mode changes (0 shelf, 1 inspect, 2 inside).
func set_mode(mode: int) -> void:
	_mode = mode
	var inspecting := mode == 1
	_inspect_button.icon = ICON_PUT_BACK if inspecting else ICON_INSPECT
	_inspect_button.tooltip_text = "Put back (Esc)" if inspecting else "Inspect (I)"
	_inside_button.icon = ICON_PUT_BACK if mode == 2 else ICON_INSIDE
	_inside_button.tooltip_text = "Back outside (V / Esc)" if mode == 2 else "Look from inside (V)"
	var text: String
	if mode == 2:
		text = "Drag to look around  ·  pinch to zoom  ·  shake the globe from in here!" if _touch 			else "Drag to look around  ·  wheel zooms  ·  Space shakes  ·  V or Esc to step out"
	elif inspecting:
		text = "Drag to turn the globe  ·  two fingers to look around  ·  pinch to bring it closer" if _touch \
			else "Drag to turn the globe  ·  right-drag to look around  ·  wheel to bring it closer  ·  Esc puts it back"
	else:
		text = "Drag a globe to swing or toss it  ·  drag elsewhere to look around  ·  pinch to zoom  ·  double-tap to inspect" if _touch \
			else "Drag a globe to swing or toss it  ·  drag elsewhere to orbit  ·  wheel zooms  ·  double-click inspects  ·  Space shakes  ·  E edits"
	_show_hint(text)


# --- Layout -------------------------------------------------------------------

func _ui_scale(window_px: Vector2) -> float:
	var s := maxf(DisplayServer.screen_get_scale(), minf(window_px.x, window_px.y) / 800.0)
	return clampf(s * ui_scale_multiplier, 1.0, 4.0)


func _layout() -> void:
	var win := get_window()
	var px := Vector2(win.size)
	if px.x < 1.0 or px.y < 1.0:
		return
	# With canvas_items + expand stretching, a base size of window/scale
	# gives a UI scale of exactly `ui_scale`, whatever the aspect ratio.
	var ui_scale := _ui_scale(px)
	win.content_scale_size = Vector2i((px / ui_scale).round())
	var size := px / ui_scale
	get_viewport().scaling_3d_scale = clampf(sqrt(max_3d_pixels / (px.x * px.y)), 0.5, 1.0)

	var portrait := size.x < size.y
	var free := Rect2(Vector2.ZERO, size)
	if editor_open:
		if portrait:
			var h := roundf(size.y * portrait_sheet_height)
			_panel.position = Vector2(0, size.y - h)
			_panel.size = Vector2(size.x, h)
			free = Rect2(0, 0, size.x, size.y - h)
		else:
			var w := clampf(size.x * 0.38, 320.0, 440.0)
			_panel.position = Vector2(size.x - w, 0)
			_panel.size = Vector2(w, size.y)
			free = Rect2(0, 0, size.x - w, size.y)

	# Edit in the top-right corner; Shake and Inspect in the bottom corners of
	# whatever part of the screen the editor leaves free.
	_edit_button.visible = not editor_open
	var top_size := Vector2.ZERO
	var x := free.end.x - MARGIN
	for b in _top_buttons:
		if not b.visible:
			continue
		b.size = Vector2.ZERO
		var bs := b.get_combined_minimum_size()
		x -= bs.x
		b.position = Vector2(x, MARGIN)
		x -= 8.0
		top_size = Vector2(free.end.x - MARGIN - x, bs.y)
	for b in [_shake_button, _inspect_button]:
		b.size = Vector2.ZERO
	var corner := MARGIN * 1.5
	var shake_size := _shake_button.get_combined_minimum_size()
	var inspect_size := _inspect_button.get_combined_minimum_size()
	_shake_button.position = Vector2(free.position.x + corner, free.end.y - shake_size.y - corner)
	_inspect_button.position = Vector2(free.end.x - inspect_size.x - corner, free.end.y - inspect_size.y - corner)

	var hint_width := minf(free.size.x - top_size.x - MARGIN * 3.0, 520.0)
	if hint_width < 180.0:
		# Not enough room beside the buttons: put the hint under them.
		_hint.position = Vector2(MARGIN, MARGIN * 2.0 + top_size.y)
		hint_width = free.size.x - MARGIN * 2.0
	else:
		_hint.position = Vector2(MARGIN, MARGIN)
	_hint.size = Vector2(hint_width, 0)

	if _fps:
		_fps.position = Vector2(free.position.x + MARGIN, free.end.y - shake_size.y - corner - 28.0)
	view_rect_changed.emit(Rect2(free.position / size, free.size / size))


func _show_hint(text: String) -> void:
	_hint.text = text
	_hint.modulate.a = 1.0
	if _hint_tween:
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(hint_duration)
	_hint_tween.tween_property(_hint, "modulate:a", 0.0, 1.5)


func _save_session() -> void:
	_autosave_in = -1.0
	save_requested.emit()


func _tool_button(icon: Texture2D, tip: String, on_press: Callable, variation := &"OverlayButton") -> Button:
	var b := Button.new()
	b.icon = icon
	b.tooltip_text = tip
	b.expand_icon = true
	b.custom_minimum_size = Vector2.ONE * (64.0 if variation == &"BigButton" else 56.0)
	b.theme_type_variation = variation
	# No keyboard focus, so Space keeps shaking the globe after a click.
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(on_press)
	_root.add_child(b)
	return b


# --- Theme --------------------------------------------------------------------

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 16

	t.set_stylebox("panel", "PanelContainer", _box(Color(0.07, 0.08, 0.11, 0.94), 14, 14))

	for type in ["Button", "OptionButton", "MenuButton", "ColorPickerButton"]:
		t.set_stylebox("normal", type, _box(Color(1, 1, 1, 0.08), 10, 12, 9))
		t.set_stylebox("hover", type, _box(Color(1, 1, 1, 0.14), 10, 12, 9))
		t.set_stylebox("pressed", type, _box(Color(1, 1, 1, 0.22), 10, 12, 9))
		t.set_stylebox("disabled", type, _box(Color(1, 1, 1, 0.04), 10, 12, 9))
		t.set_stylebox("focus", type, StyleBoxEmpty.new())

	t.add_type(&"OverlayButton")
	t.set_type_variation(&"OverlayButton", &"Button")
	t.set_stylebox("normal", &"OverlayButton", _box(Color(0.07, 0.08, 0.11, 0.72), 12, 14, 10))
	t.set_stylebox("hover", &"OverlayButton", _box(Color(0.14, 0.16, 0.2, 0.85), 12, 14, 10))
	t.set_stylebox("pressed", &"OverlayButton", _box(Color(0.22, 0.25, 0.32, 0.9), 12, 14, 10))

	t.add_type(&"BigButton")
	t.set_type_variation(&"BigButton", &"OverlayButton")
	t.set_font_size("font_size", &"BigButton", 18)
	t.set_stylebox("normal", &"BigButton", _box(Color(0.07, 0.08, 0.11, 0.72), 32, 14, 14))
	t.set_stylebox("hover", &"BigButton", _box(Color(0.14, 0.16, 0.2, 0.85), 32, 14, 14))
	t.set_stylebox("pressed", &"BigButton", _box(Color(0.22, 0.25, 0.32, 0.9), 32, 14, 14))

	t.set_stylebox("normal", "LineEdit", _box(Color(1, 1, 1, 0.08), 10, 12, 9))
	t.set_stylebox("focus", "LineEdit", _box(Color(1, 1, 1, 0.12), 10, 12, 9))

	# Chunky slider for fingers.
	var track := _box(Color(1, 1, 1, 0.14), 4, 0, 3)
	var filled := _box(ACCENT.darkened(0.2), 4, 0, 3)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	var knob := _circle(26, Color(0.92, 0.95, 1.0))
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", _circle(26, Color(1, 1, 1)))
	t.set_constant("center_grabber", "HSlider", 1)

	t.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	t.set_stylebox("tab_selected", "TabContainer", _box(Color(1, 1, 1, 0.14), 8, 14, 8))
	t.set_stylebox("tab_unselected", "TabContainer", _box(Color(1, 1, 1, 0.0), 8, 14, 8))
	t.set_stylebox("tab_hovered", "TabContainer", _box(Color(1, 1, 1, 0.07), 8, 14, 8))

	t.add_type(&"HeaderLabel")
	t.set_type_variation(&"HeaderLabel", &"Label")
	t.set_font_size("font_size", &"HeaderLabel", 20)
	t.add_type(&"SectionLabel")
	t.set_type_variation(&"SectionLabel", &"Label")
	t.set_font_size("font_size", &"SectionLabel", 13)
	t.set_color("font_color", &"SectionLabel", ACCENT)
	t.add_type(&"HintLabel")
	t.set_type_variation(&"HintLabel", &"Label")
	t.set_font_size("font_size", &"HintLabel", 13)
	t.set_color("font_color", &"HintLabel", Color(0.75, 0.78, 0.85, 0.8))
	t.add_type(&"OverlayHint")
	t.set_type_variation(&"OverlayHint", &"Label")
	t.set_font_size("font_size", &"OverlayHint", 14)
	t.set_color("font_color", &"OverlayHint", Color(0.8, 0.83, 0.9, 0.8))
	t.set_color("font_outline_color", &"OverlayHint", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", &"OverlayHint", 4)
	return t


static func _box(color: Color, radius: int, margin_h: float, margin_v := -1.0) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(radius)
	b.content_margin_left = margin_h
	b.content_margin_right = margin_h
	b.content_margin_top = margin_v if margin_v >= 0.0 else margin_h
	b.content_margin_bottom = margin_v if margin_v >= 0.0 else margin_h
	b.anti_aliasing = true
	return b


static func _circle(diameter: int, color: Color) -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.82, 0.92])
	g.colors = PackedColorArray([color, color, Color(color, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = diameter
	tex.height = diameter
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


## Tells the editor which prop was picked in the globe.
func select_prop(index: int) -> void:
	if _panel:
		_panel.select_prop(index)


## Called after a prop was dragged, so the session autosaves.
func prop_moved() -> void:
	_autosave_in = 1.0


func _wants_fps() -> bool:
	if "--fps" in OS.get_cmdline_user_args():
		return true
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("location.search.indexOf('fps') >= 0", true))
	return false


## Index of the prop selected in the editor, or -1.
func get_selected_prop() -> int:
	return _panel.selected_prop if _panel and editor_open else -1
