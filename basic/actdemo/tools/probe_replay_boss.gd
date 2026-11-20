extends Node3D
## 回放体型探针：录一段大怪（×2 / torso ×1.45 / head ×1.42），进回放后打印
## 各节点缩放并出图，确认机体没有被压成细柱子。
##
## 回归断言在 `tools/qa_replay.gd`；这里只负责肉眼验收。
##
## 跑法： DISPLAY=:0 godot --path . res://scenes/probe_replay_boss.tscn

const MainScene = preload("res://main.tscn")
const Shot = preload("res://tools/shot.gd")

var game
var shot = Shot.new()


func _ready() -> void:
	game = MainScene.instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	P.set_value("rules.god_mode", true)
	P.set_value("boss.laser_trigger", "disabled")
	P.set_value("cam.mode", "third")
	game.level.start_level(2)
	await get_tree().process_frame
	await get_tree().process_frame
	game.cam.yaw = 0.0
	var boss = null
	for e in game.level.enemies:
		if e.alive:
			boss = e
			break
	if boss == null:
		print("[rboss] 没有大怪")
		get_tree().quit()
		return
	boss.global_position = game.player.rig.global_position + Vector3(0, 0, -9.0)
	for i in 20:
		await get_tree().process_frame
	print("[rboss] 录制中：rig=%s torso=%s head=%s" % [
		str(boss.rig.global_transform.basis.get_scale()),
		str(boss.rig.torso.global_transform.basis.get_scale()),
		str(boss.rig.head.global_transform.basis.get_scale())])
	game.replay.start()
	for i in 12:
		await get_tree().process_frame
	print("[rboss] 回放中：rig=%s torso=%s head=%s" % [
		str(boss.rig.global_transform.basis.get_scale()),
		str(boss.rig.torso.global_transform.basis.get_scale()),
		str(boss.rig.head.global_transform.basis.get_scale())])
	# 冻结，把机位摆到大怪侧面，出图
	game.set_process(false)
	game.hud.visible = false
	var cam3d: Camera3D = game.cam.camera
	cam3d.global_position = boss.rig.global_position + Vector3(7.0, 3.4, 7.0)
	cam3d.look_at(boss.rig.global_position + Vector3(0, 2.6, 0), Vector3.UP)
	await shot.capture(self, "res://shots/replay_boss.png", 4)
	get_tree().quit()
