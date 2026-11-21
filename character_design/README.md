# 赛博朋克敌人角色工程

三个**独立可运行**的 Godot 4.7.2 角色工程，全部资产在运行时由代码生成：
没有任何外部网格、贴图、字体或音频。每个工程都能单独打开、旋转视角、
用场景内数值输入框实时调参、逐帧拖动时间轴检查动作。

| 目录 | 角色 | 定位 | 动画 | 视觉核心 |
| --- | --- | --- | --- | --- |
| `arc_sentinel/` | **ARC // SENTINEL v2** | 基础近战敌人 · 双轮平衡机兵 | rest / idle / walk / attack / attack_up / defend / draw / sheathe | 正面大摄像头（战斗时缩回机身）、黑色+橙红金属、双实心胎纹轮 + 独立悬挂、三球关节长臂、橙红电弧刀、硬光盾 |
| `shard_phantom/` | **SHARD // PHANTOM** | 位移敌人 · 模块化悬浮人形 | idle / walk / attack / disperse / reform | 大型相机镜头头、90 个独立模块与橙红推进器（背部/小腿/脚底悬浮喷口）、爆散重组、掌心手里剑 |
| `boss/` | **LEVIATHAN // ABYSSAL WARDEN** | 最终 Boss · 机械章鱼 | 8 条独立链式触手 · idle / support / attack1-3 / laser / 两阶段 | 2 m 半径装甲球、8 片滑动虹膜壳 + 连续孔径环、红色大摄像头眼、红色能量核心与透明约束层、15 m 横扫 |

三个工程共享同一套「暗黑舞台 + 霓虹轮廓光 + ACES/Bloom/SSAO + 扫描线暗角」
的呈现体系，与 `../basic/actdemo`、`../basic/character` 同一画风家族。

## 刀客、单轮远程机甲与折相

以下三个目录各有独立的 Godot 4.7.2 工程与第一人称试玩关。用项目管理器导入各自的 `project.godot` 即可查看展台。各工程的说明包含实战入口和角色资源路径。

| 工程 | 内容 |
| --- | --- |
| [人形机甲刀客](mech_duelist/README.md) | 近战精英，含持刀踱步、开场蓄力二连斩、三套普攻和实战判定 |
| [单轮巡射机甲](wheel_sentry/README.md) | 远程机甲，含轮组展台、走位、小束和长束的单怪实战 |
| [折相 Boss](phase_boss/README.md) | 重型四足机甲，含模型与动作展台、视野充能与虚化、侧跳后撤反击和实战演示关 |

---

## 快速开始

需要 **Godot 4.7.2**。本机 `DISPLAY=:10` 是可用 X 服务，Vulkan/Forward+ 正常。

```bash
cd arc_sentinel   && ./run.sh      # 或 godot --path .
cd shard_phantom  && ./run.sh
cd boss           && ./run.sh
```

三个工程的默认主场景都是 `res://scenes/studio.tscn`。首次打开若出现
class_name 未注册，先执行一次：

```bash
godot --headless --path . --import
```

---

## 通用操作

| 输入 | 功能 |
| --- | --- |
| 鼠标左键/右键拖动 | 环绕相机 |
| 滚轮 | 推拉 |
| `F` | 重置机位 |
| `H` | 隐藏 / 显示 UI |
| `空格` | 播放 / 暂停 |
| `F12` | 保存截图到 `renders/` |
| 右侧面板 | `ANIM` / `PARAMS` / `JOINTS` / `INFO` 四个页签 |

`PARAMS` 与 `JOINTS` 里每一个数值都是真正的 `SpinBox`：可以直接键入数字，
也可以拖箭头步进；改几何参数会即时重建模型并保持当前姿势。`JOINTS` 页
可以只用单关节角度把角色摆成任意姿势，用来验证模型不是烘焙动画。

**ARC // SENTINEL v2**：`1`~`8` 播放 rest / idle / walk / attack / attack_up / defend / draw / sheathe。攻击/格挡/收放由解析机械臂 IK + 碰撞感知 swivel 求解，烘焙成轨迹表（运行时 1–12 ms）；格挡强制左前 45° 用盾、右前 45° 用剑，没有 guard 兜底。一次攻击/格挡/收放不会在中途被取消，新请求排队到结束。

**SHARD // PHANTOM**：`1`~`5` 播放动画，`B` 闪烁（默认 5m）、`N` 散布后
自动重组、`M` 立即重组、`G` 切换「被注视即爆散」。角色顶部还有
BLINK / DISPENSE / REFORM 按钮与状态读数。

---

## ARC // SENTINEL v2

### 设定

双轮平衡机兵：左右各一枚**实心金属轮**（无辐条），轮外整圈金属胎纹甲片；两轮各自通过
独立摆臂 + 弹簧减震与小型中央底盘相连，轴心始终贴地。机身是前后轴向的小圆柱压力壳：
正面是大摄像头镜头（角色唯一的“脸”），背面有外凸弧形检修罩 + 盾牌挂钩，左侧有刀鞘，
没有头。两只长臂各由**三个球状关节**（肩/肘/腕）串成；左腕末端是盾牌挂架，右腕末端是
很短的**电弧发生器头**（无刀柄），直接生成电弧刀。整体黑 + 橙红金属。

### 动作 / 求解器

- `rest`：刀在左鞘内（发生器入鞘、刃关闭），盾挂在背后，躯干向刀鞘侧扭转，手臂低位收拢。
- `idle` / `walk`：低位持刀盾；walk 是双轮滚动步态（一轮/周期、悬挂起伏、身体前倾）。
- `attack`：左上 → 右下过顶斜劈。起手刀刃与竖直轴 30.46°、后仰、离矢状面仅 5.74°，
  刀举到左肩上方；末位置在身体右侧，刀刃向下 46.09°。
- `attack_up`：左下 → 右上撩斩。起手刀刃水平向后 (0,0,−1)，整把刀都在机身左侧
  （min x 0.497 m）；末位置手臂水平向前偏右 4.80°（离水平 1.72°），刀刃向右上 44.93°。
- `defend`：**没有 guard 兜底**。左前 45° 威胁必须用盾（盾面正对威胁线，miss 0.000 m）；
  右前 45° 威胁必须用剑（刀身横切威胁线，miss 0.000 m）。
- `draw` / `sheathe`：rest↔idle 的收放过渡；刀只有在完全离开刀鞘后才点亮，入鞘前先熄灭。
- 一次动作不会在中途被取消：攻击/格挡/收放期间的新请求会排队，结束后再切；rest↔drawn
  只通过 draw/sheathe 连接。这样任何转场都不会把剑挥穿机身。

关节运动由解析双骨 IK + 自由 swivel 角求解，肘部同时分担前臂扭转，所有关节以四元数
存储/插值（不会出现欧拉角翻转）。攻击/收放/格挡的笛卡尔关键目标被采样、碰撞修复、平滑，
再按 13.5 rad/s 的关节速度上限做局部时间重参数化，最后烘焙成
`data/arc_traj_v2.json`（约 0.7 MB，远低于 50 MB 预算）。运行时报告：attack 1 ms、
attack_up 1 ms、block ≤12 ms；离线 bake 约 20 s，是构建步骤不是帧成本。
idle/walk/rest 实时求解。

### 验收

`godot --headless --path . res://scenes/qa.tscn` → **PASS（0 failures）**：

- 所有 clip 逐帧自碰撞：rest +0.0244 / idle +0.0285 / walk +0.0217 / attack +0.0271 /
  attack_up +0.0088 / defend +0.0130 / draw +0.0265 / sheathe +0.0308 m；地面 ≥0。
- 状态机可达转场最差 +0.0287 m。
- 两个强制格挡均命中；盾/剑分别使用；无 guard。
- 攻击/攻击_up 精确约束、求解时间、关节速度全部通过。
- 金属：程序化 PBR 金属 shader（拉丝、粗糙度破碎、稀疏划痕、点蚀、边缘磨损）+ SSR/反射探针；
  最终图在 `renders/v2/`，动作分解帧在 `renders/v2/sheets/`。

详细参数、动作表、已知限制和复现命令见 **`arc_sentinel/README.md`** 与
**`arc_sentinel/DESIGN.md`**。

## SHARD // PHANTOM

### 设定与机制

悬浮的模块化人形：约 1.60m 高、悬浮 0.20m，身体由 60–90 个独立机械模块
（默认 90）围绕一圈圈拼成，每个模块都有橙红色微型推进器；内部有近黑骨架
维持形体。头部是单个大型凹陷相机镜头（深筒、光圈环、暗腔、遮光罩，
橙红虹膜，随头部关节转向），没有人脸/嘴/V 缝。双手是掌心发射器。
悬浮主推力来自背部 2 个大喷口、后小腿 2 个、脚底 2 个（胯下无喷口），
配向下的舞台光洗与地面光池。模块是独立部件，头部/身体的模块化分离感
是设定的一部分。

被注视时（或按 `B`/`N`）爆散：模块按错峰、各自独立的二次贝塞尔弧线飞向
新位置，中途云团半径约 1.4–2.8m（默认 1.84m），明显散开而不是整体平移；
随后收敛重组，5.6mm 级误差归位。默认瞬移 5m（参数范围 0–12m）。

`idle`：双手背在身后、微微起伏；`walk`：低速滑行 + 缓慢迈腿，脚始终离地；
`attack`：从背后抬手 → 手臂平举指向玩家 → 掌心充能 → 发射旋转能量手里剑 →
后坐 → 收手回背后。手里剑在 clip 结束后仍按 1.05s 生命继续飞行并自清。

### 绑定 / 参数

45 个关节、42 个参数；模块按关节分配，装配态姿势完全由关节驱动；JOINTS 页
可单独摆姿势。`module_size` / `module_gap` / `thruster_intensity` / 爆散
半径/错峰/飞行时间/重组时间/过冲/瞬移距离/手里剑速度自旋尺寸等全部接线。

### 实测

| 项 | 数值 |
| --- | --- |
| 身高 / 悬浮（脚底-台面） | 1.60 m / idle 0.207m、walk 0.209m、attack 0.209m |
| 模块 | 默认 90（参数 60–90），每模块独立推进器；`module_size` 名义 0.10m、默认实测平均最大边 0.109m |
| 爆散 | 位移 6.03m 测试、云团半径 0.84→2.66m（中段 1.84m）、98.1% 模块对间距改变 |
| 重组误差 | 5.6 mm |
| 性能 | 117.5–117.9 fps 无 vsync（SSR 开启）/ 60 fps vsync，351 draw calls，42.9k prims |

---

## LEVIATHAN // ABYSSAL WARDEN

机械章鱼最终 Boss：2 m 半径装甲球（直径 4 m）+ 8 条独立链式触手。每条触手由
**0.30 m 连杆 + 0.31 m 球形关节**交替组成（0.60 m 一个周期），细、等粗、无吸盘；
球形关节是可见的旋转节点。触手角色由调度器每 2 s 随机重排两条：同时至多 2 条
attack、至多 5 条 support、其余 idle。0 条 support 时球体落地，3 条以上撑起；
support 脚点固定，身体做 1.2 m 圆周漂移时长度变化 0.52%、脚点滑移 0.000 m。

- 眼睛：球壳内的红色大摄像头镜头，万向节自由跟踪；一阶段只从 36.3° 孔径露出，
  二阶段 8 片虹膜滑入后壳、孔径 100°、红色能量球点亮、外壁透明、可发射激光。
- 攻击：attack1 沿“当前端点→目标”的冻结直线直刺；attack2 先到目标上方 5.4 m
  再垂直下刺；attack3 以 15 m 触手做 140°、9–10.8 m 的横扫，并以下刺收尾命中目标。
- 验收：`cd boss && godot --headless --path . res://scenes/qa.tscn` →
  **46/46 PASS**，0 failures；idle 互穿间隙最小 +0.482 m，support +0.509 m，
  attack 命中 0.0023 m / <0.001 m / 0.000 m，激光端点命中，模拟 3.56 ms/60 Hz step。
- 视觉验收：连续帧（0.13–0.25 s/帧）与接触表在 `boss/renders/shots/`、
  `boss/renders/sheets/`，供直接审阅；最终视觉判定由用户自审。

```bash
cd boss
godot --headless --path . --import
godot --headless --path . res://scenes/qa.tscn
DISPLAY=:10 godot --path . res://scenes/shots.tscn
python3 compose_sheets.py
```

## 验收结论

**独立只读审计**（复制到 `/tmp` 重跑，不采信实现者自述）覆盖：
契约 API、动画名称/时长、确定性 scrub、循环接缝、全部关节有效性、参数
极值重建、无外部资源、性能、UI 功能与截图。审计发现的问题已按优先级修复，
并做了二次复测：

- Sentinel v2：双轮平衡机全新建模/绑定/动画；全部 clip 逐帧自碰撞为正（最低 +0.0088 m），
  地面 ≥0；状态机可达转场最差 +0.0287 m；攻击/攻击_up 精确约束（30.46°/5.74°、
  46.09° 右下；水平向后全左侧、末位置 0.57° 水平 / 3.00° 右 / 44.93° 右上）全部通过；
  两个强制格挡 miss 0.000 m；解析 IK + 四元数 + 烘焙轨迹表，运行时 attack 1 ms /
  attack_up 1 ms / block ≤12 ms。旧的 41 关节双足、guard 兜底、剑挡正面等失败项已被替换。
- Shard：`module_size`/`module_gap`/`thruster_intensity` 死参数 → 实测生效；
  掌心永久橙色方块 → 球形充能、非攻击隐藏；笑脸面罩 → 单个大型相机镜头；
  肩/手穿插 → 手间距 0.08m；50 模块覆盖不足 → 下限 60 并自动放大模块；
  loop 接缝 8mm → 0.000m；手里剑 clip 后冻结 → 继续飞行并自清。

**LEVIATHAN** 的验收数字、连续帧与已知限制见 `boss/README.md`、
`boss/DESIGN.md`、`boss/renders/qa_report.json`，连续帧在
`boss/renders/shots/`、接触表在 `boss/renders/sheets/`。

**定位**：按独立游戏/中型项目可用的风格化角色标准交付；工程结构、确定性、
参数化、性能与动作可读性达标。视觉上是硬表面 + 程序化微表面（划痕/色差/
边缘磨损/SSR）的风格化建模，仍不是 3A 影视级资产——与商业 3A 的主要差距
在：整体造型的细节密度、拓扑级倒角/磨损、以及手 K 级别的动画打磨。所有
已知限制都写在各工程 README（`arc_sentinel/README.md`、`shard_phantom/README.md`）中，不隐藏。

---

## 已知限制（诚实清单）

**ARC // SENTINEL v2**
- 摄像头 pod 在攻击时缩回机身（正面装甲虹膜关闭）是刻意设计；如果保持伸出，过顶/横跨
  刀路会穿过它。
- 攻击 clip 有意做得有重量感（2.1–2.2 s，含预备/跟随/回位），不是游戏化的极速快挥。
- 烘焙表绑定默认几何签名；改 hull/wheel/shield/blade 尺寸会回退到运行时求解，首次重建
  需要数秒而不是毫秒。
- 格挡演示图里的敌方刀是 HDR 自发光示意道具；真正的格挡证明是 QA 的射线/圆盘/线段测试。
- 盾是加色硬光场（unshaded），不是金属板；盾缘和骨架是金属。这是既定盾牌样式。
- 金属细节是程序化风格化硬表面，不是扫描级 3A 贴图。
- 进程退出时 Godot 报少量生成纹理 RID 泄漏；运行中无影响。

**SHARD // PHANTOM**
- 肩/上臂模块簇在 3/4 视角仍偏拥挤；这是下一次美术迭代的首要项。
- 模块数下限为 60（原需求 50–90），低于 75 时自动放大模块以维持覆盖；50 个时仍会明显变稀。
- 正面攻击图因朝相机投掷而透视缩短，侧视 `attack_side.png` 才是手里剑的判读图。
- 爆散/重组的时间轴拖动需要触发时的快照；重建几何会把飞行中的蜂群重置为装配态。
- 舞台刻意接近全黑，角色的可读性依赖高光边与自发光；这是风格选择，不是曝光错误。
- SSR + 金属 shader 使无 vsync 帧率从 ~119 降到 ~83–85；60fps 输出仍有余量。

---

## 目录

```text
boss/
  scenes/studio.tscn          交互演示主场景（8 条触手、角色调度、两阶段、激光）
  scenes/qa.tscn              全量验收（46 项）
  scenes/shots.tscn           确定性连续帧序列
  scripts/boss/               骨架、虹膜壳、万向节眼、能量核心、链式触手求解器
  scripts/qa.gd               头less 验收
  scripts/shots.gd            渲染序列
  shaders/                    金属、镜头、壳玻璃、等离子球/核心、激光、地面
  renders/qa_report.json      46/46 PASS
  renders/sheets/             接触表
  renders/shots/              227 张全分辨率连续帧
  renders/shots/MANIFEST.txt  最终渲染集时间戳/帧数清单
  README.md / DESIGN.md

arc_sentinel/
  scenes/studio.tscn          交互演示主场景
  scenes/character.tscn       角色（契约接口）
  scenes/qa.tscn              全量验收 QA（碰撞/转场/精确姿态/格挡/求解时间）
  scenes/v2_shots.tscn        动作分解帧（960×540，16 帧 ×4 视角 ×9 clip）
  scenes/v2_details.tscn      全身图 + 金属/镜头/轮/盾/刀特写
  scenes/block_demo.tscn      左/右 45° 格挡图
  scripts/ch/                 骨架/几何、解析 IK、动画、材质、电弧刀
  scripts/bake_traj.gd        轨迹表离线烘焙
  scripts/kit/                共享网格/材质/面板/演播室
  shaders/                    金属、镜头、盾、电弧、地面、调色
  data/arc_traj_v2.json       烘焙轨迹表（约 0.7 MB）
  renders/v2/                 最终图、分解帧、格挡图、QA 报告
  README.md / DESIGN.md

shard_phantom/
  scenes/studio.tscn          交互演示主场景（含 BLINK/GAZE 控件）
  scenes/character.tscn       角色（契约接口 + 爆散状态机）
  scenes/perf.tscn            性能探针
  scripts/phantom/            模块场、绑定、手里剑、材质
  renders/                    最终图、blink 条带、特写、ACCEPTANCE.md
  README.md
```

### 生成与验收命令

```bash
# Sentinel v2
cd arc_sentinel
godot --headless --path . res://scenes/qa.tscn
godot --headless --path . --script res://scripts/bake_traj.gd
DISPLAY=:10 godot --path . res://scenes/v2_shots.tscn
DISPLAY=:10 godot --path . res://scenes/v2_details.tscn
DISPLAY=:10 godot --path . res://scenes/block_demo.tscn

# Shard
cd shard_phantom
DISPLAY=:10 godot --path . res://scenes/perf.tscn
godot --headless --path . --script res://scripts/contract_test.gd
godot --headless --path . --script res://scripts/loop_soak_test.gd
DISPLAY=:10 godot --path . res://scenes/shots.tscn
```

---

## 实现与调度记录

- `arc_sentinel` v2 为**全量重做**：新骨架、几何、材质、解析 IK、四元数轨迹、
  碰撞审计、烘焙表、QA、动作分解帧和视觉验收全部在 `arc_sentinel/` 内，
  详细记录见 `arc_sentinel/IMPLEMENTATION.md`、`README.md`、`DESIGN.md`。
- 两个独立资产 subagent（`dawnfm/deepseek-v4.1-flash-1017`，variant `max`）：
  一个产出程序化金属 shader，一个移植 `weapon_electricity_sword` 的电弧场/
  电弧 ribbon 并验证刀刃长度；主会话负责集成、调参和验收。
- 视觉能力 subagent 先做能力自测，再对最终动作分解帧做独立视觉验收；
  `renders/v2/VISION_REVIEW.md` 记录其逐 clip 结论。
- 旧版 `arc_sentinel` 的双足 41 关节、guard 兜底、剑挡正面、脚底穿地等失败项
  已不再存在于交付代码/场景中；旧渲染已清理，最终图只在 `arc_sentinel/renders/v2/`。