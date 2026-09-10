# Face Customization Implementation Plan

**Goal:** 将五官贴图在首帧对齐后按轮廓绑定到序列动画。
**Architecture:** 开发插件生成运行时资源；生图和 UI 通过信号交换草稿；应用后独立保存外貌。
**Tech Stack:** Godot 4.7 / GDScript / Control / 2D mesh。
**Spec:** ../specs/2026-09-10-face-customization-design.md

## 约束

只修改主项目。沿用当前动态 Pet 和主岛入口。不修改照护和小游戏。插件排除出包。错误回到所属模块。

## 执行顺序

- [x] 添加 `scripts/tests/test_face_module.gd`，先验证运行时数据模块尚不存在，再覆盖几何与图像的行为断言。
- [x] 新建 `scripts/face/face_track.gd`（get_contour/validate）、`face_mesh.gd`（build）、`face_overlay.gd`（同步 Sprite）、`face_profile.gd`（to_dict/from_dict/save/load）。测试身份映射、变换、无效数据与存读档。
- [x] 更新迁移 `addons/face_track_editor`。默认轨迹存 `assets/pets/face_tracks/character1_walk.tres`，校验全部 33 帧并验证资源可重载。
- [x] 新建 `face_prompt.gd` 和 `face_image.gd`，FaceApi 强制五官协议。测试洋红抠图、保留眼白、不透明/空图拒绝。
- [x] 新建 `face_customizer.gd`、`face_preview.gd` 和独立场景。主岛仅接入口、采集回调和应用信号；Pet 增加运行时贴层。验证取消与应用、镜像与动画同步。
- [x] 更新导出排除规则和使用说明。运行 headless 测试、主场景和 UI 渲染，导出并检查 PCK。

## 验证结果

24 项检查通过；比例回归先失败后通过。界面和插件已渲染检查。PCK 已验证编辑器路径为零。真实生图受当前缺失 face_api.cfg 限制，手机相机与触摸尚未实机验证。详见 ../../face_customization.md。
