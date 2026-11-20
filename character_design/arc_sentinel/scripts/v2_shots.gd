extends Node3D
## Deterministic frame-strip renderer for visual review of ARC // SENTINEL v2.
##
##   DISPLAY=:10 godot --path . res://scenes/v2_shots.tscn
##
## Writes renders/v2/frames/<clip>/<view>_<index>.png at 960x540.

const STUDIO := preload("res://scenes/studio.tscn")
const ANIMS := ["rest", "idle", "walk", "draw", "attack", "attack_up", "defend_left", "defend_right", "sheathe"]
const VIEWS := {
	"three_q_r": {"yaw": -36.0, "pitch": 7.0, "dist": 3.35, "target": Vector3(0, 0.86, 0)},
	"front": {"yaw": 0.0, "pitch": 5.0, "dist": 3.30, "target": Vector3(0, 0.86, 0)},
	"side": {"yaw": 270.0, "pitch": 5.0, "dist": 3.30, "target": Vector3(0, 0.86, 0)},
	"back": {"yaw": 180.0, "pitch": 7.0, "dist": 3.30, "target": Vector3(0, 0.86, 0)},
}
const NFRAMES := 16

var studio
var ch
var out_dir := "res://renders/v2/frames"


func _ready() -> void:
	get_window().size = Vector2i(960, 540)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	studio = STUDIO.instantiate()
	add_child(studio)
	await _frames(6)
	studio.ui_root.visible = false
	if studio._overlay:
		studio._overlay.visible = false
	studio._shot_mode = true
	ch = studio.character
	ch.set_param("lens_track", 0.0)
	var only := OS.get_environment("V2_ONLY")
	for clip in ANIMS:
		if only != "" and not (clip in only.split(",", false)):
			continue
		var anim_name: String = clip
		if clip == "defend_left":
			ch.set_block_threat(0)
			anim_name = "defend"
		elif clip == "defend_right":
			ch.set_block_threat(1)
			anim_name = "defend"
		await _render_clip(clip, anim_name)
	print("[v2_shots] done")
	get_tree().quit(0)


func _render_clip(clip: String, anim_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir.path_join(clip)))
	var dur: float = ch.anim.duration(anim_name)
	for view in VIEWS:
		var vd: Dictionary = VIEWS[view]
		# the attack finish is high and reaches far forward; use a wider
		# camera for those two clips so the whole arm+blade line is in frame
		if clip == "attack" or clip == "attack_up":
			studio.set_view(vd["yaw"], vd["pitch"], 4.40, Vector3(0, 1.05, 0))
		else:
			studio.set_view(vd["yaw"], vd["pitch"], vd["dist"], vd["target"])
		for i in NFRAMES:
			var t := dur * float(i) / float(NFRAMES - 1)
			ch.current_anim = anim_name
			ch._playing = false
			ch._loop = false
			ch._t = t
			ch._manual = false
			ch._fade_t = 0.0
			ch._apply_now(t)
			ch._update_fx(0.016)
			await _frames(1)
			var path: String = out_dir.path_join(clip).path_join("%s_%02d.png" % [view, i])
			await studio.snap(path)
	print("  rendered ", clip, " x", NFRAMES, " x", VIEWS.size())


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame