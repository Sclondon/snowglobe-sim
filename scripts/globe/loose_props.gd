class_name LooseProps
extends RefCounted
## Physics for a globe's loose props (balls, rings, frogs): they fall with the
## globe's gravity, get flung by its motion, bounce off the glass and floor,
## roll and tumble — and frogs hop about, wildly when the globe is shaken.
## Owned and stepped by SnowGlobe.

var nodes: Array[Node3D] = []
var types: PackedStringArray = []
var sizes := PackedFloat32Array()
var pos := PackedVector3Array()
var vel := PackedVector3Array()
var rot: Array[Quaternion] = []
var spin := PackedVector3Array()
var hop_in := PackedFloat32Array()
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func clear() -> void:
	nodes.clear()
	types.clear()
	for arr in [sizes, hop_in]:
		arr.resize(0)
	for arr in [pos, vel, spin]:
		arr.resize(0)
	rot.clear()


## Registers a prop node to simulate, starting at globe-local `at`.
func add(node: Node3D, type: String, size: float, at: Vector3, yaw: float) -> void:
	nodes.append(node)
	types.append(type)
	sizes.append(size)
	pos.append(at)
	vel.append(Vector3.ZERO)
	rot.append(Quaternion(Vector3.UP, yaw))
	spin.append(Vector3.ZERO)
	hop_in.append(_rng.randf_range(1.0, 4.0))


## Puts one back on its start spot at rest.
func reset(i: int, at: Vector3, yaw: float) -> void:
	if i < 0 or i >= pos.size():
		return
	pos[i] = at
	vel[i] = Vector3.ZERO
	spin[i] = Vector3.ZERO
	rot[i] = Quaternion(Vector3.UP, yaw)


func step(globe: SnowGlobe, delta: float, agitation: float) -> void:
	if nodes.is_empty():
		return
	var R := globe.globe_radius
	var shape := globe.get_container()
	var gc := globe.glass_center
	var inv := globe.global_basis.orthonormalized().inverse()
	var up := inv * Vector3.UP
	var fling := -(inv * globe.linear_acceleration)
	var water := globe.fill == SnowGlobe.Fill.WATER
	for i in nodes.size():
		var info := PropLibrary.info(types[i])
		var r := float(info["radius"]) * sizes[i] * 0.8
		var bounce := float(info.get("bounce", 0.3))
		var p := pos[i]
		var v := vel[i]
		v += (-up * R * 3.0 * (0.6 if water else 1.0) + fling * 0.14) * delta
		v *= exp(-(1.5 if water else 0.15) * delta)
		p += v * delta

		var touching := false
		var ly := clampf(p.y - gc.y, shape.y_min + r, shape.y_max - r)
		if ly != p.y - gc.y:
			v.y = -v.y * bounce
			touching = true
		p.y = gc.y + ly
		var wall := maxf(shape.radius_at(ly) * shape.radius_factor(p.x, p.z) - r - R * 0.02, 0.0)
		var rr := Vector2(p.x, p.z).length()
		if rr > wall and rr > 1e-5:
			var n := Vector3(p.x, 0, p.z) / rr
			p.x *= wall / rr
			p.z *= wall / rr
			var vn := v.dot(n)
			if vn > 0.0:
				v -= n * vn * (1.0 + bounce)
			touching = true
		var fh := globe.get_floor_height(p.x, p.z) + (r if types[i] != "frog" else 0.0)
		var on_floor := p.y <= fh + R * 0.005
		if p.y < fh:
			p.y = fh
			if v.y < 0.0:
				v.y = -v.y * bounce
			touching = true

		var s := spin[i]
		if touching:
			# Friction, and rolling spin from sliding along the floor.
			v.x *= exp(-(2.0 if types[i] == "ball" else 4.0) * delta)
			v.z *= exp(-(2.0 if types[i] == "ball" else 4.0) * delta)
			var roll_axis := up.cross(v)
			if roll_axis.length_squared() > 1e-8 and types[i] != "frog":
				s = s.lerp(roll_axis.normalized() * Vector2(v.x, v.z).length() / maxf(r, 1e-3), 0.3)
			else:
				s *= exp(-6.0 * delta)
		# Jolts set things spinning.
		if agitation > 0.5 and _rng.randf() < delta * 4.0:
			s += Vector3(_rng.randf() - 0.5, _rng.randf() - 0.5, _rng.randf() - 0.5) * agitation * 12.0

		if types[i] == "frog":
			hop_in[i] -= delta * (1.0 + agitation * 6.0)
			if on_floor and hop_in[i] <= 0.0:
				hop_in[i] = _rng.randf_range(1.5, 4.5)
				var dir := Vector3(_rng.randf() - 0.5, 0, _rng.randf() - 0.5).normalized()
				v += (up * 1.1 + dir * 0.5) * R * (1.0 + agitation) * (0.7 if water else 1.0)
				# Face where it's hopping.
				rot[i] = Quaternion(up, atan2(dir.x, dir.z))
			if on_floor:
				# Frogs land on their feet.
				var face := Basis(rot[i]).z
				face = (face - up * face.dot(up)).normalized()
				if face.length_squared() > 0.5:
					rot[i] = rot[i].slerp(Basis.looking_at(-face, up).get_rotation_quaternion(), minf(1.0, delta * 8.0))
				s *= exp(-10.0 * delta)
		if s.length_squared() > 1e-8:
			rot[i] = (Quaternion(s.normalized(), s.length() * delta) * rot[i]).normalized()
		pos[i] = p
		vel[i] = v
		spin[i] = s
		# Balls and rings are centred on p; frogs stand on it.
		nodes[i].transform = Transform3D(Basis(rot[i]).scaled(Vector3.ONE * sizes[i]), p)
