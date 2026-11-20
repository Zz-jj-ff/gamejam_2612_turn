shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Mechanical iris / lens aperture.
// UV is [-1,1] radial across the lens face.  Six-blade shutter, concentric
// optical rings, machined micro-grooves, hot inner ring and a studio
// catchlight arc.  No organic sclera, no eyelids.

uniform vec3 iris_deep : source_color = vec3(0.012, 0.075, 0.135);
uniform vec3 iris_mid : source_color = vec3(0.070, 0.340, 0.560);
uniform vec3 iris_hot : source_color = vec3(0.430, 0.880, 1.000);
uniform vec3 ring_color : source_color = vec3(0.620, 0.940, 1.000);
uniform vec3 shutter_color : source_color = vec3(0.006, 0.010, 0.016);
uniform vec3 catch_color : source_color = vec3(0.900, 0.975, 1.000);
uniform float glow = 0.75;
uniform float aperture = 0.30;
uniform float pulse = 0.0;
uniform float lens_tilt = 0.0;

varying vec2 v_uv;

void vertex() {
	v_uv = UV;
}

void fragment() {
	vec2 p = v_uv;
	float r = length(p);
	if (r > 1.02) {
		discard;
	}
	float ang = atan(p.y, p.x);

	// radial optical fibres / machined grooves
	float fib = 0.5 + 0.5 * sin(ang * 52.0 + sin(ang * 7.0 + 1.3) * 2.6);
	float fib2 = 0.5 + 0.5 * sin(ang * 101.0 - 2.1);
	float radial = 0.5 + 0.5 * sin(r * 74.0 - 0.7);

	vec3 col = mix(iris_hot, iris_mid, smoothstep(0.16, 0.56, r));
	col = mix(col, iris_deep, smoothstep(0.56, 0.97, r));
	col *= 0.82 + 0.26 * mix(fib, fib2, 0.32) + 0.05 * radial;

	// dark metal limbal ring
	col = mix(col, vec3(0.010, 0.024, 0.038), smoothstep(0.83, 0.955, r) * 0.92);
	// optical ring seams
	col += ring_color * smoothstep(0.010, 0.0, abs(r - 0.60)) * 0.08;
	col += ring_color * smoothstep(0.006, 0.0, abs(r - 0.78)) * 0.06;

	// six-blade mechanical aperture
	float blade = aperture * (1.0 + 0.055 * cos(ang * 6.0 + 0.6));
	float shut = smoothstep(blade + 0.030, blade - 0.012, r);
	// blade seams radiating from the aperture
	float seam = smoothstep(0.03, 0.0, abs(fract(ang / 1.0472 + 0.5) - 0.5))
		* smoothstep(blade + 0.10, blade - 0.01, r) * 0.55;
	col = mix(col, shutter_color, max(shut, seam));

	// hot ring just outside the blades
	col += ring_color * smoothstep(0.016, 0.0, abs(r - (blade + 0.055)))
		* (0.55 + 0.35 * pulse);
	// central pin glow (servo / lens core)
	col += ring_color * smoothstep(0.10, 0.0, r) * 0.10;

	// catchlight arc: upper-left softbox reflection
	vec2 c1 = p - vec2(-0.34, 0.38);
	float h1 = exp(-dot(c1, c1) / 0.020);
	vec2 c2 = p - vec2(0.30, -0.30);
	float h2 = exp(-dot(c2, c2) / 0.0035);
	col += catch_color * (h1 * 0.85 + h2 * 0.30);

	ALBEDO = col * 0.42;
	METALLIC = 0.35;
	ROUGHNESS = 0.12;
	EMISSION = col * glow + catch_color * h1 * 0.35;
}