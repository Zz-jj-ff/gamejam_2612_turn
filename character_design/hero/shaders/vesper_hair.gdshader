shader_type spatial;
// =============================================================================
// VESPER hair — Chtholly-style blue, filament-resolved
// -----------------------------------------------------------------------------
// Every ribbon is resolved into many separate fine filaments across its width.
// The filament profile carves dark grooves between them, so the surface reads
// as a bundle of strands instead of one smooth plastic sheet.  The lower hem of
// the continuous under-sheet is cut into individual strand tips with ALPHA
// SCISSOR: fragments are discarded outright, the remaining hair writes depth and
// is fully OPAQUE, so nothing behind the hairstyle can bleed through it (the
// old alpha-blended hem was what made the inside of the head visible).
//
// Palette: Chtholly Nota Seniorious — deep marine roots, azure mid-lengths,
// pale cyan tips, with soft near-white lustre running along the strands.
// =============================================================================
render_mode blend_mix, depth_prepass_alpha, cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

uniform float energy = 0.05;
uniform vec3 root_col : source_color = vec3(0.045, 0.170, 0.390);
uniform vec3 mid_col  : source_color = vec3(0.100, 0.360, 0.680);
uniform vec3 tip_col  : source_color = vec3(0.340, 0.660, 0.860);
uniform vec3 sheen_col : source_color = vec3(0.870, 0.965, 1.0);
uniform vec3 shade_col : source_color = vec3(0.020, 0.080, 0.230);

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

void fragment() {
	float t = clamp(UV.y, 0.0, 1.0);
	float u = UV.x;
	float phase = UV2.x;
	float bias = clamp(UV2.y, 0.0, 1.0);
	vec3 vcol = COLOR.rgb;

	// sheet (UV.x >= 1) vs tube (UV.x 0..0.875)
	float is_sheet = step(0.99, u);
	float ufold;
	float fil_count;
	if (is_sheet > 0.5) {
		ufold = clamp((u - 1.0) / 3.0, 0.0, 1.0);
		fil_count = 22.0;
	} else {
		ufold = clamp(u / 0.875, 0.0, 1.0);
		fil_count = 15.0;
	}

	// ---------------------------------------------------------------- filaments
	float fx = ufold * fil_count;
	float fi = floor(fx);
	float ff = fract(fx);
	float fseed = hash11(fi * 1.37 + phase * 7.13);
	float fseed2 = hash11(fi * 4.91 + phase * 2.71);

	// Strand cross-section: a bright rounded core with a dark seam on each side.
	// The narrow profile (0.26..0.62) is what makes neighbouring filaments read
	// as separate hairs rather than one continuous surface.
	float prof = 1.0 - smoothstep(0.30, 0.68, abs(ff - 0.5));

	// ------------------------------------------------------- longitudinal ramp
	float tt = clamp(t + (fseed - 0.5) * 0.05, 0.0, 1.0);
	vec3 col = mix(root_col, mid_col, smoothstep(0.02, 0.58, tt));
	col = mix(col, tip_col, smoothstep(0.46, 1.0, tt));

	// per-lock value bands (Chtholly's hair shows clear lock-to-lock bands)
	float lock_lift = mix(-0.18, 0.14, bias);
	col *= 1.0 + lock_lift;
	col *= 0.94 + 0.12 * fseed;

	// deep grooves between filaments
	col = mix(col, shade_col, (1.0 - prof) * 0.62);

	// ------------------------------------------------------------- soft sheen
	// Long, soft near-white highlight down the middle of each filament plus the
	// pale "angel ring" near the crown.
	float halo_pos = 0.24 + 0.035 * sin(phase * 2.0 + ufold * 6.28318);
	float halo = exp(-pow((t - halo_pos) / 0.115, 2.0));
	float long_sheen = prof * (0.10 + 0.55 * halo) * (0.55 + 0.45 * fseed2);
	col = mix(col, sheen_col, clamp(long_sheen * 0.22, 0.0, 0.34));

	float sheen2 = exp(-pow((t - 0.62) / 0.16, 2.0)) * prof * 0.10;
	col = mix(col, sheen_col, sheen2);

	vec3 N = normalize(NORMAL);
	vec3 V = normalize(VIEW);
	float ndv = clamp(dot(N, V), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 3.0);

	vec3 base = col * vcol;
	base *= mix(0.88, 1.04, smoothstep(0.0, 0.35, t));

	ALBEDO = base * 0.56;
	METALLIC = 0.02;
	ROUGHNESS = mix(0.60, 0.46, smoothstep(0.0, 0.8, t));
	SPECULAR = 0.20;

	vec3 emit = base * energy;
	emit += sheen_col * (fres * 0.04);
	EMISSION = emit;

	// ------------------------------------------------------------- ragged hem
	// The under-sheet is a real slab (front + back, 7.6 mm apart) but its lower
	// edge is cut into strand tips with ALPHA SCISSOR: a hard discard, never a
	// paper-thin translucent film.  Tip depth varies in low-frequency clumps.
	float sheet_alpha = 1.0;
	if (is_sheet > 0.5) {
		float clump = 0.5 + 0.5 * sin(ufold * 9.5 + phase * 0.35);
		float clump2 = 0.5 + 0.5 * sin(ufold * 27.0 + 1.7 + phase * 0.2);
		float tip_rnd = hash11(floor(ufold * 62.0) + phase * 4.7);
		float hem_t = 0.46 + 0.16 * clump + 0.07 * clump2 + 0.05 * tip_rnd;
		sheet_alpha = 1.0 - smoothstep(hem_t - 0.006, hem_t + 0.006, t);
	}
	ALPHA = sheet_alpha;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
