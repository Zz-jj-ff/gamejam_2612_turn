shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Synthetic porcelain-titanium skin.  No subsurface scattering, no pores:
// a machined ceramic coat with micro grain, a brushed micro-normal and an
// anodized (thin-film) grazing tint.  It must read as a manufactured shell,
// never as human skin.

uniform vec3 base_color : source_color = vec3(0.600, 0.615, 0.655);
uniform vec3 warm_tint : source_color = vec3(0.930, 0.845, 0.795);
uniform vec3 cool_tint : source_color = vec3(0.470, 0.560, 0.720);
uniform vec3 edge_tint : source_color = vec3(0.520, 0.820, 1.000);
uniform float metallic_value = 0.46;
uniform float roughness_value = 0.35;
uniform float micro_amp = 0.006;
uniform float edge_glow = 0.020;
uniform float blush_amount = 0.0;
uniform float blush_y = -0.043;
uniform float brush_scale = 90.0;
uniform float grain_scale = 140.0;

varying vec3 v_obj;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_obj = VERTEX;
}

void fragment() {
	vec3 N = normalize(NORMAL);
	vec3 V = VIEW;
	vec2 uv = UV;

	float g = vnoise(uv * grain_scale);
	float g2 = vnoise(uv * grain_scale * 2.7 + 13.0);
	float brushed = sin(uv.y * brush_scale + g * 7.0 + g2 * 2.0) * 0.5 + 0.5;

	vec3 base = base_color;
	// Manufactured face plate: a pale central mask framed by darker
	// titanium cheek/jaw panels, separated by a crisp machined seam.
	float ty = smoothstep(-0.100, 0.040, v_obj.y);
	float xb = mix(0.0505, 0.0690, ty);
	float side = smoothstep(xb - 0.0007, xb + 0.0007, abs(v_obj.x));
	vec3 side_col = vec3(0.290, 0.305, 0.345);
	float seam_line = 0.0;
	base = mix(base, side_col, side * 0.94);
	base *= 1.0 - side * 0.03;
	// A trace of warm reflective paint on the cheeks — cosmetic, not skin.
	vec2 ax = vec2(abs(v_obj.x), v_obj.y);
	float cheek = smoothstep(0.056, 0.010,
		length((ax - vec2(0.049, blush_y)) * vec2(1.0, 1.25)));
	base = mix(base, warm_tint, cheek * blush_amount * 0.65);
	float hollow = exp(-dot((ax - vec2(0.062, -0.062)) / vec2(0.026, 0.018),
		(ax - vec2(0.062, -0.062)) / vec2(0.026, 0.018)));
	base *= 1.0 - hollow * 0.10;

	float fres = pow(1.0 - clamp(dot(N, V), 0.0, 1.0), 3.2);
	vec3 irid = 0.5 + 0.5 * cos(6.28318 * (vec3(0.0, 0.33, 0.67)
		+ fres * 2.2 + N.y * 0.75));
	base = mix(base, base * 0.45 + irid * 0.62, fres * 0.22);
	base = mix(base, cool_tint, fres * 0.10);

	ALBEDO = base * (0.985 + (g - 0.5) * micro_amp)
		* (0.998 + (brushed - 0.5) * 0.005);
	METALLIC = mix(metallic_value, 0.72, side);
	ROUGHNESS = clamp(roughness_value + (brushed - 0.5) * 0.030
		+ (g2 - 0.5) * 0.045 - side * 0.06, 0.10, 0.72);
	ROUGHNESS = mix(ROUGHNESS, 0.5, seam_line);
	EMISSION = edge_tint * fres * edge_glow;
}