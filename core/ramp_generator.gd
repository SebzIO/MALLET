class_name RampGenerator
extends RefCounted
## Ready-made ramp shapes. Each one is an ordinary ramp afterwards: a handful of control points (drag them like
## any other ramp). Shapes are built in a local frame (start at the origin,
## heading along -Z, "right" = +X) and then placed at a start point and heading.

const SHAPES := {
	"spiral": {"label": "Spiral", "about": "Winds down around a centre point, like a helter-skelter.",
		"params": [["radius", "Radius (m)", 30.0, 300.0, 5.0, 90.0], ["turns", "Turns", 0.25, 3.0, 0.05, 0.75],
			["drop", "Drop (m)", 0.0, 400.0, 5.0, 90.0], ["hand", "Turn to the right", 0.0, 1.0, 1.0, 1.0]]},
	"s_curve": {"label": "S-curve", "about": "Snakes left and right as it falls.",
		"params": [["length", "Length (m)", 60.0, 800.0, 10.0, 260.0], ["bends", "Bends", 1.0, 8.0, 1.0, 2.0],
			["sway", "Sway (m)", 5.0, 120.0, 1.0, 30.0], ["drop", "Drop (m)", 0.0, 400.0, 5.0, 70.0]]},
	"rollers": {"label": "Rollers", "about": "Rises and falls in waves on the way down: hills to pump over.",
		"params": [["length", "Length (m)", 60.0, 800.0, 10.0, 300.0], ["waves", "Waves", 1.0, 10.0, 1.0, 3.0],
			["wave_height", "Wave height (m)", 1.0, 60.0, 0.5, 8.0], ["drop", "Drop (m)", 0.0, 400.0, 5.0, 80.0]]},
}
const SHAPE_ORDER := ["spiral", "s_curve", "rollers"]
## Every shape starts with a straight run-in lined up with the way the rider arrives, so fast and slow jumps
## (which land at different distances) both come down on the same line.
const RUN_IN := ["run_in", "Straight start (m)", 0.0, 150.0, 5.0, 40.0]


static func params(shape: String) -> Array:
	return [RUN_IN] + SHAPES[shape]["params"]


static func defaults(shape: String) -> Dictionary:
	var d := {}
	for p in params(shape):
		d[p[0]] = p[5]
	return d


## Returns {"points": PackedVector3Array (world)}. `yaw_deg` is the heading at the start
## (0 = towards -Z, positive turns left, matching Node3D rotation about +Y).
static func generate(shape: String, p: Dictionary, start: Vector3, yaw_deg: float) -> Dictionary:
	var local := PackedVector3Array()
	match shape:
		"spiral":
			var r: float = p["radius"]
			var side := 1.0 if p.get("hand", 1.0) >= 0.5 else -1.0
			var total: float = TAU * float(p["turns"])
			var n: int = max(3, int(ceil(total / (TAU / 8.0))) + 1)       # 8 control points per full turn
			var centre := Vector3(side * r, 0, 0)
			for i in n:
				var a := total * i / (n - 1)
				# start at the origin heading -Z, circling the centre on the chosen side
				local.append(centre + Vector3(-side * r * cos(a), 0, -r * sin(a)) + Vector3(0, -float(p["drop"]) * i / (n - 1), 0))
		"s_curve":
			var bends: int = int(p["bends"])
			var n := bends * 4 + 1
			for i in n:
				var t := float(i) / (n - 1)
				local.append(Vector3(float(p["sway"]) * sin(PI * bends * t), -float(p["drop"]) * t, -float(p["length"]) * t))
		"rollers":
			var waves: int = int(p["waves"])
			var n := waves * 4 + 1
			for i in n:
				var t := float(i) / (n - 1)
				var bump := float(p["wave_height"]) * pow(sin(PI * waves * t), 2.0)
				local.append(Vector3(0, -float(p["drop"]) * t + bump, -float(p["length"]) * t))
	var run_in: float = p.get("run_in", 0.0)
	if run_in > 0.5 and local.size() >= 2:
		# straight lead-in at the shape's own opening slope, then the shape
		var slope := (local[0].y - local[1].y) / maxf(Vector2(local[1].x - local[0].x, local[1].z - local[0].z).length(), 0.01)
		slope = clampf(slope, 0.1, 0.6)
		var shift := Vector3(0, -run_in * slope, -run_in)
		var with_run := PackedVector3Array([Vector3.ZERO])
		if run_in > 60.0:
			with_run.append(shift * 0.5)
		for q in local:
			with_run.append(q + shift)
		local = with_run
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var out := PackedVector3Array()
	for q in local:
		out.append(start + b * q)
	return {"points": out}


## Highest point the rider must climb back over, measured against the height they started from (rollers):
## > 0 means a crest sits above the start, so a slow rider can stall on it.
static func crest_above_start(points: PackedVector3Array) -> float:
	var worst := -INF
	for i in range(1, points.size()):
		worst = maxf(worst, points[i].y - points[0].y)
	return worst
