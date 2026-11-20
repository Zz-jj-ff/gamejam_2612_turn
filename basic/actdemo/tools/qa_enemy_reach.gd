extends Node3D
## QA 9 —— 敌人能不能走到玩家身边（每关开局，玩家不动，跑 20 s）
##
## 跑法： godot --headless --path . res://scenes/qa_enemy_reach.tscn

const Qa = preload("res://tools/qa_lib.gd")
const PlayerS = preload("res://src/game/player.gd")
const CamS = preload("res://src/game/camera.gd")
const ProjS = preload("res://src/game/projectiles.gd")
const LevelS = preload("res://src/game/level.gd")
const DT := 1.0 / 60.0

var q
var player
var cam
var proj
var level


func _ready() -> void:
	get_window().size = Vector2i(1600, 900)
	q = Qa.new("qa_enemy_reach")
	P.reset_all()
	P.set_value("rules.god_mode", true)
	proj = ProjS.new()
	add_child(proj)
	cam = CamS.new()
	add_child(cam)
	player = PlayerS.new()
	add_child(player)
	player.set_camera(cam)
	cam.set_rig(player.rig)
	level = LevelS.new()
	add_child(level)
	level.setup(player, proj, cam)
	await get_tree().process_frame
	for idx in 3:
		await _run(idx)
	print("\n== qa_enemy_reach: %d checks, %d failed ==" % [q.checks, q.fails])
	get_tree().quit(q.summary())


func _tick() -> void:
	player.step(DT, level.arena)
	cam.step(DT, level.arena)
	var ctx: Dictionary = level.context()
	level.step(DT, ctx)
	for e in level.enemies:
		if is_instance_valid(e) and e.alive:
			Combat.enemy_swing(e, player)
	proj.step(DT, ctx)


func _run(idx: int) -> void:
	level.start_level(idx)
	for i in 120:
		_tick()
		if level.state == "fight":
			break
	P.set_value("boss.laser_trigger", "disabled")    # 别让它第一帧就秒人
	var b: AABB = level.arena["bounds"]
	var half := b.size * 0.5
	q.section("第 %d 关：开局 20 s 不干预，敌人能走到玩家身边吗" % (idx + 1))
	q.info("bounds 半宽/半深", "(%.0f, %.0f) ｜ 玩家 %s" % [half.x, half.z, str(player.rig.global_position)])
	var t := 0.0
	var dmin: Dictionary = {}
	for e in level.enemies:
		dmin[e.get_instance_id()] = 1e9
	while t < 20.0:
		_tick()
		t += DT
		for e in level.enemies:
			if is_instance_valid(e) and e.alive:
				dmin[e.get_instance_id()] = minf(dmin[e.get_instance_id()], e.dist_to_player())
	for e in level.enemies:
		if not is_instance_valid(e):
			continue
		var reach := 6.2
		if e.kind == "archer":
			reach = P.getf("archer.keep_dist") * 0.72
		elif e.kind == "boss":
			reach = P.getf("boss.slam_radius")
		q.info("%s" % e.kind, "节点 %s ｜ rig 局部 %s ｜ rig 全局 %s ｜ 最近距离 %.1f m" % [
			str(e.global_position), str(e.rig.position), str(e.rig.global_position),
			dmin[e.get_instance_id()]])
		q.ok(float(dmin[e.get_instance_id()]) <= reach, "  %s 能进入攻击距离（%.1f m）" % [e.kind, reach],
			"最近 %.1f m（卡在 rig 局部 %s → 全局 %s）" % [
				dmin[e.get_instance_id()], str(e.rig.position), str(e.rig.global_position)])
