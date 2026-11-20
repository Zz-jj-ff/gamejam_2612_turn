extends Node3D
## Renders the two mandated 45-degree block cases with a ghost threat blade.
##   DISPLAY=:10 godot --path . res://scenes/block_demo.tscn

const STUDIO := preload("res://scenes/studio.tscn")
const MK := preload("res://scripts/kit/mesh_kit.gd")
const SK := preload("res://scripts/kit/shape_kit.gd")
const AM := preload("res://scripts/ch/arc_materials.gd")

var studio
var ch
var threat_mat: StandardMaterial3D
var spark_mat: StandardMaterial3D


func _ready() -> void:
	studio = STUDIO.instantiate()
	add_child(studio)
	await _f(6)
	studio.ui_root.visible = false
	if studio._overlay:
		studio._overlay.visible = false
	studio._shot_mode = true
	ch = studio.character
	ch.set_param("lens_track", 0.0)
	threat_mat = StandardMaterial3D.new()
	threat_mat.albedo_color = Color(0.030, 0.004, 0.002)
	threat_mat.metallic = 0.90
	threat_mat.roughness = 0.30
	threat_mat.emission_enabled = true
	threat_mat.emission = Color(1.0, 0.10, 0.015)
	threat_mat.emission_energy_multiplier = 0.75
	spark_mat = StandardMaterial3D.new()
	spark_mat.albedo_color = Color(1.0, 0.4, 0.1)
	spark_mat.emission_enabled = true
	spark_mat.emission = Color(1.0, 0.32, 0.05)
	spark_mat.emission_energy_multiplier = 4.5
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders/v2"))
	await _case(0, "LEFT 45°   →   SHIELD", Vector3(0.7071, 0.0, 0.7071),
		Vector3(0.438, 1.06, 0.488), 0.0, "res://renders/v2/block_left.png")
	await _case(1, "RIGHT 45°   →   SWORD", Vector3(-0.7071, 0.0, 0.7071),
		Vector3(-0.424, 1.06, 0.474), 0.0, "res://renders/v2/block_right.png")
	get_tree().quit(0)


func _case(threat: int, label_text: String, outward: Vector3, intercept: Vector3,
		yaw: float, path: String) -> void:
	ch.set_block_threat(threat)
	ch.current_anim = "defend"
	ch._playing = false
	ch._loop = false
	ch._t = 0.55
	ch._fade_t = 0.0
	ch._apply_now(0.55)
	ch._update_fx(0.016)
	# ghost blade: base toward the attacker, tip exactly on the intercept point
	var base := intercept + outward.normalized() * 1.38
	var y := (intercept - base).normalized()
	var bxf := SK.basis_y(y, Vector3.UP)
	var blade := MeshInstance3D.new()
	blade.mesh = MK.katana(1.38, 0.062, 0.026, 0.05)
	blade.material_override = threat_mat
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blade.transform = Transform3D(bxf, base)
	studio.add_child(blade)
	# thin hot cutting edge so the threat reads as a blade, not a plank
	var edge := MeshInstance3D.new()
	edge.mesh = SK.beam(base + bxf * Vector3(0.030, 0.04, 0.0),
		intercept + bxf * Vector3(0.001, 0.0, 0.0), 0.014, 0.010, 0.004, 0.003,
		0.30, Vector3.UP, 0.002)
	edge.material_override = spark_mat
	edge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	studio.add_child(edge)
	# a soft glow at the contact
	var spark := MeshInstance3D.new()
	spark.mesh = MK.sphere(0.052, 16, 12, true)
	spark.material_override = spark_mat
	spark.position = intercept
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	studio.add_child(spark)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.25, 0.04)
	glow.light_energy = 4.0
	glow.omni_range = 1.8
	glow.shadow_enabled = false
	glow.position = intercept
	studio.add_child(glow)
	var lab := Label3D.new()
	lab.text = label_text
	lab.font_size = 44
	lab.modulate = Color(1.0, 0.62, 0.28)
	lab.outline_size = 6
	lab.outline_modulate = Color(0.02, 0.01, 0.005)
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.fixed_size = false
	lab.position = Vector3(0, 1.62, 0.10)
	studio.add_child(lab)
	studio.set_view(yaw, 5.0, 3.7, Vector3(0, 0.92, 0.12))
	await _f(3)
	await studio.snap(path)
	# clean up for the next case
	blade.queue_free()
	edge.queue_free()
	spark.queue_free()
	glow.queue_free()
	lab.queue_free()


func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame