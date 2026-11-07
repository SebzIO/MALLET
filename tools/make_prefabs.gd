extends SceneTree
## Builds the starter prefabs in res://prefabs/. Run:
##   godot --headless --path D:/SurfForge -s res://tools/make_prefabs.gd
## Each prefab is one group (so it moves as one), sitting on y = 0 around x = z = 0.

const DIR := "res://prefabs/"


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_save("Small house", "walls, a doorway, a window and a roof", house())
	_save("Tower", "a round stone tower with a lit top", tower())
	_save("Gateway", "a stone arch on two pillars", gateway())
	_save("Lamp post", "a post with a warm light", lamp_post())
	_save("Pool", "a tiled pool full of water", pool())
	_save("Lava pit", "deadly glowing lava in a stone rim", lava_pit())
	_save("Stage sign", "a board with a glowing STAGE 1 on it", stage_sign())
	print("PREFABS: built %d" % DirAccess.get_files_at(DIR).size())
	quit(0)


func _save(name: String, description: String, clip: Dictionary) -> void:
	var group := "prefab_" + name.to_lower().replace(" ", "_")
	for kind in ["blocks", "texts", "lights"]:
		for d in clip.get(kind, []):
			d["group"] = group
	var full := {"mallet_clipboard": 1, "ramps": [], "entities": [], "props": [],
		"blocks": clip.get("blocks", []), "texts": clip.get("texts", []), "lights": clip.get("lights", [])}
	Prefabs.save(name, full, description, DIR)


func block(shape: String, pos: Vector3, size: Vector3, material := "", extra := {}) -> Dictionary:
	var d := {"shape": shape, "position": [pos.x, pos.y, pos.z], "size": [size.x, size.y, size.z], "material": material}
	d.merge(extra, true)
	return d


func light(pos: Vector3, color := "ffd9a0", energy := 3.0, rng := 25.0) -> Dictionary:
	return {"kind": "point", "position": [pos.x, pos.y, pos.z], "color": color, "energy": energy, "range": rng}


func house() -> Dictionary:
	return {"blocks": [
		block("box", Vector3(0, 0, 0), Vector3(16, 8, 12), "Bricks104", {"hollow": true, "wall": 0.6}),
		block("box", Vector3(0, -0.1, 0), Vector3(16, 0.2, 12), "WoodFloor051"),
		block("box", Vector3(0, 0, 6), Vector3(3, 5, 2), "", {"cutter": true}),              # doorway
		block("box", Vector3(-8, 3, 0), Vector3(2, 2.5, 3), "", {"cutter": true}),           # window
		block("wedge", Vector3(0, 8, -3.25), Vector3(17, 3, 6.5), "RoofingTiles013A", {"yaw": 180.0}),
		block("wedge", Vector3(0, 8, 3.25), Vector3(17, 3, 6.5), "RoofingTiles013A"),
	], "lights": [light(Vector3(0, 6, 0), "ffd9a0", 2.0, 14.0)]}


func tower() -> Dictionary:
	return {"blocks": [
		block("cylinder", Vector3(0, 0, 0), Vector3(10, 24, 10), "Bricks094", {"sides": 16, "hollow": true, "wall": 0.8}),
		block("box", Vector3(0, 0, 5), Vector3(3, 5, 2), "", {"cutter": true}),
		block("cylinder", Vector3(0, 24, 0), Vector3(12, 1, 12), "Concrete034", {"sides": 16}),
		block("cone", Vector3(0, 25, 0), Vector3(12, 8, 12), "RoofingTiles013A", {"sides": 16}),
	], "lights": [light(Vector3(0, 22, 0), "ffcf80", 4.0, 40.0)]}


func gateway() -> Dictionary:
	return {"blocks": [
		block("arch", Vector3(0, 0, 0), Vector3(16, 18, 3), "PavingStones138", {"sides": 16, "wall": 2.0}),
		block("box", Vector3(-7, 0, 0), Vector3(3.6, 1.0, 3.6), "Concrete034"),
		block("box", Vector3(7, 0, 0), Vector3(3.6, 1.0, 3.6), "Concrete034"),
		block("box", Vector3(0, 18, 0), Vector3(17, 1.0, 3.6), "Concrete034"),
	]}


func lamp_post() -> Dictionary:
	return {"blocks": [
		block("cylinder", Vector3(0, 0, 0), Vector3(1.2, 0.4, 1.2), "Metal032", {"sides": 12}),
		block("cylinder", Vector3(0, 0.4, 0), Vector3(0.4, 6, 0.4), "Metal032", {"sides": 8}),
		block("sphere", Vector3(0, 6.2, 0), Vector3(1.2, 1.2, 1.2), "", {"sides": 12, "color": "ffe2a8", "glow": 3.0}),
	], "lights": [light(Vector3(0, 6.8, 0), "ffd9a0", 3.0, 22.0)]}


## Four walls around a w x d floor (an open-topped basin).
func rim(w: float, d: float, t: float, h: float, material: String) -> Array:
	return [
		block("box", Vector3(0, 0, -(d - t) * 0.5), Vector3(w, h, t), material),
		block("box", Vector3(0, 0, (d - t) * 0.5), Vector3(w, h, t), material),
		block("box", Vector3(-(w - t) * 0.5, 0, 0), Vector3(t, h, d - 2.0 * t), material),
		block("box", Vector3((w - t) * 0.5, 0, 0), Vector3(t, h, d - 2.0 * t), material),
	]


func pool() -> Dictionary:
	return {"blocks": [
		block("box", Vector3(0, 0, 0), Vector3(24, 1, 16), "Tiles107"),
	] + rim(24, 16, 1.0, 3.0, "Tiles107") + [
		block("box", Vector3(0, 1, 0), Vector3(22, 1.6, 14), "", {"water": true, "water_color": "2a8fb5", "clarity": 0.7}),
	]}


func lava_pit() -> Dictionary:
	return {"blocks": [
		block("box", Vector3(0, 0, 0), Vector3(20, 0.5, 20), "PavingStones138"),
	] + rim(20, 20, 1.5, 2.0, "PavingStones138") + [
		block("box", Vector3(0, 0.5, 0), Vector3(17, 1.0, 17), "",
			{"water": true, "deadly": true, "water_color": "ff5a10", "clarity": 0.0, "glow": 2.5}),
	], "lights": [light(Vector3(0, 4, 0), "ff6a20", 3.0, 30.0)]}


func stage_sign() -> Dictionary:
	return {"blocks": [
		block("box", Vector3(-6, 0, 0), Vector3(0.6, 9, 0.6), "Wood051"),
		block("box", Vector3(6, 0, 0), Vector3(0.6, 9, 0.6), "Wood051"),
		block("box", Vector3(0, 5, 0), Vector3(14, 4, 0.5), "Planks037A"),
	], "texts": [
		{"text": "STAGE 1", "font": "Arial Black", "height": 2.4, "depth": 0.3, "mode": "3d", "align": "center",
			"position": [0.0, 5.8, 0.26], "color": "7fe0ff", "glow": 2.0, "solid": false},
	]}
