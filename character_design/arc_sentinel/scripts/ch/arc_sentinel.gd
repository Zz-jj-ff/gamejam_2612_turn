extends Node3D
## ARC // SENTINEL v2 — two-wheel balancer contract implementation.
##
## Everything (meshes, materials, motion, FX) is generated from code. Animation
## is 100% joint-driven: poses are joint-angle dictionaries produced by ArcAnim2
## and applied by ArcRig. The attack/block key poses are solved at build time by
## the analytic arm IK with collision-aware swivel selection (ArcKin2).
##
## Contract: anim_names/play_anim/set_playing/is_playing/anim_time/set_anim_time/
## anim_duration/set_anim_speed/anim_speed/set_loop/is_looping/param_specs/
## set_param/get_param/joint_specs/set_joint/get_joint/rig_debug.

signal scene_param_changed(key: String, value: float)

const RIG := preload("res://scripts/ch/arc_rig.gd")
const ANIM := preload("res://scripts/ch/arc_anim.gd")
const KIN := preload("res://scripts/ch/arc_kin.gd")
const AM := preload("res://scripts/ch/arc_materials.gd")
const MK := preload("res://scripts/kit/mesh_kit.gd")

const D2R := PI / 180.0
const ANIMS := ["rest", "idle", "walk", "attack", "attack_up", "defend", "draw", "sheathe"]
const DRAWN := ["idle", "walk", "attack", "attack_up", "defend"]

var current_anim := "idle"
var rig: ArcRig
var kin: ArcKin2
var anim: ArcAnim2
var P: Dictionary = {}

var _t := 0.0
var _playing := true
var _loop := true
var _speed := 1.0
var _manual := false
var _pose: Dictionary = {}
var _fade_from: Dictionary = {}
var _fade_t := 0.0
const FADE_TIME := 0.12
var _after := ""
var _queued := ""
var _stance := "drawn"  # logical pose state: rest / drawn
var _camera: Camera3D
var _trail_mi: MeshInstance3D
var _trail_pts: Array = []
var _impact := 0.0
var _fx_t := 0.0
var _radius_cache := 0.0
var _radius_t := 0.0
var _clear_cache := 9.0
var _clear_pair := ["", ""]
var _clear_t := 0.0

const GEOM_KEYS := {
	"wheel_radius": true, "shield_radius": true, "blade_length": true,
}

const DEFAULTS := {
	"body_scale": 1.00, "hull_radius": 0.225, "wheel_radius": 0.325,
	"shield_radius": 0.310, "blade_length": 1.030, "blade_width": 0.176,
	"idle_sway": 1.00, "walk_lean": 1.00,
	"blade_intensity": 1.00, "shield_rings": 6.0, "shield_opacity": 0.52,
	"lens_intensity": 4.2, "trail_life": 0.09, "lens_track": 1.0,
	"shield_impact": 0.0, "arc_speed": 1.0, "_threat": 0,
	"env_energy": 1.25, "env_exposure": 1.15,
}


func _ready() -> void:
	P = DEFAULTS.duplicate()
	rig = RIG.new()
	rig.name = "Rig"
	add_child(rig)
	rig.build(P)
	kin = rig.kin
	anim = ANIM.new(kin, P)
	anim.build()
	_pose = anim.idle(0.0)
	_apply_now(0.0)
	_radius_cache = rig.measure_radius()
	_refresh_clearance()
	_build_fx()


# ================================================================== lifecycle

func _process(dt: float) -> void:
	if _fade_t > 0.0:
		_fade_t = maxf(_fade_t - dt, 0.0)
	if _playing:
		_t += dt * _speed
		var d := anim_duration()
		if _loop:
			if d > 0.001:
				_t = fmod(_t, d)
		else:
			if _t >= d:
				_t = d
				_playing = false
				_finish_one_shot()
	if _playing or not _manual:
		_apply_now(_t)
		if _fade_t > 0.0 and not _fade_from.is_empty():
			var k: float = smoothstep(0.0, 1.0, 1.0 - _fade_t / FADE_TIME)
			_pose = _blend_pose(_fade_from, _pose, k)
			rig.apply_pose(_pose)
			_track_lens()
	_update_fx(dt)


func _finish_one_shot() -> void:
	var was := current_anim
	# Update the logical stance at the instant the transition ends, never
	# before; requests made during the transition then resolve against the
	# pose that is actually on screen.
	if was == "draw":
		_stance = "drawn"
	elif was == "sheathe":
		_stance = "rest"
	if _queued != "":
		var q := _queued
		_queued = ""
		_after = ""
		_go(q)
		return
	if _after != "":
		var nxt := _after
		_after = ""
		_go(nxt)
		return
	# A directly played draw/sheathe (studio keys) settles into its loop.
	if was == "draw":
		_play_direct("idle")
	elif was == "sheathe":
		_play_direct("rest")


# ================================================================== contract

func anim_names() -> PackedStringArray:
	return PackedStringArray(ANIMS)


func play_anim(name: String) -> void:
	if not (name in ANIMS):
		return
	# Do not cancel a one-shot mid-swing: finish it, then resolve the latest
	# request against the stance that the finished clip leaves behind.
	if _playing and current_anim in ["attack", "attack_up", "defend", "draw", "sheathe"]:
		if name == current_anim and name != "attack" and name != "attack_up":
			return
		_queued = name
		return
	_go(name)


## Resolve a request into a loop or the correct rest <-> drawn transition.
## Every request ends in a loop; draw/sheathe are never skipped just because
## current_anim happens to still hold a previous transition name.
func _go(name: String) -> void:
	if name == "draw":
		_play_direct("draw")
		_after = "idle"
		return
	if name == "sheathe":
		_play_direct("sheathe")
		_after = "rest"
		return
	var target := "rest" if name == "rest" else "drawn"
	if target != _stance:
		_play_direct("sheathe" if target == "rest" else "draw")
		_after = name
		return
	_play_direct(name)


func _play_direct(name: String) -> void:
	current_anim = name
	_t = 0.0
	_playing = true
	_loop = name in ["idle", "walk", "rest"]
	_fade_from = _pose.duplicate()
	_fade_t = FADE_TIME
	_manual = false
	if name == "rest":
		_stance = "rest"
	elif name in DRAWN:
		_stance = "drawn"
	_trail_pts.clear()
	if _trail_mi:
		_trail_mi.mesh = null
	if name == "defend":
		_impact = 1.0
	_apply_now(0.0)
	_refresh_clearance()
	_update_fx(0.016)


func set_playing(v: bool) -> void:
	_playing = v


func is_playing() -> bool:
	return _playing


func anim_time() -> float:
	return _t


func set_anim_time(t: float) -> void:
	_manual = false
	_t = clampf(t, 0.0, anim_duration())
	_apply_now(_t)
	_update_fx(0.0)


func anim_duration() -> float:
	return anim.duration(current_anim)


func set_anim_speed(v: float) -> void:
	_speed = clampf(v, 0.02, 4.0)


func anim_speed() -> float:
	return _speed


func set_loop(v: bool) -> void:
	_loop = v


func is_looping() -> bool:
	return _loop


# ================================================================== params

func param_specs() -> Array:
	var s: Array = []
	_add_spec(s, "BODY", "wheel_radius", "wheel radius (m)", 0.26, 0.38, 0.005, P["wheel_radius"])
	_add_spec(s, "BODY", "idle_sway", "idle sway", 0.0, 2.5, 0.02, P["idle_sway"])
	_add_spec(s, "BODY", "walk_lean", "walk lean", 0.0, 2.0, 0.02, P["walk_lean"])
	_add_spec(s, "WEAPON", "shield_radius", "shield radius (m)", 0.25, 0.37, 0.005, P["shield_radius"])
	_add_spec(s, "WEAPON", "blade_length", "blade length (m)", 0.80, 1.25, 0.005, P["blade_length"])
	_add_spec(s, "ANIM // DEFEND", "_threat", "threat side 0=L 1=R", 0.0, 1.0, 1.0, P["_threat"])
	_add_spec(s, "FX", "blade_intensity", "blade intensity", 0.0, 2.0, 0.02, P["blade_intensity"])
	_add_spec(s, "FX", "shield_rings", "shield rings", 2.0, 14.0, 0.1, P["shield_rings"])
	_add_spec(s, "FX", "shield_opacity", "shield opacity", 0.05, 1.2, 0.01, P["shield_opacity"])
	_add_spec(s, "FX", "lens_intensity", "lens intensity", 0.0, 8.0, 0.05, P["lens_intensity"])
	_add_spec(s, "FX", "trail_life", "trail life (s)", 0.03, 0.30, 0.005, P["trail_life"])
	_add_spec(s, "FX", "lens_track", "lens tracks camera", 0.0, 1.0, 1.0, P["lens_track"])
	_add_spec(s, "FX", "shield_impact", "shield impact pulse", 0.0, 1.0, 0.01, P["shield_impact"])
	_add_spec(s, "FX", "arc_speed", "arc speed", 0.0, 2.0, 0.02, P["arc_speed"])
	_add_spec(s, "ENVIRONMENT", "env_energy", "ambient light", 0.0, 3.0, 0.05, P["env_energy"])
	_add_spec(s, "ENVIRONMENT", "env_exposure", "exposure", 0.5, 2.0, 0.01, P["env_exposure"])
	return s


func _add_spec(arr: Array, group: String, key: String, label: String,
		lo: float, hi: float, step: float, value: float) -> void:
	arr.append({"group": group, "key": key, "label": label, "min": lo,
		"max": hi, "step": step, "value": value})


func set_param(key: String, value: float) -> void:
	if not P.has(key):
		return
	P[key] = value
	if key == "env_energy" or key == "env_exposure":
		scene_param_changed.emit(key, value)
	if GEOM_KEYS.has(key):
		_rebuild()
	elif key == "_threat":
		anim.P["_threat"] = value
		anim._build_defend()
		_apply_now(_t)
	else:
		_apply_now(_t)
		_update_fx(0.0)


func get_param(key: String) -> float:
	return float(P.get(key, 0.0))


# ================================================================== joints

const JOINT_DEFS := [
	["ROOT / BODY", "root_lift", "root lift (m)", -0.20, 0.20, 0.005, 0],
	["ROOT / BODY", "root_sway", "root sway (m)", -0.15, 0.15, 0.005, 0],
	["ROOT / BODY", "root_shift", "root shift (m)", -0.15, 0.15, 0.005, 0],
	["ROOT / BODY", "body_pitch", "body pitch", -25, 25, 0.5, 1],
	["ROOT / BODY", "body_yaw", "body yaw", -35, 35, 0.5, 1],
	["ROOT / BODY", "body_roll", "body roll", -20, 20, 0.5, 1],
	["TORSO", "torso_pitch", "torso pitch", -30, 40, 0.5, 1],
	["TORSO", "torso_yaw", "torso yaw", -50, 50, 0.5, 1],
	["TORSO", "torso_roll", "torso roll", -25, 25, 0.5, 1],
	["LENS", "lens_yaw", "lens yaw", -50, 50, 0.5, 1],
	["LENS", "lens_pitch", "lens pitch", -35, 35, 0.5, 1],
	["WHEELS", "wheel_spin_L", "wheel L spin", -360, 360, 1.0, 1],
	["WHEELS", "wheel_spin_R", "wheel R spin", -360, 360, 1.0, 1],
	["ARM R", "shR_pitch", "shoulder pitch", -170, 170, 0.5, 1],
	["ARM R", "shR_yaw", "shoulder yaw", -170, 170, 0.5, 1],
	["ARM R", "shR_roll", "shoulder roll", -170, 170, 0.5, 1],
	["ARM R", "elbR_pitch", "elbow bend", -10, 165, 0.5, 1],
	["ARM R", "elbR_yaw", "elbow yaw", -60, 60, 0.5, 1],
	["ARM R", "elbR_roll", "elbow roll", -60, 60, 0.5, 1],
	["ARM R", "wrR_pitch", "wrist pitch", -170, 170, 0.5, 1],
	["ARM R", "wrR_yaw", "wrist yaw", -170, 170, 0.5, 1],
	["ARM R", "wrR_roll", "wrist roll", -170, 170, 0.5, 1],
	["ARM L", "shL_pitch", "shoulder pitch", -170, 170, 0.5, 1],
	["ARM L", "shL_yaw", "shoulder yaw", -170, 170, 0.5, 1],
	["ARM L", "shL_roll", "shoulder roll", -170, 170, 0.5, 1],
	["ARM L", "elbL_pitch", "elbow bend", -10, 165, 0.5, 1],
	["ARM L", "elbL_yaw", "elbow yaw", -60, 60, 0.5, 1],
	["ARM L", "elbL_roll", "elbow roll", -60, 60, 0.5, 1],
	["ARM L", "wrL_pitch", "wrist pitch", -170, 170, 0.5, 1],
	["ARM L", "wrL_yaw", "wrist yaw", -170, 170, 0.5, 1],
	["ARM L", "wrL_roll", "wrist roll", -170, 170, 0.5, 1],
	["SHIELD", "shield_yaw", "shield swivel", -180, 180, 1.0, 1],
	["SHIELD", "shield_pitch", "shield tilt", -60, 60, 0.5, 1],
]


func _arm_qbase(key: String) -> String:
	for j in ["sh", "elb", "wr"]:
		if key.begins_with(j) and (key.find("_pitch") > 0 or key.find("_yaw") > 0 or key.find("_roll") > 0):
			return key.substr(0, key.find("_"))
	return ""


func _joint_euler(key: String) -> Vector3:
	var base := _arm_qbase(key)
	if base != "" and _pose.has(base + "_q") and _pose[base + "_q"] is Quaternion:
		return Basis(_pose[base + "_q"] as Quaternion).get_euler()
	return Vector3(float(_pose.get(base + "_pitch", 0.0)),
		float(_pose.get(base + "_yaw", 0.0)), float(_pose.get(base + "_roll", 0.0)))


func joint_specs() -> Array:
	var out: Array = []
	for d in JOINT_DEFS:
		var rad: bool = int(d[6]) == 1
		var key: String = d[1]
		var v := 0.0
		var base := _arm_qbase(key)
		if base != "":
			var e := _joint_euler(key)
			if key.ends_with("_pitch"):
				v = e.x
			elif key.ends_with("_yaw"):
				v = e.y
			else:
				v = e.z
		else:
			v = float(_pose.get(key, 0.0))
		out.append({"group": d[0], "key": key, "label": d[2],
			"min": d[3], "max": d[4], "step": d[5],
			"value": rad_to_deg(v) if rad else v})
	return out


func set_joint(key: String, value: float) -> void:
	var is_rad := false
	var found := false
	for d in JOINT_DEFS:
		if d[1] == key:
			is_rad = int(d[6]) == 1
			found = true
			break
	if not found:
		return
	_playing = false
	_manual = true
	_pose[key] = value * D2R if is_rad else value
	var base := _arm_qbase(key)
	if base != "":
		var e := _joint_euler(key)
		if key.ends_with("_pitch"):
			e.x = float(_pose[key])
		elif key.ends_with("_yaw"):
			e.y = float(_pose[key])
		else:
			e.z = float(_pose[key])
		_pose[base + "_q"] = Basis.from_euler(e).get_rotation_quaternion()
	rig.apply_pose(_pose)
	_track_lens()


func get_joint(key: String) -> float:
	var is_rad := false
	for d in JOINT_DEFS:
		if d[1] == key:
			is_rad = int(d[6]) == 1
			break
	var base2 := _arm_qbase(key)
	var v := 0.0
	if base2 != "":
		var e2 := _joint_euler(key)
		if key.ends_with("_pitch"):
			v = e2.x
		elif key.ends_with("_yaw"):
			v = e2.y
		else:
			v = e2.z
	else:
		v = float(_pose.get(key, 0.0))
	return rad_to_deg(v) if is_rad else v


# ================================================================== planning stats

func set_block_threat(i: int) -> void:
	P["_threat"] = i
	anim.P["_threat"] = i
	anim._build_defend()
	if current_anim == "defend":
		_apply_now(_t)
		_update_fx(0.0)


func block_threat_id() -> int:
	return int(P.get("_threat", 0))


func block_plan_stats() -> Dictionary:
	var block: Dictionary = anim.action_key("defend", "block")
	var m := _measure_block(block)
	return {
		"effector": anim.defend_effector, "threat": block_threat_id(),
		"threat_name": "front-left 45" if block_threat_id() == 0 else "front-right 45",
		"plan_ms": anim.defend_ms, "total": anim.duration("defend"),
		"intercept_t": 0.45, "duration": 0.20, "hold": 0.74,
		"feasible": bool(m["blocked"]), "miss": float(m["miss"]),
		"block_point": m["point"], "blocked": bool(m["blocked"]),
		"min_clear": float(m["clear"]), "min_pair": m["pair"],
		"candidates": 49, "qdot": 0.0,
	}


func attack_plan_stats(which := "attack") -> Dictionary:
	var keys: Array = anim.attack_keys if which == "attack" else anim.attack_up_keys
	var worst := 99.0
	var wp := ["", ""]
	var tr: Array = anim.trajs.get(which, [])
	for s in tr:
		var a := kin.audit(s["pose"])
		if float(a["min"]) < worst:
			worst = float(a["min"])
			wp = a["pair"]
	var ms := anim.attack_ms if which == "attack" else anim.attack_up_ms
	var qd := anim.traj_qdot(which)
	return {"total": anim.duration(which), "plan_ms": ms, "mode": which,
		"min_clear": worst, "min_pair": wp, "qdot_max": qd,
		"keys": keys.size(), "reach_ok": true, "samples": tr.size()}


func _qdot(keys: Array) -> float:
	var best := 0.0
	for i in keys.size() - 1:
		var a: Dictionary = keys[i]["pose"]
		var b: Dictionary = keys[i + 1]["pose"]
		var dt := maxf(float(keys[i + 1]["t"]) - float(keys[i]["t"]), 1e-3)
		for k in a:
			if k.begins_with("_") or not b.has(k):
				continue
			if not (a[k] is float):
				continue
			var dv := absf(wrapf(float(b[k]) - float(a[k]), -PI, PI))
			best = maxf(best, dv / dt)
	return best


# ================================================================== evaluation

func _eval(t: float) -> Dictionary:
	return anim.sample(current_anim, t)


func _apply_now(t: float) -> void:
	_pose = _eval(t)
	rig.apply_pose(_pose)
	_track_lens()
	_update_anim_fx()


func _blend_pose(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	return ArcKin2.blend_pose(a, b, k)


func _track_lens() -> void:
	if float(P.get("lens_track", 1.0)) < 0.5:
		return
	# During the sword attacks the eye keeps its authored look direction; the
	# viewport-tracking aim could swing the barrel back into the rising arm.
	if current_anim == "attack" or current_anim == "attack_up":
		return
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
	if _camera == null:
		return
	var txf := kin.torso_xf(_pose)
	var lens_pos := Vector3(0.0, kin.cam_y, kin.cam_z - 0.020)
	var aim := ArcAnim2.lens_aim(txf, lens_pos, _camera.global_position)
	# Track with the ball housing itself; the barrel is rigidly attached.
	# Rotating the old nested lens nodes made the barrel sweep through the
	# ball/hull, which is what caused the visible fighting at the socket.
	rig.J["camera_yaw"].rotation = Vector3(aim.y, aim.x, 0)
	rig.J["lens_yaw"].rotation = Vector3.ZERO
	rig.J["lens_pitch"].rotation = Vector3.ZERO
	_pose["lens_yaw"] = 0.0
	_pose["lens_pitch"] = 0.0


func _update_anim_fx() -> void:
	var on := clampf(float(_pose.get("_blade_on", 1.0)), 0.0, 1.0)
	var intensity := float(P["blade_intensity"]) * on
	rig.set_blade_params(1.6 * intensity, P["arc_speed"], intensity)
	rig.set_lens_params(P["lens_intensity"], 0.0)
	rig.set_shield_params(P["shield_rings"], P["shield_opacity"], maxf(_impact, P["shield_impact"]))


func _measure_block(pose: Dictionary) -> Dictionary:
	var ps := kin.proxies(pose)
	var sh: Dictionary = {}
	var bl: Dictionary = {}
	for p in ps:
		if p["name"] == "shield":
			sh = p
		elif p["name"] == "blade":
			bl = p
	var chest := Vector3(0, 1.06, 0.05)
	var out := {"blocked": false, "miss": 9.0, "point": Vector3.ZERO, "clear": float(kin.audit(pose)["min"]), "pair": kin.audit(pose)["pair"]}
	if block_threat_id() == 0:
		var origin := chest + Vector3(1, 0, 1).normalized() * 0.62
		var dir := Vector3(-1, 0, -1).normalized()
		var c: Vector3 = sh["c"]
		var n: Vector3 = sh["n"]
		var denom := dir.dot(n)
		if absf(denom) > 1e-5:
			var s := (c - origin).dot(n) / denom
			var hit := origin + dir * s
			var radial := (hit - c).length()
			out["point"] = hit
			out["miss"] = maxf(radial - float(sh["r"]), 0.0)
			out["blocked"] = radial <= float(sh["r"]) and s > 0.0
	else:
		var origin2 := chest + Vector3(-1, 0, 1).normalized() * 0.62
		var dir2 := Vector3(1, 0, -1).normalized()
		var a: Vector3 = bl.get("a", Vector3.ZERO)
		var b: Vector3 = bl.get("b", Vector3.ZERO)
		var best := 9.0
		var bestp := Vector3.ZERO
		for i in 41:
			var p := origin2 + dir2 * (float(i) * 0.03)
			var d := ArcKin2.point_seg_dist(p, a, b)
			if d < best:
				best = d
				bestp = p
		out["point"] = bestp
		out["miss"] = maxf(best - 0.075, 0.0)
		out["blocked"] = best <= 0.075
	return out


# ================================================================== FX

func _build_fx() -> void:
	if _trail_mi:
		_trail_mi.queue_free()
	_trail_mi = MeshInstance3D.new()
	_trail_mi.name = "BladeTrail"
	_trail_mi.material_override = AM.trail()
	_trail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail_mi.top_level = true
	add_child(_trail_mi)


func _update_fx(dt: float) -> void:
	_fx_t += dt
	_impact = maxf(_impact - dt * 1.8, 0.0)
	rig.set_shield_impact(maxf(_impact, P["shield_impact"]))
	AM.shield().set_shader_parameter("seed", sin(_fx_t * 0.7) * 2.0)
	_update_trail(dt)


func _update_trail(_dt: float) -> void:
	if _trail_mi == null:
		return
	if not (current_anim in ["attack", "attack_up"]) or float(_pose.get("_blade_on", 1.0)) < 0.5:
		if _trail_mi.mesh != null:
			_trail_mi.mesh = null
		return
	var life := float(P["trail_life"])
	var n := 6
	var samples: Array = []
	var keep := _pose
	var t0: float = maxf(_t - life, 0.0)
	for i in n + 1:
		var tt := lerpf(t0, _t, float(i) / float(n))
		if tt >= _t:
			continue
		var p := _eval(tt)
		rig.apply_pose(p)
		var b := rig.marker_base.global_position
		var tp := rig.marker_tip.global_position
		samples.append({"b": b, "t": tp, "age": 1.0 - float(i) / float(n)})
	rig.apply_pose(keep)
	rig.marker_base.force_update_transform()
	rig.marker_tip.force_update_transform()
	if samples.size() < 2:
		_trail_mi.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var off := global_position
	for i in samples.size() - 1:
		var s0: Dictionary = samples[i]
		var s1: Dictionary = samples[i + 1]
		var pa0: Vector3 = (s0["b"] as Vector3) - off
		var pa1: Vector3 = (s0["t"] as Vector3) - off
		var pb0: Vector3 = (s1["b"] as Vector3) - off
		var pb1: Vector3 = (s1["t"] as Vector3) - off
		var a0 := pa0.lerp(pa1, 0.55)
		var a1 := pa1
		var b0 := pb0.lerp(pb1, 0.55)
		var b1 := pb1
		var age := float(s0["age"])
		var age1 := float(s1["age"])
		var c0 := Color(1.0, 0.32, 0.05, age * age * 0.05)
		var c1 := Color(1.0, 0.72, 0.42, age * age * 0.20)
		var c2 := Color(1.0, 0.72, 0.42, age1 * age1 * 0.20)
		var c3 := Color(1.0, 0.32, 0.05, age1 * age1 * 0.05)
		var u0 := float(i) / float(samples.size() - 1)
		var u1 := float(i + 1) / float(samples.size() - 1)
		_tri(st, a0, a1, b1, c0, c1, c2, Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 1))
		_tri(st, a0, b1, b0, c0, c2, c3, Vector2(u0, 0), Vector2(u1, 1), Vector2(u1, 0))
	_trail_mi.mesh = st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color,
		cc: Color, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var n := (b - a).cross(c - a).normalized()
	st.set_normal(n)
	st.set_color(ca)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(cb)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(cc)
	st.set_uv(uc)
	st.add_vertex(c)


# ================================================================== debug

func rig_debug() -> Dictionary:
	var d := {}
	d["anim"] = current_anim
	d["time"] = "%.3f / %.2f s" % [_t, anim_duration()]
	d["playing"] = _playing
	d["loop"] = _loop
	d["speed"] = "%.2f" % _speed
	d["hull radius"] = "%.3f m" % _radius_cache
	d["min clearance"] = "%.3f m (%s/%s)" % [_clear_cache, str(_clear_pair[0]), str(_clear_pair[1])]
	d["joints"] = "%d" % rig.J.size()
	d["attack plan"] = "%.0f / %.0f ms" % [anim.attack_ms, anim.attack_up_ms]
	d["block plan"] = "%.0f ms  effector=%s" % [anim.defend_ms, anim.defend_effector]
	d["blade"] = "on %.2f" % float(_pose.get("_blade_on", 1.0))
	if _queued != "":
		d["queued"] = _queued
	d["blade tip"] = _fmt_v(rig.marker_tip.global_position)
	d["shield"] = _fmt_v(rig.shield_node.global_position)
	if current_anim == "defend":
		var st := block_plan_stats()
		d["block hit"] = "%.3f m miss  %s" % [float(st["miss"]), str(st["blocked"])]
	return d


func _fmt_v(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


## Debug telemetry used to be refreshed by a periodic full-vertex radius scan
## and collision audit; that caused a visible hitch every ~0.6 s (and the arc
## sword's short-lived bolts all expired during the stall, exposing the old
## blade core).  The radius is now measured once per rig build, and clearance
## once per clip change, so the render loop does no periodic heavy work.
func _refresh_clearance() -> void:
	if rig == null:
		return
	var a := kin.audit(_pose)
	_clear_cache = float(a["min"])
	_clear_pair = a["pair"]


# ================================================================== rebuild

func _rebuild() -> void:
	var keep_t := _t
	var keep_anim := current_anim
	var keep_playing := _playing
	rig.build(P)
	_radius_cache = rig.measure_radius()
	kin = rig.kin
	anim = ANIM.new(kin, P)
	anim.build()
	current_anim = keep_anim if keep_anim in ANIMS else "idle"
	_t = keep_t
	_playing = keep_playing
	_pose = _eval(_t)
	rig.apply_pose(_pose)
	_refresh_clearance()
	_track_lens()
	_update_anim_fx()
	_build_fx()