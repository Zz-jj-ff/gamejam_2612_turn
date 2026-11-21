extends RefCounted
## VESPER v2 body builder — all geometry in metres, model faces -Z.
##
## The rig (mech_rig.gd) owns motion; this file only creates the node hierarchy
## and the meshes.  P is the single source of truth for joint dimensions.

const MK = preload("res://scripts/mech/mesh_kit.gd")
const MAT = preload("res://scripts/mech/materials.gd")
const HS = preload("res://scripts/mech/head_shape.gd")

const P := {
	"hip_y": 1.235, "hip_r": 0.30, "femur": 0.60, "tibia": 0.66,
	"foot_r": 0.50, "ankle_h": 0.08, "waist_y": 0.12,
	"torso_scale": 0.82, "upper_scale": 1.35, "lower_scale": 0.78,
	"upper": 0.62, "fore": 0.58, "grip": 0.16,
	"shoulder": Vector3(0.32, 0.38, -0.02),
	"blade_y0": 0.28, "blade_len": 1.25,
	"leg_az": [45.0, 135.0, 225.0, 315.0],
}


static func params() -> Dictionary:
	return P.duplicate(true)


static func build(rig: Node3D) -> void:
	rig.body = Node3D.new()
	rig.body.name = "Body"
	rig.body.position = Vector3(0, float(P["hip_y"]) * float(P["lower_scale"]), 0)
	rig.add_child(rig.body)

	# Lower body (pelvis + legs) scales down uniformly so the upper half can
	# read bigger/taller while the lower half shrinks.  The torso stays a
	# sibling of LowerBody under Body so the two halves resize independently.
	var lower := Node3D.new()
	lower.name = "LowerBody"
	lower.scale = Vector3.ONE * float(P["lower_scale"])
	rig.body.add_child(lower)
	rig.lower_body = lower

	_build_pelvis(rig)
	_build_torso(rig)
	for i in 4:
		_build_leg(rig, i, deg_to_rad(float(P["leg_az"][i])))
	_build_arms(rig)
	_build_weapon(rig)

	var shadow := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.4, 1.4)
	shadow.mesh = qm
	shadow.material_override = MAT.contact_shadow()
	shadow.rotation_degrees = Vector3(-90, 0, 0)
	shadow.position = Vector3(0, 0.008, 0)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(shadow)
	rig.contact_shadow = shadow

	# Leave the arms closed on the hilt so a static build already reads as a
	# two-handed ready stance (mech_rig re-solves this every frame anyway).
	_pose_arms_to_grip(rig)


# ------------------------------------------------------------------ pelvis
static func _build_pelvis(rig: Node3D) -> void:
	var body: Node3D = rig.lower_body
	# 底盘顶部改为与上身连续的白色装甲，删掉腰下那条深蓝色垫圈
	MK.add(body, MK.prism(8, 0.255, 0.205, 0.10, PI / 8.0), MAT.armor_white(), Vector3(0, 0.02, 0))
	MK.add(body, MK.prism(8, 0.205, 0.182, 0.075, PI / 8.0), MAT.armor_white(), Vector3(0, 0.085, 0))
	MK.add(body, MK.prism(16, 0.215, 0.215, 0.012, 0), MAT.emissive(Color(0.16, 0.44, 1.0), 0.7), Vector3(0, 0.05, 0))
	MK.add(body, MK.prism(8, 0.165, 0.15, 0.18, PI / 8.0), MAT.frame(), Vector3(0, -0.06, 0))
	# hip side plates
	for side in [-1.0, 1.0]:
		MK.add(body, MK.slab(0.135, 0.235, 0.18, 0.024), MAT.armor_white(),
			Vector3(0.255 * side, -0.01, -0.01), Vector3(0, 0, -16 * side))
		MK.add(body, MK.slab(0.075, 0.12, 0.06, 0.012), MAT.armor_blue(),
			Vector3(0.285 * side, 0.005, -0.055), Vector3(0, 0, -12 * side))
		MK.add(body, MK.prism(6, 0.035, 0.02, 0.035, 0), MAT.trim(),
			Vector3(0.30 * side, 0.02, -0.08), Vector3(90, 0, 0))
	# front pelvis plate
	MK.add(body, MK.slab(0.20, 0.12, 0.11, 0.018), MAT.armor_blue(), Vector3(0, -0.03, -0.20), Vector3(14, 0, 0))
	MK.add(body, MK.slab(0.12, 0.04, 0.03, 0.006), MAT.emissive(Color(0.18, 0.45, 1.0), 0.8), Vector3(0, -0.02, -0.26), Vector3(14, 0, 0))
	# 腰与下身直接衔接：去掉旧版竖经线和深蓝垫圈，避免腰部出现断开感


# ------------------------------------------------------------------- torso
static func _build_torso(rig: Node3D) -> void:
	var torso := Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0, float(P["waist_y"]), 0)
	torso.scale = Vector3.ONE * float(P["torso_scale"]) * float(P["upper_scale"])
	rig.body.add_child(torso)
	rig.torso = torso

	# 1. 参数化连续女性机甲上身曲面（从腰部 y=0.035 到领口 y=0.575，一体成型：
	#    含纤细蜂腰、一体流线型胸甲起伏、锁骨斜坡，彻底告别突兀贴球与黑柱）
	var shells := HS.build_feminine_torso_shell()
	MK.add(torso, shells["white"], MAT.armor_white(), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, "TorsoCuirassWhite")
	MK.add(torso, shells["blue"], MAT.armor_blue(), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, "TorsoBodysuitBlue")

	# 2. 直面硬表面装甲拼接（与参数曲面有机结合）：
	# 腰部衔接环（桥接四足底座 pelvis 与纤细腰身）
	MK.add(torso, MK.prism(8, 0.184, 0.184, 0.055, PI / 8.0), MAT.armor_white(), Vector3(0, 0.025, 0.0), Vector3.ZERO, Vector3(1.15, 1.0, 0.85))
	MK.add(torso, MK.prism(8, 0.167, 0.151, 0.024, PI / 8.0), MAT.trim(), Vector3(0, 0.060, 0.0), Vector3.ZERO, Vector3(1.15, 1.0, 0.85))

	# 腹部正面 V 型流线装甲板与能量导光缝
	MK.add(torso, MK.slab(0.082, 0.035, 0.14, 0.008), MAT.armor_blue(), Vector3(0, 0.20, -0.103), Vector3(6, 0, 0))
	MK.add(torso, MK.slab(0.022, 0.016, 0.11, 0.003), MAT.emissive(Color(0.24, 0.56, 1.0), 1.6), Vector3(0, 0.21, -0.117), Vector3(6, 0, 0))

	# 胸甲下方 V 型收束金属托架与高光灯带
	for side in [-1.0, 1.0]:
		MK.add(torso, MK.slab(0.095, 0.032, 0.024, 0.005), MAT.trim(),
			Vector3(0.056 * side, 0.305, -0.122), Vector3(12, -16 * side, -14 * side))
		MK.add(torso, MK.slab(0.078, 0.016, 0.010, 0.002), MAT.emissive(Color(0.28, 0.62, 1.0), 1.8),
			Vector3(0.056 * side, 0.296, -0.134), Vector3(12, -16 * side, -14 * side))
		# 肋侧斜向装甲护翼（直面折角拼接在曲面腰侧）
		MK.add(torso, MK.slab(0.036, 0.088, 0.15, 0.008), MAT.armor_white(),
			Vector3(0.142 * side, 0.185, -0.018), Vector3(4, -12 * side, -16 * side))
		MK.add(torso, MK.slab(0.024, 0.068, 0.11, 0.005), MAT.armor_blue(),
			Vector3(0.150 * side, 0.175, -0.032), Vector3(4, -12 * side, -16 * side))
		# 锁骨高光灯条与上胸侧翼装甲片
		MK.add(torso, MK.slab(0.082, 0.020, 0.016, 0.003), MAT.emissive(Color(0.55, 0.82, 1.0), 2.2),
			Vector3(0.086 * side, 0.505, -0.088), Vector3(18, -12 * side, -8 * side))
		MK.add(torso, MK.slab(0.045, 0.072, 0.085, 0.007), MAT.trim(),
			Vector3(0.168 * side, 0.420, -0.038), Vector3(0, -14 * side, -12 * side))

	# 胸口中央核心徽记（倒梯形精致装甲块 + 蓝光核心缝）
	MK.add(torso, MK.prism(6, 0.028, 0.036, 0.055, PI / 6.0), MAT.trim(), Vector3(0, 0.425, -0.140), Vector3(82, 0, 0))
	MK.add(torso, MK.slab(0.014, 0.014, 0.048, 0.002), MAT.emissive(Color(0.45, 0.78, 1.0), 2.0), Vector3(0, 0.425, -0.152), Vector3(-8, 0, 0))

	# 领口装甲环与纤细机甲脖颈
	MK.add(torso, MK.ellipsoid(Vector3(0.135, 0.026, 0.118), 12, 40, 0.0, PI * 0.62),
		MAT.armor_blue(), Vector3(0, 0.555, -0.004))
	MK.add(torso, MK.ellipsoid(Vector3(0.112, 0.018, 0.100), 10, 36, 0.0, PI * 0.55),
		MAT.trim(), Vector3(0, 0.574, -0.004))
	MK.add(torso, MK.prism(12, 0.056, 0.050, 0.070, PI / 12.0), MAT.frame(), Vector3(0, 0.555, -0.005))
	MK.add(torso, MK.prism(12, 0.076, 0.066, 0.028, PI / 12.0), MAT.trim(), Vector3(0, 0.574, -0.005))
	MK.add(torso, MK.prism(12, 0.066, 0.060, 0.018, PI / 12.0), MAT.armor_blue(), Vector3(0, 0.588, -0.005))

	# 背部脊椎装甲板（与参数曲面背部贴合）
	MK.add(torso, MK.slab(0.24, 0.08, 0.20, 0.018), MAT.armor_blue(), Vector3(0, 0.42, 0.115), Vector3(4, 0, 0))
	MK.add(torso, MK.slab(0.16, 0.04, 0.12, 0.010), MAT.armor_white(), Vector3(0, 0.48, 0.142), Vector3(10, 0, 0))
	_build_backpack(rig, torso)
	_build_head(rig, torso)


## Engine plume cone with its BASE BAKED onto the mesh origin and its tip on +Y.
## The old mesh was centred on its origin, so scaling it for a dash pushed half
## of the cone *inside* the backpack — the source of the "opposite-side plume"
## clipping.  With the base at the origin the plume can never enter the body.
static func _plume_mesh(radius: float, height: float) -> ArrayMesh:
	var src := MK.prism(12, radius, 0.0, height)
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] = verts[i] + Vector3(0.0, height * 0.5, 0.0)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


static func _build_backpack(rig: Node3D, torso: Node3D) -> void:
	var pack := Node3D.new()
	pack.name = "VectorPack"
	pack.position = Vector3(0, 0.115, 0.225)
	torso.add_child(pack)
	# main vector-thruster housing: deliberately oversized so it reads from
	# the gameplay camera and gives the long hair a shelf to drape over.
	MK.add(pack, MK.slab(0.42, 0.165, 0.23, 0.028), MAT.armor_dark(), Vector3.ZERO)
	MK.add(pack, MK.slab(0.335, 0.105, 0.16, 0.018), MAT.armor_blue(), Vector3(0, 0.012, 0.02))
	MK.add(pack, MK.slab(0.255, 0.060, 0.10, 0.012), MAT.armor_white(), Vector3(0, 0.058, 0.012))
	MK.add(pack, MK.prism(8, 0.062, 0.052, 0.070, 0), MAT.trim(), Vector3(0, 0.100, 0.022))
	MK.add(pack, MK.prism(8, 0.045, 0.030, 0.035, 0), MAT.emissive(Color(0.22, 0.52, 1.0), 1.2),
		Vector3(0, 0.140, 0.022))
	# 单一矢量引擎：三喷口在旋转时会互相打架，背部只保留中央一枚大推力喷口
	var sc := 1.15
	var nozzle := Node3D.new()
	nozzle.name = "Thruster0"
	nozzle.position = Vector3(0.0, -0.032, 0.100)
	pack.add_child(nozzle)
	MK.add(nozzle, MK.prism(12, 0.050 * sc, 0.050 * sc, 0.035, 0), MAT.trim(), Vector3.ZERO, Vector3(90, 0, 0))
	# 中空引擎筒：外壁是深色隔热层，后段是抛光的喷口环
	MK.add(nozzle, MK.prism(12, 0.108 * sc, 0.118 * sc, 0.180, 0), MAT.armor_dark(), Vector3(0, 0, 0.0), Vector3(90, 0, 0))
	MK.add(nozzle, MK.prism(12, 0.118 * sc, 0.118 * sc, 0.024, 0), MAT.trim(), Vector3(0, 0, 0.100), Vector3(90, 0, 0))
	# 喷口内壁（收敛筒）与喉部发光盘：都位于虹膜叶片之后，合上时完全看不到
	MK.add(nozzle, MK.prism(12, 0.112 * sc, 0.096 * sc, 0.062, 0, true, false), MAT.armor_dark(), Vector3(0, 0, 0.070), Vector3(90, 0, 0))
	MK.add(nozzle, MK.prism(12, 0.088 * sc, 0.088 * sc, 0.008, 0), MAT.emissive(Color(0.28, 0.62, 1.0), 1.6),
		Vector3(0, 0, 0.040), Vector3(90, 0, 0))
	# 分层尾焰：内芯 / 中层 / 外层共用同一套火焰 shader，靠不同半径和 mode 区分。
	# 火焰网格的底面被烘焙在节点原点上，因此喷焰永远从喷口面起算，不会倒插进机体。
	var plume_specs := [
		["flame_core", 0.052 * sc, 0.0],
		["flame", 0.078 * sc, 0.25],
		["flame_outer", 0.120 * sc, 0.70],
	]
	for spec in plume_specs:
		var flame := MeshInstance3D.new()
		flame.name = String(spec[0])
		flame.mesh = _plume_mesh(float(spec[1]), 0.95)
		flame.material_override = MAT.thruster().duplicate()
		(flame.material_override as ShaderMaterial).set_shader_parameter("boost", float(spec[2]) * 0.15)
		flame.position = Vector3(0, 0, 0.118)
		flame.rotation_degrees = Vector3(90, 0, 0)
		flame.scale = Vector3(0.1, 0.1, 0.1)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nozzle.add_child(flame)
	rig.thruster_nodes.append(nozzle)
	# 引擎盖：真正的虹膜光圈。8 片重叠金属叶片，每片绕自己位于喷口边缘的销轴
	# 在封面内旋转；合上时互相压住完全封死喷口，张开时像相机光圈一样各自滑开。
	var cover := Node3D.new()
	cover.name = "EngineIris"
	cover.position = Vector3(0, 0, 0.124)
	nozzle.add_child(cover)
	# 固定金属压圈：叶片从它下面滑出
	var bezel := TorusMesh.new()
	bezel.inner_radius = 0.118
	bezel.outer_radius = 0.152
	bezel.rings = 32
	bezel.ring_segments = 8
	MK.add(cover, bezel, MAT.trim(), Vector3.ZERO, Vector3(90, 0, 0), Vector3(1, 1, 0.8), "IrisBezel")
	for i in 8:
		var a := TAU * float(i) / 8.0
		var pivot := Node3D.new()
		pivot.name = "IrisBlade%d" % i
		pivot.position = Vector3(cos(a) * 0.116, sin(a) * 0.116, 0.0014 * float(i))
		pivot.rotation.z = a
		cover.add_child(pivot)
		var plate := MeshInstance3D.new()
		plate.name = "Plate"
		plate.mesh = MK.slab(0.168, 0.135, 0.0050, 0.0012)
		plate.material_override = MAT.engine_petal()
		plate.rotation_degrees = Vector3(90, 0, 0)
		plate.position = Vector3(-0.084, 0, 0)
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(plate)
		rig.engine_petals.append(pivot)
	# Central hub: the 8 tips cross here; a small machined cap hides the pinhole
	# and keeps any throat light from leaking through the closed iris.
	MK.add(cover, MK.prism(10, 0.024, 0.016, 0.012, 0), MAT.trim(),
		Vector3(0, 0, 0.014), Vector3(90, 0, 0), Vector3.ONE, "IrisHub")
	# side vector vanes
	for side in [-1.0, 1.0]:
		MK.add(pack, MK.beam_x(0.26, 0.040, 0.13, 0.020, 0.065), MAT.armor_blue(),
			Vector3(0.212 * side, -0.01, 0.02), Vector3(0, 0, -90))
		MK.add(pack, MK.beam_x(0.18, 0.022, 0.050, 0.012, 0.026), MAT.emissive(Color(0.22, 0.52, 1.0), 1.2),
			Vector3(0.220 * side, 0.038, 0.02), Vector3(0, 0, -90))
	var tl := OmniLight3D.new()
	tl.name = "ThrusterLight"
	tl.light_color = Color(0.28, 0.58, 1.0)
	tl.light_energy = 0.0
	tl.omni_range = 3.0
	tl.shadow_enabled = false
	tl.position = Vector3(0, -0.04, 0.30)
	pack.add_child(tl)
	rig.thruster_light = tl


static func _build_head(rig: Node3D, torso: Node3D) -> void:
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.720, -0.006)
	head.scale = Vector3.ONE
	torso.add_child(head)
	rig.head = head

	# ---- 少女脸型基底 + 半透明黑色前脸壳 + 内部蓝色摄像头灯与小巧绿色指示灯 ----
	var eye_p := Vector3(0.0, 0.002, -0.098)
	var green_p := Vector3(-0.050, -0.046, -0.072)
	# 整个头就是一层半透明玻璃壳：没有黑色内罩，蓝色恒星悬浮在头壳内部，
	# 从外面直接透过玻璃看到它。玻璃里除了这颗恒星与绿色指示灯之外不再有
	# 任何可见几何（旧版的金属托环与下巴缝已移除）。
	var lens_mat: ShaderMaterial = (MAT.lens_blue() as ShaderMaterial).duplicate()
	lens_mat.set_shader_parameter("lens_radius", 0.062)
	rig.lens_material = lens_mat
	# Boss-style optic: the dome's pole faces the viewer (-Z), so the 7-blade
	# aperture / iris / scan wedge project as a clean disc, ~70% of head radius.
	var blue_eye := MK.add(head, MK.dome(0.062, 24, 64), lens_mat,
		Vector3(0.0, -0.012, -0.026), Vector3(-90, 0, 0), Vector3.ONE, "BlueBossEye")
	blue_eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# 镜片自身的内发光把腔体和面壳边缘照亮，形成真正的「发光」而非纯色
	var lens_light := OmniLight3D.new()
	lens_light.name = "EyeGlow"
	lens_light.light_color = Color(0.24, 0.55, 1.0)
	lens_light.light_energy = 0.9
	lens_light.omni_range = 0.32
	lens_light.shadow_enabled = false
	lens_light.position = Vector3(0.0, 0.002, -0.095)
	head.add_child(lens_light)
	rig.lens_light = lens_light

	var cam_pod := Node3D.new()
	cam_pod.name = "HeadCamera"
	cam_pod.position = Vector3(0.0, 0.002, -0.085)
	cam_pod.set_meta("lens_diameter", 0.24)
	cam_pod.set_meta("forward_axis", "-Z")
	head.add_child(cam_pod)
	rig.head_camera = cam_pod

	# 内部小巧精致的绿色指示灯（位于半透明黑壳内部 -X 侧下颌上方，比之前显著缩小）
	var green_dot := MK.add(head, MK.dome(0.0042, 6, 16), MAT.indicator_green(),
		Vector3(-0.048, -0.044, -0.064), Vector3(-90, 0, 0), Vector3.ONE, "GreenIndicator")
	rig.head_green_dot = green_dot

	# 头腔后半圈的漆黑色内衬：从面罩外面看，恒星后面只有纯黑，不见后脑壳/脖子
	MK.add(head, HS.build_cavity_liner(0.965), MAT.cavity_black(),
		Vector3.ZERO, Vector3.ZERO, Vector3.ONE, "CavityLiner")

	# 前半张脸的半透明黑壳（少女脸型轮廓，内部清晰透出蓝色摄像头灯和小型绿色指示灯）
	var visor_mi := MK.add(head, HS.build_front_visor(0.0034),
		MAT.visor_glass(), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, "FrontVisorShell")
	visor_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# ---- 浓密头皮覆盖发层（覆盖头顶、后脑勺、鬓角，与长发和刘海无缝衔接） ------
	var scalp := MK.add(head, HS.build_scalp_hair_base(), MAT.hair_cap(),
		Vector3.ZERO, Vector3.ZERO, Vector3.ONE, "ScalpHairBase")
	# No shadow casting: the scalp's shadow map produced acne stipple on the hair.
	scalp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# hair anchor
	var anchor := Node3D.new()
	anchor.name = "HairAnchor"
	anchor.position = Vector3(0, 0.115, 0.045)
	head.add_child(anchor)
	rig.hair_anchor = anchor

	# head light
	var hl := OmniLight3D.new()
	hl.light_color = Color(0.35, 0.65, 1.0)
	hl.light_energy = 0.22
	hl.omni_range = 0.75
	hl.shadow_enabled = false
	hl.position = Vector3(0.09, 0.03, -0.11)
	head.add_child(hl)


# -------------------------------------------------------------------- legs
static func _build_leg(rig: Node3D, index: int, az: float) -> void:
	var dir := Vector3(cos(az), 0, sin(az))
	var root := Node3D.new()
	root.name = "Leg%d" % index
	root.position = dir * float(P["hip_r"])
	root.rotation.y = -az
	rig.lower_body.add_child(root)

	var mount := Node3D.new()
	mount.position = dir * (float(P["hip_r"]) - 0.008)
	mount.rotation.y = -az
	rig.lower_body.add_child(mount)
	MK.add(mount, MK.prism(6, 0.10, 0.085, 0.075, 0), MAT.armor_blue(), Vector3(0.01, 0.015, 0), Vector3(0, 0, 90))
	MK.add(mount, MK.prism(12, 0.065, 0.065, 0.018, 0), MAT.trim(), Vector3(0.05, 0.015, 0), Vector3(0, 0, 90))
	MK.add(mount, MK.prism(12, 0.050, 0.045, 0.008, 0), MAT.emissive(Color(0.18, 0.45, 1.0), 0.5), Vector3(0.06, 0.015, 0), Vector3(0, 0, 90))

	var yaw := Node3D.new()
	yaw.name = "HipYaw"
	root.add_child(yaw)
	var hip := Node3D.new()
	hip.name = "HipPitch"
	yaw.add_child(hip)
	# solid hip cap: a filled disk (nonzero top radius) so the thigh root reads
	# as a capped socket rather than the old gem + open-centred torus ring.
	MK.add(hip, MK.prism(12, 0.090, 0.090, 0.028, 0), MAT.frame_light(), Vector3(0.008, 0, 0), Vector3(0, 0, 90))
	MK.add(hip, MK.prism(8, 0.020, 0.020, 0.010, 0), MAT.emissive(Color(0.35, 0.70, 1.0), 0.8), Vector3(0.055, 0.045, 0.045), Vector3(90, 0, 0))

	# femur (0.60 m)
	var femur: float = float(P["femur"])
	MK.add(hip, MK.beam_x(femur, 0.125, 0.105, 0.085, 0.075, 0.36), MAT.frame(), Vector3.ZERO)
	MK.add(hip, MK.beam_x(femur * 0.90, 0.085, 0.195, 0.060, 0.135, 0.34), MAT.armor_white(), Vector3(0.025, 0.040, 0))
	for zs in [-1.0, 1.0]:
		MK.add(hip, MK.beam_x(femur * 0.52, 0.115, 0.024, 0.080, 0.016, 0.30), MAT.armor_white(),
			Vector3(0.08, 0.005, 0.080 * zs))
		MK.add(hip, MK.beam_x(femur * 0.34, 0.022, 0.012, 0.016, 0.010), MAT.emissive(Color(0.22, 0.55, 1.0), 2.0),
			Vector3(0.16, -0.005, 0.094 * zs))
	MK.add(hip, MK.beam_x(femur * 0.70, 0.030, 0.075, 0.024, 0.055, 0.30), MAT.armor_blue(), Vector3(0.08, 0.070, 0))
	MK.add(hip, MK.beam_x(femur * 0.52, 0.014, 0.024, 0.010, 0.018), MAT.emissive(Color(0.20, 0.50, 1.0), 0.8), Vector3(0.12, 0.005, 0.062))
	MK.add(hip, MK.beam_x(femur * 0.30, 0.038, 0.13, 0.026, 0.09, 0.30), MAT.armor_blue(), Vector3(0.17, -0.055, 0))
	MK.add(hip, MK.slab(0.11, 0.13, 0.045, 0.010), MAT.armor_white(), Vector3(0.12, 0.075, 0.0), Vector3(0, 0, -6))
	MK.bolt(hip, Vector3(0.125, 0.070, 0.065), 0.012, 0.012, MAT.trim())
	MK.bolt(hip, Vector3(0.45, 0.060, 0.060), 0.010, 0.010, MAT.trim())

	# knee
	var knee := Node3D.new()
	knee.name = "Knee"
	knee.position = Vector3(femur, 0, 0)
	hip.add_child(knee)
	MK.add(knee, MK.prism(10, 0.075, 0.075, 0.13, 0), MAT.frame(), Vector3.ZERO, Vector3(90, 0, 0))
	MK.add(knee, MK.prism(6, 0.095, 0.075, 0.055, 0), MAT.armor_blue(), Vector3(0.015, 0.01, -0.070), Vector3(90, 0, 0))
	MK.add(knee, MK.prism(6, 0.080, 0.060, 0.035, 0), MAT.armor_white(), Vector3(0.015, 0.01, -0.100), Vector3(90, 0, 0))
	MK.add(knee, MK.prism(10, 0.048, 0.048, 0.008, 0), MAT.emissive(Color(0.22, 0.55, 1.0), 0.7), Vector3(0.015, 0.01, -0.122), Vector3(90, 0, 0))
	for side in [-1.0, 1.0]:
		MK.add(knee, MK.prism(6, 0.058, 0.050, 0.028, 0), MAT.trim(), Vector3(0, 0, 0.068 * side), Vector3(90, 0, 0))

	# tibia (0.66 m)
	var tibia: float = float(P["tibia"])
	MK.add(knee, MK.beam_x(tibia, 0.105, 0.090, 0.060, 0.062, 0.36), MAT.frame(), Vector3.ZERO)
	MK.add(knee, MK.beam_x(tibia * 0.88, 0.062, 0.165, 0.048, 0.105, 0.32), MAT.armor_white(), Vector3(0.035, 0.028, 0))
	for zs in [-1.0, 1.0]:
		MK.add(knee, MK.beam_x(tibia * 0.50, 0.090, 0.020, 0.060, 0.014, 0.28), MAT.armor_white(),
			Vector3(0.10, 0.004, 0.070 * zs))
	MK.add(knee, MK.beam_x(tibia * 0.44, 0.028, 0.075, 0.018, 0.050, 0.26), MAT.armor_blue(), Vector3(0.18, 0.055, 0))
	MK.add(knee, MK.beam_x(tibia * 0.54, 0.012, 0.024, 0.009, 0.016), MAT.emissive(Color(0.20, 0.50, 1.0), 0.8), Vector3(0.14, 0.005, 0.060))
	MK.add(knee, MK.beam_x(tibia * 0.30, 0.030, 0.060, 0.020, 0.040, 0.24), MAT.armor_blue(), Vector3(0.20, -0.060, 0))
	for i in 2:
		MK.add(knee, MK.beam_x(0.020, 0.115, 0.150, 0.100, 0.130, 0.30), MAT.frame_light(), Vector3(tibia * (0.34 + i * 0.30), 0, 0))
	MK.add(knee, MK.beam_x(0.030, 0.050, 0.014, 0.040, 0.010), MAT.emissive(Color(0.45, 0.75, 1.0), 1.8), Vector3(tibia * 0.70, 0.085, 0.0))
	# shin spur
	MK.add(knee, MK.blade(0.20, 0.030, 0.012, 0.02, 6), MAT.armor_white(), Vector3(tibia * 0.62, 0.055, 0.0), Vector3(0, 0, 90))

	# ankle + three-claw foot
	var ankle := Node3D.new()
	ankle.name = "Ankle"
	ankle.position = Vector3(tibia, 0, 0)
	knee.add_child(ankle)
	MK.add(ankle, MK.gem(0.045, 3, 8), MAT.frame_light(), Vector3.ZERO)
	MK.add(ankle, MK.slab(0.16, 0.15, 0.045, 0.009), MAT.armor_white(), Vector3(0.035, -0.023, 0), Vector3(0, 0, -5))
	MK.add(ankle, MK.slab(0.105, 0.085, 0.025, 0.006), MAT.armor_blue(), Vector3(0.045, -0.051, 0), Vector3(0, 0, -5))
	MK.add(ankle, MK.slab(0.070, 0.060, 0.012, 0.003), MAT.emissive(Color(0.22, 0.55, 1.0), 1.8), Vector3(0.045, -0.067, 0), Vector3(0, 0, -5))
	# rubber sole: the lowest point of the whole body sits at y ~= 0
	MK.add(ankle, MK.slab(0.150, 0.125, 0.008, 0.002), MAT.rubber(), Vector3(0.035, -0.074, 0))
	var claw_dirs := [Vector3(1, 0, 0), Vector3(1, 0, 0.62), Vector3(1, 0, -0.62)]
	for k in 3:
		var claw := MeshInstance3D.new()
		claw.mesh = MK.prism(4, 0.024, 0.0, 0.085)
		claw.material_override = MAT.armor_white()
		claw.position = Vector3(0.065, -0.028, 0.045 * (k - 1))
		claw.quaternion = Quaternion(Vector3.UP, claw_dirs[k].normalized())
		ankle.add_child(claw)
	var heel := MeshInstance3D.new()
	heel.mesh = MK.prism(4, 0.016, 0.0, 0.05)
	heel.material_override = MAT.frame_light()
	heel.position = Vector3(-0.04, -0.028, 0)
	heel.rotation_degrees = Vector3(180, 0, -26)
	ankle.add_child(heel)

	rig.legs.append({
		"root": root, "yaw": yaw, "hip": hip, "knee": knee, "ankle": ankle,
		"az": az, "down": true, "phase": 0.0, "target": Vector3.ZERO,
	})

	# Static rest pose: solve the same two-bone IK the rig uses so the model
	# stands correctly even when no motion script has touched it.  With the
	# numbers in P this lands on a ~136.9 deg knee and the soles at y ~= 0.
	var f: float = float(P["femur"])
	var t: float = float(P["tibia"])
	var d := float(P["foot_r"]) - float(P["hip_r"])
	var h := float(P["ankle_h"]) - float(P["hip_y"])
	var reach := sqrt(d * d + h * h)
	var base := atan2(h, d)
	var aa := acos(clampf((f * f + reach * reach - t * t) / (2.0 * f * reach), -1.0, 1.0))
	var bb := acos(clampf((f * f + t * t - reach * reach) / (2.0 * f * t), -1.0, 1.0))
	var femur_angle := base + aa
	hip.rotation.z = femur_angle
	knee.rotation.z = -(PI - bb)
	ankle.rotation.z = -(femur_angle + knee.rotation.z)


# -------------------------------------------------------------------- arms
static func _build_arms(rig: Node3D) -> void:
	for side in [1.0, -1.0]:
		_build_arm(rig, side)


static func _build_arm(rig: Node3D, side: float) -> void:
	var torso: Node3D = rig.torso
	var shoulder := Node3D.new()
	shoulder.name = "ShoulderR" if side > 0 else "ShoulderL"
	shoulder.position = Vector3(float(P["shoulder"].x) * side, float(P["shoulder"].y), float(P["shoulder"].z))
	torso.add_child(shoulder)

	var pauldron := Node3D.new()
	pauldron.name = "PauldronR" if side > 0 else "PauldronL"
	pauldron.position = shoulder.position
	pauldron.rotation_degrees = Vector3(0, 0, -14 * side)
	torso.add_child(pauldron)
	MK.add(pauldron, MK.gem(0.070, 3, 8), MAT.frame(), Vector3.ZERO)
	MK.add(pauldron, MK.prism(6, 0.135, 0.105, 0.060, PI / 6.0), MAT.armor_white(),
		Vector3(0.026 * side, 0.055, 0.0), Vector3(0, 0, 0), Vector3(1.25, 1.0, 1.15))
	MK.add(pauldron, MK.prism(6, 0.100, 0.075, 0.030, PI / 6.0), MAT.armor_blue(),
		Vector3(0.038 * side, 0.095, 0.0), Vector3(0, 0, 0), Vector3(1.25, 1.0, 1.15))
	MK.add(pauldron, MK.slab(0.055, 0.070, 0.012, 0.002), MAT.emissive(Color(0.28, 0.62, 1.0), 1.8),
		Vector3(0.075 * side, 0.045, -0.065), Vector3(0, 0, -8 * side))
	MK.bolt(pauldron, Vector3(0.04 * side, 0.06, -0.075), 0.010, 0.010, MAT.trim())
	rig.pauldrons.append(pauldron)

	var upper: float = float(P["upper"])
	# 上臂参照大腿beam_x 分层构造：粗骨架 + 外覆装甲板 + 侧甲 + 导光缝，保持明确的多段关节感
	MK.add(shoulder, MK.beam_x(upper, 0.100, 0.094, 0.078, 0.072, 0.34), MAT.frame(), Vector3.ZERO, Vector3(0, 0, -90))
	MK.add(shoulder, MK.beam_x(upper * 0.74, 0.084, 0.140, 0.070, 0.110, 0.32), MAT.armor_white(), Vector3(0.0, -0.028, 0), Vector3(0, 0, -90))
	MK.add(shoulder, MK.beam_x(upper * 0.30, 0.022, 0.160, 0.019, 0.135, 0.26), MAT.armor_blue(), Vector3(0.0, -0.052, 0), Vector3(0, 0, -90))
	MK.add(shoulder, MK.beam_x(upper * 0.22, 0.010, 0.024, 0.009, 0.020), MAT.emissive(Color(0.25, 0.55, 1.0), 2.2), Vector3(0.058, -0.16, 0.0), Vector3(0, 0, -90))
	for zs in [-1.0, 1.0]:
		MK.add(shoulder, MK.beam_x(upper * 0.52, 0.095, 0.022, 0.070, 0.016, 0.30), MAT.armor_white(),
			Vector3(0.0, -0.10, 0.072 * zs), Vector3(0, 0, -90))
		MK.add(shoulder, MK.beam_x(upper * 0.34, 0.020, 0.011, 0.015, 0.009), MAT.emissive(Color(0.22, 0.55, 1.0), 2.0),
			Vector3(0.0, -0.24, 0.084 * zs), Vector3(0, 0, -90))
	MK.add(shoulder, MK.beam_x(upper * 0.70, 0.028, 0.085, 0.022, 0.060, 0.30), MAT.armor_blue(), Vector3(0.0, -0.14, 0.0), Vector3(0, 0, -90))
	MK.add(shoulder, MK.beam_x(upper * 0.52, 0.012, 0.022, 0.009, 0.017), MAT.emissive(Color(0.20, 0.50, 1.0), 0.8), Vector3(0.0, -0.26, 0.058), Vector3(0, 0, -90))

	var elbow := Node3D.new()
	elbow.name = "Elbow"
	elbow.position = Vector3(0, -upper, 0)
	shoulder.add_child(elbow)
	MK.add(elbow, MK.prism(10, 0.068, 0.068, 0.115, 0), MAT.frame(), Vector3.ZERO, Vector3(0, 0, 90))
	MK.add(elbow, MK.prism(6, 0.085, 0.070, 0.048, 0), MAT.armor_blue(), Vector3(0.0, 0.008, -0.060), Vector3(90, 0, 0))
	MK.add(elbow, MK.prism(10, 0.038, 0.038, 0.008, 0), MAT.emissive(Color(0.25, 0.55, 1.0), 2.0), Vector3(0, 0, 0.062), Vector3(90, 0, 0))
	MK.add(elbow, MK.prism(6, 0.062, 0.048, 0.030, 0), MAT.armor_white(), Vector3(0.0, 0.008, -0.080), Vector3(90, 0, 0))
	for zs in [-1.0, 1.0]:
		MK.add(elbow, MK.prism(6, 0.045, 0.040, 0.024, 0), MAT.trim(), Vector3(0, 0, 0.055 * zs), Vector3(90, 0, 0))

	var fore: float = float(P["fore"])
	MK.add(elbow, MK.beam_x(fore, 0.082, 0.078, 0.055, 0.058, 0.32), MAT.frame(), Vector3.ZERO, Vector3(0, 0, -90))
	MK.add(elbow, MK.beam_x(fore * 0.88, 0.066, 0.118, 0.046, 0.082, 0.30), MAT.armor_white(), Vector3(0.0, -0.025, 0), Vector3(0, 0, -90))
	MK.add(elbow, MK.beam_x(fore * 0.42, 0.024, 0.092, 0.018, 0.064, 0.26), MAT.armor_blue(), Vector3(0.0, -0.070, 0), Vector3(0, 0, -90))
	for zs in [-1.0, 1.0]:
		MK.add(elbow, MK.beam_x(fore * 0.50, 0.068, 0.016, 0.050, 0.012, 0.28), MAT.armor_white(),
			Vector3(0.0, -0.08, 0.050 * zs), Vector3(0, 0, -90))
	MK.add(elbow, MK.beam_x(fore * 0.44, 0.028, 0.085, 0.020, 0.060, 0.26), MAT.armor_blue(), Vector3(0.0, -0.16, 0.0), Vector3(0, 0, -90))
	MK.add(elbow, MK.beam_x(fore * 0.54, 0.011, 0.022, 0.008, 0.016), MAT.emissive(Color(0.20, 0.50, 1.0), 0.8), Vector3(0.0, -0.20, 0.052), Vector3(0, 0, -90))
	MK.bolt(elbow, Vector3(0.04, -0.05, 0.035), 0.010, 0.010, MAT.trim())

	var wrist := Node3D.new()
	wrist.name = "Wrist"
	wrist.position = Vector3(0, -fore, 0)
	elbow.add_child(wrist)
	# fist, grip axis = local Y
	MK.add(wrist, MK.prism(8, 0.040, 0.037, 0.072, PI / 8.0), MAT.frame_light(), Vector3(0, -0.005, 0))
	MK.add(wrist, MK.slab(0.070, 0.068, 0.048, 0.008), MAT.armor_white(), Vector3(0.002 * side, -0.028, 0.0))
	MK.add(wrist, MK.slab(0.064, 0.044, 0.036, 0.006), MAT.armor_blue(), Vector3(0.0, -0.042, -0.024))
	for i in 3:
		MK.add(wrist, MK.slab(0.014, 0.032, 0.018, 0.002), MAT.frame(), Vector3(-0.017 + i * 0.017, -0.056, -0.020))
	MK.add(wrist, MK.prism(8, 0.016, 0.013, 0.010, 0), MAT.emissive(Color(0.30, 0.65, 1.0), 2.2), Vector3(0.0, -0.056, 0.032), Vector3(90, 0, 0))
	MK.add(wrist, MK.prism(8, 0.030, 0.027, 0.018, PI / 8.0), MAT.trim(), Vector3(0.0, 0.026, 0.0))

	# left forearm indicator strip: 3 blue status lamps + 1 green ready lamp
	if side < 0:
		for i in 4:
			var col := Color(0.22, 0.55, 1.0) if i < 3 else Color(0.20, 1.0, 0.45)
			# 指示灯必须贴在手臂外表面，不能埋进加粗后的装甲里
			var ind := MK.add(elbow, MK.prism(10, 0.013, 0.013, 0.010, 0),
				MAT.emissive(col, 2.6), Vector3(-0.072, -0.055 - i * 0.050, 0.0))
			ind.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rig.left_indicator_meshes.append(ind)

	rig.arms.append({
		"side": side, "shoulder": shoulder, "elbow": elbow, "wrist": wrist,
		"upper": upper, "fore": fore,
	})


# ------------------------------------------------------------------ weapon
static func _build_weapon(rig: Node3D) -> void:
	var torso: Node3D = rig.torso
	var root := Node3D.new()
	root.name = "Greatsword"
	root.position = Vector3(0.20, 0.20, -0.40)
	root.rotation = Vector3(-0.05, 0.0, 0.10)
	# The sword is authored in real metres; compensate the torso's combined
	# uniform scale (torso_scale * upper_scale) so a 1.8 m greatsword stays
	# 1.8 m in world space.
	root.scale = Vector3.ONE / (float(P["torso_scale"]) * float(P["upper_scale"]))
	torso.add_child(root)
	rig.weapon_root = root
	var spin := Node3D.new()
	spin.name = "BladeRoll"
	spin.rotation.y = 2.35
	root.add_child(spin)
	rig.weapon_spin = spin

	var grip: float = float(P["grip"])
	var blade_y0: float = float(P["blade_y0"])
	var blade_len: float = float(P["blade_len"])

	# hilt assembly
	MK.add(spin, MK.prism(8, 0.019, 0.021, 0.34, PI / 8.0), MAT.frame(), Vector3(0, -0.03, 0))
	for i in 3:
		MK.add(spin, MK.prism(10, 0.024, 0.024, 0.010, 0), MAT.trim(), Vector3(0, -0.16 + i * 0.08, 0))
	for gy in [grip, -grip]:
		MK.add(spin, MK.prism(8, 0.022, 0.022, 0.085, PI / 8.0), MAT.rubber(), Vector3(0, gy, 0))
		MK.add(spin, MK.prism(10, 0.024, 0.024, 0.006, 0), MAT.emissive(Color(0.24, 0.55, 1.0), 0.5), Vector3(0, gy - 0.040, 0))
	MK.add(spin, MK.prism(6, 0.040, 0.020, 0.065, PI / 6.0), MAT.armor_blue(), Vector3(0, -0.195, 0))
	MK.add(spin, MK.gem(0.024, 3, 6), MAT.emissive(Color(0.30, 0.65, 1.0), 0.25), Vector3(0, -0.225, 0))

	# guard housing
	MK.add(spin, MK.slab(0.085, 0.060, 0.085, 0.008), MAT.trim(), Vector3(0, 0.185, 0))
	MK.add(spin, MK.beam_x(0.46, 0.040, 0.045, 0.030, 0.036), MAT.armor_white(), Vector3(-0.23, 0.195, 0))
	for side in [-1.0, 1.0]:
		MK.add(spin, MK.prism(6, 0.034, 0.024, 0.065, 0), MAT.armor_blue(), Vector3(0.225 * side, 0.20, 0))
		# Kylo-style short energy prongs, raked forward from the emitter
		MK.add(spin, MK.flat_blade(0.185, 0.038, 0.012, 0.55, 5), MAT.crossguard(),
			Vector3(0.245 * side, 0.205, 0), Vector3(0, 0, -90 * side))
		MK.add(spin, MK.slab(0.030, 0.030, 0.048, 0.006), MAT.trim(),
			Vector3(0.058 * side, 0.222, 0), Vector3(0, 0, -35 * side))
	# central emitter
	MK.add(spin, MK.prism(10, 0.036, 0.028, 0.035, 0), MAT.emissive(Color(0.30, 0.65, 1.0), 0.6), Vector3(0, 0.225, 0))

	# flat plasma blade: white core + blue shells
	MK.add(spin, MK.flat_blade(blade_len, 0.205, 0.038, 0.78, 24), MAT.blade_core(), Vector3(0, blade_y0, 0))
	MK.add(spin, MK.flat_blade(blade_len, 0.255, 0.050, 0.78, 24), MAT.blade_glow(),
		Vector3(0, blade_y0, 0), Vector3.ZERO, Vector3(1.06, 1.0, 1.10), "BladeGlow1")
	var aura_mat: ShaderMaterial = (MAT.blade_glow() as ShaderMaterial).duplicate()
	aura_mat.set_shader_parameter("strength", 0.32)
	aura_mat.set_shader_parameter("color", Color(0.12, 0.38, 1.0))
	MK.add(spin, MK.flat_blade(blade_len * 1.01, 0.360, 0.075, 0.78, 22), aura_mat,
		Vector3(0, blade_y0, 0), Vector3.ZERO, Vector3(1.0, 1.0, 1.0), "BladeAura")
	# central fuller / hot line
	MK.add(spin, MK.flat_blade(blade_len * 0.94, 0.035, 0.036, 0.20, 18),
		MAT.emissive(Color(0.82, 0.95, 1.0), 2.2), Vector3(0, blade_y0 + 0.006, 0))

	var base := Marker3D.new()
	base.position = Vector3(0, blade_y0 + blade_len * 0.80, 0)
	spin.add_child(base)
	rig.blade_base = base
	var tip := Marker3D.new()
	tip.position = Vector3(0, blade_y0 + blade_len * 0.96, 0)
	spin.add_child(tip)
	rig.blade_tip = tip

	var wl := OmniLight3D.new()
	wl.light_color = Color(0.30, 0.60, 1.0)
	wl.light_energy = 0.30
	wl.omni_range = 1.8
	wl.shadow_enabled = false
	wl.position = Vector3(0, 0.75, 0)
	spin.add_child(wl)
	rig.weapon_light = wl

	# torso chest light
	var cl := OmniLight3D.new()
	cl.light_color = Color(0.30, 0.58, 1.0)
	cl.light_energy = 0.35
	cl.omni_range = 1.4
	cl.shadow_enabled = false
	cl.position = Vector3(0, 0.42, -0.20)
	torso.add_child(cl)
	rig.chest_light = cl


# ------------------------------------------------------------------ helpers

## Two-bone arm IK onto the sword grips, identical maths to the rig solver.
static func _pose_arms_to_grip(rig: Node3D) -> void:
	if rig.weapon_root == null or rig.arms.size() < 2:
		return
	var hilt_y: Vector3 = rig.weapon_root.basis.y.normalized()
	var hilt_x: Vector3 = rig.weapon_spin.basis.x.normalized()
	var grip: float = float(P["grip"])
	var targets := [
		rig.weapon_root.transform * Vector3(0, grip, 0),
		rig.weapon_root.transform * Vector3(0, -grip, 0),
	]
	for k in 2:
		_solve_arm(rig.arms[k], targets[k], hilt_y, hilt_x)


static func _solve_arm(arm: Dictionary, target: Vector3, hilt_y: Vector3, hilt_x: Vector3) -> void:
	var shoulder: Node3D = arm["shoulder"]
	var elbow: Node3D = arm["elbow"]
	var wrist: Node3D = arm["wrist"]
	var side: float = arm["side"]
	var upper: float = arm["upper"]
	var fore: float = arm["fore"]
	var S := shoulder.position
	var delta := target - S
	var dist := clampf(delta.length(), 0.24, upper + fore - 0.012)
	var dir := delta.normalized()
	var pole := Vector3(side * 0.55, -0.55, 0.45)
	var perp := pole - dir * pole.dot(dir)
	if perp.length_squared() < 0.001:
		perp = Vector3(side, 0, 0)
	perp = perp.normalized()
	var a := (upper * upper - fore * fore + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(upper * upper - a * a, 0.0))
	var elbow_pos := S + dir * a + perp * h
	var Teff := S + dir * dist
	var up_dir := (elbow_pos - S).normalized()
	var fore_dir := (Teff - elbow_pos).normalized()
	var x_axis := up_dir.cross(fore_dir)
	if x_axis.length_squared() < 0.0001:
		x_axis = perp
	x_axis = x_axis.normalized()
	var y_axis := -up_dir
	var z_axis := x_axis.cross(y_axis).normalized()
	x_axis = y_axis.cross(z_axis).normalized()
	shoulder.basis = Basis(x_axis, y_axis, z_axis)
	var ang := acos(clampf(up_dir.dot(fore_dir), -1.0, 1.0))
	elbow.rotation = Vector3(ang, 0.0, 0.0)
	var parent_basis := shoulder.basis * elbow.transform.basis
	var hy := hilt_y.normalized()
	var hx := hilt_x - hy * hilt_x.dot(hy)
	if hx.length_squared() < 0.0001:
		hx = x_axis
	hx = hx.normalized()
	var hz := hx.cross(hy).normalized()
	hx = hy.cross(hz).normalized()
	wrist.basis = parent_basis.inverse() * Basis(hx, hy, hz)
const TAU := PI * 2.0