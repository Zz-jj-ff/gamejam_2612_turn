extends SceneTree
## Headless build probe: builds the bust without rendering.

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var scene: PackedScene = load("res://scenes/head.tscn")
	if scene == null:
		print("no scene")
		quit(1)
		return
	var head = scene.instantiate()
	root.add_child(head)
	await process_frame
	var meshes := 0
	var verts := 0
	var nan_count := 0
	var big := 0
	var stack := [head]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and n.mesh is ArrayMesh:
			if n.mesh.get_surface_count() == 0:
				print("empty: ", n.name)
				continue
			meshes += 1
			var arr: Array = n.mesh.surface_get_arrays(0)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			if v.size() > 60000:
				print("large mesh: ", n.name, " ", v.size())
			verts += v.size()
			for p in v:
				if is_nan(p.x) or is_nan(p.y) or is_nan(p.z):
					nan_count += 1
				elif absf(p.x) + absf(p.y) + absf(p.z) > 10.0:
					big += 1
		for c in n.get_children():
			stack.append(c)
	print("meshes=", meshes, " verts=", verts, " nan=", nan_count, " big=", big,
		" ms=", Time.get_ticks_msec() - t0)
	quit(0)