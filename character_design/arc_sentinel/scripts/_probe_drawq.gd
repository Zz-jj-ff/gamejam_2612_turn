extends SceneTree
var ch
func _initialize() -> void:
	ch = load("res://scenes/character.tscn").instantiate()
	root.add_child(ch)
	await process_frame
	for name in ["draw", "sheathe"]:
		var tr: Array = ch.anim.trajs[name]
		var best := 0.0; var bk := ""; var bi := 0; var bt := 0.0
		for i in range(1, tr.size()):
			var a: Dictionary = tr[i - 1]["pose"]
			var b: Dictionary = tr[i]["pose"]
			var dt: float = maxf(float(tr[i]["t"]) - float(tr[i - 1]["t"]), 1e-4)
			for k in a:
				if k.begins_with("_") or not b.has(k): continue
				var ang := 0.0
				if a[k] is Quaternion and b[k] is Quaternion:
					ang = (a[k] as Quaternion).angle_to(b[k])
				elif a[k] is float:
					ang = absf(wrapf(float(b[k]) - float(a[k]), -PI, PI))
				var q := ang / dt
				if q > best: best = q; bk = k; bi = i; bt = float(tr[i]["t"])
		print("%s peak %.1f rad/s key %s idx %d t %.3f n %d dur %.2f" % [name, best, bk, bi, bt, tr.size(), float(tr[-1]["t"])])
	quit()
