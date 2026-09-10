# 换脸通用提示词设计（gpt-image-2 拼接参考图编辑）

> 版本 v2.0 · 2026-09-09 · 适用 `scripts/face_api.gd` 的单图 `/images/edits` 管线
> 目标：**一份提示词适配所有游戏角色**，新增角色只需提供一张规范参考图，提示词零改动。
>
> v2.0 变更：实测当前网关（routerapi）的上游**不支持多图表单**（`image[]` 双图稳定 400），
> 且对较大输入图不稳定。改为把「角色参考图 + 真人照片」在客户端**左右拼成一张
> 512×384 参考图**上传（总像素 ≤ 196608 是实测安全线），提示词相应改为描述拼接图。
> 网关另有随机性上游 400（与载荷无关），客户端内置自动重试（最多 5 次，退避 1.5s 递增）。

## 1. 设计目标

把「真人大头照叠层贴图」升级为真正的 AI 换脸融合：

1. 模型先从真人照片中**分离出身份特征**（五官形状、比例、表情、标志性特征）；
2. 再**对照角色参考图**的脸部结构与画风；
3. **替换角色的五官**为真人的长相，并用角色自己的画风**重新绘制、融合**；
4. 角色的躯干、四肢、姿势、配色、背景、构图**完全不变**。

提示词必须是**角色无关（character-agnostic）**的：生产环境有数十种角色，形态、五官构成、运动方式各异，提示词里不允许出现任何物种名或具体五官假设。

## 2. 通用提示词（中文版，默认）

`face_api.cfg` 的 `prompt` 与 `FaceApi.DEFAULT_PROMPT` 使用此版：

> 这是一张左右拼接的参考图：左半部分是一张游戏角色图，右半部分是一张真人照片。请完成一次「保身份换脸」：把右半人物的长相移植到左半角色的脸上。
>
> 按以下步骤处理：
> 1. 从右半真人照片中提取此人的身份特征：脸型轮廓与比例、眼睛形状与间距、眉毛、鼻子、嘴部与表情、肤色，以及标志性特征（眼镜、胡须、痣、发型轮廓）；
> 2. 分析左半角色的脸部结构与画风：它有哪些五官、各自位置、线条粗细、配色与阴影方式；
> 3. 只重绘角色的五官，使其一眼可辨是右半照片本人——将真人的眼睛、眉毛、嘴部表情与脸型特征映射到角色对应的五官上；角色没有的五官（如鼻子、耳朵）不要凭空添加；真人特征必须改用角色的画风重新绘制（同样的笔触、线宽、配色、阴影），严禁照片直接拼贴或写实风格。
>
> 硬性约束：
> - 输出图只画游戏角色本身，**不要输出拼接参考图**；
> - 除脸部/头部区域外的一切保持不变，包括身体、四肢、姿势、服装、配饰、配色、背景、光影与构图；
> - 不添加文字、水印、边框或新道具；
> - 成品必须仍是同一个角色，只是脸变成了照片中的人。

## 3. 通用提示词（英文版，A/B 备选）

多图编辑任务中英文指令的空间/语义遵循度通常更稳，若中文版效果漂移可切到此版对照测试：

> This is a side-by-side reference sheet: the LEFT half is a game character artwork, the RIGHT half is a real person's portrait. Perform an identity-preserving face swap: give the character on the left the face of the person on the right.
>
> Steps:
> 1. Extract the person's identity from the right half: face contour and proportions, eye shape and spacing, eyebrows, nose, mouth and expression, skin tone, and signature traits (glasses, facial hair, moles, hairstyle silhouette).
> 2. Analyze the character's facial anatomy and art style on the left half: which facial features it has, their placement, line weight, color palette and shading.
> 3. Redraw ONLY the character's facial features so it is clearly recognizable as the person from the right half: map the person's eyes, eyebrows, mouth/expression and face contour onto the character's corresponding features. If the character lacks a feature the person has (e.g. no nose, no ears), do not invent it. Render every transferred feature in the character's exact art style — same brushwork, line weight, palette and shading. No photo cut-outs, no photorealism.
>
> Hard constraints:
> - Output ONLY the character itself — never the side-by-side sheet.
> - Everything outside the face/head region stays identical: body, limbs, pose, outfit, accessories, colors, background, lighting and composition.
> - No text, watermark, border or new props.
> - The result must still read as the same character — only its face now belongs to the person in the photo.

## 4. 设计理由（为什么这样写就通用）

- **角色定位引用（左半/右半）**：全程不命名角色、不描述物种，模型只能从拼接图左半自身推断画风与结构 → 任何角色都适用。
- **三步结构（提取 → 对照 → 替换融合）**：显式要求模型先分离真人特征再比对角色五官，避免它"偷懒"直接把照片脸贴上去；这正是用户要求的处理顺序。
- **解剖结构自适应条款**：「角色没有的五官（如鼻子、耳朵）不要凭空添加」是通用性的关键——布丁团子没有鼻子、鸟类是喙、人形有完整五官，这一条让同一提示词安全覆盖所有解剖结构，不会给无鼻角色强行加鼻子。
- **画风融合条款**：「改用图1的画风重新绘制，严禁照片拼贴」消灭"贴图感"，保证输出与角色立绘原生一体。
- **硬约束清单**：把"只改脸"写成不可违反的否定约束（身体/四肢/姿势/背景/尺寸逐项列出），比正面描述更能压住模型的自由发挥。
- **身份锚点**：「朋友一眼认出是本人」类表述（"clearly recognizable"）防止模型输出 generic 卡通脸，保住换脸的意义。

## 5. 角色参考图规范（每个物种一张）

通用提示词把角色差异转移到了**参考图**上，因此参考图质量直接决定换脸质量。新增角色时遵守：

| 要求 | 原因 |
|---|---|
| 正面或轻微侧面，脸部五官清晰可见 | 模型需要明确的脸部结构才能做映射 |
| 全身/半身完整入镜（含躯干四肢） | 约束模型保留身体，不会裁掉肢体 |
| 中性表情 | 避免角色表情污染真人表情迁移 |
| 透明或纯色背景 | 背景变化会浪费模型的"改动预算"，透明底可直接被游戏当贴图用 |
| 竖版全身 PNG，单帧 ≤ 512×512 | 拼图时会被等比缩进 256×384 左半区；原始尺寸过大徒增加载耗时 |
| 放 `assets/pets/<species>.png`，cfg 里配 `character_ref` | 一角色一配置，提示词不变 |

## 6. API 集成说明

- 端点：`POST {base_url}/images/edits`（OpenAI 兼容）。**多图表单不可用**（上游对 `image[]` 双图稳定 400），客户端用 `FaceApi._build_composite()` 把角色图（左）与裁方后的真人照（右）拼成单张 512×384 RGBA PNG，以 `image` 字段上传。
- 输入图总像素必须 ≤ 196608（512×384），实测更大的输入（如 512×512）会被上游 400 拒绝；旧单图漫画头像模式同步降到 400×400（`FALLBACK_AVATAR_SIZE`）。
- 网关上游有随机性 400（与载荷无关），`_on_request_completed` 对一切失败自动重试，最多 5 次、退避 1.5s 递增；仍失败才弹错误对话框（用户可再点「重试」）。
- **角色参考图必须经 `ResourceLoader.load()` 加载**（`_load_character_ref()`）：导出包里 `res://` 纹理已被导入为 `.ctex`，`Image.load()` 读不到原始 PNG 会静默失败、整条换脸管线退回降级模式。勿改回 `Image.load`。
- 可选参数：`size`（如 `1024x1024`）、`quality`（如 `high`/`medium`/`low`）——只在 `face_api.cfg` 里配置了才发送，避免严格网关拒绝未知字段。
- `_build_composite()` 拼贴前统一 `convert(Image.FORMAT_RGBA8)`：`blit_rect` 要求源图与目标格式一致，JPEG/相机帧是 RGB8，不转换会静默贴不上（右半空白，模型拿不到人脸，输出只剩角色重绘）。
- 透明背景：此网关接受但**忽略** `background=transparent` 表单字段（实测返回仍是不透明黑底、无 alpha）。因此客户端双保险：发送时给 prompt 追加 `TRANSPARENT_BG_SUFFIX`（代码侧强制，不依赖 cfg）；收到结果后用 `FaceApi.cutout_character()` 从边缘洪泛抠掉四角取样的纯色底（四角颜色不一致时原样返回，不误伤画了场景的结果）。旧单图漫画头像模式仍发送 `background=transparent`（该路径实测可用）。
- 若未来网关支持真正的多图编辑，改回双图只需重写 `_request_cloud_swap` 并恢复 v1 提示词（见 git 历史）。

## 7. 降级行为

`character_ref` 未配置或图片加载失败时，`FaceApi` 自动退回旧管线（单图 → 黑白漫画头像 → 叠层贴到程序化身体），并 `push_warning` 提示。角色立绘未到位前功能不崩；立绘与配置就位后自动升级为双图换脸。

## 8. 调优与验收

调优旋钮：
- 效果不像本人 → 加强第 1 步特征列举（如加"双眼皮/卧蚕"等），或切英文版。
- 身体/背景被改动 → 在硬约束开头加 "Do not redraw or restyle anything outside the face region, even partially."
- 出现拼贴感 → 把「严禁照片直接拼贴或写实风格」提前到任务定义句里。
- 成本/耗时 → cfg 里配 `quality="medium"` 或更小 `size`。

真机验收清单：
1. 拍照 → 确认 → 返回的立绘：身体/四肢/姿势与角色参考图一致，只有脸变了。
2. 五官能认出是拍照者本人（换两个人各试一次）。
3. 无文字/水印/边框；画布尺寸与参考图一致。
4. 宠物在岛上以新立绘渲染，弹跳/挤压动画正常。
5. 杀进程重进游戏，`user://pet_look.png` 被正确加载。
