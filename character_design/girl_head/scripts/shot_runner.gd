extends Node3D
## Deterministic portrait sheet.
##
##   DISPLAY=:10 godot --path . res://scenes/shots.tscn
##   SHOT_DIR=res://renders/final SHOT_ONLY=front,three_q,face ...
##   SHOT_TURNTABLE=1 renders an 8-step yaw sweep into the same directory.

const STUDIO := preload("res://scenes/studio.tscn")

const VIEWS := {
	"front": {"yaw": 0.0, "pitch": 3.0, "dist": 0.62, "target": Vector3(0, -0.055, 0)},
	"three_q": {"yaw": 28.0, "pitch": 3.0, "dist": 0.60, "target": Vector3(0, -0.055, 0),
		"joints": {"head_yaw": 4.0, "eye_yaw": 5.0, "head_pitch": -1.5}},
	"three_q_left": {"yaw": -30.0, "pitch": 3.0, "dist": 0.60, "target": Vector3(0, -0.055, 0),
		"joints": {"head_yaw": -3.0, "eye_yaw": -4.0}},
	"profile": {"yaw": 88.0, "pitch": 2.0, "dist": 0.66, "target": Vector3(0, -0.05, 0)},
	"back": {"yaw": 176.0, "pitch": 5.0, "dist": 0.80, "target": Vector3(0, -0.10, 0)},
	"low": {"yaw": 20.0, "pitch": -10.0, "dist": 0.64, "target": Vector3(0, -0.045, 0)},
	"high": {"yaw": 18.0, "pitch": 28.0, "dist": 0.72, "target": Vector3(0, -0.08, 0)},
	"bust": {"yaw": 24.0, "pitch": 3.0, "dist": 1.00, "target": Vector3(0, -0.14, 0)},
	"face": {"yaw": 12.0, "pitch": 1.0, "dist": 0.47, "target": Vector3(0, -0.052, 0.01),
		"joints": {"head_yaw": 3.0, "eye_yaw": 5.0}},
	"face_left": {"yaw": -18.0, "pitch": 1.0, "dist": 0.47, "target": Vector3(0, -0.052, 0.01)},
	"eyes": {"yaw": 5.0, "pitch": 0.0, "dist": 0.225, "target": Vector3(0, -0.020, 0.048)},
	"eyes_three_q": {"yaw": 28.0, "pitch": 1.0, "dist": 0.235, "target": Vector3(0, -0.018, 0.040)},
	"lips": {"yaw": 4.0, "pitch": -2.0, "dist": 0.19, "target": Vector3(0, -0.058, 0.070)},
	"hair_top": {"yaw": 20.0, "pitch": 32.0, "dist": 0.56, "target": Vector3(0, 0.005, -0.015)},
	"hair_back": {"yaw": 152.0, "pitch": 4.0, "dist": 0.90, "target": Vector3(0, -0.16, -0.04)},
}

var studio: Node3D


func _ready() -> void:
	var out_dir := OS.get_environment("SHOT_DIR")
	if out_dir == "":
		out_dir = "res://renders/final"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	studio = STUDIO.instantiate()
	add_child(studio)
	await _frames(6)
	studio.ui_root.visible = false
	studio._shot_mode = true
	var ch: GirlHead = studio.character
	if ch == null:
		push_error("[shots] no character")
		get_tree().quit(1)
		return
	var count := 0
	var lines := PackedStringArray()
	if OS.get_environment("SHOT_TURNTABLE") != "":
		ch.play_anim("idle")
		ch.set_playing(false)
		ch.set_anim_time(0.0)
		for i in 8:
			var yaw := float(i) * 45.0
			studio.set_view(yaw, 4.0, 0.95, Vector3(0, -0.12, 0))
			await _frames(3)
			var path: String = out_dir.path_join("turntable_%02d.png" % i)
			await studio.snap(path)
			lines.append("turntable %02d yaw=%.1f" % [i, yaw])
			count += 1
		print("[shots] rendered %d turntable stills" % count)
		get_tree().quit(0)
		return
	var only := OS.get_environment("SHOT_ONLY")
	var ids := []
	if only == "":
		ids = VIEWS.keys()
	else:
		for s in only.split(",", false):
			ids.append(s.strip_edges())
	for id in ids:
		if not VIEWS.has(id):
			continue
		var v: Dictionary = VIEWS[id]
		for k in ch.joint_specs():
			ch.set_joint(k["key"], 0.0)
		if v.has("joints"):
			for k in v["joints"]:
				ch.set_joint(k, float(v["joints"][k]))
		studio.set_view(v["yaw"], v["pitch"], v["dist"], v["target"])
		ch.play_anim("idle")
		ch.set_playing(false)
		ch.set_anim_time(0.0)
		ch._apply_pose()
		await _frames(3)
		var path: String = out_dir.path_join("%s.png" % id)
		await studio.snap(path)
		lines.append("%s  yaw=%.1f dist=%.2f" % [id, v["yaw"], v["dist"]])
		count += 1
	print("[shots] rendered %d stills into %s" % [count, out_dir])
	var f := FileAccess.open(out_dir.path_join("index.txt"), FileAccess.WRITE)
	if f:
		f.store_string("\n".join(lines))
		f.close()
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame