extends Node3D
const STUDIO := preload("res://scenes/studio.tscn")
var studio
var ch
const SHOTS := [
	["hero", -36.0, 7.0, 3.35, Vector3(0, 0.90, 0.0)],
	["front_full", 0.0, 5.0, 3.25, Vector3(0, 0.90, 0.0)],
	["side_full", 270.0, 5.0, 3.25, Vector3(0, 0.90, 0.0)],
	["back_full", 180.0, 7.0, 3.25, Vector3(0, 0.90, 0.0)],
	["camera", 18.0, 2.0, 1.35, Vector3(0, 1.06, 0.34)],
	["camera_side", -58.0, 4.0, 1.30, Vector3(0, 1.06, 0.28)],
	["wheel", 32.0, 10.0, 1.15, Vector3(0.45, 0.32, 0.02)],
	["wheel_front", 0.0, 8.0, 1.25, Vector3(0.45, 0.30, 0.18)],
	["body", 25.0, 4.0, 1.75, Vector3(0, 0.95, 0.05)],
	["metal", 35.0, 5.0, 0.95, Vector3(-0.15, 1.02, 0.12)],
	["shield", 55.0, 4.0, 1.65, Vector3(0.45, 1.0, 0.40)],
	["sword", 12.0, 0.0, 1.75, Vector3(-0.55, 0.80, 0.50)],
	["back", 180.0, 6.0, 1.80, Vector3(0, 1.00, -0.20)],
	["shoulder", -30.0, 4.0, 1.05, Vector3(0.27, 1.10, 0.02)],
]
func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders/v2/details"))
	studio = STUDIO.instantiate(); add_child(studio); await _f(6)
	studio.ui_root.visible = false
	if studio._overlay: studio._overlay.visible = false
	studio._shot_mode = true
	ch = studio.character
	ch.set_param("lens_track", 0.0)
	ch.current_anim = "idle"; ch._playing = false; ch._t = 0.3; ch._apply_now(0.3); ch._update_fx(0.016)
	for s in SHOTS:
		if str(s[0]).begins_with("camera"):
			# clean camera inspection: sword stowed, shield on the back, arms hidden
			ch.current_anim = "rest"; ch._playing = false; ch._t = 0.4
			ch._apply_now(0.4); ch._update_fx(0.016)
			ch.rig.J["shL"].visible = false
			ch.rig.J["shR"].visible = false
		else:
			ch.rig.J["shL"].visible = true
			ch.rig.J["shR"].visible = true
			ch.current_anim = "idle"; ch._playing = false; ch._t = 0.3
			ch._apply_now(0.3); ch._update_fx(0.016)
		studio.set_view(float(s[1]), float(s[2]), float(s[3]), s[4])
		await _f(2)
		await studio.snap("res://renders/v2/details/" + str(s[0]) + ".png")
	# rest back / sheath
	ch.current_anim = "rest"; ch._t = 0.4; ch._apply_now(0.4); ch._update_fx(0.016)
	studio.set_view(205.0, 8.0, 1.7, Vector3(0, 0.85, -0.15))
	await _f(2); await studio.snap("res://renders/v2/details/rest_back.png")
	studio.set_view(300.0, 6.0, 1.6, Vector3(0.28, 0.72, 0.0))
	await _f(2); await studio.snap("res://renders/v2/details/sheath.png")
	get_tree().quit(0)
func _f(n: int) -> void:
	for i in n: await get_tree().process_frame
