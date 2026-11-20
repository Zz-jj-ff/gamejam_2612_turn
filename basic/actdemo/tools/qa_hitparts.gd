extends Node3D
## QA —— 敌人「多段受击判定件」是否真的覆盖四肢。
##
## 用户报的问题：原来整只怪只有一个躯干大胶囊，打腿/打手完全没反应。
## 这里验证：
##   1) hit_parts() 真的生成了骨盆/胸/头/肩甲/四条腿/双臂；
##   2) 刀扫过每一段都能命中，且命中的正是那一段；
##   3) 原来那个单胶囊会漏掉这些腿；
##   4) Combat.player_swing 走完整链路打腿也能掉血；
##   5) 打空处不会误判。
##
## 跑法： godot --headless --path . res://scenes/qa_hitparts.tscn

const Qa = preload("res://tools/qa_lib.gd")
const PlayerS = preload("res://src/game/player.gd")
const MobS = preload("res://src/game/enemy_mob.gd")
const ArcherS = preload("res://src/game/enemy_archer.gd")
const BossS = preload("res://src/game/enemy_boss.gd")
const CombatS = preload("res://src/game/combat.gd")
const PAL := {"tag": "probe", "accent": Color(0.30, 1.0, 0.72),
	"tint": Color(0.80, 0.92, 1.02), "metal_mix": 0.16}

var q
var player
var mob

var body_parts: int = 0
var leg_parts := []
var arm_parts := []


func _ready() -> void:
	q = Qa.new("qa_hitparts")
	P.reset_all()
	player = PlayerS.new()
	add_child(player)
	mob = MobS.new()
	mob.setup_mob(PAL)
	add_child(mob)
	await get_tree().process_frame
	await get_tree().process_frame
	mob.global_position = Vector3(0, 0, 0)
	for i in 4:
		mob.rig.advance(1.0 / 60.0)
	player.reset(Transform3D(Basis(), Vector3(0, 0, 6)))

	await _t_parts()
	await _t_all_kinds()
	await _t_geometry()
	await _t_old_capsule()
	await _t_combat()
	await _t_no_false_positive()
	_t_perf()
	q.summary()
	get_tree().quit()


func _t_perf() -> void:
	q.section("开销")
	var n := 2000
	var t0 := Time.get_ticks_usec()
	for i in n:
		mob.hit_parts()
	var per_part := float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)
	q.ok(per_part < 0.5, "单次 hit_parts < 0.5 ms", "%.4f ms/次" % per_part)
	var discs: Array = mob.rig.blade_discs
	if discs.is_empty():
		discs = [{"y": 0.0, "r": 0.06}]
	var mid: Vector3 = mob.global_position + Vector3(0, 1.4, 0)
	var prev := Transform3D(Basis(), mid + Vector3(1.2, 0, 0))
	var cur := Transform3D(Basis(), mid - Vector3(1.2, 0, 0))
	var m := 200
	t0 = Time.get_ticks_usec()
	for i in m:
		Hit.sweep_blade_parts(prev, cur, discs, 1.0, mob.hit_parts())
	var per_sweep := float(Time.get_ticks_usec() - t0) / 1000.0 / float(m)
	q.ok(per_sweep < 2.0, "单次多段挥砍判定 < 2 ms", "%.4f ms/次（%d 圆盘）" % [per_sweep, discs.size()])


func _t_parts() -> void:
	q.section("判定件由关节生成")
	var parts: Array = mob.hit_parts()
	for p in parts:
		if String(p["label"]) == "leg":
			leg_parts.append(p)
		elif String(p["label"]) == "arm":
			arm_parts.append(p)
		if String(p["label"]) in ["pelvis", "chest", "head", "pauldron", "pack"]:
			body_parts += 1
	q.ok(parts.size() >= 18, "判定件数量 >= 18", "实际 %d" % parts.size())
	q.ok(leg_parts.size() == 8, "四条腿 = 8 段（股骨 + 胫骨）", "实际 %d" % leg_parts.size())
	q.ok(arm_parts.size() == 4, "双臂 = 4 段（上臂 + 前臂）", "实际 %d" % arm_parts.size())
	q.ok(body_parts >= 5, "躯干/头/肩甲/背包齐全", "实际 %d" % body_parts)
	# 最外侧的腿必须伸出机体躯干之外（这正是原来漏判的地方）
	var far := 0.0
	for p in leg_parts:
		var m: Vector3 = (Vector3(p["a"]) + Vector3(p["b"])) * 0.5
		far = maxf(far, Vector2(m.x - mob.global_position.x, m.z - mob.global_position.z).length())
	q.ok(far > 1.2, "腿段伸到躯干之外", "最远 XZ 半径 %.2f" % far)
	# 判定件半径都必须是正数
	var bad := 0
	for p in parts:
		if float(p["r"]) <= 0.02:
			bad += 1
	q.ok(bad == 0, "所有判定件半径 > 0", "异常 %d" % bad)


func _t_all_kinds() -> void:
	q.section("三种怪都走同一套判定件")
	var archer = ArcherS.new()
	archer.setup_archer(PAL)
	add_child(archer)
	var boss = BossS.new()
	boss.setup_boss(PAL)
	add_child(boss)
	await get_tree().process_frame
	await get_tree().process_frame
	archer.global_position = Vector3(12, 0, 0)
	boss.global_position = Vector3(-14, 0, 0)
	for i in 4:
		archer.rig.advance(1.0 / 60.0)
		boss.rig.advance(1.0 / 60.0)
	var mob_r := _leg_radius(mob.hit_parts())
	var arc_r := _leg_radius(archer.hit_parts())
	var boss_r := _leg_radius(boss.hit_parts())
	q.ok(archer.hit_parts().size() >= 18, "远程怪判定件齐全（没刀也算）",
		"%d 件" % archer.hit_parts().size())
	q.ok(absf(arc_r - mob_r) < 0.05, "远程怪判定件半径与小怪一致",
		"%.2f / %.2f" % [arc_r, mob_r])
	q.ok(absf(boss_r - 2.0 * mob_r) < 0.12, "大怪判定件随 ×2 体型放大",
		"%.2f / 小怪 %.2f" % [boss_r, mob_r])
	archer.queue_free()
	boss.queue_free()


func _leg_radius(parts: Array) -> float:
	var r := 0.0
	for p in parts:
		if String(p["label"]) == "leg":
			r = maxf(r, float(p["r"]))
	return r


func _t_geometry() -> void:
	q.section("刀扫过每一段都能命中")
	var labels := ["pelvis", "chest", "head", "pauldron", "pack", "leg", "foot", "arm", "hand"]
	var parts: Array = mob.hit_parts()
	for label in labels:
		var part: Dictionary = {}
		for p in parts:
			if String(p["label"]) == label:
				part = p
				break
		if part.is_empty():
			q.ok(false, "缺少判定件 %s" % label)
			continue
		var mid: Vector3 = (Vector3(part["a"]) + Vector3(part["b"])) * 0.5
		var res := Hit.sweep_blade_parts(
			Transform3D(Basis(), mid + Vector3(3, 0, 0)),
			Transform3D(Basis(), mid - Vector3(3, 0, 0)),
			[{"y": 0.0, "r": 0.05}], 1.0, parts)
		var got := String(res.get("part", ""))
		# 拳头和手腕同心：前臂末端的胶囊本来就会先吃到这一刀，两者都算对
		var want: Array = ["hand", "arm"] if label == "hand" else [label]
		q.ok(bool(res.get("hit", false)) and got in want,
			"横斩 %s 判定件" % label, "命中=%s 件=%s 深度=%.3f" % [
				str(res.get("hit", false)), got, float(res.get("depth", 0.0))])


func _t_old_capsule() -> void:
	q.section("旧单胶囊覆盖不到腿（回归对照）")
	var old: Dictionary = Hit.rig_capsule(mob.rig, 1.1, 3.4)
	var missed := 0
	var worst := -999.0
	for p in leg_parts:
		var mid: Vector3 = (Vector3(p["a"]) + Vector3(p["b"])) * 0.5
		var gap: float = Hit.dist_point_segment(mid, old["a"], old["b"]) - float(old["r"])
		worst = maxf(worst, gap)
		if gap > 0.0:
			missed += 1
	q.ok(missed > 0, "旧胶囊至少漏掉一段腿", "漏 %d/%d 段，最远差 %.2f" % [
		missed, leg_parts.size(), worst])


func _t_combat() -> void:
	q.section("Combat.player_swing 打腿 → 真的掉血")
	P.set_value("mob.block_when_visible", false)
	P.set_value("rules.vision_occlusion", false)
	var hp0: float = mob.hp
	var leg: Dictionary = {}
	for p in leg_parts:
		if String(p["label"]) == "leg":
			leg = p
			break
	var mid: Vector3 = (Vector3(leg["a"]) + Vector3(leg["b"])) * 0.5
	player.last_attack = "slash_fwd"
	player.swing_serial += 1
	var rig = player.rig
	rig.is_attacking = true
	rig.attack_elapsed = 0.0
	rig.attack_hit_from = -1.0
	rig.attack_hit_to = 99.0
	rig.blade_discs = [{"y": 0.0, "r": 0.06}]
	rig.weapon_scale = 1.0
	rig.weapon_prev_xf = Transform3D(Basis(), mid + Vector3(2, 0, 0))
	rig.weapon_xf = Transform3D(Basis(), mid - Vector3(2, 0, 0))
	var evs: Array = CombatS.player_swing(player, [mob], null, [])
	var kind := String(evs[0]["kind"]) if evs.size() > 0 else "无事件"
	q.ok(evs.size() == 1 and kind in ["hit", "kill"], "打腿产生命中事件",
		"事件=%s" % kind)
	q.ok(mob.hp < hp0, "怪物掉血", "hp %.0f → %.0f" % [hp0, mob.hp])


func _t_no_false_positive() -> void:
	q.section("打空处不误判")
	var mob2 = MobS.new()
	mob2.setup_mob(PAL)
	add_child(mob2)
	await get_tree().process_frame
	mob2.global_position = Vector3(0, 0, 0)
	for i in 4:
		mob2.rig.advance(1.0 / 60.0)
	var parts: Array = mob2.hit_parts()
	# 找一个离所有判定件都够远的空点
	var air := Vector3(0, 1.2, -1.15)
	var clear := 999.0
	for p in parts:
		clear = minf(clear, Hit.dist_point_segment(air, p["a"], p["b"]) - float(p["r"]))
	q.ok(clear > 0.25, "测试点确实在判定件之外", "净空 %.2f" % clear)
	var res := Hit.sweep_blade_parts(
		Transform3D(Basis(), air + Vector3(0.6, 0, 0)),
		Transform3D(Basis(), air - Vector3(0.6, 0, 0)),
		[{"y": 0.0, "r": 0.05}], 1.0, parts)
	q.ok(not bool(res.get("hit", false)), "空处横扫不命中",
		"件=%s" % String(res.get("part", "")))
	mob2.queue_free()
