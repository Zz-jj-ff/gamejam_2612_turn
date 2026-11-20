extends Node3D
class_name ArcRig
## ARC // SENTINEL v2 — skeleton + procedural geometry.
##
## Two-wheel balancer: fixed axles under an independently sprung chassis, a
## cylindrical front/back hull with a large camera objective, a rear shield
## hook, a left sheath, and two 3-ball-joint arms. Everything is generated from
## code; geometry is merged per (joint, material) to keep draw calls low.

const MK := preload("res://scripts/kit/mesh_kit.gd")
const SK := preload("res://scripts/kit/shape_kit.gd")
const AM := preload("res://scripts/ch/arc_materials.gd")
const KIN := preload("res://scripts/ch/arc_kin.gd")
const D2R := PI / 180.0
const TAU := PI * 2.0

var J: Dictionary = {}
var P: Dictionary = {}
var kin: ArcKin2

var marker_tip: Node3D
var marker_base: Node3D
var shield_node: Node3D
var blade_fx: Node3D
var blade_core: MeshInstance3D
var blade_light: OmniLight3D
var lens_node: Node3D

var _susp_nodes: Dictionary = {}
var _shock_nodes: Dictionary = {}

var body_y := 0.620
var torso_y := 0.160
var hull_y := 0.280
var hull_r := 0.225
var hull_half := 0.260
var shoulder_x := 0.270
var shoulder_y := 0.320
var shoulder_z := 0.020
var L1 := 0.340
var L2 := 0.330
var L3 := 0.130
var cam_y := 0.280
var cam_z := 0.330
var back_y := 0.280
var back_z := -0.300
var shield_off := 0.110
var wheel_x := 0.450
var wheel_y := 0.325
var wheel_r := 0.325


# ================================================================== build

func build(p: Dictionary) -> void:
	P = p.duplicate()
	kin = KIN.new(P)
	_dims()
	for c in get_children():
		c.free()
	J.clear()
	_susp_nodes.clear()
	_shock_nodes.clear()
	_build_skeleton()
	_build_body_geo()
	_build_camera_geo()
	_build_rear_geo()
	_build_sheath_geo()
	_build_wheel_geo(1)
	_build_wheel_geo(-1)
	_build_susp_geo()
	_build_arm_geo(1)
	_build_arm_geo(-1)
	_build_shield_geo()
	_build_blade_geo()
	_build_lights()
	apply_pose({})


func _dims() -> void:
	body_y = kin.body_y
	torso_y = kin.torso_y
	hull_y = kin.hull_y
	hull_r = kin.hull_r
	hull_half = kin.hull_half
	shoulder_x = kin.shoulder_x
	shoulder_y = kin.shoulder_y
	shoulder_z = kin.shoulder_z
	L1 = kin.L1
	L2 = kin.L2
	L3 = kin.L3
	cam_y = kin.cam_y
	cam_z = kin.cam_z
	back_y = kin.back_y
	back_z = kin.back_z
	shield_off = kin.shield_off
	wheel_x = kin.wheel_x
	wheel_y = kin.wheel_y
	wheel_r = kin.wheel_r


func _node(parent: Node3D, nm: String, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = nm
	n.position = pos
	parent.add_child(n)
	J[nm] = n
	return n


func _build_skeleton() -> void:
	var body := _node(self, "body", Vector3(0, body_y, 0))
	_node(body, "chassis", Vector3(0, 0.060, 0))
	var torso := _node(body, "torso", Vector3(0, torso_y, 0))
	var cam_yaw := _node(torso, "camera_yaw", Vector3(0, kin.cam_y, kin.cam_z - 0.020))
	var lens_yaw := _node(cam_yaw, "lens_yaw", Vector3(0, 0, 0.065))
	lens_node = _node(lens_yaw, "lens_pitch", Vector3.ZERO)
	# arms
	for s in [1, -1]:
		var nm := "L" if s > 0 else "R"
		var sh := _node(torso, "sh" + nm,
			Vector3(float(s) * shoulder_x, shoulder_y, shoulder_z))
		var el := _node(sh, "elb" + nm, Vector3(0, -L1, 0))
		var wr := _node(el, "wr" + nm, Vector3(0, -L2, 0))
		var tool := _node(wr, "tool" + nm, Vector3(0, -L3, 0))
		if s > 0:
			var gim := _node(tool, "shield_gimbal", Vector3(0, 0, kin.shield_off))
			shield_node = _node(gim, "shield", Vector3.ZERO)
			# shield is built facing +Z in its local frame
		else:
			var bfx := _node(tool, "blade_fx", Vector3.ZERO)
			bfx.rotation.x = PI
			blade_fx = bfx
			marker_base = _node(tool, "marker_base", Vector3.ZERO)
			marker_tip = _node(tool, "marker_tip", Vector3(0, -kin.blade_len, 0))
	# wheels + suspension are under the rig root (axles stay on the ground)
	for s in [1, -1]:
		var nm2 := "L" if s > 0 else "R"
		var axle := _node(self, "wheel" + nm2,
			Vector3(float(s) * wheel_x, wheel_y, 0.0))
		axle.set_meta("side", s)
		var susp := _node(self, "susp" + nm2, Vector3.ZERO)
		_susp_nodes[nm2] = susp
		var shock := _node(self, "shock" + nm2, Vector3.ZERO)
		_shock_nodes[nm2] = shock


# ================================================================== geo utils

func _bake(node: Node3D, parts: Array) -> void:
	for e in SK.bake(parts):
		var mi := MeshInstance3D.new()
		mi.mesh = e["mesh"]
		mi.material_override = e["mat"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.add_child(mi)


func _p(parts: Array, mesh: Mesh, mat: Material, pos := Vector3.ZERO,
		rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> void:
	if mesh == null:
		return
	var b := Basis.from_euler(rot_deg * D2R)
	if scl != Vector3.ONE:
		b = b * Basis.from_scale(scl)
	parts.append({"mesh": mesh, "mat": mat, "xf": Transform3D(b, pos)})


func _disc(parts: Array, r: float, t: float, sides: int, pos: Vector3,
		axis: Vector3, mat: Material, bevel := 0.0, hint := Vector3.RIGHT) -> void:
	parts.append({"mesh": MK.disc(r, t, sides, bevel), "mat": mat,
		"xf": Transform3D(SK.basis_y(axis, hint), pos)})


func _ring(parts: Array, r_in: float, r_out: float, t: float, sides: int,
		pos: Vector3, axis: Vector3, mat: Material, bevel := 0.0,
		hint := Vector3.RIGHT) -> void:
	parts.append({"mesh": MK.ring(r_in, r_out, t, sides, bevel), "mat": mat,
		"xf": Transform3D(SK.basis_y(axis, hint), pos)})


## Smooth elliptical loft along +Z. sections: [{z, rx, ry}]
func _z_loft(sections: Array, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for s in sections:
		var ring: Array[Vector3] = []
		var nrm: Array[Vector3] = []
		var rx: float = s["rx"]
		var ry: float = s["ry"]
		for i in sides:
			var a := TAU * float(i) / float(sides)
			ring.append(Vector3(cos(a) * rx, sin(a) * ry, float(s["z"])))
			nrm.append(Vector3(cos(a) / maxf(rx, 0.001), sin(a) / maxf(ry, 0.001), 0).normalized())
		rings.append({"p": ring, "n": nrm})
	for r in rings.size() - 1:
		var a: Dictionary = rings[r]
		var b: Dictionary = rings[r + 1]
		for i in sides:
			var j := (i + 1) % sides
			var p0: Vector3 = a["p"][i]
			var p1: Vector3 = a["p"][j]
			var p2: Vector3 = b["p"][j]
			var p3: Vector3 = b["p"][i]
			var n0: Vector3 = a["n"][i]
			var n1: Vector3 = a["n"][j]
			var n2: Vector3 = b["n"][j]
			var n3: Vector3 = b["n"][i]
			_quad_n(st, p0, p1, p2, p3, n0, n1, n2, n3)
	# caps
	var first: Dictionary = rings[0]
	var last: Dictionary = rings[rings.size() - 1]
	var z0 := float(sections[0]["z"])
	var z1 := float(sections[sections.size() - 1]["z"])
	var c0 := Vector3(0, 0, z0)
	var c1 := Vector3(0, 0, z1)
	for i in sides:
		var j := (i + 1) % sides
		_tri(st, c0, first["p"][j], first["p"][i], Vector3.BACK)
		_tri(st, c1, last["p"][i], last["p"][j], Vector3.FORWARD)
	return st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, guide: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-12:
		return
	if n.dot(guide) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	n = n.normalized()
	# Godot's front faces are clockwise; emit the triangle CW.
	st.set_normal(n)
	st.add_vertex(a)
	st.set_normal(n)
	st.add_vertex(c)
	st.set_normal(n)
	st.add_vertex(b)


func _quad_n(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3) -> void:
	var g := (b - a).cross(c - a)
	if g.length_squared() < 1e-12:
		return
	var flip := g.dot(na + nb + nc + nd) < 0.0
	var p := [a, b, c, d]
	var n := [na, nb, nc, nd]
	if flip:
		p = [a, d, c, b]
		n = [na, nd, nc, nb]
	# Godot's front faces are clockwise; emit the quad CW.
	for idx in [0, 2, 1, 0, 3, 2]:
		st.set_normal(n[idx])
		st.add_vertex(p[idx])


## Unit coil spring along +Y (0..1), meant to be scaled along Y.
func _coil_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 12
	var h := 1.0
	var tor := MK.ring(0.026, 0.046, 0.012, 20, 0.002)
	for i in rings:
		var y := (float(i) + 0.5) / float(rings) * h
		SK.stack(st, tor, Transform3D(Basis.IDENTITY, Vector3(0, y, 0)))
	SK.stack(st, MK.prism(10, 0.018, 0.018, h, 0.0),
		Transform3D(Basis.IDENTITY, Vector3(0, h * 0.5, 0)))
	return st.commit()


# ================================================================== body

func _build_body_geo() -> void:
	var body: Node3D = J["body"]
	var torso: Node3D = J["torso"]
	var hull := AM.hull()
	var hull2 := AM.hull_soft()
	var steel := AM.steel()
	var steel_d := AM.steel_dark()
	var orange := AM.orange_panel()
	var orange_d := AM.orange_deep()
	var joint := AM.joint()
	var emis := AM.signal_orange()

	var parts: Array = []
	# chassis + waist
	_p(parts, SK.loft([
		{"y": -0.075, "w": 0.250, "d": 0.200, "c": 0.32},
		{"y": 0.010, "w": 0.350, "d": 0.280, "c": 0.28},
		{"y": 0.090, "w": 0.310, "d": 0.250, "c": 0.30},
	]), hull2)
	_p(parts, SK.loft([
		{"y": 0.075, "w": 0.220, "d": 0.190, "c": 0.26},
		{"y": 0.160, "w": 0.200, "d": 0.180, "c": 0.26},
	]), steel_d)
	_ring(parts, 0.095, 0.125, 0.030, 28, Vector3(0, 0.170, 0), Vector3.UP, steel)
	_ring(parts, 0.080, 0.105, 0.024, 24, Vector3(0, 0.198, 0), Vector3.UP, orange)
	# chassis side armour + orange seam
	for s in [1, -1]:
		_p(parts, MK.plate(0.185, 0.110, 0.020, 0.006), orange_d,
			Vector3(float(s) * 0.176, 0.020, 0.0), Vector3(0, 90, 0))
		_p(parts, MK.plate(0.150, 0.035, 0.008, 0.002), emis,
			Vector3(float(s) * 0.188, 0.020, 0.0), Vector3(0, 90, 0))
		# suspension shoulder pods
		_p(parts, MK.sphere(0.085, 20, 14, true), steel_d,
			Vector3(float(s) * 0.300, 0.020, -0.020))
		_ring(parts, 0.070, 0.090, 0.026, 26,
			Vector3(float(s) * 0.300, 0.020, -0.020), Vector3(float(s), 0, 0), orange, 0.004)
	# underside skid
	_p(parts, MK.plate(0.240, 0.020, 0.380, 0.008), steel_d, Vector3(0, -0.070, 0.0))
	# rear service block
	_p(parts, SK.loft([
		{"y": 0.020, "w": 0.190, "d": 0.120, "c": 0.30},
		{"y": 0.120, "w": 0.160, "d": 0.100, "c": 0.30},
	]), steel_d, Vector3(0, 0.0, -0.200))
	_bake(body, parts)

	# ---- torso hull (cylinder axis = Z)
	var hp: Array = []
	_p(hp, _z_loft([
		{"z": -0.270, "rx": 0.190, "ry": 0.200},
		{"z": -0.245, "rx": 0.222, "ry": 0.230},
		{"z": -0.100, "rx": 0.228, "ry": 0.238},
		{"z": 0.100, "rx": 0.228, "ry": 0.238},
		{"z": 0.245, "rx": 0.222, "ry": 0.230},
		{"z": 0.270, "rx": 0.190, "ry": 0.200},
	], 32), hull, Vector3(0, hull_y, 0))
	# Explicit solid front/back caps.  The custom z-loft caps are kept as a
	# fallback, but these mesh-kit discs guarantee an opaque hull end (the old
	# back face could be culled, showing the camera lens through the body).
	_disc(hp, 0.190, 0.014, 40, Vector3(0, hull_y, -0.270), Vector3.BACK, hull, 0.003)
	_disc(hp, 0.190, 0.014, 40, Vector3(0, hull_y, 0.270), Vector3.FORWARD, hull, 0.003)
	# circumferential armour bands
	for z in [-0.200, 0.0, 0.200]:
		_ring(hp, 0.224, 0.246, 0.022, 40, Vector3(0, hull_y, z),
			Vector3.FORWARD, steel, 0.004)
		_ring(hp, 0.232, 0.240, 0.006, 40, Vector3(0, hull_y, z + 0.014),
			Vector3.FORWARD, orange, 0.001)
	# top deck
	_p(hp, MK.plate(0.300, 0.400, 0.030, 0.008), hull2,
		Vector3(0, hull_y + hull_r - 0.006, 0.0), Vector3(90, 0, 0))
	_p(hp, MK.plate(0.230, 0.330, 0.014, 0.004), steel_d,
		Vector3(0, hull_y + hull_r + 0.012, -0.010), Vector3(90, 0, 0))
	for i in 4:
		_p(hp, MK.plate(0.030, 0.090, 0.008, 0.002), joint,
			Vector3(-0.075 + float(i) * 0.050, hull_y + hull_r + 0.020, -0.030),
			Vector3(90, 0, 0))
	# status bar on the deck
	_p(hp, MK.plate(0.140, 0.014, 0.006, 0.002), emis,
		Vector3(0, hull_y + hull_r + 0.022, 0.160), Vector3(90, 0, 0))
	# side panels (orange + vent slits)
	for s in [1, -1]:
		_p(hp, MK.plate(0.185, 0.145, 0.020, 0.006), orange,
			Vector3(float(s) * 0.226, hull_y, 0.020), Vector3(0, 90, 0))
		for k in 3:
			_p(hp, MK.plate(0.110, 0.018, 0.006, 0.002), joint,
				Vector3(float(s) * 0.236, hull_y + 0.045 - float(k) * 0.045, 0.020),
				Vector3(0, 90, 0))
		# shoulder mount block
		_p(hp, SK.loft([
			{"y": -0.070, "w": 0.100, "d": 0.100, "c": 0.30},
			{"y": 0.070, "w": 0.080, "d": 0.085, "c": 0.30},
		]), hull2, Vector3(float(s) * 0.250, shoulder_y - 0.030, shoulder_z))
	# front collar ring
	_ring(hp, 0.172, 0.205, 0.030, 36, Vector3(0, hull_y, 0.262),
		Vector3.FORWARD, steel, 0.005)
	# bottom keel
	_p(hp, SK.loft([
		{"y": -0.060, "w": 0.150, "d": 0.200, "c": 0.32},
		{"y": 0.000, "w": 0.230, "d": 0.300, "c": 0.30},
	]), hull2, Vector3(0, hull_y - hull_r + 0.010, 0.0))
	# small rear-upper antenna / sensor pod (not a head)
	_p(hp, SK.beam(Vector3(0.075, hull_y + hull_r - 0.01, -0.120),
		Vector3(0.115, hull_y + hull_r + 0.090, -0.155), 0.030, 0.030, 0.018, 0.018,
		0.30, Vector3.UP, 0.004), steel_d)
	_p(hp, MK.sphere(0.022, 12, 8, true), emis,
		Vector3(0.116, hull_y + hull_r + 0.094, -0.156))
	_bake(torso, hp)


func _build_camera_geo() -> void:
	var torso: Node3D = J["torso"]
	var cam_yaw: Node3D = J["camera_yaw"]
	var lens: Node3D = J["lens_yaw"]
	var hull2 := AM.hull_soft()
	var steel_d := AM.steel_dark()
	var joint := AM.joint()
	var orange := AM.orange_panel()
	var emis := AM.signal_orange()

	# Armoured iris/socket on the hull front.  It is a closed static plate, so
	# the small ball never opens a see-through gap.
	var ip: Array = []
	_disc(ip, 0.126, 0.014, 40, Vector3(0, hull_y, 0.269), Vector3.FORWARD, joint, 0.003)
	_ring(ip, 0.106, 0.126, 0.012, 40, Vector3(0, hull_y, 0.274), Vector3.FORWARD, orange, 0.002)
	_disc(ip, 0.026, 0.008, 20, Vector3(0, hull_y, 0.278), Vector3.FORWARD, emis, 0.001)
	_bake(torso, ip)

	# The ball is the eye housing and stays outside the hull.  Only the barrel
	# telescopes back into this closed ball; the ball never enters the body,
	# so no interior can be exposed during an attack.
	var hp: Array = []
	_p(hp, MK.sphere(0.115, 32, 20, true), hull2, Vector3.ZERO)
	_ring(hp, 0.110, 0.118, 0.006, 32, Vector3(0, 0, 0.034),
		Vector3.FORWARD, orange, 0.001)
	_bake(cam_yaw, hp)

	# Barrel lives on the sliding lens node (local z = 0..0.14); when it
	# retracts, its front disappears inside the solid ball.
	var lp: Array = []
	_p(lp, MK.prism(28, 0.092, 0.086, 0.120, 0.0), hull2,
		Vector3(0, 0, 0.055), Vector3(90, 0, 0))
	_ring(lp, 0.084, 0.098, 0.014, 36, Vector3(0, 0, 0.118),
		Vector3.FORWARD, steel_d, 0.003)
	_ring(lp, 0.078, 0.088, 0.008, 36, Vector3(0, 0, 0.127),
		Vector3.FORWARD, orange, 0.001)
	_p(lp, MK.dome(0.080, 0.014, 40, 12, true), AM.lens(), Vector3(0, 0, 0.128),
		Vector3(90, 0, 0))
	_ring(lp, 0.024, 0.034, 0.006, 32, Vector3(0, 0, 0.140),
		Vector3.FORWARD, emis, 0.001)
	_bake(lens, lp)


func _build_rear_geo() -> void:
	var torso: Node3D = J["torso"]
	var hull2 := AM.hull_soft()
	var steel := AM.steel()
	var steel_d := AM.steel_dark()
	var orange := AM.orange_panel()
	var emis := AM.signal_orange()

	var parts: Array = []
	# rear dome
	_p(parts, MK.dome(0.200, 0.090, 40, 12, true), hull2,
		Vector3(0, hull_y, -0.262), Vector3(-90, 0, 0))
	_ring(parts, 0.176, 0.204, 0.026, 36, Vector3(0, hull_y, -0.280),
		Vector3.BACK, steel, 0.004)
	_ring(parts, 0.120, 0.136, 0.014, 32, Vector3(0, hull_y, -0.350),
		Vector3.BACK, orange, 0.002)
	_disc(parts, 0.100, 0.014, 32, Vector3(0, hull_y, -0.342),
		Vector3.BACK, steel_d, 0.003)
	# 4 radial fins on the rear dome
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.785
		_p(parts, MK.plate(0.024, 0.130, 0.030, 0.005), steel_d,
			Vector3(cos(a) * 0.130, hull_y + sin(a) * 0.130, -0.330),
			Vector3(0, 0, rad_to_deg(a)))
	# shield hook: two prongs + crossbar + magnetic pad
	for s in [1, -1]:
		_p(parts, SK.beam(Vector3(float(s) * 0.090, hull_y + 0.010, -0.300),
			Vector3(float(s) * 0.105, hull_y + 0.010, -0.420),
			0.045, 0.055, 0.035, 0.042, 0.30, Vector3.UP, 0.004), steel_d)
		_p(parts, MK.sphere(0.030, 14, 10, true), orange,
			Vector3(float(s) * 0.105, hull_y + 0.010, -0.430))
	_p(parts, SK.beam(Vector3(-0.105, hull_y + 0.010, -0.405),
		Vector3(0.105, hull_y + 0.010, -0.405), 0.040, 0.040, 0.040, 0.040,
		0.30, Vector3.UP, 0.004), steel)
	_p(parts, MK.disc(0.060, 0.018, 28, 0.004), emis,
		Vector3(0, hull_y + 0.010, -0.424), Vector3(90, 0, 0))
	# rear service vents
	for i in 3:
		_p(parts, MK.plate(0.150, 0.016, 0.010, 0.002), steel_d,
			Vector3(0, hull_y - 0.120 - float(i) * 0.030, -0.245),
			Vector3(90, 0, 0))
	_bake(torso, parts)


func _build_sheath_geo() -> void:
	var body: Node3D = J["body"]
	var a := kin.sheath_a
	var b := kin.sheath_b
	var dir := (b - a).normalized()
	var bp := Basis(Vector3.UP, atan2(dir.x, dir.z))
	var hull2 := AM.hull_soft()
	var steel := AM.steel_dark()
	var orange := AM.orange_panel()
	var emis := AM.signal_orange()
	var parts: Array = []
	# main scabbard body
	_p(parts, SK.beam(a, b, 0.100, 0.078, 0.070, 0.052, 0.30, Vector3.UP, 0.006),
		hull2)
	# mouth collar
	var mouth := a + dir * 0.012
	_ring(parts, 0.040, 0.062, 0.032, 24, mouth, dir, steel, 0.003)
	_ring(parts, 0.036, 0.048, 0.010, 24, mouth + dir * 0.018, dir, emis, 0.001)
	# tip cap
	_ring(parts, 0.028, 0.042, 0.020, 20, b - dir * 0.006, dir, steel, 0.002)
	# orange seam along the outward face
	var side := Vector3(0, 1, 0).cross(dir).normalized()
	var outward := dir.cross(side).normalized()
	if outward.dot(Vector3(1, 0, 0)) < 0:
		outward = -outward
	var mid := (a + b) * 0.5
	_p(parts, MK.plate(0.014, (b - a).length() * 0.62, 0.006, 0.002), emis,
		mid + outward * 0.052, Vector3(rad_to_deg(asin(dir.y)), rad_to_deg(atan2(dir.x, dir.z)), 0))
	# two mounting clamps to the chassis
	for t in [0.25, 0.68]:
		var p := a.lerp(b, t)
		_p(parts, SK.beam(p, p + Vector3(-0.08, 0.02, 0.0), 0.045, 0.030, 0.035, 0.024,
			0.30, Vector3.UP, 0.003), steel)
	_bake(body, parts)


func _build_wheel_geo(side: int) -> void:
	var nm := "L" if side > 0 else "R"
	var node: Node3D = J["wheel" + nm]
	var tire := AM.tire()
	var tread := AM.tread()
	var hub := AM.steel_dark()
	var steel := AM.steel()
	var orange := AM.orange_panel()
	var emis := AM.signal_orange()
	var parts: Array = []
	# solid tyre (no spokes)
	_disc(parts, wheel_r, 0.150, 48, Vector3.ZERO, Vector3.RIGHT, tire, 0.020)
	# side face rings
	for sx in [1, -1]:
		var x := float(sx) * 0.078
		_ring(parts, 0.225, 0.262, 0.012, 40, Vector3(x, 0, 0), Vector3.RIGHT, hub, 0.002)
		_ring(parts, 0.178, 0.196, 0.010, 36, Vector3(x, 0, 0), Vector3.RIGHT, hub, 0.002)
		_ring(parts, 0.130, 0.144, 0.008, 32, Vector3(x, 0, 0), Vector3.RIGHT, orange, 0.001)
		_disc(parts, 0.105, 0.020, 32, Vector3(x, 0, 0), Vector3.RIGHT, steel, 0.004)
		_disc(parts, 0.055, 0.026, 24, Vector3(float(sx) * 0.086, 0, 0), Vector3.RIGHT, hub, 0.003)
		_disc(parts, 0.022, 0.028, 16, Vector3(float(sx) * 0.094, 0, 0), Vector3.RIGHT, emis, 0.002)
		# 6 hub bolts
		for i in 6:
			var a := TAU * float(i) / 6.0
			_p(parts, MK.prism(6, 0.010, 0.008, 0.018, 0.0), steel,
				Vector3(float(sx) * 0.090, cos(a) * 0.080, sin(a) * 0.080),
				Vector3(0, 0, 90))
	# glowing ring on the outboard cylinder face (one per wheel)
	_ring(parts, 0.270, 0.288, 0.010, 48, Vector3(float(side) * 0.082, 0, 0),
		Vector3.RIGHT, emis, 0.002)
	# tread plates (armour ring)
	var n := 18
	for i in n:
		var a := TAU * float(i) / float(n)
		var tangent := Vector3(0, sin(a), -cos(a)).normalized()
		var radial := Vector3(0, cos(a), sin(a)).normalized()
		var x := Vector3(1, 0, 0)
		var basis := Basis(x, tangent, radial)
		var pos := radial * (wheel_r - 0.006)
		parts.append({"mesh": MK.plate(0.150, 0.098, 0.030, 0.006),
			"mat": tread if i % 3 != 0 else orange, "xf": Transform3D(basis, pos)})
		# steel ridge on each plate
		parts.append({"mesh": MK.plate(0.120, 0.020, 0.012, 0.002),
			"mat": steel, "xf": Transform3D(basis, pos + radial * 0.020)})
		# dark machined groove + two rivets + an orange wear edge
		parts.append({"mesh": MK.plate(0.112, 0.009, 0.007, 0.002),
			"mat": hub, "xf": Transform3D(basis, pos + radial * 0.016)})
		for rx in [-0.054, 0.054]:
			parts.append({"mesh": MK.sphere(0.0085, 10, 8, true), "mat": steel,
				"xf": Transform3D(Basis.IDENTITY,
					pos + basis * Vector3(float(rx), 0.0, 0.017))})
		parts.append({"mesh": MK.plate(0.150, 0.007, 0.005, 0.001),
			"mat": orange if i % 3 == 0 else steel,
			"xf": Transform3D(basis, pos + basis * Vector3(0.0, 0.046, 0.017))})
	_bake(node, parts)


func _build_susp_geo() -> void:
	for side in [1, -1]:
		var nm := "L" if side > 0 else "R"
		# A telescopic strut from the body mount to the inboard hub carrier,
		# with the coil spring sleeved directly over the rod.  The whole unit
		# is stretched between the two points, so rod, sleeve and spring
		# extend/compress together (no separate lever arm crossing the wheel).
		var strut: Array = []
		_p(strut, SK.beam(Vector3(0, 0.42, 0), Vector3(0, 1.0, 0),
			0.034, 0.034, 0.028, 0.028, 0.15, Vector3.FORWARD, 0.003),
			AM.steel())
		_p(strut, SK.beam(Vector3(0, 0.0, 0), Vector3(0, 0.62, 0),
			0.018, 0.018, 0.016, 0.016, 0.10, Vector3.FORWARD, 0.002),
			AM.steel_dark())
		_p(strut, MK.disc(0.050, 0.022, 20, 0.004), AM.steel_dark(),
			Vector3(0, 0.985, 0), Vector3(90, 0, 0))
		_p(strut, MK.disc(0.046, 0.020, 20, 0.004), AM.steel_dark(),
			Vector3(0, 0.012, 0), Vector3(90, 0, 0))
		# spring: 12-coil unit, scaled down and fitted between the seats
		strut.append({"mesh": _coil_mesh(), "mat": AM.orange_metal(),
			"xf": Transform3D(Basis.IDENTITY.scaled(Vector3(0.85, 0.62, 0.85)),
				Vector3(0, 0.19, 0))})
		_p(strut, MK.disc(0.052, 0.014, 20, 0.003), AM.steel(),
			Vector3(0, 0.19, 0), Vector3(90, 0, 0))
		_p(strut, MK.disc(0.052, 0.014, 20, 0.003), AM.steel(),
			Vector3(0, 0.81, 0), Vector3(90, 0, 0))
		for e in SK.bake(strut):
			var mi := MeshInstance3D.new()
			mi.mesh = e["mesh"]
			mi.material_override = e["mat"]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			(_susp_nodes[nm] as Node3D).add_child(mi)
		# static hub carrier; a short axle pin reaches the wheel's inner face
		var hub_node := _node(self, "hub" + nm,
			Vector3(float(side) * (wheel_x - 0.115), wheel_y, 0.0))
		var hp: Array = []
		_disc(hp, 0.082, 0.030, 28, Vector3.ZERO, Vector3(float(side), 0, 0),
			AM.steel_dark(), 0.004)
		_ring(hp, 0.060, 0.076, 0.012, 24,
			Vector3(float(side) * 0.018, 0, 0), Vector3(float(side), 0, 0),
			AM.orange_panel(), 0.002)
		_p(hp, MK.prism(16, 0.022, 0.022, 0.060, 0.0), AM.steel(),
			Vector3(float(side) * 0.030, 0, 0), Vector3(0, 0, 90))
		_bake(hub_node, hp)


# ================================================================== arms

func _build_arm_geo(side: int) -> void:
	var nm := "L" if side > 0 else "R"
	var sh: Node3D = J["sh" + nm]
	var el: Node3D = J["elb" + nm]
	var wr: Node3D = J["wr" + nm]
	var tool: Node3D = J["tool" + nm]
	var hull2 := AM.hull_soft()
	var steel := AM.steel()
	var steel_d := AM.steel_dark()
	var orange := AM.orange_panel()
	var emis := AM.signal_orange()
	var joint := AM.joint()

	# shoulder ball + socket
	var sp: Array = []
	_p(sp, MK.sphere(0.098, 24, 16, true), hull2)
	_ring(sp, 0.088, 0.106, 0.018, 28, Vector3(0, 0.065, 0), Vector3.UP, orange, 0.002)
	_p(sp, MK.disc(0.040, 0.012, 20, 0.002), emis, Vector3(0, 0.070, 0), Vector3(0, 0, 0))
	_bake(sh, sp)
	# upper arm
	var up: Array = []
	_p(up, SK.beam(Vector3(0, -0.070, 0), Vector3(0, -L1 + 0.070, 0),
		0.086, 0.082, 0.072, 0.068, 0.30, Vector3.FORWARD, 0.008), hull2)
	_p(up, MK.plate(0.060, L1 * 0.44, 0.018, 0.004), orange,
		Vector3(0, -L1 * 0.50, 0.045), Vector3(0, 0, 0))
	_p(up, MK.plate(0.012, L1 * 0.40, 0.006, 0.002), emis,
		Vector3(0, -L1 * 0.50, 0.058), Vector3(0, 0, 0))
	_p(up, MK.plate(0.070, L1 * 0.28, 0.020, 0.004), steel_d,
		Vector3(0, -L1 * 0.76, -0.045), Vector3(0, 0, 0))
	_bake(sh, up)
	# elbow ball
	var ep: Array = []
	_p(ep, MK.sphere(0.090, 24, 16, true), hull2)
	_ring(ep, 0.080, 0.098, 0.016, 28, Vector3(0, 0, 0.060), Vector3.BACK, orange, 0.002)
	_p(ep, MK.disc(0.032, 0.014, 18, 0.002), steel, Vector3(0, 0, 0.066), Vector3(0, 0, 0))
	_bake(el, ep)
	# forearm
	var fp: Array = []
	_p(fp, SK.beam(Vector3(0, -0.070, 0), Vector3(0, -L2 + 0.070, 0),
		0.074, 0.070, 0.060, 0.056, 0.30, Vector3.FORWARD, 0.007), hull2)
	_p(fp, MK.plate(0.050, L2 * 0.42, 0.016, 0.004), orange,
		Vector3(0, -L2 * 0.52, 0.040), Vector3(0, 0, 0))
	_p(fp, MK.plate(0.010, L2 * 0.36, 0.006, 0.002), emis,
		Vector3(0, -L2 * 0.52, 0.050), Vector3(0, 0, 0))
	_bake(el, fp)
	# wrist ball
	var wp: Array = []
	_p(wp, MK.sphere(0.078, 22, 14, true), hull2)
	_ring(wp, 0.068, 0.084, 0.014, 26, Vector3(0, 0, 0.048), Vector3.BACK, orange, 0.002)
	_bake(wr, wp)
	# tool / generator
	var tp: Array = []
	if side < 0:
		# short arc generator: no hilt, just a compact emitter head
		_p(tp, MK.prism(16, 0.058, 0.050, L3 - 0.020, 0.0), steel_d,
			Vector3(0, -(L3 - 0.020) * 0.5, 0), Vector3(0, 0, 0))
		for i in 3:
			_ring(tp, 0.050, 0.062, 0.010, 20,
				Vector3(0, -0.030 - float(i) * 0.030, 0), Vector3.UP, orange, 0.001)
		_p(tp, MK.disc(0.050, 0.014, 24, 0.003), emis,
			Vector3(0, -L3 + 0.008, 0), Vector3(0, 0, 0))
		_p(tp, MK.prism(12, 0.040, 0.055, 0.030, 0.0), steel,
			Vector3(0, -L3 + 0.030, 0), Vector3(0, 0, 0))
	else:
		# shield mount: compact clamp + gimbal
		_p(tp, MK.prism(16, 0.060, 0.052, L3 - 0.020, 0.0), steel_d,
			Vector3(0, -(L3 - 0.020) * 0.5, 0))
		_ring(tp, 0.050, 0.064, 0.012, 20, Vector3(0, -0.045, 0), Vector3.UP, orange, 0.001)
		_p(tp, MK.sphere(0.045, 16, 12, true), steel,
			Vector3(0, -L3 + 0.012, 0))
		_p(tp, MK.disc(0.030, 0.010, 18, 0.002), emis,
			Vector3(0, -L3 + 0.012, 0.044), Vector3(0, 0, 0))
	_bake(tool, tp)


# ================================================================== shield

func _build_shield_geo() -> void:
	var node: Node3D = shield_node
	var steel := AM.steel()
	var steel_d := AM.steel_dark()
	var hull2 := AM.hull_soft()
	var orange := AM.orange_panel()
	var emis := AM.signal_orange()
	var parts: Array = []
	# physical rim & backing (the energy field faces +Z)
	_ring(parts, 0.286, 0.318, 0.048, 48, Vector3(0, 0, 0.040),
		Vector3.FORWARD, steel_d, 0.006)
	_ring(parts, 0.300, 0.312, 0.014, 48, Vector3(0, 0, 0.066),
		Vector3.FORWARD, orange, 0.002)
	# radial struts + hub
	_p(parts, MK.disc(0.070, 0.050, 28, 0.006), steel,
		Vector3(0, 0, 0.010), Vector3(90, 0, 0))
	for i in 4:
		var a := TAU * float(i) / 4.0 + 0.785
		_p(parts, SK.beam(Vector3.ZERO, Vector3(cos(a) * 0.288, sin(a) * 0.288, 0.040),
			0.040, 0.020, 0.026, 0.014, 0.30, Vector3.BACK, 0.004), steel_d)
	# energy field (dome facing +Z)
	_p(parts, MK.dome(0.300, 0.075, 56, 18, true), AM.shield(),
		Vector3(0, 0, 0.064), Vector3(90, 0, 0))
	# central emitter
	_p(parts, MK.sphere(0.038, 16, 12, true), emis, Vector3(0, 0, 0.090))
	_p(parts, MK.disc(0.050, 0.012, 24, 0.002), steel,
		Vector3(0, 0, 0.100), Vector3(90, 0, 0))
	_bake(node, parts)
	var sscale := kin.shield_r / 0.310
	node.scale = Vector3.ONE * sscale


# ================================================================== blade FX

func _build_blade_geo() -> void:
	# Pure electric arc: no filled or translucent blade plane at all.  The arc
	# field is kept dense enough (see arc_sword_fx.gd) that the sword reads as
	# a continuous lightning blade without any painted background.
	# arc field
	var fx_script = null
	if ResourceLoader.exists("res://scripts/ch/arc_sword_fx.gd"):
		fx_script = load("res://scripts/ch/arc_sword_fx.gd")
	if fx_script != null:
		var fx := Node3D.new()
		fx.set_script(fx_script)
		fx.name = "ArcSwordFX"
		blade_fx.add_child(fx)
	# tip light
	blade_light = OmniLight3D.new()
	blade_light.light_color = Color(1.0, 0.32, 0.06)
	blade_light.light_energy = 1.6
	blade_light.omni_range = 2.2
	blade_light.shadow_enabled = false
	blade_light.position = Vector3(0, -0.45, 0)
	J["toolR"].add_child(blade_light)


func _blade_core_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 14
	var len := 1.03
	# a very thin lens-section blade, widest in the middle, tapering to the tip
	for i in seg:
		var t0 := float(i) / float(seg)
		var t1 := float(i + 1) / float(seg)
		var w0 := 0.078 * sin(pow(t0, 0.55) * PI) + 0.006
		var w1 := 0.078 * sin(pow(t1, 0.55) * PI) + 0.006
		var y0 := -len * t0
		var y1 := -len * t1
		var z0 := 0.012 * (1.0 - t0)
		var z1 := 0.012 * (1.0 - t1)
		# front face
		st.set_normal(Vector3.BACK)
		st.set_uv(Vector2(0, t0)); st.add_vertex(Vector3(-w0, y0, z0))
		st.set_uv(Vector2(1, t0)); st.add_vertex(Vector3(w0, y0, z0))
		st.set_uv(Vector2(1, t1)); st.add_vertex(Vector3(w1, y1, z1))
		st.set_uv(Vector2(0, t0)); st.add_vertex(Vector3(-w0, y0, z0))
		st.set_uv(Vector2(1, t1)); st.add_vertex(Vector3(w1, y1, z1))
		st.set_uv(Vector2(0, t1)); st.add_vertex(Vector3(-w1, y1, z1))
		# back face
		st.set_normal(Vector3.FORWARD)
		st.set_uv(Vector2(0, t0)); st.add_vertex(Vector3(-w0, y0, -z0))
		st.set_uv(Vector2(1, t1)); st.add_vertex(Vector3(w1, y1, -z1))
		st.set_uv(Vector2(1, t0)); st.add_vertex(Vector3(w0, y0, -z0))
		st.set_uv(Vector2(0, t0)); st.add_vertex(Vector3(-w0, y0, -z0))
		st.set_uv(Vector2(0, t1)); st.add_vertex(Vector3(-w1, y1, -z1))
		st.set_uv(Vector2(1, t1)); st.add_vertex(Vector3(w1, y1, -z1))
	return st.commit()


func _build_lights() -> void:
	var lens_light := OmniLight3D.new()
	lens_light.light_color = Color(1.0, 0.26, 0.05)
	lens_light.light_energy = 2.4
	lens_light.omni_range = 1.3
	lens_light.shadow_enabled = false
	lens_light.position = Vector3(0, 0, 0.16)
	J["lens_pitch"].add_child(lens_light)
	var under := OmniLight3D.new()
	under.light_color = Color(1.0, 0.22, 0.04)
	under.light_energy = 1.2
	under.omni_range = 1.8
	under.shadow_enabled = false
	under.position = Vector3(0, 0.02, 0)
	J["body"].add_child(under)


# ================================================================== apply

func apply_pose(pose: Dictionary) -> void:
	if pose.is_empty():
		pose = {}
	var body: Node3D = J["body"]
	body.position = Vector3(float(pose.get("root_sway", 0.0)),
		body_y + float(pose.get("root_lift", 0.0)), float(pose.get("root_shift", 0.0)))
	body.rotation = Vector3(float(pose.get("body_pitch", 0.0)),
		float(pose.get("body_yaw", 0.0)), float(pose.get("body_roll", 0.0)))
	var torso: Node3D = J["torso"]
	torso.rotation = Vector3(float(pose.get("torso_pitch", 0.0)),
		float(pose.get("torso_yaw", 0.0)), float(pose.get("torso_roll", 0.0)))
	var cam_slide := clampf(float(pose.get("cam_slide", 0.0)), 0.0, 0.32)
	var cam_drop := clampf(float(pose.get("cam_drop", 0.0)), 0.0, 0.36)
	# A small retraction only: the whole eye stays outside the hull and the lens
# remains the outermost part.  It does not close, hide or dive into the body.
	var pod_slide := clampf(cam_slide, 0.0, 0.08)
	J["camera_yaw"].position = Vector3(0, cam_y - cam_drop, cam_z - 0.020 - pod_slide)
	var eye_yaw := float(pose.get("cam_yaw", 0.0)) + float(pose.get("lens_yaw", 0.0))
	var eye_pitch := float(pose.get("lens_pitch", 0.0))
	J["camera_yaw"].rotation = Vector3(eye_pitch, eye_yaw, 0)
	J["lens_yaw"].position = Vector3(0, 0, 0.065)
	J["lens_yaw"].rotation = Vector3.ZERO
	J["lens_pitch"].rotation = Vector3.ZERO
	for s in [1, -1]:
		var nm := "L" if s > 0 else "R"
		_apply_arm_joint("sh" + nm, "sh" + nm, pose, nm)
		_apply_arm_joint("elb" + nm, "elb" + nm, pose, nm)
		_apply_arm_joint("wr" + nm, "wr" + nm, pose, nm)
	# wheel spin
	J["wheelL"].rotation = Vector3(float(pose.get("wheel_spin_L", 0.0)), 0, 0)
	J["wheelR"].rotation = Vector3(float(pose.get("wheel_spin_R", 0.0)), 0, 0)
	# shield gimbal
	J["shield_gimbal"].rotation = Vector3(float(pose.get("shield_pitch", 0.0)),
		float(pose.get("shield_yaw", 0.0)), 0)
	# suspension visuals: stretch a unit beam between body mount and fixed axle
	var bx := kin.body_xf(pose)
	for s in [1, -1]:
		var nm2 := "L" if s > 0 else "R"
		var mount := bx * Vector3(float(s) * 0.300, 0.020, -0.020)
		# arm ends at the hub carrier, inboard of the solid wheel
		var hub := Vector3(float(s) * (wheel_x - 0.115), wheel_y, 0.0)
		_set_stretch(_susp_nodes[nm2], mount, hub)
	# blade FX
	var on := clampf((float(pose.get("_blade_on", 1.0)) - 0.45) / 0.55, 0.0, 1.0)
	if blade_light:
		blade_light.light_energy = 1.6 * on
	if blade_fx:
		blade_fx.visible = on > 0.02
	if blade_core:
		blade_core.visible = on > 0.02
	var fx := get_node_or_null("torso/shR/toolR/blade_fx/ArcSwordFX")
	if fx:
		fx.visible = on > 0.02
		fx.external_intensity = on


func _apply_arm_joint(node_name: String, key: String, pose: Dictionary, nm: String) -> void:
	var q = pose.get(key + "_q")
	if q is Quaternion:
		J[node_name].quaternion = q
	else:
		J[node_name].rotation = Vector3(
			float(pose.get("%s_pitch" % key, 0.0)),
			float(pose.get("%s_yaw" % key, 0.0)),
			float(pose.get("%s_roll" % key, 0.0)))


func _set_stretch(node: Node3D, a: Vector3, b: Vector3) -> void:
	if node == null:
		return
	var d := b - a
	var l := d.length()
	if l < 1e-4:
		node.visible = false
		return
	node.visible = true
	var y := d / l
	var x := Vector3.UP.cross(y)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT.cross(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	node.transform = Transform3D(Basis(x, y, z).scaled(Vector3(1, l, 1)), a)


func set_blade_params(intensity: float, speed: float, charge: float) -> void:
	var fx := get_node_or_null("torso/shR/toolR/blade_fx/ArcSwordFX")
	if fx:
		fx.external_intensity = clampf(intensity, 0.0, 3.0)
		var bs := clampf(float(P.get("blade_length", 1.03)) / 2.24, 0.05, 2.0)
		if fx.has_method("set_blade_scale"):
			fx.set_blade_scale(bs)


func set_shield_params(rings: float, opacity: float, impact: float) -> void:
	var m := AM.shield()
	m.set_shader_parameter("ring_count", rings)
	m.set_shader_parameter("opacity", opacity)
	m.set_shader_parameter("impact", impact)


func set_shield_impact(v: float) -> void:
	AM.shield().set_shader_parameter("impact", clampf(v, 0.0, 1.5))


func set_lens_params(intensity: float, _x: float) -> void:
	var m := AM.lens()
	m.set_shader_parameter("intensity", intensity)


func shield_world() -> Dictionary:
	var node: Node3D = shield_node
	var xf := node.global_transform
	var n := (xf.basis * Vector3(0, 0, 1)).normalized()
	return {"c": xf.origin, "n": n, "r": kin.shield_r}


func blade_world() -> Dictionary:
	var a: Vector3 = marker_base.global_position
	var b: Vector3 = marker_tip.global_position
	return {"a": a, "b": b, "dir": (b - a).normalized()}


func measure_radius(_include_weapons := true) -> float:
	var best := 0.0
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var mi: MeshInstance3D = n
			for v in mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				var w: Vector3 = mi.global_transform * v
				best = maxf(best, Vector2(w.x, w.z).length())
	return best