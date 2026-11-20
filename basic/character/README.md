# T4 // VESPER

程序化四足高速 ACT 主角 —— Godot 4.7 项目。

四足呈 4 次中心对称的 T4 噬菌体式机械腿，上身为人形战斗底盘，双手共握 **一把** 激光大剑（不是双持）。模型、材质、动作、刀光、HUD 全部由代码生成，不依赖任何外部模型、贴图或动画资源。

> 渲染图与展示片未入库：`renders/` 由源码渲染生成，命令见下文「渲染」一节（`scenes/render_stills.tscn` 定格 / `scenes/render_movie.tscn` 序列 + ffmpeg 合成 22 s 展示片）。

## 快速开始

```bash
./run.sh            # 在本目录执行（任意位置用绝对/相对路径调用均可）
```

启动后会自动播放展示循环；按下任意移动/攻击键即可接管操作。

| 输入 | 功能 |
| --- | --- |
| `W A S D` | 移动（相对镜头） |
| `Shift` | 冲刺 |
| `J` | 双手剑连段：Rift Cleave → Ascending Fang → Guillotine |
| `K` | 直接发动 Guillotine 重斩 |
| `L` | Helix Storm：腰部 360° 回旋斩 |
| `Space` | 跳跃（起跳 → 空中 → 落地三态） |
| `Q` | 矢量冲刺（Dash） |
| `← / →` | 调整镜头环绕 |
| `Tab` | 切换自动演示 / 手动 |
| `H` | 隐藏 / 显示 HUD |

> 手动模式的镜头是“固定世界朝向的环绕镜头”：`W` 始终沿镜头正前方直行，不会因为角色转向而反复偏转。停止移动后镜头会缓慢回到角色背后。

> 渲染器使用 `gl_compatibility`，在只有集显/无 Vulkan 的机器上也能跑。项目按 1600×900 设计，窗口默认 1280×720。

## 概念与造型

T4 噬菌体的解剖结构被映射到人形机甲上：

| T4 结构 | 机甲部件 |
| --- | --- |
| 六边形衣壳（capsid） | 背部巨大的六边形背包，中央为橙色传感器眼，外圈六枚铆钉 |
| 颈环（collar）与尾丝 | 背包外圈的六根晶须尖刺、四足髋部的基板光纤 |
| 尾鞘（tail sheath） | 骨盆到胸腔之间的分段式机械脊柱，段间有橙色发光缝 |
| 基板（baseplate） | 八边形骨盆基座，四足以 45° / 135° / 225° / 315° 方位放射状安装 |
| 尾丝（tail fibres） | 四条两段式机械腿：高膝、折叠腔节、三爪足 |

关键点：

- **休息时四足严格 4 次中心对称**：髋部方位间隔 90°，每条腿的几何完全一致。行走/奔跑时相位偏移打破对称，形成波步或对角小跑。
- **四条腿不是马/半人马式前后腿**：从俯视看，四条腿围绕身体中心呈 X 形展开，像噬菌体的尾丝。
- **双手剑**：单把约 3.2 m（世界尺度）的激光大剑，左右手同时握在刀柄上；两臂的 IK 每帧解算到刀柄的两个握点，不存在第二把剑。待机时剑持在身体右前侧（侧向高架），而不是横在胸口/头顶，避免剑柄与胸腔、肩甲相交。
- **长臂与大幅动作**：上臂/前臂合计约 2.7 m。攻击时武器根节点在躯干空间内大幅平移（例如 Rift Cleave 的双手从 `x=+0.55` 扫到 `x=-0.58`，Guillotine 从 `y=1.06` 砸到 `y=0.16`），不是只靠手腕做小范围旋转。

## 渲染与画面

全部资产在运行时构建：

- 网格：`MeshKit` 自己发射带平面法线的三角形（六/八棱柱、八棱梁、倒角板、双刃刀身、低多边形宝石）；没有使用任何导入的 `.glb`、`.obj` 或贴图。
- 材质：PBR 标准材质 + 手写 shader（刀刃核心、刀刃辉光、刀光带、场地网格、冲击环、HUD 扫描线）。
- 场景：六边形决斗台、蓝色网格 + 橙色环形标记、远景黑塔、雾、GPU/CPU 粒子余烬。
- 后期：ACES tonemap、环境 glow、屏幕暗角/扫描线（Compatibility 渲染器可用的近似）。

![back](renders/still_back.png)

## 动画的数学原理

项目里没有 `AnimationPlayer` 的关键帧。每个姿态都是时间、速度和相位的函数。

### 1. 四足步态

步态相位为

$$
\phi_i=(\phi+\delta_i)\bmod 1
$$

`walk` 使用波步偏移 $\delta=[0,0.25,0.5,0.75]$，`run` 使用对角小跑 $\delta=[0,0.5,0,0.5]$，按速度平滑混合。占空比

$$
D=\operatorname{lerp}(0.68,0.44,s)
$$

其中 $s$ 是速度归一化值。步幅由世界锁定条件给出：

$$
\text{stride}=\frac{vD}{f}
$$

支撑相内，足端在角色局部空间向后匀速移动，正好抵消根节点前进，避免滑步；摆动相用 $\sin(\pi t)$ 抬起足端并带一点前伸过冲。足端的水平目标再经过“朝向目标的髋部 yaw + 竖直平面内两段 IK”转换为关节角。

### 2. 腿部两段 IK

设髋到足端在竖直平面内的水平距离为 $d$、高差为 $h$、大腿/小腿长度为 $L_1,L_2$，则

$$
L=\sqrt{d^2+h^2}
$$

$$
\alpha=\arccos\!\left(\frac{L_1^2+L^2-L_2^2}{2L_1L}\right),\qquad
\beta=\arccos\!\left(\frac{L_1^2+L_2^2-L^2}{2L_1L_2}\right)
$$

大腿角为基线角加 $\alpha$，膝关节角为 $-(\pi-\beta)$，踝关节再反向补偿使爪垫尽量水平。膝部始终向“上/外”折，呈昆虫/噬菌体尾丝的折角轮廓。

### 3. 身体动力学

- 前倾：`lean ∝ speed`
- 转向侧倾：`bank ∝ yaw_rate × speed`，身体向转弯内侧压
- 足落冲击：按处于支撑相的腿数给身体一个下沉分量；支撑腿越少，下沉越多
- 待机呼吸、腰部反应堆环旋转、头部看向速度方向

### 4. 双手剑与手臂 IK

剑的位姿在**躯干空间**中由战斗姿态给出（位置 + Euler 旋转）。刀柄上的两个握点随之移动，左右臂各自解一个带极向量的两段 IK：

1. 由肩到握点求肘位置（余弦定理 + 极向量把肘推向身体外侧/后方）；
2. 用肩部基向量让上臂指向肘；
3. 用肘部弯曲角让前臂指向握点；
4. 腕部基向量对齐刀柄轴线，让拳头真正“包住”刀柄。

每次渲染都会打印握持误差；QA 场景中全程为 **0.0000 m**，双手在任何攻击姿态下都不会脱离剑柄。

![heavy](renders/still_heavy_raise.png)

### 5. 跳跃 / 空中 / 落地

跳跃不是一段固定长度的动画，而是三个独立状态：

- **TAKEOFF**（0.14 s）：身体下蹲蓄力、腿部压缩；结束时给根节点一个向上初速度。
- **AIR**：根节点做抛物线运动，状态持续到脚底重新接触地面为止，因此腾空时长可以是任意值。腿部目标根据竖直速度在“收腿”与“伸腿准备落地”之间连续插值；身体前倾/后仰也由竖直速度驱动。
- **LANDING**（0.56 s）：脚触地瞬间切换，根节点归零，身体深蹲吸收冲击，四足张开，刀刃下压；同时生成地面尘环/烟尘与镜头震动，然后平滑回到待机或奔跑。

竖直运动为

$$
y(t)=y_0+v_0t-\tfrac{1}{2}gt^2
$$

其中 $v_0=8.2\,\mathrm{m/s}$、$g=22\,\mathrm{m/s^2}$。`AIR` 的结束条件只有 $y\le 0$，所以从高处落下、被击飞或改变重力时，落地动作会在真正触地的那一帧触发。

### 6. 战斗姿态曲线

攻击是一串“武器位姿关键点”，用 smootherstep 插值：

$$
u'=6u^5-15u^4+10u^3
$$

每个关键点只覆盖需要改变的通道（腰部 yaw/pitch/roll、武器位置、武器 Euler、下蹲量等），首尾自动回到持剑待机。连段在攻击时间达到 `0.72 × duration` 时接续下一段。

重斩 Guillotine：举剑过顶 → 弓背 → 下蹲砸地，配合冲击波与镜头震动。
回旋 Helix Storm：腰部 `ty` 从 `0` 连续变化到 `2π`，整把剑绕身体扫一圈；腰部环和刀光带同时旋出。

### 7. 刀光带

每一帧记录刀刃后段（约 82% 处）→刀尖两个世界坐标；只保留最近约 0.12 s、且位移超过阈值的样本。相邻样本构建双面三角形带，透明度按年龄的 1.6 次幂衰减，基座一侧额外淡出，避免变成一整块“扇形烟幕”。材质为 additive、无光照、无深度写入。

## 工程结构

```
project.godot
scenes/main.tscn                  # 可交互展示
scenes/render_stills.tscn         # 1600×900 定格渲染
scenes/render_movie.tscn          # 1280×720 / 30fps 序列渲染
scripts/main.gd                   # 输入、总装、手动/自动切换
scripts/mech/mesh_kit.gd          # 程序化网格工厂
scripts/mech/materials.gd         # 全局材质/缓存
scripts/mech/mech_rig.gd          # 角色构建 + 步态/IK/战斗/刀光
scripts/mech/blade_trail.gd       # 扫掠刀光带
scripts/world/arena.gd            # 竞技场、灯光、粒子、环境
scripts/world/camera_rig.gd       # 跟随/电影镜头、FOV、震动
scripts/world/hud.gd              # 纯代码 HUD
scripts/world/showcase.gd         # 22 秒自动演示导演
scripts/world/fx.gd               # 冲击环、火花、闪光
shaders/                          # 刀刃、刀光、地台、HUD 后期
renders/                          # 定格图与视频
```

## 渲染 / 出片

固定步长定格（1600×900）：

```bash
DISPLAY=:10 XAUTHORITY=$HOME/.Xauthority \
  godot --path . res://scenes/render_stills.tscn
```

固定 30 fps 视频序列（1280×720，22 秒）：

```bash
DISPLAY=:10 XAUTHORITY=$HOME/.Xauthority \
  godot --path . res://scenes/render_movie.tscn

ffmpeg -framerate 60 -i renders/movie/frame_%04d.jpg \
  -c:v libx264 -pix_fmt yuv420p -crf 18 -movflags +faststart \
  renders/vesper_showreel.mp4
```

`render_movie.gd` 支持环境变量，方便只渲染片段：

```bash
MOVIE_START=8.5 MOVIE_SECONDS=2.4 MOVIE_OUT=renders/test \
  godot --path . res://scenes/render_movie.tscn
```

Rig / HUD / FX 都由同一个固定 `dt` 驱动（`rig.advance()` 内推进 FX），因此出片与实时预览的动作一致。

## 展示片

[`renders/vesper_showreel.mp4`](renders/vesper_showreel.mp4)（22 s，60 fps，1280×720）：

- 00.0–02.9 待机 / 校准
- 02.9–05.7 行走，刀收到肩上
- 05.7–08.6 冲刺，低机位跟随
- 08.6–11.5 Rift Cleave + Ascending Fang 连段
- 11.5–13.5 Guillotine 重斩（高位举剑 → 低位砸地）
- 13.5–16.2 Helix Storm 腰部 360° 回旋斩
- 16.2–18.8 Vector Dash → 起跳 → 空中收腿 → 落地深蹲（三个独立状态）
- 18.8–22.0 收剑待机，镜头绕向背部展示 T4 衣壳

## 图集

- 接触表：`renders/contact_sheet.png`
- Hero：`renders/still_hero.png`
- T4 背面（衣壳、颈环、脊柱）：`renders/still_back.png`
- 四足中心对称俯视：`renders/still_top.png`
- 冲刺：`renders/still_sprint.png`
- 连段 / 重斩 / 回旋 / 冲刺：`renders/still_rift.png`、`renders/still_heavy_raise.png`、`renders/still_spin_late.png`、`renders/still_dash.png`
- 起跳 / 空中 / 落地：`renders/still_takeoff.png`、`renders/still_jump.png`、`renders/still_land.png`

## 验收

已实际运行并检查：

- 主场景 300 帧无脚本错误；
- 双手握持误差：所有测试姿态 `0.0000`；
- 定格图 1600×900，视频序列 1280×720；
- 四足静止姿态按 45° 等分，外观中心对称；
- 行走/奔跑时足端目标、摆动相位、身体起伏均由代码实时计算。

QA 场景：`scenes/test_poses.tscn`、`scenes/test_anim.tscn`、`scenes/test_cine.tscn`。

## 迭代记录（针对验收反馈）

1. **上身与手臂比例**：躯干缩放提升到 1.45，上臂/前臂加长到 0.98/0.88，拳头加大；剑的待机位置改为右前侧竖向高架，双手和手肘完全露在躯干轮廓之外。
2. **J/K 特效时机**：命中特效不再固定在身前地面，而是在 `hit_at` 时刻读取刀刃标记的**世界位置**：Rift Cleave 在刀锋扫过的瞬间于刀尖爆出空中火花/烟尘；Guillotine 在刀尖触地的那一帧于地面爆出冲击尘环。镜头震动、HUD 闪白与命中特效共用同一个时刻。
3. **WASD 直行**：手动镜头改为固定世界 Yaw 的环绕镜头，移动方向不再随角色朝向反馈；`W` 沿镜头正前方直行。停止移动后镜头缓慢回正到角色背后。
4. **跳跃三态**：新增 `TAKEOFF / AIR / LANDING` 状态机、空中收腿与落地深蹲、接触阴影、落地尘环和镜头震动；空中不依赖固定时长，触地即进入落地动作。`Space` 跳跃，冲刺改为 `Q`。

5. **剑柄/肩甲穿模**：新增武器前向净空约束（躯干空间 `wpz ≤ -0.88`），待机/攻击的武器根节点全部移到胸前 0.9 m 以外；待机剑改为侧向高架，刀刃不再经过头部/肩甲。新增 `scenes/test_clip.tscn` 从正面和侧面渲染各关键姿态做穿模检查。镜头也改到角色左前方，避免剑脊挡在镜头与头部之间。

6. **Helix Storm 的“一顿一顿”**：躯干 360° 旋转原来被拆成多个关键帧，每段都用 smootherstep，角速度会在每个关键帧降到 0，因此看起来像停顿。现在躯干 yaw 改用独立的梯形角速度曲线 `_spin_progress()`（两端各 24% 平滑加速/减速，中段恒定角速度），一次连续转满一圈；其余姿态仍然正常缓动。展示片同时改为 60 fps 重新渲染。

## 已知边界

- 这是展示型 ACT 角色 Demo，不是完整游戏：没有碰撞、伤害、锁定或敌人 AI。
- 臂部 IK 没有关节限位；通过武器姿态的合理范围保证可达。真实项目可加 Shoulder 限位与肘极向量约束。
- 腿部对平面场地做了世界锁定；复杂地形需要加足端射线检测和坡度适配。
- 没有音频与贴图。刀刃、地面、HUD 的“发光感”依赖 shader + Bloom 近似。
- HUD 使用 Godot 内置 fallback 字体，避免引入外部字体资源。