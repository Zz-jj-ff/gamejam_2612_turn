extends SceneTree
## Offline trajectory bake. Run:
##   godot --headless --path . --script res://scripts/bake_traj.gd
##
## The runtime uses this table (a few hundred KB) instead of re-solving the
## per-sample IK. If geometry parameters change, the signature check fails and
## the runtime solver rebuilds instead of using a stale table.

func _init() -> void:
	var P := {
		"body_scale": 1.00, "hull_radius": 0.225, "wheel_radius": 0.325,
		"shield_radius": 0.310, "blade_length": 1.030, "blade_width": 0.176,
		"_threat": 0, "_no_bake": 1.0,
	}
	var KIN = load("res://scripts/ch/arc_kin.gd")
	var ANIM = load("res://scripts/ch/arc_anim.gd")
	var kin = KIN.new(P)
	var anim = ANIM.new(kin, P)
	var t0 := Time.get_ticks_msec()
	anim.build()
	anim.baked_defend["shield"] = {"samples": anim.trajs["defend"],
		"dur": anim.clip_dur["defend"]}
	for arr in [anim.attack_keys, anim.attack_up_keys, anim.draw_keys, anim.sheathe_keys]:
		for k in arr:
			var lb := str(k.get("label", ""))
			if lb != "" and lb != "idle" and lb != "rest":
				anim.baked_keys[lb] = k["pose"]
	anim.P["_threat"] = 1
	anim._build_defend()
	anim.baked_defend["sword"] = {"samples": anim.trajs["defend"],
		"dur": anim.clip_dur["defend"]}
	anim.write_bake()
	var ms := Time.get_ticks_msec() - t0
	print("BAKE done in %d ms  build_ms=%d  attack_ms=%d  attack_up_ms=%d  defend_ms=%d" % [
		ms, anim.build_ms, anim.attack_ms, anim.attack_up_ms, anim.defend_ms])
	print("  clips: ", anim.trajs.keys())
	for k in anim.trajs:
		print("    %-9s samples=%d dur=%.2f" % [k, anim.trajs[k].size(), anim.clip_dur.get(k, 0.0)])
	quit()
