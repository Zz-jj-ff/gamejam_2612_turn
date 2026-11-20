extends SceneTree
func _init():
	var scene: PackedScene = load("res://scenes/head.tscn")
	var head = scene.instantiate()
	root.add_child(head)
	for i in 20:
		await process_frame
	var skel: Skeleton3D = head.get_node_or_null("HeadPivot/HairSkeleton")
	if skel == null:
		print("no skeleton")
		quit(1)
		return
	var sim = skel.get_node_or_null("HairSprings")
	print("bones ", skel.get_bone_count(), " settings ", sim.setting_count if sim else -1)
	if sim:
		for gi in [0, 5, 20, 32]:
			if gi < sim.setting_count:
				print("g", gi, " joints ", sim.get_joint_count(gi),
					" root ", sim.get_root_bone_name(gi), " end ", sim.get_end_bone_name(gi))
	for gi in [0, 5, 20, 32]:
		var g = head._hair_guides[gi] if head._hair_guides.size() > gi else null
		if g == null: continue
		var b = int(g["first"])
		print("guide ", gi, " first ", b, " pose ", skel.get_bone_global_pose(b), " rest ", skel.get_bone_global_rest(b))
		var e = int(g["end"])
		print("   end ", e, " pose ", skel.get_bone_global_pose(e), " rest ", skel.get_bone_global_rest(e))
	quit(0)
