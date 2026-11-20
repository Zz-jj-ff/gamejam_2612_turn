extends Node3D
## 调试探针：小怪为什么不靠近（在真 main 里逐段观察）

const DT := 1.0 / 60.0
var main
var player
var level
var cam
var mob


func _ready() -> void:
	Engine.max_fps = 60
	P.reset_all()
	P.set_value("rules.god_mode", true)
	main = load("res://main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	player = main.player
	level = main.level
	cam = main.cam
	while level.state != "fight":
		await get_tree().process_frame
	mob = level.enemies[0]
	print("spawn: mob=", mob.rig.global_position, " player=", player.rig.global_position,
		" dist=", mob.dist_to_player())
	for i in 300:
		await get_tree().process_frame
		if i % 30 == 0:
			print("A t=%d mob=%s heading=%.1f speed=%.2f cmd=%s attacking=%s" % [
				i, str(mob.rig.position), rad_to_deg(mob.rig.heading), mob.rig.speed,
				str(mob.rig.move_command), str(mob.rig.is_attacking)])
	print("---- 转镜头 + 攻击 ----")
	var sens: float = P.getf("cam.sensitivity")
	var target := PI
	for i in 8:
		var err: float = wrapf(target - cam.yaw, -PI, PI)
		if absf(err) < deg_to_rad(1.0):
			break
		cam.look(Vector2(-err / sens, 0.0))
		cam.step(DT, level.arena)
		await get_tree().process_frame
	print("cam.yaw=", rad_to_deg(cam.yaw), " heading=", rad_to_deg(player.rig.heading))
	player._attack_from_input(Vector2.ZERO)
	for i in 300:
		await get_tree().process_frame
		if i % 30 == 0:
			print("B t=%d mob=%s heading=%.1f speed=%.2f cmd=%s attacking=%s player_attacking=%s" % [
				i, str(mob.rig.position), rad_to_deg(mob.rig.heading), mob.rig.speed,
				str(mob.rig.move_command), str(mob.rig.is_attacking), str(player.rig.is_attacking)])
	get_tree().quit(0)
