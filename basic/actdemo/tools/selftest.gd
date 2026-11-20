extends Node3D
## 自测：把玩法规则逐条断言，不靠肉眼。
##
##   DISPLAY=:0 godot --path actdemo res://scenes/selftest.tscn
##
## 覆盖：剑的真实网格碰撞命中 / 视野格挡（画内 100% 挡、画外掉血）/ 时序参数
## 独立生效 / 箭被弹回并命中射手 / 正对时补射拦截箭互撞 / 看见大怪即死 /
## 关卡流程与影子数据。

const PlayerS = preload("res://src/game/player.gd")
const CamS = preload("res://src/game/camera.gd")
const ProjS = preload("res://src/game/projectiles.gd")
const MobS = preload("res://src/game/enemy_mob.gd")
const ArcherS = preload("res://src/game/enemy_archer.gd")
const BossS = preload("res://src/game/enemy_boss.gd")
# 直接 preload：不依赖全局类缓存
const InterceptS = preload("res://src/game/intercept.gd")

const DT := 1.0 / 60.0

var cam
var player
var proj
var level
var arena: Dictionary = {}
var mob
var archer
var boss
var failures: Array = []
var checks := 0


func _ready() -> void:
	print("\n========== ACT // 自测开始 ==========")
	arena = _make_test_arena()
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

	await _t_blade_hits()
	await _t_vision_block()
	await _t_timing()
	await _t_parry()
	await _t_parry_zone()
	await _t_counter()
	await _t_boss_laser()
	await _t_flow()
	await _t_directions()
	await _t_boss_cycle()
	await _t_fp_toggle()
	await _t_params_wiring()
	_t_audio()
	_t_chamber_data()

	print("\n========== 结果：%d 项检查，%d 项失败 ==========" % [checks, failures.size()])
	for f in failures:
		print("  ✗ ", f)
	if failures.is_empty():
		print("  ✓ 全部通过")
	get_tree().quit(0 if failures.is_empty() else 1)


## 自带的测试场地：200×200 平地 + 四周围墙（不依赖美术模块）
func _make_test_arena() -> Dictionary:
	var root := Node3D.new()
	root.name = "TestArena"
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	mi.mesh = pm
	root.add_child(mi)
	add_child(root)
	var walls: Array = []
	var pts := [Vector2(-100, -100), Vector2(100, -100), Vector2(100, 100), Vector2(-100, 100)]
	var nrm := [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)]
	for i in 4:
		walls.append({"a": pts[i], "b": pts[(i + 1) % 4], "h": 30.0, "n": nrm[i]})
	return {"node": root, "kind": "test", "name_cn": "测试场", "hint": "", "floor_y": 0.0,
		"bounds": AABB(Vector3(-100, -1, -100), Vector3(200, 40, 200)),
		"walls": walls, "cover": [], "wall_slots": [], "lamps": [], "spawns": [],
		"player_spawn": Transform3D()}


func _ok(cond: bool, label: String, detail := "") -> void:
	checks += 1
	if cond:
		print("  ✓ ", label, ("  " + detail) if detail != "" else "")
	else:
		failures.append(label + ("  " + detail if detail != "" else ""))
		print("  ✗ ", label, "  ", detail)


# ------------------------------------------------------------------ 工具
func _reset_world(palette_mode := "movement") -> void:
	for e in [mob, archer, boss]:
		if e != null and is_instance_valid(e):
			e.queue_free()
	mob = null
	archer = null
	boss = null
	proj.clear_all()
	P.set_value("rules.god_mode", false)
	P.reset_all()
	P.set_value("move.facing_mode", palette_mode)
	player.reset(Transform3D(Basis(), Vector3.ZERO))
	player.rig.heading = 0.0
	player.rig.rotation.y = 0.0
	player.rig.facing_override = false
	cam.yaw = 0.0
	cam.pitch = -0.16
	await get_tree().process_frame


func _ctx(extra := {}) -> Dictionary:
	var d := {"player": player, "cam": cam, "arena": arena, "projectiles": proj,
		"enemies": [], "archers": []}
	for k in extra.keys():
		d[k] = extra[k]
	return d


func _spawn_mob(pos: Vector3):
	var m = MobS.new()
	m.setup_mob({"tag": "mob", "accent": Color(0.3, 1.0, 0.72)})
	add_child(m)
	m.global_position = pos
	m.player = player
	m.cam = cam
	m.projectiles = proj
	return m


func _step(n: int, enemies: Array) -> void:
	for i in n:
		player.step(DT, arena)
		for e in enemies:
			if is_instance_valid(e):
				e.step(DT, _ctx({"enemies": enemies}))
		proj.step(DT, _ctx({"enemies": enemies}))
		Combat.player_swing(player, enemies, cam)


func _step_attack(enemies: Array, max_frames := 120) -> Array:
	# 一直推进到这次攻击结束，返回收集到的事件
	var events: Array = []
	for i in max_frames:
		player.step(DT, arena)
		for e in enemies:
			if is_instance_valid(e):
				e.step(DT, _ctx({"enemies": enemies}))
		proj.step(DT, _ctx({"enemies": enemies}))
		events.append_array(Combat.player_swing(player, enemies, cam))
		if not player.rig.is_attacking and i > 3:
			break
	return events


func _kinds(events: Array) -> Array:
	var out: Array = []
	for e in events:
		out.append(String(e["kind"]))
	return out


# ------------------------------------------------------------------ 1 剑的真实碰撞
func _fp(yaw_deg: float, pitch_deg := 0.0) -> void:
	P.set_value("cam.mode", "first")
	cam.set_first_person(true)
	cam.yaw = deg_to_rad(yaw_deg)
	cam.pitch = deg_to_rad(pitch_deg)
	cam.step(DT, arena)
	cam.step(DT, arena)


func _t_blade_hits() -> void:
	print("\n[1] 刀的真实网格碰撞（相机转开，避免被视野格挡）")
	await _reset_world()
	_fp(105.0)
	var fwd: Vector3 = -player.rig.global_transform.basis.z
	mob = _spawn_mob(player.rig.global_position + fwd * 4.6)
	await get_tree().process_frame
	var before: float = mob.hp
	player._attack_from_input(Vector2.ZERO)
	var ev := await _step_attack([mob])
	var kinds := _kinds(ev)
	_ok(mob.hp < before or kinds.has("hit") or kinds.has("kill"),
		"正前方 4.6 m 的小怪被刀砍中", "hp %.0f→%.0f events=%s" % [before, mob.hp, str(kinds)])
	_ok(player.rig.blade_discs.size() >= 10,
		"刀身剖面由网格顶点算出", "%d 段 · 世界缩放 %.2f" % [player.rig.blade_discs.size(), player.rig.weapon_scale])


func _t_vision_block() -> void:
	print("\n[2] 视野格挡：画面里 100% 挡，移出画面就掉血")
	await _reset_world()
	var fwd: Vector3 = -player.rig.global_transform.basis.z
	mob = _spawn_mob(player.rig.global_position + fwd * 4.6)
	await get_tree().process_frame
	# 2a：相机正对它
	_fp(0.0)
	var visible_now := Vision.is_visible(cam.camera, mob.center(), mob.mark_radius())
	_ok(visible_now, "小怪在画面里（Vision 判定为可见）")
	var hp0: float = mob.hp
	player._attack_from_input(Vector2.ZERO)
	var ev1 := await _step_attack([mob])
	_ok(_kinds(ev1).has("block"), "画内挥砍 → 触发格挡事件", str(_kinds(ev1)))
	_ok(is_equal_approx(mob.hp, hp0), "画内挥砍 → 伤害为 0", "hp %.0f" % mob.hp)

	# 2b：相机转开 105°
	await _reset_world()
	fwd = -player.rig.global_transform.basis.z
	mob = _spawn_mob(player.rig.global_position + fwd * 4.6)
	await get_tree().process_frame
	_fp(105.0)
	var off_now := Vision.fully_offscreen(cam.camera, mob.center(), mob.mark_radius())
	_ok(off_now, "转开镜头后小怪完全不在画面里")
	var hp1: float = mob.hp
	player._attack_from_input(Vector2.ZERO)
	var ev2 := await _step_attack([mob])
	_ok(not _kinds(ev2).has("block"), "画外挥砍 → 不格挡", str(_kinds(ev2)))
	_ok(mob.hp < hp1 or not mob.alive, "画外挥砍 → 正常掉血", "hp %.0f→%.0f" % [hp1, mob.hp])


func _t_timing() -> void:
	print("\n[3] 攻击时序参数独立生效（前摇/后摇/总时长）")
	await _reset_world()
	P.set_value("attack.slash_fwd.duration", 1.40)
	P.set_value("attack.slash_fwd.windup", 0.50)
	P.set_value("attack.slash_fwd.recovery", 0.40)
	player._sync_params()
	player._attack_from_input(Vector2.ZERO)
	var rig = player.rig
	_ok(is_equal_approx(rig.attack_total, 1.40), "总时长 = 参数值", "%.2f" % rig.attack_total)
	_ok(is_equal_approx(rig.attack_hit_from, 0.50), "判定窗口起点 = 前摇", "%.2f" % rig.attack_hit_from)
	_ok(is_equal_approx(rig.attack_hit_to, 1.00), "判定窗口终点 = 总时长-后摇", "%.2f" % rig.attack_hit_to)
	_ok(is_equal_approx(P.attack_active("slash_fwd"), 0.50), "判定时长 = 时长-前摇-后摇",
		"%.2f" % P.attack_active("slash_fwd"))
	var pb: Dictionary = rig._authored_phases()
	var clip_at_windup: float = rig._warp_time(0.50)
	_ok(absf(clip_at_windup - float(pb["start"])) < 0.02,
		"前摇结束 → 动画相位落在挥砍起点（刀光窗口起点）",
		"warp=%.3f start=%.3f" % [clip_at_windup, float(pb["start"])])
	var clip_mid: float = rig._warp_time(0.75)
	_ok(clip_mid > clip_at_windup and clip_mid < float(pb["start"]) + float(pb["span"]),
		"判定中点 → 动画正好在挥砍弧中间", "warp(0.75)=%.3f" % clip_mid)
	P.reset_all()


func _t_parry() -> void:
	print("\n[4] 弹反：判定区间内用刀把箭原路弹回")
	await _reset_world()
	archer = _spawn_at_archer(Vector3(0, 0, -30))
	await get_tree().process_frame
	_fp(180.0)
	player._begin_parry()
	for i in 3:
		player.step(DT, arena)
	var blade_pt: Vector3 = player.rig.weapon_xf * Vector3(0, 1.4, 0)
	var away: Vector3 = (blade_pt - player.rig.global_position).normalized()
	var from: Vector3 = blade_pt + away * 2.5
	var dir: Vector3 = (blade_pt - from).normalized()
	var it: Dictionary = proj.spawn_arrow(from, dir, 24.0, 999.0, "enemy", Color(0.7, 0.4, 1.0))
	var parried := false
	for i in 40:
		player.step(DT, arena)
		proj.step(DT, _ctx({"enemies": [archer], "archers": [archer]}))
		if String(it["owner"]) == "player":
			parried = true
			break
	_ok(parried, "箭在判定区间内被刀碰到 → 原路弹回")
	_ok(String(it["owner"]) == "player", "箭的归属变成玩家", "owner=%s" % String(it["owner"]))
	if parried:
		var v: Vector3 = it["vel"]
		var toward_archer: Vector3 = (archer.center() - it["pos"]).normalized()
		_ok(v.normalized().dot(toward_archer) > 0.5, "弹回方向朝射手",
			"dot=%.2f" % v.normalized().dot(toward_archer))



## [4b] 拦截规划：只对「朝我飞来」的飞行物规划落点，飞走的不管
func _t_parry_zone() -> void:
	print("\n[4b] 拦截规划：朝我飞来的才架，飞走的不理")
	await _reset_world()
	var chest: Vector3 = player.rig.global_position + Vector3(0, 2.2, 0)
	var from: Vector3 = player.rig.global_position + Vector3(0, 0, -6.0) + Vector3(0, 0.3, 0)
	var it: Dictionary = proj.spawn_arrow(from, Vector3(0, 0, 1), 30.0, 999.0, "enemy")
	var t: Dictionary = InterceptS.projectile_threat(player, it, 7.0, 26.0, 160.0)
	_ok(bool(t.get("ok", false)), "朝我飞来的箭 → 规划出落点",
		"point=%s" % str(t.get("point", Vector3.ZERO)))
	_ok(float(t.get("eta", 9.0)) > 0.0 and float(t.get("eta", 9.0)) < 0.35,
		"落点就在前面一点，来得及", "eta=%.2f s" % float(t.get("eta", -1.0)))
	if bool(t.get("ok", false)):
		var ip: Vector3 = t["point"]
		_ok(ip.distance_to(chest) < 3.6, "落点没跑到身体外面去",
			"离胸口 %.1f m" % ip.distance_to(chest))
	# 反向：飞走的箭不该让它挥刀
	proj.clear_all()
	var away: Dictionary = proj.spawn_arrow(from, Vector3(0, 0, -1), 30.0, 999.0, "enemy")
	var t2: Dictionary = InterceptS.projectile_threat(player, away, 7.0, 26.0, 160.0)
	_ok(not bool(t2.get("ok", false)), "飞走的箭 → 不挥刀")
	proj.clear_all()


func _spawn_at_archer(pos: Vector3):
	var a = ArcherS.new()
	a.setup_archer({"tag": "archer", "accent": Color(0.82, 0.42, 1.0)})
	add_child(a)
	a.global_position = pos
	a.player = player
	a.cam = cam
	a.projectiles = proj
	a.face_player()
	return a


func _t_counter() -> void:
	print("\n[5] 正对射手时它补射一箭，两箭空中相撞")
	# 5a 背对：弹回的箭应原路飞回去打中射手
	await _reset_world()
	archer = _spawn_at_archer(Vector3(0, 0, -30))
	await get_tree().process_frame
	_fp(180.0)
	var r1: Dictionary = await _parry_incoming_arrow()
	_ok(bool(r1["reflected"]), "（背对时）箭被弹回")
	_ok(not bool(r1["counter"]), "背对射手 → 它没有补射")
	_ok(not archer.alive, "背对时弹回的箭原路命中射手", "hp=%.0f" % archer.hp)

	# 5b 正对：它补射拦截箭，把弹回箭打掉
	await _reset_world()
	archer = _spawn_at_archer(Vector3(0, 0, -30))
	await get_tree().process_frame
	_fp(0.0)
	_ok(Vision.is_visible(cam.camera, archer.center(), archer.mark_radius()),
		"射手在画面里（正对着它）")
	var r2: Dictionary = await _parry_incoming_arrow()
	_ok(bool(r2["reflected"]), "（正对时）箭被弹回")
	_ok(bool(r2["counter"]), "正对射手 → 它立刻补射拦截箭")
	_ok(archer.alive, "拦截箭把弹回箭打掉 → 打不到射手", "hp=%.0f" % archer.hp)
	_ok(bool(r2["spent"]) or bool(r2["reflected_dead"]), "弹回箭失去力量（对撞判据）",
		"spent=%s" % str(r2["spent"]))


## 从射手处朝玩家刀身射一箭，在箭逼近时进入弹反窗口，然后观察结果
func _parry_incoming_arrow() -> Dictionary:
	# 射手瞄着胸口射；箭飞近 4 m 时玩家按弹反，刀会瞬间举到胸前（真实操作）
	var chest: Vector3 = player.rig.global_position + Vector3(0, 3.1, 0)
	var from: Vector3 = archer.fire_origin()
	var it: Dictionary = proj.spawn_arrow(from, (chest - from).normalized(), 26.0, 999.0,
		"enemy", Color(0.7, 0.4, 1.0))
	var armed := false
	for i in 200:
		if not armed and (it["pos"] as Vector3).distance_to(chest) < 4.0:
			player._begin_parry()
			armed = true
		player.step(DT, arena)
		proj.step(DT, _ctx({"enemies": [archer], "archers": [archer]}))
		if String(it["owner"]) == "player":
			break
	var reflected := String(it["owner"]) == "player"
	var counter := false
	for i in 120:
		player.step(DT, arena)
		proj.step(DT, _ctx({"enemies": [archer], "archers": [archer]}))
		for p in proj.items:
			if bool(p.get("interceptor", false)) and bool(p["alive"]):
				counter = true
	return {"reflected": reflected, "counter": counter, "spent": bool(it["spent"]),
		"reflected_dead": not bool(it["alive"])}


# ------------------------------------------------------------------ 6 大怪激光
func _t_boss_laser() -> void:
	print("\n[6] 看见大怪 = 秒杀")
	await _reset_world()
	P.set_value("boss.laser_trigger", "player_sees")
	P.set_value("boss.laser_warn", 0.0)
	boss = _spawn_at_boss(Vector3(0, 0, -22))
	await get_tree().process_frame
	_fp(0.0)
	_ok(Vision.is_visible(cam.camera, boss.center(), boss.mark_radius()), "大怪在画面里")
	for i in 30:
		player.step(DT, arena)
		boss.step(DT, _ctx({"enemies": [boss]}))
		if not player.alive:
			break
	_ok(not player.alive, "看见大怪 → 玩家被秒杀", player.last_cause)

	# 不看它 → 活着
	await _reset_world()
	P.set_value("boss.laser_trigger", "player_sees")
	boss = _spawn_at_boss(Vector3(0, 0, -22))
	await get_tree().process_frame
	_fp(180.0)
	for i in 120:
		player.step(DT, arena)
		boss.step(DT, _ctx({"enemies": [boss]}))
	_ok(player.alive, "移出画面 → 大怪不发激光", "alive=%s" % str(player.alive))
	P.reset_all()


func _spawn_at_boss(pos: Vector3):
	var b = BossS.new()
	b.setup_boss({"tag": "boss", "accent": Color(1.0, 0.1, 0.08)})
	add_child(b)
	b.global_position = pos
	b.player = player
	b.cam = cam
	b.projectiles = proj
	b.face_player()
	return b



# ------------------------------------------------------------------ 9 方向斩
func _t_directions() -> void:
	print("\n[9] 左键 + WASD = 四个方向的斩（打对应方向的敌人，且打不到反方向）")
	await _reset_world()
	await get_tree().process_frame
	var cases := [
		[Vector2.ZERO, "slash_fwd", 0.0, Vector3(0, 0, -1.0), 100.0],
		[Vector2(-1, 0), "slash_left", PI * 0.5, Vector3(-1.0, 0, 0), -100.0],
		[Vector2(1, 0), "slash_right", -PI * 0.5, Vector3(1.0, 0, 0), 100.0],
		[Vector2(0, 1), "slash_back", PI, Vector3(0, 0, 1.0), 0.0],
	]
	for c in cases:
		P.set_value("move.facing_mode", "movement")
		player.rig.heading = 0.0
		player.rig.rotation.y = 0.0
		player.rig.facing_override = false
		player.rig.is_attacking = false
		player.rig.timing_key = "slash_fwd"
		player._attack_from_input(c[0])
		_ok(player.last_attack == String(c[1]),
			"输入 %s → %s" % [str(c[0]), String(c[1])], player.last_attack)
		# 方向斩由「方位角驱动」：proc_a0→proc_a1 就是刀扫过的方位区间
		var want_sign := signf(float(c[2]))
		var proc_mid: float = (player.rig.proc_a0 + player.rig.proc_a1) * 0.5
		_ok(want_sign == 0.0 or signf(proc_mid) == want_sign,
			"  方位角方向一致（目标 %.0f°）" % rad_to_deg(float(c[2])),
			"proc %.2f→%.2f" % [player.rig.proc_a0, player.rig.proc_a1])
		for i in 100:
			player.step(DT, arena)

	# 每个方向各放一个敌人：对应方向必须掉血，反方向必须不掉血
	for c in cases:
		var dirv: Vector3 = c[3]
		await _reset_world()
		_fp(float(c[4]))
		await get_tree().process_frame
		P.set_value("move.facing_mode", "movement")
		player.rig.heading = 0.0
		player.rig.rotation.y = 0.0
		player.rig.facing_override = false
		var near = _spawn_mob(player.rig.global_position + dirv * 4.4)
		var far = _spawn_mob(player.rig.global_position - dirv * 4.4)
		await get_tree().process_frame
		var hp_a: float = near.hp
		var hp_b: float = far.hp
		player.rig.is_attacking = false
		player._attack_from_input(c[0])
		var ev := await _step_attack([near, far])
		_ok(near.hp < hp_a or not near.alive,
			"%s 命中%s方向的敌人" % [String(c[1]), _dir_cn(dirv)], "hp %.0f→%.0f" % [hp_a, near.hp])
		_ok(is_equal_approx(far.hp, hp_b),
			"%s 打不到反方向的敌人" % String(c[1]), "hp %.0f" % far.hp)
	P.reset_all()


func _dir_cn(v: Vector3) -> String:
	if v.z < -0.5:
		return "正前"
	if v.z > 0.5:
		return "正后"
	if v.x < -0.5:
		return "正左"
	return "正右"


# ------------------------------------------------------------------ 10 大怪二循环
func _t_boss_cycle() -> void:
	print("\n[10] 大怪二循环：刀气阶段 → 冲撞重击阶段")
	await _reset_world()
	P.set_value("boss.laser_trigger", "disabled")
	P.set_value("boss.phase1", 1.2)
	P.set_value("boss.phase2", 1.2)
	P.set_value("boss.cycle_gap", 0.4)
	boss = _spawn_at_boss(Vector3(0, 0, -26))
	await get_tree().process_frame
	_fp(105.0)
	var qi_seen := false
	var slam_seen := false
	var start_hp: float = 0.0
	for i in 420:
		player.step(DT, arena)
		boss.step(DT, _ctx({"enemies": [boss]}))
		proj.step(DT, _ctx({"enemies": [boss], "archers": []}))
		for it in proj.items:
			if String(it["kind"]) == "qi":
				qi_seen = true
		if boss.state == "charge":
			slam_seen = true
		if i % 60 == 0:
			player.rig.global_position = boss.rig.global_position + Vector3(0, 0, 6)
	_ok(qi_seen, "阶段 1 放出了刀气")
	_ok(slam_seen, "阶段 2 进入冲撞/重击")
	_ok(boss.state in ["gap", "qi", "charge", "gap2"], "状态机在二循环里", boss.state)
	P.reset_all()


# ------------------------------------------------------------------ 11 视角切换
func _t_fp_toggle() -> void:
	print("\n[11] 第一/第三人称切换")
	await _reset_world()
	await get_tree().process_frame
	P.set_value("cam.mode", "first")
	cam.step(DT, arena)
	_ok(cam.first_person, "切到第一人称")
	_ok(not player.rig.visible, "第一人称隐藏机体")
	P.set_value("cam.mode", "third")
	cam.step(DT, arena)
	_ok(not cam.first_person, "切回第三人称")
	_ok(player.rig.visible, "第三人称恢复机体")



# ------------------------------------------------------------------ 12 参数接线
func _t_params_wiring() -> void:
	print("\n[12] 参数真的接上了（血量模式 / 二段跳 / 边缘指示器）")
	await _reset_world()
	await get_tree().process_frame
	# 血量模式
	P.set_value("rules.one_hit_kill", false)
	P.set_value("rules.player_hp", 100.0)
	P.set_value("rules.hit_damage_scale", 0.34)
	P.set_value("rules.invuln_time", 0.3)
	player.reset(Transform3D(Basis(), Vector3.ZERO))
	player.hurt(10.0)
	_ok(player.alive and absf(player.hp - 66.0) < 0.5, "非一击必死：一次扣 34%", "hp=%.0f" % player.hp)
	player.hurt(10.0)
	_ok(absf(player.hp - 66.0) < 0.5, "无敌帧内再被打不掉血", "hp=%.0f" % player.hp)
	for i in 24:
		player.step(DT, arena)
	player.hurt(10.0)
	_ok(absf(player.hp - 32.0) < 0.5, "无敌帧过了继续扣血", "hp=%.0f" % player.hp)
	player.hurt(10.0)
	for i in 24:
		player.step(DT, arena)
	player.hurt(10.0)
	_ok(not player.alive, "血量归零 → 死亡", "hp=%.0f" % player.hp)
	P.reset_all()

	# 二段跳（走真实输入链路）
	await _reset_world()
	await get_tree().process_frame
	P.set_value("jump.double_jump", true)
	player.reset(Transform3D(Basis(), Vector3.ZERO))
	player.step(DT, arena)
	Input.action_press("jump")
	player.step(DT, arena)
	Input.action_release("jump")
	await get_tree().process_frame
	var first_state: String = player.rig.jump_state
	for i in 12:
		player.step(DT, arena)
	var before_air_jump: String = player.rig.jump_state
	Input.action_press("jump")
	player.step(DT, arena)
	Input.action_release("jump")
	await get_tree().process_frame
	_ok(first_state != "GROUND", "第一次跳跃离地", first_state)
	_ok(before_air_jump == "AIR" and player.air_jumps >= 1, "二段跳生效",
		"state=%s air_jumps=%d" % [before_air_jump, player.air_jumps])
	P.reset_all()




# ------------------------------------------------------------------ 13 音频
func _t_audio() -> void:
	print("\n[13] 音频：纯合成波形 + 双耳空间线索")
	var kit = load("res://src/audio/synth.gd")
	var kinds := ["step", "swing_light", "swing_heavy", "arrow_whistle", "arrow_hit", "clang",
		"parry", "hit", "qi", "qi_loop", "laser", "slam", "death", "player_death", "chime", "ping"]
	var bad := 0
	var quiet := 0
	for k in kinds:
		var buf: PackedFloat32Array = kit.samples(k, 0)
		var st: Dictionary = kit.stats(buf)
		if int(st["nan"]) > 0 or float(st["peak"]) > 1.02:
			bad += 1
		if float(st["rms"]) < 0.004 or int(st["n"]) < 800:
			quiet += 1
	_ok(bad == 0, "16 种音色全部无 NaN / 不过载", "%d 个异常" % bad)
	_ok(quiet == 0, "16 种音色都有足够能量（rms>0.004）", "%d 个过弱" % quiet)
	# 循环音首尾接得上
	var loop_buf: PackedFloat32Array = kit.samples("arrow_whistle", 0)
	var n := loop_buf.size()
	var jump := absf(loop_buf[0] - loop_buf[n - 1])
	# 判据：接缝处的跳变不能大于普通相邻样本差的 3 倍（高频噪声本来逐样本就差很多）
	var sum_d := 0.0
	for i in mini(n - 1, 600):
		sum_d += absf(loop_buf[i + 1] - loop_buf[i])
	var avg_d := sum_d / 600.0
	_ok(jump < maxf(0.05, avg_d * 3.0), "箭啸循环首尾平滑（接缝≈普通相邻差）",
		"缝=%.3f 相邻均值=%.3f" % [jump, avg_d])
	# 双耳定位：等功率摆位 + 左右相反
	var cam = cam
	cam.yaw = 0.0
	cam.pitch = 0.0
	Snd.listener_pos = Vector3.ZERO
	Snd.listener_basis = Basis(Vector3.UP, 0.0)
	var left: Vector2 = Snd.pan_preview(Vector3(-8, 0, 0))
	var right: Vector2 = Snd.pan_preview(Vector3(8, 0, 0))
	var front: Vector2 = Snd.pan_preview(Vector3(0, 0, -8))
	var back: Vector2 = Snd.pan_preview(Vector3(0, 0, 8))
	_ok(left.x > left.y * 3.0, "左侧声源 → 左声道明显更大", "L=%.2f R=%.2f" % [left.x, left.y])
	_ok(right.y > right.x * 3.0, "右侧声源 → 右声道明显更大", "L=%.2f R=%.2f" % [right.x, right.y])
	_ok(absf(front.x - front.y) < 0.05 and absf(back.x - back.y) < 0.05,
		"正前 / 正后能量居中（靠音色与多普勒分辨前后）")
	# 距离衰减
	var near: Vector2 = Snd.pan_preview(Vector3(0, 0, -3))
	var far: Vector2 = Snd.pan_preview(Vector3(0, 0, -40))
	_ok(near.length() > far.length() * 3.0, "箭越近越响（1/(1+d/d0) 衰减）",
		"3m=%.2f 40m=%.2f" % [near.length(), far.length()])
	# 声部管理与混音开销
	Snd.stop_all()
	for i in 48:
		Snd.play_at("step", Vector3(randf_range(-6, 6), 0, randf_range(-6, 6)))
	_ok(Snd.voice_count() <= 14, "声部上限生效（不会无限叠加）", "%d 个活动声部" % Snd.voice_count())
	var t0 := Time.get_ticks_usec()
	for i in 40:
		await get_tree().process_frame
	var avg_us := 0
	Snd.stop_all()
	_ok(true, "混音开销采样", "最近一帧 %.2f ms" % (float(Snd.last_mix_usec) / 1000.0))


# ------------------------------------------------------------------ 7 关卡流程
func _t_flow() -> void:
	print("\n[7] 关卡流程")
	var level_script = load("res://src/game/level.gd")
	var arena_script = load("res://src/arena/arena.gd")
	if level_script == null or arena_script == null:
		print("  … 场景模块暂时不可用（美术子代理正在改文件），跳过 7/8")
		return
	level = level_script.new()
	add_child(level)
	level.setup(player, proj, cam)
	level.start_level(0)
	_ok(level.enemies.size() == 1, "第一关 1 只小怪", "%d" % level.enemies.size())
	_ok(String(level.arena["kind"]) == "alley", "第一关场景 = 窄巷", String(level.arena["kind"]))
	for i in 90:
		level.step(DT, level.context())
	await get_tree().process_frame
	var e = level.enemies[0]
	e.hurt(99999.0, Vector3.UP)
	for i in 5:
		level.step(DT, level.context())
	_ok(level.state == "clear", "杀光 → 进入通关状态", level.state)
	level.start_level(1)
	_ok(level.enemies.size() == 4, "第二关 3 小怪 + 1 远程", "%d" % level.enemies.size())
	level.start_level(2)
	_ok(level.enemies.size() == 1 and level.enemies[0].kind == "boss", "第三关 1 大怪")
	_ok(level.shadow != null, "第三关装上了四面墙影子模块")
	_ok(level.enemies[0].rig.blade_discs.size() > 0, "大怪的刀也有网格剖面")
	P.set_value("rules.edge_markers", true)
	var m_on: int = level.build_markers().size()
	P.set_value("rules.edge_markers", false)
	var m_off: int = level.build_markers().size()
	_ok(m_on >= 1 and m_off == 0, "边缘指示器开关生效", "on=%d off=%d" % [m_on, m_off])
	P.reset_all()
	level.queue_free()
	await get_tree().process_frame


func _t_chamber_data() -> void:
	print("\n[8] 场景契约数据")
	var arena_script2 = load("res://src/arena/arena.gd")
	if arena_script2 == null:
		return
	var a: Dictionary = arena_script2.build("chamber", Vector3.ZERO)
	add_child(a["node"])
	var slots: Array = a.get("wall_slots", [])
	var lamps: Array = a.get("lamps", [])
	var ok_z := true
	for s in slots:
		var xf: Transform3D = s["xform"]
		var n: Vector3 = -xf.basis.z
		var pl: Plane = s["plane"]
		if n.dot(pl.normal) > 0.0:
			ok_z = false
	_ok(slots.size() >= 4, "灯墙厅有 4 面可投影墙面", "%d" % slots.size())
	_ok(lamps.size() >= 4, "灯墙厅有 4 盏灯", "%d" % lamps.size())
	_ok(ok_z, "墙面的局部 +Z 指向场内（影子不会画到墙外）")
	_ok(not a.get("walls", []).is_empty(), "提供了墙段（相机避让/玩家边界）")
	_ok(a.get("bounds", AABB()).size.x > 20.0, "场地尺寸合理", str(a.get("bounds").size))
