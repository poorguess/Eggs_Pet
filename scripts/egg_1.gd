extends Sprite2D

func _ready():
	print("小岛就绪！")

# 检测点击输入
func _input(event):
	# 检查是否为鼠标左键点击（在手机上会自动等同于手指触控）
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		play_bounce()

# Q弹果冻动画：先压扁，再回弹
func play_bounce():
	var tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 瞬间压扁 (宽 1.25, 高 0.75)
	tween.tween_property(self, "scale", Vector2(1.25, 0.75), 0.08)
	# 回弹到原本大小 (宽 1.0, 高 1.0)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15)
