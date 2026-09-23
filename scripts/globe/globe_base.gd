class_name GlobeBase
extends RefCounted
## Builds what the glass stands on: a turned pedestal, a ring on legs, or
## nothing. Materials come from the caller (see SnowGlobe._update_materials).

enum Kind { PEDESTAL, LEGS, NONE, PLATFORM }
enum Finish { WOOD, METAL, CERAMIC, STONE }

const KIND_NAMES := ["Pedestal", "Legs & ring", "None", "Platform & legs"]
const FINISH_NAMES := ["Wood", "Metal", "Ceramic", "Stone"]
## Default (colour, accent) per finish, used when the finish is changed.
const FINISH_COLORS := [
	[Color(0.5, 0.3, 0.17), Color(0.24, 0.12, 0.06)],
	[Color(0.72, 0.73, 0.76), Color(0.4, 0.41, 0.44)],
	[Color(0.9, 0.87, 0.8), Color(0.35, 0.45, 0.6)],
	[Color(0.88, 0.87, 0.85), Color(0.35, 0.36, 0.4)],
]


## Pedestal: a faceted turned stand whose top is `top_r` wide at `height`.
## The trim band sits at 84–90% of the height (see trim_range()).
static func build_pedestal(sides: int, height: float, bottom_r: float, top_r: float, body: Material) -> Node3D:
	var profile := PackedVector2Array([
		Vector2(0, 0),
		Vector2(bottom_r, 0.0),
		Vector2(bottom_r, height * 0.12),
		Vector2(bottom_r * 0.95, height * 0.18),
		Vector2(top_r, height * 0.84),
		Vector2(top_r * 1.05, height * 0.84),
		Vector2(top_r * 1.05, height * 0.9),
		Vector2(top_r, height),
		Vector2(0, height),
	])
	var mi := MeshInstance3D.new()
	mi.name = "Pedestal"
	mi.mesh = MeshUtil.revolve(profile, sides, true)
	mi.material_override = body
	return mi


static func trim_range(height: float) -> Vector2:
	return Vector2(height * 0.84, height * 0.9)


## A flat slab the glass sits on, at height `top`, on legs at its corners.
static func build_platform(sides: int, top: float, radius: float, size: float, body: Material, trim: Material) -> Node3D:
	var root := Node3D.new()
	root.name = "Platform"
	var t := size * 0.07
	var slab := MeshInstance3D.new()
	slab.mesh = MeshUtil.revolve(PackedVector2Array([Vector2(0, top - t), Vector2(radius, top - t), Vector2(radius, top), Vector2(0, top)]), sides, true)
	slab.material_override = body
	root.add_child(slab)
	# A thin trim band round the slab's edge.
	var band := MeshInstance3D.new()
	band.mesh = MeshUtil.revolve(PackedVector2Array([Vector2(radius * 1.01, top - t * 0.65), Vector2(radius * 1.01, top - t * 0.35)]), sides, true)
	band.material_override = trim
	root.add_child(band)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foot_mesh := SphereMesh.new()
	foot_mesh.radius = size * 0.045
	foot_mesh.height = size * 0.045
	var legs := sides if sides <= 6 else 4
	for i in legs:
		var d := MeshUtil.ring_dir(i, legs)
		var from := d * radius * 0.85 + Vector3(0, top - t, 0)
		var to := d * radius * 0.95 + Vector3(0, size * 0.02, 0)
		MeshUtil.add_beam(st, from, to, size * 0.06, size * 0.045)
		var f := MeshInstance3D.new()
		f.mesh = foot_mesh
		f.position = to
		f.material_override = trim
		root.add_child(f)
	var leg_mi := MeshInstance3D.new()
	leg_mi.mesh = st.commit()
	leg_mi.material_override = body
	root.add_child(leg_mi)
	return root


## A ring hugging the glass at `ring_y` (radius `ring_r`) on `legs` splayed
## legs reaching the ground.
static func build_legs(legs: int, ring_y: float, ring_r: float, size: float, body: Material, trim: Material) -> Node3D:
	var root := Node3D.new()
	root.name = "Legs"
	var tube := size * 0.035

	# Ring: a torus (circle cross-section revolved).
	var cross := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		cross.append(Vector2(ring_r + tube + cos(a) * tube, ring_y + sin(a) * tube))
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = MeshUtil.revolve(cross, 48, false, true)
	ring.material_override = trim
	root.add_child(ring)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foot_mesh := SphereMesh.new()
	foot_mesh.radius = size * 0.05
	foot_mesh.height = size * 0.05
	for i in legs:
		var a := TAU * (float(i) + 0.5) / legs
		var dir := Vector3(sin(a), 0, cos(a))
		var top := dir * (ring_r + tube) + Vector3(0, ring_y, 0)
		var foot := dir * (ring_r + size * 0.28) + Vector3(0, size * 0.025, 0)
		MeshUtil.add_beam(st, top + Vector3(0, tube, 0), foot, size * 0.05, size * 0.035)
		var f := MeshInstance3D.new()
		f.mesh = foot_mesh
		f.position = foot
		f.material_override = trim
		root.add_child(f)
	var leg_mi := MeshInstance3D.new()
	leg_mi.name = "LegBeams"
	leg_mi.mesh = st.commit()
	leg_mi.material_override = body
	root.add_child(leg_mi)
	return root
