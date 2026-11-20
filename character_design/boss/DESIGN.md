# LEVIATHAN — design / implementation notes

This document explains *why* the boss is built this way, the math behind the
limbs and the shell, and what the acceptance suite actually measures.

---

## 1. Scale and silhouette

The user asked for a final boss that reads as a **mechanical octopus**, not a
biological one, with the sphere reduced to **2/3** of the earlier 3 m radius and
limbs that are **uniform, thin, long chains**.

| quantity | value |
| --- | --- |
| body radius | **2.00 m** (4.0 m diameter) |
| body centre, supported | **3.70 m** |
| body centre, resting (0 support) | **2.06 m** |
| limb joints | one 0.30 m rod + one ≈0.31 m ball joint, repeating every 0.60 m |
| rod diameter | **0.19 m** |
| ball diameter | **0.31 m** |
| idle limb length | **6.0 m** |
| support limb length | **7.6–8.7 m** (planted) |
| attack 3 length | **15 m** |
| phase-1 aperture | **36.3°** half-angle |
| phase-2 aperture | **100°** half-angle |
| core orb, phase 2 | ≈1.39 m radius plasma shell + 1.27 m solid core |

The visual rule: *one arm segment, one ball joint, repeating*. The chain is
rendered from three instanced meshes per limb (rods, ball joints, emissive joint
rings), each a `MultiMesh`; this makes the eight animated chains cheap and keeps
the silhouette crisp. The rods are dark graphite; the balls are polished steel
with a role-coloured emissive ring. The last 6 cm is a pointed claw.

The body is a sphere with:

- a fixed **rear armour shell** (θ 100°…180° around +Z),
- an **inner liner** (r 2.70–2.76 local) so the opened interior is a dark metal
  cavity rather than a see-through shell,
- **eight iris blades** at r 2.88–2.915 local; each blade is a spherical patch
  from θ 9° to 100°, 48° wide, layer-staggered by 0.005 m so they overlap
  without z-fighting,
- a continuous **aperture guide ring** that follows the aperture edge. The ring
  is a rigid annulus: radius = 2.88·sin(θ_ap), z = 2.88·cos(θ_ap); it covers the
  stepped blade edges, so the eye is framed by a clean circular camera-iris lip
  instead of eight bright “teeth”.

The blades *slide* outward by rotating about the tangent axis at the sphere’s
centre by α (0 → 88°). A spherical patch rotated about the centre stays on the
sphere, so the blades slide under the rear armour and disappear at full open.
The guide ring is a flat annulus perpendicular to the local meridian, scaled by
the aperture radius; it becomes the visible retracted collar at phase 2.

The eye is a gimbal inside the shell: a horizontal ring, a pitch ring and a
dark pod with a red camera-lens shader (coated glass, aperture polygon, iris
scans, hot core). The pod tracks the target with damped yaw/pitch; phase 2
retracts it 0.34 local units and dims the lens so the plasma core takes over.

The phase-2 **plasma core** is a solid red shader sphere (1.45 energy, deep red
with orange filaments) inside an additive plasma shell (1.15 energy) and a
faint additive containment bubble (opacity 0.16). The core light is a red
OmniLight; the gimbal/cage remain as a containment structure. All “energy”
shaders write HDR colour into `ALBEDO` (unshaded additive/mix modes), which is
what actually survives the tonemap in this pipeline.

---

## 2. Limb architecture

Each limb has its own state machine and planner; no animation tracks, no shared
sine. The limb is a 26-point world-space spine, solved every frame.

### 2.1 Modes and transitions

- `idle`: tip rides an arc around the socket; the socket remains the base of the
  arc. `swing` (elevation) and `reach` are independently phased, giving a large
  low lash / high overhead whip. The two front sockets run a **low scissor**
  (azimuth ±0.40 rad, elevation −0.12…0 rad) so they never cross the eye.
- `support`: a foot is chosen in the limb’s own vertical sector at 6.2–7.5 m
  from the current body centre, lifted into a Bézier transition, then **pinned**.
  The target length is fixed at plant time = chord + 2.4 m (minimum 7.4 m, clamped 7–12 m).
- `attack`: one-shot timeline; see §2.4.
- `retract`: when a limb is cut, its target length collapses to 1.2 m, the visual
  root hides after 1 s, and the live count drops.

Idle↔support transitions use a quadratic Bézier tip path with a lift (0.95 s)
so the chain lifts and re-plants rather than teleporting its end.

### 2.2 Curve construction

For a base `B`, tip `T`, base socket direction `u`, target length `L`, tip
approach direction `a`, bow direction `b`:

1. `m0 = normalize(0.75 u + 0.25 u_h) · clamp(0.30 L, 0.9, 3.2)`
2. `m1 = normalize(a) · clamp(0.24 L, 0.7, 2.8)`
3. a cubic Hermite `H(t)` through `B, m0, T, m1`;
4. a perpendicular bow `b⊥ · bow · sin(πt)^0.92`;
5. two travelling waves perpendicular to the chord (`latp`, `bowp`) with
   amplitudes that decay at both ends; `wave_amp` is 0.52 for idle (1.15 and
   1.95 wave cycles), 0.12 for support, near zero during strikes;
6. the bow magnitude is **solved** so the resulting arc length matches `L`
   (8 bisection steps). The expensive Hermite/wave samples are precomputed once
   per frame at 48 samples, so the bisection only rescales the bow term (the
   limb update is a few hundred microseconds for all 8 limbs).

The curve is resampled to 26 equal-arc points and then projected:

- out of the body sphere (`2.035 + radius + 0.02`),
- above the floor (`radius + 0.03`),
- endpoints re-pinned (base on the socket, tip on the foot or attack target).

A light self-clearance pass pushes non-adjacent spine points apart, then
re-projects and re-pins. The mutual pass is a broad-phase AABB check + point
pairs on all overlapping limb pairs with a 0.16 m margin; attacks push their
partners 90 % and themselves 10 %, so they win the contest.

### 2.3 Why idle and support limbs cannot intersect

Each limb is assigned the vertical sector of its socket (≈45° apart). Idle and
support curves are generated with the bow and waves in that sector; the only
shared axis of two adjacent sector planes is the vertical line through the body,
and every spine point is at least `R_body + radius` from it. At the base ring
the sockets are 1.20 m apart with ≤0.31 m collars; in the air the planes diverge
linearly with radius. That gives a **geometric guarantee** for idle/support, and
the scalar collision pass is only a safety net.

Attacks deliberately leave the sector past the outer third of the limb. Attack
3 sweeps at radius ≈9.5 m, while idle tips are limited to ~8 m; the other limbs
also duck (`duck` lowers the idle swing and shortens the reach) while a sweep is
active. At most one attack-3 is allowed at a time.

### 2.4 Attack timelines

| kind | duration | key frames (seconds) | length target |
| --- | --- | --- | --- |
| 1 | 2.45 | windup 0–0.30, thrust 0.30–0.63, hold 0.63–1.00, recover 1.00–2.45 | base→target · 1.05 + 1.15 m |
| 2 | 3.00 | reach 0.15–0.95, hold 0.95–1.20, plunge 1.20–1.45, hold 1.45–1.80, recover 1.80–3.00 | max(overhead, target) + 1.8 m |
| 3 | 3.95 | windup 0–0.55, hold 0.55–0.75, sweep 0.75–2.30 (140°), dive 2.30–2.75, hold 2.75–3.05, recover 3.05–3.95 | 15 m |

Attack 1 freezes the strike line at the current tip and the target **at start**,
as requested (“along the line from the current endpoint to the player”). The
strike is kinematic (no spring lag) so the tip lands exactly; the recoil is
smoothed. Attack 2 uses a quadratic Bézier to a point 5.4 m above the target,
then a straight vertical plunge. Attack 3 orbits the tip at a target-aware radius (9.0–10.8 m, clamped from the
target's horizontal distance), 7 cm above the body centre +1.7 m, with a
tangential approach, then dives onto the target for a finish hit. The other
limbs duck while a sweep is active.

The joint rings/role glow are updated per limb: idle orange, support amber,
attack hot red; the tip heat increases during the strike. The trail ribbon is
built from the last ~30 sampled tip positions; attack 3 gets a wider ribbon.

---

## 3. Role scheduler and support

Every 2 s, if auto roles are on:

1. collect live limbs not currently attacking;
2. pick two at random;
3. each gets a weighted role (idle 0.52 / support 0.16 / attack 0.16 with caps);
   if the result equals the current role, it is nudged to the alternative;
4. clamp support ≤ 5 and attacks ≤ 2; a “no attack for 8 s” rule forces an
   attack so the boss never stalls.

An attack occupies its role slot until the timeline ends; then the limb becomes
idle and the slot frees. Support assignment plants a foot; support removal lifts
it. The body target height is:

`H = 2.06 + (3.70 − 2.06) · clamp(support_count / 3, 0, 1)`

so 0 supports rests on the floor, 3+ stands; the value is rate-limited at
0.62 m/s. The body also drifts on a slow 3-D Lissajous within the 2 m budget
(default 1.15 m horizontal + 0.16 m vertical), with tiny roll/pitch/yaw. For QA
and the support shots a 1.2 m circle / 10 s mode is used.

**Constant-length support**: the foot is pinned but the body moves; the chord
changes; the solver changes the bow to keep the arc length at the planted L.
The QA found **0.52 %** worst-limb length variation and **0.000 m** foot slip
over two circles (22 s). The limb also holds a **1.25 m** minimum chord
deviation, so it is never a straight strut.

---

## 4. Phases and laser

`phase = 2` if `live <= 3` or the UI forces it. The shell target opens from
0.30 to 1.00 at 0.22/s; the core transforms at 0.65/s. Phase-2 entry spawns a
shock ring. At `shell_t > 0.90` and `phase2_t > 0.5` the laser is armed; auto
fire every 6.2 s, or `FIRE LASER`/`fire_laser()`.

Laser sequence: charge 0.95 s (orb charge 0→1, red light), fire 0.72 s (two
additive cylinders from the core toward the target, plus a muzzle quad and an
impact), cool 0.55 s. The beam endpoint is `origin + dir·distance`; the QA
verifies it is within 0.35 m of the target (it is exact by construction).

The red energy shaders are unshaded; their HDR output is written to `ALBEDO`
because an `EMISSION`-only unshaded material did not survive the tonemap in this
render path. This is a deliberate implementation detail, not a physical light.

---

## 5. Rendering

- Forward+, MSAA 4×, ACES, glow, SSR, SSAO, volumetric fog (low density).
- All metal is the procedural `boss_metal` shader (object-space triplanar noise,
  brushed micro-grooves, pits, sparse scratches, fresnel edge wear).
- The arena floor is a custom polar-ring shader; a 15.2 m service plate, 8
  pylons, 22 horizon monoliths, neon bars, haze motes and a reflection probe.
- The boss's dynamic parts are:
  - 8 × `MultiMeshInstance3D` for rods (≤ 32 instances each),
  - 8 × ball joints,
  - 8 × emissive joint rings,
  - 8 tip claws + tip rings,
  - 8-blade pivots (MeshInstances), the guide ring, the gimbal, the core, the
    glass, the beam, the impact pool and the trail ribbons.
- Per-frame sim cost measured by QA: **3.56 ms** at 60 Hz on this machine
  (headless, no render). Mesh pools update transforms, not vertices.

The screenshot suite is deterministic (manual `sim_step(1/60)`, fixed roles and
targets) and writes 227 PNGs in `renders/shots/` plus eleven contact sheets.

---

## 6. Acceptance and limits

The headless suite (`scenes/qa.tscn`) runs 46 checks at 60 Hz with a fixed seed:
idle clearance/waving/speed, support clearance/pin/length/bend/circle, three
attack types on three targets, scheduler caps/rotation, phase transition, laser
terminal point, and a perf budget. It currently reports **PASS / 0 failures** (46/46).
The JSON is `renders/qa_report.json`.

Motion stiffness is *not* a numeric claim: the continuous frames (0.13–0.25 s
apart) and contact sheets are provided for direct human review. An earlier
preliminary reviewer pass flagged foot-contact visibility, idle amplitude,
attack-1 bloom and attack-3 target reach; those were addressed before the final
render set (contact rings/shadows on the planted feet, stronger travelling
S-wave and closer idle camera, reduced role bloom/trail, target-aware sweep with
a downward finish). No independent verdict is shipped with this build.

Known trade-offs:

- the chain is a spline dressed with rigid links; it is not a physical rigid
  body chain with ball-joint constraints;
- the shell blades hide under the rear armour at full open; the guide ring is
  the visible collar;
- the containment wall is additive, not refractive glass;
- the laser/impacts are visual only;
- the support-length result is validated at 1.2 m body drift; the 2 m design
  budget has less slack, and the 5-support configuration is the binding case.