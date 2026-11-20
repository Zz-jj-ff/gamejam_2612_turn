extends SceneTree
func _init() -> void:
	var scene: PackedScene = load("res://scenes/head.tscn")
	var head = scene.instantiate()
	root.add_child(head)
	await process_frame
	var stack := [head]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and n.mesh is ArrayMesh and n.mesh.get_surface_count() > 0:
			var nm := String(n.name)
			if nm.begins_with("Hair"):
				var arr: Array = n.mesh.surface_get_arrays(0)
				var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var mn := Vector3(1e9, 1e9, 1e9)
				var mx := -mn
				for p in v:
					mn = Vector3(minf(mn.x, p.x), minf(mn.y, p.y), minf(mn.z, p.z))
					mx = Vector3(maxf(mx.x, p.x), maxf(mx.y, p.y), maxf(mx.z, p.z))
				print("%-16s x[%.3f %.3f] y[%.3f %.3f] z[%.3f %.3f]" % [nm, mn.x, mx.x, mn.y, mx.y, mn.z, mx.z])
		for c in n.get_children():
			stack.append(c)
	quit(0)
