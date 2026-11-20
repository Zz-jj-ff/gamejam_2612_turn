extends Node3D
## 覆盖面矩阵：不同角度上的敌人，四种攻击分别能不能打到（FPS 模式）

const PlayerS = preload("res://src/game/player.gd")
const CamS = preload("res://src/game/camera.gd")
const MobS = preload("res://src/game/enemy_mob.gd")
const DT := 1.0 / 60.0

var player
var cam
var arena: Dictionary


func _ready() -> void:
	arena = {"bounds": AABB(Vector3(-200, -1, -200), Vector3(400, 40, 400)), "walls": [], "cover": []}
	cam = CamS.new()
	add_child(cam)
	player = PlayerS.new()
	add_child(player)
	player.set_camera(cam)
	cam.set_rig(player.rig)
	await get_tree().process_frame
	P.set_value("move.facing_mode", "camera")
	P.set_value("mob.block_when_visible", false)
	P.set_value("cam.mode", "first")
	cam.set_first_person(true)
	cam.yaw = 0.0
	print("[arc] 角度：0=正前, +左, -右, ±180=正后；格内 = 该攻击命中")
	var header := "       "
	for atk in ["前(不按)", "左(A)", "右(D)", "后(S)"]:
		header += "%-9s" % atk
	print(header)
	for deg in [0, 45, 90, 135, 180, -45, -90, -135]:
		var a: float = deg_to_rad(float(deg))
		var dir := Vector3(-sin(a), 0.0, -cos(a))
		var row := "%5d  " % deg
		for atk in ["slash_fwd", "slash_left", "slash_right", "slash_back"]:
			player.reset(Transform3D(Basis(), Vector3.ZERO))
			player.rig.heading = 0.0
			player.rig.rotation.y = 0.0
			player.rig.facing_override = true
			cam.yaw = 0.0
			await get_tree().process_frame
			var mob = MobS.new()
			mob.setup_mob({"tag": "mob", "accent": Color(0.3, 1.0, 0.72)})
			add_child(mob)
			mob.global_position = dir * 4.6
			mob.player = player
			mob.cam = cam
			var hp0: float = mob.hp
			player.rig.is_attacking = false
			player._attack(atk, 0.0)
			for i in 150:
				player.step(DT, arena)
				Combat.player_swing(player, [mob], cam, [])
			row += "%-9s" % ("命中" if mob.hp < hp0 else "—")
			mob.queue_free()
			await get_tree().process_frame
		print(row)
	get_tree().quit()
