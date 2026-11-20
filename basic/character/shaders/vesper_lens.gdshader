shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// =============================================================================
// VESPER // optical lens
// Black coated glass with an electric-blue iris, a hot inner core, a slow
// scanning wedge and a crisp specular glint.
//
// Shape-agnostic: the iris is projected in object space on the local XZ plane
// (works for a disc / dome / prism cap whose optical axis is local Y) and is
// masked by the object-space normal so it never smears over the barrel. A
// fresnel ring keeps the rim of the optic alive on any other shape.
// =============================================================================

uniform vec4 glass_color : source_color = vec4(0.006, 0.010, 0.018, 1.0);
uniform vec4 iris_color : source_color = vec4(0.16, 0.44, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(0.78, 0.92, 1.0, 1.0);
uniform float intensity = 3.6;
uniform float lens_radius = 0.080;
uniform float pupil_radius : hint_range(0.0, 1.0) = 0.34;
uniform float iris_radius : hint_range(0.0, 1.0) = 0.62;
uniform float blade_count = 7.0;
uniform float scan_speed = 0.7;
uniform float seed = 0.0;
uniform float glint_strength : hint_range(0.0, 4.0) = 1.1;

varying vec3 opos;
varying vec3 onrm;

void vertex() {
	opos = VERTEX;
	onrm = normalize(NORMAL);
}

void fragment() {
	// --- object-space polar coordinates around the optical axis (local Y) --
	vec2 p = opos.xz / max(lens_radius, 0.001);
	float r = clamp(length(p), 0.0, 1.4);
	float ang = atan(p.y, p.x);
	float axial = smoothstep(0.50, 0.92, abs(onrm.y));

	// iris aperture: a soft annulus with faceted blade seams
	float iris = smoothstep(pupil_radius * 1.22, pupil_radius * 1.02, r)
			* smoothstep(iris_radius * 0.82, iris_radius * 1.04, r);
	float seam = pow(0.5 + 0.5 * cos(ang * blade_count + seed), 18.0);
	float blades = seam * smoothstep(iris_radius, pupil_radius, r) * 0.35;

	// hot inner ring just inside the pupil edge
	float core_ring = smoothstep(pupil_radius * 1.06, pupil_radius * 0.96, r)
			* smoothstep(pupil_radius * 0.70, pupil_radius * 0.95, r);

	// faint machined rings on the inner barrel
	float rings = pow(0.5 + 0.5 * cos(r * 40.0), 26.0) * smoothstep(1.05, 0.35, r) * 0.16;

	// scanning wedge that sweeps around the optic
	float sweep = pow(0.5 + 0.5 * cos(ang - TIME * scan_speed + seed), 26.0)
			* smoothstep(1.02, 0.14, r);
	float sweep_soft = pow(0.5 + 0.5 * cos(ang - TIME * scan_speed + seed), 6.0)
			* smoothstep(1.02, 0.22, r) * 0.10;

	float breathe = 0.86 + 0.14 * sin(TIME * 1.9 + seed * 3.0);
	float hot = (iris * (1.15 + 0.25 * breathe) + core_ring * 0.9
			+ blades * 0.35 + rings + sweep * 1.25 + sweep_soft) * axial;

	// --- fallback rim: keeps any lens shape reading as a lit optic ---------
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, 3.0);
	hot += rim * (0.55 + 0.15 * breathe);

	// --- view-space specular glint (reads as a coated-glass highlight) -----
	float glint = pow(max(dot(normalize(NORMAL), normalize(vec3(-0.45, 0.62, 0.64))), 0.0), 42.0);
	glint += pow(max(dot(normalize(NORMAL), normalize(vec3(0.30, 0.78, 0.55))), 0.0), 90.0) * 0.55;

	ALBEDO = glass_color.rgb;
	METALLIC = 0.0;
	ROUGHNESS = 0.14;
	SPECULAR = 0.62;
	EMISSION = iris_color.rgb * intensity * hot
			+ core_color.rgb * intensity * (core_ring * 0.55 + sweep * 0.30) * axial
			+ core_color.rgb * glint * glint_strength;
}