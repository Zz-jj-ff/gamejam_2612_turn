extends Node3D
class_name GirlHead
## GIRL // HEAD — a fully procedural android girl bust.
##
## Head shell, mechanical eye units, brows, lips, ear pods, neck hardware and
## every one of the ~100 silver hair locks are generated from math at load.
## The face is a synthetic porcelain-titanium shell (no skin shading).

const HB := preload("res://scripts/build/head_builder.gd")
const HR := preload("res://scripts/build/hair_rig.gd")
const MATS := preload("res://scripts/build/head_materials.gd")

const ANIMS := ["idle", "glance"]

var P := {
	"jaw": 1.0,
	"cheek": 1.0,
	"head_w": 1.0,
	"face_depth": 1.0,
	"eye_gap": 1.0,
	"eye_size": 1.0,
	"eye_raise": 0.0,
	"iris_size": 1.0,
	"brow_raise": 0.0,
	"smile": 0.65,
	"blush": 0.0,
	"hair_length": 1.0,
	"hair_width": 1.0,
	"wind_strength": 0.22,
	"wind_angle": 35.0,
	"hair_stiffness": 1.0,
	"hair_gravity": 1.0,
}
const PARAM_META := [
	["HEAD", "jaw", "jaw width", 0.72, 1.16, 0.005],
	["HEAD", "cheek", "cheek fullness", 0.0, 1.8, 0.01],
	["HEAD", "head_w", "head width", 0.94, 1.06, 0.002],
	["HEAD", "face_depth", "face depth", 0.95, 1.06, 0.002],
	["EYES", "eye_gap", "eye spacing", 0.90, 1.10, 0.002],
	["EYES", "eye_size", "eye size", 0.86, 1.14, 0.005],
	["EYES", "eye_raise", "eye height", -0.006, 0.006, 0.0005],
	["EYES", "iris_size", "iris size", 0.80, 1.20, 0.005],
	["FACE", "brow_raise", "brow lift", -0.003, 0.005, 0.0005],
	["FACE", "smile", "smile", 0.0, 1.0, 0.01],
	["FACE", "blush", "cheek tint", 0.0, 1.0, 0.01],
	["HAIR", "hair_length", "hair length", 0.72, 1.20, 0.005],
	["HAIR", "hair_width", "lock width", 0.75, 1.30, 0.005],
	["WIND", "wind_strength", "wind strength", 0.0, 2.0, 0.01],
	["WIND", "wind_angle", "wind angle", 0.0, 360.0, 1.0],
	["WIND", "hair_stiffness", "hair stiffness", 0.35, 2.0, 0.01],
	["WIND", "hair_gravity", "gravity scale", 0.3, 2.0, 0.01],
]

var JOINT_DEFAULT := {
	"head_yaw": 0.0, "head_pitch": 0.0, "head_roll": 0.0,
	"eye_yaw": 0.0, "eye_pitch": 0.0,
}
var _joints := {}

var pivot: Node3D
var neck_root: Node3D
var _hair_sim: SpringBoneSimulator3D
var _hair_skel: Skeleton3D
var _hair_guides: Array = []
var _face_mat: ShaderMaterial
var _hair_mat: ShaderMaterial
var _lens_mat: ShaderMaterial
var _iris_mat: ShaderMaterial
var _materials := {}
var _stats := {}

var _anim := "idle"
var _t := 0.0
var _playing := true
var _loop := true
var _speed := 1.0
var _dirty := false
var _dirty_t := 0.0
var _last_build_ms := 0.0
var _frames := 0
var _fps := 0.0
var _fps_t := 0.0


func _ready() -> void:
	_joints = JOINT_DEFAULT.duplicate()
	pivot = Node3D.new()
	pivot.name = "HeadPivot"
	add_child(pivot)
	neck_root = Node3D.new()
	neck_root.name = "NeckRoot"
	add_child(neck_root)
	_rebuild()
	set_process(true)


# ------------------------------------------------------------------- build

func _clear(node: Node3D) -> void:
	for c in node.get_children():
		c.free()


func _rebuild() -> void:
	var t0 := Time.get_ticks_usec()
	if pivot == null:
		return
	_clear(pivot)
	_clear(neck_root)
	_materials.clear()

	var sp := P.duplicate()
	_face_mat = MATS.face(float(P["blush"]))
	_hair_mat = MATS.hair()
	_lens_mat = MATS.eye_lens()
	_iris_mat = MATS.eye_iris()
	var seam_mat := MATS.graphite_soft()
	var lip_mat := MATS.lip_metal()
	var brow_mat := MATS.brow_metal()
	var trim_mat := MATS.trim_mid()
	var trim_bright := MATS.trim_bright()
	var neck_dark := MATS.graphite()
	var neck_glow := MATS.emissive(Color(0.42, 0.86, 1.0), 2.2)
	var ear_glow := MATS.emissive(Color(0.50, 0.90, 1.0), 1.6)
	_materials = {
		"face": _face_mat, "hair": _hair_mat, "lens": _lens_mat,
		"iris": _iris_mat, "trim": trim_mat, "neck_glow": neck_glow,
	}

	var head_mesh := HB.build_head(sp, [])
	_mesh(pivot, head_mesh, _face_mat, "Face")

	# ---- black visor + blue camera sensors
	var mask := HB.build_mask(sp)
	var mask_mat := MATS.mask_black()
	_mesh(pivot, mask["plate"], mask_mat, "VisorPlate")
	_mesh(pivot, mask["frame"], trim_bright, "VisorFrame")
	var sensor_glow := MATS.emissive(Color(0.35, 0.80, 1.0), 2.6)
	for si in mask["sensors"].size():
		var sensor: Dictionary = mask["sensors"][si]
		_mesh(pivot, sensor["bezel"], trim_mat, "SensorBezel%d" % si)
		_mesh(pivot, sensor["body"], _lens_mat, "SensorBody%d" % si)
		_mesh(pivot, sensor["iris"], _iris_mat, "SensorIris%d" % si)
		_mesh(pivot, sensor["glow"], sensor_glow, "SensorGlow%d" % si)

	# ---- ears
	var ears := HB.build_ears(sp)
	_mesh(pivot, ears["dark"], neck_dark, "EarDark")
	_mesh(pivot, ears["trim"], trim_mat, "EarTrim")
	_mesh(pivot, ears["glow"], ear_glow, "EarGlow")

	# ---- skinned silver hair + spring bones (real wind physics)
	var hair := HR.build(sp)

	var skel := Skeleton3D.new()
	skel.name = "HairSkeleton"
	pivot.add_child(skel)
	var bdefs: Array = hair["bones"]
	for bi in bdefs.size():
		var b: Dictionary = bdefs[bi]
		var idx := skel.add_bone(String(b["name"]))
		if int(b["parent"]) >= 0:
			skel.set_bone_parent(idx, int(b["parent"]))
		skel.set_bone_rest(idx, b["local"])
	skel.reset_bone_poses()
	var skin := skel.create_skin_from_rest_transforms()
	var locks_mi := MeshInstance3D.new()
	locks_mi.name = "HairLocks"
	locks_mi.mesh = hair["mesh"]
	if not OS.has_environment("NO_SKIN"):
		locks_mi.skin = skin
		locks_mi.skeleton = NodePath("../HairSkeleton")
	locks_mi.material_override = _hair_mat
	locks_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(locks_mi)
	if OS.has_environment("NO_SIM"):
		return
	var sim := SpringBoneSimulator3D.new()
	sim.name = "HairSprings"
	skel.add_child(sim)
	_hair_guides = hair["guides"]
	sim.set_setting_count(0 if OS.has_environment("NO_SETTINGS") else _hair_guides.size())
	for gi in (0 if OS.has_environment("NO_SETTINGS") else _hair_guides.size()):
		var g: Dictionary = _hair_guides[gi]
		sim.set_root_bone(gi, int(g["first"]))
		sim.set_end_bone(gi, int(g["end"]))
		sim.set_stiffness(gi, 0.9)
		sim.set_drag(gi, 0.6)
		sim.set_gravity(gi, 0.4)
		sim.set_gravity_direction(gi, Vector3.DOWN)
		sim.set_radius(gi, 0.006)
		sim.set_extend_end_bone(gi, true)
		sim.set_end_bone_length(gi, float(g.get("end_len", 0.02)))
		sim.set_center_from(gi, SpringBoneSimulator3D.CENTER_FROM_BONE)
		sim.set_center_bone_name(gi, "hair_root")
		sim.set_enable_all_child_collisions(gi, true)
	sim.external_force = Vector3(0.2, 0.05, 1.0)
	if OS.has_environment("ZERO_G"):
		for gi in _hair_guides.size():
			sim.set_gravity(gi, 0.0)
	if not OS.has_environment("NO_COLL"):
		var col := SpringBoneCollisionSphere3D.new()
		col.name = "HeadCollider"
		col.position = Vector3(0.0, -0.004, -0.006)
		col.radius = 0.080
		sim.add_child(col)
		var col2 := SpringBoneCollisionSphere3D.new()
		col2.name = "JawCollider"
		col2.position = Vector3(0.0, -0.048, 0.020)
		col2.radius = 0.040
		sim.add_child(col2)
	_hair_sim = sim
	_hair_skel = skel
	_apply_hair_tuning()
	var under_mat := _hair_mat.duplicate() as ShaderMaterial
	under_mat.set_shader_parameter("root_color", Color(0.030, 0.034, 0.044))
	under_mat.set_shader_parameter("tip_color", Color(0.070, 0.078, 0.095))
	under_mat.set_shader_parameter("sheen_strength", 0.06)
	under_mat.set_shader_parameter("sheen2_strength", 0.02)
	under_mat.set_shader_parameter("rim_strength", 0.02)
	under_mat.set_shader_parameter("sway_amp", 0.0)
	if OS.has_environment("CAP_RED"):
		under_mat.set_shader_parameter("root_color", Color(1.0, 0.0, 0.0))
		under_mat.set_shader_parameter("tip_color", Color(1.0, 0.0, 0.0))
		under_mat.set_shader_parameter("band_strength", 0.0)
		under_mat.set_shader_parameter("band2_strength", 0.0)
		under_mat.set_shader_parameter("rim_strength", 0.0)
		under_mat.set_shader_parameter("SPECULAR_AMOUNT", 0.0)
	if OS.has_environment("CAP_RED"):
		_mesh(pivot, hair["cap"], MATS.pbr(Color(1, 0, 0), 0.0, 0.8), "HairCap")
	else:
		_mesh(pivot, hair["cap"], under_mat, "HairCap")

	# ---- neck / bust
	var neck := HB.build_neck(sp)
	_mesh(neck_root, neck["dark"], neck_dark, "NeckColumn")
	_mesh(neck_root, neck["trim"], trim_mat, "NeckCollars")
	_mesh(neck_root, neck["glow"], neck_glow, "NeckGlow")

	_last_build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	var tris := 0
	for mi in _all_meshes(self):
		if mi.mesh and mi.mesh.get_surface_count() > 0:
			tris += mi.mesh.surface_get_array_index_len(0) / 3
	_stats = {"tris": tris, "locks": HR.lock_count, "build_ms": _last_build_ms}
	_apply_pose()


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _all_meshes(root: Node) -> Array:
	var out := []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_all_meshes(c))
	return out


# --------------------------------------------------------------- animation

func anim_names() -> PackedStringArray:
	return PackedStringArray(ANIMS)


func play_anim(anim: String) -> void:
	if anim in ANIMS:
		_anim = anim
		_t = 0.0
		_playing = true
		_apply_pose()


func set_playing(v: bool) -> void:
	_playing = v


func is_playing() -> bool:
	return _playing


func anim_time() -> float:
	return _t


func set_anim_time(t: float) -> void:
	_t = clampf(t, 0.0, anim_duration())
	_apply_pose()


func anim_duration() -> float:
	return 6.0 if _anim == "idle" else 4.2


func set_anim_speed(v: float) -> void:
	_speed = v


func anim_speed() -> float:
	return _speed


func set_loop(v: bool) -> void:
	_loop = v


func is_looping() -> bool:
	return _loop


func _process(dt: float) -> void:
	_frames += 1
	_fps_t += dt
	if _fps_t >= 0.5:
		_fps = float(_frames) / _fps_t
		_frames = 0
		_fps_t = 0.0
	if _dirty:
		_dirty_t += dt
		if _dirty_t >= 0.12:
			_dirty = false
			_dirty_t = 0.0
			_rebuild()
	if _playing:
		_t += dt * _speed
		if _t > anim_duration():
			if _loop:
				_t = fmod(_t, anim_duration())
			else:
				_t = anim_duration()
				_playing = false
	_apply_pose()


func _idle_pose(t: float) -> Dictionary:
	var yaw := 2.4 * sin(t * 0.55) + 1.0 * sin(t * 1.31 + 1.2)
	var pitch := 1.5 * sin(t * 0.47 + 0.6) - 1.0
	var roll := 0.9 * sin(t * 0.33 + 2.0)
	var gaze_yaw := 2.6 * sin(t * 0.42 + 0.4) + 0.7 * sin(t * 1.7)
	var gaze_pitch := 1.2 * sin(t * 0.63 + 1.1) - 0.4
	return {"yaw": yaw, "pitch": pitch, "roll": roll,
		"gaze_yaw": gaze_yaw, "gaze_pitch": gaze_pitch}


func _glance_pose(t: float) -> Dictionary:
	# lead with the eyes, then the head follows, hold, return
	var e := 0.0
	var h := 0.0
	if t < 0.55:
		e = smoothstep(0.0, 0.55, t) * 7.0
	elif t < 1.9:
		e = 7.0
		h = smoothstep(0.55, 1.25, t) * 12.0
	elif t < 2.7:
		e = 7.0
		h = 12.0
	elif t < 3.5:
		var u := smoothstep(2.7, 3.5, t)
		e = lerpf(7.0, -6.0, u)
		h = lerpf(12.0, -8.0, u)
	elif t < 3.9:
		e = -6.0
		h = -8.0
	else:
		var u := smoothstep(3.9, 4.2, t)
		e = lerpf(-6.0, 0.0, u)
		h = lerpf(-8.0, 0.0, u)
	return {"yaw": h, "pitch": -1.2 * sin(minf(t, 1.0) * PI) - 0.6,
		"roll": h * -0.12, "gaze_yaw": e, "gaze_pitch": h * 0.10}


func _apply_hair_tuning() -> void:
	if _hair_sim == null:
		return
	var ks: float = float(P.get("hair_stiffness", 1.0))
	var kg: float = float(P.get("hair_gravity", 1.0))
	for gi in _hair_guides.size():
		var g: Dictionary = _hair_guides[gi]
		_hair_sim.set_stiffness(gi, float(g["stiff"]) * ks)
		_hair_sim.set_gravity(gi, float(g["grav"]) * kg)
	_hair_sim.reset()


func prewarm_hair(seconds := 0.9) -> void:
	if _hair_skel == null:
		return
	_update_hair_wind()
	for i in int(seconds * 60.0):
		_hair_skel.advance(1.0 / 60.0)


func _wind_vector() -> Vector3:
	var ang := deg_to_rad(float(P.get("wind_angle", 30.0)))
	var gust := 0.72 + 0.28 * sin(_t * 1.9) + 0.10 * sin(_t * 4.7 + 1.3)
	var boost := 1.0
	if _anim == "gust":
		boost = 1.0 + 2.6 * pow(sin(clampf(_t / 3.6, 0.0, 1.0) * PI), 1.4)
	var s := float(P.get("wind_strength", 0.5)) * gust * boost * 2.0
	if OS.has_environment("NO_WIND"):
		s = 0.0
	return Vector3(sin(ang), 0.10, cos(ang)).normalized() * s


func _update_hair_wind() -> void:
	if _hair_sim == null:
		return
	var f := _wind_vector()
	f = pivot.global_transform.basis.inverse() * f
	_hair_sim.external_force = f


func _apply_pose() -> void:
	if pivot == null:
		return
	var pose := _idle_pose(_t) if _anim == "idle" else _glance_pose(_t)
	var yaw: float = pose["yaw"] + float(_joints.get("head_yaw", 0.0))
	var pitch: float = pose["pitch"] + float(_joints.get("head_pitch", 0.0))
	var roll: float = pose["roll"] + float(_joints.get("head_roll", 0.0))
	pivot.rotation_degrees = Vector3(pitch, yaw, roll)
	pivot.position = Vector3(0.0, sin(_t * 0.9) * 0.0022, 0.0)
	_iris_mat.set_shader_parameter("pulse", 0.5 + 0.5 * sin(_t * 0.9))
	_iris_mat.set_shader_parameter("glow", 0.80 + 0.08 * sin(_t * 0.6))
	if _hair_mat:
		_hair_mat.set_shader_parameter("sway_phase", _t * 0.55)
		_hair_mat.set_shader_parameter("sway_amp", 0.0008)
	_update_hair_wind()


# ------------------------------------------------------------------- params

func param_specs() -> Array:
	var out := []
	for m in PARAM_META:
		out.append({
			"group": m[0], "key": m[1], "label": m[2],
			"min": m[3], "max": m[4], "step": m[5],
			"value": float(P.get(m[1], 0.0)),
		})
	return out


func set_param(key: String, value: float) -> void:
	if not P.has(key):
		return
	P[key] = value
	if key == "blush":
		if _face_mat:
			_face_mat.set_shader_parameter("blush_amount", value)
		return
	if key == "wind_strength" or key == "wind_angle":
		_update_hair_wind()
		return
	if key == "hair_stiffness" or key == "hair_gravity":
		_apply_hair_tuning()
		return
	_dirty = true
	_dirty_t = 0.0


func get_param(key: String) -> float:
	return float(P.get(key, 0.0))


func joint_specs() -> Array:
	return [
		{"group": "HEAD", "key": "head_yaw", "label": "head yaw", "min": -26.0, "max": 26.0, "step": 0.5},
		{"group": "HEAD", "key": "head_pitch", "label": "head pitch", "min": -16.0, "max": 16.0, "step": 0.5},
		{"group": "HEAD", "key": "head_roll", "label": "head roll", "min": -14.0, "max": 14.0, "step": 0.5},
		{"group": "EYES", "key": "eye_yaw", "label": "eye yaw", "min": -9.0, "max": 9.0, "step": 0.25},
		{"group": "EYES", "key": "eye_pitch", "label": "eye pitch", "min": -7.0, "max": 7.0, "step": 0.25},
	]


func set_joint(key: String, value: float) -> void:
	_joints[key] = value
	_apply_pose()


func get_joint(key: String) -> float:
	return float(_joints.get(key, 0.0))


func rig_debug() -> Dictionary:
	return {
		"fps": "%.1f" % _fps,
		"triangles": _stats.get("tris", 0),
		"hair locks": _stats.get("locks", 0),
		"build": "%.1f ms" % _stats.get("build_ms", 0.0),
		"skull height": "%.1f mm" % 250.0,
		"eye spacing": "%.1f mm" % (79.6 * float(P["eye_gap"])),
	}
