class_name CreatureMeshes
extends RefCounted
## Simple-shape creature models, one merged mesh per body type. Swimmers,
## fliers and ants are 1 unit long along +Z (forward); people are 1 unit
## tall along +Y. Walkers have their feet at y = 0.
##
## UV2.x tags parts for creature.gdshader: 0 = body (per-creature colour),
## 1 = accent, 2 = detail.

const BODY := 0
const ACCENT := 1
const DETAIL := 2

static var _cache := {}


static func get_mesh(body: CreatureSpecies.Body) -> ArrayMesh:
	if not _cache.has(body):
		match body:
			CreatureSpecies.Body.BUTTERFLY: _cache[body] = _butterfly()
			CreatureSpecies.Body.ANT: _cache[body] = _ant()
			CreatureSpecies.Body.PERSON: _cache[body] = _person()
			_: _cache[body] = _sea_monkey()
	return _cache[body]


static func _sea_monkey() -> ArrayMesh:
	var parts := []
	parts.append([_capsule(0.12, 0.72), _xf(Vector3(0, 0, 0), Vector3(PI * 0.5, 0, 0)), BODY])
	parts.append([_sphere(0.15), _xf(Vector3(0, 0.01, 0.36)), BODY])
	parts.append([_sphere(1.0), _xf(Vector3(0, 0, -0.44), Vector3.ZERO, Vector3(0.025, 0.15, 0.17)), ACCENT])
	for side in [-1.0, 1.0]:
		parts.append([_sphere(0.045), _xf(Vector3(side * 0.08, 0.07, 0.46)), DETAIL])
		parts.append([_cyl(0.008, 0.012, 0.22), _xf(Vector3(side * 0.06, 0.14, 0.52), Vector3(0.9, 0, side * -0.4)), ACCENT])
		# Little paddling legs along the belly.
		for k in 3:
			parts.append([_cyl(0.01, 0.012, 0.12), _xf(Vector3(side * 0.09, -0.1, 0.12 - k * 0.13), Vector3(0, 0, side * 0.9)), ACCENT])
	return MeshUtil.merge_parts(parts)


static func _butterfly() -> ArrayMesh:
	var parts := []
	parts.append([_capsule(0.035, 0.45), _xf(Vector3.ZERO, Vector3(PI * 0.5, 0, 0)), DETAIL])
	for side in [-1.0, 1.0]:
		parts.append([_sphere(1.0), _xf(Vector3(side * 0.3, 0, 0.07), Vector3(0, side * -0.25, 0), Vector3(0.3, 0.012, 0.22)), BODY])
		parts.append([_sphere(1.0), _xf(Vector3(side * 0.21, -0.005, -0.14), Vector3(0, side * 0.35, 0), Vector3(0.2, 0.012, 0.15)), ACCENT])
		parts.append([_cyl(0.005, 0.006, 0.2), _xf(Vector3(side * 0.04, 0.05, 0.3), Vector3(1.1, 0, side * -0.35)), DETAIL])
	return MeshUtil.merge_parts(parts)


static func _ant() -> ArrayMesh:
	var parts := []
	var y := 0.16
	parts.append([_sphere(1.0), _xf(Vector3(0, y + 0.02, -0.28), Vector3.ZERO, Vector3(0.17, 0.14, 0.24)), BODY])
	parts.append([_sphere(1.0), _xf(Vector3(0, y, 0.0), Vector3.ZERO, Vector3(0.08, 0.07, 0.13)), BODY])
	parts.append([_sphere(1.0), _xf(Vector3(0, y + 0.02, 0.2), Vector3.ZERO, Vector3(0.11, 0.1, 0.11)), BODY])
	for side in [-1.0, 1.0]:
		for k in 3:
			var z := 0.08 - k * 0.08
			# Leg from the thorax out and down to the ground.
			parts.append([_cyl(0.012, 0.012, 0.3), _xf(Vector3(side * 0.13, y * 0.5, z), Vector3(0, 0, side * 1.0)), DETAIL])
		parts.append([_cyl(0.006, 0.008, 0.2), _xf(Vector3(side * 0.05, y + 0.1, 0.33), Vector3(0.9, 0, side * -0.5)), DETAIL])
	return MeshUtil.merge_parts(parts)


static func _person() -> ArrayMesh:
	var parts := []
	for side in [-1.0, 1.0]:
		parts.append([_cyl(0.055, 0.06, 0.42), _xf(Vector3(side * 0.07, 0.21, 0)), DETAIL])
		parts.append([_capsule(0.045, 0.36), _xf(Vector3(side * 0.19, 0.6, 0)), BODY])
		parts.append([_sphere(0.018), _xf(Vector3(side * 0.04, 0.95, 0.105)), DETAIL])
	parts.append([_capsule(0.13, 0.44), _xf(Vector3(0, 0.62, 0)), BODY])
	parts.append([_sphere(0.12), _xf(Vector3(0, 0.93, 0)), ACCENT])
	return MeshUtil.merge_parts(parts)


static func _xf(pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return Transform3D(Basis.from_euler(rot).scaled(scl), pos)


static func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 12
	s.rings = 6
	return s


static func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 10
	c.rings = 3
	return c


static func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 6
	c.rings = 1
	return c
