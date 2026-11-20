# ARC // SENTINEL v2 — two-wheel balancer redesign

This document is the contract the implementation is audited against. The old
biped rig is replaced wholesale; only the studio shell (camera / UI / stage) and
the shared mesh kit are reused.

## 1. Silhouette

* Two-wheel balancing machine, no legs, no head.
* Two solid metal wheels (R 0.325 m, W 0.15 m), one per side, no spokes, with a
  full ring of raised metal tread plates (18 per wheel).
* Each wheel is carried by a telescopic strut from the chassis to the inboard
  hub; the coil spring is sleeved directly on the rod and stretches/compresses
  with it. No lever arm crosses the wheel face. Wheel axles stay on the ground
  while the body pitches/rolls/bobs.
* Body is an approximately cylindrical pressure hull whose axis is front/back:
  * front: a small ball-turret camera eye with a retracting barrel;
  * rear: a small domed bulge with a mechanical shield hook;
  * left flank: a long sword sheath;
  * no head, top capped with a machined deck + vents.
* Two 3-ball-joint arms (shoulder / elbow / wrist spheres), 0.80 m total reach.
  Left wrist ends in the shield mount; right wrist ends in a very short arc
  generator head (no hilt). Weapons are part of the last arm segment.
* Palette: black/graphite machined metal + orange-red (accent panels, seams,
  iris, electric blade, shield energy). Metal, not plastic.

## 2. Coordinates

`+X = character left`, `+Y = up`, `+Z = forward`. Ground `y=0`.

| item | value |
| --- | --- |
| wheel radius / width | 0.325 / 0.150 m |
| axle centers | x ±0.450, y 0.325, z 0.000 |
| body root | (0, 0.620, 0) |
| torso pivot | body-local (0, 0.160, 0) |
| hull center | torso-local (0, 0.280, 0), r 0.225, half-length 0.26 |
| camera ball center | torso-local (0, 0.280, 0.310), r 0.115; barrel/pod retracts ≤0.08 m; lens stays outside |
| shoulder pivots | torso-local (±0.270, 0.320, 0.020) |
| upper / fore / tool | 0.480 / 0.400 / 0.130 m (reach 1.010) |
| shield radius / dome | 0.310 / 0.080 m |
| blade length (visual) | 1.030 m |
| camera eye | front centre y ~0.90 m, ball r 0.115 m, barrel r 0.092 m; small retraction only |
| sheath | body-local (0.225, 0.090, 0.180) → (0.235, -0.020, -0.330) |

## 3. Animation set

`rest`, `idle`, `walk`, `attack`, `attack_up`, `defend`, `draw`, `sheathe`.

* `rest` — sword generator docked in the left sheath (blade off), shield hung on
  the rear hook, arms folded low/relaxed. Loop.
* `idle` — weapons deployed: the arm is bent and the blade points up-right; shield low-left/front. Loop.
* `walk` — two-wheel rolling gait: wheel spin, suspension bob, body lean, arm
  counter-swing. Loop.
* `draw` / `sheathe` — one-shot transitions `rest → idle` / `idle → rest`,
  solved with the same analytic arm IK; blade ignites only after it clears the
  sheath.
* `attack` — body-turned overhead cut upper-left → front; the arm/blade line is straight through the finish.
* `attack_up` — rising cut lower-left → upper-right; the arm/blade line is straight at the finish.
* `defend` — shield block for a front-left 45° threat, sword block for a
  front-right 45° threat. No "guard" fallback: both threats always resolve to
  their mandated effector.

All non-transition clips start and end on the idle base pose, so crossfades do
not pop. `rest ↔ idle` only happens through `draw` / `sheathe` (automatic when
`play_anim` is called across that boundary).

## 4. Exact attack constraints

Measured from the analytic blade axis `d` (unit, root space).

### attack (left-back → left-front-up → right-down)

* Windup:
  * generator above the **left** shoulder: tool (0.45, 1.55, −0.05) m;
  * blade direction left-back-up (0.55, 0.50, −0.67);
  * body/torso yaw +12°/+30° — a large left twist.
* Via:
  * blade left-front-up (0.60, 0.45, 0.66);
  * arm and blade collinear (≤6°), full reach.
* Front:
  * blade exactly forward `d = (0, 0, 1)`, arm straight, tip z 2.06 m, chest
    facing front — the blade must travel through the space in front of the body.
* End:
  * blade right-down with **zero front/back** component: `d = (−0.906, −0.423, 0)`;
  * arm and blade collinear (≤6°), tool x −1.18 m / z −0.16 m, tip y 0.20 m;
  * body/torso turn right (−12°/−30°) so this rightward cut is in front of the
    body, not off its front-right.
* The whole start → via → end → follow swing is re-timed by the sword-tip arc
  length with one smooth bell; there are no per-key velocity zeros. Peak tip
  speed 16.2 m/s; peak joint diagnostic 47.7 rad/s (shield arm correction).

### attack_up (lower-left → upper-right)

* Windup:
  * blade horizontal and backward: `d.y ≈ 0`, `d.z < -0.97`;
  * every sampled point of the blade volume has `x > 0.26` (entirely left of
    the hull);
  * tool point low-left: `y < 0.90`, `x > 0.30`.
* End:
  * arm and blade are collinear (≤6° between shoulder→wrist and blade);
  * the whole line is raised 44.93° up-right; the arm is no longer horizontal;
  * blade 45° up-right: `d.x < 0`, `d.y > 0`, angle to horizontal
    `asin(d.y) = 45° ± 5°`.

## 5. Block contract

* Threat A: incoming blade from front-left 45° toward the chest.
  **Effector must be `shield`.** The shield disc plane is orthogonal to the
  threat direction and the threat ray passes through the disc centre (measured
  miss 0.000 m).
* Threat B: incoming blade from front-right 45° toward the chest.
  **Effector must be `sword`.** The threat ray crosses the blade segment
  (measured miss 0.000 m).
* `effector ∈ {shield, sword}` always; the string `guard` / `none` is a test
  failure.
* Runtime plan time < 50 ms; measured 1–5 ms with the baked table; the offline
  bake takes ~20 s and is a build step, not a frame cost.

## 6. Collision contract

Every pair of collision proxies that is not physically connected (same link
chain) must keep positive clearance in every frame of every clip, every
transition and both block poses. Connected pairs (adjacent arm links, wheel ↔
suspension, weapon ↔ its tool) are exempt. Docked pairs (generator ↔ sheath in
`rest`, shield ↔ rear hook in `rest`) are treated as connected while docked.

Proxies: capsules for hull/waist/camera/arms/blade, discs for shield/wheels,
spheres for joints. Clearance = minimum surface distance between proxies.

## 7. Solver

* Two-bone analytic IK with a free swivel angle around the shoulder→wrist axis
  (Korein/Badler style), collision-aware swivel selection; the elbow also
  shares the forearm twist so the wrist stays out of gimbal lock. Joint
  orientations are stored and interpolated as quaternions.
* Wrist (3 DOF) aligns the tool frame exactly; elbow is a pure pitch.
* Tool targets are authored in root space and transformed into torso space, so
  torso yaw/lean participates without breaking the exact end poses.
* Cartesian key poses + collision-aware sampling for the sword arcs; the
  sampled joint trajectory is smoothed and locally time-reparameterized to a
  25 rad/s joint-speed cap for the non-attack clips; the attack uses the smooth tip-speed retime.
* The resulting trajectory table is baked to `data/arc_traj_v2.json` (≈0.7 MB,
  far below the 50 MB budget). Runtime attack/block plan: 1–5 ms. The table is
  signed by the geometry parameters; a geometry change falls back to the
  runtime solver.

## 8. Visual acceptance

* Metal surfaces show procedural brushed streaks, micro-pitting, scratches,
  roughness breakup, edge wear and environment/SSR highlights.
* Renders: hero, front, side, back, rest, idle, walk, attack, attack_up,
  defend-shield, defend-sword, block demos, wheel/camera/metal closeups.
* A vision-capable subagent reviews every animation's decomposed frame strip
  and must report no motion that reads as physically impossible / unnatural for
  the machine.