extends Node3D
## T4 // VESPER — playable showcase.
## Procedural arena + procedural mech + procedural animation + code-drawn HUD.

const Arena = preload("res://scripts/world/arena.gd")
const Rig = preload("res://scripts/mech/mech_rig.gd")
const CameraRig = preload("res://scripts/world/camera_rig.gd")
const HUD = preload("res://scripts/world/hud.gd")
const Showcase = preload("res://scripts/world/showcase.gd")

var arena
var rig
var cam_rig
var hud
var director
var hud_layer: CanvasLayer
var auto_mode := true
var hud_visible := true
var _started := false


func _ready() -> void:
	get_window().title = "T4 // VESPER"
	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)

	rig = Rig.new()
	rig.name = "VESPER"
	rig.auto_step = false
	add_child(rig)
	rig.set_process(false)

	cam_rig = CameraRig.new()
	cam_rig.name = "CombatCamera"
	cam_rig.target = rig
	add_child(cam_rig)

	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	hud = HUD.new()
	hud_layer.add_child(hud)
	hud.set_rig(rig)
	hud.auto_mode = true

	director = Showcase.new()
	director.setup(rig, cam_rig, hud)
	director.reset()

	rig.footstep.connect(_on_footstep)
	rig.impact.connect(_on_impact)
	rig.attack_started.connect(_on_attack_started)
	_started = true


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)
	if auto_mode:
		if _input_requested():
			_take_control()
			_manual_control(delta)
		else:
			director.update(delta)
	else:
		_manual_control(delta)
	rig.advance(delta)
	cam_rig.update_camera(delta, rig.speed)
	hud.auto_mode = auto_mode


func _input_requested() -> bool:
	if Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() > 0.25:
		return true
	for a in ["attack_light", "attack_heavy", "attack_spin", "dash", "jump", "camera_left", "camera_right"]:
		if InputMap.has_action(a) and Input.is_action_just_pressed(a):
			return true
	return false


func _take_control() -> void:
	auto_mode = false
	rig.move_command = Vector3.ZERO
	cam_rig.set_shot(0.0, 7.0, 2.3, 1.25, 40.0, true, rig.rotation.y)
	cam_rig.snap()
	cam_rig.update_camera(0.0, 0.0)
	hud.phase_text = "MANUAL / LIVE BLADE"
	hud.auto_mode = false
	hud.set_fade(0.0)
	hud.flash(0.10)


func _manual_control(delta: float) -> void:
	var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var cam_fwd: Vector3 = -cam_rig.camera.global_transform.basis.z
	cam_fwd.y = 0.0
	cam_fwd = cam_fwd.normalized()
	var cam_right: Vector3 = cam_rig.camera.global_transform.basis.x
	cam_right.y = 0.0
	cam_right = cam_right.normalized()
	var dir: Vector3 = cam_right * v.x + cam_fwd * (-v.y)
	var sprint := Input.is_action_pressed("sprint")
	if dir.length() > 0.12:
		var spd := 7.2 if sprint else 3.4
		rig.move_command = dir.normalized() * spd
	else:
		rig.move_command = Vector3.ZERO

	if Input.is_action_just_pressed("attack_light"):
		rig.request_light_attack()
	if InputMap.has_action("attack_side") and Input.is_action_just_pressed("attack_side"):
		rig.request_side_attack(1.0)
	if InputMap.has_action("attack_back") and Input.is_action_just_pressed("attack_back"):
		rig.request_back_attack()
	if Input.is_action_just_pressed("attack_heavy"):
		rig.request_heavy_attack()
	if InputMap.has_action("attack_spin") and Input.is_action_just_pressed("attack_spin"):
		rig.request_spin_attack()
	if Input.is_action_just_pressed("dash"):
		var dash_local := Vector3(0, 0, -1)
		if dir.length() > 0.12:
			dash_local = rig.global_transform.basis.inverse() * dir.normalized()
		rig.request_dash(dash_local)
	if Input.is_action_just_pressed("jump"):
		rig.request_jump()
	var orbiting := Input.is_action_pressed("camera_left") or Input.is_action_pressed("camera_right")
	if Input.is_action_pressed("camera_left"):
		cam_rig.world_yaw += 1.5 * delta
	if Input.is_action_pressed("camera_right"):
		cam_rig.world_yaw -= 1.5 * delta
	if not orbiting and dir.length() <= 0.12 and not rig.is_attacking and rig.jump_state == "GROUND":
		cam_rig.world_yaw = lerp_angle(cam_rig.world_yaw, rig.heading, 1.0 - exp(-1.3 * delta))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_hud"):
		hud_visible = not hud_visible
		hud.set_hud_visible(hud_visible)
	elif event.is_action_pressed("toggle_auto"):
		if auto_mode:
			_take_control()
		else:
			auto_mode = true
			director.reset()
			cam_rig.snap()


func _on_footstep(_pos: Vector3, strength: float) -> void:
	if cam_rig != null:
		cam_rig.add_shake(0.022 * strength)


func _on_impact(_pos: Vector3, strength: float) -> void:
	cam_rig.add_shake(0.5 * strength)
	hud.flash(0.55 * strength)


func _on_attack_started(_label: String, _heavy: bool) -> void:
	pass