class_name MeshUtil
extends RefCounted
## Procedural mesh helpers shared by the glass, stands, props and creatures.
## Godot treats clockwise triangles as front-facing; the helpers here take an
## "outward" hint and fix the winding themselves.


## Adds a flat-shaded triangle facing `out`.
static func add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		ua: Vector2, ub: Vector2, uc: Vector2, out: Vector3) -> void:
	var normal := (c - a).cross(b - a)
	if normal.length_squared() < 1e-14:
		return
	if normal.dot(out) < 0.0:
		var tmp := b; b = c; c = tmp
		var tu := ub; ub = uc; uc = tu
		normal = -normal
	normal = normal.normalized()
	for pair in [[a, ua], [b, ub], [c, uc]]:
		st.set_normal(normal)
		st.set_uv(pair[1])
		st.add_vertex(pair[0])


## Adds a smooth-shaded triangle (per-vertex normals) facing `out`.
static func add_tri_smooth(st: SurfaceTool, p: Array, n: Array, uv: Array, out: Vector3) -> void:
	var face: Vector3 = (p[2] - p[0]).cross(p[1] - p[0])
	if face.length_squared() < 1e-14:
		return
	var order := [0, 1, 2] if face.dot(out) >= 0.0 else [0, 2, 1]
	for i in order:
		st.set_normal(n[i])
		st.set_uv(uv[i])
		st.add_vertex(p[i])


static func add_quad(st: SurfaceTool, p: Array, uv: Array, out: Vector3) -> void:
	add_tri(st, p[0], p[1], p[2], uv[0], uv[1], uv[2], out)
	add_tri(st, p[0], p[2], p[3], uv[0], uv[2], uv[3], out)


## Direction around the Y axis for side `i` of `sides`, offset by half a side
## so a flat face points toward +Z.
static func ring_dir(i: int, sides: int) -> Vector3:
	var a := TAU * (float(i) + 0.5) / sides
	return Vector3(sin(a), 0.0, cos(a))


## Revolves a (radius, y) profile around the Y axis.
## Open profiles should start and end on the axis (r = 0); pass `closed` for a
## loop that doesn't touch the axis (e.g. a ring's cross-section).
## `flat` gives faceted shading (one normal per face).
static func revolve(profile: PackedVector2Array, sides: int, flat: bool, closed := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	var seg_count := n if closed else n - 1
	var normals2d := _profile_normals(profile, closed)
	var total := 0.0
	for j in seg_count:
		total += profile[j].distance_to(profile[(j + 1) % n])
	var v := 0.0
	for j in seg_count:
		var p := profile[j]
		var q := profile[(j + 1) % n]
		var v2 := v + p.distance_to(q) / maxf(total, 1e-6)
		var seg := q - p
		var seg_normal := Vector2(seg.y, -seg.x).normalized()
		for i in sides:
			var d0 := ring_dir(i, sides)
			var d1 := ring_dir(i + 1, sides)
			var a0 := d0 * p.x + Vector3(0, p.y, 0)
			var a1 := d1 * p.x + Vector3(0, p.y, 0)
			var b0 := d0 * q.x + Vector3(0, q.y, 0)
			var b1 := d1 * q.x + Vector3(0, q.y, 0)
			var mid := (d0 + d1).normalized()
			var out := mid * seg_normal.x + Vector3(0, seg_normal.y, 0)
			var u0 := float(i) / sides
			var u1 := float(i + 1) / sides
			var uvs := [Vector2(u0, 1 - v), Vector2(u1, 1 - v), Vector2(u1, 1 - v2), Vector2(u0, 1 - v2)]
			if flat:
				add_quad(st, [a0, a1, b1, b0], uvs, out)
			else:
				var np := normals2d[j]
				var nq := normals2d[(j + 1) % n]
				var n_a0 := (d0 * np.x + Vector3(0, np.y, 0)).normalized()
				var n_a1 := (d1 * np.x + Vector3(0, np.y, 0)).normalized()
				var n_b0 := (d0 * nq.x + Vector3(0, nq.y, 0)).normalized()
				var n_b1 := (d1 * nq.x + Vector3(0, nq.y, 0)).normalized()
				add_tri_smooth(st, [a0, a1, b1], [n_a0, n_a1, n_b1], [uvs[0], uvs[1], uvs[2]], out)
				add_tri_smooth(st, [a0, b1, b0], [n_a0, n_b1, n_b0], [uvs[0], uvs[2], uvs[3]], out)
		v = v2
	return st.commit()


## Outward 2D normals at each profile point (averaged from its segments).
static func _profile_normals(profile: PackedVector2Array, closed: bool) -> PackedVector2Array:
	var n := profile.size()
	var out := PackedVector2Array()
	out.resize(n)
	for j in n:
		var prev := profile[(j - 1 + n) % n] if (closed or j > 0) else profile[j]
		var next := profile[(j + 1) % n] if (closed or j < n - 1) else profile[j]
		var t := (next - prev)
		var nn := Vector2(t.y, -t.x).normalized()
		if nn == Vector2.ZERO:
			nn = Vector2(0, 1)
		out[j] = nn
	return out


## A box stretched between two points (legs, beams), tapering from w0 to w1.
static func add_beam(st: SurfaceTool, from: Vector3, to: Vector3, w0: float, w1: float) -> void:
	var axis := (to - from).normalized()
	var side := axis.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = axis.cross(Vector3.RIGHT)
	side = side.normalized()
	var up := side.cross(axis).normalized()
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	var a: Array[Vector3] = []
	var b: Array[Vector3] = []
	for c in corners:
		a.append(from + (side * c.x + up * c.y) * w0 * 0.5)
		b.append(to + (side * c.x + up * c.y) * w1 * 0.5)
	var center := (from + to) * 0.5
	for i in 4:
		var k := (i + 1) % 4
		var out := ((a[i] + a[k] + b[i] + b[k]) * 0.25 - center)
		add_quad(st, [a[i], a[k], b[k], b[i]], [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], out)
	add_quad(st, [a[0], a[1], a[2], a[3]], [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN], -axis)
	add_quad(st, [b[0], b[1], b[2], b[3]], [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN], axis)


## Merges primitive meshes into one, tagging every vertex with a part id in
## UV2.x (shaders use it to colour body / accent / detail parts differently).
## parts: Array of [Mesh, Transform3D, part_id].
static func merge_parts(parts: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for part in parts:
		var mesh: Mesh = part[0]
		var xf: Transform3D = part[1]
		var id: float = part[2]
		var arrays := mesh.surface_get_arrays(0)
		var base := verts.size()
		var nb := xf.basis.inverse().transposed()
		for p in arrays[Mesh.ARRAY_VERTEX]:
			verts.append(xf * p)
			uv2.append(Vector2(id, 0))
		for nrm in arrays[Mesh.ARRAY_NORMAL]:
			norms.append((nb * nrm).normalized())
		var src_idx = arrays[Mesh.ARRAY_INDEX]
		if src_idx == null or src_idx.is_empty():
			for i in arrays[Mesh.ARRAY_VERTEX].size():
				idx.append(base + i)
		else:
			# Mirrored transforms flip winding; undo that.
			var flip := xf.basis.determinant() < 0.0
			for t in range(0, src_idx.size(), 3):
				idx.append(base + src_idx[t])
				idx.append(base + src_idx[t + (2 if flip else 1)])
				idx.append(base + src_idx[t + (1 if flip else 2)])
	var out := [] as Array
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = norms
	out[Mesh.ARRAY_TEX_UV2] = uv2
	out[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return m
