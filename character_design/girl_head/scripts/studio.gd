extends Node3D
## Portrait studio for GIRL // HEAD.
## Dark cyclorama, neon rim kickers, warm key, orbit camera and a live
## tuning panel.  All geometry and light rigs are code.

const CHARACTER_SCENE := "res://scenes/head.tscn"
const OVERLAY_SHADER := preload("res://shaders/screen_overlay.gdshader")
const SKY_SHADER := preload("res://shaders/studio_sky.gdshader")
const BACKDROP_SHADER := preload("res://shaders/backdrop.gdshader")
const MB := preload("res://scripts/build/mesh_builder.gd")
const MATS := preload("res://scripts/build/head_materials.gd")

var character: GirlHead
var camera: Camera3D
var cam_pivot: Node3D
var ui_root: Control
var panel_root: PanelContainer
var title_label: Label
var info_label: RichTextLabel
var timeline: HSlider
var play_btn: Button

var _yaw := 26.0
var _pitch := 4.0
var _dist := 0.62
var _target := Vector3(0.0, -0.055, 0.0)
var _home := Vector3(26.0, 4.0, 0.62)
var _home_target := Vector3(0.0, -0.055, 0.0)
var _dragging := false
var _drag_button := 0
var _ui_visible := true
var _shot_mode := false
var _shot_index := 0
var _scrubbing := false
var _auto_orbit := false
var _fps := 0.0
var _frames := 0
var _fps_t := 0.0
var _btns := {}
var _value_labels := {}


func _ready() -> void:
	_build_environment()
	_build_backdrop()
	_build_lights()
	_build_dust()
	_build_camera()
	_spawn_character()
	_build_ui()
	_build_overlay()
	if OS.get_environment("STUDIO_SHOT") != "":
		_shot_mode = true
		ui_root.visible = false
		var ov := get_node_or_null("Grade")
		if ov:
			ov.visible = false
	var cam_env := OS.get_environment("STUDIO_CAM")
	if cam_env != "":
		var p := cam_env.split(",", false)
		if p.size() >= 3:
			var tgt := _target
			if p.size() >= 4:
				tgt = Vector3(0.0, float(p[3]), 0.0)
			var tgt_env := OS.get_environment("STUDIO_TARGET")
			if tgt_env != "":
				var t := tgt_env.split(",", false)
				if t.size() >= 3:
					tgt = Vector3(float(t[0]), float(t[1]), float(t[2]))
			set_view(float(p[0]), float(p[1]), float(p[2]), tgt)
	var anim_env := OS.get_environment("STUDIO_ANIM")
	if anim_env != "" and character:
		character.play_anim(anim_env)
	var time_env := OS.get_environment("STUDIO_TIME")
	if time_env != "" and character:
		character.set_playing(false)
		character.set_anim_time(float(time_env))
	var par_env := OS.get_environment("STUDIO_PARAM")
	if par_env != "" and character:
		for kv in par_env.split(";", false):
			var bits := kv.split("=", false)
			if bits.size() == 2:
				character.set_param(bits[0].strip_edges(), float(bits[1]))
	var snap := OS.get_environment("STUDIO_SNAP")
	if snap != "":
		_auto_snap(snap)
	set_process(true)


func _auto_snap(path: String) -> void:
	for i in 20:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	await snap(path)
	get_tree().quit(0)


# --------------------------------------------------------------- environment

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.sky = sky
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.004, 0.005, 0.008)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.38
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.94
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.20
	env.glow_strength = 1.05
	env.glow_bloom = 0.02
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.22
	env.glow_hdr_scale = 2.0
	env.ssao_enabled = true
	env.ssao_radius = 0.16
	env.ssao_intensity = 1.9
	env.ssao_power = 1.5
	env.ssao_light_affect = 0.10
	env.ssr_enabled = true
	env.ssr_max_steps = 56
	env.ssr_fade_in = 0.10
	env.ssr_fade_out = 1.6
	env.ssr_depth_tolerance = 0.10
	env.fog_enabled = true
	env.fog_light_color = Color(0.030, 0.036, 0.055)
	env.fog_light_energy = 0.45
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.01
	env.adjustment_contrast = 1.055
	env.adjustment_saturation = 1.04
	we.environment = env
	add_child(we)


func _build_backdrop() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 7.0
	sphere.height = 14.0
	sphere.radial_segments = 96
	sphere.rings = 48
	var mi := MeshInstance3D.new()
	mi.name = "Backdrop"
	mi.mesh = sphere
	var mat := ShaderMaterial.new()
	mat.shader = BACKDROP_SHADER
	mi.material_override = mat
	mi.position = Vector3(0.0, -0.08, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	var spot := OmniLight3D.new()
	spot.position = Vector3(0.0, -0.42, 0.0)
	spot.light_color = Color(0.35, 0.70, 1.0)
	spot.light_energy = 0.35
	spot.omni_range = 0.8
	add_child(spot)


func _build_lights() -> void:
	# warm key: high front-left
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.basis = Basis.looking_at(Vector3(-0.62, -0.72, -0.62).normalized(), Vector3.UP)
	key.light_color = Color(1.0, 0.945, 0.885)
	key.light_energy = 1.15
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 4.0
	key.shadow_bias = 0.008
	key.shadow_blur = 1.4
	add_child(key)

	# cool fill: low front-right
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.basis = Basis.looking_at(Vector3(0.68, -0.30, -0.67).normalized(), Vector3.UP)
	fill.light_color = Color(0.52, 0.68, 1.0)
	fill.light_energy = 0.50
	add_child(fill)

	# cyan rim: back-right, cuts the silver hair
	var rim_c := DirectionalLight3D.new()
	rim_c.name = "RimCyan"
	rim_c.basis = Basis.looking_at(Vector3(0.52, -0.22, 0.83).normalized(), Vector3.UP)
	rim_c.light_color = Color(0.44, 0.80, 1.0)
	rim_c.light_energy = 1.30
	add_child(rim_c)

	# magenta rim: back-left
	var rim_m := DirectionalLight3D.new()
	rim_m.name = "RimMagenta"
	rim_m.basis = Basis.looking_at(Vector3(-0.58, -0.18, 0.80).normalized(), Vector3.UP)
	rim_m.light_color = Color(1.0, 0.36, 0.62)
	rim_m.light_energy = 1.00
	add_child(rim_m)

	var front_fill := DirectionalLight3D.new()
	front_fill.name = "FrontFill"
	front_fill.basis = Basis.looking_at(Vector3(0.10, -0.22, -0.97).normalized(), Vector3.UP)
	front_fill.light_color = Color(0.72, 0.80, 1.0)
	front_fill.light_energy = 0.55
	add_child(front_fill)

	# top soft
	var top := DirectionalLight3D.new()
	top.name = "Top"
	top.basis = Basis.looking_at(Vector3(0.05, -0.99, 0.10).normalized(), Vector3.UP)
	top.light_color = Color(0.68, 0.78, 1.0)
	top.light_energy = 0.32
	add_child(top)

	# small frontal beauty spot (eyes / lips speculars)
	var beauty := SpotLight3D.new()
	beauty.name = "Beauty"
	beauty.position = Vector3(0.26, 0.18, 0.80)
	beauty.look_at_from_position(beauty.position, Vector3(0.0, -0.045, 0.06), Vector3.UP)
	beauty.light_color = Color(1.0, 0.93, 0.86)
	beauty.light_energy = 0.85
	beauty.spot_range = 2.4
	beauty.spot_angle = 22.0
	beauty.spot_attenuation = 1.2
	add_child(beauty)
	# cool kick on the far cheek
	var cheek := SpotLight3D.new()
	cheek.name = "CheekKick"
	cheek.position = Vector3(-0.55, 0.10, 0.62)
	cheek.look_at_from_position(cheek.position, Vector3(-0.03, -0.06, 0.05), Vector3.UP)
	cheek.light_color = Color(0.55, 0.74, 1.0)
	cheek.light_energy = 0.42
	cheek.spot_range = 2.0
	cheek.spot_angle = 18.0
	add_child(cheek)


func _build_dust() -> void:
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = 14.0
	p.preprocess = 8.0
	p.position = Vector3(0, 0.15, 0)
	p.visibility_aabb = AABB(Vector3(-2, -3, -2), Vector3(4, 4, 4))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.9, 0.9, 0.7)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.004
	pm.initial_velocity_max = 0.02
	pm.gravity = Vector3(0.002, 0.004, 0.0)
	pm.scale_min = 0.35
	pm.scale_max = 1.0
	pm.color = Color(0.62, 0.78, 1.0, 0.35)
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.010, 0.010)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.55, 0.72, 1.0, 0.35)
	quad.material = mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)


func _build_camera() -> void:
	cam_pivot = Node3D.new()
	cam_pivot.name = "CamPivot"
	add_child(cam_pivot)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 30.0
	camera.near = 0.01
	camera.far = 60.0
	cam_pivot.add_child(camera)
	var fov_env := OS.get_environment("STUDIO_FOV")
	if fov_env != "":
		camera.fov = float(fov_env)
	_update_camera()


func _spawn_character() -> void:
	var ps: PackedScene = load(CHARACTER_SCENE)
	if ps == null:
		push_error("missing scenes/head.tscn")
		return
	character = ps.instantiate()
	character.name = "Character"
	add_child(character)
	if OS.has_environment("DEBUG_RAINBOW"):
		await get_tree().process_frame
		await get_tree().process_frame
		var stack := [character]
		var idx := 0
		while not stack.is_empty():
			var n = stack.pop_back()
			if n is MeshInstance3D:
				var col := Color.from_hsv(fmod(float(idx) * 0.137, 1.0), 0.9, 1.0)
				var m := StandardMaterial3D.new()
				m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				m.albedo_color = col
				n.material_override = m
				print("DBG %02d %-16s %s" % [idx, n.name, col.to_html(false)])
				idx += 1
			for c in n.get_children():
				stack.append(c)


func set_view(yaw: float, pitch: float, dist: float, target: Vector3) -> void:
	_yaw = yaw
	_pitch = pitch
	_dist = dist
	_target = target
	_update_camera()


func reset_view() -> void:
	_yaw = _home.x
	_pitch = _home.y
	_dist = _home.z
	_target = _home_target
	_update_camera()


func _update_camera() -> void:
	if cam_pivot == null:
		return
	cam_pivot.position = _target
	var y := deg_to_rad(_yaw)
	var p := deg_to_rad(_pitch)
	var offset := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * _dist
	camera.position = offset
	camera.basis = Basis.looking_at(-offset.normalized(), Vector3.UP)


# ------------------------------------------------------------------------ UI

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)

	# title bottom-left
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 30
	box.offset_right = 720
	box.offset_top = -132
	box.offset_bottom = -30
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(box)
	var accent := ColorRect.new()
	accent.color = Color(0.62, 0.86, 1.0, 0.9)
	accent.custom_minimum_size = Vector2(58, 2)
	accent.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(accent)
	title_label = Label.new()
	title_label.text = "GIRL // HEAD"
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	box.add_child(title_label)
	var sub := Label.new()
	sub.text = "procedural android portrait · 0 imported assets · live rig"
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.52, 0.60, 0.72))
	box.add_child(sub)

	# panel right
	panel_root = PanelContainer.new()
	panel_root.anchor_left = 1.0
	panel_root.anchor_right = 1.0
	panel_root.anchor_top = 0.0
	panel_root.anchor_bottom = 1.0
	panel_root.offset_left = -352.0
	panel_root.offset_right = -18.0
	panel_root.offset_top = 18.0
	panel_root.offset_bottom = -18.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.012, 0.015, 0.022, 0.92)
	sb.border_color = Color(0.26, 0.46, 0.66, 0.50)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel_root.add_theme_stylebox_override("panel", sb)
	panel_root.add_theme_font_size_override("font_size", 12)
	ui_root.add_child(panel_root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	panel_root.add_child(col)
	var head_lbl := Label.new()
	head_lbl.text = "TUNING // LIVE"
	head_lbl.add_theme_font_size_override("font_size", 15)
	head_lbl.add_theme_color_override("font_color", Color(0.78, 0.90, 1.0))
	col.add_child(head_lbl)

	# animation row
	var arow := HBoxContainer.new()
	arow.add_theme_constant_override("separation", 4)
	col.add_child(arow)
	for a in GirlHead.ANIMS:
		var b := Button.new()
		b.text = a.to_upper()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_on_anim.bind(a))
		arow.add_child(b)
		_btns[a] = b
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 6)
	col.add_child(trow)
	play_btn = Button.new()
	play_btn.text = "PAUSE"
	play_btn.add_theme_font_size_override("font_size", 10)
	play_btn.custom_minimum_size = Vector2(70, 24)
	play_btn.pressed.connect(_on_play)
	trow.add_child(play_btn)
	timeline = HSlider.new()
	timeline.min_value = 0.0
	timeline.max_value = 1.0
	timeline.step = 0.001
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.mouse_filter = Control.MOUSE_FILTER_STOP
	timeline.value_changed.connect(_on_timeline)
	timeline.drag_started.connect(func(): _scrubbing = true)
	timeline.drag_ended.connect(func(_v): _scrubbing = false)
	trow.add_child(timeline)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)

	var group := ""
	for spec in character.param_specs():
		if spec["group"] != group:
			group = spec["group"]
			var gl := Label.new()
			gl.text = "— " + group
			gl.add_theme_font_size_override("font_size", 11)
			gl.add_theme_color_override("font_color", Color(0.60, 0.80, 0.98))
			list.add_child(gl)
		list.add_child(_param_row(spec, false))
	var jgroup := ""
	for spec in character.joint_specs():
		if spec["group"] != jgroup:
			jgroup = spec["group"]
			var jl := Label.new()
			jl.text = "— JOINT " + jgroup
			jl.add_theme_font_size_override("font_size", 11)
			jl.add_theme_color_override("font_color", Color(0.95, 0.68, 0.42))
			list.add_child(jl)
		list.add_child(_param_row(spec, true))

	var info_box := VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 2)
	col.add_child(info_box)
	var div := ColorRect.new()
	div.color = Color(0.24, 0.40, 0.56, 0.5)
	div.custom_minimum_size = Vector2(1, 1)
	info_box.add_child(div)
	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_label.custom_minimum_size = Vector2(0, 88)
	info_label.add_theme_font_size_override("font_size", 10)
	info_box.add_child(info_label)

	var hint := Label.new()
	hint.text = "LMB orbit · wheel zoom · F reset · H hide · F12 shot"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(0.42, 0.48, 0.58))
	ui_root.add_child(hint)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -430
	hint.offset_right = -356
	hint.offset_top = -30
	hint.offset_bottom = -16


func _param_row(spec: Dictionary, is_joint: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var lab := Label.new()
	lab.text = str(spec["label"])
	lab.custom_minimum_size = Vector2(110, 0)
	lab.add_theme_font_size_override("font_size", 10)
	lab.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
	row.add_child(lab)
	var sl := HSlider.new()
	sl.min_value = spec["min"]
	sl.max_value = spec["max"]
	sl.step = spec["step"]
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.custom_minimum_size = Vector2(90, 18)
	if is_joint:
		sl.value = character.get_joint(spec["key"] if character.get_joint(spec["key"]) != 0.0 else spec["key"])
		sl.value = character.get_joint(spec["key"])
	else:
		sl.value = spec["value"]
	row.add_child(sl)
	var val := Label.new()
	val.custom_minimum_size = Vector2(48, 0)
	val.add_theme_font_size_override("font_size", 10)
	val.add_theme_color_override("font_color", Color(0.58, 0.74, 0.92))
	val.text = "%.3f" % sl.value
	row.add_child(val)
	_value_labels[spec["key"]] = val
	sl.value_changed.connect(func(v: float) -> void:
		if is_joint:
			character.set_joint(spec["key"], v)
		else:
			character.set_param(spec["key"], v)
		val.text = "%.3f" % v
	)
	return row


func _on_anim(a: String) -> void:
	if character:
		character.play_anim(a)


func _on_play() -> void:
	if character == null:
		return
	character.set_playing(not character.is_playing())
	play_btn.text = "PLAY" if not character.is_playing() else "PAUSE"


func _on_timeline(v: float) -> void:
	if character == null or not _scrubbing:
		return
	character.set_anim_time(v * character.anim_duration())


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Grade"
	layer.layer = 2
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = OVERLAY_SHADER
	rect.material = mat
	layer.add_child(rect)
	if _shot_mode:
		layer.visible = false


# -------------------------------------------------------------------- input

func _process(dt: float) -> void:
	_frames += 1
	_fps_t += dt
	if _fps_t >= 0.4:
		_fps = float(_frames) / _fps_t
		_frames = 0
		_fps_t = 0.0
		_update_info()
	if _auto_orbit and not _shot_mode:
		_yaw += dt * 14.0
		_update_camera()
	if character and not _scrubbing:
		var dur: float = maxf(character.anim_duration(), 0.001)
		timeline.set_value_no_signal(character.anim_time() / dur)
	if character:
		play_btn.text = "PAUSE" if character.is_playing() else "PLAY"


func _update_info() -> void:
	if character == null or info_label == null:
		return
	var d := character.rig_debug()
	var txt := ""
	txt += "[color=#7f9ab4]FPS[/color] %s   [color=#7f9ab4]TRIS[/color] %s\n" % [d["fps"], str(d["triangles"])]
	txt += "[color=#7f9ab4]LOCKS[/color] %s   [color=#7f9ab4]BUILD[/color] %s\n" % [str(d["hair locks"]), d["build"]]
	txt += "[color=#7f9ab4]EYE GAP[/color] %s   [color=#7f9ab4]SKULL H[/color] %s" % [d["eye spacing"], d["skull height"]]
	info_label.text = txt


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = maxf(0.26, _dist * 0.91)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = minf(3.2, _dist * 1.09)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.30
		_pitch = clampf(_pitch + mm.relative.y * 0.24, -35.0, 70.0)
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_F:
				reset_view()
			KEY_H:
				_ui_visible = not _ui_visible
				panel_root.visible = _ui_visible
			KEY_F12:
				_save_screenshot()
			KEY_SPACE:
				_on_play()
			KEY_1:
				_on_anim("idle")
			KEY_2:
				_on_anim("glance")
			KEY_O:
				_auto_orbit = not _auto_orbit


func _save_screenshot() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "res://renders/manual_%03d.png" % _shot_index
	img.save_png(path)
	_shot_index += 1
	print("[studio] saved ", ProjectSettings.globalize_path(path))


func snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[studio] saved ", path)