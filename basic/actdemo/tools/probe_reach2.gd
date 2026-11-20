extends Node3D
## 探针：新动作（单手横斩 / 反手后刺）的有效距离

const PlayerS = preload("res://src/game/player.gd")
const CamS = preload("res://src/game/camera.gd")
const MobS = preload("res://src/game/enemy_mob.gd")
const DT := 1.0 / 60.0

var player
var cam
var arena: Dictionary


func _ready() -> void:
	arena = {"bounds": AABB(Vector3(-100, -1, -100), Vector3(200, 40, 200)), "walls": [], "cover": []}
	cam = CamS.new()
	add_child(cam)
	player = PlayerS.new()
	add_child(player)
	player.set_camera(cam)
	cam.set_rig(player.rig)
	await get_tree().process_frame
	P.set_value("move.facing_mode", "movement")
	P.set_value("mob.block_when_visible", false)
	for case in [["slash_left", Vector3(-1, 0, 0), "左"], ["slash_right", Vector3(1, 0, 0), "右"],
			["slash_back", Vector3(0, 0, 1), "后"], ["slash_fwd", Vector3(0, 0, -1), "前"]]:
		var out: Array = []
		for dist in [4.0, 5.5, 6.5, 7.5]:
			player.reset(Transform3D(Basis(), Vector3.ZERO))
			player.rig.heading = 0.0
			player.rig.rotation.y = 0.0
			player.rig.facing_override = false
			player.rig.is_attacking = false
			player.swing_serial += 1
			await get_tree().process_frame
			var mob = MobS.new()
			mob.setup_mob({"tag": "mob", "accent": Color(0.3, 1.0, 0.72)})
			add_child(mob)
			mob.global_position = case[1] * dist
			mob.player = player
			mob.cam = cam
			var hp0: float = mob.hp
			player.rig.is_attacking = false
			player._attack_from_input(_mv(case[0]))
			var win_frames := 0
			var min_clear := 999.0
			for i in 140:
				player.step(DT, arena)
				if player.rig.in_hit_window():
					win_frames += 1
				var tip: Vector3 = player.rig.weapon_xf * Vector3(0, 2.87, 0)
				min_clear = minf(min_clear, tip.distance_to(mob.global_position + Vector3(0, 2.2, 0)))
				Combat.player_swing(player, [mob], cam, [])
			if case[0] == "slash_fwd" and dist == 4.0:
				print("      [dbg] attack=%s proc=%s a0=%.2f a1=%.2f total=%.2f win=%d/%d tip=%.2f" % [
					player.last_attack, str(player.rig.proc_active), player.rig.proc_a0,
					player.rig.proc_a1, player.rig.attack_total, win_frames, 140, min_clear])
			out.append("%.1fm:%s" % [dist, "命中" if mob.hp < hp0 else "—"])
			mob.queue_free()
			await get_tree().process_frame
		print("[reach] %s  %s" % [case[2], str(out)])
	get_tree().quit()


func _mv(id: String) -> Vector2:
	match id:
		"slash_left": return Vector2(-1, 0)
		"slash_right": return Vector2(1, 0)
		"slash_back": return Vector2(0, 1)
	return Vector2.ZERO
