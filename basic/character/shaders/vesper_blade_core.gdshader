shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled;

// =============================================================================
// VESPER // greatsword plasma core
// Flat, faceted blade: white-hot plasma at the guard, electric blue through
// the body, an icy edge at the point. UV.y runs guard (0) -> tip (1).
// Unshaded HDR output feeds the environment glow/bloom pass. The additive
// shell (vesper_blade_glow) supplies the blue outer aura.
// =============================================================================

uniform vec4 hot_color : source_color = vec4(0.88, 0.96, 1.0, 1.0);
uniform vec4 mid_color : source_color = vec4(0.10, 0.36, 1.0, 1.0);
uniform vec4 tip_color : source_color = vec4(0.62, 0.90, 1.0, 1.0);
uniform float energy = 4.2;
uniform float core_boost : hint_range(0.0, 1.0) = 0.55;
uniform float scan_scale = 26.0;
uniform float flow_speed = 14.0;
uniform float scan_strength : hint_range(0.0, 1.0) = 0.16;

void fragment() {
	float t = UV.y;

	// guard -> body -> point gradient
	vec3 col = mix(hot_color.rgb, mid_color.rgb, smoothstep(0.02, 0.34, t));
	col = mix(col, tip_color.rgb, smoothstep(0.70, 1.0, t));

	// flat faces facing the camera read as the white-hot core; grazing
	// faces stay saturated blue so the silhouette reads as plasma.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float core = pow(facing, 2.2);
	col = mix(col, hot_color.rgb, core * core_boost);

	// travelling energy flow + fine scan bands
	float flow = 0.90 + 0.10 * sin(t * 7.0 - TIME * 2.0 + sin(TIME * 1.7) * 1.5);
	float bands = 1.0 + scan_strength * sin(t * scan_scale - TIME * flow_speed);
	float jitter = 0.97 + 0.03 * sin(TIME * 47.0 + t * 13.0);

	// bright sweep racing up the blade
	float sweep_t = fract(TIME * 0.33);
	float sweep = smoothstep(0.055, 0.0, abs(t - sweep_t)) * 0.55;

	vec3 out_col = col * energy * flow * bands * jitter;
	out_col += hot_color.rgb * sweep * energy * 0.35;
	ALBEDO = out_col;
	ALPHA = 1.0;
}