# LEVIATHAN // ABYSSAL WARDEN

A code-generated **final boss**: a mechanical octopus built around a 2 m-radius
armoured sphere (4 m diameter), with **eight independent jointed chains**, a
gimballed red **camera eye**, an iris shell with two phases, a red **energy core**
and a **laser**. Everything — meshes, materials, shaders, motion, scheduling,
FX — is generated at runtime. No imported meshes, textures, fonts or audio.

| | |
| --- | --- |
| Engine | Godot **4.7.2**, Forward+ |
| Body | 2.0 m radius sphere, 4.0 m diameter |
| Limbs | 8 · alternating ~0.30 m arm link + ~0.31 m ball joint |
| Limb lengths | idle **15.0 m** (2.5×) · support 7.5–8.8 m · attack 3 **15 m** |
| Role cap | default ≤ 2 attacks · ≤ 5 supports · rest idle · 2 re-tasks / 2 s |
| Phases | 1 = camera eye through aperture · 2 = shell fully open, red core + laser |
| QA | **49 / 49 PASS**, 0 failures · 6.09 ms per 60 Hz sim step (CPU) |

---

## Quick start

```bash
cd boss
./run.sh                       # or: godot --path .
godot --headless --path . --import         # first time only
godot --headless --path . res://scenes/qa.tscn       # acceptance suite
DISPLAY=:10 godot --path . res://scenes/shots.tscn   # deterministic render suite
python3 compose_sheets.py                            # contact sheets
```

The default scene is `scenes/studio.tscn`. The right panel drives roles, phase,
target, limb dynamics and live parameters.

**Controls:** LMB/RMB drag orbit · wheel zoom · `F` reset camera · `H` hide UI ·
`SPACE` pause · `1`–`8` select a limb · `I` idle · `U` support · `J/K/L`
attack 1/2/3 · `C` cut a limb · `P` toggle phase · `A` auto roles · `N` move the
target · `R` reset boss · `F12` screenshot.

---

## What is on screen

### Body and shell

The body is a sphere with a **fixed rear armour shell** and an **8-blade iris**
recessed inside it. The blades slide outward and disappear under the rear
armour; a continuous machined **guide ring** follows the aperture edge, so the
opening is always a clean mechanical circle.

- Phase 1: aperture **36.3°** per side; the red camera eye is visible through a
  large camera-iris hole; the plasma core is cold.
- Phase 2: aperture **100°** per side, shell blades fully retracted, the red
  plasma core ignites, a faint **transparent containment wall** fades in, and the
  eye pod retracts/dims behind the core. The laser becomes available.

The eye is a real gimbal: a heavy ring + pitch ring + lens pod that tracks the
target inside the shell, using the same red camera-lens shader family as
`arc_sentinel` / `shard_phantom`.

### Limbs

Each limb is a **mechanical chain**, not an octopus arm:

- one ~0.30 m dark graphite arm rod (thin cylinder, ≈0.19 m diameter),
- one ~0.31 m polished steel **ball joint** (≈0.31 m diameter) with an emissive
  role ring,
- repeated every 0.60 m along the limb. The ball joints are the visible pivots;
  the limb bends at the joints, and the rods remain rigid.
- two **fixed root balls** at 0.38 m and 1.00 m on the socket axis: the chain
  visibly comes straight out of the hole for the first metre, then follows the
  curve.

There are no suckers, no tapering over the length, no organic skin. The last
0.06 m is a small pointed claw/end effector. The chain is driven by
`MultiMeshInstance3D` pools (rods + balls + emissive joint rings), so the
animated silhouettes cost almost nothing to render and update.

### Root telescoping and length

The joint pattern is **anchored to the tip**, not the socket. When a limb
extends, the extra length appears between the socket and the first visible
joint: the chain telescopes out of the hole, and **new links appear at the
root**. Retraction is swallowed by the socket the same way; the tip-side
pattern stays intact. The two fixed root balls keep the first metre centred in
the hole.

The telescoping rate, idle length, acceleration cap and minimum bend radius are
all live parameters (`telescope rate`, `idle length`, `joint accel cap`,
`min bend radius`).

### Role behaviour

At any instant the boss enforces the configured caps (default **≤ 2 attacks** and
**≤ 5 supports**); the rest are idle. Every 2 s the scheduler re-tasks **two
random eligible limbs**. Attacks are one-shot actions; support↔idle changes
blend through a lifted Bézier tip path. When a support is assigned, a foot is
planted in the limb's own vertical sector and stays fixed until the role changes.

- **idle** (15 m): a large low lash / high overhead whip (~12 s period) plus a
  faster secondary lash and a travelling S-wave along the chain. The two front
  limbs perform a fast low scissor below the aperture so the eye is never crossed
  by its own arm. The idle/support vertical sectors are hard-clamped so adjacent
  limbs cannot cross near the base.
- **support** (≈7.5–8.8 m): foot planted; the body can drift on a 1.2 m circle
  while the solver changes the limb's bow; the QA measures **2.28 %** length
  variation and **0.000 m** foot slip, with a **1.31 m** minimum chord deviation
  (never a straight strut).
- **attack 1**: first the end of the limb is **pre-aimed** along the frozen
  start-tip→target line (last-segment dot **0.998**), then it accelerates from
  rest to the target, passes **through** it and decelerates over a configurable
  overshoot (2.2 m). QA closest sample 0.05–0.15 m at 60 Hz.
- **attack 2**: the tip arcs to a point **5.4 m above** the target, holds with
  the end pointing **straight down** (down dot **1.000**), then accelerates down,
  passes through the chest and decelerates below it. QA hit 0.256 m sample.
- **attack 3**: the limb extends to its full 15 m, sets the sweep height
  (default **4.2 m**), then performs a **full 360°** horizontal sweep around the
  body, with the side of the chain doing the cutting (tangential approach).
  QA measured **359.4°** at **11.0 m** tip radius, **4.2 m** height.
- **laser**: only in phase 2 with the shell fully open. 0.95 s charge, 0.72 s
  fire, aimed through the core at the target; QA beam **12.2 m**, endpoint on
  target.

When **3 or fewer limbs remain**, phase 2 starts automatically. The UI has
`CUT LIMB` and `PHASE 1/2` preview buttons. With **0 supports** the sphere
settles onto the ground; with 1–2 it lowers; with **3+** it stands (body centre
3.70 m, resting 2.06 m).

### Dynamics

Every limb is a 40-point spine with:

- a curvature cap (`min bend radius`, default 0.95 m) applied to the target
  curve;
- a per-point acceleration cap (`joint accel cap`, default 110 m/s²) on the
  spring-driven spine;
- a stable FABRIK length pass with base/tip pinned (so support lengths stay
  fixed through role changes and body motion);
- attack/ground/body/sector projections, with the first two links of an attack
  forced straight along the strike or plunge direction;
- a hard vertical-sector clamp for idle/support, which—together with the
  per-limb sockets and the collision pass—keeps adjacent limbs from crossing.

---

## Acceptance

Run `godot --headless --path . res://scenes/qa.tscn`. It steps the simulation at
a fixed 60 Hz with a fixed seed (261218) and measures the actual spines, not the
rendered images:

| check | result |
| --- | --- |
| idle: mutual clearance (8 limbs) | **+0.288 m** min capsule gap |
| idle: self clearance | **+0.317 m** |
| idle: body / ground clearance | **+0.031 m / +0.152 m** |
| idle: large, continuous waving | **8.21 m** 3D tip range, ≤5.5 m/s |
| support: mutual / self clearance | **+0.237 m / +0.150 m** |
| support: foot pin / ground | **0.000 m slip / +0.070 m** |
| support: constant length | **2.28 %** worst limb |
| support: bent, not a strut | **1.31 m** minimum chord deviation |
| support: body circle | **1.20 m** radius, 10 s period |
| attack 1: straight line | **0.000 m** deviation from the frozen line |
| attack 1: pre-aimed tip | last-segment dot **0.998** |
| attack 1: hit | **0.05–0.15 m** closest 60 Hz sample |
| attack 2: over → down | **5.46 m** above target, down dot **1.000** |
| attack 2: hit | **0.256 m** closest sample |
| attack 3: full sweep | **359.4°** at **11.0 m**, height **4.2 m** |
| scheduler | max 2 attacks / 5 support, **0** cap violations |
| phase 2 at 3 limbs | shell 0.30 → **1.00**, aperture 36.3° → **100°**, core 1.0 |
| laser | **12.2 m**, endpoint within 0.35 m of the target |
| performance | **6.09 ms** per 60 Hz sim step (CPU, no render) |

The full JSON is in `renders/qa_report.json`.

### Visual material (for direct review)

The deterministic render suite writes continuous sequences (0.1–0.25 s apart)
and labelled contact sheets. An independent vision subagent was stopped before
writing a verdict at the user's request; no independent verdict is shipped.
The evidence is for the user's own review:

- `idle/` 30 frames, `idle_top/` 20 — 15 m waving and top clearance;
- `support/` 30, `support_side/` 20, `support_feet/` 10 — planted feet, circles;
- `telescope_idle/` 8, `telescope_in/` 16, `telescope_out/` 16 — root
  telescoping on one limb;
- `attack1/` 22, `attack2/` 26, `attack3/` 28 — the three attacks;
- `phase2_open/` 18 + `phase1/`, `phase2/` stills + `laser/` 14.

The attack sheets share one camera; the attack 3 sheet uses a high 3/4 camera to
show the full 360°. `renders/shots/MANIFEST.txt` records the generation time,
frame counts and cameras.

---

## Files

```text
boss/
  project.godot · run.sh
  scenes/             studio (main), character, qa, shots, probe, debug_probe
  scripts/
    boss/
      boss.gd         contract, scheduler, phases, laser, FX, QA/shot API
      boss_rig.gd     shell, iris + guide ring, sockets, gimbal eye, core, glass
      tentacle.gd     per-limb planner, curvature/accel solver, telescoping chain
      boss_materials.gd
    boss_stage.gd     arena, lights, environment
    target_dummy.gd   the small cyan scout target
    boss_studio.gd    camera, panel, controls, overlays
    qa.gd             headless acceptance suite
    shots.gd          deterministic sequences
    probe.gd / debug_probe.gd   development probes
  shaders/            procedural metal, lens, shell glass, plasma core/orb,
                      laser, floor, screen grade, trail
  renders/
    qa_report.json    49/49 PASS
    sheets/           labelled contact sheets
    shots/            sequences + MANIFEST.txt
  README.md / DESIGN.md
```

---

## Honest limitations

- The limb is a spline dressed with rigid rods and ball joints. The ball joints
  are visually the pivots; this is not a physical 3-DOF rigid-body chain. The
  acceleration cap applies to the spine points, not literal joint torque limits.
- The curvature cap is a target-curve/point-space constraint; extreme user
  parameter combinations can still look tight or coil near the body.
- The iris blades slide under the rear shell; their visible phase-2 collar is the
  guide ring + rear armour.
- The containment wall is additive, not refractive glass.
- Attack 3 is a full 360° sweep at the configured height (default 4.2 m); it is
  deliberately above the ground, so a 2 m ground target is not hit by it. Use the
  sweep-height parameter to set the band you want.
- Support-length invariance was validated for a 1.2 m circular body drift; the
  2 m design budget has less slack.
- The QA clearance numbers use a capsule proxy per segment; visual review remains
  the final judge.
- This is a stylized procedural game asset, not a 3A film asset.