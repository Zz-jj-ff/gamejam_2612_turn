extends RefCounted
class_name HeadBuilder
## Procedural face / head generator.
##
## The skull is a vertical loft: for every height y a superellipse cross
## section is defined by (half width, front depth, back depth) through PCHIP
## interpolated profile curves.  Facial features are anisotropic gaussian
## blobs displaced along the analytic surface normal.  Nothing is imported;
## every number below is a design decision.
##
## Coordinates: y up, +z = face forward.  Head is roughly 0.25 m tall (chin to
## crown) so the whole bust reads at portrait distance.

const MB := preload("res://scripts/build/mesh_builder.gd")
const TAU := PI * 2.0

# ------------------------------------------------------------------ profile
# bottom (chin) -> top (crown)
const Y_BOTTOM := -0.0980
const Y_TOP := 0.1085
const P_Y := [
	-0.0980, -0.0955, -0.0915, -0.0865, -0.0805, -0.0725,
	-0.0625, -0.0510, -0.0370, -0.0200, -0.0020, 0.0180,
	0.0380, 0.0560, 0.0730, 0.0870, 0.0980, 0.1045, 0.1085,
]
const P_W := [
	0.0015, 0.0110, 0.0220, 0.0330, 0.0430, 0.0530,
	0.0610, 0.0675, 0.0725, 0.0760, 0.0775, 0.0775,
	0.0748, 0.0690, 0.0605, 0.0480, 0.0320, 0.0145, 0.0010,
]
const P_F := [
	0.0120, 0.0260, 0.0410, 0.0540, 0.0640, 0.0720,
	0.0785, 0.0830, 0.0860, 0.0878, 0.0882, 0.0865,
	0.0825, 0.0755, 0.0645, 0.0500, 0.0335, 0.0155, 0.0010,
]
const P_B := [
	0.0100, 0.0180, 0.0310, 0.0440, 0.0570, 0.0680,
	0.0780, 0.0860, 0.0925, 0.0975, 0.1000, 0.0990,
	0.0950, 0.0875, 0.0760, 0.0590, 0.0400, 0.0190, 0.0010,
]

const EX := 1.16  # superellipse exponent of the cross section

const HEAD_ROWS := 148
const HEAD_SEGS := 28

# ----------------------------------------------------------------- features
# [center, sigma, amplitude] — + pushes out along the base normal.
static var BLOBS := [
	# cheeks (youthful apples)
	[Vector3(0.048, -0.038, 0.071), Vector3(0.031, 0.027, 0.025), 0.0062],
	[Vector3(-0.048, -0.038, 0.071), Vector3(0.031, 0.027, 0.025), 0.0062],
	# cheekbone
	[Vector3(0.062, -0.016, 0.055), Vector3(0.021, 0.016, 0.026), 0.0024],
	[Vector3(-0.062, -0.016, 0.055), Vector3(0.021, 0.016, 0.026), 0.0024],
	# eye socket (wide, shallow bowl)
	[Vector3(0.0365, -0.018, 0.0825), Vector3(0.030, 0.018, 0.020), -0.0072],
	[Vector3(-0.0365, -0.018, 0.0825), Vector3(0.030, 0.018, 0.020), -0.0072],
	# brow ridge
	[Vector3(0.030, 0.004, 0.0845), Vector3(0.031, 0.013, 0.016), 0.0030],
	[Vector3(-0.030, 0.004, 0.0845), Vector3(0.031, 0.013, 0.016), 0.0030],
	# nasolabial softness
	[Vector3(0.0165, -0.0495, 0.0875), Vector3(0.0075, 0.010, 0.008), -0.0016],
	[Vector3(-0.0165, -0.0495, 0.0875), Vector3(0.0075, 0.010, 0.008), -0.0016],
	# under-eye softness
	[Vector3(0.035, -0.0305, 0.0820), Vector3(0.019, 0.0075, 0.012), 0.0020],
	[Vector3(-0.035, -0.0305, 0.0820), Vector3(0.019, 0.0075, 0.012), 0.0020],
	# philtrum groove
	[Vector3(0.0, -0.0468, 0.0905), Vector3(0.0052, 0.007, 0.006), -0.0015],
	# lips
	[Vector3(0.0, -0.0552, 0.0912), Vector3(0.0205, 0.0062, 0.009), 0.0036],
	[Vector3(0.0, -0.0642, 0.0912), Vector3(0.0188, 0.0078, 0.010), 0.0048],
	# mouth corners
	[Vector3(0.0182, -0.0595, 0.0860), Vector3(0.0068, 0.006, 0.007), -0.0020],
	[Vector3(-0.0182, -0.0595, 0.0860), Vector3(0.0068, 0.006, 0.007), -0.0020],
	# mentolabial crease + chin
	[Vector3(0.0, -0.0755, 0.0780), Vector3(0.016, 0.0075, 0.010), -0.0016],
	[Vector3(0.0, -0.0855, 0.0560), Vector3(0.016, 0.014, 0.015), 0.0052],
	# jaw corner
	[Vector3(0.052, -0.063, 0.030), Vector3(0.018, 0.016, 0.020), 0.0020],
	[Vector3(-0.052, -0.063, 0.030), Vector3(0.018, 0.016, 0.020), 0.0020],
	# temples (very soft hollow)
	[Vector3(0.071, 0.020, 0.038), Vector3(0.016, 0.022, 0.020), -0.0016],
	[Vector3(-0.071, 0.020, 0.038), Vector3(0.016, 0.022, 0.020), -0.0016],
]

static var _slopes: Array = []


# ---------------------------------------------------------------- utilities

static func _init_profile() -> void:
	if not _slopes.is_empty():
		return
	for arr in [P_W, P_F, P_B]:
		var n := P_Y.size()
		var m := []
		m.resize(n)
		for i in n:
			m[i] = 0.0
		var d := []
		d.resize(n - 1)
		for i in n - 1:
			d[i] = (arr[i + 1] - arr[i]) / (P_Y[i + 1] - P_Y[i])
		m[0] = d[0]
		m[n - 1] = d[n - 2]
		for i in range(1, n - 1):
			if d[i - 1] * d[i] <= 0.0:
				m[i] = 0.0
			else:
				var h0: float = P_Y[i] - P_Y[i - 1]
				var h1: float = P_Y[i + 1] - P_Y[i]
				var w1 := 2.0 * h1 + h0
				var w2 := h1 + 2.0 * h0
				m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
		_slopes.append(m)


static func _pchip(arr: Array, m: Array, x: float) -> float:
	var n := P_Y.size()
	if x <= P_Y[0]:
		return arr[0]
	if x >= P_Y[n - 1]:
		return arr[n - 1]
	var lo := 0
	var hi := n - 1
	while hi - lo > 1:
		var mid := (lo + hi) >> 1
		if P_Y[mid] <= x:
			lo = mid
		else:
			hi = mid
	var h: float = P_Y[hi] - P_Y[lo]
	var t: float = (x - float(P_Y[lo])) / h
	var t2: float = t * t
	var t3: float = t2 * t
	var h00: float = 2.0 * t3 - 3.0 * t2 + 1.0
	var h10: float = t3 - 2.0 * t2 + t
	var h01: float = -2.0 * t3 + 3.0 * t2
	var h11: float = t3 - t2
	return h00 * arr[lo] + h10 * h * m[lo] + h01 * arr[hi] + h11 * h * m[hi]


## (half width, front depth, back depth) at height y, after spec tweaks.
static func profile(y: float, sp: Dictionary) -> Vector3:
	_init_profile()
	var w := _pchip(P_W, _slopes[0], y)
	var f := _pchip(P_F, _slopes[1], y)
	var b := _pchip(P_B, _slopes[2], y)
	var jaw := float(sp.get("jaw", 1.0))
	var jaw_t := clampf((-y - 0.045) / 0.070, 0.0, 1.0)
	w *= lerpf(1.0, jaw, jaw_t * jaw_t * (3.0 - 2.0 * jaw_t))
	w *= float(sp.get("head_w", 1.0))
	f *= float(sp.get("face_depth", 1.0))
	b *= float(sp.get("head_depth", 1.0))
	return Vector3(maxf(w, 0.0), maxf(f, 0.0), maxf(b, 0.0))


static func base_point(y: float, phi: float, sp: Dictionary) -> Vector3:
	var pr := profile(y, sp)
	var sx := sin(phi)
	var cz := cos(phi)
	var ax := pow(absf(sx), EX)
	var az := pow(absf(cz), EX)
	var x := pr.x * signf(sx) * ax
	var z := (pr.y if cz >= 0.0 else pr.z) * signf(cz) * az
	return Vector3(x, y, z)


static func base_normal(y: float, phi: float, sp: Dictionary) -> Vector3:
	var e := 0.0015
	var dy := 0.0015
	var p0 := base_point(y, phi, sp)
	var pu := base_point(y, phi + e, sp)
	var pv := base_point(y + dy, phi, sp)
	var n := (pu - p0).cross(pv - p0)
	if n.length_squared() < 1e-14:
		return Vector3(sin(phi), 0.0, cos(phi)).normalized()
	return n.normalized()


static func blob_disp(p: Vector3, sp: Dictionary) -> float:
	var cheek := float(sp.get("cheek", 1.0))
	var d := 0.0
	for b in BLOBS:
		var c: Vector3 = b[0]
		var s: Vector3 = b[1]
		var a: float = b[2]
		var qx := (p.x - c.x) / s.x
		var qy := (p.y - c.y) / s.y
		var qz := (p.z - c.z) / s.z
		var q := qx * qx + qy * qy + qz * qz
		if q > 12.0:
			continue
		if absf(c.y + 0.042) < 0.012 and absf(c.x) > 0.02:
			a *= cheek
		d += a * exp(-0.5 * q)
	return d


static func surface_point(y: float, phi: float, sp: Dictionary) -> Vector3:
	var p := base_point(y, phi, sp)
	var n := base_normal(y, phi, sp)
	return p + n * blob_disp(p, sp)


## Surface at a front-view (x, y); used to lay decals / rims on the face.
static func surface_at(x: float, y: float, sp: Dictionary) -> Vector3:
	var pr := profile(y, sp)
	var w := maxf(pr.x, 1e-4)
	var t := clampf(absf(x) / w, 0.0, 0.9995)
	var spow := pow(t, 1.0 / EX)
	var phi := asin(clampf(spow, 0.0, 1.0))
	if x < 0.0:
		phi = -phi
	var p := base_point(y, phi, sp)
	var n := base_normal(y, phi, sp)
	return p + n * blob_disp(p, sp)


static func normal_at(x: float, y: float, sp: Dictionary) -> Vector3:
	var e := 0.0012
	var dx := surface_at(x + e, y, sp) - surface_at(x - e, y, sp)
	var dy := surface_at(x, y + e, sp) - surface_at(x, y - e, sp)
	var n := dx.cross(dy)
	if n.length_squared() < 1e-14:
		return Vector3.FORWARD
	return n.normalized()


# ------------------------------------------------------------------- shapes

static func build_head(sp: Dictionary, eye_specs: Array) -> ArrayMesh:
	var mb := MB.new()
	var rows := []
	var norms := []
	for r in HEAD_ROWS + 1:
		var y: float = lerpf(Y_BOTTOM + 0.0008, Y_TOP, float(r) / float(HEAD_ROWS))
		var prow := []
		var nrow := []
		for s in HEAD_SEGS:
			var phi := TAU * float(s) / float(HEAD_SEGS)
			prow.append(surface_point(y, phi, sp))
		rows.append(prow)
	# normals from displaced grid
	for r in HEAD_ROWS + 1:
		var nrow := []
		for s in HEAD_SEGS:
			var r0: int = maxi(r - 1, 0)
			var r1: int = mini(r + 1, HEAD_ROWS)
			var s0: int = (s - 1 + HEAD_SEGS) % HEAD_SEGS
			var s1: int = (s + 1) % HEAD_SEGS
			var du: Vector3 = rows[r][s1] - rows[r][s0]
			var dv: Vector3 = rows[r1][s] - rows[r0][s]
			var n := du.cross(dv)
			if n.length_squared() < 1e-14:
				n = Vector3(0.0, 1.0 if r == 0 else -1.0, 0.0)
			n = n.normalized()
			# force outward
			var c := Vector3(0.0, lerpf(Y_BOTTOM + 0.0008, Y_TOP, float(r) / float(HEAD_ROWS)) - 0.02, 0.0)
			if n.dot(rows[r][s] - c) < 0.0:
				n = -n
			nrow.append(n)
		norms.append(nrow)
	# Faceted shell: quads on the face are flat-shaded (hard panel surfaces),
	# the cranium / sides keep smooth normals under the hair.
	var cuts := []
	for es in eye_specs:
		cuts.append(_almond_poly(es["center"], es["a"] * 0.70, es["b"] * 0.74,
			es["side"], 0.0))
	for r in HEAD_ROWS:
		for s in HEAD_SEGS:
			var s1 := (s + 1) % HEAD_SEGS
			var p0: Vector3 = rows[r][s]
			var p1: Vector3 = rows[r][s1]
			var p2: Vector3 = rows[r + 1][s1]
			var p3: Vector3 = rows[r + 1][s]
			var mid := (p0 + p1 + p2 + p3) * 0.25
			var skip := false
			for poly in cuts:
				if _point_in_poly(Vector2(mid.x, mid.y), poly):
					skip = true
					break
			if skip:
				continue
			var phi := TAU * (float(s) + 0.5) / float(HEAD_SEGS)
			var front := absf(wrapf(phi, -PI, PI)) < 1.55
			var nrm: Vector3
			if front:
				var g := (p1 - p0).cross(p3 - p0)
				nrm = g.normalized() if g.length_squared() > 1e-14 else norms[r][s]
			var uv0 := Vector2(float(s) / float(HEAD_SEGS), float(r) / float(HEAD_ROWS))
			var uv1 := Vector2(float(s + 1) / float(HEAD_SEGS), float(r) / float(HEAD_ROWS))
			var uv2 := Vector2(float(s + 1) / float(HEAD_SEGS), float(r + 1) / float(HEAD_ROWS))
			var uv3 := Vector2(float(s) / float(HEAD_SEGS), float(r + 1) / float(HEAD_ROWS))
			var i0: int
			var i1: int
			var i2: int
			var i3: int
			if front:
				i0 = mb.add_vert(p0, nrm, uv0, Vector2(p0.x, p0.y))
				i1 = mb.add_vert(p1, nrm, uv1, Vector2(p1.x, p1.y))
				i2 = mb.add_vert(p2, nrm, uv2, Vector2(p2.x, p2.y))
				i3 = mb.add_vert(p3, nrm, uv3, Vector2(p3.x, p3.y))
			else:
				i0 = mb.add_vert(p0, norms[r][s], uv0, Vector2(p0.x, p0.y))
				i1 = mb.add_vert(p1, norms[r][s1], uv1, Vector2(p1.x, p1.y))
				i2 = mb.add_vert(p2, norms[r + 1][s1], uv2, Vector2(p2.x, p2.y))
				i3 = mb.add_vert(p3, norms[r + 1][s], uv3, Vector2(p3.x, p3.y))
			var g2: Vector3 = (nrm if front else
				(norms[r][s] + norms[r][s1] + norms[r + 1][s1] + norms[r + 1][s]).normalized())
			mb.add_quad(i0, i1, i2, i3, g2)
	return mb.commit("head")


# --------------------------------------------------------------------- eyes

static func eye_specs(sp: Dictionary) -> Array:
	var eye_x := 0.0368 * float(sp.get("eye_gap", 1.0))
	var eye_y := -0.0180 + float(sp.get("eye_raise", 0.0))
	var a := 0.0245 * float(sp.get("eye_size", 1.0))
	var b := 0.0132 * float(sp.get("eye_size", 1.0))
	var out := []
	for side in [1.0, -1.0]:
		var surf := surface_at(eye_x * side, eye_y, sp)
		var n := Vector3(0.235 * side, -0.015, 1.0).normalized()
		var up := Vector3.UP
		var u := (up - n * up.dot(n)).normalized()
		var r := u.cross(n).normalized()
		var center := surf
		out.append({
			"side": side, "center": center, "n": n, "u": u, "r": r,
			"a": a, "b": b, "eye_y": eye_y,
		})
	return out


static func _almond_poly(center: Vector3, a: float, b: float, side: float,
		scale: float) -> Array:
	var pts2d := [
		Vector2(-1.00, 0.00), Vector2(-0.84, 0.58), Vector2(-0.45, 0.94),
		Vector2(0.00, 1.00), Vector2(0.40, 0.90), Vector2(0.78, 0.62),
		Vector2(1.00, 0.28), Vector2(0.80, -0.26), Vector2(0.40, -0.60),
		Vector2(-0.05, -0.72), Vector2(-0.55, -0.66), Vector2(-0.90, -0.34),
	]
	var out := []
	for p in pts2d:
		out.append(Vector2(center.x + side * p.x * a * scale,
			center.y + p.y * b * scale))
	return out


static func almond_curve(a: float, b: float, side: float, scale: float,
		segments := 96) -> Array:
	# closed catmull-rom through the almond control points
	var pts2d := [
		Vector2(-1.00, 0.00), Vector2(-0.84, 0.58), Vector2(-0.45, 0.94),
		Vector2(0.00, 1.00), Vector2(0.40, 0.90), Vector2(0.78, 0.62),
		Vector2(1.00, 0.28), Vector2(0.80, -0.26), Vector2(0.40, -0.60),
		Vector2(-0.05, -0.72), Vector2(-0.55, -0.66), Vector2(-0.90, -0.34),
	]
	var out := []
	var n := pts2d.size()
	for i in segments:
		var f := float(i) / float(segments) * float(n)
		var k := int(f)
		var t := f - float(k)
		var p0: Vector2 = pts2d[(k - 1 + n) % n]
		var p1: Vector2 = pts2d[k % n]
		var p2: Vector2 = pts2d[(k + 1) % n]
		var p3: Vector2 = pts2d[(k + 2) % n]
		var q := 0.5 * ((2.0 * p1) + (-p0 + p2) * t \
			+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t \
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)
		out.append(Vector2(side * q.x * a * scale, q.y * b * scale))
	return out


static func _point_in_poly(p: Vector2, poly: Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var pi: Vector2 = poly[i]
		var pj: Vector2 = poly[j]
		if (pi.y > p.y) != (pj.y > p.y):
			var xint: float = (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x
			if p.x < xint:
				inside = not inside
		j = i
	return inside


## Mechanical eye.  A beveled almond bezel set into the face, a recessed
## smoked-optic plate, and an oval glowing iris ring.  No sclera, no lids,
## no lashes — this is an instrument, not an eyeball.
static func build_eye_unit(es: Dictionary, sp: Dictionary) -> Dictionary:
	var a: float = es["a"]
	var b: float = es["b"]
	var side: float = es["side"]
	var C: Vector3 = es["center"]
	var R: Vector3 = es["r"]
	var U: Vector3 = es["u"]
	var N: Vector3 = es["n"]
	var out := {}

	# ---------------------------------------------------------- bezel
	var outer := almond_curve(a, b, side, 1.085)
	var inner := almond_curve(a, b, side, 0.900)
	var bez := MB.new()
	var oi := []
	var ii := []
	for k in outer.size():
		var o2: Vector2 = outer[k]
		var wp := surface_at(C.x + o2.x, C.y + o2.y, sp)
		var wn := normal_at(C.x + o2.x, C.y + o2.y, sp)
		var d := wp - C
		var lp := Vector3(d.dot(R), d.dot(U), d.dot(N) + 0.0002)
		var ln := Vector3(wn.dot(R), wn.dot(U), wn.dot(N)).normalized()
		oi.append(bez.add_vert(lp, ln))
	for k in inner.size():
		var q: Vector2 = inner[k]
		ii.append(bez.add_vert(Vector3(q.x, q.y, 0.0029), N))
	for k in outer.size():
		var k1 := (k + 1) % outer.size()
		var c := (bez.V[oi[k]] + bez.V[oi[k1]] + bez.V[ii[k1]] + bez.V[ii[k]]) * 0.25
		bez.add_quad(oi[k], oi[k1], ii[k1], ii[k], c.normalized() + N * 0.3)
	# inner wall slopes down into the socket
	for k in inner.size():
		var k1 := (k + 1) % inner.size()
		var p0 := Vector3(inner[k].x, inner[k].y, 0.0029)
		var p1 := Vector3(inner[k1].x, inner[k1].y, 0.0029)
		var p2 := Vector3(inner[k1].x * 0.995, inner[k1].y * 0.995, 0.0006)
		var p3 := Vector3(inner[k].x * 0.995, inner[k].y * 0.995, 0.0006)
		var i0 := bez.add_vert(p0, -N)
		var i1 := bez.add_vert(p1, -N)
		var i2 := bez.add_vert(p2, -N)
		var i3 := bez.add_vert(p3, -N)
		bez.add_quad(i0, i1, i2, i3, -N)
	out["bezel"] = bez.commit("bezel")

	# ------------------------------------------------- smoked optic plate
	var lens := MB.new()
	var rings := 10
	var edge := almond_curve(a, b, side, 0.985)
	var lg := []
	for k in rings + 1:
		var sc := 1.0 - float(k) / float(rings) * 0.97
		var z := 0.0012 + 0.0005 * (1.0 - sc)
		var row := []
		for q in edge:
			row.append(Vector3(q.x * sc, q.y * sc, z))
		lg.append(row)
	for k in rings:
		for j in edge.size():
			var j1 := (j + 1) % edge.size()
			var i0 := lens.add_vert(lg[k][j], N, Vector2(lg[k][j].x / (a * 0.99), lg[k][j].y / (b * 0.99)))
			var i1 := lens.add_vert(lg[k][j1], N, Vector2(lg[k][j1].x / (a * 0.99), lg[k][j1].y / (b * 0.99)))
			var i2 := lens.add_vert(lg[k + 1][j1], N, Vector2(lg[k + 1][j1].x / (a * 0.99), lg[k + 1][j1].y / (b * 0.99)))
			var i3 := lens.add_vert(lg[k + 1][j], N, Vector2(lg[k + 1][j].x / (a * 0.99), lg[k + 1][j].y / (b * 0.99)))
			lens.add_quad(i0, i1, i2, i3, N)
	out["lens"] = lens.commit("lens")

	# ------------------------------------------------------- oval iris
	var rx := 0.0132 * float(sp.get("iris_size", 1.0))
	var ry := 0.0095 * float(sp.get("iris_size", 1.0))
	var ic := Vector2(-0.0008 * side, 0.0009)
	var iris := MB.new()
	var irings := 7
	var iseg := 56
	var ig := []
	for k in irings + 1:
		var rr := float(k) / float(irings)
		var z := 0.0019 + 0.0005 * (1.0 - rr * rr)
		var row := []
		for j in iseg:
			var ang := TAU * float(j) / float(iseg)
			row.append(Vector3(ic.x + cos(ang) * rx * rr,
				ic.y + sin(ang) * ry * rr, z))
		ig.append(row)
	for k in irings:
		for j in iseg:
			var j1 := (j + 1) % iseg
			var u0 := Vector2(cos(TAU * float(j) / iseg), sin(TAU * float(j) / iseg)) * (float(k) / irings)
			var u1 := Vector2(cos(TAU * float(j1) / iseg), sin(TAU * float(j1) / iseg)) * (float(k) / irings)
			var u2 := Vector2(cos(TAU * float(j1) / iseg), sin(TAU * float(j1) / iseg)) * (float(k + 1) / irings)
			var u3 := Vector2(cos(TAU * float(j) / iseg), sin(TAU * float(j) / iseg)) * (float(k + 1) / irings)
			var i0 := iris.add_vert(ig[k][j], N, u0)
			var i1 := iris.add_vert(ig[k][j1], N, u1)
			var i2 := iris.add_vert(ig[k + 1][j1], N, u2)
			var i3 := iris.add_vert(ig[k + 1][j], N, u3)
			iris.add_quad(i0, i1, i2, i3, N)
	out["iris"] = iris.commit("iris")
	out["iris_rx"] = rx
	out["iris_ry"] = ry

	# --------------------------------------------------- iris mount ring
	var mount := MB.new()
	var segs := 64
	var r0 := 1.0
	var r1 := 1.16
	for j in segs:
		var a0 := TAU * float(j) / segs
		var a1 := TAU * float(j + 1) / segs
		var pts := [
			Vector3(ic.x + cos(a0) * rx * r0, ic.y + sin(a0) * ry * r0, 0.00225),
			Vector3(ic.x + cos(a1) * rx * r0, ic.y + sin(a1) * ry * r0, 0.00225),
			Vector3(ic.x + cos(a1) * rx * r1, ic.y + sin(a1) * ry * r1, 0.00155),
			Vector3(ic.x + cos(a0) * rx * r1, ic.y + sin(a0) * ry * r1, 0.00155),
			Vector3(ic.x + cos(a0) * rx * r1, ic.y + sin(a0) * ry * r1, 0.00075),
			Vector3(ic.x + cos(a1) * rx * r1, ic.y + sin(a1) * ry * r1, 0.00075),
			Vector3(ic.x + cos(a1) * rx * r0, ic.y + sin(a1) * ry * r0, 0.00135),
			Vector3(ic.x + cos(a0) * rx * r0, ic.y + sin(a0) * ry * r0, 0.00135),
		]
		var ids := []
		for p in pts:
			var nn: Vector3 = (N + R * (p.x - ic.x) * 45.0 + U * (p.y - ic.y) * 45.0).normalized()
			ids.append(mount.add_vert(p, nn))
		mount.add_quad(ids[0], ids[1], ids[2], ids[3], N)
		mount.add_quad(ids[3], ids[2], ids[5], ids[4], N + R * 0.4)
		mount.add_quad(ids[5], ids[6], ids[7], ids[4], -N - R * 0.2)
		mount.add_quad(ids[6], ids[1], ids[0], ids[7], N)
	out["mount"] = mount.commit("mount")
	return out


static func _curve_at(points: Array, t: float) -> Vector2:
	var f := clampf(t, 0.0, 0.9999) * float(points.size() - 1)
	var i := int(f)
	var u := f - float(i)
	var a: Vector2 = points[i]
	var b: Vector2 = points[mini(i + 1, points.size() - 1)]
	return a.lerp(b, u)


## Swell-lock: closed leaf tube swept along a polyline.
## `widths` is the full width at each sample, `thickness` the half depth.
static func sweep_lock(points: Array, widths: Array, thickness: float,
		cross_segs := 10, normal_hint := Vector3.ZERO, col := Color.WHITE,
		taper_tip := true, phase := 0.0) -> ArrayMesh:
	var mb := MB.new()
	var n := points.size()
	if n < 2:
		return mb.commit("lock")
	var cs := cross_segs
	var rings := []
	var nrings := []
	var tangents := []
	for i in n:
		var t: Vector3
		if i == 0:
			t = (points[1] - points[0])
		elif i == n - 1:
			t = (points[n - 1] - points[n - 2])
		else:
			t = (points[i + 1] - points[i - 1])
		if t.length_squared() < 1e-12:
			t = Vector3.DOWN
		t = t.normalized()
		tangents.append(t)
	for i in n:
		var t: Vector3 = tangents[i]
		var hint: Vector3 = normal_hint
		if hint == Vector3.ZERO:
			hint = points[i] - Vector3(0.0, -0.02, -0.01)
			if hint.length_squared() < 1e-10:
				hint = Vector3.BACK
		var nrm: Vector3 = (hint - t * hint.dot(t))
		if nrm.length_squared() < 1e-10:
			nrm = t.cross(Vector3.RIGHT)
		nrm = nrm.normalized()
		var bnr: Vector3 = t.cross(nrm).normalized()
		var w: float = widths[i]
		var tt := thickness
		if taper_tip and i == n - 1:
			w = minf(w, 0.0004)
			tt = minf(tt, 0.00025)
		var row := []
		var nrow := []
		for j in cs:
			var ang := TAU * float(j) / float(cs)
			var bo := cos(ang) * w
			var no := sin(ang) * tt
			var p: Vector3 = points[i] + bnr * bo + nrm * no
			var nn: Vector3 = (bnr * (bo / maxf(w * w, 1e-9)) + nrm * (no / maxf(tt * tt, 1e-9))).normalized()
			row.append(p)
			nrow.append(nn)
		rings.append(row)
		nrings.append(nrow)
	for i in n - 1:
		var v0 := float(i) / float(n - 1)
		var v1 := float(i + 1) / float(n - 1)
		for j in cs:
			var j1 := (j + 1) % cs
			var i0 := mb.add_vert(rings[i][j], nrings[i][j], Vector2(0.0, v0), Vector2(phase, v0), col)
			var i1 := mb.add_vert(rings[i][j1], nrings[i][j1], Vector2(1.0, v0), Vector2(phase, v0), col)
			var i2 := mb.add_vert(rings[i + 1][j1], nrings[i + 1][j1], Vector2(1.0, v1), Vector2(phase, v1), col)
			var i3 := mb.add_vert(rings[i + 1][j], nrings[i + 1][j], Vector2(0.0, v1), Vector2(phase, v1), col)
			mb.set_tangent(i0, tangents[i])
			mb.set_tangent(i1, tangents[i])
			mb.set_tangent(i2, tangents[i + 1])
			mb.set_tangent(i3, tangents[i + 1])
			var g: Vector3 = (nrings[i][j] + nrings[i][j1] + nrings[i + 1][j] + nrings[i + 1][j1]).normalized()
			mb.add_quad(i0, i1, i2, i3, g)
	# caps
	for endi in [0, n - 1]:
		var c: Vector3 = Vector3.ZERO
		for p in rings[endi]:
			c += p
		c /= float(cs)
		var cd: Vector3 = -tangents[endi] if endi == 0 else tangents[endi]
		var ci := mb.add_vert(c, cd, Vector2(0.5, 0.5), Vector2(phase, 0.0), col)
		mb.set_tangent(ci, cd)
		for j in cs:
			var j1 := (j + 1) % cs
			var i0 := mb.add_vert(rings[endi][j], nrings[endi][j], Vector2.ZERO, Vector2(phase, 0.0), col)
			var i1 := mb.add_vert(rings[endi][j1], nrings[endi][j1], Vector2.ONE, Vector2(phase, 0.0), col)
			mb.set_tangent(i0, tangents[endi])
			mb.set_tangent(i1, tangents[endi])
			mb.add_tri(ci, i0, i1, cd)
	return mb.commit("lock")


# --------------------------------------------------------------- face decals

## Sculpted nose unit: a lofted ridge that blends into the face at its rim.
static func build_nose(sp: Dictionary) -> ArrayMesh:
	var mb := MB.new()
	var rows_data := [
		[-0.0100, 0.0050, 0.0000],
		[-0.0160, 0.0054, 0.0010],
		[-0.0215, 0.0060, 0.0022],
		[-0.0265, 0.0068, 0.0034],
		[-0.0305, 0.0080, 0.0042],
		[-0.0338, 0.0096, 0.0046],
		[-0.0365, 0.0098, 0.0032],
		[-0.0385, 0.0086, 0.0010],
	]
	var cols := 16
	var grid := []
	var norms := []
	for row in rows_data:
		var y: float = row[0]
		var w: float = row[1]
		var prot: float = row[2]
		var prow := []
		var nrow := []
		for c in cols + 1:
			var u := lerpf(-1.0, 1.0, float(c) / float(cols))
			var x := u * w
			var base := surface_at(x, y, sp)
			var bn := normal_at(x, y, sp)
			var falloff := pow(maxf(1.0 - absf(u), 0.0), 1.55)
			var p := base + bn * (prot * falloff - 0.0005)
			prow.append(p)
			nrow.append(bn)
		grid.append(prow)
		norms.append(nrow)
	# recompute normals from the displaced grid
	for r in rows_data.size():
		for c in cols + 1:
			var r0: int = maxi(r - 1, 0)
			var r1: int = mini(r + 1, rows_data.size() - 1)
			var c0: int = maxi(c - 1, 0)
			var c1: int = mini(c + 1, cols)
			var du: Vector3 = grid[r][c1] - grid[r][c0]
			var dv: Vector3 = grid[r1][c] - grid[r0][c]
			var n := du.cross(dv)
			if n.length_squared() < 1e-14:
				n = norms[r][c]
			n = n.normalized()
			if n.dot(norms[r][c]) < 0.0:
				n = -n
			norms[r][c] = n
	for r in rows_data.size() - 1:
		for c in cols:
			var p0: Vector3 = grid[r][c]
			var p1: Vector3 = grid[r][c + 1]
			var p2: Vector3 = grid[r + 1][c + 1]
			var p3: Vector3 = grid[r + 1][c]
			var gg := (p1 - p0).cross(p3 - p0)
			var fn: Vector3 = gg.normalized() if gg.length_squared() > 1e-14 else norms[r][c]
			var i0 := mb.add_vert(p0, fn, Vector2(float(c) / cols, float(r) / rows_data.size()))
			var i1 := mb.add_vert(p1, fn, Vector2(float(c + 1) / cols, float(r) / rows_data.size()))
			var i2 := mb.add_vert(p2, fn, Vector2(float(c + 1) / cols, float(r + 1) / rows_data.size()))
			var i3 := mb.add_vert(p3, fn, Vector2(float(c) / cols, float(r + 1) / rows_data.size()))
			mb.add_quad(i0, i1, i2, i3, fn)
	return mb.commit("nose")


static func build_brow(sp: Dictionary, side: float) -> ArrayMesh:
	var pts := []
	var widths := []
	var segs := 10
	for i in segs + 1:
		var t := float(i) / float(segs)
		var x := lerpf(0.0135, 0.0585, t) * side
		var y := 0.0006 + 0.0030 * t + float(sp.get("brow_raise", 0.0))
		var p := surface_at(x, y, sp)
		var n := normal_at(x, y, sp)
		pts.append(p + n * 0.0011)
		var taper := sin(clampf(t, 0.03, 0.99) * PI)
		widths.append(0.00145 * pow(maxf(taper, 0.05), 0.40) * (1.10 - 0.25 * t))
	return sweep_lock(pts, widths, 0.00055, 6, Vector3.FORWARD, Color.WHITE, true)


static func build_lips(sp: Dictionary) -> Dictionary:
	var out := {}
	var half := 0.0150
	var y0 := -0.0592
	var cols := 20
	var rows := 3
	var mb := MB.new()
	var grid := []
	for c in cols + 1:
		var t := float(c) / float(cols)
		var x := lerpf(-half, half, t)
		var u := x / half
		var env := pow(maxf(1.0 - u * u, 0.0), 0.50)
		var y_line := y0 + 0.0012 * u * u
		var y_top := y_line + 0.0030 * env
		var y_bot := y_line - 0.0046 * env
		var row := []
		for r in rows + 1:
			var v := float(r) / float(rows)
			var y := lerpf(y_top, y_bot, v)
			var p := surface_at(x, y, sp)
			var n := normal_at(x, y, sp)
			var bulge := 0.0004 + 0.0007 * sin(v * PI) * env
			p += n * bulge
			row.append([p, n, Vector2(t, v)])
		grid.append(row)
	for c in cols:
		for r in rows:
			var a0: Array = grid[c][r]
			var a1: Array = grid[c + 1][r]
			var a2: Array = grid[c + 1][r + 1]
			var a3: Array = grid[c][r + 1]
			var i0 := mb.add_vert(a0[0], a0[1], a0[2])
			var i1 := mb.add_vert(a1[0], a1[1], a1[2])
			var i2 := mb.add_vert(a2[0], a2[1], a2[2])
			var i3 := mb.add_vert(a3[0], a3[1], a3[2])
			var g: Vector3 = (a0[1] + a1[1] + a2[1] + a3[1]).normalized()
			mb.add_quad(i0, i1, i2, i3, g)
	out["lips"] = mb.commit("lip_plate")

	# straight machined mouth seam
	var line_pts := []
	var line_w := []
	for i in 25:
		var t := float(i) / 24.0
		var x := lerpf(-half * 0.94, half * 0.94, t)
		var u := x / half
		var y := y0 + 0.0012 * u * u
		var p := surface_at(x, y, sp)
		var n := normal_at(x, y, sp)
		line_pts.append(p + n * 0.0011)
		var taper := pow(maxf(1.0 - u * u, 0.0), 0.42)
		line_w.append(0.00055 * maxf(taper, 0.06))
	out["line"] = sweep_lock(line_pts, line_w, 0.00036, 6, Vector3.FORWARD, Color.WHITE)

	# three tiny voice slits under the lower lip
	var slits := MB.new()
	for k in 3:
		var pts := []
		var ws := []
		var y := y0 - 0.0085 - 0.0024 * float(k)
		var hwid := 0.0052 - 0.0009 * float(k)
		for i in 9:
			var t := float(i) / 8.0
			var x := lerpf(-hwid, hwid, t)
			var p := surface_at(x, y, sp)
			var n := normal_at(x, y, sp)
			pts.append(p + n * 0.0005)
			ws.append(0.00028 * sin(clampf(t, 0.03, 0.97) * PI))
		slits.append_mesh(sweep_lock(pts, ws, 0.00022, 4, Vector3.FORWARD, Color.WHITE))
	out["slits"] = slits.commit("voice_slits")
	return out


## Raised conformal panel with a chamfered edge.  points2d is a convex
## counter-clockwise loop in face (x,y); the plate sits offset above the shell.
static func build_panel(points2d: Array, sp: Dictionary, offset := 0.0010,
		bevel := 0.0007) -> ArrayMesh:
	var mb := MB.new()
	var n := points2d.size()
	var cx := 0.0
	var cy := 0.0
	for q in points2d:
		cx += q.x
		cy += q.y
	cx /= float(n)
	cy /= float(n)
	var rings := 5
	var rows := []
	for r in rings + 1:
		var sc := 1.0 - 0.5 * float(r) / float(rings)
		var row := []
		for k in n:
			var q: Vector2 = points2d[k]
			var x := lerpf(cx, q.x, sc)
			var y := lerpf(cy, q.y, sc)
			var p := surface_at(x, y, sp)
			var nrm := normal_at(x, y, sp)
			var zoff := offset if r > 0 else 0.0
			if r == 1:
				zoff = offset
			row.append([p + nrm * zoff, nrm])
		rows.append(row)
	# top surface rings 1..end (smooth-ish)
	for r in range(1, rings):
		for k in n:
			var k1 := (k + 1) % n
			var a0: Array = rows[r][k]
			var a1: Array = rows[r][k1]
			var a2: Array = rows[r + 1][k1]
			var a3: Array = rows[r + 1][k]
			var i0 := mb.add_vert(a0[0], a0[1], Vector2(float(k) / n, float(r) / rings))
			var i1 := mb.add_vert(a1[0], a1[1], Vector2(float(k + 1) / n, float(r) / rings))
			var i2 := mb.add_vert(a2[0], a2[1], Vector2(float(k + 1) / n, float(r + 1) / rings))
			var i3 := mb.add_vert(a3[0], a3[1], Vector2(float(k) / n, float(r + 1) / rings))
			var g: Vector3 = (a0[1] + a1[1] + a2[1] + a3[1]).normalized()
			mb.add_quad(i0, i1, i2, i3, g)
	# bevel wall from the boundary (on the shell) to ring 1
	for k in n:
		var k1 := (k + 1) % n
		var a0: Array = rows[0][k]
		var a1: Array = rows[0][k1]
		var a2: Array = rows[1][k1]
		var a3: Array = rows[1][k]
		var side: Vector3 = (a0[0] + a1[0] + a2[0] + a3[0]) * 0.25
		var radial: Vector3 = Vector3(side.x - cx, side.y - cy, 0.0).normalized()
		var g: Vector3 = (a0[1] + a1[1] + a2[1] + a3[1]).normalized() * 0.4 + radial
		var i0 := mb.add_vert(a0[0], g.normalized(), Vector2(float(k) / n, 0.0))
		var i1 := mb.add_vert(a1[0], g.normalized(), Vector2(float(k + 1) / n, 0.0))
		var i2 := mb.add_vert(a2[0], g.normalized(), Vector2(float(k + 1) / n, 0.08))
		var i3 := mb.add_vert(a3[0], g.normalized(), Vector2(float(k) / n, 0.08))
		mb.add_quad(i0, i1, i2, i3, g.normalized())
	return mb.commit("panel")


static func build_seams(sp: Dictionary) -> ArrayMesh:
	var mb := MB.new()

	# jaw / cheek / forehead panel gaps, mirrored
	for side in [1.0, -1.0]:
		var jaw := [
			Vector2(0.0735, -0.012), Vector2(0.0695, -0.042), Vector2(0.0600, -0.066),
			Vector2(0.0445, -0.081), Vector2(0.0245, -0.0915), Vector2(0.0065, -0.0962),
		]
		var cheek := [
			Vector2(0.0600, -0.027), Vector2(0.0632, -0.048), Vector2(0.0560, -0.065),
			Vector2(0.0445, -0.081),
		]
		for pth in [jaw, cheek]:
			mb.append_mesh(groove(pth, side, sp, 0.00135, 0.0009))
	# forehead centre seam (hidden by fringe mostly)
	var centre := [Vector2(0.0, 0.078), Vector2(0.0, 0.058), Vector2(0.0, 0.036), Vector2(0.0, 0.016)]
	mb.append_mesh(groove(centre, 1.0, sp, 0.0011, 0.0007))
	# nose bridge panel gap
	var nbridge := [Vector2(0.0, -0.0105), Vector2(0.0, -0.020), Vector2(0.0, -0.029), Vector2(0.0, -0.0375)]
	mb.append_mesh(groove(nbridge, 1.0, sp, 0.00085, 0.00055))
	# nostril vents
	for side in [1.0, -1.0]:
		var nost := [Vector2(0.0074, -0.0362), Vector2(0.0096, -0.0382)]
		mb.append_mesh(groove(nost, side, sp, 0.0011, 0.0008))
	return mb.commit("seams")


## V-groove following a 2D polyline on the face; reads as a panel gap.
static func groove(points: Array, side: float, sp: Dictionary, width: float, depth: float) -> ArrayMesh:
	var mb := MB.new()
	var n := 44
	var rows := []
	var norms := []
	for i in n:
		var t := float(i) / float(n - 1)
		var q := _poly2d(points, t)
		var x: float = q.x * side
		var p := surface_at(x, q.y, sp)
		var nrm := normal_at(x, q.y, sp)
		var tau := 0.0
		if i > 0 and i < n - 1:
			var qa := _poly2d(points, float(i - 1) / float(n - 1))
			var qb := _poly2d(points, float(i + 1) / float(n - 1))
			tau = 1.0 if qb.y >= qa.y else -1.0
		var taper := pow(sin(clampf(t, 0.02, 0.98) * PI), 0.35)
		var row := []
		var nrow := []
		for k in 5:
			var off := 0.0
			var dz := 0.0
			if k == 0:
				off = -width
			elif k == 1:
				off = -width * 0.45
				dz = -depth
			elif k == 2:
				off = 0.0
				dz = -depth
			elif k == 3:
				off = width * 0.45
				dz = -depth
			else:
				off = width
			var pp := p + nrm * (0.0002 + dz * taper)
			pp += Vector3(cos(0.0), 0.0, 0.0)
			# lateral offset along the surface tangent perpendicular to the path
			var side_t := Vector3(1.0, 0.0, 0.0) * side
			row.append(pp + side_t * off * taper)
			nrow.append(nrm)
		rows.append(row)
		norms.append(nrow)
	for i in n - 1:
		for k in 4:
			var i0 := mb.add_vert(rows[i][k], norms[i][k])
			var i1 := mb.add_vert(rows[i][k + 1], norms[i][k + 1])
			var i2 := mb.add_vert(rows[i + 1][k + 1], norms[i + 1][k + 1])
			var i3 := mb.add_vert(rows[i + 1][k], norms[i + 1][k])
			mb.add_quad(i0, i1, i2, i3, norms[i][k])
	return mb.commit("groove")


# ----------------------------------------------------------------- neck/bust

static func _poly2d(points: Array, t: float) -> Vector2:
	var f := clampf(t, 0.0, 1.0) * float(points.size() - 1)
	var i := int(f)
	var u := f - float(i)
	var a: Vector2 = points[i]
	var b: Vector2 = points[mini(i + 1, points.size() - 1)]
	return a.lerp(b, u)


static func build_neck(sp: Dictionary) -> Dictionary:
	var out := {}
	var dark := MB.new()
	var trim := MB.new()
	var glow := MB.new()
	var cx := 0.0
	var cz := -0.010
	var ys := [-0.100, -0.145, -0.190, -0.235, -0.278]
	# central column
	var off := Transform3D(Basis.IDENTITY, Vector3(cx, -0.195, cz))
	dark.append_mesh(cylinder(0.0315, 0.0330, 0.215, 56, 6), off)
	for i in ys.size():
		var y: float = ys[i]
		var major := i == ys.size() - 1
		var r_in := 0.0325
		var r_out := 0.0455 if not major else 0.0600
		var th := 0.0145 if not major else 0.0210
		var ring := annulus(r_out, r_in, th, 64, 0.0028)
		trim.append_mesh(ring, Transform3D(Basis.IDENTITY, Vector3(cx, y, cz)))
		# dark channel between collars
		if i < ys.size() - 1:
			var y2: float = ys[i + 1]
			var chan := cylinder(0.0300, 0.0300, absf(y2 - y) * 0.55, 48, 3)
			dark.append_mesh(chan, Transform3D(Basis.IDENTITY, Vector3(cx, (y + y2) * 0.5, cz)))
		var g := annulus(0.0355, 0.0335, 0.0035, 64, 0.0006)
		glow.append_mesh(g, Transform3D(Basis.IDENTITY, Vector3(cx, y + th * 0.5 + 0.0015, cz)))
	# mount disc at bottom
	var mount := annulus(0.072, 0.030, 0.022, 72, 0.004)
	trim.append_mesh(mount, Transform3D(Basis.IDENTITY, Vector3(cx, -0.297, cz)))
	var mg := annulus(0.066, 0.060, 0.004, 72, 0.0010)
	glow.append_mesh(mg, Transform3D(Basis.IDENTITY, Vector3(cx, -0.285, cz)))
	out["dark"] = dark.commit("neck_dark")
	out["trim"] = trim.commit("neck_trim")
	out["glow"] = glow.commit("neck_glow")
	return out


static func build_ears(sp: Dictionary) -> Dictionary:
	var out := {}
	var dark := MB.new()
	var trim := MB.new()
	var glow := MB.new()
	for side_v in [1.0, -1.0]:
		var side: float = side_v
		var y: float = -0.008
		var x: float = 0.0765 * side
		var z: float = -0.004
		# pod axis along X (disc local +Y -> outward X)
		var xform := Transform3D(Basis(Vector3.BACK, -side * PI * 0.5),
			Vector3(x + 0.0045 * side, y, z))
		# base disc
		var d1 := cydisc(0.0185, 0.0085, 48, 0.0025)
		trim.append_mesh(d1, xform)
		var d2 := cydisc(0.0125, 0.0118, 44, 0.0018)
		dark.append_mesh(d2, xform)
		var r1 := annulus(0.0172, 0.0148, 0.0030, 48, 0.0008)
		trim.append_mesh(r1, xform)
		var r2 := annulus(0.0118, 0.0102, 0.0026, 44, 0.0006)
		trim.append_mesh(r2, xform)
		var g := cydisc(0.0032, 0.0125, 24, 0.0008)
		glow.append_mesh(g, xform)
	out["dark"] = dark.commit("ear_dark")
	out["trim"] = trim.commit("ear_trim")
	out["glow"] = glow.commit("ear_glow")
	return out


# ---------------------------------------------------------------- primitives

static func cylinder(r0: float, r1: float, h: float, sides := 48,
		rings := 4) -> ArrayMesh:
	var mb := MB.new()
	var grid := []
	for k in rings + 1:
		var t := float(k) / float(rings)
		var y := -h * 0.5 + h * t
		var r := lerpf(r0, r1, t)
		var row := []
		for i in sides:
			var a := TAU * float(i) / float(sides)
			row.append(Vector3(cos(a) * r, y, sin(a) * r))
		grid.append(row)
	for k in rings:
		for i in sides:
			var i1 := (i + 1) % sides
			var n0 := Vector3(grid[k][i].x, 0, grid[k][i].z).normalized()
			var n1 := Vector3(grid[k][i1].x, 0, grid[k][i1].z).normalized()
			var n2 := Vector3(grid[k + 1][i1].x, 0, grid[k + 1][i1].z).normalized()
			var n3 := Vector3(grid[k + 1][i].x, 0, grid[k + 1][i].z).normalized()
			var s := (r1 - r0) / maxf(h, 1e-4)
			var a0 := mb.add_vert(grid[k][i], (n0 + Vector3(0, -s, 0)).normalized())
			var a1 := mb.add_vert(grid[k][i1], (n1 + Vector3(0, -s, 0)).normalized())
			var a2 := mb.add_vert(grid[k + 1][i1], (n2 + Vector3(0, -s, 0)).normalized())
			var a3 := mb.add_vert(grid[k + 1][i], (n3 + Vector3(0, -s, 0)).normalized())
			mb.add_quad(a0, a1, a2, a3, (n0 + n1 + n2 + n3) * 0.25)
	# caps
	for endk in [0, rings]:
		var y := -h * 0.5 if endk == 0 else h * 0.5
		var r := r0 if endk == 0 else r1
		var up := Vector3.DOWN if endk == 0 else Vector3.UP
		var ci := mb.add_vert(Vector3(0, y, 0), up)
		var ids := []
		for i in sides:
			var a := TAU * float(i) / float(sides)
			ids.append(mb.add_vert(Vector3(cos(a) * r, y, sin(a) * r), up))
		for i in sides:
			mb.add_tri(ci, ids[i], ids[(i + 1) % sides], up)
	return mb.commit("cyl")


## Disc lying in XZ (axis +Y), with beveled rim.
static func cydisc(radius: float, thickness: float, sides := 40,
		bevel := 0.001) -> ArrayMesh:
	var mb := MB.new()
	var h := thickness * 0.5
	var b := clampf(bevel, 0.0002, minf(h * 0.8, radius * 0.3))
	var levels := [
		Vector2(-h, radius - b), Vector2(-h + b, radius),
		Vector2(h - b, radius), Vector2(h, radius - b),
	]
	var loops := []
	for lv in levels:
		var row := []
		for i in sides:
			var a := TAU * float(i) / float(sides)
			row.append(Vector3(cos(a) * lv.y, lv.x, sin(a) * lv.y))
		loops.append(row)
	for l in 3:
		for i in sides:
			var i1 := (i + 1) % sides
			var p0: Vector3 = loops[l][i]
			var p1: Vector3 = loops[l][i1]
			var p2: Vector3 = loops[l + 1][i1]
			var p3: Vector3 = loops[l + 1][i]
			var g := Vector3(p0.x + p3.x, (levels[l + 1].x - levels[l].x) * 6.0, p0.z + p3.z)
			var i0 := mb.add_vert(p0, g.normalized())
			var j0 := mb.add_vert(p1, g.normalized())
			var j1 := mb.add_vert(p2, g.normalized())
			var i1v := mb.add_vert(p3, g.normalized())
			mb.add_quad(i0, j0, j1, i1v, g)
	# top / bottom
	for endk in [0, 3]:
		var y: float = levels[endk].x
		var up := Vector3.UP if endk == 3 else Vector3.DOWN
		var r := radius - b
		var ci := mb.add_vert(Vector3(0, y, 0), up)
		var ids := []
		for i in sides:
			var a := TAU * float(i) / float(sides)
			ids.append(mb.add_vert(Vector3(cos(a) * r, y, sin(a) * r), up))
		for i in sides:
			mb.add_tri(ci, ids[i], ids[(i + 1) % sides], up)
	return mb.commit("disc")


## Annulus lying in XZ (axis +Y), beveled outer and inner rims.
static func annulus(r_out: float, r_in: float, thickness: float,
		sides := 48, bevel := 0.001) -> ArrayMesh:
	var mb := MB.new()
	var h := thickness * 0.5
	var b := clampf(bevel, 0.0002, minf(h * 0.6, (r_out - r_in) * 0.25))
	var ro := [r_out - b, r_out, r_out, r_out - b]
	var ri := [r_in + b, r_in, r_in, r_in + b]
	var yy := [-h, -h + b, h - b, h]
	var loops := []
	for l in 4:
		var row := []
		for i in sides:
			var a := TAU * float(i) / float(sides)
			row.append(Vector3(cos(a) * ro[l], yy[l], sin(a) * ro[l]))
		loops.append(row)
	var loops_in := []
	for l in 4:
		var row := []
		for i in sides:
			var a := TAU * float(i) / float(sides)
			row.append(Vector3(cos(a) * ri[l], yy[l], sin(a) * ri[l]))
		loops_in.append(row)
	# outer wall
	for l in 3:
		for i in sides:
			var i1 := (i + 1) % sides
			var p0: Vector3 = loops[l][i]
			var p1: Vector3 = loops[l][i1]
			var p2: Vector3 = loops[l + 1][i1]
			var p3: Vector3 = loops[l + 1][i]
			var g := Vector3(p0.x, (yy[l + 1] - yy[l]) * 5.0, p0.z)
			var a0 := mb.add_vert(p0, g.normalized())
			var a1 := mb.add_vert(p1, g.normalized())
			var a2 := mb.add_vert(p2, g.normalized())
			var a3 := mb.add_vert(p3, g.normalized())
			mb.add_quad(a0, a1, a2, a3, g)
	# inner wall
	for l in 3:
		for i in sides:
			var i1 := (i + 1) % sides
			var p0: Vector3 = loops_in[l][i]
			var p1: Vector3 = loops_in[l][i1]
			var p2: Vector3 = loops_in[l + 1][i1]
			var p3: Vector3 = loops_in[l + 1][i]
			var g := -Vector3(p0.x, (yy[l + 1] - yy[l]) * 5.0, p0.z)
			var a0 := mb.add_vert(p0, g.normalized())
			var a1 := mb.add_vert(p1, g.normalized())
			var a2 := mb.add_vert(p2, g.normalized())
			var a3 := mb.add_vert(p3, g.normalized())
			mb.add_quad(a0, a1, a2, a3, g)
	# top / bottom faces
	for l in [0, 3]:
		var up := Vector3.UP if l == 3 else Vector3.DOWN
		for i in sides:
			var i1 := (i + 1) % sides
			var p0: Vector3 = loops[l][i]
			var p1: Vector3 = loops[l][i1]
			var p2: Vector3 = loops_in[l][i1]
			var p3: Vector3 = loops_in[l][i]
			var a0 := mb.add_vert(p0, up)
			var a1 := mb.add_vert(p1, up)
			var a2 := mb.add_vert(p2, up)
			var a3 := mb.add_vert(p3, up)
			mb.add_quad(a0, a1, a2, a3, up)
	return mb.commit("annulus")

# ------------------------------------------------------------------ mask

static func mask_outline() -> Array:
	return [
		Vector2(-0.050, 0.030), Vector2(-0.026, 0.040), Vector2(0.0, 0.043),
		Vector2(0.026, 0.040), Vector2(0.050, 0.030), Vector2(0.058, 0.008),
		Vector2(0.058, -0.022), Vector2(0.048, -0.052), Vector2(0.028, -0.076),
		Vector2(0.0, -0.086), Vector2(-0.028, -0.076), Vector2(-0.048, -0.052),
		Vector2(-0.058, -0.022), Vector2(-0.058, 0.008),
	]


## Rounded black visor plate + titanium frame.  Returns two meshes.
static func build_mask(sp: Dictionary) -> Dictionary:
	var out := {}
	var poly := mask_outline()
	var cx := 0.0
	var cy := -0.020
	var rings := 8
	for pass_i in 2:
		var mb := MB.new()
		var grid := []
		var nrm_grid := []
		var scale_outer := 1.055 if pass_i == 0 else 1.0
		var z_edge := 0.0024 if pass_i == 0 else 0.0032
		var z_center := 0.0032 if pass_i == 0 else 0.0058
		var loops := rings + 1
		for r in loops:
			var sc := scale_outer * (1.0 - float(r) / float(loops - 1) * 0.985)
			var z := lerpf(z_edge, z_center, pow(float(r) / float(loops - 1), 1.4))
			var row := []
			for q in poly:
				var x: float = cx + (q.x - cx) * sc
				var y: float = cy + (q.y - cy) * sc
				var p := surface_at(x, y, sp)
				var n := normal_at(x, y, sp)
				row.append(p + n * z)
			grid.append(row)
		# normals
		for r in loops:
			var nrow := []
			for k in poly.size():
				var r0: int = maxi(r - 1, 0)
				var r1: int = mini(r + 1, loops - 1)
				var k0: int = (k - 1 + poly.size()) % poly.size()
				var k1: int = (k + 1) % poly.size()
				var du: Vector3 = grid[r][k1] - grid[r][k0]
				var dv: Vector3 = grid[r1][k] - grid[r0][k]
				var nn := dv.cross(du)
				if nn.length_squared() < 1e-14:
					nn = normal_at(cx, cy, sp)
				nrow.append(nn.normalized())
			nrm_grid.append(nrow)
		for r in loops - 1:
			for k in poly.size():
				var k1 := (k + 1) % poly.size()
				var i0 := mb.add_vert(grid[r][k], nrm_grid[r][k],
					Vector2(grid[r][k].x / 0.06, grid[r][k].y / 0.05))
				var i1 := mb.add_vert(grid[r][k1], nrm_grid[r][k1],
					Vector2(grid[r][k1].x / 0.06, grid[r][k1].y / 0.05))
				var i2 := mb.add_vert(grid[r + 1][k1], nrm_grid[r + 1][k1],
					Vector2(grid[r + 1][k1].x / 0.06, grid[r + 1][k1].y / 0.05))
				var i3 := mb.add_vert(grid[r + 1][k], nrm_grid[r + 1][k],
					Vector2(grid[r + 1][k].x / 0.06, grid[r + 1][k].y / 0.05))
				var g: Vector3 = (nrm_grid[r][k] + nrm_grid[r][k1] + nrm_grid[r + 1][k] + nrm_grid[r + 1][k1]).normalized()
				mb.add_quad(i0, i1, i2, i3, g)
		# bevel wall down to the face at the outermost loop
		if pass_i == 0:
			for k in poly.size():
				var k1 := (k + 1) % poly.size()
				var p0 := surface_at(poly[k].x, poly[k].y, sp) + normal_at(poly[k].x, poly[k].y, sp) * 0.0003
				var p1 := surface_at(poly[k1].x, poly[k1].y, sp) + normal_at(poly[k1].x, poly[k1].y, sp) * 0.0003
				var a0 := mb.add_vert(p0, normal_at(poly[k].x, poly[k].y, sp))
				var a1 := mb.add_vert(p1, normal_at(poly[k1].x, poly[k1].y, sp))
				var b0 := mb.add_vert(grid[0][k], nrm_grid[0][k])
				var b1 := mb.add_vert(grid[0][k1], nrm_grid[0][k1])
				mb.add_quad(a0, a1, b1, b0, nrm_grid[0][k])
		out["frame" if pass_i == 0 else "plate"] = mb.commit("mask")
	# camera sensor ports
	var sensors := []
	for side in [1.0, -1.0]:
		var scx: float = 0.0300 * side
		var scy := -0.0060
		var p := surface_at(scx, scy, sp)
		var n := normal_at(scx, scy, sp)
		p += n * 0.0048
		sensors.append(build_sensor(p, n, 0.0148 * float(sp.get("eye_size", 1.0))))
	out["sensors"] = sensors
	return out


## One circular camera sensor set into the visor.
static func build_sensor(origin: Vector3, normal: Vector3, radius: float) -> Dictionary:
	var out := {}
	var up := Vector3.UP - normal * Vector3.UP.dot(normal)
	if up.length_squared() < 1e-8:
		up = Vector3.RIGHT
	up = up.normalized()
	var right := up.cross(normal).normalized()
	var frame := Transform3D(Basis(right, up, normal), origin)
	var bez := MB.new()
	var seg := 56
	var r0 := radius
	var r1 := radius * 1.24
	for j in seg:
		var a0 := TAU * float(j) / seg
		var a1 := TAU * float(j + 1) / seg
		var pts := [
			Vector3(cos(a0) * r1, sin(a0) * r1, 0.0000),
			Vector3(cos(a1) * r1, sin(a1) * r1, 0.0000),
			Vector3(cos(a1) * r1, sin(a1) * r1, 0.0022),
			Vector3(cos(a0) * r1, sin(a0) * r1, 0.0022),
			Vector3(cos(a0) * r0, sin(a0) * r0, 0.0022),
			Vector3(cos(a1) * r0, sin(a1) * r0, 0.0022),
			Vector3(cos(a1) * r0, sin(a1) * r0, 0.0006),
			Vector3(cos(a0) * r0, sin(a0) * r0, 0.0006),
		]
		var ids := []
		for pp in pts:
			var nn: Vector3 = (normal + right * pp.x * 28.0 + up * pp.y * 28.0).normalized()
			ids.append(bez.add_vert(frame * pp, nn))
		bez.add_quad(ids[0], ids[1], ids[2], ids[3], -normal)
		bez.add_quad(ids[3], ids[2], ids[5], ids[4], normal)
		bez.add_quad(ids[5], ids[6], ids[7], ids[4], -normal)
		bez.add_quad(ids[6], ids[1], ids[0], ids[7], normal)
	out["bezel"] = bez.commit("sensor_bezel")
	# dark lens body
	var body := MB.new()
	var brings := 6
	for k in brings + 1:
		var rr := float(k) / float(brings) * radius * 0.99
		var z := 0.0004 - 0.0012 * (1.0 - float(k) / float(brings))
		for j in 56:
			pass
	# simple disc fan recessed
	var center_idx := body.add_vert(frame * Vector3(0, 0, -0.0008), normal, Vector2(0, 0))
	for j in 56:
		var a := TAU * float(j) / 56
		var v := Vector3(cos(a) * radius * 0.99, sin(a) * radius * 0.99, 0.0004)
		body.add_vert(frame * v, normal, Vector2(cos(a), sin(a)))
	for j in 56:
		var i0 := 1 + j
		var i1 := 1 + (j + 1) % 56
		body.add_tri(center_idx, i0, i1, normal)
	out["body"] = body.commit("sensor_body")
	# glowing iris lens
	var iris := MB.new()
	var iris_r := radius * 0.70
	var iseg := 56
	var ic := iris.add_vert(frame * Vector3(0, 0, 0.0005), normal, Vector2(0, 0))
	for j in iseg:
		var a := TAU * float(j) / iseg
		var v := Vector3(cos(a) * iris_r, sin(a) * iris_r, 0.0005)
		iris.add_vert(frame * v, normal, Vector2(cos(a), sin(a)))
	for j in iseg:
		iris.add_tri(ic, 1 + j, 1 + (j + 1) % iseg, normal)
	out["iris"] = iris.commit("sensor_iris")
	# thin emissive collar
	var glow := MB.new()
	var gseg := 56
	for j in gseg:
		var a0 := TAU * float(j) / gseg
		var a1 := TAU * float(j + 1) / gseg
		var r_in := radius * 0.845
		var r_out := radius * 0.915
		var v0 := frame * Vector3(cos(a0) * r_in, sin(a0) * r_in, 0.0009)
		var v1 := frame * Vector3(cos(a1) * r_in, sin(a1) * r_in, 0.0009)
		var v2 := frame * Vector3(cos(a1) * r_out, sin(a1) * r_out, 0.0009)
		var v3 := frame * Vector3(cos(a0) * r_out, sin(a0) * r_out, 0.0009)
		var i0 := glow.add_vert(v0, normal)
		var i1 := glow.add_vert(v1, normal)
		var i2 := glow.add_vert(v2, normal)
		var i3 := glow.add_vert(v3, normal)
		glow.add_quad(i0, i1, i2, i3, normal)
	out["glow"] = glow.commit("sensor_glow")
	return out
