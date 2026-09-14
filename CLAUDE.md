# CLAUDE.md — Eggs 项目开发规范

本文件是本项目 AI 辅助开发与人工开发的统一规范。任何代码改动前先读本文件和设计文档。

## 项目概述

- **游戏定位**：一款治愈系 2D 手绘风移动端横屏养成游戏。玩家在浮空小岛上照护一颗蛋，孵化出第一只宠物 Shell Pudding，并通过场景化互动持续培养亲密度。
- **当前阶段**：规划 / 游戏策划 / 美术资产准备阶段。主岛原型（`scenes/main_island.tscn`）已有可运行的占位实现。
- **设计文档**：`docs/superpowers/specs/2026_09_07_egg_pet_mvp_design.md`（Egg Pet MVP Design）。**所有功能实现以该文档为准**，本规范仅补充工程约定。
- **核心循环**：照护循环是主游戏；小游戏是可选娱乐，不产出任何资源、进度或核心状态变化。

## 技术栈

- **引擎**：Godot 4.7，Mobile 渲染管线（`rendering_method="mobile"`），2D 项目。
- **语言**：GDScript（不使用 C#）。
- **目标平台**：移动端横屏。PC 仅用于开发调试，鼠标/键盘是触摸的临时替代输入，实现交互时必须同时考虑触摸路径。
- **主场景**：`scenes/start_screen.tscn`（启动页，已设为 main scene）；游戏主场景为 `scenes/main_island.tscn`。

## 目录结构约定

```
assets/          # 美术资产（background/、eggs_pics/ 等）
scenes/          # 所有 .tscn 场景文件
scripts/         # 所有 .gd 脚本
docs/            # 设计文档与规划
addons/          # 第三方插件（见"插件使用约定"）
```

设计文档规划的后续场景（新建时放入 `scenes/`）：

- `egg_view.tscn` — 蛋阶段展示与动作播放
- `pet_view.tscn` — Shell Pudding 展示与动作播放
- `interactable_item.tscn` — 可复用的可交互物体基类
- `food_bowl.tscn` / `warm_lamp.tscn` / `clean_tool.tscn` / `toy.tscn` — 四类照护交互物
- `minigame_hub.tscn` — 小游戏选择入口
- `bubble_survivor.tscn` — 第一个小游戏

规划的核心脚本（新建时放入 `scripts/`）：`care_state.gd`、`growth_state.gd`（已存在）、`save_data.gd`、`save_service.gd`（已存在）、`creature_animator.gd`、`interactable_item.gd`、`minigame_hub.gd`、`bubble_survivor_controller.gd`。

## GDScript 编码规范

### 命名

- 变量 / 函数：`snake_case`
- 类名 / `class_name`：`PascalCase`（如 `CareState`、`SaveService`）
- 常量：`SCREAMING_SNAKE_CASE`（如 `const PATH := "user://egg_pet_save.json"`）
- 信号：`snake_case` 动词过去式或事件式命名（如 `hatched`、`food_placed`）

### 类型与风格

- **静态类型必填**：所有变量、参数、返回值都写类型标注（`var x: float`、`func tick(delta: float) -> void`）。
- 能推断时用 `:=`（如 `var care := CareState.new()`）。
- 每行一个语句；用 `match` 处理动作分派（参考 `CareState.apply_action()`）。
- 不滥用注释；代码本身应自解释。仅在不明显的数值依据或设计意图处注释。

### 类的组织

- **纯数据 / 纯逻辑类**继承 `RefCounted` 并声明 `class_name`，不挂场景树（参考 `care_state.gd`、`save_service.gd`）。
- 数值的 clamp / 范围校验统一收敛在状态类内部（如 `CareState.clamp_values()`），调用方不自行裁剪。
- 序列化统一走 `to_dict()` / `from_dict()` 模式；`from_dict()` 必须对缺失字段使用 `data.get(key, 当前值)` 兜底，保证旧存档兼容。
- 存档一律 JSON 写入 `user://`（参考 `SaveService`），保存前写入 `last_saved` 时间戳。
- 跨场景 / 跨模块通信用**信号**，不直接引用对方节点；场景树内部节点引用用 `@onready`。
- 静态工具函数用 `static func`（参考 `SaveService.load_data()`）。

## 游戏设计红线（不可违背）

以下约束来自设计文档，实现任何功能时不得违反：

1. **四项照护状态**（Temperature / Hunger / Cleanliness / Mood）取值 `0–100`，舒适区间约 `60–100`；低于 `40` 需有可见的需求表达，低于 `20` 表现为轻度负面行为（躲藏、迟缓、变脏、响应变弱）。
2. **无死亡、无遗弃、无永久失败、无严厉惩罚**。所有负面状态都是轻度且可恢复的，目的是邀请照护而非惩罚玩家。
3. **场景化交互**：主岛不设置常驻的右侧/底部照护工具栏；照护通过场景物体完成，临时 UI（如选食物、选小游戏）只在交互后出现，默认画面保持干净。
4. **离线进度必须有安全下限**（参考 `SaveService.apply_offline()` 的下限值），且离线时长封顶（当前为 3 天），不得造成严厉惩罚。
5. **小游戏隔离**：Bubble Survivor 不产出金币、材料、亲密度、心情、记忆、孵化进度或任何照护奖励，只返回胜/负结果并播放对应动画。主照护系统不得知晓小游戏内部规则。
6. **动画按动作名调用**：游戏逻辑通过动作名（action name）触发 creature 动作，后续帧动画资产可替换/增强程序化动画而不改动照护逻辑。
7. **孵化呈现**：孵化进度到 100 进入 hatch-ready 状态；孵化须由玩家触发或明确呈现，不得突兀自动切换。
8. **不引入设计文档未列出的系统**：MVP 无商店、无货币、无材料、无道具经济、无复杂 roguelike build。

## 插件使用约定

项目已启用 16 个插件。使用时**优先调用插件能力，不要重复造轮子**：

| 插件 | 用途定位 |
|---|---|
| scene_manager（`SceneManager` / `Scenes` autoload） | 场景切换统一入口（主岛 ↔ 小游戏等） |
| sound_manager（`SoundManager` autoload） | 音乐 / 音效播放统一入口 |
| input_helper（`InputHelper` autoload） | 输入设备检测与键位提示，统一输入处理 |
| godot_state_charts | 状态机（照护状态、宠物行为状态等需要状态机时使用） |
| phantom_camera（`PhantomCameraManager` autoload） | 相机控制与镜头切换 |
| dialogue_manager（`DialogueManager` autoload） | 对话 / 文本呈现 |
| GDMP（`MediaPipeExternalFiles` / `GDMPAndroid` autoload） | 端侧 MediaPipe 人脸关键点，换脸"本机合成"模式用；仅 macOS arm64 / Android arm64 / iOS 原生库，Windows 编辑器中 `FaceAnalyzer.is_available()` 为 false |
| NativeCameraPlugin | 原生相机采集（自拍流程） |
| face_track_editor | 脸部轮廓逐帧标注（编辑器工具，导出排除） |
| nklbdev.importality、AS2P | Aseprite / 精灵表动画导入 |
| gdfxr | 程序化音效生成（sfxr 风格） |
| csv-data-importer | CSV 数据表导入（如多蛋种/多物种数据准备） |
| script-ide、Todo_Manager、godot_ai | 编辑器增强工具，**不参与运行时逻辑**，运行时代码不得依赖它们 |

- 新增插件前先确认与现有插件功能是否重叠，并说明理由。
- `_mcp_game_helper` 为 godot_ai 的运行时辅助 autoload，业务代码不直接调用。

## 资产规范

- 视觉风格：2D 手绘可爱风（hand-drawn cute）。占位图允许先行，但最终资产须统一风格。
- 命名：小写蛇形 + 序号/语义后缀（如 `egg1.png`）；同一系列资产放同一目录。
- 主画面构图优先级：蛋 / Shell Pudding / 可交互物体 > 界面控件；UI 不喧宾夺主。
- 导入设置：遵循 Mobile 管线，注意纹理压缩与滤镜模式与手绘风格匹配（非像素风不使用 nearest 滤镜）。

## 开发阶段（对应设计文档 Phases）

1. **Phase 1 — 主岛原型**：移动端横屏浮空岛，蛋巢、食盆、暖灯、清洁物、玩具、小游戏入口齐备，占位美术但交互可用。（当前进度）
2. **Phase 2 — 照护与孵化循环**：care_state、growth_state、save_data、存读档、离线进度、hatch-ready、孵化转场。
3. **Phase 3 — Shell Pudding**：宠物阶段、三级亲密度（Stranger / Comfortable / Close）、动作解锁、`creature_animator.gd` 动作名体系，MVP 用程序化动画。
4. **Phase 4 — Bubble Survivor**：Minigame Hub、移动控制、自动泡泡弹、简单敌人、胜负条件、返回岛屿播结果动画。

## 存档数据规范

主存档必须包含以下字段（见设计文档 Save Data 一节）：

- `stage`：`"egg"` 或 `"pet"`
- `egg_type`：`"common_egg"`
- `pet_species`：孵化后为 `"shell_pudding"`
- `care`：四项核心状态值
- `hatch_progress` / `hatch_ready`
- `intimacy_points` / 亲密度等级
- `unlocked_actions`：已解锁动作名
- 场景物体状态（如 `food_ready`、`lamp_on`）
- `last_saved`：保存时间戳

记忆（memory）记录可做结构预留，但小游戏在 MVP 不写记忆。

## 验证要求

完成功能后对照设计文档 Verification 清单自查：

- 核心状态值始终在 `0–100` 边界内。
- 离线进度安全应用，不产生严厉惩罚。
- 蛋可达 hatch-ready 并正常孵化为 Shell Pudding。
- 存读档完整保留 stage、状态、孵化进度、亲密度与物体状态。
- 主岛在移动端横屏布局下保持干净、可交互。
- 小游戏入口在主岛可见或可明确发现。
- Bubble Survivor 仅返回胜/负，不改动照护进度或资源；返回后结果动画正确播放。

## AI 协作约定

- 改动前先读设计文档与本规范；实现范围以设计文档为准，不擅自扩系统。
- 优先复用现有 autoload 与插件能力，不重复实现场景切换、音效、输入等功能。
- 新增脚本 / 场景遵循上述目录与命名约定。
- 涉及存档结构变更时，保持 `from_dict()` 对旧存档的向后兼容。
