extends Node3D
## QA —— 剑挡剑：读招 → 规划一条机械臂路径 → 架住（免伤 + 被击退）
##
## 跑法： godot --headless --path . res://scenes/qa_parry.tscn

const Qa = preload("res://tools/qa_lib.gd")
const PlayerS = preload("res://src/game/player.gd")
const CamS = preload("res://src/game/camera.gd")
const ProjS = preload("res://src/game/projectiles.gd")
const MobS = preload("res://src/game/enemy_mob.gd")
# 直接 preload：不依赖全局类缓存
const InterceptS = preload("res://src/game/intercept.gd")
const DT := 1.0 / 60.0

var q
var player
var cam
var proj
var mob
var arena: Dictionary = {}


func _ready() -> void:
	q = Qa.new("qa_parry")
	P.reset_all()
	P.set_value("rules.one_hit_kill", true)
	proj = ProjS.new()
	add_child(proj)
	cam = CamS.new()
	add_child(cam)
	player = PlayerS.new()
	add_child(player)
	player.set_camera(cam)
	player.projectiles = proj
	cam.set_rig(player.rig)
	await get_tree().process_frame
	# 灯下黑：别让 HUD/相机相关的东西影响判定
	P.set_value("cam.mode", "third")
	await _t_blade_vs_blade()
	await _t_predict()
	await _t_block(0.0, "正对")
	await _t_block(PI * 0.5, "身体转开 90°")
	await _t_block(PI, "背对")
	await _t_block(0.0, "一起手就按（提前 0.5 s）", 0.5)
	await _t_block(PI * 0.5, "侧身 + 一起手就按", 0.5)
	await _t_no_parry_dies()
	await _t_arrow()
	print("\n== qa_parry: %d checks, %d failed ==" % [q.checks, q.fails])
	get_tree().quit(q.summary())


# ------------------------------------------------------------------ 工具
func _reset_world() -> void:
	if mob != null and is_instance_valid(mob):
		mob.queue_free()
	mob = null
	proj.clear_all()
	player.reset(Transform3D(Basis(), Vector3(0, 0, 0)))
	cam.yaw = 0.0
	cam.pitch = -0.16
	await get_tree().process_frame


## 在玩家前方 spawn_m 米处放一只小怪，起手一次挥砍（不走 AI，时间轴完全可控）
## body_yaw = 玩家身体的朝向偏移（0 = 正对它，±90° = 用侧面/余光架）
func _spawn_swinger(spawn_m: float, body_yaw := 0.0) -> void:
	player.rig.facing_override = true
	player.rig.facing_heading = body_yaw
	player.rig.heading = body_yaw
	player.rig.rotation.y = body_yaw
	cam.yaw = body_yaw
	mob = MobS.new()
	add_child(mob)
	mob.setup_mob({"tag": "mob", "accent": Color(0.6, 0.9, 0.4)})
	mob.projectiles = proj
	mob.player = player
	mob.cam = cam
	mob.global_position = Vector3(0, 0, -spawn_m)
	await get_tree().process_frame
	mob.rig.face_target(player.rig.global_position)
	mob.rig.face_rate = 6.0
	mob.rig.heading = mob.rig.facing_heading
	mob.rig.rotation.y = mob.rig.heading
	var w: float = P.getf("mob.windup")
	var a: float = P.getf("mob.active")
	var r: float = P.getf("mob.recovery")
	mob.rig.set_timings({"mob": {"duration": w + a + r, "windup": w, "active": a, "recovery": r}})
	mob.rig.timing_key = "mob"
	mob.swung_serial += 1
	mob.rig.force_attack("light")


## 一帧：玩家（带敌人列表）→ 敌人动画 → 伤害结算
func _tick() -> void:
	_tick_frame()


var _last_swing: Dictionary = {}


func _tick_frame() -> void:
	player.step(DT, arena, [mob])
	_last_swing = {}
	if mob != null and is_instance_valid(mob) and mob.alive:
		mob.rig.advance(DT)
		_last_swing = Combat.enemy_swing(mob, player)
		proj.step(DT, {"player": player, "enemies": [mob], "cam": cam, "arena": arena})


## 玩家刀身（世界线段）离某点最近的距离
func _blade_gap(point: Vector3) -> float:
	var rig = player.rig
	var span: Vector2 = rig.blade_span()
	var a: Vector3 = rig.weapon_xf * Vector3(0, span.x, 0)
	var b: Vector3 = rig.weapon_xf * Vector3(0, span.y, 0)
	return Hit.dist_point_segment(point, a, b)


# ------------------------------------------------------------------ 1 剑挡剑几何
func _t_blade_vs_blade() -> void:
	q.section("1 剑挡剑：两把刀的真几何相交才算挡住")
	await _reset_world()
	var span: Vector2 = player.rig.blade_span()
	# 横刀（沿世界 X）竖刀（沿世界 Y）在原点交叉 → 命中
	var xf_x := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
	var xf_z := Transform3D(Basis(), Vector3(0, -1.4, 0))
	var discs: Array = player.rig.blade_discs
	var scale: float = player.rig.weapon_scale
	var hit: Dictionary = Hit.blade_vs_blade(xf_x, discs, scale, span, xf_z, discs, scale, span)
	q.ok(bool(hit.get("hit", false)), "交叉的两把刀算接触", "gap=%.2f m" % float(hit.get("gap", 0.0)))
	# 平行、分开 1.2 m → 不算
	var far := Transform3D(Basis(), Vector3(0, -1.4, 1.2))
	var miss: Dictionary = Hit.blade_vs_blade(xf_x, discs, scale, span, far, discs, scale, span)
	q.ok(not bool(miss.get("hit", false)), "平行且相距 1.2 m 不算接触",
		"gap=%.2f m" % float(miss.get("gap", 0.0)))


# ------------------------------------------------------------------ 2 读招
func _t_predict() -> void:
	q.section("2 读招：从这一刀的时间轴解出未来的刀位姿")
	await _reset_world()
	await _spawn_swinger(4.2)
	var max_err := 0.0
	var seen_window := false
	for i in 200:
		mob.rig.advance(DT)
		player.step(DT, arena, [mob])
		if mob.rig.is_attacking:
			# 预测「现在」应该等于真实的刀位姿
			var pred: Transform3D = mob.rig.predict_weapon_xf(mob.rig.attack_elapsed)
			max_err = maxf(max_err, pred.origin.distance_to(mob.rig.weapon_xf.origin))
		if mob.rig.in_hit_window():
			seen_window = true
		if not mob.rig.is_attacking:
			break
	q.ok(max_err < 0.35, "predict_weapon_xf(现在) 与真实刀位姿一致",
		"最大偏差 %.2f m（只差呼吸/摇摆的那点量）" % max_err)
	q.ok(seen_window, "挥砍确实进入过判定窗口")
	# 威胁解算：能算出「还有多久到、架在哪」
	var threat: Dictionary = InterceptS.melee_threat(player, mob, 0.6)
	q.info("威胁解算", "（已挥完，仅看接口形状）ok=%s" % str(threat.get("ok", false)))


# ------------------------------------------------------------------ 3 架住
## lead = 提前多久按（秒，相对于它的判定窗口开始）。0.12 = 前摇将尽；0.5 = 一起手就按
func _t_block(body_yaw := 0.0, tag := "正对", lead := 0.12) -> void:
	q.section("3 架住一刀：免伤 + 被击退（%s）" % tag)
	await _reset_world()
	await _spawn_swinger(4.2, body_yaw)
	var before: Vector3 = player.rig.global_position
	var pressed := false
	var plan_point := Vector3.ZERO
	var got_plan := false
	var best_gap := 1e9
	var block_ev := {}
	var max_push := 0.0
	var kinds: Array = []
	for i in 300:
		# 看到它的前摇快结束（出刀前一瞬）才按右键 —— 真实操作时序
		if not pressed and mob.rig.is_attacking \
				and float(mob.rig.attack_hit_from) - float(mob.rig.attack_elapsed) <= lead:
			player._begin_parry()
			pressed = true
		_tick_frame()
		if not got_plan and player._intercept_on:
			got_plan = true
			plan_point = player._plan_point
			kinds.append(player._intercept_kind)
		if got_plan:
			best_gap = minf(best_gap, _blade_gap(plan_point))
		max_push = maxf(max_push, player.block_push.length())
		if block_ev.is_empty() and bool(_last_swing.get("parried", false)):
			block_ev = _last_swing.duplicate()
		if not mob.rig.is_attacking:
			break
	var after: Vector3 = player.rig.global_position
	q.ok(pressed, "[%s] 在预定时刻按下了右键" % tag)
	q.ok(got_plan, "[%s] 按下的瞬间就开始规划刀路" % tag, "kind=%s" % str(kinds))
	q.ok(best_gap < 0.45, "[%s] 刀真的被送到了规划落点" % tag, "落点最近距离 %.2f m" % best_gap)
	q.ok(bool(block_ev.get("parried", false)), "[%s] 这一刀被架掉（parried）" % tag, str(block_ev))
	q.ok(player.alive, "[%s] 免伤：一击必死模式下还活着" % tag, "alive=%s" % str(player.alive))
	q.ok(max_push > 0.5, "[%s] 被击退：有推开速度" % tag, "峰值 push=%.1f m/s" % max_push)
	q.ok(after.distance_to(before) > 0.15, "[%s] 人被推开了" % tag,
		"位移 %.2f m" % after.distance_to(before))


# ------------------------------------------------------------------ 4 不按弹反
func _t_no_parry_dies() -> void:
	q.section("4 对照：同样一刀、不按弹反 → 被砍死")
	await _reset_world()
	await _spawn_swinger(4.2)
	for i in 300:
		_tick()
		if not player.alive or not mob.rig.is_attacking:
			break
	q.ok(not player.alive, "不架刀就是一刀死（对照组有效）", "cause=%s" % player.last_cause)


# ------------------------------------------------------------------ 5 远程
func _t_arrow() -> void:
	q.section("5 远程：同一套规划，把刀送到箭的必经之路上")
	await _reset_world()
	var chest: Vector3 = player.rig.global_position + Vector3(0, 2.2, 0)
	var from: Vector3 = player.rig.global_position + Vector3(0, 0, -6.5) + Vector3(0, 2.6, 0)
	var it: Dictionary = proj.spawn_arrow(from, (chest - from).normalized(), 30.0, 999.0, "enemy")
	var pressed := false
	var got_plan := false
	var reflected := false
	for i in 200:
		if not pressed and (it["pos"] as Vector3).distance_to(chest) < 4.0:
			player._begin_parry()
			pressed = true
		player.step(DT, arena, [])
		proj.step(DT, {"player": player, "enemies": [], "cam": cam, "arena": arena})
		if player._intercept_on and player._intercept_kind == "shot":
			got_plan = true
		if String(it["owner"]) == "player":
			reflected = true
			break
		if not player.alive:
			break
	q.ok(pressed, "箭飞近 4 m 时按弹反")
	q.ok(got_plan, "远程也走同一套拦截规划", "kind=%s" % player._intercept_kind)
	q.ok(reflected, "箭被刀身真几何挡到 → 原路弹回", "owner=%s alive=%s" % [String(it["owner"]), player.alive])
	q.ok(player.alive, "弹反成功 → 免伤")

	# 对照：同样的箭、不按弹反 → 被射死
	await _reset_world()
	var chest2: Vector3 = player.rig.global_position + Vector3(0, 2.2, 0)
	var from2: Vector3 = player.rig.global_position + Vector3(0, 0, -6.5) + Vector3(0, 2.6, 0)
	proj.spawn_arrow(from2, (chest2 - from2).normalized(), 30.0, 999.0, "enemy")
	for i in 120:
		player.step(DT, arena, [])
		proj.step(DT, {"player": player, "enemies": [], "cam": cam, "arena": arena})
		if not player.alive:
			break
	q.ok(not player.alive, "不弹反就被箭射死（对照组有效）", "cause=%s" % player.last_cause)
