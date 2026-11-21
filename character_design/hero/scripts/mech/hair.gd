extends Node3D
## VESPER hair — volumetric 3D anime locks + continuous under-sheet + dense
## scalp integration, driven by SpringBoneSimulator3D with strict geometric
## anti-clipping against head, neck, torso, shoulders and vector thruster pack.
##
## Architecture
##   head -> this node
##     Skeleton3D (top_level, world-metre scale)
##       hair_base + guide bone chains (10 bones each)
##       SpringBoneSimulator3D (gravity / wind / 7 collision shapes)
##       MeshInstance3D (volumetric 3D leaf-section locks + continuous back sheet)
##
## Public API (preserved for mech_rig / qa_v2 / test_hair):
##   setup(head: Node3D, opts := {})
##   update(dt: float, rig: Node3D)
##   set_wind(world_force: Vector3)
##   get_tip_positions() -> Array[Vector3]      (world space)
##   reset_sim()

const HAIR_SHADER := preload("res://shaders/vesper_hair.gdshader")
const HS := preload("res://scripts/mech/head_shape.gd")

const SEGMENTS := 10
const POINTS := SEGMENTS + 1
const SUB_STEPS := 2
const RENDER_SEGMENTS := SEGMENTS * SUB_STEPS
const RENDER_POINTS := RENDER_SEGMENTS + 1
const CROSS_SEGS := 8   # 8-sided volumetric leaf cross-section per lock
const TAU := PI * 2.0

# 珂朵莉式连续蓝发：根部深海蓝 -> 中段天蓝 -> 发梢浅冰蓝。
# 每束头发只做轻微明度偏移，不再做白底蓝色挑染。
const HAIR_ROOT := Color(0.075, 0.235, 0.480)
const HAIR_MID := Color(0.180, 0.500, 0.800)
const HAIR_TIP := Color(0.560, 0.845, 0.955)

# Head-local coords (torso_scale=0.82) → world-metre (hairstyle skeleton frame).
# The upper body is scaled upper_scale ×（1.35× total）；the hair skeleton is
# top_level / unparented and does not inherit torso scale, so all hand-authored
# world positions (colliders / barriers) relative to the head origin must be
# scaled by HEAD_SCALE.  Scalp roots use HEAD_TO_METRE = 0.82 × upper_scale.
const HEAD_TO_METRE := 1.107
const HEAD_SCALE := 1.35

var _head: Node3D
var _skeleton: Skeleton3D
var _sim: SpringBoneSimulator3D
var _mesh_inst: MeshInstance3D
var _mesh := ArrayMesh.new()
var _material: ShaderMaterial

var _strands: Array[Dictionary] = []
var _back_row_indices: Array[PackedInt32Array] = []
var _fringe_indices: PackedInt32Array = []
var _base_bone := -1
var _colliders: Array[Node3D] = []

var _wind := Vector3.ZERO
var _tip_world: Array[Vector3] = []
var _time := 0.0
var _rig_vel := Vector3.ZERO
var _prev_rig_pos := Vector3.ZERO
var _has_prev_rig := false
var _configured := false
var _last_dt := 1.0 / 60.0
var _advance_frame := -1

var _barriers: Array[Dictionary] = []

# Precomputed head-surface radius lookup (built once in setup).  The old code
# re-evaluated the PCHIP profile + 4 normal samples + 8 gaussian blobs for every
# hair point on every frame, which alone cost ~80 ms/frame.
const HR_NY := 48
const HR_NPHI := 64
var _hr_table := PackedFloat32Array()
var _hr_ready := false


# ================================================================== setup
func setup(head: Node3D, opts := {}) -> void:
	_head = head
	_wind = opts.get("wind", _wind)
	_init_head_radius_table()
	_init_barriers()
	_build_skeleton()
	_build_material()
	_build_collisions()
	_build_sim_settings()
	_align_skeleton()
	_skeleton.reset_bone_poses()
	_skeleton.force_update_all_bone_transforms()
	_configured = true
	if is_inside_tree() and _sim != null:
		_sim.reset()
	_build_skinned_mesh()
	_update_tips()


func _init_head_radius_table() -> void:
	if _hr_ready:
		return
	_hr_table.resize(HR_NY * HR_NPHI)
	var y0: float = HS.Y_BOTTOM
	var y1: float = HS.Y_TOP
	for iy in HR_NY:
		var y := lerpf(y0, y1, float(iy) / float(HR_NY - 1))
		for ip in HR_NPHI:
			var phi := TAU * float(ip) / float(HR_NPHI)
			var s: Vector3 = HS.surface_point(y, phi, 1.0, 0.0)
			_hr_table[iy * HR_NPHI + ip] = Vector2(s.x, s.z).length()
	_hr_ready = true


## Bilinear lookup of the head radius at local head-space (y, phi).
func _head_radius_fast(y: float, phi: float) -> float:
	if not _hr_ready:
		return 0.10
	var fy := clampf((y - HS.Y_BOTTOM) / (HS.Y_TOP - HS.Y_BOTTOM), 0.0, 1.0) * float(HR_NY - 1)
	var fp := wrapf(phi, 0.0, TAU) / TAU * float(HR_NPHI)
	var iy := mini(int(fy), HR_NY - 2)
	var ip := int(fp) % HR_NPHI
	var ip1 := (ip + 1) % HR_NPHI
	var ty := fy - float(iy)
	var tp := fp - floorf(fp)
	var r00: float = _hr_table[iy * HR_NPHI + ip]
	var r10: float = _hr_table[iy * HR_NPHI + ip1]
	var r01: float = _hr_table[(iy + 1) * HR_NPHI + ip]
	var r11: float = _hr_table[(iy + 1) * HR_NPHI + ip1]
	return lerpf(lerpf(r00, r10, tp), lerpf(r01, r11, tp), ty)


## Cheap equivalent of HS.push_outside_head using the precomputed radius table.
func _push_head_fast(p: Vector3, clear: float) -> Vector3:
	if p.y > HS.Y_TOP - 0.012:
		var center := Vector3(0.0, 0.025, 0.005)
		var rx := 0.095 + clear
		var ry := 0.122 + clear
		var rz := 0.114 + clear
		var q := Vector3((p.x - center.x) / rx, (p.y - center.y) / ry, (p.z - center.z) / rz)
		var l := q.length()
		if l < 1.0 and l > 1e-6:
			q /= l
			return Vector3(center.x + q.x * rx, center.y + q.y * ry, center.z + q.z * rz)
		return p
	if p.y < HS.Y_BOTTOM:
		return p
	var phi := atan2(p.x, p.z)
	var want := _head_radius_fast(p.y, phi) + clear
	var rp := Vector2(p.x, p.z).length()
	if rp < want:
		if rp < 1e-6:
			return Vector3(0.0, p.y, want)
		var k := want / rp
		return Vector3(p.x * k, p.y, p.z * k)
	return p


func _init_barriers() -> void:
	_barriers.clear()
	# 1. 头部与面部（略大于真实少女脸型表面，彻底阻止任何头发切进面罩或后脑）
	_barriers.append({"type": "sphere", "c": Vector3(0.0, 0.018, 0.004) * HEAD_SCALE, "r": 0.092 * HEAD_SCALE})
	_barriers.append({"type": "sphere", "c": Vector3(0.0, -0.028, -0.020) * HEAD_SCALE, "r": 0.080 * HEAD_SCALE})
	# 2. 脖颈与衣领
	_barriers.append({"type": "capsule", "a": Vector3(0.0, -0.04, 0.0) * HEAD_SCALE, "b": Vector3(0.0, -0.17, 0.0) * HEAD_SCALE, "r": 0.078 * HEAD_SCALE})
	# 3. 胸腔与上背（圆滑胶囊：包围后背装甲板，让后发顺滑贴着后背外侧垂落）
	_barriers.append({"type": "capsule", "a": Vector3(0.0, -0.18, 0.045) * HEAD_SCALE, "b": Vector3(0.0, -0.52, 0.055) * HEAD_SCALE, "r": 0.192 * HEAD_SCALE})
	_barriers.append({"type": "sphere", "c": Vector3(0.065, -0.23, -0.085) * HEAD_SCALE, "r": 0.088 * HEAD_SCALE})
	_barriers.append({"type": "sphere", "c": Vector3(-0.065, -0.23, -0.085) * HEAD_SCALE, "r": 0.088 * HEAD_SCALE})
	# 4. 左右肩甲：收小并略向后上移，避免发束贴着球体内侧被“挡”出一个折角
	_barriers.append({"type": "sphere", "c": Vector3(0.285, -0.24, 0.005) * HEAD_SCALE, "r": 0.072 * HEAD_SCALE})
	_barriers.append({"type": "sphere", "c": Vector3(-0.285, -0.24, 0.005) * HEAD_SCALE, "r": 0.072 * HEAD_SCALE})
	# 5. 背部矢量推进器缓坡包络（上移后移贴紧真实背包位置）
	_barriers.append({"type": "sphere", "c": Vector3(0.0, -0.24, 0.18) * HEAD_SCALE, "r": 0.115 * HEAD_SCALE})
	_barriers.append({"type": "sphere", "c": Vector3(0.0, -0.33, 0.18) * HEAD_SCALE, "r": 0.175 * HEAD_SCALE})
	_barriers.append({"type": "sphere", "c": Vector3(0.0, -0.42, 0.20) * HEAD_SCALE, "r": 0.185 * HEAD_SCALE})


func _build_skeleton() -> void:
	_skeleton = Skeleton3D.new()
	_skeleton.name = "HairSkeleton"
	_skeleton.top_level = true
	_skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	add_child(_skeleton)

	_base_bone = _skeleton.add_bone("hair_base")
	_skeleton.set_bone_parent(_base_bone, -1)
	_skeleton.set_bone_rest(_base_bone, Transform3D.IDENTITY)

	var layout := _make_layout()
	_strands.clear()
	if not _skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		_skeleton.skeleton_updated.connect(_on_skeleton_updated)
	for s in layout.size():
		var spec: Dictionary = layout[s]
		var points: PackedVector3Array = _grow_rest(spec)
		var lens: PackedFloat32Array = spec["lens_exact"]
		var bones := PackedInt32Array()
		var prev_basis := Basis.IDENTITY
		for i in SEGMENTS:
			var idx := _skeleton.add_bone("hair_%02d_%02d" % [s, i])
			_skeleton.set_bone_parent(idx, _base_bone if i == 0 else bones[i - 1])
			var from_p := points[i]
			var to_p := points[i + 1]
			var seg := lens[i]
			var dir := (to_p - from_p).normalized()
			var global_basis := _basis_from_y(dir)
			if i == 0:
				_skeleton.set_bone_rest(idx, Transform3D(global_basis, from_p))
			else:
				_skeleton.set_bone_rest(idx, Transform3D(prev_basis.inverse() * global_basis, Vector3(0, seg, 0)))
			prev_basis = global_basis
			bones.append(idx)

		# color_blend is now only a gentle lock-to-lock value shift (0..1)
		var blend := float(spec["color_blend"])
		var lift := 0.90 + 0.20 * blend
		var cr := HAIR_ROOT * lift
		var cm := HAIR_MID * lift
		var ct := HAIR_TIP * lift

		_strands.append({
			"bones": bones,
			"rest_points": points.duplicate(),
			"points": points,
			"lens": lens,
			"radial": spec["radial"],
			"normal_hint": spec["normal_hint"],
			"width": float(spec["width"]),
			"thick": float(spec["thick"]),
			"phase": float(spec["phase"]),
			"twist": float(spec["twist"]),
			"role": String(spec["role"]),
			"stiff": float(spec["stiff"]),
			"drag": float(spec["drag"]),
			"grav": float(spec["grav"]),
			"root": cr,
			"mid": cm,
			"tip": ct,
			"color_blend": blend,
		})


func _build_material() -> void:
	_material = ShaderMaterial.new()
	_material.shader = HAIR_SHADER
	_material.set_shader_parameter("energy", 0.18)
	_material.set_shader_parameter("root_alpha", 1.0)
	_material.set_shader_parameter("tip_alpha", 1.0)

	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.name = "HairRibbons"
	_mesh_inst.mesh = _mesh
	_mesh_inst.material_override = _material
	_mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_inst.extra_cull_margin = 1.0
	_skeleton.add_child(_mesh_inst)


func _build_collisions() -> void:
	_sim = SpringBoneSimulator3D.new()
	_sim.name = "SpringBone"
	_skeleton.add_child(_sim)
	_colliders.clear()

	# 1. 头部球体
	var head_c := SpringBoneCollisionSphere3D.new()
	head_c.name = "HeadCol"
	head_c.position = Vector3(0.0, 0.015, 0.002) * HEAD_SCALE
	head_c.radius = 0.092 * HEAD_SCALE
	_sim.add_child(head_c)
	_colliders.append(head_c)

	# 2. 面部前侧保护球
	var face_c := SpringBoneCollisionSphere3D.new()
	face_c.name = "FaceCol"
	face_c.position = Vector3(0.0, -0.025, -0.030) * HEAD_SCALE
	face_c.radius = 0.084 * HEAD_SCALE
	_sim.add_child(face_c)
	_colliders.append(face_c)

	# 3. 颈部与上胸胶囊
	var torso_c := SpringBoneCollisionCapsule3D.new()
	torso_c.name = "TorsoCol"
	torso_c.position = Vector3(0.0, -0.32, 0.045) * HEAD_SCALE
	torso_c.radius = 0.190 * HEAD_SCALE
	torso_c.height = 0.46 * HEAD_SCALE
	_sim.add_child(torso_c)
	_colliders.append(torso_c)

	# 4. 左右肩甲碰撞球
	for side in [-1.0, 1.0]:
		var sh_c := SpringBoneCollisionSphere3D.new()
		sh_c.name = "ShoulderColR" if side > 0.0 else "ShoulderColL"
		sh_c.position = Vector3(0.275 * side, -0.25, -0.01) * HEAD_SCALE
		sh_c.radius = 0.090 * HEAD_SCALE
		_sim.add_child(sh_c)
		_colliders.append(sh_c)

	# 5. 背部推进器缓坡碰撞球（上移后移贴紧真实背包，阻止头发覆盖引擎）
	var pack_top := SpringBoneCollisionSphere3D.new()
	pack_top.name = "PackTop"
	pack_top.position = Vector3(0.0, -0.26, 0.18) * HEAD_SCALE
	pack_top.radius = 0.110 * HEAD_SCALE
	_sim.add_child(pack_top)
	_colliders.append(pack_top)

	var pack_a := SpringBoneCollisionSphere3D.new()
	pack_a.name = "PackUpper"
	pack_a.position = Vector3(0.0, -0.35, 0.18) * HEAD_SCALE
	pack_a.radius = 0.168 * HEAD_SCALE
	_sim.add_child(pack_a)
	_colliders.append(pack_a)

	var pack_b := SpringBoneCollisionSphere3D.new()
	pack_b.name = "PackLower"
	pack_b.position = Vector3(0.0, -0.44, 0.20) * HEAD_SCALE
	pack_b.radius = 0.180 * HEAD_SCALE
	_sim.add_child(pack_b)
	_colliders.append(pack_b)


func _build_sim_settings() -> void:
	_sim.set_setting_count(_strands.size())
	for s in _strands.size():
		var strand: Dictionary = _strands[s]
		var bones: PackedInt32Array = strand["bones"]
		var lens: PackedFloat32Array = strand["lens"]
		var root_name := _skeleton.get_bone_name(bones[0])
		var end_name := _skeleton.get_bone_name(bones[SEGMENTS - 1])

		_sim.set_root_bone_name(s, root_name)
		_sim.set_end_bone_name(s, end_name)
		_sim.set_extend_end_bone(s, true)
		_sim.set_end_bone_length(s, lens[SEGMENTS - 1])
		_sim.set_center_from(s, SpringBoneSimulator3D.CENTER_FROM_BONE)
		_sim.set_center_bone_name(s, "hair_base")
		_sim.set_rotation_axis(s, SkeletonModifier3D.ROTATION_AXIS_ALL)
		_sim.set_individual_config(s, true)
		_sim.set_collision_count(s, _colliders.size())
		for ci in _colliders.size():
			_sim.set_collision_path(s, ci, NodePath(_colliders[ci].name))

		var base_stiff: float = strand["stiff"]
		var base_drag: float = strand["drag"]
		var base_grav: float = strand["grav"]
		var radial: Vector3 = strand["radial"]
		var role: String = strand["role"]
		var grav_dir := (Vector3.DOWN + radial * (0.04 if role == "fringe" else 0.18)).normalized()

		for j in SEGMENTS:
			var t := float(j) / float(SEGMENTS - 1)
			# 更硬且有真实弯曲阻尼：外层/中段关节保留大部分根部刚度
			#（0.42 收尾而非 0.30），末梢阻尼抬升（1.9× 而非 1.6×），使发束
			# 有可见抗弯、并能快速沉降、不再抖动。
			_sim.set_joint_stiffness(s, j, lerpf(base_stiff, base_stiff * 0.42, t))
			_sim.set_joint_drag(s, j, lerpf(base_drag, base_drag * 1.9, t))
			_sim.set_joint_gravity(s, j, lerpf(base_grav * 0.9, base_grav * 1.1, t))
			_sim.set_joint_gravity_direction(s, j, grav_dir)
			_sim.set_joint_radius(s, j, 0.009)
	_sim.set_external_force(Vector3.ZERO)


# ================================================================== layout
func _scalp_point_m(y_head: float, phi: float, lift_head := 0.0035) -> Array:
	var p := HS.surface_point(y_head, phi, 1.0, lift_head) * HEAD_TO_METRE
	var n := HS.surface_normal(y_head, phi)
	return [p, n]


## 空间连续谐波蓝白挑染混合权重 [0..1]
func _color_blend_at(phi: float, layer_offset := 0.0) -> float:
	var w1 := 0.5 + 0.5 * sin(phi * 5.0 + layer_offset * 1.3 + 0.4)
	var w2 := 0.5 + 0.5 * cos(phi * 11.0 - layer_offset * 2.1 + 1.1)
	var mix_v := w1 * 0.58 + w2 * 0.42
	return smoothstep(0.22, 0.86, mix_v)


func _make_layout() -> Array:
	var out: Array = []
	_back_row_indices.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261120

	# ------------------------------------------------------------------
	# 1. 后发主瀑布：所有表层与中层长发全部从头顶百会穴发旋 (y=0.137..0.141) 放射生长，
	#    顺着头顶和后脑勺形成一条从头顶直达后背的连续一气呵成轮廓，彻底消灭“上下两段”！
	#    底层 (r_idx=0) 扎在枕部内侧填充厚度。
	# ------------------------------------------------------------------
	var back_rows := [
		{"count": 21, "y": 0.048, "az_max": 92.0, "len": 0.39, "w": 0.032, "th": 0.0095, "out": 0.12, "layer": 0.0},
		{"count": 27, "y": 0.138, "az_max": 104.0, "len": 0.50, "w": 0.034, "th": 0.0095, "out": 0.15, "layer": 1.0},
		{"count": 25, "y": 0.140, "az_max": 100.0, "len": 0.48, "w": 0.031, "th": 0.0085, "out": 0.16, "layer": 2.0},
	]
	for r_idx in back_rows.size():
		var row: Dictionary = back_rows[r_idx]
		var n: int = row["count"]
		var row_ids := PackedInt32Array()
		for i in n:
			var u := float(i) / float(n - 1)
			var az_deg := lerpf(-float(row["az_max"]), float(row["az_max"]), u)
			var phi := deg_to_rad(az_deg + rng.randf_range(-1.0, 1.0))
			var y_h := float(row["y"])
			var sp := _scalp_point_m(y_h, phi, 0.0052 + 0.0008 * float(r_idx))
			var root: Vector3 = sp[0]
			var radial := Vector3(sin(phi), 0.0, cos(phi)).normalized()
			var start_dir := (radial * (0.75 if r_idx > 0 else 0.18) + Vector3.DOWN * (0.66 if r_idx > 0 else 0.98)).normalized()
			var center_falloff := 1.0 - 0.14 * absf(u - 0.5) * 2.0
			# low-frequency length wave: neighbouring locks end in clumps, with
			# a few longer strands hanging past the rest
			var len_wave := 0.78 + 0.22 * (0.5 + 0.5 * sin(phi * 1.9 + float(r_idx) * 2.1)) + 0.07 * (0.5 + 0.5 * sin(phi * 5.3 + 0.7))
			var length := float(row["len"]) * center_falloff * len_wave * rng.randf_range(0.97, 1.03)
			var c_blend := 0.35 + 0.30 * (0.5 + 0.5 * sin(phi * 3.0 + float(r_idx)))
			row_ids.append(out.size())
			out.append({
				"root": root,
				"dir": start_dir,
				"radial": radial,
				"normal_hint": radial,
				"length": length,
				"width": float(row["w"]) * rng.randf_range(0.96, 1.05),
				"thick": float(row["th"]),
				"color_blend": c_blend,
				"phase": u * 5.3 + float(r_idx) * 2.1 + rng.randf() * 1.5,
				"twist": (u - 0.5) * 0.10,
				"role": "back",
				"stiff": 0.42,
				"drag": 0.32,
				"grav": 0.90,
			})
		_back_row_indices.append(row_ids)

	# ------------------------------------------------------------------
	# 1b. 头顶覆盖层：一圈短而密的发束，把头皮基底完全盖住（不能露出光滑头皮）
	# ------------------------------------------------------------------
	var n_crown := 30
	for i in n_crown:
		var cu := float(i) / float(n_crown)
		var phi := TAU * cu
		var sp := _scalp_point_m(0.133, phi, 0.0050)
		var root: Vector3 = sp[0]
		var radial := Vector3(sin(phi), 0.0, cos(phi)).normalized()
		var start_dir := (radial * 0.42 + Vector3.DOWN * 0.90).normalized()
		var clen := 0.085 + 0.055 * (0.5 + 0.5 * sin(phi * 2.1 + 1.3))
		out.append({
			"root": root,
			"dir": start_dir,
			"radial": radial,
			"normal_hint": radial,
			"length": clen,
			"width": 0.034 * (1.0 + 0.10 * sin(phi * 3.7)),
			"thick": 0.0065,
			"color_blend": 0.30 + 0.30 * (0.5 + 0.5 * sin(phi * 2.0)),
			"phase": cu * 6.2 + 1.7,
			"twist": (cu - 0.5) * 0.06,
			"role": "crown",
			"stiff": 0.66,
			"drag": 0.38,
			"grav": 0.85,
		})

	# ------------------------------------------------------------------
	# 2. 姬发式 / 少女脸侧修饰长鬓发 (Sideburns / Face-framing locks)
	# 从头顶中分发缝 (y=0.139) 顺应太阳穴→脸颊垂下，先贴紧头皮面颊再自由垂落至胸侧！
	# ------------------------------------------------------------------
	for side in [-1.0, 1.0]:
		var side_specs := [
			{"az": 108.0, "y": 0.139, "len": 0.50, "w": 0.025, "th": 0.0080},
			{"az": 116.0, "y": 0.139, "len": 0.47, "w": 0.024, "th": 0.0080},
			{"az": 124.0, "y": 0.138, "len": 0.44, "w": 0.022, "th": 0.0075},
			{"az": 132.0, "y": 0.138, "len": 0.40, "w": 0.020, "th": 0.0070},
		]
		for k in side_specs.size():
			var sc: Dictionary = side_specs[k]
			var phi := deg_to_rad(side * float(sc["az"]))
			var sp := _scalp_point_m(float(sc["y"]), phi, 0.0055)
			var root: Vector3 = sp[0]
			var radial := Vector3(sin(phi), 0.0, cos(phi)).normalized()
			# Side locks hug the cheek: start nearly vertical with a hint of outward,
			# then _grow_rest pulls inward to follow the head surface.
			var start_dir := (radial * 0.14 + Vector3(side * 0.03, -0.82, -0.06)).normalized()
			var c_blend := 0.38 + 0.25 * (0.5 + 0.5 * sin(phi * 4.0 + float(k)))
			out.append({
				"root": root,
				"dir": start_dir,
				"radial": radial,
				"normal_hint": Vector3(side * 0.35, -0.15, -0.52).normalized(),
				"length": float(sc["len"]),
				"width": float(sc["w"]),
				"thick": float(sc["th"]),
				"color_blend": c_blend,
				"phase": float(k) * 1.9 + (0.4 if side < 0.0 else 3.5),
				"twist": side * 0.04,
				"role": "side",
				"stiff": 0.30,
				"drag": 0.34,
				"grav": 1.15,
			})

	# ------------------------------------------------------------------
	# 3. 前额柔顺少女刘海 (Fringe / Bangs)
	# 直接从头顶百会穴发旋 (y=0.139) 顺着前额弧面一气呵成垂下，无任何分界！
	# ------------------------------------------------------------------
	var n_fringe := 29
	_fringe_indices.clear()
	for i in n_fringe:
		var u := float(i) / float(n_fringe - 1)
		var front_offset_deg := lerpf(-52.0, 52.0, u)
		var phi := PI - deg_to_rad(front_offset_deg)
		var y_h := 0.139
		var sp := _scalp_point_m(y_h, phi, 0.0055)
		var root: Vector3 = sp[0]

		var cam_zone := exp(-pow((front_offset_deg - 19.0) / 16.0, 2.0))
		var base_len := lerpf(0.152, 0.126, u)
		var length := base_len * (1.0 - 0.30 * cam_zone)
		if absf(front_offset_deg) > 28.0:
			length += 0.028 * ((absf(front_offset_deg) - 28.0) / 12.0)

		var radial := Vector3(sin(phi), 0.0, cos(phi)).normalized()
		var sweep_x := -0.10 - 0.10 * cam_zone + 0.14 * (u - 0.5)
		var start_dir := (radial * 0.72 + Vector3(sweep_x, -0.68, -0.25)).normalized()
		var c_blend := 0.42 + 0.24 * sin(u * PI * 2.0)

		_fringe_indices.append(out.size())
		out.append({
			"root": root,
			"dir": start_dir,
			"radial": radial,
			"normal_hint": Vector3(sin(phi) * 0.6, 0.20, -0.85).normalized(),
			"length": length,
			"width": 0.046 * (1.05 - 0.12 * cam_zone),
			"thick": 0.0062,
			"color_blend": c_blend,
			"phase": u * 6.1 + 0.9,
			"twist": -0.05,
			"role": "fringe",
			"stiff": 0.62,
			"drag": 0.40,
			"grav": 0.85,
		})

	return out


func _grow_rest(spec: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array()
	var p: Vector3 = spec["root"]
	var dir: Vector3 = spec["dir"]
	var radial: Vector3 = spec["radial"]
	var total: float = spec["length"]
	var role: String = spec["role"]
	var lens := PackedFloat32Array()
	var sum := 0.0
	for i in SEGMENTS:
		var seg := total / float(SEGMENTS)
		lens.append(seg)
		sum += seg
	for i in SEGMENTS:
		lens[i] = lens[i] / sum * total

	points.append(p)
	for i in SEGMENTS:
		var t := float(i + 1) / float(SEGMENTS)
		var prev_p := p
		if role == "fringe":
			dir = (dir + Vector3.DOWN * 0.22 + Vector3(0.0, 0.0, 0.05 * t)).normalized()
		elif role == "side":
			var hug := 0.45 * smoothstep(0.55, 0.0, t)   # strong inward pull near root, fades
			dir = (dir + Vector3.DOWN * 0.52 - radial * hug).normalized()
		else:
			var flare := 0.06 * smoothstep(0.30, 0.90, t)
			dir = (dir + Vector3.DOWN * 0.36 + radial * flare).normalized()
		p = prev_p + dir * lens[i]
		p = _clamp_point_outside_barriers(p, role, t)
		var actual_dir := p - prev_p
		if actual_dir.length_squared() > 1e-10:
			dir = actual_dir.normalized()
			p = prev_p + dir * lens[i]
		points.append(p)
	spec["lens_exact"] = lens
	return points


func _clamp_point_outside_barriers(p: Vector3, role: String, t: float) -> Vector3:
	# 快速排除：所有碰撞体都集中在头部/躯干附近的有限空间内，远离该区域的
	# 发梢（尤其是长发末段）无需做任何投影。
	if p.y < -0.70 * HEAD_SCALE or p.y > 0.22 * HEAD_SCALE or absf(p.x) > 0.38 * HEAD_SCALE or p.z < -0.22 * HEAD_SCALE or p.z > 0.34 * HEAD_SCALE:
		return p
	# 1. 少女头部精确曲面外推：贴合 6.8mm 头皮发壳一路顺滑包络下来，无任何台阶感
	var p_head := p / HEAD_TO_METRE
	var max_clear := 0.0068 if role == "fringe" else 0.0082
	var head_clear := lerpf(0.0042, max_clear, smoothstep(0.0, 0.25, t))
	p_head = _push_head_fast(p_head, head_clear)
	p = p_head * HEAD_TO_METRE

	# 2. 身体/肩甲/推进器解析屏障外推
	var extra := 0.003 if role == "fringe" else 0.008
	for b in _barriers:
		if b["type"] == "sphere":
			var c: Vector3 = b["c"]
			var r: float = float(b["r"]) + extra
			var d := p - c
			var dl2 := d.length_squared()
			if dl2 < r * r and dl2 > 1e-12:
				p = c + d * (r / sqrt(dl2))
		elif b["type"] == "capsule":
			var a: Vector3 = b["a"]
			var cb: Vector3 = b["b"]
			var r2: float = float(b["r"]) + extra
			var ab := cb - a
			var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-8), 0.0, 1.0)
			var closest := a + ab * u
			var d2 := p - closest
			var dl2 := d2.length()
			if dl2 < r2 and dl2 > 1e-6:
				p = closest + d2 * (r2 / dl2)

	# 3. 方向性防穿模半球约束
	if role in ["back", "crown"] and t > 0.05:
		# 单一连续 z 下限：后颈穹顶 (顶点 +0.025 / 半宽 0.105) 平滑过渡到
		# 胸口穹顶 (顶点 -0.02 / 半宽 0.175)。旧的 if/elif 在 y=-0.22 处
		# 让 z 下限跳变 0.045 m，发束经过时会出现明显“被挡住”的不可导点。
		var s := 1.0 - smoothstep(-0.28 * HEAD_SCALE, -0.16 * HEAD_SCALE, p.y)
		var half_w := lerpf(0.105 * HEAD_SCALE, 0.175 * HEAD_SCALE, s)
		var apex_z := lerpf(0.025 * HEAD_SCALE, -0.02 * HEAD_SCALE, s)
		var z_min := apex_z * (1.0 - clampf(absf(p.x) / maxf(half_w, 1e-6), 0.0, 1.0))
		if absf(p.x) < half_w and p.z < z_min:
			p.z = z_min
	elif role == "side" and t > 0.05:
		if p.y > -0.10 * HEAD_SCALE and p.z < 0.02 * HEAD_SCALE:
			var min_abs_x := 0.066 * HEAD_SCALE * (1.0 - clampf((-0.02 * HEAD_SCALE - p.y) / (0.10 * HEAD_SCALE), 0.0, 1.0))
			if absf(p.x) < min_abs_x:
				p.x = signf(p.x if absf(p.x) > 1e-5 else 1.0) * min_abs_x
	elif role == "fringe":
		if p.y > -0.06 * HEAD_SCALE:
			var p_h := p / HEAD_TO_METRE
			var phi := atan2(p_h.x, p_h.z)
			var surf := HS.surface_point(clampf(p_h.y, HS.Y_BOTTOM, HS.Y_TOP), phi, 1.0, 0.0050) * HEAD_TO_METRE
			if p.z > surf.z:
				p.z = surf.z
	return p


func _basis_from_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


# ================================================================== runtime
func _align_skeleton() -> void:
	if _head == null or _skeleton == null:
		return
	var xf := _head.global_transform
	var b := xf.basis.orthonormalized()
	_skeleton.global_transform = Transform3D(b, xf.origin)


func update(dt: float, rig: Node3D) -> void:
	if not is_finite(dt) or _head == null or _skeleton == null:
		return
	dt = maxf(dt, 0.0)
	_align_skeleton()
	if dt <= 0.0:
		return
	_time += dt
	_last_dt = dt

	if rig != null and is_instance_valid(rig):
		var rp := rig.global_position
		if _has_prev_rig:
			var v := (rp - _prev_rig_pos) / dt
			if v.length() > 24.0:
				v = v.limit_length(24.0)
			_rig_vel = _rig_vel.lerp(v, 1.0 - exp(-14.0 * dt))
		_prev_rig_pos = rp
		_has_prev_rig = true

	var skel_basis := _skeleton.global_transform.basis
	var head_fwd := -skel_basis.z
	var head_back := skel_basis.z

	var force := _wind
	force += skel_basis.x * (sin(_time * 0.85) * 0.07) + head_back * (0.06 + 0.04 * cos(_time * 0.6))
	var slip := -_rig_vel * 0.24
	var fwd_comp := slip.dot(head_fwd)
	if fwd_comp > 0.0:
		slip -= head_fwd * fwd_comp
		var side_split := sin(_time * 2.2) * 0.35 + (1.0 if slip.dot(skel_basis.x) >= 0.0 else -1.0) * 0.65
		slip += skel_basis.x * (fwd_comp * 0.40 * side_split) + Vector3.UP * (fwd_comp * 0.10)
	var lat_comp := slip.dot(skel_basis.x)
	if absf(lat_comp) > 1.35:
		slip -= skel_basis.x * (lat_comp - signf(lat_comp) * 1.35)
		slip += head_back * (absf(lat_comp) * 0.22)
	force += slip

	if rig != null and is_instance_valid(rig):
		var dash := float(rig.get("dash_time")) if rig.get("dash_time") != null else 0.0
		if dash > 0.0:
			force += head_back * 1.0
		var attacking := bool(rig.get("is_attacking")) if rig.get("is_attacking") != null else false
		if attacking:
			var at := float(rig.get("attack_time")) if rig.get("attack_time") != null else _time
			force += skel_basis.x * sin(at * 11.0) * 0.35
			force += head_back * (0.28 + 0.16 * sin(at * 7.0))
			force += Vector3.UP * 0.08
	force = force.limit_length(3.5)
	if _sim != null:
		_sim.set_external_force(skel_basis.inverse() * force)

	if is_inside_tree():
		var pf := Engine.get_process_frames()
		if pf != _advance_frame:
			_advance_frame = pf
			_skeleton.advance(dt)


func set_wind(world_force: Vector3) -> void:
	_wind = world_force


func get_tip_positions() -> Array[Vector3]:
	if _tip_world.size() == _strands.size():
		return _tip_world.duplicate()
	var out: Array[Vector3] = []
	for s in _strands.size():
		var pts: PackedVector3Array = _strands[s]["points"]
		out.append(_skeleton.global_transform * pts[POINTS - 1])
	_tip_world = out
	return _tip_world.duplicate()


func reset_sim() -> void:
	if _skeleton == null:
		return
	_align_skeleton()
	_skeleton.reset_bone_poses()
	_skeleton.force_update_all_bone_transforms()
	if is_inside_tree() and _sim != null:
		_sim.reset()
	_rig_vel = Vector3.ZERO
	_has_prev_rig = false
	_time = 0.0
	_tip_world.clear()
	_update_tips()


# ================================================================== readback & spline smoothing
func _read_points(strand: Dictionary) -> PackedVector3Array:
	var bones: PackedInt32Array = strand["bones"]
	var lens: PackedFloat32Array = strand["lens"]
	var role: String = strand["role"]
	var pts := PackedVector3Array()
	pts.resize(POINTS)
	pts[0] = _skeleton.get_bone_global_pose(bones[0]).origin
	for i in range(1, SEGMENTS):
		var raw_p := _skeleton.get_bone_global_pose(bones[i]).origin
		var t := float(i) / float(SEGMENTS)
		# 先按骨长重建，再做唯一一次屏障投影（旧实现投影两次，开销翻倍）
		var dir := raw_p - pts[i - 1]
		if dir.length_squared() > 1e-10:
			pts[i] = _clamp_point_outside_barriers(pts[i - 1] + dir.normalized() * lens[i - 1], role, t)
		else:
			pts[i] = _clamp_point_outside_barriers(raw_p, role, t)
	var last := _skeleton.get_bone_global_pose(bones[SEGMENTS - 1])
	var raw_tip := pts[SEGMENTS - 1] + last.basis.y * lens[SEGMENTS - 1]
	var tip_dir := raw_tip - pts[SEGMENTS - 1]
	if tip_dir.length_squared() > 1e-10:
		pts[SEGMENTS] = _clamp_point_outside_barriers(pts[SEGMENTS - 1] + tip_dir.normalized() * lens[SEGMENTS - 1], role, 1.0)
	else:
		pts[SEGMENTS] = _clamp_point_outside_barriers(raw_tip, role, 1.0)
	return pts


## 将 11 个骨骼节点用 Catmull-Rom 样条细分为 21 个超平滑采样点，彻底消除多段折线感
func _subdivide_smooth(pts: PackedVector3Array, role: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(RENDER_POINTS)
	for i in SEGMENTS:
		var p0 := pts[maxi(i - 1, 0)]
		var p1 := pts[i]
		var p2 := pts[i + 1]
		var p3 := pts[mini(i + 2, POINTS - 1)]
		out[i * 2] = p1
		var mid := 0.5 * ((2.0 * p1) + (-p0 + p2) * 0.5 + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * 0.25 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * 0.125)
		out[i * 2 + 1] = mid
	out[RENDER_POINTS - 1] = pts[POINTS - 1]
	return out


## 将屏障外推量分摊到相邻采样点：发束贴着后颈/肩甲滑过时不再在接触点出现
## 折角（不可导点），同时仍然保证每一点最终位于所有碰撞体之外。
func _relax_render_points(pts: PackedVector3Array, role: String) -> void:
	var n := pts.size()
	if n < 3:
		return
	for _pass in 2:
		var disp := PackedVector3Array()
		disp.resize(n)
		for i in n:
			var t := float(i) / float(n - 1)
			disp[i] = _clamp_point_outside_barriers(pts[i], role, t) - pts[i]
		for i in range(1, n - 1):
			var d: Vector3 = disp[i]
			if d.length_squared() < 1e-10:
				continue
			pts[i] += d * 0.5
			if i > 1:
				pts[i - 1] += d * 0.25
			if i < n - 2:
				pts[i + 1] += d * 0.25
	# 骨骼离散采样本身也会带进折角（10 根骨骼 → 21 个采样点）。对局部转角
	# 超阈值的点做邻域平均，直到整条曲线的一阶导数连续。
	for _iter in 3:
		var moved := false
		for i in range(3, n - 3):
			var a: Vector3 = pts[i - 1]
			var b: Vector3 = pts[i]
			var c: Vector3 = pts[i + 1]
			var d0 := (b - a).normalized()
			var d1 := (c - b).normalized()
			if rad_to_deg(d0.angle_to(d1)) > 16.0:
				pts[i] = b.lerp((a + c) * 0.5, 0.55)
				moved = true
		if not moved:
			break
	for i in n:
		pts[i] = _clamp_point_outside_barriers(pts[i], role, float(i) / float(n - 1))


func _on_skeleton_updated() -> void:
	if not _configured:
		return
	# 网格由 GPU 蒙皮跟随骨骼，这里只更新用于 QA/特效的刀尖缓存
	_update_tips()


func _update_tips() -> void:
	if _skeleton == null or _strands.is_empty():
		return
	var world_xf := _skeleton.global_transform
	var tips: Array[Vector3] = []
	tips.resize(_strands.size())
	for s in _strands.size():
		var chain: PackedInt32Array = _strands[s]["bones"]
		var last: int = chain[SEGMENTS - 1]
		var pose := _skeleton.get_bone_global_pose(last)
		tips[s] = world_xf * (pose.origin + pose.basis.y * float(_strands[s]["lens"][SEGMENTS - 1]))
	_tip_world = tips


func _rebuild_from_poses() -> void:
	if _mesh_inst == null or _skeleton == null or _strands.is_empty():
		return
	var world_xf := _skeleton.global_transform
	var tips: Array[Vector3] = []
	tips.resize(_strands.size())
	for s in _strands.size():
		var strand: Dictionary = _strands[s]
		var pts := _read_points(strand)
		strand["points"] = pts
		var role := String(strand["role"])
		var render_pts := _subdivide_smooth(pts, role)
		# _relax_render_points(render_pts, role)  # disabled for profiling
		strand["render_points"] = render_pts
		tips[s] = world_xf * pts[POINTS - 1]
	_tip_world = tips
	_rebuild_surface()


func _rebuild_surface() -> void:
	var n := _strands.size()
	var cs := CROSS_SEGS
	var r_pts := RENDER_POINTS
	var r_segs := RENDER_SEGMENTS
	var verts_per_strand := r_pts * cs + 2
	var tris_per_strand := r_segs * cs * 2 + cs * 2

	var sheet_rows: Array[PackedInt32Array] = []
	for r_i in mini(_back_row_indices.size(), 2):
		if _back_row_indices[r_i].size() >= 2:
			sheet_rows.append(_back_row_indices[r_i])

	var sheet_verts := 0
	var sheet_tris := 0
	for sr in sheet_rows:
		var cols := sr.size()
		sheet_verts += cols * r_pts * 2
		sheet_tris += (cols - 1) * r_segs * 4 + (cols - 1) * 2 + 2 * r_segs * 2

	var total_verts := n * verts_per_strand + sheet_verts
	var total_indices := (n * tris_per_strand + sheet_tris) * 3

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var idx := PackedInt32Array()

	verts.resize(total_verts)
	normals.resize(total_verts)
	colors.resize(total_verts)
	uvs.resize(total_verts)
	uv2s.resize(total_verts)
	idx.resize(total_indices)

	var vi := 0
	var ii := 0

	for s in n:
		var strand: Dictionary = _strands[s]
		var pts: PackedVector3Array = strand.get("render_points", _subdivide_smooth(strand["points"], String(strand["role"])))
		var w0: float = strand["width"]
		var th0: float = strand["thick"]
		var phase: float = strand["phase"]
		var twist: float = strand["twist"]
		var cr: Color = strand["root"]
		var cm: Color = strand["mid"]
		var ct: Color = strand["tip"]
		var nhint: Vector3 = strand["normal_hint"]
		var role: String = strand["role"]

		var base_v := vi
		var tangents := PackedVector3Array()
		tangents.resize(r_pts)
		for j in r_pts:
			var t_vec: Vector3
			if j == 0:
				t_vec = pts[1] - pts[0]
			elif j == r_pts - 1:
				t_vec = pts[r_pts - 1] - pts[r_pts - 2]
			else:
				t_vec = pts[j + 1] - pts[j - 1]
			if t_vec.length_squared() < 1e-10:
				t_vec = Vector3.DOWN
			tangents[j] = t_vec.normalized()

		var prev_nrm := (nhint - tangents[0] * nhint.dot(tangents[0]))
		if prev_nrm.length_squared() < 1e-6:
			prev_nrm = tangents[0].cross(Vector3.RIGHT)
		prev_nrm = prev_nrm.normalized()

		for j in r_pts:
			var t := float(j) / float(r_pts - 1)
			var tang := tangents[j]
			var nrm := prev_nrm - tang * prev_nrm.dot(tang)
			if nrm.length_squared() < 1e-6:
				nrm = tang.cross(Vector3.RIGHT)
			nrm = nrm.normalized()
			prev_nrm = nrm
			var bnr := tang.cross(nrm).normalized()

			var tw_ang := twist * t
			var b_rot := bnr * cos(tw_ang) + nrm * sin(tw_ang)
			var n_rot := -bnr * sin(tw_ang) + nrm * cos(tw_ang)

			# 根部扁平贴合头皮发壳（只留 0.4mm 薄过渡，绝不突兀拱起），向下垂落时渐变为饱满立体发束
			var root_swell_w := 0.85 + 0.15 * smoothstep(0.0, 0.22, t)
			var root_swell_th := 0.08 + 0.92 * smoothstep(0.04, 0.30, t)
			var mid_bulge := 1.0 + 0.16 * sin(clampf(t / 0.72, 0.0, 1.0) * PI)
			# Per-lock tip shape.  `phase` runs smoothly along each row, so these
			# vary in LOW-frequency clusters: some locks end in a sharp point,
			# neighbouring locks end in a blunt/rounded cut, and the taper starts
			# at different depths.  Not every strand is a spike.
			var tip_wave := 0.5 + 0.5 * sin(phase * 1.7 + 0.35)
			var tip_wave2 := 0.5 + 0.5 * sin(phase * 0.53 + 1.15)
			var tip_start := lerpf(0.52, 0.84, tip_wave)
			var tip_min := lerpf(0.035, 0.46, tip_wave2)
			var tip_pow := lerpf(2.6, 0.85, tip_wave)
			if role == "fringe":
				tip_start = lerpf(0.42, 0.72, tip_wave)
				tip_min = lerpf(0.03, 0.34, tip_wave2)
			var tip_taper := 1.0
			if t > tip_start:
				var ut := (t - tip_start) / (1.0 - tip_start)
				tip_taper = tip_min + (1.0 - tip_min) * pow(maxf(1.0 - ut, 0.0), tip_pow)
			var w := maxf(w0 * 0.5 * root_swell_w * mid_bulge * tip_taper, 0.00004)
			var th := maxf(th0 * 0.5 * root_swell_th * tip_taper, 0.00004)

			var col_along := cr.lerp(cm, smoothstep(0.0, 0.55, t)).lerp(ct, smoothstep(0.45, 1.0, t))

			for k in cs:
				var ang := TAU * float(k) / float(cs)
				var ca := cos(ang)
				var sa := sin(ang)
				var bo := ca * w
				var no := sa * th * (0.72 + 0.28 * absf(sa))
				var vp := pts[j] + b_rot * bo + n_rot * no
				var vn := (b_rot * (ca / maxf(w, 1e-5)) + n_rot * (sa / maxf(th, 1e-5))).normalized()

				var side_shade := 0.90 + 0.10 * maxf(sa, -0.3)
				var c_vert := Color(side_shade, side_shade, side_shade, 1.0)
				var bias_v: float = strand["color_blend"]

				verts[vi] = vp
				normals[vi] = vn
				colors[vi] = c_vert
				uvs[vi] = Vector2(float(k) / float(cs), t)
				uv2s[vi] = Vector2(phase, bias_v)
				vi += 1

		var root_cap_i := vi
		var bias_cap: float = strand["color_blend"]
		verts[vi] = pts[0]
		normals[vi] = -tangents[0]
		colors[vi] = Color(0.88, 0.88, 0.88, 1.0)
		uvs[vi] = Vector2(0.5, 0.0)
		uv2s[vi] = Vector2(phase, bias_cap)
		vi += 1

		var tip_cap_i := vi
		verts[vi] = pts[r_pts - 1]
		normals[vi] = tangents[r_pts - 1]
		colors[vi] = Color(1.0, 1.0, 1.0, 1.0)
		uvs[vi] = Vector2(0.5, 1.0)
		uv2s[vi] = Vector2(phase, bias_cap)
		vi += 1

		for j in r_segs:
			var r0 := base_v + j * cs
			var r1 := base_v + (j + 1) * cs
			for k in cs:
				var k1 := (k + 1) % cs
				var a0 := r0 + k
				var a1 := r0 + k1
				var b1 := r1 + k1
				var b0 := r1 + k
				idx[ii] = a0
				idx[ii + 1] = a1
				idx[ii + 2] = b1
				idx[ii + 3] = a0
				idx[ii + 4] = b1
				idx[ii + 5] = b0
				ii += 6

		for k in cs:
			var k1 := (k + 1) % cs
			idx[ii] = root_cap_i
			idx[ii + 1] = base_v + k1
			idx[ii + 2] = base_v + k
			ii += 3
			var last_r := base_v + (r_pts - 1) * cs
			idx[ii] = tip_cap_i
			idx[ii + 1] = last_r + k
			idx[ii + 2] = last_r + k1
			ii += 3

	for sr in sheet_rows:
		var cols := sr.size()
		for pass_side in 1:
			var s_sign := 1.0 if pass_side == 0 else -1.0
			var sheet_base := vi
			for c in cols:
				var s_idx: int = sr[c]
				var st_d: Dictionary = _strands[s_idx]
				var pts: PackedVector3Array = st_d.get("render_points", _subdivide_smooth(st_d["points"], String(st_d["role"])))
				var rad: Vector3 = st_d["radial"]
				var cr: Color = st_d["root"].darkened(0.18)
				var cm: Color = st_d["mid"].darkened(0.14)
				var ct: Color = st_d["tip"].darkened(0.10)
				var ph: float = st_d["phase"]
				var bias_s: float = st_d["color_blend"]
				for j in r_pts:
					var t := float(j) / float(r_pts - 1)
					var p := pts[j] - rad * (0.0038 * (1.0 - 0.5 * t))
					verts[vi] = p
					normals[vi] = rad * s_sign
					colors[vi] = Color(0.80, 0.80, 0.80, 1.0)
					uvs[vi] = Vector2(float(c) / float(cols - 1) * 4.0, t)
					uv2s[vi] = Vector2(ph, bias_s)
					vi += 1
			for c in cols - 1:
				for j in r_segs:
					var i0 := sheet_base + c * r_pts + j
					var i1 := sheet_base + (c + 1) * r_pts + j
					var i2 := i1 + 1
					var i3 := i0 + 1
					if pass_side == 0:
						idx[ii] = i0
						idx[ii + 1] = i1
						idx[ii + 2] = i2
						idx[ii + 3] = i0
						idx[ii + 4] = i2
						idx[ii + 5] = i3
					else:
						idx[ii] = i0
						idx[ii + 1] = i2
						idx[ii + 2] = i1
						idx[ii + 3] = i0
						idx[ii + 4] = i3
						idx[ii + 5] = i2
					ii += 6


	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_INDEX] = idx
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_inst.visible = true


## Deterministic hash → [0, 1).  Used to give each sheet column an irregular
## hem depth so the lower edge reads ragged instead of a flat horizontal cut.
func _hem_hash(x: float) -> float:
	x = sin(x * 12.9898 + 78.233) * 43758.5453
	return x - floor(x)


## Per-column hem length factor in [0.82, 1.0].  A low-frequency envelope makes
## neighbouring columns end at similar depths (clusters), while a per-column
## jitter keeps every column a little different.  Dips below 1.0 shorten the
## column so the sheet's bottom border is a ragged line of fine points.
func _col_tip_fac(c: int, ph: float, seed: float) -> float:
	# Low-frequency clumps: neighbouring columns end at similar depths, with a
	# second slower wave and per-column jitter on top.
	var low := 0.5 + 0.5 * sin(float(c) * 0.33 + ph * 1.7 + seed)
	var low2 := 0.5 + 0.5 * sin(float(c) * 0.91 + 2.3 + ph * 0.4)
	var jit := _hem_hash(float(c) * 3.101 + ph * 7.717 + seed * 1.31) - 0.5
	var v := clampf(0.58 * low + 0.24 * low2 + 0.36 * jit + 0.09, 0.0, 1.0)
	return 0.90 + 0.10 * v


## Squeeze the lower portion of a sheet column so its tip lands at `tip_fac` of
## its natural length (the root stays fixed and every column keeps the same
## vertex count, so the quad strip remains valid).  Used to break the common
## bottom parameter into a ragged hem.
func _sheet_column_pts(pts: PackedVector3Array, tip_fac: float) -> PackedVector3Array:
	if tip_fac >= 1.0:
		return pts
	var n := pts.size()
	if n < 2:
		return pts
	var root := pts[0]
	var dir := pts[n - 1] - root
	var dlen := dir.length()
	if dlen < 1e-6:
		return pts
	dir /= dlen
	var target := root + dir * (dlen * tip_fac)
	var out := pts.duplicate()
	for i in n:
		var tt := float(i) / float(n - 1)
		var w := smoothstep(0.42, 0.92, tt)
		out[i] = pts[i].lerp(target, w)
	return out


## Build the hair ONCE as a GPU-skinned mesh.  SpringBoneSimulator animates the
## 10-bone chains; Godot's skinning deforms the rest-pose ribbons every frame at
## zero CPU cost.  The old per-frame ArrayMesh rebuild cost ~20-60 ms/frame.
func _build_skinned_mesh() -> void:
	var n := _strands.size()
	var cs := CROSS_SEGS
	var r_pts := RENDER_POINTS
	var r_segs := RENDER_SEGMENTS
	var verts_per_strand := r_pts * cs + 2
	var tris_per_strand := r_segs * cs * 2 + cs * 2

	var sheet_rows: Array[PackedInt32Array] = []
	for r_i in mini(_back_row_indices.size(), 2):
		if _back_row_indices[r_i].size() >= 2:
			sheet_rows.append(_back_row_indices[r_i])
	var sheet_verts := 0
	var sheet_tris := 0
	for sr in sheet_rows:
		var cols := sr.size()
		sheet_verts += cols * r_pts * 2
		sheet_tris += (cols - 1) * r_segs * 4 + (cols - 1) * 2 + 2 * r_segs * 2
	# 前额/刘海下衬层：贴合额头的连续深色内层，正反两面各一遍（cols×r_pts×2 顶点）
	var fringe_verts := 0
	var fringe_tris := 0
	if _fringe_indices.size() >= 2:
		fringe_verts = _fringe_indices.size() * r_pts * 2
		fringe_tris = (_fringe_indices.size() - 1) * r_segs * 4
	var total_verts := n * verts_per_strand + sheet_verts + fringe_verts
	var total_indices := (n * tris_per_strand + sheet_tris + fringe_tris) * 3

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()
	verts.resize(total_verts)
	normals.resize(total_verts)
	colors.resize(total_verts)
	uvs.resize(total_verts)
	uv2s.resize(total_verts)
	bones.resize(total_verts * 4)
	weights.resize(total_verts * 4)
	idx.resize(total_indices)

	var vi := 0
	var ii := 0

	for s in n:
		var strand: Dictionary = _strands[s]
		var rest_pts: PackedVector3Array = strand["rest_points"]
		var pts := _subdivide_smooth(rest_pts, String(strand["role"]))
		_relax_render_points(pts, String(strand["role"]))
		strand["render_points"] = pts
		var chain: PackedInt32Array = strand["bones"]
		var w0: float = strand["width"]
		var th0: float = strand["thick"]
		var phase: float = strand["phase"]
		var twist: float = strand["twist"]
		var cr: Color = strand["root"]
		var cm: Color = strand["mid"]
		var ct: Color = strand["tip"]
		var nhint: Vector3 = strand["normal_hint"]
		var role: String = strand["role"]
		var base_v := vi

		var tangents := PackedVector3Array()
		tangents.resize(r_pts)
		for j in r_pts:
			var t_vec: Vector3
			if j == 0:
				t_vec = pts[1] - pts[0]
			elif j == r_pts - 1:
				t_vec = pts[r_pts - 1] - pts[r_pts - 2]
			else:
				t_vec = pts[j + 1] - pts[j - 1]
			if t_vec.length_squared() < 1e-10:
				t_vec = Vector3.DOWN
			tangents[j] = t_vec.normalized()
		var prev_nrm := (nhint - tangents[0] * nhint.dot(tangents[0]))
		if prev_nrm.length_squared() < 1e-6:
			prev_nrm = tangents[0].cross(Vector3.RIGHT)
		prev_nrm = prev_nrm.normalized()

		for j in r_pts:
			var t := float(j) / float(r_pts - 1)
			var tang := tangents[j]
			var nrm := prev_nrm - tang * prev_nrm.dot(tang)
			if nrm.length_squared() < 1e-6:
				nrm = tang.cross(Vector3.RIGHT)
			nrm = nrm.normalized()
			prev_nrm = nrm
			var bnr := tang.cross(nrm).normalized()
			var tw_ang := twist * t
			var b_rot := bnr * cos(tw_ang) + nrm * sin(tw_ang)
			var n_rot := -bnr * sin(tw_ang) + nrm * cos(tw_ang)
			var root_swell_w := 0.85 + 0.15 * smoothstep(0.0, 0.22, t)
			var root_swell_th := 0.08 + 0.92 * smoothstep(0.04, 0.30, t)
			var mid_bulge := 1.0 + 0.16 * sin(clampf(t / 0.72, 0.0, 1.0) * PI)
			# Per-lock tip shape.  `phase` runs smoothly along each row, so these
			# vary in LOW-frequency clusters: some locks end in a sharp point,
			# neighbouring locks end in a blunt/rounded cut, and the taper starts
			# at different depths.  Not every strand is a spike.
			var tip_wave := 0.5 + 0.5 * sin(phase * 1.7 + 0.35)
			var tip_wave2 := 0.5 + 0.5 * sin(phase * 0.53 + 1.15)
			var tip_start := lerpf(0.52, 0.84, tip_wave)
			var tip_min := lerpf(0.035, 0.46, tip_wave2)
			var tip_pow := lerpf(2.6, 0.85, tip_wave)
			if role == "fringe":
				tip_start = lerpf(0.42, 0.72, tip_wave)
				tip_min = lerpf(0.03, 0.34, tip_wave2)
			var tip_taper := 1.0
			if t > tip_start:
				var ut := (t - tip_start) / (1.0 - tip_start)
				tip_taper = tip_min + (1.0 - tip_min) * pow(maxf(1.0 - ut, 0.0), tip_pow)
			var w := maxf(w0 * 0.5 * root_swell_w * mid_bulge * tip_taper, 0.00004)
			var th := maxf(th0 * 0.5 * root_swell_th * tip_taper, 0.00004)

			# 骨骼权重：相邻两骨线性混合，曲线弯曲处保持光滑
			var bf := clampf(t * float(SEGMENTS), 0.0, float(SEGMENTS))
			var bi := mini(int(bf), SEGMENTS - 1)
			var f := bf - float(bi)
			if bi == SEGMENTS - 1:
				f = 0.0
			var bone_a := chain[bi]
			var bone_b := chain[mini(bi + 1, SEGMENTS - 1)]

			for k in cs:
				var ang := TAU * float(k) / float(cs)
				var ca := cos(ang)
				var sa := sin(ang)
				var bo := ca * w
				var no := sa * th * (0.72 + 0.28 * absf(sa))
				verts[vi] = pts[j] + b_rot * bo + n_rot * no
				normals[vi] = (b_rot * (ca / maxf(w, 1e-5)) + n_rot * (sa / maxf(th, 1e-5))).normalized()
				colors[vi] = Color(0.90 + 0.10 * maxf(sa, -0.3), 0.90 + 0.10 * maxf(sa, -0.3), 0.90 + 0.10 * maxf(sa, -0.3), 1.0)
				uvs[vi] = Vector2(float(k) / float(cs), t)
				uv2s[vi] = Vector2(phase, float(strand["color_blend"]))
				var bo4 := vi * 4
				bones[bo4] = bone_a
				bones[bo4 + 1] = bone_b
				weights[bo4] = 1.0 - f
				weights[bo4 + 1] = f
				vi += 1

		var root_cap_i := vi
		verts[vi] = pts[0]
		normals[vi] = -tangents[0]
		colors[vi] = Color(0.88, 0.88, 0.88, 1.0)
		uvs[vi] = Vector2(0.5, 0.0)
		uv2s[vi] = Vector2(phase, float(strand["color_blend"]))
		bones[vi * 4] = chain[0]
		weights[vi * 4] = 1.0
		vi += 1
		var tip_cap_i := vi
		verts[vi] = pts[r_pts - 1]
		normals[vi] = tangents[r_pts - 1]
		colors[vi] = Color(1.0, 1.0, 1.0, 1.0)
		uvs[vi] = Vector2(0.5, 1.0)
		uv2s[vi] = Vector2(phase, float(strand["color_blend"]))
		bones[vi * 4] = chain[SEGMENTS - 1]
		weights[vi * 4] = 1.0
		vi += 1

		for j in r_segs:
			var r0 := base_v + j * cs
			var r1 := base_v + (j + 1) * cs
			for k in cs:
				var k1 := (k + 1) % cs
				idx[ii] = r0 + k
				idx[ii + 1] = r0 + k1
				idx[ii + 2] = r1 + k1
				idx[ii + 3] = r0 + k
				idx[ii + 4] = r1 + k1
				idx[ii + 5] = r1 + k
				ii += 6
		for k in cs:
			var k1 := (k + 1) % cs
			idx[ii] = root_cap_i
			idx[ii + 1] = base_v + k1
			idx[ii + 2] = base_v + k
			ii += 3
			var last_r := base_v + (r_pts - 1) * cs
			idx[ii] = tip_cap_i
			idx[ii + 1] = last_r + k
			idx[ii + 2] = last_r + k1
			ii += 3

	for sr_i in sheet_rows.size():
		var sr: PackedInt32Array = sheet_rows[sr_i]
		var cols := sr.size()
		var sheet_bases := PackedInt32Array()
		for pass_side in 2:
			var s_sign := 1.0 if pass_side == 0 else -1.0
			var sheet_base := vi
			sheet_bases.append(sheet_base)
			for c in cols:
				var s_idx: int = sr[c]
				var st_d: Dictionary = _strands[s_idx]
				var chain: PackedInt32Array = st_d["bones"]
				var rad: Vector3 = st_d["radial"]
				var ph: float = st_d["phase"]
				var bias_s: float = st_d["color_blend"]
				# Ragged hem: each column ends at its own depth.
				var tip_fac: float = _col_tip_fac(c, ph, float(sr_i) * 2.31)
				var pts: PackedVector3Array = _sheet_column_pts(st_d["render_points"], tip_fac)
				# Each sheet column is pushed out by its own small amount so the
				# back of the hairstyle reads as overlapping locks instead of one
				# perfectly smooth balloon.
				var ridge := 0.0
				var row_in := 0.0065 - 0.0045 * float(sr_i)
				for j in r_pts:
					var t := float(j) / float(r_pts - 1)
					verts[vi] = pts[j] + rad * ridge - rad * (row_in * (1.0 - 0.5 * t))
					normals[vi] = rad * s_sign
					colors[vi] = Color(0.80, 0.80, 0.80, 1.0)
					uvs[vi] = Vector2(1.0 + float(c) / float(cols - 1) * 3.0, t)
					uv2s[vi] = Vector2(ph, bias_s)
					var bf := clampf(t * float(SEGMENTS), 0.0, float(SEGMENTS))
					var bi := mini(int(bf), SEGMENTS - 1)
					var f := bf - float(bi)
					if bi == SEGMENTS - 1:
						f = 0.0
					var bo4 := vi * 4
					bones[bo4] = chain[bi]
					bones[bo4 + 1] = chain[mini(bi + 1, SEGMENTS - 1)]
					weights[bo4] = 1.0 - f
					weights[bo4 + 1] = f
					vi += 1
			for c in cols - 1:
				for j in r_segs:
					var i0 := sheet_base + c * r_pts + j
					var i1 := sheet_base + (c + 1) * r_pts + j
					var i2 := i1 + 1
					var i3 := i0 + 1
					if pass_side == 0:
						idx[ii] = i0
						idx[ii + 1] = i1
						idx[ii + 2] = i2
						idx[ii + 3] = i0
						idx[ii + 4] = i2
						idx[ii + 5] = i3
					else:
						idx[ii] = i0
						idx[ii + 1] = i2
						idx[ii + 2] = i1
						idx[ii + 3] = i0
						idx[ii + 4] = i3
						idx[ii + 5] = i2
					ii += 6

		# Close the sheet slab: real thickness instead of a paper plane.
		if sheet_bases.size() == 2:
			var fb: int = sheet_bases[0]
			var bb: int = sheet_bases[1]
			for c in cols - 1:
				var f0: int = fb + c * r_pts + (r_pts - 1)
				var f1: int = fb + (c + 1) * r_pts + (r_pts - 1)
				var b0: int = bb + c * r_pts + (r_pts - 1)
				var b1: int = bb + (c + 1) * r_pts + (r_pts - 1)
				idx[ii] = f0
				idx[ii + 1] = f1
				idx[ii + 2] = b1
				idx[ii + 3] = f0
				idx[ii + 4] = b1
				idx[ii + 5] = b0
				ii += 6
			for edge_c in [0, cols - 1]:
				for j in r_segs:
					var f0: int = fb + edge_c * r_pts + j
					var f1: int = fb + edge_c * r_pts + j + 1
					var b0: int = bb + edge_c * r_pts + j
					var b1: int = bb + edge_c * r_pts + j + 1
					idx[ii] = f0
					idx[ii + 1] = f1
					idx[ii + 2] = b1
					idx[ii + 3] = f0
					idx[ii + 4] = b1
					idx[ii + 5] = b0
					ii += 6

	# 前额/刘海下衬层：贴合额头的一整片连续深色内层，蒙皮到刘海骨骼。
	# 顶点沿 radial 反向（朝头）内收，根部收得更多好藏进发根；骨骼权重向根偏置
	# （0.7），使这层比表层刘海摆动更小、始终贴住额头，刘海被风吹起/甩动时露出的是
	# 浓密的下层头发而非秃头皮。正反两面各一遍（双面），避免卷绕方向歧义。
	if _fringe_indices.size() >= 2:
		var cols := _fringe_indices.size()
		for pass_side in 1:
			var s_sign := 1.0 if pass_side == 0 else -1.0
			var sheet_base := vi
			for c in cols:
				var s_idx: int = _fringe_indices[c]
				var st_d: Dictionary = _strands[s_idx]
				var chain: PackedInt32Array = st_d["bones"]
				var rad: Vector3 = st_d["radial"]
				var ph: float = st_d["phase"]
				# Ragged hem on the fringe under-sheet too (soft, per-column depth).
				var tip_fac: float = _col_tip_fac(c, ph, 5.17)
				var pts: PackedVector3Array = _sheet_column_pts(st_d["render_points"], tip_fac)
				for j in r_pts:
					var t := float(j) / float(r_pts - 1)
					verts[vi] = pts[j] - rad * (0.0045 * (1.0 - 0.3 * t))
					normals[vi] = rad * s_sign
					colors[vi] = Color(0.60, 0.72, 0.86, 1.0)
					uvs[vi] = Vector2(1.0 + float(c) / float(cols - 1) * 2.0, t)
					uv2s[vi] = Vector2(ph, 0.22)
					var bf := clampf(t * float(SEGMENTS) * 0.7, 0.0, float(SEGMENTS) - 0.001)
					var bi := mini(int(bf), SEGMENTS - 1)
					var f := bf - float(bi)
					if bi == SEGMENTS - 1:
						f = 0.0
					var bo4 := vi * 4
					bones[bo4] = chain[bi]
					bones[bo4 + 1] = chain[mini(bi + 1, SEGMENTS - 1)]
					weights[bo4] = 1.0 - f
					weights[bo4 + 1] = f
					vi += 1
			for c in cols - 1:
				for j in r_segs:
					var i0 := sheet_base + c * r_pts + j
					var i1 := sheet_base + (c + 1) * r_pts + j
					var i2 := i1 + 1
					var i3 := i0 + 1
					if pass_side == 0:
						idx[ii] = i0
						idx[ii + 1] = i1
						idx[ii + 2] = i2
						idx[ii + 3] = i0
						idx[ii + 4] = i2
						idx[ii + 5] = i3
					else:
						idx[ii] = i0
						idx[ii + 1] = i2
						idx[ii + 2] = i1
						idx[ii + 3] = i0
						idx[ii + 4] = i3
						idx[ii + 5] = i2
					ii += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	arrays[Mesh.ARRAY_INDEX] = idx
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_inst.skeleton = _skeleton.get_path()
	_mesh_inst.visible = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE and _skeleton != null and _configured:
		if _sim != null:
			_sim.reset()
		_align_skeleton()
		_update_tips()
