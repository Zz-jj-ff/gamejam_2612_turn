extends Node3D
## ARC // SENTINEL v2 — acceptance QA.
##
## Headless: godot --headless --path . res://scenes/qa.tscn
## Checks: every clip frame for self-collision, all direct animation blends,
## exact attack pose constraints, both mandated blocks, solver timings.

const D2R := PI / 180.0
const CH_SCENE := "res://scenes/character.tscn"

var ch: Node3D
var kin
var anim
var fails: Array = []
var rows: Array = []


func _ready() -> void:
	ch = load(CH_SCENE).instantiate()
	add_child(ch)
	await get_tree().process_frame
	kin = ch.kin
	anim = ch.anim
	print("=== ARC SENTINEL v2 QA ===")
	print("anims: ", ch.anim_names())
	print("build_ms: ", anim.build_ms, "  attack: ", anim.attack_ms,
		"  attack_up: ", anim.attack_up_ms, "  defend: ", anim.defend_ms)
	_test_clip_clearance()
	_test_transitions()
	_test_attack_poses()
	_test_blocks()
	_test_timing()
	_write_report()
	print("\n=== RESULT: %s (%d failures) ===" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	for f in fails:
		print("  FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


func _fail(msg: String) -> void:
	fails.append(msg)


func _test_clip_clearance() -> void:
	print("\n-- clip clearance --")
	for name in ch.anim_names():
		var dur: float = anim.duration(name)
		var n := 96
		var worst := 9.0
		var wp := ["", ""]
		var wt := 0.0
		var floor_worst := 9.0
		for i in n + 1:
			var t := dur * float(i) / float(n)
			var pose: Dictionary = anim.sample(name, t)
			var a: Dictionary = kin.audit(pose)
			if float(a["min"]) < worst:
				worst = float(a["min"])
				wp = a["pair"]
				wt = t
			floor_worst = minf(floor_worst, float(a["floor"]))
		var ok := worst > 0.0 and floor_worst > -0.002
		print("  %-9s dur %.2f  min %+.4f m at %.2fs %s  floor %+.4f  %s" % [
			name, dur, worst, wt, str(wp), floor_worst, "OK" if ok else "FAIL"])
		rows.append({"clip": name, "dur": dur, "min": worst, "pair": wp,
			"t": wt, "floor": floor_worst})
		if not ok:
			_fail("%s collision %.4f m %s at %.2fs (floor %.4f)" % [name, worst, str(wp), wt, floor_worst])


func _test_transitions() -> void:
	print("\n-- animation blends (state-machine reachable) --")
	var loops := ["idle", "walk"]
	var drawn := ["idle", "walk", "attack", "attack_up", "defend"]
	var worst := 9.0
	var wdesc := ""
	for a in loops:
		for b in drawn:
			if a == b:
				continue
			var ta: float = anim.duration(a) * 0.55
			var pa: Dictionary = anim.sample(a, ta)
			var pb: Dictionary = anim.sample(b, 0.0)
			var mn := 9.0
			var mp := ["", ""]
			for k in 13:
				var u := float(k) / 12.0
				var p: Dictionary = ArcKin2.blend_pose(pa, pb, u)
				var au: Dictionary = kin.audit(p)
				if float(au["min"]) < mn:
					mn = float(au["min"])
					mp = au["pair"]
			if mn < worst:
				worst = mn
				wdesc = "%s@%.2f -> %s : %.4f %s" % [a, ta, b, mn, str(mp)]
			rows.append({"blend": "%s->%s" % [a, b], "min": mn, "pair": mp})
	# one-shots are never cancelled: their end pose is the idle base
	for a in ["attack", "attack_up", "defend"]:
		var pa2: Dictionary = anim.sample(a, anim.duration(a))
		for b in drawn:
			var pb2: Dictionary = anim.sample(b, 0.0)
			var mn2 := 9.0
			var mp2 := ["", ""]
			for k in 13:
				var p2: Dictionary = ArcKin2.blend_pose(pa2, pb2, float(k) / 12.0)
				var au2: Dictionary = kin.audit(p2)
				if float(au2["min"]) < mn2:
					mn2 = float(au2["min"])
					mp2 = au2["pair"]
			if mn2 < worst:
				worst = mn2
				wdesc = "%s(end) -> %s : %.4f %s" % [a, b, mn2, str(mp2)]
			rows.append({"blend": "%s(end)->%s" % [a, b], "min": mn2, "pair": mp2})
	print("  worst reachable blend: %s" % wdesc)
	if worst <= 0.0:
		_fail("animation blend collision: %s" % wdesc)
	# rest <-> idle must go through draw / sheathe
	for pair in [["rest", "idle"], ["idle", "rest"]]:
		var pa3: Dictionary = anim.sample(pair[0], 0.0)
		var pb3: Dictionary = anim.sample(pair[1], 0.0)
		var mn3 := 9.0
		for k in 13:
			var p3: Dictionary = ArcKin2.blend_pose(pa3, pb3, float(k) / 12.0)
			mn3 = minf(mn3, float(kin.audit(p3)["min"]))
		print("  direct %s->%s min %+.4f (routed via draw/sheathe)" % [pair[0], pair[1], mn3])


func _blade_info(pose: Dictionary) -> Dictionary:
	var fk: Dictionary = kin.arm_fk(-1, pose)
	var b: Basis = fk["tool_basis"]
	var d := b * Vector3(0, -1, 0)
	var sx := b * Vector3(1, 0, 0)
	var sz := b * Vector3(0, 0, 1)
	var minx := 99.0
	for i in 8:
		var f := float(i) / 7.0
		var p: Vector3 = (fk["tool"] as Vector3) + d * (kin.blade_len * f)
		var hw: float = kin.blade_half_w * (1.0 - 0.65 * f)
		var ht: float = kin.blade_half_t * (1.0 - 0.65 * f)
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				var q: Vector3 = p + sx * (cx * hw) + sz * (cz * ht)
				minx = minf(minx, q.x)
	return {"s": fk["s"], "e": fk["e"], "w": fk["w"], "tool": fk["tool"], "dir": d,
		"basis": b, "minx": minx, "tip": (fk["tool"] as Vector3) + d * kin.blade_len}


func _test_attack_poses() -> void:
	print("\n-- exact attack poses --")
	# attack windup: above the LEFT shoulder, blade left-back-up
	var pw: Dictionary = anim.action_key("attack", "windup")
	var bw := _blade_info(pw)
	var dw: Vector3 = bw["dir"]
	print("  attack windup: tool (%.2f, %.2f, %.2f)  dir %s  body/torso yaw %.1f/%.1f" % [
		float(bw["tool"].x), float(bw["tool"].y), float(bw["tool"].z), str(dw),
		rad_to_deg(float(pw.get("body_yaw", 0.0))), rad_to_deg(float(pw.get("torso_yaw", 0.0)))])
	if float(bw["tool"].y) < 1.35 or float(bw["tool"].x) < 0.30:
		_fail("attack windup not above the left shoulder")
	if dw.x < 0.35 or dw.y < 0.25 or dw.z > -0.45:
		_fail("attack windup blade not left-back-up (%s)" % str(dw))
	if float(pw.get("torso_yaw", 0.0)) < 20.0 * D2R:
		_fail("attack windup torso twist too small")
	# attack via: straight arm, blade left-front-up
	var pv: Dictionary = anim.action_key("attack", "via")
	var bv := _blade_info(pv)
	var vdir: Vector3 = bv["dir"]
	var varm: Vector3 = ((bv["w"] as Vector3) - (bv["s"] as Vector3)).normalized()
	var vbend := rad_to_deg(varm.angle_to(vdir))
	var velb := rad_to_deg(((bv["e"] as Vector3) - (bv["s"] as Vector3)).normalized().angle_to(((bv["w"] as Vector3) - (bv["e"] as Vector3)).normalized()))
	print("  attack via: dir %s  arm/blade %.2f deg  elbow %.2f deg  tool x %.2f y %.2f z %.2f" % [
		str(vdir), vbend, velb, float(bv["tool"].x), float(bv["tool"].y), float(bv["tool"].z)])
	if vdir.x < 0.30 or vdir.y < 0.30 or vdir.z < 0.30:
		_fail("attack via blade not left-front-up (%s)" % str(vdir))
	if vbend > 6.0:
		_fail("attack via arm not straight (%.1f deg)" % vbend)
	if velb > 10.0:
		_fail("attack via elbow not straight (%.1f deg)" % velb)
	# attack front: blade straight forward, through the space in front
	var pf: Dictionary = anim.action_key("attack", "front")
	var bf := _blade_info(pf)
	var fdir: Vector3 = bf["dir"]
	var farm: Vector3 = ((bf["w"] as Vector3) - (bf["s"] as Vector3)).normalized()
	var fbend := rad_to_deg(farm.angle_to(fdir))
	print("  attack front: dir %s  arm/blade %.2f deg  tip z %.2f  body/torso %.1f/%.1f" % [
		str(fdir), fbend, float(bf["tip"].z),
		rad_to_deg(float(pf.get("body_yaw", 0.0))), rad_to_deg(float(pf.get("torso_yaw", 0.0)))])
	if fdir.z < 0.85 or absf(fdir.x) > 0.15 or absf(fdir.y) > 0.25:
		_fail("attack front blade not straight forward (%s)" % str(fdir))
	if fbend > 6.0:
		_fail("attack front arm not straight (%.1f deg)" % fbend)
	if float(bf["tip"].z) < 1.70:
		_fail("attack front does not reach in front (tip z %.2f)" % float(bf["tip"].z))
	# attack end: straight arm/blade right-down, no front/back component
	var pe: Dictionary = anim.action_key("attack", "end")
	var be := _blade_info(pe)
	var down := asin(clampf(-(be["dir"] as Vector3).y, -1.0, 1.0)) / D2R
	var arm_dir: Vector3 = ((be["w"] as Vector3) - (be["s"] as Vector3)).normalized()
	var arm_bend := rad_to_deg(arm_dir.angle_to(be["dir"] as Vector3))
	var eelb := rad_to_deg(((be["e"] as Vector3) - (be["s"] as Vector3)).normalized().angle_to(((be["w"] as Vector3) - (be["e"] as Vector3)).normalized()))
	print("  attack end: tool x %.2f z %.2f  dir %s  down %.2f  tip y %.2f z %.2f  arm/blade %.2f elbow %.2f  body/torso %.1f/%.1f" % [
		float(be["tool"].x), float(be["tool"].z), str(be["dir"]), down,
		float(be["tip"].y), float(be["tip"].z), arm_bend, eelb,
		rad_to_deg(float(pe.get("body_yaw", 0.0))), rad_to_deg(float(pe.get("torso_yaw", 0.0)))])
	if (be["dir"] as Vector3).z < 0.55:
		_fail("attack end blade leaves the front (dz %.2f)" % float((be["dir"] as Vector3).z))
	if (be["dir"] as Vector3).x >= 0.0 or (be["dir"] as Vector3).y >= 0.0:
		_fail("attack end not right-down")
	if absf(down - 25.0) > 6.0:
		_fail("attack end down angle %.1f not 25±6" % down)
	if arm_bend > 6.0:
		_fail("attack end arm not straight (%.1f deg to blade)" % arm_bend)
	if eelb > 10.0:
		_fail("attack end elbow not straight (%.1f deg)" % eelb)
	if float(be["tool"].x) > -0.80:
		_fail("attack end not on the body's right")
	if float(be["tip"].y) < 0.05:
		_fail("attack end tip through the floor")
	if float(be["tip"].z) < 1.0:
		_fail("attack end not in front (tip z %.2f)" % float(be["tip"].z))
	if float(pe.get("torso_yaw", 0.0)) > -5.0 * D2R:
		_fail("attack end torso not turned right")
	# attack_up windup
	var puw: Dictionary = anim.action_key("attack_up", "windup")
	var buw := _blade_info(puw)
	var duw: Vector3 = buw["dir"]
	print("  attack_up windup: dir %s  min x %.3f  tool y %.2f x %.2f" % [
		str(duw), float(buw["minx"]), float(buw["tool"].y), float(buw["tool"].x)])
	if absf(duw.y) > 0.08 or duw.z > -0.97:
		_fail("attack_up windup blade not horizontal backward")
	if float(buw["minx"]) <= 0.26:
		_fail("attack_up windup blade not entirely left of the hull (min x %.3f)" % float(buw["minx"]))
	if float(buw["tool"].y) > 0.90 or float(buw["tool"].x) < 0.30:
		_fail("attack_up windup not low-left")
	# attack_up end
	var pue: Dictionary = anim.action_key("attack_up", "end")
	var bue := _blade_info(pue)
	var up_arm_dir: Vector3 = ((bue["w"] as Vector3) - (bue["s"] as Vector3)).normalized()
	var arm_up := asin(clampf(up_arm_dir.y, -1.0, 1.0)) / D2R
	var up_arm_bend := rad_to_deg(up_arm_dir.angle_to(bue["dir"] as Vector3))
	var up := asin(clampf((bue["dir"] as Vector3).y, -1.0, 1.0)) / D2R
	print("  attack_up end: arm up %.2f deg, blade up %.2f deg, arm/blade %.2f deg, dir %s" % [
		arm_up, up, up_arm_bend, str(bue["dir"])])
	if absf(up - 45.0) > 5.0 or (bue["dir"] as Vector3).x >= 0.0:
		_fail("attack_up end blade not 45 deg up-right")
	if up_arm_bend > 6.0:
		_fail("attack_up end arm not straight (%.1f deg to blade)" % up_arm_bend)
	if arm_up < 35.0:
		_fail("attack_up end arm not raised with the blade (%.1f deg up)" % arm_up)


func _test_blocks() -> void:
	print("\n-- mandated blocks --")
	ch.set_block_threat(0)
	var a: Dictionary = ch.block_plan_stats()
	ch.set_block_threat(1)
	var b: Dictionary = ch.block_plan_stats()
	for r in [a, b]:
		print("  threat %d %s: effector %s blocked %s miss %.4f clear %.4f plan %.1f ms" % [
			int(r["threat"]), str(r["threat_name"]), str(r["effector"]),
			str(r["blocked"]), float(r["miss"]), float(r["min_clear"]), float(r["plan_ms"])])
		if not bool(r["blocked"]):
			_fail("block %s not intercepted" % str(r["threat_name"]))
		if str(r["effector"]) != ("shield" if int(r["threat"]) == 0 else "sword"):
			_fail("block %s wrong effector %s" % [str(r["threat_name"]), str(r["effector"])])
		if float(r["min_clear"]) <= 0.0:
			_fail("block %s collision %.4f" % [str(r["threat_name"]), float(r["min_clear"])])
	if str(a["effector"]) == "guard" or str(b["effector"]) == "guard":
		_fail("guard fallback used")


func _test_timing() -> void:
	print("\n-- solver timing --")
	var atk: Dictionary = ch.attack_plan_stats("attack")
	var up: Dictionary = ch.attack_plan_stats("attack_up")
	ch.set_block_threat(0)
	var bl: Dictionary = ch.block_plan_stats()
	print("  attack plan %.1f ms (min clear %.4f, qdot %.1f)" % [
		float(atk["plan_ms"]), float(atk["min_clear"]), float(atk["qdot_max"])])
	print("  attack_up plan %.1f ms (min clear %.4f, qdot %.1f)" % [
		float(up["plan_ms"]), float(up["min_clear"]), float(up["qdot_max"])])
	print("  block plan %.1f ms" % float(bl["plan_ms"]))
	if float(atk["plan_ms"]) > 50.0:
		_fail("attack plan %.1f ms > 50" % float(atk["plan_ms"]))
	if float(up["plan_ms"]) > 50.0:
		_fail("attack_up plan %.1f ms > 50" % float(up["plan_ms"]))
	if float(bl["plan_ms"]) > 50.0:
		_fail("block plan %.1f ms > 50" % float(bl["plan_ms"]))
	if float(atk["min_clear"]) <= 0.0:
		_fail("attack table collision %.4f %s" % [float(atk["min_clear"]), str(atk["min_pair"])])
	if float(atk["qdot_max"]) > 60.0:
		_fail("attack qdot %.1f > 60 rad/s" % float(atk["qdot_max"]))
	if float(up["min_clear"]) <= 0.0:
		_fail("attack_up table collision %.4f %s" % [float(up["min_clear"]), str(up["min_pair"])])
	if float(up["qdot_max"]) > 25.5:
		_fail("attack_up qdot %.1f > 25.5 rad/s" % float(up["qdot_max"]))


func _write_report() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))
	var f := FileAccess.open("res://renders/v2/qa_report.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"pass": fails.is_empty(), "fails": fails, "rows": rows,
			"timing": {"attack_ms": anim.attack_ms, "attack_up_ms": anim.attack_up_ms,
				"defend_ms": anim.defend_ms, "build_ms": anim.build_ms},
		}, "  "))
		f.close()