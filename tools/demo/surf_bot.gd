class_name SurfBot
extends RefCounted
## Surfs a map with SUCC (SurfsUp's own movement code) through SUCC.command, the way a good player does:
##   start plate:  run forward and hop off the front edge
##   on a ramp:    look where you're going; ride a line that starts high near the spine, drifts down the face, then
##                 climbs back up near the end for a small flick into the transfer
##   in the air:   predict your own arc and air-strafe so it lands high on the next ramp's face, a few meters in
## Steering is always a strafe key square to your motion (that turns you without costing speed). The technique's
## numbers live in `params` so a trainer can tune them per map (see tools/demo/train_bot.gd).

const DEFAULTS := {
	"top": 1.2,          ## meters out from the spine where a ramp is joined
	"deep": 3.0,         ## deepest point of the line, mid-ramp
	"flick_at": 0.78,    ## fraction of the ramp where the line climbs back up
	"end": 0.9,          ## meters out from the spine at the very end (the flick)
	"land_in": 6.0,      ## meters into the next ramp to land
	"land_out": 1.8,     ## meters out from its spine to land
	"damp": 0.35,        ## how strongly sideways drift is damped while steering
	"air_lead": 1.0,     ## how hard to correct the predicted landing in the air
}
const LOOK_RATE := 14.0          ## how quickly the view turns (1/s): smooth for footage, quick enough not to brake
const RIDE_PITCH := -0.12

var ed
var params := DEFAULTS.duplicate()
var yaw := 0.0
var pitch := 0.0
var on_ramp := false
var _ramps := []                 ## [RampNode, ridge, tangents, rights, cumulative distance]
var _face := 1.0
var _face_ramp = null
var _target_ramp = null          ## the ramp we're flying to
var _landing := Vector3.ZERO


func _init(editor, p := {}) -> void:
	ed = editor
	params.merge(p, true)
	for r in ed.ramps_root.get_children():
		var g: Dictionary = r.geometry
		var ridge: PackedVector3Array = g["ridge"]
		var dist := PackedFloat32Array([0.0])
		for i in range(1, ridge.size()):
			dist.append(dist[i - 1] + ridge[i].distance_to(ridge[i - 1]))
		_ramps.append([r, ridge, g["tan"], g["rights"], dist])


func tick(delta: float) -> void:
	var p: SUCC = ed.play.player
	if p == null:
		return
	if p.command == null:
		p.command = SUCCInput.new()
		yaw = p.rotation.y
	var cmd := p.command
	var pos := p.global_position + Vector3(0, 0.9, 0)
	var vel := p.velocity
	var hv := Vector3(vel.x, 0, vel.z)
	var want_yaw := yaw
	var want_pitch := 0.0
	cmd.move = Vector2.ZERO
	cmd.jump = false
	on_ramp = false
	var plate := _plate_under(p.global_position)
	var near := _nearest(pos)
	if plate:
		want_yaw = deg_to_rad(plate.yaw)
		cmd.move = Vector2(0, -1)
		var local := plate.global_transform.affine_inverse() * p.global_position
		cmd.jump = local.z < -plate.size.z * 0.5 + 1.2 and p.is_on_floor()
		_target_ramp = null
	elif not near.is_empty() and near["dist"] < 8.0 and not near["past_end"]:
		on_ramp = true
		_ride(p, near, cmd)
		want_yaw = atan2(-hv.x, -hv.z) if hv.length() > 3.0 else atan2(-near["tan"].x, -near["tan"].z)
		want_pitch = RIDE_PITCH
	else:
		_fly(p, pos, vel, cmd)
		if hv.length() > 1.0:
			want_yaw = atan2(-hv.x, -hv.z)
		want_pitch = clampf(atan2(vel.y, hv.length()) * 0.5, -0.5, 0.2)
	var k := 1.0 - exp(-delta * LOOK_RATE)
	yaw = lerp_angle(yaw, want_yaw, k)
	pitch = lerpf(pitch, want_pitch, k)
	cmd.yaw = yaw
	cmd.pitch = pitch


## On a ramp: hold the riding line for this point of the ramp.
func _ride(p: SUCC, near: Dictionary, cmd: SUCCInput) -> void:
	var pos := p.global_position + Vector3(0, 0.9, 0)
	var r: Vector3 = near["right"]
	var off: float = (pos - near["point"]).dot(r)
	_target_ramp = null                                 # landed: the next jump picks its own target
	if near["ramp"] != _face_ramp:
		_face_ramp = near["ramp"]
		_face = _face_for(near["ramp"], off)
	var s: float = near["s"]
	var rp: RampNode = near["ramp"]
	var fa := P("flick_at", rp)
	var line: float
	if s < fa:
		line = lerpf(P("top", rp), P("deep", rp), smoothstep(0.0, fa, s))
	else:
		line = lerpf(P("deep", rp), P("end", rp), smoothstep(fa, 1.0, s))
	var vlat: float = p.velocity.dot(r)
	var u: float = (_face * line - off) - vlat * P("damp", rp)
	cmd.move = Vector2(_strafe_sign(u, p, r), 0)
	if p.is_on_floor():
		cmd.jump = true                                 # perched on the spine: hop off towards the face
		cmd.move = Vector2(_strafe_sign(_face, p, r), 0)


## In the air: aim the landing high on the next ramp's face by air-strafing square to our motion.
func _fly(p: SUCC, pos: Vector3, vel: Vector3, cmd: SUCCInput) -> void:
	if _target_ramp == null or not is_instance_valid(_target_ramp):
		_pick_target(pos, vel)
	if _target_ramp == null:
		return
	# where does our arc pass closest (horizontally) to the landing spot?
	var hv := Vector2(vel.x, vel.z)
	if hv.length() < 1.0:
		return
	var to := Vector2(_landing.x - pos.x, _landing.z - pos.z)
	var t := clampf(to.dot(hv) / hv.length_squared(), 0.0, 6.0)
	var pred := pos + vel * t + Vector3.DOWN * 0.5 * JumpCheck.G * t * t
	var side := Vector3(-vel.z, 0, vel.x).normalized()               # right of our motion (heading -Z -> +X)
	var e: float = (_landing - pred).dot(side) * P("air_lead", _target_ramp)
	cmd.move = Vector2(signf(e) if absf(e) > 0.5 else 0.0, 0)


## Choose the ramp our current arc is heading for, and a spot high on its face a few meters in.
func _pick_target(pos: Vector3, vel: Vector3) -> void:
	_target_ramp = null
	var best := INF
	for rr in _ramps:
		if rr[0] == _face_ramp:
			continue
		var ridge: PackedVector3Array = rr[1]
		# test the arc against the first stretch of this ramp
		for k in range(0, mini(ridge.size(), 60), 4):
			var q := ridge[k]
			var hv := Vector2(vel.x, vel.z)
			if hv.length() < 1.0:
				continue
			var t := Vector2(q.x - pos.x, q.z - pos.z).dot(hv) / hv.length_squared()
			if t <= 0.0 or t > 6.0:
				continue
			var pred := pos + vel * t + Vector3.DOWN * 0.5 * JumpCheck.G * t * t
			var miss := pred.distance_to(q)
			if miss < best:
				best = miss
				_target_ramp = rr[0]
	if _target_ramp == null or best > 60.0:
		_target_ramp = null
		return
	for rr in _ramps:
		if rr[0] == _target_ramp:
			var dist: PackedFloat32Array = rr[4]
			var i := 0
			while i < dist.size() - 1 and dist[i] < P("land_in", rr[0]):
				i += 1
			var face := _face_for(rr[0], ((pos - rr[1][i]) as Vector3).dot(rr[3][i]))
			var out := P("land_out", rr[0])
			_landing = rr[1][i] + (rr[3][i] as Vector3) * face * out \
				+ Vector3.DOWN * out * tan(deg_to_rad((rr[0] as RampNode).angle))


## A technique setting for one ramp: its own value if training gave it one, else the bot's general value.
## params["ramps"] = {"<ramp index>": {setting: value}}.
func P(key: String, ramp) -> float:
	if ramp != null and is_instance_valid(ramp):
		var per: Dictionary = params.get("ramps", {}).get(str(ramp.get_index()), {})
		if per.has(key):
			return float(per[key])
	return float(params[key])


func _strafe_sign(u: float, p: SUCC, r: Vector3) -> float:
	if absf(u) < 0.25:
		return 0.0
	# move.x is "right of where we look"; we look along our motion, whose right is the ramp's right (or its opposite)
	var hv := Vector3(p.velocity.x, 0, p.velocity.z)
	var look_right := Vector3(-hv.z, 0, hv.x).normalized() if hv.length() > 1.0 else r
	return signf(u) * signf(look_right.dot(r) if absf(look_right.dot(r)) > 0.1 else 1.0)


func _face_for(ramp: RampNode, off: float) -> float:
	match ramp.style:
		"half_left": return -1.0
		"half_right": return 1.0
	return signf(off) if absf(off) > 0.3 else 1.0


func _plate_under(feet: Vector3) -> EntityNode:
	for e in ed.entities_root.get_children():
		if e.kind in ["start", "stage"]:
			var local: Vector3 = e.global_transform.affine_inverse() * feet
			if absf(local.x) <= e.size.x * 0.5 + 0.5 and absf(local.z) <= e.size.z * 0.5 + 0.5 and local.y > -0.5 and local.y < 3.0:
				return e
	return null


## The closest spine point (any ramp) to `pos`: where, which way, how far along (0..1), and whether we're past its end.
func _nearest(pos: Vector3) -> Dictionary:
	var best := {}
	var best_d := INF
	for rr in _ramps:
		var ridge: PackedVector3Array = rr[1]
		var step := maxi(1, ridge.size() / 200)
		var i := 0
		while i < ridge.size():
			var d := ridge[i].distance_squared_to(pos)
			if d < best_d:
				best_d = d
				best = {"i": i, "rr": rr}
			i += step
	if best.is_empty():
		return {}
	var rr: Array = best["rr"]
	var ridge: PackedVector3Array = rr[1]
	for i in range(maxi(0, best["i"] - 8), mini(ridge.size(), best["i"] + 9)):
		var d := ridge[i].distance_squared_to(pos)
		if d <= best_d:
			best_d = d
			best["i"] = i
	var j: int = best["i"]
	var dist: PackedFloat32Array = rr[4]
	var t: Vector3 = rr[2][j]
	var past_end: bool = j >= ridge.size() - 1 and (pos - ridge[j]).dot(t) > 0.5
	return {"point": ridge[j], "tan": t, "right": rr[3][j], "dist": sqrt(best_d), "ramp": rr[0], "index": j,
		"s": dist[j] / maxf(dist[dist.size() - 1], 1.0), "past_end": past_end}
