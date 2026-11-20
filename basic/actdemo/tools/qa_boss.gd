extends Node3D
## QA 6 —— 大怪 AI：30 s 二循环 + 激光
##
## 跑法： godot --headless --path . res://scenes/qa_boss.tscn

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
var boss
var t := 0.0

var qi_releases := 0
var charges := 0
var slams := 0
var slam_dists: Array = []
var qi_hits := 0
var melee_hits := 0
var laser_fires := 0
var _prev_cd := 0.0
var _prev_qi := false
var _prev_slam := false
var _prev_state := ""
var charge_attack_frames := 0
var atk_log: Array = []
var _prev_attacking := false
var state_seq: Array = []


func _ready() -> void:
	get_window().size = Vector2i(1600, 900)   # headless 默认是 1600×1600，这里恢复 16:9 的真实取景
	q = Qa.new("qa_boss")
	P.reset_all()
	P.set_value("rules.god_mode", true)          # 只统计出招，不被打断
	P.set_value("boss.laser_trigger", "disabled")
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
	level.start_level(2)
	await get_tree().process_frame
	await get_tree().process_frame
	cam.yaw = player.rig.heading
	cam.pitch = -0.16
	boss = level.enemies[0]
	q.info("第三关装配", "boss at %s ；player at %s ；距离 %.1f m" % [
		str(boss.rig.global_position), str(player.rig.global_position), boss.dist_to_player()])
	await _t_cycle()
	await _t_slam_radius()
	await _t_laser()
	await _t_entry()
	print("\n== qa_boss: %d checks, %d failed ==" % [q.checks, q.fails])
	get_tree().quit(q.summary())


func _tick() -> void:
	player.step(DT, level.arena)
	cam.step(DT, level.arena)
	var ctx: Dictionary = level.context()
	level.step(DT, ctx)
	Combat.player_swing(player, level.enemies, cam)
	for e in level.enemies:
		if is_instance_valid(e) and e.alive:
			var r: Dictionary = Combat.enemy_swing(e, player)
			if bool(r.get("hit", false)):
				melee_hits += 1
	if boss.state == "charge" and bool(boss.rig.is_attacking):
		charge_attack_frames += 1
	if bool(boss.rig.is_attacking) != _prev_attacking:
		if atk_log.size() < 24:
			atk_log.append("%.2fs %s %s" % [t, boss.state,
				"BEGIN:" + String(boss.rig.attack_name) if bool(boss.rig.is_attacking) else "END"])
		_prev_attacking = bool(boss.rig.is_attacking)
	var events: Array = proj.step(DT, ctx)
	for ev in events:
		if String(ev["kind"]) == "player_hit" and String(ev["it"]["kind"]) == "qi":
			qi_hits += 1
	t += DT


func _track() -> void:
	# 阶段进入次数
	if boss.state != _prev_state:
		if boss.state == "qi":
			qi_releases += 0  # 刀气实际释放另算
		if boss.state == "charge":
			charges += 1
		if state_seq.size() < 60:
			state_seq.append(boss.state)
		_prev_state = boss.state
	if bool(boss.qi_fired) and not _prev_qi:
		qi_releases += 1
	_prev_qi = bool(boss.qi_fired)
	if bool(boss.slam_done) and not _prev_slam:
		slams += 1
		slam_dists.append(boss.dist_to_player())
	_prev_slam = bool(boss.slam_done)
	# 激光：cd 被重新填满 = 发了一次
	if float(boss.laser_cd) - _prev_cd > 0.5:
		laser_fires += 1
	_prev_cd = float(boss.laser_cd)


# ------------------------------------------------------------------ 30 s 循环
func _t_cycle() -> void:
	q.section("6a 大怪 30 s 二循环（激光关闭，玩家站桩）")
	t = 0.0
	_prev_cd = float(boss.laser_cd)
	var d0: float = boss.dist_to_player()
	while t < 30.0:
		_tick()
		_track()
	q.info("阶段序列（进入顺序）", " → ".join(state_seq))
	q.info("与玩家距离", "开局 %.1f m → 结束 %.1f m" % [d0, boss.dist_to_player()])
	q.ok(qi_releases >= 2, "30 s 内至少放 2 次刀气（阶段 1）", "%d 次" % qi_releases)
	q.ok(charges >= 2, "30 s 内至少冲撞 2 次（阶段 2）", "%d 次" % charges)
	q.ok(slams >= 2, "冲撞都落到重击", "%d 次重击" % slams)
	q.ok(qi_releases > 0 and charges > 0, "两个阶段都在循环（不是卡在一个阶段）",
		"qi=%d charge=%d" % [qi_releases, charges])
	if slam_dists.size() > 0:
		q.info("每次重击时的距离", str(slam_dists))
		var inside := 0
		for d in slam_dists:
			if float(d) <= P.getf("boss.slam_radius"):
				inside += 1
		q.ok(inside >= 1, "至少有重击落在 slam_radius（%.1f m）内" % P.getf("boss.slam_radius"),
			"%d/%d 次在范围内；距离序列 %s" % [inside, slam_dists.size(), str(slam_dists)])
		q.ok(inside == slam_dists.size(), "每次重击都在范围内（冲撞应该能冲到你面前）",
			"%d/%d" % [inside, slam_dists.size()])
	if qi_hits > 0:
		q.ok(qi_hits >= 1, "刀气能命中站桩的玩家", "%d 次" % qi_hits)
	q.info("玩家被近战刀扫到次数", "%d" % melee_hits)
	q.info("攻击开始/结束时间线（前 24 条）", " | ".join(atk_log))
	q.info("冲撞阶段里身体还在播刀气动画的帧数", "%d 帧（%.2f s）→ 这期间 is_attacking 会锁住位移" % [
		charge_attack_frames, float(charge_attack_frames) / 60.0])


# ------------------------------------------------------------------ 重击半径
func _t_slam_radius() -> void:
	q.section("6b 重击半径判定：9 m 内致死，之外不致死")
	P.set_value("rules.god_mode", false)
	P.set_value("rules.one_hit_kill", true)
	# 半径内 5 m
	player.reset(level.arena["player_spawn"])
	boss.rig.global_position = Vector3(0, 0, 0)
	player.rig.global_position = Vector3(0, 0, 5)
	await get_tree().process_frame
	boss.slam_done = false
	boss._slam()
	q.ok(not player.alive, "距 5 m（< 9 m）→ 被重击杀死", "cause=%s" % player.last_cause)
	q.ok(player.last_cause == "被重击碾碎", "死因正确", player.last_cause)
	# 半径外 20 m
	player.reset(level.arena["player_spawn"])
	player.rig.global_position = Vector3(0, 0, 20)
	await get_tree().process_frame
	boss.slam_done = false
	boss._slam()
	q.ok(player.alive, "距 20 m（> 9 m）→ 不吃伤害", "alive=%s cause=%s" % [
		str(player.alive), player.last_cause])
	# 边界 8.9 / 9.1
	player.reset(level.arena["player_spawn"])
	player.rig.global_position = Vector3(0, 0, 8.9)
	await get_tree().process_frame
	boss.slam_done = false
	boss._slam()
	var at_89: bool = not player.alive
	player.reset(level.arena["player_spawn"])
	player.rig.global_position = Vector3(0, 0, 9.1)
	await get_tree().process_frame
	boss.slam_done = false
	boss._slam()
	var at_91: bool = not player.alive
	q.ok(at_89 and not at_91, "半径边界在 9.0 m 附近", "8.9 m 死=%s / 9.1 m 死=%s" % [
		str(at_89), str(at_91)])
	P.set_value("rules.god_mode", true)


# ------------------------------------------------------------------ 激光
func _t_laser() -> void:
	q.section("6c 激光：看到大怪才触发（laser_trigger=player_sees）")
	P.set_value("boss.laser_trigger", "player_sees")
	P.set_value("boss.laser_warn", 0.0)
	P.set_value("rules.god_mode", true)
	player.reset(level.arena["player_spawn"])
	boss.rig.global_position = player.rig.global_position + Vector3(0, 0, -22)
	boss.state = "gap"
	boss.st_t = 0.0
	boss.laser_cd = 0.0
	cam.yaw = 0.0
	cam.step(DT, level.arena)
	await get_tree().process_frame
	var vis: bool = Vision.is_visible(cam.camera, boss.center(), boss.mark_radius())
	q.ok(vis, "大怪在画面里")
	laser_fires = 0
	_prev_cd = 0.0
	t = 0.0
	while t < 8.0:
		_tick()
		_track()
	q.info("8 s 内激光次数", "%d（冷却 %.1f s → 理论 ≈ 4）" % [laser_fires, P.getf("boss.laser_cooldown")])
	q.ok(laser_fires >= 3, "看着它就持续被激光点名", "%d 次" % laser_fires)

	# 看到就死
	P.set_value("rules.god_mode", false)
	player.reset(level.arena["player_spawn"])
	cam.yaw = 0.0
	cam.step(DT, level.arena)
	boss.laser_cd = 0.0
	t = 0.0
	var died := false
	while t < 3.0:
		_tick()
		if not player.alive:
			died = true
			break
	q.ok(died, "看一眼 → 被激光秒杀", "cause=%s" % player.last_cause)
	q.ok(player.last_cause == "被激光蒸发", "死因正确", player.last_cause)

	# 不看它 → 不发激光
	P.set_value("rules.god_mode", true)
	player.reset(level.arena["player_spawn"])
	boss.rig.global_position = player.rig.global_position + Vector3(0, 0, 13)   # 站到它背后
	cam.yaw = 0.0
	await get_tree().process_frame
	var vis_back: bool = Vision.is_visible(cam.camera, boss.center(), boss.mark_radius())
	boss.laser_cd = 0.0
	laser_fires = 0
	_prev_cd = 0.0
	t = 0.0
	var hp_start: float = player.hp
	while t < 8.0:
		# 钉住大怪的状态机（只测激光的视野门限，不让它自己跑到镜头里）
		boss.state = "gap"
		boss.st_t = 0.0
		_tick()
		_track()
		if is_instance_valid(boss):
			boss.rig.global_position = player.rig.global_position + Vector3(0, 0, 13)
	q.ok(not vis_back, "大怪在身后（画面里看不到）", "visible=%s" % str(vis_back))
	q.ok(laser_fires == 0, "看不见它 → 8 s 内 0 次激光", "%d 次" % laser_fires)
	P.set_value("rules.god_mode", false)


# ------------------------------------------------------------------ 入场
## 6d 第三关入场：相机会立刻对位（不残留上一关），背向大怪，且开场横幅期间不开激光。
func _t_entry() -> void:
	q.section("6d 第三关入场：背向进入 + 开场不被激光秒")
	P.set_value("boss.laser_trigger", "player_sees")
	P.set_value("boss.laser_warn", 0.0)
	P.set_value("rules.god_mode", false)
	level.start_level(2)
	boss = level.enemies[0]
	# 故意不手动推相机：start_level 自己必须把相机对位到新出生点
	var vis_entry: bool = Vision.is_visible(cam.camera, boss.center(), boss.mark_radius())
	q.ok(not vis_entry, "入场第一帧：大怪不在画面里（背向进入）",
		"visible=%s boss=%s player=%s" % [str(vis_entry),
			str(boss.rig.global_position), str(player.rig.global_position)])
	q.ok(cam.camera.global_position.distance_to(player.rig.global_position) < 20.0,
		"相机已对位到新出生点（不残留上一关的位置）",
		"cam=%s player=%s" % [str(cam.camera.global_position), str(player.rig.global_position)])
	# 把大怪硬塞到镜头正前方：intro 期间它就是不开火
	boss.rig.global_position = player.rig.global_position + Vector3(0, 0, -20)
	boss.state = "gap"
	boss.st_t = 0.0
	boss.laser_cd = 0.0
	cam.yaw = 0.0
	laser_fires = 0
	_prev_cd = 0.0
	t = 0.0
	var intro_seen := false
	while level.state == "intro" and t < 4.0:
		boss.state = "gap"
		boss.st_t = 0.0
		boss.rig.global_position = player.rig.global_position + Vector3(0, 0, -20)
		_tick()
		_track()
		if Vision.is_visible(cam.camera, boss.center(), boss.mark_radius()):
			intro_seen = true
	q.ok(intro_seen, "intro 期间大怪确实占满画面（开场保护的对照）", "seen=%s" % str(intro_seen))
	q.ok(player.alive and laser_fires == 0, "intro 期间不触发激光（开场不被秒）",
		"alive=%s laser=%d" % [str(player.alive), laser_fires])
	# 真正进 fight 后：照旧「看见即死」
	var died := false
	while t < 8.0:
		boss.state = "gap"
		boss.st_t = 0.0
		boss.rig.global_position = player.rig.global_position + Vector3(0, 0, -20)
		_tick()
		_track()
		if not player.alive:
			died = true
			break
	q.ok(died and player.last_cause == "被激光蒸发", "intro 结束后依然看见即死",
		"died=%s cause=%s" % [str(died), player.last_cause])
	P.set_value("rules.god_mode", false)
