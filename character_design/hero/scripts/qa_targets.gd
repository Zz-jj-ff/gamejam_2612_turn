extends Node3D
## Target-hit acceptance: at each attack's hit frame the blade must actually
## reach and intersect a humanoid standing 1.8 m away in that direction.
const Rig = preload("res://scripts/mech/mech_rig.gd")

var rig
var fails: Array[String] = []
var rows: Array[String] = []

func _ready() -> void:
	rig = Rig.new()
	rig.auto_step = false
	rig.set_process(false)
	add_child(rig)
	await get_tree().process_frame
	await _run("FRONT_R", Vector3(0, 1.0, -1.8), 1)
	await _run("SIDE_THRUST_R", Vector3(1.8, 1.0, 0), 2)
	await _run("BACK_THRUST", Vector3(0, 1.0, 1.8), 3)
	print("\n==== TARGET HIT QA (1.8 m humanoid) ====")
	for r in rows: print(r)
	print("failures: ", fails.size())
	for f in fails: print("FAIL: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)

func _run(label: String, target: Vector3, idx: int) -> void:
	rig.reset_demo(Vector3.ZERO, 0.0)
	await get_tree().process_frame
	match idx:
		1: rig.request_front_attack(1)
		2: rig.request_side_attack(1.0)
		3: rig.request_back_attack()
	var best := 1e9
	var best_tip_dist := 1e9
	var at_t := 0.0
	var guard := 0
	while guard < 300:
		rig.advance(1.0 / 120.0)
		guard += 1
		var hit_at := float(rig._attack.get("hit_at", 0.3)) if rig.is_attacking else -1.0
		if hit_at < 0.0:
			break
		if absf(rig.attack_time - hit_at) <= 0.02:
			var a: Vector3 = rig.blade_base.global_position
			var b: Vector3 = rig.blade_tip.global_position
			var ta: Vector3 = target + Vector3(0, -0.9, 0)
			var tb: Vector3 = target + Vector3(0, 0.9, 0)
			var d := _seg_seg(a, b, ta, tb) - 0.30
			var td := Vector3(b.x, target.y, b.z).distance_to(Vector3(target.x, target.y, target.z))
			if d < best:
				best = d; best_tip_dist = td; at_t = rig.attack_time
		if not rig.is_attacking and guard > 20:
			break
	var ok := best <= 0.0
	var tag := "PASS" if ok else "FAIL"
	rows.append("%-14s %s  blade-to-target=%.3f m  tip-horizontal=%.3f m @ t=%.3f" % [label, tag, best, best_tip_dist, at_t])
	if not ok:
		fails.append("%s blade misses 1.8 m target by %.3f m" % [label, best])

func _seg_seg(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> float:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	var s := 0.0
	var t := 0.0
	if a <= 1e-9 and e <= 1e-9:
		return p1.distance_to(p2)
	if a <= 1e-9:
		t = clampf(f / e, 0.0, 1.0)
	else:
		var c := d1.dot(r)
		if e <= 1e-9:
			s = clampf(-c / a, 0.0, 1.0)
		else:
			var b := d1.dot(d2)
			var denom := a * e - b * b
			if denom != 0.0:
				s = clampf((b * f - c * e) / denom, 0.0, 1.0)
			t = (b * s + f) / e
			if t < 0.0:
				t = 0.0
				s = clampf(-c / a, 0.0, 1.0)
			elif t > 1.0:
				t = 1.0
				s = clampf((b - c) / a, 0.0, 1.0)
	return (p1 + d1 * s).distance_to(p2 + d2 * t)
