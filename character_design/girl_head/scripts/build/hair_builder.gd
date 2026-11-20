extends RefCounted
class_name HairBuilder
## Procedural silver hair: an under-scalp shell plus ~90 swept, tapered locks.
##
## Every lock is grown by integrating a direction that is pulled by gravity,
## pushed away from the skull (real head profile, not a sphere) and decorated
## with a low-frequency S-wave.  Roots sit on the procedural scalp, so the
## hairline and the parting are data, not textures.

const MB := preload("res://scripts/build/mesh_builder.gd")
const HB := preload("res://scripts/build/head_builder.gd")
const TAU := PI * 2.0

static var _rng := RandomNumberGenerator.new()
static var last_lock_count := 0


# ------------------------------------------------------------------- helpers

static func _radial_xz(p: Vector3) -> Vector3:
	var v := Vector3(p.x, 0.0, p.z)
	if v.length_squared() < 1e-9:
		return Vector3.FORWARD
	return v.normalized()


static func _scalp(y: float, az_deg: float, sp: Dictionary, lift: float) -> Array:
	var phi := deg_to_rad(az_deg)
	var p := HB.surface_point(y, phi, sp)
	var n := HB.base_normal(y, phi, sp)
	return [p + n * lift, n]


## Pushes a point outside the actual head profile at its height.
static func _push_out(p: Vector3, clear: float, sp: Dictionary) -> Vector3:
	if p.y > 0.093:
		var rx := 0.0815
		var ry := 0.115
		var rz := 0.103
		var q := Vector3(p.x / rx, p.y / ry, p.z / rz)
		var l := q.length()
		var lim := 1.0 + clear / 0.095
		if l < lim and l > 1e-6:
			q *= lim / l
			return Vector3(q.x * rx, q.y * ry, q.z * rz)
		return p
	var y := clampf(p.y, -0.118, 0.100)
	var phi := atan2(p.x, p.z)
	var s := HB.surface_point(y, phi, sp)
	var rs := Vector2(s.x, s.z).length()
	var rp := Vector2(p.x, p.z).length()
	var want := rs + clear
	if rp < want:
		if rp < 1e-5:
			p.x = 0.0
			p.z = want
		else:
			var k := want / rp
			p.x *= k
			p.z *= k
	return p


static func _grow(root: Vector3, dir0: Vector3, length: float, sp: Dictionary,
		opts: Dictionary) -> Array:
	var steps: int = int(opts.get("steps", 26))
	var ds := length / float(steps)
	var p := root
	var d := dir0.normalized()
	var pts := [p]
	var phase: float = float(opts.get("phase", 0.0))
	var sway: float = float(opts.get("sway", 0.0))
	var flare: float = float(opts.get("flare", 0.0))
	var gravity: float = float(opts.get("gravity", 2.2))
	var clear0: float = float(opts.get("clear0", 0.006))
	var clear1: float = float(opts.get("clear1", 0.02))
	for i in steps:
		var t := float(i + 1) / float(steps)
		d = (d + Vector3.DOWN * gravity * ds).normalized()
		var rad := _radial_xz(p)
		if flare != 0.0:
			d = (d + rad * flare * ds * smoothstep(0.12, 1.0, t)).normalized()
		if sway != 0.0:
			var sidev := d.cross(Vector3.UP)
			if sidev.length_squared() > 1e-8:
				sidev = sidev.normalized()
				d = (d + sidev * sin(t * 4.2 + phase * TAU) * sway * ds).normalized()
		p = p + d * ds
		var clear := lerpf(clear0, clear1, t * t)
		p = _push_out(p, clear, sp)
		var max_r: float = float(opts.get("max_r", 0.145))
		var rxz := Vector2(p.x, p.z)
		if rxz.length() > max_r:
			rxz = rxz.normalized() * max_r
			p.x = rxz.x
			p.z = rxz.y
		pts.append(p)
	# low-frequency wave so long locks do not read as straight wires
	for i in range(1, pts.size()):
		var tw := float(i) / float(pts.size() - 1)
		var q: Vector3 = pts[i]
		var sid := Vector3(q.x, 0.0, q.z).cross(Vector3.UP)
		if sid.length_squared() > 1e-10:
			sid = sid.normalized()
			pts[i] = q + sid * (sin(tw * 4.6 + phase * TAU) * 0.0042
				+ sin(tw * 9.3 + phase * 3.1) * 0.0020) * tw
	return pts


static func _trim_y(pts: Array, y_min: float) -> Array:
	if pts.size() < 3:
		return pts
	var out := [pts[0]]
	for i in range(1, pts.size()):
		var b: Vector3 = pts[i]
		if b.y < y_min:
			var a: Vector3 = pts[i - 1]
			var dy := b.y - a.y
			var tt := 0.0 if absf(dy) < 1e-8 else clampf((y_min - a.y) / dy, 0.0, 1.0)
			out.append(a.lerp(b, tt))
			break
		out.append(b)
	if out.size() < 3:
		return pts
	return out


static func _widths(n: int, w0: float, root_taper := 0.62, tip_start := 0.55,
		bulge := 0.22) -> Array:
	var out := []
	for i in n:
		var t := float(i) / float(maxi(n - 1, 1))
		var w := w0 * (root_taper + (1.0 - root_taper) * smoothstep(0.0, 0.16, t))
		w *= 1.0 + bulge * sin(clampf(t / tip_start, 0.0, 1.0) * PI)
		if t > tip_start:
			var u := (t - tip_start) / (1.0 - tip_start)
			w *= pow(maxf(1.0 - u, 0.0), 0.62)
		out.append(maxf(w, 0.00035))
	return out


static func _lock(mb: MeshBuilder, pts: Array, w0: float, thick_ratio: float,
		phase: float, tint: Color, segs := 10) -> void:
	var widths := _widths(pts.size(), w0)
	var th := maxf(w0 * thick_ratio, 0.0009)
	var mesh := HB.sweep_lock(pts, widths, th, segs, Vector3.ZERO, tint, true, phase)
	mb.append_mesh(mesh)
	last_lock_count += 1


# --------------------------------------------------------------------- build

static func build(sp: Dictionary) -> Dictionary:
	_rng.seed = 20261120
	last_lock_count = 0
	var locks := MB.new()
	var length_scale: float = float(sp.get("hair_length", 1.0))
	var volume: float = float(sp.get("hair_volume", 1.0))
	var width_scale: float = float(sp.get("hair_width", 1.0))
	var count_scale: float = float(sp.get("hair_density", 1.0))

	# ---------------------------------------------------------- 1. back mass
	var back_rows := [
		{"y": 0.0830, "az0": 100.0, "az1": 260.0, "n": 40, "len": 0.53, "w": 0.0136, "clear1": 0.034},
		{"y": 0.0580, "az0": 96.0, "az1": 264.0, "n": 40, "len": 0.49, "w": 0.0140, "clear1": 0.038},
		{"y": 0.0300, "az0": 104.0, "az1": 256.0, "n": 31, "len": 0.45, "w": 0.0130, "clear1": 0.032},
	]
	for row in back_rows:
		var n: int = int(round(float(row["n"]) * clampf(count_scale, 0.6, 1.5)))
		for i in n:
			var tt := (float(i) + 0.5) / float(n)
			var az: float = lerpf(row["az0"], row["az1"], tt) + _rng.randf_range(-3.0, 3.0)
			var y: float = float(row["y"]) + _rng.randf_range(-0.006, 0.006)
			var rr := _scalp(y, az, sp, 0.0025 + _rng.randf_range(0.0, 0.0035))
			var root: Vector3 = rr[0]
			var nrm: Vector3 = rr[1]
			var rad := _radial_xz(root)
			var d0 := (nrm * 0.03 + Vector3.DOWN * 1.0 + rad * 0.05 + Vector3.FORWARD * 0.22).normalized()
			var mid_t: float = 1.0 - absf(tt - 0.5) * 2.0
			var ln: float = float(row["len"]) * length_scale * (0.80 + 0.20 * mid_t) * _rng.randf_range(0.90, 1.05)
			var clear1: float = float(row["clear1"]) * volume
			var pts := _grow(root, d0, ln, sp, {
				"steps": 30, "phase": _rng.randf(), "sway": 0.35,
				"flare": 0.30 * volume, "gravity": 2.1,
				"clear0": 0.008 + _rng.randf() * 0.0035,
				"clear1": clear1 + _rng.randf() * 0.008, "max_r": 0.086,
			})
			var tint := Color(1.0, 1.0, 1.0) * _rng.randf_range(0.93, 1.05)
			tint.a = 1.0
			_lock(locks, pts, float(row["w"]) * width_scale * _rng.randf_range(0.86, 1.10),
				0.24, _rng.randf(), tint, 10)

	# ------------------------------------------------------ 1b. short layer
	for i in 16:
		var t := (float(i) + 0.5) / 16.0
		var az := lerpf(88.0, 272.0, t) + _rng.randf_range(-5.0, 5.0)
		var rr := _scalp(0.052 + _rng.randf_range(-0.008, 0.008), az, sp, 0.004)
		var root: Vector3 = rr[0]
		var rad := _radial_xz(root)
		var d0 := (Vector3.DOWN * 1.0 + rad * 0.18 + Vector3.FORWARD * 0.18).normalized()
		var pts := _grow(root, d0, 0.24 * length_scale * _rng.randf_range(0.85, 1.15), sp, {
			"steps": 18, "phase": _rng.randf(), "sway": 0.35,
			"flare": 0.03, "gravity": 2.3,
			"clear0": 0.012, "clear1": 0.020, "max_r": 0.120,
		})
		_lock(locks, pts, 0.0105 * width_scale, 0.26, _rng.randf(), Color(0.98, 0.98, 1.0), 9)

	# ------------------------------------------------------- 2. crown cover
	for i in 0:
		var t := float(i) / 13.0
		var az: float = lerpf(0.0, 360.0, t) + _rng.randf_range(-6.0, 6.0)
		var azw := wrapf(az, -180.0, 180.0)
		if absf(azw) < 48.0:
			continue
		var rr := _scalp(0.1020 - _rng.randf_range(0.0, 0.004), az, sp, 0.0012)
		var root: Vector3 = rr[0]
		var rad := _radial_xz(root)
		var d0 := (rad * 0.22 + Vector3.DOWN * 0.55 + Vector3.FORWARD * 0.35).normalized()
		var pts := _grow(root, d0, 0.085 * length_scale * _rng.randf_range(0.85, 1.15), sp, {
			"steps": 12, "phase": _rng.randf(), "sway": 0.12,
			"flare": 0.02, "gravity": 2.0,
			"clear0": 0.0010, "clear1": 0.0030, "max_r": 0.074,
		})
		_lock(locks, pts, 0.0080 * width_scale, 0.18, _rng.randf(), Color(0.99, 0.99, 1.0), 8)

	for i in 0:
		var t := float(i) / 17.0
		var az: float = lerpf(52.0, 308.0, t) + _rng.randf_range(-4.0, 4.0)
		if az > 180.0:
			az -= 360.0
		var rr := _scalp(0.1005 - _rng.randf_range(0.0, 0.004), az, sp, 0.0015)
		var root: Vector3 = rr[0]
		var nrm: Vector3 = rr[1]
		var rad := _radial_xz(root)
		var d0 := (nrm * 0.10 + rad * 0.02 + Vector3.DOWN * 0.55 + Vector3.FORWARD * 0.95).normalized()
		var ln := 0.18 * length_scale * _rng.randf_range(0.85, 1.05)
		var pts := _grow(root, d0, ln, sp, {
			"steps": 22, "phase": _rng.randf(), "sway": 0.25,
			"flare": 0.04 * volume, "gravity": 2.2,
			"clear0": 0.004 + _rng.randf() * 0.002,
			"clear1": 0.010 * volume + _rng.randf() * 0.003, "max_r": 0.120,
		})
		_lock(locks, pts, 0.0115 * width_scale * _rng.randf_range(0.88, 1.10),
			0.23, _rng.randf(), Color(0.99, 0.99, 1.0), 9)

	# ------------------------------------------------- 3. face-framing sides
	for side in [1.0, -1.0]:
		var specs := [
			{"az": 52.0, "y": 0.082, "len": 0.24, "w": 0.0115, "c1": 0.008},
			{"az": 58.0, "y": 0.064, "len": 0.33, "w": 0.0128, "c1": 0.010},
			{"az": 65.0, "y": 0.044, "len": 0.36, "w": 0.0135, "c1": 0.014},
			{"az": 72.0, "y": 0.022, "len": 0.34, "w": 0.0135, "c1": 0.018},
			{"az": 80.0, "y": 0.004, "len": 0.26, "w": 0.0125, "c1": 0.018},
			{"az": 55.0, "y": 0.070, "len": 0.20, "w": 0.0100, "c1": 0.010},
		]
		for sidx in specs.size():
			var spc: Dictionary = specs[sidx]
			var az: float = float(spc["az"]) * side + _rng.randf_range(-2.0, 2.0)
			var rr := _scalp(float(spc["y"]), az, sp, 0.0025)
			var root: Vector3 = rr[0]
			var nrm: Vector3 = rr[1]
			var d0 := (Vector3(side * 0.10, -1.0, 0.0) + nrm * 0.02).normalized()
			var ln: float = float(spc["len"]) * length_scale * _rng.randf_range(0.94, 1.04)
			var pts := _grow(root, d0, ln, sp, {
				"steps": 26, "phase": _rng.randf(), "sway": 0.22,
				"flare": 0.01, "gravity": 2.5,
				"clear0": 0.005 + _rng.randf() * 0.0025,
				"clear1": float(spc["c1"]) * volume + _rng.randf() * 0.004, "max_r": 0.098,
			})
			if sidx % 2 == 0:
				for k in range(6, pts.size()):
					pts[k] += Vector3(0.0, 0.0, 0.005) * (float(k) / float(pts.size() - 1))
			_lock(locks, pts, float(spc["w"]) * width_scale * _rng.randf_range(0.9, 1.06),
				0.23, _rng.randf(), Color(0.98, 0.99, 1.0), 9)

	# ------------------------------------------------------------- 4. fringe
	# many fine strands over the shaped fringe card
	var n_f = 0
	for i in n_f:
		var t := (float(i) + 0.5) / float(n_f)
		var az := lerpf(-46.0, 46.0, t) + _rng.randf_range(-1.2, 1.2)
		var rr := _scalp(0.080 + 0.009 * cos((t - 0.5) * PI * 1.2), az, sp, 0.0022 + _rng.randf() * 0.0020)
		var root: Vector3 = rr[0]
		var nrm: Vector3 = rr[1]
		var sweep := lerpf(-0.28, 0.22, t)
		var d0 := (Vector3(sweep, -1.05, 0.90) + nrm * 0.16).normalized()
		var ln := _rng.randf_range(0.060, 0.090)
		var pts := _grow(root, d0, ln, sp, {
			"steps": 14, "phase": _rng.randf(), "sway": 0.16,
			"flare": 0.0, "gravity": 1.05,
			"clear0": 0.0026, "clear1": 0.0064,
			"max_r": 0.115,
		})
		var target := 0.030 + 0.007 * sin(t * PI * 5.0 + 0.6) + _rng.randf_range(-0.002, 0.002)
		pts = _trim_y(pts, target)
		var wpts := _widths(pts.size(), _rng.randf_range(0.0085, 0.0105) * width_scale,
			0.22, 0.5, 0.18)
		var wmesh := HB.sweep_lock(pts, wpts, 0.0026, 7, Vector3.ZERO, Color(1, 1, 1), true,
			_rng.randf())
		locks.append_mesh(wmesh)

	# two long swept fringe strands crossing toward the left temple
	for k in 2:
		var rr := _scalp(0.091, 10.0 + 7.0 * float(k), sp, 0.004)
		var root: Vector3 = rr[0]
		var pts := _grow(root, Vector3(-0.88, -0.78, 0.55), 0.125 + 0.02 * float(k), sp, {
			"steps": 18, "phase": 0.2 + 0.3 * float(k), "sway": 0.45,
			"flare": 0.0, "gravity": 0.55,
			"clear0": 0.0045, "clear1": 0.008,
		})
		_lock(locks, pts, 0.0115 * width_scale, 0.24, 0.5, Color(1, 1, 1), 8)

	# --------------------------------------------------------- 5. flyaways
	for i in 0:
		var az := _rng.randf_range(70.0, 290.0)
		var y := _rng.randf_range(0.030, 0.085)
		var rr := _scalp(y, az, sp, 0.006)
		var root: Vector3 = rr[0]
		var rad := _radial_xz(root)
		var d0 := (rad * 0.35 + Vector3.DOWN * 1.0 + Vector3.FORWARD * 0.15).normalized()
		var pts := _grow(root, d0, _rng.randf_range(0.14, 0.26) * length_scale, sp, {
			"steps": 18, "phase": _rng.randf(), "sway": 0.55,
			"flare": 0.18, "gravity": 1.8,
			"clear0": 0.009, "clear1": 0.022 * volume,
		})
		_lock(locks, pts, 0.0030 * width_scale, 0.6, _rng.randf(), Color(1, 1, 1), 5)

	# ------------------------------------------------------- 7. under layers
	var cap := _build_cap(sp)
	var sheet := _build_back_sheet(sp, length_scale, volume, width_scale)
	var fringe_sheet := _build_fringe_sheet(sp, width_scale)

	return {
		"locks": locks.commit("hair_locks"),
		"cap": cap.commit("hair_cap"),
		"sheet": sheet.commit("hair_sheet"),
		"fringe_sheet": fringe_sheet.commit("hair_fringe_sheet"),
	}


## A shaped fringe card that guarantees a clean hairline and a pointed,
## slightly jagged bottom edge in front of the forehead.  Detail locks sit on
## top of it.  This is what keeps the fringe from reading as separate icicles.
static func _build_fringe_sheet(sp: Dictionary, width_scale: float) -> MeshBuilder:
	var mb := MB.new()
	var cols := 40
	var rows := 12
	var grid := []
	var norms := []
	var tans := []
	for c in cols + 1:
		var t := float(c) / float(cols)
		var az := lerpf(-71.0, 71.0, t)
		var rr := _scalp(0.0875, az, sp, 0.0030)
		var root: Vector3 = rr[0]
		# jagged bottom edge: coarser teeth + a finer ripple, with a side sweep
		var y_bot := 0.0125
		y_bot += 0.0018 * sin(t * PI * 3.0 + 0.9)
		y_bot += 0.0009 * sin(t * PI * 7.0 + 2.3)
		y_bot += -0.003 * pow(absf(t - 0.42) * 1.7, 2.0)

		if t < 0.08 or t > 0.92:
			y_bot = 0.060
		var row := []
		var nrow := []
		var trow := []
		var x_root: float = root.x
		for r in rows + 1:
			var u := float(r) / float(rows)
			var y := lerpf(0.0875, y_bot, u)
			var x := x_root + (-0.010 + 0.006 * sin(t * PI * 3.0)) * u * u
			var p := HB.surface_at(x, y, sp)
			var n := HB.normal_at(x, y, sp)
			var ridge := 0.0006 * sin(t * PI * 7.0 + u * 5.0)
			row.append(p + n * (0.0050 + ridge))
			nrow.append(n)
			trow.append((HB.surface_at(x, y - 0.003, sp) - HB.surface_at(x, y + 0.003, sp)).normalized())
		grid.append(row)
		norms.append(nrow)
		tans.append(trow)
	for c in cols:
		for r in rows:
			var v0 := float(r) / float(rows)
			var v1 := float(r + 1) / float(rows)
			var i0 := mb.add_vert(grid[c][r], norms[c][r],
				Vector2(float(c) / float(cols), v0), Vector2(float(c) / float(cols), v0))
			var i1 := mb.add_vert(grid[c + 1][r], norms[c + 1][r],
				Vector2(float(c + 1) / float(cols), v0), Vector2(float(c + 1) / float(cols), v0))
			var i2 := mb.add_vert(grid[c + 1][r + 1], norms[c + 1][r + 1],
				Vector2(float(c + 1) / float(cols), v1), Vector2(float(c + 1) / float(cols), v1))
			var i3 := mb.add_vert(grid[c][r + 1], norms[c][r + 1],
				Vector2(float(c) / float(cols), v1), Vector2(float(c) / float(cols), v1))
			mb.set_tangent(i0, tans[c][r])
			mb.set_tangent(i1, tans[c + 1][r])
			mb.set_tangent(i2, tans[c + 1][r + 1])
			mb.set_tangent(i3, tans[c][r + 1])
			var g: Vector3 = (norms[c][r] + norms[c + 1][r] + norms[c][r + 1] + norms[c + 1][r + 1]).normalized()
			mb.add_quad(i0, i1, i2, i3, g)
	return mb


## A soft continuous sheet behind the back locks.  Locks alone can show the
## backdrop between strands; this fills the mass and reads as hair with the
## same anisotropic shader.  Kept 1.0-1.6 cm inside the lock layer.
static func _build_back_sheet(sp: Dictionary, length_scale: float,
		volume: float, width_scale: float) -> MeshBuilder:
	var mb := MB.new()
	var cols := 25
	var steps := 24
	var paths := []
	for c in cols + 1:
		var t := float(c) / float(cols)
		var az: float = lerpf(76.0, 284.0, t)
		var rr := _scalp(0.090 + 0.004 * sin(t * PI), az, sp, 0.0015)
		var root: Vector3 = rr[0]
		var rad := _radial_xz(root)
		var d0 := (Vector3.DOWN * 1.0 + rad * 0.30 + Vector3.FORWARD * 0.26).normalized()
		var pts := _grow(root, d0, (0.58 + 0.07 * sin(t * PI * 2.0)) * length_scale, sp, {
			"steps": steps, "phase": t * 3.7, "sway": 0.25,
			"flare": 0.22 * volume, "gravity": 2.2,
			"clear0": 0.004, "clear1": 0.022 * volume, "max_r": 0.086,
		})
		paths.append(pts)
	var rows := []
	var nrows := []
	var tans := []
	for c in cols + 1:
		var row := []
		var nrow := []
		var trow := []
		for k in steps + 1:
			var p: Vector3 = paths[c][k]
			var inn := _radial_xz(p)
			var v := float(k) / float(steps)
			p -= inn * (0.014 + 0.004 * sin(float(c) * 2.1 + v * 9.0))
			p = _push_out(p, 0.0025, sp)
			row.append(p)
			var nrm := inn
			if c > 0 and c < cols:
				var du: Vector3 = paths[c + 1][k] - paths[c - 1][k]
				var dv: Vector3 = paths[c][mini(k + 1, steps)] - paths[c][maxi(k - 1, 0)]
				var nn := dv.cross(du)
				if nn.length_squared() > 1e-10:
					nrm = nn.normalized()
					if nrm.dot(inn) < 0.0:
						nrm = -nrm
			nrow.append(nrm)
			trow.append((paths[c][mini(k + 1, steps)] - paths[c][maxi(k - 1, 0)]).normalized())
		rows.append(row)
		nrows.append(nrow)
		tans.append(trow)
	for c in cols:
		for k in steps:
			var v0 := float(k) / float(steps)
			var v1 := float(k + 1) / float(steps)
			var i0 := mb.add_vert(rows[c][k], nrows[c][k],
				Vector2(float(c) / float(cols), v0), Vector2(0.5, v0))
			var i1 := mb.add_vert(rows[c + 1][k], nrows[c + 1][k],
				Vector2(float(c + 1) / float(cols), v0), Vector2(0.5, v0))
			var i2 := mb.add_vert(rows[c + 1][k + 1], nrows[c + 1][k + 1],
				Vector2(float(c + 1) / float(cols), v1), Vector2(0.5, v1))
			var i3 := mb.add_vert(rows[c][k + 1], nrows[c][k + 1],
				Vector2(float(c) / float(cols), v1), Vector2(0.5, v1))
			mb.set_tangent(i0, tans[c][k])
			mb.set_tangent(i1, tans[c + 1][k])
			mb.set_tangent(i2, tans[c + 1][k + 1])
			mb.set_tangent(i3, tans[c][k + 1])
			var g: Vector3 = (nrows[c][k] + nrows[c + 1][k] + nrows[c][k + 1] + nrows[c + 1][k + 1]).normalized()
			mb.add_quad(i0, i1, i2, i3, g)
	return mb


static func _build_cap(sp: Dictionary) -> MeshBuilder:
	var mb := MB.new()
	var segs := 96
	var rows := 30
	var grid := []
	var norms := []
	for r in rows + 1:
		var row := []
		var nrow := []
		for s in segs:
			var phi := TAU * float(s) / float(segs)
			var az := rad_to_deg(phi)
			var a := absf(az)
			if a > 180.0:
				a = 360.0 - a
			var ymin := 0.0500
			if a > 52.0:
				ymin = lerpf(0.0500, 0.0200, clampf((a - 52.0) / 30.0, 0.0, 1.0))
			if a > 82.0:
				ymin = lerpf(0.0340, -0.030, clampf((a - 82.0) / 30.0, 0.0, 1.0))
			if a > 112.0:
				ymin = lerpf(-0.030, -0.056, clampf((a - 112.0) / 40.0, 0.0, 1.0))
			var y := lerpf(ymin, 0.1065, float(r) / float(rows))
			var p := HB.surface_point(y, phi, sp)
			var nrm := HB.base_normal(y, phi, sp)
			row.append(p + nrm * 0.0200)
			nrow.append(nrm)
		grid.append(row)
		norms.append(nrow)
	for r in rows:
		for s in segs:
			var s1 := (s + 1) % segs
			var v0 := 1.0 - float(r) / float(rows)
			var v1 := 1.0 - float(r + 1) / float(rows)
			var i0 := mb.add_vert(grid[r][s], norms[r][s],
				Vector2(float(s) / segs, v0), Vector2(0.5, v0))
			var i1 := mb.add_vert(grid[r][s1], norms[r][s1],
				Vector2(float(s + 1) / segs, v0), Vector2(0.5, v0))
			var i2 := mb.add_vert(grid[r + 1][s1], norms[r + 1][s1],
				Vector2(float(s + 1) / segs, v1), Vector2(0.5, v1))
			var i3 := mb.add_vert(grid[r + 1][s], norms[r + 1][s],
				Vector2(float(s) / segs, v1), Vector2(0.5, v1))
			for ii in [i0, i1, i2, i3]:
				var nrmv: Vector3 = norms[r][s] if ii == i0 or ii == i1 else norms[r + 1][s]
				var tanv := (Vector3.DOWN - nrmv * Vector3.DOWN.dot(nrmv))
				mb.set_tangent(ii, tanv)
			var g: Vector3 = (norms[r][s] + norms[r][s1] + norms[r + 1][s] + norms[r + 1][s1]).normalized()
			mb.add_quad(i0, i1, i2, i3, g)
	return mb