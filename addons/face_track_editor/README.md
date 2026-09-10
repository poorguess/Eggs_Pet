# Face Contour Track Editor 2

开发者专用插件。在 Godot 底部 **Face Contour** 面板逐帧编辑轮廓。

完整说明见 [docs/face_customization.md](../../docs/face_customization.md)。

运行时资源与网格代码放在 `scripts/face/`，本目录仅用于编辑器。
默认轨迹为 `assets/pets/face_tracks/character1_walk.tres`。

与原三点插件的变化：

- 同序轮廓取代固定眼睛/嘴巴锚点。
- 支持点拖动、整轮廓平移、关键帧插值、隐藏帧和播放检查。
- 旧三点数据可以显式导入为待校正的椭圆草稿。
- 保存时校验退化、自交、点数和范围。
- 资源脚本移出 addons；导出保护同时排除本目录及其启用路径。
