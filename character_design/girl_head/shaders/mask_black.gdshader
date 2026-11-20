shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Black visor plate: smoked ceramic glass across the face.  Fine machined
// scan lines, a cold fresnel rim and a faint thin-film edge.  The camera
// sensors behind it are the only light sources on the face.

uniform vec3 base_color : source_color = vec3(0.006, 0.009, 0.014);
uniform vec3 edge_tint : source_color = vec3(0.200, 0.560, 0.900);
uniform float edge_glow = 0.35;
uniform float scan_scale = 820.0;
uniform float micro_scale = 620.0;
uniform float iridescence = 0.16;
uniform float metallic_value = 0.55;
uniform float roughness_value = 0.15;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	vec3 N = normalize(NORMAL);
	vec3 V = VIEW;
	float r = length(v_uv);
	float scan = 0.5 + 0.5 * sin(v_uv.y * scan_scale);
	float micro = 0.5 + 0.5 * sin(v_uv.x * micro_scale + v_uv.y * 120.0);
	vec3 base = base_color * (0.88 + 0.16 * micro);
	float fres = pow(1.0 - clamp(dot(N, V), 0.0, 1.0), 3.0);
	vec3 irid = 0.5 + 0.5 * cos(6.28318 * (vec3(0.0, 0.33, 0.67) + fres * 2.0));
	ALBEDO = base + irid * iridescence * fres * 0.22;
	METALLIC = metallic_value;
	ROUGHNESS = clamp(roughness_value + 0.05 * scan + 0.04 * micro, 0.06, 0.5);
	EMISSION = edge_tint * (edge_glow * fres * 0.26)
		+ edge_tint * smoothstep(0.62, 1.08, r) * 0.055;
}