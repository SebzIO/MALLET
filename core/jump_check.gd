class_name JumpCheck
extends RefCounted
## Where does a rider go when they leave the end of a ramp?
## Speed comes from energy: SurfsUp's movement is nearly lossless on ramps (SUCC measured 98-99%), so the speed at
## a height is sqrt(v0^2 + 2 g (y0 - y)) from the plate the rider started on. The flight is plain ballistics with no
## air strafing, the honest baseline: good players can stretch and bend a jump beyond it.

const G := 20.32                       ## m/s^2, SurfsUp gravity (800 u/s^2)
const U := 39.37                       ## SurfsUp units per meter
const START_SPEED := 400.0 / U         ## the start / stage zone caps speed at 400 u/s
const RIDER_BELOW_RIDGE := 2.0         ## riders surf a little below the ridge
const DT := 1.0 / 30.0
const MAX_TIME := 8.0
const CHUNK := 4                       ## steps checked with one ray first (see fly)


## Speed (m/s) at height `y` for a rider who left a plate at height `y0` going `v0`.
static func speed_at(y0: float, v0: float, y: float) -> float:
	return sqrt(maxf(v0 * v0 + 2.0 * G * (y0 - y), 0.0))


## Launch point and unit direction at the end of a sampled ridge.
static func exit_of(ridge: PackedVector3Array) -> Array:
	var n := ridge.size()
	var dir := (ridge[n - 1] - ridge[max(n - 4, 0)]).normalized()
	return [ridge[n - 1] + Vector3(0, -RIDER_BELOW_RIDGE, 0) + dir * 1.5, dir]


## Where to put the next ramp's first ridge point so a rider leaving `exit_point` along `exit_dir` at `speed`
## (m/s) lands on its face after flying `gap` meters horizontally. `side` +1 / -1 picks which face they land on:
## the ridge is moved 3 m sideways so the arc meets the face 3 m out from the ridge, just under its top.
## `slope` is the tan of that face's angle (RampShape.face_slope).
static func next_ramp_start(exit_point: Vector3, exit_dir: Vector3, speed: float, gap: float, side: float,
		slope: float) -> Vector3:
	var v := exit_dir * speed
	var vh := maxf(Vector2(v.x, v.z).length(), 0.5)
	var t := gap / vh
	var land := exit_point + v * t + Vector3.DOWN * 0.5 * G * t * t
	var lateral := Vector3.UP.cross(exit_dir).normalized() * side
	return land + lateral * 3.0 + Vector3(0, 3.0 * slope - 0.6, 0)


## Flies from `from` with velocity `vel`. `volumes` are EntityNodes (kill / teleport / booster boxes) tested by
## containment; solid things are found with rays on collision layer 1 (ramps and platforms).
## Returns {points, outcome: "ramp"/"platform"/"teleport"/"booster"/"kill"/"floor"/"air", label, hit_point}.
## `zones` are [AABB, label, object] goal areas (finish / stage zones) that count as a landing when entered.
static func fly(space: PhysicsDirectSpaceState3D, from: Vector3, vel: Vector3, volumes: Array, kill_y: float,
		ignore: Array = [], zones: Array = []) -> Dictionary:
	var pts := PackedVector3Array([from])
	var p := from
	var v := vel
	var t := 0.0
	while t < MAX_TIME:
		# One ray along the next CHUNK steps first (the arc bends < 3 cm from that line); only where it hits are the
		# steps cast one by one - the same result as stepping every time, for about a quarter of the rays.
		var cp := p
		var cv := v
		var ends := []
		for i in CHUNK:
			var nv := cv + Vector3.DOWN * G * DT
			cp = cp + (cv + nv) * 0.5 * DT
			cv = nv
			ends.append([cp, cv])
		var fine := not space.intersect_ray(PhysicsRayQueryParameters3D.create(p, cp, 1, ignore)).is_empty()
		for e in ends:
			var np: Vector3 = e[0]
			if fine:
				var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, np, 1, ignore))
				if hit:
					pts.append(hit.position)
					var c: Object = hit.collider
					if c.has_meta("ramp"):
						var surfable: bool = hit.normal.y < 0.7 and hit.normal.y > 0.0
						return {"points": pts, "outcome": "ramp" if surfable else "floor", "hit_point": hit.position,
							"label": "lands on a ramp" if surfable else "lands on top of a ramp (flat: they'd stop)", "target": c.get_meta("ramp")}
					if c.has_meta("entity"):
						var en = c.get_meta("entity")
						return {"points": pts, "outcome": "platform", "hit_point": hit.position, "label": "lands on the " + en.label().to_lower(), "target": en}
					return {"points": pts, "outcome": "floor", "hit_point": hit.position, "label": "hits something", "target": null}
			for z in zones:
				if (z[0] as AABB).has_point(np):
					pts.append(np)
					return {"points": pts, "outcome": "platform", "hit_point": np, "label": z[1], "target": z[2]}
			for vol in volumes:
				if vol.contains(np):
					pts.append(np)
					match vol.kind:
						"kill": return {"points": pts, "outcome": "kill", "hit_point": np, "label": "flies into a kill zone", "target": vol}
						"teleport": return {"points": pts, "outcome": "teleport", "hit_point": np, "label": "reaches the teleport to stage %d" % vol.number, "target": vol}
						"booster": return {"points": pts, "outcome": "booster", "hit_point": np, "label": "reaches a booster", "target": vol}
			if np.y < kill_y:
				pts.append(np)
				return {"points": pts, "outcome": "air", "hit_point": np, "label": "falls to the kill floor", "target": null}
			pts.append(np)
			p = np
			v = e[1]
			t += DT
			if t >= MAX_TIME:
				break
	return {"points": pts, "outcome": "air", "hit_point": p, "label": "still falling after 8 s", "target": null}


static func good(outcome: String) -> bool:
	return outcome in ["ramp", "platform", "teleport", "booster"]
