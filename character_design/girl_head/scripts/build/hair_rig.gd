extends RefCounted
class_name HairRig
## Skinned, physics-driven silver hair.
##
## 33 guide chains (fringe / side / long side / back / short layer).  Every
## chain is a real bone chain in a Skeleton3D; every lock in the mesh is
## weighted to two adjacent bones of its guide.  A SpringBoneSimulator3D drives
## the chains with gravity / inertia / drag and an external wind force, so the
## hair is genuinely animated (not a fixed vertex shader wobble).
##
## The rest shape is generated here; the character builds the Skeleton3D,
## Skin, MeshInstance3D and SpringBoneSimulator3D from the returned data.

const MB := preload("res://scripts/build/mesh_builder.gd")
const HB := preload("res://scripts/build/hair_builder.gd")

static var _rng := RandomNumberGenerator.new()
static var lock_count := 0


static func build(sp: Dictionary) -> Dictionary:
	_rng.seed = 20261121
	lock_count = 0
	var guides := []

	# ------------------------------------------------------------- fringe
	var fringe_az := [-44.0, -22.0, 0.0, 22.0, 44.0]
	for k in fringe_az.size():
		var az: float = fringe_az[k]
		var rr: Array = HB._scalp(0.0845, az, sp, 0.0018)
		var root: Vector3 = rr[0]
		var sweep := lerpf(-0.16, 0.16, float(k) / 4.0)
		var d0: Vector3 = (Vector3(sweep, -1.05, 0.92) + rr[1] * 0.12).normalized()
		var pts := HB._grow(root, d0, 0.108 * float(sp.get("hair_length", 1.0)),
			sp, {"steps": 8, "phase": _rng.randf(), "sway": 0.16,
			"flare": 0.0, "gravity": 1.05,
			"clear0": 0.0016, "clear1": 0.0034, "max_r": 0.105})
		guides.append({"points": pts, "bones": 6, "w0": 0.0170,
			"locks": 3, "lat": 0.0130, "stiff": 0.22, "drag": 0.18, "grav": 0.9})

	# -------------------------------------------------------- side front
	for side in [1.0, -1.0]:
		var specs := [
			{"az": 58.0, "y": 0.070, "len": 0.24, "w": 0.0125, "b": 7},
			{"az": 70.0, "y": 0.048, "len": 0.30, "w": 0.0140, "b": 7},
			{"az": 82.0, "y": 0.024, "len": 0.33, "w": 0.0140, "b": 8},
		]
		for g in specs:
			var rr: Array = HB._scalp(float(g["y"]), float(g["az"]) * side, sp, 0.0022)
			var root: Vector3 = rr[0]
			var d0: Vector3 = (Vector3(side * 0.10, -1.0, 0.05) + rr[1] * 0.03).normalized()
			var pts := HB._grow(root, d0, float(g["len"]) * float(sp.get("hair_length", 1.0)),
				sp, {"steps": 9, "phase": _rng.randf(), "sway": 0.28,
				"flare": 0.03, "gravity": 2.3,
				"clear0": 0.004, "clear1": 0.008, "max_r": 0.105})
			guides.append({"points": pts, "bones": int(g["b"]), "w0": float(g["w"]),
				"locks": 2, "lat": 0.010, "stiff": 0.16, "drag": 0.20, "grav": 1.5})

	# --------------------------------------------------------- side long
	for side in [1.0, -1.0]:
		for k in 2:
			var rr: Array = HB._scalp(0.030 - 0.018 * float(k), (68.0 + 10.0 * float(k)) * side, sp, 0.0024)
			var root: Vector3 = rr[0]
			var d0: Vector3 = (Vector3(side * 0.07, -1.0, 0.04) + rr[1] * 0.02).normalized()
			var pts := HB._grow(root, d0, (0.34 + 0.03 * float(k)) * float(sp.get("hair_length", 1.0)),
				sp, {"steps": 11, "phase": _rng.randf(), "sway": 0.30,
				"flare": 0.05, "gravity": 2.4,
				"clear0": 0.005, "clear1": 0.010, "max_r": 0.112})
			guides.append({"points": pts, "bones": 8, "w0": 0.0150,
				"locks": 2, "lat": 0.012, "stiff": 0.12, "drag": 0.22, "grav": 1.7})

	# -------------------------------------------------------------- back
	var n_back := 14
	for i in n_back:
		var t := (float(i) + 0.5) / float(n_back)
		var az := lerpf(98.0, 262.0, t) + _rng.randf_range(-4.0, 4.0)
		var rr: Array = HB._scalp(0.070 + 0.014 * cos(t * PI) - _rng.randf_range(0.0, 0.012),
			az, sp, 0.0022)
		var root: Vector3 = rr[0]
		var rad := Vector3(root.x, 0.0, root.z).normalized()
		var d0: Vector3 = (rr[1] * 0.03 + Vector3.DOWN * 1.0 + rad * 0.05 + Vector3.FORWARD * 0.22).normalized()
		var pts := HB._grow(root, d0, (0.46 + 0.06 * cos(t * PI * 2.0)) * float(sp.get("hair_length", 1.0)),
			sp, {"steps": 12, "phase": _rng.randf(), "sway": 0.24,
			"flare": 0.05, "gravity": 2.3,
			"clear0": 0.005, "clear1": 0.012, "max_r": 0.115})
		guides.append({"points": pts, "bones": 9, "w0": 0.0150,
			"locks": 3, "lat": 0.013, "stiff": 0.10, "drag": 0.24, "grav": 1.9})

	# ------------------------------------------------------- short layer
	for i in 8:
		var t := (float(i) + 0.5) / 8.0
		var az := lerpf(104.0, 256.0, t) + _rng.randf_range(-5.0, 5.0)
		var rr: Array = HB._scalp(0.030 + _rng.randf_range(-0.006, 0.006), az, sp, 0.0030)
		var root: Vector3 = rr[0]
		var rad := Vector3(root.x, 0.0, root.z).normalized()
		var d0: Vector3 = (Vector3.DOWN * 1.0 + rad * 0.10 + Vector3.FORWARD * 0.10).normalized()
		var pts := HB._grow(root, d0, 0.19 * float(sp.get("hair_length", 1.0)),
			sp, {"steps": 7, "phase": _rng.randf(), "sway": 0.25,
			"flare": 0.03, "gravity": 2.3,
			"clear0": 0.010, "clear1": 0.016, "max_r": 0.108})
		guides.append({"points": pts, "bones": 6, "w0": 0.0140,
			"locks": 2, "lat": 0.011, "stiff": 0.18, "drag": 0.20, "grav": 1.6})

	# ------------------------------------------------------------ rig data
	var mb := MB.new()
	var bones := []      # {name, parent, local_rest, global_rest}
	var guides_out := []
	bones.append({"name": "hair_root", "parent": -1, "local": Transform3D.IDENTITY,
		"global": Transform3D.IDENTITY})
	for gidx in guides.size():
		var g: Dictionary = guides[gidx]
		var pts: Array = g["points"]
		var n_bones: int = maxi(pts.size() - 1, 4)
		var end_len: float = (Vector3(pts[pts.size() - 1]) - Vector3(pts[pts.size() - 2])).length()
		var glob := []
		for i in n_bones:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[mini(i + 1, pts.size() - 1)]
			var y := (b - a)
			if y.length_squared() < 1e-12:
				y = Vector3.DOWN
			y = y.normalized()
			var x := y.cross(Vector3.UP)
			if x.length_squared() < 1e-6:
				x = y.cross(Vector3.RIGHT)
			x = x.normalized()
			var z := x.cross(y).normalized()
			glob.append(Transform3D(Basis(x, y, z), a))
		var parent := 0
		var base := bones.size()
		for i in n_bones:
			var nm := "h_%02d_%02d" % [gidx, i]
			var local: Transform3D = bones[parent]["global"].affine_inverse() * glob[i]
			bones.append({"name": nm, "parent": parent, "local": local, "global": glob[i]})
			parent = base + i
		guides_out.append({"first": base, "end": base + n_bones - 1,
			"name0": "h_%02d_00" % gidx, "name1": "h_%02d_%02d" % [gidx, n_bones - 1],
			"stiff": g["stiff"], "drag": g["drag"], "grav": g["grav"],
			"end_len": maxf(end_len, 0.01)})
		# locks around this guide
		var n_locks: int = g["locks"]
		for li in n_locks:
			var u := 0.0 if n_locks == 1 else (float(li) / float(n_locks - 1) * 2.0 - 1.0)
			var lat: float = g["lat"] * u * _rng.randf_range(0.75, 1.15)
			var out := _rng.randf_range(-0.001, 0.0035)
			var w0: float = g["w0"] * _rng.randf_range(0.90, 1.15) * float(sp.get("hair_width", 1.0))
			_lock_into(mb, pts, n_bones, base, lat, out, w0, _rng.randf(),
				Color(1.0, 1.0, 1.0) * _rng.randf_range(0.93, 1.05))
		# central wide lock for coverage
		_lock_into(mb, pts, n_bones, base, 0.0, -0.0015, g["w0"] * 1.35 * float(sp.get("hair_width", 1.0)),
			_rng.randf(), Color(1, 1, 1))

	return {
		"mesh": mb.commit("hair_skinned"),
		"bones": bones,
		"guides": guides_out,
		"cap": build_scalp_shell(sp),
		"locks": lock_count,
	}


## Simple guaranteed scalp cover: an ellipsoid shell larger than the head,
## cut at the hairline in front and at the nape behind.  Dark, so any gap
## between locks reads as shadowed hair, never as a bald forehead.
static func build_scalp_shell(sp: Dictionary) -> ArrayMesh:
	var mb := MB.new()
	var segs := 96
	var rings := 26
	var cx := 0.0
	var cy := -0.010
	var cz := -0.004
	var rx := 0.0840
	var ry := 0.1190
	var rz := 0.1070
	var grid := []
	var norms := []
	for r in rings + 1:
		var tv := float(r) / float(rings)
		var row := []
		var nrow := []
		for s in segs:
			var phi := TAU * float(s) / float(segs)
			# hairline depth varies with azimuth (front short, back long)
			var az := absf(rad_to_deg(phi))
			if az > 180.0:
				az = 360.0 - az
			var th_max := 1.24
			if az > 55.0:
				th_max = lerpf(1.24, 1.70, clampf((az - 55.0) / 45.0, 0.0, 1.0))
			if az > 100.0:
				th_max = lerpf(1.70, 1.95, clampf((az - 100.0) / 80.0, 0.0, 1.0))
			var th := th_max * tv
			var p := Vector3(cx + rx * sin(th) * sin(phi),
				cy + ry * cos(th),
				cz + rz * sin(th) * cos(phi))
			var n := Vector3((p.x - cx) / (rx * rx), (p.y - cy) / (ry * ry),
				(p.z - cz) / (rz * rz)).normalized()
			row.append(p + n * 0.0018)
			nrow.append(n)
		grid.append(row)
		norms.append(nrow)
	for r in rings:
		for s in segs:
			var s1 := (s + 1) % segs
			var i0 := mb.add_vert(grid[r][s], norms[r][s], Vector2(float(s) / segs, float(r) / rings))
			var i1 := mb.add_vert(grid[r][s1], norms[r][s1], Vector2(float(s + 1) / segs, float(r) / rings))
			var i2 := mb.add_vert(grid[r + 1][s1], norms[r + 1][s1], Vector2(float(s + 1) / segs, float(r + 1) / rings))
			var i3 := mb.add_vert(grid[r + 1][s], norms[r + 1][s], Vector2(float(s) / segs, float(r + 1) / rings))
			var g: Vector3 = (norms[r][s] + norms[r][s1] + norms[r + 1][s] + norms[r + 1][s1]).normalized()
			mb.add_quad(i0, i1, i2, i3, g)
	return mb.commit("scalp_shell")


## Builds one lock around a guide path, with 2-bone-per-vertex skinning.
static func _lock_into(mb: MB, guide_pts: Array, n_bones: int, bone_base: int,
		lat: float, out_off: float, w0: float, phase: float, tint: Color) -> void:
	lock_count += 1
	var n := guide_pts.size()
	if n < 3:
		return
	# offset path: lateral + outward
	var pts := []
	for i in n:
		var p: Vector3 = guide_pts[i]
		var a: Vector3 = guide_pts[maxi(i - 1, 0)]
		var b: Vector3 = guide_pts[mini(i + 1, n - 1)]
		var tan := (b - a)
		if tan.length_squared() < 1e-10:
			tan = Vector3.DOWN
		tan = tan.normalized()
		var rad := Vector3(p.x, 0.0, p.z)
		if rad.length_squared() < 1e-8:
			rad = Vector3.FORWARD
		rad = rad.normalized()
		var sid := tan.cross(rad).normalized()
		var taper := pow(clampf(float(i) / float(n - 1), 0.0, 1.0), 1.6)
		pts.append(p + sid * lat * taper + rad * out_off * taper)
	var widths := HB._widths(n, w0, 0.78, 0.58, 0.15)
	var thick := maxf(w0 * 0.28, 0.0012)
	var cs := 10
	var rings := []
	var nrings := []
	var tans := []
	for i in n:
		var t: Vector3
		if i == 0:
			t = pts[1] - pts[0]
		elif i == n - 1:
			t = pts[n - 1] - pts[n - 2]
		else:
			t = pts[i + 1] - pts[i - 1]
		if t.length_squared() < 1e-12:
			t = Vector3.DOWN
		t = t.normalized()
		tans.append(t)
	for i in n:
		var t: Vector3 = tans[i]
		var hint: Vector3 = pts[i] - Vector3(0.0, -0.02, -0.01)
		var nrm: Vector3 = hint - t * hint.dot(t)
		if nrm.length_squared() < 1e-10:
			nrm = t.cross(Vector3.RIGHT)
		nrm = nrm.normalized()
		var bnr: Vector3 = t.cross(nrm).normalized()
		var w: float = widths[i]
		var tt := thick
		if i == n - 1:
			w = minf(w, 0.0005)
			tt = minf(tt, 0.0003)
		var row := []
		var nrow := []
		for j in cs:
			var ang := TAU * float(j) / float(cs)
			var bo := cos(ang) * w
			var no := sin(ang) * tt
			var p: Vector3 = pts[i] + bnr * bo + nrm * no
			var nn: Vector3 = (bnr * (bo / maxf(w * w, 1e-9)) + nrm * (no / maxf(tt * tt, 1e-9))).normalized()
			row.append(p)
			nrow.append(nn)
		rings.append(row)
		nrings.append(nrow)
	for i in n - 1:
		var t0 := float(i) / float(n - 1)
		var t1 := float(i + 1) / float(n - 1)
		var bf0 := t0 * float(n_bones)
		var bf1 := t1 * float(n_bones)
		var b00 := clampi(int(floor(bf0)), 0, n_bones - 1)
		var b10 := clampi(b00 + 1, 0, n_bones - 1)
		var f0 := clampf(bf0 - float(b00), 0.0, 1.0)
		var b01 := clampi(int(floor(bf1)), 0, n_bones - 1)
		var b11 := clampi(b01 + 1, 0, n_bones - 1)
		var f1 := clampf(bf1 - float(b01), 0.0, 1.0)
		for j in cs:
			var j1 := (j + 1) % cs
			var i0 := mb.add_vert(rings[i][j], nrings[i][j], Vector2(0.0, t0), Vector2(phase, t0), tint)
			var i1 := mb.add_vert(rings[i][j1], nrings[i][j1], Vector2(1.0, t0), Vector2(phase, t0), tint)
			var i2 := mb.add_vert(rings[i + 1][j1], nrings[i + 1][j1], Vector2(1.0, t1), Vector2(phase, t1), tint)
			var i3 := mb.add_vert(rings[i + 1][j], nrings[i + 1][j], Vector2(0.0, t1), Vector2(phase, t1), tint)
			mb.set_tangent(i0, tans[i])
			mb.set_tangent(i1, tans[i])
			mb.set_tangent(i2, tans[i + 1])
			mb.set_tangent(i3, tans[i + 1])
			mb.set_skin(i0, [bone_base + b00, bone_base + b10, 0, 0], [1.0 - f0, f0, 0, 0])
			mb.set_skin(i1, [bone_base + b00, bone_base + b10, 0, 0], [1.0 - f0, f0, 0, 0])
			mb.set_skin(i2, [bone_base + b01, bone_base + b11, 0, 0], [1.0 - f1, f1, 0, 0])
			mb.set_skin(i3, [bone_base + b01, bone_base + b11, 0, 0], [1.0 - f1, f1, 0, 0])
			var g: Vector3 = (nrings[i][j] + nrings[i][j1] + nrings[i + 1][j] + nrings[i + 1][j1]).normalized()
			mb.add_quad(i0, i1, i2, i3, g)
	# caps
	for endi in [0, n - 1]:
		var c: Vector3 = Vector3.ZERO
		for p in rings[endi]:
			c += p
		c /= float(cs)
		var cd: Vector3 = -tans[endi] if endi == 0 else tans[endi]
		var b := 0 if endi == 0 else n_bones - 1
		var ci := mb.add_vert(c, cd, Vector2(0.5, 0.5), Vector2(phase, 0.0), tint)
		mb.set_tangent(ci, cd)
		mb.set_skin(ci, [bone_base + b, 0, 0, 0], [1.0, 0.0, 0.0, 0.0])
		for j in cs:
			var j1 := (j + 1) % cs
			var i0 := mb.add_vert(rings[endi][j], nrings[endi][j], Vector2.ZERO, Vector2(phase, 0.0), tint)
			var i1 := mb.add_vert(rings[endi][j1], nrings[endi][j1], Vector2.ONE, Vector2(phase, 0.0), tint)
			mb.set_tangent(i0, tans[endi])
			mb.set_tangent(i1, tans[endi])
			mb.set_skin(i0, [bone_base + b, 0, 0, 0], [1.0, 0.0, 0.0, 0.0])
			mb.set_skin(i1, [bone_base + b, 0, 0, 0], [1.0, 0.0, 0.0, 0.0])
			mb.add_tri(ci, i0, i1, cd)


static func _build_scalp_cap(sp: Dictionary) -> ArrayMesh:
	return HB._build_cap(sp).commit("hair_cap")