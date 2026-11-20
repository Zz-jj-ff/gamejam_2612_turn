extends Node3D
## Temporary API probe: one spring-bone hair chain.

var sk: Skeleton3D
var sim: SpringBoneSimulator3D
var chain: Array[int] = []
var tip_len := 0.08
var frames := 0

func _basis_from_y(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func _ready() -> void:
	Engine.max_fps = 60
	sk = Skeleton3D.new()
	sk.name = "Skeleton"
	sk.top_level = true
	add_child(sk)

	var pos := Vector3(0, 2.0, 0)
	var prev_global := Basis.IDENTITY
	for i in 8:
		var idx := sk.add_bone("chain_%02d" % i)
		chain.append(idx)
		if i == 0:
			sk.set_bone_parent(idx, -1)
		else:
			sk.set_bone_parent(idx, chain[i - 1])
		var dir := Vector3(0, -1, 0.25).normalized()
		var global_basis := _basis_from_y(dir)
		var local_basis := global_basis if i == 0 else prev_global.inverse() * global_basis
		var rest := Transform3D(local_basis, pos if i == 0 else Vector3(0, 0.09, 0))
		sk.set_bone_rest(idx, rest)
		prev_global = global_basis
		pos += dir * 0.09

	sim = SpringBoneSimulator3D.new()
	sim.name = "SpringBone"
	sk.add_child(sim)
	sim.set_setting_count(1)
	sim.set_root_bone_name(0, "chain_00")
	sim.set_end_bone_name(0, "chain_07")
	sim.set_extend_end_bone(0, true)
	sim.set_end_bone_length(0, tip_len)
	sim.set_gravity(0, 0.5)
	sim.set_gravity_direction(0, Vector3(0, -1, 0))
	sim.set_stiffness(0, 0.5)
	sim.set_drag(0, 0.2)
	sim.set_radius(0, 0.015)
	sim.set_rotation_axis(0, SkeletonModifier3D.ROTATION_AXIS_ALL)
	sim.set_center_from(0, SpringBoneSimulator3D.CENTER_FROM_WORLD_ORIGIN)
	sim.set_individual_config(0, true)
	for j in 8:
		sim.set_joint_stiffness(0, j, 0.5)
		sim.set_joint_drag(0, j, 0.2)
		sim.set_joint_gravity(0, j, 5.0)
		sim.set_joint_gravity_direction(0, j, Vector3(0, -1, 0))
		sim.set_joint_radius(0, j, 0.015)
	sim.set_external_force(Vector3(10, 0, 0))
	var col := SpringBoneCollisionSphere3D.new()
	col.name = "HeadCol"
	sim.add_child(col)
	col.position = Vector3(0, 2.1, 0)
	col.radius = 0.25
	sim.set_collision_count(0, 1)
	sim.set_collision_path(0, 0, NodePath("../SpringBone/HeadCol"))

	var cam := Camera3D.new()
	cam.position = Vector3(3, 2, 3)
	add_child(cam)
	cam.look_at_from_position(cam.position, Vector3(0, 1.6, 0), Vector3.UP)

	sim.modification_processed.connect(func(): frames += 1)
	sim.reset()
	sk.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_IDLE
	sk.global_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	sk.reset_bone_poses()
	sk.force_update_all_bone_transforms()
	print("bones=", sk.get_bone_count(), " settings=", sim.get_setting_count(), " joints=", sim.get_joint_count(0), " active=", sim.active, " skel=", sim.get_skeleton(), " pi=", sk.is_physics_processing_internal(), " i=", sk.is_processing_internal(), " jb=", sim.get_joint_bone_name(0, 0), ",", sim.get_joint_bone_name(0, 7), " ext=", sim.get_external_force(), " mods=", sim.get_influence())
	for i in 8:
		var gp := sk.get_bone_global_pose(chain[i])
		print("b", i, " pose_o=", gp.origin, " By=", gp.basis.y)
	_report("t=0.00")
	await get_tree().process_frame
	for f in range(240):
		if f == 60:
			sk.global_position = Vector3(0, 0, 0)
		if f == 120:
			sk.global_position = Vector3(1.5, 0, 0)
		if f == 180:
			sk.global_position = Vector3(1.5, 0, 1.5)
		await get_tree().process_frame
		if f % 20 == 0:
			_report("f=%d pf=%d qf=%d dt=%.4f mods=%d r0=%s" % [f, Engine.get_process_frames(), Engine.get_physics_frames(), get_process_delta_time(), frames, sk.get_bone_pose_rotation(chain[0])])
	_report("final")
	get_tree().quit()

func _report(tag: String) -> void:
	var s := ""
	for i in 8:
		var p := sk.get_bone_global_pose(chain[i]).origin
		s += " %.3f" % p.y
	var last := sk.get_bone_global_pose(chain[7])
	var tip := last.origin + last.basis.y * tip_len
	var rot := sk.get_bone_pose_rotation(chain[7])
	print(tag, " y:", s, " | tip=", tip, " rot7=", rot)