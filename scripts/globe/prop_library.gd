class_name PropLibrary
extends RefCounted
## Little scenery pieces for inside the globe, built from simple shapes.
## Built at the size they'd have in a globe of radius 1; SnowGlobe scales
## them. `radius` is the footprint creatures and particles steer around,
## `height` how tall that obstacle is.

const TYPES := {
	"pine": {"name": "Pine tree", "radius": 0.18, "height": 0.55, "color": "#21603a"},
	"round_tree": {"name": "Round tree", "radius": 0.18, "height": 0.5, "color": "#3f7d3a"},
	"snowman": {"name": "Snowman", "radius": 0.1, "height": 0.4, "color": "#f2f5fa"},
	"cabin": {"name": "Cabin", "radius": 0.2, "height": 0.36, "color": "#7a4a2a"},
	"rocks": {"name": "Rocks", "radius": 0.15, "height": 0.12, "color": "#6f6d68"},
	"coral": {"name": "Coral", "radius": 0.14, "height": 0.3, "color": "#e8664f"},
	"seaweed": {"name": "Seaweed", "radius": 0.07, "height": 0.45, "color": "#2f7d4f"},
	"cactus": {"name": "Cactus", "radius": 0.08, "height": 0.4, "color": "#4f8a3a"},
	"anthill": {"name": "Anthill", "radius": 0.17, "height": 0.13, "color": "#9a6a3a"},
	"lighthouse": {"name": "Lighthouse", "radius": 0.1, "height": 0.62, "color": "#e04040"},
}

static var _seaweed_shader: Shader


static func type_ids() -> Array:
	return TYPES.keys()


static func info(type: String) -> Dictionary:
	return TYPES.get(type, TYPES["pine"])


static func build(type: String, color: Color) -> Node3D:
	var root := Node3D.new()
	root.name = type.capitalize().replace(" ", "")
	match type:
		"round_tree": _round_tree(root, color)
		"snowman": _snowman(root, color)
		"cabin": _cabin(root, color)
		"rocks": _rocks(root, color)
		"coral": _coral(root, color)
		"seaweed": _seaweed(root, color)
		"cactus": _cactus(root, color)
		"anthill": _anthill(root, color)
		"lighthouse": _lighthouse(root, color)
		_: _pine(root, color)
	return root


# --- Builders -----------------------------------------------------------------

static func _pine(root: Node3D, color: Color) -> void:
	_add(root, _cyl(0.03, 0.04, 0.12, 8), _mat(Color(0.32, 0.2, 0.12)), Vector3(0, 0.06, 0))
	for i in 3:
		var w := 0.26 - 0.06 * i
		_add(root, _cyl(0.0, w, w * 1.5, 20), _mat(color), Vector3(0, 0.1 + 0.14 * i + w * 0.75, 0))


static func _round_tree(root: Node3D, color: Color) -> void:
	_add(root, _cyl(0.03, 0.045, 0.22, 8), _mat(Color(0.35, 0.22, 0.13)), Vector3(0, 0.11, 0))
	var leaf := _mat(color)
	_add(root, _sphere(0.16), leaf, Vector3(0, 0.33, 0))
	_add(root, _sphere(0.11), leaf, Vector3(0.1, 0.27, 0.05))
	_add(root, _sphere(0.1), leaf, Vector3(-0.09, 0.29, -0.04))


static func _snowman(root: Node3D, color: Color) -> void:
	var body := _mat(color, 0.9)
	_add(root, _sphere(0.1), body, Vector3(0, 0.09, 0))
	_add(root, _sphere(0.075), body, Vector3(0, 0.23, 0))
	_add(root, _sphere(0.055), body, Vector3(0, 0.34, 0))
	var coal := _mat(Color(0.05, 0.05, 0.05))
	for x in [-0.02, 0.02]:
		_add(root, _sphere(0.009), coal, Vector3(x, 0.355, 0.048))
	var nose := _add(root, _cyl(0.0, 0.012, 0.06, 8), _mat(Color(0.95, 0.45, 0.1)), Vector3(0, 0.34, 0.075))
	nose.rotation.x = PI * 0.5
	_add(root, _cyl(0.045, 0.045, 0.06, 16), coal, Vector3(0, 0.41, 0))
	_add(root, _cyl(0.07, 0.07, 0.008, 16), coal, Vector3(0, 0.385, 0))


static func _cabin(root: Node3D, color: Color) -> void:
	var walls := BoxMesh.new()
	walls.size = Vector3(0.3, 0.18, 0.24)
	_add(root, walls, _mat(color), Vector3(0, 0.09, 0))
	var roof := PrismMesh.new()
	roof.size = Vector3(0.36, 0.14, 0.3)
	_add(root, roof, _mat(Color(0.85, 0.88, 0.92)), Vector3(0, 0.25, 0))
	var door := BoxMesh.new()
	door.size = Vector3(0.06, 0.1, 0.01)
	_add(root, door, _mat(Color(0.25, 0.14, 0.08)), Vector3(0, 0.05, 0.121))
	var window := BoxMesh.new()
	window.size = Vector3(0.05, 0.05, 0.01)
	var glow := _mat(Color(1.0, 0.8, 0.4))
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.7, 0.3)
	glow.emission_energy_multiplier = 1.5
	_add(root, window, glow, Vector3(0.09, 0.1, 0.121))
	var chimney := BoxMesh.new()
	chimney.size = Vector3(0.04, 0.1, 0.04)
	_add(root, chimney, _mat(Color(0.4, 0.3, 0.28)), Vector3(0.08, 0.3, -0.04))


static func _rocks(root: Node3D, color: Color) -> void:
	var m := _mat(color, 0.95)
	var spots := [[Vector3(0, 0.04, 0), Vector3(0.1, 0.07, 0.08)], [Vector3(0.09, 0.03, 0.04), Vector3(0.06, 0.045, 0.05)], [Vector3(-0.07, 0.025, 0.06), Vector3(0.05, 0.035, 0.045)], [Vector3(-0.02, 0.02, -0.08), Vector3(0.045, 0.03, 0.04)]]
	for s in spots:
		var mesh := SphereMesh.new()
		mesh.radial_segments = 7
		mesh.rings = 4
		mesh.radius = 1.0
		mesh.height = 2.0
		var mi := _add(root, mesh, m, s[0])
		mi.scale = s[1]


static func _coral(root: Node3D, color: Color) -> void:
	var m := _mat(color, 0.7)
	var branches := [[Vector3(0, 0, 0), Vector3(0, 0, 0), 0.22], [Vector3(0.03, 0.08, 0), Vector3(0, 0, -0.6), 0.16], [Vector3(-0.03, 0.06, 0.01), Vector3(0.2, 0, 0.7), 0.15], [Vector3(0, 0.1, -0.03), Vector3(-0.6, 0, 0), 0.13]]
	for b in branches:
		var pivot := Node3D.new()
		pivot.position = b[0]
		pivot.rotation = b[1]
		root.add_child(pivot)
		var length: float = b[2]
		_add(pivot, _cyl(0.018, 0.028, length, 8), m, Vector3(0, length * 0.5, 0))
		_add(pivot, _sphere(0.03), m, Vector3(0, length, 0))


static func _seaweed(root: Node3D, color: Color) -> void:
	if _seaweed_shader == null:
		_seaweed_shader = Shader.new()
		_seaweed_shader.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 color : source_color;
void vertex() {
	float h = max(VERTEX.y, 0.0);
	VERTEX.x += sin(TIME * 1.6 + NODE_POSITION_WORLD.x * 7.0 + VERTEX.y * 5.0) * h * h * 0.6;
	VERTEX.z += cos(TIME * 1.2 + NODE_POSITION_WORLD.z * 7.0 + VERTEX.y * 4.0) * h * h * 0.4;
}
void fragment() {
	ALBEDO = color.rgb;
	ROUGHNESS = 0.6;
}
"""
	var m := ShaderMaterial.new()
	m.shader = _seaweed_shader
	m.set_shader_parameter("color", color)
	for i in 4:
		var blade := BoxMesh.new()
		var h := 0.3 + 0.04 * i
		blade.size = Vector3(0.035, h, 0.008)
		blade.subdivide_height = 8
		var mi := MeshInstance3D.new()
		# The sway shader bends by local height, so bake the blade with its
		# base at y = 0.
		mi.mesh = MeshUtil.merge_parts([[blade, Transform3D(Basis(), Vector3(0, h * 0.5, 0)), 0]])
		mi.material_override = m
		mi.position = Vector3((i - 1.5) * 0.03, 0, (i % 2) * 0.03)
		mi.rotation.y = i * 0.8
		root.add_child(mi)


static func _cactus(root: Node3D, color: Color) -> void:
	var m := _mat(color, 0.6)
	_add(root, _capsule(0.045, 0.36), m, Vector3(0, 0.18, 0))
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.07, 0.17 + (0.04 if side > 0 else 0.0), 0)
		root.add_child(arm)
		var elbow := _add(arm, _capsule(0.028, 0.08), m, Vector3.ZERO)
		elbow.rotation.z = PI * 0.5
		_add(arm, _capsule(0.028, 0.12), m, Vector3(side * 0.03, 0.05, 0))


static func _anthill(root: Node3D, color: Color) -> void:
	_add(root, _cyl(0.03, 0.17, 0.13, 20), _mat(color, 1.0), Vector3(0, 0.065, 0))
	_add(root, _cyl(0.02, 0.02, 0.005, 12), _mat(Color(0.08, 0.05, 0.03)), Vector3(0, 0.131, 0))


static func _lighthouse(root: Node3D, color: Color) -> void:
	var white := _mat(Color(0.95, 0.95, 0.93))
	var band := _mat(color)
	for i in 4:
		var r0 := 0.08 - i * 0.01
		_add(root, _cyl(r0 - 0.01, r0, 0.12, 16), band if i % 2 == 0 else white, Vector3(0, 0.06 + i * 0.12, 0))
	var lamp := _mat(Color(1.0, 0.9, 0.5))
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.85, 0.4)
	lamp.emission_energy_multiplier = 2.5
	_add(root, _cyl(0.035, 0.035, 0.06, 12), lamp, Vector3(0, 0.51, 0))
	_add(root, _cyl(0.0, 0.05, 0.06, 12), band, Vector3(0, 0.57, 0))


# --- Helpers ------------------------------------------------------------------

static func _add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _mat(color: Color, roughness := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


static func _cyl(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return c
