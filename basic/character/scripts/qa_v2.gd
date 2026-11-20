extends Node3D
## VESPER v2 acceptance harness.  Headless:
##   godot --headless --path . res://scenes/qa_v2.tscn
## Checks proportions, knee angle, all eight attacks, side/back direction,
## lateral dashes, jump crouch, hair motion and ground clearance.

const Rig = preload("res://scripts/mech/mech_rig.gd")

var rig
var fails: Array[String] = []
var checks := 0
var report := {}


func _ready() -> void:
	rig = Rig.new()
	rig.name = "VESPER"
	rig.auto_step = false
	rig.set_process(false)
	add_child(rig)
	await get_tree().process_frame
	await _run()
	_finish()


func _ok(cond: bool, label: String, detail := "") -> void:
	checks += 1
	if cond:
		print("PASS  ", label, "  ", detail)
	else:
		print("FAIL  ", label, "  ", detail)
		fails.append(label + " " + detail)


func _run() -> void:
	rig.reset_demo(Vector3.ZERO, 0.0)
	for i in 8:
		rig.advance(1.0 / 60.0)
	await get_tree().process_frame

	# ---------------- proportions
	var bb: AABB = rig.body_aabb()
	var height := bb.end.y
	var low := bb.position.y
	var radius := 0.0
	for cx in [bb.position.x, bb.end.x]:
		for cz in [bb.position.z, bb.end.z]:
			radius = maxf(radius, Vector2(cx, cz).length())
	report["height"] = height
	report["floor"] = low
	report["radius"] = radius
	_ok(height >= 1.90 and height <= 2.12, "height ~2.0 m", "%.3f m" % height)
	_ok(low >= -0.02, "feet above floor", "min y %.3f m" % low)
	_ok(radius <= 0.62, "compact body radius", "%.3f m" % radius)

	for i in 4:
		var ka: float = rig.get_knee_angle(i)
		_ok(ka >= 128.0 and ka <= 142.0, "knee %d ~135 deg" % i, "%.1f deg" % ka)
	report["knee"] = [rig.get_knee_angle(0), rig.get_knee_angle(1), rig.get_knee_angle(2), rig.get_knee_angle(3)]

	# ---------------- attacks
	var front := ["FRONT_R", "FRONT_L", "RISE_R", "RISE_L"]
	var fronts := {}
	for nm in front:
		var res := await _run_front_attack(front.find(nm) + 1)
		fronts[nm] = res
		_ok(float(res["min_z"]) < -0.75, "%s reaches forward" % nm, "tip z %.2f" % res["min_z"])
		_ok(float(res["reach"]) >= 1.2, "%s blade reach" % nm, "%.2f m" % res["reach"])
		_ok(float(res["floor"]) >= -0.03, "%s ground clearance" % nm, "%.3f" % res["floor"])
	report["front"] = fronts

	# side thrust: no body turn, tip out to +X
	rig.reset_demo(Vector3.ZERO, 0.0)
	var max_x := -99.0
	var max_yaw := 0.0
	var side_floor := 99.0
	rig.request_side_attack(1.0)
	for i in 150:
		rig.advance(1.0 / 60.0)
		max_x = maxf(max_x, rig.blade_tip_world().x)
		max_yaw = maxf(max_yaw, absf(rig.torso.rotation.y))
		side_floor = minf(side_floor, rig.body_aabb().position.y)
		if not rig.is_attacking and i > 10:
			break
	_ok(max_x >= 1.35, "side thrust reaches +X", "tip x %.2f" % max_x)
	_ok(max_yaw <= 0.20, "side thrust does not turn", "max torso yaw %.3f rad" % max_yaw)
	_ok(side_floor >= -0.03, "side thrust floor", "%.3f" % side_floor)
	report["side"] = {"tip_x": max_x, "yaw": max_yaw}

	# back thrust: tip behind (+Z) and on the body's left (-X)
	rig.reset_demo(Vector3.ZERO, 0.0)
	var best_back := Vector3.ZERO
	var back_yaw := 0.0
	rig.request_back_attack()
	for i in 170:
		rig.advance(1.0 / 60.0)
		var tip := rig.blade_tip_world()
		if tip.z > best_back.z:
			best_back = tip
		back_yaw = maxf(back_yaw, absf(rig.torso.rotation.y))
		if not rig.is_attacking and i > 10:
			break
	_ok(best_back.z >= 0.90, "back thrust reaches behind", "tip z %.2f" % best_back.z)
	_ok(best_back.x <= 0.02, "back thrust exits left side", "tip x %.2f" % best_back.x)
	_ok(back_yaw <= 0.35, "back thrust minimal turn", "%.3f rad" % back_yaw)
	report["back"] = {"tip": best_back, "yaw": back_yaw}

	# heavy: overhead and down
	rig.reset_demo(Vector3.ZERO, 0.0)
	var heavy_min_y := 99.0
	var heavy_max_y := -99.0
	rig.request_heavy_attack()
	for i in 220:
		rig.advance(1.0 / 60.0)
		var ty := rig.blade_tip_world().y
		heavy_min_y = minf(heavy_min_y, ty)
		heavy_max_y = maxf(heavy_max_y, ty)
		if not rig.is_attacking and i > 10:
			break
	_ok(heavy_max_y >= 1.55, "heavy raises overhead", "tip y %.2f" % heavy_max_y)
	_ok(heavy_min_y <= 0.35, "heavy strikes low", "tip y %.2f" % heavy_min_y)
	report["heavy"] = {"min_y": heavy_min_y, "max_y": heavy_max_y}

	# spin: continuous 360 and horizontal blade
	rig.reset_demo(Vector3.ZERO, 0.0)
	var yaw_acc := 0.0
	var prev_yaw: float = rig.torso.rotation.y
	var horiz_err := 0.0
	rig.request_spin_attack()
	for i in 220:
		rig.advance(1.0 / 60.0)
		var y: float = rig.torso.rotation.y
		yaw_acc += absf(wrapf(y - prev_yaw, -PI, PI))
		prev_yaw = y
		if rig.is_attacking and rig.attack_time > 0.55 and rig.attack_time < 0.95:
			var h := rig.weapon_root.global_position
			var t := rig.blade_tip_world()
			horiz_err = maxf(horiz_err, absf(t.y - h.y))
		if not rig.is_attacking and i > 10:
			break
	_ok(yaw_acc >= TAU * 0.92, "spin sweeps 360", "%.2f rad" % yaw_acc)
	_ok(horiz_err <= 0.55, "spin blade held level", "dy %.2f m" % horiz_err)
	report["spin"] = {"yaw": yaw_acc, "level_err": horiz_err}

	# ---------------- dashes
	var fwd := await _dash_test(Vector3(0, 0, -1), "forward")
	_ok(fwd["along"] >= 1.2, "forward dash distance", "%.2f m" % fwd["along"])
	var left := await _dash_test(Vector3(-1, 0, 0), "left")
	_ok(left["along"] >= 1.2 and left["side"] >= 1.2, "left dash", "along %.2f side %.2f" % [left["along"], left["side"]])
	var right := await _dash_test(Vector3(1, 0, 0), "right")
	_ok(right["along"] >= 1.2 and right["side"] >= 1.2, "right dash", "along %.2f side %.2f" % [right["along"], right["side"]])
	report["dash"] = {"fwd": fwd, "left": left, "right": right}

	# ---------------- jump crouch + apex
	rig.reset_demo(Vector3.ZERO, 0.0)
	var crouch_y := 99.0
	var apex := -99.0
	rig.request_jump()
	for i in 200:
		rig.advance(1.0 / 60.0)
		if rig.jump_state == "TAKEOFF":
			crouch_y = minf(crouch_y, rig.body.position.y)
		apex = maxf(apex, rig.position.y)
		if rig.jump_state == "LANDING" and i > 20:
			break
	var drop: float = 1.235 - crouch_y
	_ok(drop >= 0.18, "jump has visible crouch", "hip drop %.2f m" % drop)
	_ok(apex >= 0.55, "jump apex", "%.2f m" % apex)
	report["jump"] = {"crouch_drop": drop, "apex": apex}

	# ---------------- hair
	rig.reset_demo(Vector3.ZERO, 0.0)
	for i in 30:
		rig.advance(1.0 / 60.0)
		await get_tree().process_frame
	var tips0: Array = rig.hair_tips()
	rig.move_command = Vector3(0, 0, -5.0)
	for i in 50:
		rig.advance(1.0 / 60.0)
		await get_tree().process_frame
	var tips1: Array = rig.hair_tips()
	_ok(tips0.size() >= 20, "hair bone-chain tips", "%d tips" % tips0.size())
	var hair_move := 0.0
	var nan := false
	for i in mini(tips0.size(), tips1.size()):
		var a: Vector3 = tips0[i]
		var b: Vector3 = tips1[i]
		if is_nan(a.x) or is_nan(b.x):
			nan = true
		hair_move = maxf(hair_move, a.distance_to(b))
	_ok(not nan, "hair no NaN")
	_ok(hair_move >= 0.03, "hair responds to motion", "tip shift %.3f m" % hair_move)
	report["hair"] = {"tips": tips0.size(), "shift": hair_move}


func _run_front_attack(step: int) -> Dictionary:
	rig.reset_demo(Vector3.ZERO, 0.0)
	await get_tree().process_frame
	rig.request_front_attack(step)
	var min_z := 99.0
	var reach := 0.0
	var floor_y := 99.0
	for i in 180:
		rig.advance(1.0 / 60.0)
		var tip := rig.blade_tip_world()
		min_z = minf(min_z, tip.z)
		reach = maxf(reach, Vector2(tip.x, tip.z).length())
		floor_y = minf(floor_y, rig.body_aabb().position.y)
		if not rig.is_attacking and i > 10:
			break
	return {"min_z": min_z, "reach": reach, "floor": floor_y}


func _dash_test(local_dir: Vector3, _label: String) -> Dictionary:
	rig.reset_demo(Vector3.ZERO, 0.0)
	var p0 := rig.global_position
	rig.request_dash(local_dir)
	for i in 40:
		rig.advance(1.0 / 60.0)
	var d := rig.global_position - p0
	return {"along": d.length(), "side": absf(d.x) if absf(local_dir.x) > 0.5 else absf(d.z)}


func _finish() -> void:
	print("\n==== VESPER v2 QA: %d checks, %d failures ====" % [checks, fails.size()])
	for f in fails:
		print("  FAILED: ", f)
	var f := FileAccess.open("res://renders/qa_v2.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	get_tree().quit(0 if fails.is_empty() else 1)