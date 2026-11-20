extends Node3D
## VESPER v2 — procedural blue-white four-legged assault frame.
##
## Generated 100% from code: meshes, materials, rig, motion.  No imported assets
## and no AnimationPlayer keyframes.  Every pose is a closed-form function of
## time, velocity, gait phase and combat timeline.
##
## v2 changes
##   * 2.00 m tall (real metres), compact 0.5 m stance radius, legs near-straight
##     at rest (knee interior ~137 deg instead of 90 deg)
##   * blue/white all-metal surfaces, black asymmetric mask with one blue camera
##   * medieval flat plasma greatsword with an energy crossguard
##   * gimballed vector thruster backpack, forward / lateral dashes
##   * bone-chain + SpringBoneSimulator3D hair (blue/white, wind + motion)
##   * four front attacks (mirrored pair + mirrored risers), side thrust,
##     back thrust, overhead heavy, 360-degree spin
##
## Locomotion: analytic gait clock + two-bone leg IK (law of cosines)
## Combat:     weapon-space pose keys, two-bone arm IK solved every frame so
##             both fists track the hilt, 360-degree waist spin, blade ribbons.

const MK = preload("res://scripts/mech/mesh_kit.gd")
const MAT = preload("res://scripts/mech/materials.gd")
const BB = preload("res://scripts/mech/body_builder.gd")
const Trail = preload("res://scripts/mech/blade_trail.gd")
const FX = preload("res://scripts/world/fx.gd")

signal footstep(world_pos: Vector3, strength: float)
signal impact(world_pos: Vector3, strength: float)
signal attack_started(label: String, heavy: bool)

# ---------------------------------------------------------------- proportions
# Source of truth: body_builder.gd P.  Kept here as typed constants for the
# animation maths (all metres).
const HIP_Y := 1.235
const HIP_R := 0.30
const FEMUR := 0.60
const TIBIA := 0.66
const FOOT_R := 0.50
const ANKLE_H := 0.08
const WAIST_Y := 0.12
const TORSO_SCALE := 0.82
const UPPER := 0.42
const FORE := 0.38
const GRIP := 0.10
const BLADE_Y0 := 0.28
const BLADE_LEN := 1.25

const WALK_SPEED := 2.2
const RUN_SPEED := 5.6
const SPRINT_SPEED := 7.6
const TAU := PI * 2.0
const GRAVITY := 18.0
const JUMP_SPEED := 6.3
const TAKEOFF_TIME := 0.20
const LAND_TIME := 0.58

const LEG_AZ := [45.0, 135.0, 225.0, 315.0]

const BASE_POSE := {
	"ty": -0.10, "tx": 0.0, "tz": 0.0, "hy": 0.04, "hx": -0.02,
	"crouch": 0.0, "lean": 0.0, "offhand": 0.0, "left_raise": 0.0,
	"wpx": 0.20, "wpy": 0.20, "wpz": -0.40,
	"wrx": -0.05, "wry": 0.0, "wrz": 0.10,
}

# ---------------------------------------------------------------- public state
var move_command := Vector3.ZERO       # desired world-space velocity (XZ)
var speed := 0.0
var display_speed := 0.0
var heading := 0.0
var angular_velocity := 0.0
var gait_phase := 0.0
var locomotion_state := "IDLE"
var attack_name := ""
var combo_step := 0
var is_attacking := false
var attack_time := 0.0
var dash_time := 0.0
var jump_state := "GROUND"
var jump_t := 0.0
var vertical_velocity := 0.0
var air_time := 0.0
var time := 0.0
var auto_step := true
var vfx_root: Node3D

# ---------------------------------------------------------------- node refs
var body: Node3D
var torso: Node3D
var head: Node3D
var reactor_ring: Node3D
var chest_light: OmniLight3D
var weapon_root: Node3D
var weapon_spin: Node3D
var weapon_light: OmniLight3D
var blade_base: Marker3D
var blade_tip: Marker3D
var blade_trail
var contact_shadow: MeshInstance3D
var legs: Array = []
var arms: Array = []
var pauldrons: Array = []
var thruster_nodes: Array = []
var left_indicator_meshes: Array = []
var hair
var hair_anchor: Node3D

var _attack: Dictionary = {}
var _attack_queue: Array = []
var _clips: Dictionary = {}
var _dash_dir := Vector3.FORWARD
var _dash_cooldown := 0.0
var _yaw_rate := 0.0
var _shake_sent := {}
var _lunge_prev := 0.0
var _carry_w := 0.0
var _fx: Node3D
var _attack_style := "twohand"
var _onehand := 0.0
var _left_raise := 0.0

# actdemo-facing knobs kept at defaults so the same rig can be vendored later
var jump_vel := JUMP_SPEED
var grav := GRAVITY
var takeoff_time := TAKEOFF_TIME
var land_time := LAND_TIME
var dash_distance := 2.0
var dash_duration := 0.28
var dash_cd := 0.50
var accel_rate := 18.0
var decel_rate := 26.0
var turn_rate := 12.0
var facing_override := false
var facing_heading := 0.0
var face_rate := 7.0
var vfx_enabled := true

func _ready() -> void:
	_fx = FX.new()
	_fx.name = "FX"
	_fx.top_level = true
	add_child(_fx)
	_fx.global_transform = Transform3D.IDENTITY
	vfx_root = _fx
	_clips = _load_clips()
	BB.build(self)
	_build_hair()
	blade_trail = Trail.new()
	blade_trail.name = "GreatswordTrail"
	_fx.add_child(blade_trail)
	heading = rotation.y
	_update_legs(1.0 / 60.0, 0.0)
	_update_arms(BASE_POSE)
	_update_thrusters(0.0)
	if auto_step:
		set_process(true)


func _process(delta: float) -> void:
	if auto_step:
		advance(minf(delta, 0.05))


func _load_clips() -> Dictionary:
	var out := {}
	var ad = load("res://scripts/mech/attack_data.gd")
	if ad == null:
		push_error("attack_data.gd missing")
		return out
	for n in ["FRONT_R", "FRONT_L", "RISE_R", "RISE_L",
			"SIDE_THRUST_R", "BACK_THRUST", "HEAVY", "SPIN"]:
		var c: Dictionary = ad.get_clip(n)
		out[String(c["name"])] = c
	return out


func _build_hair() -> void:
	var hair_script = load("res://scripts/mech/hair.gd")
	if hair_script == null:
		return
	hair = hair_script.new()
	hair.name = "Hair"
	var parent: Node3D = hair_anchor if hair_anchor != null else head
	parent.add_child(hair)
	hair.setup(head, {})


# ============================================================== attack input
func request_light_attack() -> void:
	if jump_state != "GROUND":
		return
	if is_attacking:
		if combo_step < 4 and _attack_queue.is_empty():
			_attack_queue.append(combo_step + 1)
		return
	combo_step = 1
	_begin_attack(_clip("FRONT_R"), false)


## QA / demo helper: start a specific front attack (1..4).
func request_front_attack(index: int) -> void:
	if jump_state != "GROUND" or is_attacking:
		return
	var names := ["FRONT_R", "FRONT_L", "RISE_R", "RISE_L"]
	combo_step = clampi(index, 1, 4)
	_begin_attack(_clip(names[combo_step - 1]), false)


func request_side_attack(side := 1.0) -> void:
	if jump_state != "GROUND" or is_attacking:
		return
	combo_step = 0
	var c := _clip("SIDE_THRUST_R")
	_begin_attack(c, false)


func request_back_attack() -> void:
	if jump_state != "GROUND" or is_attacking:
		return
	combo_step = 0
	_begin_attack(_clip("BACK_THRUST"), true)


func request_heavy_attack() -> void:
	if jump_state != "GROUND" or is_attacking:
		return
	combo_step = 0
	_begin_attack(_clip("HEAVY"), true)


func request_spin_attack() -> void:
	if jump_state != "GROUND" or is_attacking:
		return
	combo_step = 0
	_begin_attack(_clip("SPIN"), true)


## local_dir is in the character's local space; default = forward (-Z).
func request_dash(local_dir := Vector3(0, 0, -1)) -> void:
	if jump_state != "GROUND" or _dash_cooldown > 0.0 or is_attacking:
		return
	var d := local_dir
	if d.length_squared() < 0.001:
		d = Vector3(0, 0, -1)
	_dash_dir = (global_transform.basis * d.normalized())
	_dash_dir.y = 0.0
	_dash_dir = _dash_dir.normalized()
	dash_time = dash_duration
	_dash_cooldown = dash_cd
	impact.emit(global_position + Vector3(0, 0.2, 0), 0.2)


func request_jump() -> void:
	if jump_state != "GROUND" or is_attacking or dash_time > 0.0:
		return
	jump_state = "TAKEOFF"
	jump_t = 0.0
	vertical_velocity = 0.0
	air_time = 0.0


func _clip(n: String) -> Dictionary:
	if _clips.has(n):
		return _clips[n]
	# fallback so a missing data file never hard-crashes
	return {
		"name": n, "duration": 0.8, "trail": [0.18, 0.44],
		"keys": [{"t": 0.0, "p": {}}, {"t": 0.8, "p": {}}],
		"lunge": [[0.0, 0.0], [0.8, 0.5]], "hit_at": 0.32,
		"hit_kind": "air", "style": "twohand",
	}


func _advance_jump(dt: float) -> void:
	match jump_state:
		"TAKEOFF":
			jump_t += dt
			if jump_t >= takeoff_time:
				jump_state = "AIR"
				jump_t = 0.0
				vertical_velocity = jump_vel
				air_time = 0.0
				_fx.footstep(global_position, 0.45)
		"AIR":
			air_time += dt
			vertical_velocity -= grav * dt
			position.y += vertical_velocity * dt
			if position.y <= 0.0 and vertical_velocity < 0.0:
				position.y = 0.0
				jump_state = "LANDING"
				jump_t = 0.0
				vertical_velocity = 0.0
				_fx.land(global_position, 1.0)
				impact.emit(global_position + Vector3(0, 0.12, 0), 0.75)
		"LANDING":
			jump_t += dt
			if jump_t >= land_time:
				jump_state = "GROUND"
				jump_t = 0.0


func _begin_attack(data: Dictionary, heavy: bool) -> void:
	_attack = data
	is_attacking = true
	attack_name = String(data["name"])
	attack_time = 0.0
	_attack_style = String(data.get("style", "twohand"))
	_onehand = 1.0 if _attack_style in ["side_r", "back_r"] else 0.0
	_left_raise = 1.0 if _attack_style in ["side_r", "back_r"] else 0.0
	_lunge_prev = 0.0
	_shake_sent.clear()
	attack_started.emit(attack_name, heavy)
	var tw: Array = data.get("trail", [0.0, 1.0])
	if blade_trail != null:
		blade_trail.begin(self, blade_base, blade_tip, tw[0], tw[1])


func advance(dt: float) -> void:
	dt = clampf(dt, 0.0, 0.05)
	var start_pos := position
	time += dt
	_dash_cooldown = maxf(0.0, _dash_cooldown - dt)
	_advance_jump(dt)

	# ---------------- locomotion
	var moving := move_command.length() > 0.05
	var target_speed := move_command.length()
	if is_attacking:
		target_speed *= 0.10
		moving = false
	if dash_time > 0.0:
		target_speed = 0.0
		moving = false
	var accel := accel_rate if speed < target_speed else decel_rate
	speed = move_toward(speed, target_speed, accel * dt)
	if dash_time > 0.0:
		speed = 0.0

	if moving:
		var desired := move_command.normalized()
		var target_heading := atan2(-desired.x, -desired.z)
		if facing_override:
			target_heading = facing_heading
		var turn_speed := lerpf(turn_rate * 0.42, turn_rate, clampf(speed / RUN_SPEED, 0.0, 1.0))
		if facing_override:
			turn_speed = face_rate
		var before := heading
		heading = lerp_angle(heading, target_heading, 1.0 - exp(-turn_speed * dt))
		angular_velocity = wrapf(heading - before, -PI, PI) / maxf(dt, 0.0001)
	else:
		if facing_override:
			var before_f := heading
			heading = lerp_angle(heading, facing_heading, 1.0 - exp(-face_rate * dt))
			angular_velocity = wrapf(heading - before_f, -PI, PI) / maxf(dt, 0.0001)
		else:
			angular_velocity = lerpf(angular_velocity, 0.0, 1.0 - exp(-8.0 * dt))
	rotation.y = heading
	_yaw_rate = lerpf(_yaw_rate, angular_velocity, 1.0 - exp(-6.0 * dt))

	var forward := -global_transform.basis.z
	var vel := forward * speed
	if is_attacking and _attack.has("lunge"):
		var lunge := _eval_curve(_attack["lunge"], attack_time)
		var d := lunge - _lunge_prev
		_lunge_prev = lunge
		position += forward * d
		vel += forward * (d / maxf(dt, 0.0001))
	if dash_time > 0.0:
		var dash_t := 1.0 - dash_time / maxf(dash_duration, 0.01)
		# integral of the old curve is ~9.92; convert distance to a scale
		var dash_speed := (18.0 * pow(1.0 - dash_t, 1.6) + 3.0) \
			* (dash_distance / maxf(9.923 * dash_duration, 0.001))
		# direction is fixed for the whole dash: forward and lateral dashes are
		# distinct authored inputs, not a steering blend.
		var dash_step := minf(dt, dash_time)
		position += _dash_dir * dash_speed * dash_step
		dash_time = maxf(0.0, dash_time - dash_step)
	if not is_attacking:
		position += vel * dt

	var flat := Vector2(position.x, position.z)
	if flat.length() > 15.0:
		flat = flat.normalized() * 15.0
		position.x = flat.x
		position.z = flat.y

	# ---------------- gait clock
	var run_amt := clampf((speed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)
	var freq := lerpf(1.55, 2.75, clampf(speed / RUN_SPEED, 0.0, 1.0))
	if speed > 0.08 and jump_state != "AIR" and jump_state != "LANDING":
		gait_phase = fmod(gait_phase + freq * dt, 1.0)
	locomotion_state = "IDLE"
	if speed > 0.4:
		locomotion_state = "WALK"
	if speed > WALK_SPEED:
		locomotion_state = "RUN"
	if speed > RUN_SPEED + 0.4:
		locomotion_state = "SPRINT"
	if is_attacking:
		locomotion_state = "STRIKE"
	if dash_time > 0.0:
		locomotion_state = "DASH"
	if jump_state == "TAKEOFF":
		locomotion_state = "JUMP"
	elif jump_state == "AIR":
		locomotion_state = "AIRBORNE"
	elif jump_state == "LANDING":
		locomotion_state = "LANDING"

	# ---------------- attack timeline
	if is_attacking:
		attack_time += dt
		if not _attack_queue.is_empty() and attack_time >= float(_attack["duration"]) * 0.70:
			var nxt: int = _attack_queue.pop_front()
			combo_step = nxt
			var names := ["", "FRONT_R", "FRONT_L", "RISE_R", "RISE_L"]
			_begin_attack(_clip(names[nxt]), false)
		elif attack_time >= float(_attack["duration"]):
			is_attacking = false
			attack_name = ""
			combo_step = 0
			_attack_queue.clear()
			_lunge_prev = 0.0
			_attack_style = "twohand"
			_onehand = 0.0
			_left_raise = 0.0

	# ---------------- body mechanics
	var lean_speed := clampf(speed / RUN_SPEED, 0.0, 1.2) * 0.17
	var bob_amp := lerpf(0.006, 0.026, run_amt) * clampf(speed / 1.2, 0.0, 1.0)
	var bob := sin((gait_phase * 2.0 + 0.13) * TAU) * bob_amp
	if speed < 0.4:
		bob = sin(time * 1.35) * 0.007
	if jump_state == "AIR" or jump_state == "LANDING":
		bob = 0.0
	var stance_count := 0
	for leg in legs:
		if leg["down"]:
			stance_count += 1
	if jump_state != "AIR" and jump_state != "LANDING":
		bob += (1.0 - clampf(stance_count / 4.0, 0.0, 1.0)) * lerpf(0.006, 0.020, run_amt)
	var bank := clampf(_yaw_rate * speed * 0.020, -0.24, 0.24)
	var sway := sin(gait_phase * TAU) * lerpf(0.004, 0.010, run_amt)

	var carry_target := smoothstep(0.0, 1.0, clampf((speed - 0.5) / 2.0, 0.0, 1.0))
	_carry_w = lerpf(_carry_w, carry_target, 1.0 - exp(-3.2 * dt))
	var pose := _current_pose(dt)
	var body_y := HIP_Y - float(pose["crouch"]) + bob
	if dash_time > 0.0:
		var dt_n := 1.0 - dash_time / maxf(dash_duration, 0.01)
		body_y -= 0.10 * sin(PI * clampf(dt_n, 0.0, 1.0))
	body.position = Vector3(0, body_y, 0)
	body.rotation = Vector3(-(lean_speed + float(pose["lean"])), sway, bank)
	torso.rotation = Vector3(pose["tx"], pose["ty"], pose["tz"])
	head.rotation = Vector3(pose["hx"], pose["hy"], 0)
	_update_weapon(pose)
	_update_arms(pose)
	if contact_shadow != null:
		contact_shadow.position.y = 0.012 - position.y
		var hgt := maxf(position.y, 0.0)
		var sh_scale := 1.0 + hgt * 0.14
		contact_shadow.scale = Vector3(sh_scale, 1.0, sh_scale)
		contact_shadow.transparency = clampf(hgt * 0.16, 0.0, 0.55)

	# head look / idle life
	if not is_attacking:
		var look := clampf(_yaw_rate * 0.16, -0.22, 0.22)
		head.rotation.y = lerpf(head.rotation.y, look + sin(time * 0.7) * 0.035, 1.0 - exp(-4.0 * dt))
		head.rotation.x += sin(time * 0.9 + 1.0) * 0.010

	if reactor_ring != null:
		reactor_ring.rotation.y += dt * lerpf(0.25, 2.4, clampf(speed / RUN_SPEED, 0.0, 1.0))
		reactor_ring.rotation.x = sin(time * 0.6) * 0.05

	_update_legs(dt, run_amt)
	_update_thrusters(dt)
	_update_indicators(dt)
	if hair != null:
		hair.update(dt, self)
	_update_trail(dt)
	_update_fx(dt)
	_fx.advance(dt)
	var moved := position.distance_to(start_pos)
	display_speed = lerpf(display_speed, moved / maxf(dt, 0.0001), 0.55)


func dash_direction_is_forward() -> bool:
	var f := -global_transform.basis.z
	f.y = 0.0
	return _dash_dir.dot(f.normalized()) > 0.75


func _current_pose(dt: float) -> Dictionary:
	var pose := BASE_POSE.duplicate()
	var breath := sin(time * 1.25)
	pose["tx"] = float(pose["tx"]) + breath * 0.010
	pose["wpx"] = float(pose["wpx"]) + sin(time * 0.8) * 0.004
	pose["wrx"] = float(pose["wrx"]) + sin(time * 1.05) * 0.014
	pose["wrz"] = float(pose["wrz"]) + sin(time * 0.9) * 0.010
	if _carry_w > 0.01 and not is_attacking:
		var w := clampf(_carry_w, 0.0, 1.0)
		pose["wpx"] = lerpf(0.20, 0.18, w)
		pose["wpy"] = lerpf(0.20, 0.25, w) + sin(gait_phase * TAU) * 0.012 * w
		pose["wpz"] = lerpf(-0.40, -0.44, w)
		pose["wrx"] = lerpf(-0.05, 0.10, w)
		pose["wry"] = lerpf(0.0, -0.10, w)
		pose["wrz"] = lerpf(0.10, 0.02, w)
		pose["ty"] = float(pose["ty"]) + sin(gait_phase * TAU) * 0.05 * w
		pose["tx"] = float(pose["tx"]) + 0.04 * w
	if dash_time > 0.0:
		var t := 1.0 - dash_time / maxf(dash_duration, 0.01)
		pose["wrx"] = lerpf(-1.10, -0.90, sin(PI * t))
		pose["wpz"] = float(pose["wpz"]) - 0.06
		pose["lean"] = float(pose["lean"]) + 0.10 * sin(PI * t)
	if jump_state == "TAKEOFF":
		var u := clampf(jump_t / maxf(takeoff_time, 0.001), 0.0, 1.0)
		var c := sin(PI * u)
		pose["crouch"] = float(pose["crouch"]) + 0.34 * c
		pose["tx"] = float(pose["tx"]) - 0.12 * c
		pose["lean"] = float(pose["lean"]) + 0.06 * c
		pose["wpy"] = float(pose["wpy"]) - 0.10 * c
		pose["wpz"] = float(pose["wpz"]) - 0.03 * c
	elif jump_state == "AIR":
		var fall := clampf(-vertical_velocity / 6.0, 0.0, 1.0)
		pose["crouch"] = -0.02
		pose["tx"] = 0.09 * clampf(vertical_velocity / 6.0, -1.0, 1.0)
		pose["ty"] = -0.06
		pose["hy"] = 0.02
		pose["wpx"] = 0.16
		pose["wpy"] = 0.26 + 0.02 * sin(air_time * 5.0)
		pose["wpz"] = -0.42
		pose["wrx"] = -1.05 + 0.18 * fall
		pose["wry"] = 0.06
		pose["wrz"] = 0.16
		pose["lean"] = 0.03
	elif jump_state == "LANDING":
		var u2 := clampf(jump_t / maxf(land_time, 0.001), 0.0, 1.0)
		var c2 := 1.0 - smoothstep(0.0, 1.0, u2)
		pose["crouch"] = float(pose["crouch"]) + 0.30 * c2
		pose["tx"] = float(pose["tx"]) - 0.26 * c2
		pose["lean"] = float(pose["lean"]) + 0.09 * c2
		pose["wpx"] = lerpf(0.16, 0.20, u2)
		pose["wpy"] = lerpf(0.26, 0.20, u2)
		pose["wpz"] = lerpf(-0.42, -0.40, u2)
		pose["wrx"] = lerpf(-1.05, -0.05, u2)
		pose["wry"] = lerpf(0.06, 0.0, u2)
		pose["wrz"] = lerpf(0.16, 0.10, u2)
	if is_attacking:
		var kp := _evaluate_keys(attack_time)
		for k in kp.keys():
			pose[k] = kp[k]
		_apply_attack_overrides(pose, attack_time)
	# release weights blend in/out so one-hand attacks do not pop
	pose["offhand"] = float(pose.get("offhand", 0.0)) if is_attacking else 0.0
	pose["left_raise"] = float(pose.get("left_raise", 0.0)) if is_attacking else 0.0
	return pose


## Extra pose channels driven by the attack phase rather than keyframes.
func _apply_attack_overrides(pose: Dictionary, t: float) -> void:
	var st := _attack_style
	if st == "spin":
		var dur := float(_attack.get("duration", 1.58))
		var t0 := dur * 0.16
		var t1 := dur * 0.74
		var su := clampf((t - t0) / maxf(t1 - t0, 0.001), 0.0, 1.0)
		pose["ty"] = lerpf(-0.55, TAU - 0.35, _spin_progress(su))
	if st in ["side_r", "back_r"]:
		# The clip keys already drive the one-hand reach (side: +X, back: left
		# rear).  Only the release weights are procedural here.
		pose["offhand"] = 1.0
		pose["left_raise"] = 1.0


func _evaluate_keys(t: float) -> Dictionary:
	if _attack.is_empty():
		return BASE_POSE.duplicate()
	var keys: Array = _attack.get("keys", [])
	if keys.is_empty():
		return BASE_POSE.duplicate()
	var a: Dictionary = keys[0]
	var b: Dictionary = keys[0]
	for i in keys.size() - 1:
		if t >= float(keys[i]["t"]) and t <= float(keys[i + 1]["t"]):
			a = keys[i]
			b = keys[i + 1]
			break
	var span: float = maxf(float(b["t"]) - float(a["t"]), 0.0001)
	var u: float = clampf((t - float(a["t"])) / span, 0.0, 1.0)
	u = u * u * u * (u * (u * 6.0 - 15.0) + 10.0)
	var out := {}
	var pa: Dictionary = BASE_POSE.duplicate()
	var pb: Dictionary = BASE_POSE.duplicate()
	pa.merge(a.get("p", {}), true)
	pb.merge(b.get("p", {}), true)
	for key in pa.keys():
		out[key] = lerpf(float(pa[key]), float(pb[key]), u)
	return out


func preview_weapon_pose(override: Dictionary) -> void:
	var pose := BASE_POSE.duplicate()
	for k in override.keys():
		pose[k] = override[k]
	torso.rotation = Vector3(float(pose["tx"]), float(pose["ty"]), float(pose["tz"]))
	_update_weapon(pose)
	_update_arms(pose)


func _update_weapon(pose: Dictionary) -> void:
	if weapon_root == null:
		return
	var wz := float(pose["wpz"])
	# front/two-hand swings must keep the hilt in front of the chest; the
	# one-hand side/back thrusts are allowed to pass beside/behind the body.
	if not (_attack_style in ["side_r", "back_r"]):
		wz = minf(wz, -0.34)
	weapon_root.position = Vector3(float(pose["wpx"]), float(pose["wpy"]), wz)
	weapon_root.rotation = Vector3(float(pose["wrx"]), float(pose["wry"]), float(pose["wrz"]))


func _update_arms(pose: Dictionary) -> void:
	if weapon_root == null or arms.size() < 2:
		return
	var hilt_y := weapon_root.basis.y.normalized()
	var hilt_x := weapon_spin.basis.x.normalized()
	var grip_r: Vector3 = weapon_root.transform * Vector3(0, GRIP, 0)
	var grip_l: Vector3 = weapon_root.transform * Vector3(0, -GRIP, 0)
	_solve_arm(arms[0], grip_r, hilt_y, hilt_x)
	var offhand := clampf(float(pose.get("offhand", 0.0)), 0.0, 1.0)
	var target_l := grip_l
	if offhand > 0.01:
		var sh: Vector3 = arms[1]["shoulder"].position
		var low := sh + Vector3(-0.12, -0.52, 0.06)
		var high := sh + Vector3(-0.24, 0.22, 0.10)
		var rest: Vector3 = low.lerp(high, clampf(float(pose.get("left_raise", 0.0)), 0.0, 1.0))
		target_l = grip_l.lerp(rest, offhand)
	_solve_arm(arms[1], target_l, hilt_y, hilt_x)


func _solve_arm(arm: Dictionary, target: Vector3, hilt_y: Vector3, hilt_x: Vector3) -> void:
	var shoulder: Node3D = arm["shoulder"]
	var elbow: Node3D = arm["elbow"]
	var wrist: Node3D = arm["wrist"]
	var side: float = arm["side"]
	var upper: float = arm["upper"]
	var fore: float = arm["fore"]
	var S := shoulder.position
	var delta := target - S
	var dist := clampf(delta.length(), 0.10, upper + fore - 0.006)
	var dir := delta.normalized()
	var pole := Vector3(side * 1.0, -0.15, 0.72)
	var perp := pole - dir * pole.dot(dir)
	if perp.length_squared() < 0.001:
		perp = Vector3(side, 0, 0)
	perp = perp.normalized()
	var a := (upper * upper - fore * fore + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(upper * upper - a * a, 0.0))
	var elbow_pos := S + dir * a + perp * h
	var Teff := S + dir * dist
	var up_dir := (elbow_pos - S).normalized()
	var fore_dir := (Teff - elbow_pos).normalized()
	var x_axis := up_dir.cross(fore_dir)
	if x_axis.length_squared() < 0.0001:
		x_axis = perp
	x_axis = x_axis.normalized()
	var y_axis := -up_dir
	var z_axis := x_axis.cross(y_axis).normalized()
	x_axis = y_axis.cross(z_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis)
	shoulder.basis = basis
	var ang := acos(clampf(up_dir.dot(fore_dir), -1.0, 1.0))
	elbow.rotation = Vector3(ang, 0.0, 0.0)
	var parent_basis := basis * elbow.transform.basis
	var hy := hilt_y.normalized()
	var hx := hilt_x - hy * hilt_x.dot(hy)
	if hx.length_squared() < 0.0001:
		hx = x_axis
	hx = hx.normalized()
	var hz := hx.cross(hy).normalized()
	hx = hy.cross(hz).normalized()
	var target_basis := Basis(hx, hy, hz)
	wrist.basis = parent_basis.inverse() * target_basis


# --------------------------------------------------------------------- legs
func _leg_phase_offset(index: int, run_amt: float) -> float:
	var wave := [0.0, 0.25, 0.5, 0.75]
	var trot := [0.0, 0.5, 0.0, 0.5]
	return lerpf(wave[index], trot[index], smoothstep(0.0, 1.0, run_amt))


func _update_legs(dt: float, run_amt: float) -> void:
	var duty := lerpf(0.68, 0.44, smoothstep(0.0, 1.0, run_amt))
	var freq := lerpf(1.55, 2.75, clampf(speed / RUN_SPEED, 0.0, 1.0))
	var stride := 0.0
	if speed > 0.08:
		stride = speed * duty / freq
	stride = minf(stride, 0.55)
	var lift_amt := lerpf(0.07, 0.22, smoothstep(0.0, 1.0, run_amt))
	var gait_w := clampf(speed / 1.0, 0.0, 1.0)
	var body_inv := body.transform.affine_inverse()

	for i in 4:
		var leg: Dictionary = legs[i]
		if jump_state == "AIR":
			var fall := clampf(-vertical_velocity / 6.0, 0.0, 1.0)
			var tuck := smoothstep(0.0, 0.20, air_time) * (1.0 - 0.85 * fall)
			var rr := lerpf(FOOT_R, 0.33, tuck)
			var yy := lerpf(ANKLE_H - HIP_Y, -0.62, tuck)
			var wob := sin(air_time * 4.5 + i * 1.7) * 0.02 * tuck
			var az: float = float(leg["az"])
			var target_body := Vector3(cos(az) * (rr + wob), yy, sin(az) * (rr + wob))
			_solve_leg_ik(leg, target_body, dt, 0.24 + 0.14 * fall)
			leg["down"] = false
			leg["phase"] = 0.0
			continue
		var off := _leg_phase_offset(i, run_amt)
		var q := fmod(gait_phase + off, 1.0)
		var foot := Vector3(cos(leg["az"]) * FOOT_R, ANKLE_H, sin(leg["az"]) * FOOT_R)
		var down := true
		var lift := 0.0
		var radial := 0.0
		if speed > 0.08:
			if q < duty:
				var ts := q / duty
				var s := lerpf(stride * 0.5, -stride * 0.5, ts)
				foot.z -= s
			else:
				var ts := (q - duty) / (1.0 - duty)
				var s := lerpf(-stride * 0.5, stride * 0.5, smoothstep(0.0, 1.0, ts))
				s += sin(PI * ts) * lerpf(0.01, 0.04, run_amt)
				foot.z -= s
				lift = sin(PI * ts) * lift_amt
				radial = -sin(PI * ts) * lerpf(0.02, 0.06, run_amt)
				down = false
		if gait_w < 0.99:
			var idle_w := 1.0 - gait_w
			var ph := time * 0.55 + i * 1.7
			foot.x += cos(ph) * 0.006 * idle_w
			foot.z += sin(ph) * 0.006 * idle_w
		if dash_time > 0.0:
			var d := 1.0 - dash_time / maxf(dash_duration, 0.01)
			var tuck := sin(PI * clampf(d, 0.0, 1.0))
			foot.z += tuck * 0.10
			foot.x *= (1.0 - tuck * 0.10)
			lift = maxf(lift, tuck * 0.16)
			down = false
		var radial_dir := Vector3(cos(leg["az"]), 0, sin(leg["az"]))
		foot += radial_dir * radial
		foot.y = ANKLE_H + lift
		if down and not bool(leg["down"]) and speed > 0.4:
			var wp := global_transform * Vector3(foot.x, 0.02, foot.z)
			footstep.emit(wp, clampf(speed / RUN_SPEED, 0.2, 1.0))
			if i >= 2:
				_fx.footstep(wp, clampf(speed / RUN_SPEED, 0.2, 1.0) * 0.7)
		leg["down"] = down
		leg["phase"] = q
		leg["target"] = foot

		var target := body_inv * foot
		var foot_pitch := 0.0
		if not down:
			var ts := clampf((q - duty) / maxf(1.0 - duty, 0.001), 0.0, 1.0)
			foot_pitch = sin(PI * ts) * lerpf(0.10, 0.30, run_amt)
		_solve_leg_ik(leg, target, dt, foot_pitch)


func _solve_leg_ik(leg: Dictionary, target: Vector3, dt: float, foot_pitch: float) -> void:
	var hip_pos: Vector3 = leg["root"].position
	var v := target - hip_pos
	var d := Vector2(v.x, v.z).length()
	var h := v.y
	d = maxf(d, 0.02)
	var reach := sqrt(d * d + h * h)
	var max_reach := FEMUR + TIBIA - 0.008
	if reach > max_reach:
		var k := max_reach / reach
		d *= k
		h *= k
		reach = max_reach
	var base := atan2(h, d)
	var cos_a := (FEMUR * FEMUR + reach * reach - TIBIA * TIBIA) / (2.0 * FEMUR * reach)
	var aa := acos(clampf(cos_a, -1.0, 1.0))
	var femur_angle := base + aa
	var cos_b := (FEMUR * FEMUR + TIBIA * TIBIA - reach * reach) / (2.0 * FEMUR * TIBIA)
	var bb := acos(clampf(cos_b, -1.0, 1.0))
	var knee_angle := -(PI - bb)
	var yaw_angle: float = atan2(-v.z, v.x) + float(leg["az"])
	leg["yaw"].rotation.y = lerp_angle(leg["yaw"].rotation.y, yaw_angle, 1.0 - exp(-28.0 * dt))
	leg["hip"].rotation.z = femur_angle
	leg["knee"].rotation.z = knee_angle
	leg["ankle"].rotation.z = -(femur_angle + knee_angle) + foot_pitch
	leg["ankle"].rotation.x = clampf(_yaw_rate * 0.08, -0.12, 0.12)


# ------------------------------------------------------------------ visuals
func _update_thrusters(dt: float) -> void:
	var boost := 0.0
	if dash_time > 0.0:
		boost = 1.0 - dash_time / maxf(dash_duration, 0.01)
		boost = sin(PI * clampf(boost, 0.0, 1.0))
	if is_attacking and _attack_style == "spin":
		boost = maxf(boost, 0.35)
	var local := global_transform.basis.inverse() * _dash_dir
	for n in thruster_nodes:
		if not is_instance_valid(n):
			continue
		var target_yaw := clampf(atan2(local.x, local.z) * 0.55, -0.6, 0.6) * boost
		var target_pitch := clampf(-local.y * 0.4, -0.3, 0.3) * boost
		n.rotation.y = lerpf(n.rotation.y, target_yaw, 1.0 - exp(-10.0 * dt))
		n.rotation.x = lerpf(n.rotation.x, target_pitch, 1.0 - exp(-10.0 * dt))
		var flame = n.get_node_or_null("flame")
		if flame is MeshInstance3D:
			flame.visible = boost > 0.03
			var s := 0.12 + 2.2 * boost
			flame.scale = Vector3(0.75 + 0.35 * boost, 0.75 + 0.35 * boost, s)


func _update_indicators(dt: float) -> void:
	var pulse := 0.75 + 0.25 * sin(time * 3.4)
	for i in left_indicator_meshes.size():
		var mi = left_indicator_meshes[i]
		if not is_instance_valid(mi):
			continue
		var p := pulse if i != left_indicator_meshes.size() - 1 else (0.5 + 0.5 * sin(time * 1.7))
		mi.scale = Vector3.ONE * (0.7 + 0.6 * p)


func _update_trail(dt: float) -> void:
	if blade_trail == null:
		return
	var active := is_attacking
	var window: Array = [0.0, 999.0]
	if not _attack.is_empty():
		window = _attack.get("trail", [0.0, 999.0])
	var now_active: bool = active and attack_time >= float(window[0]) and attack_time <= float(window[1])
	blade_trail.tick(dt, now_active)
	if now_active:
		blade_trail.add_sample(blade_base.global_position, blade_tip.global_position,
			Color(0.30, 0.62, 1.0, 1.0))


func _update_fx(dt: float) -> void:
	if not vfx_enabled:
		return
	if is_attacking and not _attack.is_empty():
		var hit_at: float = float(_attack.get("hit_at", -1.0))
		if hit_at >= 0.0 and attack_time >= hit_at and not _shake_sent.has("hit"):
			_shake_sent["hit"] = true
			var kind: String = String(_attack.get("hit_kind", "air"))
			var tip := blade_tip.global_position
			if kind == "ground":
				tip.y = 0.04
			var blade_dir := weapon_root.global_transform.basis.y.normalized()
			impact.emit(tip, 1.0)
			_fx.blade_hit(tip, blade_dir, kind, 1.0)
	if weapon_light != null:
		weapon_light.light_energy = 0.9 + 0.2 * sin(time * 8.0)
	if chest_light != null:
		chest_light.light_energy = 0.5 + 0.08 * sin(time * 3.2)


func reset_demo(pos: Vector3, new_heading: float) -> void:
	position = pos
	heading = new_heading
	rotation.y = new_heading
	speed = 0.0
	display_speed = 0.0
	move_command = Vector3.ZERO
	is_attacking = false
	attack_name = ""
	_attack = {}
	_attack_queue.clear()
	attack_time = 0.0
	combo_step = 0
	dash_time = 0.0
	_dash_cooldown = 0.0
	jump_state = "GROUND"
	jump_t = 0.0
	vertical_velocity = 0.0
	air_time = 0.0
	_carry_w = 0.0
	_attack_style = "twohand"
	_onehand = 0.0
	_left_raise = 0.0
	time = 0.0
	gait_phase = 0.0
	position.y = 0.0
	body.position = Vector3(0, HIP_Y, 0)
	body.rotation = Vector3.ZERO
	torso.rotation = Vector3.ZERO
	head.rotation = Vector3.ZERO
	var base := BASE_POSE.duplicate()
	_update_weapon(base)
	_update_arms(base)
	_update_legs(1.0 / 60.0, 0.0)
	if blade_trail != null:
		blade_trail.clear()
	if hair != null:
		hair.reset_sim()
	if _fx != null:
		_fx.clear_effects()


func _spin_progress(u: float) -> float:
	var r := 0.24
	var v := 1.0 / (1.0 - r)
	if u < r:
		var x := u / r
		return v * r * (x * x * x - 0.5 * x * x * x * x)
	elif u > 1.0 - r:
		var x := (1.0 - u) / r
		return 1.0 - v * r * (x * x * x - 0.5 * x * x * x * x)
	return v * r * 0.5 + v * (u - r)


func _eval_curve(curve: Array, t: float) -> float:
	if curve.is_empty():
		return 0.0
	if t <= float(curve[0][0]):
		return float(curve[0][1])
	for i in curve.size() - 1:
		if t >= float(curve[i][0]) and t <= float(curve[i + 1][0]):
			var u: float = (t - float(curve[i][0])) / maxf(float(curve[i + 1][0]) - float(curve[i][0]), 0.0001)
			u = u * u * (3.0 - 2.0 * u)
			return lerpf(float(curve[i][1]), float(curve[i + 1][1]), u)
	return float(curve[curve.size() - 1][1])


func face_target(pos: Vector3) -> void:
	var d := pos - global_position
	d.y = 0.0
	if d.length() < 0.01:
		return
	facing_override = true
	facing_heading = atan2(-d.x, -d.z)


func get_diagnostics() -> Dictionary:
	return {
		"speed": speed, "state": locomotion_state, "attack": attack_name,
		"combo": combo_step, "gait": gait_phase, "heading": heading,
		"display_speed": display_speed, "jump": jump_state, "dash": dash_time,
	}


# ------------------------------------------------------------------- QA hooks
func visual_aabb() -> AABB:
	var out := AABB()
	var started := false
	var stack: Array = [self]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n is MeshInstance3D and n.visible:
			var mi: MeshInstance3D = n
			var bb: AABB = mi.global_transform * mi.get_aabb()
			if not started:
				out = bb
				started = true
			else:
				out = out.merge(bb)
		for c in n.get_children():
			if c is Node3D:
				stack.append(c)
	return out


## Body-only AABB: excludes the sword and the hair ribbons, both of which can
## legitimately extend past the 2 m silhouette.
func body_aabb() -> AABB:
	var out := AABB()
	var started := false
	var stack: Array = [self]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n == weapon_spin or n == hair or (hair != null and n == hair):
			continue
		if n is MeshInstance3D and n.visible:
			var mi: MeshInstance3D = n
			var bb: AABB = mi.global_transform * mi.get_aabb()
			if not started:
				out = bb
				started = true
			else:
				out = out.merge(bb)
		for c in n.get_children():
			if c is Node3D:
				stack.append(c)
	return out


func get_knee_angle(index: int) -> float:
	if index < 0 or index >= legs.size():
		return 0.0
	var leg: Dictionary = legs[index]
	var hip: Node3D = leg["hip"]
	var knee: Node3D = leg["knee"]
	var ankle: Node3D = leg["ankle"]
	var a := hip.global_position - knee.global_position
	var b := ankle.global_position - knee.global_position
	return rad_to_deg(a.angle_to(b))


func blade_tip_world() -> Vector3:
	return blade_tip.global_position if blade_tip != null else global_position


func hair_tips() -> Array:
	if hair != null and hair.has_method("get_tip_positions"):
		return hair.get_tip_positions()
	return []