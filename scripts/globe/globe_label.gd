class_name GlobeLabel
extends Node3D
## The name plaque on the front of a globe's base: a small brass card, tilted
## back like a museum label, with the globe's title engraved on it and "by
## Creator" underneath when there is one. Built by SnowGlobe; faces the
## globe's front (+Z).

const MAX_CHARS := 26
const TEXT_COLOR := Color(0.06, 0.035, 0.01)

var _card: MeshInstance3D
var _title: Label3D
var _creator: Label3D
static var _brass: StandardMaterial3D


func _init() -> void:
	name = "Plaque"
	if _brass == null:
		_brass = StandardMaterial3D.new()
		_brass.albedo_color = Color(0.48, 0.32, 0.12)
		_brass.metallic = 0.35
		_brass.roughness = 0.6
	_card = MeshInstance3D.new()
	_card.mesh = BoxMesh.new()
	_card.material_override = _brass
	_card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_card)
	_title = _make_label()
	_creator = _make_label()
	add_child(_title)
	add_child(_creator)


func _make_label() -> Label3D:
	var l := Label3D.new()
	l.font_size = 64
	l.outline_size = 0
	l.modulate = TEXT_COLOR
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


## Lays the plaque out for a globe: `front` is how far forward the base
## reaches (globe-local), `radius` the globe's size.
func build(title: String, creator: String, front: float, radius: float) -> void:
	title = _shorten(title)
	creator = _shorten(creator)
	visible = not title.is_empty()
	if not visible:
		return
	var w := clampf(radius * 1.0, 0.4, 1.0)
	var h := w * (0.34 if creator.is_empty() else 0.46)
	var thick := w * 0.035
	(_card.mesh as BoxMesh).size = Vector3(w, h, thick)
	# Lean back 55° from upright, bottom edge on the shelf far enough in front
	# of the base that the top edge clears it.
	var tilt := deg_to_rad(-55.0)
	var lean := Basis(Vector3.RIGHT, tilt)
	transform = Transform3D(lean, Vector3(0, 0.004, front + w * 0.05 + h * sin(-tilt)) + lean * Vector3(0, h * 0.5, 0))
	_card.position = Vector3.ZERO
	var face := thick * 0.5 + 0.002
	_title.text = title
	_title.pixel_size = _fit(title, w * 0.88, h * (0.34 if creator.is_empty() else 0.3))
	_title.position = Vector3(0, 0.0 if creator.is_empty() else h * 0.12, face)
	_creator.visible = not creator.is_empty()
	if _creator.visible:
		_creator.text = "by " + creator
		_creator.pixel_size = _fit(_creator.text, w * 0.85, h * 0.2)
		_creator.position = Vector3(0, -h * 0.22, face)


## Pixel size that fits `text` into a w × h box (at font_size 64).
func _fit(text: String, w: float, h: float) -> float:
	var by_height := h / 64.0
	var by_width := w / (maxf(float(text.length()), 1.0) * 0.56 * 64.0)
	return minf(by_height, by_width)


static func _shorten(s: String) -> String:
	s = s.strip_edges()
	if s.length() > MAX_CHARS:
		s = s.left(MAX_CHARS - 1) + "…"
	return s
