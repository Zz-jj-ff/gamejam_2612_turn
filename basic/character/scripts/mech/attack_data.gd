extends RefCounted
## VESPER // attack choreography data (2 m frame, 1.25 m plasma greatsword).
##
## All weapon poses live in TORSO space:
##   +X = character right, +Y = up, -Z = forward.
## Poses are patch dictionaries over BASE_POSE; every key only has to spell out
## the channels it changes.  Positions are authored for the small 2 m frame
## (the old 4.2 m prototype numbers were scaled to roughly 45 %).
##
## Clip schema
##   name      : String  -- the id used by get_clip()
##   duration  : float   -- seconds
##   trail     : [t0, t1] -- blade ribbon window
##   keys      : [{t, p}] -- p is a torso-space pose patch
##   lunge     : [[t, metres]] -- forward travel of the body
##   hit_at    : float   -- contact time
##   hit_kind  : "air" | "ground"
##   style     : "twohand" | "side_r" | "back_r" | "spin"
##
## Conventions
##   sword local +Y = blade axis (hilt -> tip)
##   sword local +X = blade width, local +Z = flat-face normal
##   Node3D Euler order is YXZ
##
## Mirroring note: the ready stance is deliberately asymmetric (sword on the
## right hip, waist pre-turned -0.10 rad).  mirrored() flips only the channels
## a key actually authored, so empty t=0 / t=duration keys stay empty and both
## sides share the same neutral stance instead of teleporting the hilt to the
## other hip.  Every authored action key mirrors exactly.

const BLADE_LEN := 1.25
const TAU := PI * 2.0

const BASE_POSE := {
	"ty": -0.10, "tx": 0.0, "tz": 0.0, "hy": 0.04, "hx": -0.02,
	"crouch": 0.0, "lean": 0.0,
	"wpx": 0.20, "wpy": 0.20, "wpz": -0.40,
	"wrx": -0.05, "wry": 0.0, "wrz": 0.10,
}

const CLIP_NAMES := [
	"FRONT_R", "FRONT_L", "RISE_R", "RISE_L",
	"SIDE_THRUST_R", "BACK_THRUST", "HEAVY", "SPIN",
]

# Channels that flip sign under a left/right mirror.  wrx (blade pitch), hx
# (head pitch), crouch and lean are sagittal and stay untouched.
const MIRROR_CHANNELS := ["wpx", "ty", "hy", "wry", "wrz", "tx", "tz"]

# ---------------------------------------------------------------- 1. FRONT_R
# Front diagonal cleave: high right -> low left.  The blade starts over the
# right shoulder, sweeps in front of the chest and finishes across the left hip.
static var FRONT_R: Dictionary = {
	"name": "FRONT_R",
	"duration": 0.84,
	"trail": [0.18, 0.46],
	"keys": [
		{"t": 0.00, "p": {}},
		{"t": 0.18, "p": {
			"ty": -0.34, "tz": 0.06, "tx": 0.03, "hy": 0.30, "hx": -0.04,
			"crouch": 0.05, "lean": -0.03,
			"wpx": 0.30, "wpy": 0.42, "wpz": -0.34,
			"wrx": -0.15, "wry": 0.0, "wrz": -0.32,
		}},
		{"t": 0.30, "p": {
			"ty": 0.28, "tz": -0.08, "tx": -0.05, "hy": -0.22, "hx": 0.04,
			"crouch": 0.09, "lean": 0.07,
			"wpx": 0.04, "wpy": 0.32, "wpz": -0.36,
			"wrx": 0.0, "wry": -1.1713, "wrz": 1.7923,
		}},
		{"t": 0.44, "p": {
			"ty": 0.44, "tz": -0.10, "tx": -0.07, "hy": -0.30, "hx": 0.05,
			"crouch": 0.11, "lean": 0.09,
			"wpx": -0.22, "wpy": 0.20, "wpz": -0.40,
			"wrx": 0.0, "wry": -0.5328, "wrz": 2.0051,
		}},
		{"t": 0.60, "p": {
			"ty": 0.14, "tz": -0.03, "tx": -0.02, "hy": -0.06, "hx": 0.02,
			"crouch": 0.04, "lean": 0.03,
			"wpx": -0.06, "wpy": 0.26, "wpz": -0.38,
			"wrx": 0.0, "wry": -0.30, "wrz": 0.55,
		}},
		{"t": 0.84, "p": {}},
	],
	"lunge": [[0.0, 0.0], [0.14, 0.0], [0.30, 0.34], [0.52, 0.48], [0.84, 0.48]],
	"hit_at": 0.30, "hit_kind": "air", "style": "twohand",
}

# ---------------------------------------------------------------- 2. FRONT_L
# Exact mirror of FRONT_R: high left -> low right.
static var FRONT_L: Dictionary = mirrored(FRONT_R)

# ---------------------------------------------------------------- 3. RISE_R
# Rising fang: low right -> high left, blade dragged up through the front.
static var RISE_R: Dictionary = {
	"name": "RISE_R",
	"duration": 0.78,
	"trail": [0.18, 0.44],
	"keys": [
		{"t": 0.00, "p": {}},
		{"t": 0.16, "p": {
			"ty": -0.32, "tz": 0.05, "tx": 0.02, "hy": 0.26, "hx": 0.06,
			"crouch": 0.18, "lean": -0.05,
			"wpx": 0.32, "wpy": 0.12, "wpz": -0.34,
			"wrx": 0.0, "wry": -2.3731, "wrz": 2.1535,
		}},
		{"t": 0.30, "p": {
			"ty": 0.08, "tz": -0.05, "tx": -0.04, "hy": -0.18, "hx": -0.03,
			"crouch": 0.04, "lean": 0.05,
			"wpx": 0.02, "wpy": 0.36, "wpz": -0.44,
			"wrx": 0.0, "wry": -1.0175, "wrz": 0.9268,
		}},
		{"t": 0.44, "p": {
			"ty": 0.34, "tz": -0.02, "tx": -0.06, "hy": -0.22, "hx": -0.04,
			"crouch": -0.03, "lean": 0.03,
			"wpx": -0.08, "wpy": 0.46, "wpz": -0.34,
			"wrx": 0.0, "wry": -1.0214, "wrz": 0.6112,
		}},
		{"t": 0.60, "p": {
			"ty": 0.12, "tx": -0.01, "hy": 0.04, "crouch": 0.02, "lean": 0.01,
			"wpx": 0.02, "wpy": 0.30, "wpz": -0.38,
			"wrx": 0.0, "wry": -0.60, "wrz": 0.42,
		}},
		{"t": 0.78, "p": {}},
	],
	"lunge": [[0.0, 0.0], [0.12, 0.0], [0.30, 0.30], [0.48, 0.42], [0.78, 0.42]],
	"hit_at": 0.30, "hit_kind": "air", "style": "twohand",
}

# ---------------------------------------------------------------- 4. RISE_L
# Exact mirror of RISE_R: low left -> high right.
static var RISE_L: Dictionary = mirrored(RISE_R)

# ------------------------------------------------------------ 5. SIDE_THRUST_R
# Right-hand side thrust without turning the waist.  The hilt travels straight
# out along +X at shoulder height, blade axis exactly +X, blade face vertical.
# The left hand is released and the rig raises it out of the guard.
static var SIDE_THRUST_R: Dictionary = {
	"name": "SIDE_THRUST_R",
	"duration": 0.82,
	"trail": [0.24, 0.48],
	"keys": [
		{"t": 0.00, "p": {}},
		{"t": 0.14, "p": {
			"ty": -0.02, "tz": 0.03, "tx": 0.02, "hy": 0.14, "crouch": 0.06,
			"lean": -0.02,
			"wpx": 0.18, "wpy": 0.32, "wpz": -0.27,
			"wrx": 0.0, "wry": 1.15, "wrz": -1.5708,
		}},
		{"t": 0.28, "p": {
			"ty": 0.00, "tz": -0.02, "tx": -0.01, "hy": 0.02, "crouch": 0.04,
			"lean": 0.02,
			"wpx": 0.50, "wpy": 0.35, "wpz": -0.22,
			"wrx": 0.0, "wry": 0.35, "wrz": -1.5708,
		}},
		{"t": 0.34, "p": {
			"ty": 0.02, "tz": -0.03, "tx": -0.02, "hy": -0.06, "crouch": 0.04,
			"lean": 0.03,
			"wpx": 0.70, "wpy": 0.35, "wpz": -0.16,
			"wrx": 0.0, "wry": 0.0, "wrz": -1.5708,
		}},
		{"t": 0.46, "p": {
			"ty": 0.02, "tz": -0.03, "tx": -0.02, "hy": -0.06, "crouch": 0.05,
			"lean": 0.04,
			"wpx": 0.70, "wpy": 0.35, "wpz": -0.16,
			"wrx": 0.0, "wry": 0.0, "wrz": -1.5708,
		}},
		{"t": 0.58, "p": {
			"ty": -0.01, "tx": 0.0, "hy": 0.02, "crouch": 0.03, "lean": 0.01,
			"wpx": 0.32, "wpy": 0.30, "wpz": -0.28,
			"wrx": 0.0, "wry": 0.55, "wrz": -1.5708,
		}},
		{"t": 0.82, "p": {}},
	],
	"lunge": [[0.0, 0.0], [0.14, 0.02], [0.30, 0.28], [0.50, 0.36], [0.82, 0.36]],
	"hit_at": 0.34, "hit_kind": "air", "style": "side_r",
}

# ------------------------------------------------------------ 6. BACK_THRUST
# Sword is handed to the right hand; the right arm wraps across the chest,
# the blade sweeps around the LEFT side of the body and stabs backwards.
# The left arm is lifted clear (offhand/left_raise).
static var BACK_THRUST: Dictionary = {
	"name": "BACK_THRUST",
	"duration": 0.96,
	"trail": [0.30, 0.54],
	"keys": [
		{"t": 0.00, "p": {}},
		{"t": 0.16, "p": {
			"ty": -0.06, "tz": 0.04, "tx": 0.03, "hy": 0.16, "hx": 0.02,
			"crouch": 0.05, "lean": -0.02,
			"wpx": 0.04, "wpy": 0.30, "wpz": -0.34,
			"wrx": 0.0, "wry": -0.5229, "wrz": 1.3894,
		}},
		{"t": 0.26, "p": {
			"ty": 0.00, "tz": 0.03, "tx": 0.02, "hy": 0.02, "crouch": 0.06,
			"lean": 0.01,
			"wpx": -0.26, "wpy": 0.28, "wpz": -0.08,
			"wrx": 0.0, "wry": 0.4820, "wrz": 1.4500,
		}},
		{"t": 0.36, "p": {
			"ty": 0.03, "tz": 0.02, "tx": 0.02, "hy": -0.12, "hx": 0.04,
			"crouch": 0.07, "lean": 0.04,
			"wpx": -0.22, "wpy": 0.25, "wpz": 0.18,
			"wrx": 0.0, "wry": 1.2144, "wrz": 1.5210,
		}},
		{"t": 0.50, "p": {
			"ty": 0.04, "tz": 0.02, "tx": 0.02, "hy": -0.14, "hx": 0.04,
			"crouch": 0.06, "lean": 0.05,
			"wpx": -0.23, "wpy": 0.24, "wpz": 0.21,
			"wrx": 0.0, "wry": 1.2144, "wrz": 1.5210,
		}},
		{"t": 0.64, "p": {
			"ty": 0.00, "tz": 0.01, "tx": 0.01, "hy": -0.02, "crouch": 0.04,
			"lean": 0.02,
			"wpx": -0.16, "wpy": 0.28, "wpz": -0.02,
			"wrx": 0.0, "wry": 0.6355, "wrz": 1.4507,
		}},
		{"t": 0.96, "p": {}},
	],
	"lunge": [[0.0, 0.0], [0.16, 0.0], [0.36, 0.18], [0.56, 0.26], [0.96, 0.26]],
	"hit_at": 0.36, "hit_kind": "air", "style": "back_r",
}

# ----------------------------------------------------------------- 7. HEAVY
# Guillotine: raise overhead, arch back, then crouch and slam the tip into the
# ground in front.  wrx drives the whole sagittal arc (up -> forward -> down).
static var HEAVY: Dictionary = {
	"name": "HEAVY",
	"duration": 1.40,
	"trail": [0.46, 0.66],
	"keys": [
		{"t": 0.00, "p": {}},
		{"t": 0.32, "p": {
			"ty": 0.02, "tx": 0.12, "hy": 0.0, "hx": -0.15,
			"crouch": -0.06, "lean": -0.08,
			"wpx": 0.10, "wpy": 0.54, "wpz": -0.34,
			"wrx": 0.42, "wry": 0.0, "wrz": 0.03,
		}},
		{"t": 0.46, "p": {
			"ty": 0.0, "tx": 0.18, "hy": 0.0, "hx": -0.22,
			"crouch": -0.10, "lean": -0.12,
			"wpx": 0.05, "wpy": 0.64, "wpz": -0.34,
			"wrx": 0.72, "wry": 0.0, "wrz": 0.0,
		}},
		{"t": 0.58, "p": {
			"ty": 0.0, "tx": 0.0, "tz": 0.0, "hy": 0.0, "hx": 0.26,
			"crouch": 0.36, "lean": 0.0,
			"wpx": 0.02, "wpy": 0.02, "wpz": -0.34,
			"wrx": -2.95, "wry": 0.0, "wrz": 0.02,
		}},
		{"t": 0.72, "p": {
			"ty": 0.0, "tx": -0.24, "hy": 0.10, "hx": 0.20,
			"crouch": 0.24, "lean": 0.16,
			"wpx": 0.06, "wpy": 0.34, "wpz": -0.34,
			"wrx": -2.42, "wry": 0.0, "wrz": 0.04,
		}},
		{"t": 1.00, "p": {
			"ty": 0.0, "tx": -0.08, "hy": 0.03, "hx": 0.06,
			"crouch": 0.08, "lean": 0.04,
			"wpx": 0.14, "wpy": 0.30, "wpz": -0.38,
			"wrx": -1.35, "wry": 0.0, "wrz": 0.06,
		}},
		{"t": 1.40, "p": {}},
	],
	"lunge": [[0.0, 0.0], [0.44, 0.0], [0.54, 0.16], [0.72, 0.52], [1.40, 0.52]],
	"hit_at": 0.58, "hit_kind": "ground", "style": "twohand",
}

# ------------------------------------------------------------------ 8. SPIN
# Helix storm: waist ty runs 0 -> 2*PI, blade held out horizontally at chest
# height.  Keys 0.30 -> 1.16 are evenly spaced in ty so the mid-spin angular
# velocity is constant (the rig may replace ty with its own trapezoid).
static var SPIN: Dictionary = {
	"name": "SPIN",
	"duration": 1.42,
	"trail": [0.30, 1.20],
	"keys": [
		{"t": 0.00, "p": {}},
		{"t": 0.20, "p": {
			"ty": -0.52, "tz": 0.06, "tx": 0.03, "hy": 0.28,
			"crouch": 0.10, "lean": 0.04,
			"wpx": 0.30, "wpy": 0.34, "wpz": -0.34,
			"wrx": 0.0, "wry": -2.5061, "wrz": 1.4705,
		}},
		{"t": 0.30, "p": {
			"ty": 0.0, "crouch": 0.14, "lean": 0.06,
			"wpx": 0.20, "wpy": 0.36, "wpz": -0.34,
			"wrx": 0.0, "wry": -2.7945, "wrz": 1.5708,
		}},
		{"t": 0.60, "p": {
			"ty": 2.10, "crouch": 0.14, "lean": 0.07,
			"wpx": 0.20, "wpy": 0.36, "wpz": -0.34,
			"wrx": 0.0, "wry": -2.7945, "wrz": 1.5708,
		}},
		{"t": 0.90, "p": {
			"ty": 4.20, "crouch": 0.13, "lean": 0.07,
			"wpx": 0.20, "wpy": 0.36, "wpz": -0.34,
			"wrx": 0.0, "wry": -2.7945, "wrz": 1.5708,
		}},
		{"t": 1.16, "p": {
			"ty": 6.02, "crouch": 0.10, "lean": 0.05,
			"wpx": 0.20, "wpy": 0.36, "wpz": -0.34,
			"wrx": 0.0, "wry": -2.7945, "wrz": 1.5708,
		}},
		{"t": 1.30, "p": {
			"ty": TAU, "tz": -0.02, "crouch": 0.05, "lean": 0.02,
			"wpx": 0.28, "wpy": 0.32, "wpz": -0.34,
			"wrx": 0.0, "wry": -2.2487, "wrz": 1.4202,
		}},
		{"t": 1.42, "p": {"ty": TAU}},
	],
	"lunge": [[0.0, 0.0], [0.20, 0.03], [0.50, 0.30], [0.80, 0.55], [1.10, 0.62], [1.42, 0.62]],
	"hit_at": 0.72, "hit_kind": "air", "style": "spin",
}

# --------------------------------------------------------------------- index
static var CLIPS: Dictionary = {}


static func _static_init() -> void:
	CLIPS = {
		"FRONT_R": FRONT_R,
		"FRONT_L": FRONT_L,
		"RISE_R": RISE_R,
		"RISE_L": RISE_L,
		"SIDE_THRUST_R": SIDE_THRUST_R,
		"BACK_THRUST": BACK_THRUST,
		"HEAVY": HEAVY,
		"SPIN": SPIN,
	}


static func get_clip(name: String) -> Dictionary:
	return CLIPS.get(name, FRONT_R)


## Mix weight for the left hand: 0 = both hands on the hilt, 1 = left hand
## released and raised clear of the weapon.
static func offhand_for(clip_name: String) -> float:
	match clip_name:
		"SIDE_THRUST_R", "BACK_THRUST":
			return 1.0
		_:
			return 0.0


# ------------------------------------------------------------ mirror utility
## Reflect a clip left/right.  Only the channels present in each key are
## flipped; empty keys stay empty, so the mirrored clip enters and leaves
## through the same (asymmetric) ready stance as the original.
static func mirrored(clip: Dictionary) -> Dictionary:
	var out := clip.duplicate(true)
	var src_name := String(out.get("name", ""))
	if src_name.ends_with("_R"):
		out["name"] = src_name.substr(0, src_name.length() - 2) + "_L"
	elif src_name.ends_with("_L"):
		out["name"] = src_name.substr(0, src_name.length() - 2) + "_R"
	var new_keys: Array = []
	for key in out["keys"]:
		var pose: Dictionary = {}
		for ch in key.get("p", {}).keys():
			var v := float(key["p"][ch])
			if ch in MIRROR_CHANNELS:
				v = -v
			pose[ch] = v
		new_keys.append({"t": float(key["t"]), "p": pose})
	out["keys"] = new_keys
	return out


# ---------------------------------------------------------- special helpers
## Core of the right/left side thrust.  u = 0 is the start of the extension,
## u = 1 is full reach.  Hilt stays at shoulder height, blade axis is exactly
## +X * side, blade face vertical.
static func side_thrust_pose(u: float, side: float) -> Dictionary:
	u = clampf(u, 0.0, 1.0)
	var s := signf(side)
	if s == 0.0:
		s = 1.0
	return {
		"wpx": s * lerpf(0.55, 0.70, u),
		"wpy": lerpf(0.37, 0.35, u),
		"wpz": lerpf(-0.26, -0.16, u),
		"wrx": 0.0,
		"wry": 0.0,
		"wrz": -s * PI * 0.5,
	}


## Core of the back thrust.  u = 1 is the contact pose: hilt at the left hip/
## back corner (-0.22, 0.25, 0.18), blade axis (-0.35, 0.05, 0.94) pointing
## behind and slightly left.
static func back_thrust_pose(u: float) -> Dictionary:
	u = clampf(u, 0.0, 1.0)
	var hilt := Vector3(-0.16, 0.30, -0.06).lerp(Vector3(-0.22, 0.25, 0.18), u)
	var axis := Vector3(-0.70, 0.10, 0.71).lerp(Vector3(-0.35, 0.05, 0.94), u).normalized()
	var e := _aim_euler(axis)
	return {
		"wpx": hilt.x, "wpy": hilt.y, "wpz": hilt.z,
		"wrx": e.x, "wry": e.y, "wrz": e.z,
	}


## Euler (YXZ) that aims sword local +Y along `axis` with the blade width as
## close to world up as possible (vertical blade plane).
static func _aim_euler(axis: Vector3) -> Vector3:
	var y := axis.normalized()
	var x := Vector3.UP - y * Vector3.UP.dot(y)
	if x.length_squared() < 0.0001:
		x = Vector3.FORWARD - y * Vector3.FORWARD.dot(y)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z).get_euler(EULER_ORDER_YXZ)