class_name GlassShape
extends RefCounted
## The shape of a globe's glass, as a (radius, y) profile revolved around the
## Y axis. Everything that needs to know "where is the inside" uses this: the
## glass mesh, the fill under the floor, and the particle / creature
## simulations, which look radii up in a table (`radius_at`) so containment
## costs the same for every shape.
##
## Coordinates are glass-local: the origin is the shape's centre (the lens
## centre for the glass shader), +Y up.

enum Kind { SPHERE, TUBE, DIAMOND, EGG, HOURGLASS, BOX, PYRAMID }

const KIND_NAMES := ["Sphere", "Tube", "Diamond", "Egg", "Hourglass", "Box", "Pyramid"]
## A good floor level for each kind (used when the shape is changed).
const DEFAULT_FLOOR_DEPTH := [0.6, 0.7, 0.4, 0.6, 0.75, 0.88, 0.85]
const LUT_SIZE := 64

var kind: Kind
## Outline from the bottom (on the axis) to the top (on the axis).
var profile := PackedVector2Array()
var sides := 64
var flat_shaded := false
## For flat-sided shapes the table holds the corner radius; the walls are
## closer in between corners (see radius_factor).
var _half_sector := 0.0
var _apothem := 1.0
var y_min := 0.0
var y_max := 0.0
var max_radius := 0.0
## Glass-local Y of the floor, and the glass radius there.
var floor_y := 0.0
var floor_radius := 0.0
## Radius and dr/dy sampled evenly from y_min to y_max (LUT_SIZE + 1 entries).
var lut_r := PackedFloat32Array()
var lut_slope := PackedFloat32Array()
var lut_step := 1.0


## size: overall radius; width/height: proportions; facets: diamond sides;
## floor_depth: how far below the centre the floor is, as a fraction of the
## half-height.
static func create(p_kind: Kind, size: float, width: float, height: float, facets: int, floor_depth: float) -> GlassShape:
	var s := GlassShape.new()
	s.kind = p_kind
	var unit := _unit_profile(p_kind)
	var rx := size * width
	var ry := size * height
	for p in unit:
		s.profile.append(Vector2(p.x * rx, p.y * ry))
	s.flat_shaded = p_kind in [Kind.DIAMOND, Kind.BOX, Kind.PYRAMID]
	s.sides = 64
	if p_kind == Kind.DIAMOND:
		s.sides = clampi(facets, 3, 32)
	elif s.flat_shaded:
		s.sides = 4
	if s.flat_shaded:
		s._half_sector = PI / s.sides
		s._apothem = cos(s._half_sector)
	s._build_lut()
	s.floor_y = lerpf(0.0, s.y_min, clampf(floor_depth, 0.0, 0.95))
	s.floor_radius = s.radius_at(s.floor_y)
	return s


static func _unit_profile(k: Kind) -> PackedVector2Array:
	var pts := PackedVector2Array()
	match k:
		Kind.SPHERE, Kind.EGG:
			var n := 40
			for i in n + 1:
				var a := -PI * 0.5 + PI * i / n
				var y := sin(a)
				var r := cos(a) * ((1.0 - 0.18 * y) if k == Kind.EGG else 1.0)
				pts.append(Vector2(maxf(r, 0.0), y))
			pts[0].x = 0.0
			pts[n].x = 0.0
		Kind.TUBE:
			# Flat bottom (doubled corner keeps the edge crisp), straight
			# wall, rounded top.
			pts.append_array([Vector2(0, -1), Vector2(1, -1), Vector2(1, -1)])
			var n := 14
			for i in n + 1:
				var a := PI * 0.5 * i / n
				pts.append(Vector2(cos(a), 0.45 + 0.55 * sin(a)))
			pts[pts.size() - 1].x = 0.0
		Kind.DIAMOND:
			# Pointed pavilion, girdle, crown, flat table.
			pts.append_array([Vector2(0, -1), Vector2(1, 0.15), Vector2(1, 0.25), Vector2(0.62, 0.6), Vector2(0.62, 0.6), Vector2(0, 0.6)])
		Kind.HOURGLASS:
			# Two bulbs joined by a narrow neck, with flat ends.
			var n := 40
			pts.append(Vector2(0, -1))
			for i in n + 1:
				var y := -1.0 + 2.0 * i / n
				pts.append(Vector2(0.16 + 0.84 * pow(sin(absf(y) * PI * 0.55), 0.7), y))
			pts.append(Vector2(0, 1))
		Kind.BOX:
			pts.append_array([Vector2(0, -1), Vector2(1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(1, 1), Vector2(0, 1)])
		Kind.PYRAMID:
			pts.append_array([Vector2(0, -1), Vector2(1, -1), Vector2(1, -1), Vector2(0, 0.9)])
	return pts


func _build_lut() -> void:
	y_min = INF
	y_max = -INF
	max_radius = 0.0
	for p in profile:
		y_min = minf(y_min, p.y)
		y_max = maxf(y_max, p.y)
		max_radius = maxf(max_radius, p.x)
	lut_step = (y_max - y_min) / LUT_SIZE
	lut_r.resize(LUT_SIZE + 1)
	lut_slope.resize(LUT_SIZE + 1)
	for i in LUT_SIZE + 1:
		lut_r[i] = _profile_radius(y_min + i * lut_step)
	for i in LUT_SIZE + 1:
		var a := lut_r[maxi(i - 1, 0)]
		var b := lut_r[mini(i + 1, LUT_SIZE)]
		var span := float(mini(i + 1, LUT_SIZE) - maxi(i - 1, 0)) * lut_step
		lut_slope[i] = (b - a) / span


## Widest radius of the outline at height y (exact, from the profile).
func _profile_radius(y: float) -> float:
	var best := 0.0
	for j in profile.size() - 1:
		var p := profile[j]
		var q := profile[j + 1]
		var lo := minf(p.y, q.y)
		var hi := maxf(p.y, q.y)
		if y < lo - 1e-6 or y > hi + 1e-6:
			continue
		if hi - lo < 1e-6:
			best = maxf(best, maxf(p.x, q.x))
		else:
			best = maxf(best, lerpf(p.x, q.x, (y - p.y) / (q.y - p.y)))
	return best


## Radius of the inside at glass-local height y (from the table; 0 outside).
func radius_at(y: float) -> float:
	if y <= y_min or y >= y_max:
		return 0.0
	var f := (y - y_min) / lut_step
	var i := mini(int(f), LUT_SIZE - 1)
	return lerpf(lut_r[i], lut_r[i + 1], f - i)


## Widest the glass gets anywhere below glass-local height y.
func widest_below(y: float) -> float:
	var best := 0.0
	for i in LUT_SIZE + 1:
		if y_min + i * lut_step <= y:
			best = maxf(best, lut_r[i])
	return best


func slope_at(y: float) -> float:
	var f := clampf((y - y_min) / lut_step, 0.0, LUT_SIZE)
	var i := mini(int(f), LUT_SIZE - 1)
	return lerpf(lut_slope[i], lut_slope[i + 1], f - i)


## For flat-sided shapes, how far the wall is at this direction relative to
## the corner radius (1 at a corner, cos(pi/sides) mid-face); 1 when round.
func radius_factor(x: float, z: float) -> float:
	if not flat_shaded:
		return 1.0
	# Face centres sit at multiples of the sector angle from +Z (see
	# MeshUtil.ring_dir, which puts corners half a sector off).
	var phi := fposmod(atan2(x, z) + _half_sector, _half_sector * 2.0) - _half_sector
	return _apothem / cos(phi)


## Whether glass-local point p is inside with at least `margin` to spare.
func contains(p: Vector3, margin := 0.0) -> bool:
	if p.y < y_min + margin or p.y > y_max - margin:
		return false
	return Vector2(p.x, p.z).length() <= radius_at(p.y) * radius_factor(p.x, p.z) - margin


## Random glass-local point inside, at least `margin` from the glass and
## above `min_y`.
func random_point(rng: RandomNumberGenerator, margin: float, min_y: float) -> Vector3:
	for attempt in 40:
		var p := Vector3(rng.randf_range(-max_radius, max_radius), rng.randf_range(maxf(y_min, min_y), y_max), rng.randf_range(-max_radius, max_radius))
		if p.y > min_y and contains(p, margin):
			return p
	return Vector3(0, maxf(min_y + margin, floor_y + margin), 0)


## First point where a glass-local ray enters the shape, or null.
func raycast(origin: Vector3, dir: Vector3) -> Variant:
	var extent := Vector3(max_radius, maxf(-y_min, y_max), max_radius).length()
	var b := origin.dot(dir)
	var disc := b * b - (origin.length_squared() - extent * extent)
	if disc < 0.0:
		return null
	var t0 := maxf(-b - sqrt(disc), 0.0)
	var t1 := -b + sqrt(disc)
	if t1 < 0.0:
		return null
	var steps := 96
	var prev := t0
	for i in steps + 1:
		var t := lerpf(t0, t1, float(i) / steps)
		if contains(origin + dir * t):
			# Refine the crossing.
			var lo := prev
			var hi := t
			for k in 8:
				var mid := (lo + hi) * 0.5
				if contains(origin + dir * mid):
					hi = mid
				else:
					lo = mid
			return origin + dir * hi
		prev = t
	return null


func build_mesh() -> ArrayMesh:
	return MeshUtil.revolve(profile, sides, flat_shaded)


## Solid filling the glass below the floor (seen through the glass when
## there's no stand hiding it). `inset` shrinks it slightly inside the glass.
func build_lower_fill(inset := 0.985) -> ArrayMesh:
	var pts := PackedVector2Array()
	for j in profile.size():
		var p := profile[j]
		if p.y >= floor_y:
			if j > 0:
				var q := profile[j - 1]
				var t := (floor_y - q.y) / maxf(p.y - q.y, 1e-6)
				pts.append(Vector2(lerpf(q.x, p.x, t) * inset, floor_y))
			break
		pts.append(Vector2(p.x * inset, p.y))
	pts.append(Vector2(0, floor_y))
	return MeshUtil.revolve(pts, sides, flat_shaded)
