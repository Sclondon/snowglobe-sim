class_name GlobeSerpent
extends Node3D
## Long wriggly things: a snake slithering over the floor, a Chinese-style
## dragon undulating through the air, or a floppy noodle with googly eyes.
## Each has a simulated spine (the head steers, the body follows its path and
## flops about under gravity and shaking) drawn as one tube bent along it in
## serpent.gdshader, plus a head with eyes (and horns, whiskers, legs or a
## flicking tongue, depending on the style).

const KIND := "serpent"
const SETTINGS: Array[String] = ["style", "count", "body_length", "thickness", "color", "color2", "speed"]
const STYLE_NAMES := ["Snake", "Dragon", "Noodle"]
const EDITOR_ROWS := [
	["style", "Kind", STYLE_NAMES],
	["count", "How many", 1, 3, 1],
	["body_length", "Length", 1.0, 4.5, 0.05],
	["thickness", "Thickness", 0.02, 0.12, 0.002],
	["color", "Colour"],
	["color2", "Pattern / belly colour"],
	["speed", "Speed", 0.05, 1.0, 0.01],
]
const SHADER := preload("res://shaders/serpent.gdshader")

enum Style { SNAKE, DRAGON, NOODLE }
const DEFAULTS := {
	Style.SNAKE: {"body_length": 2.2, "thickness": 0.05, "color": Color(0.24, 0.5, 0.18), "color2": Color(0.86, 0.74, 0.28), "speed": 0.35},
	Style.DRAGON: {"body_length": 3.2, "thickness": 0.065, "color": Color(0.78, 0.12, 0.08), "color2": Color(0.96, 0.74, 0.22), "speed": 0.5},
	Style.NOODLE: {"body_length": 2.6, "thickness": 0.045, "color": Color(0.98, 0.87, 0.55), "color2": Color(0.92, 0.74, 0.42), "speed": 0.22},
}

@export var style := Style.SNAKE:
	set(v): style = v; _queue_build()
@export_range(1, 3, 1) var count := 1:
	set(v): count = v; _queue_build()
## Body length, in globe radii.
@export_range(1.0, 4.5, 0.05) var body_length := 2.2:
	set(v): body_length = v; _queue_build()
## Body radius, in globe radii.
@export_range(0.02, 0.12, 0.002) var thickness := 0.05:
	set(v): thickness = v; _queue_build()
@export var color := Color(0.24, 0.5, 0.18):
	set(v): color = v; _apply_look()
@export var color2 := Color(0.86, 0.74, 0.28):
	set(v): color2 = v; _apply_look()
## Cruising speed, in globe radii per second.
@export_range(0.05, 1.0, 0.01) var speed := 0.35

const N := 40
const RINGS := 180
const SIDES := 12

class Serpent:
	var pts := PackedVector3Array()
	var prev := PackedVector3Array()
	var ups := PackedVector3Array()
	var head_vel := Vector3.ZERO
	var wander := Vector3.FORWARD
	var phase := 0.0
	var tongue_in := 1.0
	var mi: MeshInstance3D
	var mat: ShaderMaterial
	var head: Node3D
	var tongue: Node3D
	var pupils: Array[Node3D] = []
	var pupil_offset := Vector3.ZERO
	var legs: Array[Node3D] = []

var _globe: SnowGlobe
var _serpents: Array[Serpent] = []
var _tube: ArrayMesh
var _rng := RandomNumberGenerator.new()
var _build_queued := false
var _mats := {}


static func with_style(s: Style) -> GlobeSerpent:
	var g := GlobeSerpent.new()
	g.style = s
	g.apply_style_defaults()
	return g


func _init() -> void:
	add_to_group(&"globe_layer")


## Resets length, thickness, colours and speed to suit the current style.
func apply_style_defaults() -> void:
	for k in DEFAULTS[style]:
		set(k, DEFAULTS[style][k])


## The editor calls this when a dropdown row changes.
func editor_option_changed(prop: String) -> void:
	if prop == "style":
		apply_style_defaults()


func _ready() -> void:
	var n := get_parent()
	while n and not (n is SnowGlobe):
		n = n.get_parent()
	_globe = n as SnowGlobe
	if _globe == null:
		push_warning("GlobeSerpent must be inside a SnowGlobe.")
		return
	_rng.randomize()
	_tube = _make_tube()
	_globe.rebuilt.connect(_queue_build)
	_build()


func _queue_build() -> void:
	if _build_queued or not is_inside_tree() or _globe == null:
		return
	_build_queued = true
	_build.call_deferred()


func _mat(key: String, c: Color, rough := 0.4, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	if not _mats.has(key):
		_mats[key] = StandardMaterial3D.new()
	var m: StandardMaterial3D = _mats[key]
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = glow
	return m


func _apply_look() -> void:
	for s in _serpents:
		if s.mat:
			s.mat.set_shader_parameter("color", color)
			s.mat.set_shader_parameter("color2", color2)
	if _mats.has("accent"):
		(_mats["accent"] as StandardMaterial3D).albedo_color = color2
	if _mats.has("body"):
		(_mats["body"] as StandardMaterial3D).albedo_color = color


func _build() -> void:
	_build_queued = false
	if _globe == null:
		return
	for c in get_children():
		c.queue_free()
	_serpents.clear()
	var R := _globe.globe_radius
	var L := body_length * R
	var seg := L / (N - 1)
	var shape := _globe.get_container()
	for k in count:
		var s := Serpent.new()
		# Start somewhere on the floor, heading off in a random direction.
		var a := _rng.randf() * TAU
		var rr := _rng.randf_range(0.0, shape.floor_radius * 0.4)
		var head := Vector3(sin(a) * rr, 0, cos(a) * rr)
		head.y = _globe.get_floor_height(head.x, head.z) + thickness * R
		if style == Style.DRAGON:
			head.y += R * 0.5
		var dir := Vector3(sin(a + 2.0), 0, cos(a + 2.0))
		s.wander = dir
		s.phase = _rng.randf() * TAU
		for i in N:
			# Coiled loosely behind the head so it fits in the globe.
			var ang := float(i) * seg / (R * 0.35)
			var p := head - (dir * cos(ang * 0.5) + dir.cross(Vector3.UP) * sin(ang * 0.5)) * float(i) * seg * 0.45
			p = _keep_inside(p, thickness * R)[0]
			s.pts.append(p)
			s.prev.append(p)
			s.ups.append(Vector3.UP)
		s.mat = ShaderMaterial.new()
		s.mat.shader = SHADER
		s.mat.set_shader_parameter("style", int(style))
		s.mat.set_shader_parameter("body_length", L)
		s.mat.set_shader_parameter("radius", thickness * R)
		s.mi = MeshInstance3D.new()
		s.mi.mesh = _tube
		s.mi.material_override = s.mat
		s.mi.custom_aabb = GlobeParticles.glass_aabb(_globe)
		add_child(s.mi)
		_make_head(s)
		_serpents.append(s)
	_apply_look()
	_update_shapes()


## A tube of RINGS rings: unit circle in VERTEX.xy, 0..1 along in UV.x.
func _make_tube() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for r in RINGS + 1:
		var t := float(r) / RINGS
		for k in SIDES:
			var a := TAU * k / SIDES
			var c := Vector3(sin(a), cos(a), 0)
			verts.append(c)
			norms.append(c)
			uvs.append(Vector2(t, float(k) / SIDES))
	for r in RINGS:
		for k in SIDES:
			var a := r * SIDES + k
			var b := r * SIDES + (k + 1) % SIDES
			var c := a + SIDES
			var d := b + SIDES
			idx.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 14
	m.rings = 8
	return m


func _cone(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = r
	m.height = h
	m.radial_segments = 8
	m.rings = 1
	return m


func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## Head decorations, in units of the head radius, facing +Z.
func _make_head(s: Serpent) -> void:
	s.head = Node3D.new()
	add_child(s.head)
	var black := _mat("pupil", Color(0.02, 0.02, 0.02), 0.2)
	var accent := _mat("accent", color2, 0.35, 0.4)
	match style:
		Style.SNAKE:
			var eye := _mat("snake_eye", Color(0.95, 0.78, 0.15), 0.15, 0.0, 0.15)
			for side in [-1.0, 1.0]:
				_part(s.head, _sphere(0.26), eye, Vector3(side * 0.62, 0.4, 0.35))
				_part(s.head, _sphere(0.2), black, Vector3(side * 0.75, 0.44, 0.42), Vector3.ZERO, Vector3(0.35, 1.1, 0.5))
			# Forked tongue, flicked out now and then.
			s.tongue = Node3D.new()
			s.tongue.position = Vector3(0, -0.15, 0.9)
			s.head.add_child(s.tongue)
			var red := _mat("tongue", Color(0.8, 0.08, 0.12), 0.4)
			var stem := CylinderMesh.new()
			stem.top_radius = 0.035
			stem.bottom_radius = 0.035
			stem.height = 0.9
			stem.radial_segments = 6
			_part(s.tongue, stem, red, Vector3(0, 0, 0.45), Vector3(PI * 0.5, 0, 0))
			for side in [-1.0, 1.0]:
				var fork := CylinderMesh.new()
				fork.top_radius = 0.0
				fork.bottom_radius = 0.03
				fork.height = 0.35
				fork.radial_segments = 5
				_part(s.tongue, fork, red, Vector3(side * 0.08, 0, 1.0), Vector3(PI * 0.5, side * 0.45, 0))
			s.tongue.visible = false
		Style.DRAGON:
			var white := _mat("eye_white", Color(1.0, 0.95, 0.75), 0.2, 0.0, 0.2)
			for side in [-1.0, 1.0]:
				_part(s.head, _sphere(0.26), white, Vector3(side * 0.6, 0.45, 0.3))
				_part(s.head, _sphere(0.13), black, Vector3(side * 0.72, 0.5, 0.42))
				# Antler-ish horns sweeping back.
				_part(s.head, _cone(0.14, 1.1), accent, Vector3(side * 0.4, 0.95, -0.35), Vector3(-1.0, 0, side * -0.35))
				_part(s.head, _cone(0.08, 0.5), accent, Vector3(side * 0.62, 1.2, -0.2), Vector3(-0.3, 0, side * -1.0))
				# Long whiskers drooping back from the snout.
				var whisker := CylinderMesh.new()
				whisker.top_radius = 0.0
				whisker.bottom_radius = 0.04
				whisker.height = 2.4
				whisker.radial_segments = 5
				_part(s.head, whisker, accent, Vector3(side * 1.0, -0.25, 0.1), Vector3(1.9, 0, side * 0.9))
			# Four little legs along the body.
			var leg_mesh := CylinderMesh.new()
			leg_mesh.top_radius = 0.28
			leg_mesh.bottom_radius = 0.18
			leg_mesh.height = 1.4
			leg_mesh.radial_segments = 6
			var body := _mat("body", color, 0.4, 0.2)
			for k in 4:
				var leg := Node3D.new()
				add_child(leg)
				_part(leg, leg_mesh, body, Vector3(0, -0.7, 0))
				for c in 3:
					_part(leg, _cone(0.09, 0.45), accent, Vector3((c - 1) * 0.16, -1.4, 0.18), Vector3(PI * 0.5, 0, 0))
				s.legs.append(leg)
		Style.NOODLE:
			var white := _mat("eye_white", Color(1.0, 1.0, 1.0), 0.15)
			for side in [-1.0, 1.0]:
				_part(s.head, _sphere(0.75), white, Vector3(side * 0.6, 0.85, 0.3))
				var pupil := Node3D.new()
				pupil.position = Vector3(side * 0.6, 0.85, 0.3)
				s.head.add_child(pupil)
				_part(pupil, _sphere(0.33), black, Vector3(0, 0, 0.55))
				s.pupils.append(pupil)


func _physics_process(delta: float) -> void:
	if _globe == null or _serpents.is_empty() or delta <= 0.0:
		return
	var R := _globe.globe_radius
	var inv := _globe.global_basis.orthonormalized().inverse()
	var up := inv * Vector3.UP
	var fling := -(inv * _globe.linear_acceleration)
	var agitation := _globe.agitation
	var r := thickness * R
	var L := body_length * R
	var seg := L / (N - 1)
	var ground := style != Style.DRAGON
	var g := R * 2.5
	for s in _serpents:
		s.phase += delta * (1.0 + agitation * 2.0)
		# --- Head: wander, slither / undulate, stay inside. ---
		var head := s.pts[0]
		var w := s.wander + Vector3(_rng.randf() - 0.5, (_rng.randf() - 0.5) * (0.0 if ground else 0.7), _rng.randf() - 0.5) * delta * 3.0
		if ground:
			w -= up * w.dot(up)
		var avoid := _avoid_walls(head, r * 3.0 + R * 0.15)
		# Turn away from the glass rather than pressing against it.
		w += avoid * delta * 2.0
		if ground:
			w -= up * w.dot(up)
		w = w.normalized() if w.length_squared() > 1e-6 else Vector3.FORWARD
		s.wander = w
		var steer := w + avoid
		var side := up.cross(w).normalized()
		match style:
			Style.SNAKE:
				steer += side * sin(s.phase * 5.0) * 0.7
			Style.NOODLE:
				steer += side * sin(s.phase * 2.5) * 1.0
			Style.DRAGON:
				steer += up * sin(s.phase * 1.7) * 0.6 + side * sin(s.phase * 1.1) * 0.4
		var spd := speed * R * (1.0 + agitation * 2.5)
		var on_floor := head.y <= _globe.get_floor_height(head.x, head.z) + r * 1.15
		var hv := s.head_vel
		if not ground or on_floor:
			var desired := steer.normalized() * spd
			if ground:
				desired -= up * desired.dot(up)
			var steer_v := hv
			if ground:
				steer_v -= up * steer_v.dot(up)
			var change := (desired - steer_v).limit_length(spd * 4.0 * delta)
			hv += change
		if ground:
			hv -= up * g * delta
		else:
			hv *= exp(-1.5 * delta)
		hv += fling * 0.12 * delta
		head += hv * delta
		var kept := _keep_inside(head, r)
		if kept[1] and ground:
			# Landed: stop falling.
			var n: Vector3 = up
			var vn := hv.dot(n)
			if vn < 0.0:
				hv -= n * vn
		head = kept[0]
		s.head_vel = hv
		s.pts[0] = head
		s.prev[0] = head

		# --- Body: verlet, then follow the one in front. ---
		var damp := 0.96 if ground else 0.9
		var grav := -up * (g if ground else 0.0) + fling * 0.12
		for i in range(1, N):
			var p := s.pts[i]
			var v := (p - s.prev[i]) * damp
			s.prev[i] = p
			s.pts[i] = p + v + grav * delta * delta
		for it in 2:
			for i in range(1, N):
				var d := s.pts[i] - s.pts[i - 1]
				var dl := d.length()
				if dl > 1e-6:
					s.pts[i] = s.pts[i - 1] + d / dl * seg
				var k := _keep_inside(s.pts[i], r * 0.9)
				s.pts[i] = k[0]
				if k[1] and ground:
					# Friction on the floor: the body drags rather than slides.
					s.prev[i] = s.prev[i].lerp(s.pts[i], 0.35)

		# Belly-down frames along the spine.
		for i in N:
			var t := (s.pts[i] - s.pts[mini(i + 1, N - 1)]) if i < N - 1 else (s.pts[i - 1] - s.pts[i])
			t = t.normalized() if t.length_squared() > 1e-10 else Vector3.FORWARD
			var u := up - t * up.dot(t)
			if u.length_squared() < 1e-4:
				u = s.ups[maxi(i - 1, 0)]
			s.ups[i] = u.normalized()
	_update_shapes()


func _update_shapes() -> void:
	var R := _globe.globe_radius
	var hr := thickness * R * (1.0 if style == Style.NOODLE else 1.3)
	for s in _serpents:
		s.mat.set_shader_parameter("spine", s.pts)
		s.mat.set_shader_parameter("spine_up", s.ups)
		var fwd := (s.pts[0] - s.pts[1]).normalized()
		var u := s.ups[0]
		var right := u.cross(fwd).normalized()
		if right.length_squared() < 0.5:
			continue
		u = fwd.cross(right)
		var hb := Basis(right, u, fwd).scaled(Vector3.ONE * hr)
		s.head.transform = Transform3D(hb, s.pts[0] - fwd * hr)
		if s.tongue:
			s.tongue_in -= get_physics_process_delta_time()
			if s.tongue_in <= 0.0:
				s.tongue.visible = not s.tongue.visible
				s.tongue_in = _rng.randf_range(0.15, 0.3) if s.tongue.visible else _rng.randf_range(0.8, 3.0)
			s.tongue.scale = Vector3(1, 1, 0.6 + 0.4 * absf(sin(s.phase * 25.0)))
		if not s.pupils.is_empty():
			# Googly: the pupils lag and rattle with the motion.
			var lag := -(s.head_vel * hb.orthonormalized()) / maxf(R, 1e-3) * 0.15
			s.pupil_offset = s.pupil_offset.lerp(Vector3(clampf(lag.x, -0.2, 0.2), clampf(lag.y - 0.08, -0.2, 0.2), 0), 0.2)
			for p in s.pupils:
				p.rotation = Vector3(-s.pupil_offset.y * 2.0, s.pupil_offset.x * 2.0, 0)
		for k in s.legs.size():
			var i := 8 if k < 2 else 21
			var side := -1.0 if k % 2 == 0 else 1.0
			var t := (s.pts[i - 1] - s.pts[i + 1]).normalized()
			var lu := s.ups[i]
			var lr := lu.cross(t).normalized()
			var paddle := sin(s.phase * 6.0 + k * 1.6) * 0.6
			var b := Basis(lr, lu, t).rotated(lr, paddle)
			b = b.rotated(t, side * 0.5)
			var r := thickness * R
			s.legs[k].transform = Transform3D(b.scaled(Vector3.ONE * r * 0.55), s.pts[i] + lr * side * r * 0.8 - lu * r * 0.2)


## Keeps a point inside the glass and above the floor: [point, touched floor].
func _keep_inside(p: Vector3, r: float) -> Array:
	var shape := _globe.get_container()
	var gc := _globe.glass_center
	var ly := clampf(p.y - gc.y, shape.y_min + r, shape.y_max - r)
	p.y = gc.y + ly
	var wall := maxf(shape.radius_at(ly) * shape.radius_factor(p.x, p.z) - r, 0.0)
	var rr := Vector2(p.x, p.z).length()
	if rr > wall:
		p.x *= wall / maxf(rr, 1e-5)
		p.z *= wall / maxf(rr, 1e-5)
	var fh := _globe.get_floor_height(p.x, p.z) + r
	var floor_hit := p.y <= fh + 1e-4
	if p.y < fh:
		p.y = fh
	return [p, floor_hit]


func _avoid_walls(p: Vector3, margin: float) -> Vector3:
	var shape := _globe.get_container()
	var gc := _globe.glass_center
	var ly := clampf(p.y - gc.y, shape.y_min + 1e-3, shape.y_max - 1e-3)
	var wall := shape.radius_at(ly) * shape.radius_factor(p.x, p.z)
	var rr := Vector2(p.x, p.z).length()
	var steer := Vector3.ZERO
	if rr > wall - margin and rr > 1e-5:
		steer -= Vector3(p.x, 0, p.z) / rr * (rr - (wall - margin)) / margin * 3.0
	if style == Style.DRAGON:
		var top := gc.y + shape.y_max
		var fh := _globe.get_floor_height(p.x, p.z)
		if p.y > top - margin:
			steer.y -= 3.0
		if p.y < fh + margin * 1.5:
			steer.y += 3.0
	return steer


## Dynamite: everyone goes flying.
func blast(origin: Vector3, strength: float) -> void:
	var R := _globe.globe_radius
	for s in _serpents:
		for i in N:
			var d := s.pts[i] - origin
			var k := strength * R * 0.04 / (1.0 + d.length() / R * 3.0)
			s.prev[i] -= d.normalized() * k
		s.head_vel += (s.pts[0] - origin).normalized() * strength * R * 2.0
