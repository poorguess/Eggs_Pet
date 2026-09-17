extends Node2D

# 主岛协调层：持有照护/成长状态、蛋与宠物的生命周期、换脸流程，并把状态推给 UI 场景。
# 全部子节点都在 scenes/main_island.tscn 里静态摆放（见该文件的节点顺序说明），本脚本用
# @onready 取引用，不做任何绘制，也不手写命中测试 —— 触摸目标由各 Control 自己承担。

const FACE_SAVE_PATH := "user://face.png"
const PET_LOOK_SAVE_PATH := "user://pet_look.png"
const PET_SHEET_SAVE_PATH := "user://pet_sheet.png"
const FACE_TRACK := preload("res://assets/pets/face_tracks/character1_walk.tres")
const FACE_CUSTOMIZER := preload("res://scenes/face_customizer.tscn")
# 本机合成的底图与模板：与精灵表单帧同为 320x395，锚点对应 MediaPipe 关键点。
const FACE_BASE := "res://assets/pets/shell_pudding.png"
const FACE_TEMPLATE := "res://assets/face_templates/shell_pudding.json"
const SUBTITLE := "浮空小岛  /  第一天"

var feature_profile := PetFaceProfile.new()
var feature_image: Image
var customizer: FaceCustomizer
var customizer_layer: CanvasLayer

var care := CareState.new()
var growth := GrowthState.new()
var stage := "egg"
var toast := "安静的小岛，正在等你。"
var toast_time := 3.5
var save_clock := 0.0
var face_mode := ""
var face_error := ""
var face_texture: ImageTexture
var has_pet_look := false
var pending_texture: ImageTexture
var preview_texture: ImageTexture
var face_overlay: Sprite2D
var detail_open := false
var created_at := 0.0
var hatched_at := 0.0
var _face_base: Image
var _face_template: FaceTemplate
var _ready_notified := false
var _last_margins := Vector4(-1.0, -1.0, -1.0, -1.0)

# 全部来自 scenes/main_island.tscn 的静态节点树。字段名与 @onready 路径一一对应，
# 改场景时两边必须同步改——这是静态场景树唯一的代价，换来的是编辑器里可见、可调。
@onready var egg: Egg = $Egg
@onready var pet: Pet = $Pet
@onready var face_api: FaceApi = $FaceApi
@onready var compositor: FaceCompositor = $FaceCompositor
@onready var face_camera: FaceCamera = $FaceCamera
@onready var hud: Hud = $UiLayer/Hud
@onready var detail_panel: DetailPanel = $UiLayer/DetailPanel
@onready var face_preview: FacePreview = $UiLayer/FacePreview
@onready var face_dialogs: FaceDialogs = $UiLayer/FaceDialogs

func _ready() -> void:
	face_api.completed.connect(_on_face_completed)
	face_api.failed.connect(_on_face_failed)
	compositor.completed.connect(_on_composite_completed)
	compositor.failed.connect(_on_face_failed)
	face_camera.preview_frame.connect(_on_face_preview_frame)
	face_camera.permission_denied.connect(_on_face_permission_denied)
	face_camera.unavailable.connect(_open_face_file_dialog)
	egg.animation_finished.connect(_on_egg_animation_finished)
	_install_ui()
	_load_save()
	# 壳的可见性依赖 _load_save() 读出的 stage，必须排在它后面。
	egg.set_shell_visible(stage == "egg" or stage == "hatching")
	_layout_pet()
	_apply_saved_pet_look()
	_load_features()
	_sync_pet_visibility()
	_sync_ui()

# UI 已经是场景树里的节点，这里只负责接线。
func _install_ui() -> void:
	hud.hatch_pressed.connect(_on_hud_hatch_pressed)
	hud.face_button_pressed.connect(_open_customizer)
	hud.status_pressed.connect(_open_detail)
	detail_panel.closed.connect(_on_detail_closed)
	face_preview.shutter_pressed.connect(_on_preview_shutter)
	face_preview.close_pressed.connect(_cancel_face_flow)
	face_dialogs.consent_accepted.connect(_on_face_consent)
	face_dialogs.cancelled.connect(_on_dialogs_cancelled)
	face_dialogs.confirm_accepted.connect(_apply_face_photo)
	face_dialogs.confirm_retake.connect(_retake_face_photo)
	face_dialogs.error_retry.connect(_retry_face_photo)
	face_dialogs.error_closed.connect(_close_face_error)
	get_viewport().size_changed.connect(_sync_ui)

func _on_egg_animation_finished(anim_name: StringName) -> void:
	if stage != "hatching" or anim_name != Egg.ACTION_BROKEN:
		return
	stage = "pet"
	egg.play_hatch_glow()
	# pet 一直是场景树里的节点（孵化前 _sync_pet_visibility 让它不可见），
	# 这里只把它挪到蛋破壳的位置并开演 idle。
	pet.roam_center = _egg_animation_position()
	pet.position = pet.roam_center
	pet.play_idle()
	_sync_pet_visibility()
	toast = "壳壳布丁来到岛上了。"
	toast_time = 3.0
	_save()
	_sync_ui()

func _sync_pet_visibility() -> void:
	pet.visible = stage == "pet" and face_mode == "" and not detail_open
	_sync_face_overlay()

# 降级模式（角色参考图缺失时）：把漫画头像叠到程序化宠物的头部，保证结果可见。
const FACE_OVERLAY_CANVAS_RADIUS := 44.0
const FACE_OVERLAY_CANVAS_OFFSET := Vector2(0, -12.0)

func _sync_face_overlay() -> void:
	if pet == null:
		return
	var show := face_texture != null and not has_pet_look and stage == "pet"
	if face_overlay == null:
		if not show:
			return
		face_overlay = Sprite2D.new()
		face_overlay.z_index = 1
		pet.add_child(face_overlay)
	face_overlay.visible = show
	if show:
		face_overlay.texture = face_texture
		# pet 的缩放会传导给子节点，换算回画布尺寸。
		face_overlay.position = FACE_OVERLAY_CANVAS_OFFSET / pet.pet_scale
		face_overlay.scale = Vector2.ONE * (FACE_OVERLAY_CANVAS_RADIUS * 2.0 / (pet.pet_scale * face_texture.get_width()))

static func _circle_avatar(image: Image, size: int = 256) -> Image:
	var side := mini(image.get_width(), image.get_height())
	var squared := image.get_region(Rect2i((image.get_width() - side) / 2, (image.get_height() - side) / 2, side, side))
	if side != size:
		squared.resize(size, size, Image.INTERPOLATE_LANCZOS)
	if squared.get_format() != Image.FORMAT_RGBA8:
		squared.convert(Image.FORMAT_RGBA8)
	var center := (size - 1) * 0.5
	for y in range(size):
		for x in range(size):
			var d := Vector2(x - center, y - center).length()
			if d > center:
				squared.set_pixel(x, y, Color(0, 0, 0, 0))
			elif d > center - 1.5:
				var px := squared.get_pixel(x, y)
				px.a *= (center - d) / 1.5
				squared.set_pixel(x, y, px)
	return squared

func _exit_tree() -> void:
	# 退出时主动停相机、断在途请求，避免原生资源/连接悬挂到进程 teardown。
	face_camera.stop()
	face_api.cancel()

func _notification(what: int) -> void:
	# 节点已出树、但 queue_free 还没执行时仍可能收到 size_changed 之类的通知，
	# 那时 get_viewport() 已经是 null，几何计算会炸。
	if not is_inside_tree():
		return
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_layout_pet()
		_sync_ui()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# 移动端随时可能被划掉或切后台，立刻落盘让离线进度拿到最新的 last_saved。
		_save()

func _process(delta: float) -> void:
	care.tick(delta, false)
	growth.tick(delta, care.is_comfortable())
	toast_time = maxf(0.0, toast_time - delta)
	save_clock += delta
	if save_clock >= 15.0:
		save_clock = 0.0
		_save()
	if stage == "egg" and growth.hatch_ready and not _ready_notified:
		_ready_notified = true
		toast = "蛋壳裂开了一道缝，点「迎接破壳」吧。"
		toast_time = 4.0
		_save()
	egg.set_shell_visible(stage == "egg" or stage == "hatching")
	_sync_ui()

# ---------------------------------------------------------------- UI 同步

# 弹窗/取景层打开时，世界交互与 HUD 动作一律让位（原文 _target_hit 每个 target 都带此前缀守卫）。
func _ui_blocked() -> bool:
	return detail_open or face_mode != ""

func _sync_ui() -> void:
	if hud == null or not is_inside_tree():
		return
	var margins := _safe_margins()
	if margins != _last_margins:
		_last_margins = margins
		hud.set_safe_margins(margins)
		face_preview.set_safe_margins(margins)
	hud.set_subtitle(SUBTITLE)
	hud.set_creature_name(_creature_name())
	hud.set_stats([care.temperature, care.hunger, care.cleanliness, care.mood])
	hud.set_stage(stage, growth.hatch_progress, growth.hatch_ready)
	# 原文 _draw() 的条件就是 face_mode == ""，与 detail_open 无关：详情打开时 FAB 仍被画出来，
	# 只是压在 Dim 之下变暗。这里保持同样条件 —— 层级上 detail_panel 在 hud 之上，效果一致。
	hud.set_face_button_visible(face_mode == "")
	# toast_time 仍由 _process 逐帧递减（Hud 只在被喂入时重置自己的倒计时），
	# 因此这里每帧重述一遍当前剩余时长，等价于原文 `if toast_time > 0.0: _draw_toast(...)`。
	#
	# 与原文的唯一偏离：弹窗打开时不再显示 toast。原文把 toast 画在所有东西之上，
	# 所以它会亮在 Dim 上面；Control 化后 hud 在 detail_panel / face_dialogs 之下，
	# 硬要显示只会变成压在 Dim 底下的暗条。此时玩家正在走弹窗流程，toast 也不承载可操作信息。
	if _ui_blocked() or toast_time <= 0.0:
		hud.hide_toast()
	else:
		hud.show_toast(toast, toast_time)
	if detail_open:
		_sync_detail()

func _creature_name() -> String:
	if stage == "pet":
		return "壳壳布丁  ·  " + _intimacy_level_cn()
	if stage == "egg" and growth.hatch_ready:
		return "一颗蛋  ·  即将破壳"
	if stage == "hatching":
		return "一颗蛋  ·  正在破壳"
	return "一颗蛋  ·  孵化中"

func _on_hud_hatch_pressed() -> void:
	if _ui_blocked():
		return
	if growth.hatch_ready:
		_do_hatch()
		return
	growth.accelerate()
	toast = "蛋壳里传来轻快的动静。"
	toast_time = 1.6
	_save()

func _unhandled_input(event: InputEvent) -> void:
	if customizer != null and customizer.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_close_customizer()
		return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_H and stage == "egg" and not growth.hatch_ready:
			growth.hatch_progress = 99.0
			toast = "Hatch preview: almost ready."
			toast_time = 2.0
		if event.keycode == KEY_ESCAPE:
			if detail_open:
				detail_panel.close()
			elif face_mode != "":
				_cancel_face_flow()
	# 蛋/宠本体仍由世界层命中（它们是 Node2D，没有 Control 命中区）。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if not _ui_blocked() and stage != "hatching" and _creature_hit_rect().has_point(event.position):
			_open_detail()

# ---------------------------------------------------------------- 详情弹窗

func _open_detail() -> void:
	if _ui_blocked():
		return
	detail_open = true
	_sync_pet_visibility()
	_sync_detail()
	_sync_ui()
	detail_panel.open()

# 详情内容逐帧刷新，而不是打开时拍一张快照：面板打开期间 care.tick() / growth.tick()
# 仍在跑（原文 _draw_detail_* 每帧读的就是最新值），快照会在打开后立刻过期。
func _sync_detail() -> void:
	if stage == "egg":
		var progress_text := "孵化进度  %d%%  ·  约 %ds 后破壳" % [int(floor(growth.hatch_progress)), int(ceil(growth.hatch_seconds_left()))]
		if growth.hatch_ready:
			progress_text = "孵化进度  100%  ·  可以破壳了"
		detail_panel.show_egg(_days_since(created_at), progress_text, growth.hatch_ready, true, growth.hatch_progress / 100.0)
	else:
		var sub := "Shell Pudding  ·  相伴第 %d 天" % _days_since(hatched_at)
		if hatched_at > 0.0:
			sub += "  ·  破壳于 " + _date_cn(hatched_at)
		detail_panel.show_pet("壳壳布丁", sub, _intimacy_level_cn(), _intimacy_hint(), _look_description(), growth.intimacy_progress())
	detail_panel.set_stats([care.temperature, care.hunger, care.cleanliness, care.mood])

func _on_detail_closed() -> void:
	detail_open = false
	_sync_pet_visibility()
	_sync_ui()

func _look_description() -> String:
	if feature_image != null:
		return "已对齐你的五官（动画）"
	if has_pet_look:
		return "已使用你的长相"
	if face_texture:
		return "漫画头像（简易模式）"
	return "默认样貌"

func _do_hatch() -> void:
	growth.hatch()
	if not growth.hatched:
		return
	stage = "hatching"
	growth.intimacy_points = maxf(growth.intimacy_points, 4.0)
	hatched_at = Time.get_unix_time_from_system()
	toast = "蛋壳正在裂开……"
	toast_time = 3.0
	egg.play(Egg.ACTION_BROKEN)
	_save()

# ---------------------------------------------------------------- 换脸流程

func _set_face_mode(mode: String) -> void:
	if face_mode == mode:
		return
	if mode == "" and customizer != null:
		mode = "customize"
	face_mode = mode
	if customizer != null:
		customizer.visible = mode == "customize"
	# The game is portrait throughout, including the camera and face-customizer
	# flows. Keeping one orientation avoids a disruptive rotation on phones.
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_PORTRAIT)
	_sync_pet_visibility()
	# 取景态原文直接 return，不画标题/状态面板/孵化面板；等价地整层收起 HUD，
	# 否则相机的第一帧到达前会从半透明背板后面透出来。
	hud.visible = mode != "preview"
	if mode == "preview":
		# 原文 _draw_face_preview 直接读 preview_texture，所以进 preview 时也要把
		# 手上已有的一帧推过去（重拍时会先显示上一张，直到新帧到达）。
		face_preview.set_frame(preview_texture)
		face_preview.open()
	else:
		face_preview.close()
	match mode:
		"consent":
			face_dialogs.show_consent()
		"confirm":
			face_dialogs.show_confirm(pending_texture)
		"processing":
			face_dialogs.show_processing()
		"error":
			face_dialogs.show_error(face_error)
		_:
			face_dialogs.hide_dialog()
	_sync_ui()

func _on_face_consent() -> void:
	if face_camera.native_available():
		_set_face_mode("preview")
		face_camera.start()
	else:
		_set_face_mode("")
		_open_face_file_dialog()

func _on_preview_shutter() -> void:
	var photo := face_camera.capture()
	if photo:
		_on_photo_ready(photo)

# consent 的「取消」、confirm 的「重拍」、以及三态的 × 都汇到这一个入口；
# 后两者的原文语义是「先清 pending 再退模式」，对 consent 无害（那时 pending 本就是 null）。
func _on_dialogs_cancelled() -> void:
	pending_texture = null
	_set_face_mode("")

func _open_face_file_dialog() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("选择一张自拍照片", "", "", true, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; 图片"]), _on_face_file_selected)
		return
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; 图片"])
	dialog.size = Vector2i(900, 600)
	dialog.file_selected.connect(func(path: String) -> void:
		_on_face_file_selected(true, PackedStringArray([path]), 0)
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()

func _on_face_file_selected(status: bool, paths: PackedStringArray, _filter: int) -> void:
	if not status or paths.is_empty():
		return
	var image := Image.new()
	if image.load(paths[0]) != OK:
		toast = "这张照片读取失败，换一张试试。"
		toast_time = 3.0
		_sync_ui()
		return
	_on_photo_ready(image)

func _on_photo_ready(photo: Image) -> void:
	if face_camera.native_available():
		face_camera.stop()
	print("[FaceFlow] photo ready %dx%d" % [photo.get_width(), photo.get_height()])
	pending_texture = ImageTexture.create_from_image(FaceApi.crop_square(photo))
	_set_face_mode("confirm")

func _apply_face_photo() -> void:
	_process_pending_photo()

func _retake_face_photo() -> void:
	pending_texture = null
	if face_camera.native_available():
		_set_face_mode("preview")
		face_camera.start()
	else:
		_set_face_mode("")
		_open_face_file_dialog()

func _retry_face_photo() -> void:
	_process_pending_photo()

## 确认照片后的处理入口：按定制器当前选择的生成方式分流。
## 本机合成走 FaceCompositor（离线），AI 模式走 FaceApi（联网生图服务）。
func _process_pending_photo() -> void:
	if pending_texture == null:
		_set_face_mode("")
		return
	_set_face_mode("processing")
	if customizer != null and customizer.local_mode:
		_run_local_composite(pending_texture.get_image())
	else:
		face_api.process_photo(pending_texture.get_image())

func _run_local_composite(photo: Image) -> void:
	if _face_base == null:
		_face_base = FaceApi.load_image_resource(FACE_BASE)
	if _face_template == null:
		_face_template = FaceTemplate.load_from_json(FACE_TEMPLATE)
	if _face_base == null or not _face_template.is_valid():
		_on_face_failed("本机合成缺少角色立绘或模板文件。")
		return
	compositor.process_photo(photo, _face_base, _face_template)

func _on_composite_completed(image: Image) -> void:
	print("[FaceFlow] local composite %dx%d" % [image.get_width(), image.get_height()])
	pending_texture = null
	if customizer == null:
		_open_customizer()
	customizer.set_composite_result(image)
	_set_face_mode("")

func _close_face_error() -> void:
	if pending_texture:
		_set_face_mode("confirm")
	else:
		_set_face_mode("")

func _cancel_face_flow() -> void:
	face_camera.stop()
	face_api.cancel()
	pending_texture = null
	_set_face_mode("")

func _on_face_completed(image: Image, _full_character: bool) -> void:
	print("[FaceFlow] completed image=%dx%d" % [image.get_width(), image.get_height()])
	var result := PetFaceImage.prepare(image)
	if not String(result.error).is_empty():
		_on_face_failed(String(result.error))
		return
	if customizer == null:
		_open_customizer()
	customizer.set_result(result.image)
	pending_texture = null
	_set_face_mode("")

# 把换脸结果烘焙进精灵表并应用到 pet；失败返回 false（pet 保持原样）。
func _bake_and_apply(look: Image) -> bool:
	if pet == null:
		return false
	var ref := FaceApi.load_image_resource(face_api.character_ref)
	var sheet := Pet.SHEET.get_image()
	if ref == null or sheet == null:
		return false
	var baked := FaceApi.bake_face_into_sheet(look, ref, sheet, Pet.HFRAMES, Pet.VFRAMES, Pet.FRAME_COUNT)
	if baked.is_empty():
		return false
	pet.apply_look_sheet(baked)
	baked.save_png(PET_SHEET_SAVE_PATH)
	return true

# 启动时恢复换脸外观：优先直接读烘焙好的精灵表；只有旧存档的 AI 原图时现场重烘焙迁移。
func _apply_saved_pet_look() -> void:
	if not has_pet_look or pet == null:
		return
	var sheet_image := Image.new()
	if FileAccess.file_exists(PET_SHEET_SAVE_PATH) and sheet_image.load(PET_SHEET_SAVE_PATH) == OK:
		pet.apply_look_sheet(sheet_image)
		return
	var look := Image.new()
	if FileAccess.file_exists(PET_LOOK_SAVE_PATH) and look.load(PET_LOOK_SAVE_PATH) == OK and _bake_and_apply(look):
		return
	# 贴图文件丢失或重烘焙失败：外观回退默认，避免详情页虚报"已使用你的长相"。
	has_pet_look = false

func _on_face_failed(message: String) -> void:
	print("[FaceFlow] failed: %s" % message)
	face_error = message
	_set_face_mode("error")

func _on_face_preview_frame(texture: ImageTexture) -> void:
	preview_texture = texture
	if face_mode == "preview":
		face_preview.set_frame(texture)

func _on_face_permission_denied() -> void:
	_set_face_mode("")
	toast = "没有相机权限，无法自拍。可以在系统设置里开启。"
	toast_time = 4.0
	_sync_ui()

func _debug_apply_face_from_path(path: String) -> void:
	var image := Image.new()
	if image.load(path) == OK:
		_on_photo_ready(image)
		_apply_face_photo()

# ---------------------------------------------------------------- 文案

func _days_since(timestamp: float) -> int:
	if timestamp <= 0.0:
		return 1
	return maxi(1, int((Time.get_unix_time_from_system() - timestamp) / 86400.0) + 1)

func _date_cn(timestamp: float) -> String:
	var dt := Time.get_datetime_dict_from_unix_time(int(timestamp))
	return "%d月%d日" % [dt.month, dt.day]

func _intimacy_hint() -> String:
	var level := growth.intimacy_level()
	if level == "Close":
		return "已达最高亲密度，它完全信任你。"
	var target := GrowthState.INTIMACY_COMFORTABLE if level == "Stranger" else GrowthState.INTIMACY_CLOSE
	var next := "安心" if level == "Stranger" else "亲近"
	return "再陪伴 +%d 点升到「%s」" % [int(ceil(target - growth.intimacy_points)), next]

func _intimacy_level_cn() -> String:
	return {"Stranger": "陌生", "Comfortable": "安心", "Close": "亲近"}.get(growth.intimacy_level(), "陌生")

# ---------------------------------------------------------------- 世界层几何

func _canvas_size() -> Vector2:
	return get_viewport().get_visible_rect().size

func _egg_animation_position() -> Vector2:
	return _canvas_size() * 0.5 + Vector2(0.0, -70.0)

func _layout_pet() -> void:
	if pet == null:
		return
	var canvas := _canvas_size()
	pet.roam_center = _egg_animation_position()
	pet.roam_radius = Vector2(minf(canvas.x * 0.36, 420.0), minf(canvas.y * 0.24, 520.0))
	if not Rect2(Vector2.ZERO, canvas).grow(160.0).has_point(pet.position):
		pet.position = pet.roam_center

# Vector4(left, top, right, bottom) in canvas units, at least 16px on every side.
func _safe_margins() -> Vector4:
	var canvas := _canvas_size()
	var window := Vector2(DisplayServer.window_get_size())
	if window.x <= 0.0 or window.y <= 0.0:
		return Vector4(16, 16, 16, 16)
	# get_display_safe_area() 描述的是「屏幕」的安全区，只在窗口铺满屏幕时才有意义。
	# 桌面端手动把窗口拉得比屏幕还大时（预览超长机型就会这样），
	# window - area.end 会算出一千多像素的假边距，把底栏推到屏幕中间。
	# 手机上窗口恒等于屏幕，这个分支不会触发。
	var screen := Vector2(DisplayServer.screen_get_size())
	if window.x > screen.x or window.y > screen.y:
		return Vector4(16, 16, 16, 16)
	var area := DisplayServer.get_display_safe_area()
	var sx := canvas.x / window.x
	var sy := canvas.y / window.y
	return Vector4(
		maxf(16.0, area.position.x * sx),
		maxf(16.0, area.position.y * sy),
		maxf(16.0, (window.x - area.end.x) * sx),
		maxf(16.0, (window.y - area.end.y) * sy))

# 蛋/宠是 Node2D，没有 Control 命中区，这一块仍然手写。
func _creature_hit_rect() -> Rect2:
	if stage == "egg" and egg:
		return Rect2(egg.position - Vector2(160, 100), Vector2(320, 200))
	if pet and pet.visible:
		return Rect2(pet.position - Vector2(90, 110), Vector2(180, 220))
	return Rect2(445.0, 120.0, 280.0, 320.0)

# ---------------------------------------------------------------- 存档

func _load_save() -> void:
	var data := SaveService.apply_offline(SaveService.load_data())
	stage = String(data.get("stage", "egg"))
	care.from_dict(data.get("care", {}))
	growth.from_dict(data)
	if growth.hatched:
		stage = "pet"
	created_at = float(data.get("created_at", 0.0))
	if created_at <= 0.0:
		created_at = Time.get_unix_time_from_system()
	hatched_at = float(data.get("hatched_at", 0.0))
	if bool(data.get("has_face", false)) and FileAccess.file_exists(FACE_SAVE_PATH):
		var face_image := Image.new()
		if face_image.load(FACE_SAVE_PATH) == OK:
			face_texture = ImageTexture.create_from_image(_circle_avatar(face_image))
	has_pet_look = bool(data.get("has_pet_look", false))

func _save() -> void:
	var data := {"stage": stage, "egg_type": "common_egg", "pet_species": "shell_pudding", "care": care.to_dict(), "has_face": face_texture != null, "has_pet_look": has_pet_look, "created_at": created_at, "hatched_at": hatched_at}
	data.merge(growth.to_dict())
	SaveService.save_data(data)

# ---------------------------------------------------------------- 换脸定制器

func _open_customizer() -> void:
	if customizer != null:
		return
	customizer_layer = CanvasLayer.new()
	customizer_layer.layer = 20
	add_child(customizer_layer)
	customizer = FACE_CUSTOMIZER.instantiate()
	customizer_layer.add_child(customizer)
	# 未配置生图服务时默认本机合成（离线可用）；GDMP 不可用的平台由定制器禁用该选项。
	customizer.default_local = not face_api.config_error.is_empty()
	customizer.open(FACE_TRACK, feature_profile, feature_image)
	customizer.photo_requested.connect(func() -> void: _set_face_mode("consent"))
	customizer.service_configuration_saved.connect(face_api.reload_config)
	customizer.cancelled.connect(_close_customizer)
	customizer.applied.connect(_apply_features)
	customizer.composite_applied.connect(_apply_composite_look)
	_set_face_mode("customize")

func _close_customizer() -> void:
	face_api.cancel()
	face_camera.stop()
	if customizer_layer != null:
		customizer_layer.queue_free()
	customizer = null
	customizer_layer = null
	pending_texture = null
	_set_face_mode("")

func _apply_features(image: Image, profile: PetFaceProfile) -> void:
	if image == null:
		return
	var error := FACE_TRACK.validate()
	if not error.is_empty():
		customizer.set_error(error)
		return
	var save_error := profile.save_image(image)
	if save_error != OK:
		customizer.set_error("保存失败（%d），原外貌未更改。" % save_error)
		return
	feature_profile = profile
	feature_image = image
	pet.apply_features(ImageTexture.create_from_image(image), profile, FACE_TRACK)
	# 新五官贴层取代烘焙外观，恢复默认序列帧显示。
	pet.reset_look()
	has_pet_look = false
	face_texture = null
	_close_customizer()
	_save()
	toast = "五官已对齐，继续跟随角色运动。"
	toast_time = 3

## 本机合成应用：整帧成品逐帧烘焙进精灵表，33 帧动画与漫游逻辑不变。
## 与 AI 贴层互斥：清除已保存的五官外貌，外观改由烘焙表承载并随存档恢复。
func _apply_composite_look(image: Image) -> void:
	if image == null or pet == null or _face_base == null:
		return
	var baked := compositor.bake_into_sheet(_face_base, Pet.SHEET.get_image(), Pet.HFRAMES, Pet.VFRAMES, Pet.FRAME_COUNT)
	if baked.is_empty():
		customizer.set_error("合成结果烘焙失败，原外貌未更改。")
		return
	image.save_png(PET_LOOK_SAVE_PATH)
	baked.save_png(PET_SHEET_SAVE_PATH)
	pet.apply_look_sheet(baked)
	pet.clear_features()
	PetFaceProfile.reset_saved()
	feature_profile = PetFaceProfile.new()
	feature_image = null
	face_texture = null
	has_pet_look = true
	_close_customizer()
	_save()
	toast = "壳壳布丁换上了你的脸。"
	toast_time = 3.0

func _load_features() -> void:
	feature_profile = PetFaceProfile.load_saved()
	if feature_profile.image_path.is_empty() or not FileAccess.file_exists(feature_profile.image_path):
		return
	var image := Image.new()
	if image.load(feature_profile.image_path) != OK:
		push_warning("换脸模块：外貌图片读取失败，保留旧外貌。")
		return
	# Saved local cutouts need not match the model's coverage rules.
	if image.detect_alpha() == Image.ALPHA_NONE or not image.get_used_rect().has_area():
		push_warning("换脸模块：已保存图片缺少透明区域或有效五官。")
		return
	var error := pet.apply_features(ImageTexture.create_from_image(image), feature_profile, FACE_TRACK)
	if not error.is_empty():
		push_warning("换脸模块：" + error)
		return
	feature_image = image
	pet.reset_look()
	has_pet_look = false
	face_texture = null
