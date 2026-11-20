extends RefCounted
class_name HeadMaterials
## All materials are created here from shaders + math.  No textures.

const FACE := preload("res://shaders/face_shell.gdshader")
const HAIR := preload("res://shaders/hair_silver.gdshader")
const LENS := preload("res://shaders/eye_lens.gdshader")
const IRIS := preload("res://shaders/eye_iris.gdshader")
const MASK := preload("res://shaders/mask_black.gdshader")


static func pbr(albedo: Color, metallic: float, roughness: float,
		rim := 0.0, rim_tint := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metallic
	m.roughness = roughness
	if rim > 0.0:
		m.rim_enabled = true
		m.rim = rim
		m.rim_tint = rim_tint
	return m


static func face(blush := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FACE
	m.set_shader_parameter("blush_amount", blush)
	return m


static func hair() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HAIR
	return m


static func mask_black() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = MASK
	return m


static func eye_lens() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LENS
	return m


static func eye_iris() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = IRIS
	return m


## Dark precision hardware: eye bezel, neck column, panel gaps.
static func graphite() -> StandardMaterial3D:
	return pbr(Color(0.020, 0.022, 0.028), 0.55, 0.34, 0.25, 0.6)


static func graphite_soft() -> StandardMaterial3D:
	return pbr(Color(0.045, 0.048, 0.056), 0.72, 0.46)


static func face_panel_dark() -> StandardMaterial3D:
	return pbr(Color(0.300, 0.318, 0.360), 0.86, 0.30, 0.35, 0.6)


static func trim_mid() -> StandardMaterial3D:
	return pbr(Color(0.300, 0.315, 0.350), 1.0, 0.30, 0.30, 0.55)


static func trim_bright() -> StandardMaterial3D:
	return pbr(Color(0.560, 0.585, 0.630), 1.0, 0.24, 0.40, 0.6)


static func lip_metal() -> StandardMaterial3D:
	return pbr(Color(0.235, 0.185, 0.195), 0.72, 0.26, 0.45, 0.7)


static func eye_rim() -> StandardMaterial3D:
	return pbr(Color(0.500, 0.520, 0.570), 0.35, 0.42, 0.25, 0.6)


static func brow_metal() -> StandardMaterial3D:
	return pbr(Color(0.130, 0.132, 0.148), 0.35, 0.48, 0.15, 0.7)


static func eye_white_gloss() -> StandardMaterial3D:
	return pbr(Color(0.830, 0.860, 0.910), 0.35, 0.08, 0.30, 0.5)


static func undercap() -> StandardMaterial3D:
	return pbr(Color(0.075, 0.080, 0.095), 0.45, 0.55)


static func emissive(color: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.5)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.metallic = 0.2
	m.roughness = 0.4
	m.disable_receive_shadows = true
	return m


static func backdrop() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/backdrop.gdshader")
	return m