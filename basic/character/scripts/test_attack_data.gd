extends SceneTree
## Headless self-test for scripts/mech/attack_data.gd.
## Run: godot --headless --path . --script res://scripts/test_attack_data.gd
##
## World-space checks use the v2 frame:
##   body y = 1.235 - crouch, torso origin +0.12, torso scale 0.82
##   hilt = torso_transform * (wpx, wpy, wpz)
##   tip  = hilt + (torso rotation) * (0.82 * 1.25) * blade_axis
## (the rig's body lean pitch is included as well; it is what the mesh does).

const AD = preload("res://scripts/mech/attack_data.gd")
const EPS := 1.0e-6
const EULER_ORDER := EULER_ORDER_YXZ

const HIP_Y := 1.235
const WAIST_Y := 0.12
const TORSO_SCALE := 0.82
const WORLD_BLADE := 1.25      # metres, hilt origin -> tip

var failures: Array[String] = []
var checks := 0

const STYLE_OF := {
	"FRONT_R": "twohand", "FRONT_L": "twohand",
	"RISE_R": "twohand", "RISE_L": "twohand",
	"SIDE_THRUST_R": "side_r", "BACK_THRUST": "back_r",
	"HEAVY": "twohand", "SPIN": "spin",
}
const STYLE_VALUES := ["twohand", "side_r", "back_r", "spin"]


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures.append(msg)


func _initialize() -> void:
	print("=== VESPER attack_data self-test ===")
	print("frame: hip y=%.3f waist=+%.2f torso_scale=%.2f blade=%.2f m" % [
		HIP_Y, WAIST_Y, TORSO_SCALE, WORLD_BLADE])
	print("BASE_POSE = ", AD.BASE_POSE)

	_check_clip_table()
	_check_mirror()
	_check_front_arcs()
	_check_side_thrust()
	_check_back_thrust()
	_check_heavy()
	_check_spin()

	print("\n%d checks, %d failures" % [checks, failures.size()])
	if failures.is_empty():
		print("PASS attack_data")
		quit(0)
	else:
		for f in failures:
			print("FAIL: " + f)
		quit(1)


# ------------------------------------------------------------------ helpers
func sample(clip: Dictionary, t: float) -> Dictionary:
	var keys: Array = clip["keys"]
	var tt := clampf(t, 0.0, float(clip["duration"]))
	var a: Dictionary = keys[0]
	var b: Dictionary = keys[0]
	for i in keys.size() - 1:
		if tt >= float(keys[i]["t"]) and tt <= float(keys[i + 1]["t"]):
			a = keys[i]
			b = keys[i + 1]
			break
	var span: float = maxf(float(b["t"]) - float(a["t"]), 1.0e-9)
	var u: float = clampf((tt - float(a["t"])) / span, 0.0, 1.0)
	u = u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
	var pa: Dictionary = AD.BASE_POSE.duplicate()
	pa.merge(a.get("p", {}), true)
	var pb: Dictionary = AD.BASE_POSE.duplicate()
	pb.merge(b.get("p", {}), true)
	var out := {}
	for ch in pa.keys():
		out[ch] = lerpf(float(pa[ch]), float(pb[ch]), u)
	return out


func resolved_key(key: Dictionary) -> Dictionary:
	var p: Dictionary = AD.BASE_POSE.duplicate()
	p.merge(key.get("p", {}), true)
	return p


func mirror_pose(p: Dictionary) -> Dictionary:
	# Independent implementation: explicit sign table, no shared helper.
	var signs := {
		"wpx": -1.0, "ty": -1.0, "hy": -1.0, "wry": -1.0, "wrz": -1.0,
		"tx": -1.0, "tz": -1.0,
	}
	var out := {}
	for ch in p.keys():
		out[ch] = float(p[ch]) * float(signs.get(ch, 1.0))
	return out


func basis_of(p: Dictionary) -> Basis:
	return Basis.from_euler(
		Vector3(float(p["wrx"]), float(p["wry"]), float(p["wrz"])), EULER_ORDER)


func hilt_of(p: Dictionary) -> Vector3:
	return Vector3(float(p["wpx"]), float(p["wpy"]), float(p["wpz"]))


## Full authored pose -> rig world space (body lean + torso rotation + scale).
func world_pose(p: Dictionary) -> Dictionary:
	var body_basis := Basis(Vector3.RIGHT, -float(p["lean"]))
	var body_origin := Vector3(0.0, HIP_Y - float(p["crouch"]), 0.0)
	var torso_origin: Vector3 = body_origin + body_basis * Vector3(0.0, WAIST_Y, 0.0)
	var torso_basis: Basis = body_basis * Basis.from_euler(
		Vector3(float(p["tx"]), float(p["ty"]), float(p["tz"])), EULER_ORDER)
	var hilt: Vector3 = torso_origin + torso_basis * (hilt_of(p) * TORSO_SCALE)
	var axis: Vector3 = (torso_basis * basis_of(p).y).normalized()
	var tip: Vector3 = hilt + axis * (TORSO_SCALE * WORLD_BLADE)
	return {"hilt": hilt, "axis": axis, "tip": tip}


func cmp_pose(a: Dictionary, b: Dictionary, tol: float, tag: String) -> void:
	for ch in a.keys():
		if not b.has(ch):
			check(false, "%s: missing channel %s" % [tag, ch])
			continue
		var d := absf(float(a[ch]) - float(b[ch]))
		check(d < tol, "%s: channel %s differs %.9f" % [tag, ch, d])


func v3s(v: Vector3) -> String:
	return "(%+.3f, %+.3f, %+.3f)" % [v.x, v.y, v.z]


# --------------------------------------------------------------- clip table
func _check_clip_table() -> void:
	print("\n--- clips ---")
	check(AD.CLIP_NAMES.size() == 8, "CLIP_NAMES must have 8 entries")
	for name in AD.CLIP_NAMES:
		check(AD.CLIPS.has(name), "CLIPS missing " + name)
		check(AD.get_clip(name)["name"] == name, "get_clip(%s) name mismatch" % name)
		var c: Dictionary = AD.get_clip(name)
		for field in ["name", "duration", "trail", "keys", "lunge", "hit_at", "hit_kind", "style"]:
			check(c.has(field), "%s missing field %s" % [name, field])

		var dur := float(c["duration"])
		check(dur >= 0.70 and dur <= 1.60, "%s duration %.3f out of 0.7..1.6" % [name, dur])
		var hit := float(c["hit_at"])
		check(hit > dur * 0.2 and hit < dur * 0.8, "%s hit_at %.3f not mid-clip" % [name, hit])
		var trail: Array = c["trail"]
		check(trail.size() == 2, "%s trail needs 2 values" % name)
		check(float(trail[0]) >= 0.0 and float(trail[0]) < float(trail[1]) and float(trail[1]) <= dur + EPS,
			"%s bad trail %s" % [name, str(trail)])
		check(hit >= float(trail[0]) - EPS and hit <= float(trail[1]) + EPS,
			"%s hit_at outside trail" % name)
		check(STYLE_OF.get(name, "?") == String(c["style"]), "%s style mismatch" % name)
		check(String(c["style"]) in STYLE_VALUES, "%s style outside the 4 allowed values" % name)
		check(String(c["hit_kind"]) in ["air", "ground"], "%s bad hit_kind" % name)

		# keys: strict time order, 0 .. duration
		var keys: Array = c["keys"]
		check(keys.size() >= 3, "%s needs at least 3 keys" % name)
		check(absf(float(keys[0]["t"])) < EPS, "%s first key must be t=0" % name)
		check(absf(float(keys[keys.size() - 1]["t"]) - dur) < EPS, "%s last key must be duration" % name)
		var min_hilt_y := 1.0e9
		var max_hilt_y := -1.0e9
		for i in keys.size():
			check(absf(float(keys[i]["t"])) <= dur + EPS, "%s key %d out of range" % [name, i])
			if i > 0:
				check(float(keys[i]["t"]) > float(keys[i - 1]["t"]),
					"%s keys not strictly monotonic at %d" % [name, i])
			var p: Dictionary = keys[i].get("p", {})
			for ch in p.keys():
				check(AD.BASE_POSE.has(ch), "%s key %d unknown channel %s" % [name, i, ch])
				var v = p[ch]
				check(typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT,
					"%s key %d channel %s is not numeric" % [name, i, ch])
				if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
					check(is_finite(float(v)), "%s key %d channel %s is not finite" % [name, i, ch])
			var full := resolved_key(keys[i])
			var wh := world_pose(full)["hilt"] as Vector3
			min_hilt_y = minf(min_hilt_y, wh.y)
			max_hilt_y = maxf(max_hilt_y, wh.y)
			# gameplay reach envelope: wpy in [-0.10, 0.65]
			check(float(full["wpy"]) >= -0.10 - EPS and float(full["wpy"]) <= 0.65 + EPS,
				"%s key %d wpy %.3f outside [-0.10, 0.65]" % [name, i, float(full["wpy"])])
		# HEAVY's overhead raise is allowed above the normal hilt band.
		if name != "HEAVY":
			check(min_hilt_y >= 0.85 - EPS and max_hilt_y <= 1.90 + EPS,
				"%s hilt world y range %.3f..%.3f outside 0.85..1.90" % [name, min_hilt_y, max_hilt_y])

		# lunge: ordered, non-negative, inside the clip
		var lunge: Array = c["lunge"]
		check(lunge.size() >= 2, "%s lunge needs >= 2 points" % name)
		for i in lunge.size():
			check(absf(float(lunge[i][0])) <= dur + EPS, "%s lunge t out of range" % name)
			check(float(lunge[i][1]) >= -EPS, "%s lunge negative distance" % name)
			if i > 0:
				check(float(lunge[i][0]) > float(lunge[i - 1][0]),
					"%s lunge times not increasing" % name)
				check(float(lunge[i][1]) >= float(lunge[i - 1][1]) - EPS,
					"%s lunge must not reverse" % name)

		var off := AD.offhand_for(name)
		var want_off := 1.0 if (name == "SIDE_THRUST_R" or name == "BACK_THRUST") else 0.0
		check(absf(off - want_off) < EPS, "%s offhand_for = %.3f, want %.1f" % [name, off, want_off])

		var hp := sample(c, hit)
		check(hp.size() == AD.BASE_POSE.size(), "%s hit pose incomplete" % name)
		var wh := world_pose(hp)["hilt"] as Vector3
		var wt := world_pose(hp)["tip"] as Vector3
		print("%-14s dur=%.2f hit=%.2f %-7s hilt_y=%.2f..%.2f tip=(%.2f,%.2f,%.2f)" % [
			name, dur, hit, String(c["style"]), min_hilt_y, max_hilt_y, wt.x, wt.y, wt.z])

	check(AD.get_clip("NOPE")["name"] == "FRONT_R", "unknown clip must fall back to FRONT_R")
	check(AD.get_clip("FRONT_L")["name"] == "FRONT_L", "FRONT_L lookup broken")


# ------------------------------------------------------------------ mirrors
func _check_mirror() -> void:
	print("\n--- mirror symmetry ---")
	for pair in [["FRONT_R", "FRONT_L"], ["RISE_R", "RISE_L"]]:
		var r: Dictionary = AD.get_clip(pair[0])
		var l: Dictionary = AD.get_clip(pair[1])
		check(String(l["name"]) == pair[1], "%s wrong mirrored name" % pair[1])
		check(absf(float(r["duration"]) - float(l["duration"])) < EPS, "%s duration mismatch" % pair[1])
		check(absf(float(r["hit_at"]) - float(l["hit_at"])) < EPS, "%s hit_at mismatch" % pair[1])
		check(int(r["keys"].size()) == int(l["keys"].size()), "%s key count mismatch" % pair[1])

		# Compare the authored action span only: both sides deliberately share
		# the same neutral ready stance at t=0 / t=duration.
		var ta := 0.0
		var tb := float(r["duration"])
		for key in r["keys"]:
			if not key.get("p", {}).is_empty():
				ta = float(key["t"])
				break
		var rev: Array = r["keys"]
		for i in range(rev.size() - 1, -1, -1):
			if not rev[i].get("p", {}).is_empty():
				tb = float(rev[i]["t"])
				break
		var worst := 0.0
		var n := 24
		for i in n + 1:
			var t := ta + (tb - ta) * float(i) / float(n)
			var want := mirror_pose(sample(r, t))
			var got := sample(l, t)
			for ch in want.keys():
				worst = maxf(worst, absf(float(want[ch]) - float(got[ch])))
		check(worst < EPS, "%s mirror error %.9f" % [pair[1], worst])
		print("%-8s <-> %-8s action span %.2f..%.2f, max channel error = %.9f" % [
			pair[0], pair[1], ta, tb, worst])

		# mirrored(mirrored(x)) must restore x (pose-wise, whole clip)
		var back := AD.mirrored(AD.mirrored(r))
		var wr := 0.0
		for i in n + 1:
			var t := float(r["duration"]) * float(i) / float(n)
			var a := sample(r, t)
			var b := sample(back, t)
			for ch in a.keys():
				wr = maxf(wr, absf(float(a[ch]) - float(b[ch])))
		check(wr < 1.0e-5, "%s double mirror error %.9f" % [pair[0], wr])
		print("%-8s double-mirror error = %.9f" % [pair[0], wr])

		# Both clips must share the exact same neutral endpoints.
		cmp_pose(sample(r, 0.0), sample(l, 0.0), EPS, "%s/%s start stance mismatch" % [pair[0], pair[1]])
		cmp_pose(sample(r, float(r["duration"])), sample(l, float(l["duration"])),
			EPS, "%s/%s end stance mismatch" % [pair[0], pair[1]])


# ------------------------------------------------------------- front strikes
func _check_front_arcs() -> void:
	print("\n--- front hemisphere strikes (world) ---")
	for name in ["FRONT_R", "FRONT_L", "RISE_R", "RISE_L"]:
		var c: Dictionary = AD.get_clip(name)
		var hp := sample(c, float(c["hit_at"]))
		var w := world_pose(hp)
		var side := 1.0 if name.ends_with("_L") else -1.0
		# hit tip must be at least 0.9 m in front of the body and cross sides
		check((w["tip"] as Vector3).z <= -0.90,
			"%s hit tip.z %.3f > -0.90" % [name, (w["tip"] as Vector3).z])
		check((w["axis"] as Vector3).z < -0.20,
			"%s hit blade not forward (axis.z=%.3f)" % [name, (w["axis"] as Vector3).z])
		check((w["tip"] as Vector3).x * side > 0.05, "%s hit tip did not cross sides" % name)
		if name.begins_with("FRONT"):
			check((w["tip"] as Vector3).y < (w["hilt"] as Vector3).y - 0.20,
				"%s should chop downward" % name)
		else:
			check((w["tip"] as Vector3).y > (w["hilt"] as Vector3).y + 0.20,
				"%s should rise" % name)
		# windup must sit on the named side and high/low
		var wind_t := 0.18 if name.begins_with("FRONT") else 0.16
		var ww := world_pose(sample(c, wind_t))
		var wind_side := 1.0 if name.ends_with("_R") else -1.0
		check((ww["tip"] as Vector3).x * wind_side > 0.20,
			"%s windup tip not on %s side" % [name, "right" if wind_side > 0 else "left"])
		if name.begins_with("FRONT"):
			check((ww["tip"] as Vector3).y > (ww["hilt"] as Vector3).y + 0.30,
				"%s windup not high" % name)
		else:
			check((ww["tip"] as Vector3).y < (ww["hilt"] as Vector3).y,
				"%s windup not low" % name)
		print("%-8s hilt=%s axis=%s tip=%s" % [
			name, v3s(w["hilt"]), v3s(w["axis"]), v3s(w["tip"])])


# --------------------------------------------------------------- side thrust
func _check_side_thrust() -> void:
	print("\n--- SIDE_THRUST_R (world) ---")
	var c: Dictionary = AD.get_clip("SIDE_THRUST_R")
	var ty_values := []
	for key in c["keys"]:
		var p := resolved_key(key)
		ty_values.append(float(p["ty"]))
	var ty_min = ty_values.min()
	var ty_max = ty_values.max()
	check(ty_max - ty_min <= 0.12 + EPS, "SIDE yaw range %.3f exceeds 0.12" % (ty_max - ty_min))
	check(absf(ty_min) <= 0.12 + EPS and absf(ty_max) <= 0.12 + EPS,
		"SIDE yaw leaves +-0.12")
	print("waist yaw range: %.3f .. %.3f rad (|ty| <= 0.12)" % [ty_min, ty_max])

	var hp := sample(c, float(c["hit_at"]))
	var hw := world_pose(hp)
	check((hw["tip"] as Vector3).x >= 1.35,
		"SIDE clip hit tip.x %.3f < 1.35" % (hw["tip"] as Vector3).x)
	check(absf(float(hp["ty"])) <= 0.12 + EPS, "SIDE hit ty %.3f" % float(hp["ty"]))
	print("clip hit hilt=%s axis=%s tip=%s" % [
		v3s(hw["hilt"]), v3s(hw["axis"]), v3s(hw["tip"])])

	for u in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var sp: Dictionary = AD.side_thrust_pose(u, 1.0)
		var p := hp.duplicate()
		for ch in ["wpx", "wpy", "wpz", "wrx", "wry", "wrz"]:
			p[ch] = sp[ch]
		var b := basis_of(sp)
		var w := world_pose(p)
		check(absf((b.y as Vector3).y) < EPS, "SIDE u=%.2f local axis not horizontal" % u)
		check((b.y as Vector3).x > 0.999999, "SIDE u=%.2f local axis not +X" % u)
		check(absf((b.z as Vector3).y) < EPS, "SIDE u=%.2f blade face not vertical" % u)
		check((w["tip"] as Vector3).x >= 1.35,
			"SIDE u=%.2f world tip.x %.3f < 1.35" % [u, (w["tip"] as Vector3).x])
		print("u=%.2f hilt=%s axis=%s tip=%s" % [
			u, v3s(w["hilt"]), v3s(w["axis"]), v3s(w["tip"])])

	# left variant is the exact reflection of the right one
	for u in [0.0, 0.5, 1.0]:
		var pr: Dictionary = AD.side_thrust_pose(u, 1.0)
		var pl: Dictionary = AD.side_thrust_pose(u, -1.0)
		cmp_pose(mirror_pose(pr), pl, EPS, "SIDE mirror u=%.2f" % u)

	# authored hit key must match the static contact pose
	var sp: Dictionary = AD.side_thrust_pose(1.0, 1.0)
	cmp_pose(sp, hp, 1.0e-3, "SIDE clip hit vs static")


# --------------------------------------------------------------- back thrust
func _check_back_thrust() -> void:
	print("\n--- BACK_THRUST (world) ---")
	var c: Dictionary = AD.get_clip("BACK_THRUST")
	var hp := sample(c, float(c["hit_at"]))
	var hw := world_pose(hp)
	check((hw["tip"] as Vector3).z >= 0.90,
		"BACK clip hit tip.z %.3f < 0.90" % (hw["tip"] as Vector3).z)
	check((hw["tip"] as Vector3).x <= 0.0,
		"BACK clip hit tip.x %.3f > 0" % (hw["tip"] as Vector3).x)
	print("clip hit hilt=%s axis=%s tip=%s" % [
		v3s(hw["hilt"]), v3s(hw["axis"]), v3s(hw["tip"])])

	for u in [0.0, 0.5, 0.75, 1.0]:
		var sp: Dictionary = AD.back_thrust_pose(u)
		var p := hp.duplicate()
		for ch in ["wpx", "wpy", "wpz", "wrx", "wry", "wrz"]:
			p[ch] = sp[ch]
		var b := basis_of(sp)
		var w := world_pose(p)
		check(not is_nan((b.y as Vector3).x), "BACK axis NaN")
		print("u=%.2f hilt=%s axis=%s tip=%s" % [
			u, v3s(w["hilt"]), v3s(w["axis"]), v3s(w["tip"])])
		if u >= 0.999:
			var h := hilt_of(sp)
			check(absf(h.x + 0.22) < 1.0e-4, "BACK hit hilt x %.4f" % h.x)
			check(absf(h.y - 0.25) < 1.0e-4, "BACK hit hilt y %.4f" % h.y)
			check(absf(h.z - 0.18) < 1.0e-4, "BACK hit hilt z %.4f" % h.z)
			var target := Vector3(-0.35, 0.05, 0.94).normalized()
			check((b.y as Vector3).dot(target) > 0.9999,
				"BACK hit axis %.6f" % (b.y as Vector3).dot(target))
			check((w["tip"] as Vector3).z >= 0.90,
				"BACK static hit tip.z %.3f < 0.90" % (w["tip"] as Vector3).z)
			check((w["tip"] as Vector3).x <= 0.0,
				"BACK static hit tip.x %.3f > 0" % (w["tip"] as Vector3).x)

	# authored hit key must match the static contact pose
	var sp: Dictionary = AD.back_thrust_pose(1.0)
	cmp_pose(sp, hp, 1.0e-3, "BACK clip hit vs static")


# -------------------------------------------------------------------- heavy
func _check_heavy() -> void:
	print("\n--- HEAVY ground slam (world) ---")
	var c: Dictionary = AD.get_clip("HEAVY")
	var peak := resolved_key({})
	var best_wpy := -99.0
	for key in c["keys"]:
		var p := resolved_key(key)
		if float(p["wpy"]) > best_wpy:
			best_wpy = float(p["wpy"])
			peak = p
	var pw := world_pose(peak)
	check(best_wpy >= 0.60 and best_wpy <= 0.68,
		"HEAVY raise wpy %.3f not around 0.64" % best_wpy)
	check((pw["tip"] as Vector3).y >= 2.20,
		"HEAVY raise tip.y %.3f < 2.20" % (pw["tip"] as Vector3).y)
	print("raise  wpy=%.2f hilt=%s tip=%s" % [best_wpy, v3s(pw["hilt"]), v3s(pw["tip"])])

	var hp := sample(c, float(c["hit_at"]))
	var hw := world_pose(hp)
	check((hw["tip"] as Vector3).y <= 0.35,
		"HEAVY hit tip.y %.3f > 0.35" % (hw["tip"] as Vector3).y)
	check((hw["tip"] as Vector3).y >= -0.10,
		"HEAVY hit tip.y %.3f is far below the floor" % (hw["tip"] as Vector3).y)
	check((hw["tip"] as Vector3).z <= -0.25,
		"HEAVY hit tip.z %.3f is not in front" % (hw["tip"] as Vector3).z)
	var key := {}
	for k in c["keys"]:
		if absf(float(k["t"]) - float(c["hit_at"])) < EPS:
			key = k
	check(not key.is_empty(), "HEAVY hit_at must land on a key")
	if not key.is_empty():
		check(float(key["p"].get("wpy", 99.0)) <= 0.05, "HEAVY hit wpy not ~0.02")
		check(float(key["p"].get("crouch", 0.0)) >= 0.30, "HEAVY hit crouch not deep")
	print("impact wpy=%.2f crouch=%.2f hilt=%s tip=%s" % [
		float(hp["wpy"]), float(hp["crouch"]), v3s(hw["hilt"]), v3s(hw["tip"])])


# --------------------------------------------------------------------- spin
func _check_spin() -> void:
	print("\n--- SPIN ---")
	var c: Dictionary = AD.get_clip("SPIN")
	var keys: Array = c["keys"]
	var mid := []
	for key in keys:
		var t := float(key["t"])
		if t >= 0.30 - EPS and t <= 1.16 + EPS:
			var p := resolved_key(key)
			mid.append({"t": t, "ty": float(p["ty"]), "p": p})
	check(mid.size() >= 4, "SPIN needs >= 4 mid keys")
	var rates := []
	for i in range(1, mid.size()):
		var dt: float = float(mid[i]["t"]) - float(mid[i - 1]["t"])
		var dty: float = float(mid[i]["ty"]) - float(mid[i - 1]["ty"])
		rates.append(dty / dt)
		check(dty > 0.0, "SPIN ty not increasing")
		var axis: Vector3 = basis_of(mid[i]["p"]).y
		check(absf(axis.y) < 1.0e-4, "SPIN blade not horizontal at t=%.2f" % float(mid[i]["t"]))
	var r0: float = rates[0]
	for r in rates:
		check(absf(float(r) - r0) < 0.05, "SPIN mid angular rate %.3f != %.3f" % [r, r0])
	var total := float(mid[mid.size() - 1]["ty"]) - float(mid[0]["ty"])
	check(total > TAU - 0.30, "SPIN only spans %.3f rad" % total)
	check(float(keys[keys.size() - 1]["t"]) >= 1.30, "SPIN too short")
	print("mid angular rate = %.3f rad/s, span %.3f rad, %d mid keys" % [r0, total, mid.size()])