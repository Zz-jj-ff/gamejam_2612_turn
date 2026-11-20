extends Node3D
## QA 4 —— 小怪视野格挡的边界（零余量）
##
## 跑法： godot --headless --path . res://scenes/qa_vision.tscn
##
## 自己的小型测试场（200×200 平地 + 四面墙），玩家固定在原点、朝向 -Z，
## 小怪固定在正前方 4.6 m，只有相机 yaw 在变（facing_mode=movement，玩家不跟着转），
## 所以「刀能不能砍到」只由视野判定决定。

const Qa = preload("res://tools/qa_lib.gd")
const PlayerS = preload("res://src/game/player.gd")
const CamS = preload("res://src/game/camera.gd")
const ProjS = preload("res://src/game/projectiles.gd")
const MobS = preload("res://src/game/enemy_mob.gd")
const DT := 1.0 / 60.0

var q
var cam
var player
var proj
var arena: Dictionary = {}
var mob


func _ready() -> void:
	Engine.max_fps = 60
	q = Qa.new("qa_vision")
	get_tree().create_timer(120.0).timeout.connect(func(): get_tree().quit(2))
	get_window().size = Vector2i(1600, 900)   # headless 默认是 1600×1600，这里恢复 16:9 的真实取景
	arena = _make_arena()
	proj = ProjS.new()
	add_child(proj)
	cam = CamS.new()
	add_child(cam)
	player = PlayerS.new()
	add_child(player)
	player.set_camera(cam)
	cam.set_rig(player.rig)
	_make_floor()
	await get_tree().process_frame
	await _t_center()
	await _t_angles()
	await _t_sweep()
	await _t_camera_mode()
	await _t_side_slash()
	print("\n== qa_vision: %d checks, %d failed ==" % [q.checks, q.fails])
	get_tree().quit(q.summary())


func _make_floor() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	mi.mesh = pm
	add_child(mi)


func _make_arena() -> Dictionary:
	var walls: Array = []
	var pts := [Vector2(-100, -100), Vector2(100, -100), Vector2(100, 100), Vector2(-100, 100)]
	var nrm := [Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0)]
	for i in 4:
		walls.append({"a": pts[i], "b": pts[(i + 1) % 4], "h": 30.0, "n": nrm[i]})
	return {"node": null, "kind": "test", "name_cn": "测试场", "hint": "", "floor_y": 0.0,
		"bounds": AABB(Vector3(-100, -1, -100), Vector3(200, 40, 200)),
		"walls": walls, "cover": [], "wall_slots": [], "lamps": [], "spawns": [],
		"player_spawn": Transform3D()}


func _reset(face_mode := "movement") -> void:
	if mob != null and is_instance_valid(mob):
		mob.queue_free()
	mob = null
	proj.clear_all()
	P.reset_all()
	P.set_value("move.facing_mode", face_mode)
	P.set_value("mob.aggro_range", 0.5)      # 冻住小怪：它只转身、不追不打
	player.reset(Transform3D(Basis(), Vector3.ZERO))
	player.rig.heading = 0.0
	player.rig.rotation.y = 0.0
	player.rig.facing_override = false
	cam.yaw = 0.0
	cam.pitch = -0.16
	await get_tree().process_frame


func _fp(yaw_deg: float) -> void:
	P.set_value("cam.mode", "first")
	cam.set_first_person(true)
	cam.yaw = deg_to_rad(yaw_deg)
	cam.pitch = deg_to_rad(-6.0)
	cam.step(DT, arena)
	cam.step(DT, arena)


func _spawn_mob(pos: Vector3):
	var m = MobS.new()
	m.setup_mob({"tag": "mob", "accent": Color(0.30, 1.0, 0.72)})
	add_child(m)
	m.global_position = pos
	m.player = player
	m.cam = cam
	m.projectiles = proj
	m.rig.rotation.y = 0.0
	m.rig.heading = 0.0
	return m


## 打一刀，收集：「开局是否可见 / 判定窗口内是否可见 / 是否被格挡 / 掉血」
func _slash(yaw_deg: float) -> Dictionary:
	await _reset()
	_fp(yaw_deg)
	mob = _spawn_mob(Vector3(0, 0, -4.6))
	mob.rig.rotation.y = 0.0
	await get_tree().process_frame
	var vis0: bool = Vision.is_visible(cam.camera, mob.center(), mob.mark_radius())
	var hp0: float = mob.hp
	player._attack_from_input(Vector2.ZERO)
	var events: Array = []
	var vis_in_window := false
	var block_first_frame := -1
	for i in 120:
		player.step(DT, arena)
		mob.step(DT, {"player": player, "cam": cam, "arena": arena,
			"projectiles": proj, "enemies": [mob], "archers": []})
		if player.rig.in_hit_window():
			if Vision.is_visible(cam.camera, mob.center(), mob.mark_radius()):
				vis_in_window = true
		var ev := Combat.player_swing(player, [mob], cam)
		for e in ev:
			if block_first_frame < 0:
				block_first_frame = i
			events.append(String(e["kind"]))
		if not player.rig.is_attacking and i > 3:
			break
	var kinds := ""
	for k in events:
		kinds += k + " "
	if kinds == "":
		kinds = "(无接触)"
	return {"vis0": vis0, "vis_window": vis_in_window,
		"blocked": events.has("block"), "kinds": kinds.strip_edges(),
		"hp": mob.hp, "hp0": hp0, "damaged": mob.hp < hp0 - 0.01,
		"frame": block_first_frame}


# ------------------------------------------------------------------ 4a 中央必挡
func _t_center() -> void:
	q.section("4a 小怪在画面正中央 → 攻击必须被挡")
	var r: Dictionary = await _slash(0.0)
	q.ok(bool(r["vis0"]), "正对时 Vision 判定为可见")
	q.ok(bool(r["blocked"]), "正中央挥砍 → 触发 block", String(r["kinds"]))
	q.ok(not bool(r["damaged"]), "正中央挥砍 → 0 伤害", "hp %.0f → %.0f" % [float(r["hp0"]), float(r["hp"])])


# ------------------------------------------------------------------ 4b 10/20/40 度
func _t_angles() -> void:
	q.section("4b 相机转开 10° / 20° / 40°（零余量规则：必须完全出画）")
	for deg in [10.0, 20.0, 40.0, 60.0]:
		var r: Dictionary = await _slash(deg)
		var consistent := (bool(r["blocked"]) == bool(r["vis0"]))
		q.ok(consistent, "转开 %.0f°：结果与视野判定一致" % deg,
			"可见=%s block=%s 伤害=%s events=%s" % [str(r["vis0"]), str(r["blocked"]),
				str(r["damaged"]), String(r["kinds"])])
		q.info("  %.0f° 细节" % deg, "判定窗口内可见=%s hp %.0f→%.0f" % [
			str(r["vis_window"]), float(r["hp0"]), float(r["hp"])])


# ------------------------------------------------------------------ 4c 精细扫描：出画阈值
func _t_sweep() -> void:
	q.section("4c 扫描：从多少度开始能打到（1° 步长）")
	var first_invisible := -1.0
	var first_damage := -1.0
	var rows: Array = []
	for i in range(0, 91, 2):
		var deg := float(i)
		var r: Dictionary = await _slash(deg)
		if first_invisible < 0.0 and not bool(r["vis0"]):
			first_invisible = deg
		if first_damage < 0.0 and bool(r["damaged"]):
			first_damage = deg
		if i % 10 == 0 or (first_invisible >= 0.0 and deg <= first_invisible + 4.0):
			rows.append("%.0f°:vis=%d blk=%d dmg=%d" % [deg, int(bool(r["vis0"])),
				int(bool(r["blocked"])), int(bool(r["damaged"]))])
		if first_damage >= 0.0 and deg > first_damage + 4.0:
			break
	for row in rows:
		q.info("  " + String(row))
	q.info("小怪完全出画的第一个角度", "%.0f°" % first_invisible)
	q.info("第一次能打出伤害的角度", "%.0f°" % first_damage)
	q.ok(first_invisible >= 0.0, "存在「完全出画」的角度", "%.0f°" % first_invisible)
	q.ok(first_damage >= 0.0, "存在「能打到」的角度", "%.0f°" % first_damage)
	q.ok(absf(first_damage - first_invisible) <= 2.0, "能打到 ⇔ 完全出画（零余量一致）",
		"出画 %.0f° vs 首次伤害 %.0f°" % [first_invisible, first_damage])


# ------------------------------------------------------------------ 4d 默认 facing=camera
func _t_camera_mode() -> void:
	q.section("4d 默认朝向模式 camera：相机转开时玩家跟着转")
	if mob != null and is_instance_valid(mob):
		mob.queue_free()
	await _reset("camera")
	_fp(60.0)
	mob = _spawn_mob(Vector3(0, 0, -4.6))
	await get_tree().process_frame
	# 等朝向跟到相机（facing_heading = cam_yaw）
	for i in 60:
		player.step(DT, arena)
	var heading_err := absf(wrapf(player.rig.heading - cam.yaw, -PI, PI))
	q.ok(heading_err < deg_to_rad(3.0), "camera 模式：玩家朝向跟随相机（转镜头 = 转身）",
		"heading=%.1f° cam.yaw=%.1f°" % [rad_to_deg(player.rig.heading), rad_to_deg(cam.yaw)])
	var vis: bool = Vision.is_visible(cam.camera, mob.center(), mob.mark_radius())
	player._attack_from_input(Vector2.ZERO)
	var kinds := ""
	for i in 120:
		player.step(DT, arena)
		mob.step(DT, {"player": player, "cam": cam, "arena": arena,
			"projectiles": proj, "enemies": [mob], "archers": []})
		for e in Combat.player_swing(player, [mob], cam):
			kinds += String(e["kind"]) + " "
		if not player.rig.is_attacking and i > 3:
			break
	q.info("camera 模式：相机偏 60° 挥正前斩",
		"可见=%s events=%s（刀跟相机转，怪出画但也在刀弧外）" % [str(vis), kinds.strip_edges()])
	P.set_value("move.facing_mode", "movement")


# ------------------------------------------------------------------ 4e 设计意图：侧斩打盲区
func _t_side_slash() -> void:
	q.section("4e 设计意图：把怪放到画面外，用侧斩打死")
	await _reset("movement")
	_fp(0.0)                                     # 相机看正前
	var side := Vector3(-4.2, 0, 0)              # 怪在左侧（-X）
	mob = _spawn_mob(side)
	await get_tree().process_frame
	var off: bool = Vision.fully_offscreen(cam.camera, mob.center(), mob.mark_radius())
	q.ok(off, "左侧 4.2 m 的怪完全不在画面里（相机朝 -Z，FOV 80，横屏 = 水平 ±56°）",
		"角度 %.0f°" % rad_to_deg(atan2(4.2, 4.6)))
	var hp0: float = mob.hp
	player._attack_from_input(Vector2(-1.0, 0.0))     # 左斩
	var kinds := ""
	for i in 120:
		player.step(DT, arena)
		mob.step(DT, {"player": player, "cam": cam, "arena": arena,
			"projectiles": proj, "enemies": [mob], "archers": []})
		for e in Combat.player_swing(player, [mob], cam):
			kinds += String(e["kind"]) + " "
		if not player.rig.is_attacking and i > 3:
			break
	q.ok(mob.hp < hp0 or not mob.alive, "左斩命中画面外的怪", "hp %.0f→%.0f events=%s" % [hp0, mob.hp, kinds.strip_edges()])
