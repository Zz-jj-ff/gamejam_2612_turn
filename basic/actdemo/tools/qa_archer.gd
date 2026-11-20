extends Node3D
## QA 5 —— 远程怪 AI：不干预跑 20 s
##
## 跑法： godot --headless --path . res://scenes/qa_archer.tscn
##
## 用真实 LevelUnit（第二关）+ 固定 60 Hz 手动推进（与 main._process 同序），
## 玩家完全不操作、原地站着，只观察远程怪。

const Qa = preload("res://tools/qa_lib.gd")
const PlayerS = preload("res://src/game/player.gd")
const CamS = preload("res://src/game/camera.gd")
const ProjS = preload("res://src/game/projectiles.gd")
const LevelS = preload("res://src/game/level.gd")
const DT := 1.0 / 60.0
const DURATION := 20.0

var q
var player
var cam
var proj
var level
var archer

var fire_times: Array = []
var player_hits: Array = []          # {t, kind}
var wall_hits := 0
var dist_min := 1e9
var dist_max := 0.0
var dist_sum := 0.0
var dist_n := 0
var prev_seq := 0
var t := 0.0
var samples: Array = []
var player_spawn_pos := Vector3.ZERO


func _ready() -> void:
	q = Qa.new("qa_archer")
	P.reset_all()
	P.set_value("rules.god_mode", true)      # 只统计命中，不让第一箭就结束测试
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
	level.start_level(1)
	await get_tree().process_frame
	await get_tree().process_frame
	cam.yaw = player.rig.heading
	cam.pitch = -0.16
	player_spawn_pos = player.rig.global_position
	q.info("第二关装配", "enemies=%d archers=%d 玩家=%s" % [
		level.enemies.size(), level.archers.size(), str(player.rig.global_position)])
	for e in level.enemies:
		if e.kind == "mob":
			e.hurt(99999.0, Vector3.UP)
	archer = level.archers[0]
	for i in 120:
		_tick()
		if level.state == "fight":
			break
	q.info("开场距离", "%.1f m（keep_dist=%.1f，理想区间 %.1f–%.1f）" % [
		archer.dist_to_player(), P.getf("archer.keep_dist"),
		P.getf("archer.keep_dist") * 0.72, P.getf("archer.keep_dist") * 1.35])
	prev_seq = proj._seq
	await _t_run()
	print("\n== qa_archer: %d checks, %d failed ==" % [q.checks, q.fails])
	get_tree().quit(q.summary())


func _tick() -> void:
	player.step(DT, level.arena)
	var ctx: Dictionary = level.context()
	level.step(DT, ctx)
	Combat.player_swing(player, level.enemies, cam)
	for e in level.enemies:
		if is_instance_valid(e) and e.alive:
			Combat.enemy_swing(e, player)
	var events: Array = proj.step(DT, ctx)
	for ev in events:
		match String(ev["kind"]):
			"player_hit":
				player_hits.append({"t": t, "kind": String(ev["it"]["kind"]),
					"dist": archer.dist_to_player()})
			"wall":
				wall_hits += 1


func _t_run() -> void:
	q.section("5 远程怪 20 s 无人干预")
	var last_dist := -1.0
	while t < DURATION:
		_tick()
		t += DT
		# 用 projectiles 的序号统计射击次数（贴脸命中的箭会在同一帧被回收，看不到节点）
		if proj._seq > prev_seq:
			for k in (proj._seq - prev_seq):
				fire_times.append(t)
			prev_seq = proj._seq
		if is_instance_valid(archer) and archer.player != null:
			var d: float = archer.dist_to_player()
			dist_min = minf(dist_min, d)
			dist_max = maxf(dist_max, d)
			dist_sum += d
			dist_n += 1
			if int(t * 2.0) != int((t - DT) * 2.0):
				samples.append("%.1fs:%.1fm" % [t, d])

	var n_arrows := fire_times.size()
	var avg_dist := dist_sum / maxf(1.0, float(dist_n))
	var keep := P.getf("archer.keep_dist")

	q.info("20 s 内射击次数", "%d 支（理论 ≈ %.0f 支：间隔 %.1f s + 拉弓 %.2f s）" % [
		n_arrows, DURATION / (P.getf("archer.fire_interval") + P.getf("archer.telegraph")),
		P.getf("archer.fire_interval"), P.getf("archer.telegraph")])
	q.ok(n_arrows >= 4, "远程怪持续输出（20 s ≥ 4 箭）", "%d 支" % n_arrows)
	if fire_times.size() >= 3:
		var gaps: Array = []
		for i in range(1, fire_times.size()):
			gaps.append(float(fire_times[i]) - float(fire_times[i - 1]))
		q.info("相邻两箭间隔", "%s" % str(gaps))
		q.ok(float(gaps.min()) > 1.0, "不会疯狂连射", "最小间隔 %.2f s" % float(gaps.min()))

	q.info("与玩家距离 min/avg/max", "%.1f / %.1f / %.1f m" % [dist_min, avg_dist, dist_max])
	q.info("距离采样（每 0.5 s）", " ".join(samples.slice(0, 20)))
	q.info("距离采样（后半程）", " ".join(samples.slice(maxi(0, samples.size() - 12), samples.size())))
	q.ok(dist_min > keep * 0.72 - 2.0, "保持距离（没贴到脸上）",
		"最近 %.1f m，keep_dist×0.72 = %.1f m" % [dist_min, keep * 0.72])
	q.ok(dist_min > 8.0, "任何时刻都没有怼进 8 m 内", "最近 %.1f m" % dist_min)
	q.ok(dist_max < 60.0, "没有跑到天边去", "最远 %.1f m" % dist_max)

	var hits := player_hits.size()
	q.info("命中玩家 / 撞墙 / 其它", "命中 %d · 撞墙 %d · 其它 %d" % [
		hits, wall_hits, maxi(0, n_arrows - hits - wall_hits)])
	q.ok(hits >= 1, "箭真的能命中静止的玩家", "%d 次 player_hit" % hits)
	if hits > 0 and n_arrows > 0:
		q.info("命中率", "%.0f%%（%d/%d）" % [100.0 * float(hits) / float(n_arrows), hits, n_arrows])
		q.ok(float(hits) / float(n_arrows) >= 0.3, "静态目标命中率 ≥30%",
			"%.0f%%" % (100.0 * float(hits) / float(n_arrows)))
	var moved := Vector2(player.rig.global_position.x - player_spawn_pos.x,
		player.rig.global_position.z - player_spawn_pos.z).length()
	q.info("玩家位移（应该 ~0）", "%.2f m" % moved)
	q.info("远程怪最终位置", str(archer.rig.global_position))
